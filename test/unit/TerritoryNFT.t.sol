// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {TerritoryNFT} from "../../src/tokens/TerritoryNFT.sol";
import {ITerritoryNFT} from "../../src/interfaces/ITerritoryNFT.sol";

contract TerritoryNFTTest is Test {
    TerritoryNFT public nft;

    address public admin      = makeAddr("admin");
    address public minter     = makeAddr("minter");
    address public gameEngine = makeAddr("gameEngine");
    address public player1    = makeAddr("player1");
    address public player2    = makeAddr("player2");

    function setUp() public {
        vm.startPrank(admin);
        nft = new TerritoryNFT(admin);
        nft.grantRole(nft.MINTER_ROLE(), minter);
        nft.grantRole(nft.GAME_ENGINE_ROLE(), gameEngine);
        nft.initializeMap();
        vm.stopPrank();
    }

    // ── Map Initialization ────────────────────────────────────────────────────

    function test_mapInitialized() public view {
        assertTrue(nft.mapInitialized());
    }

    function test_continentMetaSet() public view {
        ITerritoryNFT.ContinentMeta memory northlands = nft.getContinentMeta(1);
        assertEq(northlands.bonusArmies, 5);
        assertEq(northlands.territoryIds.length, 9);
    }

    function test_allContinentBonuses() public view {
        uint8[6] memory expectedBonuses = [5, 3, 2, 7, 2, 2];
        for (uint8 c = 1; c <= 6; ++c) {
            assertEq(nft.getContinentMeta(c).bonusArmies, expectedBonuses[c - 1]);
        }
    }

    function test_adjacencySymmetric() public view {
        // Territory 1 is adjacent to 2 and 4
        assertTrue(nft.isAdjacent(1, 2));
        assertTrue(nft.isAdjacent(2, 1));
        assertTrue(nft.isAdjacent(1, 4));
        assertTrue(nft.isAdjacent(4, 1));
    }

    function test_nonAdjacentReturnsFalse() public view {
        assertFalse(nft.isAdjacent(1, 42));
        assertFalse(nft.isAdjacent(10, 34));
    }

    function test_navalLinkLeafendToDreadhollow() public view {
        uint256[] memory naval38 = nft.navalTargetsOf(38);
        assertEq(naval38.length, 1);
        assertEq(naval38[0], 42);

        uint256[] memory naval42 = nft.navalTargetsOf(42);
        assertEq(naval42.length, 1);
        assertEq(naval42[0], 38);
    }

    function test_crossContinentAdjacency_northlands_to_barrens() public view {
        // Territory 7 (Northlands) → Territory 23 (Barrens)
        assertTrue(nft.isAdjacent(7, 23));
    }

    function test_totalTerritoriesIs42() public pure {
        assertEq(TerritoryNFT(address(0)).TOTAL_TERRITORIES(), 42);
    }

    // ── Minting ───────────────────────────────────────────────────────────────

    function test_mintByMinter() public {
        vm.prank(minter);
        nft.mint(player1, 1);
        assertEq(nft.ownerOf(1), player1);
        assertEq(nft.territoriesOwnedBy(player1), 1);
    }

    function test_mintRevertsIfNotMinter() public {
        vm.expectRevert();
        vm.prank(player1);
        nft.mint(player1, 1);
    }

    function test_mintRevertsOnInvalidId() public {
        vm.startPrank(minter);
        vm.expectRevert(abi.encodeWithSelector(ITerritoryNFT.TerritoryNFT__InvalidTerritoryId.selector, 0));
        nft.mint(player1, 0);

        vm.expectRevert(abi.encodeWithSelector(ITerritoryNFT.TerritoryNFT__InvalidTerritoryId.selector, 43));
        nft.mint(player1, 43);
        vm.stopPrank();
    }

    function test_mintRevertsOnDuplicate() public {
        vm.startPrank(minter);
        nft.mint(player1, 1);
        vm.expectRevert(abi.encodeWithSelector(ITerritoryNFT.TerritoryNFT__AlreadyMinted.selector, 1));
        nft.mint(player2, 1);
        vm.stopPrank();
    }

    function test_walletCapEnforced() public {
        vm.startPrank(minter);
        for (uint256 i = 1; i <= 12; ++i) {
            nft.mint(player1, i);
        }
        // 13th mint should revert
        vm.expectRevert(
            abi.encodeWithSelector(ITerritoryNFT.TerritoryNFT__MaxTerritoriesExceeded.selector, player1, 12)
        );
        nft.mint(player1, 13);
        vm.stopPrank();
    }

    // ── Season Lock ───────────────────────────────────────────────────────────

    function test_lockForSeason() public {
        vm.prank(gameEngine);
        nft.lockForSeason(1);
        assertTrue(nft.isLocked());
    }

    function test_transferRevertsWhenLocked() public {
        vm.prank(minter);
        nft.mint(player1, 1);

        vm.prank(gameEngine);
        nft.lockForSeason(1);

        vm.prank(player1);
        vm.expectRevert(abi.encodeWithSelector(ITerritoryNFT.TerritoryNFT__TransferLocked.selector, 1));
        nft.transferFrom(player1, player2, 1);
    }

    function test_conquestTransferBypassesLock() public {
        vm.prank(minter);
        nft.mint(player1, 1);

        vm.prank(gameEngine);
        nft.lockForSeason(1);

        vm.prank(gameEngine);
        nft.conquestTransfer(player1, player2, 1);

        assertEq(nft.ownerOf(1), player2);
        assertEq(nft.territoriesOwnedBy(player1), 0);
        assertEq(nft.territoriesOwnedBy(player2), 1);
    }

    function test_conquestTransferRevertsIfNotGameEngine() public {
        vm.prank(minter);
        nft.mint(player1, 1);

        vm.prank(gameEngine);
        nft.lockForSeason(1);

        vm.prank(player1);
        vm.expectRevert();
        nft.conquestTransfer(player1, player2, 1);
    }

    // ── Unlock & Trading Window ───────────────────────────────────────────────

    function test_unlockAfterSeason() public {
        vm.prank(minter);
        nft.mint(player1, 1);

        vm.prank(gameEngine);
        nft.lockForSeason(1);

        vm.prank(gameEngine);
        nft.unlockAfterSeason(1);

        assertFalse(nft.isLocked());
        assertTrue(nft.tradingWindowEndsAt() > block.timestamp);
    }

    function test_transferAllowedDuringTradingWindow() public {
        vm.prank(minter);
        nft.mint(player1, 1);

        vm.prank(gameEngine);
        nft.lockForSeason(1);

        vm.prank(gameEngine);
        nft.unlockAfterSeason(1);

        vm.prank(player1);
        nft.transferFrom(player1, player2, 1);
        assertEq(nft.ownerOf(1), player2);
    }

    function test_transferRevertsAfterTradingWindowExpires() public {
        vm.prank(minter);
        nft.mint(player1, 1);

        vm.prank(gameEngine);
        nft.lockForSeason(1);
        vm.prank(gameEngine);
        nft.unlockAfterSeason(1);

        // Advance past 14-day trading window
        vm.warp(block.timestamp + 15 days);

        vm.prank(player1);
        vm.expectRevert(ITerritoryNFT.TerritoryNFT__TradingWindowExpired.selector);
        nft.transferFrom(player1, player2, 1);
    }

    // ── Continent Control ─────────────────────────────────────────────────────

    function test_controlsContinent_northlands() public {
        vm.startPrank(minter);
        for (uint256 i = 1; i <= 9; ++i) nft.mint(player1, i);
        vm.stopPrank();

        assertTrue(nft.controlsContinent(player1, 1));
        assertFalse(nft.controlsContinent(player2, 1));
    }

    function test_controlsContinent_falseIfMissOne() public {
        vm.startPrank(minter);
        for (uint256 i = 1; i <= 8; ++i) nft.mint(player1, i); // miss territory 9
        nft.mint(player2, 9);
        vm.stopPrank();

        assertFalse(nft.controlsContinent(player1, 1));
    }

    // ── Double-init guard ────────────────────────────────────────────────────

    function test_initializeMapRevertsIfCalledTwice() public {
        vm.prank(admin);
        vm.expectRevert();
        nft.initializeMap();
    }

    // ── Burn ─────────────────────────────────────────────────────────────────

    function test_burnByMinter() public {
        vm.prank(minter);
        nft.mint(player1, 5);
        vm.prank(minter);
        nft.burn(5);
        vm.expectRevert();
        nft.ownerOf(5);
    }
}
