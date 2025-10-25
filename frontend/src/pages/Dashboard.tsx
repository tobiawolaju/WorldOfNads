import React, { useEffect, useState } from "react";
import { usePrivy } from "@privy-io/react-auth";
import { useNavigate } from "react-router-dom";
import { FullScreenLoader } from "../components/ui/fullscreen-loader";
import { Canvas } from "@react-three/fiber";
import { OrbitControls } from "@react-three/drei";
import "./Dashboard.css";

const Character = () => (
  <mesh rotation={[0.4, 0.6, 0]}>
    <boxGeometry args={[1.4, 2, 1.4]} />
    <meshStandardMaterial color="#a000ff" metalness={0.4} roughness={0.3} />
  </mesh>
);

export default function Dashboard() {
  const { ready, authenticated, user, logout } = usePrivy();
  const navigate = useNavigate();
  const [earned, setEarned] = useState(0);
  const [selectedMatch, setSelectedMatch] = useState<number | null>(null);

  const [tab, setTab] = useState<"events" | "results">("events");
  const [filter, setFilter] = useState<"upcoming" | "live" | "completed">("upcoming");

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
  }, []);

  if (!ready) return <FullScreenLoader />;
  if (!authenticated || !user) return null;

  const twitter = user.linkedAccounts?.find((acc) => acc.type === "twitter_oauth");
  const wallets = user.linkedAccounts?.filter((acc) => acc.type === "wallet") || [];
  const truncateAddress = (addr: string) => addr.slice(0, 6) + "..." + addr.slice(-4);

const matches = [
  // --- LIVE EVENTS ---
  { id: 9, sponsor: "World of Nads", reward: "50,000 WONs", status: "live", time: "Live Now" },
  { id: 10, sponsor: "Iron Legion Arena", reward: "22,000 WONs", status: "live", time: "Live Now" },
  { id: 11, sponsor: "House of Havoc", reward: "14,500 WONs", status: "live", time: "Live Now" },

  // --- UPCOMING EVENTS ---
  { id: 1, sponsor: "Kitio Labs", reward: "5,000 WONs", status: "upcoming", time: "Starts in 3h" },
  { id: 2, sponsor: "Monad Testnet", reward: "10,000 WONs", status: "upcoming", time: "Starts in 5h" },
  { id: 3, sponsor: "Astra Robotics", reward: "7,500 WONs", status: "upcoming", time: "Tomorrow 14:00" },
  { id: 4, sponsor: "Covenant Core", reward: "25,000 WONs", status: "upcoming", time: "Tomorrow 18:30" },
  { id: 5, sponsor: "NOVA Protocol", reward: "13,000 WONs", status: "upcoming", time: "In 2 Days" },
  { id: 6, sponsor: "EtherGuard Guild", reward: "9,800 WONs", status: "upcoming", time: "In 3 Days" },

  // --- COMPLETED EVENTS ---
  { id: 7, sponsor: "Blocksmith Arena", reward: "6,400 WONs", status: "completed", time: "Completed" },
  { id: 8, sponsor: "Elysium Works", reward: "18,200 WONs", status: "completed", time: "Completed" },
  { id: 12, sponsor: "MEGA Labs Clash", reward: "33,000 WONs", status: "completed", time: "Completed" },
  { id: 13, sponsor: "Dark Circuit League", reward: "20,000 WONs", status: "completed", time: "Completed" },
  { id: 14, sponsor: "CryptoThrone Trials", reward: "42,000 WONs", status: "completed", time: "Completed" }
];


  const filteredMatches = matches.filter(m => m.status === filter);

  return (
    <div className="dashboard-wrapper">

      {/* FIXED PLAYER PANEL */}
      <div className="fixed-player-info">
        <img src={twitter?.profilePictureUrl || "/default-avatar.png"} className="label-avatar" />
        <div className="label-name">{twitter?.name || "Player"}</div>
        <div className="label-handle">@{twitter?.username}</div>

        <div className="label-wallets">
          {wallets.map((w, i) => <div key={i}>{truncateAddress(w.address)}</div>)}
        </div>

        <div className="label-earned">{earned.toLocaleString()} WONs Earned</div>
        <button className="logout-button-fixed" onClick={logout}>Logout</button>
      </div>

      {/* 3D CHARACTER VIEW */}
      <div className="left-3d-section">
        <Canvas camera={{ position: [3, 3, 4] }}>
          <ambientLight intensity={1.2} />
          <directionalLight position={[5, 5, 5]} intensity={1.2} />
          <Character />
          <OrbitControls enableZoom={false} enablePan={false} />
        </Canvas>
      </div>

      {/* RIGHT PANEL */}
      <div className="right-info-section">
        
        {/* Tabs */}
        <div className="tabs">
          <div className={tab === "events" ? "tab active" : "tab"} onClick={() => setTab("events")}>Events</div>
          <div className={tab === "results" ? "tab active" : "tab"} onClick={() => setTab("results")}>Results</div>
        </div>

        {/* Filters */}
        <div className="filters">
          <span className={filter === "upcoming" ? "filter active" : "filter"} onClick={() => setFilter("upcoming")}>Upcoming</span>
          <span className={filter === "live" ? "filter active" : "filter"} onClick={() => setFilter("live")}>Live</span>
          <span className={filter === "completed" ? "filter active" : "filter"} onClick={() => setFilter("completed")}>Completed</span>
        </div>

        <div className="matches-carousel">
          {filteredMatches.map(m => (
            <div
              key={m.id}
              className={`match-card ${selectedMatch === m.id ? "selected" : ""}`}
              onClick={() => setSelectedMatch(m.id)}
            >
              <h3>{m.sponsor}</h3>
              <p className="reward">{m.reward}</p>
              <p className="time">{m.time}</p>
            </div>
          ))}
        </div>

      </div>

      {/* PLAY BUTTON */}
      <button
        className={`play-fixed ${selectedMatch ? "active" : "disabled"}`}
        onClick={() => selectedMatch && navigate("/play")}
      >
        <span>PLAY</span>
      </button>

    </div>
  );
}
