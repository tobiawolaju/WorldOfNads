// Avatar directory tests. No Firebase and no network: the profile lookup, the
// clock and the client-IP resolver are all injected.
//
// Run with: node --test backend/avatarDirectory.test.js

import test from "node:test";
import assert from "node:assert/strict";

import {
  MAX_USERNAME_LENGTH,
  createAvatarCache,
  createAvatarDirectoryHandler,
  isValidLookupUsername,
  pickProfilePictureUrl
} from "./avatarDirectory.js";

function makeRes() {
  const res = {
    statusCode: 0,
    headers: {},
    body: undefined,
    setHeader(name, value) {
      res.headers[String(name).toLowerCase()] = value;
    }
  };
  return res;
}

function makeSendJson() {
  return (res, status, payload) => {
    res.statusCode = status;
    res.body = payload;
  };
}

function makeReq({ method = "GET", username = "alice", ip = "1.2.3.4" } = {}) {
  const query = username === null ? "" : `?username=${encodeURIComponent(username)}`;
  return {
    method,
    url: `/api/profile/picture${query}`,
    headers: {},
    socket: { remoteAddress: ip }
  };
}

function makeHandler({ profile = null, fail = false, now = Date.now } = {}) {
  const calls = [];
  const handler = createAvatarDirectoryHandler({
    lookupProfile: async (username) => {
      calls.push(username);
      if (fail) throw new Error("rtdb_unavailable");
      return profile;
    },
    getClientIp: (req) => String(req.socket?.remoteAddress || ""),
    cache: createAvatarCache({ now }),
    sendJson: makeSendJson(),
    log: { error() {} }
  });
  return { handler, calls };
}

// ---------------------------------------------------------------------------
// Username validation
// ---------------------------------------------------------------------------

test("accepts ordinary usernames", () => {
  for (const name of ["alice", "Alice_99", "won-abc123", "a.b", "big chog"]) {
    assert.equal(isValidLookupUsername(name), true, name);
  }
});

test("rejects path and key injection attempts", () => {
  for (const name of ["alice/bob", "../users", "a\\b", "x#y", "x$y", "x[y]", ""]) {
    assert.equal(isValidLookupUsername(name), false, name);
  }
});

test("rejects overlong names", () => {
  assert.equal(isValidLookupUsername("a".repeat(MAX_USERNAME_LENGTH)), true);
  assert.equal(isValidLookupUsername("a".repeat(MAX_USERNAME_LENGTH + 1)), false);
});

test("rejects non-strings", () => {
  assert.equal(isValidLookupUsername(null), false);
  assert.equal(isValidLookupUsername(42), false);
});

// ---------------------------------------------------------------------------
// Picture extraction
// ---------------------------------------------------------------------------

test("reads both stored spellings", () => {
  assert.equal(
    pickProfilePictureUrl({ profile_picture_url: "https://img.example/a.png" }),
    "https://img.example/a.png"
  );
  assert.equal(
    pickProfilePictureUrl({ profilePictureUrl: "https://img.example/b.png" }),
    "https://img.example/b.png"
  );
});

test("drops non-https and non-string values", () => {
  assert.equal(pickProfilePictureUrl({ profile_picture_url: "javascript:alert(1)" }), "");
  assert.equal(pickProfilePictureUrl({ profile_picture_url: "http://img.example/a.png" }), "");
  assert.equal(pickProfilePictureUrl({ profile_picture_url: 42 }), "");
  assert.equal(pickProfilePictureUrl(null), "");
  assert.equal(pickProfilePictureUrl({}), "");
});

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

test("returns the picture for a known player", async () => {
  const { handler, calls } = makeHandler({
    profile: { profile_picture_url: "https://img.example/alice.png" }
  });
  const res = makeRes();
  await handler(makeReq(), res);

  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.body, { profile_picture_url: "https://img.example/alice.png" });
  assert.deepEqual(calls, ["alice"]);
});

test("unknown player is an empty answer, not an error", async () => {
  const { handler } = makeHandler({ profile: null });
  const res = makeRes();
  await handler(makeReq(), res);

  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.body, { profile_picture_url: "" });
});

test("a profile without a picture answers empty", async () => {
  const { handler } = makeHandler({ profile: { profile_picture_url: "" } });
  const res = makeRes();
  await handler(makeReq(), res);

  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.body, { profile_picture_url: "" });
});

test("rejects a missing username", async () => {
  const { handler, calls } = makeHandler();
  const res = makeRes();
  await handler(makeReq({ username: null }), res);

  assert.equal(res.statusCode, 400);
  assert.equal(res.body.error, "username_required");
  assert.deepEqual(calls, []);
});

