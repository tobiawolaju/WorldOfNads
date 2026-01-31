// server.js
import { createServer } from 'http';
import { WebSocketServer } from 'ws';

const PORT = process.env.PORT || 8080;
const BROADCAST_RATE = 20; // Broadcasts per second

// --- Data Structures ---
// We use a fixed array for IDs to map them to bytes (0-255)
const MAX_PLAYERS = 255;
const idSlots = new Array(MAX_PLAYERS).fill(null); // Slots: null or { ws, x, y, z, rot, anim }
const activeSockets = new Map(); // Map: ws -> playerObject

const server = createServer((req, res) => {
    res.writeHead(200);
    res.end('Game Server Running');
});

const wss = new WebSocketServer({ server });

console.log(`🚀 Binary Server started on port ${PORT}`);

// --- Helper: Find free ID ---
function getFreeId() {
    for (let i = 1; i < MAX_PLAYERS; i++) {
        if (idSlots[i] === null) return i;
    }
    return null;
}

wss.on('connection', (ws) => {
    ws.binaryType = 'arraybuffer'; // Important: Receive data as Buffer

    const myId = getFreeId();
    if (myId === null) {
        console.log("Server full, rejecting connection.");
        ws.close();
        return;
    }

    console.log(`Player connected. Assigned ID: ${myId}`);

    // Init Player State
    const player = { id: myId, ws, x: 0, y: 0, z: 0, rot: 0, anim: 0 };
    idSlots[myId] = player;
    activeSockets.set(ws, player);

    // 1. Send Handshake Packet: [Type 0 (1B)] [MyID (1B)]
    const handshake = Buffer.alloc(2);
    handshake.writeUInt8(0, 0);
    handshake.writeUInt8(myId, 1);
    ws.send(handshake);

    ws.on('message', (buffer) => {
        // Client sends: [Type 1 (1B)] [X (4B)] [Y (4B)] [Z (4B)] [Rot (4B)] [Anim (1B)]
        // Total length expected: 1 + 4 + 4 + 4 + 4 + 1 = 18 bytes
        if (buffer.byteLength < 18) return;

        try {
            const view = Buffer.from(buffer); // Ensure it's a Buffer
            const type = view.readUInt8(0);

            if (type === 1) {
                player.x = view.readFloatLE(1);
                player.y = view.readFloatLE(5);
                player.z = view.readFloatLE(9);
                player.rot = view.readFloatLE(13);
                player.anim = view.readUInt8(17);
            }
        } catch (e) {
            console.error("Error parsing packet", e);
        }
    });

    ws.on('close', () => {
        console.log(`Player ${myId} disconnected.`);
        idSlots[myId] = null;
        activeSockets.delete(ws);

        // Broadcast Disconnect: [Type 2 (1B)] [ID (1B)]
        const out = Buffer.alloc(2);
        out.writeUInt8(2, 0);
        out.writeUInt8(myId, 1);
        
        wss.clients.forEach(client => {
            if (client.readyState === 1 && client !== ws) client.send(out);
        });
    });
});

// --- Broadcast Loop ---
// Packet Structure: [Type 3 (1B)] [Count (1B)] ... [ID][X][Y][Z][Rot][Anim] ...
setInterval(() => {
    // Filter valid players
    const players = idSlots.filter(p => p !== null);
    const count = players.length;
    
    if (count === 0) return;

    // 2 bytes header + (18 bytes per player)
    const size = 2 + (count * 18); 
    const buf = Buffer.allocUnsafe(size);

    buf.writeUInt8(3, 0); // Type 3 = World State
    buf.writeUInt8(count, 1);

    let offset = 2;
    for (const p of players) {
        buf.writeUInt8(p.id, offset);
        buf.writeFloatLE(p.x, offset + 1);
        buf.writeFloatLE(p.y, offset + 5);
        buf.writeFloatLE(p.z, offset + 9);
        buf.writeFloatLE(p.rot, offset + 13);
        buf.writeUInt8(p.anim, offset + 17);
        offset += 18;
    }

    wss.clients.forEach(client => {
        if (client.readyState === 1) client.send(buf);
    });

}, 1000 / BROADCAST_RATE);

server.listen(PORT, '0.0.0.0', () => {
    console.log(`✅ Server live on ${PORT}`);
});