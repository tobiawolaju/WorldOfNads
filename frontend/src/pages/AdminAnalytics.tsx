import React, { useEffect, useMemo, useRef, useState } from "react";
import Chart from "chart.js/auto";
import "./AdminAnalytics.css";
import { showErrorToast, showSuccessToast } from "../components/ui/custom-toast";

const API_BASE = import.meta.env.VITE_ANALYTICS_API_URL || "";
const DEFAULT_RANGE_DAYS = 30;

function buildUrl(path: string) {
  if (!API_BASE) return path;
  return `${API_BASE}${path}`;
}

function formatDateInput(value: Date) {
  return value.toISOString().slice(0, 10);
}

function formatNumber(value: number, decimals = 0) {
  if (!Number.isFinite(value)) return "0";
  return value.toLocaleString(undefined, {
    maximumFractionDigits: decimals,
    minimumFractionDigits: decimals
  });
}

function formatPercent(value: number) {
  if (!Number.isFinite(value)) return "0%";
  return `${formatNumber(value, 1)}%`;
}

type SeriesPoint = { date: string; value: number };

type AnalyticsSummary = {
  overview: {
    dailyActiveUsers: number;
    totalUsers: number;
    matchesToday: number;
    totalRewardsDistributed: number;
    totalSponsors: number;
  };
  growthMetrics: {
    dailyUserGrowthRate: number;
    weeklyGrowthRate: number;
    matchCreationGrowthRate: number;
  };
  userMetrics: {
    dau: number;
    wau: number;
    mau: number;
    totalUsers: number;
    newUsersPerDay: number;
    uniqueUsersPerDay: number;
  };
  gameMetrics: {
    matchesCreatedPerDay: number;
    matchesCompleted: number;
    matchesCurrentlyActive: number;
    averagePlayersPerMatch: number;
    matchCompletionRate: number;
    matchesPerUser: number;
  };
  economyMetrics: {
    totalRewardsDistributed: number;
    rewardsDistributedPerDay: number;
    averageRewardPerMatch: number;
    totalRewardVolume: number;
    topWinningPlayers: Array<{ user_id: string; total: number }>;
  };
  sponsorMetrics: {
    totalSponsors: number;
    matchesSponsored: number;
    sponsorFundingVolume: number;
    averageSponsorValue: number;
  };
  engagementMetrics: {
    averageSessionDuration: number;
    returningUsers: number;
    newUsers: number;
    gamesPlayedPerUser: number;
    playerRetention: {
      day1: number;
      day7: number;
      day30: number;
    };
  };
  grantMetrics: {
    dailyActiveUsers: number;
    totalUsers: number;
    totalMatchesPlayed: number;
    totalRewardsDistributed: number;
    numberOfSponsors: number;
    averageMatchesPerUser: number;
    userGrowthRate: number;
    matchGrowthRate: number;
    day7Retention: number;
  };
};

type AnalyticsSeries = {
  series: {
    dailyActiveUsers: SeriesPoint[];
    userGrowth: SeriesPoint[];
    matchesCreated: SeriesPoint[];
    rewardsDistributed: SeriesPoint[];
    sponsorGrowth: SeriesPoint[];
    matchesPerUser: SeriesPoint[];
  };
  retention: {
    day1: number;
    day7: number;
    day30: number;
  };
};

function ChartCard({
  title,
  labels,
  values,
  color = "#2f855a",
  type = "line"
}: {
  title: string;
  labels: string[];
  values: number[];
  color?: string;
  type?: "line" | "bar";
}) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const chartRef = useRef<Chart | null>(null);

  useEffect(() => {
    if (!canvasRef.current) return;

    if (chartRef.current) {
      chartRef.current.destroy();
    }

    chartRef.current = new Chart(canvasRef.current, {
      type,
      data: {
        labels,
        datasets: [
          {
            label: title,
            data: values,
            borderColor: color,
            backgroundColor: type === "bar" ? "rgba(47, 133, 90, 0.4)" : "rgba(47, 133, 90, 0.2)",
            fill: type === "line",
            tension: 0.3,
            pointRadius: 2
          }
        ]
      },
      options: {
        maintainAspectRatio: false,
        plugins: {
          legend: { display: false }
        },
        scales: {
          x: {
            ticks: { maxTicksLimit: 6 }
          },
          y: {
            beginAtZero: true
          }
        }
      }
    });

    return () => {
      if (chartRef.current) {
        chartRef.current.destroy();
      }
    };
  }, [labels, values, color, title, type]);

  return (
    <div className="analytics-card chart-card">
      <div className="analytics-card__header">
        <h3>{title}</h3>
      </div>
      <div className="chart-wrapper">
        <canvas ref={canvasRef} />
      </div>
    </div>
  );
}

