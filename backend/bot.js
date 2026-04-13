import { WebSocket } from "ws";
import { encode as mpEncode, decode as mpDecode } from "@msgpack/msgpack";

const SERVER_URL =
  process.env.BOT_SERVER_URL || "wss://worldofnads.onrender.com";
const BOT_COUNT = Number(process.env.BOT_COUNT || 9);
const BOT_MOVE_SPEED = Number(process.env.BOT_MOVE_SPEED || 5.0);
const PICKUP_RADIUS = Number(process.env.BOT_PICKUP_RADIUS || 2.0);
const BOT_PERSONAL_SPACE = Number(process.env.BOT_PERSONAL_SPACE || 1.1);
const BOT_SEPARATION_WEIGHT = Number(process.env.BOT_SEPARATION_WEIGHT || 1.6);
const CAN_PICK = false;
const RECONNECT_MS = 1200;
const TICK_MS = 50;
const HOLD_DISTANCE = 0.9;
const HOLD_HEIGHT = 1.0;
const POS_SCALE = 100;

function createSpawn(index) {
  const ring = Math.floor(index / 8);
  const slot = index % 8;
  const radius = 2.8 + ring * 1.1;
  const angle = (Math.PI * 2 * slot) / 8 + ring * 0.35;
  return {
    x: Math.cos(angle) * radius,
    y: 0,
    z: Math.sin(angle) * radius,
  };
}

class BotClient {
  constructor(index, allBots) {
    this.index = index;
    this.allBots = allBots;
    this.username = `bot${index + 1}`;
    this.id = "";
    this.ws = null;
    this.position = createSpawn(index);
    this.rotationY = 0;
    this.animation = "idle";
    this.animId = 0;
    this.lastState = null;
    this.stateByPlayerId = new Map();
    this.lastChicken = null;
    this.connected = false;
    this.protocol = "unknown"; // unknown | msgpack | json
  }

  start() {
    this.connect();
    setInterval(() => this.tick(), TICK_MS);
  }

  connect() {
    const url = `${SERVER_URL}?username=${encodeURIComponent(this.username)}`;
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
      setTimeout(() => this.connect(), RECONNECT_MS);
    });

    this.ws.on("error", () => {
      // Close event handles reconnect.
    });
  }

  onMessage(raw) {
    const data = this._decodeIncoming(raw);
    if (!data) return;
    if (!data || typeof data !== "object") {
      return;
    }

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
      return;
    }
  }

  _decodeIncoming(raw) {
    // Prefer current beta protocol first, then fallback for live server compatibility.
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
      return;
    }
    this.ws.send(mpEncode(payload));
  }

  _decodePos(value, quantized) {
    if (!quantized) return Number(value);
    return Number(value) / POS_SCALE;
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
    this.lastState = {
      chicken: this.lastChicken,
      players,
    };
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
      chicken: this.lastChicken,
      players: Array.from(this.stateByPlayerId.values()),
    };
  }

  tick() {
    if (!this.connected || !this.ws || this.ws.readyState !== WebSocket.OPEN) {
      return;
    }
    if (!this.id || !this.lastState || !this.lastState.chicken) {
      return;
    }

    const chicken = this.lastState.chicken;
    const cx = Number(chicken.x);
    const cy = Number(chicken.y);
    const cz = Number(chicken.z);
    if (!Number.isFinite(cx) || !Number.isFinite(cy) || !Number.isFinite(cz)) {
      return;
    }

    const dt = TICK_MS / 1000;
    const dx = cx - this.position.x;
    const dz = cz - this.position.z;
    const dist2D = Math.hypot(dx, dz);
    let dirX = 0;
    let dirZ = 0;

    if (dist2D > 0.0001) {
      dirX += dx / dist2D;
      dirZ += dz / dist2D;
    }

    for (const other of this.allBots) {
      if (other === this) {
        continue;
      }
      const ox = this.position.x - other.position.x;
      const oz = this.position.z - other.position.z;
      const od = Math.hypot(ox, oz);
      if (od <= 0.0001 || od >= BOT_PERSONAL_SPACE) {
        continue;
      }
      const strength = (BOT_PERSONAL_SPACE - od) / BOT_PERSONAL_SPACE;
      dirX += (ox / od) * strength * BOT_SEPARATION_WEIGHT;
      dirZ += (oz / od) * strength * BOT_SEPARATION_WEIGHT;
    }

    const desiredLen = Math.hypot(dirX, dirZ);
    if (desiredLen > 0.0001) {
      const nx = dirX / desiredLen;
      const nz = dirZ / desiredLen;
      const step = Math.min(BOT_MOVE_SPEED * dt, Math.max(dist2D, 0.15));
      this.position.x += nx * step;
      this.position.z += nz * step;
      this.rotationY = Math.atan2(nx, nz);
      this.animation = "running";
      this.animId = 1;
    } else {
      this.animation = "idle";
      this.animId = 0;
    }

    const isHeld = Boolean(chicken.isHeld);
    const holderId = String(chicken.holderId || "");
    const iHoldChicken = isHeld && holderId === this.id;

    const statePayload = {
      type: "update_state",
      x: this.position.x,
      y: this.position.y,
      z: this.position.z,
      rotation_y: this.rotationY,
      anim_id: this.animId,
    };

    if (iHoldChicken) {
      const forwardX = Math.sin(this.rotationY);
      const forwardZ = Math.cos(this.rotationY);
      statePayload.chicken = {
        x: this.position.x + forwardX * HOLD_DISTANCE,
        y: this.position.y + HOLD_HEIGHT,
        z: this.position.z + forwardZ * HOLD_DISTANCE,
        rotation_y: this.rotationY,
      };
    }

    this._send(statePayload);

    if (CAN_PICK && !isHeld) {
      const dist3D = Math.hypot(
        cx - this.position.x,
        cy - this.position.y,
        cz - this.position.z,
      );
      if (dist3D <= PICKUP_RADIUS) {
        this._send({
          type: "pickup_request",
          item_id: "Chicken",
        });
      }
    }
  }
}

const totalBots = Math.max(0, Math.floor(BOT_COUNT));
const botClients = [];
for (let i = 0; i < totalBots; i += 1) {
  botClients.push(new BotClient(i, botClients));
}
for (const bot of botClients) {
  bot.start();
}

console.log(`Bot runner started with ${totalBots} bot(s) -> ${SERVER_URL}`);
