import React, { useEffect } from "react";
import EmailCapture from "../components/waitlist/EmailCapture";
import MetricsGrid from "../components/waitlist/MetricsGrid";
import "./Waitlist.css";

const waitlistMetrics = [
  { label: "Players joined", value: "312" },
  { label: "Matches created", value: "18" },
  { label: "Rewards paid", value: "$0.10" },
  { label: "Sponsors", value: "5" },
];

const Waitlist: React.FC = () => {
  useEffect(() => {
    const revealEls = Array.from(document.querySelectorAll<HTMLElement>(".waitlist-page .reveal"));
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

    return () => {
      revealObserver.disconnect();
    };
  }, []);

  return (
    <div className="home-wrapper waitlist-page">
      <div className="noise-overlay" />

      <section className="hero-section waitlist-hero">
        <div className="hero-bg-container">
          <img src="/wons.gif" alt="Live gameplay" className="hero-bg-video" loading="lazy" />
          <div className="hero-overlay" />
        </div>

        <div className="hero-content reveal">
          <h1 className="waitlist-headline">Competitive gaming with real rewards.</h1>
          <p className="waitlist-subtext">Play. Win. Get paid. First matches live this week.</p>
          <EmailCapture
            buttonLabel="Join Early Access"
            helperText="Get beta access, rewards, and match invites"
          />
        </div>
      </section>



      <section className="events-grid-section waitlist-section">
        <h2 className="section-title reveal">Early traction</h2>
        <MetricsGrid metrics={waitlistMetrics} />
      </section>

      <section className="events-grid-section waitlist-section reveal">
        <h2 className="section-title">How it works</h2>
        <div className="waitlist-steps-grid">
          {[
            "Join waitlist",
            "Get access to matches",
            "Compete & earn",
          ].map((step, index) => (
            <article key={step} className="tweet-card waitlist-step-card">
              <span className="waitlist-step-icon">0{index + 1}</span>
              <p className="waitlist-step-label">{step}</p>
            </article>
          ))}
        </div>
      </section>

      <section className="events-grid-section waitlist-section reveal">
        <h2 className="section-title">Why it’s different</h2>
        <div className="waitlist-pill-row">
          {[
            "No downloads",
            "Instant matches",
            "Real rewards",
          ].map((item) => (
            <span key={item} className="waitlist-pill">{item}</span>
          ))}
        </div>
        <p className="waitlist-powered">Powered onchain</p>
      </section>


    </div>
  );
};

export default Waitlist;
