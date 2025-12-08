import React, { useRef } from "react";
import { useNavigate } from "react-router-dom";
import { usePrivy } from "@privy-io/react-auth";
import "./Home.css";
import { FaDiscord } from "react-icons/fa";
import { useGSAP } from "@gsap/react";
import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";

//remeber to unsinstall this
import Rive from '@rive-app/react-canvas';

// Register the ScrollTrigger plugin
gsap.registerPlugin(ScrollTrigger);

const Home: React.FC = () => {
  const { ready, authenticated, login } = usePrivy();
  const navigate = useNavigate();

  // Refs for GSAP animations
  const container = useRef<HTMLDivElement>(null);
  const titleRef = useRef<HTMLHeadingElement>(null);
  const discordBtnRef = useRef<HTMLAnchorElement>(null);
  const playBtnRef = useRef<HTMLButtonElement>(null);

  // GSAP animations
  useGSAP(() => {

    gsap.from(".stats-card", {
      opacity: 0,
      y: 50,
      stagger: 0.1,
      duration: 0.6,
      scrollTrigger: {
        trigger: ".stats-section",
        start: "top bottom-=100",
        end: "top center",
        scrub: 1,
      }
    });

    gsap.from(".event-card", {
      opacity: 0,
      y: 30,
      stagger: 0.15,
      duration: 0.6,
      scrollTrigger: {
        trigger: ".events-section",
        start: "top bottom-=100",
        end: "top center",
        scrub: 1,
      }
    });


    // 1. Animate .title on page load (no change)
    gsap.from(titleRef.current, {
      duration: 2.0,
      opacity: 0,
      y: 50,
      ease: "power3.out",
      delay: 0.5,
    });

    // 2. Animate .wons-card elements tied to scroll position
    gsap.from(".wons-card", {
      opacity: 0,
      y: 0,
      rotation: (i) => gsap.utils.random(-10, 5), // 🔥 random per card
      stagger: 0.1,
      ease: "power2.out",
      scrollTrigger: {
        trigger: ".wons-grid",
        start: "top bottom-=100",
        end: "top center",
        scrub: 1,
      }
    });


    // 3. Animate buttons on hover (no change)
    const animateButtonHover = (target: Element, glowColor: string) => {
      gsap.to(target, {
        border: '8px solid rgba(255, 255, 255, 0.197)',
        duration: 0.3,
        ease: "power1.inOut",
      });
    };

    const resetButtonHover = (target: Element) => {
      gsap.to(target, {
        border: 'none',
        duration: 0.3,
        ease: "power1.inOut",
      });
    };

    const discordBtn = discordBtnRef.current;
    if (discordBtn) {
      discordBtn.addEventListener("mouseenter", () => animateButtonHover(discordBtn, "rgba(110, 89, 255, 0.7)"));
      discordBtn.addEventListener("mouseleave", () => resetButtonHover(discordBtn));
    }

    const playBtn = playBtnRef.current;
    if (playBtn) {
      playBtn.addEventListener("mouseenter", () => animateButtonHover(playBtn, "rgba(110, 89, 255, 0.7)"));
      playBtn.addEventListener("mouseleave", () => resetButtonHover(playBtn));
    }


    // Cleanup event listeners on component unmount
    return () => {
      if (discordBtn) {
        discordBtn.removeEventListener("mouseenter", () => animateButtonHover(discordBtn, "rgba(110, 89, 255, 0.7)"));
        discordBtn.removeEventListener("mouseleave", () => resetButtonHover(discordBtn));
      }
      if (playBtn) {
        playBtn.removeEventListener("mouseenter", () => animateButtonHover(playBtn, "rgba(110, 89, 255, 0.7)"));
        playBtn.removeEventListener("mouseleave", () => resetButtonHover(playBtn));
      }
    };

  }, { scope: container }); // Scope GSAP selectors to the container ref

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
          1.2k Nads
        </h1>


        <div
          className="absolute bottom-0 w-[80vw] h-[80vw] md:w-[80vh] md:h-[80vh]"
        >
          <Rive
            src="https://cdn.rive.app/animations/vehicles.riv"
            stateMachines="bumpy"
          />
        </div>


      </div>

      {/* Contents Section */}
      <div>
        {/* --- WHAT'S ON WONS SECTION --- */}
        <section className="wons-section">
          <div className="wons-grid">
            <div className="wons-card"></div>
            <div className="wons-card"></div>
            <div className="wons-card"></div>
            <div className="wons-card"></div>
          </div>
        </section>

        {/* ====== BACKED BY SECTION ====== */}
        <section className="backed-section">
          <h2>Backed By</h2>
          <div className="backed-logos">
            <div className="backed-card">******</div>
            <div className="backed-card">******</div>
            <div className="backed-card">******</div>
            <div className="backed-card">******</div>
          </div>
        </section>

        {/* ====== LIVE STATS SECTION ====== */}
        <section className="stats-section">
          <h2>WON Network Stats</h2>
          <div className="stats-grid">
            <div className="stats-card">
              <span className="stats-value">12,342</span>
              <span className="stats-label">Players on WONs</span>
            </div>
            <div className="stats-card">
              <span className="stats-value">98,221</span>
              <span className="stats-label">Total Matches</span>
            </div>
            <div className="stats-card">
              <span className="stats-value">42ms</span>
              <span className="stats-label">Latency</span>
            </div>
            <div className="stats-card">
              <span className="stats-value">0.3s</span>
              <span className="stats-label">Block Time</span>
            </div>
          </div>
        </section>

        {/* ====== WONs CHICKEN CHAOS NIGHT PREVIEW ====== */}
        <section className="dex-section">
          <h2>Chicken CHAOS Night</h2>
          <p>Compete for $10k every Weekend on WONs.</p>
          <div className="dex-preview">
            <div className="dex-screenshot">CHAOS MATCH and TAG TWEET PLACEHOLDER</div>
          </div>
        </section>

        {/* ====== WONs HAPPENINGS ====== */}
        <section className="events-section">
          <h2>WONs Happenings</h2>
          <div className="events-grid">
            <div className="event-card">
              <h3>WON Substack</h3>
              <p>Read the latest development drops from the core team.</p>
            </div>
            <div className="event-card">
              <h3>WON Batches</h3>
              <p>Seasonal competitive game waves and challenge rounds.</p>
            </div>
            <div className="event-card">
              <h3>WON CAMP</h3>
              <p>2025 Bootcamp — Learn, build, and compete on WON.</p>
            </div>
            <div className="event-card">
              <h3>Meetups</h3>
              <p>Local gatherings and Web3 gaming meetups.</p>
            </div>
          </div>

          <button className="events-btn">Read More</button>
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
        
          `}
        </style>
      </footer>

    </div>
  );
};

export default Home;