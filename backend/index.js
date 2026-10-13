import { createServer } from 'http';
import { WebSocketServer } from 'ws';
import { randomUUID, createHmac, timingSafeEqual } from 'crypto';
import { encode as mpEncode, decode as mpDecode } from '@msgpack/msgpack';
import { getPlayerWallet, findActiveMatch, markMatchSettled, getAllMatches, updateMatchStatus, saveReward, updateUserRoles, getPlayerProfile, saveSkin, getSkin, getAllSkins, getPlayerSkin } from './firebaseClient.js';
import { settleMatchOnchain, batchStreamMON, mintXP, contractWithdraw, createSkinOnchain, getNextSkinId, calcMonPerSec } from './contractClient.js';
import { initAnalyticsDb, logAnalyticsEvent, getAnalyticsSummary, getAnalyticsTimeseries, exportAnalyticsEvents } from './analyticsService.js';
import { refreshAllUserPfps } from './refreshUserPfps.js';
import { attachmentsForId, loadCombos, loadDefaults } from './skinIndex.js';
import {
  approveDeviceLogin,
  cancelDeviceLogin,
  exchangeDeviceLogin,
  getAuthenticatedSession,
  getDeviceLoginStatus,
  lookupDeviceLogin,
  logoutSession,
  refreshSession,
  startDeviceLogin
} from './authService.js';

const PORT = process.env.PORT || 8080;
const BROADCAST_RATE = 20;
const FIXED_DT = 1 / BROADCAST_RATE;
const NEAR_UPDATE_RATE = 20;
const MEDIUM_UPDATE_RATE = 15;
const FAR_UPDATE_RATE = 6;
const NEAR_UPDATE_DISTANCE = 12.0;
const MEDIUM_UPDATE_DISTANCE = 28.0;
const CELL_SIZE = 18.0;
const CELL_REPLICATION_RADIUS = 3;
const FULL_SNAPSHOT_INTERVAL_MS = 2000;
const MATCH_HEARTBEAT_INTERVAL_MS = 1000;
const POS_SCALE = 100; // centimeters
const ROT_SCALE = 1000; // milliradians
const MAX_CLIENT_BUFFERED_BYTES = 512 * 1024;

const AUTH_TOKEN_SECRET = process.env.AUTH_TOKEN_SECRET || 'change-me-in-production-wons-' + randomUUID();
const WS_RATE_LIMIT_WINDOW_MS = 1000;
const WS_RATE_LIMIT_MAX_MESSAGES = 60;
const WS_MAX_MESSAGE_SIZE = 4096;
const RATE_LIMIT_BAN_DURATION_MS = 60000;
const SESSION_TOKEN_EXPIRY_MS = 1800000; // 30 minutes — long enough for match + reconnection
const sessionTokens = new Map();
const rateLimitTracker = new Map();
const ipBanTracker = new Map();

const MAX_PLAYER_SPEED = 12.0; // units/sec horizontal clamp against teleport cheating
// Vertical is clamped separately: jumps/falls move far faster vertically than a
// player can run. The LEAP mega-leap launches at ~24 u/s up and falls back at the
// same speed, so a single 3D cap (MAX_PLAYER_SPEED) used to halve it for everyone
// else. Bounded, but with room for that leap (and network jitter).
const MAX_PLAYER_VERTICAL_SPEED = 36.0; // units/sec vertical allowance (mega-leap/falls)
const PICKUP_RADIUS = 2.2;
// Stealing works off the distance to the HOLDER (not the item), since the item
// rides ~1 off their body.
const STEAL_RADIUS = 2.0;
const MAX_THROW_IMPULSE = 8.0;
const CHICKEN_GRAVITY = 14.0;
const FLOOR_Y = 1.195;
const MATCH_DURATION_SECONDS = 180.0;
const DEFAULT_MIN_PLAYERS_TO_START = 2;
const ANIM_NAME_TO_ID = Object.freeze({
  idle: 0,
  running: 1,
  runningjump: 2,
  falling: 3,
  runningslide: 4
});
const ANIM_ID_TO_NAME = Object.freeze({
  0: 'idle',
  1: 'running',
  2: 'runningjump',
  3: 'falling',
  4: 'runningslide'
});


const MAX_EVENT_HISTORY = 100;
let eventSequence = 0;
const eventHistory = [];

const players = {};
let matchTimeLeft = MATCH_DURATION_SECONDS;
let matchRunning = false;
let matchStartedThisRound = false;
let isBatchResetting = false;
let currentMinPlayersToStart = 2; // Force minimum of 2 for now
let currentMaxPlayers = null;

// Pre-start lobby countdown: once enough players are connected, wait this long
// so everyone gets a clear "Match starts in N…" before movement unlocks.
const MATCH_START_COUNTDOWN_SECONDS = 5;
let matchStartCountdown = -1; // -1 = not counting down; >0 = counting to start

// Storm radius (server-authoritative)
let stormRadius = 20.0;
const STORM_SHRINK_INTERVAL = 20.0;
const STORM_SHRINK_DURATION = 5.0;
const STORM_SHRINK_STEP = 2.0;
const STORM_MIN_RADIUS = 3.0;
let stormShrinkTimer = 0.0;
let stormIsShrinking = false;
let stormShrinkProgress = 0.0;
let stormStartRadius = 20.0;
let stormTargetRadius = 20.0;
const recipientNetworkState = new Map();
const playerCellIndex = new Map();
const cellOccupants = new Map();
const backgroundJobs = [];
let backgroundJobActive = false;


const chicken = {
  id: 'Chicken',
  x: 1.9764378,
  y: 1.195,
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
  y: 1.195,
  z: -1.5649502,
  rotationY: 0
};

const lootbox = {
  id: 'LootBox',
  x: 5,
  y: 1.195,
  z: 0,
  rotationY: 0,
  isHeld: false,
  holderId: null,
  vx: 0,
  vy: 0,
  vz: 0
};

const DEFAULT_LOOTBOX_STATE = {
  x: 5,
  y: 1.195,
  z: 0,
  rotationY: 0
};

// --- POWER-UPS (server-authoritative) ---
// The five map power-ups. Like the chicken and lootbox they are owned by the
// server: it picks a random spot for each at match start, tracks who is holding
// them, re-rolls the spot when they are used, and drops them where the holder
// died or disconnected. Clients mirror the server position and hide a power-up
// while it is being carried.
const POWER_UP_IDS = ['p1', 'p2', 'p3', 'p4', 'p5'];

// Whole-map random spawn bounds. The client minimap is 70x70 centred on the
// origin, so spawns stay inside +/- ARENA_HALF_SIZE with an edge margin.
const ARENA_HALF_SIZE = 35.0;
const ITEM_SPAWN_MARGIN = 4.0;

const powerUps = {};
for (const id of POWER_UP_IDS) {
  powerUps[id] = {
    id,
    x: 0,
    y: FLOOR_Y,
    z: 0,
    rotationY: 0,
    isHeld: false,
    holderId: null,
    vx: 0,
    vy: 0,
    vz: 0
  };
}

// --- MATCH-START ITEM SPAWNS ---
// The server picks where every item starts each match (whole map, see above)
// and re-rolls the spot whenever an item is used. y is FLOOR_Y so items rest on
// the floor instead of the editor scene positions (the chicken node in
// gameplay.tscn floats high above the terrain).

function length3(x, y, z) {
  return Math.sqrt(x * x + y * y + z * z);
}

function quantizePosition(value) {
  return Math.round(value * POS_SCALE);
}

function dequantizePosition(value) {
  return value / POS_SCALE;
}

function quantizeRotation(value) {
  return Math.round(value * ROT_SCALE);
}

function dequantizeRotation(value) {
  return value / ROT_SCALE;
}

function getCellCoords(x, z) {
  return {
    cx: Math.floor(x / CELL_SIZE),
    cz: Math.floor(z / CELL_SIZE)
  };
}

function getCellKey(cx, cz) {
  return `${cx}:${cz}`;
}

