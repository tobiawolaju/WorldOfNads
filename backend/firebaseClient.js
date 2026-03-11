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

    const activeMatch = Object.values(matches)
        .filter(m => (m.status === "upcoming" || m.status === "live") && m.startTime <= now + 600) // 10 min buffer
        .sort((a, b) => a.startTime - b.startTime)[0];

    if (activeMatch) {
        console.log(`[Firebase] Found candidate match for payout: ${activeMatch.matchId} (Status: ${activeMatch.status})`);
    }

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

export async function getAllMatches() {
    const matchesRef = ref(db, "matches");
    const snapshot = await get(matchesRef);
    if (!snapshot.exists()) return {};
    return snapshot.val();
}

export async function updateMatchStatus(matchId, status) {
    const matchRef = ref(db, `matches/${matchId}`);
    await update(matchRef, { status });
}

export async function saveReward(rewardData) {
    const rewardId = `reward-${Date.now()}-${Math.floor(Math.random() * 1000)}`;
    const rewardRef = ref(db, `rewards/${rewardId}`);
    await update(rewardRef, {
        ...rewardData,
        id: rewardId,
        createdAt: new Date().toISOString()
    });
    console.log(`[Firebase] Reward saved for ${rewardData.username}: ${rewardData.amount}`);
}
