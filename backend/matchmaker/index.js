// matchmaker.js — CLEAN SIMPLE LOAD BALANCER

import express from 'express';
import fetch from 'node-fetch';
import cors from 'cors';

const app = express();
app.use(cors());

const PORT = process.env.PORT || 3000;
const MAX_PLAYERS_PER_SERVER = 10;

const GAME_SERVERS = [
    { id: 1, url: 'https://worldofnads-server-1.onrender.com' },
    { id: 2, url: 'https://worldofnads-server-2.onrender.com' },
];

// Check stats
async function checkServer(serverUrl) {
    try {
        const response = await fetch(`${serverUrl}/stats`, { timeout: 2000 });
        if (!response.ok) return null;
        const data = await response.json();
        return { url: serverUrl, count: data.playerCount };
    } catch {
        return null;
    }
}

app.get('/find-match', async (req, res) => {
    console.log("Match request received.");

    const statuses = await Promise.all(
        GAME_SERVERS.map(s => checkServer(s.url))
    );

    // 1. find non-full server
    const available = statuses.find(s => s && s.count < MAX_PLAYERS_PER_SERVER);
    if (available) {
        console.log(`Sending to active server: ${available.url}`);
        return res.json({
            status: "ready",
            serverUrl: available.url.replace("https://", "wss://")
        });
    }

    // 2. OR find empty / offline server
    const sleeping = statuses.find(s => !s);
    if (sleeping) {
        const target = GAME_SERVERS[statuses.indexOf(sleeping)];
        console.log(`Server offline or empty, sending anyway: ${target.url}`);
        return res.json({
            status: "ready",
            serverUrl: target.url.replace("https://", "wss://")
        });
    }

    console.log("No servers available.");
    res.status(503).json({ error: "All servers full or down." });
});

app.get('/', (req, res) => res.send("Matchmaker running."));

app.listen(PORT, () => console.log("Matchmaker live on", PORT));
