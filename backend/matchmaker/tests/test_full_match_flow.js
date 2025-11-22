import fetch from "node-fetch";
import WebSocket from "ws";

const MATCHMAKER = "http://localhost:3000/find-match";
const CLIENTS = 20;
const CONNECT_DELAY = 300;

function sleep(ms) {
    return new Promise(r => setTimeout(r, ms));
}

async function simulateClient(i) {
    try {
        console.log(`\n🔎 Client ${i} requesting a match...`);
        
        const res = await fetch(MATCHMAKER);
        const data = await res.json();

        console.log(`Client ${i} matchmaker response:`, data);

        if (data.status !== "ready") return;

        const wsURL = data.serverUrl.replace("http://", "ws://");

        console.log(`Client ${i} connecting to WS: ${wsURL}`);

        const ws = new WebSocket(wsURL);

        ws.on("open", () => {
            console.log(`Client ${i}: WS connected.`);

            // send fake player movement
            setInterval(() => {
                ws.send(JSON.stringify({
                    type: "update_state",
                    player_id: "test-client-" + i,
                    x: Math.random(),
                    y: 0,
                    z: Math.random(),
                    rotation_y: Math.random() * 360,
                    animation: "run"
                }));
            }, 100);
        });

        ws.on("message", msg => {
            const data = JSON.parse(msg);
            if (data.type === "state") {
                console.log(`Client ${i}: received ${data.players.length} players`);
            }
        });

        ws.on("close", () => console.log(`Client ${i}: WS closed.`));
        ws.on("error", err => console.log(`Client ${i}: WS error`, err.message));

    } catch (err) {
        console.log(`Client ${i}: ERROR ->`, err.message);
    }
}

(async () => {
    console.log(`\nLaunching ${CLIENTS} simulated players...\n`);

    for (let i = 1; i <= CLIENTS; i++) {
        simulateClient(i);
        await sleep(CONNECT_DELAY);
    }
})();
