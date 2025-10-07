import React, { useState } from "react";
import {
  LineChart,
  Line,
  ResponsiveContainer,
  Tooltip,
} from "recharts";
import "./Leaderboard.css";

interface Project {
  name: string;
  interactions: number;
  trend: number[]; // 7 data points for chart
}

interface User {
  username: string;
  won: number;
  project: string;
}

const Leaderboard: React.FC = () => {
  const projects: Project[] = [
    { name: "NovaForge", interactions: 120, trend: [100, 110, 95, 120, 130, 125, 140] },
    { name: "EchoDrift", interactions: 95, trend: [70, 80, 90, 85, 95, 100, 110] },
    { name: "Mythra Protocol", interactions: 160, trend: [150, 155, 140, 160, 170, 165, 180] },
    { name: "Orion Frontier", interactions: 80, trend: [60, 65, 70, 75, 80, 78, 85] },
    { name: "Astra Dawn", interactions: 45, trend: [30, 35, 40, 45, 42, 48, 50] },
    { name: "LumaCore", interactions: 140, trend: [120, 130, 125, 135, 145, 150, 155] },
    { name: "ZephyrNet", interactions: 110, trend: [90, 95, 100, 110, 120, 115, 125] },
    { name: "HoloLink", interactions: 70, trend: [50, 55, 60, 65, 68, 70, 75] },
    { name: "DriftLabs", interactions: 150, trend: [130, 135, 145, 150, 155, 160, 170] },
    { name: "Cryovault", interactions: 100, trend: [80, 90, 95, 100, 105, 110, 108] },
    { name: "SpectraX", interactions: 130, trend: [115, 120, 125, 130, 128, 135, 140] },
    { name: "Vertex One", interactions: 60, trend: [40, 45, 50, 55, 60, 65, 70] },
    { name: "Flux Matrix", interactions: 90, trend: [75, 80, 85, 90, 88, 92, 95] },
    { name: "OmniBridge", interactions: 155, trend: [130, 135, 145, 150, 155, 160, 165] },
    { name: "NeuraStream", interactions: 105, trend: [90, 95, 100, 105, 110, 115, 120] },
    { name: "EtherNova", interactions: 115, trend: [95, 100, 105, 110, 115, 120, 125] },
    { name: "PulseEdge", interactions: 125, trend: [100, 105, 110, 120, 125, 130, 140] },
    { name: "ChronaNet", interactions: 85, trend: [60, 65, 75, 80, 85, 88, 90] },
    { name: "AetherField", interactions: 65, trend: [40, 45, 50, 60, 65, 62, 70] },
    { name: "Quantra Labs", interactions: 135, trend: [120, 125, 130, 135, 140, 145, 150] },
  ];

  const allUsers: User[] = [
    { username: "0xNadLord", won: 580, project: "NovaForge" },
    { username: "0xShinobi", won: 460, project: "EchoDrift" },
    { username: "0xWanderer", won: 410, project: "Mythra Protocol" },
    { username: "0xDataGhost", won: 360, project: "NovaForge" },
    { username: "0xVoidHero", won: 320, project: "Orion Frontier" },
    { username: "0xMoonSmith", won: 270, project: "Astra Dawn" },
    { username: "0xSeraph", won: 260, project: "EchoDrift" },
    { username: "0xWarden", won: 190, project: "Mythra Protocol" },
    { username: "0xLunaByte", won: 400, project: "LumaCore" },
    { username: "0xHexKnight", won: 380, project: "ZephyrNet" },
    { username: "0xDrifter", won: 420, project: "DriftLabs" },
    { username: "0xCryoMage", won: 350, project: "Cryovault" },
    { username: "0xSpecter", won: 310, project: "SpectraX" },
    { username: "0xVertex", won: 295, project: "Vertex One" },
    { username: "0xFluxor", won: 270, project: "Flux Matrix" },
    { username: "0xOmniSoul", won: 390, project: "OmniBridge" },
    { username: "0xNeura", won: 330, project: "NeuraStream" },
    { username: "0xEtherLord", won: 345, project: "EtherNova" },
    { username: "0xPulseMaster", won: 375, project: "PulseEdge" },
    { username: "0xChrona", won: 290, project: "ChronaNet" },
    { username: "0xAetherian", won: 315, project: "AetherField" },
    { username: "0xQuantix", won: 405, project: "Quantra Labs" },
  ];

  const [selectedProject, setSelectedProject] = useState<string | null>(null);

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
      <div className="leaderboard-content">
        {/* Left side */}
        <div className="interaction-grid">
          {projects.map((proj, i) => {
            const color = getColor(proj.interactions);
            const isActive = selectedProject === proj.name;
            const chartData = proj.trend.map((val, idx) => ({ day: idx + 1, value: val }));

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
                        stroke="#ffd700" // gold/yellow line for contrast
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
                  <span className="proj-name">{proj.name}</span>
                  <span className="proj-interactions">
                    {proj.interactions} interactions
                  </span>
                </div>
              </div>
            );
          })}
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
                <span className="username">{user.username}</span>
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