test("rejects an injected username before touching the store", async () => {
  const { handler, calls } = makeHandler();
  const res = makeRes();
  await handler(makeReq({ username: "alice/bob" }), res);

  assert.equal(res.statusCode, 400);
  assert.equal(res.body.error, "invalid_username");
  assert.deepEqual(calls, []);
});

test("rejects non-GET methods", async () => {
  const { handler, calls } = makeHandler();
  const res = makeRes();
  await handler(makeReq({ method: "POST" }), res);

  assert.equal(res.statusCode, 405);
  assert.deepEqual(calls, []);
});

test("caches a hit and skips the second lookup", async () => {
  const { handler, calls } = makeHandler({
    profile: { profile_picture_url: "https://img.example/alice.png" }
  });
  await handler(makeReq(), makeRes());
  const res = makeRes();
  await handler(makeReq(), res);

  assert.equal(calls.length, 1);
  assert.equal(res.body.profile_picture_url, "https://img.example/alice.png");
});

test("caches case-insensitively", async () => {
  const { handler, calls } = makeHandler({
    profile: { profile_picture_url: "https://img.example/alice.png" }
  });
  await handler(makeReq({ username: "Alice" }), makeRes());
  await handler(makeReq({ username: "alice" }), makeRes());

  assert.equal(calls.length, 1);
});

test("does not cache a lookup failure", async () => {
  let fail = true;
  let calls = 0;
  const handler = createAvatarDirectoryHandler({
    lookupProfile: async () => {
      calls += 1;
      if (fail) throw new Error("rtdb_unavailable");
      return { profile_picture_url: "https://img.example/alice.png" };
    },
    getClientIp: () => "1.2.3.4",
    cache: createAvatarCache(),
    sendJson: makeSendJson(),
    log: { error() {} }
  });

  const failed = makeRes();
  await handler(makeReq(), failed);
  assert.equal(failed.statusCode, 503);
  assert.equal(failed.body.error, "profile_lookup_failed");

  fail = false;
  const recovered = makeRes();
  await handler(makeReq(), recovered);
  assert.equal(recovered.statusCode, 200);
  assert.equal(recovered.body.profile_picture_url, "https://img.example/alice.png");
  assert.equal(calls, 2);
});

test("expires cache entries after the TTL", async () => {
  let clock = 1_000_000;
  let calls = 0;
  const handler = createAvatarDirectoryHandler({
    lookupProfile: async () => {
      calls += 1;
      return { profile_picture_url: "https://img.example/a.png" };
    },
    getClientIp: () => "1.2.3.4",
    cache: createAvatarCache({ ttlMs: 1000, now: () => clock }),
    sendJson: makeSendJson(),
    log: { error() {} }
  });

  await handler(makeReq(), makeRes());
  clock += 999;
  await handler(makeReq(), makeRes());
  assert.equal(calls, 1);

  clock += 2;
  await handler(makeReq(), makeRes());
  assert.equal(calls, 2);
});

test("rate limits per client IP", async () => {
  const handler = createAvatarDirectoryHandler({
    lookupProfile: async () => ({ profile_picture_url: "" }),
    getClientIp: (req) => String(req.socket?.remoteAddress || ""),
    rateLimiter: {
      check(key) {
        return key === "9.9.9.9"
          ? { allowed: false, retryAfter: 7 }
          : { allowed: true, retryAfter: 0 };
      }
    },
    cache: createAvatarCache(),
    sendJson: makeSendJson(),
    log: { error() {} }
  });

  const ok = makeRes();
  await handler(makeReq({ ip: "1.2.3.4" }), ok);
  assert.equal(ok.statusCode, 200);

  const limited = makeRes();
  await handler(makeReq({ ip: "9.9.9.9" }), limited);
  assert.equal(limited.statusCode, 429);
  assert.equal(limited.body.error, "rate_limited");
  assert.equal(limited.headers["retry-after"], "7");
});

test("sends no-store so a changed avatar is picked up promptly", async () => {
  const { handler } = makeHandler({ profile: { profile_picture_url: "https://x.test/a.png" } });
  const res = makeRes();
  await handler(makeReq(), res);
  assert.equal(res.headers["cache-control"], "no-store");
});

test("cache evicts the oldest entry at the cap", () => {
  const clock = () => 0;
  const cache = createAvatarCache({ ttlMs: 10_000, maxEntries: 2, now: clock });
  cache.set("a", "1");
  cache.set("b", "2");
  cache.set("c", "3");
  assert.equal(cache.size, 2);
  assert.equal(cache.get("a"), undefined);
  assert.equal(cache.get("c"), "3");
});
