// @ts-nocheck
import { useEffect, useRef, useState } from "react";
import { usePrivy } from "@privy-io/react-auth";
import { useNavigate } from "react-router-dom";
import { ethers } from "ethers";
import { FullScreenLoader } from "../components/ui/fullscreen-loader";
import { ThreeScene } from "../components/ThreeScene";
import "./Dashboard.css";
import {
  fetchMatchesFromFirebase,
  getUsernameFromPrivy,
  saveUserToFirebase,
  updateUserProjects,
  fetchUserRewards,
  recordSponsorDailyUniquePlayer
} from "./firebaseClient";
import { trackMatchJoined } from "../lib/analyticsClient";
import { staticMatches } from "./staticMatches.js";

type Twitter = {
  username?: string;
  profilePictureUrl?: string;
  name?: string;
};

type Wallet = {
  address: string;
};

type Match = {
  id: number;
  matchId: string;
  sponsor: string;
  prize: string;
  prizeAmount: number;
  prizeToken: string;
  status: "upcoming" | "live" | "completed";
  time: string;
  date: string;
  image: string;
  description: string;
  url: string;
  createdAt?: string;
  createdByWallet?: string;
  depositTxHash?: string;
  startTime?: number; // Unix timestamp in seconds
  settleTxHash?: string;
};

type RewardItem = {
  id: string;
  username: string;
  amount: string;
  source: string;
  category: "earned" | "gifted";
  date: string;
};

type SkinConfig = {
  attachmentShape?: "box" | "cone" | "sphere" | "cylinder";
  color?: string;
  cheekColor?: string;
};

type StoreItem = {
  id: string;
  name: string;
  price: string;
  image: string;
  category: "skins" | "costumes" | "bundles";
  description: string;
  skinConfig?: SkinConfig;
};

const dummyStore: StoreItem[] = [
  { 
    id: "s0", 
    name: "Default Skin", 
    price: "0 MON", 
    image: "/logo.jpg", 
    category: "skins", 
    description: "The classic Nad look.",
    skinConfig: { color: "#ff2496", cheekColor: "#ff40bf" }
  },
  { 
    id: "s1", 
    name: "Gladiator Skin", 
    price: "20 MON", 
    image: "/logo.jpg", 
    category: "skins", 
    description: "Battle-hardened armor for your character.",
    skinConfig: { attachmentShape: "box", color: "#ff4444" }
  },
  { 
    id: "s2", 
    name: "Ninja Costume", 
    price: "35 MON", 
    image: "/logo.jpg", 
    category: "costumes", 
    description: "Move like a shadow.",
    skinConfig: { attachmentShape: "cylinder", color: "#222222" }
  },
  { 
    id: "s3", 
    name: "Golden Nad Bundle", 
    price: "150 MON", 
    image: "/logo.jpg", 
    category: "bundles", 
    description: "The elite choice.",
    skinConfig: { attachmentShape: "sphere", color: "#ffd700" }
  },
  { 
    id: "s4", 
    name: "Cyberpunk Skin", 
    price: "60 MON", 
    image: "/logo.jpg", 
    category: "skins", 
    description: "Neon-soaked aesthetic.",
    skinConfig: { attachmentShape: "box", color: "#b026ff" }
  },
  { 
    id: "s5", 
    name: "Witch Costume", 
    price: "40 MON", 
    image: "/logo.jpg", 
    category: "costumes", 
    description: "Spooky and mysterious.",
    skinConfig: { attachmentShape: "cone", color: "#4b0082" }
  },
  { 
    id: "s6", 
    name: "Starter Bundle", 
    price: "45 MON", 
    image: "/logo.jpg", 
    category: "bundles", 
    description: "Essential gear.",
    skinConfig: { attachmentShape: "box", color: "#44ff44" }
  },
];

const dummyOwnedItems: string[] = ["s0", "s1", "s5"]; // IDs matching dummyStore