function getPlayerCellKey(player) {
  if (!player) return '';
  const { cx, cz } = getCellCoords(player.x, player.z);
  return getCellKey(cx, cz);
}

function removePlayerFromCellIndex(playerId) {
  const previousCellKey = playerCellIndex.get(playerId);
  if (!previousCellKey) return;
  const occupants = cellOccupants.get(previousCellKey);
  if (occupants) {
    occupants.delete(playerId);
    if (occupants.size === 0) {
      cellOccupants.delete(previousCellKey);
    }
  }
  playerCellIndex.delete(playerId);
}

function updatePlayerCellIndex(playerId, player) {
  const nextCellKey = getPlayerCellKey(player);
  const previousCellKey = playerCellIndex.get(playerId);
  if (previousCellKey === nextCellKey) {
    return nextCellKey;
  }

  if (previousCellKey) {
    const previousOccupants = cellOccupants.get(previousCellKey);
    if (previousOccupants) {
      previousOccupants.delete(playerId);
      if (previousOccupants.size === 0) {
        cellOccupants.delete(previousCellKey);
      }
    }
  }

  let occupants = cellOccupants.get(nextCellKey);
  if (!occupants) {
    occupants = new Set();
    cellOccupants.set(nextCellKey, occupants);
  }
  occupants.add(playerId);
  playerCellIndex.set(playerId, nextCellKey);
  player.cellKey = nextCellKey;
  return nextCellKey;
}

function collectVisiblePlayerIds(recipientId) {
  const recipient = players[recipientId];
  if (!recipient) return [];

  const { cx, cz } = getCellCoords(recipient.x, recipient.z);
  const ids = new Set();

  for (let dx = -CELL_REPLICATION_RADIUS; dx <= CELL_REPLICATION_RADIUS; dx += 1) {
    for (let dz = -CELL_REPLICATION_RADIUS; dz <= CELL_REPLICATION_RADIUS; dz += 1) {
      const cellKey = getCellKey(cx + dx, cz + dz);
      const occupants = cellOccupants.get(cellKey);
      if (!occupants) continue;
      for (const id of occupants) {
        ids.add(id);
      }
    }
  }

  ids.add(recipientId);
  return Array.from(ids);
}

function enqueueBackgroundJob(label, task) {
  backgroundJobs.push({ label, task });
  if (backgroundJobActive) {
    return;
  }

  backgroundJobActive = true;
  setImmediate(async () => {
    while (backgroundJobs.length > 0) {
      const job = backgroundJobs.shift();
      if (!job) {
        continue;
      }
      try {
        await job.task();
      } catch (error) {
        console.error(`[BackgroundJob] ${job.label} failed:`, error);
      }
    }
    backgroundJobActive = false;
  });
}

function isRateLimited(ws) {
  const ip = ws._socket?.remoteAddress || 'unknown';
  const banExpiry = ipBanTracker.get(ip);
  if (banExpiry && Date.now() < banExpiry) return true;
  if (banExpiry) ipBanTracker.delete(ip);

  const now = Date.now();
  let entry = rateLimitTracker.get(ws);
  if (!entry || now - entry.windowStart > WS_RATE_LIMIT_WINDOW_MS) {
    entry = { windowStart: now, count: 0 };
    rateLimitTracker.set(ws, entry);
  }
  entry.count++;
  if (entry.count > WS_RATE_LIMIT_MAX_MESSAGES) {
    ipBanTracker.set(ip, now + RATE_LIMIT_BAN_DURATION_MS);
    console.warn(`[RateLimit] Banned ${ip} for ${RATE_LIMIT_BAN_DURATION_MS}ms`);
    ws.close(1008, 'rate_limited');
    return true;
  }
  return false;
}

function createSessionToken(username) {
  const token = randomUUID().replace(/-/g, '');
  sessionTokens.set(token, {
    username,
    createdAt: Date.now()
  });
  return token;
}

function verifySessionToken(token) {
  const session = sessionTokens.get(token);
  if (!session) return null;
  if (Date.now() - session.createdAt > SESSION_TOKEN_EXPIRY_MS) {
    sessionTokens.delete(token);
    return null;
  }
  return session.username;
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

function resolveSkinName(value) {
  const key = String(value || '').trim().toLowerCase().replace(/\s+/g, ' ');
  return key || 's-default';
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

function setCors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  // `Authorization` is required by /auth/device/approve and /auth/me, which the
  // web approval page calls with a Privy access token.
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
}

function sendJson(res, status, payload) {
  setCors(res);
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(payload));
}

/**
 * Device-auth endpoints tolerate an empty body (the native client may POST with
 * no payload at all), so a parse failure is not treated as a hard error.
 */
async function readOptionalJsonBody(req) {
  try {
    return await readJsonBody(req);
  } catch (error) {
    return {};
  }
}

function getClientIp(req) {
  const forwarded = String(req.headers['x-forwarded-for'] || '');
  if (forwarded) return forwarded.split(',')[0].trim();
  return String(req.socket?.remoteAddress || '');
}

/** Maps an authService result onto an HTTP response, including Retry-After. */
function sendAuthResult(res, result) {
  if (result?.ok) {
    sendJson(res, result.status || 200, { ok: true, ...result.payload });
    return;
  }
  if (result?.retry_after) {
    setCors(res);
    res.setHeader('Retry-After', String(result.retry_after));
  }
  sendJson(res, result?.status || 500, { ok: false, error: result?.error || 'internal_error' });
}

async function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', (chunk) => {
      body += chunk;
      if (body.length > 1_000_000) {
        reject(new Error('Payload too large'));
      }
    });
    req.on('end', () => {
      if (!body) return resolve({});
      try {
        resolve(JSON.parse(body));
      } catch (error) {
        reject(error);
      }
    });
  });
}

