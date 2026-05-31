import { getApp, getApps, initializeApp } from "firebase/app";
import { getDatabase, get, ref, set, update, remove } from "firebase/database";
import { trackUserJoined, trackUserRegistered } from "../lib/analyticsClient";

const firebaseConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY || "AIzaSyD3Md8vlOQDg4QoTRJuwNmrv3mg11WMDss",
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN || "worldofnads-1afcf.firebaseapp.com",
  databaseURL:
    import.meta.env.VITE_FIREBASE_DATABASE_URL ||
    "https://worldofnads-1afcf-default-rtdb.firebaseio.com",
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID || "worldofnads-1afcf",
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET || "worldofnads-1afcf.firebasestorage.app",
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID || "129481786742",
  appId: import.meta.env.VITE_FIREBASE_APP_ID || "1:129481786742:web:4bf0e136f1a6e9a72fa657",
  measurementId: import.meta.env.VITE_FIREBASE_MEASUREMENT_ID || "G-QP22W5T17Z"
};

const API_BASE = import.meta.env.VITE_ANALYTICS_API_URL || "";
function buildUrl(path) {
  if (!API_BASE) return path;
  return `${API_BASE}${path}`;
}

export const firebaseApp = getApps().length > 0 ? getApp() : initializeApp(firebaseConfig);
export const db = getDatabase(firebaseApp);

export function getUsernameFromPrivy(user) {
  if (!user?.linkedAccounts) return "Anon";

  // Priority order for social handles
  const providers = [
    { type: "twitter_oauth", field: "username" },
    { type: "farcaster", field: "username" },
    { type: "google_oauth", field: "name" },
    { type: "twitch_oauth", field: "username" },
    { type: "tiktok_oauth", field: "username" },
    { type: "spotify_oauth", field: "name" }
  ];

  for (const provider of providers) {
    const acc = user.linkedAccounts.find((a) => a.type === provider.type);
    if (acc) {
      const val = acc[provider.field];
      if (val) return val;
    }
  }

  // Fallback to wallets
  const ethWallet = user.linkedAccounts.find((acc) => acc.type === "wallet" && acc.chainType === "ethereum");
  const solWallet = user.linkedAccounts.find((acc) => acc.type === "wallet" && acc.chainType === "solana");
  
  return ethWallet?.address || solWallet?.address || "Anon";
}

export function getPrimaryWalletAddress(user) {
  const ethWallet = user?.linkedAccounts?.find((acc) => acc.type === "wallet" && acc.chainType === "ethereum");
  return ethWallet?.address || "";
}

export function getProfilePictureFromPrivy(user) {
  return null;
}

