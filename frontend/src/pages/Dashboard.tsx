import React, { useEffect, useState, useRef } from "react";
import { usePrivy } from "@privy-io/react-auth";
import { useNavigate } from "react-router-dom";
import { FullScreenLoader } from "../components/ui/fullscreen-loader";
import "./Dashboard.css";

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
      if (start >= end) {
        start = end;
        clearInterval(interval);
      }
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
    { id: 1, sponsor: "Kitio Labs", logo: "/w.png", reward: "5,000 WONs", status: "upcoming", time: "Starts in 3h", button: "Join" },
    { id: 2, sponsor: "Monad Testnet", logo: "/w.png", reward: "10,000 WONs", status: "upcoming", time: "Starts in 5h", button: "Join" },
    { id: 3, sponsor: "Codigo DAO", logo: "/w.png", reward: "3,000 WONs", status: "ended", time: "Ended - 1h Ago", button: "Results" },
    { id: 4, sponsor: "Aptos Arena", logo: "/w.png", reward: "7,500 WONs", status: "upcoming", time: "Starts in 6h", button: "Join" },
    { id: 5, sponsor: "Zeta Labs", logo: "/w.png", reward: "4,000 WONs", status: "ended", time: "Ended - Yesterday", button: "Results" },
    { id: 6, sponsor: "Covalent Clash", logo: "/w.png", reward: "2,000 WONs", status: "upcoming", time: "Starts Tomorrow", button: "Join" },
    { id: 7, sponsor: "Celestia League", logo: "/w.png", reward: "1,000 WONs", status: "ended", time: "Ended - 3h Ago", button: "Results" },
    { id: 8, sponsor: "Linea Quest", logo: "/w.png", reward: "8,000 WONs", status: "upcoming", time: "Starts Tomorrow", button: "Join" },
    // ✅ Only one live match with Play
    { id: 9, sponsor: "World of Nads", logo: "/w.png", reward: "50,000 WONs", status: "live", time: "Live Now", button: "Play" },
    { id: 10, sponsor: "Sui Challenge", logo: "/w.png", reward: "6,000 WONs", status: "ended", time: "Ended - 1 Day Ago", button: "Results" },
    { id: 11, sponsor: "Polygon Labs", logo: "/w.png", reward: "3,500 WONs", status: "upcoming", time: "Starts in 4h", button: "Join" },
    { id: 12, sponsor: "Optimism Game", logo: "/w.png", reward: "9,000 WONs", status: "ended", time: "Ended - 2 Days Ago", button: "Results" },
    { id: 13, sponsor: "Base Quest", logo: "/w.png", reward: "12,000 WONs", status: "upcoming", time: "Starts in 1h", button: "Join" },
    { id: 14, sponsor: "Blast Arena", logo: "/w.png", reward: "5,500 WONs", status: "upcoming", time: "Starts Soon", button: "Join" },
    { id: 15, sponsor: "Arbitrum Cup", logo: "/w.png", reward: "2,500 WONs", status: "ended", time: "Ended - 4h Ago", button: "Results" },
    { id: 16, sponsor: "Scroll League", logo: "/w.png", reward: "10,000 WONs", status: "upcoming", time: "Starts in 3h", button: "Join" },
    { id: 17, sponsor: "Taiko Trials", logo: "/w.png", reward: "11,000 WONs", status: "ended", time: "Ended - 2 Days Ago", button: "Results" },
    { id: 18, sponsor: "Degen Wars", logo: "/w.png", reward: "20,000 WONs", status: "upcoming", time: "Starts in 12h", button: "Join" },
    { id: 19, sponsor: "Mantle Clash", logo: "/w.png", reward: "13,000 WONs", status: "upcoming", time: "Starts Tonight", button: "Join" },
    { id: 20, sponsor: "StarkNet Battle", logo: "/w.png", reward: "15,000 WONs", status: "ended", time: "Ended - 3 Days Ago", button: "Results" },
  ];

  const liveMatch = matches.find((m) => m.status === "live");

  useEffect(() => {
    const container = scrollRef.current;
    if (!container) return;

    const liveIndex = matches.findIndex((m) => m.status === "live");
    if (liveIndex === -1) return;

    const cardWidth = 280;
    container.scrollTo({
      left: liveIndex * cardWidth,
      behavior: "smooth",
    });
  }, []);

  return (
    <div className="dashboard-container">
      {/* --- Profile Section --- */}
      <div className="profile-section">
        <img
          src={twitter?.profilePictureUrl || "/default-avatar.png"}
          alt="Profile"
          className="profile-picture"
        />
        <h2 className="username">{twitter?.name || "Player"}</h2>
        <p className="user-handle">@{twitter?.username}</p>

        {/* --- Connected Wallets --- */}
        <div className="wallets-section">
          {wallets.length > 0 ? (
            wallets.map((w, i) => (
              <div
                key={i}
                className="wallet-item"
                onClick={() => copyToClipboard(w.address)}
                title="Click to copy"
              >
                {truncateAddress(w.address)}
              </div>
            ))
          ) : (
            <p className="no-wallet">No wallet connected</p>
          )}
        </div>

        <div className="won-balance">
          <span>🏅 {earned.toLocaleString()} WONs Earned</span>
        </div>
      </div>

      {/* --- Matches Section --- */}
      <div className="matches-scroll" ref={scrollRef}>
        {matches.map((m) => (
          <div key={m.id} className={`match-card ${m.status}`}>
            <div className="sponsor-info">
              <img src={m.logo} alt={m.sponsor} className="sponsor-logo" />
              <h3>{m.sponsor}</h3>
            </div>
            <div className="match-details">
              <p className="reward">{m.reward}</p>
              <p className="time">{m.time}</p>
            </div>
            {m.id === liveMatch?.id && (
              <button
                className={`match-button ${m.status}`}
                onClick={() => navigate("/play")}
              >
                {m.button}
              </button>
            )}
          </div>
        ))}
      </div>

      <button className="logout-button" onClick={logout}>
        Logout
      </button>
    </div>
  );
};

export default Dashboard;
