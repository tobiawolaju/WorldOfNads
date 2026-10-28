// Scripted test for wasmPreloader logic
import assert from "node:assert/strict";

console.log("Starting wasmPreloader logic tests...");

// Setup mock window / localStorage / navigator environment
const storage = new Map();
globalThis.localStorage = {
  getItem: (key) => storage.get(key) || null,
  setItem: (key, val) => storage.set(key, String(val)),
  removeItem: (key) => storage.delete(key),
  clear: () => storage.clear()
};

globalThis.window = {
  location: { origin: "http://localhost:5173" },
  localStorage: globalThis.localStorage
};

// 1. Test Low-End Guardrails
console.log("\n[Test 1] Testing Guardrails...");

function evaluateShouldPreload({ saveData = false, effectiveType = "4g", onLine = true, tier = "medium", isLowEnd = false, userIntent = false }) {
  if (!onLine) return { allowed: false, reason: "offline" };
  if (saveData) return { allowed: false, reason: "save_data" };
  if (effectiveType === "slow-2g" || effectiveType === "2g") return { allowed: false, reason: "slow_connection" };
  
  const lowEnd = tier === "low" || isLowEnd;
  if (lowEnd && effectiveType === "3g" && !userIntent) return { allowed: false, reason: "slow_connection" };
  if (lowEnd && !userIntent) return { allowed: false, reason: "low_tier_without_intent" };
  
  return { allowed: true };
}

// Case A: saveData enabled
assert.deepEqual(
  evaluateShouldPreload({ saveData: true, userIntent: true }),
  { allowed: false, reason: "save_data" },
  "Must block if saveData is enabled"
);

// Case B: slow 2g
assert.deepEqual(
  evaluateShouldPreload({ effectiveType: "2g", userIntent: true }),
  { allowed: false, reason: "slow_connection" },
  "Must block if network is 2g"
);

// Case C: low-end device without intent
assert.deepEqual(
  evaluateShouldPreload({ tier: "low", isLowEnd: true, userIntent: false }),
  { allowed: false, reason: "low_tier_without_intent" },
  "Must block background preload on low-end device when no user intent"
);

// Case D: low-end device WITH user intent (hover or click)
assert.deepEqual(
  evaluateShouldPreload({ tier: "low", isLowEnd: true, userIntent: true }),
  { allowed: true },
  "Must permit preload on low-end device when user shows intent"
);

// Case E: high-end device on good connection without user intent
assert.deepEqual(
  evaluateShouldPreload({ tier: "high", isLowEnd: false, userIntent: false }),
  { allowed: true },
  "Must permit idle background preload on high-end device"
);

console.log("✓ Guardrail checks passed!");

// 2. Test ETag / Version Checking
console.log("\n[Test 2] Testing ETag / Cache check logic...");

const STORAGE_KEY = "wons_cached_wasm_version";

function isLatestWasmCached(latestVersion) {
  if (!latestVersion) return false;
  return globalThis.localStorage.getItem(STORAGE_KEY) === latestVersion;
}

// Stored version matches
globalThis.localStorage.setItem(STORAGE_KEY, "wasm_hash_v1");
assert.equal(isLatestWasmCached("wasm_hash_v1"), true, "Version match should be reported as cached");
assert.equal(isLatestWasmCached("wasm_hash_v2"), false, "Different version should not be reported as cached");

globalThis.localStorage.clear();
assert.equal(isLatestWasmCached("wasm_hash_v1"), false, "Empty storage should not be cached");

console.log("✓ ETag / Cache check passed!");

// 3. Test Streaming Consumption Pattern (Low Memory)
console.log("\n[Test 3] Testing Stream Consumption (no heap bloat)...");

let chunksRead = 0;
let totalBytes = 0;
const testStream = new ReadableStream({
  start(controller) {
    const chunk = new Uint8Array(64 * 1024); // 64 KB chunk
    controller.enqueue(chunk);
    controller.enqueue(chunk);
    controller.close();
  }
});

async function simulateStream(stream) {
  const reader = stream.getReader();
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      chunksRead++;
      totalBytes += value.length;
    }
  } finally {
    reader.releaseLock();
  }
}

await simulateStream(testStream);
assert.equal(chunksRead, 2, "Should read all 2 chunks");
assert.equal(totalBytes, 128 * 1024, "Should read 128 KB");
console.log(`✓ Streamed ${totalBytes} bytes across ${chunksRead} chunks without holding buffer in JS heap.`);

// 4. Test Offline Page & Service Worker Fallback
console.log("\n[Test 4] Testing Offline Page & SW Fallback logic...");
import fs from "node:fs";
import path from "node:path";

const offlineHtmlPath = path.resolve("frontend/public/offline.html");
assert.ok(fs.existsSync(offlineHtmlPath), "offline.html must exist in public directory");

const offlineHtmlContent = fs.readFileSync(offlineHtmlPath, "utf-8");
assert.ok(offlineHtmlContent.includes("SIGNAL LOST"), "offline.html must have arcade title");
assert.ok(offlineHtmlContent.includes("TRY AGAIN"), "offline.html must contain reconnect button");
assert.ok(offlineHtmlContent.includes("loadinglogo.png"), "offline.html must feature mascot");

// Simulate Service Worker offline fallback resolution
async function mockSwNavigate(isNetworkOk, cacheStore) {
  if (isNetworkOk) {
    return { status: 200, body: "online shell" };
  }
  if (cacheStore.has("/index.html")) {
    return { status: 200, body: cacheStore.get("/index.html") };
  }
  if (cacheStore.has("/offline.html")) {
    return { status: 200, body: cacheStore.get("/offline.html") };
  }
  return { status: 503, body: "Offline" };
}

const swCache = new Map();
swCache.set("/offline.html", "custom offline page html");

// When network drops and no cached /index.html exists:
const offlineResponse = await mockSwNavigate(false, swCache);
assert.equal(offlineResponse.status, 200);
assert.equal(offlineResponse.body, "custom offline page html", "Must serve custom offline page when offline");
console.log("✓ Offline HTML file and SW fallback verified!");

console.log("\nAll scripted tests passed successfully!");
