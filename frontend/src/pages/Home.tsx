import React, { useRef } from "react";
import { useNavigate } from "react-router-dom";
import "./Home.css";
import { FaDiscord } from "react-icons/fa";
import { useGSAP } from "@gsap/react";
import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";

// Register the ScrollTrigger plugin
gsap.registerPlugin(ScrollTrigger);

const Home: React.FC = () => {
  const navigate = useNavigate();

  // Refs for GSAP animations
  const container = useRef<HTMLDivElement>(null);
  const titleRef = useRef<HTMLHeadingElement>(null);
  const discordBtnRef = useRef<HTMLAnchorElement>(null);
  const playBtnRef = useRef<HTMLButtonElement>(null);

  // GSAP animations
  useGSAP(() => {
    // ---------- HERO TITLE (still load-based, allowed)
    gsap.from(titleRef.current, {
      opacity: 0,
      y: 60,
      ease: "power3.out",
      duration: 1.8,
      delay: 0.3
    });

    // ---------- WONS CARDS (true scroll-y driven)
    gsap.utils.toArray<HTMLElement>(".wons-card").forEach((card, i) => {
      gsap.from(card, {
        opacity: 0,
        y: 90,
        scale: 0.94,
        rotation: i % 2 ? 4 : -3,
        ease: "none", // important for scrub
        scrollTrigger: {
          trigger: card,
          start: "top 90%",
          end: "top 60%",
          scrub: true
        }
      });
    });

    // ---------- STATS
    gsap.utils.toArray<HTMLElement>(".stats-card").forEach((card, i) => {
      gsap.from(card, {
        opacity: 0,
        y: 70,
        ease: "none",
        scrollTrigger: {
          trigger: card,
          start: "top 85%",
          end: "top 55%",
          scrub: true
        }
      });
    });

    // ---------- EVENTS
    gsap.utils.toArray<HTMLElement>(".event-card").forEach((card, i) => {
      gsap.from(card, {
        opacity: 0,
        y: 60,
        ease: "none",
        scrollTrigger: {
          trigger: card,
          start: "top 85%",
          end: "top 60%",
          scrub: true
        }
      });
    });

    // ---------- BUTTON HOVER (unchanged, not scroll-based)
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

    return () => ScrollTrigger.getAll().forEach(t => t.kill());
  }, { scope: container });

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
    padding: '5px'
  };

  const playBtn: React.CSSProperties = {
    ...btnBase,
    backgroundColor: "#907cff",
    color: "#ffffff",
    position: "relative",
    overflow: "hidden",
  };

  const handlePlay = (): void => {
    navigate("/dashboard");
  };

  return (
    <div
      ref={container}
      className="home-container"
      style={{
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

        <h1 className="title" ref={titleRef}>
          World of Nads
        </h1>

      </div>

      {/* Contents Section */}
      <div>
        {/* --- WHAT'S ON WONS SECTION --- */}
        <section className="wons-section">
          <div className="wons-grid">
            <div className="wons-card"><h2>Enter the Arena</h2></div>
            <div className="wons-card"><h2>Steal the Chicken</h2></div>
            <div className="wons-card"><h2>Outrun Everyone</h2></div>
            <div className="wons-card"><h2>Become a Problem</h2></div>
          </div>

        </section>




        {/* ====== WONs HAPPENINGS ====== */}
        <section className="events-section">
          <h2>WONs Happenings</h2>
          <div className="events-grid">
            <div className="event-card">
              <h3>Latest on WONs</h3>
              <p>Read the latest development drops from the core team.</p>
              <a href="https://www.google.com" target="_blank" rel="noopener noreferrer" className="match-details-twitter">
                Read ↗
              </a>
            </div>
            <div className="event-card">
              <h3>WON Batches</h3>
              <p>Seasonal competitive game waves and challenge rounds.</p>
              <a href="https://www.google.com" target="_blank" rel="noopener noreferrer" className="match-details-twitter">
                Read ↗
              </a>
            </div>
            <div className="event-card">
              <h3>WON CREATORS</h3>
              <p>2025 Wons creators program —  start your wonstreaming career with Wons.</p>
              <a href="https://www.google.com" target="_blank" rel="noopener noreferrer" className="match-details-twitter">
                Read ↗
              </a>
            </div>
          </div>

        </section>




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
            style={playBtn}
            className="play-btn"
            title="Play"
          >
            <span className="stars"></span>
            <span>Lobby</span>
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
        
          `}
        </style>
      </footer>

    </div>
  );
};

export default Home;