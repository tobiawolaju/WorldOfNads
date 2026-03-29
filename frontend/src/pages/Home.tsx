import React, { useRef } from "react";
import { useNavigate } from "react-router-dom";
import { usePrivy } from "@privy-io/react-auth";
import "./Home.css";
import { FaDiscord } from "react-icons/fa";
import { useGSAP } from "@gsap/react";
import gsap from "gsap";

const Home: React.FC = () => {
  const { login, authenticated, ready } = usePrivy();
  const navigate = useNavigate();

  // Refs for buttons
  const discordBtnRef = useRef<HTMLAnchorElement>(null);
  const playBtnRef = useRef<HTMLButtonElement>(null);

  // Button hover animations
  useGSAP(() => {
    const hoverIn = (el: Element) =>
      gsap.to(el, { border: "8px solid rgba(255,255,255,0.2)", duration: 0.25 });

    const hoverOut = (el: Element) =>
      gsap.to(el, { border: "none", duration: 0.25 });

    const discordBtn = discordBtnRef.current;
    const playBtn = playBtnRef.current;

    if (discordBtn) {
      discordBtn.addEventListener("mouseenter", () => hoverIn(discordBtn));
      discordBtn.addEventListener("mouseleave", () => hoverOut(discordBtn));
    }

    if (playBtn) {
      playBtn.addEventListener("mouseenter", () => hoverIn(playBtn));
      playBtn.addEventListener("mouseleave", () => hoverOut(playBtn));
    }
  }, []);

  const btnBase: React.CSSProperties = {
    width: "120px",
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
    fontWeight: "bold",
  };

  const discordBtn: React.CSSProperties = {
    ...btnBase,
    backgroundColor: "#907cff",
    color: "#ffffff",
    width: "60px",
    padding: "5px",
  };

  const playBtnStyle: React.CSSProperties = {
    ...btnBase,
    backgroundColor: "#907cff",
    color: "#ffffff",
    position: "relative",
    overflow: "hidden",
  };

  const handlePlay = (): void => {
    if (!ready) return;
    if (authenticated) {
      navigate("/dashboard");
    } else {
      login();
    }
  };

  return (
    <div className="home-container">
      <div className="footer-buttons">
        <a
          ref={discordBtnRef}
          href="https://discord.gg/z4SUdrKayb"
          target="_blank"
          rel="noopener noreferrer"
          style={discordBtn}
          className="discord-btn"
          title="Join Discord"
        >
          <FaDiscord size={28} />
        </a>
        <button
          ref={playBtnRef}
          onClick={handlePlay}
          disabled={!ready}
          style={playBtnStyle}
          className="play-btn sparkle-btn"
          title="Play"
        >
          <span className="sparkle-particle">👻</span>
          <span className="sparkle-particle">🐔</span>
          <span className="sparkle-particle">😶‍🌫️</span>
          <span className="btn-text">Play</span>
        </button>
      </div>

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

          .sparkle-btn {
            position: relative;
            overflow: visible !important;
          }

          .sparkle-btn .btn-text {
            position: relative;
            z-index: 2;
          }

          .sparkle-particle {
            position: absolute;
            font-size: 14px;
            scale: 2.0;
            opacity: 0;
            pointer-events: none;
            animation: sparkle-rise 4s ease-out infinite;
            text-shadow: 0 0 10px rgba(144, 124, 255, 0.2), 0 0 20px rgba(144, 124, 255, 0.15);
            filter: drop-shadow(0 0 8px rgba(144, 124, 255, 0.2));
          }

          .sparkle-particle:nth-child(1) {
            left: 20%;
            animation-delay: 0s;
          }
          .sparkle-particle:nth-child(2) {
            left: 50%;
            animation-delay: 1.3s;
          }
          .sparkle-particle:nth-child(3) {
            left: 80%;
            animation-delay: 2.6s;
          }

          @keyframes sparkle-rise {
            0% {
              opacity: 0;
              transform: translateY(0) scale(0.6);
              bottom: 50%;
            }
            15% {
              opacity: 0.7;
            }
            50% {
              opacity: 0.5;
            }
            100% {
              opacity: 0;
              transform: translateY(-50px) scale(1.5);
              bottom: 100%;
            }
          }
        `}
      </style>
    </div>
  );
};

export default Home;
