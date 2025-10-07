import React, { useState } from "react";
import { LineChart, Line, ResponsiveContainer, Tooltip } from "recharts";
import "./Leaderboard.css";

interface Project {
  name: string;
  interactions: number;
  trend: number[];
  logo: string;
}

interface User {
  username: string;
  won: number;
  project: string;
  pfp: string;
}

const Leaderboard: React.FC = () => {
  const projects: Project[] = [
    { name: "NovaForge", interactions: 120, trend: [100, 110, 95, 120, 130, 125, 140], logo: "/logos/ape.png" },
    { name: "EchoDrift", interactions: 95, trend: [70, 80, 90, 85, 95, 100, 110], logo: "/logos/ape.png" },
    { name: "Mythra Protocol", interactions: 160, trend: [150, 155, 140, 160, 170, 165, 180], logo: "/logos/ape.png" },
    { name: "Orion Frontier", interactions: 80, trend: [60, 65, 70, 75, 80, 78, 85], logo: "/logos/ape.png" },
    { name: "Astra Dawn", interactions: 45, trend: [30, 35, 40, 45, 42, 48, 50], logo: "/logos/ape.png" },
    { name: "LumaCore", interactions: 140, trend: [120, 130, 125, 135, 145, 150, 155], logo: "/logos/ape.png" },
    { name: "ZephyrNet", interactions: 110, trend: [90, 95, 100, 110, 120, 115, 125], logo: "/logos/ape.png" },
    { name: "HoloLink", interactions: 70, trend: [50, 55, 60, 65, 68, 70, 75], logo: "/logos/ape.png" },
    { name: "DriftLabs", interactions: 150, trend: [130, 135, 145, 150, 155, 160, 170], logo: "/logos/ape.png" },
    { name: "Cryovault", interactions: 100, trend: [80, 90, 95, 100, 105, 110, 108], logo: "/logos/ape.png" },
  ];

  const allUsers: User[] = [
    { username: "0xNadLord", won: 580, project: "NovaForge", pfp: "/logos/ape.png" },
    { username: "0xShinobi", won: 460, project: "EchoDrift", pfp: "/logos/ape.png" },
    { username: "0xWanderer", won: 410, project: "Mythra Protocol", pfp: "/logos/ape.png" },
    { username: "0xDataGhost", won: 360, project: "NovaForge", pfp: "/logos/ape.png" },
    { username: "0xVoidHero", won: 320, project: "Orion Frontier", pfp: "/logos/ape.png" },
    { username: "0xMoonSmith", won: 270, project: "Astra Dawn", pfp: "/logos/ape.png" },
  ];

  const [selectedProject, setSelectedProject] = useState<string | null>(null);
  const [searchTerm, setSearchTerm] = useState("");

  const filteredProjects = projects.filter((p) =>
    p.name.toLowerCase().includes(searchTerm.toLowerCase())
  );

  const filteredUsers = selectedProject
    ? allUsers.filter((u) => u.project === selectedProject)
    : allUsers;

  const maxInteractions = Math.max(...projects.map((p) => p.interactions));
  const minInteractions = Math.min(...projects.map((p) => p.interactions));

  const getColor = (val: number): string => {
    const ratio = (val - minInteractions) / (maxInteractions - minInteractions);
    const r = Math.round(100 + 100 * ratio);
    const g = Math.round(0 + 40 * ratio);
    const b = Math.round(180 + 60 * ratio);
    const a = 0.4 + 0.6 * ratio;
    return `rgba(${r}, ${g}, ${b}, ${a})`;
  };

  const handleProjectClick = (projName: string): void => {
    setSelectedProject(selectedProject === projName ? null : projName);
  };

  return (
    <div className="leaderboard-container">
      <div style={{ height: "60px" }} />

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

      <div className="leaderboard-content">
        {/* Left side */}
        <div className="interaction-grid">
          {filteredProjects.length > 0 ? (
            filteredProjects.map((proj, i) => {
              const color = getColor(proj.interactions);
              const isActive = selectedProject === proj.name;
              const chartData = proj.trend.map((val, idx) => ({
                day: idx + 1,
                value: val,
              }));

              return (
                <div
                  key={i}
                  className={`interaction-rect ${isActive ? "active" : ""}`}
                  style={{
                    flexGrow: proj.interactions / 10,
                    backgroundColor: color,
                    opacity: selectedProject && !isActive ? 0.5 : 1,
                    border: "2px solid white",
                    cursor: "pointer",
                    position: "relative",
                  }}
                  onClick={() => handleProjectClick(proj.name)}
                >
                  <div className="mini-chart">
                    <ResponsiveContainer width="100%" height={50}>
                      <LineChart data={chartData}>
                        <Line
                          type="monotone"
                          dataKey="value"
                          stroke="#ffd700"
                          strokeWidth={2}
                          dot={false}
                          isAnimationActive={true}
                        />
                        <Tooltip
                          contentStyle={{
                            background: "rgba(255,255,255,0.8)",
                            borderRadius: "6px",
                            color: "#000",
                          }}
                        />
                      </LineChart>
                    </ResponsiveContainer>
                  </div>
                  <div className="rect-label">
                    <img
                      src={proj.logo}
                      alt={proj.name}
                      className="proj-logo"
                    />
                    <span className="proj-name">{proj.name}</span>
                    <span className="proj-interactions">
                      {proj.interactions} interactions
                    </span>
                  </div>
                </div>
              );
            })
          ) : (
            <p style={{ color: "#fff", textAlign: "center", width: "100%" }}>
              No matching projects found.
            </p>
          )}
        </div>

        {/* Right side leaderboard */}
        <div className="user-leaderboard">
          <h2>
            {selectedProject
              ? `${selectedProject} Top Users`
              : "Global Rankings"}
          </h2>
          <ul>
            {filteredUsers.map((user, i) => (
              <li key={i} className="user-entry">
                <span className="rank">#{i + 1}</span>
                <div className="user-info">
                  <img src={user.pfp} alt={user.username} className="user-pfp" />
                  <span className="username">{user.username}</span>
                </div>
                <span className="won">{user.won} WON</span>
              </li>
            ))}
          </ul>
        </div>
      </div>
    </div>
  );
};

export default Leaderboard;
