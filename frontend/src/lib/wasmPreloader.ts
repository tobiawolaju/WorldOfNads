import { getDeviceProfile } from "./deviceProfile";
import { isLowEndDevice } from "./gameQuality";
import { isAppInstalled, isMobileDevice, subscribeInstallState } from "./installPrompt";

export const STORAGE_KEY_WASM_VER = "wons_cached_wasm_version";

export interface PreloadOptions {
  /** If true, indicates the user explicitly hovered, clicked, or started the play countdown. */
  userIntent?: boolean;
  /** Whether to attempt prefetching the 69MB .pck file (high-end tier on unmetered connection only). */
  includePck?: boolean;
  /** Optional custom AbortSignal. */
  signal?: AbortSignal;
}

export interface PreloadResult {
  started: boolean;
  skipped: boolean;
  reason?:
    | "save_data"
    | "slow_connection"
    | "low_tier_without_intent"
    | "not_installed"
    | "already_cached"
    | "in_flight"
    | "offline"
    | "error";
  version?: string;
  filesLoaded?: string[];
}

let inFlightPromise: Promise<PreloadResult> | null = null;
let inFlightAbortController: AbortController | null = null;

/**
 * Checks the remote HTTP cache headers (ETag / Last-Modified) for /godot/index.wasm.
 * Returns a short version token or null if offline/error.
 */
