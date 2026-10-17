// HTTP-triggered bot swarm for the World of Nads room server.
//
// One process serves an HTTP control surface and runs N WebSocket bots against a
// room. It is meant to be deployed on Render (a plain web service) so a phone or a
// browser can spin a swarm up with a single GET:
//
//   https://<bot-runner>.onrender.com/?matchId=<id>&botCount=20
//   https://<bot-runner>.onrender.com/?botCount=10          # the `default` room
//   https://<bot-runner>.onrender.com/?botCount=0           # stop the swarm
//   https://<bot-runner>.onrender.com/status                # live counts
//
// The bots speak the same MessagePack wire protocol the Godot client does and play
// the real loop, so the server is exercised end to end:
//   * check in on the lootbox (walk to it, then `pickup_request`)
//   * steal an item another player is carrying (pickup overwrites the holder)
//   * run: carry an objective item away from the nearest chaser
//   * use power-ups (`use_request`) after carrying them for a moment
//
// Wire protocol (see backend-rust/src/{protocol,world}.rs):
//   server -> client  connect | state_full | state_delta | reward_update
//   client -> server  update_state | pickup_request | use_request | drop_request
//
// Items are "Chicken", "LootBox" and the five power-ups "p1".."p5".

import http from "node:http";
import { WebSocket } from "ws";
import { encode as mpEncode, decode as mpDecode } from "@msgpack/msgpack";

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const PORT = Number(process.env.PORT || 3000);

const DEFAULT_SERVER =
  process.env.BOT_SERVER_URL || "wss://wons-room-server.onrender.com";

const DEFAULT_BOT_COUNT = Number(process.env.BOT_COUNT || 10);
const MAX_BOT_COUNT = Number(process.env.BOT_MAX_COUNT || 300);

const TICK_MS = clampTick(Number(process.env.BOT_TICK_MS || 33));
const MOVE_SPEED = Number(process.env.BOT_MOVE_SPEED || 5.0);

const MAX_SERVER_SPEED = 12.0; // server MAX_PLAYER_SPEED; keep a margin under it
const ARENA_LIMIT = 33.0;

const PICKUP_RADIUS = Number(process.env.BOT_PICKUP_RADIUS || 2.5);
const STEAL_RADIUS = Number(process.env.BOT_STEAL_RADIUS || 1.8);
const PERSONAL_SPACE = Number(process.env.BOT_PERSONAL_SPACE || 1.1);
const SEPARATION_WEIGHT = Number(process.env.BOT_SEPARATION_WEIGHT || 1.6);
const ACTION_COOLDOWN_MS = 400;

const RECONNECT_MS = 1200;
const POS_SCALE = 100.0;
const ROT_SCALE = 1000.0;
const POWER_UP_IDS = ["p1", "p2", "p3", "p4", "p5"];

const SKINS = [
  "defaultnad",
  "buggy",
  "Aurum",
  "Abbss",
  "Hellion",
  "Seraphim",
  "mouch",
  "john deo",
];

function clampTick(ms) {
  if (!Number.isFinite(ms) || ms < 25) return 25;
  if (ms > 200) return 200;
  return Math.floor(ms);
}

function randomBetween(min, max) {
  return min + Math.random() * (max - min);
}

function distance2D(a, b) {
  return Math.hypot(a.x - b.x, a.z - b.z);
}

function isPowerUp(itemId) {
  return POWER_UP_IDS.includes(itemId);
}

function createSpawn(index) {
  const ring = Math.floor(index / 8);
  const slot = index % 8;
  const radius = 2.8 + ring * 1.1;
  const angle = (Math.PI * 2 * slot) / 8 + ring * 0.35;
  return { x: Math.cos(angle) * radius, z: Math.sin(angle) * radius };
}

