/**
 * Firebase RTDB persistence for the native device-login flow.
 *
 * Everything the native (Godot) client authenticates with lives here. The rules
 * that shaped this file:
 *
 *   - Nothing that can be replayed as a credential is ever stored in plaintext.
 *     The human-readable code, the device secret, and both session tokens are
 *     stored as SHA-256/HMAC digests only. A dump of the RTDB is therefore not a
 *     list of usable credentials.
 *   - The stable game identity (`wonUserId`) is an immutable id minted by the
 *     backend. The existing `users/{username}` records keep working as they are
 *     (roles, xp, equippedSkinId, rewards...), we only add the id to them so web
 *     and native players share ONE account instead of forking per platform.
 */

import { ref, get, set, update, remove } from "firebase/database";
import { db } from "./firebaseClient.js";

const DEVICE_LOGINS_PATH = "device_logins";
const DEVICE_CODE_INDEX_PATH = "device_login_codes";
const NATIVE_SESSIONS_PATH = "native_sessions";
const NATIVE_REFRESH_INDEX_PATH = "native_refresh_index";
const NATIVE_ACCESS_INDEX_PATH = "native_access_index";
const WON_USER_INDEX_PATH = "won_user_index";

function nowMs() {
  return Date.now();
}

// ---------------------------------------------------------------------------
// Device logins
// ---------------------------------------------------------------------------

/**
 * @param {object} record fully-formed device_login record (already hashed)
 */
export async function createDeviceLogin(record) {
  const id = String(record.device_login_id || "");
  if (!id) throw new Error("createDeviceLogin requires device_login_id");
  await set(ref(db, `${DEVICE_LOGINS_PATH}/${id}`), record);

  // Secondary index so the web approval page can resolve a typed-in code in one
  // read. Keyed by the code *digest*, never the code itself.
  if (record.code_hash) {
    await set(ref(db, `${DEVICE_CODE_INDEX_PATH}/${record.code_hash}`), id);
  }
  return record;
}

export async function getDeviceLogin(deviceLoginId) {
  if (!deviceLoginId) return null;
  const snapshot = await get(ref(db, `${DEVICE_LOGINS_PATH}/${deviceLoginId}`));
  return snapshot.exists() ? snapshot.val() : null;
}

export async function getDeviceLoginIdByCodeHash(codeHash) {
  if (!codeHash) return null;
  const snapshot = await get(ref(db, `${DEVICE_CODE_INDEX_PATH}/${codeHash}`));
  return snapshot.exists() ? snapshot.val() : null;
}

export async function updateDeviceLogin(deviceLoginId, patch) {
  if (!deviceLoginId) return null;
  const refPath = ref(db, `${DEVICE_LOGINS_PATH}/${deviceLoginId}`);
  const payload = { ...patch, updated_at: nowMs() };
  await update(refPath, payload);
  return payload;
}

export async function deleteDeviceLogin(deviceLoginId) {
  if (!deviceLoginId) return;
  const record = await getDeviceLogin(deviceLoginId);
  await remove(ref(db, `${DEVICE_LOGINS_PATH}/${deviceLoginId}`));
  if (record?.code_hash) {
    await remove(ref(db, `${DEVICE_CODE_INDEX_PATH}/${record.code_hash}`));
  }
}

// ---------------------------------------------------------------------------
// Native sessions
// ---------------------------------------------------------------------------

/**
 * Native sessions are stored per access token *and* per refresh token so both
 * lookups are O(1) single reads. `refresh_token_hash` is the searchable key
 * because the refresh token is what a cold-starting client presents first.
 */
export async function createNativeSession(session) {
  const sessionId = String(session.session_id || "");
  if (!sessionId) throw new Error("createNativeSession requires session_id");
  await set(ref(db, `${NATIVE_SESSIONS_PATH}/${sessionId}`), session);
  if (session.refresh_token_hash) {
    await set(ref(db, `${NATIVE_REFRESH_INDEX_PATH}/${session.refresh_token_hash}`), sessionId);
  }
  if (session.access_token_hash) {
    await set(ref(db, `${NATIVE_ACCESS_INDEX_PATH}/${session.access_token_hash}`), sessionId);
  }
  return session;
}

/**
 * Access tokens are indexed by digest too, so `/auth/me` is a single read
 * instead of a scan over every live session.
 */
export async function getNativeSessionIdByAccessHash(accessHash) {
  if (!accessHash) return null;
  const snapshot = await get(ref(db, `${NATIVE_ACCESS_INDEX_PATH}/${accessHash}`));
  return snapshot.exists() ? snapshot.val() : null;
}

export async function getNativeSession(sessionId) {
  if (!sessionId) return null;
  const snapshot = await get(ref(db, `${NATIVE_SESSIONS_PATH}/${sessionId}`));
  return snapshot.exists() ? snapshot.val() : null;
}

export async function getNativeSessionIdByRefreshHash(refreshHash) {
  if (!refreshHash) return null;
  const snapshot = await get(ref(db, `${NATIVE_REFRESH_INDEX_PATH}/${refreshHash}`));
  return snapshot.exists() ? snapshot.val() : null;
}

export async function updateNativeSession(sessionId, patch) {
  if (!sessionId) return null;
  const refPath = ref(db, `${NATIVE_SESSIONS_PATH}/${sessionId}`);
  await update(refPath, patch);
  return patch;
}

