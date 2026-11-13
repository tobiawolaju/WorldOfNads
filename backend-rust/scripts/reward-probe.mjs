#!/usr/bin/env node
// Zero-dependency probe for the reward flow.
//
// The room server accrues rewards once a second (xp from chicken proximity, MON
// from the lootbox stream) and pushes a `reward_update` frame to every player.
// This probe joins a room, optionally walks to the chicken and picks it up, and
// prints every reward_update it receives plus a verdict at the end.
//
// Needs no Rust toolchain and no `npm install` (Node 22+ has WebSocket + fetch).
//
//   node backend-rust/scripts/reward-probe.mjs                              # live server, 2 players, 40s
//   node backend-rust/scripts/reward-probe.mjs ws://127.0.0.1:8080/        # local server
//   node backend-rust/scripts/reward-probe.mjs --selftest                  # codec check, no network
//
// Env:
//   PROBE_SECONDS  how long to stay connected          (default 40)
//   PROBE_CLIENTS  how many players to join with; the  (default 2)
//                  match only starts at 2 players
//   PROBE_MOVE     walk to the chicken                 (default 1)
//   PROBE_PICKUP   grab the chicken once in range      (default 1)
//   PROBE_ROOM     room id (the server may fall back to the shared room)
//
// Exit code 0 when at least one reward_update arrived and xp grew, 1 otherwise.

const DEFAULT_URL = "wss://wons-room-server.onrender.com/";
const SECONDS = Number(process.env.PROBE_SECONDS || 40);
const CLIENTS = Math.max(1, Number(process.env.PROBE_CLIENTS || 2));
const MOVE = process.env.PROBE_MOVE !== "0";
const PICKUP = process.env.PROBE_PICKUP !== "0";
const ROOM = process.env.PROBE_ROOM || "";

const POS_SCALE = 100; // wire positions are centimetres
const STEP_MS = 200;
const WALK_SPEED = 4.5; // m/s, under the server's MAX_PLAYER_SPEED

// --- minimal MessagePack codec (the subset the wire protocol uses) ------------
class Reader {
  constructor(buf) {
    this.b = buf;
    this.i = 0;
  }
  u8() { return this.b[this.i++]; }
  u16() { const v = this.b.readUInt16BE(this.i); this.i += 2; return v; }
  u32() { const v = this.b.readUInt32BE(this.i); this.i += 4; return v; }
  f32() { const v = this.b.readFloatBE(this.i); this.i += 4; return v; }
  f64() { const v = this.b.readDoubleBE(this.i); this.i += 8; return v; }
  str(n) { const s = this.b.toString("utf8", this.i, this.i + n); this.i += n; return s; }
  bin(n) { const v = this.b.subarray(this.i, this.i + n); this.i += n; return v; }
  map(n) { const o = {}; for (let k = 0; k < n; k++) o[this.decode()] = this.decode(); return o; }
  arr(n) { const a = new Array(n); for (let k = 0; k < n; k++) a[k] = this.decode(); return a; }

  decode() {
    const c = this.u8();
    if (c <= 0x7f) return c;                                  // positive fixint
    if (c >= 0xe0) return c - 0x100;                          // negative fixint
    if ((c & 0xf0) === 0x80) return this.map(c & 0x0f);       // fixmap
    if ((c & 0xf0) === 0x90) return this.arr(c & 0x0f);       // fixarray
    if ((c & 0xe0) === 0xa0) return this.str(c & 0x1f);       // fixstr
    switch (c) {
      case 0xc0: return null;
      case 0xc2: return false;
      case 0xc3: return true;
      case 0xc4: return this.bin(this.u8());
      case 0xc5: return this.bin(this.u16());
      case 0xc6: return this.bin(this.u32());
      case 0xc7: { const n = this.u8(); this.i += 1; return this.bin(n); }  // ext8
      case 0xc8: { const n = this.u16(); this.i += 1; return this.bin(n); } // ext16
      case 0xc9: { const n = this.u32(); this.i += 1; return this.bin(n); } // ext32
      case 0xca: return this.f32();
      case 0xcb: return this.f64();
      case 0xcc: return this.u8();
      case 0xcd: return this.u16();
      case 0xce: return this.u32();
      case 0xcf: { const v = this.b.readBigUInt64BE(this.i); this.i += 8; return Number(v); }
      case 0xd0: { const v = this.b.readInt8(this.i); this.i += 1; return v; }
      case 0xd1: { const v = this.b.readInt16BE(this.i); this.i += 2; return v; }
      case 0xd2: { const v = this.b.readInt32BE(this.i); this.i += 4; return v; }
      case 0xd3: { const v = this.b.readBigInt64BE(this.i); this.i += 8; return Number(v); }
      case 0xd9: return this.str(this.u8());
      case 0xda: return this.str(this.u16());
      case 0xdb: return this.str(this.u32());
      case 0xdc: return this.arr(this.u16());
      case 0xdd: return this.arr(this.u32());
      case 0xde: return this.map(this.u16());
      case 0xdf: return this.map(this.u32());
      default:
        throw new Error(`unsupported msgpack byte 0x${c.toString(16)} at offset ${this.i - 1}`);
    }
  }
}