function normalizeSkin(raw, fallbackIndex) {
  const key = String(raw || "").trim().toLowerCase().replace(/\s+/g, " ");
  switch (key) {
    case "defaultnad":
    case "s-default":
      return "defaultnad";
    case "buggy":
    case "s0":
      return "buggy";
    case "aurum":
    case "s1":
      return "Aurum";
    case "abbss":
    case "abyss":
    case "s2":
      return "Abbss";
    case "hellion":
    case "s3":
      return "Hellion";
    case "seraphim":
    case "s4":
      return "Seraphim";
    case "mouch":
    case "s5":
      return "mouch";
    case "john deo":
    case "johndeo":
    case "s6":
      return "john deo";
    default:
      return SKINS[fallbackIndex % SKINS.length];
  }
}

function clamp(v, min, max) {
  if (!Number.isFinite(v)) return min;
  return Math.min(max, Math.max(min, v));
}

// ---------------------------------------------------------------------------
// Wire decoding
// ---------------------------------------------------------------------------

function toUint8(raw) {
  if (raw instanceof Uint8Array) return raw;
  if (raw instanceof ArrayBuffer) return new Uint8Array(raw);
  if (ArrayBuffer.isView(raw)) return new Uint8Array(raw.buffer, raw.byteOffset, raw.byteLength);
  if (Buffer.isBuffer(raw)) return new Uint8Array(raw);
  if (raw && typeof raw === "object" && raw.type) {
    // Node's `ws` may hand back a Blob-backed value; fall back to a zero-copy view.
    return new Uint8Array(0);
  }
  return new Uint8Array(0);
}

function decodeFrame(raw) {
  try {
    const decoded = mpDecode(toUint8(raw));
    if (decoded && typeof decoded === "object" && typeof decoded.type === "string") {
      return decoded;
    }
  } catch {
    // fall through to JSON
  }
  try {
    const text = Buffer.isBuffer(raw) ? raw.toString("utf8") : String(raw);
    const decoded = JSON.parse(text);
    if (decoded && typeof decoded === "object" && typeof decoded.type === "string") {
      return decoded;
    }
  } catch {
    // ignore
  }
  return null;
}

function decodePlayer(raw, quantized) {
  if (!raw || typeof raw !== "object" || !raw.id) return null;
  const scale = quantized ? POS_SCALE : 1;
  return {
    id: String(raw.id),
    x: Number(raw.x ?? 0) / scale,
    y: Number(raw.y ?? 0) / scale,
    z: Number(raw.z ?? 0) / scale,
    r: Number(raw.r ?? 0) / (quantized ? ROT_SCALE : 1),
    a: Number(raw.a ?? 0) / (quantized ? ROT_SCALE : 1),
    skin: String(raw.skin ?? ""),
    u: raw.u ? String(raw.u) : undefined,
  };
}

function decodeItem(raw, quantized) {
  if (!raw || typeof raw !== "object") return null;
  const scale = quantized ? POS_SCALE : 1;
  const rotScale = quantized ? ROT_SCALE : 1;
  return {
    id: String(raw.i ?? raw.id ?? ""),
    x: Number(raw.x ?? 0) / scale,
    y: Number(raw.y ?? 0) / scale,
    z: Number(raw.z ?? 0) / scale,
    held: Boolean(raw.h ?? raw.isHeld),
    holder: String(raw.o ?? raw.holderId ?? ""),
  };
}

// ---------------------------------------------------------------------------
// A single bot
// ---------------------------------------------------------------------------

class BotClient {
  constructor(index, opts, swarm) {
    this.index = index;
    this.opts = opts;
    this.swarm = swarm;
    this.username = `${opts.prefix}${index + 1}`;
    this.skin = normalizeSkin(opts.skin || "", index);

    this.id = "";
    this.ws = null;
    this.connected = false;
    this.protocol = "msgpack";
    this.lastClose = "";

    this.position = createSpawn(index);
    this.rotationY = 0;
    this.animId = 0;

    this.players = new Map();
    this.chicken = null;
    this.lootbox = null;
    this.items = new Map();
    this.match = null;

    this.holding = "";
    this.target = "";
    this.wander = { x: 8, z: 8 };
    this.wanderTimer = 0;

    this.actionCooldown = 0;
    this.useTimer = randomBetween(1500, 4000);
    this.reconnectTimer = null;
    this.stats = { pickups: 0, steals: 0, uses: 0, frames: 0 };
    this.lastTargetSwitchAt = 0;
  }

