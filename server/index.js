// Final Production Version - CLIENT AUTHORITATIVE + MANAGEMENT API

import { createServer } from 'http';
import { WebSocketServer } from 'ws';
import { randomUUID } from 'crypto';

// --- Configuration ---
const PORT = process.env.PORT || 8080;
const BROADCAST_RATE = 20;
const IDLE_TIMEOUT_MS = 1000 * 60 * 2; // 2 Minutes (Auto-Shutdown time)

// --- Server State ---
const players = {};
const logs = []; // In-memory log storage
let idleTimer = null;

// --- Helper: Logger ---
function serverLog(message) {
    const timestamp = new Date().toISOString();
    const logEntry = `[${timestamp}] ${message}`;
    console.log(logEntry);
    logs.push(logEntry);
    if (logs.length > 500) logs.shift(); // Keep last 500 logs
}

// --- HTTP Server (API & Health) ---
const server = createServer((req, res) => {
    // CORS Headers (Allow matchmaker to talk to us)
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST');

    const url = req.url;
    const method = req.method;

    // 1. /wakeup & Root (Knock on door)
    if (method === 'GET' && (url === '/' || url === '/wakeup')) {
        res.writeHead(200, { 'Content-Type': 'text/plain' });
        resetIdleTimer(); // Traffic detected, reset timer
        res.end('awake');
        return;
    }

    // 2. /stats (Matchmaker checks this)
    if (method === 'GET' && url === '/stats') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
            playerCount: Object.keys(players).length,
            playerIds: Object.keys(players),
            uptime: process.uptime()
        }));
        return;
    }

    // 3. /dumplog (View logs)
    if (method === 'GET' && url === '/dumplog') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(logs));
        return;
    }

    // 4. /spindown (Force shutdown command)
    if (method === 'POST' && url === '/spindown') {
        serverLog('Received manual spindown command.');
        res.writeHead(200, { 'Content-Type': 'text/plain' });
        res.end('Spinning down...');
        gracefulShutdown();
        return;
    }

    res.writeHead(404);
    res.end();
});

// --- WebSocket Server ---
const wss = new WebSocketServer({ noServer: true });

serverLog(`🚀 Server starting on port ${PORT}...`);

server.on('upgrade', (req, socket, head) => {
    wss.handleUpgrade(req, socket, head, (ws) => {
        wss.emit('connection', ws, req);
    });
});

// --- Connection Handling ---
wss.on('connection', (ws, req) => {
    resetIdleTimer(); // Player joined, reset timer
    const playerId = randomUUID();
    
    players[playerId] = { id: playerId, x: 0, y: 0, z: 0, rotationY: 0, animation: "idle" };
    serverLog(`🎮 Player connected: ${playerId}`);

    ws.send(JSON.stringify({ type: 'connect', id: playerId }));

    ws.on('message', (message) => {
        try {
            // Note: We don't reset idle timer on every input (too expensive), 
            // only on connect/disconnect or HTTP hits.
            const data = JSON.parse(message.toString());
            if (data.type === 'update_state') {
                const player = players[data.player_id];
                if (player) {
                    player.x = data.x;
                    player.y = data.y;
                    player.z = data.z;
                    player.rotationY = data.rotation_y;
                    player.animation = data.animation;
                }
            }
        } catch (error) {
            console.error('Failed to parse message:', error);
        }
    });

    ws.on('close', () => {
        serverLog(`💀 Player disconnected: ${playerId}`);
        delete players[playerId];
        
        // If server is empty, start the countdown to death
        if (Object.keys(players).length === 0) {
            serverLog('Server empty. Starting idle timer...');
            resetIdleTimer();
        }
    });
});

// --- Broadcast Loop ---
const broadcastLoop = () => {
    // Don't broadcast if empty to save CPU
    if (Object.keys(players).length === 0) return;

    const stateData = {
        type: 'state',
        players: Object.values(players),
    };
    const stateString = JSON.stringify(stateData);

    wss.clients.forEach((client) => {
        if (client.readyState === 1) {
            client.send(stateString);
        }
    });
};

setInterval(broadcastLoop, 1000 / BROADCAST_RATE);

// --- Idle / Shutdown Logic ---
function resetIdleTimer() {
    if (idleTimer) clearTimeout(idleTimer);
    
    // Set new timer
    idleTimer = setTimeout(() => {
        if (Object.keys(players).length === 0) {
            serverLog(`💤 No activity for ${IDLE_TIMEOUT_MS / 1000}s. Shutting down to save resources.`);
            gracefulShutdown();
        }
    }, IDLE_TIMEOUT_MS);
}

function gracefulShutdown() {
    // Close WSS clients
    wss.clients.forEach(client => client.close());
    
    // Close HTTP server
    server.close(() => {
        console.log('Server closed.');
        process.exit(0); // Render will see this as a crash or stop and spin it down eventually
    });
}

// Initialize timer on start
resetIdleTimer();

server.listen(PORT, '0.0.0.0', () => {
    serverLog(`✅ Server1  live on port ${PORT}`);
});