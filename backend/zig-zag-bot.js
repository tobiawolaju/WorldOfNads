import { WebSocket } from "ws";
import { encode as mpEncode, decode as mpDecode } from "@msgpack/msgpack";

const SERVER_URL =
  process.env.BOT_SERVER_URL || "wss://worldofnads.onrender.com";
const BOT_COUNT = Number(process.env.BOT_COUNT || 9);
const BOT_MOVE_SPEED = Number(process.env.BOT_MOVE_SPEED || 4.8);
const ZIGZAG_WIDTH = Number(process.env.BOT_ZIGZAG_WIDTH || 2.2);
const ZIGZAG_FREQ = Number(process.env.BOT_ZIGZAG_FREQ || 1.35);
const RECONNECT_MS = 1200;
const TICK_MS = 50;
const DEFAULT_BOT_SKINS = [
  "defaultnad",
  "buggy",
  "Aurum",
  "Abbss",
  "Hellion",
  "Seraphim",
  "mouch",
  "john deo",
];

function normalizeBotSkinName(rawSkin) {
  const key = String(rawSkin || "")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, " ");

  switch (key) {
    case "s-default":
    case "defaultnad":
      return "defaultnad";
    case "s0":
    case "buggy":
      return "buggy";
    case "s1":
    case "aurum":
      return "Aurum";
    case "s2":
    case "abbss":
    case "abyss":
      return "Abbss";
    case "s3":
    case "hellion":
      return "Hellion";
    case "s4":
    case "seraphim":
      return "Seraphim";
    case "s5":
    case "mouch":
      return "mouch";
    case "s6":
    case "john deo":
    case "johndeo":
      return "john deo";
    default:
      return "defaultnad";
  }
}

function parseBotSkins(value) {
  const parsed = String(value || "")
    .split(",")
    .map((skin) => normalizeBotSkinName(skin))
    .filter((skin, index, all) => skin && all.indexOf(skin) === index);
  return parsed.length > 0 ? parsed : DEFAULT_BOT_SKINS;
}

const BOT_SKINS = parseBotSkins(process.env.BOT_SKINS);

function createSpawn(index) {
  const ring = Math.floor(index / 8);
  const slot = index % 8;
  const radius = 3.2 + ring * 1.1;
  const angle = (Math.PI * 2 * slot) / 8 + ring * 0.28;
  return {
    x: Math.cos(angle) * radius,
    y: 0,
    z: Math.sin(angle) * radius,
  };
}

class ZigZagBotClient {
  constructor(index) {
    this.index = index;
    this.username = `zigzag${index + 1}`;
    this.skin = BOT_SKINS[index % BOT_SKINS.length];
    this.id = "";
    this.ws = null;
    this.connected = false;
    this.protocol = "unknown"; // unknown | msgpack | json

    this.position = createSpawn(index);
    this.rotationY = 0;
    this.animId = 0;
    this.phase = index * 0.53;
    this.anchor = { ...this.position };

    this.lastState = null;
    this.stateByPlayerId = new Map();
    this.lastChicken = null;
    this.lastYaw = Math.PI * 0.5;
  }

  start() {
    this.connect();
    setInterval(() => this.tick(), TICK_MS);
  }

  connect() {
    const url = `${SERVER_URL}?username=${encodeURIComponent(this.username)}&skin=${encodeURIComponent(this.skin)}`;
    this.ws = new WebSocket(url);

    this.ws.on("open", () => {
      this.connected = true;
      console.log(`[${this.username}] connected`);
    });

    this.ws.on("message", (raw) => {
      this.onMessage(raw);
    });

    this.ws.on("close", () => {
      if (this.connected) {
        console.log(`[${this.username}] disconnected, retrying...`);
      }
      this.connected = false;
      this.id = "";
      this.protocol = "unknown";
      this.stateByPlayerId.clear();
      this.lastState = null;
      setTimeout(() => this.connect(), RECONNECT_MS);
    });

    this.ws.on("error", () => {
      // close event handles reconnect
    });
  }

  onMessage(raw) {
    const data = this._decodeIncoming(raw);
    if (!data || typeof data !== "object") return;

    if (data.type === "connect") {
      this.id = String(data.id || "");
      return;
    }
    if (data.type === "state") {
      this.lastState = data;
      this.lastChicken = data.chicken || this.lastChicken;
      return;
    }
    if (data.type === "state_full") {
      this._applyFullState(data);
      return;
    }
    if (data.type === "state_delta") {
      this._applyDeltaState(data);
    }
  }

