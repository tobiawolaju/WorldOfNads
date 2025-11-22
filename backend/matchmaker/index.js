// matchmaker.js - REVISED WITH PERSISTENT POLLING LOGIC
import express from 'express';
import fetch from 'node-fetch';
import cors from 'cors';

const app = express();
app.use(cors());
const PORT = process.env.PORT || 3000;

// --- Configuration ---
const MAX_PLAYERS_PER_SERVER = 10;
// How often to check on waking servers.
const POLLING_INTERVAL_MS = 3000; 
// A very long safety timeout for the entire request, in case all servers fail to start. 2 minutes.
const REQUEST_SAFETY_TIMEOUT_MS = 120000; 

const GAME_SERVERS = [
    { id: 1, url: 'https://worldofnads-server-1.onrender.com' },
    { id: 2, url: 'https://worldofnads-server-1.onrender.com' }
];

// --- Helper to check a server's status (no changes needed) ---
async function checkServer(serverUrl) {
    try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 2500);
        const response = await fetch(`${serverUrl}/stats`, { signal: controller.signal });
        clearTimeout(timeoutId);
        if (response.ok) {
            const data = await response.json();
            return { status: 'active', count: data.playerCount, url: serverUrl };
        }
    } catch (error) {
        // Fallthrough means it's sleeping
    }
    return { status: 'sleeping', count: 0, url: serverUrl };
}

// --- Endpoint: Find a Match (The New Logic) ---
app.get('/find-match', async (req, res) => {
    console.log("🔎 Client requested a match. Performing initial check...");
    const requestStartTime = Date.now();

    // --- Step 1: Check all servers to see if one is already active ---
    const serverStatuses = await Promise.all(GAME_SERVERS.map(s => checkServer(s.url)));
    
    const activeServer = serverStatuses.find(s => s.status === 'active' && s.count < MAX_PLAYERS_PER_SERVER);

    if (activeServer) {
        console.log(`✅ Found an active server immediately: ${activeServer.url}`);
        return res.json({
            status: 'ready',
            serverUrl: activeServer.url.replace('https://', 'wss://')
        });
    }

    // --- Step 2: No active servers. Let's wake them up and start polling. ---
    const sleepingServers = serverStatuses.filter(s => s.status === 'sleeping');
    if (sleepingServers.length === 0) {
        console.log("❌ All servers are full or in an error state. Cannot find a match.");
        return res.status(503).json({ error: 'All servers are currently full or unavailable.' });
    }

    console.log(`💤 No active servers found. Waking up ${sleepingServers.length} sleeping server(s)...`);
    sleepingServers.forEach(server => {
        console.log(`  - Sending wakeup to ${server.url}`);
        fetch(`${server.url}/wakeup`).catch(e => {}); // Fire and forget
    });

    // --- Step 3: Enter the persistent polling loop ---
    console.log("Entering persistent polling loop. Will check every few seconds...");
    while (Date.now() - requestStartTime < REQUEST_SAFETY_TIMEOUT_MS) {
        await new Promise(resolve => setTimeout(resolve, POLLING_INTERVAL_MS));
        const elapsed = ((Date.now() - requestStartTime) / 1000).toFixed(1);
        console.log(`  ...polling for active server (${elapsed}s)`);

        // Check all the candidates again
        for (const candidate of sleepingServers) {
            const currentStatus = await checkServer(candidate.url);
            if (currentStatus.status === 'active') {
                console.log(`🏆 SUCCESS! Server ${currentStatus.url} is now active.`);
                return res.json({
                    status: 'ready',
                    serverUrl: currentStatus.url.replace('https://', 'wss://')
                });
            }
        }
    }

    // --- Step 4: If the loop finishes, the safety timeout was hit ---
    console.log(`❌ SAFETY TIMEOUT! No server became active after ${REQUEST_SAFETY_TIMEOUT_MS / 1000} seconds.`);
    res.status(503).json({ error: 'Failed to find an available server in time.' });
});


// --- Other Endpoints ---
app.get('/', (req, res) => res.send('✅ PERSISTENT MATCHMAKER IS RUNNING.'));
// ... (dashboard endpoint remains the same) ...

app.listen(PORT, () => {
    console.log(`Matchmaker running on port ${PORT}`);
});