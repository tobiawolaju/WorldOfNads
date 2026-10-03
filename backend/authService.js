/**
 * Device-link authentication service.
 *
 * Authority model:
 *   Privy        -> identity (who you are)
 *   WON backend  -> accounts, device linking, session issuance
 *   Godot        -> game client only
 *
 * Nothing in here trusts the caller. `/auth/device/approve` derives identity
 * from a server-verified Privy access token; every other endpoint is
 * unauthenticated but only ever hands out short-lived, single-use material.
 */

import { createHash, createHmac, randomBytes, timingSafeEqual } from "node:crypto";
import { PrivyClient } from "@privy-io/node";
import * as dotenv from "dotenv";
import {
  createDeviceLogin,
  createNativeSession,
  deleteDeviceLogin,
  getDeviceLogin,
  getDeviceLoginIdByCodeHash,
  getNativeSession,
  getNativeSessionIdByAccessHash,
  getNativeSessionIdByRefreshHash,
  resolveWonUser,
  revokeNativeSession,
  updateDeviceLogin,
  updateNativeSession
} from "./authStore.js";

dotenv.config();

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

// Full alphanumeric alphabet so codes match the documented `KJI-FYE` shape.
// The short code carries ~31 bits of entropy and is heavily rate limited; it is
// a lookup handle for the approval page, NOT a credential. The credential is
// the 256-bit device secret, which is required at exchange time.
const CODE_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
const POLL_INTERVAL_MS = 1500;

const config = {
  // Pepper for digests. MUST be set in production: the per-process fallback is a
  // dev-only convenience, because it invalidates every digest (and therefore
  // every live session) on restart.
  secret: process.env.WON_AUTH_SECRET || process.env.AUTH_TOKEN_SECRET || "",

  // The short code + device secret live this long. Deliberately brief: a user
  // has to scan a QR and approve on a second device.
  deviceLoginTtlSeconds: clampInt(process.env.DEVICE_LOGIN_TTL_SECONDS, 120, 30, 900),
  pollIntervalMs: POLL_INTERVAL_MS,

  accessTokenTtlSeconds: clampInt(process.env.NATIVE_ACCESS_TOKEN_TTL_SECONDS, 3600, 300, 86400),
  refreshTokenTtlSeconds: clampInt(
    process.env.NATIVE_REFRESH_TOKEN_TTL_SECONDS,
    60 * 60 * 24 * 30,
    3600,
    60 * 60 * 24 * 365
  ),

  // Origin the login screen prints into the QR code.
  webAuthBaseUrl: (process.env.WON_WEB_ORIGIN || "https://worldofnads.xyz").replace(/\/+$/, ""),

  rateLimits: {
    startPerIp: clampInt(process.env.DEVICE_LOGIN_START_LIMIT, 5, 1, 100),
    startPerDevice: 3,
    startWindowMs: clampInt(process.env.DEVICE_LOGIN_START_WINDOW_MS, 60_000, 5_000, 600_000),
    approvePerUser: clampInt(process.env.DEVICE_LOGIN_APPROVE_LIMIT, 10, 1, 100),
    approveWindowMs: 10 * 60_000,
    exchangePerIp: clampInt(process.env.DEVICE_LOGIN_EXCHANGE_LIMIT, 20, 1, 500),
    exchangeWindowMs: 60_000,
    lookupPerIp: 20,
    lookupWindowMs: 60_000,
    refreshPerIp: 30,
    refreshWindowMs: 60_000
  }
};

if (!config.secret) {
  console.warn(
    "[Auth] WON_AUTH_SECRET / AUTH_TOKEN_SECRET is unset. Using a per-process secret (dev only): " +
      "codes and sessions will not survive a restart."
  );
  config.secret = randomBytes(32).toString("hex");
}

const ALLOWED_PLATFORMS = new Set(["android", "ios", "desktop", "web"]);

