import React, { useEffect } from "react";
import EmailCapture from "../components/waitlist/EmailCapture";
import "./Waitlist.css";

const PillPair: React.FC<{ top: string; bottom: string; rotation: number; isAlt?: boolean }> = ({ top, bottom, rotation, isAlt }) => (
  <div
    className={`pill-pair ${isAlt ? 'alt-color' : ''}`}
    style={{ transform: `rotate(${rotation}deg)` }}
  >
    <span className="pill-label-top">{top}</span>
    <div className="pill-capsule">
      <p className="pill-label-bottom">{bottom}</p>
    </div>
  </div>
);

const Waitlist: React.FC = () => {
  useEffect(() => {
    const observerOptions = {
      threshold: 0.15,
      rootMargin: "0px 0px -50px 0px"
    };

    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add('revealed');
        }
      });
    }, observerOptions);

    const sections = document.querySelectorAll('.waitlist-section');
    sections.forEach(section => observer.observe(section));

    // Handle Hero & Pill logic on scroll
    const container = document.querySelector('.waitlist-scroll-container');
    const hero = document.querySelector('.waitlist-hero') as HTMLElement;
    
    if (!container || !hero) return;

    const handleScroll = () => {
      const scrollY = (container as HTMLElement).scrollTop;
      
      // Fade out hero as we scroll
      const fadeStart = 100;
      const fadeEnd = 500;
      const opacity = Math.max(0, 1 - (scrollY - fadeStart) / (fadeEnd - fadeStart));
      const scale = Math.max(0.9, 1 - (scrollY - fadeStart) / (fadeEnd - fadeStart) * 0.1);
      
      if (scrollY > fadeStart) {
        hero.style.opacity = opacity.toString();
        hero.style.transform = `scale(${scale}) translateY(${- (scrollY - fadeStart) * 0.2}px)`;
        hero.style.pointerEvents = opacity < 0.1 ? 'none' : 'auto';
      } else {
        hero.style.opacity = '1';
        hero.style.transform = 'scale(1) translateY(0)';
        hero.style.pointerEvents = 'auto';
      }

      // Handle individual pill "near top" effect
      const pills = document.querySelectorAll('.pill-pair');
      pills.forEach((pill) => {
        const rect = pill.getBoundingClientRect();
        if (rect.top < 200 && rect.top > 0) {
          pill.classList.add('near-top');
        } else {
          pill.classList.remove('near-top');
        }
      });
    };

    container.addEventListener('scroll', handleScroll, { passive: true });
    handleScroll();

    return () => {
      observer.disconnect();
      container.removeEventListener('scroll', handleScroll);
    };
  }, []);

  return (
    <div className="home-wrapper waitlist-page">
      <div className="noise-overlay" />

      <div className="hero-bg-container">
        <img src="/wons.gif" alt="Live gameplay" className="hero-bg-video" loading="lazy" />
        <div className="hero-overlay" />
      </div>

      {/* FIXED HERO SECTION */}
      <header className="waitlist-hero">
        <div className="hero-content">
          <h1 className="hero-headline">Competitive gaming with real rewards.</h1>
          <p className="hero-subtext">
            Play. Win. Get paid. First matches live this week. Join the elite.
          </p>
        </div>
      </header>

      <main className="waitlist-scroll-container">
        {/* HERO CAPTURE AREA */}
        <section className="waitlist-section" style={{ minHeight: '70vh' }}>
          <EmailCapture
            buttonLabel="Join Early Access"
            helperText="Get beta access, rewards, and match invites"
          />
        </section>

        {/* EARLY TRACTION */}
        <section className="waitlist-section">
          <h2 className="section-title">Early traction</h2>
          <div className="pill-group">
            <PillPair top="312" bottom="Players joined" rotation={-2} />
            <PillPair top="18" bottom="Matches created" rotation={3} />
            <PillPair top="$0.10" bottom="Rewards paid" rotation={-1.5} />
            <PillPair top="5" bottom="Sponsors" rotation={4} />
          </div>
        </section>

        {/* HOW IT WORKS */}
        <section className="waitlist-section">
          <h2 className="section-title">How it works</h2>
          <div className="pill-group">
            <PillPair top="01" bottom="Join waitlist" rotation={1.5} isAlt />
            <PillPair top="02" bottom="Get access to matches" rotation={-2.5} isAlt />
            <PillPair top="03" bottom="Compete & earn" rotation={2} isAlt />
          </div>
        </section>

        {/* WHY IT'S DIFFERENT */}
        <section className="waitlist-section">
          <h2 className="section-title">Why we win</h2>
          <div className="pill-group">
            <PillPair top="Edge" bottom="No downloads" rotation={-3} />
            <PillPair top="Speed" bottom="Instant matches" rotation={2.5} />
            <PillPair top="Value" bottom="Real rewards" rotation={-1} />
            <div className="pill-pair" style={{ marginTop: '20px' }}>
               <p className="pill-label-top" style={{ fontSize: '16px', opacity: 0.8 }}>Powered onchain</p>
            </div>
          </div>
        </section>
      </main>
    </div>
  );
};

export default Waitlist;
