// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/WONsXP.sol";
import "../src/WONsLootBox.sol";
import "../src/WONsMatchEngine.sol";
import "../src/WONsSkins.sol";

/**
 * Redeploys only the escrow pair (LootBox + MatchEngine) and points it at the
 * already-deployed XP and Skins tokens.
 *
 * The first deployment (Deploy.s.sol) also created XP and Skins. Those hold
 * live state (player XP balances, 22 skins) that must survive a settlement fix,
 * so this script reuses them instead of minting a fresh, empty set.
 *
 * The old engine stays on-chain so its unsettled matches can still be closed
 * out; the app is pointed at the addresses printed here.
 *
 *   forge script DeploymentScripts/DeployV2.s.sol:DeployV2 \
 *     --rpc-url https://testnet-rpc.monad.xyz --broadcast
 */
contract DeployV2 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("MN_PRIVATE_KEY");
        address initialOwner = vm.envAddress("INITIAL_OWNER");
        address trustedAuthority = vm.envAddress("INITIAL_TRUSTED_AUTHORITY");
        address mainWallet = vm.envAddress("MAIN_WALLET_ADDRESS");
        address xpAddress = vm.envAddress("XP_ADDRESS");
        address skinsAddress = vm.envAddress("SKINS_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // 1. LootBox first (the engine needs its address), with the owner as a
        //    temporary engine until the real one exists.
        WONsLootBox lootBox = new WONsLootBox(initialOwner, initialOwner, trustedAuthority);
        console.log("WONsLootBox (V2) deployed at:", address(lootBox));

        // 2. Engine wired to the existing XP + Skins and the new LootBox.
        WONsMatchEngine matchEngine = new WONsMatchEngine(
            initialOwner,
            trustedAuthority,
            address(lootBox),
            xpAddress,
            mainWallet
        );
        console.log("WONsMatchEngine (V2) deployed at:", address(matchEngine));

        // 3. Only the new engine may fund/settle/drain pools.
        lootBox.setMatchEngine(address(matchEngine));

        // 4. Both the engine and the server may mint XP.
        WONsXP xp = WONsXP(xpAddress);
        xp.setMinter(trustedAuthority, true);
        xp.setMinter(address(matchEngine), true);

        vm.stopBroadcast();

        string memory content = string.concat(
            "WONsXP: ", vm.toString(xpAddress), "\n",
            "WONsLootBox: ", vm.toString(address(lootBox)), "\n",
            "WONsMatchEngine: ", vm.toString(address(matchEngine)), "\n",
            "WONsSkins: ", vm.toString(skinsAddress), "\n",
            "Owner: ", vm.toString(initialOwner), "\n",
            "TrustedAuthority (Server): ", vm.toString(trustedAuthority), "\n",
            "MainWallet: ", vm.toString(mainWallet), "\n",
            "Timestamp: ", vm.toString(block.timestamp)
        );
        vm.writeFile("DeploymentScripts/latest_deployment.txt", content);
        console.log("Deployment info saved to DeploymentScripts/latest_deployment.txt");
    }
}