export const DEVICE_LOGIN_STATUS = Object.freeze({
  PENDING: "pending",
  APPROVED: "approved",
  USED: "used",
  EXPIRED: "expired",
  CANCELLED: "cancelled"
});

// ---------------------------------------------------------------------------
// Privy
// ---------------------------------------------------------------------------

let privyClient = null;

function getPrivyClient() {
  if (privyClient) return privyClient;
  const appId = process.env.PRIVY_APP_ID || "";
  const appSecret = process.env.PRIVY_APP_SECRET || "";
  if (!appId || !appSecret) return null;

  privyClient = new PrivyClient({
    appId,
    appSecret,
    // Optional: copy "Configuration > App settings > JWT verification key" from
    // the Privy dashboard to skip an API round-trip per verification.
    ...(process.env.PRIVY_JWT_VERIFICATION_KEY
      ? { jwtVerificationKey: process.env.PRIVY_JWT_VERIFICATION_KEY }
      : {})
  });
  return privyClient;
}

/**
 * Verifies a Privy access token using the official Privy server SDK.
 *
 * Returns the verified claims, or a failure. There is intentionally no
 * "trust the caller" path: if Privy cannot verify, the request is unauthorized.
 */
export async function verifyPrivyAccessToken(accessToken) {
  const client = getPrivyClient();
  if (!client) {
    console.error("[Auth] PRIVY_APP_ID / PRIVY_APP_SECRET missing -- refusing to trust this request.");
    return { ok: false, error: "privy_not_configured" };
  }

  try {
    // The public SDK helper takes the raw token string and returns snake_case
    // claims. Passing an object here (or reading camelCase fields below) makes
    // jose reject the input and surfaces as "Failed to verify authentication token".
    const claims = await client.utils().auth().verifyAccessToken(accessToken);
    if (!claims?.user_id) {
      return { ok: false, error: "missing_subject" };
    }
    return {
      ok: true,
      claims: {
        userId: claims.user_id,
        appId: claims.app_id,
        issuer: claims.issuer,
        sessionId: claims.session_id,
        issuedAt: claims.issued_at,
        expiration: claims.expiration
      }
    };
  } catch (error) {
    console.warn("[Auth] Privy access token verification failed:", error?.message || error);
    return { ok: false, error: "verification_failed" };
  }
}

/**
 * Normalizes the Privy `User` object returned by `users()._get()` into the
 * camelCase shape this service uses. The SDK resolves the user object directly
 * (no `{ user }` envelope) and every field is snake_case, e.g. `linked_accounts`
 * and each wallet's `chain_type`. Exported so the parsing can be unit-tested
 * without touching Privy.
 */
export function normalizePrivyUser(raw) {
  if (!raw) return null;
  const accounts = Array.isArray(raw.linked_accounts)
    ? raw.linked_accounts
    : Array.isArray(raw.linkedAccounts)
      ? raw.linkedAccounts
      : [];
  const pick = (entry, snake, camel) => entry?.[snake] ?? entry?.[camel];
  const walletFor = (chainType) =>
    accounts.find(
      (entry) => entry?.type === "wallet" && (chainType === null || pick(entry, "chain_type", "chainType") === chainType)
    );
  const profilePicture = (entry) => {
    const value = pick(entry, "profile_picture_url", "profilePictureUrl");
    return typeof value === "string" && value ? value : "";
  };
  return {
    id: raw.id || "",
    walletAddress: walletFor("ethereum")?.address || "",
    solanaAddress: walletFor("solana")?.address || "",
    linkedAccounts: accounts,
    profilePictureUrl: accounts.map(profilePicture).find(Boolean) || ""
  };
}

/**
 * Server-side fetch of the Privy user object for a verified DID.
 * Identity data is read from Privy, never from the HTTP request body.
 */