  start() {
    this.connect();
  }

  stop() {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    this.connected = false;
    if (this.ws) {
      try {
        this.ws.close();
      } catch {
        // ignore
      }
      this.ws = null;
    }
  }

  connect() {
    const url = new URL(this.swarm.server);
    url.searchParams.set("username", this.username);
    url.searchParams.set("skin", this.skin);
    if (this.swarm.room) url.searchParams.set("room", this.swarm.room);

    let ws;
    try {
      ws = new WebSocket(url.toString());
    } catch {
      this.scheduleReconnect();
      return;
    }
    this.ws = ws;
    ws.binaryType = "arraybuffer";

    ws.on("open", () => {
      this.connected = true;
      this.protocol = "msgpack";
    });
    ws.on("message", (raw) => this.onMessage(raw));
    ws.on("close", (code, reason) => {
      this.connected = false;
      this.id = "";
      if (code && code !== 1000) {
        this.lastClose = `code=${code} reason=${reason ? reason.toString() : ""}`;
      }
      this.scheduleReconnect();
    });
    ws.on("error", () => {
      // close handles the reconnect bookkeeping.
    });
  }

  scheduleReconnect() {
    if (this.reconnectTimer) return;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      this.connect();
    }, RECONNECT_MS);
  }

  send(payload) {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return;
    try {
      this.ws.send(mpEncode(payload));
    } catch {
      // ignore; the close handler will reconnect.
    }
  }

  onMessage(raw) {
    const data = decodeFrame(raw);
    if (!data) return;
    this.stats.frames += 1;
    switch (data.type) {
      case "connect":
        this.id = String(data.id ?? data.player_id ?? "");
        break;
      case "state_full":
        this.applyFullState(data);
        break;
      case "state_delta":
        this.applyDeltaState(data);
        break;
      default:
        break;
    }
  }

  applyFullState(data) {
    const quantized = Boolean(data.q ?? data.quantized);
    this.players.clear();
    for (const p of data.players || []) {
      const player = decodePlayer(p, quantized);
      if (player) this.players.set(player.id, player);
    }
    this.chicken = decodeItem(data.chicken, quantized);
    this.lootbox = decodeItem(data.lootbox, quantized);
    if (Array.isArray(data.items)) {
      const next = new Map();
      for (const raw of data.items) {
        const item = decodeItem(raw, quantized);
        if (item) next.set(item.id, item);
      }
      this.items = next;
    }
    this.match = data.match || data.matchState || this.match;
    this.lastState = data;
  }

  applyDeltaState(data) {
    const quantized = Boolean(data.q ?? data.quantized);
    if (Array.isArray(data.players)) {
      for (const p of data.players) {
        const player = decodePlayer(p, quantized);
        if (player) this.players.set(player.id, player);
      }
    }
    if (Array.isArray(data.removed)) {
      for (const id of data.removed) this.players.delete(String(id));
    }
    if (data.chicken) this.chicken = decodeItem(data.chicken, quantized);
    if (data.lootbox) this.lootbox = decodeItem(data.lootbox, quantized);
    if (Array.isArray(data.items)) {
      const next = new Map();
      for (const raw of data.items) {
        const item = decodeItem(raw, quantized);
        if (item) next.set(item.id, item);
      }
      this.items = next;
    }
    if (data.match) this.match = data.match;
  }

  /// The id of the item this bot is holding, or "" when carrying nothing.
  heldItemId() {
    if (this.lootbox && this.lootbox.held && this.lootbox.holder === this.id) {
      return "LootBox";
    }
    if (this.chicken && this.chicken.held && this.chicken.holder === this.id) {
      return "Chicken";
    }
    for (const item of this.items.values()) {
      if (item.held && item.holder === this.id) return item.id;
    }
    return "";
  }

  pickTarget() {
    const candidates = [];
    const add = (item, kind, weight) => {
      if (!item) return;
      candidates.push({
        id: item.id,
        x: item.x,
        z: item.z,
        y: item.y,
        held: item.held,
        holder: item.holder,
        kind,
        weight: item.held ? 1 : weight,
      });
    };

    add(this.lootbox, "LootBox", 3);
    add(this.chicken, "Chicken", 2);
    for (const item of this.items.values()) {
      add(item, item.id, 2);
    }

    let best = null;
    let bestScore = -Infinity;
    for (const c of candidates) {
      const dist = Math.hypot(c.x - this.position.x, c.z - this.position.z);
      const score = c.weight * 1000 - dist;
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    return best;
  }

  wanderPoint() {
    this.wanderTimer -= this.opts.tickMs;
    if (this.wanderTimer <= 0) {
      this.wander = {
        x: clamp(randomBetween(-ARENA_LIMIT + 2, ARENA_LIMIT - 2), -ARENA_LIMIT, ARENA_LIMIT),
        z: clamp(randomBetween(-ARENA_LIMIT + 2, ARENA_LIMIT - 2), -ARENA_LIMIT, ARENA_LIMIT),
      };
      this.wanderTimer = randomBetween(2500, 5000);
    }
    return this.wander;
  }

  /// Goal while carrying an objective: put distance between us and the nearest
  /// chaser so the test produces "runs" rather than static holding.
  runPoint() {
    let nearest = null;
    let nearestDist = Infinity;
    for (const [id, player] of this.players) {
      if (id === this.id) continue;
      const dist = Math.hypot(player.x - this.position.x, player.z - this.position.z);
      if (dist < nearestDist) {
        nearestDist = dist;
        nearest = player;
      }
    }
    const flee = nearest && nearestDist < 8;
    if (flee) {
      const dirX = this.position.x - nearest.x;
      const dirZ = this.position.z - nearest.z;
      const len = Math.hypot(dirX, dirZ) || 1;
      const point = {
        x: this.position.x + (dirX / len) * 12,
        z: this.position.z + (dirZ / len) * 12,
      };
      return {
        x: clamp(point.x, -ARENA_LIMIT + 1, ARENA_LIMIT - 1),
        z: clamp(point.z, -ARENA_LIMIT + 1, ARENA_LIMIT - 1),
      };
    }
    return this.wanderPoint();
  }

  tick() {
    if (!this.connected || !this.ws || this.ws.readyState !== WebSocket.OPEN) return;
    if (!this.id) return;

    if (this.actionCooldown > 0) this.actionCooldown -= this.opts.tickMs;

    const held = this.heldItemId();
    this.holding = held;

    let goal = null;

    if (held && isPowerUp(held)) {
      goal = this.wanderPoint();
      this.useTimer -= this.opts.tickMs;
      if (this.useTimer <= 0 && this.actionCooldown <= 0) {
        this.send({ type: "use_request", item_id: held });
        this.stats.uses += 1;
        this.actionCooldown = ACTION_COOLDOWN_MS;
        this.useTimer = randomBetween(1500, 4000);
      }
    } else if (held) {
      // Holding an objective: run away from whoever is close.
      goal = this.runPoint();
    } else {
      const target = this.pickTarget();
      if (target) {
        this.target = target.id;
        goal = { x: target.x, z: target.z };
        const dist = Math.hypot(this.position.x - target.x, this.position.z - target.z);
        const reach = target.held ? STEAL_RADIUS : PICKUP_RADIUS;
        if (dist <= reach && this.actionCooldown <= 0) {
          this.send({
            type: "pickup_request",
            item_id: target.id,
          });
          this.stats.pickups += 1;
          if (target.held) this.stats.steals += 1;
          this.actionCooldown = ACTION_COOLDOWN_MS;
        }
      } else {
        goal = this.wanderPoint();
      }
    }

    // Steer towards the goal with separation from the other bots in the swarm.
    let dirX = 0;
    let dirZ = 0;
    if (goal) {
      const dx = goal.x - this.position.x;
      const dz = goal.z - this.position.z;
      const dist2D2 = Math.hypot(dx, dz);
      if (dist2D2 > 0.0001) {
        dirX += dx / dist2D2;
        dirZ += dz / dist2D2;
      }
    }
    for (const other of this.swarm.bots) {
      if (other === this || !other.connected) continue;
      const ox = this.position.x - other.position.x;
      const oz = this.position.z - other.position.z;
      const od = Math.hypot(ox, oz);
      if (od <= 0.0001 || od >= PERSONAL_SPACE) continue;
      const strength = (PERSONAL_SPACE - od) / PERSONAL_SPACE;
      dirX += (ox / od) * strength * SEPARATION_WEIGHT;
      dirZ += (oz / od) * strength * SEPARATION_WEIGHT;
    }

    const desired = Math.hypot(dirX, dirZ);
    if (desired > 0.0001) {
      dirX /= desired;
      dirZ /= desired;
      const step = Math.min(MOVE_SPEED, MAX_SERVER_SPEED) * (this.opts.tickMs / 1000);
      this.position.x += dirX * step;
      this.position.z += dirZ * step;
      this.rotationY = Math.atan2(dirX, dirZ);
      this.animId = 1;
    } else {
      this.animId = 0;
    }

    this.position.x = clamp(this.position.x, -ARENA_LIMIT, ARENA_LIMIT);
    this.position.z = clamp(this.position.z, -ARENA_LIMIT, ARENA_LIMIT);

    this.send({
      type: "update_state",
      x: this.position.x,
      y: this.position.y ?? 1.195,
      z: this.position.z,
      rotation_y: this.rotationY,
      anim_id: this.animId,
      skin: this.skin,
    });
  }
}

