import React from "react";
import "./Milestone.css";
import Footer from "../components/Footer";

type MilestoneItem = {
  phase: "live" | "next" | "growth" | "scale" | "future" | "beyond";
  title: string;
  description: string;
  metrics: Record<string, string | number | boolean>;
  status: "completed" | "in_progress" | "pending";
};

const formatPhase = (phase: MilestoneItem["phase"]) =>
  phase.charAt(0).toUpperCase() + phase.slice(1);

const formatMetricKey = (key: string) =>
  key
    .split("_")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");

const formatMetricValue = (value: string | number | boolean) => {
  if (typeof value === "boolean") return value ? "Yes" : "No";
  return String(value);
};

const Milestone: React.FC = () => {
  const events: MilestoneItem[] = [
    {
      phase: "live",
      title: "Playable Core System",
      description:
        "Real-time multiplayer browser game with working match flow and session lifecycle.",
      metrics: {
        matches_completed: 2,
        match_completion_rate: 100,
        avg_players_per_match: 2.0,
      },
      status: "completed",
    },
    {
      phase: "live",
      title: "Escrow Validation",
      description:
        "Working payout system with real value transfers and automated settlement.",
      metrics: {
        total_rewards_distributed: 0.1,
        successful_payouts: 2,
        failed_payouts: 0,
      },
      status: "completed",
    },
    {
      phase: "live",
      title: "Early Analytics Layer",
      description:
        "Tracking gameplay, users, and reward flow across matches.",
      metrics: {
        total_users: 4,
        daily_active_users: 2,
        matches_tracked: 2,
      },
      status: "completed",
    },
    {
      phase: "live",
      title: "Initial Community",
      description:
        "Early testers actively playing matches and providing feedback.",
      metrics: {
        returning_users: 2,
        total_players: 4,
      },
      status: "completed",
    },
    {
      phase: "next",
      title: "First Competitive Loop",
      description:
        "Players return to play multiple matches and begin exhibiting competitive behavior.",
      metrics: {
        target_repeat_player_rate: "20%",
        target_matches_per_user: 3,
      },
      status: "in_progress",
    },
    {
      phase: "next",
      title: "Match Reliability Layer",
      description:
        "Ensure matches are fair, synchronized, and consistently complete without errors.",
      metrics: {
        target_match_success_rate: "95%+",
        target_desync_rate: "<5%",
      },
      status: "pending",
    },
    {
      phase: "next",
      title: "Sponsor-to-Match Flow",
      description:
        "End-to-end flow where sponsors fund matches and payouts complete automatically.",
      metrics: {
        target_sponsor_funded_matches: 5,
        target_sponsor_conversion: "50%",
      },
      status: "pending",
    },
    {
      phase: "next",
      title: "Closed Economy Test",
      description:
        "Validate loop where rewards are reinvested into new matches.",
      metrics: {
        target_reinvestment_rate: "30%",
        target_repeat_matches_from_rewards: 5,
      },
      status: "pending",
    },
    {
      phase: "next",
      title: "Player Onboarding Funnel",
      description:
        "Optimize flow from landing → match start → match completion.",
      metrics: {
        target_start_rate: "60%",
        target_completion_rate: "80%",
      },
      status: "pending",
    },
    {
      phase: "next",
      title: "Anti-Cheat / Fair Play Layer (V1)",
      description:
        "Detect abnormal gameplay behavior and flag suspicious matches.",
      metrics: {
        target_detection_accuracy: "80%",
        flagged_matches_tracked: true,
      },
      status: "pending",
    },
    {
      phase: "growth",
      title: "Retention Signal",
      description:
        "Measure and improve player return behavior over time.",
      metrics: {
        target_day1_retention: "25%",
        target_day7_retention: "15%",
      },
      status: "pending",
    },
    {
      phase: "growth",
      title: "Skill Expression Layer",
      description:
        "Introduce mechanics that reward strategy, timing, and positioning.",
      metrics: {
        player_skill_variance_detected: true,
        repeat_competitive_matches: 10,
      },
      status: "pending",
    },
    {
      phase: "growth",
      title: "Insights & Analytics Upgrade",
      description:
        "Move from tracking to actionable insights like player behavior and win patterns.",
      metrics: {
        top_player_tracking: true,
        win_pattern_analysis: true,
      },
      status: "pending",
    },
    {
      phase: "scale",
      title: "Lightweight Matchmaking",
      description:
        "Group players by skill level or win rate for fairer matches.",
      metrics: {
        skill_based_matches: "enabled",
        reduced_skill_gap: true,
      },
      status: "pending",
    },
    {
      phase: "scale",
      title: "Competitive Identity",
      description:
        "Introduce player profiles, stats, streaks, and leaderboard.",
      metrics: {
        leaderboard_active: true,
        player_profiles_created: 100,
      },
      status: "pending",
    },
    {
      phase: "scale",
      title: "Sponsor Marketplace",
      description:
        "Allow sponsors to fund specific match types and formats.",
      metrics: {
        target_active_sponsors: 50,
        match_types_sponsored: 3,
      },
      status: "pending",
    },
    {
      phase: "future",
      title: "Game Engine Abstraction",
      description:
        "Abstract core systems (escrow, matchmaking, competition) into reusable modules.",
      metrics: {
        core_modules_extracted: 3,
        sdk_ready: true,
      },
      status: "pending",
    },
    {
      phase: "future",
      title: "Multi-Game Expansion",
      description:
        "Enable multiple games to plug into the same competitive infrastructure.",
      metrics: {
        games_integrated: 3,
        shared_player_pool: true,
      },
      status: "pending",
    },
    {
      phase: "beyond",
      title: "On-Chain Competitive Layer",
      description:
        "Transform into a reusable competition and reward infrastructure for games.",
      metrics: {
        external_games_integrated: 5,
        monthly_active_players: 10000,
      },
      status: "pending",
    },
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
            className={`milestone-row ${event.status === "completed" ? "reached" : "unreached"}`}
          >
            <div className="milestone-time">
              <span>{formatPhase(event.phase)}</span>
            </div>
            <div className="milestone-marker" aria-hidden="true">
              <span className="milestone-dot" />
            </div>
            <div className="milestone-event">
              <h2>{event.title}</h2>
              <p>{event.description}</p>
              <p className="milestone-highlight">
                {Object.entries(event.metrics)
                  .map(([key, value]) => `${formatMetricKey(key)}: ${formatMetricValue(value)}`)
                  .join(" • ")}
              </p>
            </div>
          </article>
        ))}
      </section>
      <Footer />
    </div>
  );
};

export default Milestone;
