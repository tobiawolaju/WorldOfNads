import React from "react";
import "./Milestone.css";
import Footer from "../components/Footer";

type MilestoneEvent = {
  quarter: string;
  title: string;
  description: string;
  highlight: string;
  reached: boolean;
};

const Milestone: React.FC = () => {
  const events: MilestoneEvent[] = [
    {
      quarter: "Live",
      title: "Playable Game + Core System",
      description:
        "A fully playable browser-based multiplayer game with real-time matches, payout system, and smooth session flow.",
      highlight: "Live game with real players",
      reached: true,
    },
    {
      quarter: "Live",
      title: "Payout & Escrow System",
      description:
        "Matches settle instantly with built-in escrow. Winners receive rewards automatically without manual steps.",
      highlight: "$7K+ paid to players",
      reached: true,
    },
    {
      quarter: "Live",
      title: "Analytics & Tracking",
      description:
        "Full visibility into gameplay and transactions through Google Analytics, Dune dashboards, and internal tracking tools.",
      highlight: "200K+ matches tracked",
      reached: true,
    },
    {
      quarter: "Live",
      title: "Community & Distribution",
      description:
        "Active Discord and X presence with early players testing matches and providing feedback.",
      highlight: "Early player base established",
      reached: true,
    },
    {
      quarter: "Live",
      title: "Security & Audit Readiness",
      description:
        "Core systems structured for transparency and review, with audit processes prepared as the platform scales.",
      highlight: "Audit-ready architecture",
      reached: true,
    },

    // 🚀 NEXT PHASE

    {
      quarter: "Next",
      title: "Initial Sponsor Onboarding",
      description:
        "Bring in the first wave of sponsors to fund matches and establish consistent competitive activity.",
      highlight: "Target: 10 sponsors",
      reached: false,
    },
    {
      quarter: "Next",
      title: "Early Player Growth",
      description:
        "Grow the active player base through direct onboarding and community-driven playtests.",
      highlight: "Target: 100 active players",
      reached: false,
    },
    {
      quarter: "Next",
      title: "Gameplay Optimization",
      description:
        "Improve responsiveness, reduce latency, and refine core mechanics to make matches smoother and more engaging.",
      highlight: "Faster, smoother matches",
      reached: false,
    },
    {
      quarter: "Next",
      title: "Retention & Competitive Loop",
      description:
        "Enhance the gameplay loop to increase repeat play through better match flow, tension, and competitive dynamics.",
      highlight: "Higher player return rate",
      reached: false,
    },

    // 🔥 SCALE PHASE

    {
      quarter: "Scale",
      title: "Sponsor Expansion",
      description:
        "Expand sponsor participation as match activity increases and visibility grows inside the game.",
      highlight: "Target: 50+ sponsors",
      reached: false,
    },
    {
      quarter: "Scale",
      title: "Player Growth",
      description:
        "Scale the player base through improved gameplay, competition, and organic engagement loops.",
      highlight: "Target: 1,000+ players",
      reached: false,
    },
    {
      quarter: "Scale",
      title: "System Scaling",
      description:
        "Increase match volume, optimize session flow, and support higher concurrency across players and matches.",
      highlight: "High match throughput",
      reached: false,
    },
    {
      quarter: "Future",
      title: "Mass Adoption Push",
      description:
        "Grow into a large-scale competitive platform with strong retention and continuous match activity.",
      highlight: "10K+ players → 100K+ → 1M",
      reached: false,
    },
    {
      quarter: "Beyond",
      title: "Multi-Game Expansion",
      description:
        "Expand beyond a single game into multiple competitive experiences built on the same core system. New modes, mini-games, and formats plug into the same match and competition layer.",
      highlight: "From one game → many experiences",
      reached: false,
    },
    {
      quarter: "Beyond",
      title: "Competitive Gaming Layer",
      description:
        "Evolve into a shared competitive layer that can power multiple games and experiences. Matches, rewards, and competition become reusable across different formats and audiences.",
      highlight: "A system that grows with every game",
      reached: false,
    }
  ];

  return (
    <div className="milestone-container">
      <div style={{ height: "60px" }} />
      <h1 className="milestone-title">Progress</h1>
      <p className="milestone-description">Major product and competition moments across WONs.</p>

      <section className="milestone-track" aria-label="Milestone timeline">
        {events.map((event) => (
          <article
            key={event.title}
            className={`milestone-row ${event.reached ? "reached" : "unreached"}`}
          >
            <div className="milestone-time">
              <span>{event.quarter}</span>
            </div>
            <div className="milestone-marker" aria-hidden="true">
              <span className="milestone-dot" />
            </div>
            <div className="milestone-event">
              <h2>{event.title}</h2>
              <p>{event.description}</p>
              <p className="milestone-highlight">{event.highlight}</p>
            </div>
          </article>
        ))}
      </section>
      <Footer />
    </div>
  );
};

export default Milestone;
