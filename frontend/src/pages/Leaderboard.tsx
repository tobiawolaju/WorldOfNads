import React, { useEffect, useMemo, useState } from "react";
import { LineChart, Line, ResponsiveContainer, Tooltip } from "recharts";
import "./Leaderboard.css";
import {
  fetchMatchesFromFirebase,
  fetchUsersFromFirebase,
  fetchSponsorDailyPlayers
} from "./firebaseClient";

type Project = {
  name: string;
  interactions: number;
  trend: number[];
  logo: string;
};

type User = {
  username: string;
  won: number;
  projects: string[];
  pfp: string;
};

type MatchRecord = {
  sponsor?: string;
  image?: string;
};

type SponsorDailyData = {
  dates: string[];
  sponsors: Record<string, { dailyCounts: Record<string, number>; usersByDate: Record<string, string[]> }>;
};

const TREND_DAYS = 7;
const DEFAULT_LOGO = "/logo.jpg";

const Leaderboard: React.FC = () => {
  const [projects, setProjects] = useState<Project[]>([]);
  const [allUsers, setAllUsers] = useState<User[]>([]);
  const [sponsorUsers, setSponsorUsers] = useState<Record<string, string[]>>({});
  const [selectedProject, setSelectedProject] = useState<string | null>(null);
  const [searchTerm, setSearchTerm] = useState("");
  const [currentPage, setCurrentPage] = useState(1);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState("");

  const usersPerPage = 8;

  useEffect(() => {
    const loadData = async () => {
      setLoading(true);
      setLoadError("");
      try {
        const [matches, users, sponsorDaily] = await Promise.all([
          fetchMatchesFromFirebase(),
          fetchUsersFromFirebase(),
          fetchSponsorDailyPlayers(TREND_DAYS)
        ]);

        const normalizedUsers: User[] = (users || []).map((user: any) => ({
          username: String(user.username || "Anon"),
          won: Number(user.won || 0),
          projects: Array.isArray(user.projects) ? user.projects : [],
          pfp: String(user.pfp || user.profilePictureUrl || DEFAULT_LOGO)
        }));

        const projectStats = buildProjects(matches as MatchRecord[], sponsorDaily as SponsorDailyData);
        const sponsorUsersLookup = buildSponsorUsersLookup(sponsorDaily as SponsorDailyData);

        setAllUsers(normalizedUsers);
        setProjects(projectStats);
        setSponsorUsers(sponsorUsersLookup);
      } catch (error) {
        console.error("Failed to load leaderboard data", error);
        setLoadError("Failed to load leaderboard data.");
      } finally {
        setLoading(false);
      }
    };

    loadData();
  }, []);

  useEffect(() => {
    setCurrentPage(1); // Reset to first page when filter changes
  }, [selectedProject]);

  const filteredProjects = useMemo(() =>
    projects.filter((p) =>
      p.name.toLowerCase().includes(searchTerm.toLowerCase())
    ), [projects, searchTerm]);

  const filteredUsers = useMemo(() => {
    if (!selectedProject) return allUsers;
    const activeUsers = sponsorUsers[selectedProject] || [];
    return activeUsers
      .map((username) => {
        const match = allUsers.find((user) => user.username === username);
        if (match) return match;
        return { username, won: 0, projects: [], pfp: DEFAULT_LOGO };
      });
  }, [allUsers, selectedProject, sponsorUsers]);

  const indexOfLastUser = currentPage * usersPerPage;
  const indexOfFirstUser = indexOfLastUser - usersPerPage;
  const currentUsers = filteredUsers.slice(indexOfFirstUser, indexOfLastUser);
  const totalPages = Math.ceil(filteredUsers.length / usersPerPage);

  const interactionValues = projects.map((p) => p.interactions);
  const maxInteractions = interactionValues.length ? Math.max(...interactionValues) : 0;
  const minInteractions = interactionValues.length ? Math.min(...interactionValues) : 0;

  const getColor = (val: number): string => {
    if (maxInteractions === minInteractions) {
      return "rgba(120, 120, 200, 0.7)";
    }
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

  if (loading) {
    return (
      <div className="leaderboard-container">
        <div style={{ height: "60px" }} />
        <p style={{ color: "#fff", textAlign: "center" }}>Loading leaderboard...</p>
      </div>
    );
  }

  if (loadError) {
    return (
      <div className="leaderboard-container">
        <div style={{ height: "60px" }} />
        <p style={{ color: "#fff", textAlign: "center" }}>{loadError}</p>
      </div>
    );
  }

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
                    flexGrow: proj.interactions > 0 ? proj.interactions / 10 : 1,
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
              ? `${selectedProject} Players (last ${TREND_DAYS} days)`
              : "Global Rankings"}
          </h2>
          {filteredUsers.length === 0 ? (
            <p style={{ color: "#fff" }}>No users yet.</p>
          ) : (
            <ul>
              {currentUsers.map((user, i) => (
                <li key={`${user.username}-${i}`} className="user-entry">
                  <span className="rank">#{indexOfFirstUser + i + 1}</span>
                  <div className="user-info">
                    <img src={user.pfp} alt={user.username} className="user-pfp" />
                    <span className="username">{user.username}</span>
                  </div>
                  <span className="won">{user.won} WON</span>
                </li>
              ))}
            </ul>
          )}
          {totalPages > 1 && (
            <div className="pagination">
              {currentPage > 1 && (
                <button onClick={() => setCurrentPage(currentPage - 1)}>
                  Previous
                </button>
              )}

              {Array.from(
                { length: Math.ceil(filteredUsers.length / usersPerPage) },
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

              {currentPage < Math.ceil(filteredUsers.length / usersPerPage) && (
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

function buildProjects(matches: MatchRecord[], sponsorDaily: SponsorDailyData): Project[] {
  const map = new Map<string, Project>();
  const dates = sponsorDaily?.dates || [];

  const ensureProject = (name: string) => {
    if (!map.has(name)) {
      map.set(name, {
        name,
        interactions: 0,
        trend: Array.from({ length: TREND_DAYS }, () => 0),
        logo: DEFAULT_LOGO
      });
    }
    return map.get(name)!;
  };

  const sponsors = sponsorDaily?.sponsors || {};
  Object.entries(sponsors).forEach(([name, data]) => {
    const project = ensureProject(name);
    project.trend = dates.map((date) => Number(data.dailyCounts?.[date] || 0));
    project.interactions = project.trend.reduce((sum, val) => sum + val, 0);
  });

  matches.forEach((match) => {
    const sponsor = (match.sponsor || "Unknown Sponsor").trim();
    if (!sponsor) return;
    const project = ensureProject(sponsor);
    if (match.image && match.image !== DEFAULT_LOGO) {
      project.logo = match.image;
    }
  });

  return Array.from(map.values()).sort((a, b) => b.interactions - a.interactions);
}

function buildSponsorUsersLookup(sponsorDaily: SponsorDailyData): Record<string, string[]> {
  const lookup: Record<string, Set<string>> = {};
  const sponsors = sponsorDaily?.sponsors || {};

  Object.entries(sponsors).forEach(([name, data]) => {
    const users = new Set<string>();
    Object.values(data.usersByDate || {}).forEach((list) => {
      list.forEach((username) => users.add(username));
    });
    lookup[name] = users;
  });

  return Object.fromEntries(
    Object.entries(lookup).map(([name, set]) => [name, Array.from(set)])
  );
}

export default Leaderboard;
