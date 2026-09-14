import { db } from './firebaseClient.js';
import { ref, get, update } from 'firebase/database';

const PRIVY_APP_ID = process.env.PRIVY_APP_ID;
const PRIVY_APP_SECRET = process.env.PRIVY_APP_SECRET;
const PRIVY_API_BASE = 'https://auth.privy.io/api/v1';

const BATCH_SIZE = 10;
const DELAY_BETWEEN_BATCHES_MS = 1000;
const REFRESH_INTERVAL_MS = 24 * 60 * 60 * 1000; // 24 hours — skip users refreshed recently

function getAuthHeader() {
  const token = Buffer.from(`${PRIVY_APP_ID}:${PRIVY_APP_SECRET}`).toString('base64');
  return `Basic ${token}`;
}

async function fetchPrivyUser(privyId) {
  const res = await fetch(`${PRIVY_API_BASE}/users/${privyId}`, {
    headers: {
      'Authorization': getAuthHeader(),
      'privy-app-id': PRIVY_APP_ID,
      'Content-Type': 'application/json',
    },
  });

  if (!res.ok) {
    throw new Error(`Privy API ${res.status}: ${res.statusText}`);
  }

  return res.json();
}

function extractPfp(privyUser) {
  const linkedAccounts = privyUser?.linked_accounts || privyUser?.linkedAccounts || [];
  for (const acc of linkedAccounts) {
    const pfp = acc.profile_picture_url || acc.profilePictureUrl || acc.image || acc.avatar || acc.picture || null;
    if (pfp) return pfp;
  }
  return null;
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function needsRefresh(userData) {
  const lastRefresh = userData?.lastPfpRefresh;
  if (!lastRefresh) return true;
  const elapsed = Date.now() - new Date(lastRefresh).getTime();
  return elapsed > REFRESH_INTERVAL_MS;
}

export async function refreshAllUserPfps(force = false) {
  if (!PRIVY_APP_ID || !PRIVY_APP_SECRET) {
    console.warn('[PfpRefresh] Missing PRIVY_APP_SECRET, skipping.');
    return { updated: 0, skipped: 0, errors: 0, total: 0 };
  }

  console.log('[PfpRefresh] Starting PFP refresh cycle...');
  const usersRef = ref(db, 'users');
  const snapshot = await get(usersRef);

  if (!snapshot.exists()) {
    console.log('[PfpRefresh] No users found.');
    return { updated: 0, skipped: 0, errors: 0, total: 0 };
  }

  const users = snapshot.val();
  const allEntries = Object.entries(users).filter(([, data]) => data?.privyId);
  const needsRefreshEntries = force
    ? allEntries
    : allEntries.filter(([, data]) => needsRefresh(data));

  console.log(`[PfpRefresh] ${allEntries.length} users total, ${needsRefreshEntries.length} need refresh${force ? ' (forced)' : ' (>24h since last)'}.`);

  if (needsRefreshEntries.length === 0) {
    console.log('[PfpRefresh] All users recently refreshed, skipping.');
    return { updated: 0, skipped: 0, errors: 0, total: allEntries.length };
  }

  let updated = 0;
  let skipped = 0;
  let errors = 0;
  let loggedDebug = false;

  for (let i = 0; i < needsRefreshEntries.length; i += BATCH_SIZE) {
    const batch = needsRefreshEntries.slice(i, i + BATCH_SIZE);

    const results = await Promise.allSettled(
      batch.map(async ([username, userData]) => {
        try {
          const privyUser = await fetchPrivyUser(userData.privyId);
          const newPfp = extractPfp(privyUser);
          const currentPfp = userData.profilePictureUrl || '';

          // Debug: log first user's raw response to inspect field names
          if (i === 0 && !loggedDebug) {
            loggedDebug = true;
            const accounts = privyUser?.linked_accounts || privyUser?.linkedAccounts || [];
            console.log(`[PfpRefresh] DEBUG raw linked_accounts for ${username}:`, JSON.stringify(accounts.map(a => ({ type: a.type, keys: Object.keys(a), pfp: a.profile_picture_url || a.profilePictureUrl || a.image || a.avatar || null })), null, 2));
          }

          if (newPfp && newPfp !== currentPfp) {
            await update(ref(db, `users/${username}`), {
              profilePictureUrl: newPfp,
              lastPfpRefresh: new Date().toISOString(),
            });
            console.log(`[PfpRefresh] Updated ${username}: ${currentPfp.slice(0, 40)} → ${newPfp.slice(0, 40)}`);
            return 'updated';
          }

          // PFP unchanged — just update the timestamp so we don't re-check for 24h
          await update(ref(db, `users/${username}`), {
            lastPfpRefresh: new Date().toISOString(),
          });
          return 'skipped';
        } catch (err) {
          console.error(`[PfpRefresh] Failed for ${username}:`, err.message);
          return 'error';
        }
      })
    );

    for (const r of results) {
      const val = r.status === 'fulfilled' ? r.value : 'error';
      if (val === 'updated') updated++;
      else if (val === 'skipped') skipped++;
      else errors++;
    }

    if (i + BATCH_SIZE < needsRefreshEntries.length) {
      await sleep(DELAY_BETWEEN_BATCHES_MS);
    }
  }

  console.log(`[PfpRefresh] Done. Updated: ${updated}, Skipped: ${skipped}, Errors: ${errors}`);
  return { updated, skipped, errors, total: allEntries.length };
}
