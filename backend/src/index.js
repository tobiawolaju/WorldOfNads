// src/index.js


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