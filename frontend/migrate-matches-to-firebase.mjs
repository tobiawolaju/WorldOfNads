import { staticMatches } from "./src/pages/staticMatches.js";

const FIREBASE_DB_URL = "https://worldofnads-1afcf-default-rtdb.firebaseio.com";

async function migrate() {
  for (const match of staticMatches) {
    const payload = {
      ...match,
      createdAt: match.createdAt || new Date(`${match.date}T00:00:00.000Z`).toISOString()
    };

    const response = await fetch(`${FIREBASE_DB_URL}/matches/${payload.matchId}.json`, {
      method: "PUT",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify(payload)
    });

    if (!response.ok) {
      throw new Error(`Failed to migrate ${payload.matchId}: ${response.status} ${response.statusText}`);
    }

    console.log(`migrated ${match.matchId}`);
  }

  console.log(`done: ${staticMatches.length} matches migrated`);
}

migrate().catch((error) => {
  console.error(error);
  process.exit(1);
});
