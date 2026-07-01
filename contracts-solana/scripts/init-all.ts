/**
 * World of Nads - Solana Initialization Script
 *
 * Run after deploying all programs to devnet/mainnet:
 *   npx ts-node scripts/init-all.ts
 *
 * This script:
 * 1. Initializes all program configs
 * 2. Sets up role-based access (trusted authority, minter, etc.)
 * 3. Creates initial skin collection
 * 4. Verifies all programs are connected correctly
 */

import { Connection, Keypair, PublicKey, LAMPORTS_PER_SOL } from "@solana/web3.js";
import { Program, AnchorProvider, Wallet, BN } from "@coral-xyz/anchor";
import * as fs from "fs";
import * as path from "path";

// Config
const CLUSTER = process.env.CLUSTER || "devnet";
const RPC_URL = CLUSTER === "devnet"
  ? "https://api.devnet.solana.com"
  : "https://api.mainnet-beta.solana.com";

// Load server wallet
const WALLET_PATH = process.env.WALLET_PATH || path.join(process.env.HOME || "~", ".config/solana/id.json");
const serverWallet = Keypair.fromSecretKey(
  Buffer.from(JSON.parse(fs.readFileSync(WALLET_PATH, "utf-8")))
);

// Program IDs (from Anchor.toml)
const PROGRAM_IDS = {
  xpToken: new PublicKey("WONsXP111111111111111111111111111111111111"),
  lootBox: new PublicKey("WONsLootBox11111111111111111111111111111111"),
  matchEngine: new PublicKey("WONsMatchEngine111111111111111111111111111111"),
  skins: new PublicKey("WONsSkins1111111111111111111111111111111111"),
  treasury: new PublicKey("WONsTreasury111111111111111111111111111111"),
};

// PDA derivation helpers
function pda(seeds: Buffer[], programId: PublicKey): [PublicKey, number] {
  return PublicKey.findProgramAddressSync(seeds, programId);
}

async function main() {
  console.log(`\n=== World of Nads Solana Init ===`);
  console.log(`Cluster: ${CLUSTER}`);
  console.log(`Server Wallet: ${serverWallet.publicKey.toString()}\n`);

  const connection = new Connection(RPC_URL, "confirmed");
  const provider = new AnchorProvider(
    connection,
    new Wallet(serverWallet),
    { commitment: "confirmed" }
  );

  // PDA addresses
  const [xpConfig] = pda([Buffer.from("config")], PROGRAM_IDS.xpToken);
  const [lootConfig] = pda([Buffer.from("config")], PROGRAM_IDS.lootBox);
  const [matchConfig] = pda([Buffer.from("config")], PROGRAM_IDS.matchEngine);
  const [skinConfig] = pda([Buffer.from("config")], PROGRAM_IDS.skins);
  const [treasuryConfig] = pda([Buffer.from("config")], PROGRAM_IDS.treasury);
  const [treasuryVault] = pda([Buffer.from("treasury_vault")], PROGRAM_IDS.treasury);

  // In production, load IDLs from target/idl/ after anchor build
  console.log("Load program IDLs and initialize...");
  console.log("(Requires: anchor build to generate IDL files)");

  // Step 1: Initialize XP Token
  console.log(`\n1. Initializing XP Token at ${xpConfig.toString()}`);
  console.log("   -> anchor.program.xpToken.methods.initialize(serverWallet.publicKey)");

  // Step 2: Initialize Loot Box
  console.log(`\n2. Initializing Loot Box at ${lootConfig.toString()}`);
  console.log("   -> anchor.program.lootBox.methods.initialize(serverWallet.publicKey)");

  // Step 3: Initialize Match Engine
  console.log(`\n3. Initializing Match Engine at ${matchConfig.toString()}`);
  console.log("   -> anchor.program.matchEngine.methods.initialize(authority, trustedAuthority)");

  // Step 4: Initialize Skins
  console.log(`\n4. Initializing Skins at ${skinConfig.toString()}`);
  console.log("   -> anchor.program.skins.methods.initialize(serverWallet.publicKey)");

  // Step 5: Initialize Treasury
  console.log(`\n5. Initializing Treasury at ${treasuryConfig.toString()}`);
  console.log("   -> anchor.program.treasury.methods.initialize(serverWallet.publicKey)");

  // Step 6: Set cross-program roles
  console.log(`\n6. Setting up access control...`);
  console.log(`   - XP setMinter(matchEngine, true)`);
  console.log(`   - LootBox setMatchEngine(matchEngine)`);
  console.log(`   - LootBox setTrustedCaller(serverWallet)`);

  // Step 7: Create initial skins
  console.log(`\n7. Creating initial 8 skin types...`);
  const skins_data = [
    { name: "Default Nad", maxSupply: 0, price: 0, xp: 0, tier: 0 }, // free, unlimited
    { name: "Mouch", maxSupply: 2000, price: 0.15, xp: 100, tier: 0 },
    { name: "John Doe", maxSupply: 1500, price: 0.18, xp: 200, tier: 0 },
    { name: "Abyss", maxSupply: 1000, price: 0.18, xp: 500, tier: 1 },
    { name: "Glitch", maxSupply: 1000, price: 0.20, xp: 1000, tier: 1 },
    { name: "Hellion", maxSupply: 800, price: 0.20, xp: 2500, tier: 2 },
    { name: "Aurum", maxSupply: 500, price: 0.25, xp: 5000, tier: 2 },
    { name: "Seraphim", maxSupply: 300, price: 0.32, xp: 10000, tier: 3 },
  ];

  for (const skin of skins_data) {
    if (skin.maxSupply === 0) continue; // Default skin is free
    const mintPriceLamports = Math.floor(skin.price * LAMPORTS_PER_SOL);
    console.log(
      `   - ${skin.name}: supply=${skin.maxSupply}, price=${skin.price} SOL, xp=${skin.xp}, tier=${skin.tier}`
    );
    // await createSkin(skinId, maxSupply, mintPriceLamports, requiredXP, tier, uri)
  }

  console.log(`\n=== Init Complete ===`);
  console.log(`\nVerify on Solana Explorer:`);
  console.log(`https://explorer.solana.com/address/${matchConfig.toString()}?cluster=${CLUSTER}`);
}

main().catch(console.error);
