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

function formatMon(value: number) {
  if (!Number.isFinite(value)) return "0 MON";
  return `${formatNumber(value, 2)} MON`;
}

type SeriesPoint = { date: string; value: number };

type AnalyticsSummary = {
  range?: {
    start: string;
    end: string;
    startDay: string;
    endDay: string;
    days: number;
    dataStartDay?: string;
  };
  overview: {
    dailyActiveUsers: number;
    totalUsers: number;
    matchesToday: number;
    totalRewardsDistributed: number;
    totalSponsors: number;
    matchesInRange?: number;
    activeUsersInRange?: number;
    pendingRewards?: number;
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
    newUsersInRange?: number;
    activeUsersInRange?: number;
  };
  gameMetrics: {
    matchesCreatedPerDay: number;
    matchesCompleted: number;
    matchesCurrentlyActive: number;
    averagePlayersPerMatch: number;
    matchCompletionRate: number;
    matchesPerUser: number;
    matchesCreatedInRange?: number;
    matchesPlayedInRange?: number;
    playersTracked?: number;
  };
  economyMetrics: {
    totalRewardsDistributed: number;
    rewardsDistributedPerDay: number;
    averageRewardPerMatch: number;
    totalRewardVolume: number;
    pendingRewards?: number;
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
    pairedSessions?: number;
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

function MetricCard({
  title,
  value,
  hint
}: {
  title: string;
  value: React.ReactNode;
  hint?: string;
}) {
  return (
    <div className="analytics-card">
      <h3>{title}</h3>
      <p>{value}</p>
      {hint ? <small className="analytics-card__hint">{hint}</small> : null}
    </div>
  );
}

function ChartCard({
  title,
  labels,
  values,
  color = "#2f855a",
  type = "line",
  percent = false
}: {
  title: string;
  labels: string[];
  values: number[];
  color?: string;
  type?: "line" | "bar";
  percent?: boolean;
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
            backgroundColor: type === "bar" ? "rgba(255, 122, 182, 0.4)" : "rgba(255, 122, 182, 0.2)",
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
            beginAtZero: true,
            ...(percent
              ? { max: 100, ticks: { callback: (value: string | number) => `${value}%` } }
              : {})
          }
        }
      }
    });

    return () => {
      if (chartRef.current) {
        chartRef.current.destroy();
      }
    };
  }, [labels, values, color, title, type, percent]);

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

  const loadAnalytics = async (from = startDate, to = endDate) => {
    setLoading(true);
    setError("");
    try {
      // `ok` used to be ignored, so a 404 (the API URL not configured) or a 500
      // was parsed as JSON, threw somewhere else, and surfaced as "no data".
      const [summaryRes, seriesRes] = await Promise.all([
        fetch(buildUrl(`/analytics/summary?start=${from}&end=${to}`), { cache: "no-store" }),
        fetch(buildUrl(`/analytics/timeseries?start=${from}&end=${to}`), { cache: "no-store" })
      ]);

      if (!summaryRes.ok || !seriesRes.ok) {
        throw new Error(
          `The analytics API answered ${summaryRes.status} and ${seriesRes.status}.`
        );
      }

      const summaryData = (await summaryRes.json()) as AnalyticsSummary;
      const seriesData = (await seriesRes.json()) as AnalyticsSeries;

      if (!summaryData?.overview || !seriesData?.series) {
        throw new Error("The analytics API returned an unexpected shape.");
      }

      setSummary(summaryData);
      setSeries(seriesData);
    } catch (err) {
      const msg =
        err instanceof Error && err.message
          ? `Failed to load analytics data. ${err.message}`
          : "Failed to load analytics data.";
      setError(msg);
      showErrorToast("Failed to load analytics data.");
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
      if (!response.ok) {
        throw new Error(`The export endpoint answered ${response.status}.`);
      }
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
        {error ? (
          <div className="analytics-empty">
            <p className="analytics-auth__error">{error}</p>
            <button onClick={() => loadAnalytics()} disabled={loading}>
              {loading ? "Retrying..." : "Retry"}
            </button>
          </div>
        ) : (
          <p className="text-inline-accent">{loading ? "Loading analytics..." : "No analytics data yet."}</p>
        )}
      </div>
    );
  }

  const chartLabels = series.series.dailyActiveUsers.map((point) => point.date);
  const rangeStart = summary.range?.startDay ?? startDate;
  const rangeEnd = summary.range?.endDay ?? endDate;
  const rangeDays = summary.range?.days ?? chartLabels.length;

  const activeInRange = summary.userMetrics.activeUsersInRange ?? summary.overview.activeUsersInRange ?? 0;
  const newInRange = summary.userMetrics.newUsersInRange ?? summary.engagementMetrics.newUsers;
  const matchesInRange = summary.gameMetrics.matchesCreatedInRange ?? summary.overview.matchesInRange ?? 0;
  const matchesPlayed = summary.gameMetrics.matchesPlayedInRange ?? summary.gameMetrics.matchesCompleted;
  const pendingRewards = summary.economyMetrics.pendingRewards ?? summary.overview.pendingRewards ?? 0;
  const pairedSessions = summary.engagementMetrics.pairedSessions ?? 0;

  return (
    <div className="analytics-page">
      <header className="analytics-header">
        <div>
          <p className="analytics-eyebrow">World Of Nads</p>
          <h1>Analytics Dashboard</h1>
          <p className="analytics-subtext">
            Traction, growth, engagement, and economy insights.
          </p>
          <p className="analytics-subtext analytics-range">
            {rangeStart} → {rangeEnd} · {rangeDays} {rangeDays === 1 ? "day" : "days"} · UTC days ·
            users, matches and rewards are read from their records, activity from the event log.
          </p>
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
            <button onClick={() => loadAnalytics()} disabled={loading}>
              {loading ? "Refreshing..." : "Apply"}
            </button>
            {summary.range?.dataStartDay ? (
              <button
                type="button"
                onClick={() => {
                  const from = summary.range?.dataStartDay ?? startDate;
                  setStartDate(from);
                  loadAnalytics(from, endDate);
                }}
                disabled={loading}
              >
                All time
              </button>
            ) : null}
          </div>
          <div className="export-actions">
            <button onClick={() => handleExport("csv")}>Export CSV</button>
          </div>
        </div>
      </header>

      <section className="analytics-section">
        <h2>Overview</h2>
        <div className="analytics-grid">
          <MetricCard
            title="Active Users"
            value={formatNumber(summary.overview.dailyActiveUsers)}
            hint={`on ${rangeEnd}`}
          />
          <MetricCard
            title="Active Users (range)"
            value={formatNumber(activeInRange)}
            hint={`any activity between ${rangeStart} and ${rangeEnd}`}
          />
          <MetricCard
            title="Registered Users"
            value={formatNumber(summary.overview.totalUsers)}
            hint="one per person, de-duplicated by Privy id"
          />
          <MetricCard
            title="Matches Created"
            value={formatNumber(matchesInRange)}
            hint="in the selected range"
          />
          <MetricCard
            title="Rewards Paid"
            value={formatMon(summary.overview.totalRewardsDistributed)}
            hint="settled reward rows in the range"
          />
          <MetricCard
            title="Sponsors"
            value={formatNumber(summary.overview.totalSponsors)}
            hint="all time"
          />
        </div>
      </section>

      <section className="analytics-section">
        <h2>Growth</h2>
        <div className="analytics-grid">
          <MetricCard title="Daily User Growth Rate" value={formatPercent(summary.growthMetrics.dailyUserGrowthRate)} hint={`${rangeEnd} vs the day before`} />
          <MetricCard title="Weekly Growth Rate" value={formatPercent(summary.growthMetrics.weeklyGrowthRate)} hint="last 7 days vs the 7 before" />
          <MetricCard title="Match Creation Growth Rate" value={formatPercent(summary.growthMetrics.matchCreationGrowthRate)} hint="last 7 days vs the 7 before" />
        </div>
        <div className="analytics-grid charts-grid">
          <ChartCard
            title="Daily Active Users"
            labels={chartLabels}
            values={series.series.dailyActiveUsers.map((point) => point.value)}
            color="#ff7ab6"
          />
          <ChartCard
            title="Registered Users (cumulative)"
            labels={chartLabels}
            values={series.series.userGrowth.map((point) => point.value)}
            color="#ff7ab6"
          />
        </div>
      </section>

      <section className="analytics-section">
        <h2>Users</h2>
        <div className="analytics-grid">
          <MetricCard title="DAU" value={formatNumber(summary.userMetrics.dau)} hint={`active on ${rangeEnd}`} />
          <MetricCard title="WAU" value={formatNumber(summary.userMetrics.wau)} hint="last 7 days of the range" />
          <MetricCard title="MAU" value={formatNumber(summary.userMetrics.mau)} hint="last 30 days of the range" />
          <MetricCard title="New Users (range)" value={formatNumber(newInRange)} hint="first seen in the range" />
          <MetricCard title="New Users" value={formatNumber(summary.userMetrics.newUsersPerDay)} hint={`first seen on ${rangeEnd}`} />
          <MetricCard title="Returning Users" value={formatNumber(summary.engagementMetrics.returningUsers)} hint="active in the range, first seen before it" />
        </div>
      </section>

      <section className="analytics-section">
        <h2>Matches</h2>
        <div className="analytics-grid">
          <MetricCard title="Matches Created" value={formatNumber(matchesInRange)} hint="in the range, from match records" />
          <MetricCard title="Matches Played" value={formatNumber(matchesPlayed)} hint="started in the range and not cancelled" />
          <MetricCard title="Live Now" value={formatNumber(summary.gameMetrics.matchesCurrentlyActive)} hint="inside the 300 s round window" />
          <MetricCard
            title="Average Players Per Match"
            value={formatNumber(summary.gameMetrics.averagePlayersPerMatch, 1)}
            hint={`from join events, practice rooms excluded${summary.gameMetrics.playersTracked ? ` · ${summary.gameMetrics.playersTracked} players tracked` : ""}`}
          />
          <MetricCard title="Match Completion Rate" value={formatPercent(summary.gameMetrics.matchCompletionRate)} hint="played ÷ started in the range" />
          <MetricCard title="Matches Per User" value={formatNumber(summary.gameMetrics.matchesPerUser, 2)} hint="matches joined by the players who joined them" />
        </div>
        <div className="analytics-grid charts-grid">
          <ChartCard
            title="Matches Created Per Day"
            labels={chartLabels}
            values={series.series.matchesCreated.map((point) => point.value)}
            color="#ff7ab6"
          />
          <ChartCard
            title="Matches Per Active User"
            labels={chartLabels}
            values={series.series.matchesPerUser.map((point) => point.value)}
            color="#ff7ab6"
          />
        </div>
      </section>

      <section className="analytics-section">
        <h2>Economy</h2>
        <div className="analytics-grid">
          <MetricCard title="Rewards Paid (range)" value={formatMon(summary.economyMetrics.totalRewardsDistributed)} hint="from the rewards ledger" />
          <MetricCard title="Rewards Paid" value={formatMon(summary.economyMetrics.rewardsDistributedPerDay)} hint={`on ${rangeEnd}`} />
          <MetricCard title="Average Reward Per Match" value={formatMon(summary.economyMetrics.averageRewardPerMatch)} hint="only matches that paid out" />
          <MetricCard title="Prize Pool Escrowed" value={formatMon(summary.economyMetrics.totalRewardVolume)} hint="prizes of matches created in the range" />
          <MetricCard title="Pending Rewards" value={formatMon(pendingRewards)} hint="written but not yet settled" />
        </div>
        <div className="analytics-grid charts-grid">
          <ChartCard
            title="Rewards Paid Per Day (MON)"
            labels={chartLabels}
            values={series.series.rewardsDistributed.map((point) => point.value)}
            color="#ff7ab6"
          />
        </div>
        <div className="analytics-card">
          <h3>Top Winning Players</h3>
          <div className="analytics-table">
            <div className="analytics-table__row analytics-table__row--head">
              <span>Player</span>
              <span>Rewards</span>
            </div>
            {summary.economyMetrics.topWinningPlayers.length === 0 ? (
              <div className="analytics-table__empty">No rewards paid in this range.</div>
            ) : (
              summary.economyMetrics.topWinningPlayers.map((player) => (
                <div className="analytics-table__row" key={player.user_id}>
                  <span>{player.user_id}</span>
                  <span>{formatMon(player.total)}</span>
                </div>
              ))
            )}
          </div>
        </div>
      </section>

      <section className="analytics-section">
        <h2>Sponsors</h2>
        <div className="analytics-grid">
          <MetricCard title="Sponsors" value={formatNumber(summary.sponsorMetrics.totalSponsors)} hint="all time, from match records" />
          <MetricCard title="Matches Sponsored" value={formatNumber(summary.sponsorMetrics.matchesSponsored)} hint="created in the range" />
          <MetricCard title="Sponsor Funding" value={formatMon(summary.sponsorMetrics.sponsorFundingVolume)} hint="prizes escrowed in the range" />
          <MetricCard title="Average Sponsor Value" value={formatMon(summary.sponsorMetrics.averageSponsorValue)} hint="per sponsor active in the range" />
        </div>
        <div className="analytics-grid charts-grid">
          <ChartCard
            title="Sponsors (cumulative)"
            labels={chartLabels}
            values={series.series.sponsorGrowth.map((point) => point.value)}
            color="#ff7ab6"
          />
        </div>
      </section>

      <section className="analytics-section">
        <h2>Engagement</h2>
        <div className="analytics-grid">
          <MetricCard
            title="Average Session Duration"
            value={pairedSessions ? `${formatNumber(summary.engagementMetrics.averageSessionDuration, 1)} s` : "—"}
            hint={pairedSessions ? `from ${formatNumber(pairedSessions)} completed sessions` : "no session has reported an end yet"}
          />
          <MetricCard title="Returning Users" value={formatNumber(summary.engagementMetrics.returningUsers)} hint="active in the range, first seen before it" />
          <MetricCard title="New Users" value={formatNumber(newInRange)} hint="first seen in the range" />
          <MetricCard title="Matches Played Per Active User" value={formatNumber(summary.engagementMetrics.gamesPlayedPerUser, 2)} hint="played matches ÷ active users in the range" />
        </div>
        <div className="analytics-grid charts-grid">
          <ChartCard
            title="Retention (all-time cohorts)"
            labels={["Day 1", "Day 7", "Day 30"]}
            values={[series.retention.day1, series.retention.day7, series.retention.day30]}
            color="#ff7ab6"
            type="bar"
            percent
          />
        </div>
      </section>

      <section className="analytics-section">
        <h2>Grant Metrics</h2>
        <div className="analytics-grid">
          <MetricCard title="Daily Active Users" value={formatNumber(summary.grantMetrics.dailyActiveUsers)} hint={`on ${rangeEnd}`} />
          <MetricCard title="Total Users" value={formatNumber(summary.grantMetrics.totalUsers)} hint="registered accounts" />
          <MetricCard title="Total Matches Played" value={formatNumber(summary.grantMetrics.totalMatchesPlayed)} hint="in the range" />
          <MetricCard title="Total Rewards Distributed" value={formatMon(summary.grantMetrics.totalRewardsDistributed)} hint="in the range" />
          <MetricCard title="Number of Sponsors" value={formatNumber(summary.grantMetrics.numberOfSponsors)} hint="all time" />
          <MetricCard title="Average Matches per User" value={formatNumber(summary.grantMetrics.averageMatchesPerUser, 2)} hint="matches joined per joined player" />
          <MetricCard title="User Growth Rate" value={formatPercent(summary.grantMetrics.userGrowthRate)} hint="day over day" />
          <MetricCard title="Match Growth Rate" value={formatPercent(summary.grantMetrics.matchGrowthRate)} hint="week over week" />
          <MetricCard title="Day 7 Retention" value={formatPercent(summary.grantMetrics.day7Retention)} hint="all-time cohorts" />
        </div>
      </section>
    </div>
  );
}
