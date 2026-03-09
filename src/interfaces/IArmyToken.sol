// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IArmyToken
/// @notice ERC-1155 interface for Base-Conquest army units.
/// @dev Five unit types exist with the following token IDs and Infantry-equivalent costs:
///
///      ID  | Name      | Cost (Infantry) | Combat Effect
///      ----|-----------|-----------------|----------------------------------------------------
///       1  | Infantry  | 1               | Standard unit; counts as 1 army slot
///       2  | Cavalry   | 3               | Attacker rerolls lowest attack die
///       3  | Artillery | 5               | Defender rerolls lowest defense die
///       4  | General   | 10              | Adds +1 attack die to the territory (max 4 total)
///       5  | Admiral   | 10              | Enables naval attacks from this territory
///
///      Army tokens are SOULBOUND to the game session:
///      - Transferability is disabled for all token IDs (reverts on safeTransferFrom)
///      - Only the GameEngine contract (holding MINTER_ROLE and BURNER_ROLE) may mint/burn
///      - Upgrade trades (Infantry → Cavalry etc.) are done through GameEngine, not direct transfer
///
///      Territory assignment is tracked in the GameEngine's storage, not in this contract.
///      This contract only tracks the per-wallet balance of each unit type.
interface IArmyToken {
    // ─────────────────────────────────────────────────────────────────────────
    // Constants (returned as view functions for use in interfaces)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Token ID for Infantry units.
    function INFANTRY() external view returns (uint256);

    /// @notice Token ID for Cavalry units.
    function CAVALRY() external view returns (uint256);

    /// @notice Token ID for Artillery units.
    function ARTILLERY() external view returns (uint256);

    /// @notice Token ID for General units.
    function GENERAL() external view returns (uint256);

    /// @notice Token ID for Admiral units.
    function ADMIRAL() external view returns (uint256);

    /// @notice Infantry cost to upgrade to Cavalry (3 Infantry → 1 Cavalry).
    function CAVALRY_COST() external view returns (uint256);

    /// @notice Infantry cost to upgrade to Artillery (5 Infantry → 1 Artillery).
    function ARTILLERY_COST() external view returns (uint256);

    /// @notice Infantry cost to upgrade to General (10 Infantry → 1 General).
    function GENERAL_COST() external view returns (uint256);

    /// @notice Infantry cost to upgrade to Admiral (10 Infantry → 1 Admiral).
    function ADMIRAL_COST() external view returns (uint256);

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Emitted when units are minted to a player during Reinforce phase.
    event ArmiesMinted(address indexed player, uint256 indexed unitType, uint256 amount);

    /// @notice Emitted when units are burned after combat losses.
    event ArmiesBurned(address indexed player, uint256 indexed unitType, uint256 amount);

    /// @notice Emitted when a player upgrades Infantry to a higher-tier unit.
    event UnitsUpgraded(
        address indexed player,
        uint256 indexed fromUnitType,
        uint256 indexed toUnitType,
        uint256 amountUpgraded,
        uint256 infantryConsumed
    );

    // ─────────────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────────────

    error ArmyToken__Soulbound();
    error ArmyToken__NotGameEngine(address caller);
    error ArmyToken__InvalidUnitType(uint256 unitType);
    error ArmyToken__InsufficientBalance(address player, uint256 unitType, uint256 available, uint256 required);
    error ArmyToken__InvalidUpgradeTarget(uint256 fromUnitType, uint256 toUnitType);
    error ArmyToken__ZeroAmount();

    // ─────────────────────────────────────────────────────────────────────────
    // Minting & Burning (MINTER_ROLE / BURNER_ROLE — GameEngine only)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Mints `amount` units of `unitType` to `player`.
    /// @dev Only callable by MINTER_ROLE (GameEngine). Called during startTurn() when
    ///      reinforcement armies are granted.
    ///      Reverts if `unitType` is not in [1, 5].
    /// @param player    Address receiving the units.
    /// @param unitType  Unit type token ID (1–5).
    /// @param amount    Number of units to mint.
    function mint(address player, uint256 unitType, uint256 amount) external;

    /// @notice Mints multiple unit types in a single call (gas-efficient batch reinforce).
    /// @dev Only callable by MINTER_ROLE. Arrays must be the same length.
    /// @param player     Address receiving the units.
    /// @param unitTypes  Array of unit type IDs.
    /// @param amounts    Corresponding amounts for each unit type.
    function mintBatch(address player, uint256[] calldata unitTypes, uint256[] calldata amounts) external;

    /// @notice Burns `amount` units of `unitType` from `player` after combat losses.
    /// @dev Only callable by BURNER_ROLE (GameEngine).
    ///      Reverts if player balance is insufficient.
    /// @param player    Address losing the units.
    /// @param unitType  Unit type token ID (1–5).
    /// @param amount    Number of units to burn.
    function burn(address player, uint256 unitType, uint256 amount) external;

    /// @notice Burns multiple unit types in a single call.
    /// @dev Only callable by BURNER_ROLE.
    function burnBatch(address player, uint256[] calldata unitTypes, uint256[] calldata amounts) external;

    // ─────────────────────────────────────────────────────────────────────────
    // Unit Upgrades (callable by players via GameEngine)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Upgrades Infantry units to a higher-tier unit type.
    /// @dev Burns the required Infantry and mints the target unit type.
    ///      Only callable by GameEngine (which validates season phase).
    ///      Valid upgrades:
    ///        INFANTRY (1) → CAVALRY   (2): costs 3 Infantry each
    ///        INFANTRY (1) → ARTILLERY (3): costs 5 Infantry each
    ///        INFANTRY (1) → GENERAL   (4): costs 10 Infantry each
    ///        INFANTRY (1) → ADMIRAL   (5): costs 10 Infantry each
    /// @param player         Player performing the upgrade.
    /// @param toUnitType     Target unit type (2, 3, 4, or 5).
    /// @param upgradeAmount  Number of upgraded units to produce.
    function upgradeUnits(address player, uint256 toUnitType, uint256 upgradeAmount) external;

    // ─────────────────────────────────────────────────────────────────────────
    // View Functions
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Returns the player's balance of a specific unit type.
    /// @param player    Address to query.
    /// @param unitType  Unit type token ID (1–5).
    function balanceOf(address player, uint256 unitType) external view returns (uint256);

    /// @notice Returns the player's balance of all five unit types.
    /// @return balances  Array of balances indexed [0..4] corresponding to unit types [1..5].
    function allBalances(address player) external view returns (uint256[5] memory balances);

    /// @notice Returns the total Infantry-equivalent strength of a player's holdings.
    /// @dev Infantry=1, Cavalry=3, Artillery=5, General=10, Admiral=10.
    function totalStrength(address player) external view returns (uint256);

    /// @notice Returns the Infantry cost to produce one unit of `toUnitType`.
    /// @param toUnitType  Target unit type (2–5). Reverts for Infantry (1).
    function upgradeCost(uint256 toUnitType) external view returns (uint256 infantryCost);

    /// @notice Returns true if `unitType` is a valid unit type ID (1–5).
    function isValidUnitType(uint256 unitType) external pure returns (bool);
}
