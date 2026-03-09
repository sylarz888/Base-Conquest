// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ArmyToken} from "../../src/tokens/ArmyToken.sol";
import {IArmyToken} from "../../src/interfaces/IArmyToken.sol";

contract ArmyTokenTest is Test {
    ArmyToken public token;

    address public admin      = makeAddr("admin");
    address public gameEngine = makeAddr("gameEngine");
    address public player     = makeAddr("player");
    address public other      = makeAddr("other");

    function setUp() public {
        vm.startPrank(admin);
        token = new ArmyToken(admin, "https://base-conquest.io/army/{id}.json");
        token.grantRole(token.GAME_ENGINE_ROLE(), gameEngine);
        vm.stopPrank();
    }

    // ── Constants ─────────────────────────────────────────────────────────────

    function test_unitTypeConstants() public view {
        assertEq(token.INFANTRY(),  1);
        assertEq(token.CAVALRY(),   2);
        assertEq(token.ARTILLERY(), 3);
        assertEq(token.GENERAL(),   4);
        assertEq(token.ADMIRAL(),   5);
    }

    function test_upgradeCosts() public view {
        assertEq(token.CAVALRY_COST(),   3);
        assertEq(token.ARTILLERY_COST(), 5);
        assertEq(token.GENERAL_COST(),   10);
        assertEq(token.ADMIRAL_COST(),   10);
    }

    // ── Minting ───────────────────────────────────────────────────────────────

    function test_mintInfantryByGameEngine() public {
        vm.prank(gameEngine);
        token.mint(player, 1, 10);
        assertEq(token.balanceOf(player, 1), 10);
    }

    function test_mintAllUnitTypes() public {
        vm.startPrank(gameEngine);
        for (uint256 t = 1; t <= 5; ++t) {
            token.mint(player, t, 1);
        }
        vm.stopPrank();
        uint256[5] memory bals = token.allBalances(player);
        for (uint256 i; i < 5; ++i) assertEq(bals[i], 1);
    }

    function test_mintRevertsIfNotGameEngine() public {
        vm.prank(player);
        vm.expectRevert();
        token.mint(player, 1, 10);
    }

    function test_mintRevertsOnInvalidUnitType() public {
        vm.prank(gameEngine);
        vm.expectRevert(abi.encodeWithSelector(IArmyToken.ArmyToken__InvalidUnitType.selector, 6));
        token.mint(player, 6, 1);
    }

    function test_mintRevertsOnZeroAmount() public {
        vm.prank(gameEngine);
        vm.expectRevert(IArmyToken.ArmyToken__ZeroAmount.selector);
        token.mint(player, 1, 0);
    }

    function test_mintBatch() public {
        uint256[] memory types   = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        types[0] = 1; amounts[0] = 5;
        types[1] = 2; amounts[1] = 2;

        vm.prank(gameEngine);
        token.mintBatch(player, types, amounts);

        assertEq(token.balanceOf(player, 1), 5);
        assertEq(token.balanceOf(player, 2), 2);
    }

    // ── Burning ───────────────────────────────────────────────────────────────

    function test_burnByGameEngine() public {
        vm.prank(gameEngine);
        token.mint(player, 1, 10);

        vm.prank(gameEngine);
        token.burn(player, 1, 4);

        assertEq(token.balanceOf(player, 1), 6);
    }

    function test_burnRevertsIfInsufficientBalance() public {
        vm.prank(gameEngine);
        token.mint(player, 1, 3);

        vm.prank(gameEngine);
        vm.expectRevert(
            abi.encodeWithSelector(IArmyToken.ArmyToken__InsufficientBalance.selector, player, 1, 3, 5)
        );
        token.burn(player, 1, 5);
    }

    function test_burnBatch() public {
        vm.startPrank(gameEngine);
        token.mint(player, 1, 10);
        token.mint(player, 2, 5);

        uint256[] memory types   = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        types[0] = 1; amounts[0] = 3;
        types[1] = 2; amounts[1] = 2;
        token.burnBatch(player, types, amounts);
        vm.stopPrank();

        assertEq(token.balanceOf(player, 1), 7);
        assertEq(token.balanceOf(player, 2), 3);
    }

    // ── Unit Upgrades ─────────────────────────────────────────────────────────

    function test_upgradeInfantryToCavalry() public {
        vm.startPrank(gameEngine);
        token.mint(player, 1, 9); // enough for 3 cavalry
        token.upgradeUnits(player, 2, 3);
        vm.stopPrank();

        assertEq(token.balanceOf(player, 1), 0); // 9 Infantry burned
        assertEq(token.balanceOf(player, 2), 3); // 3 Cavalry minted
    }

    function test_upgradeInfantryToArtillery() public {
        vm.startPrank(gameEngine);
        token.mint(player, 1, 10);
        token.upgradeUnits(player, 3, 2); // 2 Artillery = 10 Infantry
        vm.stopPrank();

        assertEq(token.balanceOf(player, 1), 0);
        assertEq(token.balanceOf(player, 3), 2);
    }

    function test_upgradeInfantryToGeneral() public {
        vm.startPrank(gameEngine);
        token.mint(player, 1, 10);
        token.upgradeUnits(player, 4, 1);
        vm.stopPrank();

        assertEq(token.balanceOf(player, 1), 0);
        assertEq(token.balanceOf(player, 4), 1);
    }

    function test_upgradeRevertsOnInsufficientInfantry() public {
        vm.startPrank(gameEngine);
        token.mint(player, 1, 2); // need 3 for 1 cavalry
        vm.expectRevert(
            abi.encodeWithSelector(IArmyToken.ArmyToken__InsufficientBalance.selector, player, 1, 2, 3)
        );
        token.upgradeUnits(player, 2, 1);
        vm.stopPrank();
    }

    function test_upgradeRevertsOnInvalidTarget() public {
        vm.startPrank(gameEngine);
        token.mint(player, 1, 10);
        vm.expectRevert(abi.encodeWithSelector(IArmyToken.ArmyToken__InvalidUpgradeTarget.selector, 1, 1));
        token.upgradeUnits(player, 1, 1); // can't "upgrade" to Infantry
        vm.stopPrank();
    }

    // ── Soulbound ─────────────────────────────────────────────────────────────

    function test_transferReverts() public {
        vm.prank(gameEngine);
        token.mint(player, 1, 5);

        vm.prank(player);
        vm.expectRevert(IArmyToken.ArmyToken__Soulbound.selector);
        token.safeTransferFrom(player, other, 1, 5, "");
    }

    function test_batchTransferReverts() public {
        vm.prank(gameEngine);
        token.mint(player, 1, 5);

        uint256[] memory ids    = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        ids[0] = 1; amounts[0] = 5;

        vm.prank(player);
        vm.expectRevert(IArmyToken.ArmyToken__Soulbound.selector);
        token.safeBatchTransferFrom(player, other, ids, amounts, "");
    }

    // ── Total Strength ────────────────────────────────────────────────────────

    function test_totalStrength() public {
        vm.startPrank(gameEngine);
        token.mint(player, 1, 3);  // 3 × 1  = 3
        token.mint(player, 2, 2);  // 2 × 3  = 6
        token.mint(player, 3, 1);  // 1 × 5  = 5
        token.mint(player, 4, 1);  // 1 × 10 = 10
        vm.stopPrank();

        assertEq(token.totalStrength(player), 24);
    }

    // ── Fuzz ─────────────────────────────────────────────────────────────────

    function testFuzz_mintAndBurnNeverUnderflows(uint256 mintAmount, uint256 burnAmount) public {
        mintAmount = bound(mintAmount, 1, 1_000_000);
        burnAmount = bound(burnAmount, 1, mintAmount);

        vm.startPrank(gameEngine);
        token.mint(player, 1, mintAmount);
        token.burn(player, 1, burnAmount);
        vm.stopPrank();

        assertEq(token.balanceOf(player, 1), mintAmount - burnAmount);
    }

    function testFuzz_upgradeConsumesExactInfantry(uint256 upgradeCount) public {
        upgradeCount = bound(upgradeCount, 1, 100);
        uint256 needed = upgradeCount * 3; // Cavalry costs 3 each

        vm.startPrank(gameEngine);
        token.mint(player, 1, needed);
        token.upgradeUnits(player, 2, upgradeCount);
        vm.stopPrank();

        assertEq(token.balanceOf(player, 1), 0);
        assertEq(token.balanceOf(player, 2), upgradeCount);
    }
}