const server = createServer(async (req, res) => {
  const reqUrl = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);

  if (req.method === 'OPTIONS') {
    setCors(res);
    res.writeHead(204);
    res.end();
    return;
  }

  if (req.method === 'GET' && reqUrl.pathname === '/') {
    setCors(res);
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('Server is alive and healthy!\\n');
    return;
  }

  if (req.method === 'GET' && reqUrl.pathname === '/events') {
    setCors(res);
    res.writeHead(200, {
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store'
    });
    res.end(JSON.stringify({
      type: 'events_snapshot',
      events: eventHistory
    }));
    return;
  }

  if (req.method === 'POST' && reqUrl.pathname === '/analytics/events') {
    try {
      const payload = await readJsonBody(req);
      const result = await logAnalyticsEvent(payload);
      if (!result.ok) {
        sendJson(res, 400, { ok: false, error: result.error });
        return;
      }
      sendJson(res, 200, { ok: true, id: result.id, timestamp: result.timestamp });
    } catch (error) {
      sendJson(res, 400, { ok: false, error: 'Invalid JSON payload' });
    }
    return;
  }

  if (req.method === 'GET' && reqUrl.pathname === '/analytics/summary') {
    const summary = await getAnalyticsSummary({
      start: reqUrl.searchParams.get('start'),
      end: reqUrl.searchParams.get('end')
    });
    sendJson(res, 200, summary);
    return;
  }

  if (req.method === 'GET' && reqUrl.pathname === '/analytics/timeseries') {
    const data = await getAnalyticsTimeseries({
      start: reqUrl.searchParams.get('start'),
      end: reqUrl.searchParams.get('end')
    });
    sendJson(res, 200, data);
    return;
  }

  if (req.method === 'GET' && reqUrl.pathname === '/analytics/export') {
    const format = reqUrl.searchParams.get('format') || 'json';
    const exportData = await exportAnalyticsEvents({
      format,
      start: reqUrl.searchParams.get('start'),
      end: reqUrl.searchParams.get('end')
    });
    setCors(res);
    res.writeHead(200, { 'Content-Type': exportData.contentType });
    res.end(exportData.body);
    return;
  }

  // ─── SKIN METADATA API ───
  if (req.method === 'GET' && reqUrl.pathname === '/api/skins') {
    const skins = await getAllSkins();
    sendJson(res, 200, { ok: true, skins });
    return;
  }

  // The ordered id -> combo index. Clients use it to resolve attachments for
  // numbered ids that have no per-skin document (unminted ids, previews), so
  // appending a combo to skinCombos.json lights it up everywhere at once.
  if (req.method === 'GET' && reqUrl.pathname === '/api/skin-combos') {
    sendJson(res, 200, { ok: true, combos: loadCombos(), defaults: loadDefaults() });
    return;
  }

  if (req.method === 'GET' && reqUrl.pathname === '/api/player-skin') {
    const username = (reqUrl.searchParams.get('username') || '').trim();
    if (!username) {
      sendJson(res, 400, { ok: false, error: 'username required' });
      return;
    }
    const skin = await getPlayerSkin(username);
    sendJson(res, 200, { ok: true, username, skin: skin || 's-default' });
    return;
  }

  if (req.method === 'GET' && reqUrl.pathname.startsWith('/api/skins/')) {
    const skinId = reqUrl.pathname.slice('/api/skins/'.length);
    if (!skinId) {
      sendJson(res, 400, { ok: false, error: 'Skin ID required' });
      return;
    }
    const skin = await getSkin(skinId);
    if (!skin) {
      sendJson(res, 404, { ok: false, error: 'Skin not found' });
      return;
    }
    sendJson(res, 200, { ok: true, skin });
    return;
  }

  if (req.method === 'POST' && reqUrl.pathname === '/admin/verify-access') {
    try {
      const payload = await readJsonBody(req);
      const code = typeof payload?.code === 'string' ? payload.code.trim() : '';
      const expected = process.env.ADMIN_ACCESS_CODE || 'WONS';
      if (code && code === expected) {
        sendJson(res, 200, { ok: true });
        return;
      }
      sendJson(res, 403, { ok: false, error: 'Invalid access code' });
    } catch (error) {
      sendJson(res, 400, { ok: false, error: 'Invalid JSON payload' });
    }
    return;
  }

  if (req.method === 'POST' && reqUrl.pathname === '/auth/request-token') {
    try {
      const payload = await readJsonBody(req);
      const username = typeof payload?.username === 'string' ? payload.username.trim().slice(0, 24) : '';
      if (!username) {
        sendJson(res, 400, { ok: false, error: 'username required' });
        return;
      }
      const token = createSessionToken(username);
      sendJson(res, 200, { ok: true, token, username });
    } catch (error) {
      sendJson(res, 400, { ok: false, error: 'Invalid request' });
    }
    return;
  }

  // ---------------------------------------------------------------------------
  // NATIVE DEVICE AUTH (QR / short-code device linking)
  //
  // Privy is the identity authority, this service is the account + session
  // authority, and the native Godot client is treated as untrusted throughout.
  // The web build keeps using Privy directly and never enters this flow.
  // See docs/authentication.md.
  // ---------------------------------------------------------------------------
  if (req.method === 'POST' && reqUrl.pathname === '/auth/device/start') {
    const body = await readOptionalJsonBody(req);
    const result = await startDeviceLogin({
      ip: getClientIp(req),
      platform: body?.platform,
      deviceId: body?.device_id,
      deviceLabel: body?.device_label
    });
    sendAuthResult(res, result);
    return;
  }

  if (req.method === 'GET' && reqUrl.pathname === '/auth/device/status') {
    const result = await getDeviceLoginStatus({ deviceLoginId: reqUrl.searchParams.get('device_login_id') });
    sendAuthResult(res, result);
    return;
  }

  if (req.method === 'GET' && reqUrl.pathname === '/auth/device/lookup') {
    const result = await lookupDeviceLogin({
      code: reqUrl.searchParams.get('code'),
      ip: getClientIp(req)
    });
    sendAuthResult(res, result);
    return;
  }

  if (req.method === 'POST' && reqUrl.pathname === '/auth/device/approve') {
    const body = await readOptionalJsonBody(req);
    const result = await approveDeviceLogin({
      authorizationHeader: req.headers.authorization,
      deviceLoginId: body?.device_login_id,
      code: body?.code
    });
    sendAuthResult(res, result);
    return;
  }

  if (req.method === 'POST' && reqUrl.pathname === '/auth/device/cancel') {
    const body = await readOptionalJsonBody(req);
    const result = await cancelDeviceLogin({ deviceLoginId: body?.device_login_id, secret: body?.secret });
    sendAuthResult(res, result);
    return;
  }

  if (req.method === 'POST' && reqUrl.pathname === '/auth/device/exchange') {
    const body = await readOptionalJsonBody(req);
    const result = await exchangeDeviceLogin({
      deviceLoginId: body?.device_login_id,
      secret: body?.secret,
      platform: body?.platform,
      deviceId: body?.device_id,
      ip: getClientIp(req)
    });
    sendAuthResult(res, result);
    return;
  }

  if (req.method === 'POST' && reqUrl.pathname === '/auth/refresh') {
    const body = await readOptionalJsonBody(req);
    const result = await refreshSession({
      refreshToken: body?.refresh_token,
      deviceId: body?.device_id,
      ip: getClientIp(req)
    });
    sendAuthResult(res, result);
    return;
  }

  if (req.method === 'POST' && reqUrl.pathname === '/auth/logout') {
    const body = await readOptionalJsonBody(req);
    const result = await logoutSession({ refreshToken: body?.refresh_token });
    sendAuthResult(res, result);
    return;
  }

  if (req.method === 'GET' && reqUrl.pathname === '/auth/me') {
    const result = await getAuthenticatedSession({ authorizationHeader: req.headers.authorization });
    sendAuthResult(res, result);
    return;
  }

  if (req.method === 'POST' && reqUrl.pathname === '/admin/update-user-roles') {
    try {
      const payload = await readJsonBody(req);
      const code = typeof payload?.code === 'string' ? payload.code.trim() : '';
      const { username, roles } = payload;
      const expected = process.env.ADMIN_ACCESS_CODE || 'WONS';

      if (code && code === expected) {
        if (!username || !Array.isArray(roles)) {
          sendJson(res, 400, { ok: false, error: 'Invalid payload: username and roles (array) required' });
          return;
        }
        await updateUserRoles(username, roles);
        sendJson(res, 200, { ok: true });
        return;
      }
      sendJson(res, 403, { ok: false, error: 'Invalid access code' });
    } catch (error) {
      console.error('[Admin] Failed to update user roles:', error);
      sendJson(res, 500, { ok: false, error: 'Internal server error' });
    }
    return;
  }

  if (req.method === 'POST' && reqUrl.pathname === '/admin/contract-withdraw') {
    try {
      const payload = await readJsonBody(req);
      const code = typeof payload?.code === 'string' ? payload.code.trim() : '';
      const contractAddress = typeof payload?.contractAddress === 'string' ? payload.contractAddress.trim() : '';
      const expected = process.env.ADMIN_ACCESS_CODE || 'WONS';

      if (!code || code !== expected) {
        sendJson(res, 403, { ok: false, error: 'Invalid access code' });
        return;
      }

      if (!contractAddress || !/^0x[a-fA-F0-9]{40}$/.test(contractAddress)) {
        sendJson(res, 400, { ok: false, error: 'Valid contract address required' });
        return;
      }

      const result = await contractWithdraw(contractAddress);
      if (result.success) {
        sendJson(res, 200, { ok: true, txHash: result.txHash });
      } else {
        sendJson(res, 500, { ok: false, error: result.error });
      }
    } catch (error) {
      console.error('[Admin] Withdraw failed:', error);
      sendJson(res, 500, { ok: false, error: 'Internal server error' });
    }
    return;
  }

  if (req.method === 'POST' && reqUrl.pathname === '/admin/create-skin') {
    try {
      const payload = await readJsonBody(req);
      const code = typeof payload?.code === 'string' ? payload.code.trim() : '';
      const expected = process.env.ADMIN_ACCESS_CODE || 'WONS';

      if (!code || code !== expected) {
        sendJson(res, 403, { ok: false, error: 'Invalid access code' });
        return;
      }

      const { onChainId, name, tier, price, maxSupply, requiredXP, image, skinConfig } = payload;
      if (!name || !skinConfig) {
        sendJson(res, 400, { ok: false, error: 'name and skinConfig are required' });
        return;
      }

      // 1. Predict next on-chain ID and save to Firebase FIRST
      let predictedOnChainId = null;
      if (maxSupply != null) {
        const idResult = await getNextSkinId();
        if (idResult.success) {
          predictedOnChainId = idResult.nextId;
        }
      }
      const skinId = onChainId || String(predictedOnChainId || `s-${Date.now()}`);
      const baseUrl = process.env.RENDER_EXTERNAL_URL || `https://worldofnads.onrender.com`;

      // Numeric ids own a combo in skinCombos.json: fill attachments from the
      // shared index unless the caller pinned them explicitly. Appending a
      // combo to that list is then all it takes for new ids to dress right.
      const resolvedSkinConfig = { ...(skinConfig || {}) };
      if (!Array.isArray(resolvedSkinConfig.attachments)) {
        const indexed = attachmentsForId(skinId);
        if (indexed) resolvedSkinConfig.attachments = indexed;
      }

      await saveSkin(skinId, {
        name,
        tier: tier || 'common',
        price: price || '0 MON',
        maxSupply: maxSupply || null,
        requiredXP: requiredXP || 0,
        image: image || '',
        onChainId: predictedOnChainId || null,
        skinConfig: resolvedSkinConfig
      });

      // 2. Create on-chain with correct URI pointing to Firebase
      let chainResult = null;
      if (maxSupply != null) {
        const priceStr = String(price || '0').replace(/[^0-9.]/g, '');
        const tierIndex = ['common','rare','epic','legendary'].indexOf((tier || 'common').toLowerCase());
        const uri = `${baseUrl}/api/skins/${skinId}`;
        chainResult = await createSkinOnchain(
          maxSupply,
          priceStr,
          requiredXP || 0,
          tierIndex >= 0 ? tierIndex : 0,
          uri
        );
        if (!chainResult.success) {
          // On-chain failed — update Firebase to reflect no on-chain ID
          chainResult = { success: false, skinId: skinId, error: chainResult.error };
        }
      }

      const resultId = chainResult?.skinId || skinId;
      const ok = !chainResult || chainResult.success !== false;
      sendJson(res, ok ? 200 : 500, {
        ok,
        skinId: resultId,
        txHash: chainResult?.txHash || null,
        ...(chainResult && !chainResult.success ? { error: chainResult.error } : {})
      });
    } catch (error) {
      console.error('[Admin] Create skin failed:', error);
      sendJson(res, 500, { ok: false, error: 'Internal server error' });
    }
    return;
  }

  if (req.method === 'POST' && reqUrl.pathname === '/admin/refresh-pfps') {
    try {
      const payload = await readJsonBody(req);
      const code = typeof payload?.code === 'string' ? payload.code.trim() : '';
      const expected = process.env.ADMIN_ACCESS_CODE || 'WONS';

      if (!code || code !== expected) {
        sendJson(res, 403, { ok: false, error: 'Invalid access code' });
        return;
      }

      const force = payload?.force === true;
      const result = await refreshAllUserPfps(force);
      sendJson(res, 200, { ok: true, ...result });
    } catch (error) {
      console.error('[Admin] PFP refresh failed:', error);
      sendJson(res, 500, { ok: false, error: 'Internal server error' });
    }
    return;
  }

  setCors(res);
  res.writeHead(404);
  res.end();
});

