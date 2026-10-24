// Chog Genesis ownership gate tests. No Firebase, Privy, ethers or network:
// the RPC transport, clock and identity resolver are all injected.
//
// Run with: node --test backend/chogNft.test.js

import test from "node:test";
import assert from "node:assert/strict";

import {
  CHOG_GENESIS_CHAIN_ID,
  createChogOwnershipHandler,
  createChogOwnershipService,
  createRateLimiter,
  decodeUint256,
  encodeBalanceOf,
  isValidWalletAddress
} from "./chogNft.js";

const WALLET_A = "0x1111111111111111111111111111111111111111";
const WALLET_B = "0x2222222222222222222222222222222222222222";
const WALLET_C = "0x3333333333333333333333333333333333333333";

function rpcOk(result) {
  return {
    ok: true,
    status: 200,
    json: async () => ({ jsonrpc: "2.0", id: 1, result })
  };
}

function makeRpc({ chain = "0x8f", balances = {}, url = "https://mainnet.invalid" } = {}) {
  const calls = [];
  const fetchImpl = async (calledUrl, init) => {
    const body = JSON.parse(init.body);
    calls.push({ url: calledUrl, method: body.method, params: body.params });
    if (body.method === "eth_chainId") return rpcOk(chain);
    if (body.method === "eth_call") {
      const data = String(body.params?.[0]?.data || "");
      const address = `0x${data.slice(-40)}`.toLowerCase();
      return rpcOk(balances[address] || "0x0");
    }
    return rpcOk("0x0");
  };
  return { fetchImpl, calls, url };
}

function makeHandlerHarness({ service, authenticate, rateLimiter } = {}) {
  const responses = [];
  const headers = {};
  const sendJson = (_res, status, payload) => {
    responses.push({ status, payload });
  };
  const handler = createChogOwnershipHandler({
    authenticate,
    service,
    rateLimiter,
    sendJson,
    log: { error() {} }
  });
  const res = {
    setHeader(key, value) {
      headers[key] = value;
    }
  };
  const req = {
    method: "GET",
    url: "/api/nft/chog-genesis/ownership?wallet=0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
    headers: { authorization: "Bearer test-token" }
  };
  return { handler, req, res, responses, headers };
}

test("wallet validation accepts only 20-byte hex addresses", () => {
  assert.equal(isValidWalletAddress(WALLET_A), true);
  assert.equal(isValidWalletAddress(` ${WALLET_A.toUpperCase().replace("0X", "0x")} `), true);
  assert.equal(isValidWalletAddress("0x1234"), false);
  assert.equal(isValidWalletAddress("1111111111111111111111111111111111111111"), false);
  assert.equal(isValidWalletAddress(""), false);
  assert.equal(isValidWalletAddress(null), false);
});

test("balanceOf calldata pads the address", () => {
  const data = encodeBalanceOf(WALLET_A);
  assert.equal(data.slice(0, 10), "0x70a08231");
  assert.equal(data.slice(10), WALLET_A.slice(2).padStart(64, "0"));
  assert.throws(() => encodeBalanceOf("nope"), /invalid_wallet_address/);
});

test("uint256 decoding refuses garbage", () => {
  assert.equal(decodeUint256("0x1"), 1n);
  assert.equal(decodeUint256("0x"), null);
  assert.equal(decodeUint256("not-hex"), null);
  assert.equal(decodeUint256(null), null);
});

test("a wallet with a positive mainnet balance is a holder", async () => {
  const rpc = makeRpc({ balances: { [WALLET_A]: "0x1" } });
  const service = createChogOwnershipService({ rpcUrl: rpc.url, fetchImpl: rpc.fetchImpl });
  assert.equal(await service.isHolder(WALLET_A), true);
  assert.equal(rpc.calls[0].method, "eth_chainId");
  assert.equal(rpc.calls[1].method, "eth_call");
  assert.equal(rpc.calls[1].url, rpc.url);
  assert.equal(rpc.calls[1].params[0].to.length, 42);
});

test("a wallet with a zero mainnet balance is not a holder", async () => {
  const rpc = makeRpc({ balances: { [WALLET_A]: "0x0" } });
  const service = createChogOwnershipService({ rpcUrl: rpc.url, fetchImpl: rpc.fetchImpl });
  assert.equal(await service.isHolder(WALLET_A), false);
});

test("results are cached per wallet for the TTL", async () => {
  const rpc = makeRpc({ balances: { [WALLET_A]: "0x2" } });
  let now = 1_000;
  const service = createChogOwnershipService({
    rpcUrl: rpc.url,
    fetchImpl: rpc.fetchImpl,
    now: () => now,
    cacheTtlMs: 5_000
  });
  assert.equal(await service.isHolder(WALLET_A), true);
  assert.equal(await service.isHolder(WALLET_A), true);
  assert.equal(rpc.calls.filter((call) => call.method === "eth_call").length, 1);

  now += 5_001;
  assert.equal(await service.isHolder(WALLET_A), true);
  assert.equal(rpc.calls.filter((call) => call.method === "eth_call").length, 2);
});

test("cache entries never leak between wallets", async () => {
  const rpc = makeRpc({ balances: { [WALLET_A]: "0x1", [WALLET_B]: "0x0" } });
  const service = createChogOwnershipService({ rpcUrl: rpc.url, fetchImpl: rpc.fetchImpl });
  assert.equal(await service.isHolder(WALLET_A), true);
  assert.equal(await service.isHolder(WALLET_B), false);
  assert.equal(await service.isHolder(WALLET_A), true);
  assert.equal(rpc.calls.filter((call) => call.method === "eth_call").length, 2);
});

