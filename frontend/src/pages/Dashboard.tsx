import React, { useEffect, useState, useRef } from "react";
import { usePrivy } from "@privy-io/react-auth";
import { useNavigate } from "react-router-dom";
import { FullScreenLoader } from "../components/ui/fullscreen-loader";
import { ThreeScene } from "../components/ThreeScene";
import "./Dashboard.css";

// --- FIREBASE REALTIME DATABASE IMPORTS ---
import { initializeApp } from "firebase/app";
import { 
  getDatabase, 
  ref, 
  set, 
  get, 
  update
} from "firebase/database";

// --- CONFIGURATION ---
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

// Initialize Realtime Database
const app = initializeApp(firebaseConfig);
const db = getDatabase(app);

// --- HELPER FUNCTIONS ---

function getUsernameFromPrivy(user: any): string {
  const twitter = user.linkedAccounts?.find((acc: any) => acc.type === "twitter_oauth");
  const wallet = user.linkedAccounts?.find((acc: any) => acc.type === "wallet");
  return twitter?.username || wallet?.address || "Anon";
}

async function saveUserToFirebase(user: any, db: any) {
  if (!user?.id) return;

  const username = getUsernameFromPrivy(user);
  
  // Extract specific fields from Linked Accounts
  const twitter = user.linkedAccounts?.find((acc: any) => acc.type === "twitter_oauth");
  const wallet = user.linkedAccounts?.find((acc: any) => acc.type === "wallet");

  // Point to "users/{username}"
  const userRef = ref(db, `users/${username}`);

  try {
    const snapshot = await get(userRef);

    // Common data to update regardless if new or old
    const updates = {
      lastLogin: new Date().toISOString(),
      latestVerifiedAt: twitter?.latestVerifiedAt || wallet?.latestVerifiedAt || new Date().toISOString(),
      profilePictureUrl: twitter?.profilePictureUrl || "https://abs.twimg.com/sticky/default_profile_images/default_profile_400x400.png"
    };

    if (snapshot.exists()) {
      // ✅ User exists: Update metadata ONLY (Do not overwrite projects or won count)
      await update(userRef, updates);
      console.log("✅ User metadata updated.");
    } else {
      // 🆕 New User: Write FULL data
      const newUserPayload = {
        privyId: user.id,
        username: username,
        wallet: wallet?.address || null,
        firstVerifiedAt: twitter?.firstVerifiedAt || wallet?.firstVerifiedAt || new Date().toISOString(),
        won: 0,
        projects: [], // Initialize empty array
        ...updates
      };

      await set(userRef, newUserPayload);
      console.log("🆕 New user created:", newUserPayload);
    }
  } catch (err) {
    console.error("🔥 Error saving user:", err);
  }
}

// ✅ NEW LOGIC: Add Match Name to User's "projects" array
async function updateUserProjects(username: string, matchSponsorName: string, db: any) {
  try {
    const userRef = ref(db, `users/${username}`);
    const snapshot = await get(userRef);

    if (snapshot.exists()) {
      const userData = snapshot.val();
      const currentProjects = userData.projects || [];

      // Check if this project is already in the list
      if (!currentProjects.includes(matchSponsorName)) {
        const updatedProjects = [...currentProjects, matchSponsorName];
        
        await update(userRef, {
          projects: updatedProjects
        });
        console.log(`✅ Added "${matchSponsorName}" to ${username}'s projects.`);
      } else {
        console.log(`ℹ️ User already has "${matchSponsorName}" in projects.`);
      }
    }
  } catch (err) {
    console.error("🔥 Error updating projects:", err);
  }
}

// --- TYPES ---
type Twitter = {
  username?: string;
  profile_picture_url?: string;
};

type Wallet = {
  address: string;
};

type Match = {
  id: number;
  sponsor: string;
  reward: string;
  status: "upcoming" | "live" | "completed";
  time: string;
  image: string;
  description: string;
  url: string;
};

