// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {WONsMatchEngine} from "../src/WONsMatchEngine.sol";
import {WONsLootBox} from "../src/WONsLootBox.sol";
import {WONsXP} from "../src/WONsXP.sol";

/// Covers the V2 settlement paths: split payouts, expiry refunds and the
/// escrow-safe withdrawal that replaced the balance-draining `withdraw()`.
contract WONsMatchEngineSplitTest is Test {
    WONsMatchEngine matchEngine;
    WONsLootBox lootBox;
    WONsXP xp;

    address owner = makeAddr("owner");
    address trustedAuthority = makeAddr("authority");
    address mainWallet = makeAddr("mainWallet");
    address sponsor = makeAddr("sponsor");
    address holder = makeAddr("holder");
    address leader = makeAddr("leader");
    address thirdPlayer = makeAddr("third");

    bytes32 matchId = keccak256("split-match");

    function setUp() public {
        vm.deal(sponsor, 100 ether);

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

    function _createMatch(uint256 totalPrize, bytes32 id) internal {
        vm.prank(sponsor);
        matchEngine.createSponsoredMatch{value: totalPrize}(
            id,
            address(0),
            totalPrize,
            20,
            uint64(block.timestamp + 1 hours),
            "",
            "",
            ""
        );
    }

    function _twoWinners() internal view returns (address[] memory winners, uint16[] memory shares) {
        winners = new address[](2);
        winners[0] = holder;
        winners[1] = leader;
        shares = new uint16[](2);
        shares[0] = 2000; // 20% to the holder
        shares[1] = 8000; // 80% to the progress leader
    }

    function _participants() internal view returns (address[] memory participants) {
        participants = new address[](3);
        participants[0] = holder;
        participants[1] = leader;
        participants[2] = thirdPlayer;
    }

    function test_SplitPaysEachWinnerTheirShare() public {
        _createMatch(10 ether, matchId);
        vm.warp(block.timestamp + 1 hours + 1);

        (address[] memory winners, uint16[] memory shares) = _twoWinners();
        address[] memory participants = _participants();

        vm.prank(trustedAuthority);
        matchEngine.settleMatchSplit(matchId, winners, shares, participants, thirdPlayer);

        assertEq(holder.balance, 1.44 ether, "holder gets 20% of 7.2");
        assertEq(leader.balance, 5.76 ether, "leader gets 80% of 7.2");
        assertEq(thirdPlayer.balance, 1.8 ether, "lootbox holder gets the pool");
        assertEq(address(matchEngine).balance, 0, "engine keeps nothing");
        assertEq(matchEngine.totalEscrowed(address(0)), 0, "escrow released");
    }

    function test_SplitMintsWinnerAndParticipationTokens() public {
        _createMatch(10 ether, matchId);
        vm.warp(block.timestamp + 1 hours + 1);

        (address[] memory winners, uint16[] memory shares) = _twoWinners();

        vm.prank(trustedAuthority);
        matchEngine.settleMatchSplit(matchId, winners, shares, _participants(), thirdPlayer);

        assertEq(matchEngine.balanceOf(holder, 1), 1, "holder winner NFT");
        assertEq(matchEngine.balanceOf(leader, 1), 1, "leader winner NFT");
        assertEq(matchEngine.balanceOf(thirdPlayer, 2), 1, "participation NFT");
        assertEq(matchEngine.balanceOf(holder, 2), 0, "winners get no participation NFT");
    }

    function test_SplitRejectsSharesThatDoNotAddUp() public {
        _createMatch(10 ether, matchId);
        vm.warp(block.timestamp + 1 hours + 1);

        (address[] memory winners, uint16[] memory shares) = _twoWinners();
        shares[0] = 1999; // 1999 + 8000 = 9999

        vm.prank(trustedAuthority);
        vm.expectRevert(WONsMatchEngine.InvalidShareTotal.selector);
        matchEngine.settleMatchSplit(matchId, winners, shares, _participants(), thirdPlayer);
    }

    function test_SplitRejectsAWinnerWhoIsNotAParticipant() public {
        _createMatch(10 ether, matchId);
        vm.warp(block.timestamp + 1 hours + 1);

        (address[] memory winners, uint16[] memory shares) = _twoWinners();
        address[] memory participants = new address[](2);
        participants[0] = holder;
        participants[1] = thirdPlayer; // leader is missing

        vm.prank(trustedAuthority);
        vm.expectRevert(WONsMatchEngine.InvalidWinner.selector);
        matchEngine.settleMatchSplit(matchId, winners, shares, participants, thirdPlayer);
    }

    function test_SettleBeforeStartTimeReverts() public {
        _createMatch(10 ether, matchId);

        address[] memory participants = new address[](1);
        participants[0] = holder;

        vm.prank(trustedAuthority);
        vm.expectRevert(WONsMatchEngine.MatchNotStarted.selector);
        matchEngine.settleMatch(matchId, holder, participants, holder, 0);
    }

    function test_WithdrawSurplusCannotTouchEscrow() public {
        _createMatch(10 ether, matchId);

        // Someone sends MON straight to the engine: that is a surplus.
        vm.deal(address(this), 1 ether);
        (bool sent, ) = address(matchEngine).call{value: 1 ether}("");
        assertTrue(sent, "top-up sent");

        uint256 ownerBefore = owner.balance;
        vm.prank(owner);
        matchEngine.withdrawSurplus(address(0));

        assertEq(owner.balance - ownerBefore, 1 ether, "only the surplus moves");
        assertEq(address(matchEngine).balance, 7.2 ether, "escrow is untouched");

        vm.prank(owner);
        vm.expectRevert(WONsMatchEngine.NothingToWithdraw.selector);
        matchEngine.withdrawSurplus(address(0));
    }

    function test_RefundExpiredReturnsTheEscrowedPrize() public {
        uint256 sponsorBefore = sponsor.balance;
        _createMatch(10 ether, matchId);

        uint64 deadline = matchEngine.settleDeadlineOf(matchId);
        assertEq(deadline, uint64(block.timestamp + 1 hours) + matchEngine.SETTLE_WINDOW(), "deadline recorded");

        vm.warp(uint256(deadline) + 1);

        matchEngine.refundExpired(matchId);

        // 7.2 winner prize + 1.8 lootbox pool come back; the 10% fee is kept.
        assertEq(sponsor.balance, sponsorBefore - 1 ether, "sponsor gets the escrow back");
        assertEq(address(matchEngine).balance, 0, "engine holds nothing");
        assertEq(address(lootBox).balance, 0, "lootbox holds nothing");
        assertEq(matchEngine.totalEscrowed(address(0)), 0, "escrow released");
        assertEq(lootBox.totalPooled(), 0, "pool released");
    }

    function test_RefundBeforeTheDeadlineReverts() public {
        _createMatch(10 ether, matchId);

        vm.expectRevert(WONsMatchEngine.SettleDeadlineNotReached.selector);
        matchEngine.refundExpired(matchId);
    }

    function test_RefundIsOneShotAndBlocksSettlement() public {
        _createMatch(10 ether, matchId);
        vm.warp(uint256(matchEngine.settleDeadlineOf(matchId)) + 1);
        matchEngine.refundExpired(matchId);

        vm.expectRevert(WONsMatchEngine.MatchAlreadyCancelled.selector);
        matchEngine.refundExpired(matchId);

        address[] memory participants = new address[](1);
        participants[0] = holder;

        vm.prank(trustedAuthority);
        vm.expectRevert(WONsMatchEngine.MatchAlreadyCancelled.selector);
        matchEngine.settleMatch(matchId, holder, participants, holder, 0);
    }

    function test_LootBoxWithdrawSurplusLeavesPoolsAlone() public {
        _createMatch(10 ether, matchId);

        // Extra MON sent to the lootbox is a surplus; the funded pool is not.
        vm.deal(address(this), 1 ether);
        (bool sent, ) = address(lootBox).call{value: 1 ether}("");
        assertTrue(sent, "top-up sent");

        uint256 ownerBefore = owner.balance;
        vm.prank(owner);
        lootBox.withdrawSurplus();

        assertEq(owner.balance - ownerBefore, 1 ether, "only the surplus moves");
        assertEq(lootBox.getPoolValue(matchId), 1.8 ether, "pool is untouched");

        vm.prank(owner);
        vm.expectRevert(WONsLootBox.NothingToWithdraw.selector);
        lootBox.withdrawSurplus();
    }
}
