import { initializeApp } from "firebase/app";
import { getDatabase, ref, get, update } from "firebase/database";
import * as dotenv from 'dotenv';
dotenv.config();

const firebaseConfig = {
    apiKey: "AIzaSyD3Md8vlOQDg4QoTRJuwNmrv3mg11WMDss",
    authDomain: "worldofnads-1afcf.firebaseapp.com",
    databaseURL: "https://worldofnads-1afcf-default-rtdb.firebaseio.com",
    projectId: "worldofnads-1afcf",
    storageBucket: "worldofnads-1afcf.firebasestorage.app",
    messagingSenderId: "129481786742",
    appId: "1:129481786742:web:4bf0e136f1a6e9a72fa657",
    measurementId: "G-QP22W5T17Z"
};

const app = initializeApp(firebaseConfig);
const db = getDatabase(app);

export async function getPlayerWallet(username) {
    if (!username) return null;
    const userRef = ref(db, `users/${username}`);
    const snapshot = await get(userRef);
    if (snapshot.exists()) {
        const data = snapshot.val();
        return data.ethAddress || data.wallet || null;
    }
    return null;
}

export async function findActiveMatch() {
    const matchesRef = ref(db, "matches");
    const snapshot = await get(matchesRef);
    if (!snapshot.exists()) return null;

    const matches = snapshot.val();
    const now = Math.floor(Date.now() / 1000);

    // Find a match that is "upcoming" and whose startTime has passed (or is close)
    // Logic: oldest upcoming match that is already started or about to start
    const activeMatch = Object.values(matches)
        .filter(m => m.status === "upcoming" && m.startTime <= now + 300) // 5 min buffer
        .sort((a, b) => a.startTime - b.startTime)[0];

    return activeMatch || null;
}

export async function markMatchSettled(matchId, txHash) {
    const matchRef = ref(db, `matches/${matchId}`);
    await update(matchRef, {
        status: "settled",
        settledAt: new Date().toISOString(),
        settleTxHash: txHash
    });
}
