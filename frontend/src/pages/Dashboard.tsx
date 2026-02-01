import React, { useEffect, useState, useRef } from "react";
import { useNavigate } from "react-router-dom";
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

// Mock user for now (without Privy)
const mockUser = {
  id: "guest-user",
  username: "Guest",
};

function getUsername(): string {
  return mockUser.username;
}

async function saveUserToFirebase(username: string, db: any) {
  const userRef = ref(db, `users/${username}`);

  try {
    const snapshot = await get(userRef);

    const updates = {
      lastLogin: new Date().toISOString(),
    };

    if (snapshot.exists()) {
      await update(userRef, updates);
      console.log("✅ User metadata updated.");
    } else {
      const newUserPayload = {
        username: username,
        won: 0,
        projects: [],
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
  const navigate = useNavigate();

  const [earned, setEarned] = useState<number>(0);
  const [selectedMatch, setSelectedMatch] = useState<number | null>(null);
  const [tab, setTab] = useState<"events" | "rewards" | "store">("events");
  const [filter, setFilter] = useState<"upcoming" | "live" | "completed">("live");

  const [playButtonState, setPlayButtonState] = useState<"idle" | "counting">("idle");
  const [elapsedTime, setElapsedTime] = useState(0);

  const carouselRef = useRef<HTMLDivElement>(null);
  const isManuallyScrolling = useRef<boolean>(false);
  const scrollTimeout = useRef<NodeJS.Timeout | null>(null);
  const intervalRef = useRef<NodeJS.Timeout | null>(null);
  const navigationTimeoutRef = useRef<NodeJS.Timeout | null>(null);

  // Mock data for display (without Privy)
  const twitter: Twitter | undefined = undefined;
  const wallets: Wallet[] = [];

  // 1. Save User to Realtime DB on Load
  useEffect(() => {
    const username = getUsername();
    saveUserToFirebase(username, db);
  }, []);

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
    const match = matches.find(m => m.id === selectedMatch);
    if (match) {
      const username = getUsername();
      // Add sponsor name to 'projects' array
      await updateUserProjects(username, match.sponsor, db);
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
      }, 3000);
    } else {
      if (intervalRef.current) clearInterval(intervalRef.current);
      if (navigationTimeoutRef.current) clearTimeout(navigationTimeoutRef.current);
      setPlayButtonState("idle");
    }
  };

  const handleLogout = () => {
    navigate("/");
  };

  // --- DATA: MATCHES ---
  // MATCHES 
  const matches: Match[] = [
    {
      id: 1,
      sponsor: "Monad Mainnet",
      reward: "10 MON",
      status: "live",
      time: "Live Now",
      image: "https://pbs.twimg.com/profile_images/1861739634428174336/26FzLLyr.jpg",
      description: "Monad is a high-performance EVM-compatible Layer 1 blockchain with 10,000 TPS, 1-second block times, and sub-cent fees.",
      url: "https://x.com/monad_xyz"
    },
    {
      id: 18,
      sponsor: "Monad Testnet",
      reward: "Testnet MON",
      status: "completed",
      time: "Completed",
      image: "https://pbs.twimg.com/profile_images/1861739634428174336/26FzLLyr.jpg",
      description: "The early testing environment for Monad. Experience high-performance consensus and execution before Mainnet launch.",
      url: "https://x.com/monad_xyz"
    },
    {
      id: 17,
      sponsor: "LootGO",
      reward: "50,000 WONs",
      status: "upcoming",
      time: "Upcoming",
      image: "https://pbs.twimg.com/profile_images/1947490514921488384/TLSJg7Z5.jpg",
      description: "Discover → Play → Earn. The ultimate on-chain discovery app. Turn every interaction into real rewards.",
      url: "https://x.com/lootgo_official"
    },
    {
      id: 2,
      sponsor: "Nad.fun",
      reward: "22,000 WONs",
      status: "upcoming",
      time: "Upcoming",
      image: "https://pbs.twimg.com/profile_images/1827607782356619264/Owr-840k.jpg",
      description: "The most degenerate memecoin arena on Monad. Launch, pump, snipe, rug — pure chaos, zero mercy.",
      url: "https://x.com/naddotfun"
    },
    {
      id: 3,
      sponsor: "Kizzy Mobile",
      reward: "14,500 WONs",
      status: "upcoming",
      time: "Upcoming",
      image: "https://pbs.twimg.com/profile_images/2000251466468978688/Q7hvNgR3.jpg",
      description: "Web3 in your pocket. The fastest mobile gateway to on-chain games, rewards, and social quests.",
      url: "https://x.com/kizzymobile"
    },
    {
      id: 4,
      sponsor: "Kuru Exchange",
      reward: "5,000 WONs",
      status: "upcoming",
      time: "Upcoming",
      image: "https://pbs.twimg.com/profile_images/1950962142917619714/R7Cj_qk7.jpg",
      description: "Lightning-fast perpetuals on Monad. Up to 100x leverage, deep liquidity, zero gas drama.",
      url: "https://x.com/KuruExchange"
    },
    {
      id: 5,
      sponsor: "Lumiterra",
      reward: "10,000 WONs",
      status: "upcoming",
      time: "Upcoming",
      image: "https://pbs.twimg.com/profile_images/1667436896480563200/8YPmbLbv.png",
      description: "An open-world MMORPG where you fight, farm, craft, and own your destiny across infinite lands.",
      url: "https://x.com/LumiterraGame"
    },
    {
      id: 6,
      sponsor: "Levr Bet",
      reward: "7,500 WONs",
      status: "upcoming",
      time: "Upcoming",
      image: "https://pbs.twimg.com/profile_images/1836024387042004992/YKdDMkOG.jpg",
      description: "Prediction markets & sports betting on-chain. Bet with leverage, earn with accuracy.",
      url: "https://x.com/Levr_Bet"
    },
    {
      id: 7,
      sponsor: "Drake Exchange",
      reward: "25,000 WONs",
      status: "upcoming",
      time: "Upcoming",
      image: "https://pbs.twimg.com/profile_images/1974759389354491904/2vcC-dd4.jpg",
      description: "Next-gen perpetuals & spot trading on Monad. Fast. Cheap. Ruthless execution.",
      url: "https://x.com/DrakeExchange"
    },
    {
      id: 8,
      sponsor: "Omnia Explorer",
      reward: "13,000 WONs",
      status: "upcoming",
      time: "Upcoming",
      image: "https://pbs.twimg.com/profile_images/1796709016808394752/C91LWB9H.jpg",
      description: "The most powerful Monad block explorer. Real-time analytics, mempool sniper, gamified quests.",
      url: "https://x.com/ExploreOmnia"
    },
    {
      id: 9,
      sponsor: "SeerTrade",
      reward: "9,800 WONs",
      status: "upcoming",
      time: "Upcoming",
      image: "https://pbs.twimg.com/profile_images/1992956835922587649/6s2RZ9xf.jpg",
      description: "Advanced trading terminal for Monad. Sniping, copy-trading, AI signals, limit orders that actually fill.",
      url: "https://x.com/seertrade"
    },
    {
      id: 10,
      sponsor: "Monday Trade",
      reward: "6,400 WONs",
      status: "upcoming",
      time: "Upcoming",
      image: "https://pbs.twimg.com/profile_images/1973421191202209797/qRXSiR5e.jpg",
      description: "Set it and forget it. Automated DCA, grid, and martingale bots for Monad degens.",
      url: "https://x.com/MondayTrade_"
    },
    {
      id: 11,
      sponsor: "Symphony",
      reward: "18,200 WONs",
      status: "upcoming",
      time: "Upcoming",
      image: "https://pbs.twimg.com/profile_images/1893386930605211648/-APwnLNM.jpg",
      description: "Social trading on Monad. Follow top traders, copy flows, split profits, climb the leaderboard.",
      url: "https://x.com/symphonyio"
    },
    {
      id: 12,
      sponsor: "Kinetik AI",
      reward: "33,000 WONs",
      status: "upcoming",
      time: "Upcoming",
      image: "https://pbs.twimg.com/profile_images/1947607859702673408/hpZ89aya.jpg",
      description: "AI-powered on-chain movement battles. Run, jump, dodge — turn your activity into crypto.",
      url: "https://x.com/KINETK_AI"
    },
    {
      id: 13,
      sponsor: "TeleMafia",
      reward: "20,000 WONs",
      status: "upcoming",
      time: "Upcoming",
      image: "https://pbs.twimg.com/profile_images/1967887075316994050/STzEqU1y.jpg",
      description: "The ultimate Telegram mafia game. Lie, betray, vote out — last don standing wins the pot.",
      url: "https://x.com/TeleMafia"
    },
    {
      id: 14,
      sponsor: "Fluffle World",
      reward: "42,000 WONs",
      status: "upcoming",
      time: "Upcoming",
      image: "https://pbs.twimg.com/profile_images/1972672305336569856/JLjBcagi.jpg",
      description: "Home of the cutest (and most savage) bunnies on Monad. Collect, breed, battle, fluff.",
      url: "https://x.com/fluffleworld"
    },
    {
      id: 15,
      sponsor: "BRO.fun",
      reward: "18,000 WONs",
      status: "upcoming",
      time: "Upcoming",
      image: "https://pbs.twimg.com/profile_images/1983519855279042560/ntgzrOaU.jpg",
      description: "For the bros, by the bros. Gaming, memes, gains — pure brotherhood on Monad.",
      url: "https://x.com/bro_dot_fun"
    },
    {
      id: 16,
      sponsor: "RareBet Sports",
      reward: "55,000 WONs",
      status: "upcoming",
      time: "Upcoming",
      image: "https://pbs.twimg.com/profile_images/1802788848956506112/KJnlcaQj.jpg",
      description: "Elite on-chain sports betting. Parlay everything, leverage your takes, get paid instantly.",
      url: "https://x.com/RareBetSports"
    }
  ];


  const filteredMatches = matches.filter((m) => m.status === filter);

  // Add this here
  const selectedMatchData = matches.find((m) => m.id === selectedMatch);
  const isLive = selectedMatchData?.status === "live"

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
        <ThreeScene twitter={twitter} wallets={wallets} earned={earned} onLogout={handleLogout} />
      </div>

      <div className="right-info-section">
        <div className="tabs">
          <div className={tab === "events" ? "tab active" : "tab"} onClick={() => setTab("events")}>
            Events
          </div>
          <div className={tab === "rewards" ? "tab active" : "tab"} onClick={() => setTab("rewards")}>
            Rewards
          </div>
          <div className={tab === "store" ? "tab active" : "tab"} onClick={() => setTab("store")}>
            Store
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
                className={`match-card ${selectedMatch === m.id ? "selected" : ""} ${m.status !== "live" ? "grayscale-card" : ""}`}
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
        className={`play-fixed ${isLive ? "active" : "disabled"} ${playButtonState === "counting" ? "counting" : ""
          }`}
        onClick={isLive ? handlePlayClick : undefined}
        disabled={!isLive}
        style={{
          opacity: isLive ? 1 : 0.5,
          pointerEvents: isLive ? "auto" : "none"
        }}
      >
        {playButtonState === "counting" ? (
          <span>{elapsedTime.toFixed(1)}s Cancel</span>
        ) : (
          <span>PLAY</span>
        )}
      </button>



    </div>
  );
}