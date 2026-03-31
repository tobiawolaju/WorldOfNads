import { createServer } from 'http';
import { WebSocketServer } from 'ws';
import { randomUUID } from 'crypto';
import { getPlayerWallet, findActiveMatch, markMatchSettled, getAllMatches, updateMatchStatus, saveReward } from './firebaseClient.js';
import { settleMatchOnchain } from './contractClient.js';
import { initAnalyticsDb, logAnalyticsEvent, getAnalyticsSummary, getAnalyticsTimeseries, exportAnalyticsEvents } from './analyticsService.js';

const PORT = process.env.PORT || 8080;
const BROADCAST_RATE = 20;
const FIXED_DT = 1 / BROADCAST_RATE;

const MAX_PLAYER_SPEED = 12.0; // units/sec server-side clamp against teleport cheating
const PICKUP_RADIUS = 1.1;
const MAX_THROW_IMPULSE = 8.0;
const CHICKEN_GRAVITY = 14.0;
const FLOOR_Y = 0.5869336;
const MATCH_DURATION_SECONDS = 180.0;
const DEFAULT_MIN_PLAYERS_TO_START = 3;

const MAX_EVENT_HISTORY = 100;
let eventSequence = 0;
const eventHistory = [];

const players = {};
let matchTimeLeft = MATCH_DURATION_SECONDS;
let matchRunning = false;
let matchStartedThisRound = false;
let isBatchResetting = false;
let currentMinPlayersToStart = DEFAULT_MIN_PLAYERS_TO_START;
let currentMaxPlayers = null;

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

function setCors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}

function sendJson(res, status, payload) {
  setCors(res);
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(payload));
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

  setCors(res);
  res.writeHead(404);
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
    maxPlayers: currentMaxPlayers
  };
}

function restartMatchIfEligible() {
  matchTimeLeft = MATCH_DURATION_SECONDS;
  matchRunning = getPlayerCount() >= currentMinPlayersToStart;
  if (matchRunning) {
    matchStartedThisRound = true;
  }
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
  matchStartedThisRound = false;

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
  if (currentMaxPlayers !== null && getPlayerCount() >= currentMaxPlayers) {
    ws.close(1008, 'match_full');
    return;
  }

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
  if (!matchRunning && getPlayerCount() >= currentMinPlayersToStart) {
    matchRunning = true;
    matchStartedThisRound = true;
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
        const dist = length3(
          chicken.x - player.x,
          chicken.y - player.y,
          chicken.z - player.z
        );

        if (dist <= PICKUP_RADIUS) {
          if (chicken.isHeld && chicken.holderId === playerId) {
            return;
          }

          const previousHolder = chicken.holderId;
          chicken.isHeld = true;
          chicken.holderId = playerId;
          chicken.vx = 0;
          chicken.vy = 0;
          chicken.vz = 0;
          if (previousHolder && previousHolder !== playerId) {
            console.log(`🐔 Chicken stolen by ${playerId} from ${previousHolder}`);
          } else {
            console.log(`🐔 Chicken picked by ${playerId}`);
          }
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
    if (!matchStartedThisRound && getPlayerCount() < currentMinPlayersToStart) {
      matchRunning = false;
      matchTimeLeft = MATCH_DURATION_SECONDS;
    }
  });
});

const statusWorkerInterval = setInterval(async () => {
  try {
    const matches = await getAllMatches();
    const now = Math.floor(Date.now() / 1000);
    const fiveMinutes = 300;
    const matchBuffer = 60; // Extra minute after duration

    for (const match of Object.values(matches)) {
      const { matchId, status, startTime } = match;
      if (!matchId || !startTime) continue;

      // 1. Upcoming -> Live (5 minutes before startTime)
      if (status === "upcoming" && now >= startTime - fiveMinutes) {
        console.log(`[Worker] [${new Date().toISOString()}] Match ${matchId} (Starts: ${new Date(startTime * 1000).toISOString()}) is now LIVE.`);
        await updateMatchStatus(matchId, "live");
        await logAnalyticsEvent({
          event_type: 'match_started',
          match_id: matchId,
          sponsor_id: match.sponsor || '',
          value: Number(match.prizeAmount || 0),
          metadata: {
            startTime,
            status: 'live'
          }
        });
      }

      // 2. Live -> Completed (Duration + buffer after startTime)
      // Duration is 180s, so we wait 180s + 60s buffer = 240s
      if (status === "live" && now >= startTime + MATCH_DURATION_SECONDS + matchBuffer) {
        console.log(`[Worker] [${new Date().toISOString()}] Match ${matchId} (Started: ${new Date(startTime * 1000).toISOString()}) is now COMPLETED.`);
        await updateMatchStatus(matchId, "completed");
        await logAnalyticsEvent({
          event_type: 'match_finished',
          match_id: matchId,
          sponsor_id: match.sponsor || '',
          value: Number(match.prizeAmount || 0),
          metadata: {
            startTime,
            status: 'completed'
          }
        });
      }
    }
  } catch (error) {
    console.error("[Worker] Error updating match statuses:", error);
  }
}, 30000); // Run every 30 seconds for better precision

