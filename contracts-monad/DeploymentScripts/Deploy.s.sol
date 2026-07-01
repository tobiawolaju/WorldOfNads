// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/WONsXP.sol";
import "../src/WONsLootBox.sol";
import "../src/WONsMatchEngine.sol";
import "../src/WONsSkins.sol";

contract DeployAll is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("MN_PRIVATE_KEY");
        address initialOwner = vm.envAddress("INITIAL_OWNER");
        address trustedAuthority = vm.envAddress("INITIAL_TRUSTED_AUTHORITY");
        address mainWallet = vm.envAddress("MAIN_WALLET_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy WONsXP (no deps)
        WONsXP xp = new WONsXP(initialOwner);
        console.log("WONsXP deployed at:", address(xp));

        // 2. Deploy WONsLootBox with temp matchEngine = deployer (will update later)
        WONsLootBox lootBox = new WONsLootBox(initialOwner, initialOwner, trustedAuthority);
        console.log("WONsLootBox deployed at:", address(lootBox));

        // 3. Deploy WONsMatchEngine with lootBox + xp + mainWallet addresses
        WONsMatchEngine matchEngine = new WONsMatchEngine(
            initialOwner,
            trustedAuthority,
            address(lootBox),
            address(xp),
            mainWallet
        );
        console.log("WONsMatchEngine deployed at:", address(matchEngine));

        // 4. Set matchEngine in lootBox
        lootBox.setMatchEngine(address(matchEngine));

        // 5. Deploy WONsSkins with XP token
        WONsSkins skins = new WONsSkins(initialOwner, "", address(xp));
        console.log("WONsSkins deployed at:", address(skins));

        // 6. Set server as minter on XP token
        xp.setMinter(trustedAuthority, true);

        vm.stopBroadcast();

        // Save deployment addresses
        string memory content = string.concat(
            "WONsXP: ", vm.toString(address(xp)), "\n",
            "WONsLootBox: ", vm.toString(address(lootBox)), "\n",
            "WONsMatchEngine: ", vm.toString(address(matchEngine)), "\n",
            "WONsSkins: ", vm.toString(address(skins)), "\n",
            "Owner: ", vm.toString(initialOwner), "\n",
            "TrustedAuthority (Server): ", vm.toString(trustedAuthority), "\n",
            "MainWallet: ", vm.toString(mainWallet), "\n",
            "Timestamp: ", vm.toString(block.timestamp)
        );
        vm.writeFile("DeploymentScripts/latest_deployment.txt", content);
        console.log("Deployment info saved to DeploymentScripts/latest_deployment.txt");
    }
}

// forge script DeploymentScripts/Deploy.s.sol:DeployAll --rpc-url https://testnet-rpc.monad.xyz --broadcast
