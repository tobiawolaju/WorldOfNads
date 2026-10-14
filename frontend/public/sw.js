// Minimal service worker for World of Nads.
//
// Its only job is to make the site installable as a real app (PWA). Chrome
// mints a proper WebAPK and fires `beforeinstallprompt` only when the service
// worker registers a `fetch` handler, so this file exists mainly to provide
// one. It deliberately does NOT cache or rewrite anything: every request is
// left to the browser, which keeps the game's large ranged asset downloads and
// every deploy working exactly as they do without a service worker.

self.addEventListener("install", () => {
  // Activate the new worker as soon as it has downloaded instead of waiting for
  // every tab to close.
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    (async () => {
      // Drop any caches an older build may have created so nothing is stale.
      const keys = await caches.keys();
      await Promise.all(keys.map((key) => caches.delete(key)));
      // Take control of already-open pages immediately.
      await self.clients.claim();
    })(),
  );
});

// Presence of this handler is what unlocks the install prompt. We intentionally
// never call event.respondWith(), so every request passes straight through to
// the network as normal.
self.addEventListener("fetch", () => {});