export async function revokeNativeSession(sessionId) {
  if (!sessionId) return;
  const session = await getNativeSession(sessionId);
  await update(ref(db, `${NATIVE_SESSIONS_PATH}/${sessionId}`), {
    revoked_at: nowMs(),
    access_token_hash: "",
    refresh_token_hash: ""
  });
  if (session?.refresh_token_hash) {
    await remove(ref(db, `${NATIVE_REFRESH_INDEX_PATH}/${session.refresh_token_hash}`));
  }
  if (session?.access_token_hash) {
    await remove(ref(db, `${NATIVE_ACCESS_INDEX_PATH}/${session.access_token_hash}`));
  }
}

// ---------------------------------------------------------------------------
// Stable WON user ids
// ---------------------------------------------------------------------------

/**
 * Resolves (and if needed creates) the immutable WON account for a verified
 * Privy identity.
 *
 * This is the ONLY place that decides who a Privy user is on WON. It is called
 * with the DID taken from a server-verified Privy access token -- never with
 * anything the client sent in the request body.
 *
 * @param {string} privyUserId  verified Privy DID
 * @param {object} privyUser    user object fetched server-side from Privy
 */
export async function resolveWonUser(privyUserId, privyUser) {
  const indexRef = ref(db, `${WON_USER_INDEX_PATH}/${privyUserId}`);
  const indexSnapshot = await get(indexRef);

  if (indexSnapshot.exists()) {
    const existing = indexSnapshot.val();
    const username = existing.username;
    // Keep the mutable parts (wallet/avatar) fresh without touching anything
    // gameplay owns such as roles, xp or the equipped skin.
    const patch = { last_login_at: new Date().toISOString() };
    if (privyUser?.walletAddress) patch.eth_address = privyUser.walletAddress;
    await update(ref(db, `users/${username}`), patch);
    await update(indexRef, {
      privy_user_id: privyUserId,
      username,
      wallet_address: privyUser?.walletAddress || existing.wallet_address || "",
      last_login_at: patch.last_login_at
    });
    return {
      user_id: existing.user_id,
      username,
      privy_user_id: privyUserId,
      created: false
    };
  }

  // First time this Privy identity has touched WON. Mint the immutable id and
  // anchor it to the username the *rest of the stack already uses* (Privy social
  // handle, else wallet address) so the web build keeps finding this profile.
  const username = deriveUsername(privyUser);
  const userId = `won_${randomId(12)}`;

  const createdAt = new Date().toISOString();
  const userRef = ref(db, `users/${username}`);
  const userSnapshot = await get(userRef);
  const existingProfile = userSnapshot.exists() ? userSnapshot.val() || {} : {};

  // `update` (not `set`) so a returning web player keeps xp/roles/equippedSkin.
  await update(userRef, {
    wonUserId: userId,
    privyId: privyUserId,
    ...(privyUser?.walletAddress ? { ethAddress: privyUser.walletAddress } : {}),
    lastLogin: createdAt
  });

  await set(indexRef, {
    user_id: userId,
    privy_user_id: privyUserId,
    username,
    wallet_address: privyUser?.walletAddress || existingProfile.ethAddress || "",
    created_at: existingProfile.createdAt || createdAt,
    last_login_at: createdAt
  });

  return { user_id: userId, username, privy_user_id: privyUserId, created: true };
}

/**
 * Re-implements the frontend's `getUsernameFromPrivy()` (frontend/src/pages/
 * firebaseClient.js) so both platforms land on the same Firebase user record.
 * Kept deliberately identical -- changing one without the other would split a
 * player's account in two, which is the exact thing this flow must avoid.
 */
export function deriveUsername(privyUser) {
  const accounts = Array.isArray(privyUser?.linkedAccounts) ? privyUser.linkedAccounts : [];

  const providers = [
    { type: "twitter_oauth", field: "username" },
    { type: "farcaster", field: "username" },
    { type: "google_oauth", field: "name" },
    { type: "twitch_oauth", field: "username" },
    { type: "tiktok_oauth", field: "username" },
    { type: "spotify_oauth", field: "name" }
  ];

  for (const provider of providers) {
    const account = accounts.find((entry) => entry?.type === provider.type);
    const value = account?.[provider.field];
    if (typeof value === "string" && value.trim()) {
      return sanitizeUsername(value);
    }
  }

  const ethWallet = accounts.find((entry) => entry?.type === "wallet" && entry?.chainType === "ethereum");
  if (ethWallet?.address) return sanitizeUsername(ethWallet.address);

  const solWallet = accounts.find((entry) => entry?.type === "wallet" && entry?.chainType === "solana");
  if (solWallet?.address) return sanitizeUsername(solWallet.address);

  return `won-${randomId(8)}`;
}

function sanitizeUsername(value) {
  const cleaned = String(value).trim().slice(0, 24);
  return cleaned.replace(/[.#$/[\]]/g, "_") || `won-${randomId(8)}`;
}

function randomId(bytes) {
  const buffer = new Uint8Array(bytes);
  globalThis.crypto.getRandomValues(buffer);
  return Array.from(buffer, (byte) => byte.toString(16).padStart(2, "0")).join("");
}