// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/WONSponsorArenaEscrow.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract WONSponsorArenaEscrowTest is Script {
    function run() external {
        // This is a test/interaction script
        uint256 deployerPrivateKey = vm.envUint("MN_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        address contractAddr = address(0);
        WONSponsorArenaEscrow escrow = WONSponsorArenaEscrow(contractAddr);

        vm.startBroadcast(deployerPrivateKey);

        // Example: Create a match
        bytes32 matchId = keccak256(abi.encodePacked("test-match", block.timestamp));
        address prizeToken = address(0);
        uint256 prizeAmount = 1 ether;
        
        // Mock token approval if needed
        // IERC20(prizeToken).approve(address(escrow), prizeAmount);

        /*
        escrow.createSponsoredMatch(
            matchId,
            prizeToken,
            prizeAmount,
            10, // expected participants
            "ipfs://winner",
            "ipfs://participant",
            "ipfs://match-metadata"
        );
        */

        vm.stopBroadcast();
    }
}
