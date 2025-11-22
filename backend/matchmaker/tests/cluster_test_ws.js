import WebSocket from "ws";

//
// 🔧 CONFIGURATION
//
const SERVERS = [
    "ws://localhost:4000",
    "ws://localhost:4001",
    "ws://localhost:4002",
    "ws://localhost:4003",
    "ws://localhost:4004",
    "ws://localhost:4005",
    "ws://localhost:4006",
    "ws://localhost:4007",
    "ws://localhost:4008",
    "ws://localhost:4009"
];

const PLAYERS_PER_SERVER = 5;        // Number of fake players each server gets
const MOVEMENT_INTERVAL = 100;       // ms — send movement updates
const CONNECT_DELAY = 150;           // ms between opening players
//

function randomFloat() {
    return Math.random() * 10;
}

function createFakePlayer(serverUrl, index) {
    const ws = new WebSocket(serverUrl);

    const id = `${serverUrl}-fake-${index}`;

    ws.on("open", () => {
        console.log(`🟢 [${serverUrl}] Player connected: ${id}`);

        // Movement spam
        const interval = setInterval(() => {
            if (ws.readyState !== 1) return;

            ws.send(JSON.stringify({
                type: "update_state",
                player_id: id,
                x: randomFloat(),
                y: 0,
                z: randomFloat(),
                rotation_y: Math.random() * 360,
                animation: "run"
            }));
        }, MOVEMENT_INTERVAL);

        ws.on("close", () => {
            console.log(`🔴 [${serverUrl}] Player disconnected: ${id}`);
            clearInterval(interval);
        });

        ws.on("error", err => {
            console.log(`❌ [${serverUrl}] Error for ${id}:`, err.message);
        });
    });

    ws.on("message", msg => {
        try {
            const data = JSON.parse(msg);
            if (data.type === "state") {
                console.log(`📡 [${serverUrl}] Broadcast players: ${data.players.length}`);
            }
        } catch (e) {}
    });
}

async function loadServer(serverUrl) {
    console.log(`\n🚀 Loading server ${serverUrl} with ${PLAYERS_PER_SERVER} fake players...\n`);

    for (let i = 1; i <= PLAYERS_PER_SERVER; i++) {
        createFakePlayer(serverUrl, i);
        await new Promise(res => setTimeout(res, CONNECT_DELAY));
    }
}

(async () => {
    console.log(`\n🔥 STRESS TEST STARTED — ${SERVERS.length} servers, ${PLAYERS_PER_SERVER} players each\n`);

    const tasks = SERVERS.map(url => loadServer(url));
    await Promise.all(tasks);

    console.log("\n✨ All fake players spawned. Test running...\n");
})();
