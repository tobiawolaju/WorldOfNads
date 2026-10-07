// Materialize the skin index (skinCombos.json) onto Firebase.
//
//   id N -> combo floor((N - 1) / 2);  odd id = shaded, even id = unshaded
//
// By default it only *stamps* skins that already exist: for each numeric skin
// doc it sets skinConfig.attachments to the combo its id owns, preserving the
// palette/name/tier the skin already has. That fixes existing skins that
// render bare because they predate the attachments field.
//
// Usage (from backend/):
//   node scripts/generateSkinsFromCombos.js                  # dry run (default)
//   node scripts/generateSkinsFromCombos.js --write          # stamp existing skins
//   node scripts/generateSkinsFromCombos.js --write --create-missing
//
// --create-missing also materializes a Firebase doc for every combo pair
// (2n+1 / 2n+2) that has no skin yet, so any future mint / preview of that id
// resolves the right combo. Off by default because both the in-game store and
// the web dashboard list every /api/skins entry.

import * as dotenv from "dotenv";
dotenv.config();

import { initializeApp } from "firebase/app";
import { getDatabase, ref, get, update } from "firebase/database";
import { loadCombos, attachmentsForId, idsForCombo, isShadedId, isNumericSkinId, newDocForCombo } from "../skinIndex.js";

const firebaseConfig = {
  apiKey: "AIzaSyBNFaveUoWNE4bBTNBgCnK63Bp25BFr5gs",
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

async function main() {
  const write = process.argv.includes("--write");
  const createMissing = process.argv.includes("--create-missing");
  const combos = loadCombos();

  console.log(`Skin index: ${combos.length} combos -> ids 1..${combos.length * 2}`);
  console.log(write ? "MODE: WRITE" : "MODE: dry-run (pass --write to apply)");
  if (createMissing) console.log("Also creating docs for combos without ids (--create-missing)");
  console.log("");

  const snap = await get(ref(db, "skins"));
  const existing = snap.exists() ? snap.val() : {};
  const existingIds = new Set(Object.keys(existing));

  let updates = 0;
  let skipped = 0;
  const creates = [];

  // 1. Stamp attachments onto every existing skin by its index (or the pinned
  //    defaults map for non-numeric ids like s-default).
  for (const [id, doc] of Object.entries(existing)) {
    const after = attachmentsForId(id);
    if (after === null) {
      console.log(`  - skins/${id} (${doc?.name ?? "?"}) -- no combo for this id, skipped`);
      skipped++;
      continue;
    }
    const before = Array.isArray(doc?.skinConfig?.attachments) ? doc.skinConfig.attachments : null;
    const parity = isNumericSkinId(id) ? (isShadedId(id) ? " shaded" : " unshaded") : " (named)";
    if (before && JSON.stringify(before) === JSON.stringify(after)) {
      console.log(`  = skins/${id} (${doc?.name ?? "?"}) -> [${after.join(", ")}]${parity} (unchanged)`);
      continue;
    }
    console.log(`  ~ skins/${id} (${doc?.name ?? "?"}) -> [${after.join(", ")}]${parity}` +
      (before ? `  was [${before.join(", ")}]` : "  was (none)"));
    updates++;
    if (write) {
      await update(ref(db, `skins/${id}/skinConfig`), { attachments: after });
    }
  }

  // 2. Optionally materialize the full index for not-yet-minted ids.
  if (createMissing) {
    for (let index = 0; index < combos.length; index++) {
      const { shaded, unshaded } = idsForCombo(index);
      for (const id of [shaded, unshaded]) {
        const key = String(id);
        if (existingIds.has(key)) continue;
        const doc = newDocForCombo(combos[index], key);
        creates.push(key);
        console.log(`  + skins/${key} (${doc.name}) -> [${doc.skinConfig.attachments.join(", ")}]`);
        if (write) {
          await update(ref(db, `skins/${key}`), doc);
        }
      }
    }
  }

  console.log("");
  console.log(`${updates} update(s), ${creates.length} create(s), ${skipped} skipped.`);
  console.log(write ? "Done." : "Dry-run only -- re-run with --write to apply.");
  process.exit(0);
}

main().catch((err) => {
  console.error("Generator failed:", err);
  process.exit(1);
});