test("a testnet RPC never answers the mainnet ownership question", async () => {
  const rpc = makeRpc({ chain: "0x279f", balances: { [WALLET_A]: "0x1" } }); // 10143
  const service = createChogOwnershipService({ rpcUrl: rpc.url, fetchImpl: rpc.fetchImpl });
  await assert.rejects(() => service.isHolder(WALLET_A), /wrong_chain/);
  assert.equal(rpc.calls.filter((call) => call.method === "eth_call").length, 0);
  assert.notEqual(CHOG_GENESIS_CHAIN_ID, 10143);
});

test("RPC errors and timeouts are errors, not eligibility", async () => {
  const failing = createChogOwnershipService({
    rpcUrl: "https://mainnet.invalid",
    fetchImpl: async () => ({ ok: false, status: 429, json: async () => ({}) })
  });
  await assert.rejects(() => failing.isHolder(WALLET_A), /rpc_http_429/);

  const hanging = createChogOwnershipService({
    rpcUrl: "https://mainnet.invalid",
    timeoutMs: 20,
    fetchImpl: (_url, init) =>
      new Promise((_resolve, reject) => {
        init.signal.addEventListener("abort", () => reject(new Error("aborted")));
      })
  });
  await assert.rejects(() => hanging.isHolder(WALLET_A));
});

test("a transient failure is not cached as a negative result", async () => {
  let attempts = 0;
  const service = createChogOwnershipService({
    rpcUrl: "https://mainnet.invalid",
    fetchImpl: async (_url, init) => {
      const body = JSON.parse(init.body);
      if (body.method === "eth_chainId") return rpcOk("0x8f");
      attempts += 1;
      if (attempts === 1) throw new Error("socket closed");
      return rpcOk("0x1");
    }
  });
  await assert.rejects(() => service.isHolder(WALLET_A), /rpc_transport_error/);
  assert.equal(await service.isHolder(WALLET_A), true);
});

test("the handler uses the authenticated wallet and ignores query/body addresses", async () => {
  const rpc = makeRpc({ balances: { [WALLET_A]: "0x1" } });
  const service = createChogOwnershipService({ rpcUrl: rpc.url, fetchImpl: rpc.fetchImpl });
  const { handler, req, res, responses } = makeHandlerHarness({
    service,
    authenticate: async () => ({ ok: true, userId: "user-1", walletAddress: WALLET_A })
  });

  await handler(req, res);

  assert.equal(responses.length, 1);
  assert.equal(responses[0].status, 200);
  assert.deepEqual(responses[0].payload, { has_chog_nft: true });
  const call = rpc.calls.find((entry) => entry.method === "eth_call");
  assert.equal(`0x${call.params[0].data.slice(-40)}`, WALLET_A);
});

test("a non-holder gets has_chog_nft false", async () => {
  const rpc = makeRpc({ balances: { [WALLET_B]: "0x0" } });
  const service = createChogOwnershipService({ rpcUrl: rpc.url, fetchImpl: rpc.fetchImpl });
  const { handler, req, res, responses } = makeHandlerHarness({
    service,
    authenticate: async () => ({ ok: true, userId: "user-2", walletAddress: WALLET_B })
  });

  await handler(req, res);

  assert.equal(responses[0].status, 200);
  assert.deepEqual(responses[0].payload, { has_chog_nft: false });
});

test("unauthenticated requests are rejected before any RPC", async () => {
  let queried = false;
  const service = {
    async isHolder() {
      queried = true;
      return true;
    }
  };
  const { handler, req, res, responses } = makeHandlerHarness({
    service,
    authenticate: async () => ({ ok: false, status: 401, error: "invalid_access_token" })
  });

  await handler(req, res);

  assert.equal(responses[0].status, 401);
  assert.equal(responses[0].payload.has_chog_nft, undefined);
  assert.equal(queried, false);
});

test("a malformed authenticated wallet is rejected before any RPC", async () => {
  let queried = false;
  const service = {
    async isHolder() {
      queried = true;
      return true;
    }
  };
  const { handler, req, res, responses } = makeHandlerHarness({
    service,
    authenticate: async () => ({ ok: true, userId: "user-3", walletAddress: "not-an-address" })
  });

  await handler(req, res);

  assert.equal(responses[0].status, 400);
  assert.equal(responses[0].payload.error, "invalid_wallet_address");
  assert.equal(queried, false);
});

test("an RPC failure returns 503 without leaking internals", async () => {
  const { handler, req, res, responses } = makeHandlerHarness({
    service: {
      async isHolder() {
        throw new Error("https://secret-rpc.example/key?token=abc timed out");
      }
    },
    authenticate: async () => ({ ok: true, userId: "user-4", walletAddress: WALLET_A })
  });

  await handler(req, res);

  const body = JSON.stringify(responses[0]);
  assert.equal(responses[0].status, 503);
  assert.equal(responses[0].payload.error, "ownership_unavailable");
  assert.equal(body.includes("secret-rpc"), false);
  assert.equal(body.includes("Bearer"), false);
});

test("rate limiting is per identity and sets Retry-After", async () => {
  const limiter = createRateLimiter({ max: 2, windowMs: 60_000, now: () => 1_000 });
  const service = { async isHolder() { return false; } };
  const { handler, req, res, responses, headers } = makeHandlerHarness({
    service,
    rateLimiter: limiter,
    authenticate: async () => ({ ok: true, userId: "user-5", walletAddress: WALLET_A })
  });

  await handler(req, res);
  await handler(req, res);
  await handler(req, res);

  assert.deepEqual(responses.map((entry) => entry.status), [200, 200, 429]);
  assert.equal(responses[2].payload.error, "rate_limited");
  assert.equal(headers["Retry-After"], "60");
});
