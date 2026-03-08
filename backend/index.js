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
const MATCH_DURATION_SECONDS = 180.0;
const MIN_PLAYERS_TO_START = 3;

const MAX_EVENT_HISTORY = 100;
let eventSequence = 0;
const eventHistory = [];

const players = {};
let matchTimeLeft = MATCH_DURATION_SECONDS;
let matchRunning = false;
let isBatchResetting = false;

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

const DEFAULT_CHICKEN_STATE = {
  x: 1.9764378,
  y: 0.5869336,
  z: -1.5649502,
  rotationY: 0
};

function length3(x, y, z) {
  return Math.sqrt(x * x + y * y + z * z);
}

function sanitizeMessage(value) {
  if (typeof value !== 'string') {
    return '';
  }
  return value.trim().slice(0, 220);
}

function sanitizeUsername(value) {
  if (typeof value !== 'string') {
    return '';
  }
  return value.trim().replace(/\s+/g, ' ').slice(0, 24);
}

function sanitizeMeta(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return {};
  }
  const safe = {};
  for (const [key, item] of Object.entries(value)) {
    if (typeof key !== 'string' || key.length > 40) {
      continue;
    }
    if (typeof item === 'string' || typeof item === 'number' || typeof item === 'boolean' || item === null) {
      safe[key] = item;
    }
  }
  return safe;
}

const server = createServer((req, res) => {
  const reqUrl = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);

  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET,OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type'
    });
    res.end();
    return;
  }

  if (req.method === 'GET' && reqUrl.pathname === '/') {
    res.writeHead(200, {
      'Content-Type': 'text/plain',
      'Access-Control-Allow-Origin': '*'
    });
    res.end('Server is alive and healthy!\\n');
    return;
  }

  if (req.method === 'GET' && reqUrl.pathname === '/events') {
    res.writeHead(200, {
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
      'Access-Control-Allow-Origin': '*'
    });
    res.end(JSON.stringify({
      type: 'events_snapshot',
      events: eventHistory
    }));
    return;
  }

  res.writeHead(404, {
    'Access-Control-Allow-Origin': '*'
  });
  res.end();
});

const gameWss = new WebSocketServer({ noServer: true });
const eventsWss = new WebSocketServer({ noServer: true });

function publishEvent(eventType, message, playerId = '', meta = {}) {
  const event = {
    id: ++eventSequence,
    eventType,
    message,
    playerId,
    timestamp: new Date().toISOString(),
    meta
  };

  eventHistory.push(event);
  if (eventHistory.length > MAX_EVENT_HISTORY) {
    eventHistory.shift();
  }

  const payload = JSON.stringify({ type: 'event', event });
  eventsWss.clients.forEach((client) => {
    if (client.readyState === 1) {
      client.send(payload);
    }
  });
}

function getPlayerCount() {
  return Object.keys(players).length;
}

function buildMatchState() {
  return {
    timeLeft: Number(matchTimeLeft.toFixed(2)),
    isRunning: matchRunning,
    durationSeconds: MATCH_DURATION_SECONDS,
    minPlayersToStart: MIN_PLAYERS_TO_START
  };
}

function restartMatchIfEligible() {
  matchTimeLeft = MATCH_DURATION_SECONDS;
  matchRunning = getPlayerCount() >= MIN_PLAYERS_TO_START;
}

function resolveRoundWinner() {
  if (!chicken.isHeld || !chicken.holderId) {
    return { winnerId: '', winnerName: 'No one' };
  }
  const holder = players[chicken.holderId];
  if (!holder) {
    return { winnerId: '', winnerName: 'No one' };
  }
  return { winnerId: holder.id, winnerName: holder.username || `player-${holder.id.slice(0, 8)}` };
}

function resetChickenState() {
  chicken.x = DEFAULT_CHICKEN_STATE.x;
  chicken.y = DEFAULT_CHICKEN_STATE.y;
  chicken.z = DEFAULT_CHICKEN_STATE.z;
  chicken.rotationY = DEFAULT_CHICKEN_STATE.rotationY;
  chicken.isHeld = false;
  chicken.holderId = null;
  chicken.vx = 0;
  chicken.vy = 0;
  chicken.vz = 0;
}

