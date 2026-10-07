// Shared skin index: the deterministic map from a skin's numeric id to the
// attachment combination it wears.
//
//   combo n (0-based) -> ids 2n+1 (shaded, odd) and 2n+2 (unshaded, even)
//   id N              -> combo floor((N - 1) / 2)
//
// The combo list lives in skinCombos.json and is the single source of truth.
// Game and web never read this file directly: they consume the flat
// `attachments` list materialized onto each skin by
// scripts/generateSkinsFromCombos.js. That keeps the runtime dumb and means
// adding a new attachment + combo needs no game/web changes.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));

let _combos = null;
let _defaults = null;

export function loadCombos() {
  if (_combos) return _combos;
  try {
    const raw = JSON.parse(readFileSync(join(__dirname, "skinCombos.json"), "utf8"));
    _combos = Array.isArray(raw.combos) ? raw.combos : [];
  } catch (err) {
    console.error("[skinIndex] Failed to read skinCombos.json:", err.message);
    _combos = [];
  }
  return _combos;
}

// Pinned attachments for non-numeric ids (e.g. "s-default"), which sit
// outside the numeric index.
export function loadDefaults() {
  if (_defaults) return _defaults;
  try {
    const raw = JSON.parse(readFileSync(join(__dirname, "skinCombos.json"), "utf8"));
    _combos = Array.isArray(raw.combos) ? raw.combos : _combos;
    _defaults = raw.defaults && typeof raw.defaults === "object" ? raw.defaults : {};
  } catch (err) {
    console.error("[skinIndex] Failed to read skinCombos.json:", err.message);
    _defaults = {};
  }
  return _defaults;
}

// True for zero-padded positive integers like "0002" / "6" (not "s-default").
export function isNumericSkinId(id) {
  return /^\d+$/.test(String(id ?? "").trim());
}

// 0-based combo position for a numeric id, or null for non-numeric ids.
export function comboIndexForId(id) {
  if (!isNumericSkinId(id)) return null;
  const n = Number(String(id).trim());
  if (!Number.isInteger(n) || n < 1) return null;
  return Math.floor((n - 1) / 2);
}

export function comboForId(id) {
  const index = comboIndexForId(id);
  if (index === null) return null;
  return loadCombos()[index] ?? null;
}

// The attachments list for an id, or null when the id falls outside the
// authored index (numeric id beyond the combos, or an unpinned named id).
export function attachmentsForId(id) {
  if (isNumericSkinId(id)) {
    const combo = comboForId(id);
    return combo && Array.isArray(combo.attachments) ? combo.attachments : null;
  }
  const pinned = loadDefaults()[String(id ?? "").trim()];
  return Array.isArray(pinned) ? pinned : null;
}

// Odd id = shaded, even id = unshaded (mirrors SkinApplier parity).
export function isShadedId(id) {
  return isNumericSkinId(id) && Number(String(id).trim()) % 2 !== 0;
}

export function idsForCombo(index) {
  return { shaded: index * 2 + 1, unshaded: index * 2 + 2 };
}

export const DEFAULT_PALETTE = { body: "#fc2d96", body_alt: "#fc4b8c", cheek: "#fc6a9b", eye: "#e7e7e7", skin: "#ff9c6e" };

// Firebase doc for a numeric id whose combo comes from the index. Odd ids are
// shaded, even ids are the "(Flat)" unshaded variant (parity is also enforced
// at runtime by SkinApplier; naming it here just keeps the store readable).
export function newDocForCombo(combo, id) {
  const numericId = Number(id);
  const flat = Number.isFinite(numericId) && numericId % 2 === 0;
  return {
    name: `${combo.name}${flat ? " (Flat)" : ""}`,
    tier: combo.tier || "common",
    price: combo.price || "0.01 MON",
    maxSupply: combo.maxSupply ?? 1000,
    requiredXP: combo.requiredXP ?? 0,
    image: combo.image || "/skins_png/s-default.png",
    onChainId: Number.isFinite(numericId) ? numericId : null,
    skinConfig: {
      palette: combo.palette || DEFAULT_PALETTE,
      outline_color: combo.outline_color || "#fc00d9",
      crown_color: combo.crown_color || "#fc00d9",
      face_texture: "",
      shader: "default",
      shader_targets: ["body", "cheek", "eye"],
      attachments: Array.isArray(combo.attachments) ? combo.attachments : [],
    },
    schemaVersion: 1,
    updatedAt: new Date().toISOString(),
  };
}