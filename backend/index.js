// server.js
import { createServer } from 'http';
import { WebSocketServer } from 'ws';
import { randomUUID } from 'crypto';

const PORT = process.env.PORT || 8080;
const BROADCAST_RATE = 20;

const players = {};

const server = createServer((req, res) => {
    if (req.method === 'GET' && req.url === '/') {
        res.writeHead(200, { 'Content-Type': 'text/plain' });
        res.end('Server is alive and healthy!\n');
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
        animation: "idle"
    };

    console.log(`🎮 Player connected: ${playerId}`);
    ws.send(JSON.stringify({ type: 'connect', id: playerId }));

    ws.on('message', (message) => {
        try {
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
        console.log(`💀 Player disconnected: ${playerId}`);
        delete players[playerId];
    });
});

setInterval(() => {
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

}, 1000 / BROADCAST_RATE);

server.listen(PORT, '0.0.0.0', () => {
    console.log(`✅ Server is live on port ${PORT}`);
});