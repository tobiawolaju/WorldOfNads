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