export default function Dashboard() {
  const { ready, authenticated, user, logout } = usePrivy();
  const navigate = useNavigate();

  const [earned, setEarned] = useState<number>(0);
  const [selectedMatch, setSelectedMatch] = useState<string | null>(null);
  const [selectedReward, setSelectedReward] = useState<string | null>(null);
  const [selectedStore, setSelectedStore] = useState<string | null>(null);
  const [equippedSkin, setEquippedSkin] = useState<StoreItem | null>(dummyStore[0]);

  const [tab, setTab] = useState<"events" | "rewards" | "store">("events");
  const [filter, setFilter] = useState<"upcoming" | "live" | "completed">("live");

  const [matches, setMatches] = useState<Match[]>(staticMatches as Match[]);
  const [rewards, setRewards] = useState<RewardItem[]>([]);
  const [playButtonState, setPlayButtonState] = useState<"idle" | "counting">("idle");
  const [elapsedTime, setElapsedTime] = useState(0);
  const [nowMs, setNowMs] = useState(Date.now());

  const carouselRef = useRef<HTMLDivElement>(null);
  const isManuallyScrolling = useRef<boolean>(false);
  const scrollTimeout = useRef<NodeJS.Timeout | null>(null);
  const intervalRef = useRef<NodeJS.Timeout | null>(null);
  const navigationTimeoutRef = useRef<NodeJS.Timeout | null>(null);

  useEffect(() => {
    if (authenticated && user) {
      saveUserToFirebase(user).catch((error: any) => {
        console.error("Failed to save user", error);
      });
    }
  }, [authenticated, user]);

  // Fetch actual MON balance
  useEffect(() => {
    if (!authenticated || !user) return;

    const fetchBalance = async () => {
      try {
        const ethWallet = user.linkedAccounts?.find(
          (acc) => acc.type === "wallet" && acc.chainType === "ethereum"
        );
        if (ethWallet && "address" in ethWallet && ethWallet.address) {
          const provider = new ethers.JsonRpcProvider("https://rpc.monad.xyz");
          const balance = await provider.getBalance(ethWallet.address);
          const formatted = ethers.formatEther(balance);
          // Trim to 4 decimal places for display
          setEarned(parseFloat(formatted));
        }
      } catch (error: any) {
        console.error("Failed to fetch MON balance:", error);
      }
    };

    fetchBalance();
    // Refresh balance every 30 seconds
    const interval = setInterval(fetchBalance, 30000);
    return () => clearInterval(interval);
  }, [authenticated, user]);

  useEffect(() => {
    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current);
      if (navigationTimeoutRef.current) clearTimeout(navigationTimeoutRef.current);
    };
  }, []);

  useEffect(() => {
    const ticker = setInterval(() => {
      setNowMs(Date.now());
    }, 5000);
    return () => clearInterval(ticker);
  }, []);

  useEffect(() => {
    const mergeMatches = (liveMatches: Match[]) => {
      const map = new Map<string, Match>();
      [...staticMatches, ...liveMatches].forEach((match) => {
        map.set(match.matchId, match);
      });
      return Array.from(map.values());
    };

    const loadMatches = async () => {
      try {
        const firebaseMatches = await fetchMatchesFromFirebase();
        if (firebaseMatches.length > 0) {
          setMatches(mergeMatches(firebaseMatches as Match[]));
        }
      } catch (error: any) {
        console.error("Failed to fetch Firebase matches", error);
      }
    };

    loadMatches();
  }, []);

  useEffect(() => {
    const loadRewards = async () => {
      if (!authenticated || !user) return;
      try {
        const username = getUsernameFromPrivy(user);
        const liveRewards = await fetchUserRewards(username);
        setRewards(liveRewards as RewardItem[]);
      } catch (error: any) {
        console.error("Failed to fetch rewards", error);
      }
    };

    loadRewards();
  }, [authenticated, user]);

  const handlePlayClick = async () => {
    if (!selectedMatch || !user) return;

    const match = matches.find((item) => item.matchId === selectedMatch);
    if (match) {
      const username = getUsernameFromPrivy(user);
      await updateUserProjects(username, match.sponsor);
      await recordSponsorDailyUniquePlayer({ sponsor: match.sponsor, username });
      trackMatchJoined({
        userId: user.id,
        matchId: match.matchId,
        sponsorId: match.sponsor,
        metadata: { username }
      });
    }

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

  const formatLocalTime = (timestamp: number | undefined) => {
    if (!timestamp) return "";
    return new Intl.DateTimeFormat("default", {
      hour: "2-digit",
      minute: "2-digit",
      hour12: false
    }).format(new Date(timestamp * 1000));
  };

  if (!ready) return <FullScreenLoader />;
  if (!authenticated || !user) return null;

  const twitterAcc = user.linkedAccounts?.find((acc) => acc.type === "twitter_oauth");
  const twitterData: Twitter | undefined = twitterAcc
    ? {
      username: twitterAcc.username ?? undefined,
      profilePictureUrl: twitterAcc.profilePictureUrl ?? undefined,
      name: twitterAcc.name || twitterAcc.username || undefined
    }
    : undefined;

  // Filter for ONLY the Ethereum wallet (Monad)
  const wallets = (user.linkedAccounts?.filter(
    (acc) => acc.type === "wallet" && acc.chainType === "ethereum"
  ) || []) as Wallet[];

  const filteredMatches = matches.filter((match) => {
    if (filter === "completed") {
      return match.status === "completed" || match.status === "settled";
    }
    return match.status === filter;
  });
  const selectedMatchData = matches.find((match) => match.matchId === selectedMatch) || null;
  const isLive = selectedMatchData?.status === "live";
  const isStartTimeReached = selectedMatchData?.startTime
    ? nowMs >= selectedMatchData.startTime * 1000
    : true;
  const canPlay = isLive && isStartTimeReached;

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

    if (closest && (closest as HTMLElement).dataset.id) {
      setSelectedMatch(String((closest as HTMLElement).dataset.id));
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
  }, [filter, filteredMatches.length]);

  return (
    <div className="dashboard-wrapper">
      <div className="left-3d-section">
        <ThreeScene
          twitter={twitterData}
          wallets={wallets}
          earned={earned}
          username={getUsernameFromPrivy(user)}
          onLogout={logout}
          equippedSkin={equippedSkin}
        />
      </div>

      <div className="right-info-section">
        <div className="tabs">
          <div className={tab === "events" ? "tab active" : "tab"} onClick={() => { setTab("events"); setSelectedMatch(null); setSelectedReward(null); setSelectedStore(null); }}>
            Events
          </div>
          <div className={tab === "rewards" ? "tab active" : "tab"} onClick={() => { setTab("rewards"); setSelectedMatch(null); setSelectedReward(null); setSelectedStore(null); }}>
            Rewards
          </div>
          <div className={tab === "store" ? "tab active" : "tab"} onClick={() => { setTab("store"); setSelectedMatch(null); setSelectedReward(null); setSelectedStore(null); }}>
            Store
          </div>
        </div>

        <div className="filters">
          {tab === "events" && (
            <>
              <span className={filter === "upcoming" ? "filter active" : "filter"} onClick={() => { setFilter("upcoming"); setSelectedMatch(null); }}>Upcoming</span>
              <span className={filter === "live" ? "filter active" : "filter"} onClick={() => { setFilter("live"); setSelectedMatch(null); }}>Live</span>
              <span className={filter === "completed" ? "filter active" : "filter"} onClick={() => { setFilter("completed"); setSelectedMatch(null); }}>Completed</span>
            </>
          )}
        </div>

        <div className="tab-content-scroll">
          <div className="matches-wrapper">
          {tab === "events" && (
            <div className="matches-carousel" ref={carouselRef}>
              {filteredMatches.map((match) => (
                <div
                  key={match.matchId}
                  data-id={match.matchId}
                  className={`match-card ${selectedMatch === match.matchId ? "selected" : ""} ${match.status !== "live" ? "grayscale-card" : ""}`}
                  style={{ backgroundImage: `url(${match.image})` }}
                  onClick={(event) => {
                    const card = event.currentTarget;
                    const carousel = carouselRef.current;
                    if (!carousel) return;
                    const target = card.offsetLeft - carousel.offsetWidth / 2 + card.offsetWidth / 2;
                    carousel.scrollTo({ left: target, behavior: "smooth" });
                    isManuallyScrolling.current = true;
                    setSelectedMatch(match.matchId);
                    setTimeout(() => {
                      isManuallyScrolling.current = false;
                    }, 600);
                  }}
                >
                  {selectedMatch === match.matchId ? (
                    <div className="match-card-overlay selected-overlay">

                      <div className="match-details-inner">
                        <p className="match-desc">{match.description}</p>
                        <p className="match-info">Prize: {match.prize}</p>
                        <p className="match-info">Time: {match.startTime ? `${formatLocalTime(match.startTime)}` : match.time}</p>
                      </div>
                    </div>
                  ) : (
                    <div className="match-card-overlay">
                      <h3 className="match-sponsor">{match.sponsor}</h3>
                      <p className="match-reward">{match.prize}</p>
                      <p className="match-time">
                        {match.status === "upcoming" && match.startTime
                          ? `${formatLocalTime(match.startTime)} (Local)`
                          : match.time}
                      </p>
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}

          {tab === "rewards" && (
            <div className="reward-list">
              {rewards.length === 0 ? (
                <div className="reward-empty">
                  No rewards yet. Join a match to win some.
                </div>
              ) : (
                rewards
                  .map((reward) => (
                    <div
                      key={reward.id}
                      className={`reward-item ${selectedReward === reward.id ? "selected" : ""}`}
                      onClick={() => setSelectedReward(reward.id)}
                    >
                      <div className="reward-item-icon">🏆</div>
                      <div className="reward-item-text">
                        <div className="reward-item-header">
                           <strong>{reward.username}</strong>
                           <span className={`item-badge badge-${reward.category}`}>{reward.category}</span>
                        </div>
                        <div>won <span>{reward.amount}</span> from {reward.source}</div>
                      </div>
                    </div>
                  ))
              )}
            </div>
          )}

          {tab === "store" && (
            <div className="store-grid">
              {dummyStore
                .map((item) => (
                  <div
                    key={item.id}
                    className={`store-card ${selectedStore === item.id ? "selected" : ""}`}
                    onClick={() => setSelectedStore(item.id)}
                  >
                    <div className="store-card-image" style={{ backgroundImage: `url(${item.image})` }}>
                       <span className={`item-badge badge-store badge-${item.category}`}>{item.category}</span>
                    </div>
                    <div className="store-card-info">
                      <h3>{item.name}</h3>
                      <p>
                        {dummyOwnedItems.includes(item.id) ? "Owned" : item.price}
                      </p>
                    </div>
                  </div>
                ))}
            </div>
          )}
        </div>
        </div>


      </div>

      {tab === "events" && selectedMatch && (
        <button
          className={`play-fixed ${canPlay ? "active" : "disabled"} ${playButtonState === "counting" ? "counting" : ""}`}
          onClick={canPlay ? handlePlayClick : undefined}
          disabled={!canPlay}
          style={{
            opacity: canPlay ? 1 : 0.5,
            pointerEvents: canPlay ? "auto" : "none"
          }}
        >
          {playButtonState === "counting" ? (
            <span>{elapsedTime.toFixed(1)}s Cancel</span>
          ) : (
            <span>
              {canPlay
                ? "PLAY"
                : isLive && selectedMatchData?.startTime
                  ? `Starts at ${formatLocalTime(selectedMatchData.startTime)}`
                  : "Not Live"}
            </span>
          )}
        </button>
      )}

      {tab === "store" && selectedStore && (
        <button
          className="buy-fixed active"
          onClick={() => {
            const item = dummyStore.find(i => i.id === selectedStore);
            if (!item) return;
            const isOwned = dummyOwnedItems.includes(selectedStore);
            if (isOwned) {
              setEquippedSkin(item);
            } else {
              // Future: Add purchase logic here
            }
          }}
          style={{
            opacity: 1,
            pointerEvents: "auto"
          }}
        >
          <span>
            {dummyOwnedItems.includes(selectedStore) ? "EQUIP" : "BUY"}
          </span>
        </button>
      )}
    </div>
  );
}
