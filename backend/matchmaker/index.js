// matchmaker.js - FINAL VERSION WITH BROWSER-LIKE HEADERS
import express from 'express';
import fetch from 'node-fetch';
import cors from 'cors';

const app = express();
app.use(cors());
const PORT = process.env.PORT || 3000;

// --- Configuration ---
const MAX_PLAYERS_PER_SERVER = 10;
const POLLING_INTERVAL_MS = 3000; 
const REQUEST_SAFETY_TIMEOUT_MS = 120000; 

// This header will make our requests look like they're from a standard browser.
const BROWSER_HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
};

const GAME_SERVERS = [
    { id: 1, url: 'https://worldofnads-server-1.onrender.com' },
    { id: 2, url: 'https://worldofnads-server-1.onrender.com' }
];

// --- Helper to check a server's status ---
async function checkServer(serverUrl) {
    try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 2500);
        // We add the browser headers to the stats check
        const response = await fetch(`${serverUrl}/stats`, { 
            signal: controller.signal,
            headers: BROWSER_HEADERS 
        });
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

// --- Endpoint: Find a Match ---
app.get('/find-match', async (req, res) => {
    console.log("🔎 Client requested a match. Performing initial check...");
    const requestStartTime = Date.now();

    const serverStatuses = await Promise.all(GAME_SERVERS.map(s => checkServer(s.url)));
    
    const activeServer = serverStatuses.find(s => s.status === 'active' && s.count < MAX_PLAYERS_PER_SERVER);

    if (activeServer) {
        console.log(`✅ Found an active server immediately: ${activeServer.url}`);
        return res.json({ status: 'ready', serverUrl: activeServer.url.replace('https://', 'wss://') });
    }

    const sleepingServers = serverStatuses.filter(s => s.status === 'sleeping');
    if (sleepingServers.length === 0) {
        console.log("❌ All servers are full or in an error state.");
        return res.status(503).json({ error: 'All servers are currently full or unavailable.' });
    }

    console.log(`💤 No active servers found. Waking up ${sleepingServers.length} sleeping server(s) using browser-like requests...`);
    sleepingServers.forEach(server => {
        // We add the browser headers to the wakeup call
        fetch(`${server.url}/wakeup`, { headers: BROWSER_HEADERS }).catch(e => {}); // Fire and forget
    });

    console.log("Entering persistent polling loop...");
    while (Date.now() - requestStartTime < REQUEST_SAFETY_TIMEOUT_MS) {
        await new Promise(resolve => setTimeout(resolve, POLLING_INTERVAL_MS));
        const elapsed = ((Date.now() - requestStartTime) / 1000).toFixed(1);
        console.log(`  ...polling for active server (${elapsed}s)`);

        for (const candidate of sleepingServers) {
            const currentStatus = await checkServer(candidate.url);
            if (currentStatus.status === 'active') {
                console.log(`🏆 SUCCESS! Server ${currentStatus.url} is now active.`);
                return res.json({ status: 'ready', serverUrl: currentStatus.url.replace('https://', 'wss://') });
            }
        }
    }

    console.log(`❌ SAFETY TIMEOUT! No server became active after ${REQUEST_SAFETY_TIMEOUT_MS / 1000} seconds.`);
    res.status(503).json({ error: 'Failed to find an available server in time.' });
});


// --- Other Endpoints ---
app.get('/', (req, res) => res.send('✅ PERSISTENT MATCHMAKER IS RUNNING.'));
// ... (dashboard and listen) ...
app.listen(PORT, () => {
    console.log(`Matchmaker running on port ${PORT}`);
});