  _decodeIncoming(raw) {
    if (this.protocol !== "json") {
      try {
        const decoded = mpDecode(new Uint8Array(raw));
        if (decoded && typeof decoded === "object" && typeof decoded.type === "string") {
          this.protocol = "msgpack";
          return decoded;
        }
      } catch {
        // fallback below
      }
    }

    try {
      const text = Buffer.isBuffer(raw) ? raw.toString("utf8") : String(raw);
      const decoded = JSON.parse(text);
      if (decoded && typeof decoded === "object" && typeof decoded.type === "string") {
        this.protocol = "json";
        return decoded;
      }
    } catch {
      // no-op
    }
    return null;
  }

  _send(payload) {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return;
    if (this.protocol === "json") {
      this.ws.send(JSON.stringify(payload));
    } else {
      this.ws.send(mpEncode(payload));
    }
  }

  _decodePos(v, quantized) {
    return quantized ? Number(v) / 100 : Number(v);
  }

  _decodeChicken(chicken, quantized) {
    if (!chicken || typeof chicken !== "object") return null;
    if (!quantized) {
      return {
        x: Number(chicken.x),
        y: Number(chicken.y),
        z: Number(chicken.z),
        isHeld: Boolean(chicken.isHeld),
        holderId: String(chicken.holderId || ""),
      };
    }
    return {
      x: this._decodePos(chicken.x, true),
      y: this._decodePos(chicken.y, true),
      z: this._decodePos(chicken.z, true),
      isHeld: Boolean(chicken.h),
      holderId: String(chicken.o || ""),
    };
  }

  _applyFullState(data) {
    const quantized = Boolean(data.q || data.quantized);
    const players = Array.isArray(data.players) ? data.players : [];
    this.stateByPlayerId.clear();
    for (const p of players) {
      if (!p || typeof p !== "object" || !p.id) continue;
      this.stateByPlayerId.set(String(p.id), p);
    }
    if (data.chicken) {
      this.lastChicken = this._decodeChicken(data.chicken, quantized);
    }
    this.lastState = { players, chicken: this.lastChicken };
  }

  _applyDeltaState(data) {
    const quantized = Boolean(data.q || data.quantized);
    if (Array.isArray(data.players)) {
      for (const p of data.players) {
        if (!p || typeof p !== "object" || !p.id) continue;
        this.stateByPlayerId.set(String(p.id), p);
      }
    }
    if (Array.isArray(data.removed)) {
      for (const id of data.removed) {
        this.stateByPlayerId.delete(String(id));
      }
    }
    if (data.chicken) {
      this.lastChicken = this._decodeChicken(data.chicken, quantized);
    }
    this.lastState = {
      players: Array.from(this.stateByPlayerId.values()),
      chicken: this.lastChicken,
    };
  }

  tick() {
    if (!this.connected || !this.ws || this.ws.readyState !== WebSocket.OPEN || !this.id) {
      return;
    }

    const dt = TICK_MS / 1000;
    this.phase += dt * ZIGZAG_FREQ;

    // Forward drift + sinusoidal lateral movement.
    const forwardSpeed = BOT_MOVE_SPEED * 0.75;
    const lateral = Math.sin(this.phase) * ZIGZAG_WIDTH;
    const forward = Math.cos(this.phase * 0.37) * 5.5;

    const targetX = this.anchor.x + lateral;
    const targetZ = this.anchor.z + forward;

    const dx = targetX - this.position.x;
    const dz = targetZ - this.position.z;
    const dist = Math.hypot(dx, dz);
    if (dist > 0.001) {
      const step = Math.min(forwardSpeed * dt, dist);
      const nx = dx / dist;
      const nz = dz / dist;
      this.position.x += nx * step;
      this.position.z += nz * step;
      this.lastYaw = Math.atan2(nx, nz);
      this.animId = 1;
    } else {
      this.animId = 0;
    }
    this.rotationY = this.lastYaw;

    this._send({
      type: "update_state",
      x: this.position.x,
      y: this.position.y,
      z: this.position.z,
      rotation_y: this.rotationY,
      anim_id: this.animId,
      skin: this.skin,
    });
  }
}

const totalBots = Math.max(0, Math.floor(BOT_COUNT));
const botClients = [];
for (let i = 0; i < totalBots; i += 1) {
  botClients.push(new ZigZagBotClient(i));
}
for (const bot of botClients) {
  bot.start();
}

console.log(`Zig-zag bot runner started with ${totalBots} bot(s) -> ${SERVER_URL}`);
