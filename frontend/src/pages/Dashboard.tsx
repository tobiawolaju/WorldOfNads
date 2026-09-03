// @ts-nocheck
import { useEffect, useMemo, useRef, useState, useCallback } from "react";
import { usePrivy, useWallets } from "@privy-io/react-auth";
import { useNavigate } from "react-router-dom";
import { ethers } from "ethers";
import { FullScreenLoader } from "../components/ui/fullscreen-loader";
import { ThreeScene } from "../components/ThreeScene";
import "./Dashboard.css";
import {
  fetchMatchesFromFirebase,
  fetchUserRoles,
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
import { showSuccessToast, showErrorToast } from "../components/ui/custom-toast";
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
  onChainId?: number | null;
  requiredXP?: number;
  maxSupply?: number | null;
  tier?: string;
  skinConfig?: SkinConfig;
};

const SKINS_ABI = [
  "function mintSkin(uint256 skinId, uint256 amount) external payable",
  "function balanceOf(address account, uint256 id) external view returns (uint256)",
  "function skins(uint256) view returns (uint256 maxSupply, uint256 minted, uint256 mintPrice, uint256 requiredXP, uint8 tier, bool exists)",
  "error InvalidSkin()",
  "error SupplyExhausted()",
  "error InsufficientPayment()",
  "error InsufficientXP()"
];

const XP_ABI = [
  "function balanceOf(address account) external view returns (uint256)"
];

const LAUNCHER_API = import.meta.env.VITE_ANALYTICS_API_URL || "https://worldofnads.onrender.com";
const LOCAL_ITEMS = storeItemsData as StoreItem[];

const getStoreImageUrl = (item: StoreItem) => item.image || `/skins_png/${item.id}.png`;

function getLevelFromXP(xp: number): number {
  if (xp <= 0) return 1;
  return Math.floor(Math.sqrt(xp / 100)) + 1;
}

function getXPForLevel(level: number): number {
  if (level <= 1) return 0;
  return (level - 1) * (level - 1) * 100;
}