export async function fetchPrivyUser(privyUserId) {
  const client = getPrivyClient();
  if (!client || !privyUserId) return null;
  try {
    // `users()._get()` resolves to the Privy user object itself, not `{ user }`.
    const raw = await client.users()._get(privyUserId);
    return normalizePrivyUser(raw);
  } catch (error) {
    console.warn("[Auth] Privy user lookup failed:", error?.message || error);
    return null;
  }
}

// ---------------------------------------------------------------------------
// Device login lifecycle
// ---------------------------------------------------------------------------

/**
 * POST /auth/device/start
 *
 * Mints a pending device login: a short human code for the web approval page
 * plus a high-entropy secret the native client must present at exchange time.
 * The 6-character code is NOT a credential -- it only addresses the page.
 */
export async function startDeviceLogin({ ip, platform, deviceId, deviceLabel } = {}) {
  const byIp = checkRateLimit(`start:ip:${ip}`, config.rateLimits.startPerIp, config.rateLimits.startWindowMs);
  if (!byIp.allowed) return tooManyRequests(byIp);

  if (deviceId) {
    const byDevice = checkRateLimit(
      `start:device:${sanitizeShort(deviceId, 64)}`,
      config.rateLimits.startPerDevice,
      config.rateLimits.startWindowMs
    );
    if (!byDevice.allowed) return tooManyRequests(byDevice);
  }

  const deviceLoginId = `dl_${randomToken(16)}`;
  const code = generateHumanCode();
  const secret = randomToken(32);
  const createdAt = Date.now();
  const expiresAt = createdAt + config.deviceLoginTtlSeconds * 1000;

  await createDeviceLogin({
    device_login_id: deviceLoginId,
    // Digests only -- an RTDB dump is not a list of usable credentials.
    code_hash: digestWithPepper(code),
    secret_hash: sha256(secret),
    status: DEVICE_LOGIN_STATUS.PENDING,
    created_at: createdAt,
    expires_at: expiresAt,
    approved_at: null,
    used_at: null,
    platform: ALLOWED_PLATFORMS.has(platform) ? platform : "desktop",
    device_id: sanitizeShort(deviceId, 64),
    device_label: sanitizeShort(deviceLabel, 64),
    // Abuse signal only; never returned to the web page.
    request_ip_hash: ip ? digestWithPepper(ip) : null,
    user_id: null,
    privy_user_id: null,
    username: null,
    wallet_address: null
  });

  return {
    ok: true,
    status: 201,
    payload: {
      device_login_id: deviceLoginId,
      // Half of the device credential, shown to nobody but the asking client.
      secret,
      code,
      code_display: formatCode(code),
      auth_url: `${config.webAuthBaseUrl}/auth?code=${encodeURIComponent(code)}`,
      expires_in: config.deviceLoginTtlSeconds,
      expires_at: new Date(expiresAt).toISOString(),
      poll_interval_ms: config.pollIntervalMs
    }
  };
}

/**
 * GET /auth/device/status?device_login_id=...
 *
 * Polled by the native client. Reveals only whether the ticket can still be
 * exchanged -- never who approved it.
 */
export async function getDeviceLoginStatus({ deviceLoginId } = {}) {
  if (!isDeviceLoginId(deviceLoginId)) {
    return { ok: false, status: 400, error: "invalid_device_login_id" };
  }

  const record = await getDeviceLogin(String(deviceLoginId));
  if (!record) {
    return { ok: false, status: 404, error: "device_login_not_found" };
  }

  const status = resolveStatus(record);
  return {
    ok: true,
    status: 200,
    payload: {
      status,
      // Derived from the server clock so a tampered client clock cannot extend
      // a login by polling.
      poll_interval_ms: status === DEVICE_LOGIN_STATUS.PENDING ? config.pollIntervalMs : 0,
      expires_at: new Date(Number(record.expires_at)).toISOString(),
      expires_in_seconds: Math.max(0, Math.ceil((Number(record.expires_at) - Date.now()) / 1000))
    }
  };
}

