// server.js
// Final Production Version with Health Check and Vertical State Sync

import { createServer } from 'http';
import { WebSocketServer } from 'ws';
import { randomUUID } from 'crypto';

// --- Configuration ---
const PORT = process.env.PORT || 8080;
const TICK_RATE = 20;
const PLAYER_SPEED = 4.5;
const GRAVITY = 9.8;
const JUMP_VELOCITY = 4.5;

// --- Server State ---
const players = {};

// --- HTTP Server Setup ---
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
  players[playerId] = {
    id: playerId,
    x: 0, y: 0, z: 0,
    rotationY: 0,
    velocityY: 0,
    onGround: true,
    inputs: { forward: false, back: false, left: false, right: false, jump: false },
  };
  console.log(`🎮 Player connected: ${playerId}`);

  ws.send(JSON.stringify({ type: 'connect', id: playerId }));

  // Message Handling
  ws.on('message', (message) => {
    try {
      const data = JSON.parse(message.toString());
      if (data.type === 'input') {
        const player = players[data.player_id];
        if (player) {
          player.inputs = data.inputs;
          player.rotationY = data.rotation_y;
          if (data.inputs.jump && player.onGround) {
            player.velocityY = JUMP_VELOCITY;
            player.onGround = false;
          }
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

// --- Server Game Loop ---
const gameLoop = () => {
  const delta = 1 / TICK_RATE;
  for (const playerId in players) {
    const player = players[playerId];
    const inputs = player.inputs;
    const rotationY = player.rotationY;
    const forwardX = Math.sin(rotationY);
    const forwardZ = Math.cos(rotationY);
    let moveX = 0;
    let moveZ = 0;
    if (inputs.forward) { moveX -= forwardX; moveZ -= forwardZ; }
    if (inputs.back)    { moveX += forwardX; moveZ += forwardZ; }
    if (inputs.left)    { moveX -= forwardZ; moveZ += forwardX; }
    if (inputs.right)   { moveX += forwardZ; moveZ -= forwardX; }
    const magnitude = Math.sqrt(moveX * moveX + moveZ * moveZ);
    if (magnitude > 0) {
        moveX = (moveX / magnitude) * PLAYER_SPEED * delta;
        moveZ = (moveZ / magnitude) * PLAYER_SPEED * delta;
    }
    player.x += moveX;
    player.z += moveZ;
    player.velocityY -= GRAVITY * delta;
    player.y += player.velocityY * delta;
    if (player.y < 0) {
        player.y = 0;
        player.velocityY = 0;
        player.onGround = true;
    }
  }
  const stateData = {
    type: 'state',
    players: Object.values(players).map(p => ({
      id: p.id, x: p.x, y: p.y, z: p.z, rotationY: p.rotationY,
      // --- CHANGE: Send vertical state for better reconciliation ---
      velocityY: p.velocityY,
      onGround: p.onGround,
    })),
  };
  const stateString = JSON.stringify(stateData);
  wss.clients.forEach((client) => {
    if (client.readyState === 1) { // WebSocket.OPEN
      client.send(stateString);
    }
  });
};

setInterval(gameLoop, 1000 / TICK_RATE);

// --- Start the HTTP Server ---
server.listen(PORT, '0.0.0.0', () => {
    console.log(`✅ Server is live and listening on port ${PORT}`);
});