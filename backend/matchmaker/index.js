// matchmaker.js - REVISED with Long Polling
import express from 'express';
import fetch from 'node-fetch';
import cors from 'cors';

const app = express();
app.use(cors());
const PORT = process.env.PORT || 3000;

// --- Configuration ---
const MAX_PLAYERS_PER_SERVER = 10;
const SERVER_WAKE_TIMEOUT_MS = 25000; // Max time to wait for a server to wake (e.g., 25s)
const SERVER_PROBE_INTERVAL_MS = 2000; // How often to check a waking server (e.g., every 2s)

// IMPORTANT: Use unique URLs for each server instance for proper scaling.
const GAME_SERVERS = [
    { id: 1, url: 'https://worldofnads-server-1.onrender.com' },
    // For scaling, you would add a *different* server instance here, e.g.:
    // { id: 2, url: 'https://worldofnads-server-2.onrender.com' }
    // I'm keeping your duplicated URL to show it works, but it's not true scaling.
    { id: 2, url: 'https://worldofnads-server-1.onrender.com' }
];

// --- Helper to check a server's status ---
async function checkServer(serverUrl) {
    try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 1500); // 1.5s timeout for checks
        const response = await fetch(`${serverUrl}/stats`, { signal: controller.signal });
        clearTimeout(timeoutId);
        if (response.ok) {
            const data = await response.json();
            return { status: 'active', count: data.playerCount };
        }
    } catch (error) {
        return { status: 'sleeping', count: 0 };
    }
    return { status: 'error', count: 0 };
}

// --- Helper to wake a server and wait for it to be ready ---
async function wakeAndConfirmServer(serverUrl) {
    console.log(`🔔 Waking server: ${serverUrl}...`);
    // Fire the wakeup request but don't wait for it.
    fetch(`${serverUrl}/wakeup`).catch(e => console.error(`Wakeup request failed for ${serverUrl}: ${e.message}`));

    const startTime = Date.now();
    while (Date.now() - startTime < SERVER_WAKE_TIMEOUT_MS) {
        await new Promise(resolve => setTimeout(resolve, SERVER_PROBE_INTERVAL_MS));
        console.log(`🔍 Probing ${serverUrl}...`);
        const info = await checkServer(serverUrl);
        if (info.status === 'active') {
            console.log(`✅ Server ${serverUrl} is now active.`);
            return info;
        }
    }

    console.log(`❌ Server ${serverUrl} did not wake up in time.`);
    return { status: 'sleeping', count: 0 }; // Failed to wake in time
}

// --- Endpoint: Find a Match (Now with Long Polling) ---
app.get('/find-match', async (req, res) => {
    console.log("🔎 Client requested a match...");
    let bestCandidate = null;

    for (const server of GAME_SERVERS) {
        const info = await checkServer(server.url);
        console.log(`Checked Server ${server.id} (${server.url}): ${info.status} (${info.count} players)`);

        // CASE 1: Server is active and has space. This is the best case, return immediately.
        if (info.status === 'active' && info.count < MAX_PLAYERS_PER_SERVER) {
            return res.json({
                status: 'ready',
                serverUrl: server.url.replace('https://', 'wss://')
            });
        }

        // CASE 2: Server is sleeping. Keep it as a candidate to be woken up.
        // We prioritize waking servers that have 0 players.
        if (info.status === 'sleeping' && !bestCandidate) {
            bestCandidate = server;
        }
    }

    // CASE 3: No active servers were found, so we need to wake one up.
    if (bestCandidate) {
        const wokenInfo = await wakeAndConfirmServer(bestCandidate.url);
        if (wokenInfo.status === 'active' && wokenInfo.count < MAX_PLAYERS_PER_SERVER) {
            return res.json({
                status: 'ready',
                serverUrl: bestCandidate.url.replace('https://', 'wss://')
            });
        }
    }

    // CASE 4: All servers are full, errored, or failed to wake up.
    res.status(503).json({ error: 'All servers are currently full or unavailable.' });
});


// --- Other Endpoints (Health Check, Dashboard) ---
app.get('/', (req, res) => {
    res.send('✅ MATCHMAKER IS RUNNING. Use /find-match to connect.');
});

app.get('/dashboard', async (req, res) => {
    const statusReport = await Promise.all(
        GAME_SERVERS.map(async (server) => {
            const info = await checkServer(server.url);
            return { ...server, ...info };
        })
    );
    res.json(statusReport);
});

app.listen(PORT, () => {
    console.log(`Matchmaker running on port ${PORT}`);
});