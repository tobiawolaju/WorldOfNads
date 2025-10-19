// server.js
// Authoritative server using modern ES Module (import) syntax.

import { WebSocketServer } from 'ws';
import { randomUUID } from 'crypto';

// --- Configuration ---
const PORT = 8080;
const TICK_RATE = 20;
const PLAYER_SPEED = 4.5;
const GRAVITY = 9.8;
const JUMP_VELOCITY = 4.5;

// --- Server State ---
const wss = new WebSocketServer({ port: PORT });
const players = {};

console.log(`🚀 WebSocket server started on ws://localhost:${PORT}`);

// --- Connection Handling ---
wss.on('connection', (ws) => {
  const playerId = randomUUID();
  players[playerId] = {
    id: playerId,
    x: 0, y: 0, z: 0,
    rotationY: 0,
    velocityY: 0,
    onGround: true,
    inputs: { forward: false, back: false, left: false, right: false, jump: false },
  };
  console.log(`✅ Player connected: ${playerId}`);

  ws.send(JSON.stringify({ type: 'connect', id: playerId }));

  // --- Message Handling ---
  ws.on('message', (message) => {
    try {
      const data = JSON.parse(message.toString());

      if (data.type === 'input') {
        const player = players[data.player_id];
        if (player) {
          // Store continuous inputs (like movement)
          player.inputs = data.inputs;
          player.rotationY = data.rotation_y;
          
          // --- FIX: PROCESS JUMP AS AN IMMEDIATE EVENT ---
          // If the jump input is true AND the player is on the ground...
          if (data.inputs.jump && player.onGround) {
            // ...apply the jump velocity immediately.
            player.velocityY = JUMP_VELOCITY;
            player.onGround = false; // The player is now in the air.
          }
        }
      }
    } catch (error) {
      console.error('Failed to parse message:', error);
    }
  });

  ws.on('close', () => {
    console.log(`❌ Player disconnected: ${playerId}`);
    delete players[playerId];
  });
});

// --- Server Game Loop ---
const gameLoop = () => {
  const delta = 1 / TICK_RATE;

  for (const playerId in players) {
    const player = players[playerId];
    const inputs = player.inputs;
    
    // --- MOVEMENT PHYSICS ---
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

    // --- GRAVITY PHYSICS (JUMP LOGIC IS NO LONGER HERE) ---
    player.velocityY -= GRAVITY * delta;
    player.y += player.velocityY * delta;

    if (player.y < 0) {
        player.y = 0;
        player.velocityY = 0;
        player.onGround = true;
    }
  }

  // --- Broadcast State ---
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