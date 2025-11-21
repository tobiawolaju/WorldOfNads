# WorldOfNads Backend

This document outlines the file structure and purpose of each file in the backend of the WorldOfNads project.

## File Structure

```
backend/
├───package-lock.json
├───package.json
├───server.js
├───node_modules/
└───src/
    ├───MessageTypes.js
    ├───Player.js
    └───World.js
```

## File Descriptions

### `server.js`
This is the main entry point for the backend server. It initializes the WebSocket server using the `ws` library, handles incoming player connections, processes player inputs, and broadcasts the authoritative game state to all clients at a fixed tick rate. It contains the primary game loop and server-side physics calculations.

### `package.json`
Defines the project's metadata, including its name, version, and dependencies. Key dependencies include `ws` for the WebSocket server and `uuid` for generating unique player identifiers. It also contains scripts for running the server.

### `package-lock.json`
An auto-generated file that locks the specific versions of the project's dependencies to ensure consistent installations across different environments.

### `src/`
This directory contains the core application logic, separated into distinct modules.

#### `src/World.js`
Defines the `World` class, which is responsible for managing the overall game state. This includes maintaining a collection of all connected players and providing methods to add, remove, and update them.

#### `src/Player.js`
Defines the `Player` class. Each instance represents a player connected to the server. It holds player-specific state such as their unique ID, position (`x`, `y`, `z`), rotation, and current inputs.

#### `src/MessageTypes.js`
A utility file that exports constants for the different types of messages sent over the WebSocket connection (e.g., `CONNECT`, `STATE`, `INPUT`). This provides a clear and consistent communication protocol between the client and server.














//for non game part
# WONs Backend Starter Repo

This document contains a complete starter backend repo for **World of Nads (WONs)** using **Node.js** + **Firebase Realtime Database** and a cron job to rebuild the leaderboard hourly. It also includes endpoints for creating users (sent from the frontend via Privy), signaling when joining a match, and recording match results so the leaderboard can be generated.

---

## Repo structure (what you'll get)

```
/wons-backend-starter
├─ README.md
├─ package.json
├─ .env.example
├─ serviceAccount.example.json (rename to serviceAccount.json when deploying)
├─ src/
│  ├─ index.js               # Main Express server + endpoints
│  ├─ firebase.js            # Firebase admin init & helpers
│  ├─ leaderboardWorker.js   # Cron worker that rebuilds /leaderboard every hour
│  └─ utils.js               # small helpers & validation
└─ firebase.rules.json       # Example Realtime DB rules
```

---

## README (quick start)

```md
# WONs Backend Starter

## Requirements
- Node.js 18+
- Firebase project (Realtime Database enabled)
- Service account JSON with admin privileges (download from Firebase Console)

## Setup
1. Clone this repo.
2. Copy `.env.example` to `.env` and fill values.
3. Place your Firebase serviceAccount JSON at `serviceAccount.json` (or point env to its path).
4. `npm install`
5. `npm run dev` to run in development.

## Endpoints
- `POST /api/create-user` - Create or update a user (payload from Privy/frontend).
- `POST /api/join-match` - Signal a user joining a match (frontend signals when joining lobby/match).
- `POST /api/record-match` - Record a finished match and the winner(s).
- `GET /api/leaderboard` - Read the cached leaderboard (also served via realtime DB at `/leaderboard`).

## Cron
A cron job rebuilds `/leaderboard` hourly. It can be run as a separate worker process (provided here) or imported into your server run.

## Security
- Use `BACKEND_SECRET` env var and require it in requests from your frontend if you don't use a full auth middleware yet.
- For production, use Firebase Auth or signed tokens (demonstrated as future improvements).
```

---

## package.json

```json
{
  "name": "wons-backend-starter",
  "version": "1.0.0",
  "main": "src/index.js",
  "scripts": {
    "start": "node src/index.js",
    "dev": "nodemon src/index.js",
    "worker": "node src/leaderboardWorker.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "firebase-admin": "^11.10.1",
    "body-parser": "^1.20.2",
    "node-cron": "^3.0.2",
    "cors": "^2.8.5",
    "dotenv": "^16.3.1"
  },
  "devDependencies": {
    "nodemon": "^3.0.1"
  }
}
```

---

## .env.example

```
PORT=4000
FIREBASE_DB_URL=https://<your-project-id>.firebaseio.com
SERVICE_ACCOUNT_PATH=./serviceAccount.json
BACKEND_SECRET=replace_with_a_long_random_string
LEADERBOARD_SIZE=50
```

---

## src/firebase.js