/**
 * GET /auth/device/lookup?code=...
 *
 * Backs the web approval page so it can render "Android device wants to connect
 * / code KJI-FYE" before the user has signed in. Read-only, rate limited, and
 * it returns no user information.
 */
export async function lookupDeviceLogin({ code, ip } = {}) {
  const limit = checkRateLimit(`lookup:ip:${ip}`, config.rateLimits.lookupPerIp, config.rateLimits.lookupWindowMs);
  if (!limit.allowed) return tooManyRequests(limit);

  const normalized = normalizeCode(code);
  if (!normalized) return { ok: false, status: 400, error: "invalid_code" };

  const deviceLoginId = await getDeviceLoginIdByCodeHash(digestWithPepper(normalized));
  if (!deviceLoginId) return { ok: false, status: 404, error: "invalid_code" };

  const record = await getDeviceLogin(deviceLoginId);
  if (!record) return { ok: false, status: 404, error: "invalid_code" };

  const status = resolveStatus(record);
  if (status === DEVICE_LOGIN_STATUS.USED) {
    return { ok: false, status: 410, error: "device_login_already_used" };
  }
  if (status !== DEVICE_LOGIN_STATUS.PENDING && status !== DEVICE_LOGIN_STATUS.APPROVED) {
    return {
      ok: false,
      status: 410,
      error: status === DEVICE_LOGIN_STATUS.EXPIRED ? "device_login_expired" : "device_login_cancelled"
    };
  }

  return {
    ok: true,
    status: 200,
    payload: {
      device_login_id: record.device_login_id,
      code_display: formatCode(normalized),
      platform: record.platform || "desktop",
      device_label: record.device_label || "",
      status,
      expires_at: new Date(Number(record.expires_at)).toISOString(),
      expires_in_seconds: Math.max(0, Math.ceil((Number(record.expires_at) - Date.now()) / 1000)),
      // An already-bound ticket must never be re-pointed at another account.
      bound: Boolean(record.user_id)
    }
  };
}

/**
 * POST /auth/device/approve
 * Authorization: Bearer <Privy access token>
 * Body: { device_login_id }  -- or { code } for the web flow
 *
 * Identity comes exclusively from the verified Privy token. A `user_id` in the
 * body is never read; there is no code path that accepts client-supplied
 * identity.
 */
export async function approveDeviceLogin({ authorizationHeader, deviceLoginId, code } = {}) {
  const accessToken = extractBearer(authorizationHeader);
  if (!accessToken) {
    return { ok: false, status: 401, error: "missing_privy_access_token" };
  }

  const verified = await verifyPrivyAccessToken(accessToken);
  if (!verified.ok) {
    // Opaque on purpose: the caller must not be able to distinguish "expired"
    // from "signed for a different app".
    return { ok: false, status: 401, error: "invalid_privy_access_token" };
  }

  const limit = checkRateLimit(
    `approve:user:${verified.claims.userId}`,
    config.rateLimits.approvePerUser,
    config.rateLimits.approveWindowMs
  );
  if (!limit.allowed) return tooManyRequests(limit);

  const resolvedId = deviceLoginId ? String(deviceLoginId) : await resolveDeviceLoginIdByCode(code);
  if (!resolvedId) {
    return { ok: false, status: 400, error: "device_login_id_or_code_required" };
  }

  const result = await approveDeviceLoginById({
    deviceLoginId: resolvedId,
    privyUserId: verified.claims.userId
  });
  if (!result.ok) return result;

  return {
    ok: true,
    status: 200,
    payload: {
      approved: true,
      device_login_id: result.device.device_login_id,
      platform: result.device.platform,
      user: result.device.user
    }
  };
}

/**
 * POST /auth/device/cancel
 *
 * Lets the native client invalidate its own ticket so a code left on a lost
 * phone (or in a screenshot) cannot be approved later.
 */
