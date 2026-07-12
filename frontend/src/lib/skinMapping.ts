const DEFAULT_GAME_SKIN_NAME = "defaultnad";

const GAME_SKIN_NAME_BY_KEY: Record<string, string> = {
  "s-default": DEFAULT_GAME_SKIN_NAME,
  "s-default-unshaded": "defaultnad_unshaded",
  s1: "sprout",
  s2: "cobalt",
  s3: "magma",
  s4: "aether",
  defaultnad: DEFAULT_GAME_SKIN_NAME,
  defaultnad_unshaded: "defaultnad_unshaded",
  sprout: "sprout",
  cobalt: "cobalt",
  magma: "magma",
  aether: "aether"
};

function normalizeSkinKey(rawSkin: string | null | undefined): string {
  return String(rawSkin || "")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, " ");
}

export function resolveGameSkinName(rawSkin: string | null | undefined): string {
  const key = normalizeSkinKey(rawSkin);
  return GAME_SKIN_NAME_BY_KEY[key] || DEFAULT_GAME_SKIN_NAME;
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
}

export function hexToRgbaArray(hex: string): number[] {
  const c = new (globalThis as any).THREE?.Color(hex) || { r: 1, g: 1, b: 1 };
  return [c.r, c.g, c.b, 1];
}
