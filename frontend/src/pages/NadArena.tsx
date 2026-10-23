// @ts-nocheck
import { useEffect, useMemo, useState } from "react";
import "./NadArena.css";
// @ts-ignore
import { fetchMatchesFromFirebase } from "./firebaseClient";
import { displayMatchStatus, type DisplayMatchStatus } from "../lib/matchStatus";
import Footer from "../components/Footer";

type MatchRecord = {
  id?: number;
  matchId?: string;
  sponsor?: string;
  description?: string;
  status?: string;
  date?: string;
  time?: string;
  startTime?: number;
  ctaMode?: string;
  image?: string;
  url?: string;
  prize?: string;
  createdAt?: string;
  settleTxHash?: string;
};

type ProjectCard = {
  id: string;
  name: string;
  tagline: string;
  description: string;
  stage: DisplayMatchStatus;
  launchDate: string;
  xHandle: string;
  logo: string;
  url: string;
  settleTxHash?: string;
};

const DEFAULT_LOGO = "/logo.jpg";

function NadArena() {
  const [searchTerm, setSearchTerm] = useState("");
  const [filterStatus, setFilterStatus] = useState("all"); // 'all', 'upcoming', 'live', 'completed'
  const [matches, setMatches] = useState<MatchRecord[]>([]);
  const [nowMs, setNowMs] = useState(Date.now());
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState("");

  useEffect(() => {
    const loadMatches = async () => {
      setLoading(true);
      setLoadError("");
      try {
        const records = await fetchMatchesFromFirebase();
        setMatches(records as MatchRecord[]);
      } catch (error) {
        console.error("Failed to load matches", error);
        setLoadError("Failed to load matches.");
      } finally {
        setLoading(false);
      }
    };

    loadMatches();
  }, []);

  // Cards must age on their own: a stored `status` whose worker flip never
  // landed used to keep a finished event at "live"/"upcoming" for as long as
  // the tab was open.
  useEffect(() => {
    const ticker = setInterval(() => setNowMs(Date.now()), 30_000);
    return () => clearInterval(ticker);
  }, []);

  const projects = useMemo(
    () => matches.map((match) => mapMatchToProject(match, nowMs)),
    [matches, nowMs]
  );

  const filteredProjects = useMemo(() =>
    projects
      .filter((project) => {
        if (filterStatus === "all") {
          return true;
        }
        // Refunded/cancelled events are over: the page keeps its three tabs, so
        // they belong under Completed while still carrying a "cancelled" badge.
        if (filterStatus === "completed") {
          return project.stage === "completed" || project.stage === "cancelled";
        }
        return project.stage === filterStatus;
      })
      .filter((project) =>
        project.name.toLowerCase().includes(searchTerm.toLowerCase())
      ), [projects, filterStatus, searchTerm]);

  const renderStatusBadge = (stage: ProjectCard["stage"]) => {
    const map = {
      live: "arena-status-live",
      upcoming: "arena-status-upcoming",
      completed: "arena-status-completed",
      cancelled: "arena-status-cancelled",
    } as const;

    return (
      <span className={`arena-status ${map[stage]}`}>
        {stage}
      </span>
    );
  };

  if (loading) {
    return (
      <div className="arena-container">
        <div style={{ height: "60px" }}></div>
        <p className="text-inline-accent">Loading matches...</p>
      </div>
    );
  }

  if (loadError) {
    return (
      <div className="arena-container">
        <div style={{ height: "60px" }}></div>
        <p className="text-inline-muted">{loadError}</p>
      </div>
    );
  }

  return (
    <div className="arena-container">
      <div style={{ height: "60px" }}></div>
      <h1 className="arena-title">Nad Arena</h1>
      <p className="arena-intro">
        Discover the next wave of innovation. Early access to groundbreaking
        projects before they launch.
      </p>

      <div className="search-wrapper">
        <input
          type="text"
          placeholder="Search for projects..."
          value={searchTerm}
          onChange={(e) => setSearchTerm(e.target.value)}
          className="partner-search"
        />
      </div>

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

      <div className="arena-grid">
        {filteredProjects.length > 0 ? (
          filteredProjects.map((project) => (
            <div
              key={project.id}
              className={`arena-card arena-card-${project.stage}`}
            >
              <div className="arena-card-header">
                <img
                  src={project.logo}
                  alt={`${project.name} logo`}
                  className="arena-logo"
                />
                <h2 className="arena-project-name">{project.name}</h2>
              </div>
              <p className="arena-tagline">{project.tagline}</p>
              <p className="arena-description">{project.description}</p>
              <div className="arena-meta">
                {renderStatusBadge(project.stage)}
                {project.stage === "completed" && project.settleTxHash && (
                  <a
                    href={`https://monadexplorer.com/tx/${project.settleTxHash}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="arena-tx-link arena-tx-link-inline-replaced"
                    title="View Settlement Transaction"
                    style={{ marginLeft: '10px', fontWeight: 'bold', fontSize: '0.8rem', textDecoration: 'underline' }}
                  >
                    Tx Hash
                  </a>
                )}
                <span className="arena-handle">
                  {project.url ? (
                    <a
                      href={project.url}
                      target="_blank"
                      rel="noopener noreferrer"
                    >
                      {project.xHandle}
                    </a>
                  ) : (
                    <span>{project.xHandle}</span>
                  )}
                </span>
              </div>
            </div>
          ))
        ) : (
          <p className="text-inline-muted">
            No projects match your criteria.
          </p>
        )}
      </div>
      <Footer />
    </div>
  );
}

function mapMatchToProject(match: MatchRecord, nowMs: number): ProjectCard {
  const name = (match.sponsor || "Unknown Sponsor").trim();
  const status = displayMatchStatus(match, nowMs);
  const url = String(match.url || "").trim();
  const handle = deriveHandle(url, name);

  return {
    id: String(match.matchId || match.id || `${name}-${match.date || Date.now()}`),
    name,
    tagline: match.prize ? `Prize: ${match.prize}` : "Sponsored match",
    description: match.description || "New sponsored match from World of Nads.",
    stage: status,
    launchDate:
      status === "live" ? "Live Now"
        : status === "completed" ? "Completed"
          : status === "cancelled" ? "Cancelled"
            : "Upcoming",
    xHandle: handle,
    logo: match.image || DEFAULT_LOGO,
    url,
    settleTxHash: match.settleTxHash
  };
}

function deriveHandle(url: string, fallback: string): string {
  if (!url) return fallback || "Learn more";

  try {
    const parsed = new URL(url);
    if (parsed.hostname.includes("x.com") || parsed.hostname.includes("twitter.com")) {
      const handle = parsed.pathname.split("/").filter(Boolean)[0];
      return handle ? `@${handle}` : "View";
    }
    return parsed.hostname.replace("www.", "");
  } catch {
    return fallback || "Learn more";
  }
}

export default NadArena;
