import React from "react";
import { useNavigate } from "react-router-dom";
import { usePrivy } from "@privy-io/react-auth";
import "./Home.css";

const Home: React.FC = () => {
  const { ready, authenticated, login } = usePrivy();
  const navigate = useNavigate();

  const btnBase: React.CSSProperties = {
    width: "auto",
    height: "50px",
    border: "none",
    borderRadius: "50px",
    margin: "10px",
    cursor: "pointer",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    fontSize: "20px",
    textDecoration: "none",
    padding: "5px 30px",
    fontFamily: "Font1",
  };

  const discordBtn: React.CSSProperties = {
    ...btnBase,
    backgroundColor: "#907cff",
    color: "#ffffff",
  };

  const playBtn: React.CSSProperties = {
    ...btnBase,
    backgroundColor: "#907cff",
    color: "#ffffff",
    position: "relative",
    overflow: "hidden",
    border: "2px solid #d9ceff",
  };

  const handlePlay = async (): Promise<void> => {
    try {
      if (!authenticated) {
        await login();
      }
      navigate("/dashboard");
    } catch (err) {
      console.error("Login failed:", err);
    }
  };

  if (!ready) return <div>Loading...</div>;

  return (
    <div
      className="home-container"
      style={{
        backgroundColor: "#ffffff",
        color: "#000000",
        minHeight: "100vh",
        display: "flex",
        flexDirection: "column",
        justifyContent: "space-between",
      }}
    >
      {/* Centered Section */}
      <div
        className="hero-center"
        style={{
          flex: 1,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        <h1 className="title" style={{ fontFamily: "Font2", fontSize: "48px" }}>
          1.2k Nads
        </h1>
      </div>

      {/* Footer Section */}
      <footer
        style={{
          padding: "10px",
          color: "rgba(0, 0, 0, 0.51)",
          textAlign: "center",
          fontSize: "medium",
          position: "relative",
        }}
      >
        &copy; {new Date().getFullYear()} WON – All rights reserved

        {/* Button container */}
        <div className="footer-buttons">
          <a
            href="https://discord.gg/z4SUdrKayb"
            target="_blank"
            rel="noopener noreferrer"
            style={discordBtn}
            className="discord-btn"
            title="Join Discord"
          >
            Discord
          </a>

          <button
            onClick={handlePlay}
            style={playBtn}
            className="play-btn"
            title="Play"
          >
            <span className="stars"></span>
            <span>{authenticated ? "Lobby" : "Login"}</span>
          </button>
        </div>

        {/* Inline Styles */}
        <style>
          {`
            .footer-buttons {
              position: fixed;
              bottom: 20px;
              display: flex;
              flex-direction: row;
            }

            @media (min-width: 768px) {
              .footer-buttons {
                right: 20px;
                left: auto;
                justify-content: flex-end;
              }
            }

            @media (max-width: 767px) {
              .footer-buttons {
                left: 50%;
                transform: translateX(-50%);
                right: auto;
                justify-content: center;
              }
            }

            /* PLAY BUTTON EFFECTS */
            .play-btn {
              position: relative;
              overflow: hidden;
              animation: pulseScale 2.4s ease-in-out infinite alternate;
              box-shadow: 0 0 20px #907cff;
              z-index: 1;
            }

            @keyframes pulseScale {
              0% { transform: scale(0.95); }
              100% { transform: scale(1); }
            }

            /* STAR BACKGROUND LAYER */
            .play-btn .stars {
              position: absolute;
              inset: 0;
              background: radial-gradient(circle at 20% 30%, rgba(255,255,255,0.2) 0%, transparent 40%),
                          radial-gradient(circle at 80% 60%, rgba(255,158,242,0.2) 0%, transparent 20%),
                          radial-gradient(circle at 50% 80%, rgba(255,158,242,0.15) 0%, transparent 20%);
              background-size: 200% 200%;
              animation: twinkle 4s infinite ease-in-out alternate;
              border-radius: 50px;
              z-index: 0;
              filter: blur(0);
              pointer-events: none;
            }

            @keyframes twinkle {
              0% {
                opacity: 0.6;
                background-position: 0% 50%;
              }
              100% {
                opacity: 1;
                background-position: 100% 50%;
              }
            }

            /* TEXT ABOVE THE STARS */
            .play-btn span {
              position: relative;
              z-index: 1;
            }
          `}
        </style>
      </footer>
    </div>
  );
};

export default Home;
