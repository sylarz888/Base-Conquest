// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IArmyToken} from "../interfaces/IArmyToken.sol";

/// @title ArmyToken
/// @notice ERC-1155 representing the five army unit types in Base-Conquest.
/// @dev Tokens are soulbound — all external transfers are disabled. Only the GameEngine
///      (GAME_ENGINE_ROLE) may mint, burn, or upgrade units.
///
///      Unit type IDs and Infantry-equivalent costs:
///        1 Infantry  — 1  Infantry  (base unit)
///        2 Cavalry   — 3  Infantry  (attacker rerolls lowest die)
///        3 Artillery — 5  Infantry  (defender rerolls lowest die)
///        4 General   — 10 Infantry  (+1 attack die, max 4 total)
///        5 Admiral   — 10 Infantry  (enables naval attacks)
contract ArmyToken is IArmyToken, ERC1155, AccessControl {
    // ── Roles ─────────────────────────────────────────────────────────────────
    bytes32 public constant GAME_ENGINE_ROLE = keccak256("GAME_ENGINE_ROLE");

    // ── Unit Type Constants ───────────────────────────────────────────────────
    uint256 private constant _INFANTRY  = 1;
    uint256 private constant _CAVALRY   = 2;
    uint256 private constant _ARTILLERY = 3;
    uint256 private constant _GENERAL   = 4;
    uint256 private constant _ADMIRAL   = 5;

    uint256 private constant _CAVALRY_COST   = 3;
    uint256 private constant _ARTILLERY_COST = 5;
    uint256 private constant _GENERAL_COST   = 10;
    uint256 private constant _ADMIRAL_COST   = 10;

    // ── Infantry-equivalent strength per unit type ────────────────────────────
    uint256[6] private _strength = [0, 1, 3, 5, 10, 10]; // index = unit type

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    constructor(address admin, string memory uri_) ERC1155(uri_) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // IArmyToken constant views
    // ─────────────────────────────────────────────────────────────────────────

    function INFANTRY()  external pure returns (uint256) { return _INFANTRY; }
    function CAVALRY()   external pure returns (uint256) { return _CAVALRY; }
    function ARTILLERY() external pure returns (uint256) { return _ARTILLERY; }
    function GENERAL()   external pure returns (uint256) { return _GENERAL; }
    function ADMIRAL()   external pure returns (uint256) { return _ADMIRAL; }

    function CAVALRY_COST()   external pure returns (uint256) { return _CAVALRY_COST; }
    function ARTILLERY_COST() external pure returns (uint256) { return _ARTILLERY_COST; }
    function GENERAL_COST()   external pure returns (uint256) { return _GENERAL_COST; }
    function ADMIRAL_COST()   external pure returns (uint256) { return _ADMIRAL_COST; }

    // ─────────────────────────────────────────────────────────────────────────
    // Soulbound — disable all external transfers
    // ─────────────────────────────────────────────────────────────────────────

    function safeTransferFrom(address, address, uint256, uint256, bytes memory)
        public
        pure
        override
    {
        revert ArmyToken__Soulbound();
    }

    function safeBatchTransferFrom(address, address, uint256[] memory, uint256[] memory, bytes memory)
        public
        pure
        override
    {
        revert ArmyToken__Soulbound();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Minting (GAME_ENGINE_ROLE)
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IArmyToken
    function mint(address player, uint256 unitType, uint256 amount)
        external
        onlyRole(GAME_ENGINE_ROLE)
    {
        if (amount == 0) revert ArmyToken__ZeroAmount();
        if (!_validType(unitType)) revert ArmyToken__InvalidUnitType(unitType);
        _mint(player, unitType, amount, "");
        emit ArmiesMinted(player, unitType, amount);
    }

    /// @inheritdoc IArmyToken
    function mintBatch(address player, uint256[] calldata unitTypes, uint256[] calldata amounts)
        external
        onlyRole(GAME_ENGINE_ROLE)
    {
        uint256 len = unitTypes.length;
        for (uint256 i; i < len; ++i) {
            if (!_validType(unitTypes[i])) revert ArmyToken__InvalidUnitType(unitTypes[i]);
            if (amounts[i] == 0) revert ArmyToken__ZeroAmount();
        }
        _mintBatch(player, unitTypes, amounts, "");
        for (uint256 i; i < len; ++i) {
            emit ArmiesMinted(player, unitTypes[i], amounts[i]);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Burning (GAME_ENGINE_ROLE)
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IArmyToken
    function burn(address player, uint256 unitType, uint256 amount)
        external
        onlyRole(GAME_ENGINE_ROLE)
    {
        if (amount == 0) revert ArmyToken__ZeroAmount();
        if (!_validType(unitType)) revert ArmyToken__InvalidUnitType(unitType);
        uint256 bal = balanceOf(player, unitType);
        if (bal < amount) revert ArmyToken__InsufficientBalance(player, unitType, bal, amount);
        _burn(player, unitType, amount);
        emit ArmiesBurned(player, unitType, amount);
    }

    /// @inheritdoc IArmyToken
    function burnBatch(address player, uint256[] calldata unitTypes, uint256[] calldata amounts)
        external
        onlyRole(GAME_ENGINE_ROLE)
    {
        uint256 len = unitTypes.length;
        for (uint256 i; i < len; ++i) {
            if (!_validType(unitTypes[i])) revert ArmyToken__InvalidUnitType(unitTypes[i]);
            uint256 bal = balanceOf(player, unitTypes[i]);
            if (bal < amounts[i]) {
                revert ArmyToken__InsufficientBalance(player, unitTypes[i], bal, amounts[i]);
            }
        }
        _burnBatch(player, unitTypes, amounts);
        for (uint256 i; i < len; ++i) {
            emit ArmiesBurned(player, unitTypes[i], amounts[i]);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Unit Upgrades (GAME_ENGINE_ROLE)
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IArmyToken
    function upgradeUnits(address player, uint256 toUnitType, uint256 upgradeAmount)
        external
        onlyRole(GAME_ENGINE_ROLE)
    {
        if (toUnitType < _CAVALRY || toUnitType > _ADMIRAL) {
            revert ArmyToken__InvalidUpgradeTarget(_INFANTRY, toUnitType);
        }
        if (upgradeAmount == 0) revert ArmyToken__ZeroAmount();

        uint256 cost = _upgradeCost(toUnitType) * upgradeAmount;
        uint256 infantryBal = balanceOf(player, _INFANTRY);
        if (infantryBal < cost) {
            revert ArmyToken__InsufficientBalance(player, _INFANTRY, infantryBal, cost);
        }

        _burn(player, _INFANTRY, cost);
        _mint(player, toUnitType, upgradeAmount, "");

        emit UnitsUpgraded(player, _INFANTRY, toUnitType, upgradeAmount, cost);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // View Functions
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IArmyToken
    function allBalances(address player) external view returns (uint256[5] memory bals) {
        for (uint256 i; i < 5; ++i) bals[i] = balanceOf(player, i + 1);
    }

    /// @inheritdoc IArmyToken
    function totalStrength(address player) external view returns (uint256 total) {
        for (uint256 t = 1; t <= 5; ++t) {
            total += balanceOf(player, t) * _strength[t];
        }
    }

    /// @inheritdoc IArmyToken
    function upgradeCost(uint256 toUnitType) external pure returns (uint256) {
        if (toUnitType < _CAVALRY || toUnitType > _ADMIRAL) {
            revert ArmyToken__InvalidUnitType(toUnitType);
        }
        return _upgradeCost(toUnitType);
    }

    /// @inheritdoc IArmyToken
    function isValidUnitType(uint256 unitType) external pure returns (bool) {
        return _validType(unitType);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internals
    // ─────────────────────────────────────────────────────────────────────────

    function _validType(uint256 t) internal pure returns (bool) {
        return t >= _INFANTRY && t <= _ADMIRAL;
    }

    function _upgradeCost(uint256 toUnitType) internal pure returns (uint256) {
        if (toUnitType == _CAVALRY)   return _CAVALRY_COST;
        if (toUnitType == _ARTILLERY) return _ARTILLERY_COST;
        if (toUnitType == _GENERAL)   return _GENERAL_COST;
        if (toUnitType == _ADMIRAL)   return _ADMIRAL_COST;
        revert ArmyToken__InvalidUnitType(toUnitType);
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