const gameWss = new WebSocketServer({ noServer: true });
const eventsWss = new WebSocketServer({ noServer: true });

// Heartbeat: a client that vanishes without a clean WebSocket close (tab killed,
// network drop, proxy timeout) would otherwise linger in `players` and keep being
// broadcast to everyone else at its last position - a frozen player. Ping every
// interval and terminate any socket that missed the previous pong, which fires the
// normal 'close' handler so the player is cleaned up and everyone is told.
// The Godot WebSocketPeer answers ping frames automatically during poll().
const GAME_HEARTBEAT_INTERVAL_MS = 30000;
const gameHeartbeat = setInterval(() => {
  gameWss.clients.forEach((client) => {
    if (client.isAlive === false) {
      client.terminate();
      return;
    }
    client.isAlive = false;
    client.ping();
  });
}, GAME_HEARTBEAT_INTERVAL_MS);
gameWss.on('close', () => clearInterval(gameHeartbeat));

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
    if (client.readyState === 1 && client.bufferedAmount < MAX_CLIENT_BUFFERED_BYTES) {
      client.send(payload);
    }
  });
}

function getPlayerCount() {
  return Object.keys(players).length;
}

function normalizeAnimId(data) {
  if (data && Number.isFinite(Number(data.anim_id))) {
    const n = Math.floor(Number(data.anim_id));
    if (Object.prototype.hasOwnProperty.call(ANIM_ID_TO_NAME, n)) return n;
  }
  if (data && typeof data.animation === 'string') {
    const key = data.animation.trim().toLowerCase();
    if (Object.prototype.hasOwnProperty.call(ANIM_NAME_TO_ID, key)) return ANIM_NAME_TO_ID[key];
  }
  return 0;
}

function normalizeLimitValue(value, fallback) {
  if (value === null || value === undefined) return fallback;
  if (typeof value === "string") {
    if (value.toLowerCase() === "unlimited") return null;
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
  }
  return Number.isFinite(value) ? value : fallback;
}

function updateMatchLimitsFromActiveMatch(activeMatch) {
  if (!activeMatch) {
    currentMinPlayersToStart = DEFAULT_MIN_PLAYERS_TO_START;
    currentMaxPlayers = null;
    return;
  }

  const minPlayers = normalizeLimitValue(activeMatch.minPlayersToStart, DEFAULT_MIN_PLAYERS_TO_START);
  const maxPlayers = normalizeLimitValue(activeMatch.maxPlayers, null);

  currentMinPlayersToStart = Math.max(1, Math.floor(minPlayers));
  if (maxPlayers === null) {
    currentMaxPlayers = null;
  } else {
    const normalizedMax = Math.max(1, Math.floor(maxPlayers));
    currentMaxPlayers = normalizedMax < currentMinPlayersToStart ? currentMinPlayersToStart : normalizedMax;
  }
}

function selectMatchForLimits(matchesMap) {
  if (!matchesMap) return null;
  const now = Math.floor(Date.now() / 1000);
  const matches = Object.values(matchesMap).filter((m) => {
    if (!m || !m.matchId || !m.startTime) return false;
    if (m.status === "cancelled" || m.status === "settled") return false;
    return true;
  });

  if (!matches.length) return null;

  const liveOrStarted = matches.filter((m) => m.status === "live" || (m.status === "upcoming" && m.startTime <= now));
  if (liveOrStarted.length) {
    return liveOrStarted.sort((a, b) => b.startTime - a.startTime)[0];
  }

  const upcoming = matches.filter((m) => m.status === "upcoming" && m.startTime > now);
  if (upcoming.length) {
    return upcoming.sort((a, b) => a.startTime - b.startTime)[0];
  }

  return null;
}

function buildMatchState() {
  return {
    timeLeft: Number(matchTimeLeft.toFixed(2)),
    isRunning: matchRunning,
    durationSeconds: MATCH_DURATION_SECONDS,
    minPlayersToStart: currentMinPlayersToStart,
    maxPlayers: currentMaxPlayers,
    stormRadius: Number(stormRadius.toFixed(4))
  };
}

