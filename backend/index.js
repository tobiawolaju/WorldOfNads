// server.js
import { createServer } from 'http';
import { WebSocketServer } from 'ws';
import { randomUUID } from 'crypto';

const PORT = process.env.PORT || 8080;
const BROADCAST_RATE = 20;
const FIXED_DT = 1 / BROADCAST_RATE;

const MAX_PLAYER_SPEED = 12.0; // units/sec server-side clamp against teleport cheating
const PICKUP_RADIUS = 2.2;
const MAX_THROW_IMPULSE = 8.0;
const CHICKEN_GRAVITY = 14.0;
const FLOOR_Y = 0.5869336;

const players = {};

const chicken = {
  id: 'Chicken',
  x: 1.9764378,
  y: 0.5869336,
  z: -1.5649502,
  rotationY: 0,
  isHeld: false,
  holderId: null,
  vx: 0,
  vy: 0,
  vz: 0
};

function length3(x, y, z) {
  return Math.sqrt(x * x + y * y + z * z);
}

const server = createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('Server is alive and healthy!\\n');
    return;
  }
  res.writeHead(404);
  res.end();
});

const wss = new WebSocketServer({ noServer: true });

server.on('upgrade', (req, socket, head) => {
  wss.handleUpgrade(req, socket, head, (ws) => {
    wss.emit('connection', ws, req);
  });
});

wss.on('connection', (ws) => {
  const playerId = randomUUID();

  players[playerId] = {
    id: playerId,
    x: 0,
    y: 0,
    z: 0,
    rotationY: 0,
    animation: 'idle'
  };

  console.log(`🎮 Player connected: ${playerId}`);
  ws.send(JSON.stringify({ type: 'connect', id: playerId }));

  ws.on('message', (message) => {
    try {
      const data = JSON.parse(message.toString());
      const player = players[playerId];
      if (!player || !data || typeof data.type !== 'string') {
        return;
      }

      if (data.type === 'update_state') {
        const nx = Number(data.x);
        const ny = Number(data.y);
        const nz = Number(data.z);
        const nrot = Number(data.rotation_y);
        const anim = typeof data.animation === 'string' ? data.animation : 'idle';

        if (!Number.isFinite(nx) || !Number.isFinite(ny) || !Number.isFinite(nz) || !Number.isFinite(nrot)) {
          return;
        }

        const dx = nx - player.x;
        const dy = ny - player.y;
        const dz = nz - player.z;
        const maxStep = MAX_PLAYER_SPEED * FIXED_DT;
        const dist = length3(dx, dy, dz);

        if (dist <= maxStep || dist === 0) {
          player.x = nx;
          player.y = ny;
          player.z = nz;
        } else {
          const scale = maxStep / dist;
          player.x += dx * scale;
          player.y += dy * scale;
          player.z += dz * scale;
        }

        player.rotationY = nrot;
        player.animation = anim;

        // Holder is allowed to stream chicken pose, but it is distance-validated.
        if (chicken.isHeld && chicken.holderId === playerId && data.chicken && typeof data.chicken === 'object') {
          const cx = Number(data.chicken.x);
          const cy = Number(data.chicken.y);
          const cz = Number(data.chicken.z);
          const crot = Number(data.chicken.rotation_y);

          if (Number.isFinite(cx) && Number.isFinite(cy) && Number.isFinite(cz) && Number.isFinite(crot)) {
            const pdx = cx - player.x;
            const pdy = cy - player.y;
            const pdz = cz - player.z;
            const fromPlayer = length3(pdx, pdy, pdz);
            if (fromPlayer <= PICKUP_RADIUS + 1.2) {
              chicken.x = cx;
              chicken.y = cy;
              chicken.z = cz;
              chicken.rotationY = crot;
              chicken.vx = 0;
              chicken.vy = 0;
              chicken.vz = 0;
            }
          }
        }
      }

      if (data.type === 'pickup_request') {
        if (chicken.isHeld) {
          return;
        }

        const dist = length3(
          chicken.x - player.x,
          chicken.y - player.y,
          chicken.z - player.z
        );

        if (dist <= PICKUP_RADIUS) {
          chicken.isHeld = true;
          chicken.holderId = playerId;
          chicken.vx = 0;
          chicken.vy = 0;
          chicken.vz = 0;
          console.log(`🐔 Chicken picked by ${playerId}`);
        }
      }

      if (data.type === 'drop_request') {
        if (!chicken.isHeld || chicken.holderId !== playerId) {
          return;
        }

        chicken.isHeld = false;
        chicken.holderId = null;

        const ix = Number(data.throw_x);
        const iy = Number(data.throw_y);
        const iz = Number(data.throw_z);

        if (Number.isFinite(ix) && Number.isFinite(iy) && Number.isFinite(iz)) {
          const len = length3(ix, iy, iz);
          if (len > 0) {
            const capped = Math.min(len, MAX_THROW_IMPULSE);
            const scale = capped / len;
            chicken.vx = ix * scale;
            chicken.vy = iy * scale;
            chicken.vz = iz * scale;
          }
        }

        console.log(`🥚 Chicken dropped by ${playerId}`);
      }
    } catch (error) {
      console.error('Failed to parse message:', error);
    }
  });

  ws.on('close', () => {
    console.log(`💀 Player disconnected: ${playerId}`);
    if (chicken.holderId === playerId) {
      chicken.isHeld = false;
      chicken.holderId = null;
      chicken.vx = 0;
      chicken.vy = 0;
      chicken.vz = 0;
    }
    delete players[playerId];
  });
});

setInterval(() => {
  if (!chicken.isHeld) {
    chicken.vy -= CHICKEN_GRAVITY * FIXED_DT;
    chicken.x += chicken.vx * FIXED_DT;
    chicken.y += chicken.vy * FIXED_DT;
    chicken.z += chicken.vz * FIXED_DT;

    chicken.vx *= 0.96;
    chicken.vz *= 0.96;

    if (chicken.y <= FLOOR_Y) {
      chicken.y = FLOOR_Y;
      if (Math.abs(chicken.vy) > 0.5) {
        chicken.vy *= -0.2;
      } else {
        chicken.vy = 0;
      }
    }
  }

  const stateData = {
    type: 'state',
    players: Object.values(players),
    chicken: {
      id: chicken.id,
      x: chicken.x,
      y: chicken.y,
      z: chicken.z,
      rotationY: chicken.rotationY,
      isHeld: chicken.isHeld,
      holderId: chicken.holderId
    }
  };

  const stateString = JSON.stringify(stateData);

  wss.clients.forEach((client) => {
    if (client.readyState === 1) {
      client.send(stateString);
    }
  });

}, 1000 / BROADCAST_RATE);

server.listen(PORT, '0.0.0.0', () => {
  console.log(`✅ Server is live on port ${PORT}`);
});
