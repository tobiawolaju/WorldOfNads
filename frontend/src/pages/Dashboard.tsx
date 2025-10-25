import React, { useEffect, useState, useRef } from "react";
import { usePrivy } from "@privy-io/react-auth";
import { useNavigate } from "react-router-dom";
import { FullScreenLoader } from "../components/ui/fullscreen-loader";
import { Canvas } from "@react-three/fiber";
import { OrbitControls, Html } from "@react-three/drei";
import "./Dashboard.css";

// Interfaces for our data structures
interface Twitter {
  profilePictureUrl?: string;
  name?: string;
  username?: string;
  type?: "twitter_oauth"; // Added for better type guarding
}

interface Wallet {
  address: string;
  type?: "wallet"; // Added for better type guarding
}

// A union type for more precise account handling
type LinkedAccount = (Twitter | Wallet) & { type: string };

interface User {
  linkedAccounts?: LinkedAccount[];
}

interface Match {
  id: number;
  sponsor: string;
  reward: string;
  status: "live" | "upcoming" | "completed";
  time: string;
}

// Props for the IdCard component
interface IdCardProps {
  twitter: Twitter | undefined;
  wallets: Wallet[];
  earned: number;
  onLogout: () => void;
}

const IdCard: React.FC<IdCardProps> = ({ twitter, wallets, earned, onLogout }) => (
  <mesh rotation={[0.4, 0.6, 0]}>
    <boxGeometry args={[4, 2.5, 0.1]} />
    <meshStandardMaterial color="rgba(255, 255, 255, 0)ff" />
    <Html
      transform
      occlude
      position={[0, 0, 0.6]}
      style={{
        width: '300px',
        userSelect: 'none',
      }}
    >
      <div className="id-card-container">
        <img src={twitter?.profilePictureUrl || "/default-avatar.png"} className="id-card-avatar" alt="Avatar" />
        <div className="id-card-name">{twitter?.name || "Player"}</div>
        <div className="id-card-handle">@{twitter?.username}</div>
        <div className="id-card-wallets">
          {wallets.map((w, i) => <div key={i}>{w.address.slice(0, 6)}...{w.address.slice(-4)}</div>)}
        </div>
        <div className="id-card-earned">{earned.toLocaleString()} WONs Earned</div>
        <button className="id-card-logout-button" onClick={onLogout}>
          Logout
        </button>
      </div>
    </Html>
  </mesh>
);

