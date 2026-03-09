// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ITerritoryNFT} from "../interfaces/ITerritoryNFT.sol";

/// @title TerritoryNFT
/// @notice ERC-721 representing the 42 territories of The Base Archipelago.
/// @dev Tokens are locked (non-transferable) during active seasons.
///      Conquest transfers are allowed exclusively via GameEngine (GAME_ENGINE_ROLE).
///      Inter-season: tokens are freely tradeable for a 14-day window.
contract TerritoryNFT is ITerritoryNFT, ERC721, AccessControl, Pausable {
    // ── Roles ─────────────────────────────────────────────────────────────────
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant GAME_MASTER_ROLE = keccak256("GAME_MASTER_ROLE");
    bytes32 public constant GAME_ENGINE_ROLE = keccak256("GAME_ENGINE_ROLE");

    // ── Constants ─────────────────────────────────────────────────────────────
    uint256 public constant TOTAL_TERRITORIES = 42;
    uint256 public constant MAX_TERRITORIES_PER_WALLET = 12;
    uint256 public constant TRADING_WINDOW_DURATION = 14 days;

    // ── Map Data ──────────────────────────────────────────────────────────────
    mapping(uint256 => TerritoryMeta) private _territoryMeta;
    mapping(uint8 => ContinentMeta) private _continentMeta;
    bool public mapInitialized;

    // ── Season State ──────────────────────────────────────────────────────────
    bool private _seasonLocked;
    uint256 private _currentSeasonId;
    uint256 private _tradingWindowEnd;

    // ── In-conquest flag (allows GameEngine to bypass lock) ───────────────────
    bool private _inConquestTransfer;

    // ── Ownership Count (for wallet cap) ──────────────────────────────────────
    mapping(address => uint256) private _walletCount;

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    constructor(address admin) ERC721("Base-Conquest Territory", "BCT") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GAME_MASTER_ROLE, admin);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Map Initialization
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc ITerritoryNFT
    function initializeMap() external onlyRole(GAME_MASTER_ROLE) {
        if (mapInitialized) revert TerritoryNFT__AlreadyMinted(0);
        mapInitialized = true;
        _initContinents();
        _initTerritories();
    }

    function _initContinents() private {
        // 1: The Northlands — 9 territories, +5 armies
        _continentMeta[1] = ContinentMeta({
            name: "The Northlands",
            territoryIds: _range(1, 9),
            bonusArmies: 5
        });
        // 2: Merchant Straits — 7 territories, +3 armies
        _continentMeta[2] = ContinentMeta({
            name: "Merchant Straits",
            territoryIds: _range(10, 16),
            bonusArmies: 3
        });
        // 3: Iron Coast — 6 territories, +2 armies
        _continentMeta[3] = ContinentMeta({
            name: "Iron Coast",
            territoryIds: _range(17, 22),
            bonusArmies: 2
        });
        // 4: The Barrens — 12 territories, +7 armies
        _continentMeta[4] = ContinentMeta({
            name: "The Barrens",
            territoryIds: _range(23, 34),
            bonusArmies: 7
        });
        // 5: Verdant Isles — 4 territories, +2 armies
        _continentMeta[5] = ContinentMeta({
            name: "Verdant Isles",
            territoryIds: _range(35, 38),
            bonusArmies: 2
        });
        // 6: The Deep Expanse — 4 territories, +2 armies
        _continentMeta[6] = ContinentMeta({
            name: "The Deep Expanse",
            territoryIds: _range(39, 42),
            bonusArmies: 2
        });
    }

    function _initTerritories() private {
        // ── The Northlands (1–9) ──────────────────────────────────────────────
        _setT(1, 1, "Stonehaven",   _a2(2, 4),       _empty());
        _setT(2, 1, "Frostpeak",    _a3(1, 3, 5),    _empty());
        _setT(3, 1, "Glacierhold",  _a2(2, 6),       _empty());
        _setT(4, 1, "Ironwarden",   _a3(1, 5, 7),    _empty());
        _setT(5, 1, "Rimegate",     _a4(2, 4, 6, 8), _empty());
        _setT(6, 1, "Iceholm",      _a3(3, 5, 9),    _empty());
        _setT(7, 1, "Coldpass",     _a3(4, 8, 23),   _empty()); // → Barrens
        _setT(8, 1, "Blizzardrun",  _a3(5, 7, 9),    _empty());
        _setT(9, 1, "Northwatch",   _a3(6, 8, 10),   _empty()); // → Merchant Straits

        // ── Merchant Straits (10–16) ──────────────────────────────────────────
        _setT(10, 2, "Tradehaven",   _a3(9, 11, 13),     _empty()); // ← Northlands
        _setT(11, 2, "Saltbridge",   _a3(10, 12, 14),    _empty());
        _setT(12, 2, "Harborkeep",   _a2(11, 15),        _empty());
        _setT(13, 2, "Coinwater",    _a3(10, 14, 23),    _empty()); // → Barrens
        _setT(14, 2, "Marketpass",   _a4(11, 13, 15, 16),_empty());
        _setT(15, 2, "Spicedock",    _a3(12, 14, 16),    _empty());
        _setT(16, 2, "Merchantfall", _a3(14, 15, 17),    _empty()); // → Iron Coast

        // ── Iron Coast (17–22) ────────────────────────────────────────────────
        _setT(17, 3, "Ironcliff",   _a3(16, 18, 20),  _empty()); // ← Merchant Straits
        _setT(18, 3, "Forgeharbor", _a2(17, 19),      _empty());
        _setT(19, 3, "Steelcove",   _a2(18, 22),      _empty());
        _setT(20, 3, "Anviltide",   _a3(17, 21, 35),  _empty()); // → Verdant Isles
        _setT(21, 3, "Rustwater",   _a2(20, 22),      _empty());
        _setT(22, 3, "Slagport",    _a2(19, 34),      _empty()); // → Barrens (34)

        // ── The Barrens (23–34) ───────────────────────────────────────────────
        _setT(23, 4, "Dustvault",   _a4(7, 13, 24, 26),  _empty()); // ← Northlands, Merchant Straits
        _setT(24, 4, "Ashreach",    _a3(23, 25, 27),     _empty());
        _setT(25, 4, "Sandbarrow",  _a2(24, 28),         _empty());
        _setT(26, 4, "Drypass",     _a3(23, 27, 29),     _empty());
        _setT(27, 4, "Bonecross",   _a4(24, 26, 28, 30), _empty());
        _setT(28, 4, "Saltflat",    _a3(25, 27, 31),     _empty());
        _setT(29, 4, "Mirage",      _a3(26, 30, 39),     _empty()); // → Deep Expanse
        _setT(30, 4, "Scorchfield", _a4(27, 29, 31, 32), _empty());
        _setT(31, 4, "Cinderholm",  _a3(28, 30, 33),     _empty());
        _setT(32, 4, "Embervast",   _a2(30, 33),         _empty());
        _setT(33, 4, "Dustcrown",   _a3(31, 32, 34),     _empty());
        _setT(34, 4, "Barrenkeep",  _a2(22, 33),         _empty()); // ← Iron Coast

        // ── Verdant Isles (35–38) ─────────────────────────────────────────────
        _setT(35, 5, "Greenwatch",  _a2(20, 36),  _empty());       // ← Iron Coast
        _setT(36, 5, "Bloomhaven",  _a2(35, 37),  _empty());
        _setT(37, 5, "Ferncoast",   _a2(36, 38),  _empty());
        _setT(38, 5, "Leafend",     _a1(37),      _a1(42));        // naval ↔ Deep Expanse 42

        // ── The Deep Expanse (39–42) ──────────────────────────────────────────
        _setT(39, 6, "Abyssgate",   _a2(29, 40),  _empty());       // ← Barrens
        _setT(40, 6, "Deepcurrent", _a2(39, 41),  _empty());
        _setT(41, 6, "Voidreach",   _a2(40, 42),  _empty());
        _setT(42, 6, "Dreadhollow", _a1(41),      _a1(38));        // naval ↔ Verdant Isles 38
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Minting & Burning
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc ITerritoryNFT
    function mint(address to, uint256 tokenId) external onlyRole(MINTER_ROLE) {
        if (tokenId == 0 || tokenId > TOTAL_TERRITORIES) revert TerritoryNFT__InvalidTerritoryId(tokenId);
        if (_ownerOf(tokenId) != address(0)) revert TerritoryNFT__AlreadyMinted(tokenId);
        if (_walletCount[to] >= MAX_TERRITORIES_PER_WALLET) {
            revert TerritoryNFT__MaxTerritoriesExceeded(to, MAX_TERRITORIES_PER_WALLET);
        }
        _safeMint(to, tokenId);
    }

    /// @inheritdoc ITerritoryNFT
    function burn(uint256 tokenId) external onlyRole(MINTER_ROLE) {
        _burn(tokenId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Season Lifecycle
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc ITerritoryNFT
    function lockForSeason(uint256 seasonId) external onlyRole(GAME_ENGINE_ROLE) {
        _seasonLocked = true;
        _currentSeasonId = seasonId;
        _tradingWindowEnd = 0;
        emit SeasonLocked(seasonId);
    }

    /// @inheritdoc ITerritoryNFT
    function unlockAfterSeason(uint256 seasonId) external onlyRole(GAME_ENGINE_ROLE) {
        _seasonLocked = false;
        _tradingWindowEnd = block.timestamp + TRADING_WINDOW_DURATION;
        emit SeasonUnlocked(seasonId, _tradingWindowEnd);
    }

    /// @inheritdoc ITerritoryNFT
    function closeTradingWindow() external onlyRole(GAME_MASTER_ROLE) {
        _seasonLocked = true;
        _tradingWindowEnd = 0;
        emit TradingWindowClosed(_currentSeasonId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Conquest Transfer (GameEngine only — bypasses season lock)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Transfers a territory as a result of in-game conquest.
    /// @dev Bypasses the season lock. Only callable by GameEngine (GAME_ENGINE_ROLE).
    ///      Uses a re-entrancy-safe flag to allow _update to proceed.
    function conquestTransfer(address from, address to, uint256 tokenId)
        external
        onlyRole(GAME_ENGINE_ROLE)
    {
        _inConquestTransfer = true;
        _transfer(from, to, tokenId);
        _inConquestTransfer = false;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ERC-721 Overrides
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Enforces season lock and wallet cap. Conquest transfers bypass the lock.
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        whenNotPaused
        returns (address)
    {
        address from = _ownerOf(tokenId);

        // Real transfer (not mint or burn)
        if (from != address(0) && to != address(0)) {
            // During season: only GameEngine conquest transfers allowed
            if (_seasonLocked && !_inConquestTransfer) {
                revert TerritoryNFT__TransferLocked(tokenId);
            }
            // Inter-season: enforce trading window
            if (!_seasonLocked && _tradingWindowEnd > 0 && block.timestamp > _tradingWindowEnd) {
                revert TerritoryNFT__TradingWindowExpired();
            }
            // Wallet cap on incoming transfers (not conquest — GameEngine handles cap internally)
            if (!_inConquestTransfer && _walletCount[to] >= MAX_TERRITORIES_PER_WALLET) {
                revert TerritoryNFT__MaxTerritoriesExceeded(to, MAX_TERRITORIES_PER_WALLET);
            }
            _walletCount[from]--;
            _walletCount[to]++;
        } else if (from == address(0)) {
            // Minting
            _walletCount[to]++;
        } else {
            // Burning
            _walletCount[from]--;
        }

        return super._update(to, tokenId, auth);
    }

    /// @dev Required by Solidity for multiple inheritance.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Pause (emergency)
    // ─────────────────────────────────────────────────────────────────────────

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Map Queries
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc ITerritoryNFT
    function getTerritoryMeta(uint256 tokenId) external view returns (TerritoryMeta memory) {
        if (tokenId == 0 || tokenId > TOTAL_TERRITORIES) revert TerritoryNFT__InvalidTerritoryId(tokenId);
        return _territoryMeta[tokenId];
    }

    /// @inheritdoc ITerritoryNFT
    function getContinentMeta(uint8 continentId) external view returns (ContinentMeta memory) {
        return _continentMeta[continentId];
    }

    /// @inheritdoc ITerritoryNFT
    function continentOf(uint256 tokenId) external view returns (uint8) {
        return _territoryMeta[tokenId].continentId;
    }

    /// @inheritdoc ITerritoryNFT
    function adjacentTo(uint256 tokenId) external view returns (uint256[] memory) {
        return _territoryMeta[tokenId].adjacentIds;
    }

    /// @inheritdoc ITerritoryNFT
    function navalTargetsOf(uint256 tokenId) external view returns (uint256[] memory) {
        return _territoryMeta[tokenId].navalIds;
    }

    /// @inheritdoc ITerritoryNFT
    function isAdjacent(uint256 tokenId, uint256 otherId) external view returns (bool) {
        return _isAdjacent(tokenId, otherId);
    }

    function _isAdjacent(uint256 tokenId, uint256 otherId) internal view returns (bool) {
        uint256[] storage adj = _territoryMeta[tokenId].adjacentIds;
        for (uint256 i; i < adj.length; ++i) {
            if (adj[i] == otherId) return true;
        }
        return false;
    }

    /// @inheritdoc ITerritoryNFT
    function controlsContinent(address owner, uint8 continentId) external view returns (bool) {
        uint256[] storage territories = _continentMeta[continentId].territoryIds;
        for (uint256 i; i < territories.length; ++i) {
            if (ownerOf(territories[i]) != owner) return false;
        }
        return true;
    }

    /// @inheritdoc ITerritoryNFT
    function territoriesOwnedBy(address owner) external view returns (uint256) {
        return _walletCount[owner];
    }

    /// @inheritdoc ITerritoryNFT
    function territoriesOf(address owner) external view returns (uint256[] memory) {
        uint256 count = _walletCount[owner];
        uint256[] memory result = new uint256[](count);
        uint256 idx;
        for (uint256 i = 1; i <= TOTAL_TERRITORIES && idx < count; ++i) {
            if (_ownerOf(i) == owner) {
                result[idx++] = i;
            }
        }
        return result;
    }

    /// @inheritdoc ITerritoryNFT
    function canTransfer(uint256 /*tokenId*/) external view returns (bool) {
        if (_seasonLocked) return false;
        if (_tradingWindowEnd > 0 && block.timestamp > _tradingWindowEnd) return false;
        return true;
    }

    /// @inheritdoc ITerritoryNFT
    function isLocked() external view returns (bool) {
        return _seasonLocked;
    }

    /// @inheritdoc ITerritoryNFT
    function tradingWindowEndsAt() external view returns (uint256) {
        return _tradingWindowEnd;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private Array Helpers
    // ─────────────────────────────────────────────────────────────────────────

    function _setT(
        uint256 id,
        uint8 continent,
        bytes32 name,
        uint256[] memory adj,
        uint256[] memory naval
    ) private {
        _territoryMeta[id] = TerritoryMeta({
            continentId: continent,
            name: name,
            adjacentIds: adj,
            navalIds: naval
        });
    }

    function _range(uint256 from, uint256 to) private pure returns (uint256[] memory arr) {
        arr = new uint256[](to - from + 1);
        for (uint256 i; i < arr.length; ++i) arr[i] = from + i;
    }

    function _empty() private pure returns (uint256[] memory arr) { arr = new uint256[](0); }

    function _a1(uint256 a) private pure returns (uint256[] memory arr) {
        arr = new uint256[](1);
        arr[0] = a;
    }

    function _a2(uint256 a, uint256 b) private pure returns (uint256[] memory arr) {
        arr = new uint256[](2);
        arr[0] = a; arr[1] = b;
    }

    function _a3(uint256 a, uint256 b, uint256 c) private pure returns (uint256[] memory arr) {
        arr = new uint256[](3);
        arr[0] = a; arr[1] = b; arr[2] = c;
    }

    function _a4(uint256 a, uint256 b, uint256 c, uint256 d) private pure returns (uint256[] memory arr) {
        arr = new uint256[](4);
        arr[0] = a; arr[1] = b; arr[2] = c; arr[3] = d;
    }
}