export default function AdminAnalytics() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [summary, setSummary] = useState<AnalyticsSummary | null>(null);
  const [series, setSeries] = useState<AnalyticsSeries | null>(null);

  const defaultDates = useMemo(() => {
    const end = new Date();
    const start = new Date();
    start.setDate(start.getDate() - DEFAULT_RANGE_DAYS);
    return { start: formatDateInput(start), end: formatDateInput(end) };
  }, []);

  const [startDate, setStartDate] = useState(defaultDates.start);
  const [endDate, setEndDate] = useState(defaultDates.end);

  const loadAnalytics = async () => {
    setLoading(true);
    setError("");
    try {
      const summaryRes = await fetch(buildUrl(`/analytics/summary?start=${startDate}&end=${endDate}`));
      const summaryData = await summaryRes.json();
      const seriesRes = await fetch(buildUrl(`/analytics/timeseries?start=${startDate}&end=${endDate}`));
      const seriesData = await seriesRes.json();
      setSummary(summaryData);
      setSeries(seriesData);
    } catch {
      const msg = "Failed to load analytics data.";
      setError(msg);
      showErrorToast(msg);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadAnalytics();
  }, []);

  const handleExport = async (format: "csv" | "json") => {
    try {
      const response = await fetch(buildUrl(`/analytics/export?format=${format}&start=${startDate}&end=${endDate}`));
      const blob = await response.blob();
      const url = window.URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = `wons-analytics-${startDate}-to-${endDate}.${format}`;
      document.body.appendChild(link);
      link.click();
      link.remove();
      window.URL.revokeObjectURL(url);
      showSuccessToast(`Export downloaded as ${format.toUpperCase()}.`);
    } catch {
      const msg = "Export failed. Try again.";
      setError(msg);
      showErrorToast(msg);
    }
  };

  if (!summary || !series) {
    return (
      <div className="analytics-loading">
        <p className={loading ? "text-inline-accent" : undefined}>
          {loading ? "Loading analytics..." : "No analytics data yet."}
        </p>
        {error ? <span className="analytics-auth__error">{error}</span> : null}
      </div>
    );
  }

  const chartLabels = series.series.dailyActiveUsers.map((point) => point.date);

  return (
    <div className="analytics-page">
      <header className="analytics-header">
        <div>
          <p className="analytics-eyebrow">World Of Nads</p>
          <h1>Analytics Dashboard</h1>
          <p className="analytics-subtext">Traction, growth, engagement, and economy insights.</p>
        </div>
        <div className="analytics-actions">
          <div className="date-range">
            <label>
              Start
              <input type="date" value={startDate} onChange={(event) => setStartDate(event.target.value)} />
            </label>
            <label>
              End
              <input type="date" value={endDate} onChange={(event) => setEndDate(event.target.value)} />
            </label>
            <button onClick={loadAnalytics} disabled={loading}>
              {loading ? "Refreshing..." : "Apply"}
            </button>
          </div>
          <div className="export-actions">
            <button onClick={() => handleExport("csv")}>Export CSV</button>
            <button onClick={() => handleExport("json")}>Export JSON</button>
          </div>
        </div>
      </header>

      <section className="analytics-section">
        <h2>Overview</h2>
        <div className="analytics-grid">
          <div className="analytics-card">
            <h3>Daily Active Users</h3>
            <p>{formatNumber(summary.overview.dailyActiveUsers)}</p>
          </div>
          <div className="analytics-card">
            <h3>Total Users</h3>
            <p>{formatNumber(summary.overview.totalUsers)}</p>
          </div>
          <div className="analytics-card">
            <h3>Matches Today</h3>
            <p>{formatNumber(summary.overview.matchesToday)}</p>
          </div>
          <div className="analytics-card">
            <h3>Total Rewards Distributed</h3>
            <p>{formatNumber(summary.overview.totalRewardsDistributed, 2)}</p>
          </div>
          <div className="analytics-card">
            <h3>Total Sponsors</h3>
            <p>{formatNumber(summary.overview.totalSponsors)}</p>
          </div>
        </div>
      </section>

      <section className="analytics-section">
        <h2>Growth</h2>
        <div className="analytics-grid">
          <div className="analytics-card">
            <h3>Daily User Growth Rate</h3>
            <p>{formatPercent(summary.growthMetrics.dailyUserGrowthRate)}</p>
          </div>
          <div className="analytics-card">
            <h3>Weekly Growth Rate</h3>
            <p>{formatPercent(summary.growthMetrics.weeklyGrowthRate)}</p>
          </div>
          <div className="analytics-card">
            <h3>Match Creation Growth Rate</h3>
            <p>{formatPercent(summary.growthMetrics.matchCreationGrowthRate)}</p>
          </div>
        </div>
        <div className="analytics-grid charts-grid">
          <ChartCard
            title="Daily Active Users"
            labels={chartLabels}
            values={series.series.dailyActiveUsers.map((point) => point.value)}
            color="#1f7aec"
          />
          <ChartCard
            title="User Growth"
            labels={chartLabels}
            values={series.series.userGrowth.map((point) => point.value)}
            color="#2f855a"
          />
        </div>
      </section>

      <section className="analytics-section">
        <h2>Users</h2>
        <div className="analytics-grid">
          <div className="analytics-card">
            <h3>DAU</h3>
            <p>{formatNumber(summary.userMetrics.dau)}</p>
          </div>
          <div className="analytics-card">
            <h3>WAU</h3>
            <p>{formatNumber(summary.userMetrics.wau)}</p>
          </div>
          <div className="analytics-card">
            <h3>MAU</h3>
            <p>{formatNumber(summary.userMetrics.mau)}</p>
          </div>
          <div className="analytics-card">
            <h3>New Users Per Day</h3>
            <p>{formatNumber(summary.userMetrics.newUsersPerDay)}</p>
          </div>
          <div className="analytics-card">
            <h3>Unique Users Per Day</h3>
            <p>{formatNumber(summary.userMetrics.uniqueUsersPerDay)}</p>
          </div>
        </div>
      </section>

      <section className="analytics-section">
        <h2>Matches</h2>
        <div className="analytics-grid">
          <div className="analytics-card">
            <h3>Matches Created Per Day</h3>
            <p>{formatNumber(summary.gameMetrics.matchesCreatedPerDay)}</p>
          </div>
          <div className="analytics-card">
            <h3>Matches Completed</h3>
            <p>{formatNumber(summary.gameMetrics.matchesCompleted)}</p>
          </div>
          <div className="analytics-card">
            <h3>Matches Currently Active</h3>
            <p>{formatNumber(summary.gameMetrics.matchesCurrentlyActive)}</p>
          </div>
          <div className="analytics-card">
            <h3>Average Players Per Match</h3>
            <p>{formatNumber(summary.gameMetrics.averagePlayersPerMatch, 1)}</p>
          </div>
          <div className="analytics-card">
            <h3>Match Completion Rate</h3>
            <p>{formatPercent(summary.gameMetrics.matchCompletionRate)}</p>
          </div>
          <div className="analytics-card">
            <h3>Matches Per User</h3>
            <p>{formatNumber(summary.gameMetrics.matchesPerUser, 2)}</p>
          </div>
        </div>
        <div className="analytics-grid charts-grid">
          <ChartCard
            title="Matches Created Per Day"
            labels={chartLabels}
            values={series.series.matchesCreated.map((point) => point.value)}
            color="#ef6c00"
          />
          <ChartCard
            title="Matches Per User"
            labels={chartLabels}
            values={series.series.matchesPerUser.map((point) => point.value)}
            color="#8e24aa"
          />
        </div>
      </section>

      <section className="analytics-section">
        <h2>Economy</h2>
        <div className="analytics-grid">
          <div className="analytics-card">
            <h3>Total Rewards Distributed</h3>
            <p>{formatNumber(summary.economyMetrics.totalRewardsDistributed, 2)}</p>
          </div>
          <div className="analytics-card">
            <h3>Rewards Distributed Per Day</h3>
            <p>{formatNumber(summary.economyMetrics.rewardsDistributedPerDay, 2)}</p>
          </div>
          <div className="analytics-card">
            <h3>Average Reward Per Match</h3>
            <p>{formatNumber(summary.economyMetrics.averageRewardPerMatch, 2)}</p>
          </div>
          <div className="analytics-card">
            <h3>Total Reward Volume</h3>
            <p>{formatNumber(summary.economyMetrics.totalRewardVolume, 2)}</p>
          </div>
        </div>
        <div className="analytics-grid charts-grid">
          <ChartCard
            title="Rewards Distributed Per Day"
            labels={chartLabels}
            values={series.series.rewardsDistributed.map((point) => point.value)}
            color="#d32f2f"
          />
        </div>
        <div className="analytics-card">
          <h3>Top Winning Players</h3>
          <div className="analytics-table">
            <div className="analytics-table__row analytics-table__row--head">
              <span>Player</span>
              <span>Total Rewards</span>
            </div>
            {summary.economyMetrics.topWinningPlayers.length === 0 ? (
              <div className="analytics-table__empty">No reward data yet.</div>
            ) : (
              summary.economyMetrics.topWinningPlayers.map((player) => (
                <div className="analytics-table__row" key={player.user_id}>
                  <span>{player.user_id}</span>
                  <span>{formatNumber(player.total, 2)}</span>
                </div>
              ))
            )}
          </div>
        </div>
      </section>

      <section className="analytics-section">
        <h2>Sponsors</h2>
        <div className="analytics-grid">
          <div className="analytics-card">
            <h3>Total Sponsors</h3>
            <p>{formatNumber(summary.sponsorMetrics.totalSponsors)}</p>
          </div>
          <div className="analytics-card">
            <h3>Matches Sponsored</h3>
            <p>{formatNumber(summary.sponsorMetrics.matchesSponsored)}</p>
          </div>
          <div className="analytics-card">
            <h3>Sponsor Funding Volume</h3>
            <p>{formatNumber(summary.sponsorMetrics.sponsorFundingVolume, 2)}</p>
          </div>
          <div className="analytics-card">
            <h3>Average Sponsor Value</h3>
            <p>{formatNumber(summary.sponsorMetrics.averageSponsorValue, 2)}</p>
          </div>
        </div>
        <div className="analytics-grid charts-grid">
          <ChartCard
            title="Sponsor Growth"
            labels={chartLabels}
            values={series.series.sponsorGrowth.map((point) => point.value)}
            color="#00897b"
          />
        </div>
      </section>

      <section className="analytics-section">
        <h2>Engagement</h2>
        <div className="analytics-grid">
          <div className="analytics-card">
            <h3>Average Session Duration (sec)</h3>
            <p>{formatNumber(summary.engagementMetrics.averageSessionDuration, 1)}</p>
          </div>
          <div className="analytics-card">
            <h3>Returning Users</h3>
            <p>{formatNumber(summary.engagementMetrics.returningUsers)}</p>
          </div>
          <div className="analytics-card">
            <h3>New Users</h3>
            <p>{formatNumber(summary.engagementMetrics.newUsers)}</p>
          </div>
          <div className="analytics-card">
            <h3>Games Played Per User</h3>
            <p>{formatNumber(summary.engagementMetrics.gamesPlayedPerUser, 2)}</p>
          </div>
        </div>
        <div className="analytics-grid charts-grid">
          <ChartCard
            title="Retention"
            labels={["Day 1", "Day 7", "Day 30"]}
            values={[series.retention.day1, series.retention.day7, series.retention.day30]}
            color="#5e35b1"
            type="bar"
          />
        </div>
      </section>

      <section className="analytics-section">
        <h2>Grant Metrics</h2>
        <div className="analytics-grid">
          <div className="analytics-card">
            <h3>Daily Active Users</h3>
            <p>{formatNumber(summary.grantMetrics.dailyActiveUsers)}</p>
          </div>
          <div className="analytics-card">
            <h3>Total Users</h3>
            <p>{formatNumber(summary.grantMetrics.totalUsers)}</p>
          </div>
          <div className="analytics-card">
            <h3>Total Matches Played</h3>
            <p>{formatNumber(summary.grantMetrics.totalMatchesPlayed)}</p>
          </div>
          <div className="analytics-card">
            <h3>Total Rewards Distributed</h3>
            <p>{formatNumber(summary.grantMetrics.totalRewardsDistributed, 2)}</p>
          </div>
          <div className="analytics-card">
            <h3>Number of Sponsors</h3>
            <p>{formatNumber(summary.grantMetrics.numberOfSponsors)}</p>
          </div>
          <div className="analytics-card">
            <h3>Average Matches per User</h3>
            <p>{formatNumber(summary.grantMetrics.averageMatchesPerUser, 2)}</p>
          </div>
          <div className="analytics-card">
            <h3>User Growth Rate</h3>
            <p>{formatPercent(summary.grantMetrics.userGrowthRate)}</p>
          </div>
          <div className="analytics-card">
            <h3>Match Growth Rate</h3>
            <p>{formatPercent(summary.grantMetrics.matchGrowthRate)}</p>
          </div>
          <div className="analytics-card">
            <h3>Day 7 Retention</h3>
            <p>{formatPercent(summary.grantMetrics.day7Retention)}</p>
          </div>
        </div>
      </section>
    </div>
  );
}
