// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ITerritoryNFT
/// @notice ERC-721 interface for Base-Conquest territory ownership.
/// @dev Each of the 42 territories on The Base Archipelago map is represented as an NFT.
///      Token IDs 1–42 are used. IDs are fixed to specific map territories and never change.
///
///      Lifecycle per Season:
///      1. GAME_MASTER mints all 42 tokens at auction start → owners set by auction winner
///      2. On `lockForSeason`: tokens become non-transferable (in-game conquest only)
///      3. On `unlockAfterSeason`: tokens become freely tradeable for a 14-day window
///      4. Next season: tokens are burned and re-minted by the new auction
///
///      The `_update` override checks `IGameEngine.canTransfer` during the locked phase.
interface ITerritoryNFT {
    // ─────────────────────────────────────────────────────────────────────────
    // Structs
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Static map metadata for a territory. Set at contract deployment and immutable.
    /// @param continentId   ID of the island chain (1–6) this territory belongs to.
    /// @param name          Human-readable territory name (e.g. "Stonehaven").
    /// @param adjacentIds   Token IDs of territories that share a land border.
    /// @param navalIds      Token IDs reachable via Admiral naval attacks only.
    struct TerritoryMeta {
        uint8 continentId;
        bytes32 name;
        uint256[] adjacentIds;
        uint256[] navalIds;
    }

    /// @notice Per-continent configuration. Set at deployment and immutable.
    /// @param name         Human-readable continent name (e.g. "The Northlands").
    /// @param territoryIds All territory token IDs belonging to this continent.
    /// @param bonusArmies  Reinforcement bonus awarded for controlling all territories.
    struct ContinentMeta {
        bytes32 name;
        uint256[] territoryIds;
        uint8 bonusArmies;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Emitted when all territory NFTs are locked at the start of an active season.
    event SeasonLocked(uint256 indexed seasonId);

    /// @notice Emitted when territory NFTs are unlocked for the inter-season trading window.
    event SeasonUnlocked(uint256 indexed seasonId, uint256 tradingWindowEndsAt);

    /// @notice Emitted when the inter-season trading window closes.
    event TradingWindowClosed(uint256 indexed seasonId);

    // ─────────────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────────────

    error TerritoryNFT__TransferLocked(uint256 tokenId);
    error TerritoryNFT__NotGameEngine(address caller);
    error TerritoryNFT__NotMinter(address caller);
    error TerritoryNFT__InvalidTerritoryId(uint256 tokenId);
    error TerritoryNFT__AlreadyMinted(uint256 tokenId);
    error TerritoryNFT__TradingWindowExpired();
    error TerritoryNFT__MaxTerritoriesExceeded(address buyer, uint256 cap);

    // ─────────────────────────────────────────────────────────────────────────
    // Minting & Burning (MINTER_ROLE only)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Mints a territory NFT to an address (called by auction contract at season start).
    /// @dev Only callable by MINTER_ROLE. Reverts if token ID is not in range [1, 42].
    ///      Enforces the 12-territory-per-wallet cap at mint time.
    /// @param to        Address to receive the NFT.
    /// @param tokenId   Territory token ID (1–42).
    function mint(address to, uint256 tokenId) external;

    /// @notice Burns a territory NFT at end of season before re-minting for the next auction.
    /// @dev Only callable by MINTER_ROLE. Token must exist.
    /// @param tokenId  Territory token ID to burn.
    function burn(uint256 tokenId) external;

    // ─────────────────────────────────────────────────────────────────────────
    // Season Lifecycle (GAME_MASTER_ROLE / GameEngine only)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Locks all tokens. Called by GameEngine when AUCTION → ACTIVE transition occurs.
    /// @dev Sets `_seasonLocked = true`. Subsequent transfers via `_update` revert with
    ///      `TerritoryNFT__TransferLocked` unless the caller is the GameEngine contract.
    /// @param seasonId  The ID of the season being activated.
    function lockForSeason(uint256 seasonId) external;

    /// @notice Unlocks tokens for the 14-day inter-season trading window.
    /// @dev Called by GameEngine when a season ends (domination or timer).
    ///      Sets `_tradingWindowEndsAt = block.timestamp + 14 days`.
    /// @param seasonId  The ID of the season that just ended.
    function unlockAfterSeason(uint256 seasonId) external;

    /// @notice Closes the trading window early or on-demand (called before next season auction).
    /// @dev Sets `_seasonLocked = true` again. Only callable by GAME_MASTER_ROLE.
    function closeTradingWindow() external;

    // ─────────────────────────────────────────────────────────────────────────
    // Map Queries
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Returns the static map metadata for a territory.
    /// @param tokenId  Territory token ID (1–42).
    function getTerritoryMeta(uint256 tokenId) external view returns (TerritoryMeta memory);

    /// @notice Returns the continent configuration for a given continent ID (1–6).
    function getContinentMeta(uint8 continentId) external view returns (ContinentMeta memory);

    /// @notice Returns the continent ID that `tokenId` belongs to.
    function continentOf(uint256 tokenId) external view returns (uint8);

    /// @notice Returns all territory IDs adjacent to `tokenId` (land borders only).
    function adjacentTo(uint256 tokenId) external view returns (uint256[] memory);

    /// @notice Returns all territory IDs reachable via naval attack from `tokenId`.
    function navalTargetsOf(uint256 tokenId) external view returns (uint256[] memory);

    /// @notice Returns true if `tokenId` and `otherId` share a land border.
    function isAdjacent(uint256 tokenId, uint256 otherId) external view returns (bool);

    /// @notice Returns true if `owner` controls all territories in `continentId`.
    function controlsContinent(address owner, uint8 continentId) external view returns (bool);

    /// @notice Returns the number of territories currently owned by `owner`.
    function territoriesOwnedBy(address owner) external view returns (uint256);

    /// @notice Returns all territory token IDs currently owned by `owner`.
    function territoriesOf(address owner) external view returns (uint256[] memory);

    // ─────────────────────────────────────────────────────────────────────────
    // Transfer Guard (called by GameEngine)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Returns true if `tokenId` may be externally transferred right now.
    /// @dev Returns true only when the season is not locked (inter-season trading window).
    ///      GameEngine calls this from its own `canTransfer` implementation.
    function canTransfer(uint256 tokenId) external view returns (bool);

    // ─────────────────────────────────────────────────────────────────────────
    // Season State Queries
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Returns true if tokens are currently locked (active season in progress).
    function isLocked() external view returns (bool);

    /// @notice Returns the Unix timestamp at which the inter-season trading window closes.
    ///         Returns 0 if the trading window is not currently open.
    function tradingWindowEndsAt() external view returns (uint256);
}