export default function Dashboard() {
  const [storeItems, setStoreItems] = useState<StoreItem[]>(LOCAL_ITEMS);
  useEffect(() => {
    let mounted = true;
    const fetchSkins = async () => {
      try {
        const res = await fetch(`${LAUNCHER_API}/api/skins`);
        if (!res.ok) return;
        const data = await res.json();
        if (!data.ok || !Array.isArray(data.skins) || !mounted) return;
        const apiItems: StoreItem[] = data.skins.map((s: any): StoreItem => ({
          id: String(s.id || ''),
          name: s.name || 'Unknown',
          price: s.price || '0 MON',
          image: s.image || `/skins_png/${s.id || ''}.png`,
          category: 'skins',
          description: s.description || `${s.name || 'Skin'} from the catalog.`,
          onChainId: s.onChainId ?? null,
          requiredXP: s.requiredXP || 0,
          maxSupply: s.maxSupply || null,
          tier: s.tier || 'common',
          skinConfig: s.skinConfig,
        })).filter(item => item.id !== '');
        if (!mounted) return;
        setStoreItems(prev => {
          const map = new Map(prev.map(item => [item.id, item]));
          for (const apiItem of apiItems) {
            map.set(apiItem.id, apiItem);
          }
          return Array.from(map.values());
        });
      } catch { /* API unavailable, keep local fallback */ }
    };
    fetchSkins();
    return () => { mounted = false; };
  }, []);
  const { ready, authenticated, user, logout } = usePrivy();
  const { wallets } = useWallets();
  const navigate = useNavigate();

  const [earned, setEarned] = useState<number>(0);
  const [selectedMatch, setSelectedMatch] = useState<string | null>(null);
  const [selectedReward, setSelectedReward] = useState<string | null>(null);
  const [selectedStore, setSelectedStore] = useState<string | null>(null);
  const [equippedSkin, setEquippedSkin] = useState<StoreItem | null>(LOCAL_ITEMS[0]);
  const [xp, setXp] = useState<number>(0);
  const [xpBalance, setXpBalance] = useState<number>(0);
  const [ownedSkinIds, setOwnedSkinIds] = useState<number[]>([]);
  const [isMinting, setIsMinting] = useState(false);
  const [mintError, setMintError] = useState<string | null>(null);
  const [equipFlash, setEquipFlash] = useState(false);
  const newStoreItemCount = 1;
  const [copied, setCopied] = useState(false);
  const [roles, setRoles] = useState<string[]>([]);

  const { level, xpInLevel, levelRequirement } = useMemo(() => {
    let currentLvl = 0;
    let tempXp = xp;
    let req = 10 * (currentLvl + 1);
    while (tempXp >= req) {
      tempXp -= req;
      currentLvl += 1;
      req = 10 * (currentLvl + 1);
    }
    return { level: currentLvl, xpInLevel: tempXp, levelRequirement: req };
  }, [xp]);

  const [tab, setTab] = useState<"events" | "rewards" | "store">("events");
  const [filter, setFilter] = useState<"upcoming" | "live" | "completed">("live");
  const [storeFilter, setStoreFilter] = useState<"all" | "common" | "rare" | "epic" | "legendary">("all");
  const [supplyData, setSupplyData] = useState<Record<number, { minted: number; maxSupply: number }>>({});

  const currentStoreItem = selectedStore ? storeItems.find((i) => i.id === selectedStore) || null : null;
  const isSelectedStoreOwned = Boolean(
    currentStoreItem &&
    (currentStoreItem.id === "s-default" || currentStoreItem.id === "s-default-unshaded" || // defaults always owned
      (currentStoreItem.onChainId && ownedSkinIds.includes(currentStoreItem.onChainId)))
  );
  const selectedItemXP = currentStoreItem?.requiredXP || 0;
  const hasEnoughXP = xpBalance >= selectedItemXP;
  const selectedItemLevel = getLevelFromXP(selectedItemXP);
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
  const pendingAutoScrollToLive = useRef<boolean>(true);
  const previousTab = useRef<"events" | "rewards" | "store">("events");

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
        const savedSkin = storeItems.find((item) => item.id === savedSkinId) || LOCAL_ITEMS[0];
        setEquippedSkin(savedSkin);
      } catch (error) {
        console.error("Failed to load user profile", error);
      }
    };

    loadSavedSkin();
  }, [authenticated, user, storeItems]);

  // Load on-chain XP balance and owned skins
  useEffect(() => {
    if (!authenticated || !user) return;

    const loadOnchainData = async () => {
      try {
        const ethWallet = user.linkedAccounts?.find(
          (acc) => acc.type === "wallet" && acc.chainType === "ethereum"
        );
        if (!ethWallet || !("address" in ethWallet) || !ethWallet.address) return;

        const provider = new ethers.JsonRpcProvider("https://testnet-rpc.monad.xyz");
        const address = ethWallet.address;

        // Load XP balance
        const xpContractAddress = import.meta.env.VITE_XP_TOKEN_ADDRESS;
        if (xpContractAddress) {
          try {
            const xpContract = new ethers.Contract(xpContractAddress, XP_ABI, provider);
            const xpRaw = await xpContract.balanceOf(address);
            const xpFormatted = Number(ethers.formatEther(xpRaw));
            setXpBalance(xpFormatted);
            setXp(xpFormatted);
          } catch { /* XP contract not deployed yet */ }
        }

        // Load owned skins + supply data from on-chain
        const skinsContractAddress = import.meta.env.VITE_SKINS_CONTRACT_ADDRESS;
        if (skinsContractAddress) {
          try {
            const skinsContract = new ethers.Contract(skinsContractAddress, SKINS_ABI, provider);
            const owned: number[] = [];
            const supplies: Record<number, { minted: number; maxSupply: number }> = {};
            for (const item of storeItems) {
              if (item.onChainId) {
                const [balance, skinData] = await Promise.all([
                  skinsContract.balanceOf(address, item.onChainId),
                  skinsContract.skins(item.onChainId)
                ]);
                if (Number(balance) > 0) owned.push(item.onChainId);
                supplies[item.onChainId] = {
                  minted: Number(skinData.minted),
                  maxSupply: Number(skinData.maxSupply)
                };
              }
            }
            setOwnedSkinIds(owned);
            setSupplyData(supplies);
          } catch { /* Skins contract not deployed yet */ }
        }
      } catch (error) {
        console.error("Failed to load on-chain data:", error);
      }
    };

    loadOnchainData();
  }, [authenticated, user, storeItems]);

  // Fetch actual MON balance
  useEffect(() => {
    if (!authenticated || !user) return;

    const fetchBalance = async () => {
      try {
        const ethWallet = user.linkedAccounts?.find(
          (acc) => acc.type === "wallet" && acc.chainType === "ethereum"
        );
        if (ethWallet && "address" in ethWallet && ethWallet.address) {
        const provider = new ethers.JsonRpcProvider("https://testnet-rpc.monad.xyz");
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
    }, 1000);
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

  const handlePlayClick = useCallback(() => {
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
          showErrorToast("Failed to save play session data.");
        }
      })();
    } else {
      clearPlayTimers();
      setPlayButtonState("idle");
    }
  }, [selectedMatch, user, playButtonState, displayedSkin, equippedSkin, matches, navigate]);

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

  const username = getUsernameFromPrivy(user);

  useEffect(() => {
    let mounted = true;
    if (!username) return;
    fetchUserRoles(username)
      .then((data) => {
        if (mounted) setRoles(data || []);
      })
      .catch(() => {});
    return () => { mounted = false; };
  }, [username]);

  const handleCardClick = () => {
    if (wallets.length > 0) {
      const addr = wallets[0].address;
      navigator.clipboard.writeText(addr);
      showSuccessToast("Wallet address copied!");
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  };

  // Filter for ONLY the Ethereum wallet (Monad)
  const linkedWallets = (user.linkedAccounts?.filter(
    (acc) => acc.type === "wallet" && acc.chainType === "ethereum"
  ) || []) as Wallet[];

  const normalizeMatchStatus = (status: Match["status"] | string) =>
    status === "settled" ? "completed" : status;

  const statusOrder: Array<"upcoming" | "live" | "completed"> = ["upcoming", "live", "completed"];
  const orderedMatches = useMemo(() => {
    return [...matches].sort((a, b) => {
      const aRank = statusOrder.indexOf(normalizeMatchStatus(a.status) as "upcoming" | "live" | "completed");
      const bRank = statusOrder.indexOf(normalizeMatchStatus(b.status) as "upcoming" | "live" | "completed");
      if (aRank !== bRank) return aRank - bRank;
      return (a.startTime || 0) - (b.startTime || 0);
    });
  }, [matches]);

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
  const getFallbackMatch = useCallback(() =>
    orderedMatches.find((match) => normalizeMatchStatus(match.status) === filter) || orderedMatches[0] || null,
    [orderedMatches, filter]
  );

  const updateSelectedCard = useCallback(() => {
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
  }, [filter]);

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
    if (tab === "events" && previousTab.current === "store") {
      pendingAutoScrollToLive.current = true;
    }
    previousTab.current = tab;
  }, [tab]);

  const jumpToStatus = useCallback((status: "upcoming" | "live" | "completed") => {
    setFilter(status);
    setSelectedMatch(null);

    const carousel = carouselRef.current;
    if (!carousel) return false;

    const targetCard = Array.from(carousel.children).find(
      (child) => (child as HTMLElement).dataset.status === status
    ) as HTMLElement | undefined;

    if (!targetCard) return false;

    const target = targetCard.offsetLeft - carousel.offsetWidth / 2 + targetCard.offsetWidth / 2;
    isManuallyScrolling.current = true;
    carousel.scrollTo({ left: target, behavior: "smooth" });
    setSelectedMatch(targetCard.dataset.id || null);
    setTimeout(() => {
      isManuallyScrolling.current = false;
      updateSelectedCard();
    }, 600);

    return true;
  }, [updateSelectedCard]);

  useEffect(() => {
    if (tab !== "events" || showLoader || !pendingAutoScrollToLive.current) return;

    const didScroll = jumpToStatus("live");
    if (didScroll) {
      pendingAutoScrollToLive.current = false;
    }
  }, [tab, showLoader, orderedMatches.length]);

  return (
    <>
      <FullScreenLoader visible={showLoader} />
      {!showLoader && authenticated && user && (
        <div className="dashboard-wrapper">
        <div className={`left-3d-section ${equipFlash ? "shake" : ""}`}>
        <ThreeScene
          equippedSkin={displayedSkin}
          isStoreOpen={tab === "store"}
        />
        {equipFlash && <div className="equip-flash" />}

        <div className="card-overlay">
          <div className="card-top-left">
            <div className="card-balance">{earned.toFixed(4)} MON</div>
            <div className="card-wallet" onClick={handleCardClick}>
              {wallets.length > 0
                ? (copied ? "Copied!" : `${wallets[0].address.slice(0, 6)}...${wallets[0].address.slice(-4)}`)
                : "No wallet"}
            </div>
          </div>
          <div className="card-top-right">
            <div className="card-level">Level {level}</div>
            <div className="xp-bar-track">
              <div className="xp-bar-fill" style={{ width: `${Math.min((xpInLevel / levelRequirement) * 100, 100)}%` }} />
            </div>
          </div>
          <div className="card-bottom">
            {roles.includes("admin") && (
              <button onClick={() => navigate("/admin/dashboard")}>Admin</button>
            )}
            {roles.includes("sponsor") && (
              <button onClick={() => navigate("/sponsor")}>Host Match</button>
            )}
            <button onClick={() => logout()}>Logout</button>
          </div>
        </div>
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
          {tab === "store" && (
            <>
              <span className={storeFilter === "all" ? "filter active" : "filter"} onClick={() => setStoreFilter("all")}>All</span>
              <span className={storeFilter === "common" ? "filter active" : "filter"} onClick={() => setStoreFilter("common")}>Common</span>
              <span className={storeFilter === "rare" ? "filter active" : "filter"} onClick={() => setStoreFilter("rare")}>Rare</span>
              <span className={storeFilter === "epic" ? "filter active" : "filter"} onClick={() => setStoreFilter("epic")}>Epic</span>
              <span className={storeFilter === "legendary" ? "filter active" : "filter"} onClick={() => setStoreFilter("legendary")}>Legendary</span>
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
                    className={`match-card ${selectedMatch === match.matchId ? "selected" : ""} ${normalizeMatchStatus(match.status) === "completed" ? "grayscale-card" : ""}`}
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
                        <div className="match-card-content">
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
                      </div>
                    ) : (
                      <div className="match-card-overlay">
                        <div className="match-card-content">
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
                {storeItems
                  .filter((item) => storeFilter === "all" || item.tier === storeFilter)
                  .map((item) => {
                    const isOwned = item.id === "s-default" || item.id === "s-default-unshaded" || (item.onChainId && ownedSkinIds.includes(item.onChainId));
                    const itemSupply = item.onChainId ? supplyData[item.onChainId] : null;
                    return (
                    <div
                      key={item.id}
                      className={`store-card ${isOwned ? "owned" : "unowned"} ${selectedStore === item.id ? "selected" : ""}`}
                      onClick={() => setSelectedStore(item.id)}
                    >
                      <div className="store-card-image" style={{ backgroundImage: `url(${getStoreImageUrl(item)})` }}>
                        {!isOwned && (
                          <span className="item-badge badge-store">new</span>
                        )}
                        {item.badge && (
                          <span className="item-badge badge-store badge-new">{item.badge}</span>
                        )}
                      </div>
                      <div className="store-card-info">
                        <h3>{item.name}</h3>
                        <p>
                          {isOwned ? "Owned" : item.price}
                        </p>
                        {item.tier && (
                          <span className={`store-tier store-tier--${item.tier}`}>{item.tier}</span>
                        )}
                        {itemSupply && (
                          <p className="store-supply">{itemSupply.minted}/{itemSupply.maxSupply} minted</p>
                        )}
                        {item.requiredXP > 0 && !isOwned && (
                          <p className={`xp-requirement ${xpBalance >= item.requiredXP ? "xp-met" : "xp-needed"}`}>
                            Lvl {getLevelFromXP(item.requiredXP)} required
                          </p>
                        )}
                      </div>
                    </div>
                    );
                  })}
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
          {mintError && (
            <div className="mint-error">{mintError}</div>
          )}
          <button
            className="play-btn-fixed"
            disabled={isMinting || (!isSelectedStoreOwned && !hasEnoughXP)}
            onClick={async () => {
              if (!currentStoreItem || !user) return;
              if (isSelectedStoreOwned) {
                setEquippedSkin(currentStoreItem);
                setEquipFlash(true);
                setTimeout(() => setEquipFlash(false), 500);
                updateUserEquippedSkin(getUsernameFromPrivy(user), currentStoreItem.id).then(() => {
                  showSuccessToast(`${currentStoreItem.name} equipped!`);
                }).catch((error: any) => {
                  console.error("Failed to save equipped skin", error);
                  showErrorToast("Failed to equip skin.");
                });
                setSelectedStore(null);
                return;
              }
              if (!currentStoreItem.onChainId) return;
              setMintError(null);
              setIsMinting(true);
              try {
                const ethWallet = wallets.find(
                  (w) => w.walletClientType === "privy" || w.chainType === "ethereum"
                );
                if (!ethWallet) {
                  setMintError("No Ethereum wallet connected");
                  setIsMinting(false);
                  return;
                }
                const providerSource = await ethWallet.getEthereumProvider();
                if (!providerSource) {
                  setMintError("Wallet provider not available");
                  setIsMinting(false);
                  return;
                }
                const browserProvider = new ethers.BrowserProvider(providerSource);
                const signer = await browserProvider.getSigner();
                const contractAddress = import.meta.env.VITE_SKINS_CONTRACT_ADDRESS;
                if (!contractAddress) {
                  setMintError("Skins contract not configured");
                  setIsMinting(false);
                  return;
                }
                const contract = new ethers.Contract(contractAddress, SKINS_ABI, signer);
                const priceWei = ethers.parseUnits(
                  currentStoreItem.price.replace(" MON", ""),
                  18
                );
                const tx = await contract.mintSkin(currentStoreItem.onChainId, 1, {
                  value: priceWei
                });
                await tx.wait();
                setOwnedSkinIds((prev) => [...prev, currentStoreItem.onChainId]);
                setSelectedStore(null);
                showSuccessToast(`${currentStoreItem.name} minted successfully!`);
              } catch (error: any) {
                console.error("Mint failed:", error);
                showErrorToast(error?.reason || error?.message || "Mint failed");
                setMintError(error?.reason || error?.message || "Mint failed");
              } finally {
                setIsMinting(false);
              }
            }}
          >
            {isMinting ? "MINTING..." : isSelectedStoreOwned ? "EQUIP" : hasEnoughXP ? "MINT" : `Need Lvl ${selectedItemLevel}`}
          </button>
          {isSelectedStoreOwned && (
            <button
              type="button"
              className="discord-btn-fixed"
              onClick={() => {
                if (!currentStoreItem) return;
                setEquippedSkin(currentStoreItem);
                setEquipFlash(true);
                setTimeout(() => setEquipFlash(false), 500);
                updateUserEquippedSkin(getUsernameFromPrivy(user), currentStoreItem.id).then(() => {
                  showSuccessToast(`${currentStoreItem.name} equipped!`);
                }).catch((error: any) => {
                  console.error("Failed to save equipped skin", error);
                  showErrorToast("Failed to equip skin.");
                });
                setSelectedStore(null);
              }}
              aria-label={`Equip ${currentStoreItem.name}`}
              title={`Equip ${currentStoreItem.name}`}
            >
              <img src="/mon.png" alt="Mon" style={{ width: 28, height: 28 }} />
            </button>
          )}
        </div>
      )}
        </div>
      )}
    </>
  );
}
