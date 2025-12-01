// server.js
import { createServer } from 'http';
import { WebSocketServer } from 'ws';
import { randomUUID } from 'crypto';

const PORT = process.env.PORT || 8080;
const TICK_RATE = 60; // Hz
const BROADCAST_RATE = 20; // Hz
const WIN_TIME_MS = 30_000;
const PICKUP_RANGE = 3.0;
const HIT_RANGE = 2.5;
const TUG_DIRECTION_THRESHOLD = 0.7; // cos(angle) ~ 0.7 -> ~45 degrees

// players: id -> {id, x,y,z, rotY, animation, ws, lastPos: {x,y,z}, lastUpdateAt, inputs}
const players = new Map();
const wsToId = new Map();

// flag state
const flag = {
  id: 'flag1',
  position: { x: 0, y: 1, z: 0 },
  ownerId: null,
  isTugging: false,
  tuggers: [], // [idA, idB]
  holdMs: WIN_TIME_MS,
  lastStateChange: Date.now(),
};

// helpers
function now() { return Date.now(); }
function dist(a, b) {
  const dx = a.x - b.x, dy = (a.y || 0) - (b.y || 0), dz = a.z - b.z;
  return Math.sqrt(dx * dx + dy * dy + dz * dz);
}
function midpoint(a, b) {
  return { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, z: (a.z + b.z) / 2 };
}
function normalize(v) {
  const mag = Math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
  if (mag < 1e-6) return { x: 0, y: 0, z: 0, mag: 0 };
  return { x: v.x / mag, y: v.y / mag, z: v.z / mag, mag };
}
function dot(a, b) { return a.x * b.x + a.y * b.y + a.z * b.z; }

// send JSON to single client
function send(ws, obj) {
  if (!ws || ws.readyState !== 1) return;
  ws.send(JSON.stringify(obj));
}
function broadcast(obj) {
  const msg = JSON.stringify(obj);
  for (const [, p] of players) {
    if (p.ws && p.ws.readyState === 1) p.ws.send(msg);
  }
}

// create HTTP server for health checks
const httpServer = createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('OK\n');
    return;
  }
  res.writeHead(404); res.end();
});

const wss = new WebSocketServer({ noServer: true });
httpServer.on('upgrade', (req, socket, head) => {
  wss.handleUpgrade(req, socket, head, (ws) => wss.emit('connection', ws, req));
});

wss.on('connection', (ws) => {
  const id = randomUUID();
  const p = {
    id,
    ws,
    x: 0, y: 0, z: 0,
    rotationY: 0,
    animation: 'idle',
    inputs: {},
    lastPos: { x: 0, y: 0, z: 0 },
    lastUpdateAt: now(),
    lastHitAt: 0,
    isDodging: false,
  };
  players.set(id, p);
  wsToId.set(ws, id);

  console.log(`Player connected ${id}`);
  send(ws, { type: 'connect', id });
  // initial world snapshot
  send(ws, { type: 'state', players: Array.from(players.values()).map(playerToJSON) });
  send(ws, { type: 'flag_update', flag: serializeFlag() });

  ws.on('message', raw => {
    let data;
    try { data = JSON.parse(raw.toString()); } catch (e) { return; }
    handleMessage(id, data);
  });

  ws.on('close', () => {
    console.log(`Player disconnected ${id}`);
    handleDisconnect(id);
    players.delete(id);
    wsToId.delete(ws);
  });
});

// serialize helpers
function playerToJSON(p) {
  return {
    id: p.id,
    x: p.x, y: p.y, z: p.z,
    rotationY: p.rotationY,
    animation: p.animation,
  };
}
function serializeFlag() {
  return {
    id: flag.id,
    position: flag.position,
    ownerId: flag.ownerId,
    isTugging: flag.isTugging,
    tuggers: [...flag.tuggers],
    holdMs: Math.max(0, Math.floor(flag.holdMs)),
  };
}

