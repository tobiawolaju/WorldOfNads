export type GameQuality = "auto" | "low" | "high";

export const QUALITY_STORAGE_KEY = "wons_game_quality";

export const QUALITY_OPTIONS: GameQuality[] = ["auto", "low", "high"];

export const QUALITY_LABELS: Record<GameQuality, string> = {
  auto: "Auto",
  low: "Low",
  high: "High"
};

// The Godot canvas is rendered at (viewport * renderScale) and scaled back up
// in CSS, so the engine's own pixel budget (GameManager) also lands on a
// smaller scaling_3d_scale. This is the only knob that cuts fill rate without
// a game rebuild.
const RENDER_SCALE_LOW = 0.65;
const RENDER_SCALE_AUTO_LOW_END = 0.7;

export function isLowEndDevice(): boolean {
  if (typeof navigator === "undefined") return false;
  const cores =
    typeof navigator.hardwareConcurrency === "number" ? navigator.hardwareConcurrency : 8;
  const memory = Number((navigator as unknown as { deviceMemory?: number }).deviceMemory) || 8;
  return cores <= 4 || memory <= 4;
}

export function normalizeQuality(value: unknown): GameQuality {
  return value === "low" || value === "high" || value === "auto" ? value : "auto";
}

export function resolveQuality(value: unknown): { quality: GameQuality; renderScale: number } {
  const quality = normalizeQuality(value);
  if (quality === "high") return { quality, renderScale: 1 };
  if (quality === "low") return { quality, renderScale: RENDER_SCALE_LOW };
  return { quality, renderScale: isLowEndDevice() ? RENDER_SCALE_AUTO_LOW_END : 1 };
}

export function readGameQuality(): GameQuality {
  if (typeof localStorage === "undefined") return "auto";
  try {
    return normalizeQuality(localStorage.getItem(QUALITY_STORAGE_KEY));
  } catch {
    return "auto";
  }
}

export function writeGameQuality(quality: GameQuality): void {
  if (typeof localStorage === "undefined") return;
  try {
    localStorage.setItem(QUALITY_STORAGE_KEY, quality);
  } catch {}
}
