// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ITerritoryCard
/// @notice ERC-1155 interface for Base-Conquest territory cards.
/// @dev Cards are drawn when a player captures at least one territory per turn.
///      Three card types exist:
///
///      ID | Type      | Bonus (classic Risk set trades)
///      ---|-----------|--------------------------------
///       1 | Infantry  | Part of all valid card sets
///       2 | Cavalry   | Part of all valid card sets
///       3 | Artillery | Part of all valid card sets
///
///      Valid set trades (burned by GameEngine during redeemCards):
///        3 × Infantry  → 4  bonus armies (before global escalation)
///        3 × Cavalry   → 6  bonus armies
///        3 × Artillery → 8  bonus armies
///        1 × each type → 10 bonus armies
///      +2 additional armies to a territory the player owns if one card matches it.
///
///      Unlike ArmyTokens, territory cards ARE tradeable between players during an
///      active season (creates in-game card economy). They are burned on use.
///      After a season ends, surplus cards can be redeemed for CONQUEST tokens.
interface ITerritoryCard {
    // ─────────────────────────────────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Token ID for Infantry cards.
    function INFANTRY_CARD() external view returns (uint256);

    /// @notice Token ID for Cavalry cards.
    function CAVALRY_CARD() external view returns (uint256);

    /// @notice Token ID for Artillery cards.
    function ARTILLERY_CARD() external view returns (uint256);

    // ─────────────────────────────────────────────────────────────────────────
    // Structs
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Metadata embedded in each card token (stored off-chain in URI, verified on-chain via hash).
    /// @param territoryId   The territory depicted on the card (1–42).
    /// @param cardType      Card type (1=Infantry, 2=Cavalry, 3=Artillery).
    /// @param seasonId      Season in which the card was drawn.
    struct CardMeta {
        uint256 territoryId;
        uint8 cardType;
        uint256 seasonId;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Emitted when a card is drawn by a player after capturing a territory.
    event CardDrawn(address indexed player, uint8 indexed cardType, uint256 indexed territoryId, uint256 seasonId);

    /// @notice Emitted when a set of three cards is burned for bonus armies.
    event CardSetBurned(address indexed player, uint8[3] cardTypes, uint256 bonusArmies, uint256 setsRedeemedGlobal);

    /// @notice Emitted when surplus cards are redeemed for CONQUEST tokens after a season.
    event CardsRedeemedForConquest(address indexed player, uint8 cardType, uint256 amount, uint256 conquestAwarded);

    // ─────────────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────────────

    error TerritoryCard__NotGameEngine(address caller);
    error TerritoryCard__InvalidCardType(uint8 cardType);
    error TerritoryCard__InvalidCardSet(uint8[3] cardTypes);
    error TerritoryCard__InsufficientCards(address player, uint8 cardType, uint256 available, uint256 required);
    error TerritoryCard__SeasonStillActive();
    error TerritoryCard__ZeroAmount();

    // ─────────────────────────────────────────────────────────────────────────
    // Minting (MINTER_ROLE — GameEngine only)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Draws one card of a pseudo-random type for a player.
    /// @dev Only callable by MINTER_ROLE (GameEngine). Called in `endTurn()` when
    ///      `drewCardThisTurn == true`. Card type is derived from VRF randomness stored
    ///      in the combat that triggered the conquest.
    ///      The `territoryId` is the territory that triggered the card draw.
    /// @param player       Address receiving the card.
    /// @param cardType     Card type to mint (1, 2, or 3).
    /// @param territoryId  Territory depicted on this card (1–42).
    function draw(address player, uint8 cardType, uint256 territoryId) external;

    // ─────────────────────────────────────────────────────────────────────────
    // Burning (BURNER_ROLE — GameEngine only)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Burns a set of three cards from a player's hand.
    /// @dev Only callable by BURNER_ROLE (GameEngine). Called during `redeemCards()`.
    ///      Validates that the set is one of the four valid combinations before burning.
    ///      Increments the global `setsRedeemedCount` used for escalation.
    /// @param player     Address whose cards are being burned.
    /// @param cardTypes  Three card type values forming a valid set.
    /// @return bonusArmies  Armies awarded based on the set type and global escalation.
    function burnSet(address player, uint8[3] calldata cardTypes) external returns (uint256 bonusArmies);

    /// @notice Redeems surplus cards for CONQUEST tokens after a season ends.
    /// @dev Only callable after the season has ended (`seasonPhase == ENDED`).
    ///      Burns `amount` cards of `cardType` from the caller and transfers CONQUEST.
    ///      Rate: configurable by governance; starts at 10 CONQUEST per card.
    /// @param cardType  Card type to redeem (1, 2, or 3).
    /// @param amount    Number of cards to redeem.
    function redeemForConquest(uint8 cardType, uint256 amount) external;

    // ─────────────────────────────────────────────────────────────────────────
    // View Functions
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Returns the player's balance of a specific card type.
    /// @param player    Address to query.
    /// @param cardType  Card type (1, 2, or 3).
    function cardBalance(address player, uint8 cardType) external view returns (uint256);

    /// @notice Returns the player's balance of all three card types.
    /// @return infantry   Balance of Infantry cards.
    /// @return cavalry    Balance of Cavalry cards.
    /// @return artillery  Balance of Artillery cards.
    function allCardBalances(address player)
        external
        view
        returns (uint256 infantry, uint256 cavalry, uint256 artillery);

    /// @notice Returns the global count of card sets that have been redeemed this season.
    /// @dev Used to determine the escalated bonus army value for the next redemption.
    function setsRedeemedCount() external view returns (uint256);

    /// @notice Calculates the bonus armies for the next set redemption given the current
    ///         global count and the type of set being redeemed.
    /// @param setsAlreadyRedeemed  Current value of `setsRedeemedCount()` before this trade.
    /// @param cardTypes            The three card type values of the proposed set.
    /// @return bonusArmies         Armies that would be awarded (before +2 territory bonus).
    function previewSetBonus(uint256 setsAlreadyRedeemed, uint8[3] calldata cardTypes)
        external
        view
        returns (uint256 bonusArmies);

    /// @notice Returns true if the three card types form a valid redeemable set.
    /// @dev Valid sets: 3×Infantry, 3×Cavalry, 3×Artillery, or 1×each.
    function isValidSet(uint8[3] calldata cardTypes) external pure returns (bool);

    /// @notice Returns the CONQUEST token redemption rate per card (in wei).
    function conquestRedemptionRate() external view returns (uint256);
}
