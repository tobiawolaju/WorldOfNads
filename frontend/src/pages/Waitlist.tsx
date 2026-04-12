import React, { useEffect } from "react";
import EmailCapture from "../components/waitlist/EmailCapture";
import "./Waitlist.css";

const PillPair: React.FC<{ top: string; bottom: string; rotation: number; isAlt?: boolean; isNearTop?: boolean }> = ({ top, bottom, rotation, isAlt, isNearTop }) => (
  <div
    className={`pill-pair ${isAlt ? 'alt-color' : ''} ${isNearTop ? 'near-top' : ''}`}
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
    const container = document.querySelector('.waitlist-scroll-container');
    if (!container) return;

    const handleScroll = () => {
      const sections = document.querySelectorAll('.waitlist-section');
      sections.forEach((section) => {
        const rect = section.getBoundingClientRect();
        // If section is entering viewport
        if (rect.top < window.innerHeight * 0.8) {
          section.classList.add('revealed');
        }

        // Handle pill fade-out near top
        const pills = section.querySelectorAll('.pill-pair');
        pills.forEach((pill) => {
          const pillRect = pill.getBoundingClientRect();
          if (pillRect.top < 150) {
            pill.classList.add('near-top');
          } else {
            pill.classList.remove('near-top');
          }
        });
      });
    };

    container.addEventListener('scroll', handleScroll);
    handleScroll(); // Initial check

    return () => container.removeEventListener('scroll', handleScroll);
  }, []);

  return (
    <div className="home-wrapper waitlist-page">
      <div className="noise-overlay" />

      <div className="hero-bg-container">
        <img src="/wons.gif" alt="Live gameplay" className="hero-bg-video" loading="lazy" />
        <div className="hero-overlay" />
      </div>

      {/* FIXED HERO SECTION */}
      <section className="waitlist-hero revealed">
        <div className="hero-content">
          <h1 className="hero-headline">Competitive gaming with real rewards.</h1>
          <p className="hero-subtext" style={{ color: 'rgba(255,255,255,0.7)', fontSize: '20px' }}>
            Play. Win. Get paid. First matches live this week.
          </p>
          <EmailCapture
            buttonLabel="Join Early Access"
            helperText="Get beta access, rewards, and match invites"
          />
        </div>
      </section>

      <div className="waitlist-scroll-container">
        {/* EMPTY SPACER FOR THE FIXED HERO */}
        <div style={{ height: '50vh' }}></div>

        {/* EARLY TRACTION */}
        <section className="waitlist-section">
          <h2 className="section-title">Early traction</h2>
          <div className="pill-group" style={{ gap: '60px' }}>
            <PillPair top="312" bottom="Players joined" rotation={-3} />
            <PillPair top="18" bottom="Matches created" rotation={2} />
            <PillPair top="$0.10" bottom="Rewards paid" rotation={-1} />
            <PillPair top="5" bottom="Sponsors" rotation={4} />
          </div>
        </section>

        {/* HOW IT WORKS */}
        <section className="waitlist-section">
          <h2 className="section-title">How it works</h2>
          <div className="pill-group" style={{ gap: '60px' }}>
            <PillPair top="01" bottom="Join waitlist" rotation={2} isAlt />
            <PillPair top="02" bottom="Get access to matches" rotation={-2} isAlt />
            <PillPair top="03" bottom="Compete & earn" rotation={1} isAlt />
          </div>
        </section>

        {/* WHY IT'S DIFFERENT */}
        <section className="waitlist-section">
          <h2 className="section-title">Why it’s different</h2>
          <div className="pill-group" style={{ gap: '40px' }}>
            <PillPair top="Edge" bottom="No downloads" rotation={-4} />
            <PillPair top="Speed" bottom="Instant matches" rotation={3} />
            <PillPair top="Value" bottom="Real rewards" rotation={-2} />
            <div className="pill-pair" style={{ marginTop: '20px' }}>
              <p className="waitlist-powered">Powered onchain</p>
            </div>
          </div>
        </section>
      </div>
    </div>
  );
};

export default Waitlist;
