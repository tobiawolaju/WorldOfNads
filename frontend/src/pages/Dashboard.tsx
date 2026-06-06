// @ts-nocheck
import { useEffect, useRef, useState } from "react";
import { usePrivy } from "@privy-io/react-auth";
import { useNavigate } from "react-router-dom";
import { ethers } from "ethers";
import { FaFire } from "react-icons/fa";
import { FullScreenLoader } from "../components/ui/fullscreen-loader";
import { ThreeScene } from "../components/ThreeScene";
import "./Dashboard.css";
import {
  fetchMatchesFromFirebase,
  getUsernameFromPrivy,
  getProfilePictureFromPrivy,
  fetchUserProfile,
  saveUserToFirebase,
  updateUserEquippedSkin,
  updateUserProjects,
  fetchUserRewards,
  recordSponsorDailyUniquePlayer
} from "./firebaseClient";
import { trackMatchJoined } from "../lib/analyticsClient";
import { resolveGameSkinName } from "../lib/skinMapping";
import { staticMatches } from "./staticMatches.js";
import storeItemsData from "../data/items.json";

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
  ctaMode?: "play" | "countdown";
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
  attachmentShape?: "box" | "cone" | "sphere" | "cylinder" | "torus";
  color?: string;
  cheekColor?: string;
  attachmentColor?: string;
  shader?: "ghost" | "gold" | "shadow" | "angel" | "default";
  shaderTargets?: ("body" | "cheek" | "eye" | "attachment")[];
  eyeColor?: string;
  rawFragmentShader?: string;
  rawVertexShader?: string;
};

type StoreItem = {
  id: string;
  name: string;
  price: string;
  image: string;
  category: "skins" | "costumes" | "bundles";
  description: string;
  badge?: "new";
  skinConfig?: SkinConfig;
};

const dummyStore: StoreItem[] = storeItemsData as StoreItem[];

const dummyOwnedItems: string[] = ["s-default", "s0", "s1", "s2", "s3", "s4", "s5", "s6"]; // All skins except beNad
const getStoreImageUrl = (item: StoreItem) => item.image || `/skins_png/${item.id}.png`;

