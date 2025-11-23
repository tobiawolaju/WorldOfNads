// server.js
// Production-ready (compact JSON arrays + delta broadcasting)
// Requires: node >=16 and the 'ws' package (you already used it)

import { createServer } from 'http';
import { WebSocketServer } from 'ws';
import { randomUUID } from 'crypto';

const PORT = process.env.PORT || 8080;
const BROADCAST_RATE = 20; // ticks per second
const FULL_SNAPSHOT_INTERVAL_MS = 5000; // full snapshot every 5s

// Animation mapping: small integers
const ANIM = { idle: 0, running: 1 };
const ANIM_REV = { 0: 'idle', 1: 'running' };

// --- Server state ---
let nextNumericId = 1; // small numeric id assignment
const players = new Map(); // numericId -> playerState
const sockets = new Map(); // ws -> numericId
const dirtyPlayers = new Set(); // numeric ids changed since last broadcast

// --- HTTP server for health checks ---
const server = createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('Server alive\n');
    return;
  }
  res.writeHead(404);
  res.end();
});

const wss = new WebSocketServer({ noServer: true, maxPayload: 1024 * 64 });

server.on('upgrade', (req, socket, head) => {
  wss.handleUpgrade(req, socket, head, (ws) => {
    wss.emit('connection', ws, req);
  });
});

console.log(`🚀 Starting server on port ${PORT}`);

wss.on('connection', (ws) => {
  const id = nextNumericId++;
  sockets.set(ws, id);

  // initial small default state
  const defaultPlayer = {
    id,
    x: 0,
    y: 0,
    z: 0,
    rotationY: 0,
    animation: ANIM.idle,
    lastUpdate: Date.now()
  };
  players.set(id, defaultPlayer);
  dirtyPlayers.add(id);

  console.log(`🎮 Player connected (num id=${id})`);

  // send connect message (compact)
  // format: { type: 'connect', id: <number> }
  try {
    ws.send(JSON.stringify({ type: 'connect', id }));
  } catch (e) {
    console.error('send connect failed', e);
  }

  ws.on('message', (message) => {
    // Accept either compact array updates or legacy object
    // Compact update formats supported:
    // 1) array: ["u", id, x, y, z, rotationY, animIndex]
    // 2) object: { type: 'update_state', player_id: <id>, x, y, z, rotation_y, animation }
    // Guard and parse
    try {
      const text = message.toString();
      const data = JSON.parse(text);

      if (Array.isArray(data)) {
        // compact array protocol
        // expect ["u", id, x, y, z, rotationY, animIndex]
        if (data[0] === 'u' && typeof data[1] === 'number') {
          const pid = data[1];
          let p = players.get(pid);
          if (!p) {
            // if unknown, create minimal entry
            p = { id: pid, x: 0, y: 0, z: 0, rotationY: 0, animation: ANIM.idle, lastUpdate: 0 };
            players.set(pid, p);
          }
          p.x = Number(data[2]) || 0;
          p.y = Number(data[3]) || 0;
          p.z = Number(data[4]) || 0;
          p.rotationY = Number(data[5]) || 0;
          p.animation = Number.isInteger(data[6]) ? data[6] : ANIM.idle;
          p.lastUpdate = Date.now();
          dirtyPlayers.add(pid);
        }
      } else if (data && typeof data === 'object') {
        // legacy object
        if (data.type === 'update_state') {
          const pid = Number(data.player_id);
          if (!Number.isFinite(pid)) return;
          let p = players.get(pid);
          if (!p) {
            p = { id: pid, x: 0, y: 0, z: 0, rotationY: 0, animation: ANIM.idle, lastUpdate: 0 };
            players.set(pid, p);
          }
          p.x = Number(data.x) || 0;
          p.y = Number(data.y) || 0;
          p.z = Number(data.z) || 0;
          p.rotationY = Number(data.rotation_y) || 0;
          // accept either string or numeric animation
          if (typeof data.animation === 'string') {
            p.animation = ANIM[data.animation] ?? ANIM.idle;
          } else {
            p.animation = Number.isInteger(data.animation) ? data.animation : ANIM.idle;
          }
          p.lastUpdate = Date.now();
          dirtyPlayers.add(pid);
        }
      }
    } catch (err) {
      // ignore malformed packets; log occasionally
      // console.error('bad message', err);
    }
  });

  ws.on('close', () => {
    const pid = sockets.get(ws);
    if (pid) {
      players.delete(pid);
      dirtyPlayers.add(pid); // signal removal
    }
    sockets.delete(ws);
    console.log(`💀 Player disconnected (num id=${id})`);
  });

  ws.on('error', (err) => {
    console.warn('ws error', err);
  });
});

// Broadcast loop: send delta updates frequently, send occasional full snapshot
let lastFullSnapshot = Date.now();

function buildDeltaPayload() {
  // Format: { type: 'state_delta', players: [ [id,x,y,z,rot,anim], ... ], removed: [id,...] }
  const updated = [];
  const removed = [];

  for (const pid of dirtyPlayers) {
    const p = players.get(pid);
    if (!p) {
      // player removed
      removed.push(pid);
      continue;
    }
    // push compact array for each player
    updated.push([p.id, p.x, p.y, p.z, p.rotationY, p.animation]);
  }
  dirtyPlayers.clear();

  if (updated.length === 0 && removed.length === 0) return null;
  return JSON.stringify({ type: 'state_delta', players: updated, removed });
}

function buildFullSnapshot() {
  // Format: { type: 'state', players: [ [id,x,y,z,rot,anim], ... ] }
  const arr = [];
  for (const p of players.values()) {
    arr.push([p.id, p.x, p.y, p.z, p.rotationY, p.animation]);
  }
  return JSON.stringify({ type: 'state', players: arr });
}

function broadcastLoop() {
  try {
    // Always send delta if present
    const delta = buildDeltaPayload();
    const now = Date.now();
    const doFull = now - lastFullSnapshot >= FULL_SNAPSHOT_INTERVAL_MS;

    // prefer sending delta; if no delta but it's time, send full
    if (delta) {
      for (const client of wss.clients) {
        if (client.readyState === client.OPEN) {
          try { client.send(delta); } catch(e) { /* ignore per-client send errors */ }
        }
      }
    } else if (doFull) {
      const full = buildFullSnapshot();
      lastFullSnapshot = now;
      for (const client of wss.clients) {
        if (client.readyState === client.OPEN) {
          try { client.send(full); } catch(e) {}
        }
      }
    }
  } catch (e) {
    console.error('broadcast error', e);
  }
}

setInterval(broadcastLoop, 1000 / BROADCAST_RATE);

server.listen(PORT, '0.0.0.0', () => {
  console.log(`✅ Server listening on ${PORT}`);
});
