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
  const projects: Project[] = [
    { name: "Monad", interactions: 185, trend: [120, 140, 150, 160, 170, 180, 185], logo: "https://pbs.twimg.com/profile_images/1861739634428174336/26FzLLyr.jpg" },
    { name: "LootGO", interactions: 260, trend: [180, 190, 210, 230, 240, 255, 260], logo: "https://pbs.twimg.com/profile_images/1947490514921488384/TLSJg7Z5.jpg" },
    { name: "Nad.fun", interactions: 300, trend: [200, 220, 240, 260, 280, 290, 300], logo: "https://pbs.twimg.com/profile_images/1827607782356619264/Owr-840k.jpg" },
    { name: "Kizzy Mobile", interactions: 155, trend: [90, 100, 110, 120, 135, 145, 155], logo: "https://pbs.twimg.com/profile_images/1889975983941591040/NeddfENS.jpg" },
    { name: "Kuru Exchange", interactions: 130, trend: [70, 80, 95, 105, 115, 125, 130], logo: "https://pbs.twimg.com/profile_images/1950962142917619714/R7Cj_qk7.jpg" },
    { name: "Lumiterra", interactions: 175, trend: [110, 120, 130, 145, 155, 165, 175], logo: "https://pbs.twimg.com/profile_images/1667436896480563200/8YPmbLbv.png" },
    { name: "Levr Bet", interactions: 90, trend: [50, 60, 65, 70, 75, 85, 90], logo: "https://pbs.twimg.com/profile_images/1836024387042004992/YKdDMkOG.jpg" },
    { name: "Drake Exchange", interactions: 210, trend: [150, 160, 170, 180, 190, 200, 210], logo: "https://pbs.twimg.com/profile_images/1974759389354491904/2vcC-dd4.jpg" },
    { name: "Omnia Explorer", interactions: 140, trend: [80, 90, 95, 110, 120, 135, 140], logo: "https://pbs.twimg.com/profile_images/1796709016808394752/C91LWB9H.jpg" },
    { name: "SeerTrade", interactions: 125, trend: [70, 75, 85, 95, 105, 115, 125], logo: "https://pbs.twimg.com/profile_images/1957497669959761920/IMS0lJhe.jpg" },
    { name: "Monday Trade", interactions: 105, trend: [60, 70, 75, 85, 90, 95, 105], logo: "https://pbs.twimg.com/profile_images/1973421191202209797/qRXSiR5e.jpg" },
    { name: "Symphony", interactions: 170, trend: [110, 125, 130, 145, 150, 160, 170], logo: "https://pbs.twimg.com/profile_images/1893386930605211648/-APwnLNM.jpg" },
    { name: "Kinetik AI", interactions: 190, trend: [120, 130, 140, 155, 165, 175, 190], logo: "https://pbs.twimg.com/profile_images/1947607859702673408/hpZ89aya.jpg" },
    { name: "TeleMafia", interactions: 160, trend: [95, 110, 120, 130, 140, 150, 160], logo: "https://pbs.twimg.com/profile_images/1967887075316994050/STzEqU1y.jpg" },
    { name: "Fluffle World", interactions: 210, trend: [140, 150, 165, 175, 185, 200, 210], logo: "https://pbs.twimg.com/profile_images/1972672305336569856/JLjBcagi.jpg" },
    { name: "BRO.fun", interactions: 135, trend: [75, 85, 95, 110, 120, 130, 135], logo: "https://pbs.twimg.com/profile_images/1983519855279042560/ntgzrOaU.jpg" },
    { name: "RareBet Sports", interactions: 250, trend: [180, 190, 200, 210, 220, 235, 250], logo: "https://pbs.twimg.com/profile_images/1802788848956506112/KJnlcaQj.jpg" }
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
  const usersPerPage = 10;

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
                        <Line type="monotone" dataKey="value" stroke="#ffd700" strokeWidth={2} dot={false} isAnimationActive={true}/>
                        <Tooltip contentStyle={{ background: "rgba(255,255,255,0.8)", borderRadius: "6px", color: "#000" }}/>
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
              <button onClick={() => setCurrentPage(prev => Math.max(prev - 1, 1))} disabled={currentPage === 1}>
                Prev
              </button>
              {Array.from({ length: totalPages }, (_, i) => i + 1).map(number => (
                <button
                    key={number}
                    onClick={() => setCurrentPage(number)}
                    className={`page-btn ${currentPage === number ? 'active' : ''}`}
                >
                    {number}
                </button>
              ))}
              <button onClick={() => setCurrentPage(prev => Math.min(prev + 1, totalPages))} disabled={currentPage === totalPages}>
                Next
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default Leaderboard;