export async function cancelDeviceLogin({ deviceLoginId, secret } = {}) {
  const verified = await verifyDeviceLoginSecret(deviceLoginId, secret);
  if (!verified.ok) return verified.error;

  const status = resolveStatus(verified.record);
  if (status !== DEVICE_LOGIN_STATUS.PENDING && status !== DEVICE_LOGIN_STATUS.APPROVED) {
    return { ok: false, status: 409, error: "device_login_not_cancellable" };
  }

  // Mark first, then purge: the status write is what makes a concurrent
  // exchange fail even if the delete has not landed yet.
  await updateDeviceLogin(String(deviceLoginId), { status: DEVICE_LOGIN_STATUS.CANCELLED });
  await deleteDeviceLogin(String(deviceLoginId));
  return { ok: true, status: 200, payload: { cancelled: true } };
}

/**
 * POST /auth/device/exchange
 *
 * The only place a WON native session is minted. Single use: the ticket is
 * burned inside this call, so a captured (device_login_id, secret) pair is
 * worthless from the next request onwards.
 */
export async function exchangeDeviceLogin({ deviceLoginId, secret, platform, deviceId, ip } = {}) {
  const limit = checkRateLimit(`exchange:ip:${ip}`, config.rateLimits.exchangePerIp, config.rateLimits.exchangeWindowMs);
  if (!limit.allowed) return tooManyRequests(limit);

  const verified = await verifyDeviceLoginSecret(deviceLoginId, secret);
  if (!verified.ok) return verified.error;

  const record = verified.record;
  const status = resolveStatus(record);

  if (status !== DEVICE_LOGIN_STATUS.APPROVED) {
    return { ok: false, status: 409, error: `device_login_${status}` };
  }
  if (!record.user_id) {
    // Defensive: an approved ticket must always carry an identity.
    return { ok: false, status: 409, error: "device_login_unbound" };
  }
  if (record.device_id && deviceId && record.device_id !== sanitizeShort(deviceId, 64)) {
    return { ok: false, status: 403, error: "device_mismatch" };
  }

  // Burn the ticket. Overwriting the digests means even a stale read of the
  // record cannot be exchanged, and deleting the code index stops the code from
  // being approved by a different account afterwards.
  await updateDeviceLogin(String(deviceLoginId), {
    status: DEVICE_LOGIN_STATUS.USED,
    used_at: Date.now(),
    secret_hash: sha256(randomToken(32)),
    code_hash: ""
  });
  await deleteDeviceLogin(String(deviceLoginId));

  const session = await issueNativeSession({
    user_id: record.user_id,
    username: record.username,
    privy_user_id: record.privy_user_id,
    wallet_address: record.wallet_address,
    device_login_id: String(deviceLoginId),
    platform: ALLOWED_PLATFORMS.has(platform) ? platform : record.platform,
    device_id: sanitizeShort(deviceId, 64) || record.device_id
  });

  return {
    ok: true,
    status: 200,
    payload: {
      access_token: session.access_token,
      refresh_token: session.refresh_token,
      token_type: "Bearer",
      token_expires_in: config.accessTokenTtlSeconds,
      expires_in: config.accessTokenTtlSeconds,
      user: session.user
    }
  };
}

// ---------------------------------------------------------------------------
// Session lifecycle
// ---------------------------------------------------------------------------

/**
 * POST /auth/refresh
 *
 * Refresh tokens rotate: the presented token is revoked and replaced. A stolen
 * refresh token therefore stops working the moment the legitimate client next
 * refreshes.
 */
