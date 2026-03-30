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
  const statsContainerRef = useRef<HTMLDivElement>(null);

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
    // ---------- FADE BUTTONS ON SCROLL ----------
    gsap.set(".footer-buttons", { opacity: 0.0, pointerEvents: "none", y: 20 });
    ScrollTrigger.create({
      start: 100,
      onEnter: () => gsap.to(".footer-buttons", { opacity: 1, pointerEvents: "auto", y: 0, duration: 0.4 }),
      onLeaveBack: () => gsap.to(".footer-buttons", { opacity: 0.0, pointerEvents: "none", y: 20, duration: 0.4 })
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

  // Marquee logic for stats bar
  useEffect(() => {
    const container = statsContainerRef.current;
    if (!container) return;

    let animId: number;
    let isUserInteracting = false;
    let isDown = false;
    let startX: number;
    let scrollLeftPos: number;

    const onTouchStart = () => { isUserInteracting = true; };
    const onTouchEnd = () => { isUserInteracting = false; };
    const onMouseEnter = () => { isUserInteracting = true; };
    
    const onMouseDown = (e: MouseEvent) => {
      isUserInteracting = true;
      isDown = true;
      startX = e.pageX - container.offsetLeft;
      scrollLeftPos = container.scrollLeft;
      container.style.cursor = 'grabbing';
    };
    const onMouseLeave = () => {
      isUserInteracting = false;
      isDown = false;
      container.style.cursor = 'grab';
    };
    const onMouseUp = () => {
      isUserInteracting = false;
      isDown = false;
      container.style.cursor = 'grab';
    };
    const onMouseMove = (e: MouseEvent) => {
      if (!isDown) return;
      e.preventDefault();
      const x = e.pageX - container.offsetLeft;
      const walk = (x - startX) * 2;
      container.scrollLeft = scrollLeftPos - walk;
    };

    container.addEventListener('mousedown', onMouseDown);
    container.addEventListener('mouseleave', onMouseLeave);
    container.addEventListener('mouseup', onMouseUp);
    container.addEventListener('mousemove', onMouseMove);
    container.addEventListener('touchstart', onTouchStart, {passive: true});
    container.addEventListener('touchend', onTouchEnd);
    container.addEventListener('mouseenter', onMouseEnter);

    let wheelTimeout: ReturnType<typeof setTimeout>;
    const onWheel = () => {
       isUserInteracting = true;
       clearTimeout(wheelTimeout);
       wheelTimeout = setTimeout(() => { isUserInteracting = false; }, 1000);
    };
    container.addEventListener('wheel', onWheel, {passive: true});

    const step = () => {
      if (!isUserInteracting) {
        container.scrollLeft += 1;
      }
      
      // Infinite loop check
      if (container.scrollLeft >= container.scrollWidth / 2) {
        container.scrollLeft -= container.scrollWidth / 2;
      } else if (container.scrollLeft <= 0) {
        container.scrollLeft += container.scrollWidth / 2;
      }
      
      animId = requestAnimationFrame(step);
    };

    animId = requestAnimationFrame(step);

    return () => {
      cancelAnimationFrame(animId);
      container.removeEventListener('mousedown', onMouseDown);
      container.removeEventListener('mouseleave', onMouseLeave);
      container.removeEventListener('mouseup', onMouseUp);
      container.removeEventListener('mousemove', onMouseMove);
      container.removeEventListener('touchstart', onTouchStart);
      container.removeEventListener('touchend', onTouchEnd);
      container.removeEventListener('mouseenter', onMouseEnter);
      container.removeEventListener('wheel', onWheel);
      clearTimeout(wheelTimeout);
    };
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
          <h1 className="hero-headline"> WORLD OF NADS</h1>
        </div>
        <p className="hero-subtext">Gmonad, Welcome too the edge of Web2, scroll down there Nad ⇙</p>

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
      <section className="stats-bar-section reveal" ref={statsContainerRef}>
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
        <h2 className="section-title">News</h2>
        <div className="events-grid">
          {/* Tweet 1 */}
          <div className="tweet-card">
            <div className="tweet-header">
              <img src="/logo.jpg" alt="Avatar" className="tweet-avatar" />
              <div className="tweet-user">
                <span className="tweet-name">World of Nads</span>
                <span className="tweet-handle">@WorldOfNads · Mar 2026</span>
              </div>
            </div>
            <p className="tweet-body blur-news">Won Monad Blitz for our new feature! 🏆 Extremely excited for what's next.</p>
            <a href="#" className="tweet-link">View Post</a>
          </div>

          {/* Tweet 2 */}
          <div className="tweet-card">
            <div className="tweet-header">
              <img src="/logo.jpg" alt="Avatar" className="tweet-avatar" />
              <div className="tweet-user">
                <span className="tweet-name">World of Nads</span>
                <span className="tweet-handle">@WorldOfNads · Feb 2026</span>
              </div>
            </div>
            <p className="tweet-body blur-news">Just crossed 200K active players! The community momentum is absolutely insane right now. 🚀</p>
            <a href="#" className="tweet-link">View Post</a>
          </div>

          {/* Tweet 3 */}
          <div className="tweet-card">
            <div className="tweet-header">
              <img src="/logo.jpg" alt="Avatar" className="tweet-avatar" />
              <div className="tweet-user">
                <span className="tweet-name">World of Nads</span>
                <span className="tweet-handle">@WorldOfNads · Jan 2026</span>
              </div>
            </div>
            <p className="tweet-body blur-news">Officially raised our community funding round! Thank you to everyone who believes in the vision. 🎮</p>
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

