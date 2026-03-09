// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TerritoryCard} from "../../src/tokens/TerritoryCard.sol";
import {ITerritoryCard} from "../../src/interfaces/ITerritoryCard.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract TerritoryCardTest is Test {
    TerritoryCard public card;
    ERC20Mock     public conquest;

    address public admin      = makeAddr("admin");
    address public gameEngine = makeAddr("gameEngine");
    address public player     = makeAddr("player");

    uint256 public constant REDEMPTION_RATE = 10e18; // 10 CONQUEST per card

    function setUp() public {
        vm.startPrank(admin);
        conquest = new ERC20Mock();
        conquest.mint(admin, 1_000_000e18);

        card = new TerritoryCard(
            admin,
            "https://base-conquest.io/card/{id}.json",
            address(conquest),
            REDEMPTION_RATE
        );
        card.grantRole(card.GAME_ENGINE_ROLE(), gameEngine);

        // Fund card contract with CONQUEST for end-of-season redemptions
        conquest.transfer(address(card), 100_000e18);
        vm.stopPrank();
    }

    // ── Constants ─────────────────────────────────────────────────────────────

    function test_cardTypeConstants() public view {
        assertEq(card.INFANTRY_CARD(),  1);
        assertEq(card.CAVALRY_CARD(),   2);
        assertEq(card.ARTILLERY_CARD(), 3);
    }

    // ── Drawing ───────────────────────────────────────────────────────────────

    function test_drawByGameEngine() public {
        vm.prank(gameEngine);
        card.draw(player, 1, 5);
        assertEq(card.cardBalance(player, 1), 1);
    }

    function test_drawAllTypes() public {
        vm.startPrank(gameEngine);
        card.draw(player, 1, 1);
        card.draw(player, 2, 2);
        card.draw(player, 3, 3);
        vm.stopPrank();

        (uint256 inf, uint256 cav, uint256 art) = card.allCardBalances(player);
        assertEq(inf, 1);
        assertEq(cav, 1);
        assertEq(art, 1);
    }

    function test_drawRevertsIfNotGameEngine() public {
        vm.prank(player);
        vm.expectRevert();
        card.draw(player, 1, 1);
    }

    function test_drawRevertsOnInvalidCardType() public {
        vm.prank(gameEngine);
        vm.expectRevert(abi.encodeWithSelector(ITerritoryCard.TerritoryCard__InvalidCardType.selector, 4));
        card.draw(player, 4, 1);
    }

    // ── Set Validation ────────────────────────────────────────────────────────

    function test_isValidSet_threeInfantry() public view {
        uint8[3] memory set = [1, 1, 1];
        assertTrue(card.isValidSet(set));
    }

    function test_isValidSet_threeCavalry() public view {
        uint8[3] memory set = [2, 2, 2];
        assertTrue(card.isValidSet(set));
    }

    function test_isValidSet_threeArtillery() public view {
        uint8[3] memory set = [3, 3, 3];
        assertTrue(card.isValidSet(set));
    }

    function test_isValidSet_oneOfEach() public view {
        uint8[3] memory set = [1, 2, 3];
        assertTrue(card.isValidSet(set));
        uint8[3] memory set2 = [3, 1, 2];
        assertTrue(card.isValidSet(set2));
    }

    function test_isValidSet_invalidMix() public view {
        uint8[3] memory set = [1, 1, 2]; // not valid
        assertFalse(card.isValidSet(set));
    }

    // ── Burning Sets ─────────────────────────────────────────────────────────

    function test_burnSet_threeInfantry_firstSet() public {
        vm.startPrank(gameEngine);
        card.draw(player, 1, 1);
        card.draw(player, 1, 2);
        card.draw(player, 1, 3);

        uint8[3] memory set = [1, 1, 1];
        uint256 bonus = card.burnSet(player, set);
        vm.stopPrank();

        // First set: Infantry base (4) + 0 escalation = 4
        assertEq(bonus, 4);
        assertEq(card.cardBalance(player, 1), 0);
        assertEq(card.setsRedeemedCount(), 1);
    }

    function test_burnSet_threeInfantry_secondSet_escalated() public {
        vm.startPrank(gameEngine);
        // Draw 6 Infantry cards
        for (uint256 i; i < 6; ++i) card.draw(player, 1, 1);

        uint8[3] memory set = [1, 1, 1];
        card.burnSet(player, set); // set 1 → 4 armies
        uint256 bonus2 = card.burnSet(player, set); // set 2 → 6 armies
        vm.stopPrank();

        assertEq(bonus2, 6); // 4 base + 2 escalation (1 set already redeemed)
    }

    function test_burnSet_mixed_10armies() public {
        vm.startPrank(gameEngine);
        card.draw(player, 1, 1);
        card.draw(player, 2, 2);
        card.draw(player, 3, 3);

        uint8[3] memory set = [1, 2, 3];
        uint256 bonus = card.burnSet(player, set);
        vm.stopPrank();

        assertEq(bonus, 10); // Mixed base, no escalation yet
    }

    function test_burnSetRevertsOnInsufficientCards() public {
        vm.startPrank(gameEngine);
        card.draw(player, 1, 1); // only 1 Infantry card
        card.draw(player, 1, 2);
        // missing 3rd Infantry card

        uint8[3] memory set = [1, 1, 1];
        vm.expectRevert(
            abi.encodeWithSelector(
                ITerritoryCard.TerritoryCard__InsufficientCards.selector, player, 1, 2, 3
            )
        );
        card.burnSet(player, set);
        vm.stopPrank();
    }

    function test_burnSetRevertsOnInvalidSet() public {
        vm.startPrank(gameEngine);
        card.draw(player, 1, 1);
        card.draw(player, 1, 2);
        card.draw(player, 2, 3);

        uint8[3] memory set = [1, 1, 2];
        vm.expectRevert(abi.encodeWithSelector(ITerritoryCard.TerritoryCard__InvalidCardSet.selector, set));
        card.burnSet(player, set);
        vm.stopPrank();
    }

    // ── Escalation Cap ────────────────────────────────────────────────────────

    function test_escalationCaps_at25() public {
        // After 7+ sets redeemed, bonus should be 25
        uint256 preview = card.previewSetBonus(7, _infantrySet());
        assertEq(preview, 25);

        preview = card.previewSetBonus(100, _infantrySet());
        assertEq(preview, 25);
    }

    function test_escalationAt5_returns15() public view {
        uint256 preview = card.previewSetBonus(5, _infantrySet());
        assertEq(preview, 15);
    }

    function test_escalationAt6_returns20() public view {
        uint256 preview = card.previewSetBonus(6, _infantrySet());
        assertEq(preview, 20);
    }

    // ── End-of-Season Redemption ──────────────────────────────────────────────

    function test_redeemForConquestAfterSeason() public {
        vm.prank(gameEngine);
        card.draw(player, 1, 1);

        // End season
        vm.prank(gameEngine);
        card.setSeasonActive(false);

        vm.prank(player);
        card.redeemForConquest(1, 1);

        assertEq(card.cardBalance(player, 1), 0);
        assertEq(conquest.balanceOf(player), REDEMPTION_RATE);
    }

    function test_redeemRevertsIfSeasonActive() public {
        vm.startPrank(gameEngine);
        card.draw(player, 1, 1);
        card.setSeasonActive(true);
        vm.stopPrank();

        vm.prank(player);
        vm.expectRevert(ITerritoryCard.TerritoryCard__SeasonStillActive.selector);
        card.redeemForConquest(1, 1);
    }

    // ── Preview Set Bonus ─────────────────────────────────────────────────────

    function test_previewMatchesBurnResult() public {
        vm.startPrank(gameEngine);
        card.draw(player, 2, 1);
        card.draw(player, 2, 2);
        card.draw(player, 2, 3);
        vm.stopPrank();

        uint8[3] memory set = [2, 2, 2];
        uint256 preview = card.previewSetBonus(0, set);

        vm.prank(gameEngine);
        uint256 actual = card.burnSet(player, set);

        assertEq(preview, actual);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    function _infantrySet() internal pure returns (uint8[3] memory) {
        return [uint8(1), uint8(1), uint8(1)];
    }
}
