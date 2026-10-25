// What the device can actually handle.
//
// There is no web API that asks the OS for "more performance" - a page cannot
// request a faster CPU or GPU profile. What it *can* do is (a) ask for
// persistence so caches survive, and (b) read the hints the browser does expose
// and size its own work to fit. That is what this module is for: it reads the
// capability hints once, turns them into a quality tier, and every renderer
// (three.js canvas, service worker artwork) sizes itself from that tier.

export type QualityTier = "low" | "medium" | "high";

export interface DeviceProfile {
  tier: QualityTier;
  /** navigator.deviceMemory in GB (Chromium only; 4 when unknown). */
  memoryGb: number;
  /** navigator.hardwareConcurrency (4 when unknown). */
  cores: number;
  /** Device pixel ratio ceiling handed to the three.js renderer. */
  maxDpr: number;
  antialias: boolean;
  /** Cubemap size for the pre-baked lightformers. */
  environmentResolution: number;
  /** Decorative background chickens. Purely visual, pure draw calls. */
  decorativeChickens: number;
  reducedMotion: boolean;
  saveData: boolean;
  coarsePointer: boolean;
}

let cached: DeviceProfile | null = null;

const num = (value: unknown, fallback: number): number =>
  typeof value === "number" && Number.isFinite(value) && value > 0 ? value : fallback;

/**
 * Reads the browser's capability hints and maps them to a tier.
 *
 * `navigator.deviceMemory` is rounded by the spec (0.25/0.5/1/2/4/8), which is
 * exactly the granularity needed here: a 2 GB phone scores high enough on its
 * own to drop the tier. Firefox and Safari do not report it, so the core count
 * and pointer type carry those browsers.
 */
export function getDeviceProfile(): DeviceProfile {
  if (cached) return cached;

  if (typeof window === "undefined") {
    cached = {
      tier: "medium",
      memoryGb: 4,
      cores: 4,
      maxDpr: 1.35,
      antialias: true,
      environmentResolution: 64,
      decorativeChickens: 6,
      reducedMotion: false,
      saveData: false,
      coarsePointer: false,
    };
    return cached;
  }

  const nav = window.navigator as Navigator & {
    deviceMemory?: number;
    connection?: { saveData?: boolean; effectiveType?: string };
  };

  const memoryGb = num(nav.deviceMemory, 4);
  const cores = num(nav.hardwareConcurrency, 4);
  const dpr = window.devicePixelRatio || 1;
  const saveData = nav.connection?.saveData === true;
  const coarsePointer = window.matchMedia("(hover: none) and (pointer: coarse)").matches;
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // Higher score = weaker device.
  let score = 0;
  if (memoryGb <= 2) score += 2;
  else if (memoryGb <= 4) score += 1;
  if (cores <= 2) score += 2;
  else if (cores <= 4) score += 1;
  if (saveData) score += 2;
  // A dense phone panel means many more pixels to shade for the same CSS size,
  // which is exactly what makes the 3D preview stutter on cheap handsets.
  if (coarsePointer && dpr > 2.5) score += 1;

  const tier: QualityTier =
    score >= 3 ? "low" : score === 0 && memoryGb >= 8 && cores >= 8 ? "high" : "medium";

  // `medium` and `high` keep the previous look exactly. Only `low` renders less.
  const quality: Record<QualityTier, Omit<DeviceProfile, "tier" | "memoryGb" | "cores" | "reducedMotion" | "saveData" | "coarsePointer">> = {
    low: { maxDpr: 1, antialias: false, environmentResolution: 16, decorativeChickens: 2 },
    medium: { maxDpr: 1.35, antialias: true, environmentResolution: 64, decorativeChickens: 6 },
    high: { maxDpr: 1.35, antialias: true, environmentResolution: 64, decorativeChickens: 6 },
  };

  cached = {
    tier,
    memoryGb,
    cores,
    reducedMotion,
    saveData,
    coarsePointer,
    ...quality[tier],
  };
  return cached;
}

/**
 * Marks the document with the tier so CSS can drop expensive effects (blur,
 * long animations) on weak hardware without every component asking.
 */
export function initDeviceProfile(): DeviceProfile {
  const profile = getDeviceProfile();
  if (typeof document !== "undefined") {
    const root = document.documentElement;
    root.dataset.perf = profile.tier;
    if (profile.reducedMotion) root.dataset.motion = "reduced";
  }
  return profile;
}

/**
 * Asks the browser to keep this origin's caches (service worker + HTTP cache)
 * instead of evicting them when the device runs low on space.
 *
 * Chromium grants this silently for installed PWAs and for sites the user has
 * engaged with; there is no permission prompt. Without it, Android will happily
 * throw away the artwork cache between sessions, which puts us straight back to
 * re-downloading every image.
 */
export async function requestPersistentStorage(): Promise<boolean> {
  try {
    if (typeof navigator === "undefined" || !navigator.storage?.persist) return false;
    if (await navigator.storage.persisted()) return true;
    return await navigator.storage.persist();
  } catch {
    return false;
  }
}
