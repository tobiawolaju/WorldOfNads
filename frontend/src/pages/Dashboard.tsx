import React, { useEffect, useRef, useState } from "react";
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
};

type RewardItem = {
  id: string;
  username: string;
  amount: string;
  source: string;
  category: "earned" | "gifted";
  date: string;
};

type StoreItem = {
  id: string;
  name: string;
  price: string;
  image: string;
  category: "skins" | "emotes" | "bundles";
  description: string;
};

const dummyStore: StoreItem[] = [
  { id: "s1", name: "Gladiator Skin", price: "20 MON", image: "/logo.jpg", category: "skins", description: "Battle-hardened armor for your character." },
  { id: "s2", name: "Heart Wave", price: "5 MON", image: "/logo.jpg", category: "emotes", description: "Spread the love in the arena." },
  { id: "s3", name: "Starter Bundle", price: "45 MON", image: "/logo.jpg", category: "bundles", description: "Everything a new Nad needs to survive." },
  { id: "s4", name: "Ninja Skin", price: "35 MON", image: "/logo.jpg", category: "skins", description: "Move like a shadow, strike like lightning." },
  { id: "s5", name: "Chicken Dance", price: "8 MON", image: "/logo.jpg", category: "emotes", description: "A classic victory taunt." },
  { id: "s6", name: "Elite Bundle", price: "150 MON", image: "/logo.jpg", category: "bundles", description: "Full set of elite gear and exclusive emotes." },
  { id: "s7", name: "Cyberpunk Skin", price: "60 MON", image: "/logo.jpg", category: "skins", description: "Neon-soaked aesthetic for the modern warrior." },
  { id: "s8", name: "Llama Dance", price: "12 MON", image: "/logo.jpg", category: "emotes", description: "Celebrate with some llama energy." },
];