function encodePlayerForNetwork(player) {
  return {
    id: player.id,
    x: quantizePosition(player.x),
    y: quantizePosition(player.y),
    z: quantizePosition(player.z),
    r: quantizeRotation(player.rotationY),
    a: normalizeAnimId(player),
    skin: player.skin || 'defaultnad'
  };
}

function buildEncodedPlayersMap() {
  const map = new Map();
  for (const player of Object.values(players)) {
    map.set(player.id, encodePlayerForNetwork(player));
  }
  return map;
}

function buildEncodedChicken() {
  return {
    i: chicken.id,
    x: quantizePosition(chicken.x),
    y: quantizePosition(chicken.y),
    z: quantizePosition(chicken.z),
    r: quantizeRotation(chicken.rotationY),
    h: chicken.isHeld ? 1 : 0,
    o: chicken.holderId || ''
  };
}

function buildEncodedLootbox() {
  return {
    i: lootbox.id,
    x: quantizePosition(lootbox.x),
    y: quantizePosition(lootbox.y),
    z: quantizePosition(lootbox.z),
    r: quantizeRotation(lootbox.rotationY),
    h: lootbox.isHeld ? 1 : 0,
    o: lootbox.holderId || ''
  };
}

function buildEncodedItem(item) {
  return {
    i: item.id,
    x: quantizePosition(item.x),
    y: quantizePosition(item.y),
    z: quantizePosition(item.z),
    r: quantizeRotation(item.rotationY),
    h: item.isHeld ? 1 : 0,
    o: item.holderId || ''
  };
}

function buildEncodedPowerUps() {
  const list = [];
  for (const id of POWER_UP_IDS) {
    list.push(buildEncodedItem(powerUps[id]));
  }
  return list;
}

function randomItemSpawnPoint() {
  const half = Math.max(ARENA_HALF_SIZE - ITEM_SPAWN_MARGIN, 1.0);
  return {
    x: (Math.random() * 2 - 1) * half,
    y: FLOOR_Y,
    z: (Math.random() * 2 - 1) * half,
    rotationY: Math.random() * Math.PI * 2
  };
}

function placeItemAtRandomSpawn(item) {
  const p = randomItemSpawnPoint();
  item.x = p.x;
  item.y = p.y;
  item.z = p.z;
  item.rotationY = p.rotationY;
  item.vx = 0;
  item.vy = 0;
  item.vz = 0;
}

// Re-rolls every item onto a fresh random spot with no holder. Called at server
// start and at the start of every match, so a new round never starts with last
// round's item positions.
function randomizeAllItemSpawns() {
  for (const id of POWER_UP_IDS) {
    const item = powerUps[id];
    item.isHeld = false;
    item.holderId = null;
    placeItemAtRandomSpawn(item);
  }
  chicken.isHeld = false;
  chicken.holderId = null;
  placeItemAtRandomSpawn(chicken);
  lootbox.isHeld = false;
  lootbox.holderId = null;
  placeItemAtRandomSpawn(lootbox);
}

// Resolves a client item id to the authoritative item object. Power-ups, the
// chicken and the lootbox are all server-tracked now. Returns null for anything
// unknown, so an unknown id can never fall back onto the chicken.
function resolveItemById(itemId) {
  if (itemId === 'Chicken') return chicken;
  if (itemId === 'LootBox') return lootbox;
  if (Object.prototype.hasOwnProperty.call(powerUps, itemId)) return powerUps[itemId];
  return null;
}

function itemEmoji(itemId) {
  if (itemId === 'Chicken') return '🥚';
  if (itemId === 'LootBox') return '📦';
  return '⚡';
}

// Drops every item held by this player at the player's last known position.
// Used on death (client asks for a drop) and on a full disconnect.
function dropHeldItemsAtPlayer(itemHolderId) {
  const holder = players[itemHolderId];
  const items = [chicken, lootbox];
  for (const id of POWER_UP_IDS) {
    items.push(powerUps[id]);
  }
  for (const item of items) {
    if (item.holderId !== itemHolderId) continue;
    item.isHeld = false;
    item.holderId = null;
    if (holder) {
      item.x = holder.x;
      item.y = holder.y;
      item.z = holder.z;
    }
    item.vx = 0;
    item.vy = 0;
    item.vz = 0;
  }
}

// Seed the world so the first pre-match snapshot already has spread-out items.
randomizeAllItemSpawns();

function buildEncodedMatch() {
  const matchState = buildMatchState();
  return {
    t: Math.round(matchState.timeLeft * 100),
    r: matchState.isRunning ? 1 : 0,
    d: Math.round(matchState.durationSeconds * 100),
    min: matchState.minPlayersToStart,
    max: matchState.maxPlayers,
    sr: Math.round(matchState.stormRadius * 100),
    pl: getPlayerCount(),
    c: matchStartCountdown >= 0 ? Math.max(0, Math.ceil(matchStartCountdown)) : 0
  };
}

function getUpdateRateForDistance(distance) {
  if (distance <= NEAR_UPDATE_DISTANCE) {
    return NEAR_UPDATE_RATE;
  }
  if (distance <= MEDIUM_UPDATE_DISTANCE) {
    return MEDIUM_UPDATE_RATE;
  }
  return FAR_UPDATE_RATE;
}

function getUpdateIntervalMsForDistance(distance) {
  return 1000 / getUpdateRateForDistance(distance);
}

function shallowEqualObject(a, b) {
  if (a === b) return true;
  if (!a || !b) return false;
  const aKeys = Object.keys(a);
  const bKeys = Object.keys(b);
  if (aKeys.length !== bKeys.length) return false;
  for (const key of aKeys) {
    if (a[key] !== b[key]) return false;
  }
  return true;
}

// Per-item equality for the power-up snapshot. Both sides are short arrays of
// flat encoded objects, so an element-wise shallow compare is exact and cheap.
function shallowEqualItemArray(a, b) {
  if (a === b) return true;
  if (!a || !b || a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (!shallowEqualObject(a[i], b[i])) return false;
  }
  return true;
}

function cloneEncodedPlayersMap(currentPlayers) {
  return new Map(Array.from(currentPlayers.entries(), ([id, encoded]) => [id, { ...encoded }]));
}

function getRecipientNetworkState(recipientId) {
  let state = recipientNetworkState.get(recipientId);
  if (!state) {
    state = {
      lastSentPlayers: new Map(),
      lastSentPlayerAt: new Map(),
      lastSentChicken: null,
      lastSentLootbox: null,
      lastSentPowerUps: null,
      lastSentMatch: null,
      lastFullSnapshotAt: 0,
      lastMatchHeartbeatAt: 0
    };
    recipientNetworkState.set(recipientId, state);
  }
  return state;
}

// Drops a disconnected player from every recipient's last-sent bookkeeping, so no
// later delta or full snapshot re-announces them once the removal was broadcast.
function forgetPlayerForAllRecipients(playerId) {
  for (const state of recipientNetworkState.values()) {
    state.lastSentPlayers.delete(playerId);
    state.lastSentPlayerAt.delete(playerId);
  }
}