setInterval(() => {
  if (matchRunning) {
    matchTimeLeft -= FIXED_DT;
    if (matchTimeLeft <= 0) {
      const winner = resolveRoundWinner();
      const participantNames = Object.values(players).map(p => p.username);

      // Perform On-chain Settlement if it's a sponsored match
      (async (winnerInfo, allParticipants) => {
        try {
          console.log(`[Payout-Debug] Round ended. Potential winner: ${winnerInfo.winnerName}`);
          const activeMatch = await findActiveMatch();

          if (!activeMatch) {
            console.log(`[Payout-Debug] No 'upcoming' or 'live' matches found in Firebase for payout.`);
            return;
          }

          console.log(`[Payout-Debug] Found candidate match: ${activeMatch.matchId} (Status: ${activeMatch.status})`);

          if (winnerInfo.winnerId && winnerInfo.winnerName !== 'No one') {
            console.log(`[Payout] Sponsored match found: ${activeMatch.matchId}. Resolving for winner ${winnerInfo.winnerName}...`);

            // Get winner's wallet
            const winnerWallet = await getPlayerWallet(winnerInfo.winnerName);

            if (winnerWallet) {
              console.log(`[Payout] Winner ${winnerInfo.winnerName} wallet: ${winnerWallet}`);

              // Get all participant wallets (for the NFT mints)
              // Note: winner MUST be in this list for the contract to succeed
              const participantPromises = allParticipants.map(name => getPlayerWallet(name));
              const allWallets = await Promise.all(participantPromises);
              let validParticipants = [...new Set(allWallets.filter(w => !!w))]; // unique valid wallets

              // safety: ensure winner is in participants list
              if (!validParticipants.some(w => w.toLowerCase() === winnerWallet.toLowerCase())) {
                validParticipants.push(winnerWallet);
              }

              console.log(`[Payout] Settle params: winner=${winnerWallet}, participantsCount=${validParticipants.length}`);

              const result = await settleMatchOnchain(activeMatch.matchId, winnerWallet, validParticipants);
              if (result.success) {
                await markMatchSettled(activeMatch.matchId, result.txHash);
                console.log(`[Payout] Payout successful for ${activeMatch.matchId}. TX: ${result.txHash}`);

                // Save reward record to Firebase
                await saveReward({
                  username: winnerInfo.winnerName,
                  wallet: winnerWallet,
                  amount: activeMatch.prize,
                  matchId: activeMatch.matchId,
                  source: activeMatch.sponsor,
                  category: "earned",
                  txHash: result.txHash
                });

                const prizeAmount = Number(activeMatch.prizeAmount || String(activeMatch.prize || '').split(' ')[0] || 0);
                await logAnalyticsEvent({
                  event_type: 'reward_paid',
                  user_id: winnerInfo.winnerName,
                  match_id: activeMatch.matchId,
                  sponsor_id: activeMatch.sponsor || '',
                  value: Number.isFinite(prizeAmount) ? prizeAmount : 0,
                  metadata: {
                    txHash: result.txHash,
                    prize: activeMatch.prize
                  }
                });
              } else {
                console.error(`[Payout] On-chain settlement failed: ${result.error}`);
              }
            } else {
              console.warn(`[Payout] Could not find wallet for winner: ${winnerInfo.winnerName}. Ensure they are logged in on the dashboard first.`);
            }
          } else {
            console.log(`[Payout-Debug] No valid winner found for this round.`);
          }
        } catch (err) {
          console.error(`[Payout] Error during automated settlement:`, err);
        }
      })(winner, participantNames);

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
    if (!matchStartedThisRound) {
      matchTimeLeft = MATCH_DURATION_SECONDS;
      if (getPlayerCount() >= currentMinPlayersToStart) {
        matchRunning = true;
        matchStartedThisRound = true;
      }
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
    server.listen(PORT, '0.0.0.0', () => {
      console.log(`✅ Server is live on port ${PORT}`);
    });
  })
  .catch((error) => {
    console.error('[Analytics] Failed to initialize analytics database', error);
    process.exit(1);
  });
