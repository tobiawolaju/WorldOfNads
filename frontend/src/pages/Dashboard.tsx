import React, { useEffect, useState, useRef } from "react";
import { usePrivy } from "@privy-io/react-auth";
import { useNavigate } from "react-router-dom";
import { FullScreenLoader } from "../components/ui/fullscreen-loader";
import { ThreeScene } from "../components/ThreeScene";
import "./Dashboard.css";

// ↓ Types
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

  // Animate earned
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

  // Cleanup
  useEffect(() => {
    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current);
      if (navigationTimeoutRef.current) clearTimeout(navigationTimeoutRef.current);
    };
  }, []);

  const handlePlayClick = () => {
    if (!selectedMatch) return;

    if (playButtonState === "idle") {
      setPlayButtonState("counting");
      setElapsedTime(0);

      intervalRef.current = setInterval(() => {
        setElapsedTime(prev => prev + 0.1);
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

  const twitter = user.linkedAccounts?.find(acc => acc.type === "twitter_oauth") as Twitter | undefined;
  const wallets = (user.linkedAccounts?.filter(acc => acc.type === "wallet") || []) as Wallet[];

  // MATCHES
  const matches: Match[] = [
    {
      id: 9,
      sponsor: "World of Nads",
      reward: "50,000 WONs",
      status: "live",
      time: "Live Now",
      image: "logos/card.jpg",
      description: "A chaotic arena where agility and strategy collide in every round.",
      url: "https://twitter.com/worldofnads"
    },
    {
      id: 10,
      sponsor: "Iron Legion Arena",
      reward: "22,000 WONs",
      status: "live",
      time: "Live Now",
      image: "logos/card.jpg",
      description: "Metal, might, and mechanical warriors in a high-stakes showdown.",
      url: "https://twitter.com/ironlegionarena"
    },
    {
      id: 11,
      sponsor: "House of Havoc",
      reward: "14,500 WONs",
      status: "live",
      time: "Live Now",
      image: "logos/card.jpg",
      description: "Pure destruction and unpredictable matchups inside the Havoc halls.",
      url: "https://twitter.com/houseofhavoc"
    },
    {
      id: 1,
      sponsor: "Kitio Labs",
      reward: "5,000 WONs",
      status: "upcoming",
      time: "Starts in 3h",
      image: "logos/card.jpg",
      description: "Experimental combat simulations powered by cutting-edge tech.",
      url: "https://twitter.com/kitiolabs"
    },
    {
      id: 2,
      sponsor: "Monad Testnet",
      reward: "10,000 WONs",
      status: "upcoming",
      time: "Starts in 5h",
      image: "logos/card.jpg",
      description: "High-speed duels hosted on next-gen blockchain infrastructure.",
      url: "https://twitter.com/monad_xyz"
    },
    {
      id: 3,
      sponsor: "Astra Robotics",
      reward: "7,500 WONs",
      status: "upcoming",
      time: "Tomorrow 14:00",
      image: "logos/card.jpg",
      description: "Precision robotic challengers engineered for flawless combat.",
      url: "https://twitter.com/astrarobotics"
    },
    {
      id: 4,
      sponsor: "Covenant Core",
      reward: "25,000 WONs",
      status: "upcoming",
      time: "Tomorrow 18:30",
      image: "logos/card.jpg",
      description: "Strategic alliances clash in a battle of factions and power.",
      url: "https://twitter.com/covenantcore"
    },
    {
      id: 5,
      sponsor: "NOVA Protocol",
      reward: "13,000 WONs",
      status: "upcoming",
      time: "In 2 Days",
      image: "logos/card.jpg",
      description: "A cosmic-themed arena where energy, timing, and skill decide all.",
      url: "https://twitter.com/novaprotocol"
    },
    {
      id: 6,
      sponsor: "EtherGuard Guild",
      reward: "9,800 WONs",
      status: "upcoming",
      time: "In 3 Days",
      image: "logos/card.jpg",
      description: "Guardians of the digital realm face off in tactical matchups.",
      url: "https://twitter.com/etherguardguild"
    },
    {
      id: 7,
      sponsor: "Blocksmith Arena",
      reward: "6,400 WONs",
      status: "completed",
      time: "Completed",
      image: "logos/card.jpg",
      description: "Forged champions battled in a handcrafted arena of steel and code.",
      url: "https://twitter.com/blocksmitharena"
    },
    {
      id: 8,
      sponsor: "Elysium Works",
      reward: "18,200 WONs",
      status: "completed",
      time: "Completed",
      image: "logos/card.jpg",
      description: "A serene battlefield where elegance meets efficient destruction.",
      url: "https://twitter.com/elysiumworks"
    },
    {
      id: 12,
      sponsor: "MEGA Labs Clash",
      reward: "33,000 WONs",
      status: "completed",
      time: "Completed",
      image: "logos/card.jpg",
      description: "Massive-scale prototypes unleashed in an ultimate tech duel.",
      url: "https://twitter.com/megalabs"
    },
    {
      id: 13,
      sponsor: "Dark Circuit League",
      reward: "20,000 WONs",
      status: "completed",
      time: "Completed",
      image: "logos/card.jpg",
      description: "Shadow-tier competitors fought through electrifying circuits.",
      url: "https://twitter.com/darkcircuitleague"
    },
    {
      id: 14,
      sponsor: "CryptoThrone Trials",
      reward: "42,000 WONs",
      status: "completed",
      time: "Completed",
      image: "logos/card.jpg",
      description: "Only the strongest contenders advanced toward the digital throne.",
      url: "https://twitter.com/cryptothronetrials"
    }
  ];

  const filteredMatches = matches.filter(m => m.status === filter);

  const updateSelectedCard = () => {
    if (isManuallyScrolling.current) return;

    const carousel = carouselRef.current;
    if (!carousel) return;

    const cards = Array.from(carousel.children) as HTMLElement[];
    const centerX = carousel.getBoundingClientRect().left + carousel.offsetWidth / 2;

    let closest: HTMLElement | null = null;
    let min = Infinity;

    cards.forEach(card => {
      const dist = Math.abs((card.getBoundingClientRect().left + card.offsetWidth / 2) - centerX);
      if (dist < min) {
        min = dist;
        closest = card;
      }
    });

    if (closest) setSelectedMatch(Number(closest.dataset.id));
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
          <div className={tab === "events" ? "tab active" : "tab"} onClick={() => setTab("events")}>Events</div>
          <div className={tab === "results" ? "tab active" : "tab"} onClick={() => setTab("results")}>Results</div>
        </div>

        <div className="filters">
          <span className={filter === "upcoming" ? "filter active" : "filter"} onClick={() => setFilter("upcoming")}>Upcoming</span>
          <span className={filter === "live" ? "filter active" : "filter"} onClick={() => setFilter("live")}>Live</span>
          <span className={filter === "completed" ? "filter active" : "filter"} onClick={() => setFilter("completed")}>Completed</span>
        </div>

        <div className="matches-wrapper">
          <div className="matches-carousel" ref={carouselRef}>
            {filteredMatches.map(m => (
              <div
                key={m.id}
                data-id={m.id}
                className={`match-card ${selectedMatch === m.id ? "selected" : ""}`}
                style={{ backgroundImage: `url(${m.image})` }}
                onClick={(e) => {
                  const card = e.currentTarget;
                  const carousel = carouselRef.current;
                  if (!carousel) return;
                  const target = card.offsetLeft - (carousel.offsetWidth / 2) + (card.offsetWidth / 2);
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

        {/* --- MATCH DETAILS SECTION --- */}
        <div className="match-details">
          {selectedMatch ? (
            (() => {
              const match = matches.find(m => m.id === selectedMatch);
              if (!match) return null;

              return (
                <div className="match-details-box">
                  <h2 className="match-details-title">{match.sponsor}</h2>

                  <p className="match-details-description">{match.description}</p>

                  <a
                    href={match.url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="match-details-twitter"
                  >
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
        className={`play-fixed ${selectedMatch ? "active" : "disabled"} ${playButtonState === "counting" ? "counting" : ""}`}
        onClick={handlePlayClick}
        disabled={!selectedMatch}
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