function buildRecipientPayload(recipientId, currentPlayers, currentChicken, currentLootbox, currentMatch, currentPowerUps, now) {
  const recipient = players[recipientId];
  if (!recipient) {
    return null;
  }

  const state = getRecipientNetworkState(recipientId);
  const shouldSendFullSnapshot = (now - state.lastFullSnapshotAt) >= FULL_SNAPSHOT_INTERVAL_MS;
  const shouldSendMatchHeartbeat = (now - state.lastMatchHeartbeatAt) >= MATCH_HEARTBEAT_INTERVAL_MS;
  const visibleIds = collectVisiblePlayerIds(recipientId);
  const visiblePlayers = new Map();
  for (const id of visibleIds) {
    const encoded = currentPlayers.get(id);
    if (encoded) {
      visiblePlayers.set(id, encoded);
    }
  }

  if (shouldSendFullSnapshot) {
    const fullPlayers = Array.from(visiblePlayers.values()).map((p) => {
      const source = players[p.id];
      return source ? { ...p, u: source.username } : { ...p };
    });

    state.lastSentPlayers = cloneEncodedPlayersMap(visiblePlayers);
    state.lastSentPlayerAt = new Map(Array.from(visiblePlayers.keys(), (id) => [id, now]));
    state.lastSentChicken = { ...currentChicken };
    state.lastSentLootbox = { ...currentLootbox };
    state.lastSentPowerUps = currentPowerUps.map((item) => ({ ...item }));
    state.lastSentMatch = { ...currentMatch };
    state.lastFullSnapshotAt = now;
    state.lastMatchHeartbeatAt = now;

    return {
      type: 'state_full',
      q: 1,
      players: fullPlayers,
      chicken: currentChicken,
      lootbox: currentLootbox,
      items: currentPowerUps,
      match: currentMatch
    };
  }

  const payload = {
    type: 'state_delta',
    q: 1
  };

  const changedPlayers = [];
  for (const [id, encoded] of visiblePlayers.entries()) {
    const currentPos = players[id];
    if (!currentPos) {
      continue;
    }

    const distance = length3(
      currentPos.x - recipient.x,
      currentPos.y - recipient.y,
      currentPos.z - recipient.z
    );
    const lastSentAt = Number(state.lastSentPlayerAt.get(id) || 0);
    const intervalMs = getUpdateIntervalMsForDistance(distance);
    const due = (now - lastSentAt) >= intervalMs;

    if (due) {
      changedPlayers.push(encoded);
      state.lastSentPlayers.set(id, { ...encoded });
      state.lastSentPlayerAt.set(id, now);
    }
  }

  const removedPlayerIds = [];
  for (const id of state.lastSentPlayers.keys()) {
    if (!visiblePlayers.has(id)) {
      removedPlayerIds.push(id);
      state.lastSentPlayers.delete(id);
      state.lastSentPlayerAt.delete(id);
    }
  }

  const chickenChanged = !shallowEqualObject(state.lastSentChicken, currentChicken);
  const lootboxChanged = !shallowEqualObject(state.lastSentLootbox, currentLootbox);
  const powerUpsChanged = !shallowEqualItemArray(state.lastSentPowerUps, currentPowerUps);
  const matchChanged = !shallowEqualObject(state.lastSentMatch, currentMatch);

  if (changedPlayers.length > 0) {
    payload.players = changedPlayers;
  }
  if (removedPlayerIds.length > 0) {
    payload.removed = removedPlayerIds;
  }
  if (chickenChanged || shouldSendMatchHeartbeat) {
    payload.chicken = currentChicken;
    state.lastSentChicken = { ...currentChicken };
  }
  if (lootboxChanged || shouldSendMatchHeartbeat) {
    payload.lootbox = currentLootbox;
    state.lastSentLootbox = { ...currentLootbox };
  }
  if (powerUpsChanged || shouldSendMatchHeartbeat) {
    payload.items = currentPowerUps;
    state.lastSentPowerUps = currentPowerUps.map((item) => ({ ...item }));
  }
  if (matchChanged || shouldSendMatchHeartbeat) {
    payload.match = currentMatch;
    state.lastSentMatch = { ...currentMatch };
    state.lastMatchHeartbeatAt = now;
  }

  if (!payload.players && !payload.removed && !payload.chicken && !payload.lootbox && !payload.items && !payload.match) {
    return null;
  }

  return payload;
}

function broadcastPayload(payload) {
  const body = mpEncode(payload);
  gameWss.clients.forEach((client) => {
    if (client.readyState === 1 && client.bufferedAmount < MAX_CLIENT_BUFFERED_BYTES) {
      client.send(body);
    }
  });
}

function restartMatchIfEligible() {
  matchTimeLeft = MATCH_DURATION_SECONDS;
  // Minimum players to start is 3 (for now)
  matchRunning = getPlayerCount() >= 3;
  if (matchRunning) {
    matchStartedThisRound = true;
  }
}

