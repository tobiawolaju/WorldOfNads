import { db } from './firebaseClient.js';
import { ref, get, update } from 'firebase/database';

const PRIVY_APP_ID = process.env.PRIVY_APP_ID;
const PRIVY_APP_SECRET = process.env.PRIVY_APP_SECRET;
const PRIVY_API_BASE = 'https://api.privy.io/v1';

const BATCH_SIZE = 10;
const DELAY_BETWEEN_BATCHES_MS = 1000;

function getAuthHeader() {
  const token = Buffer.from(`${PRIVY_APP_ID}:${PRIVY_APP_SECRET}`).toString('base64');
  return `Basic ${token}`;
}

async function fetchPrivyUser(privyId) {
  const res = await fetch(`${PRIVY_API_BASE}/users/${privyId}`, {
    headers: {
      'Authorization': getAuthHeader(),
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
    if (acc.profile_picture_url || acc.profilePictureUrl) {
      return acc.profile_picture_url || acc.profilePictureUrl;
    }
  }
  return null;
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

export async function refreshAllUserPfps() {
  if (!PRIVY_APP_ID || !PRIVY_APP_SECRET) {
    console.warn('[PfpRefresh] Missing PRIVY_APP_SECRET, skipping.');
    return { updated: 0, skipped: 0, errors: 0 };
  }

  console.log('[PfpRefresh] Starting PFP refresh cycle...');
  const usersRef = ref(db, 'users');
  const snapshot = await get(usersRef);

  if (!snapshot.exists()) {
    console.log('[PfpRefresh] No users found.');
    return { updated: 0, skipped: 0, errors: 0 };
  }

  const users = snapshot.val();
  const entries = Object.entries(users).filter(([, data]) => data?.privyId);

  console.log(`[PfpRefresh] Found ${entries.length} users with privyId.`);

  let updated = 0;
  let skipped = 0;
  let errors = 0;

  for (let i = 0; i < entries.length; i += BATCH_SIZE) {
    const batch = entries.slice(i, i + BATCH_SIZE);

    const results = await Promise.allSettled(
      batch.map(async ([username, userData]) => {
        try {
          const privyUser = await fetchPrivyUser(userData.privyId);
          const newPfp = extractPfp(privyUser);
          const currentPfp = userData.profilePictureUrl || '';

          if (newPfp && newPfp !== currentPfp) {
            await update(ref(db, `users/${username}`), {
              profilePictureUrl: newPfp,
            });
            console.log(`[PfpRefresh] Updated ${username}: ${currentPfp.slice(0, 40)} → ${newPfp.slice(0, 40)}`);
            return 'updated';
          }

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

    if (i + BATCH_SIZE < entries.length) {
      await sleep(DELAY_BETWEEN_BATCHES_MS);
    }
  }

  console.log(`[PfpRefresh] Done. Updated: ${updated}, Skipped: ${skipped}, Errors: ${errors}`);
  return { updated, skipped, errors };
}
