import { getApp, getApps, initializeApp } from "firebase/app";
import { getDatabase, get, ref, set, update } from "firebase/database";

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

export const firebaseApp = getApps().length > 0 ? getApp() : initializeApp(firebaseConfig);
export const db = getDatabase(firebaseApp);

export function getUsernameFromPrivy(user) {
  const twitter = user?.linkedAccounts?.find((acc) => acc.type === "twitter_oauth");
  const ethWallet = user?.linkedAccounts?.find((acc) => acc.type === "wallet" && acc.chainType === "ethereum");
  const solWallet = user?.linkedAccounts?.find((acc) => acc.type === "wallet" && acc.chainType === "solana");
  return twitter?.username || ethWallet?.address || solWallet?.address || "Anon";
}

export function getPrimaryWalletAddress(user) {
  const ethWallet = user?.linkedAccounts?.find((acc) => acc.type === "wallet" && acc.chainType === "ethereum");
  return ethWallet?.address || "";
}

export async function saveUserToFirebase(user) {
  if (!user?.id) return;

  const username = getUsernameFromPrivy(user);
  const twitter = user.linkedAccounts?.find((acc) => acc.type === "twitter_oauth");
  const wallet = user.linkedAccounts?.find((acc) => acc.type === "wallet");
  const userRef = ref(db, `users/${username}`);
  const snapshot = await get(userRef);

  const updates = {
    lastLogin: new Date().toISOString(),
    latestVerifiedAt: twitter?.latestVerifiedAt || wallet?.latestVerifiedAt || new Date().toISOString(),
    profilePictureUrl:
      twitter?.profilePictureUrl ||
      "https://abs.twimg.com/sticky/default_profile_images/default_profile_400x400.png"
  };

  if (snapshot.exists()) {
    await update(userRef, updates);
    return;
  }

  await set(userRef, {
    privyId: user.id,
    username,
    wallet: wallet?.address || null,
    firstVerifiedAt: twitter?.firstVerifiedAt || wallet?.firstVerifiedAt || new Date().toISOString(),
    won: 0,
    projects: [],
    ...updates
  });
}

export async function updateUserProjects(username, matchSponsorName) {
  const userRef = ref(db, `users/${username}`);
  const snapshot = await get(userRef);
  if (!snapshot.exists()) return;

  const userData = snapshot.val();
  const currentProjects = userData.projects || [];
  if (currentProjects.includes(matchSponsorName)) return;

  await update(userRef, {
    projects: [...currentProjects, matchSponsorName]
  });
}

export function normalizeMatchRecord(match, fallbackKey = "") {
  const matchId = String(match?.matchId || fallbackKey || `match-${Date.now()}`);
  const prizeAmount = Number(match?.prizeAmount || 0);

  return {
    id: Number(match?.id || Date.now()),
    matchId,
    sponsor: String(match?.sponsor || "Unknown Sponsor"),
    prize: String(match?.prize || (prizeAmount > 0 ? `${prizeAmount} ${match?.prizeToken || "MON"}` : "0 MON")),
    prizeAmount,
    prizeToken: String(match?.prizeToken || "MON"),
    status: match?.status || "upcoming",
    time: String(match?.time || "Upcoming"),
    date: String(match?.date || new Date().toISOString().slice(0, 10)),
    image: String(match?.image || "/logo.jpg"),
    description: String(match?.description || ""),
    url: String(match?.url || ""),
    createdAt: String(match?.createdAt || new Date().toISOString()),
    createdByWallet: String(match?.createdByWallet || ""),
    depositTxHash: String(match?.depositTxHash || "")
  };
}

export async function fetchMatchesFromFirebase() {
  const snapshot = await get(ref(db, "matches"));
  if (!snapshot.exists()) {
    return [];
  }

  const data = snapshot.val();
  return Object.entries(data)
    .map(([key, value]) => normalizeMatchRecord(value, key))
    .sort((a, b) => {
      const left = new Date(b.createdAt || b.date).getTime();
      const right = new Date(a.createdAt || a.date).getTime();
      return left - right;
    });
}

export async function saveMatchToFirebase(matchInput) {
  const match = normalizeMatchRecord(matchInput);
  await set(ref(db, `matches/${match.matchId}`), match);
  return match;
}