function resolveRoundWinner() {
  let winnerId = '';
  let winnerName = 'No one';
  let secondId = '';
  let secondName = '';

  if (chicken.isHeld && chicken.holderId) {
    const holder = players[chicken.holderId];
    if (holder) {
      winnerId = holder.id;
      winnerName = holder.username || `player-${holder.id.slice(0, 8)}`;
    }
  }

  if (lootbox.isHeld && lootbox.holderId) {
    const holder = players[lootbox.holderId];
    if (holder) {
      secondId = holder.id;
      secondName = holder.username || `player-${holder.id.slice(0, 8)}`;
    }
  }

  return { winnerId, winnerName, secondId, secondName };
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

function resetLootBoxState() {
  lootbox.x = DEFAULT_LOOTBOX_STATE.x;
  lootbox.y = DEFAULT_LOOTBOX_STATE.y;
  lootbox.z = DEFAULT_LOOTBOX_STATE.z;
  lootbox.rotationY = DEFAULT_LOOTBOX_STATE.rotationY;
  lootbox.isHeld = false;
  lootbox.holderId = null;
  lootbox.vx = 0;
  lootbox.vy = 0;
  lootbox.vz = 0;
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
  playerCellIndex.clear();
  cellOccupants.clear();

  resetChickenState();
  resetLootBoxState();
  randomizeAllItemSpawns();
  matchRunning = false;
  matchTimeLeft = MATCH_DURATION_SECONDS;
  matchStartedThisRound = false;
  matchStartCountdown = -1;

  stormRadius = 20.0;
  stormShrinkTimer = 0.0;
  stormIsShrinking = false;
  stormShrinkProgress = 0.0;
  stormStartRadius = 20.0;
  stormTargetRadius = 20.0;

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
  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });

  if (currentMaxPlayers !== null && getPlayerCount() >= currentMaxPlayers) {
    ws.close(1008, 'match_full');
    return;
  }

  const playerId = randomUUID();
  // Set when the socket closes, so an in-flight profile fetch cannot resurrect the
  // player after the 'close' cleanup has already removed it.
  let connectionClosed = false;
  const reqUrl = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);
  const rawParam = (reqUrl.searchParams.get('username') || '').trim();
  const requestedSkin = resolveSkinName(reqUrl.searchParams.get('skin') || reqUrl.searchParams.get('skinId') || '');

  // Extract session token from username param (format: "<token>:<username>")
  let username = `player-${playerId.slice(0, 8)}`;
  if (rawParam !== '') {
    const colonIdx = rawParam.indexOf(':');
    if (colonIdx > 0) {
      const tokenPart = rawParam.slice(0, colonIdx);
      const resolvedUsername = verifySessionToken(tokenPart);
      if (resolvedUsername) {
        username = sanitizeUsername(resolvedUsername);
        ws.authToken = tokenPart;
      } else {
        console.warn(`[Auth] Invalid session token, rejecting`);
        ws.close(1008, 'invalid_token');
        return;
      }
    } else {
      username = sanitizeUsername(rawParam);
    }
  }

  const requestedOrDefaultSkin = requestedSkin || 's-default';

  getPlayerProfile(username).then(async (profile) => {
    const xp = profile?.xp || 0;
    const walletAddress = await getPlayerWallet(username);
    const firebaseSkin = resolveSkinName(profile?.skin || profile?.equippedSkinId || profile?.selectedSkin || profile?.selectedSkinId || profile?.skinName || profile?.skinId || await getPlayerSkin(username) || '');
    const resolvedSkin = firebaseSkin || requestedOrDefaultSkin;

    if (connectionClosed) return; // socket dropped mid-fetch; do not resurrect it

    players[playerId] = {
      id: playerId,
      username,
      walletAddress,
      skin: resolvedSkin,
      x: 0,
      y: 0,
      z: 0,
      rotationY: 0,
      animation: 'idle',
      xp: xp,
      lastUpdateAt: Date.now()
    };
    updatePlayerCellIndex(playerId, players[playerId]);

    console.log(`🎮 Player connected: ${playerId} (${username}) skin=${resolvedSkin} xp=${xp}`);
    ws.playerId = playerId;
    ws.send(mpEncode({ type: 'connect', id: playerId, username, skin: resolvedSkin, xp }));
    getRecipientNetworkState(playerId);
    // Kick off the pre-start countdown as soon as enough players are in; the sim
    // loop flips matchRunning once MATCH_START_COUNTDOWN_SECONDS elapses.
    if (!matchRunning && matchStartCountdown < 0 && getPlayerCount() >= currentMinPlayersToStart) {
      matchStartCountdown = MATCH_START_COUNTDOWN_SECONDS;
    }
  }).catch((err) => {
    console.error(`[Firebase] Failed to fetch profile for ${username}:`, err);
    if (connectionClosed) return;
    const resolvedSkin = requestedOrDefaultSkin;
    players[playerId] = {
      id: playerId,
      username,
      walletAddress: null,
      skin: resolvedSkin,
      x: 0,
      y: 0,
      z: 0,
      rotationY: 0,
      animation: 'idle',
      xp: 0,
      lastUpdateAt: Date.now()
    };
    updatePlayerCellIndex(playerId, players[playerId]);
    ws.playerId = playerId;
    ws.send(mpEncode({ type: 'connect', id: playerId, username, skin: resolvedSkin, xp: 0 }));
  });

  ws.on('message', (message) => {
    if (isRateLimited(ws)) return;
    if (message.length > WS_MAX_MESSAGE_SIZE) {
      ws.close(1009, 'message_too_large');
      return;
    }

    try {
      const data = mpDecode(new Uint8Array(message));
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
        const hasQuantizedPos = Number.isFinite(Number(data.qx)) && Number.isFinite(Number(data.qy)) && Number.isFinite(Number(data.qz));
        const nx = hasQuantizedPos ? dequantizePosition(Number(data.qx)) : Number(data.x);
        const ny = hasQuantizedPos ? dequantizePosition(Number(data.qy)) : Number(data.y);
        const nz = hasQuantizedPos ? dequantizePosition(Number(data.qz)) : Number(data.z);
        const hasQuantizedRot = Number.isFinite(Number(data.qrot));
        const nrot = hasQuantizedRot ? dequantizeRotation(Number(data.qrot)) : Number(data.rotation_y);
        const animId = normalizeAnimId(data);
        const isSliding = Boolean(data.slide) || animId === 4 || (typeof data.animation === 'string' && data.animation.trim().toLowerCase() === 'runningslide');

        if (!Number.isFinite(nx) || !Number.isFinite(ny) || !Number.isFinite(nz) || !Number.isFinite(nrot)) {
          return;
        }

        const now = Date.now();
        const elapsedSec = Math.min((now - (player.lastUpdateAt || now)) / 1000, 0.5);
        player.lastUpdateAt = now;

        const dx = nx - player.x;
        const dy = ny - player.y;
        const dz = nz - player.z;
        const stepScale = Math.max(elapsedSec, FIXED_DT);
        // Clamp horizontal and vertical independently. Horizontal keeps the tight
        // anti-teleport cap (with the slide allowance), while vertical gets its own
        // larger cap so jumps/falls are not squashed.
        const maxHorizontalStep = MAX_PLAYER_SPEED * stepScale * (isSliding ? 1.75 : 1.0);
        const maxVerticalStep = MAX_PLAYER_VERTICAL_SPEED * stepScale;

        const horizontalDist = Math.sqrt(dx * dx + dz * dz);
        if (horizontalDist <= maxHorizontalStep || horizontalDist === 0) {
          player.x = nx;
          player.z = nz;
        } else {
          const scale = maxHorizontalStep / horizontalDist;
          player.x += dx * scale;
          player.z += dz * scale;
        }

        if (Math.abs(dy) <= maxVerticalStep || dy === 0) {
          player.y = ny;
        } else {
          player.y += Math.sign(dy) * maxVerticalStep;
        }

        player.rotationY = nrot;
        player.animation = ANIM_ID_TO_NAME[animId] || 'idle';
        if (typeof data.skin === 'string') {
          player.skin = resolveSkinName(data.skin);
        }
        updatePlayerCellIndex(playerId, player);

      }

      if (data.type === 'pickup_request') {
        // Server-authoritative hold. The client claims the grab, but the server
        // owns who holds each item (power-ups, chicken, lootbox) and where it is.
        // Last claim wins, so a player can snatch an item off another's back.
        const itemId = typeof data.item_id === 'string' ? data.item_id : '';
        const item = resolveItemById(itemId);
        if (!item) {
          return;
        }
        if (item.isHeld && item.holderId === playerId) {
          return;
        }
        const previousHolder = item.holderId;
        item.isHeld = true;
        item.holderId = playerId;
        const emoji = itemEmoji(itemId);
        if (previousHolder && previousHolder !== playerId) {
          console.log(`${emoji} ${itemId} stolen by ${playerId} from ${previousHolder}`);
        } else {
          console.log(`${emoji} ${itemId} picked by ${playerId}`);
        }
      }

      if (data.type === 'use_request') {
        // A carried power-up was used: it is consumed and re-rolled to a new
        // random spot on the map. Only the current holder may use it, and only
        // power-ups can be used (the chicken/lootbox are carried, never used).
        const itemId = typeof data.item_id === 'string' ? data.item_id : '';
        const item = resolveItemById(itemId);
        if (!item || !POWER_UP_IDS.includes(itemId) || !item.isHeld || item.holderId !== playerId) {
          return;
        }
        item.isHeld = false;
        item.holderId = null;
        placeItemAtRandomSpawn(item);
        console.log(`${itemEmoji(itemId)} ${itemId} used by ${playerId}`);
      }

      if (data.type === 'drop_request') {
        // Dropped on death or on purpose: it lands where the server last saw the
        // player, so every client sees it in the same spot.
        const itemId = typeof data.item_id === 'string' ? data.item_id : '';
        const item = resolveItemById(itemId);
        if (!item || !item.isHeld || item.holderId !== playerId) {
          return;
        }
        item.isHeld = false;
        item.holderId = null;
        item.x = player.x;
        item.y = player.y;
        item.z = player.z;
        item.vx = 0;
        item.vy = 0;
        item.vz = 0;
        console.log(`${itemEmoji(itemId)} ${itemId} dropped by ${playerId}`);
      }

      if (data.type === 'request_full_state') {
        const state = recipientNetworkState.get(playerId);
        if (state) {
          state.lastFullSnapshotAt = 0;
        }
      }
    } catch (error) {
      console.error('Failed to parse message:', error);
    }
  });

  ws.on('close', () => {
    connectionClosed = true;
    rateLimitTracker.delete(ws);

    // Clean up session token
    if (ws.authToken) {
      sessionTokens.delete(ws.authToken);
    }

    console.log(`💀 Player disconnected: ${playerId}`);

    if (!isBatchResetting) {
      publishEvent(
        'player_left',
        `${username} left the game`,
        playerId,
        {}
      );
    }

    // Drop anything this player was carrying where they were last seen, so the
    // items stay in the world instead of vanishing with them.
    dropHeldItemsAtPlayer(playerId);
    delete players[playerId];
    removePlayerFromCellIndex(playerId);
    recipientNetworkState.delete(playerId);

    // Tell every remaining client to drop this player now, instead of leaving
    // them frozen at their last broadcast position, and forget them so no later
    // delta or full snapshot re-announces them. Skipped during a batch reset,
    // which closes every client at once and resets the world itself.
    if (!isBatchResetting) {
      forgetPlayerForAllRecipients(playerId);
      broadcastPayload({ type: 'state_delta', q: 1, removed: [playerId] });
    }
    if (!matchStartedThisRound && getPlayerCount() < currentMinPlayersToStart) {
      matchRunning = false;
      matchTimeLeft = MATCH_DURATION_SECONDS;
      matchStartCountdown = -1;
    }
  });
});

