// server.js
// Final version with HTTP Server for WebSocket Upgrades.
// This is the correct way to deploy on a "Web Service" platform like Render.

import { createServer } from 'http'; // We need the built-in HTTP server
import { WebSocketServer } from 'ws';
import { randomUUID } from 'crypto';

// --- Configuration ---
// Render provides the PORT as an environment variable. Fallback to 8080 for local use.
const PORT = process.env.PORT || 8080;
const TICK_RATE = 20;
const PLAYER_SPEED = 4.5;
const GRAVITY = 9.8;
const JUMP_VELOCITY = 4.5;

// --- Server State ---
const players = {};

// --- HTTP Server Setup ---
// We create a basic HTTP server. It won't serve any webpages.
// Its only job is to listen for the WebSocket upgrade request.
const server = createServer();

// --- WebSocket Server Setup ---
// We attach the WebSocket server to the HTTP server, but tell it not to listen on its own.
const wss = new WebSocketServer({ noServer: true });

console.log(`🚀 Server starting on port ${PORT}...`);

// --- The "Upgrade" Logic ---
server.on('upgrade', (req, socket, head) => {
  // This event fires when a client sends the "Upgrade: websocket" header.
  
  // We can add origin checks here for security if needed, but for now, we'll accept all.
  // This is the "hand-off". The HTTP server gives the connection to the WebSocket server.
  wss.handleUpgrade(req, socket, head, (ws) => {
    wss.emit('connection', ws, req);
  });
});


// --- Connection Handling (This part is exactly the same as before) ---
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

// --- Server Game Loop (Exactly the same as before) ---
const gameLoop = () => {
  const delta = 1 / TICK_RATE;

  for (const playerId in players) {
    const player = players[playerId];
    // ... (rest of game loop logic is identical)
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

  // Broadcast State
  const stateData = {
    type: 'state',
    players: Object.values(players).map(p => ({
      id: p.id, x: p.x, y: p.y, z: p.z, rotationY: p.rotationY,
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
// The HTTP server now listens on the port, and the WebSocket server is attached to it.
server.listen(PORT, '0.0.0.0', () => {
    console.log(`✅ Server is live and listening on port ${PORT}`);
});