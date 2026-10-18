// Backfill a lobby background onto every match that does not have one.
//
// The dashboard no longer chooses the backdrop at random: it shows the `lobbyBg`
// stored on the match record, falling back to a stable per-match hash. This script
// writes that same stable choice onto older records so their stored detail is
// explicit instead of being derived at read time.
//
// Zero dependencies — it talks to the Firebase Realtime Database REST API with the
// built-in fetch — so it runs with plain `node` (no npm install):
//
//   node scripts/assignLobbyBackgrounds.js           # dry run: print the plan
//   node scripts/assignLobbyBackgrounds.js --write   # persist lobbyBg to Firebase
//
// The image list and hash mirror frontend/src/data/lobbyBackgrounds.js; keep them
// in sync so a match shows the same image before and after it is backfilled.

const LOBBY_BACKGROUNDS = [
  "/lobbybg/lobby (1).jpg",
  "/lobbybg/lobby (2).jpg",
  "/lobbybg/lobby (3).jpg",
  "/lobbybg/lobby (4).jpg",
  "/lobbybg/lobby (5).jpg",
  "/lobbybg/lobby (6).jpg",
  "/lobbybg/lobby (7).jpg",
  "/lobbybg/lobby (8).jpg",
  "/lobbybg/lobby (9).jpg",
];

const DB_URL = (process.env.FIREBASE_DB_URL || "https://worldofnads-3b1a2-default-rtdb.firebaseio.com").replace(/\/+$/, "");
const WRITE = process.argv.includes("--write");

function stableLobbyBgFor(matchId) {
  if (!matchId || !LOBBY_BACKGROUNDS.length) return "/lobbybg.jpeg";
  let hash = 0;
  for (let i = 0; i < matchId.length; i += 1) {
    hash = (hash * 31 + matchId.charCodeAt(i)) >>> 0;
  }
  return LOBBY_BACKGROUNDS[hash % LOBBY_BACKGROUNDS.length];
}

async function main() {
  const res = await fetch(`${DB_URL}/matches.json`);
  if (!res.ok) throw new Error(`GET /matches.json failed: ${res.status} ${await res.text()}`);
  const matches = (await res.json()) || {};

  const entries = Object.entries(matches);
  if (!entries.length) {
    console.log("No matches found.");
    return;
  }

  let changed = 0;
  let skipped = 0;

  for (const [key, match] of entries) {
    const matchId = String(match?.matchId || key);
    const existing = typeof match?.lobbyBg === "string" ? match.lobbyBg.trim() : "";
    if (existing) {
      skipped += 1;
      console.log(`= ${matchId}  keeps ${existing}`);
      continue;
    }

    const lobbyBg = stableLobbyBgFor(matchId);
    changed += 1;

    if (!WRITE) {
      console.log(`~ ${matchId}  -> ${lobbyBg}  (dry run)`);
      continue;
    }

    const putRes = await fetch(`${DB_URL}/matches/${encodeURIComponent(key)}/lobbyBg.json`, {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(lobbyBg),
    });
    if (!putRes.ok) {
      console.error(`! ${matchId}  write failed: ${putRes.status} ${await putRes.text()}`);
      continue;
    }
    console.log(`+ ${matchId}  -> ${lobbyBg}`);
  }

  console.log(`\n${WRITE ? "Wrote" : "Would write"} ${changed} match(es); ${skipped} already set.`);
  if (!WRITE && changed) console.log("Re-run with --write to persist.");
}

main().catch((err) => {
  console.error("assignLobbyBackgrounds failed:", err);
  process.exit(1);
});
