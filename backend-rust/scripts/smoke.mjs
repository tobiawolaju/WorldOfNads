#!/usr/bin/env node
// Zero-dependency smoke probe for the room server.
//
// Uses Node's built-in WebSocket + fetch (Node 22+), so it needs no WSL, no
// Rust toolchain and no `npm install`. It connects, decodes the MessagePack
// frames and prints a summary of what the server sent.
//
//   node backend-rust/scripts/smoke.mjs                                    # local default
//   node backend-rust/scripts/smoke.mjs ws://127.0.0.1:18080/?username=x   # anything running
//   node backend-rust/scripts/smoke.mjs wss://wons-room-server.onrender.com/?username=x
//   node backend-rust/scripts/smoke.mjs --selftest                         # decoder check, no network
//
// Env: SMOKE_FRAMES (default 12), SMOKE_TIMEOUT_MS (default 20000)

const DEFAULT_URL = "ws://127.0.0.1:8080/?username=probe";
const MAX_FRAMES = Number(process.env.SMOKE_FRAMES || 12);
const TIMEOUT_MS = Number(process.env.SMOKE_TIMEOUT_MS || 20000);

// --- minimal MessagePack decoder (the subset the wire protocol uses) ---
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
  ext() { const n = this.u8(); this.u8(); return this.bin(n); }

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
      case 0xd4: { this.i += 1; return this.bin(1); }   // fixext1
      case 0xd5: { this.i += 1; return this.bin(2); }   // fixext2
      case 0xd6: { this.i += 1; return this.bin(4); }   // fixext4
      case 0xd7: { this.i += 1; return this.bin(8); }   // fixext8
      case 0xd8: { this.i += 1; return this.bin(16); }  // fixext16
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

function decode(buf) {
  const r = new Reader(buf);
  const value = r.decode();
  return { value, consumed: r.i, total: buf.length };
}

// Node's WebSocket hands back a Blob unless binaryType is set; accept all shapes.
function toBuffer(data) {
  if (typeof data === "string") return Buffer.from(data, "utf8");
  if (data instanceof ArrayBuffer) return Buffer.from(data);
  if (ArrayBuffer.isView(data)) return Buffer.from(data.buffer, data.byteOffset, data.byteLength);
  throw new Error(`unsupported frame type: ${data?.constructor?.name ?? typeof data}`);
}

// --- selftest: prove the decoder works with no network ---
if (process.argv.includes("--selftest")) {
  const parts = [
    0x82, 0xa4, ...Buffer.from("type"), 0xa7, ...Buffer.from("connect"),
    0xa1, ...Buffer.from("u"), 0xa3, ...Buffer.from("abc"),
  ];
  const buf = Buffer.from(parts);
  const { value, consumed, total } = decode(buf);
  console.log("selftest decoded:", JSON.stringify(value));
  const ok = value.type === "connect" && value.u === "abc" && consumed === total;
  console.log(ok ? "SELFTEST OK" : "SELFTEST FAILED");
  process.exit(ok ? 0 : 1);
}

const url = process.argv[2] || DEFAULT_URL;

// --- health endpoint (only for http/ws URLs on the same host) ---
async function checkHealth(u) {
  try {
    const httpUrl = u.replace(/^ws/, "http").split("?")[0];
    const res = await fetch(new URL("/health", httpUrl), { method: "GET" });
    const body = (await res.text()).trim();
    console.log(`health: ${res.status} ${body.slice(0, 60)}`);
  } catch (err) {
    console.log(`health: unreachable (${err.message})`);
  }
}

console.log(`probing ${url}`);
await checkHealth(url);

const summary = [];
let failures = 0;

await new Promise((resolve) => {
  const ws = new WebSocket(url);
  ws.binaryType = "arraybuffer"; // Node defaults to Blob; we decode synchronously
  const seen = new Map();

  const finish = (code) => {
    try { ws.close(); } catch { /* ignore */ }
    resolve(code);
  };

  const timer = setTimeout(() => {
    console.log(`\ntimeout after ${TIMEOUT_MS} ms`);
    finish(failures === 0 && summary.length > 0 ? 0 : 1);
  }, TIMEOUT_MS);

  ws.addEventListener("open", () => {
    console.log("websocket: open (101 upgrade accepted)");
  });

  ws.addEventListener("message", (event) => {
    let buf;
    let frame;
    try {
      buf = toBuffer(event.data);
      frame = decode(buf).value;
    } catch (err) {
      failures += 1;
      console.log(`frame decode FAILED (${buf ? buf.length : 0} bytes): ${err.message}`);
      return;
    }
    const type = frame && frame.type ? frame.type : "(no type)";
    seen.set(type, (seen.get(type) || 0) + 1);
    summary.push({ type, bytes: buf.length });
    console.log(`frame #${summary.length}: ${type} (${buf.length} bytes)`);

    if (type === "connect") {
      console.log("  connect:", JSON.stringify({
        id: frame.id ?? frame.player_id ?? frame.u,
        u: frame.u,
        keys: Object.keys(frame),
      }));
    }
    if (type === "state_full" || type === "state_delta") {
      const players = frame.players || [];
      console.log(`  ${type}: q=${frame.q} players=${players.length} match=${frame.match ? "present" : "absent"}`);
      if (players.length > 0) console.log("  first player keys:", Object.keys(players[0]).join(","));
      if (frame.match) console.log("  match:", JSON.stringify(frame.match));
      if (frame.items) console.log(`  items=${frame.items.length}`);
    }

    if (summary.length >= MAX_FRAMES) {
      clearTimeout(timer);
      finish(0);
    }
  });

  ws.addEventListener("error", () => {
    failures += 1;
    console.log("websocket: error");
  });

  ws.addEventListener("close", (event) => {
    console.log(`websocket: closed (code ${event.code}${event.reason ? ", " + event.reason : ""})`);
    clearTimeout(timer);
    finish(failures === 0 && summary.length > 0 ? 0 : 1);
  });
}).then((code) => {
  console.log("\n--- summary ---");
  for (const [type, count] of seenCounts(summary)) console.log(`  ${type}: ${count}`);
  console.log(code === 0 ? "SMOKE OK" : "SMOKE FAILED");
  process.exit(code);
});

function seenCounts(entries) {
  const m = new Map();
  for (const { type } of entries) m.set(type, (m.get(type) || 0) + 1);
  return m;
}
