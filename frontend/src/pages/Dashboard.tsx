import React, { useEffect, useState, useRef } from "react";
import { usePrivy } from "@privy-io/react-auth";
import { useNavigate } from "react-router-dom";
import { FullScreenLoader } from "../components/ui/fullscreen-loader";
import { Canvas } from "@react-three/fiber";
import { OrbitControls } from "@react-three/drei";
import "./Dashboard.css";

const Cube = () => {
  return (
    <mesh rotation={[0.4, 0.6, 0]}>
      <boxGeometry args={[1.4, 1.4, 1.4]} />
      <meshStandardMaterial color="#a000ff" metalness={0.4} roughness={0.3} />
    </mesh>
  );
};

const Dashboard: React.FC = () => {
  const { ready, authenticated, user, logout } = usePrivy();
  const navigate = useNavigate();
  const [earned, setEarned] = useState(0);
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    let start = 0;
    const end = 30000;
    const duration = 1500;
    const stepTime = 15;
    const step = Math.ceil(end / (duration / stepTime));

    const interval = setInterval(() => {
      start += step;
      if (start >= end) { start = end; clearInterval(interval); }
      setEarned(start);
    }, stepTime);
  }, []);

  if (!ready) return <FullScreenLoader />;
  if (!authenticated || !user) return null;

  const twitter = user.linkedAccounts?.find((acc) => acc.type === "twitter_oauth");
  const wallets = user.linkedAccounts?.filter((acc) => acc.type === "wallet") || [];

  const truncateAddress = (addr: string) =>
    addr.slice(0, 6) + "..." + addr.slice(-4);

  const copyToClipboard = (text: string) => {
    navigator.clipboard.writeText(text);
    alert("Wallet address copied!");
  };

  const matches = [
    { id: 9, sponsor: "World of Nads", logo: "/w.png", reward: "50,000 WONs", status: "live", time: "Live Now", button: "Play" },
    { id: 1, sponsor: "Kitio Labs", logo: "/w.png", reward: "5,000 WONs", status: "upcoming", time: "Starts in 3h", button: "Join" },
    { id: 2, sponsor: "Monad Testnet", logo: "/w.png", reward: "10,000 WONs", status: "upcoming", time: "Starts in 5h", button: "Join" },
    // ...
  ];

  const liveMatch = matches.find((m) => m.status === "live");

  useEffect(() => {
    const container = scrollRef.current;
    if (!container) return;

    const liveIndex = matches.findIndex((m) => m.status === "live");
    if (liveIndex === -1) return;

    const cardWidth = 280;
    container.scrollTo({ left: liveIndex * cardWidth, behavior: "smooth" });
  }, []);

  return (
    <div className="dashboard-wrapper">
      {/* LEFT SIDE – Avatar + Stats */}
      <div className="left-panel">
        <div className="profile-section">
          <img
            src={twitter?.profilePictureUrl || "/default-avatar.png"}
            alt="Profile"
            className="profile-picture"
          />
          <h2 className="username">{twitter?.name || "Player"}</h2>
          <p className="user-handle">@{twitter?.username}</p>

          <div className="wallets-section">
            {wallets.length > 0 ? (
              wallets.map((w, i) => (
                <div key={i} className="wallet-item" onClick={() => copyToClipboard(w.address)}>
                  {truncateAddress(w.address)}
                </div>
              ))
            ) : (
              <p className="no-wallet">No wallet connected</p>
            )}
          </div>

          <div className="won-balance">🏅 {earned.toLocaleString()} WONs Earned</div>

          <button className="logout-button" onClick={logout}>Logout</button>
        </div>
      </div>

      {/* CENTER – Character Display */}
      <div className="character-view">
        <Canvas camera={{ position: [3, 3, 3] }}>
          <ambientLight intensity={1.2} />
          <directionalLight position={[5, 5, 5]} intensity={1.2} />
          <Cube />
          <OrbitControls enableZoom={false} />
        </Canvas>
      </div>

      {/* RIGHT – Matches */}
      <div className="matches-panel">
        <h2 className="mode-title">Matches</h2>

        <div className="matches-scroll" ref={scrollRef}>
          {matches.map((m) => (
            <div key={m.id} className={`match-card ${m.status}`}>
              <img src={m.logo} alt={m.sponsor} className="sponsor-logo" />
              <h3>{m.sponsor}</h3>
              <p className="reward">{m.reward}</p>
              <p className="time">{m.time}</p>

              {m.id === liveMatch?.id && (
                <button className="match-button live" onClick={() => navigate("/play")}>
                  Play
                </button>
              )}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};

export default Dashboard;
