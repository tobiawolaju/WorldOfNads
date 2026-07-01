// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {WONsMatchEngine} from "../src/WONsMatchEngine.sol";
import {WONsLootBox} from "../src/WONsLootBox.sol";
import {WONsXP} from "../src/WONsXP.sol";

contract WONsMatchEngineTest is Test {
    WONsMatchEngine matchEngine;
    WONsLootBox lootBox;
    WONsXP xp;

    address owner = makeAddr("owner");
    address trustedAuthority = makeAddr("authority");
    address mainWallet = makeAddr("mainWallet");
    address sponsor = makeAddr("sponsor");
    address winner = makeAddr("winner");
    address player2 = makeAddr("player2");

    bytes32 matchId = keccak256("test-match-1");

    function setUp() public {
        vm.deal(sponsor, 100 ether);
        vm.deal(winner, 1 ether);
        vm.deal(player2, 1 ether);

        vm.prank(owner);
        xp = new WONsXP(owner);

        vm.prank(owner);
        lootBox = new WONsLootBox(owner, owner, trustedAuthority);

        vm.prank(owner);
        matchEngine = new WONsMatchEngine(
            owner,
            trustedAuthority,
            address(lootBox),
            address(xp),
            mainWallet
        );

        vm.prank(owner);
        lootBox.setMatchEngine(address(matchEngine));

        vm.prank(owner);
        xp.setMinter(trustedAuthority, true);
    }

    function test_Split_10ToFoundation_80ToWinner_20ToLootBox() public {
        uint256 totalPrize = 10 ether; // 10 MON

        vm.prank(sponsor);
        matchEngine.createSponsoredMatch{value: totalPrize}(
            matchId,
            address(0),
            totalPrize,
            20,
            uint64(block.timestamp + 1 hours),
            "",
            "",
            ""
        );

        // 10% fee to mainWallet
        assertEq(mainWallet.balance, 1 ether, "mainWallet should get 1 MON (10%)");

        // Net = 9 MON
        // Winner should get 80% of net = 7.2 MON
        // Loot box should get 20% of net = 1.8 MON
        WONsMatchEngine.MatchConfig memory cfg = matchEngine.getMatch(matchId);
        assertEq(cfg.winnerPrize, 7.2 ether, "winner should get 7.2 MON");
        assertEq(cfg.lootBoxPool, 1.8 ether, "lootbox should get 1.8 MON");

        // Loot box contract holds the pool
        assertEq(address(lootBox).balance, 1.8 ether, "lootBox contract holds 1.8 MON");
    }

    function test_WinnerGetsFullPrize_NoGasDeduction() public {
        uint256 totalPrize = 10 ether;

        vm.prank(sponsor);
        matchEngine.createSponsoredMatch{value: totalPrize}(
            matchId,
            address(0),
            totalPrize,
            20,
            uint64(block.timestamp + 1 hours),
            "",
            "",
            ""
        );

        uint256 winnerBalanceBefore = winner.balance;

        address[] memory participants = new address[](2);
        participants[0] = winner;
        participants[1] = player2;

        vm.prank(trustedAuthority);
        matchEngine.settleMatch(matchId, winner, participants, player2, 0);

        // Winner gets 7.2 MON (80% of net). player2 gets 1.8 MON as lootBoxFinalHolder
        uint256 winnerPayout = winner.balance - winnerBalanceBefore;
        assertEq(winnerPayout, 7.2 ether, "winner should get exactly 7.2 MON");
        assertEq(player2.balance, 1 ether + 1.8 ether, "lootBoxFinalHolder gets 1.8 MON");
    }

    function test_LootBoxPaysFinalHolder() public {
        uint256 totalPrize = 10 ether;
        address lootBoxFinalHolder = makeAddr("lootBoxHolder");

        vm.prank(sponsor);
        matchEngine.createSponsoredMatch{value: totalPrize}(
            matchId,
            address(0),
            totalPrize,
            20,
            uint64(block.timestamp + 1 hours),
            "",
            "",
            ""
        );

        uint256 holderBalanceBefore = lootBoxFinalHolder.balance;

        address[] memory participants = new address[](2);
        participants[0] = winner;
        participants[1] = player2;

        vm.prank(trustedAuthority);
        matchEngine.settleMatch(matchId, winner, participants, lootBoxFinalHolder, 0);

        // Final holder gets the 1.8 MON loot box pool
        uint256 payout = lootBoxFinalHolder.balance - holderBalanceBefore;
        assertEq(payout, 1.8 ether, "lootbox final holder gets 1.8 MON");
    }

    function test_FullMatchFlow() public {
        uint256 totalPrize = 10 ether;
        uint256 expectedFee = 1 ether;
        uint256 expectedNet = 9 ether;
        uint256 expectedWinnerPrize = 7.2 ether;
        uint256 expectedLootBoxPool = 1.8 ether;

        uint256 mainWalletBefore = mainWallet.balance;

        vm.prank(sponsor);
        matchEngine.createSponsoredMatch{value: totalPrize}(
            matchId,
            address(0),
            totalPrize,
            20,
            uint64(block.timestamp + 1 hours),
            "",
            "",
            ""
        );

        // Verify fee
        assertEq(mainWallet.balance - mainWalletBefore, expectedFee, "fee check");

        // Verify match config
        WONsMatchEngine.MatchConfig memory cfg = matchEngine.getMatch(matchId);
        assertEq(cfg.winnerPrize, expectedWinnerPrize, "winner prize check");
        assertEq(cfg.lootBoxPool, expectedLootBoxPool, "loot box pool check");

        // Settle
        address[] memory participants = new address[](3);
        participants[0] = winner;
        participants[1] = player2;
        address player3 = makeAddr("player3");
        participants[2] = player3;

        uint256 winnerBefore = winner.balance;

        vm.prank(trustedAuthority);
        matchEngine.settleMatch(matchId, winner, participants, player3, 0);

        // Winner gets full prize
        assertEq(winner.balance - winnerBefore, expectedWinnerPrize, "winner paid in full");
        // Player 3 (lootBoxFinalHolder) gets loot box pool
        assertEq(player3.balance, expectedLootBoxPool, "final holder paid");

        // Check NFTs minted (nextTokenId starts at 1, incremented by 2 for match)
        // winnerTokenId = 1, participationTokenId = 2
        assertEq(matchEngine.balanceOf(winner, 1), 1, "winner NFT minted");
        assertEq(matchEngine.balanceOf(winner, 2), 0, "winner not in participation NFT");
        assertEq(matchEngine.balanceOf(player2, 2), 1, "player2 participation NFT");
        assertEq(matchEngine.balanceOf(player3, 2), 1, "player3 participation NFT");
    }
}