// The return type is removed here - No more red line!
export default function Dashboard() {
  const { ready, authenticated, user, logout } = usePrivy();
  const navigate = useNavigate();
  const [earned, setEarned] = useState<number>(0);
  const [selectedMatch, setSelectedMatch] = useState<number | null>(null);

  const [tab, setTab] = useState<"events" | "results">("events");
  const [filter, setFilter] = useState<"upcoming" | "live" | "completed">("upcoming");

  const carouselRef = useRef<HTMLDivElement>(null);
  const isManuallyScrolling = useRef<boolean>(false);
  const scrollTimeout = useRef<NodeJS.Timeout | null>(null);

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

  if (!ready) return <FullScreenLoader />;
  if (!authenticated || !user) return null;

  const twitter = user.linkedAccounts?.find((acc) => acc.type === "twitter_oauth") as Twitter | undefined;
  const wallets = (user.linkedAccounts?.filter((acc) => acc.type === "wallet") || []) as Wallet[];

  const matches: Match[] = [
    { id: 9, sponsor: "World of Nads", reward: "50,000 WONs", status: "live", time: "Live Now" },
    { id: 10, sponsor: "Iron Legion Arena", reward: "22,000 WONs", status: "live", time: "Live Now" },
    { id: 11, sponsor: "House of Havoc", reward: "14,500 WONs", status: "live", time: "Live Now" },
    { id: 1, sponsor: "Kitio Labs", reward: "5,000 WONs", status: "upcoming", time: "Starts in 3h" },
    { id: 2, sponsor: "Monad Testnet", reward: "10,000 WONs", status: "upcoming", time: "Starts in 5h" },
    { id: 3, sponsor: "Astra Robotics", reward: "7,500 WONs", status: "upcoming", time: "Tomorrow 14:00" },
    { id: 4, sponsor: "Covenant Core", reward: "25,000 WONs", status: "upcoming", time: "Tomorrow 18:30" },
    { id: 5, sponsor: "NOVA Protocol", reward: "13,000 WONs", status: "upcoming", time: "In 2 Days" },
    { id: 6, sponsor: "EtherGuard Guild", reward: "9,800 WONs", status: "upcoming", time: "In 3 Days" },
    { id: 7, sponsor: "Blocksmith Arena", reward: "6,400 WONs", status: "completed", time: "Completed" },
    { id: 8, sponsor: "Elysium Works", reward: "18,200 WONs", status: "completed", time: "Completed" },
    { id: 12, sponsor: "MEGA Labs Clash", reward: "33,000 WONs", status: "completed", time: "Completed" },
    { id: 13, sponsor: "Dark Circuit League", reward: "20,000 WONs", status: "completed", time: "Completed" },
    { id: 14, sponsor: "CryptoThrone Trials", reward: "42,000 WONs", status: "completed", time: "Completed" }
  ];

  const filteredMatches = matches.filter(m => m.status === filter);

  const updateSelectedCard = () => {
    if (isManuallyScrolling.current) return;

    const carousel = carouselRef.current;
    if (!carousel) return;

    const cards = Array.from(carousel.children) as HTMLElement[];
    const rect = carousel.getBoundingClientRect();
    const centerX = rect.left + rect.width / 2;

    let closestCard: HTMLElement | undefined;
    let minDistance = Infinity;

    cards.forEach(card => {
      const cardRect = card.getBoundingClientRect();
      const cardCenter = cardRect.left + cardRect.width / 2;
      const distance = Math.abs(centerX - cardCenter);

      if (distance < minDistance) {
        minDistance = distance;
        closestCard = card;
      }
    });

    if (closestCard) {
      const id = Number(closestCard.getAttribute("data-id"));
      setSelectedMatch(id);
    }
  };

  useEffect(() => {
    const carousel = carouselRef.current;
    if (!carousel) return;

    const handleScroll = () => {
      if (scrollTimeout.current) {
        clearTimeout(scrollTimeout.current);
      }
      scrollTimeout.current = setTimeout(updateSelectedCard, 150);
    };

    carousel.addEventListener("scroll", handleScroll);
    updateSelectedCard();

    return () => {
      carousel.removeEventListener("scroll", handleScroll);
      if (scrollTimeout.current) {
        clearTimeout(scrollTimeout.current);
      }
    };
  }, [filter]);

  return (
    <div className="dashboard-wrapper">
      <div className="left-3d-section">
        <Canvas camera={{ position: [8, 8, 8] }}>
          <ambientLight intensity={1.2} />
          <directionalLight position={[5, 5, 5]} intensity={1.2} />
          <IdCard twitter={twitter} wallets={wallets} earned={earned} onLogout={logout} />
          <OrbitControls enableZoom={false} enablePan={false} />
        </Canvas>
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

        <div className="matches-carousel" ref={carouselRef}>
          {filteredMatches.map(m => (
            <div
              key={m.id}
              data-id={m.id}
              className={`match-card ${selectedMatch === m.id ? "selected" : ""}`}
              onClick={(e: React.MouseEvent<HTMLDivElement>) => {
                const cardElement = e.currentTarget;
                cardElement.scrollIntoView({ behavior: "smooth", inline: "center" });
                isManuallyScrolling.current = true;
                setSelectedMatch(m.id);
                if (scrollTimeout.current) {
                  clearTimeout(scrollTimeout.current);
                }
                scrollTimeout.current = setTimeout(() => {
                  isManuallyScrolling.current = false;
                }, 800);
              }}
            >
              <h3>{m.sponsor}</h3>
              <p className="reward">{m.reward}</p>
              <p className="time">{m.time}</p>
            </div>
          ))}
        </div>
      </div>

      <button
        className={`play-fixed ${selectedMatch ? "active" : "disabled"}`}
        onClick={() => selectedMatch && navigate("/play")}
      >
        <span>PLAY</span>
      </button>
    </div>
  );
}