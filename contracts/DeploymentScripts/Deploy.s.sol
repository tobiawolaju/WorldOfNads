// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/WONSponsorArenaEscrow.sol";

contract DeployWONSponsorArenaEscrow is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("MN_PRIVATE_KEY");
        address initialOwner = vm.envAddress("INITIAL_OWNER");
        address trustedAuthority = vm.envAddress("INITIAL_TRUSTED_AUTHORITY");

        vm.startBroadcast(deployerPrivateKey);

        WONSponsorArenaEscrow escrow = new WONSponsorArenaEscrow(initialOwner, trustedAuthority);

        vm.stopBroadcast();

        console.log("Contract deployed at:", address(escrow));

        // Write the address to a file in DeploymentScripts
        string memory path = "DeploymentScripts/latest_deployment.txt";
        string memory content = string.concat("Contract Address: ", vm.toString(address(escrow)), "\nTimestamp: ", vm.toString(block.timestamp));
        vm.writeFile(path, content);
        
        console.log("Deployment info saved to:", path);
    }
}
