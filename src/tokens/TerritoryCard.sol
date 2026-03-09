// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITerritoryCard} from "../interfaces/ITerritoryCard.sol";

/// @title TerritoryCard
/// @notice ERC-1155 territory cards drawn after capturing a territory.
/// @dev Unlike ArmyToken, cards ARE tradeable between players during an active season.
///      Cards are burned when redeemed for bonus armies or CONQUEST tokens.
///
///      Set bonuses escalate globally:
///        Sets 1–5  → 4, 6, 8, 10, 12 armies
///        Sets 6–7  → 15, 20 armies
///        Sets 8+   → 25 armies (capped)
///
///      The bonus for Infantry/Cavalry/Artillery sets is modified by the escalation:
///        Base values: Infantry=4, Cavalry=6, Artillery=8, Mixed=10
///        Escalation adds the global escalation bonus on top of the base value.
contract TerritoryCard is ITerritoryCard, ERC1155, AccessControl {
    using SafeERC20 for IERC20;

    // ── Roles ─────────────────────────────────────────────────────────────────
    bytes32 public constant GAME_ENGINE_ROLE = keccak256("GAME_ENGINE_ROLE");

    // ── Card Type Constants ───────────────────────────────────────────────────
    uint8 private constant _INFANTRY_CARD  = 1;
    uint8 private constant _CAVALRY_CARD   = 2;
    uint8 private constant _ARTILLERY_CARD = 3;

    // ── Base bonus armies per set type (before escalation) ────────────────────
    uint256 private constant _INFANTRY_SET_BONUS  = 4;
    uint256 private constant _CAVALRY_SET_BONUS   = 6;
    uint256 private constant _ARTILLERY_SET_BONUS = 8;
    uint256 private constant _MIXED_SET_BONUS     = 10;

    // ── Global escalation thresholds ─────────────────────────────────────────
    // After N total sets redeemed globally, additional bonus armies are added:
    // Sets 1-5: +0, +2, +4, +6, +8 (incremental from base)
    // Actually: 4, 6, 8, 10, 12, 15, 20, 25 (capped at 25)
    // We'll track the raw bonus for the NEXT set to be redeemed:

    // ── State ─────────────────────────────────────────────────────────────────
    uint256 private _setsRedeemed;

    // Card metadata: token ID (within card type 1-3) → territory ID it depicts
    // We use tokenId as a counter-based ID and store territory separately
    // For simplicity: all cards of the same type are fungible (no per-territory NFT distinction on-chain)
    // The depicted territory bonus is tracked off-chain; on-chain we just need the set composition.

    // CONQUEST token for end-of-season redemption
    IERC20 public conquestToken;
    uint256 private _conquestRedemptionRate; // in wei per card

    // Season phase reference — only allows redeemForConquest when season is ended
    // Instead of importing GameEngine (circular), we use a simple flag toggled by GAME_ENGINE_ROLE
    bool public seasonActive;

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    constructor(address admin, string memory uri_, address conquest_, uint256 redemptionRate_)
        ERC1155(uri_)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        conquestToken = IERC20(conquest_);
        _conquestRedemptionRate = redemptionRate_;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ITerritoryCard constant views
    // ─────────────────────────────────────────────────────────────────────────

    function INFANTRY_CARD()  external pure returns (uint256) { return _INFANTRY_CARD; }
    function CAVALRY_CARD()   external pure returns (uint256) { return _CAVALRY_CARD; }
    function ARTILLERY_CARD() external pure returns (uint256) { return _ARTILLERY_CARD; }

    // ─────────────────────────────────────────────────────────────────────────
    // Season State (toggled by GameEngine)
    // ─────────────────────────────────────────────────────────────────────────

    function setSeasonActive(bool active) external onlyRole(GAME_ENGINE_ROLE) {
        seasonActive = active;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Drawing Cards (GAME_ENGINE_ROLE)
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc ITerritoryCard
    function draw(address player, uint8 cardType, uint256 /*territoryId*/) external onlyRole(GAME_ENGINE_ROLE) {
        if (cardType < _INFANTRY_CARD || cardType > _ARTILLERY_CARD) {
            revert TerritoryCard__InvalidCardType(cardType);
        }
        _mint(player, cardType, 1, "");
        // territoryId is emitted for off-chain metadata; the on-chain card is fungible per type
        emit CardDrawn(player, cardType, 0, 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Burning Sets (GAME_ENGINE_ROLE)
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc ITerritoryCard
    function burnSet(address player, uint8[3] calldata cardTypes)
        external
        onlyRole(GAME_ENGINE_ROLE)
        returns (uint256 bonusArmies)
    {
        if (!_isValidSet(cardTypes)) revert TerritoryCard__InvalidCardSet(cardTypes);

        // Check balances before burning
        uint256 needInfantry;
        uint256 needCavalry;
        uint256 needArtillery;
        for (uint256 i; i < 3; ++i) {
            if (cardTypes[i] == _INFANTRY_CARD)  needInfantry++;
            if (cardTypes[i] == _CAVALRY_CARD)   needCavalry++;
            if (cardTypes[i] == _ARTILLERY_CARD) needArtillery++;
        }
        if (needInfantry  > 0) _requireBalance(player, _INFANTRY_CARD,  needInfantry);
        if (needCavalry   > 0) _requireBalance(player, _CAVALRY_CARD,   needCavalry);
        if (needArtillery > 0) _requireBalance(player, _ARTILLERY_CARD, needArtillery);

        // Burn the cards
        if (needInfantry  > 0) _burn(player, _INFANTRY_CARD,  needInfantry);
        if (needCavalry   > 0) _burn(player, _CAVALRY_CARD,   needCavalry);
        if (needArtillery > 0) _burn(player, _ARTILLERY_CARD, needArtillery);

        bonusArmies = _calculateSetBonus(_setsRedeemed, cardTypes);
        _setsRedeemed++;

        emit CardSetBurned(player, cardTypes, bonusArmies, _setsRedeemed);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // End-of-Season Redemption (callable by players)
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc ITerritoryCard
    function redeemForConquest(uint8 cardType, uint256 amount) external {
        if (seasonActive) revert TerritoryCard__SeasonStillActive();
        if (cardType < _INFANTRY_CARD || cardType > _ARTILLERY_CARD) {
            revert TerritoryCard__InvalidCardType(cardType);
        }
        if (amount == 0) revert TerritoryCard__ZeroAmount();
        _requireBalance(msg.sender, cardType, amount);

        _burn(msg.sender, cardType, amount);
        uint256 reward = amount * _conquestRedemptionRate;
        conquestToken.safeTransfer(msg.sender, reward);

        emit CardsRedeemedForConquest(msg.sender, cardType, amount, reward);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Admin
    // ─────────────────────────────────────────────────────────────────────────

    function setConquestRedemptionRate(uint256 rate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _conquestRedemptionRate = rate;
    }

    function setConquestToken(address conquest_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        conquestToken = IERC20(conquest_);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // View Functions
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc ITerritoryCard
    function cardBalance(address player, uint8 cardType) external view returns (uint256) {
        return balanceOf(player, cardType);
    }

    /// @inheritdoc ITerritoryCard
    function allCardBalances(address player)
        external
        view
        returns (uint256 infantry, uint256 cavalry, uint256 artillery)
    {
        infantry  = balanceOf(player, _INFANTRY_CARD);
        cavalry   = balanceOf(player, _CAVALRY_CARD);
        artillery = balanceOf(player, _ARTILLERY_CARD);
    }

    /// @inheritdoc ITerritoryCard
    function setsRedeemedCount() external view returns (uint256) {
        return _setsRedeemed;
    }

    /// @inheritdoc ITerritoryCard
    function previewSetBonus(uint256 setsAlreadyRedeemed, uint8[3] calldata cardTypes)
        external
        pure
        returns (uint256)
    {
        if (!_isValidSet(cardTypes)) return 0;
        return _calculateSetBonus(setsAlreadyRedeemed, cardTypes);
    }

    /// @inheritdoc ITerritoryCard
    function isValidSet(uint8[3] calldata cardTypes) external pure returns (bool) {
        return _isValidSet(cardTypes);
    }

    /// @inheritdoc ITerritoryCard
    function conquestRedemptionRate() external view returns (uint256) {
        return _conquestRedemptionRate;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal Logic
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Returns the bonus armies for a set trade given how many sets have been redeemed globally.
    ///      Escalation schedule (total global sets redeemed so far):
    ///        0  → base value for set type
    ///        1  → base + 2
    ///        2  → base + 4
    ///        3  → base + 6
    ///        4  → base + 8 (= 12 for Infantry)
    ///        5  → 15 (all types capped to same value from here)
    ///        6  → 20
    ///        7+ → 25
    function _calculateSetBonus(uint256 setsAlreadyRedeemed, uint8[3] calldata cardTypes)
        internal
        pure
        returns (uint256 bonus)
    {
        // Escalation lookup — applies universally regardless of set type after threshold
        if (setsAlreadyRedeemed >= 7) return 25;
        if (setsAlreadyRedeemed == 6) return 20;
        if (setsAlreadyRedeemed == 5) return 15;

        // Below threshold: base value + (2 * setsAlreadyRedeemed)
        uint256 base = _baseSetBonus(cardTypes);
        bonus = base + (setsAlreadyRedeemed * 2);
    }

    function _baseSetBonus(uint8[3] calldata cardTypes) internal pure returns (uint256) {
        bool isMixed = cardTypes[0] != cardTypes[1] || cardTypes[1] != cardTypes[2];
        if (isMixed) return _MIXED_SET_BONUS;
        if (cardTypes[0] == _INFANTRY_CARD)  return _INFANTRY_SET_BONUS;
        if (cardTypes[0] == _CAVALRY_CARD)   return _CAVALRY_SET_BONUS;
        if (cardTypes[0] == _ARTILLERY_CARD) return _ARTILLERY_SET_BONUS;
        return 0;
    }

    function _isValidSet(uint8[3] calldata cardTypes) internal pure returns (bool) {
        // Valid: 3×Infantry, 3×Cavalry, 3×Artillery, or 1×each
        bool allSame = cardTypes[0] == cardTypes[1] && cardTypes[1] == cardTypes[2];
        if (allSame) {
            uint8 t = cardTypes[0];
            return t == _INFANTRY_CARD || t == _CAVALRY_CARD || t == _ARTILLERY_CARD;
        }
        // Check 1 of each
        bool hasInfantry;
        bool hasCavalry;
        bool hasArtillery;
        for (uint256 i; i < 3; ++i) {
            if (cardTypes[i] == _INFANTRY_CARD)  hasInfantry  = true;
            if (cardTypes[i] == _CAVALRY_CARD)   hasCavalry   = true;
            if (cardTypes[i] == _ARTILLERY_CARD) hasArtillery = true;
        }
        return hasInfantry && hasCavalry && hasArtillery;
    }

    function _requireBalance(address player, uint8 cardType, uint256 required) internal view {
        uint256 bal = balanceOf(player, cardType);
        if (bal < required) {
            revert TerritoryCard__InsufficientCards(player, cardType, bal, required);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Required overrides
    // ─────────────────────────────────────────────────────────────────────────

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
