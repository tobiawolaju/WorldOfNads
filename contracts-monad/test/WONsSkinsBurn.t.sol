// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {WONsSkins} from "../src/WONsSkins.sol";

/// The store advertises "burn 2 commons for a rare". This proves the contract
/// actually does it, since `burnSkins` alone destroyed the tokens for nothing.
contract WONsSkinsBurnTest is Test {
    WONsSkins skins;
    address owner = makeAddr("owner");
    address player = makeAddr("player");

    function setUp() public {
        vm.prank(owner);
        skins = new WONsSkins(owner, "", address(0));

        vm.startPrank(owner);
        skins.createSkin(100, 0, 0, WONsSkins.Tier.Common, "common");
        skins.createSkin(10, 5 ether, 0, WONsSkins.Tier.Rare, "rare");
        vm.stopPrank();

        vm.deal(player, 100 ether);
    }

    function test_BurningTwoCommonsMintsARare() public {
        vm.startPrank(player);
        skins.mintSkin(1, 2);
        assertEq(skins.balanceOf(player, 1), 2, "two commons minted");

        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 1;
        skins.burnForRare(ids);

        assertEq(skins.balanceOf(player, 1), 0, "commons burned");
        assertEq(skins.balanceOf(player, 2), 1, "rare minted");
        vm.stopPrank();
    }

    function test_BurningRequiresExactlyTheBurnRate() public {
        vm.startPrank(player);
        skins.mintSkin(1, 2);

        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;

        vm.expectRevert(WONsSkins.InsufficientBurnQuantity.selector);
        skins.burnForRare(ids);
        vm.stopPrank();
    }

    function test_OnlyCommonsCanBeBurnedForARare() public {
        vm.startPrank(player);
        skins.mintSkin{value: 10 ether}(2, 2); // two rares

        uint256[] memory ids = new uint256[](2);
        ids[0] = 2;
        ids[1] = 2;

        vm.expectRevert(WONsSkins.BurnNotAllowed.selector);
        skins.burnForRare(ids);
        vm.stopPrank();
    }

    function test_BurningWithoutARareInSupplyReverts() public {
        vm.prank(owner);
        WONsSkins commonsOnly = new WONsSkins(owner, "", address(0));

        vm.startPrank(owner);
        commonsOnly.createSkin(100, 0, 0, WONsSkins.Tier.Common, "common");
        vm.stopPrank();

        vm.startPrank(player);
        commonsOnly.mintSkin(1, 2);

        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 1;

        vm.expectRevert(WONsSkins.SupplyExhausted.selector);
        commonsOnly.burnForRare(ids);
        vm.stopPrank();
    }

    function test_BurningMoreThanYouOwnReverts() public {
        vm.startPrank(player);
        skins.mintSkin(1, 1);

        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 1;

        vm.expectRevert();
        skins.burnForRare(ids);
        vm.stopPrank();
    }
}
