import React, { useRef, useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { usePrivy } from "@privy-io/react-auth";
import "./Home.css";
import { FaDiscord } from "react-icons/fa";
import Slide1 from "../components/Slide1";
import Slide2 from "../components/Slide2";
import Footer from "../components/Footer";

const WaveText = React.memo(({ text }: { text: string }) => {
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
});

const Home: React.FC = () => {
  const { login, authenticated, ready } = usePrivy();
  const navigate = useNavigate();
  const statsContainerRef = useRef<HTMLDivElement>(null);

  // Hero Parallax
  const heroRef = useRef<HTMLDivElement>(null);
  const heroBgRef = useRef<HTMLImageElement>(null);
  const [showFooterButtons, setShowFooterButtons] = useState(false);
  const heroFrameRef = useRef<number | null>(null);
  const heroVisibleRef = useRef(false);
  const heroPausedByVisibilityRef = useRef(false);
  const statsFrameRef = useRef<number | null>(null);
  const statsVisibleRef = useRef(false);
  const statsInteractingRef = useRef(false);
  const statsDocumentVisibleRef = useRef(!document.hidden);

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
    const stop = () => {
      if (heroFrameRef.current != null) {
        cancelAnimationFrame(heroFrameRef.current);
        heroFrameRef.current = null;
      }
    };

    const animate = () => {
      if (!heroVisibleRef.current || document.hidden) {
        stop();
        return;
      }

      currentX += (targetX - currentX) * 0.12;
      currentY += (targetY - currentY) * 0.12;
      heroBg.style.transform = `translate3d(${currentX}px, ${currentY}px, 0)`;

      const isSettled =
        Math.abs(targetX - currentX) < 0.05 &&
        Math.abs(targetY - currentY) < 0.05 &&
        targetX === 0 &&
        targetY === 0;

      if (isSettled) {
        stop();
        return;
      }

      heroFrameRef.current = requestAnimationFrame(animate);
    };

    const start = () => {
      if (heroFrameRef.current != null || !heroVisibleRef.current || document.hidden) return;
      heroFrameRef.current = requestAnimationFrame(animate);
    };

    const onMouseMove = (e: MouseEvent) => {
      const xPos = (e.clientX / window.innerWidth - 0.5) * 20;
      const yPos = (e.clientY / window.innerHeight - 0.5) * 20;
      targetX = xPos;
      targetY = yPos;
      start();
    };

    const onMouseLeave = () => {
      targetX = 0;
      targetY = 0;
    };

    const visibilityObserver = new IntersectionObserver(
      ([entry]) => {
        heroVisibleRef.current = Boolean(entry?.isIntersecting);
        if (heroVisibleRef.current) {
          start();
        } else {
          stop();
        }
      },
      { threshold: 0.2 }
    );

    const onVisibilityChange = () => {
      if (document.hidden) {
        heroPausedByVisibilityRef.current = heroFrameRef.current != null;
        stop();
        return;
      }

      if (heroPausedByVisibilityRef.current) {
        heroPausedByVisibilityRef.current = false;
        start();
      }
    };

    visibilityObserver.observe(hero);
    hero.addEventListener("mousemove", onMouseMove);
    hero.addEventListener("mouseleave", onMouseLeave);
    document.addEventListener("visibilitychange", onVisibilityChange);

    return () => {
      visibilityObserver.disconnect();
      stop();
      hero.removeEventListener("mousemove", onMouseMove);
      hero.removeEventListener("mouseleave", onMouseLeave);
      document.removeEventListener("visibilitychange", onVisibilityChange);
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

    const stop = () => {
      if (statsFrameRef.current != null) {
        cancelAnimationFrame(statsFrameRef.current);
        statsFrameRef.current = null;
      }
    };

    const start = () => {
      if (statsFrameRef.current != null || !statsVisibleRef.current || !statsDocumentVisibleRef.current) return;
      statsFrameRef.current = requestAnimationFrame(step);
    };

    let isDown = false;
    let startX: number;
    let scrollLeftPos: number;

    const onTouchStart = () => {
      statsInteractingRef.current = true;
      stop();
    };
    const onTouchEnd = () => {
      statsInteractingRef.current = false;
      start();
    };
    const onMouseEnter = () => {
      statsInteractingRef.current = true;
      stop();
    };

    const onMouseDown = (e: MouseEvent) => {
      statsInteractingRef.current = true;
      isDown = true;
      startX = e.pageX - container.offsetLeft;
      scrollLeftPos = container.scrollLeft;
      container.style.cursor = 'grabbing';
      stop();
    };
    const onMouseLeave = () => {
      statsInteractingRef.current = false;
      isDown = false;
      container.style.cursor = 'grab';
      start();
    };
    const onMouseUp = () => {
      statsInteractingRef.current = false;
      isDown = false;
      container.style.cursor = 'grab';
      start();
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
      statsInteractingRef.current = true;
      stop();
      clearTimeout(wheelTimeout);
      wheelTimeout = setTimeout(() => {
        statsInteractingRef.current = false;
        start();
      }, 1000);
    };
    container.addEventListener('wheel', onWheel, { passive: true });

    const visibilityObserver = new IntersectionObserver(
      ([entry]) => {
        statsVisibleRef.current = Boolean(entry?.isIntersecting);
        if (statsVisibleRef.current) {
          start();
        } else {
          stop();
        }
      },
      { threshold: 0.1 }
    );
    visibilityObserver.observe(container);

    const onDocumentVisibilityChange = () => {
      statsDocumentVisibleRef.current = !document.hidden;
      if (document.hidden) {
        stop();
      } else {
        start();
      }
    };

    document.addEventListener("visibilitychange", onDocumentVisibilityChange);

    const step = () => {
      statsFrameRef.current = null;

      if (statsVisibleRef.current && !statsInteractingRef.current && statsDocumentVisibleRef.current) {
        container.scrollLeft += 1;

        // Infinite loop check
        if (container.scrollLeft >= container.scrollWidth / 2) {
          container.scrollLeft -= container.scrollWidth / 2;
        } else if (container.scrollLeft <= 0) {
          container.scrollLeft += container.scrollWidth / 2;
        }
      }

      start();
    };

    start();

    return () => {
      stop();
      container.removeEventListener('mousedown', onMouseDown);
      container.removeEventListener('mouseleave', onMouseLeave);
      container.removeEventListener('mouseup', onMouseUp);
      container.removeEventListener('mousemove', onMouseMove);
      container.removeEventListener('touchstart', onTouchStart);
      container.removeEventListener('touchend', onTouchEnd);
      container.removeEventListener('mouseenter', onMouseEnter);
      container.removeEventListener('wheel', onWheel);
      visibilityObserver.disconnect();
      document.removeEventListener("visibilitychange", onDocumentVisibilityChange);
      clearTimeout(wheelTimeout);
    };
  }, []);

  const tweets = [
    {
      month: "Apr 2026",
      bodyLines: [
        "We're opening early access to a new competitive gaming platform today.",
        "Test matches are already running with early players.",
        "If you want in, join here:",
        "👉 WAITLIST_LINK",
        "Discord access + beta matches unlocked after sign up.",
      ],
      waitlistLink: "https://worldofnads.xyz/waitlist",
      discordLink: "https://discord.gg/z4SUdrKayb",
      link: "https://x.com/i/status/2043666277927956534",
    },
  ];

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
        <p className="hero-subtext">A million Nads enter. Only one becomes Prime. No luck. Just skill. ↓</p>

      </section>

      {/* SECTION 2: SCROLL STORY */}
      <section className="scroll-story-container functional-purple">
        <div className="story-content-wrapper">

          {/* Slide 1: Gameplay */}
          <div className="functional-slide">
            <div className="func-content">
              <h2 className="func-headline">Play</h2>
              <p className="func-subtext func-subtext-inline-replaced" style={{ fontSize: '40px' }}>
                <WaveText text="Drop into the arena. Outplay everyone. Earn your place. Every match is a fight for position. Every win moves you closer to recognition." />
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
              <p className="func-subtext func-subtext-inline-replaced" style={{ fontSize: '40px' }}> <WaveText text="Control the arena. Shape the battlefield. Get seen where competition happens. Sponsors don’t just fund matches — they influence the game." /></p>
            </div>
            <div className="func-image">
              <Slide2 />
            </div>
          </div>

          {/* Slide 3: Vision */}
          <div className="functional-slide">
            <div className="func-content">
              <h2 className="func-headline">Built for Competition</h2>
              <p className="func-subtext func-subtext-inline-replaced" style={{ fontSize: '40px' }}><WaveText text="No bots. No shortcuts. No second chances. Every match is real. Every win is earned. Only skill decides who rises." /></p>
              <h2 className="section-title">How it works</h2>
              <p className="func-subtext func-subtext-inline-replaced" style={{ fontSize: '40px' }}><WaveText text="The arena resets every month. Players compete. Only the top rise. The best become recognized Nads." /></p>


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
                <span className="stat-num" style={{ fontSize: 'clamp(18px, 2vw, 28px)' }}>100 enter. Only the best rise.</span>
                <span className="stat-label" style={{ textTransform: 'none', letterSpacing: 'normal', fontSize: '13px' }}>Be early. Or fight your way in</span>
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* SECTION 4: EVENTS GRID */}
      <section className="events-grid-section reveal">
        <h2 className="section-title">What’s happening</h2>
        <div className="events-grid">
          {tweets.map((tweet) => (
            <article className="tweet-card" key={tweet.month}>
              <div className="tweet-header">
                <img src="/logo.jpg" alt="Avatar" className="tweet-avatar" />
                <div className="tweet-user">
                  <span className="tweet-name">World of Nads</span>
                  <span className="tweet-handle">@WorldOfNads · {tweet.month}</span>
                </div>
              </div>
              <p className="tweet-body">
                {tweet.bodyLines.map((line) => (
                  <React.Fragment key={line}>
                    {line === "👉 WAITLIST_LINK" ? (
                      <>
                        👉{" "}
                        <a
                          href={tweet.waitlistLink}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="tweet-inline-link"
                        >
                          worldofnads.xyz/waitlist
                        </a>
                      </>
                    ) : (
                      line
                    )}
                    <br />
                    <br />
                  </React.Fragment>
                ))}
                Join →{" "}
                <a
                  href={tweet.discordLink}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="tweet-inline-link"
                >
                  discord.gg/z4SUdrKayb
                </a>
                .
              </p>
              <a href={tweet.link} className="tweet-link" target="_blank" rel="noopener noreferrer">View Post</a>
            </article>
          ))}
        </div>
      </section>

      <Footer />

      {/* FIXED BUTTONS */}
      <div className={`footer-buttons ${showFooterButtons ? "is-visible" : ""}`}>

        <button
          onClick={handlePlay}
          disabled={!ready}
          className="play-btn-fixed"
          title="Play"
        >
          Play
        </button>

        <a
          href="https://discord.gg/z4SUdrKayb"
          target="_blank"
          rel="noopener noreferrer"
          className="discord-btn-fixed"
          title="Join Discord"
        >
          <FaDiscord size={28} />
        </a>


      </div>
    </div>
  );
};

export default Home;
