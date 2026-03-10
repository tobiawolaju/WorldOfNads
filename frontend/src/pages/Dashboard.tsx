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
  updateUserProjects
} from "./firebaseClient";
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
};

export default function Dashboard() {
  const { ready, authenticated, user, logout } = usePrivy();
  const navigate = useNavigate();

  const [earned, setEarned] = useState<number>(0);
  const [monBalance, setMonBalance] = useState<string>("0");
  const [selectedMatch, setSelectedMatch] = useState<string | null>(null);
  const [tab, setTab] = useState<"events" | "rewards" | "store">("events");
  const [filter, setFilter] = useState<"upcoming" | "live" | "completed">("live");
  const [matches, setMatches] = useState<Match[]>(staticMatches as Match[]);
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
    const candidate = matches.find((match) => match.status === filter) || matches[0];
    if (candidate) {
      setSelectedMatch(candidate.matchId);
    }
  }, [filter, matches]);

  useEffect(() => {
    if (!selectedMatch) return;
    window.scrollTo({
      top: document.body.scrollHeight,
      behavior: "smooth"
    });
  }, [selectedMatch]);

  const handlePlayClick = async () => {
    if (!selectedMatch || !user) return;

    const match = matches.find((item) => item.matchId === selectedMatch);
    if (match) {
      const username = getUsernameFromPrivy(user);
      await updateUserProjects(username, match.sponsor);
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
        <ThreeScene twitter={twitterData} wallets={wallets} earned={earned} onLogout={logout} />
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
                  <p className="match-time">{match.time}</p>
                </div>
              </div>
            ))}
          </div>
        </div>

        <div className="match-details">
          {selectedMatchData ? (
            <div className="match-details-box">
              <h2 className="match-details-title">{selectedMatchData.sponsor}</h2>
              <p className="match-details-description">{selectedMatchData.description}</p>
              <p className="match-details-description">
                Match ID: {selectedMatchData.matchId}
                <br />
                Prize Deposited: {selectedMatchData.prize}
                <br />
                Match Date: {selectedMatchData.date}
              </p>
              <a href={selectedMatchData.url} target="_blank" rel="noopener noreferrer" className="match-details-twitter">
                Visit Sponsor -{'>'}
              </a>
            </div>
          ) : (
            <div className="match-details-empty">
              <p>Select a match to view details</p>
            </div>
          )}
        </div>
      </div>

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
    </div>
  );
}
