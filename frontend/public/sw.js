// Service worker for World of Nads.
//
// Installed users get three caches:
//   shell  - the HTML entry point, network-first (a deploy still lands on the
//            next navigation) with the last good copy as the offline fallback.
//   assets - Vite's hashed build output, cache-first. The filename *is* the
//            content hash, so a hit can never be stale.
//   media  - artwork and fonts, stale-while-revalidate: paint the copy we have
//            immediately, refresh it in the background.
//
// Deliberately NOT cached: /api (live data), /godot (the large, ranged game
// bundle) and /attachments (GLBs fetched through a manifest). Those are either
// time sensitive or big enough that the HTTP cache already does the right thing.

const VERSION = "won-v3";
const SHELL = `won-shell-${VERSION}`;
const ASSETS = `won-assets-${VERSION}`;
const MEDIA = `won-media-${VERSION}`;

// Bounded so an installed app never turns into hundreds of megabytes of
// artwork on a phone with very little free space. Oldest entries go first.
const MAX_MEDIA_ENTRIES = 90;
// Older deploys retire their chunks without telling us, so the build-output
// cache is bounded too (~a handful of deploys) instead of growing forever.
const MAX_ASSET_ENTRIES = 120;

const SHELL_URLS = ["/", "/index.html", "/manifest.json", "/offline.html", "/loadinglogo.png", "/w.png"];

const MEDIA_PATTERN =
  /\.(?:png|jpe?g|webp|avif|gif|svg|ico|woff2?|ttf|otf|mp3|ogg|wav|m4a|webm|mp4)$/i;

const BYPASS_PREFIXES = ["/api/", "/godot/", "/attachments/"];

self.addEventListener("install", (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(SHELL);
      // add() per URL: a single 404 must not abort the whole install.
      await Promise.all(SHELL_URLS.map((url) => cache.add(url).catch(() => {})));
      // Take over as soon as the new worker is downloaded.
      await self.skipWaiting();
    })(),
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    (async () => {
      // Only drop caches from other versions; keep the current three.
      const keep = new Set([SHELL, ASSETS, MEDIA]);
      const keys = await caches.keys();
      await Promise.all(keys.filter((key) => !keep.has(key)).map((key) => caches.delete(key)));
      // Control already-open pages immediately.
      await self.clients.claim();
    })(),
  );
});

const isBypassed = (url) =>
  url.pathname === "/sw.js" || BYPASS_PREFIXES.some((prefix) => url.pathname.startsWith(prefix));

/** Drops the oldest entries once a cache grows past `max`. */
async function trim(cacheName, max) {
  const cache = await caches.open(cacheName);
  const keys = await cache.keys();
  if (keys.length <= max) return;
  // Cache.keys() is insertion ordered, so the front of the list is the oldest.
  await Promise.all(keys.slice(0, keys.length - max).map((key) => cache.delete(key)));
}

async function cacheFirst(request, cacheName, max) {
  const cache = await caches.open(cacheName);
  const cached = await cache.match(request);
  if (cached) return cached;
  const response = await fetch(request);
  if (response.ok) {
    cache
      .put(request, response.clone())
      .then(() => trim(cacheName, max))
      .catch(() => {});
  }
  return response;
}

async function staleWhileRevalidate(request, cacheName, max) {
  const cache = await caches.open(cacheName);
  const cached = await cache.match(request);
  const network = fetch(request)
    .then((response) => {
      if (response.ok) {
        cache
          .put(request, response.clone())
          .then(() => trim(cacheName, max))
          .catch(() => {});
      }
      return response;
    })
    .catch(
      () =>
        cached ||
        new Response("", {
          status: 504,
          statusText: "Offline",
        }),
    );
  return cached || network;
}

async function networkFirstShell(request, url) {
  try {
    const response = await fetch(request);
    // Only the SPA entry point is worth keeping as the offline fallback; other
    // routes (the game's /play.html) must never overwrite it.
    if (response.ok && (url.pathname === "/" || url.pathname === "/index.html")) {
      const cache = await caches.open(SHELL);
      cache.put("/index.html", response.clone()).catch(() => {});
    }
    return response;
  } catch {
    const cached = (await caches.match(request)) || (await caches.match("/index.html"));
    if (cached) return cached;
    const offlinePage = await caches.match("/offline.html");
    if (offlinePage) return offlinePage;
    return new Response("Offline", { status: 503, statusText: "Offline" });
  }
}

self.addEventListener("fetch", (event) => {
  const { request } = event;

  // Never interfere with anything that is not a plain same-origin read.
  if (request.method !== "GET") return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;
  if (isBypassed(url)) return;

  if (request.mode === "navigate") {
    event.respondWith(networkFirstShell(request, url));
    return;
  }

  // Tiny files first: the manifest and the icons it points at.
  if (url.pathname === "/manifest.json") return;

  if (url.pathname.startsWith("/assets/")) {
    event.respondWith(cacheFirst(request, ASSETS, MAX_ASSET_ENTRIES));
    return;
  }

  if (MEDIA_PATTERN.test(url.pathname)) {
    event.respondWith(staleWhileRevalidate(request, MEDIA, MAX_MEDIA_ENTRIES));
  }
});