// message handling
function handleMessage(id, data) {
  const p = players.get(id);
  if (!p) return;

  switch (data.type) {
    case 'update_state':
      // clients may send positions frequently; we'll validate/accept in tick loop
      // save desired position in p.desiredPos for server to validate next tick
      if (typeof data.x === 'number') p.desiredPos = { x: data.x, y: data.y ?? p.y, z: data.z };
      if (typeof data.rotationY === 'number') p.rotationY = data.rotationY;
      if (typeof data.animation === 'string') p.animation = data.animation;
      if (data.inputs) p.inputs = data.inputs;
      p.lastUpdateAt = now();
      break;

    case 'request_pickup':
      attemptPickup(id);
      break;

    case 'release_flag':
      attemptRelease(id);
      break;

    case 'hit':
      // data.targetId expected
      if (data.targetId) attemptHit(id, data.targetId);
      break;

    case 'dodge':
      startDodge(id, data.durationMs || 250);
      break;

    default:
      break;
  }
}

// pickup logic
function attemptPickup(id) {
  const p = players.get(id);
  if (!p) return;
  // If nobody holds the flag and within range, pick up
  if (!flag.ownerId && !flag.isTugging) {
    if (dist(p, flag.position) <= PICKUP_RANGE) {
      flag.ownerId = id;
      flag.holdMs = WIN_TIME_MS;
      flag.lastStateChange = now();
      broadcast({ type: 'flag_update', flag: serializeFlag(), event: 'picked' });
    }
    return;
  }
  // If someone else holds and not tugging -> start tug if both nearby
  if (flag.ownerId && flag.ownerId !== id && !flag.isTugging) {
    const owner = players.get(flag.ownerId);
    if (!owner) {
      // fallback reset
      resetFlagToSpawn();
      return;
    }
    if (dist(p, owner) <= PICKUP_RANGE && dist(p, flag.position) <= PICKUP_RANGE) {
      flag.isTugging = true;
      flag.tuggers = [flag.ownerId, id].slice(0, 2);
      flag.ownerId = null; // pause single ownership
      broadcast({ type: 'flag_update', flag: serializeFlag(), event: 'tug_started' });
    }
    return;
  }
}

// release logic (voluntary release); behaves differently during tug
function attemptRelease(id) {
  if (flag.isTugging) {
    // remove id from tuggers
    flag.tuggers = flag.tuggers.filter(x => x !== id);
    if (flag.tuggers.length === 1) {
      // remaining becomes owner and timer resumes (do not reset holdMs)
      flag.ownerId = flag.tuggers[0];
      flag.isTugging = false;
      flag.tuggers = [];
      flag.lastStateChange = now();
      broadcast({ type: 'flag_update', flag: serializeFlag(), event: 'tug_resolved_release' });
    } else if (flag.tuggers.length === 0) {
      // nobody left -> drop flag to last known position
      flag.isTugging = false;
      flag.ownerId = null;
      // choose safe drop position: midpoint of last known tuggers if available
      flag.position = flag.position; // keep as-is or set to (0,1,0)
      broadcast({ type: 'flag_update', flag: serializeFlag(), event: 'tug_both_released' });
    } else {
      broadcast({ type: 'flag_update', flag: serializeFlag() });
    }
    return;
  }

  // if single owner releases, drop at their position
  if (flag.ownerId === id) {
    const owner = players.get(id);
    if (owner) {
      flag.position = { x: owner.x, y: owner.y, z: owner.z };
    }
    flag.ownerId = null;
    flag.holdMs = WIN_TIME_MS;
    broadcast({ type: 'flag_update', flag: serializeFlag(), event: 'owner_released' });
  }
}

