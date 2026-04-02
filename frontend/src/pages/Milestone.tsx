import React from "react";
import "./Milestone.css";

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
      quarter: "Q4 2025",
      title: "Closed Alpha Matches",
      description: "First 500 players tested real-time match flow, payouts, and anti-bot controls.",
      highlight: "500 alpha players onboarded",
      reached: true,
    },
    {
      quarter: "Q1 2026",
      title: "Sponsor Match Pools",
      description: "Host-backed prize pools launched with weekly events and instant reward settlement.",
      highlight: "$7.3K+ distributed in rewards",
      reached: true,
    },
    {
      quarter: "Q2 2026",
      title: "Leaderboard Seasons",
      description: "Seasonal ranking with trackable progression and improved player stat visibility.",
      highlight: "200K+ matches recorded",
      reached: true,
    },
    {
      quarter: "Q3 2026",
      title: "Creator Tournaments",
      description: "Creator-run brackets with custom challenge formats and larger audience reach.",
      highlight: "40+ active hosts",
      reached: false,
    },
    {
      quarter: "Q4 2026",
      title: "Mobile Performance Push",
      description: "Gameplay and matchmaking optimization for lower-latency sessions across devices.",
      highlight: "30% faster average match start",
      reached: false,
    },
    {
      quarter: "Q1 2027",
      title: "Regional Championship Layer",
      description: "Cross-region finals with host-backed brackets and expanded reward tiers.",
      highlight: "Planned global season rollout",
      reached: false,
    },
  ];

  return (
    <div className="milestone-container">
      <div style={{ height: "60px" }} />
      <h1 className="milestone-title">Milestone</h1>
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
    </div>
  );
};

export default Milestone;
