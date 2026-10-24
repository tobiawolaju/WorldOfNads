/**
 * Chog Genesis NFT ownership gate.
 *
 * The CHOG reveal/power-up in a CHOG room is only allowed for a player whose
 * authenticated wallet holds at least one Chog Genesis NFT on Monad *mainnet*.
 * This module is deliberately dependency-free (no ethers, no Privy SDK) so it
 * can be unit-tested without the deployment dependencies installed:
 *
 *   - the wallet address always comes from a caller-supplied `authenticate`
 *     callback, which `index.js` wires to the existing WON session / Privy
 *     verification. A client-supplied address is never trusted;
 *   - the chain is verified with `eth_chainId` and must be Monad mainnet (143)
 *     regardless of the game's testnet configuration;
 *   - `balanceOf(address)` is read with a plain JSON-RPC `eth_call`;
 *   - every RPC failure is an error, never "no NFT" and never "owns NFT";
 *   - results are cached per lower-cased wallet address (never across wallets)
 *     for a short TTL, and requests are rate limited per authenticated identity.
 *
 * Contract address and network were verified against Monad mainnet:
 *   chain id 143, name "Chog Genesis", symbol "CHOG", totalSupply 1969.
 *
 * Environment:
 *   MONAD_MAINNET_RPC_URL          mainnet JSON-RPC (default https://rpc.monad.xyz)
 *   CHOG_GENESIS_CONTRACT_ADDRESS  defaults to the verified collection below
 *   CHOG_NFT_CACHE_TTL_MS          ownership cache TTL (default 300000)
 *   CHOG_NFT_RPC_TIMEOUT_MS        per-request RPC timeout (default 8000)
 */

export const CHOG_GENESIS_CHAIN_ID = 143;
export const CHOG_GENESIS_CONTRACT = "0xc96d31f8626c6d03fae5dcd3d61e3fb9f4a73763";
export const DEFAULT_MONAD_MAINNET_RPC_URL = "https://rpc.monad.xyz";
export const BALANCE_OF_SELECTOR = "0x70a08231";

export const DEFAULT_CACHE_TTL_MS = 5 * 60 * 1000;
export const DEFAULT_RPC_TIMEOUT_MS = 8 * 1000;
export const DEFAULT_RATE_LIMIT_MAX = 20;
export const DEFAULT_RATE_LIMIT_WINDOW_MS = 60 * 1000;

function positiveInt(value, fallback) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? Math.floor(parsed) : fallback;
}

/** True for a 20-byte hex EVM address. Case is irrelevant on EVM. */
export function isValidWalletAddress(value) {
  return typeof value === "string" && /^0x[0-9a-fA-F]{40}$/.test(value.trim());
}

/** ERC-721 `balanceOf(address)` calldata. Throws on a malformed address. */
export function encodeBalanceOf(address) {
  const clean = String(address || "").trim();
  if (!isValidWalletAddress(clean)) {
    throw new Error("invalid_wallet_address");
  }
  return `${BALANCE_OF_SELECTOR}${clean.slice(2).toLowerCase().padStart(64, "0")}`;
}

/** Decodes a JSON-RPC uint256 result. Returns null instead of guessing. */
export function decodeUint256(value) {
  if (typeof value !== "string" || !/^0x[0-9a-fA-F]+$/.test(value)) return null;
  try {
    return BigInt(value);
  } catch {
    return null;
  }
}

/**
 * Creates the mainnet reader. No network call happens at construction time, so
 * importing this module is safe when the RPC is unset or unreachable.
 */