export async function refreshSession({ refreshToken, deviceId, ip } = {}) {
  if (!refreshToken) {
    return { ok: false, status: 400, error: "refresh_token_required" };
  }

  const limit = checkRateLimit(`refresh:ip:${ip}`, config.rateLimits.refreshPerIp, config.rateLimits.refreshWindowMs);
  if (!limit.allowed) return tooManyRequests(limit);

  const sessionId = await getNativeSessionIdByRefreshHash(sha256(refreshToken));
  if (!sessionId) {
    return { ok: false, status: 401, error: "invalid_refresh_token" };
  }

  const session = await getNativeSession(sessionId);
  if (!session || session.revoked_at || !session.refresh_token_hash) {
    return { ok: false, status: 401, error: "invalid_refresh_token" };
  }
  if (!safeEquals(session.refresh_token_hash, sha256(refreshToken))) {
    return { ok: false, status: 401, error: "invalid_refresh_token" };
  }
  if (Number(session.refresh_expires_at) <= Date.now()) {
    await revokeNativeSession(sessionId);
    return { ok: false, status: 401, error: "refresh_token_expired" };
  }
  if (session.device_id && deviceId && session.device_id !== sanitizeShort(deviceId, 64)) {
    return { ok: false, status: 403, error: "device_mismatch" };
  }

  // Revoke the *superseded* token pair first, so the write below lands on a
  // clean row. Writing the rotation first and revoking afterwards would blank
  // out the very digests that were just written (revoke clears
  // access_token_hash / refresh_token_hash), leaving the client holding tokens
  // the server has already forgotten.
  await revokeNativeSession(sessionId);

  // Reuse the session row so a refresh does not multiply rows per install.
  const rotated = await issueNativeSession(
    {
      user_id: session.user_id,
      username: session.username,
      privy_user_id: session.privy_user_id,
      wallet_address: session.user?.wallet_address || session.wallet_address,
      device_login_id: session.device_login_id,
      platform: session.platform,
      device_id: session.device_id
    },
    { sessionId }
  );

  return {
    ok: true,
    status: 200,
    payload: {
      access_token: rotated.access_token,
      refresh_token: rotated.refresh_token,
      token_type: "Bearer",
      token_expires_in: config.accessTokenTtlSeconds,
      expires_in: config.accessTokenTtlSeconds,
      user: rotated.user
    }
  };
}

/**
 * POST /auth/logout
 *
 * Best effort local revoke. Clients must still drop their stored copy, and a
 * logout that fails offline must not wedge the UI.
 */
export async function logoutSession({ refreshToken } = {}) {
  if (refreshToken) {
    const sessionId = await getNativeSessionIdByRefreshHash(sha256(refreshToken));
    if (sessionId) {
      const session = await getNativeSession(sessionId);
      if (session && safeEquals(session.refresh_token_hash || "", sha256(refreshToken))) {
        await revokeNativeSession(sessionId);
      }
    }
  }
  return { ok: true, status: 200, payload: { logged_out: true } };
}

/**
 * GET /auth/me  (Authorization: Bearer <WON access token>)
 *
 * Cheap session validation for native cold starts.
 */
export async function getAuthenticatedSession({ authorizationHeader } = {}) {
  const accessToken = extractBearer(authorizationHeader);
  if (!accessToken) {
    return { ok: false, status: 401, error: "missing_access_token" };
  }

  const sessionId = await getNativeSessionIdByAccessHash(sha256(accessToken));
  if (!sessionId) {
    return { ok: false, status: 401, error: "invalid_access_token" };
  }

  const session = await getNativeSession(sessionId);
  if (!session || session.revoked_at) {
    return { ok: false, status: 401, error: "invalid_access_token" };
  }
  if (Number(session.access_expires_at) <= Date.now()) {
    return { ok: false, status: 401, error: "access_token_expired" };
  }

  await updateNativeSession(sessionId, { last_used_at: Date.now() });
  return {
    ok: true,
    status: 200,
    payload: {
      user: session.user,
      expires_in: Math.max(0, Math.floor((Number(session.access_expires_at) - Date.now()) / 1000))
    }
  };
}

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

