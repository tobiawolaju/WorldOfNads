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
console.log('Leaderboard worker is running')}