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
