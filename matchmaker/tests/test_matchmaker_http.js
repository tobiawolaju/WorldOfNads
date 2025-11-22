import fetch from "node-fetch";

const MATCHMAKER_URL = "http://localhost:3000/find-match"; 
const CLIENT_COUNT = 50; // simulate 50 users finding matches
const DELAY = 200;       // ms between each client

function wait(ms) {
    return new Promise(res => setTimeout(res, ms));
}

async function simulateClient(i) {
    try {
        const res = await fetch(MATCHMAKER_URL);
        const data = await res.json();
        console.log(`Client ${i} =>`, data);
    } catch (e) {
        console.log(`Client ${i} => ERROR`, e.message);
    }
}

(async () => {
    console.log(`Starting ${CLIENT_COUNT} matchmaker tests...\n`);
    
    for (let i = 1; i <= CLIENT_COUNT; i++) {
        simulateClient(i);
        await wait(DELAY);   
    }
})();