// ---------------------------------------------------------------------------
// Swarm container
// ---------------------------------------------------------------------------

class Swarm {
  constructor() {
    this.server = DEFAULT_SERVER;
    this.room = "";
    this.bots = [];
    this.timer = null;
  }

  start({ server, room, botCount, prefix, skin, speed }) {
    this.stop();
    this.server = server;
    this.room = room;
    const opts = {
      server,
      room,
      botCount,
      prefix,
      skin,
      speed,
      tickMs: TICK_MS,
      moveSpeed: speed,
      pickupRadius: PICKUP_RADIUS,
      stealRadius: STEAL_RADIUS,
      personalSpace: PERSONAL_SPACE,
      separationWeight: SEPARATION_WEIGHT,
      actionCooldownMs: ACTION_COOLDOWN_MS,
    };
    for (let i = 0; i < botCount; i += 1) {
      const bot = new BotClient(i, opts, this);
      this.bots.push(bot);
      bot.start();
    }
    this.timer = setInterval(() => this.tick(), opts.tickMs);
  }

  stop() {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
    for (const bot of this.bots) bot.stop();
    this.bots = [];
  }

  tick() {
    for (const bot of this.bots) bot.tick();
  }

  stats() {
    const bots = this.bots.map((b) => ({
      username: b.username,
      id: b.id || null,
      connected: b.connected,
      holding: b.holding || "",
      target: b.target || "",
      pos: { x: b.position.x, z: b.position.z },
      holdingItem: b.holding || "",
      lastClose: b.lastClose || "",
    }));
    let connected = 0;
    let holding = 0;
    const totals = { pickups: 0, steals: 0, uses: 0, frames: 0 };
    for (const b of this.bots) {
      if (b.connected) connected += 1;
      if (b.holding) holding += 1;
      totals.pickups += b.stats.pickups;
      totals.steals += b.stats.steals;
      totals.uses += b.stats.uses;
      totals.frames += b.stats.frames;
    }
    return {
      server: this.server,
      room: this.room,
      botCount: this.bots.length,
      connected,
      holding,
      startedAt: this.startedAt || null,
      lastClose: this.lastClose,
      totals,
      bots,
    };
  }