export function createChogOwnershipService({
  rpcUrl = process.env.MONAD_MAINNET_RPC_URL || DEFAULT_MONAD_MAINNET_RPC_URL,
  contractAddress = process.env.CHOG_GENESIS_CONTRACT_ADDRESS || CHOG_GENESIS_CONTRACT,
  fetchImpl = globalThis.fetch,
  now = Date.now,
  timeoutMs = positiveInt(process.env.CHOG_NFT_RPC_TIMEOUT_MS, DEFAULT_RPC_TIMEOUT_MS),
  cacheTtlMs = positiveInt(process.env.CHOG_NFT_CACHE_TTL_MS, DEFAULT_CACHE_TTL_MS)
} = {}) {
  const url = String(rpcUrl || "").trim();
  const contract = String(contractAddress || "").trim().toLowerCase();
  if (!url) throw new Error("missing_mainnet_rpc_url");
  if (!isValidWalletAddress(contract)) throw new Error("invalid_chog_contract_address");

  const cache = new Map();
  let mainnetVerified = false;

  async function rpc(method, params) {
    if (typeof fetchImpl !== "function") {
      throw new Error("rpc_unavailable");
    }
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      let response;
      try {
        response = await fetchImpl(url, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
          signal: controller.signal
        });
      } catch {
        // Never let a transport error string (which can contain the RPC URL)
        // reach a log line; an error code is enough to diagnose.
        throw new Error(controller.signal.aborted ? "rpc_timeout" : "rpc_transport_error");
      }
      if (!response?.ok) {
        throw new Error(`rpc_http_${response?.status || 0}`);
      }
      let payload;
      try {
        payload = await response.json();
      } catch {
        throw new Error("rpc_invalid_json");
      }
      if (payload?.error) {
        throw new Error("rpc_error");
      }
      if (!payload || !Object.prototype.hasOwnProperty.call(payload, "result")) {
        throw new Error("rpc_missing_result");
      }
      return payload.result;
    } finally {
      clearTimeout(timer);
    }
  }

  /**
   * Refuses to read a balance until the configured endpoint has proven it is
   * Monad mainnet. This is the guard that stops a testnet RPC (10143) from
   * silently answering the ownership question.
   */
  async function ensureMainnet() {
    if (mainnetVerified) return;
    const raw = await rpc("eth_chainId", []);
    const chainId = Number.parseInt(String(raw), 16);
    if (chainId !== CHOG_GENESIS_CHAIN_ID) {
      throw new Error("wrong_chain");
    }
    mainnetVerified = true;
  }

  async function isHolder(walletAddress) {
    const wallet = String(walletAddress || "").trim();
    if (!isValidWalletAddress(wallet)) {
      throw new Error("invalid_wallet_address");
    }
    const key = wallet.toLowerCase();
    const checkedAt = now();
    const cached = cache.get(key);
    if (cached && cached.expiresAt > checkedAt) {
      return cached.has;
    }

    await ensureMainnet();
    const result = await rpc("eth_call", [
      { to: contract, data: encodeBalanceOf(wallet) },
      "latest"
    ]);
    const balance = decodeUint256(result);
    if (balance === null) {
      throw new Error("invalid_balance_result");
    }

    const has = balance > 0n;
    cache.set(key, { has, expiresAt: checkedAt + cacheTtlMs });
    return has;
  }

  return {
    isHolder,
    clearCache() {
      cache.clear();
    },
    get contractAddress() {
      return contract;
    },
    get rpcUrl() {
      return url;
    }
  };
}

/** Fixed-window limiter keyed by the authenticated identity (not the IP). */
export function createRateLimiter({
  max = DEFAULT_RATE_LIMIT_MAX,
  windowMs = DEFAULT_RATE_LIMIT_WINDOW_MS,
  now = Date.now
} = {}) {
  const buckets = new Map();
  return {
    check(key) {
      const bucketKey = String(key || "anonymous");
      const timestamp = now();
      let bucket = buckets.get(bucketKey);
      if (!bucket || timestamp - bucket.start >= windowMs) {
        bucket = { start: timestamp, count: 0 };
        buckets.set(bucketKey, bucket);
      }
      bucket.count += 1;
      if (bucket.count <= max) {
        return { allowed: true, retryAfter: 0 };
      }
      return {
        allowed: false,
        retryAfter: Math.max(1, Math.ceil((bucket.start + windowMs - timestamp) / 1000))
      };
    },
    reset() {
      buckets.clear();
    }
  };
}

/**
 * HTTP handler for `GET /api/nft/chog-genesis/ownership`.
 *
 * `authenticate(authorizationHeader)` must return
 * `{ ok: true, userId, walletAddress }` or `{ ok: false, status, error }`.
 * It is responsible for verifying the credential; this module never reads a
 * wallet address from the query string or body.
 */
export function createChogOwnershipHandler({
  authenticate,
  service,
  rateLimiter = createRateLimiter(),
  sendJson,
  log = console
} = {}) {
  if (typeof authenticate !== "function") throw new Error("missing_authenticate");
  if (!service || typeof service.isHolder !== "function") throw new Error("missing_service");
  if (typeof sendJson !== "function") throw new Error("missing_send_json");

  return async function handleChogOwnership(req, res) {
    let identity;
    try {
      identity = await authenticate(req?.headers?.authorization);
    } catch {
      // The thrown message can carry provider/URL detail; a stable code is
      // enough, and no credential is ever logged.
      log.error("[ChogNFT] identity verification failed");
      sendJson(res, 401, { ok: false, error: "unauthorized" });
      return;
    }

    if (!identity?.ok) {
      sendJson(res, identity?.status || 401, {
        ok: false,
        error: identity?.error || "unauthorized"
      });
      return;
    }

    const limit = rateLimiter.check(identity.userId || identity.walletAddress || "unknown");
    if (!limit.allowed) {
      res?.setHeader?.("Retry-After", String(limit.retryAfter));
      sendJson(res, 429, { ok: false, error: "rate_limited" });
      return;
    }

    if (!isValidWalletAddress(identity.walletAddress)) {
      sendJson(res, 400, { ok: false, error: "invalid_wallet_address" });
      return;
    }

    try {
      const has = await service.isHolder(identity.walletAddress);
      // Response shape is intentionally tiny: no address, RPC URL or token.
      sendJson(res, 200, { has_chog_nft: has === true });
    } catch (error) {
      // Any RPC/network/timeout failure is "cannot determine", never eligible.
      const code = typeof error?.message === "string" && /^[a-z0-9_]{1,64}$/.test(error.message)
        ? error.message
        : "unknown_error";
      log.error(`[ChogNFT] mainnet ownership check failed: ${code}`);
      sendJson(res, 503, { ok: false, error: "ownership_unavailable" });
    }
  };
}
