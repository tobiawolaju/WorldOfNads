/**
 * Public profile-picture lookup for the in-game event feed.
 *
 * The Godot HUD renders the events socket as a stream-chat list: one row per
 * event with the speaker's avatar, name and message. The events payload itself
 * carries only a `playerId` that the room server mints as a random UUID (see
 * `backend-rust/src/net.rs`), so it cannot be joined back to the auth store.
 * The one identity that *is* in the payload is the username embedded in the
 * message text. This endpoint turns that username into a picture URL.
 *
 * What it will and will not return:
 *
 *   - Only `profile_picture_url`. Never the user record, roles, wallet, XP or
 *     anything else. A username is already broadcast to the whole room in the
 *     event feed, so pairing it with its public avatar leaks nothing new.
 *   - Only `https:` URLs of a sane length. A stored value is data, not a
 *     command: it must not be able to become a `javascript:` URL or a payload
 *     the client is asked to fetch.
 *   - An empty string for an unknown player. "No picture" is a normal answer,
 *     not an error, so the client can cache it and fall back to a badge.
 *
 * The lookup is unauthenticated on purpose — the caller is a game client
 * rendering public chat. Abuse is bounded by the rate limiter and by the short
 * TTL cache, which also keeps a 20-player room from hammering the RTDB.
 */

import { createRateLimiter } from "./chogNft.js";

export const DEFAULT_AVATAR_CACHE_TTL_MS = 5 * 60 * 1000;
export const DEFAULT_AVATAR_CACHE_MAX_ENTRIES = 2000;
export const DEFAULT_AVATAR_RATE_LIMIT_MAX = 120;
export const DEFAULT_AVATAR_RATE_LIMIT_WINDOW_MS = 60 * 1000;
export const MAX_USERNAME_LENGTH = 32;
export const MAX_AVATAR_URL_LENGTH = 2048;

/**
 * Characters a stored username can legitimately contain. `authStore.js`
 * replaces `. # $ / [ ]` with `_` when it mints a record, so anything in that
 * set is not a real username — and `/` in particular would walk the RTDB path
 * (`users/${username}`) somewhere else entirely.
 */
const USERNAME_PATTERN = /^[A-Za-z0-9_.\- ]+$/;

/** True when `value` is a username this service is willing to look up. */
export function isValidLookupUsername(value) {
  if (typeof value !== "string") return false;
  const trimmed = value.trim();
  if (!trimmed || trimmed.length > MAX_USERNAME_LENGTH) return false;
  if (trimmed.includes("/") || trimmed.includes("\\")) return false;
  if (trimmed.includes("..")) return false;
  return USERNAME_PATTERN.test(trimmed);
}

/**
 * Extracts a displayable picture URL from a stored user record.
 *
 * The record shape has drifted over time (Privy wrote `profile_picture_url`,
 * older rows carry `profilePictureUrl`), so both are accepted. Anything that is
 * not a plain https URL is dropped rather than passed through.
 */
export function pickProfilePictureUrl(profile) {
  if (!profile || typeof profile !== "object") return "";
  const candidates = [
    profile.profile_picture_url,
    profile.profilePictureUrl,
    profile.pfp,
    profile.avatar
  ];
  for (const candidate of candidates) {
    if (typeof candidate !== "string") continue;
    const url = candidate.trim();
    if (!url || url.length > MAX_AVATAR_URL_LENGTH) continue;
    if (!url.startsWith("https://")) continue;
    return url;
  }
  return "";
}

/**
 * TTL cache with a hard entry cap.
 *
 * Only successful lookups are stored; a transient RTDB failure must not pin an
 * empty answer for the whole TTL. Insertion order doubles as the eviction
 * order, which is good enough for a bounded, short-lived directory.
 */
export function createAvatarCache({
  ttlMs = DEFAULT_AVATAR_CACHE_TTL_MS,
  maxEntries = DEFAULT_AVATAR_CACHE_MAX_ENTRIES,
  now = Date.now
} = {}) {
  const entries = new Map();
  return {
    get(key) {
      const entry = entries.get(key);
      if (!entry) return undefined;
      if (now() >= entry.expiresAt) {
        entries.delete(key);
        return undefined;
      }
      return entry.value;
    },
    set(key, value) {
      entries.delete(key);
      if (entries.size >= maxEntries) {
        const oldest = entries.keys().next();
        if (!oldest.done) entries.delete(oldest.value);
      }
      entries.set(key, { value, expiresAt: now() + ttlMs });
      return value;
    },
    delete(key) {
      entries.delete(key);
    },
    clear() {
      entries.clear();
    },
    get size() {
      return entries.size;
    }
  };
}

/**
 * HTTP handler for `GET /api/profile/picture?username=...`.
 *
 * `lookupProfile(username)` resolves a stored user record (or null). It is
 * injected so the handler stays testable without Firebase.
 */
export function createAvatarDirectoryHandler({
  lookupProfile,
  getClientIp,
  rateLimiter = createRateLimiter({
    max: DEFAULT_AVATAR_RATE_LIMIT_MAX,
    windowMs: DEFAULT_AVATAR_RATE_LIMIT_WINDOW_MS
  }),
  cache = createAvatarCache(),
  sendJson,
  log = console
} = {}) {
  if (typeof lookupProfile !== "function") throw new Error("missing_lookup_profile");
  if (typeof sendJson !== "function") throw new Error("missing_send_json");

  return async function handleProfilePicture(req, res) {
    if (req?.method !== "GET") {
      sendJson(res, 405, { ok: false, error: "method_not_allowed" });
      return;
    }

    const raw = req?.url ? new URL(req.url, "http://localhost").searchParams.get("username") : null;
    const username = typeof raw === "string" ? raw.trim() : "";
    if (!username) {
      sendJson(res, 400, { ok: false, error: "username_required" });
      return;
    }
    if (!isValidLookupUsername(username)) {
      sendJson(res, 400, { ok: false, error: "invalid_username" });
      return;
    }

    const limiterKey = typeof getClientIp === "function" ? getClientIp(req) : "anonymous";
    const limit = rateLimiter.check(limiterKey || "anonymous");
    if (!limit.allowed) {
      res?.setHeader?.("Retry-After", String(limit.retryAfter));
      sendJson(res, 429, { ok: false, error: "rate_limited" });
      return;
    }

    // RTDB keys are case-sensitive, but two players should never resolve to
    // different pictures because one typed a capital letter. The stored record
    // wins; the cache is keyed on the folded form.
    const cacheKey = username.toLowerCase();
    const cached = cache.get(cacheKey);
    if (cached !== undefined) {
      sendJson(res, 200, { profile_picture_url: cached });
      return;
    }

    try {
      const profile = await lookupProfile(username);
      const url = pickProfilePictureUrl(profile);
      cache.set(cacheKey, url);
      // No-store on the wire: the client keeps its own copy, and the server
      // cache is the single place a TTL is enforced. A CDN caching this would
      // make a changed avatar invisible for as long as its own TTL.
      res?.setHeader?.("Cache-Control", "no-store");
      sendJson(res, 200, { profile_picture_url: url });
    } catch (error) {
      // Not cached: a lookup failure is "try again later", not "no picture".
      const code = typeof error?.message === "string" && /^[a-z0-9_]{1,64}$/.test(error.message)
        ? error.message
        : "unknown_error";
      log.error(`[AvatarDirectory] profile lookup failed: ${code}`);
      sendJson(res, 503, { ok: false, error: "profile_lookup_failed" });
    }
  };
}