async function approveDeviceLoginById({ deviceLoginId, privyUserId }) {
  const record = await getDeviceLogin(deviceLoginId);
  if (!record) return { ok: false, status: 404, error: "device_login_not_found" };

  const status = resolveStatus(record);

  // Re-clicking Approve for the same account is idempotent.
  if (status === DEVICE_LOGIN_STATUS.APPROVED && record.privy_user_id === privyUserId) {
    return {
      ok: true,
      device: {
        device_login_id: deviceLoginId,
        platform: record.platform,
        user: buildUserPayload(record)
      }
    };
  }
  if (status !== DEVICE_LOGIN_STATUS.PENDING) {
    return { ok: false, status: 409, error: `device_login_${status}` };
  }
  if (record.privy_user_id && record.privy_user_id !== privyUserId) {
    return { ok: false, status: 409, error: "device_login_already_bound" };
  }

  const privyUser = await fetchPrivyUser(privyUserId);
  if (!privyUser) {
    return { ok: false, status: 502, error: "privy_user_lookup_failed" };
  }

  // Privy identity -> WON account. This is the only mapping step, and its only
  // input is the verified DID.
  const wonUser = await resolveWonUser(privyUserId, privyUser);

  await updateDeviceLogin(deviceLoginId, {
    status: DEVICE_LOGIN_STATUS.APPROVED,
    approved_at: Date.now(),
    user_id: wonUser.user_id,
    username: wonUser.username,
    privy_user_id: privyUserId,
    wallet_address: privyUser.walletAddress || null
  });

  return {
    ok: true,
    device: {
      device_login_id: deviceLoginId,
      platform: record.platform,
      user: {
        id: wonUser.user_id,
        username: wonUser.username,
        privy_user_id: privyUserId,
        wallet_address: privyUser.walletAddress || ""
      }
    }
  };
}

function buildUserPayload(record) {
  return {
    id: record.user_id,
    username: record.username || "",
    privy_user_id: record.privy_user_id || "",
    wallet_address: record.wallet_address || ""
  };
}

async function issueNativeSession(
  { user_id, username, privy_user_id, wallet_address, device_login_id, platform, device_id },
  opts = {}
) {
  const sessionId = opts.sessionId || `ns_${randomToken(16)}`;
  const accessToken = randomToken(32);
  const refreshToken = randomToken(32);
  const createdAt = Date.now();

  // Opaque random tokens stored as digests. No signing key to leak, and a
  // stolen RTDB read yields nothing usable.
  const record = {
    session_id: sessionId,
    user_id,
    username: username || "",
    privy_user_id: privy_user_id || "",
    device_login_id: device_login_id || null,
    platform: platform || "desktop",
    device_id: device_id || "",
    access_token_hash: sha256(accessToken),
    access_expires_at: createdAt + config.accessTokenTtlSeconds * 1000,
    refresh_token_hash: sha256(refreshToken),
    refresh_expires_at: createdAt + config.refreshTokenTtlSeconds * 1000,
    created_at: createdAt,
    last_used_at: createdAt,
    revoked_at: null,
    user: {
      id: user_id,
      username: username || "",
      privy_user_id: privy_user_id || "",
      wallet_address: wallet_address || ""
    }
  };

  await createNativeSession(record);
  return {
    session_id: sessionId,
    access_token: accessToken,
    refresh_token: refreshToken,
    user: record.user
  };
}

async function resolveDeviceLoginIdByCode(code) {
  const normalized = normalizeCode(code);
  if (!normalized) return null;
  return getDeviceLoginIdByCodeHash(digestWithPepper(normalized));
}

async function verifyDeviceLoginSecret(deviceLoginId, secret) {
  if (!isDeviceLoginId(deviceLoginId) || typeof secret !== "string" || secret.length < 16) {
    return { ok: false, error: { ok: false, status: 400, error: "device_login_credentials_required" } };
  }
  const record = await getDeviceLogin(String(deviceLoginId));
  if (!record || !record.secret_hash) {
    return { ok: false, error: { ok: false, status: 404, error: "device_login_not_found" } };
  }
  if (!safeEquals(record.secret_hash, sha256(secret))) {
    return { ok: false, error: { ok: false, status: 403, error: "invalid_device_secret" } };
  }
  return { ok: true, record };
}

