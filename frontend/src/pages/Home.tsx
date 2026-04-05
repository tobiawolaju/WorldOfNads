import React, { useRef, useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { usePrivy } from "@privy-io/react-auth";
import "./Home.css";
import { FaDiscord } from "react-icons/fa";
import Slide1 from "../components/Slide1";
import Slide2 from "../components/Slide2";
import Slide3 from "../components/Slide3";
import Footer from "../components/Footer";

const Home: React.FC = () => {
  const { login, authenticated, ready } = usePrivy();
  const navigate = useNavigate();
  const statsContainerRef = useRef<HTMLDivElement>(null);

  // Hero Parallax
  const heroRef = useRef<HTMLDivElement>(null);
  const heroBgRef = useRef<HTMLImageElement>(null);
  const [showFooterButtons, setShowFooterButtons] = useState(false);

  const handlePlay = (): void => {
    if (!ready) return;
    if (authenticated) {
      navigate("/dashboard");
    } else {
      login();
    }
  };

  useEffect(() => {
    // ---------- HERO PARALLAX (throttled with rAF) ----------
    const hero = heroRef.current;
    const heroBg = heroBgRef.current;
    if (!hero || !heroBg) return;

    let targetX = 0;
    let targetY = 0;
    let currentX = 0;
    let currentY = 0;
    let rafId = 0;

    const animate = () => {
      currentX += (targetX - currentX) * 0.12;
      currentY += (targetY - currentY) * 0.12;
      heroBg.style.transform = `translate3d(${currentX}px, ${currentY}px, 0)`;
      rafId = requestAnimationFrame(animate);
    };

    const onMouseMove = (e: MouseEvent) => {
      const xPos = (e.clientX / window.innerWidth - 0.5) * 20;
      const yPos = (e.clientY / window.innerHeight - 0.5) * 20;
      targetX = xPos;
      targetY = yPos;
    };

    const onMouseLeave = () => {
      targetX = 0;
      targetY = 0;
    };

    hero.addEventListener("mousemove", onMouseMove);
    hero.addEventListener("mouseleave", onMouseLeave);
    rafId = requestAnimationFrame(animate);

    return () => {
      cancelAnimationFrame(rafId);
      hero.removeEventListener("mousemove", onMouseMove);
      hero.removeEventListener("mouseleave", onMouseLeave);
    };
  }, []);

  // Native reveal animations + footer buttons visibility
  useEffect(() => {
    const revealEls = Array.from(document.querySelectorAll<HTMLElement>(".reveal"));
    const revealObserver = new IntersectionObserver(
      (entries, observer) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("revealed");
            observer.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.12, rootMargin: "0px 0px -10% 0px" }
    );

    revealEls.forEach((el) => revealObserver.observe(el));

    let ticking = false;
    const onScroll = () => {
      if (ticking) return;
      ticking = true;
      requestAnimationFrame(() => {
        setShowFooterButtons(window.scrollY > 100);
        ticking = false;
      });
    };

    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });

    return () => {
      revealObserver.disconnect();
      window.removeEventListener("scroll", onScroll);
    };
  }, []);

  // Marquee logic for stats bar (pauses when out of viewport)
  useEffect(() => {
    const container = statsContainerRef.current;
    if (!container) return;

    let animId: number;
    let isUserInteracting = false;
    let isInView = false;
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
    container.addEventListener('touchstart', onTouchStart, { passive: true });
    container.addEventListener('touchend', onTouchEnd);
    container.addEventListener('mouseenter', onMouseEnter);

    let wheelTimeout: ReturnType<typeof setTimeout>;
    const onWheel = () => {
      isUserInteracting = true;
      clearTimeout(wheelTimeout);
      wheelTimeout = setTimeout(() => { isUserInteracting = false; }, 1000);
    };
    container.addEventListener('wheel', onWheel, { passive: true });

    const visibilityObserver = new IntersectionObserver(
      ([entry]) => {
        isInView = Boolean(entry?.isIntersecting);
      },
      { threshold: 0.1 }
    );
    visibilityObserver.observe(container);

    const step = () => {
      if (isInView && !isUserInteracting) {
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
      visibilityObserver.disconnect();
      clearTimeout(wheelTimeout);
    };
  }, []);

  const tweets = [
    {
      month: "Mar 2026",
      body: "Top players just got paid again. Skill is winning here. 🏆",
      image: "/tweets/img1.jpg",
    },
    {
      month: "Mar 2026",
      body: "200K+ matches. No bots. Just players competing. 🚀",
      image: "/tweets/img2.jpg",
    },
    {
      month: "Mar 2026",
      body: "More sponsors joining. More prize pools going live. 🎮",
      image: "/tweets/img3.jpg",
    },
  ];

  const renderWaveText = (text: string) => {
    const words = text.split(" ");
    return (
      <span className="wave-text" aria-label={text}>
        {words.map((word, index) => (
          <span
            key={`${word}-${index}`}
            className="wave-word"
            style={{ "--wave-index": index } as React.CSSProperties}
            aria-hidden="true"
          >
            {word}
            {index < words.length - 1 ? "\u00A0" : ""}
          </span>
        ))}
      </span>
    );
  };

  return (
    <div className="home-wrapper">
      {/* Noise Overlay */}
      <div className="noise-overlay" />

      {/* SECTION 1: HERO */}
      <section className="hero-section" ref={heroRef}>
        <div className="hero-bg-container">
          <img ref={heroBgRef} src="/wons.gif" alt="World of Nads Gameplay" className="hero-bg-video" />
          <div className="hero-overlay" />
        </div>

        <div className="hero-content">
          <h1 className="hero-headline"> WORLD OF NADS</h1>
        </div>
        <p className="hero-subtext">Play fast. Win real. No grind. No luck. Just skill. ↓</p>

      </section>

      {/* SECTION 2: SCROLL STORY */}
      <section className="scroll-story-container functional-purple">
        <div className="story-content-wrapper">

          {/* Slide 1: Gameplay */}
          <div className="functional-slide">
            <div className="func-content">
              <h2 className="func-headline">Play</h2>
              <p className="func-subtext" style={{ fontSize: '40px', color: 'grey' }}>
                {renderWaveText("Jump in. Compete. Win. Every match counts. Every win pays. No tutorials. No onboarding friction. You already know what to do.")}
              </p>
            </div>
            <div className="func-image">
              <Slide1 />
            </div>
          </div>



          {/* Slide 2: Hosts */}
          <div className="functional-slide reverse">
            <div className="func-content">
              <h2 className="func-headline">Hosts</h2>
              <p className="func-subtext" style={{ fontSize: '40px', color: 'grey' }}> {renderWaveText("Fund matches. Attract players. Get seen where competition happens.Sponsors drive the ecosystem.")}</p>
            </div>
            <div className="func-image">
              <Slide2 />
            </div>
          </div>

          {/* Slide 3: Vision */}
          <div className="functional-slide">
            <div className="func-content">
              <h2 className="func-headline">Built for Competition</h2>
              <p className="func-subtext" style={{ fontSize: '40px', color: 'grey' }}>{renderWaveText("No bots. No artificial rewards. No shortcuts. Every match is real. Every win is earned. Skill decides everything.")}</p>
              <h2 className="section-title">How it works</h2>
              <p className="func-subtext" style={{ fontSize: '40px', color: 'grey' }}>{renderWaveText("Sponsors fund matches. Players compete for rewards. The platform scales with every game played.")}</p>


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
                <span className="stat-num">The First</span>
                <span className="stat-label">Arena</span>
              </div>
              <div className="stat-item">
                <span className="stat-num">100</span>
                <span className="stat-label">Players</span>
              </div>
              <div className="stat-item">
                <span className="stat-num">10</span>
                <span className="stat-label">Sponsors</span>
              </div>
              <div className="stat-item">
                <span className="stat-num" style={{ fontSize: 'clamp(18px, 2vw, 28px)' }}>Real Matches. Real Rewards.</span>
                <span className="stat-label" style={{ textTransform: 'none', letterSpacing: 'normal', fontSize: '13px' }}>Be early. Or compete later</span>
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* SECTION 4: EVENTS GRID */}
      <section className="events-grid-section reveal">
        <h2 className="section-title">What’s happening</h2>
        <div className="events-grid">
          {tweets.map((tweet, index) => (
            <article className="tweet-card" key={tweet.month}>
              <div className="tweet-header">
                <img src="/logo.jpg" alt="Avatar" className="tweet-avatar" />
                <div className="tweet-user">
                  <span className="tweet-name">World of Nads</span>
                  <span className="tweet-handle">@WorldOfNads · {tweet.month}</span>
                </div>
              </div>
              <img
                src={tweet.image}
                alt={`World of Nads post ${index + 1}`}
                className="tweet-image"
              />
              <p className="tweet-body">{tweet.body}</p>
              <a href="#" className="tweet-link">View Post</a>
            </article>
          ))}
        </div>
      </section>

      <Footer />

      {/* FIXED BUTTONS */}
      <div className={`footer-buttons ${showFooterButtons ? "is-visible" : ""}`}>
        <a
          href="https://discord.gg/z4SUdrKayb"
          target="_blank"
          rel="noopener noreferrer"
          className="discord-btn-fixed"
          title="Join Discord"
        >
          <FaDiscord size={28} />
        </a>
        <button
          onClick={handlePlay}
          disabled={!ready}
          className="play-btn-fixed"
          title="Enter Arena"
        >
          Enter Arena
        </button>
      </div>
    </div>
  );
};

export default Home;
