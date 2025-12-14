import React, { useState, useEffect } from "react";
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
  projects: string[];
  pfp: string;
}

const Leaderboard: React.FC = () => {
  // --- UPDATED PROJECT DATA WITH 15-DAY REALISTIC TRENDS ---
  const projects: Project[] = [
    { name: "Monad", interactions: 185, trend: [95, 300, 110, 100, 120, 135, 130, 145, 155, 160, 150, 170, 175, 180, 185], logo: "https://pbs.twimg.com/profile_images/1861739634428174336/26FzLLyr.jpg" },
    { name: "LootGO", interactions: 260, trend: [150, 160, 500, 600, 185, 190, 205, 200, 215, 225, 230, 245, 240, 255, 260], logo: "https://pbs.twimg.com/profile_images/1947490514921488384/TLSJg7Z5.jpg" },
    { name: "Nad.fun", interactions: 300, trend: [180, 400, 300, 200, 210, 225, 230, 220, 240, 255, 265, 270, 285, 290, 300], logo: "https://pbs.twimg.com/profile_images/1827607782356619264/Owr-840k.jpg" },
    { name: "Kizzy Mobile", interactions: 155, trend: [70, 75, 80, 75, 90, 95, 100, 110, 105, 120, 130, 125, 140, 150, 155], logo: "https://pbs.twimg.com/profile_images/2000251466468978688/Q7hvNgR3.jpg" },
    { name: "Kuru Exchange", interactions: 130, trend: [60, 65, 70, 100, 75, 80, 85, 90, 85, 100, 105, 115, 110, 125, 130], logo: "https://pbs.twimg.com/profile_images/1950962142917619714/R7Cj_qk7.jpg" },
    { name: "Lumiterra", interactions: 175, trend: [90, 95, 100, 95, 110, 115, 120, 130, 125, 140, 150, 145, 160, 170, 175], logo: "https://pbs.twimg.com/profile_images/1667436896480563200/8YPmbLbv.png" },
    { name: "Levr Bet", interactions: 90, trend: [30, 35, 40, 35, 45, 50, 55, 60, 55, 70, 75, 80, 75, 85, 90], logo: "https://pbs.twimg.com/profile_images/1836024387042004992/YKdDMkOG.jpg" },
    { name: "Drake Exchange", interactions: 210, trend: [110, 120, 115, 130, 200, 150, 145, 160, 170, 175, 180, 190, 185, 200, 210], logo: "https://pbs.twimg.com/profile_images/1974759389354491904/2vcC-dd4.jpg" },
    { name: "Omnia Explorer", interactions: 140, trend: [65, 70, 20, 70, 80, 85, 90, 95, 90, 105, 110, 120, 115, 130, 140], logo: "https://pbs.twimg.com/profile_images/1796709016808394752/C91LWB9H.jpg" },
    { name: "SeerTrade", interactions: 125, trend: [55, 60, 65, 60, 70, 75, 80, 85, 80, 95, 100, 110, 105, 120, 125], logo: "https://pbs.twimg.com/profile_images/1992956835922587649/6s2RZ9xf.jpg" },
    { name: "Monday Trade", interactions: 105, trend: [40, 45, 10, 45, 55, 60, 65, 70, 65, 80, 85, 90, 85, 95, 105], logo: "https://pbs.twimg.com/profile_images/1973421191202209797/qRXSiR5e.jpg" },
    { name: "Symphony", interactions: 170, trend: [85, 90, 95, 90, 105, 110, 115, 125, 120, 135, 140, 150, 145, 160, 170], logo: "https://pbs.twimg.com/profile_images/1893386930605211648/-APwnLNM.jpg" },
    { name: "Kinetik AI", interactions: 190, trend: [100, 110, 105, 120, 130, 135, 140, 150, 145, 160, 165, 175, 170, 180, 190], logo: "https://pbs.twimg.com/profile_images/1947607859702673408/hpZ89aya.jpg" },
    { name: "TeleMafia", interactions: 160, trend: [75, 80, 85, 40, 95, 100, 105, 115, 110, 125, 130, 140, 135, 150, 160], logo: "https://pbs.twimg.com/profile_images/1967887075316994050/STzEqU1y.jpg" },
    { name: "Fluffle World", interactions: 210, trend: [110, 120, 115, 130, 140, 150, 145, 400, 170, 175, 180, 190, 185, 200, 210], logo: "https://pbs.twimg.com/profile_images/1972672305336569856/JLjBcagi.jpg" },
    { name: "BRO.fun", interactions: 135, trend: [60, 65, 70, 65, 75, 80, 85, 90, 85, 100, 105, 115, 110, 125, 135], logo: "https://pbs.twimg.com/profile_images/1983519855279042560/ntgzrOaU.jpg" },
    { name: "RareBet Sports", interactions: 250, trend: [140, 150, 145, 600, 170, 180, 175, 190, 200, 210, 205, 220, 230, 240, 250], logo: "https://pbs.twimg.com/profile_images/1802788848956506112/KJnlcaQj.jpg" }
  ];

  const allUsers: User[] = [
    // This is a truncated list for brevity. Use your full user list here.
    { username: "0xSolarKnight", won: 870, projects: ["Monad"], pfp: "https://randomuser.me/api/portraits/men/11.jpg" },
    { username: "0xPrimeSeeker", won: 860, projects: ["Nad.fun"], pfp: "https://randomuser.me/api/portraits/men/32.jpg" },
    { username: "0xApexSpectral", won: 855, projects: ["RareBet Sports"], pfp: "https://randomuser.me/api/portraits/men/44.jpg" },
    { username: "0xNovaWarden", won: 845, projects: ["Kuru Exchange"], pfp: "https://randomuser.me/api/portraits/women/22.jpg" },
    { username: "0xQuantumPulse", won: 842, projects: ["Kizzy Mobile"], pfp: "https://randomuser.me/api/portraits/men/53.jpg" },
    { username: "0xDriftCipher", won: 835, projects: ["Monad"], pfp: "https://randomuser.me/api/portraits/women/73.jpg" },
    { username: "0xEchoHarbinger", won: 830, projects: ["Nad.fun"], pfp: "https://randomuser.me/api/portraits/men/65.jpg" },
    { username: "0xSilentNova", won: 824, projects: ["RareBet Sports"], pfp: "https://randomuser.me/api/portraits/men/77.jpg" },
    { username: "0xRiftSentinel", won: 821, projects: ["Kuru Exchange"], pfp: "https://randomuser.me/api/portraits/women/81.jpg" },
    { username: "0xStormDriller", won: 818, projects: ["Monad"], pfp: "https://randomuser.me/api/portraits/men/83.jpg" },
    { username: "0xNightVigil", won: 810, projects: ["Nad.fun"], pfp: "https://randomuser.me/api/portraits/women/57.jpg" },
    { username: "0xFuryVector", won: 808, projects: ["RareBet Sports"], pfp: "https://randomuser.me/api/portraits/men/85.jpg" },
    { username: "0xIronSpectre", won: 805, projects: ["Kizzy Mobile"], pfp: "https://randomuser.me/api/portraits/women/45.jpg" },
    { username: "0xDripSamurai", won: 801, projects: ["Monad"], pfp: "https://randomuser.me/api/portraits/men/39.jpg" },
    { username: "0xProxyTitan", won: 798, projects: ["RareBet Sports"], pfp: "https://randomuser.me/api/portraits/men/51.jpg" },
    { username: "0xGhostCipher", won: 795, projects: ["Kuru Exchange"], pfp: "https://randomuser.me/api/portraits/men/23.jpg" },
    { username: "0xLoneCycler", won: 791, projects: ["Monad", "LootGO"], pfp: "https://randomuser.me/api/portraits/women/13.jpg" },
    { username: "0xChainFrost", won: 789, projects: ["Nad.fun"], pfp: "https://randomuser.me/api/portraits/women/19.jpg" },
    { username: "0xHyperFlux", won: 785, projects: ["Kizzy Mobile"], pfp: "https://randomuser.me/api/portraits/men/28.jpg" },
    { username: "0xVortexCraze", won: 783, projects: ["RareBet Sports", "LootGO"], pfp: "https://randomuser.me/api/portraits/men/29.jpg" }
    // ... your full user list
  ];

  const [selectedProject, setSelectedProject] = useState<string | null>(null);
  const [searchTerm, setSearchTerm] = useState("");
  const [currentPage, setCurrentPage] = useState(1);
  const usersPerPage = 8;

  useEffect(() => {
    setCurrentPage(1); // Reset to first page when filter changes
  }, [selectedProject]);


  const filteredProjects = projects.filter((p) =>
    p.name.toLowerCase().includes(searchTerm.toLowerCase())
  );

  const filteredUsers = selectedProject
    ? allUsers.filter((u) => u.projects.includes(selectedProject))
    : allUsers;

  // Pagination Logic
  const indexOfLastUser = currentPage * usersPerPage;
  const indexOfFirstUser = indexOfLastUser - usersPerPage;
  const currentUsers = filteredUsers.slice(indexOfFirstUser, indexOfLastUser);
  const totalPages = Math.ceil(filteredUsers.length / usersPerPage);

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
                  }}
                  onClick={() => handleProjectClick(proj.name)}
                >
                  <div className="mini-chart">
                    <ResponsiveContainer width="100%" height={50}>
                      <LineChart data={chartData}>
                        <Line type="monotone" dataKey="value" stroke="#ffd700" strokeWidth={2} dot={false} isAnimationActive={true} />
                        <Tooltip contentStyle={{ background: "rgba(255,255,255,0.8)", borderRadius: "6px", color: "#000" }} />
                      </LineChart>
                    </ResponsiveContainer>
                  </div>
                  <div className="rect-label">
                    <img src={proj.logo} alt={proj.name} className="proj-logo" />
                    <span className="proj-name">{proj.name}</span>
                    <span className="proj-interactions">{proj.interactions} interactions</span>
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

        <div className="user-leaderboard">
          <h2>
            {selectedProject
              ? `${selectedProject} Top Users`
              : "Global Rankings"}
          </h2>
          <ul>
            {currentUsers.map((user, i) => (
              <li key={i} className="user-entry">
                <span className="rank">#{indexOfFirstUser + i + 1}</span>
                <div className="user-info">
                  <img src={user.pfp} alt={user.username} className="user-pfp" />
                  <span className="username">{user.username}</span>
                </div>
                <span className="won">{user.won} WON</span>
              </li>
            ))}
          </ul>
          {totalPages > 1 && (

            <div className="pagination">
              {/* Previous Button */}
              {currentPage > 1 && (
                <button onClick={() => setCurrentPage(currentPage - 1)}>
                  Previous
                </button>
              )}

              {/* Page number buttons */}
              {Array.from(
                { length: Math.ceil(allUsers.length / usersPerPage) },
                (_, i) => (
                  <button
                    key={i}
                    onClick={() => setCurrentPage(i + 1)}
                    className={currentPage === i + 1 ? "active" : ""}
                  >
                    {i + 1}
                  </button>
                )
              )}

              {/* Next Button */}
              {currentPage < Math.ceil(allUsers.length / usersPerPage) && (
                <button onClick={() => setCurrentPage(currentPage + 1)}>
                  Next
                </button>
              )}
            </div>


          )}
        </div>
      </div>
    </div>
  );
};

export default Leaderboard;