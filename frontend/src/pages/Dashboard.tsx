import React from "react";
import { usePrivy } from "@privy-io/react-auth";
import { useNavigate } from "react-router-dom";
import { FullScreenLoader } from "../components/ui/fullscreen-loader";
import "./dashboard.css";

const Dashboard: React.FC = () => {
  const { ready, authenticated, user, logout } = usePrivy();
  const navigate = useNavigate();

  if (!ready) return <FullScreenLoader />;
  if (!authenticated || !user) return null;

  const twitter = user.linkedAccounts?.find((acc) => acc.type === "twitter_oauth");
  const wallets = user.linkedAccounts?.filter((acc) => acc.type === "wallet") || [];

  return (
    <div className="dashboard-container">
      <div className="dashboard-card">
      
      <div style={{display:"flex"}}>
          <img
          src={twitter?.profilePictureUrl || "/default-avatar.png"}
          alt="Profile"
          className="profile-picture"
        />
        <h2 className="username">
          {twitter?.name || "Player"} <span>@{twitter?.username}</span>
        </h2>
        </div>

      

        <div className="wallets-section">
          <h3 className="wallets-title">Connected Wallets</h3>
          {wallets.length > 0 ? (
            wallets.map((w, idx) => (
              <div className="wallet-item" key={idx}>
                <span>{w.chainType.toUpperCase()}</span>
                <code>{w.address}</code>
              </div>
            ))
          ) : (
            <p className="text-sm text-gray-400">No wallets connected</p>
          )}
        </div>

        <div className="balance-section">
          <span className="balance-label">Earned WONs</span>
          <span className="balance-value">30K WONs</span>
        </div>

        <div className="buttons">
          <button className="play-button" onClick={() => navigate("/play")}>
            ▶ Play
          </button>
          <button className="logout-button" onClick={logout}>
            Logout
          </button>
        </div>
      </div>

    </div>
  );
};

export default Dashboard;