```js
// src/firebase.js
const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
require('dotenv').config();

const SERVICE_ACCOUNT_PATH = process.env.SERVICE_ACCOUNT_PATH || './serviceAccount.json';
const DB_URL = process.env.FIREBASE_DB_URL;

if (!fs.existsSync(SERVICE_ACCOUNT_PATH)) {
  console.warn('WARNING: service account JSON not found at', SERVICE_ACCOUNT_PATH);
}

const serviceAccount = fs.existsSync(SERVICE_ACCOUNT_PATH)
  ? require(path.resolve(SERVICE_ACCOUNT_PATH))
  : null;

if (!admin.apps.length) {
  admin.initializeApp({
    credential: serviceAccount ? admin.credential.cert(serviceAccount) : admin.credential.applicationDefault(),
    databaseURL: DB_URL,
  });
}

const db = admin.database();

module.exports = { admin, db };
```

---

## src/utils.js

```js
// src/utils.js
function requireSecret(req, res, next) {
  const secret = req.get('x-backend-secret') || req.body.backendSecret || req.query.backendSecret;
  if (!process.env.BACKEND_SECRET) return next(); // if none set, skip (dev)
  if (!secret || secret !== process.env.BACKEND_SECRET) return res.status(401).json({ ok: false, error: 'Unauthorized' });
  next();
}

function now() {
  return Date.now();
}

module.exports = { requireSecret, now };
```

---

## src/index.js (Express server + endpoints)

```js
// src/index.js
const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');
require('dotenv').config();

const { db } = require('./firebase');
const { requireSecret, now } = require('./utils');

const app = express();
app.use(cors());
app.use(bodyParser.json());

const PORT = process.env.PORT || 4000;

// --- Helper ref getters ---
const usersRef = () => db.ref('users');
const matchesRef = () => db.ref('matches');
const leaderboardRef = () => db.ref('leaderboard');

// --- Create or update user ---
// Frontend (Privy) posts user data here. Example payload:
// { uid, username, wallet, pfp }
app.post('/api/create-user', requireSecret, async (req, res) => {
  try {
    const { uid, username, wallet, pfp } = req.body;
    if (!uid) return res.status(400).json({ ok: false, error: 'uid required' });

    const userData = {
      username: username || `user_${uid.slice(0,6)}`,
      wallet: wallet || null,
      pfp: pfp || null,
      won: 0,
      xp: 0,
      level: 1,
      totalGames: 0,
      projects: [],
      createdAt: now(),
      updatedAt: now(),
    };

    await usersRef().child(uid).update(userData);

    return res.json({ ok: true, uid, userData });
  } catch (err) {
    console.error(err);
    res.status(500).json({ ok: false, error: err.message });
  }
});

// --- Join match ---
// Frontend signals when a player joins a match/lobby.
// Payload: { matchId, title, uid }
app.post('/api/join-match', requireSecret, async (req, res) => {
  try {
    const { matchId, title, uid } = req.body;
    if (!matchId || !uid) return res.status(400).json({ ok: false, error: 'matchId and uid required' });

    const matchNode = matchesRef().child(matchId);
    const snapshot = await matchNode.once('value');

    if (!snapshot.exists()) {
      // create match
      await matchNode.set({
        matchId,
        title: title || 'untitled-match',
        participants: {},
        createdAt: now(),
        finished: false
      });
    }

    await matchNode.child(`participants/${uid}`).set({ joinedAt: now() });

    return res.json({ ok: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ ok: false, error: err.message });
  }
});

// --- Record match result ---
// Payload: { matchId, winners: [{ uid, prizeAmount }], stats?: { uid: { xpEarned, wonIncrement } } }
app.post('/api/record-match', requireSecret, async (req, res) => {
  try {
    const { matchId, winners = [], stats = {} } = req.body;
    if (!matchId) return res.status(400).json({ ok: false, error: 'matchId required' });

    const matchNode = matchesRef().child(matchId);
    const matchSnap = await matchNode.once('value');
    if (!matchSnap.exists()) return res.status(404).json({ ok: false, error: 'match not found' });

    // Mark finished
    await matchNode.update({ finished: true, finishedAt: now(), winners });

    const updates = {};

    // Apply stats/winner rewards to users
    winners.forEach(w => {
      const uid = w.uid;
      const prize = w.prizeAmount || 0;
      // increase won count or currency. We'll increment 'won' as a measure (you may store balances separately)
      updates[`users/${uid}/won`] = db.ref().child(`users/${uid}/won`).transaction(current => (current || 0) + 1).catch(() => null);
      updates[`users/${uid}/totalGames`] = db.ref().child(`users/${uid}/totalGames`).transaction(current => (current || 0) + 1).catch(() => null);
      updates[`users/${uid}/updatedAt`] = now();
    });

    // apply generic stats per uid
    for (const [uid, s] of Object.entries(stats || {})) {
      if (s.xpEarned) {
        await db.ref(`users/${uid}/xp`).transaction(curr => (curr || 0) + s.xpEarned);
      }
      if (s.wonIncrement) {
        await db.ref(`users/${uid}/won`).transaction(curr => (curr || 0) + s.wonIncrement);
      }
      await db.ref(`users/${uid}/totalGames`).transaction(curr => (curr || 0) + (s.played ? 1 : 0));
      await db.ref(`users/${uid}/updatedAt`).set(now());
    }

    return res.json({ ok: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ ok: false, error: err.message });
  }
});

// --- Read leaderboard (cached) ---
app.get('/api/leaderboard', async (req, res) => {
  try {
    const snap = await leaderboardRef().once('value');
    const data = snap.exists() ? snap.val() : null;
    res.json({ ok: true, leaderboard: data });
  } catch (err) {
    console.error(err);
    res.status(500).json({ ok: false, error: err.message });
  }
});

// --- simple health check ---
app.get('/_health', (req, res) => res.json({ ok: true, ts: now() }));

app.listen(PORT, () => console.log(`WONs backend running on port ${PORT}`));
```