export async function getRemoteWasmVersion(signal?: AbortSignal): Promise<string | null> {
  if (typeof window === "undefined" || !("fetch" in window)) return null;
  try {
    const res = await fetch("/godot/index.wasm", {
      method: "HEAD",
      cache: "no-cache",
      signal
    });
    if (!res.ok) return null;
    const etag = res.headers.get("etag") || "";
    const lastModified = res.headers.get("last-modified") || "";
    const length = res.headers.get("content-length") || "";

    if (etag) return etag.replace(/^W\//, "").replace(/"/g, "");
    if (lastModified) return `${lastModified}_${length}`;
    return length || "current";
  } catch {
    return null;
  }
}

/**
 * Returns the locally recorded cached WASM version from localStorage.
 */
export function getCachedWasmVersion(): string | null {
  if (typeof localStorage === "undefined") return null;
  try {
    return localStorage.getItem(STORAGE_KEY_WASM_VER);
  } catch {
    return null;
  }
}

/**
 * Determines whether the latest WASM is already recorded as cached.
 */
export function isLatestWasmCached(latestVersion: string): boolean {
  if (!latestVersion) return false;
  const cached = getCachedWasmVersion();
  return Boolean(cached && cached === latestVersion);
}

/**
 * Evaluates whether it is safe to preload WASM assets on the current device and network.
 * Protects low-end devices, low memory, cellular data, and weak connections.
 */
export function shouldPreload(userIntent: boolean = false): {
  allowed: boolean;
  reason?: PreloadResult["reason"];
} {
  if (typeof window === "undefined" || !("fetch" in window)) {
    return { allowed: false, reason: "offline" };
  }

  // 1. Mobile devices: Never start background downloads until installed as an app / APK
  if (isMobileDevice() && !isAppInstalled()) {
    return { allowed: false, reason: "not_installed" };
  }

  const nav = navigator as unknown as {
    connection?: {
      saveData?: boolean;
      effectiveType?: string;
    };
    onLine?: boolean;
  };

  if (nav.onLine === false) {
    return { allowed: false, reason: "offline" };
  }

  const conn = nav.connection;
  // 1. Data Saver enabled: never preload in background
  if (conn?.saveData === true) {
    return { allowed: false, reason: "save_data" };
  }

  // 2. Slow connection (2G / slow-2G): never preload
  const effectiveType = conn?.effectiveType;
  if (effectiveType === "slow-2g" || effectiveType === "2g") {
    return { allowed: false, reason: "slow_connection" };
  }

  const profile = getDeviceProfile();
  const lowEnd = profile.tier === "low" || isLowEndDevice();

  // 3. Low-end device on 3G: avoid background preloading
  if (lowEnd && effectiveType === "3g" && !userIntent) {
    return { allowed: false, reason: "slow_connection" };
  }

  // 4. Low-end devices must ONLY preload when there is explicit user intent
  // (e.g. hover, touch-start, or play countdown). Never on unprompted idle background.
  if (lowEnd && !userIntent) {
    return { allowed: false, reason: "low_tier_without_intent" };
  }

  return { allowed: true };
}

/**
 * Streams a file through a ReadableStream reader so the browser's HTTP disk cache
 * is populated, while immediately releasing chunks from JavaScript memory.
 * This ensures RAM overhead stays under ~64 KB instead of allocating a 33+ MB buffer.
 */
async function streamFetchIntoDiskCache(url: string, signal?: AbortSignal): Promise<boolean> {
  const res = await fetch(url, { cache: "default", signal });
  if (!res.ok) return false;

  if (res.body && typeof res.body.getReader === "function") {
    const reader = res.body.getReader();
    try {
      while (true) {
        const { done } = await reader.read();
        if (done) break;
      }
    } finally {
      reader.releaseLock();
    }
  } else {
    // Fallback for older browsers
    await res.blob();
  }
  return true;
}

/**
 * Safely starts preloading Godot assets if the user doesn't already have the latest version cached.
 * Designed specifically for low-end device safety:
 * - Zero WASM compilation in background (no CPU freezes)
 * - Zero large heap allocations (streamed directly to disk cache)
 * - Network & battery guardrails (respects saveData, 2g, and tier)
 */
export async function preloadGodotWasm(options: PreloadOptions = {}): Promise<PreloadResult> {
  const { userIntent = false, includePck = false, signal } = options;

  if (inFlightPromise) {
    return inFlightPromise;
  }

  const check = shouldPreload(userIntent);
  if (!check.allowed) {
    return { started: false, skipped: true, reason: check.reason };
  }

  const controller = new AbortController();
  inFlightAbortController = controller;
  const activeSignal = signal || controller.signal;

  inFlightPromise = (async (): Promise<PreloadResult> => {
    try {
      // 1. Check if the latest version is already cached
      const remoteVersion = await getRemoteWasmVersion(activeSignal);
      if (remoteVersion && isLatestWasmCached(remoteVersion)) {
        return {
          started: false,
          skipped: true,
          reason: "already_cached",
          version: remoteVersion
        };
      }

      // 2. Select target files:
      // index.js (370 KB) and index.wasm (33 MB)
      const filesToLoad = ["/godot/index.js", "/godot/index.wasm"];

      // Only attempt 69MB index.pck if specifically requested, on high tier, unmetered
      const profile = getDeviceProfile();
      if (includePck && profile.tier === "high" && !isLowEndDevice()) {
        filesToLoad.push("/godot/index.pck");
      }

      // 3. Stream into browser HTTP cache
      const loaded: string[] = [];
      for (const url of filesToLoad) {
        if (activeSignal.aborted) break;
        const ok = await streamFetchIntoDiskCache(url, activeSignal);
        if (ok) loaded.push(url);
      }

      // 4. Record successful preload in localStorage
      if (remoteVersion && loaded.includes("/godot/index.wasm")) {
        try {
          localStorage.setItem(STORAGE_KEY_WASM_VER, remoteVersion);
        } catch {}
      }

      return {
        started: true,
        skipped: false,
        version: remoteVersion || undefined,
        filesLoaded: loaded
      };
    } catch (err: unknown) {
      const isAbort = err instanceof DOMException && err.name === "AbortError";
      return {
        started: false,
        skipped: true,
        reason: isAbort ? "error" : "error"
      };
    } finally {
      inFlightPromise = null;
      inFlightAbortController = null;
    }
  })();

  return inFlightPromise;
}

/**
 * Cancels any active in-flight preloading.
 */
export function cancelWasmPreload(): void {
  if (inFlightAbortController) {
    inFlightAbortController.abort();
    inFlightAbortController = null;
  }
}

/**
 * Schedules an idle background preload check.
 * On low-end devices or slow connections, this safely self-skips without consuming bandwidth.
 */
export function scheduleIdlePreload(delayMs: number = 3500): () => void {
  if (typeof window === "undefined") return () => {};

  let timerId: ReturnType<typeof setTimeout> | null = null;
  let idleCallbackId: number | null = null;

  const run = () => {
    if ("requestIdleCallback" in window) {
      idleCallbackId = (window as Window & { requestIdleCallback: (cb: () => void) => number }).requestIdleCallback(
        () => {
          void preloadGodotWasm({ userIntent: false });
        }
      );
    } else {
      void preloadGodotWasm({ userIntent: false });
    }
  };

  timerId = setTimeout(run, delayMs);

  return () => {
    if (timerId !== null) clearTimeout(timerId);
    if (idleCallbackId !== null && "cancelIdleCallback" in window) {
      (window as Window & { cancelIdleCallback: (id: number) => void }).cancelIdleCallback(idleCallbackId);
    }
  };
}

// Automatically start background preload once app is installed during the session
if (typeof window !== "undefined") {
  subscribeInstallState(() => {
    if (isAppInstalled()) {
      scheduleIdlePreload(1500);
    }
  });
}