// --- MAIN COMPONENT ---
export default function Dashboard() {
  const { ready, authenticated, user, logout } = usePrivy();
  const navigate = useNavigate();

  const [earned, setEarned] = useState<number>(0);
  const [selectedMatch, setSelectedMatch] = useState<number | null>(null);
  const [tab, setTab] = useState<"events" | "results">("events");
  const [filter, setFilter] = useState<"upcoming" | "live" | "completed">("upcoming");

  const [playButtonState, setPlayButtonState] = useState<"idle" | "counting">("idle");
  const [elapsedTime, setElapsedTime] = useState(0);

  const carouselRef = useRef<HTMLDivElement>(null);
  const isManuallyScrolling = useRef<boolean>(false);
  const scrollTimeout = useRef<NodeJS.Timeout | null>(null);
  const intervalRef = useRef<NodeJS.Timeout | null>(null);
  const navigationTimeoutRef = useRef<NodeJS.Timeout | null>(null);

  // 1. Save User to Realtime DB on Load
  useEffect(() => {
    if (authenticated && user) {
      saveUserToFirebase(user, db);
    }
  }, [authenticated, user]);

  // 2. Animate Earned Counter
  useEffect(() => {
    let start = 0;
    const end = 30000;
    const interval = setInterval(() => {
      start += 400;
      if (start >= end) {
        start = end;
        clearInterval(interval);
      }
      setEarned(start);
    }, 20);
    return () => clearInterval(interval);
  }, []);

  // 3. Cleanup
  useEffect(() => {
    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current);
      if (navigationTimeoutRef.current) clearTimeout(navigationTimeoutRef.current);
    };
  }, []);

  // 4. Auto-scroll
  useEffect(() => {
    if (!selectedMatch) return;
    window.scrollTo({
      top: document.body.scrollHeight,
      behavior: "smooth",
    });
  }, [selectedMatch]);

  // 5. Play Button Logic
  const handlePlayClick = async () => {
    if (!selectedMatch) return;

    // --- DB ACTION: ADD PROJECT TO USER ---
    if (user) {
      const match = matches.find(m => m.id === selectedMatch);
      if (match) {
        const username = getUsernameFromPrivy(user);
        // Add sponsor name to 'projects' array
        await updateUserProjects(username, match.sponsor, db);
      }
    }

    window.scrollTo({ top: 0, behavior: "smooth" });

    if (playButtonState === "idle") {
      setPlayButtonState("counting");
      setElapsedTime(0);
      intervalRef.current = setInterval(() => {
        setElapsedTime((prev) => prev + 0.1);
      }, 100);

      navigationTimeoutRef.current = setTimeout(() => {
        if (intervalRef.current) clearInterval(intervalRef.current);
        setPlayButtonState("idle");
        navigate("/play");
      }, 15000);
    } else {
      if (intervalRef.current) clearInterval(intervalRef.current);
      if (navigationTimeoutRef.current) clearTimeout(navigationTimeoutRef.current);
      setPlayButtonState("idle");
    }
  };

  if (!ready) return <FullScreenLoader />;
  if (!authenticated || !user) return null;

  const twitter = user.linkedAccounts?.find((acc) => acc.type === "twitter_oauth") as Twitter | undefined;
  const wallets = (user.linkedAccounts?.filter((acc) => acc.type === "wallet") || []) as Wallet[];

  // --- DATA: MATCHES ---
  const matches: Match[] = [
    {
      id: 1,
      sponsor: "Monad",
      reward: "10 MON",
      status: "upcoming",
      time: "Upcoming",
      image: "https://pbs.twimg.com/profile_images/1861739634428174336/26FzLLyr.jpg",
      description: "Monad is a high-performance EVM-compatible Layer 1 blockchain with 10,000 TPS.",
      url: "https://x.com/monad_xyz"
    },
    {
      id: 17,
      sponsor: "LootGO",
      reward: "50,000 WONs",
      status: "live",
      time: "Live Now",
      image: "https://pbs.twimg.com/profile_images/1947490514921488384/TLSJg7Z5.jpg",
      description: "Discover → Play → Earn. The ultimate on-chain discovery app.",
      url: "https://x.com/lootgo_official"
    },
    // ... Other matches ...
    {
      id: 16,
      sponsor: "RareBet Sports",
      reward: "55,000 WONs",
      status: "completed",
      time: "Completed",
      image: "https://pbs.twimg.com/profile_images/1802788848956506112/KJnlcaQj.jpg",
      description: "Elite on-chain sports betting.",
      url: "https://x.com/RareBetSports"
    }
  ];

  const filteredMatches = matches.filter((m) => m.status === filter);

  const updateSelectedCard = () => {
    if (isManuallyScrolling.current) return;
    const carousel = carouselRef.current;
    if (!carousel) return;

    const cards = Array.from(carousel.children) as HTMLElement[];
    const centerX = carousel.getBoundingClientRect().left + carousel.offsetWidth / 2;
    let closest: HTMLElement | null = null;
    let min = Infinity;

    cards.forEach((card) => {
      const dist = Math.abs(card.getBoundingClientRect().left + card.offsetWidth / 2 - centerX);
      if (dist < min) {
        min = dist;
        closest = card;
      }
    });

    if (closest && closest.dataset.id) {
      setSelectedMatch(Number(closest.dataset.id));
    }
  };

  useEffect(() => {
    const el = carouselRef.current;
    if (!el) return;
    const handleScroll = () => {
      if (scrollTimeout.current) clearTimeout(scrollTimeout.current);
      scrollTimeout.current = setTimeout(updateSelectedCard, 140);
    };
    el.addEventListener("scroll", handleScroll);
    updateSelectedCard();
    return () => el.removeEventListener("scroll", handleScroll);
  }, [filter]);

  return (
    <div className="dashboard-wrapper">
      <div className="left-3d-section">
        <ThreeScene twitter={twitter} wallets={wallets} earned={earned} onLogout={logout} />
      </div>

      <div className="right-info-section">
        <div className="tabs">
          <div className={tab === "events" ? "tab active" : "tab"} onClick={() => setTab("events")}>
            Events
          </div>
          <div className={tab === "results" ? "tab active" : "tab"} onClick={() => setTab("results")}>
            Results
          </div>
        </div>

        <div className="filters">
          <span className={filter === "upcoming" ? "filter active" : "filter"} onClick={() => setFilter("upcoming")}>
            Upcoming
          </span>
          <span className={filter === "live" ? "filter active" : "filter"} onClick={() => setFilter("live")}>
            Live
          </span>
          <span className={filter === "completed" ? "filter active" : "filter"} onClick={() => setFilter("completed")}>
            Completed
          </span>
        </div>

        <div className="matches-wrapper">
          <div className="matches-carousel" ref={carouselRef}>
            {filteredMatches.map((m) => (
              <div
                key={m.id}
                data-id={m.id}
                className={`match-card ${selectedMatch === m.id ? "selected" : ""}`}
                style={{ backgroundImage: `url(${m.image})` }}
                onClick={(e) => {
                  const card = e.currentTarget;
                  const carousel = carouselRef.current;
                  if (!carousel) return;
                  const target = card.offsetLeft - carousel.offsetWidth / 2 + card.offsetWidth / 2;
                  carousel.scrollTo({ left: target, behavior: "smooth" });
                  isManuallyScrolling.current = true;
                  setSelectedMatch(m.id);
                  setTimeout(() => (isManuallyScrolling.current = false), 600);
                }}
              >
                <div className="match-card-overlay">
                  <h3 className="match-sponsor">{m.sponsor}</h3>
                  <p className="match-reward">{m.reward}</p>
                  <p className="match-time">{m.time}</p>
                </div>
              </div>
            ))}
          </div>
        </div>

        <div className="match-details">
          {selectedMatch ? (
            (() => {
              const match = matches.find((m) => m.id === selectedMatch);
              if (!match) return null;

              return (
                <div className="match-details-box">
                  <h2 className="match-details-title">{match.sponsor}</h2>
                  <p className="match-details-description">{match.description}</p>
                  <a href={match.url} target="_blank" rel="noopener noreferrer" className="match-details-twitter">
                    Visit Sponsor ↗
                  </a>
                </div>
              );
            })()
          ) : (
            <div className="match-details-empty">
              <p>Select a match to view details</p>
            </div>
          )}
        </div>
      </div>

      <button
        className={`play-fixed ${selectedMatch ? "active" : "disabled"} ${
          playButtonState === "counting" ? "counting" : ""
        }`}
        onClick={handlePlayClick}
        disabled={!selectedMatch}
      >
        {playButtonState === "counting" ? <span>{elapsedTime.toFixed(1)}s Cancel</span> : <span>PLAY</span>}
      </button>
    </div>
  );
}