  lastClose = "";
}

// ---------------------------------------------------------------------------
// HTTP control surface
// ---------------------------------------------------------------------------

const swarm = new Swarm();

function sendJson(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
  });
  res.end(payload);
}

const server = http.createServer((req, res) => {
  let url;
  try {
    url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);
  } catch {
    sendJson(res, 400, { ok: false, error: "bad_url" });
    return;
  }

  const q = url.searchParams;

  if (req.method === "OPTIONS") {
    res.writeHead(204, {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET,OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    });
    res.end();
    return;
  }

  if (req.method === "GET" && (url.pathname === "/health" || url.pathname === "/healthz")) {
    res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("ok");
    return;
  }

  if (req.method === "GET" && url.pathname === "/status") {
    return sendJson(res, 200, { ok: true, ...swarm.stats() });
  }

  if (req.method === "GET" && (url.pathname === "/" || url.pathname === "/start" || url.pathname === "/bots")) {
    const stopRequested = q.get("stop") === "1" || q.get("stop") === "true";
    const rawCount = Number(q.get("botCount") ?? q.get("count") ?? q.get("bots") ?? DEFAULT_BOT_COUNT);
    const rawRoom = q.get("matchId") || q.get("room") || q.get("match") || "default";
    const rawServer = q.get("server") || DEFAULT_SERVER;
    const rawPrefix = q.get("prefix") || `bot${String(DEFAULT_BOT_COUNT).padStart(0, 0)}`;

    if (stopRequested) {
      swarm.stop();
      return sendJson(res, 200, { ok: true, stopped: true, ...swarm.stats() });
    }

    const botCount = Number.isFinite(rawCount) ? Math.floor(rawCount) : DEFAULT_BOT_COUNT;
    const safeCount = clamp(botCount, 0, MAX_BOT_COUNT);

    swarm.start({
      server: rawServer,
      room: String(rawRoom || "default"),
      botCount: safeCount,
      prefix: rawPrefix,
      skin: q.get("skin") || "",
      speed: Number(q.get("speed") || MOVE_SPEED) || MOVE_SPEED,
    });
    swarm.startedAt = Date.now();

    return sendJson(res, 200, {
      ok: true,
      stopped: false,
      server: rawServer,
      room: String(rawRoom || "default"),
      botCount: safeCount,
      startedAt: swarm.startedAt,
      ...swarm.stats(),
    });
  }

  if (req.method === "POST" && (url.pathname === "/" || url.pathname === "/start" || url.pathname === "/bots")) {
    let body = "";
    req.on("data", (chunk) => {
      body += chunk;
    });
    req.on("end", () => {
      let parsed = {};
      try {
        parsed = body ? JSON.parse(body) : {};
      } catch {
        parsed = {};
      }
      const botCount = Number(parsed.botCount ?? parsed.count ?? DEFAULT_BOT_COUNT);
      const safeCount = clamp(Number.isFinite(botCount) ? botCount : DEFAULT_BOT_COUNT, 0, MAX_BOT_COUNT);
      const start = { ...parsed };
      swarm.start({
        server: start.server || DEFAULT_SERVER,
        room: String(start.room || start.matchId || start.match || "default"),
        botCount: safeCount,
        prefix: start.prefix || `bot${String(safeCount).padStart(2, "0")}`,
        skin: start.skin || "",
        speed: Number(start.speed) || MOVE_SPEED,
      });
      swarm.startedAt = Date.now();
      return sendJson(res, 200, { ok: true, stopped: false, botCount: safeCount, ...swarm.stats() });
    });
    return;
  }

  return sendJson(res, 404, { ok: false, error: "not_found", path: url.pathname });
});

// ---------------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------------

swarm.start({
  server: DEFAULT_SERVER,
  room: "default",
  botCount: 0,
});

server.listen(PORT, "0.0.0.0", () => {
  // Intentionally empty: the first `/start` call spins the swarm up.
  console.log(`wons-bot-runner listening on 0.0.0.0:${PORT}`);
});

function cleanup() {
  swarm.stop();
}

process.on("SIGTERM", () => {
  cleanup();
  process.exit(0);
});
process.on("SIGINT", () => {
  cleanup();
  process.exit(0);
});
