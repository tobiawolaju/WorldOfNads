// matchmaker.js
import express from 'express';
import fetch from 'node-fetch';
import cors from 'cors';

const app = express();
app.use(cors()); // Allow your frontend to call this
const PORT = process.env.PORT || 3000;

// --- Configuration ---
const MAX_PLAYERS_PER_SERVER = 10;

// LIST OF YOUR RENDER INSTANCES
const GAME_SERVERS = [
    { id: 1, url: 'https://server-1-eaim.onrender.com/' },
    { id: 2, url: 'https://server-2-7bjc.onrender.com' },
    { id: 3, url: 'https://server-3-nan3.onrender.com' }
];

// --- Helper to check a server ---
async function checkServer(serverUrl) {
    try {
        // Set a short timeout so we don't wait forever for a sleeping server
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 2000); // 2s timeout

        const response = await fetch(`${serverUrl}/stats`, { 
            signal: controller.signal 
        });
        clearTimeout(timeoutId);

        if (response.ok) {
            const data = await response.json();
            return { status: 'active', count: data.playerCount };
        }
    } catch (error) {
        // If it times out or fails, it's likely "sleeping" or booting
        return { status: 'sleeping', count: 0 };
    }
    return { status: 'error', count: 0 };
}

// --- Helper to wake a server ---
function wakeServer(serverUrl) {
    // We just fire this request and don't wait for the result immediately
    fetch(`${serverUrl}/wakeup`).catch(e => console.log(`Waking ${serverUrl}...`));
}

// --- Endpoint: Find a Match ---
app.get('/find-match', async (req, res) => {
    console.log("🔎 Client requested a match...");

    for (const server of GAME_SERVERS) {
        const info = await checkServer(server.url);
        console.log(`Checked Server ${server.id}: ${info.status} (${info.count} players)`);

        // 1. If server is active and has space
        if (info.status === 'active' && info.count < MAX_PLAYERS_PER_SERVER) {
            return res.json({
                status: 'ready',
                serverUrl: server.url.replace('https://', 'wss://') // Convert to WS
            });
        }

        // 2. If server is sleeping, wake it up and tell client to wait
        if (info.status === 'sleeping') {
            wakeServer(server.url);
            return res.json({
                status: 'waking_up',
                message: 'Server is spinning up. Please retry in 5-10 seconds.',
                retryAfter: 5000
            });
        }
    }

    // 3. All servers full or down
    res.status(503).json({ error: 'All servers are currently full.' });
});

// --- Endpoint: Admin View ---
app.get('/dashboard', async (req, res) => {
    const statusReport = [];
    for (const server of GAME_SERVERS) {
        const info = await checkServer(server.url);
        statusReport.push({ ...server, ...info });
    }
    res.json(statusReport);
});

app.listen(PORT, () => {
    console.log(`Matchmaker running on port ${PORT}`);
});