export default function Dashboard() {
  const { ready, authenticated, user, logout } = usePrivy();
  const navigate = useNavigate();

  const [earned, setEarned] = useState<number>(0);
  const [monBalance, setMonBalance] = useState<string>("0");
  const [selectedMatch, setSelectedMatch] = useState<string | null>(null);
  const [selectedReward, setSelectedReward] = useState<string | null>(null);
  const [selectedStore, setSelectedStore] = useState<string | null>(null);

  const [tab, setTab] = useState<"events" | "rewards" | "store">("events");
  const [filter, setFilter] = useState<"upcoming" | "live" | "completed">("live");
  const [rewardFilter, setRewardFilter] = useState<"earned" | "gifted">("earned");
  const [storeFilter, setStoreFilter] = useState<"skins" | "emotes" | "bundles">("skins");

  const [matches, setMatches] = useState<Match[]>(staticMatches as Match[]);
  const [rewards, setRewards] = useState<RewardItem[]>([]);
  const [playButtonState, setPlayButtonState] = useState<"idle" | "counting">("idle");
  const [elapsedTime, setElapsedTime] = useState(0);

  const carouselRef = useRef<HTMLDivElement>(null);
  const isManuallyScrolling = useRef<boolean>(false);
  const scrollTimeout = useRef<NodeJS.Timeout | null>(null);
  const intervalRef = useRef<NodeJS.Timeout | null>(null);
  const navigationTimeoutRef = useRef<NodeJS.Timeout | null>(null);

  useEffect(() => {
    if (authenticated && user) {
      saveUserToFirebase(user).catch((error) => {
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
          setMonBalance(parseFloat(formatted).toFixed(4));
          setEarned(parseFloat(formatted));
        }
      } catch (error) {
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
    const loadMatches = async () => {
      try {
        const firebaseMatches = await fetchMatchesFromFirebase();
        if (firebaseMatches.length > 0) {
          setMatches(firebaseMatches as Match[]);
        }
      } catch (error) {
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
      } catch (error) {
        console.error("Failed to fetch rewards", error);
      }
    };

    loadRewards();
  }, [authenticated, user]);

  // No longer auto-selecting the first match on filter change to allow for a clean "refresh" state
  // as requested by the user. Selection will happen via carousel scrolling or clicking.
  // useEffect(() => {
  //   const candidate = matches.find((match) => match.status === filter) || matches[0];
  //   if (candidate) {
  //     setSelectedMatch(candidate.matchId);
  //   }
  // }, [filter, matches]);

  useEffect(() => {
    if (!selectedMatch && !selectedReward && !selectedStore) return;
    window.scrollTo({
      top: document.body.scrollHeight,
      behavior: "smooth"
    });
  }, [selectedMatch, selectedReward, selectedStore]);

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

  const filteredMatches = matches.filter((match) => match.status === filter);
  const selectedMatchData = matches.find((match) => match.matchId === selectedMatch) || null;
  const isLive = selectedMatchData?.status === "live";

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

    if (closest?.dataset.id) {
      setSelectedMatch(String(closest.dataset.id));
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

          {tab === "rewards" && (
            <>
              <span className={rewardFilter === "earned" ? "filter active" : "filter"} onClick={() => { setRewardFilter("earned"); setSelectedReward(null); }}>Earned</span>
              <span className={rewardFilter === "gifted" ? "filter active" : "filter"} onClick={() => { setRewardFilter("gifted"); setSelectedReward(null); }}>Gifted</span>
            </>
          )}

          {tab === "store" && (
            <>
              <span className={storeFilter === "skins" ? "filter active" : "filter"} onClick={() => { setStoreFilter("skins"); setSelectedStore(null); }}>Skins</span>
              <span className={storeFilter === "emotes" ? "filter active" : "filter"} onClick={() => { setStoreFilter("emotes"); setSelectedStore(null); }}>Emotes</span>
              <span className={storeFilter === "bundles" ? "filter active" : "filter"} onClick={() => { setStoreFilter("bundles"); setSelectedStore(null); }}>Bundles</span>
            </>
          )}
        </div>

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
                  <div className="match-card-overlay">
                    <h3 className="match-sponsor">{match.sponsor}</h3>
                    <p className="match-reward">{match.prize}</p>
                    <p className="match-time">
                      {match.status === "upcoming" && match.startTime
                        ? `${formatLocalTime(match.startTime)} (Local)`
                        : match.time}
                    </p>
                  </div>
                </div>
              ))}
            </div>
          )}

          {tab === "rewards" && (
            <div className="reward-list">
              {rewards.filter((r) => r.category === rewardFilter).length === 0 ? (
                <div className="reward-empty">
                  No rewards yet. Join a match to win some.
                </div>
              ) : (
                rewards
                  .filter((r) => r.category === rewardFilter)
                  .map((reward) => (
                    <div
                      key={reward.id}
                      className={`reward-item ${selectedReward === reward.id ? "selected" : ""}`}
                      onClick={() => setSelectedReward(reward.id)}
                    >
                      <div className="reward-item-icon">??</div>
                      <div className="reward-item-text">
                        <strong>{reward.username}</strong> won <span>{reward.amount}</span> from {reward.source}
                      </div>
                    </div>
                  ))
              )}
            </div>
          )}

          {tab === "store" && (
            <div className="store-grid">
              {dummyStore
                .filter((s) => s.category === storeFilter)
                .map((item) => (
                  <div
                    key={item.id}
                    className={`store-card ${selectedStore === item.id ? "selected" : ""}`}
                    onClick={() => setSelectedStore(item.id)}
                  >
                    <div className="store-card-image" style={{ backgroundImage: `url(${item.image})` }}></div>
                    <div className="store-card-info">
                      <h3>{item.name}</h3>
                      <p>{item.price}</p>
                    </div>
                  </div>
                ))}
            </div>
          )}
        </div>

        <div className="match-details">
          {tab === "events" && selectedMatchData && (
            <div className="match-details-box">
              <h2 className="match-details-title">{selectedMatchData.sponsor}</h2>
              <p className="match-details-description">{selectedMatchData.description}</p>
              <p className="match-details-description">
                Match ID: {selectedMatchData.matchId}
                <br />
                Prize Deposited: {selectedMatchData.prize}
                <br />
                Match Date: {selectedMatchData.date}
                <br />
                Start Time: {selectedMatchData.startTime ? `${formatLocalTime(selectedMatchData.startTime)} (24h Local)` : selectedMatchData.time}
              </p>
              <a href={selectedMatchData.url} target="_blank" rel="noopener noreferrer" className="match-details-twitter">
                Visit Sponsor -{'>'}
              </a>
            </div>
          )}

          {tab === "rewards" && selectedReward && (
            <div className="match-details-box">
              {(() => {
                const r = rewards.find((x) => x.id === selectedReward);
                if (!r) return null;
                return (
                  <>
                    <h2 className="match-details-title">Reward Detail</h2>
                    <p className="match-details-description">
                      Username: {r.username}
                      <br />
                      Reward: {r.amount}
                      <br />
                      Source: {r.source}
                      <br />
                      Type: {r.category}
                      <br />
                      Date: {r.date}
                    </p>
                  </>
                );
              })()}
            </div>
          )}

          {tab === "store" && selectedStore && (
            <div className="match-details-box">
              {(() => {
                const s = dummyStore.find((x) => x.id === selectedStore);
                if (!s) return null;
                return (
                  <>
                    <h2 className="match-details-title">{s.name}</h2>
                    <p className="match-details-description">{s.description}</p>
                    <p className="match-details-description">
                      Price: {s.price}
                      <br />
                      Category: {s.category}
                    </p>
                    <button className="sponsor-dashboard__cta" style={{ width: '100%', marginTop: '10px' }}>Buy Now</button>
                  </>
                );
              })()}
            </div>
          )}

          {((tab === "events" && !selectedMatchData) || (tab === "rewards" && !selectedReward) || (tab === "store" && !selectedStore)) && (
            <div className="match-details-empty">
              <p>Select an item to view details</p>
            </div>
          )}
        </div>
      </div>

      {tab === "events" && (
        <button
          className={`play-fixed ${isLive ? "active" : "disabled"} ${playButtonState === "counting" ? "counting" : ""}`}
          onClick={isLive ? handlePlayClick : undefined}
          disabled={!isLive}
          style={{
            opacity: isLive ? 1 : 0.5,
            pointerEvents: isLive ? "auto" : "none"
          }}
        >
          {playButtonState === "counting" ? <span>{elapsedTime.toFixed(1)}s Cancel</span> : <span>PLAY</span>}
        </button>
      )}
    </div>
  );
}
