import { initializeApp } from "firebase/app";
import { getDatabase, ref, get, update, set } from "firebase/database";
import * as dotenv from 'dotenv';
dotenv.config();

const firebaseConfig = {
  apiKey: "AIzaSyBNFaveUoWNE4bBTNBgCnK63Bp25BFr5gs",
  authDomain: "worldofnads-3b1a2.firebaseapp.com",
  databaseURL: "https://worldofnads-3b1a2-default-rtdb.firebaseio.com",
  projectId: "worldofnads-3b1a2",
  storageBucket: "worldofnads-3b1a2.firebasestorage.app",
  messagingSenderId: "15570864804",
  appId: "1:15570864804:web:23a40e23b715988f9af431",
  measurementId: "G-K9Q3JQVRBW"
};

const app = initializeApp(firebaseConfig);
export const db = getDatabase(app);

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
    const eligibleStatuses = new Set(["upcoming", "live", "completed"]);
    const tenMinutes = 600;
    const lookbackSeconds = 3600; // avoid picking stale matches

    const eligible = Object.values(matches)
        .filter((m) => {
            if (!m || !m.matchId || !m.startTime) return false;
            if (!eligibleStatuses.has(m.status)) return false;
            if (m.status === "settled" || m.status === "cancelled") return false;
            if (m.startTime < now - lookbackSeconds) return false;
            return m.startTime <= now + tenMinutes;
        });

    const started = eligible.filter(m => m.startTime <= now);
    const pool = started.length > 0 ? started : eligible;

    const activeMatch = pool.sort((a, b) => b.startTime - a.startTime)[0];

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

export async function updateUserRoles(username, roles) {
    if (!username) return;
    const userRef = ref(db, `users/${username}`);
    await update(userRef, { roles });
    console.log(`[Firebase] Roles updated for ${username}:`, roles);
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

export async function getPlayerProfile(username) {
    if (!username) return null;
    const userRef = ref(db, `users/${username}`);
    const snapshot = await get(userRef);
    if (snapshot.exists()) {
        return snapshot.val();
    }
    return null;
}

export async function getPlayerSkin(username) {
    if (!username) return 's-default';
    const userRef = ref(db, `users/${username}/skin`);
    const snapshot = await get(userRef);
    if (snapshot.exists()) {
        const val = snapshot.val();
        if (typeof val === 'string' && val.trim()) return val.trim();
    }
    return null; // null means "not stored in Firebase yet, fallback to URL param"
}

export async function clearPlayerSkin(username) {
    if (!username) return;
    await set(ref(db, `users/${username}/skin`), null);
}

export async function updatePlayerXP(username, xp) {
    if (!username) return;
    const userRef = ref(db, `users/${username}`);
    await update(userRef, {
        xp: xp,
        lastUpdated: new Date().toISOString()
    });
}

// ─── SKIN METADATA ───

const SKIN_SCHEMA_VERSION = 1;

export async function saveSkin(skinId, skinData) {
    const skinRef = ref(db, `skins/${skinId}`);
    await update(skinRef, {
        ...skinData,
        schemaVersion: SKIN_SCHEMA_VERSION,
        updatedAt: new Date().toISOString()
    });
    console.log(`[Firebase] Skin saved: ${skinId}`);
}

export async function getSkin(skinId) {
    const skinRef = ref(db, `skins/${skinId}`);
    const snapshot = await get(skinRef);
    if (snapshot.exists()) {
        return snapshot.val();
    }
    return null;
}

export async function getAllSkins() {
    const skinsRef = ref(db, 'skins');
    const snapshot = await get(skinsRef);
    if (snapshot.exists()) {
        const data = snapshot.val();
        return Object.entries(data).map(([id, val]) => ({ id, ...val }));
    }
    return [];
}
