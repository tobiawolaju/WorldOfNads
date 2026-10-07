// Reset the numeric skin catalog to the full index in skinCombos.json.
//
//   combo n -> ids 2n+1 (shaded) / 2n+2 (unshaded), created in that order
//
// On a FRESH WONsSkins contract (nextSkinId == 1) createSkin assigns ids
// 1,2,3... in the same order, so the on-chain id, the Firebase doc key and the
// combo all line up exactly.
//
// Usage:
//   node scripts/resetSkinCatalog.js                          # dry-run plan
//   node scripts/resetSkinCatalog.js --write                  # wipe + write Firebase docs only
//   node scripts/resetSkinCatalog.js --wipe --onchain --write # delete + createSkin + save docs
//
// Flags:
//   --write    apply changes (otherwise dry-run)
//   --wipe     delete existing numeric skins/<id> docs first
//   --onchain  create on-chain supply for each id via SKINS_ADDRESS
//
// Requires the usual backend env (MN_RPC_URL, TRUSTED_AUTHORITY_PRIVATE_KEY,
// SKINS_ADDRESS). Reads combos via skinIndex.js so this stays in lock-step
// with the game/web.

import { ethers } from "ethers";
import * as dotenv from "dotenv";
dotenv.config();

import { initializeApp } from "firebase/app";
import { getDatabase, ref, get, set, remove } from "firebase/database";

import { loadCombos, idsForCombo, newDocForCombo } from "../skinIndex.js";

const firebaseConfig = {
  apiKey: "AIzaSyBNFaveUoWNE4bBTNBgCnK63bP25BFr5gs",
  authDomain: "worldofnads-3b1a2.firebaseapp.com",
  databaseURL: "https://worldofnads-3b1a2-default-rtdb.firebaseio.com",
  projectId: "worldofnads-3b1a2",
  storageBucket: "worldofnads-3b1a2.firebasestorage.app",
  messagingSenderId: "15570864804",
  appId: "1:15570864804:web:23a40e23b715988f9af431",
  measurementId: "G-K9Q3JQVRBW",
};

const app = initializeApp(firebaseConfig);
const db = getDatabase(app);

const SKINS_ABI = [
  "function createSkin(uint256 maxSupply, uint256 mintPrice, uint256 requiredXP, uint8 tier, string calldata uri) external",
  "function nextSkinId() external view returns (uint256)",
  "function owner() external view returns (address)",
];

const TIERS = ["common", "rare", "epic", "legendary"];
const BASE_URL = process.env.RENDER_EXTERNAL_URL || "https://worldofnads.onrender.com";

function buildPlan() {
  const combos = loadCombos();
  const plan = [];
  combos.forEach((combo, index) => {
    const { shaded, unshaded } = idsForCombo(index);
    for (const id of [shaded, unshaded]) {
      plan.push({ id, combo, doc: newDocForCombo(combo, id) });
    }
  });
  return plan;
}

async function main() {
  const args = process.argv.slice(2);
  const write = args.includes("--write");
  const wipe = args.includes("--wipe");
  const onchain = args.includes("--onchain");

  const combos = loadCombos();
  const plan = buildPlan();
  console.log(`Index: ${combos.length} combos -> ${plan.length} ids (1..${combos.length * 2})`);
  console.log(`MODE: ${write ? "WRITE" : "dry-run"}${wipe ? " +wipe" : ""}${onchain ? " +onchain" : ""}\n`);

  // 1. optionally remove existing numeric docs.
  const snap = await get(ref(db, "skins"));
  const existing = snap.exists() ? snap.val() : {};
  const numericIds = Object.keys(existing).filter((k) => /^\d+$/.test(k)).sort((a, b) => Number(a) - Number(b));
  if (wipe) {
    console.log(`Deleting ${numericIds.length} existing numeric doc(s):`);
    for (const id of numericIds) {
      console.log(`  - skins/${id} (${existing[id]?.name ?? "?"})`);
      if (write) await remove(ref(db, `skins/${id}`));
    }
    console.log("");
  } else if (numericIds.length) {
    console.log(`(leaving existing numeric docs: ${numericIds.join(", ")} — pass --wipe to delete)\n`);
  }

  // 2. connect to the skins contract when creating on-chain supply.
  let startId = 1;
  let contract = null;
  if (onchain) {
    if (!process.env.SKINS_ADDRESS) throw new Error("SKINS_ADDRESS is not set");
    const provider = new ethers.JsonRpcProvider(process.env.MN_RPC_URL);
    const wallet = new ethers.Wallet(process.env.TRUSTED_AUTHORITY_PRIVATE_KEY, provider);
    contract = new ethers.Contract(process.env.SKINS_ADDRESS, SKINS_ABI, wallet);
    const owner = await contract.owner();
    startId = Number(await contract.nextSkinId());
    console.log(`Contract : ${process.env.SKINS_ADDRESS}`);
    console.log(`Owner    : ${owner}`);
    console.log(`Signer   : ${wallet.address}`);
    console.log(`nextSkinId = ${startId}${startId !== 1 ? "  (NOT fresh — ids will be offset!)" : "  (fresh)"}\n`);
  }

  // 3. create on-chain (in index order) and write each doc.
  for (let k = 0; k < plan.length; k++) {
    const { doc } = plan[k];
    const predicted = onchain ? startId + k : plan[k].id;
    let actualId = predicted;
    console.log(`${String(predicted).padStart(3)}  ${doc.name.padEnd(22)} [${doc.skinConfig.attachments.join(", ") || "none"}]`);

    if (!write) continue;

    if (onchain) {
      const priceStr = String(doc.price || "0").replace(/[^0-9.]/g, "") || "0";
      const tierIdx = TIERS.indexOf(String(doc.tier).toLowerCase());
      const uri = `${BASE_URL}/api/skins/${predicted}`;
      const supply = BigInt(doc.maxSupply || 1000);
      const priceWei = ethers.parseUnits(priceStr, 18);
      const xp = BigInt(doc.requiredXP || 0);
      const tier = tierIdx < 0 ? 0 : tierIdx;

      let gasLimit = 500000n;
      try {
        const est = await contract.createSkin.estimateGas(supply, priceWei, xp, tier, uri);
        gasLimit = (est * 120n) / 100n;
      } catch { /* fall back to default gas */ }

      const tx = await contract.createSkin(supply, priceWei, xp, tier, uri, { gasLimit });
      const receipt = await tx.wait();

      let parsedId = null;
      for (const log of receipt.logs) {
        try {
          const parsed = contract.interface.parseLog(log);
          if (parsed?.name === "SkinCreated") { parsedId = Number(parsed.args.skinId); break; }
        } catch { /* not ours */ }
      }
      actualId = parsedId ?? predicted;
      if (actualId !== predicted) console.warn(`      ! on-chain id ${actualId} != predicted ${predicted} — using actual`);
      console.log(`      tx ${tx.hash}`);
    }

    await set(ref(db, `skins/${actualId}`), {
      ...doc,
      onChainId: onchain ? actualId : null,
      updatedAt: new Date().toISOString(),
    });
  }

  console.log(`\n${plan.length} skin(s) ${write ? "applied" : "planned"}.`);
  console.log(write ? "Done." : "Dry-run only — add --write to apply.");
  process.exit(0);
}

main().catch((err) => {
  console.error("resetSkinCatalog failed:", err);
  process.exit(1);
});