// hit logic (attacker tries to hit target)
function attemptHit(attackerId, targetId) {
  const attacker = players.get(attackerId);
  const target = players.get(targetId);
  if (!attacker || !target) return;
  // simple distance validation
  if (dist(attacker, target) > HIT_RANGE) {
    send(attacker.ws, { type: 'hit_result', ok: false, reason: 'out_of_range' });
    return;
  }
  // dodge check
  if (target.isDodging) {
    send(attacker.ws, { type: 'hit_result', ok: false, reason: 'dodged' });
    return;
  }

  // if target owns flag and not tugging -> drop flag
  if (flag.ownerId === targetId && !flag.isTugging) {
    flag.ownerId = null;
    flag.holdMs = WIN_TIME_MS;
    flag.position = { x: target.x, y: target.y, z: target.z };
    broadcast({ type: 'flag_update', flag: serializeFlag(), event: 'dropped_by_hit', targetId, attackerId });
    // optionally: if attacker near drop pos, immediately pickup them
    if (dist(attacker, flag.position) <= PICKUP_RANGE) {
      flag.ownerId = attackerId;
      flag.holdMs = WIN_TIME_MS;
      flag.position = { x: attacker.x, y: attacker.y, z: attacker.z };
      broadcast({ type: 'flag_update', flag: serializeFlag(), event: 'picked_after_hit', by: attackerId });
    }
    send(attacker.ws, { type: 'hit_result', ok: true, targetId });
    return;
  }

  // if tugging and target is one of tuggers -> remove them from tug (they drop)
  if (flag.isTugging && flag.tuggers.includes(targetId)) {
    flag.tuggers = flag.tuggers.filter(x => x !== targetId);
    if (flag.tuggers.length === 1) {
      // remaining becomes owner
      flag.ownerId = flag.tuggers[0];
      flag.isTugging = false;
      flag.tuggers = [];
      flag.holdMs = WIN_TIME_MS; // start full timer (design choice)
    } else if (flag.tuggers.length === 0) {
      flag.isTugging = false;
      flag.ownerId = null;
      flag.position = { x: target.x, y: target.y, z: target.z };
    }
    broadcast({ type: 'flag_update', flag: serializeFlag(), event: 'tugger_hit', attackerId, targetId });
    send(attacker.ws, { type: 'hit_result', ok: true, targetId });
    return;
  }

  // else, normal hit (no effect on flag)
  send(attacker.ws, { type: 'hit_result', ok: true, targetId });
}

// dodge: simple server side dodge window
function startDodge(id, durationMs) {
  const p = players.get(id);
  if (!p) return;
  p.isDodging = true;
  setTimeout(() => {
    const p2 = players.get(id);
    if (p2) p2.isDodging = false;
  }, Math.max(50, Math.min(1000, durationMs)));
}

// if player disconnects while tugging/holding
function handleDisconnect(id) {
  if (flag.ownerId === id) {
    flag.ownerId = null;
    flag.holdMs = WIN_TIME_MS;
    flag.position = { x: 0, y: 1, z: 0 };
    broadcast({ type: 'flag_update', flag: serializeFlag(), event: 'owner_disconnected', id });
  }
  if (flag.isTugging && flag.tuggers.includes(id)) {
    flag.tuggers = flag.tuggers.filter(x => x !== id);
    if (flag.tuggers.length === 1) {
      flag.ownerId = flag.tuggers[0];
      flag.isTugging = false;
      flag.tuggers = [];
      flag.holdMs = WIN_TIME_MS;
    } else {
      flag.isTugging = false;
      flag.tuggers = [];
      flag.ownerId = null;
      flag.holdMs = WIN_TIME_MS;
    }
    broadcast({ type: 'flag_update', flag: serializeFlag(), event: 'tugger_disconnected', id });
  }
}

// reset spawn
function resetFlagToSpawn() {
  flag.ownerId = null;
  flag.isTugging = false;
  flag.tuggers = [];
  flag.holdMs = WIN_TIME_MS;
  flag.position = { x: 0, y: 1, z: 0 };
  broadcast({ type: 'flag_update', flag: serializeFlag(), event: 'reset' });
}