function resetRoundForNextBatch() {
  isBatchResetting = true;

  gameWss.clients.forEach((client) => {
    if (client.readyState === 1) {
      client.close(1000, 'round_finished');
    }
  });

  for (const id of Object.keys(players)) {
    delete players[id];
  }

  resetChickenState();
  matchRunning = false;
  matchTimeLeft = MATCH_DURATION_SECONDS;

  setTimeout(() => {
    isBatchResetting = false;
  }, 500);
}

server.on('upgrade', (req, socket, head) => {
  const reqUrl = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);

  if (reqUrl.pathname === '/events') {
    eventsWss.handleUpgrade(req, socket, head, (ws) => {
      eventsWss.emit('connection', ws, req);
    });
    return;
  }

  gameWss.handleUpgrade(req, socket, head, (ws) => {
    gameWss.emit('connection', ws, req);
  });
});

eventsWss.on('connection', (ws) => {
  ws.send(JSON.stringify({
    type: 'events_snapshot',
    events: eventHistory
  }));
});

gameWss.on('connection', (ws, req) => {
  const playerId = randomUUID();
  const reqUrl = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);
  const requestedUsername = sanitizeUsername(reqUrl.searchParams.get('username') || '');
  const username = requestedUsername !== '' ? requestedUsername : `player-${playerId.slice(0, 8)}`;

  players[playerId] = {
    id: playerId,
    username,
    x: 0,
    y: 0,
    z: 0,
    rotationY: 0,
    animation: 'idle'
  };

  console.log(`🎮 Player connected: ${playerId} (${username})`);
  ws.send(JSON.stringify({ type: 'connect', id: playerId, username }));
  if (!matchRunning && getPlayerCount() >= MIN_PLAYERS_TO_START) {
    matchRunning = true;
  }

  ws.on('message', (message) => {
    try {
      const data = JSON.parse(message.toString());
      const player = players[playerId];
      if (!player || !data || typeof data.type !== 'string') {
        return;
      }

      if (data.type === 'client_event') {
        const eventType = typeof data.eventType === 'string' ? data.eventType.slice(0, 40) : 'client_event';
        const cleanMessage = sanitizeMessage(data.message);
        if (cleanMessage !== '') {
          publishEvent(eventType, cleanMessage, playerId, sanitizeMeta(data.meta));
        }
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

    if (!isBatchResetting) {
      publishEvent(
        'player_left',
        `${username} left the game`,
        playerId,
        {}
      );
    }

    if (chicken.holderId === playerId) {
      chicken.isHeld = false;
      chicken.holderId = null;
      chicken.vx = 0;
      chicken.vy = 0;
      chicken.vz = 0;
    }
    delete players[playerId];
    if (getPlayerCount() < MIN_PLAYERS_TO_START) {
      matchRunning = false;
      matchTimeLeft = MATCH_DURATION_SECONDS;
    }
  });
});

setInterval(() => {
  if (matchRunning) {
    matchTimeLeft -= FIXED_DT;
    if (matchTimeLeft <= 0) {
      const winner = resolveRoundWinner();
      if (winner.winnerId) {
        publishEvent('match_winner', `${winner.winnerName} won the round`, winner.winnerId, {
          winnerId: winner.winnerId,
          winnerName: winner.winnerName
        });
      } else {
        publishEvent('match_winner', 'No winner this round', '', {
          winnerId: null,
          winnerName: 'No one'
        });
      }
      resetRoundForNextBatch();
    }
  } else {
    matchTimeLeft = MATCH_DURATION_SECONDS;
    if (getPlayerCount() >= MIN_PLAYERS_TO_START) {
      matchRunning = true;
    }
  }

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
    match: buildMatchState(),
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

  gameWss.clients.forEach((client) => {
    if (client.readyState === 1) {
      client.send(stateString);
    }
  });
}, 1000 / BROADCAST_RATE);

server.listen(PORT, '0.0.0.0', () => {
  console.log(`✅ Server is live on port ${PORT}`);
});
