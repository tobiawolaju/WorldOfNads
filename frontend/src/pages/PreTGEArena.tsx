import React, { useState } from "react";
import "./PreTGEArena.css";

function PreTGEArena() {
  const [searchTerm, setSearchTerm] = useState("");

  const [projects] = useState([
    {
      name: "NovaForge",
      tagline: "Decentralized engine for AI-powered worlds.",
      description:
        "NovaForge is building the first modular AI game infrastructure that lets anyone create persistent, learning-driven universes — all backed by on-chain logic.",
      stage: "Pre-TGE",
      launchDate: "Q1 2026",
      xHandle: "@NovaForge_AI",
      logo: "/w.png",
    },
    {
      name: "EchoDrift",
      tagline: "Battle. Trade. Ascend.",
      description:
        "EchoDrift is a PvP multiverse combat arena where every weapon and ability is an NFT. The game uses zkSync to ensure fast, gasless battles.",
      stage: "Pre-TGE",
      launchDate: "Q2 2026",
      xHandle: "@EchoDriftGame",
      logo: "/w.png",
    },
    {
      name: "Mythra Protocol",
      tagline: "DeFi meets adventure.",
      description:
        "Mythra Protocol turns exploration into yield farming. Players stake time, not tokens, and earn governance shares through adventure events.",
      stage: "Private Sale",
      launchDate: "Q4 2025",
      xHandle: "@MythraProtocol",
      logo: "/w.png",
    },
    {
      name: "Orion Frontier",
      tagline: "A living galaxy for builders.",
      description:
        "A cross-chain MMO simulation where players colonize planets, build economies, and script automation using smart contracts.",
      stage: "Seed Stage",
      launchDate: "Q3 2025",
      xHandle: "@OrionFrontier",
      logo: "/w.png",
    },
  ]);

  // Filter projects by search input (case-insensitive)
  const filteredProjects = projects.filter((project) =>
    project.name.toLowerCase().includes(searchTerm.toLowerCase())
  );

  return (
    <div className="pretge-container">
      <div style={{ height: "60px" }}></div>

      <h1 className="partners-title">Pre Token GA</h1>
      <p className="partners-description">
        Be the first to discover the next moon ride
      </p>

      {/* Search Bar */}
      <div className="search-wrapper">
        <input
          type="text"
          placeholder="Search for a project..."
          value={searchTerm}
          onChange={(e) => setSearchTerm(e.target.value)}
          className="partner-search"
        />
      </div>

      {/* Project Grid */}
      <div className="pretge-grid">
        {filteredProjects.length > 0 ? (
          filteredProjects.map((project, index) => (
            <div key={index} className="pretge-card">
              <img
                src={project.logo}
                alt={project.name}
                className="pretge-logo"
              />
              <h2 className="pretge-project-name">{project.name}</h2>
              <p className="pretge-tagline">{project.tagline}</p>
              <p className="pretge-description">{project.description}</p>
              <div className="pretge-meta">
                <span className="pretge-stage">{project.stage}</span>
                <span className="pretge-launch">
                  Launch: {project.launchDate}
                </span>
              </div>
              <p className="pretge-handle">
                <a
                  href={`https://twitter.com/${project.xHandle.replace("@", "")}`}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  {project.xHandle}
                </a>
              </p>
            </div>
          ))
        ) : (
          <p style={{ marginTop: "40px", color: "#777" }}>
            No matching projects found.
          </p>
        )}
      </div>
    </div>
  );
}

export default PreTGEArena;