// server tick: validate movement and update flag timers
let lastTick = now();
setInterval(() => {
  const current = now();
  const dtMs = current - lastTick;
  lastTick = current;

  // movement validation & accept desiredPos
  // if not tugging: accept all desiredPos
  // if tugging:
  //   - get tuggers ids (2)
  //   - compute desired movement vectors for each (desiredPos - lastPos)
  //   - if both movement directions are non-zero and their normalized dot >= threshold -> accept both
  //   - if both are zero (standing) -> accept (they are locked)
  //   - else ignore movement (keep lastPos)
  if (flag.isTugging && flag.tuggers.length === 2) {
    const [aId, bId] = flag.tuggers;
    const a = players.get(aId);
    const b = players.get(bId);
    if (a && b) {
      const aDesired = a.desiredPos || { x: a.x, y: a.y, z: a.z };
      const bDesired = b.desiredPos || { x: b.x, y: b.y, z: b.z };
      const aMove = { x: aDesired.x - a.lastPos.x, y: aDesired.y - a.lastPos.y, z: aDesired.z - a.lastPos.z };
      const bMove = { x: bDesired.x - b.lastPos.x, y: bDesired.y - b.lastPos.y, z: bDesired.z - b.lastPos.z };
      const aNorm = normalize(aMove);
      const bNorm = normalize(bMove);

      let allowMovement = false;
      // if both essentially not moving (mag small) -> allow (they stay locked)
      if (aNorm.mag < 1e-3 && bNorm.mag < 1e-3) {
        allowMovement = true;
      } else {
        // if both moving enough and directions similar -> allow
        if (aNorm.mag >= 1e-3 && bNorm.mag >= 1e-3) {
          const d = dot(aNorm, bNorm);
          if (d >= TUG_DIRECTION_THRESHOLD) allowMovement = true;
        } else {
          // one moving, other not -> disallow (can't drag alone)
          allowMovement = false;
        }
      }

      if (allowMovement) {
        // accept movement: update positions and lastPos
        a.lastPos = { x: aDesired.x, y: aDesired.y, z: aDesired.z };
        a.x = aDesired.x; a.y = aDesired.y; a.z = aDesired.z;
        b.lastPos = { x: bDesired.x, y: bDesired.y, z: bDesired.z };
        b.x = bDesired.x; b.y = bDesired.y; b.z = bDesired.z;
      } else {
        // reject movement: snap desiredPos back to lastPos (server authoritative)
        if (a.desiredPos) a.desiredPos = { x: a.lastPos.x, y: a.lastPos.y, z: a.lastPos.z };
        if (b.desiredPos) b.desiredPos = { x: b.lastPos.x, y: b.lastPos.y, z: b.lastPos.z };
        // do not change positions; they remain locked
      }

      // update flag position to midpoint of current server positions
      flag.position = midpoint(a, b);
    }
  } else {
    // not tugging: accept individual desiredPos for all players
    for (const [, p] of players) {
      if (p.desiredPos) {
        p.lastPos = { x: p.desiredPos.x, y: p.desiredPos.y, z: p.desiredPos.z };
        p.x = p.desiredPos.x; p.y = p.desiredPos.y; p.z = p.desiredPos.z;
        // clear desiredPos to avoid reprocessing
        // keep it if you want continuous smoothing
      }
    }
    // if owner holds flag, make flag follow owner
    if (flag.ownerId) {
      const owner = players.get(flag.ownerId);
      if (owner) {
        flag.position = { x: owner.x, y: owner.y + 1.0, z: owner.z };
      }
    }
  }

  // update hold timer: only when single owner and not tugging
  if (!flag.isTugging && flag.ownerId) {
    const owner = players.get(flag.ownerId);
    if (!owner) {
      // owner disappeared
      flag.ownerId = null;
      flag.holdMs = WIN_TIME_MS;
    } else {
      // check owner still near flag (prevent running away)
      if (dist(owner, flag.position) <= PICKUP_RANGE * 1.5) {
        flag.holdMs -= dtMs;
        if (flag.holdMs <= 0) {
          broadcast({ type: 'flag_won', winnerId: flag.ownerId });
          // reset
          resetFlagToSpawn();
        }
      } else {
        // owner moved too far -> drop
        flag.position = { x: owner.x, y: owner.y, z: owner.z };
        flag.ownerId = null;
        flag.holdMs = WIN_TIME_MS;
        broadcast({ type: 'flag_update', flag: serializeFlag(), event: 'owner_moved_too_far' });
      }
    }
  }

}, 1000 / TICK_RATE);

// broadcast loop
setInterval(() => {
  const state = {
    type: 'state',
    players: Array.from(players.values()).map(playerToJSON),
  };
  broadcast(state);
  broadcast({ type: 'flag_update', flag: serializeFlag() });
}, 1000 / BROADCAST_RATE);

// reset flag
function resetFlagToSpawn() {
  flag.ownerId = null;
  flag.isTugging = false;
  flag.tuggers = [];
  flag.holdMs = WIN_TIME_MS;
  flag.position = { x: 0, y: 1, z: 0 };
  broadcast({ type: 'flag_update', flag: serializeFlag(), event: 'reset' });
}

// start listening
httpServer.listen(PORT, '0.0.0.0', () => {
  console.log(`Server listening on ${PORT}`);
});
