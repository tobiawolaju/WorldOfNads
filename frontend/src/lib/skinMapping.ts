export function resolveGameSkinName(rawSkin: string | null | undefined): string {
  const key = String(rawSkin || "").trim().toLowerCase();
  return key || "s-default";
}

export interface PaletteData {
  body?: number[];
  body_alt?: number[];
  cheek?: number[];
  eye?: number[];
  skin?: number[];
}

export interface AttachmentData {
  shape?: string;
  color?: number[];
}

export interface SkinData {
  palette?: PaletteData;
  outline_color?: number[];
  crown_color?: number[];
  face_texture?: string;
  shader?: string;
  shader_targets?: string[];
  attachment?: AttachmentData;
  /**
   * Attachment node names this skin wears, e.g. ["duck", "hair_001"]. Names map
   * to godot/scenes/skin.tscn and the GLBs in /attachments/. Absent or empty =
   * wears nothing; unknown names are ignored so new attachments can ship
   * without touching old configs.
   */
  attachments?: string[];
}

export function hexToRgbaArray(hex: string): number[] {
  const THREE = (globalThis as any).THREE;
  const c = THREE ? new THREE.Color(hex) : { r: 1, g: 1, b: 1 };
  return [c.r, c.g, c.b, 1];
}

/**
 * Odd numeric skin ids are the shaded edition of a skin, even ids the unshaded
 * (flat) variant of the same skin: 0001 shaded, 0002 flat, 0003 shaded, ...
 * Named ids (s-default, s-default-unshaded, ...) keep whatever shader their
 * config asks for. Mirrors SkinApplier._apply_shading_parity in Godot.
 */
export function resolveShaderType(
  skinId: string | null | undefined,
  configured?: string
): string {
  const key = String(skinId ?? "").trim();
  if (/^-?\d+$/.test(key)) {
    return Number(key) % 2 !== 0 ? "default" : "unshaded";
  }
  return configured || "default";
}

export interface SkinComboIndexPayload {
  combos?: Array<{ name?: string; attachments?: string[] }>;
  defaults?: Record<string, string[]>;
}

/**
 * Builds the id -> attachments map from GET /api/skin-combos: combo n owns ids
 * 2n+1 (shaded) and 2n+2 (unshaded), plus any named ids in "defaults". Mirrors
 * SkinApplier.seed_index_from_api in Godot.
 */
export function buildComboMap(
  payload: SkinComboIndexPayload | null | undefined
): Record<string, string[]> {
  const map: Record<string, string[]> = {};
  const combos = payload?.combos;
  if (Array.isArray(combos)) {
    combos.forEach((combo, index) => {
      const atts = Array.isArray(combo?.attachments) ? combo.attachments : [];
      map[String(index * 2 + 1)] = atts;
      map[String(index * 2 + 2)] = atts;
    });
  }
  const defaults = payload?.defaults;
  if (defaults && typeof defaults === "object") {
    for (const [id, atts] of Object.entries(defaults)) {
      if (Array.isArray(atts)) map[String(id).toLowerCase()] = atts;
    }
  }
  return map;
}

/**
 * Effective attachments for a skin: its own list when present (even []), else
 * the combo its id owns in the index. Keeps the index authoritative without any
 * extra document, and matches the Godot runtime.
 */
export function resolveSkinAttachments(
  skinId: string | null | undefined,
  configured: string[] | undefined,
  comboMap: Record<string, string[]>
): string[] {
  if (Array.isArray(configured)) return configured;
  const raw = String(skinId ?? "").trim();
  if (!raw) return [];
  const key = /^\d+$/.test(raw) ? String(Number(raw)) : raw.toLowerCase();
  return comboMap[key] ?? [];
}

/**
 * Store artwork ships as one render per store *card*, named after the two
 * catalog slots it covers (`<lo>-<hi>.png`). The catalog lists the two default
 * skins first, then the numeric combos, whose ids pair up as 2n+1 (shaded) /
 * 2n+2 (unshaded):
 *
 *   s-default, s-default-unshaded  ->  1-2.png
 *   ids 1, 2   (combo 0)           ->  3-4.png
 *   ids 3, 4   (combo 1)           ->  5-6.png
 *   ...
 *   ids 21, 22 (combo 10)          -> 23-24.png
 *
 * A card shows its shaded and flat variants with the same render, so both ids
 * of a pair resolve to the same file. Returns "" for anything the folder does
 * not cover (the caller then keeps whatever `image` the item already carries).
 * Mirrors _skin_basename() in godot/scripts/screens/dshbord.gd.
 */
export function skinArtworkFileName(skinId: string | null | undefined): string {
  const id = String(skinId ?? "").trim();
  if (!id) return "";
  if (/^\d+$/.test(id) && Number(id) >= 1) {
    const combo = Math.floor((Number(id) - 1) / 2);
    const lo = 2 * (combo + 2) - 1;
    return `${lo}-${lo + 1}.png`;
  }
  if (id.replace(/-unshaded$/i, "").toLowerCase() === "s-default") return "1-2.png";
  return "";
}

/**
 * Public URL for a skin's store artwork, falling back to the item's authored
 * `image` (or the legacy `/skins_png/<id>.png` route) when the id is not part
 * of the catalog artwork folder.
 */
export function resolveSkinImageUrl(
  skinId: string | null | undefined,
  fallback?: string
): string {
  const id = String(skinId ?? "").trim();
  const file = skinArtworkFileName(id);
  if (file) return `/skins_png/${file}`;
  if (fallback) return fallback;
  return `/skins_png/${id}.png`;
}
