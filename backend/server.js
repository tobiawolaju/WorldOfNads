// server.js
// Final Production Version - CLIENT AUTHORITATIVE MODEL

import { createServer } from 'http';
import { WebSocketServer } from 'ws';
import { randomUUID } from 'crypto';

// --- Configuration ---
const PORT = process.env.PORT || 8080;
// We broadcast the game state 20 times per second.
const BROADCAST_RATE = 20;

// --- Server State ---
// The server only stores the last known state of each player.
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
  // Player state is now very simple and will be overwritten by the client.
  players[playerId] = { id: playerId, x: 0, y: 0, z: 0, rotationY: 0 };
  
  console.log(`🎮 Player connected: ${playerId}`);

  // Send the new player their unique ID.
  ws.send(JSON.stringify({ type: 'connect', id: playerId }));

  // --- Message Handling ---
  // The server no longer simulates. It just accepts the client's state.
  ws.on('message', (message) => {
    try {
      const data = JSON.parse(message.toString());
      // We expect a new message type: 'update_state'
      if (data.type === 'update_state') {
        const player = players[data.player_id];
        if (player) {
          // Directly update the server's copy of the player's state.
          player.x = data.x;
          player.y = data.y;
          player.z = data.z;
          player.rotationY = data.rotation_y;
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
// This loop's only job is to send everyone the latest state of all players.
const broadcastLoop = () => {
  const stateData = {
    type: 'state',
    // We can just send the values of the players object directly.
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