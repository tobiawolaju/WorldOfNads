// A tiny, memory-bounded warm cache for the artwork the dashboard swaps in and
// out as its tabs change.
//
// Why: every tab renders its own <img>/background-image, so leaving a tab
// unmounts those elements. The HTTP cache stops a re-download, but the decoded
// bitmap is dropped with the element, and Chrome re-decodes (briefly painting
// blank) every time the tab comes back - very visible on low-end Android.
// Holding a reference to the decoded HTMLImageElement keeps the bitmap alive in
// the browser's memory cache, so the next mount paints from it immediately.
//
// The cache is deliberately tiny and FIFO-evicting: a decoded 1024x1024 PNG is
// roughly 4 MB, so an unbounded cache would cost more than the re-decode it
// avoids. Only art that is about to matter should be warmed.

/** How many decoded images to keep alive at once. Keep this small: this is the
 *  budget for the warm bitmaps, not a download cache (the HTTP cache does that). */
const MAX_WARM_IMAGES = 6;

const _warm = new Map<string, HTMLImageElement>();

/**
 * Keeps `url` decoded and ready for the next mount.
 *
 * Re-warming an already warm URL only refreshes its position in the FIFO, so a
 * tab the player keeps returning to is never the one that gets evicted.
 */
export function warmImage(url?: string | null): void {
  if (!url || typeof window === "undefined") return;

  const existing = _warm.get(url);
  if (existing) {
    _warm.delete(url);
    _warm.set(url, existing);
    return;
  }

  const img = new Image();
  img.decoding = "async";
  img.src = url;
  // decode() resolves once the bitmap is ready. Missing/blocked artwork must
  // never throw into the page, so failures are swallowed.
  if (typeof img.decode === "function") {
    img.decode().catch(() => {});
  }

  _warm.set(url, img);
  while (_warm.size > MAX_WARM_IMAGES) {
    const oldest = _warm.keys().next().value as string | undefined;
    if (oldest === undefined) break;
    _warm.delete(oldest);
  }
}

/** Warms a batch of URLs, ignoring empty entries. */
export function warmImages(urls: Iterable<string | null | undefined>): void {
  for (const url of urls) warmImage(url);
}

/**
 * Runs `fn` once the browser is idle, so artwork nobody has looked at yet never
 * competes with the first paint, the 3D scene or the initial data fetch. Chrome
 * on Android supports requestIdleCallback; the timeout keeps a busy tab from
 * deferring the work forever, and the setTimeout fallback covers Safari.
 */
export function whenIdle(fn: () => void, timeoutMs = 2500): void {
  if (typeof window === "undefined") return;
  const ric = (window as unknown as {
    requestIdleCallback?: (cb: () => void, opts?: { timeout: number }) => number;
  }).requestIdleCallback;
  if (typeof ric === "function") {
    ric(fn, { timeout: timeoutMs });
    return;
  }
  window.setTimeout(fn, 300);
}

/** Drops every warm bitmap. Used when the dashboard unmounts for good. */
export function clearWarmImages(): void {
  _warm.clear();
}
