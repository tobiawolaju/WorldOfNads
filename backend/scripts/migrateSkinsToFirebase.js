import { ethers } from "ethers";
import * as dotenv from 'dotenv';
dotenv.config();

import { initializeApp } from "firebase/app";
import { getDatabase, ref, update } from "firebase/database";

const firebaseConfig = {
  apiKey: "AIzaSyBNFaveUoWNE4bBTNBgCnK63Bp25BFr5gs",
  authDomain: "worldofnads-3b1a2.firebaseapp.com",
  databaseURL: "https://worldofnads-3b1a2-default-rtdb.firebaseio.com",
  projectId: "worldofnads-3b1a2",
  storageBucket: "worldofnads-3b1a2.firebasestorage.app",
  messagingSenderId: "15570864804",
  appId: "1:15570864804:web:23a40e23b715988f9af431",
  measurementId: "G-K9Q3JQVRBW"
};

const app = initializeApp(firebaseConfig);
const db = getDatabase(app);

const SKINS_ABI = [
  "function updateSkinURI(uint256 skinId, string calldata uri) external",
  "function uri(uint256) view returns (string)",
];

const EXISTING_SKINS = [
  { onChainId: 2, frontendId: "s1", name: "Sprout", tier: "common", price: "5 MON", maxSupply: 1000, requiredXP: 0, shader: "default", image: "/skins_png/s1.png",
    palette: { body: "#7bc67e", body_alt: "#5ea861", cheek: "#5ea861", eye: "#ffffff", skin: "#d9b373" },
    outline_color: "#7bc67e", crown_color: "#7bc67e", face_texture: "", shader_targets: ["body","cheek","eye"],
    attachment: { shape: "box", color: "#d9b373" } },
  { onChainId: 3, frontendId: "s2", name: "Cobalt", tier: "rare", price: "10 MON", maxSupply: 500, requiredXP: 100, shader: "gold", image: "/skins_png/s2.png",
    palette: { body: "#3b7dd8", body_alt: "#3b7dd8", cheek: "#3b7dd8", eye: "#ffffff", skin: "#8ab4f8" },
    outline_color: "#3b7dd8", crown_color: "#3b7dd8", face_texture: "", shader_targets: ["body","cheek"],
    attachment: { shape: "box", color: "#8ab4f8" } },
  { onChainId: 4, frontendId: "s3", name: "Magma", tier: "epic", price: "20 MON", maxSupply: 100, requiredXP: 500, shader: "default", image: "/skins_png/s3.png",
    palette: { body: "#ff6b35", body_alt: "#ff6b35", cheek: "#ff6b35", eye: "#ffffff", skin: "#ff9c6e" },
    outline_color: "#ff4500", crown_color: "#ff4500", face_texture: "", shader_targets: ["body","cheek","eye"],
    attachment: { shape: "cone", color: "#ff4500" } },
  { onChainId: 5, frontendId: "s4", name: "Aether", tier: "legendary", price: "50 MON", maxSupply: 50, requiredXP: 2000, shader: "angel", image: "/skins_png/s4.png",
    palette: { body: "#9b59b6", body_alt: "#9b59b6", cheek: "#9b59b6", eye: "#f1c40f", skin: "#c39bd3" },
    outline_color: "#f1c40f", crown_color: "#f1c40f", face_texture: "", shader_targets: ["body","cheek","eye"],
    attachment: { shape: "torus", color: "#f1c40f" } },
];

const BASE_URL = process.env.RENDER_EXTERNAL_URL || "https://worldofnads.onrender.com";

async function main() {
  const provider = new ethers.JsonRpcProvider(process.env.MN_RPC_URL);
  const wallet = new ethers.Wallet(process.env.TRUSTED_AUTHORITY_PRIVATE_KEY, provider);
  const skinsContract = new ethers.Contract(
    ethers.getAddress(process.env.SKINS_ADDRESS),
    SKINS_ABI,
    wallet
  );

  console.log(`Migrating ${EXISTING_SKINS.length} skins to Firebase...\n`);

  for (const skin of EXISTING_SKINS) {
    // 1. Update on-chain URI
    const newUri = `${BASE_URL}/api/skins/${skin.onChainId}`;
    console.log(`[${skin.name}] on-chain URI → ${newUri}`);
    try {
      const tx = await skinsContract.updateSkinURI(skin.onChainId, newUri, { gasLimit: 100000 });
      const receipt = await tx.wait();
      console.log(`  ✓ On-chain URI updated (tx: ${tx.hash}, block: ${receipt.blockNumber})`);
    } catch (e) {
      console.log(`  ✗ On-chain URI update failed: ${e.message}`);
    }

    // 2. Save to Firebase
    const skinData = {
      name: skin.name,
      tier: skin.tier,
      price: skin.price,
      maxSupply: skin.maxSupply,
      requiredXP: skin.requiredXP,
      image: skin.image,
      onChainId: skin.onChainId,
      skinConfig: {
        palette: skin.palette,
        outline_color: skin.outline_color,
        crown_color: skin.crown_color,
        face_texture: skin.face_texture,
        shader: skin.shader,
        shader_targets: skin.shader_targets,
        attachment: skin.attachment,
      },
      schemaVersion: 1,
      updatedAt: new Date().toISOString(),
    };

    const skinRef = ref(db, `skins/${skin.frontendId}`);
    await update(skinRef, skinData);
    console.log(`  ✓ Firebase saved as skins/${skin.frontendId}\n`);
  }

  // Also save default skins to Firebase
  const defaultSkins = [
    {
      frontendId: "s-default",
      name: "Default Nad",
      tier: "common", price: "0 MON", maxSupply: null, requiredXP: 0,
      image: "/skins_png/s-default.png", onChainId: null,
      palette: { body: "#fc2d96", body_alt: "#fc4b8c", cheek: "#fc6a9b", eye: "#e7e7e7", skin: "#ff9c6e" },
      outline_color: "#fc00d9", crown_color: "#fc00d9", face_texture: "", shader: "default",
      shader_targets: ["body","cheek","eye"], attachment: { shape: "box", color: "#ff9c6e" }
    },
    {
      frontendId: "s-default-unshaded",
      name: "Default Nad (Flat)",
      tier: "common", price: "0 MON", maxSupply: null, requiredXP: 0,
      image: "/skins_png/s-default.png", onChainId: null,
      palette: { body: "#fc2d96", body_alt: "#fc4b8c", cheek: "#fc6a9b", eye: "#e7e7e7", skin: "#ff9c6e" },
      outline_color: "#fc00d9", crown_color: "#fc00d9", face_texture: "", shader: "unshaded",
      shader_targets: ["body","cheek","eye"], attachment: { shape: "box", color: "#ff9c6e" }
    }
  ];

  for (const s of defaultSkins) {
    const skinData = {
      name: s.name, tier: s.tier, price: s.price, maxSupply: s.maxSupply,
      requiredXP: s.requiredXP, image: s.image, onChainId: s.onChainId,
      skinConfig: {
        palette: s.palette, outline_color: s.outline_color, crown_color: s.crown_color,
        face_texture: s.face_texture, shader: s.shader, shader_targets: s.shader_targets,
        attachment: s.attachment,
      },
      schemaVersion: 1, updatedAt: new Date().toISOString(),
    };
    const skinRef = ref(db, `skins/${s.frontendId}`);
    await update(skinRef, skinData);
    console.log(`  ✓ Default skin saved as skins/${s.frontendId}`);
  }

  console.log("\nDone! All skins migrated to Firebase. On-chain URIs updated.");
}

main().catch((err) => {
  console.error("Migration failed:", err);
  process.exit(1);
});
