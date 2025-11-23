// matchmaker.js - FINAL VERSION WITH A DELIBERATE WAKE-UP CALL
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
const BROWSER_HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
};

const GAME_SERVERS = [
    { id: 1, url: 'https://worldofnads-server-2.onrender.com' },
    { id: 2, url: 'https://worldofnads-server-2.onrender.com' }
];

// --- Helper to check a server's status ---
async function checkServer(serverUrl) {
    try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 2500);
        const response = await fetch(`${serverUrl}/stats`, { 
            signal: controller.signal,
            headers: BROWSER_HEADERS 
        });
        clearTimeout(timeoutId);
        if (response.ok) {
            const data = await response.json();
            return { status: 'active', count: data.playerCount, url: serverUrl };
        }
    } catch (error) {}
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

    // --- THIS IS THE CRITICAL CHANGE ---
    // Instead of a "fire-and-forget" loop, we will make ONE deliberate
    // and patient request to the first sleeping server to wake it up.
    const serverToWake = sleepingServers[0];
    console.log(`💤 No active servers. Making a deliberate call to wake up ${serverToWake.url}...`);
    try {
        // We make a full request and wait for it to complete or time out.
        // This is a much stronger signal to Render than a quick ping.
        const controller = new AbortController();
        // Give this initial wake-up call a generous timeout (e.g., 45 seconds)
        const timeoutId = setTimeout(() => controller.abort(), 45000);
        await fetch(serverToWake.url, { headers: BROWSER_HEADERS, signal: controller.signal });
        clearTimeout(timeoutId);
    } catch (e) {
        // An error here is EXPECTED. It just means the server wasn't ready in time.
        // The important thing is that the request was made and held.
        console.log("   (Deliberate wake-up call completed or timed out, which is expected.)");
    }

    // --- NOW we begin polling, confident the server is in the process of waking up ---
    console.log("Entering persistent polling loop to confirm server is active...");
    while (Date.now() - requestStartTime < REQUEST_SAFETY_TIMEOUT_MS) {
        await new Promise(resolve => setTimeout(resolve, POLLING_INTERVAL_MS));
        const elapsed = ((Date.now() - requestStartTime) / 1000).toFixed(1);

        const currentStatus = await checkServer(serverToWake.url);
        if (currentStatus.status === 'active') {
            console.log(`🏆 SUCCESS! Server ${currentStatus.url} is now active after ${elapsed}s.`);
            return res.json({ status: 'ready', serverUrl: currentStatus.url.replace('https://', 'wss://') });
        } else {
            console.log(`  ...polling for active server (${elapsed}s)`);
        }
    }

    console.log(`❌ SAFETY TIMEOUT! Server did not become active after ${REQUEST_SAFETY_TIMEOUT_MS / 1000} seconds.`);
    res.status(503).json({ error: 'Failed to find an available server in time.' });
});

// --- Other Endpoints ---
app.get('/', (req, res) => res.send('✅ PERSISTENT MATCHMAKER IS RUNNING.'));
app.listen(PORT, () => {
    console.log(`Matchmaker running on port ${PORT}`);
});