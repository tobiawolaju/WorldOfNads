import { WebSocket } from "ws";

const SERVER_URL =
  process.env.BOT_SERVER_URL || "wss://worldofnads.onrender.com";
const BOT_COUNT = Number(process.env.BOT_COUNT || 2);
const BOT_MOVE_SPEED = Number(process.env.BOT_MOVE_SPEED || 5.0);
const PICKUP_RADIUS = Number(process.env.BOT_PICKUP_RADIUS || 2.0);
const BOT_PERSONAL_SPACE = Number(process.env.BOT_PERSONAL_SPACE || 1.1);
const BOT_SEPARATION_WEIGHT = Number(process.env.BOT_SEPARATION_WEIGHT || 1.6);
const RECONNECT_MS = 1200;
const TICK_MS = 50;
const HOLD_DISTANCE = 0.9;
const HOLD_HEIGHT = 1.0;

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
    this.lastState = null;
    this.connected = false;
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
      this.onMessage(raw.toString());
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
    let data;
    try {
      data = JSON.parse(raw);
    } catch {
      return;
    }
    if (!data || typeof data !== "object") {
      return;
    }

    if (data.type === "connect") {
      this.id = String(data.id || "");
      return;
    }

    if (data.type === "state") {
      this.lastState = data;
    }
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
    } else {
      this.animation = "idle";
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
      animation: this.animation,
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

    this.ws.send(JSON.stringify(statePayload));

    if (!isHeld) {
      const dist3D = Math.hypot(
        cx - this.position.x,
        cy - this.position.y,
        cz - this.position.z,
      );
      if (dist3D <= PICKUP_RADIUS) {
        this.ws.send(
          JSON.stringify({
            type: "pickup_request",
            item_id: "Chicken",
          }),
        );
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
