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
  update, 
  runTransaction 
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

// Helper to determine the Username consistently
function getUsernameFromPrivy(user: any): string {
  const twitter = user.linkedAccounts?.find((acc: any) => acc.type === "twitter_oauth");
  const wallet = user.linkedAccounts?.find((acc: any) => acc.type === "wallet");
  
  // Use Twitter username OR Wallet address OR "Anon"
  return twitter?.username || wallet?.address || "Anon";
}

async function saveUserToFirebase(user: any, db: any) {
  if (!user?.id) return;

  // 1. Get Username and Image from Privy
  const targetUsername = getUsernameFromPrivy(user);
  const twitter = user.linkedAccounts?.find((acc: any) => acc.type === "twitter_oauth");
  const wallet = user.linkedAccounts?.find((acc: any) => acc.type === "wallet");
  
  // Use Privy Image -> Fallback to default placeholder (Not random person)
  const targetPfp = twitter?.profile_picture_url || "https://abs.twimg.com/sticky/default_profile_images/default_profile_400x400.png";

  // 2. Point to "users/{USERNAME}" instead of Privy ID
  const userRef = ref(db, `users/${targetUsername}`);

  try {
    const snapshot = await get(userRef);

    if (snapshot.exists()) {
      // User exists: just update last login and ensure PFP is current
      await update(userRef, {
        lastLogin: new Date().toISOString(),
        pfp: targetPfp // Update PFP in case they changed it on Twitter
      });
      console.log("✅ User exists, updated login & PFP.");
    } else {
      // User is NEW: Create with your EXACT format
      const newUserPayload = {
        username: targetUsername,
        won: 0,
        projects: [],
        pfp: targetPfp,
        wallet: wallet?.address || null,
        privyId: user.id, // Keep reference to Privy ID inside data just in case
        lastLogin: new Date().toISOString()
      };

      await set(userRef, newUserPayload);
      console.log("🆕 New user created:", newUserPayload);
    }
  } catch (err) {
    console.error("🔥 Error saving user:", err);
  }
}

async function joinMatch(username: string, matchId: number, db: any) {
  try {
    // 1. Log the join using USERNAME (consistent with users table)
    const joinRef = ref(db, `match_joins/${username}_${matchId}`);
    
    await set(joinRef, {
      userId: username, // Storing username as userId for consistency
      matchId,
      joinedAt: new Date().toISOString()
    });

    // 2. Increment player count
    const countRef = ref(db, `leaderboard/${matchId}/activePlayers`);
    await runTransaction(countRef, (currentValue) => {
      return (currentValue || 0) + 1;
    });

    console.log(`✅ User ${username} joined match ${matchId}`);

  } catch (err) {
    console.error("🔥 Error recording match join:", err);
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

    // --- SEND JOIN SIGNAL TO DB USING USERNAME ---
    if (user) {
      const currentUsername = getUsernameFromPrivy(user);
      await joinMatch(currentUsername, selectedMatch, db);
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
    // ... Add remaining matches here ...
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