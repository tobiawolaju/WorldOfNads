import { initializeApp } from "firebase/app";
import { getDatabase, ref, remove, get } from "firebase/database";

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
const db = getDatabase(app);

async function main() {
  const snap = await get(ref(db, 'skins'));
  if (!snap.exists()) {
    console.log('No skins found.');
    return;
  }
  const all = snap.val();
  const toDelete = Object.keys(all).filter(k => k.startsWith('s-178'));
  console.log(`Found ${toDelete.length} old API skins to delete: ${toDelete.join(', ')}`);
  for (const key of toDelete) {
    await remove(ref(db, `skins/${key}`));
    console.log(`  Deleted skins/${key}`);
  }
  console.log('\nDone.');
}

main().catch(console.error);
