// server.js — CLEAN VERSION, NO AUTO SHUTDOWN

import { createServer } from 'http';
import { WebSocketServer } from 'ws';
import { randomUUID } from 'crypto';

const PORT = process.env.PORT || 8080;
const BROADCAST_RATE = 20;

const players = {};
const logs = [];

// Logging
function serverLog(msg) {
    const line = `[${new Date().toISOString()}] ${msg}`;
    console.log(line);
    logs.push(line);
    if (logs.length > 500) logs.shift();
}

const server = createServer((req, res) => {
    res.setHeader('Access-Control-Allow-Origin', '*');

    if (req.url === '/' || req.url === '/wakeup') {
        res.writeHead(200);
        return res.end("awake");
    }

    if (req.url === '/stats') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({
            playerCount: Object.keys(players).length,
            playerIds: Object.keys(players),
            uptime: process.uptime()
        }));
    }

    if (req.url === '/dumplog') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify(logs));
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
    const id = randomUUID();
    players[id] = { id, x: 0, y: 0, z: 0, rotationY: 0, animation: "idle" };
    serverLog(`Player connected: ${id}`);

    ws.send(JSON.stringify({ type: 'connect', id }));

    ws.on('message', msg => {
        try {
            const d = JSON.parse(msg);
            if (d.type === 'update_state' && players[d.player_id]) {
                Object.assign(players[d.player_id], {
                    x: d.x, y: d.y, z: d.z,
                    rotationY: d.rotation_y,
                    animation: d.animation
                });
            }
        } catch {}
    });

    ws.on('close', () => {
        delete players[id];
        serverLog(`Player disconnected: ${id}`);
    });
});

// Broadcast (20Hz)
setInterval(() => {
    if (Object.keys(players).length === 0) return;
    const packet = JSON.stringify({
        type: 'state',
        players: Object.values(players)
    });
    wss.clients.forEach(c => c.readyState === 1 && c.send(packet));
}, 1000 / BROADCAST_RATE);

server.listen(PORT, '0.0.0.0', () => {
    serverLog(`Server live on ${PORT}`);
});
