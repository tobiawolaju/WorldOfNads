import React, { useRef, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { usePrivy } from "@privy-io/react-auth";
import "./Home.css";
import { FaDiscord, FaArrowDown, FaGamepad, FaUsers, FaTrophy } from "react-icons/fa";
import { useGSAP } from "@gsap/react";
import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";

// Register ScrollTrigger
gsap.registerPlugin(ScrollTrigger);

const Home: React.FC = () => {
  const { login, authenticated, ready } = usePrivy();
  const navigate = useNavigate();

  // Refs for Scroll Story
  const scrollContainerRef = useRef<HTMLDivElement>(null);
  const stickyRef = useRef<HTMLDivElement>(null);
  
  // Refs for buttons
  const discordBtnRef = useRef<HTMLAnchorElement>(null);
  const playBtnRef = useRef<HTMLButtonElement>(null);

  // Hero Parallax
  const heroRef = useRef<HTMLDivElement>(null);
  const heroContentRef = useRef<HTMLDivElement>(null);

  const handlePlay = (): void => {
    if (!ready) return;
    if (authenticated) {
      navigate("/dashboard");
    } else {
      login();
    }
  };

  useGSAP(() => {
    // ---------- HERO PARALLAX ----------
    const hero = heroRef.current;
    if (hero) {
      const handleMouseMove = (e: MouseEvent) => {
        const { clientX, clientY } = e;
        const xPos = (clientX / window.innerWidth - 0.5) * 20;
        const yPos = (clientY / window.innerHeight - 0.5) * 20;
        gsap.to(".hero-bg-video", {
          x: xPos,
          y: yPos,
          duration: 1,
          ease: "power2.out"
        });
      };
      hero.addEventListener("mousemove", handleMouseMove);
      return () => hero.removeEventListener("mousemove", handleMouseMove);
    }
  }, { scope: heroRef });

  useGSAP(() => {
    // ---------- FADE IN SECTIONS ----------
    gsap.utils.toArray<HTMLElement>(".reveal").forEach((el) => {
      gsap.from(el, {
        scrollTrigger: {
          trigger: el,
          start: "top 85%",
        },
        opacity: 0,
        y: 60,
        duration: 1.2,
        ease: "power3.out"
      });
    });

    // ---------- BUTTON HOVER ----------
    const hoverIn = (el: Element) =>
      gsap.to(el, { border: "8px solid rgba(255,255,255,0.2)", duration: 0.25 });
    const hoverOut = (el: Element) =>
      gsap.to(el, { border: "none", duration: 0.25 });

    [discordBtnRef.current, playBtnRef.current].forEach(btn => {
      if (btn) {
        btn.addEventListener("mouseenter", () => hoverIn(btn));
        btn.addEventListener("mouseleave", () => hoverOut(btn));
      }
    });

  }, []);

  return (
    <div className="home-wrapper">
      {/* Noise Overlay */}
      <div className="noise-overlay" />

      {/* SECTION 1: HERO */}
      <section className="hero-section" ref={heroRef}>
        <div className="hero-bg-container">
          <img src="/wons.gif" alt="World of Nads Gameplay" className="hero-bg-video" />
          <div className="hero-overlay" />
        </div>

        <div className="hero-content" ref={heroContentRef}>
          <h1 className="hero-headline">WORLD OF NADS</h1>
        </div>

      </section>

      {/* SECTION 2: SCROLL STORY */}
      <section className="scroll-story-container functional-purple">
        <div className="story-content-wrapper">
          
          {/* Slide 1: Gameplay */}
          <div className="functional-slide">
            <div className="func-content">
              <h2 className="func-headline">Gameplay</h2>
              <p className="func-subtext">Turn Players Into Community. Reward engagement and grow your ecosystem organically.</p>
            </div>
            <div className="func-image">
              <img src="/logo.jpg" alt="Gameplay" />
            </div>
          </div>

          {/* Slide 2: Projects */}
          <div className="functional-slide reverse">
            <div className="func-content">
              <h2 className="func-headline">Projects</h2>
              <p className="func-subtext">Play Together. Win Together. A new layer where games and Web3 connect seamlessly.</p>
            </div>
            <div className="func-image">
              <img src="/logo.jpg" alt="Projects" />
            </div>
          </div>

          {/* Slide 3: Vision */}
          <div className="functional-slide">
            <div className="func-content">
              <h2 className="func-headline">Vision First. Always.</h2>
              <p className="func-subtext">A new layer where games and Web3 connect seamlessly.</p>
            </div>
            <div className="func-image">
              <img src="/logo.jpg" alt="Unified Vision" />
            </div>
          </div>

        </div>
      </section>

      {/* SECTION 3: STATS BAR */}
      <section className="stats-bar-section reveal">
        <div className="stats-track">
          {[...Array(2)].map((_, i) => (
            <div key={i} className="stats-group">
              <div className="stat-item">
                <span className="stat-num">200K+</span>
                <span className="stat-label">Matches Played</span>
              </div>
              <div className="stat-item">
                <span className="stat-num">$7.3K+</span>
                <span className="stat-label">Paid Out</span>
              </div>
              <div className="stat-item">
                <span className="stat-num">15K+</span>
                <span className="stat-label">Active Players</span>
              </div>
              <div className="stat-item">
                <span className="stat-num">42+</span>
                <span className="stat-label">Integrated Projects</span>
              </div>
              {/* Sponsor Logos */}
              <div className="sponsor-logo">Monad Labs</div>
              <div className="sponsor-logo">Kizzy Mobile</div>
            </div>
          ))}
        </div>
      </section>

      {/* SECTION 4: EVENTS GRID */}
      <section className="events-grid-section reveal">
        <h2 className="section-title">Momentum</h2>
        <div className="events-grid">
          {/* Tweet 1 */}
          <div className="tweet-card">
            <div className="tweet-header">
              <img src="/logo.jpg" alt="Avatar" className="tweet-avatar" />
              <div className="tweet-user">
                <span className="tweet-name">World of Nads</span>
                <span className="tweet-handle">@WorldOfNads · Mar 2025</span>
              </div>
            </div>
            <p className="tweet-body">Won Monad Blitz for our new feature! 🏆 Extremely excited for what's next.</p>
            <a href="#" className="tweet-link">View Post</a>
          </div>

          {/* Tweet 2 */}
          <div className="tweet-card">
            <div className="tweet-header">
              <img src="/logo.jpg" alt="Avatar" className="tweet-avatar" />
              <div className="tweet-user">
                <span className="tweet-name">World of Nads</span>
                <span className="tweet-handle">@WorldOfNads · Feb 2025</span>
              </div>
            </div>
            <p className="tweet-body">Just crossed 200K active players! The community momentum is absolutely insane right now. 🚀</p>
            <a href="#" className="tweet-link">View Post</a>
          </div>

          {/* Tweet 3 */}
          <div className="tweet-card">
            <div className="tweet-header">
              <img src="/logo.jpg" alt="Avatar" className="tweet-avatar" />
              <div className="tweet-user">
                <span className="tweet-name">World of Nads</span>
                <span className="tweet-handle">@WorldOfNads · Jan 2025</span>
              </div>
            </div>
            <p className="tweet-body">Officially raised our community funding round! Thank you to everyone who believes in the vision. 🎮</p>
            <a href="#" className="tweet-link">View Post</a>
          </div>
        </div>
      </section>

      {/* FIXED BUTTONS */}
      <div className="footer-buttons">
        <a
          ref={discordBtnRef}
          href="https://discord.gg/z4SUdrKayb"
          target="_blank"
          rel="noopener noreferrer"
          className="discord-btn-fixed"
          title="Join Discord"
        >
          <FaDiscord size={28} />
        </a>
        <button
          ref={playBtnRef}
          onClick={handlePlay}
          disabled={!ready}
          className="play-btn-fixed"
          title="Play"
        >
          Play
        </button>
      </div>
    </div>
  );
};

export default Home;