// The client only ever sends small flat maps, so the encoder stays tiny. Every
// number goes out as f64; serde reads those into the f64 fields it declares.
function encode(value, out = []) {
  if (value === null || value === undefined) {
    out.push(Buffer.from([0xc0]));
  } else if (typeof value === "boolean") {
    out.push(Buffer.from([value ? 0xc3 : 0xc2]));
  } else if (typeof value === "number") {
    const b = Buffer.alloc(9);
    b[0] = 0xcb;
    b.writeDoubleBE(value, 1);
    out.push(b);
  } else if (typeof value === "string") {
    const s = Buffer.from(value, "utf8");
    if (s.length < 32) out.push(Buffer.from([0xa0 | s.length]));
    else { const h = Buffer.alloc(2); h[0] = 0xd9; h[1] = s.length; out.push(h); }
    out.push(s);
  } else if (Array.isArray(value)) {
    const h = Buffer.alloc(3);
    if (value.length < 16) out.push(Buffer.from([0x90 | value.length]));
    else { h[0] = 0xdc; h.writeUInt16BE(value.length, 1); out.push(h.subarray(0, 3)); }
    for (const item of value) encode(item, out);
  } else if (typeof value === "object") {
    const keys = Object.keys(value);
    const h = Buffer.alloc(3);
    if (keys.length < 16) out.push(Buffer.from([0x80 | keys.length]));
    else { h[0] = 0xde; h.writeUInt16BE(keys.length, 1); out.push(h.subarray(0, 3)); }
    for (const key of keys) {
      encode(key, out);
      encode(value[key], out);
    }
  } else {
    throw new Error(`cannot encode ${typeof value}`);
  }
  return Buffer.concat(out);
}

function decode(buf) {
  const r = new Reader(buf);
  return r.decode();
}

function toBuffer(data) {
  if (typeof data === "string") return Buffer.from(data, "utf8");
  if (data instanceof ArrayBuffer) return Buffer.from(data);
  if (ArrayBuffer.isView(data)) return Buffer.from(data.buffer, data.byteOffset, data.byteLength);
  throw new Error(`unsupported frame type: ${data?.constructor?.name ?? typeof data}`);
}

if (process.argv.includes("--selftest")) {
  const round = decode(encode({ type: "update_state", x: -1.5, z: 120.25, slide: true }));
  const ok = round.type === "update_state" && round.x === -1.5 && round.z === 120.25 && round.slide === true;
  console.log("selftest decoded:", JSON.stringify(round));
  console.log(ok ? "SELFTEST OK" : "SELFTEST FAILED");
  process.exit(ok ? 0 : 1);
}

const base = process.argv[2] || DEFAULT_URL;
const roomQuery = ROOM ? `room=${encodeURIComponent(ROOM)}&` : "";
const started = Date.now();
const clients = [];
let failures = 0;

function log(tag, text) {
  console.log(`${tag} ${text}`);
}

function buildUrl(index) {
  const sep = base.includes("?") ? "&" : "?";
  return `${base}${sep}${roomQuery}username=${encodeURIComponent(`reward-probe-${index + 1}`)}`;
}

