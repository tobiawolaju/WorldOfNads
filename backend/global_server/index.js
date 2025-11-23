// server.js
// Final Production Version - CLIENT AUTHORITATIVE MODEL with Animation Sync

import { createServer } from 'http';
import { WebSocketServer } from 'ws';
import { randomUUID } from 'crypto';

// --- Configuration ---
const PORT = process.env.PORT || 8080;
const BROADCAST_RATE = 20;

// --- Server State ---
const players = {};

// --- HTTP Server Setup (for health checks from Render) ---
const server = createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('Server is alive and healthy!\n');
    return;
  }
  res.writeHead(404);
  res.end();
});

// --- WebSocket Server Setup ---
const wss = new WebSocketServer({ noServer: true });

console.log(`🚀 Server starting on port ${PORT}...`);

server.on('upgrade', (req, socket, head) => {
  wss.handleUpgrade(req, socket, head, (ws) => {
    wss.emit('connection', ws, req);
  });
});

// --- Connection Handling ---
wss.on('connection', (ws, req) => {
  const playerId = randomUUID();
  // Add 'animation' to the default player state
  players[playerId] = { id: playerId, x: 0, y: 0, z: 0, rotationY: 0, animation: "idle" };
  
  console.log(`🎮 Player connected: ${playerId}`);

  ws.send(JSON.stringify({ type: 'connect', id: playerId }));

  // --- Message Handling ---
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
          // Store the animation state sent by the client
          player.animation = data.animation;
        }
      }
    } catch (error) {
      console.error('Failed to parse message:', error);
    }
  });

  // Disconnection Handling
  ws.on('close', () => {
    console.log(`💀 Player disconnected: ${playerId}`);
    delete players[playerId];
  });
});

// --- Server Broadcast Loop ---
const broadcastLoop = () => {
  const stateData = {
    type: 'state',
    players: Object.values(players),
  };
  const stateString = JSON.stringify(stateData);

  wss.clients.forEach((client) => {
    if (client.readyState === 1) { // WebSocket.OPEN
      client.send(stateString);
    }
  });
};

setInterval(broadcastLoop, 1000 / BROADCAST_RATE);

// --- Start the HTTP Server ---
server.listen(PORT, '0.0.0.0', () => {
    console.log(`✅ Server is live and listening on port ${PORT}`);
});