import React, { useState } from "react";
import "./PreTGEArena.css";

function PreTGEArena() {
  const [searchTerm, setSearchTerm] = useState("");
  const [filterStatus, setFilterStatus] = useState("all"); // 'all', 'upcoming', 'live', 'completed'

  const [projects] = useState([
    {
      id: 1,
      name: "Monad Mainnet",
      tagline: "High-performance EVM-compatible Layer 1.",
      description:
        "Monad is a high-performance EVM-compatible Layer 1 blockchain with 10,000 TPS, 1-second block times, and sub-cent fees.",
      stage: "live",
      launchDate: "Live Now",
      xHandle: "@monad_xyz",
      logo: "https://pbs.twimg.com/profile_images/1861739634428174336/26FzLLyr.jpg",
      reward: "10 MON",
      url: "https://x.com/monad_xyz",
    },
    {
      id: 18,
      name: "Monad Testnet",
      tagline: "The early testing environment.",
      description:
        "Experience high-performance consensus and execution before Mainnet launch. The foundation of the Monad ecosystem.",
      stage: "completed",
      launchDate: "Completed",
      xHandle: "@monad_xyz",
      logo: "https://pbs.twimg.com/profile_images/1861739634428174336/26FzLLyr.jpg",
      reward: "Testnet MON",
      url: "https://x.com/monad_xyz",
    },
    {
      id: 17,
      name: "LootGO",
      tagline: "Discover → Play → Earn.",
      description:
        "The ultimate on-chain discovery app. Turn every interaction into real rewards.",
      stage: "upcoming",
      launchDate: "Upcoming",
      xHandle: "@lootgo_official",
      logo: "https://pbs.twimg.com/profile_images/1947490514921488384/TLSJg7Z5.jpg",
      reward: "50,000 WONs",
      url: "https://x.com/lootgo_official",
    },
    {
      id: 2,
      name: "Nad.fun",
      tagline: "The most degenerate memecoin arena.",
      description:
        "The most degenerate memecoin arena on Monad. Launch, pump, snipe, rug — pure chaos, zero mercy.",
      stage: "upcoming",
      launchDate: "Upcoming",
      xHandle: "@naddotfun",
      logo: "https://pbs.twimg.com/profile_images/1827607782356619264/Owr-840k.jpg",
      reward: "22,000 WONs",
      url: "https://x.com/naddotfun",
    },
    {
      id: 3,
      name: "Kizzy Mobile",
      tagline: "Web3 in your pocket.",
      description:
        "The fastest mobile gateway to on-chain games, rewards, and social quests.",
      stage: "upcoming",
      launchDate: "Upcoming",
      xHandle: "@kizzymobile",
      logo: "https://pbs.twimg.com/profile_images/2000251466468978688/Q7hvNgR3.jpg",
      reward: "14,500 WONs",
      url: "https://x.com/kizzymobile",
    },
    {
      id: 4,
      name: "Kuru Exchange",
      tagline: "Lightning-fast perpetuals on Monad.",
      description: "Up to 100x leverage, deep liquidity, zero gas drama.",
      stage: "upcoming",
      launchDate: "Upcoming",
      xHandle: "@KuruExchange",
      logo: "https://pbs.twimg.com/profile_images/1950962142917619714/R7Cj_qk7.jpg",
      reward: "5,000 WONs",
      url: "https://x.com/KuruExchange",
    },
    {
      id: 5,
      name: "Lumiterra",
      tagline: "An open-world MMORPG.",
      description:
        "An open-world MMORPG where you fight, farm, craft, and own your destiny across infinite lands.",
      stage: "upcoming",
      launchDate: "Upcoming",
      xHandle: "@LumiterraGame",
      logo: "https://pbs.twimg.com/profile_images/1667436896480563200/8YPmbLbv.png",
      reward: "10,000 WONs",
      url: "https://x.com/LumiterraGame",
    },
    {
      id: 6,
      name: "Levr Bet",
      tagline: "Prediction markets & sports betting.",
      description:
        "Prediction markets & sports betting on-chain. Bet with leverage, earn with accuracy.",
      stage: "upcoming",
      launchDate: "Upcoming",
      xHandle: "@Levr_Bet",
      logo: "https://pbs.twimg.com/profile_images/1836024387042004992/YKdDMkOG.jpg",
      reward: "7,500 WONs",
      url: "https://x.com/Levr_Bet",
    },
    {
      id: 7,
      name: "Drake Exchange",
      tagline: "Next-gen perpetuals & spot trading.",
      description:
        "Next-gen perpetuals & spot trading on Monad. Fast. Cheap. Ruthless execution.",
      stage: "upcoming",
      launchDate: "Upcoming",
      xHandle: "@DrakeExchange",
      logo: "https://pbs.twimg.com/profile_images/1974759389354491904/2vcC-dd4.jpg",
      reward: "25,000 WONs",
      url: "https://x.com/DrakeExchange",
    },
    {
      id: 8,
      name: "Omnia Explorer",
      tagline: "The most powerful Monad block explorer.",
      description: "Real-time analytics, mempool sniper, gamified quests.",
      stage: "upcoming",
      launchDate: "Upcoming",
      xHandle: "@ExploreOmnia",
      logo: "https://pbs.twimg.com/profile_images/1796709016808394752/C91LWB9H.jpg",
      reward: "13,000 WONs",
      url: "https://x.com/ExploreOmnia",
    },
    {
      id: 9,
      name: "SeerTrade",
      tagline: "Advanced trading terminal for Monad.",
      description:
        "Sniping, copy-trading, AI signals, limit orders that actually fill.",
      stage: "upcoming",
      launchDate: "Upcoming",
      xHandle: "@seertrade",
      logo: "https://pbs.twimg.com/profile_images/1992956835922587649/6s2RZ9xf.jpg",
      reward: "9,800 WONs",
      url: "https://x.com/seertrade",
    },
    {
      id: 10,
      name: "Monday Trade",
      tagline: "Set it and forget it.",
      description:
        "Automated DCA, grid, and martingale bots for Monad degens.",
      stage: "upcoming",
      launchDate: "Upcoming",
      xHandle: "@MondayTrade_",
      logo: "https://pbs.twimg.com/profile_images/1973421191202209797/qRXSiR5e.jpg",
      reward: "6,400 WONs",
      url: "https://x.com/MondayTrade_",
    },
    {
      id: 11,
      name: "Symphony",
      tagline: "Social trading on Monad.",
      description:
        "Follow top traders, copy flows, split profits, climb the leaderboard.",
      stage: "upcoming",
      launchDate: "Upcoming",
      xHandle: "@symphonyio",
      logo: "https://pbs.twimg.com/profile_images/1893386930605211648/-APwnLNM.jpg",
      reward: "18,200 WONs",
      url: "https://x.com/symphonyio",
    },
    {
      id: 12,
      name: "Kinetik AI",
      tagline: "AI-powered on-chain movement battles.",
      description: "Run, jump, dodge — turn your activity into crypto.",
      stage: "upcoming",
      launchDate: "Upcoming",
      xHandle: "@KINETK_AI",
      logo: "https://pbs.twimg.com/profile_images/1947607859702673408/hpZ89aya.jpg",
      reward: "33,000 WONs",
      url: "https://x.com/KINETK_AI",
    },
    {
      id: 13,
      name: "TeleMafia",
      tagline: "The ultimate Telegram mafia game.",
      description: "Lie, betray, vote out — last don standing wins the pot.",
      stage: "upcoming",
      launchDate: "Upcoming",
      xHandle: "@TeleMafia",
      logo: "https://pbs.twimg.com/profile_images/1967887075316994050/STzEqU1y.jpg",
      reward: "20,000 WONs",
      url: "https://x.com/TeleMafia",
    },
    {
      id: 14,
      name: "Fluffle World",
      tagline: "Home of the cutest bunnies on Monad.",
      description: "Collect, breed, battle, fluff.",
      stage: "upcoming",
      launchDate: "Upcoming",
      xHandle: "@fluffleworld",
      logo: "https://pbs.twimg.com/profile_images/1972672305336569856/JLjBcagi.jpg",
      reward: "42,000 WONs",
      url: "https://x.com/fluffleworld",
    },
    {
      id: 15,
      name: "BRO.fun",
      tagline: "For the bros, by the bros.",
      description: "Gaming, memes, gains — pure brotherhood on Monad.",
      stage: "upcoming",
      launchDate: "Upcoming",
      xHandle: "@bro_dot_fun",
      logo: "https://pbs.twimg.com/profile_images/1983519855279042560/ntgzrOaU.jpg",
      reward: "18,000 WONs",
      url: "https://x.com/bro_dot_fun",
    },
    {
      id: 16,
      name: "RareBet Sports",
      tagline: "Elite on-chain sports betting.",
      description:
        "Parlay everything, leverage your takes, get paid instantly.",
      stage: "upcoming",
      launchDate: "Upcoming",
      xHandle: "@RareBetSports",
      logo: "https://pbs.twimg.com/profile_images/1802788848956506112/KJnlcaQj.jpg",
      reward: "55,000 WONs",
      url: "https://x.com/RareBetSports",
    },
  ]);

  // Combined filtering logic
  const filteredProjects = projects
    .filter((project) => {
      if (filterStatus === "all") {
        return true;
      }
      return project.stage === filterStatus;
    })
    .filter((project) =>
      project.name.toLowerCase().includes(searchTerm.toLowerCase())
    );





  const renderStatusBadge = (stage) => {
    const map = {
      live: "pretge-status-live",
      upcoming: "pretge-status-upcoming",
      completed: "pretge-status-completed",
    };

    return (
      <span className={`pretge-status ${map[stage]}`}>
        {stage}
      </span>
    );
  };





  return (
    <div className="pretge-container">
      <div style={{ height: "60px" }}></div>
      <h1 className="pretge-title">Nad Arena</h1>
      <p className="pretge-intro">
        Discover the next wave of innovation. Early access to groundbreaking
        projects before they launch.
      </p>

      {/* Search Bar */}
      <div className="search-wrapper">
        <input
          type="text"
          placeholder="Search for projects..."
          value={searchTerm}
          onChange={(e) => setSearchTerm(e.target.value)}
          className="partner-search"
        />
      </div>

      {/* Filter Buttons */}
      <div className="filter-buttons">
        <button
          className={filterStatus === "all" ? "active" : ""}
          onClick={() => setFilterStatus("all")}
        >
          All
        </button>
        <button
          className={filterStatus === "upcoming" ? "active" : ""}
          onClick={() => setFilterStatus("upcoming")}
        >
          Upcoming
        </button>
        <button
          className={filterStatus === "live" ? "active" : ""}
          onClick={() => setFilterStatus("live")}
        >
          Live
        </button>
        <button
          className={filterStatus === "completed" ? "active" : ""}
          onClick={() => setFilterStatus("completed")}
        >
          Completed
        </button>
      </div>

      {/* Project Grid */}
      <div className="pretge-grid">
        {filteredProjects.length > 0 ? (
          filteredProjects.map((project) => (
            <div
              key={project.id}
              className={`pretge-card pretge-card-${project.stage}`}
            >
              <div className="pretge-card-header">
                <img
                  src={project.logo}
                  alt={`${project.name} logo`}
                  className="pretge-logo"
                />
                <h2 className="pretge-project-name">{project.name}</h2>
              </div>
              <p className="pretge-tagline">{project.tagline}</p>
              <p className="pretge-description">{project.description}</p>
              <div className="pretge-meta">
                {renderStatusBadge(project.stage)}
                <span className="pretge-handle">
                  <a
                    href={project.url}
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    {project.xHandle}
                  </a>
                </span>
              </div>

            </div>
          ))
        ) : (
          <p style={{ color: "#718096" }}>
            No projects match your criteria.
          </p>
        )}
      </div>
    </div>
  );
}

export default PreTGEArena;