export default function Dashboard() {
  const { ready, authenticated, user, logout } = usePrivy();
  const navigate = useNavigate();

  const [earned, setEarned] = useState<number>(0);
  const [selectedMatch, setSelectedMatch] = useState<string | null>(null);
  const [selectedReward, setSelectedReward] = useState<string | null>(null);
  const [selectedStore, setSelectedStore] = useState<string | null>(null);
  const [equippedSkin, setEquippedSkin] = useState<StoreItem | null>(dummyStore[0]);
  const newStoreItemCount = 1;

  const [tab, setTab] = useState<"events" | "rewards" | "store">("events");
  const [filter, setFilter] = useState<"upcoming" | "live" | "completed">("live");

  const currentStoreItem = selectedStore ? dummyStore.find((i) => i.id === selectedStore) || null : null;
  const isSelectedStoreOwned = Boolean(currentStoreItem && dummyOwnedItems.includes(currentStoreItem.id));
  const displayedSkin = (tab === "store" && currentStoreItem) ? currentStoreItem : equippedSkin;

  const [matches, setMatches] = useState<Match[]>(staticMatches as Match[]);
  const [rewards, setRewards] = useState<RewardItem[]>([]);
  const [playButtonState, setPlayButtonState] = useState<"idle" | "counting">("idle");
  const [elapsedTime, setElapsedTime] = useState(0);
  const [nowMs, setNowMs] = useState(Date.now());
  const [showLoader, setShowLoader] = useState(true);

  const carouselRef = useRef<HTMLDivElement>(null);
  const isManuallyScrolling = useRef<boolean>(false);
  const scrollTimeout = useRef<NodeJS.Timeout | null>(null);
  const intervalRef = useRef<NodeJS.Timeout | null>(null);
  const navigationTimeoutRef = useRef<NodeJS.Timeout | null>(null);

  const clearPlayTimers = () => {
    if (intervalRef.current) {
      clearInterval(intervalRef.current);
      intervalRef.current = null;
    }
    if (navigationTimeoutRef.current) {
      clearTimeout(navigationTimeoutRef.current);
      navigationTimeoutRef.current = null;
    }
  };

  useEffect(() => {
    if (authenticated && user) {
      saveUserToFirebase(user).catch((error: any) => {
        console.error("Failed to save user", error);
      });
    }
  }, [authenticated, user]);

  useEffect(() => {
    if (!authenticated || !user) return;

    const loadSavedSkin = async () => {
      try {
        const username = getUsernameFromPrivy(user);
        const profile = await fetchUserProfile(username);
        const savedSkinId = profile?.equippedSkinId;
        const savedSkin = dummyStore.find((item) => item.id === savedSkinId) || dummyStore[0];
        setEquippedSkin(savedSkin);
      } catch (error) {
        console.error("Failed to load saved skin", error);
      }
    };

    loadSavedSkin();
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
      clearPlayTimers();
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

  useEffect(() => {
    setShowLoader(!ready);
  }, [ready]);

  const handlePlayClick = () => {
    if (!selectedMatch || !user) return;

    if (playButtonState === "idle") {
      setPlayButtonState("counting");
      setElapsedTime(0);
      clearPlayTimers();
      intervalRef.current = setInterval(() => {
        setElapsedTime((prev) => Math.min(prev + 0.1, 4));
      }, 100);

      navigationTimeoutRef.current = setTimeout(() => {
        clearPlayTimers();
        setPlayButtonState("idle");
        const currentSkinId = displayedSkin?.id || equippedSkin?.id || "s-default";
        const currentSkinName = resolveGameSkinName(currentSkinId);
        const playParams = new URLSearchParams({
          match: selectedMatch,
          skin: currentSkinName
        });
        navigate(`/play?${playParams.toString()}`);
      }, 4000);

      void (async () => {
        const match = matches.find((item) => item.matchId === selectedMatch);
        if (!match) return;

        try {
          const username = getUsernameFromPrivy(user);
          const skinId = displayedSkin?.id || equippedSkin?.id || "s-default";
          const skinName = resolveGameSkinName(skinId);
          await Promise.allSettled([
            updateUserProjects(username, match.sponsor),
            recordSponsorDailyUniquePlayer({ sponsor: match.sponsor, username })
          ]);
          trackMatchJoined({
            userId: user.id,
            matchId: match.matchId,
            sponsorId: match.sponsor,
            metadata: { username, skinId, skinName }
          });
        } catch (error) {
          console.error("Failed to start play session", error);
        }
      })();
    } else {
      clearPlayTimers();
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

  const formatCountdown = (timestamp: number | undefined) => {
    if (!timestamp) return null;
    const remainingMs = Math.max(timestamp * 1000 - nowMs, 0);
    const totalSeconds = Math.floor(remainingMs / 1000);
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;
    return (
      <>
        {hours}:{String(minutes).padStart(2, "0")}:
        <span className="countdown-seconds-wrap">
          <span className="countdown-seconds-separator">:</span>
          <span className="countdown-seconds">{String(seconds).padStart(2, "0")}</span>
        </span>
      </>
    );
  };

  // --- Multi-Provider Social Extraction ---
  const socialProviders = [
    "twitter_oauth",
    "farcaster",
    "google_oauth",
    "twitch_oauth",
    "tiktok_oauth",
    "spotify_oauth"
  ];
  
  let socialData: any = undefined;
  for (const pType of socialProviders) {
    const acc = user.linkedAccounts?.find((a) => a.type === pType);
    if (acc) {
      socialData = {
        provider: pType,
        username: acc.username || undefined,
        profilePictureUrl: getProfilePictureFromPrivy(user) || undefined,
        name: acc.name || acc.username || undefined
      };
      break;
    }
  }

  // Filter for ONLY the Ethereum wallet (Monad)
  const wallets = (user.linkedAccounts?.filter(
    (acc) => acc.type === "wallet" && acc.chainType === "ethereum"
  ) || []) as Wallet[];

  const normalizeMatchStatus = (status: Match["status"] | string) =>
    status === "settled" ? "completed" : status;

  const isPlayableLiveMatch = (match: Match) => {
    if (normalizeMatchStatus(match.status) !== "live") return false;
    if (match.ctaMode === "play") return true;
    if (!match.startTime) return true;
    return nowMs >= match.startTime * 1000;
  };

  const statusOrder: Array<"upcoming" | "live" | "completed"> = ["upcoming", "live", "completed"];
  const orderedMatches = [...matches].sort((a, b) => {
    const aRank = statusOrder.indexOf(normalizeMatchStatus(a.status) as "upcoming" | "live" | "completed");
    const bRank = statusOrder.indexOf(normalizeMatchStatus(b.status) as "upcoming" | "live" | "completed");
    if (aRank !== bRank) return aRank - bRank;
    if (normalizeMatchStatus(a.status) === "live" && normalizeMatchStatus(b.status) === "live") {
      const aPlayable = isPlayableLiveMatch(a);
      const bPlayable = isPlayableLiveMatch(b);
      if (aPlayable !== bPlayable) return aPlayable ? -1 : 1;
      return (b.startTime || 0) - (a.startTime || 0);
    }
    return (a.startTime || 0) - (b.startTime || 0);
  });

  const selectedMatchData = matches.find((match) => match.matchId === selectedMatch) || null;
  const normalizedSelectedStatus = normalizeMatchStatus(selectedMatchData?.status);
  const isLive = normalizedSelectedStatus === "live";
  const isTrainingLobby = selectedMatchData?.ctaMode === "play";
  const isStartTimeReached = selectedMatchData?.startTime
    ? nowMs >= selectedMatchData.startTime * 1000
    : true;
  const isLiveCountdownActive = Boolean(
    isLive &&
      selectedMatchData?.startTime &&
      nowMs < selectedMatchData.startTime * 1000 &&
      selectedMatchData.ctaMode !== "play"
  );
  const canPlay = isTrainingLobby || ((isLive || (normalizedSelectedStatus === "upcoming" && isStartTimeReached)) && isStartTimeReached);
  const firstPlayableLiveMatch = orderedMatches.find((match) => isPlayableLiveMatch(match)) || null;
  const getFallbackMatch = () =>
    (filter === "live"
      ? firstPlayableLiveMatch || orderedMatches.find((match) => normalizeMatchStatus(match.status) === "live")
      : orderedMatches.find((match) => normalizeMatchStatus(match.status) === filter)) || orderedMatches[0] || null;

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
      const closestStatus = (closest as HTMLElement).dataset.status as "upcoming" | "live" | "completed" | undefined;
      if (closestStatus && closestStatus !== filter) {
        setFilter(closestStatus);
      }
    }
  };

  const scrollCardIntoView = (matchId: string) => {
    const carousel = carouselRef.current;
    if (!carousel) return;

    const targetCard = Array.from(carousel.children).find(
      (child) => (child as HTMLElement).dataset.id === matchId
    ) as HTMLElement | undefined;

    if (!targetCard) return;

    const target = targetCard.offsetLeft - carousel.offsetWidth / 2 + targetCard.offsetWidth / 2;
    isManuallyScrolling.current = true;
    carousel.scrollTo({ left: target, behavior: "smooth" });
    setTimeout(() => {
      isManuallyScrolling.current = false;
      updateSelectedCard();
    }, 600);
  };

  useEffect(() => {
    if (tab !== "events") return;
    if (selectedMatch && matches.some((match) => match.matchId === selectedMatch)) return;

    const fallbackMatch = getFallbackMatch();
    if (!fallbackMatch) return;

    const fallbackStatus = normalizeMatchStatus(fallbackMatch.status);
    if (fallbackStatus !== filter) {
      setFilter(fallbackStatus);
    }
    setSelectedMatch(fallbackMatch.matchId);
    if (fallbackStatus === "live") {
      scrollCardIntoView(fallbackMatch.matchId);
    }
  }, [tab, selectedMatch, matches, orderedMatches, filter]);

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
  }, [orderedMatches.length, filter]);

  useEffect(() => {
    if (tab !== "events" || filter !== "live") return;
    if (!firstPlayableLiveMatch) return;
    if (selectedMatch === firstPlayableLiveMatch.matchId) return;
    setSelectedMatch(firstPlayableLiveMatch.matchId);
    scrollCardIntoView(firstPlayableLiveMatch.matchId);
  }, [tab, filter, firstPlayableLiveMatch, selectedMatch]);

  const jumpToStatus = (status: "upcoming" | "live" | "completed") => {
    setFilter(status);
    setSelectedMatch(null);

    const carousel = carouselRef.current;
    if (!carousel) return;

    const targetCard = Array.from(carousel.children).find(
      (child) => (child as HTMLElement).dataset.status === status
    ) as HTMLElement | undefined;

    if (!targetCard) return;
    setSelectedMatch(targetCard.dataset.id || null);
    scrollCardIntoView(targetCard.dataset.id || "");
  };

  return (
    <>
      <FullScreenLoader visible={showLoader} />
      {!showLoader && authenticated && user && (
        <div className="dashboard-wrapper">
        <div className="left-3d-section">
        <ThreeScene
          social={socialData}
          wallets={wallets}
          earned={earned}
          username={getUsernameFromPrivy(user)}
          onLogout={logout}
          equippedSkin={displayedSkin}
          isStoreOpen={tab === "store"}
        />
      </div>

      <div className="right-info-section">
        <div className="tabs">
          <div className={tab === "events" ? "tab active" : "tab"} onClick={() => { setTab("events"); setSelectedMatch(null); setSelectedReward(null); setSelectedStore(null); }}>
            <span className="tab-with-badge">Events</span>
          </div>
          <div className={tab === "rewards" ? "tab active" : "tab"} onClick={() => { setTab("rewards"); setSelectedMatch(null); setSelectedReward(null); setSelectedStore(null); }}>
            <span className="tab-with-badge">Rewards</span>
          </div>
          <div className={tab === "store" ? "tab active" : "tab"} onClick={() => { setTab("store"); setSelectedMatch(null); setSelectedReward(null); setSelectedStore(null); }}>
            <span className="tab-with-badge">
              Store
              <span className="tab-notif-badge">
                <span className="tab-notif-badge-text">{newStoreItemCount}</span>
              </span>
            </span>
          </div>
        </div>

        <div className="filters">
          {tab === "events" && (
            <>
              <span className={filter === "upcoming" ? "filter active" : "filter"} onClick={() => jumpToStatus("upcoming")}>Upcoming</span>
              <span className={filter === "live" ? "filter active" : "filter"} onClick={() => jumpToStatus("live")}>Live</span>
              <span className={filter === "completed" ? "filter active" : "filter"} onClick={() => jumpToStatus("completed")}>Completed</span>
            </>
          )}
        </div>

        <div className="tab-content-scroll">
          <div className="matches-wrapper">
            {tab === "events" && (
              <div className="matches-carousel" ref={carouselRef}>
                {orderedMatches.map((match) => (
                  <div
                    key={match.matchId}
                    data-id={match.matchId}
                    data-status={normalizeMatchStatus(match.status)}
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
                      <div className={`match-card-overlay selected-overlay status-${normalizeMatchStatus(match.status)}`}>

                        <div className="match-details-inner">
                          <p className="match-desc">{match.description}</p>
                          <p className="match-info">Prize: {match.prize}</p>
                          <p className="match-info">
                            Time: {match.ctaMode === "play"
                              ? match.time
                              : match.status === "live" && match.startTime && nowMs < match.startTime * 1000
                                ? formatCountdown(match.startTime)
                                : match.startTime
                                  ? `${formatLocalTime(match.startTime)}`
                                  : match.time}
                          </p>
                        </div>
                      </div>
                    ) : (
                      <div className="match-card-overlay">
                        <h3 className="match-sponsor">{match.sponsor}</h3>
                        <p className="match-reward">{match.prize}</p>
                        <p className="match-time">
                          {match.ctaMode === "play"
                            ? match.time
                            : match.status === "live" && match.startTime && nowMs < match.startTime * 1000
                              ? formatCountdown(match.startTime)
                              : match.status === "upcoming" && match.startTime
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
                      className={`store-card ${dummyOwnedItems.includes(item.id) ? "owned" : "unowned"} ${selectedStore === item.id ? "selected" : ""}`}
                      onClick={() => setSelectedStore(item.id)}
                    >
                      <div className="store-card-image" style={{ backgroundImage: `url(${getStoreImageUrl(item)})` }}>
                        {!dummyOwnedItems.includes(item.id) && (
                          <span className="item-badge badge-store">new</span>
                        )}
                        {item.badge && (
                          <span className="item-badge badge-store badge-new">{item.badge}</span>
                        )}
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
            opacity: 1,
            pointerEvents: canPlay ? "auto" : "none"
          }}
        >
          {playButtonState === "counting" ? (
            <span>{elapsedTime.toFixed(1)}s Cancel</span>
          ) : (
            <span>
              {isTrainingLobby
                ? "PLAY"
                : canPlay
                  ? "PLAY"
                : normalizedSelectedStatus === "upcoming"
                  ? "•°••"
                  : isLiveCountdownActive && selectedMatchData?.startTime
                    ? formatCountdown(selectedMatchData.startTime)
                    : "Not Live"}
            </span>
          )}
        </button>
      )}

      {tab === "store" && selectedStore && (
        <div className="footer-buttons is-visible">
          <button
            className="play-btn-fixed"
            onClick={() => {
              if (!currentStoreItem) return;
              if (isSelectedStoreOwned) {
                setEquippedSkin(currentStoreItem);
                updateUserEquippedSkin(getUsernameFromPrivy(user), currentStoreItem.id).catch((error: any) => {
                  console.error("Failed to save equipped skin", error);
                });
                setSelectedStore(null);
              } else {
                // Mint Function Blank for now
              }
            }}
          >
            {isSelectedStoreOwned ? "EQUIP" : "MINT"}
          </button>
          {isSelectedStoreOwned && (
            <button
              type="button"
              className="discord-btn-fixed"
              onClick={() => {
                if (!currentStoreItem) return;
                setEquippedSkin(currentStoreItem);
                updateUserEquippedSkin(getUsernameFromPrivy(user), currentStoreItem.id).catch((error: any) => {
                  console.error("Failed to save equipped skin", error);
                });
                setSelectedStore(null);
              }}
              aria-label={`Equip ${currentStoreItem.name}`}
              title={`Equip ${currentStoreItem.name}`}
            >
              <FaFire size={28} />
            </button>
          )}
        </div>
      )}
        </div>
      )}
    </>
  );
}
