// server.js
// Authoritative server, now ready for Render and local development.

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

// --- Server Initialization ---
const wss = new WebSocketServer({
  port: PORT,
  // This is crucial for Render to accept connections from the internet.
  host: '0.0.0.0', 
  verifyClient: (info, callback) => {
    // This function provides CORS protection.
    // It will be updated with your actual Vercel URL.
    const allowedOrigins = [
      'https://worldofnads.vercel.app', // e.g., 'https://my-awesome-vercel.app'
      'http://localhost:8060',  // The default for Godot's HTML5 export testing
      undefined // Allow connections from non-browser clients (like the Godot editor itself)
    ];
    
    const origin = info.origin;

    // For local testing, origin will be undefined. We must allow this.
    if (allowedOrigins.includes(origin)) {
      console.log(`Connection from origin ${origin || 'local editor'} accepted.`);
      callback(true); // Accept the connection.
    } else {
      console.log(`Connection from origin ${origin} rejected.`);
      callback(false, 403, 'Forbidden'); // Reject the connection.
    }
  }
});

console.log(`🚀 WebSocket server starting on port ${PORT}...`);

wss.on('listening', () => {
  console.log(`✅ Server is live and listening on port ${PORT}`);
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

  // --- Message Handling ---
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
    
    // Movement Physics
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

    // Gravity Physics
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