export async function saveUserToFirebase(user) {
  if (!user?.id) return;

  const username = getUsernameFromPrivy(user);
  const twitter = user.linkedAccounts?.find((acc) => acc.type === "twitter_oauth");

  // Explicitly find Ethereum and Solana addresses
  const ethAcc = user.linkedAccounts?.find((acc) => acc.type === "wallet" && acc.chainType === "ethereum");
  const solAcc = user.linkedAccounts?.find((acc) => acc.type === "wallet" && acc.chainType === "solana");

  const userRef = ref(db, `users/${username}`);
  const snapshot = await get(userRef);

  const defaultRoles = buildDefaultRoles(username);
  const existingRoles = snapshot.exists() ? snapshot.val()?.roles : null;
  const normalizedRoles = normalizeRoles(existingRoles, username, defaultRoles);

  const updates = {
    lastLogin: new Date().toISOString(),
    latestVerifiedAt: ethAcc?.latestVerifiedAt || solAcc?.latestVerifiedAt || new Date().toISOString(),
    profilePictureUrl:
      getProfilePictureFromPrivy(user) ||
      "/logo.jpg",
    twitterUsername: twitter?.username || null,
    ethAddress: ethAcc?.address || null, // Capture specifically for Monad payouts
    solAddress: solAcc?.address || null,  // Capture for Solana compatibility
    roles: normalizedRoles,
    equippedSkinId: snapshot.exists() ? snapshot.val()?.equippedSkinId || "s-default" : "s-default"
  };

  if (snapshot.exists()) {
    await update(userRef, updates);
    trackUserJoined({
      userId: user.id,
      metadata: { username }
    });
    return;
  }

  await set(userRef, {
    privyId: user.id,
    username,
    wallet: ethAcc?.address || solAcc?.address || null, // Legacy field
    firstVerifiedAt: twitter?.firstVerifiedAt || ethAcc?.latestVerifiedAt || new Date().toISOString(),
    won: 0,
    projects: [],
    equippedSkinId: "s-default",
    ...updates
  });

  trackUserRegistered({
    userId: user.id,
    metadata: { username }
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

export async function fetchUserProfile(username) {
  if (!username) return null;

  const snapshot = await get(ref(db, `users/${username}`));
  if (!snapshot.exists()) return null;

  return snapshot.val();
}

export async function updateUserEquippedSkin(username, equippedSkinId) {
  if (!username || !equippedSkinId) return;

  await update(ref(db, `users/${username}`), {
    equippedSkinId,
    lastLogin: new Date().toISOString()
  });
}

function buildDefaultRoles(username) {
  const roles = ["player"];
  // Strip all whitespace and @ symbols for robust comparison
  const cleanUsername = String(username || "").toLowerCase().replace(/[\s@]/g, "");
  if (cleanUsername === "worldofnads" || cleanUsername === "tobiawolaju") {
    roles.push("admin", "sponsor");
  }
  return roles;
}

function normalizeRoles(roles, username, fallbackRoles = null) {
  const base = Array.isArray(roles) && roles.length > 0 ? roles : (fallbackRoles || buildDefaultRoles(username));
  const normalized = Array.from(new Set(base.map((role) => String(role).toLowerCase().trim()).filter(Boolean)));
  if (!normalized.includes("player")) normalized.push("player");

  const cleanUsername = String(username || "").toLowerCase().replace(/[\s@]/g, "");
  if (cleanUsername === "worldofnads" || cleanUsername === "tobiawolaju") {
    if (!normalized.includes("admin")) normalized.push("admin");
    if (!normalized.includes("sponsor")) normalized.push("sponsor");
  }
  return normalized;
}

export async function fetchUserRoles(username) {
  if (!username) return ["player"];

  // LOCAL-FIRST ADMIN CHECK: Ensure you always have access even if DB/Rules fail
  const cleanUsername = String(username).toLowerCase().replace(/[^a-z0-9]/g, "");
  const isAdminAccount = cleanUsername === "worldofnads" || cleanUsername === "tobiawolaju";

  try {
    const userRef = ref(db, `users/${username}`);
    const snapshot = await get(userRef);
    
    if (!snapshot.exists()) {
      return buildDefaultRoles(username);
    }

    const data = snapshot.val();
    const normalized = normalizeRoles(data?.roles, username);
    
    // Auto-update roles in DB if they are out of sync (and it's not a hardcoded admin bypass)
    if (JSON.stringify(normalized) !== JSON.stringify(data?.roles || [])) {
      update(userRef, { roles: normalized }).catch(() => {}); // Fire and forget
    }
    return normalized;
  } catch (error) {
    console.error(`[Firebase] fetchUserRoles failed for ${username}, falling back to defaults:`, error);
    // FALLBACK: If DB fails, still grant access if it's one of your known accounts
    return buildDefaultRoles(username);
  }
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
    startTime: Number(match?.startTime || 0),
    createdByWallet: String(match?.createdByWallet || ""),
    depositTxHash: String(match?.depositTxHash || ""),
    settleTxHash: String(match?.settleTxHash || "")
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

export async function deleteMatchFromFirebase(matchId) {
  await remove(ref(db, `matches/${matchId}`));
}

export async function fetchUserRewards(username) {
  if (!username) return [];
  const snapshot = await get(ref(db, "rewards"));
  if (!snapshot.exists()) return [];

  const data = snapshot.val();
  // Filter rewards where username matches
  return Object.values(data)
    .filter(r => r.username === username)
    .sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());
}

export async function fetchUsersFromFirebase() {
  const snapshot = await get(ref(db, "users"));
  if (!snapshot.exists()) return [];

  const data = snapshot.val();
  return Object.entries(data).map(([key, value]) => ({
    username: value?.username || key,
    won: Number(value?.won || 0),
    projects: Array.isArray(value?.projects) ? value.projects : [],
    profilePictureUrl: value?.profilePictureUrl || value?.pfp || "",
    twitterUsername: value?.twitterUsername || null,
    roles: normalizeRoles(value?.roles, value?.username || key)
  }));
}

export async function updateUserRoles(username, roles, adminCode) {
  if (!username) return;

  // Use the backend to update roles securely
  try {
    const response = await fetch(buildUrl("/admin/update-user-roles"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ 
        username, 
        roles, 
        code: adminCode || sessionStorage.getItem("admin_access_code") || "" 
      })
    });

    if (!response.ok) {
      const err = await response.json();
      throw new Error(err.error || "Failed to update roles");
    }

    return roles;
  } catch (error) {
    console.error("Failed to update user roles via backend:", error);
    throw error;
  }
}

function sanitizeKey(value) {
  return String(value || "unknown")
    .trim()
    .replace(/[.#$\[\]/]/g, "_");
}

export async function recordSponsorDailyUniquePlayer({ sponsor, username }) {
  if (!sponsor || !username) return;

  const dateKey = new Date().toISOString().slice(0, 10);
  const sponsorKey = sanitizeKey(sponsor);
  const userKey = sanitizeKey(username);

  const baseRef = ref(db, `analytics/sponsorDailyPlayers/${dateKey}/${sponsorKey}`);
  await set(ref(db, `analytics/sponsorDailyPlayers/${dateKey}/${sponsorKey}/__name`), sponsor);
  await set(ref(db, `analytics/sponsorDailyPlayers/${dateKey}/${sponsorKey}/${userKey}`), {
    username,
    recordedAt: new Date().toISOString()
  });
}

export async function fetchSponsorDailyPlayers(days = 7) {
  const snapshot = await get(ref(db, "analytics/sponsorDailyPlayers"));
  if (!snapshot.exists()) {
    return { dates: [], sponsors: {} };
  }

  const data = snapshot.val();
  const dates = [];
  const sponsors = {};

  for (let i = days - 1; i >= 0; i -= 1) {
    const date = new Date();
    date.setDate(date.getDate() - i);
    const dateKey = date.toISOString().slice(0, 10);
    dates.push(dateKey);

    const dayData = data?.[dateKey] || {};
    Object.entries(dayData).forEach(([sponsorKey, sponsorValue]) => {
      if (!sponsorValue || sponsorKey === "__name") return;
      const name = sponsorValue.__name || sponsorKey;
      if (!sponsors[name]) {
        sponsors[name] = { dailyCounts: {}, usersByDate: {} };
      }

      const users = Object.entries(sponsorValue)
        .filter(([key]) => key !== "__name")
        .map(([, value]) => value?.username)
        .filter(Boolean);

      sponsors[name].dailyCounts[dateKey] = new Set(users).size;
      sponsors[name].usersByDate[dateKey] = Array.from(new Set(users));
    });
  }

  return { dates, sponsors };
}
