// matchmaker.js - PLAYWRIGHT WAKE-UP VERSION (Final Guaranteed Render Fix)

import express from 'express';
import fetch from 'node-fetch';
import cors from 'cors';
import { chromium } from 'playwright';

const app = express();
app.use(cors());
const PORT = process.env.PORT || 3000;

// --- Configuration ---
const MAX_PLAYERS_PER_SERVER = 10;
const POLLING_INTERVAL_MS = 3000;
const REQUEST_SAFETY_TIMEOUT_MS = 120000;

const BROWSER_HEADERS = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
};

const GAME_SERVERS = [
    { id: 1, url: 'https://worldofnads-server-2.onrender.com' },
    { id: 2, url: 'https://worldofnads-server-2.onrender.com' },
];

// ---------------------------------------------------------------------------
// REAL BROWSER WAKE-UP (This is the only reliable method for Render Free Plan)
// ---------------------------------------------------------------------------
async function wakeServer(url) {
    console.log(`🌐 Using Playwright to wake ${url}`);

    const browser = await chromium.launch({
        headless: true,
        args: ['--no-sandbox', '--disable-setuid-sandbox'],
    });

    const page = await browser.newPage();

    try {
        await page.goto(url, {
            timeout: 45000,
            waitUntil: 'load',
        });

        console.log('🌞 Render server responded to a real browser, should be waking.');
    } catch (err) {
        console.log('⚠️ Browser wake request failed or timed out (expected during cold start).');
    }

    await browser.close();
}

// ---------------------------------------------------------------------------
// Check server status using API
// ---------------------------------------------------------------------------
async function checkServer(serverUrl) {
    try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 2500);

        const response = await fetch(`${serverUrl}/stats`, {
            signal: controller.signal,
            headers: BROWSER_HEADERS,
        });

        clearTimeout(timeoutId);

        if (response.ok) {
            const data = await response.json();
            return { status: 'active', count: data.playerCount, url: serverUrl };
        }
    } catch (error) {}

    return { status: 'sleeping', count: 0, url: serverUrl };
}

// ---------------------------------------------------------------------------
// Matchmaking endpoint
// ---------------------------------------------------------------------------
app.get('/find-match', async (req, res) => {
    console.log('🔎 Client requested a match. Performing initial check...');
    const requestStartTime = Date.now();

    const serverStatuses = await Promise.all(GAME_SERVERS.map((s) => checkServer(s.url)));
    const activeServer = serverStatuses.find(
        (s) => s.status === 'active' && s.count < MAX_PLAYERS_PER_SERVER
    );

    if (activeServer) {
        console.log(`✅ Found an active server immediately: ${activeServer.url}`);
        return res.json({
            status: 'ready',
            serverUrl: activeServer.url.replace('https://', 'wss://'),
        });
    }

    const sleepingServers = serverStatuses.filter((s) => s.status === 'sleeping');

    if (sleepingServers.length === 0) {
        console.log('❌ All servers are full or unavailable.');
        return res.status(503).json({ error: 'All servers are currently full or unavailable.' });
    }

    const serverToWake = sleepingServers[0];
    console.log(`💤 No active server. Waking ${serverToWake.url} using REAL browser...`);

    // ---------------------------------------------------------
    // Real browser wake-up
    // ---------------------------------------------------------
    await wakeServer(serverToWake.url);

    // ---------------------------------------------------------
    // Polling loop
    // ---------------------------------------------------------
    console.log('Entering persistent polling loop to confirm server is active...');

    while (Date.now() - requestStartTime < REQUEST_SAFETY_TIMEOUT_MS) {
        await new Promise((resolve) => setTimeout(resolve, POLLING_INTERVAL_MS));

        const elapsed = ((Date.now() - requestStartTime) / 1000).toFixed(1);
        const currentStatus = await checkServer(serverToWake.url);

        if (currentStatus.status === 'active') {
            console.log(`🏆 SUCCESS! Server ACTIVE after ${elapsed}s`);
            return res.json({
                status: 'ready',
                serverUrl: currentStatus.url.replace('https://', 'wss://'),
            });
        }

        console.log(`  ...polling (${elapsed}s)`);
    }

    console.log(`❌ SAFETY TIMEOUT (120s)`);
    res.status(503).json({ error: 'Failed to find an available server in time.' });
});

// ---------------------------------------------------------------------------
app.get('/', (req, res) => res.send('✅ MATCHMAKER WITH BROWSER WAKE IS RUNNING.'));
app.listen(PORT, () => console.log(`Matchmaker running on port ${PORT}`));
