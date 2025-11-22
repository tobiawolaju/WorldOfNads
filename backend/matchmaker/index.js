// matchmaker.js - REVISED AND CORRECTED
import express from 'express';
import fetch from 'node-fetch';
import cors from 'cors';

const app = express();
app.use(cors());
const PORT = process.env.PORT || 3000;

// --- Configuration ---
const MAX_PLAYERS_PER_SERVER = 10;
const SERVER_WAKE_TIMEOUT_MS = 25000;
const SERVER_PROBE_INTERVAL_MS = 2000;

const GAME_SERVERS = [
    { id: 1, url: 'https://worldofnads-server-1.onrender.com' },
    { id: 2, url: 'https://worldofnads-server-1.onrender.com' }
];

// --- Helper to check a server's status ---
// This function is now more robust. ANY failure to get a valid stats response
// means the server is considered "sleeping".
async function checkServer(serverUrl) {
    try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 1500);
        const response = await fetch(`${serverUrl}/stats`, { signal: controller.signal });
        clearTimeout(timeoutId);

        if (response.ok) {
            const data = await response.json();
            return { status: 'active', count: data.playerCount };
        }
    } catch (error) {
        // This catch block will handle timeouts, network errors, etc.
        // We consider all of these as "sleeping".
    }
    // If we reach here, it means the fetch either failed or the response was not OK.
    // In either case, the server is not ready. Treat it as sleeping.
    return { status: 'sleeping', count: 0 };
}

// --- Helper to wake a server and wait for it to be ready ---
async function wakeAndConfirmServer(serverUrl) {
    console.log(`🔔 Waking server: ${serverUrl}...`);
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
    return { status: 'sleeping', count: 0 };
}

// --- Endpoint: Find a Match (Now with corrected logic) ---
app.get('/find-match', async (req, res) => {
    console.log("🔎 Client requested a match...");
    let bestCandidate = null;

    for (const server of GAME_SERVERS) {
        const info = await checkServer(server.url);
        console.log(`Checked Server ${server.id} (${server.url}): ${info.status} (${info.count} players)`);

        if (info.status === 'active' && info.count < MAX_PLAYERS_PER_SERVER) {
            console.log(`Found active server with space: ${server.url}`);
            return res.json({
                status: 'ready',
                serverUrl: server.url.replace('https://', 'wss://')
            });
        }

        if (info.status === 'sleeping' && !bestCandidate) {
            // Found a potential server to wake up.
            bestCandidate = server;
        }
    }

    if (bestCandidate) {
        console.log(`No active servers found. Attempting to wake up candidate: ${bestCandidate.url}`);
        const wokenInfo = await wakeAndConfirmServer(bestCandidate.url);
        if (wokenInfo.status === 'active' && wokenInfo.count < MAX_PLAYERS_PER_SERVER) {
            return res.json({
                status: 'ready',
                serverUrl: bestCandidate.url.replace('https://', 'wss://')
            });
        }
    }

    console.log("All servers are full, failed to wake, or are in an error state.");
    res.status(503).json({ error: 'All servers are currently full or unavailable.' });
});

// --- Other Endpoints ---
app.get('/', (req, res) => res.send('✅ MATCHMAKER IS RUNNING.'));

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