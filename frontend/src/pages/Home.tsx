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
    // ---------- SCROLL STORY (Section 2) ----------
    const sections = gsap.utils.toArray<HTMLElement>(".story-slide");
    
    gsap.to(sections, {
      scrollTrigger: {
        trigger: scrollContainerRef.current,
        start: "top top",
        end: "bottom bottom",
        scrub: true,
      }
    });

    sections.forEach((section, i) => {
      const content = section.querySelector(".slide-content");
      const image = section.querySelector(".slide-image");

      // Initial state
      gsap.set(content, { opacity: 0, y: 50 });
      gsap.set(image, { opacity: 0, scale: 0.9 });

      ScrollTrigger.create({
        trigger: section,
        start: "top center",
        end: "bottom center",
        onEnter: () => {
          gsap.to(content, { opacity: 1, y: 0, duration: 0.8, ease: "power2.out" });
          gsap.to(image, { opacity: 1, scale: 1, duration: 1, ease: "power2.out" });
        },
        onLeave: () => {
          gsap.to(content, { opacity: 0, y: -50, duration: 0.8, ease: "power2.in" });
          gsap.to(image, { opacity: 0, scale: 1.1, duration: 1, ease: "power2.in" });
        },
        onEnterBack: () => {
          gsap.to(content, { opacity: 1, y: 0, duration: 0.8, ease: "power2.out" });
          gsap.to(image, { opacity: 1, scale: 1, duration: 1, ease: "power2.out" });
        },
        onLeaveBack: () => {
          gsap.to(content, { opacity: 0, y: 50, duration: 0.8, ease: "power2.in" });
          gsap.to(image, { opacity: 0, scale: 0.9, duration: 1, ease: "power2.in" });
        }
      });
    });

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

        <div className="scroll-hint">
          <FaArrowDown className="bounce" />
          <span>SCROLL TO EXPLORE</span>
        </div>
      </section>

      {/* SECTION 2: SCROLL STORY */}
      <section className="scroll-story-container" ref={scrollContainerRef}>
        <div className="sticky-wrapper" ref={stickyRef}>
          
          {/* Slide 1: Gameplay */}
          <div className="story-slide">
            <div className="slide-content-wrapper">
              <div className="slide-content">
                <h2 className="slide-headline">Gameplay</h2>
                <p className="slide-subtext">Turn Players Into Community. <br /> Reward engagement and grow your ecosystem organically.</p>
              </div>
              <div className="slide-image">
                <img src="/logo.jpg" alt="Gameplay" />
                <div className="image-glow" />
              </div>
            </div>
          </div>

          {/* Slide 2: Projects */}
          <div className="story-slide">
            <div className="slide-content-wrapper reverse">
              <div className="slide-content">
                <h2 className="slide-headline">Projects</h2>
                <p className="slide-subtext">Play Together. Win Together. <br /> A new layer where games and Web3 connect seamlessly.</p>
              </div>
              <div className="slide-image">
                <img src="/logo.jpg" alt="Projects" />
                <div className="image-glow" />
              </div>
            </div>
          </div>

          {/* Slide 3: Vision */}
          <div className="story-slide">
            <div className="slide-content-wrapper">
              <div className="slide-content">
                <h2 className="slide-headline">Vision First. Always.</h2>
                <p className="slide-subtext">A new layer where games and Web3 connect seamlessly.</p>
              </div>
              <div className="slide-image">
                <img src="/logo.jpg" alt="Unified Vision" />
                <div className="image-glow" />
              </div>
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
          <div className="event-card glass">
            <FaTrophy className="event-icon" />
            <h3 className="event-title">Won Monad Blitz for new feature</h3>
            <span className="event-date">March 2025</span>
          </div>
          <div className="event-card glass">
            <FaUsers className="event-icon" />
            <h3 className="event-title">Crossed 200K active players</h3>
            <span className="event-date">Feb 2025</span>
          </div>
          <div className="event-card glass">
            <FaGamepad className="event-icon" />
            <h3 className="event-title">Raised community funding runde</h3>
            <span className="event-date">Jan 2025</span>
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