async function retry(fn, label, retries = 2) {
  for (let attempt = 1; attempt <= retries; attempt++) {
    try {
      return await fn();
    } catch (error) {
      if (attempt < retries) {
        console.warn(`[Worker] ${label} failed (attempt ${attempt}/${retries}): ${error.message}. Retrying...`);
        await new Promise(r => setTimeout(r, 1000 * attempt));
      } else {
        throw error;
      }
    }
  }
}

const STALE_MATCH_GRACE_SECONDS = 3600; // 1 hour past startTime -> cancel

const statusWorkerInterval = setInterval(() => {
  enqueueBackgroundJob("match-status-worker", async () => {
    const now = Math.floor(Date.now() / 1000);
    const fiveMinutes = 300;
    const matchBuffer = 60;

    let matches;
    try {
      matches = await retry(() => getAllMatches(), "getAllMatches");
    } catch (error) {
      console.error(`[Worker] getAllMatches failed after retries:`, error.message);
      return;
    }

    if (!matches) return;

    for (const match of Object.values(matches)) {
      const { matchId, status, startTime } = match;
      if (!matchId || !startTime) continue;

      try {
        // 1. Upcoming -> Live (5 minutes before startTime)
        if (status === "upcoming" && now >= startTime - fiveMinutes && now < startTime + STALE_MATCH_GRACE_SECONDS) {
          console.log(`[Worker] [${new Date().toISOString()}] Match ${matchId} (Starts: ${new Date(startTime * 1000).toISOString()}) -> LIVE.`);
          await retry(() => updateMatchStatus(matchId, "live"), `updateMatchStatus(${matchId})`);
          await logAnalyticsEvent({
            event_type: 'match_started',
            match_id: matchId,
            sponsor_id: match.sponsor || '',
            value: Number(match.prizeAmount || 0),
            metadata: { startTime, status: 'live' }
          });
        }

        // 2. Live -> Completed (Duration + buffer after startTime)
        if (status === "live" && now >= startTime + MATCH_DURATION_SECONDS + matchBuffer) {
          console.log(`[Worker] [${new Date().toISOString()}] Match ${matchId} (Started: ${new Date(startTime * 1000).toISOString()}) -> COMPLETED.`);
          await retry(() => updateMatchStatus(matchId, "completed"), `updateMatchStatus(${matchId})`);
          await logAnalyticsEvent({
            event_type: 'match_finished',
            match_id: matchId,
            sponsor_id: match.sponsor || '',
            value: Number(match.prizeAmount || 0),
            metadata: { startTime, status: 'completed' }
          });
        }

        // 3. Stale upcoming -> cancelled (well past startTime without going live)
        if (status === "upcoming" && now >= startTime + STALE_MATCH_GRACE_SECONDS) {
          console.log(`[Worker] [${new Date().toISOString()}] Match ${matchId} (Started: ${new Date(startTime * 1000).toISOString()}) -> CANCELLED (stale).`);
          await retry(() => updateMatchStatus(matchId, "cancelled"), `updateMatchStatus(${matchId})`);
          await logAnalyticsEvent({
            event_type: 'match_cancelled',
            match_id: matchId,
            sponsor_id: match.sponsor || '',
            value: Number(match.prizeAmount || 0),
            metadata: { startTime, status: 'cancelled', reason: 'stale' }
          });
        }
      } catch (error) {
        console.error(`[Worker] Failed to process match ${matchId}:`, error.message);
      }
    }
  });
}, 30000); // Run every 30 seconds

setInterval(() => {
  if (matchRunning) {
    matchTimeLeft -= FIXED_DT;

    // Server-authoritative storm shrink
    if (stormIsShrinking) {
      stormShrinkProgress += FIXED_DT;
      const t = Math.min(stormShrinkProgress / STORM_SHRINK_DURATION, 1.0);
      const smoothT = t * t * (3.0 - 2.0 * t);
      stormRadius = stormStartRadius + (stormTargetRadius - stormStartRadius) * smoothT;
      if (stormShrinkProgress >= STORM_SHRINK_DURATION) {
        stormIsShrinking = false;
        stormShrinkTimer = 0.0;
        stormRadius = stormTargetRadius;
      }
    } else {
      stormShrinkTimer += FIXED_DT;
      if (stormShrinkTimer >= STORM_SHRINK_INTERVAL) {
        stormStartRadius = stormRadius;
        stormTargetRadius = Math.max(stormStartRadius - STORM_SHRINK_STEP, STORM_MIN_RADIUS);
        if (stormTargetRadius < stormStartRadius) {
          stormIsShrinking = true;
          stormShrinkProgress = 0.0;
        }
      }
    }


    if (matchTimeLeft <= 0) {
      const winner = resolveRoundWinner();

      if (winner.winnerId) {
        const secondPart = winner.secondId ? `, ${winner.secondName} came 2nd` : '';
        publishEvent('match_winner', `${winner.winnerName} won the round${secondPart}`, winner.winnerId, {
          winnerId: winner.winnerId,
          winnerName: winner.winnerName,
          secondId: winner.secondId || '',
          secondName: winner.secondName || ''
        });
      } else {
        const secondPart = winner.secondId ? `, ${winner.secondName} came 2nd` : '';
        publishEvent('match_winner', `No winner this round${secondPart}`, '', {
          winnerId: null,
          winnerName: 'No one',
          secondId: winner.secondId || '',
          secondName: winner.secondName || ''
        });
      }
      resetRoundForNextBatch();
    }
  } else if (!matchStartedThisRound) {
    matchTimeLeft = MATCH_DURATION_SECONDS;
    if (matchStartCountdown >= 0) {
      matchStartCountdown -= FIXED_DT;
      if (matchStartCountdown <= 0) {
        matchStartCountdown = -1;
        matchRunning = true;
        matchStartedThisRound = true;
        randomizeAllItemSpawns();
      }
    } else if (getPlayerCount() >= currentMinPlayersToStart) {
      matchStartCountdown = MATCH_START_COUNTDOWN_SECONDS;
    }
  }


  const now = Date.now();
  const currentPlayers = buildEncodedPlayersMap();
  const currentChicken = buildEncodedChicken();
  const currentLootbox = buildEncodedLootbox();
  const currentPowerUps = buildEncodedPowerUps();
  const currentMatch = buildEncodedMatch();

  for (const client of gameWss.clients) {
    if (client.readyState !== 1 || client.bufferedAmount >= MAX_CLIENT_BUFFERED_BYTES) {
      continue;
    }
    const recipientId = client.playerId;
    if (!recipientId) {
      continue;
    }
    const payload = buildRecipientPayload(recipientId, currentPlayers, currentChicken, currentLootbox, currentMatch, currentPowerUps, now);
    if (payload) {
      client.send(mpEncode(payload));
    }
  }
}, 1000 / BROADCAST_RATE);

initAnalyticsDb()
  .then(() => {
    updateMatchLimitsFromActiveMatch(null);
    setInterval(async () => {
      try {
        const allMatches = await getAllMatches();
        const matchForLimits = selectMatchForLimits(allMatches);
        updateMatchLimitsFromActiveMatch(matchForLimits);
      } catch (error) {
        console.error("[Match] Failed to refresh match limits:", error);
      }
    }, 15000);

    // Refresh user profile pictures from Privy every 6 hours
    // First run is forced to clean up stale timestamps from previous failed runs
    const SIX_HOURS_MS = 6 * 60 * 60 * 1000;
    refreshAllUserPfps(true).catch((err) => {
      console.error('[PfpRefresh] Initial refresh failed:', err.message);
    });
    setInterval(() => {
      refreshAllUserPfps().catch((err) => {
        console.error('[PfpRefresh] Scheduled refresh failed:', err.message);
      });
    }, SIX_HOURS_MS);

    server.listen(PORT, '0.0.0.0', () => {
      console.log(`✅ Server is live on port ${PORT}`);
    });
  })
  .catch((error) => {
    console.error('[Analytics] Failed to initialize analytics database', error);
    process.exit(1);
  });
