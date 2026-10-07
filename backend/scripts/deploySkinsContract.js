// Deploy a fresh WONsSkins ERC1155 so numeric skin ids can start at 1 and line
// up with the combo index (combo n -> ids 2n+1 / 2n+2).
//
//   node scripts/deploySkinsContract.js            # dry-run: show plan/balance
//   node scripts/deploySkinsContract.js --broadcast
//
// Owner defaults to the signer (TRUSTED_AUTHORITY_PRIVATE_KEY); xpToken is
// XP_TOKEN_ADDRESS so the level gate keeps working. Uses the compiled artifact
// in contracts-monad/out, so run `forge build` there first if it is missing.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import * as dotenv from "dotenv";
dotenv.config();

import { ethers } from "ethers";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ARTIFACT = join(__dirname, "..", "..", "contracts-monad", "out", "WONsSkins.sol", "WONsSkins.json");

async function main() {
  const broadcast = process.argv.includes("--broadcast");

  const artifact = JSON.parse(readFileSync(ARTIFACT, "utf8"));
  if (!artifact?.bytecode?.object || artifact.bytecode.object === "0x") {
    throw new Error(`No bytecode in ${ARTIFACT} — run 'forge build' in contracts-monad/ first`);
  }

  const provider = new ethers.JsonRpcProvider(process.env.MN_RPC_URL);
  const wallet = new ethers.Wallet(process.env.TRUSTED_AUTHORITY_PRIVATE_KEY, provider);
  const owner = process.env.SKINS_OWNER || wallet.address;
  const xpToken = process.env.XP_TOKEN_ADDRESS;
  if (!xpToken) throw new Error("XP_TOKEN_ADDRESS is not set");

  const balance = await provider.getBalance(wallet.address);
  console.log(`RPC      : ${process.env.MN_RPC_URL}`);
  console.log(`Signer   : ${wallet.address}`);
  console.log(`Balance  : ${ethers.formatEther(balance)} MON`);
  console.log(`Owner    : ${owner}`);
  console.log(`XP token : ${xpToken}`);
  console.log(`MODE     : ${broadcast ? "BROADCAST" : "dry-run (pass --broadcast to deploy)"}\n`);

  if (!broadcast) {
    console.log("Would deploy WONsSkins(initialOwner, \"\", xpToken).");
    process.exit(0);
  }

  const factory = new ethers.ContractFactory(artifact.abi, artifact.bytecode.object, wallet);
  const contract = await factory.deploy(owner, "", xpToken);
  console.log(`Deploy tx: ${contract.deploymentTransaction()?.hash}`);
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  const nextSkinId = await contract.nextSkinId();
  const onchainOwner = await contract.owner();

  console.log("\n=== NEW WONsSkins ===");
  console.log(`ADDRESS   : ${address}`);
  console.log(`owner()   : ${onchainOwner}`);
  console.log(`nextSkinId: ${nextSkinId}`);
  console.log("\nSet this address as:");
  console.log("  backend / Render : SKINS_ADDRESS");
  console.log("  frontend / Vercel: VITE_SKINS_CONTRACT_ADDRESS   (rebuild required)");
  process.exit(0);
}

main().catch((err) => {
  console.error("deploySkinsContract failed:", err);
  process.exit(1);
});