// --- one simulated player ----------------------------------------------------
function spawn(index) {
  const state = {
    name: `p${index + 1}`,
    id: null,
    xp: 0,
    mon: 0,
    pool: 0,
    hold: 0,
    possession: 0,
    target: 60,
    ticks: 0,
    firstXp: null,
    lastXp: null,
    firstMon: null,
    lastMon: null,
    x: 0,
    y: 0,
    z: 0,
    chicken: null,
    askedPickup: false,
    connected: false,
    ws: null,
    timer: null,
  };
  clients.push(state);

  let ws;
  try {
    ws = new WebSocket(buildUrl(index));
  } catch (err) {
    log(state.name, `connect failed: ${err.message}`);
    failures += 1;
    return;
  }
  ws.binaryType = "arraybuffer";
  state.ws = ws;

  ws.addEventListener("open", () => {
    state.connected = true;
    log(state.name, "socket open");
  });

  ws.addEventListener("error", () => {
    log(state.name, "socket error");
  });

  ws.addEventListener("close", (event) => {
    log(state.name, `socket closed (${event.code}${event.reason ? ` ${event.reason}` : ""})`);
  });

  ws.addEventListener("message", (event) => {
    let frame;
    try {
      frame = decode(toBuffer(event.data));
    } catch (err) {
      log(state.name, `undecodable frame: ${err.message}`);
      return;
    }
    if (!frame || typeof frame !== "object") return;

    if (frame.type === "connect") {
      state.id = frame.id ?? null;
      log(state.name, `joined as ${frame.u ?? frame.id ?? "?"}`);
      return;
    }

    // Track our own spot and the chicken so the walk can steer toward it. The
    // username only rides along in full snapshots, so match on our player id.
    if (Array.isArray(frame.players)) {
      for (const p of frame.players) {
        if (p && state.id !== null && p.id === state.id) {
          state.x = p.x / POS_SCALE;
          state.y = p.y / POS_SCALE;
          state.z = p.z / POS_SCALE;
        }
      }
    }
    if (frame.chicken && typeof frame.chicken === "object") {
      state.chicken = {
        x: frame.chicken.x / POS_SCALE,
        y: frame.chicken.y / POS_SCALE,
        z: frame.chicken.z / POS_SCALE,
        holder: frame.chicken.h ?? 0,
      };
    }

    if (frame.type !== "reward_update") return;

    const xp = Number(frame.xp ?? 0);
    const mon = Number(frame.mon ?? 0);
    const elapsed = ((Date.now() - started) / 1000).toFixed(0);
    state.ticks += 1;
    if (state.firstXp === null) state.firstXp = xp;
    if (state.firstMon === null) state.firstMon = mon;
    state.lastXp = xp;
    state.lastMon = mon;
    state.pool = Number(frame.pool ?? 0);
    state.hold = Number(frame.holdTime ?? 0);
    state.possession = Number(frame.possessionTime ?? 0);
    state.target = Number(frame.victoryTarget ?? 60);
    state.xp = xp;
    state.mon = mon;

    log(
      state.name,
      `t=${elapsed}s reward_update xp=${xp} mon=${mon.toFixed(6)} pool=${state.pool} ` +
        `holding=${state.hold}s possession=${state.possession}s target=${state.target}s`
    );
  });

  // Walk toward the chicken and grab it once it is in range.
  state.timer = setInterval(() => {
    if (!state.connected || state.ws.readyState !== 1) return;
    let { x, z } = state;
    if (MOVE && state.chicken) {
      const dx = state.chicken.x - state.x;
      const dz = state.chicken.z - state.z;
      const dist = Math.hypot(dx, dz);
      if (dist > 0.6) {
        const step = Math.min(dist, WALK_SPEED * (STEP_MS / 1000));
        x = state.x + (dx / dist) * step;
        z = state.z + (dz / dist) * step;
      } else if (PICKUP && !state.askedPickup) {
        // Inside the pickup radius: ask for the chicken, then stand still.
        state.askedPickup = true;
        state.ws.send(encode({ type: "pickup_request", item_id: "Chicken" }));
        log(state.name, "asked for the chicken");
      }
    }
    state.ws.send(
      encode({
        type: "update_state",
        x,
        y: state.y,
        z,
        rotation_y: 0,
        animation: "idle",
      })
    );
  }, STEP_MS);
}

// --- run ---------------------------------------------------------------------
console.log(`probing ${base} (${CLIENTS} player(s), ${SECONDS}s)`);
for (let i = 0; i < CLIENTS; i += 1) spawn(i);

setTimeout(() => {
  for (const state of clients) {
    clearInterval(state.timer);
    try { state.ws?.close(); } catch { /* ignore */ }
  }

  console.log("\n--- summary ---");
  let ok = true;
  for (const state of clients) {
    const xpGain = state.firstXp === null ? 0 : state.lastXp - state.firstXp;
    const monGain = state.firstMon === null ? 0 : state.lastMon - state.firstMon;
    console.log(
      `${state.name}: ticks=${state.ticks} xp ${state.firstXp ?? "-"}→${state.lastXp ?? "-"} ` +
        `(+${xpGain}) mon ${(state.firstMon ?? 0).toFixed(6)}→${(state.lastMon ?? 0).toFixed(6)} ` +
        `(+${monGain.toFixed(6)}) pool=${state.pool} possession=${state.possession}s target=${state.target}s`
    );
    if (state.ticks === 0) {
      console.log(`${state.name}: FAIL no reward_update arrived`);
      ok = false;
    } else if (xpGain <= 0) {
      console.log(`${state.name}: FAIL xp did not grow (proximity accrual is broken, or the walk never reached the chicken)`);
      ok = false;
    }
  }

  if (ok) {
    const pool = clients.find((c) => c.pool > 0);
    if (pool) console.log("OK rewards stream live: xp and the prize pool are both ticking");
    else console.log("OK xp streams live; pool=0 means this room has no escrow behind it (a practice room)");
  }
  console.log(ok ? "REWARD PROBE OK" : "REWARD PROBE FAILED");
  process.exit(ok ? 0 : 1);
}, SECONDS * 1000);
