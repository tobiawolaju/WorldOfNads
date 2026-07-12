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
}

export function hexToRgbaArray(hex: string): number[] {
  const THREE = (globalThis as any).THREE;
  const c = THREE ? new THREE.Color(hex) : { r: 1, g: 1, b: 1 };
  return [c.r, c.g, c.b, 1];
}