/**
 * Server-side view of a ticket's status. `approved` still expires on the clock
 * if it was never redeemed; `used` and `cancelled` keep their terminal meaning.
 */
function resolveStatus(record) {
  if (!record) return DEVICE_LOGIN_STATUS.EXPIRED;
  const status = record.status;
  if (status !== DEVICE_LOGIN_STATUS.PENDING && status !== DEVICE_LOGIN_STATUS.APPROVED) {
    return status;
  }
  if (Number(record.expires_at) <= Date.now()) {
    return DEVICE_LOGIN_STATUS.EXPIRED;
  }
  return status;
}

function isDeviceLoginId(value) {
  return typeof value === "string" && /^dl_[a-f0-9]{32}$/.test(value);
}

function generateHumanCode() {
  const length = 6;
  const limit = CODE_ALPHABET.length;
  // Rejection sampling: a plain `byte % 36` is biased because 256 % 36 != 0,
  // which would make four characters measurably more likely in every code.
  const maxUnbiased = Math.floor(256 / limit) * limit;
  let out = "";
  while (out.length < length) {
    for (const byte of randomBytes(length * 2)) {
      if (byte >= maxUnbiased) continue;
      out += CODE_ALPHABET[byte % limit];
      if (out.length === length) break;
    }
  }
  return out;
}

function formatCode(code) {
  const value = String(code || "");
  return value.length === 6 ? `${value.slice(0, 3)}-${value.slice(3)}` : value;
}

function normalizeCode(code) {
  const cleaned = String(code || "")
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "");
  if (cleaned.length !== 6) return null;
  for (const char of cleaned) {
    if (!CODE_ALPHABET.includes(char)) return null;
  }
  return cleaned;
}

function randomToken(bytes) {
  return randomBytes(bytes).toString("hex");
}

function sha256(value) {
  return createHash("sha256").update(String(value)).digest("hex");
}

function digestWithPepper(value) {
  return createHmac("sha256", config.secret).update(String(value)).digest("hex");
}

function safeEquals(a, b) {
  const left = String(a || "");
  const right = String(b || "");
  if (!left || !right || left.length !== right.length) return false;
  try {
    return timingSafeEqual(Buffer.from(left, "utf8"), Buffer.from(right, "utf8"));
  } catch {
    return false;
  }
}

function extractBearer(header) {
  const match = String(header || "").match(/^Bearer\s+(.+)$/i);
  return match ? match[1].trim() : "";
}

function tooManyRequests(limit) {
  return { ok: false, status: 429, error: "too_many_requests", retry_after: limit.retryAfterSeconds };
}

const rateBuckets = new Map();

function checkRateLimit(key, max, windowMs) {
  const now = Date.now();
  const bucket = rateBuckets.get(key);
  if (!bucket || now - bucket.start > windowMs) {
    rateBuckets.set(key, { start: now, count: 1 });
    if (rateBuckets.size > 5000) pruneRateBuckets(now, windowMs);
    return { allowed: true, retryAfterSeconds: 0 };
  }
  bucket.count += 1;
  if (bucket.count > max) {
    return { allowed: false, retryAfterSeconds: Math.max(1, Math.ceil((bucket.start + windowMs - now) / 1000)) };
  }
  return { allowed: true, retryAfterSeconds: 0 };
}

function pruneRateBuckets(now, windowMs) {
  for (const [key, bucket] of rateBuckets) {
    if (now - bucket.start > windowMs) rateBuckets.delete(key);
  }
}

function sanitizeShort(value, max) {
  if (typeof value !== "string") return "";
  return value.trim().replace(/[^A-Za-z0-9_.:@ -]/g, "").slice(0, max);
}

function clampInt(raw, fallback, min, max) {
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(max, Math.max(min, parsed));
}

export const authInternals = { config, generateHumanCode, normalizeCode, formatCode, digestWithPepper, sha256, resolveStatus };