---

## src/leaderboardWorker.js

This file can be run as a separate process (`npm run worker`) or imported. It scans `/users`, computes top N by `won` (or custom metric), and writes to `/leaderboard`.

```js
// src/leaderboardWorker.js
const cron = require('node-cron');
require('dotenv').config();
const { db } = require('./firebase');

const TOP_N = parseInt(process.env.LEADERBOARD_SIZE || '50', 10);

async function rebuildLeaderboard() {
  console.log('Rebuilding leaderboard...');
  try {
    const snap = await db.ref('users').once('value');
    if (!snap.exists()) {
      console.log('No users found. Clearing leaderboard.');
      await db.ref('leaderboard').set([]);
      return;
    }

    const users = snap.val();
    const arr = Object.entries(users).map(([uid, u]) => ({ uid, ...u }));

    // Sort by 'won' descending, then xp, then totalGames
    arr.sort((a, b) => {
      if ((b.won || 0) !== (a.won || 0)) return (b.won || 0) - (a.won || 0);
      if ((b.xp || 0) !== (a.xp || 0)) return (b.xp || 0) - (a.xp || 0);
      return (b.totalGames || 0) - (a.totalGames || 0);
    });

    const top = arr.slice(0, TOP_N).map((u, i) => ({ rank: i + 1, uid: u.uid, username: u.username, won: u.won || 0, xp: u.xp || 0, pfp: u.pfp || null }));

    await db.ref('leaderboard').set(top);
    console.log(`Leaderboard updated with ${top.length} entries.`);
  } catch (err) {
    console.error('Error rebuilding leaderboard', err);
  }
}

// Run immediately once
rebuildLeaderboard();

// AND schedule hourly at minute 0
cron.schedule('0 * * * *', async () => {
  console.log('Cron triggered: rebuilding leaderboard...');
  await rebuildLeaderboard();
});

// Keep process alive if run directly
if (require.main === module) {
  console.log('Leaderboard worker is running.');
}
```

---

## firebase.rules.json (example)

```json
{
  "rules": {
    "users": {
      "$uid": {
        ".read": true,
        ".write": "auth != null"
      }
    },
    "matches": {
      ".read": true,
      ".write": true
    },
    "leaderboard": {
      ".read": true,
      ".write": false
    }
  }
}
```

> **Note:** Realtime DB rules should be adapted to your auth method. Above is a minimal example — for a production app you should require authenticated requests or a server-controlled write path.

---

## Example frontend snippets

**Create user (Privy/login) — POST to backend**

```js
// after Privy or wallet login, send user to backend
const payload = { uid: userId, username: displayName, wallet, pfp };
fetch('https://your-backend.example.com/api/create-user', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', 'x-backend-secret': BACKEND_SECRET },
  body: JSON.stringify(payload)
});
```

**Signal join match**

```js
fetch('https://your-backend.example.com/api/join-match', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', 'x-backend-secret': BACKEND_SECRET },
  body: JSON.stringify({ matchId: 'match_123', title: 'Bonk Cup', uid: myUid })
});
```

**Record match (server or match host calls this)**

```js
fetch('https://your-backend.example.com/api/record-match', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', 'x-backend-secret': BACKEND_SECRET },
  body: JSON.stringify({
    matchId: 'match_123',
    winners: [{ uid: '0xabc', prizeAmount: 5 }],
    stats: { '0xabc': { xpEarned: 50, wonIncrement: 1, played: true } }
  })
});
```

---

## Deployment notes

* For small scale, run `src/index.js` (Express) and `src/leaderboardWorker.js` on the same machine or two processes.
* If using serverless (Vercel), run the API as an express server on a proper Node host (e.g., Render, Fly, Railway) and run the worker as a separate worker service.
* Use environment variables securely in production.
* Replace `BACKEND_SECRET` with a long random string and add checks in the frontend headers.
* For production security, replace `x-backend-secret` with signed JWTs or Firebase Auth tokens.

---

## Next steps & optional improvements

* Add Firebase Authentication and validate incoming requests with Firebase ID tokens.
* Implement rate limiting and stronger validation on endpoints.
* Track match telemetry (duration, passes, stamina usage) and expand leaderboard metrics.
* Add a separate financial ledger for prize payouts on-chain (Monad) — link DB match results to on-chain settlement service.

---

That's everything to get started. Copy the files into a repo and run `npm install` then `npm run dev` to test locally.
