import pg from 'pg';

const { Pool } = pg;

const pool = new Pool({
  connectionString: process.env.ANALYTICS_DB_URL,
  ssl: process.env.NODE_ENV === 'development' ? false : { rejectUnauthorized: false }
});

const MAX_METADATA_KEYS = 64;
const MAX_METADATA_STRING = 200;

function normalizeTimestamp(value) {
  if (!value) return new Date().toISOString();
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return new Date().toISOString();
  return parsed.toISOString();
}

function sanitizeString(value, max = 160) {
  if (typeof value !== 'string') return '';
  return value.trim().slice(0, max);
}

function sanitizeMetadata(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }
  const safe = {};
  let count = 0;
  for (const [key, item] of Object.entries(value)) {
    if (count >= MAX_METADATA_KEYS) break;
    if (typeof key !== 'string' || key.length > 64) continue;
    if (typeof item === 'string') {
      safe[key] = item.slice(0, MAX_METADATA_STRING);
      count += 1;
    } else if (typeof item === 'number' || typeof item === 'boolean' || item === null) {
      safe[key] = item;
      count += 1;
    }
  }
  return Object.keys(safe).length ? safe : null;
}

function parseDateInput(input, defaultValue, isEnd = false) {
  if (!input) return defaultValue;
  if (typeof input === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(input)) {
    return new Date(`${input}T${isEnd ? '23:59:59.999' : '00:00:00.000'}Z`);
  }
  const direct = new Date(input);
  if (!Number.isNaN(direct.getTime())) return direct;
  return defaultValue;
}

function toRangeDates(startInput, endInput) {
  const now = new Date();
  const defaultStart = new Date(now);
  defaultStart.setUTCDate(defaultStart.getUTCDate() - 30);
  const start = parseDateInput(startInput, defaultStart, false);
  const end = parseDateInput(endInput, now, true);
  if (start > end) {
    return { start: end, end: start };
  }
  return { start, end };
}

function toIsoRange(startInput, endInput) {
  const { start, end } = toRangeDates(startInput, endInput);
  return {
    start: start.toISOString(),
    end: end.toISOString()
  };
}

function buildDayList(startIso, endIso) {
  const list = [];
  const cursor = new Date(startIso);
  const end = new Date(endIso);
  cursor.setUTCHours(0, 0, 0, 0);
  end.setUTCHours(0, 0, 0, 0);
  while (cursor <= end) {
    list.push(cursor.toISOString().slice(0, 10));
    cursor.setUTCDate(cursor.getUTCDate() + 1);
  }
  return list;
}

const ACTIVE_EVENT_TYPES = [
  'session_started',
  'session_ended',
  'user_joined',
  'match_joined',
  'match_created',
  'match_started',
  'match_finished',
  'reward_paid',
  'sponsor_match_created'
];

function fillSeries(days, rows) {
  const map = new Map(rows.map((row) => [row.day, Number(row.total) || 0]));
  return days.map((day) => ({ date: day, value: Number(map.get(day) || 0) }));
}

function computeGrowthRate(current, previous) {
  if (previous === 0) {
    return current > 0 ? 100 : 0;
  }
  return ((current - previous) / previous) * 100;
}

function computeRetention(cohortRows, activityRows) {
  const activityByUser = new Map();
  for (const row of activityRows) {
    const userId = row.user_id;
    if (!userId) continue;
    if (!activityByUser.has(userId)) {
      activityByUser.set(userId, new Set());
    }
    activityByUser.get(userId).add(row.day);
  }

  const now = new Date();
  const retention = { day1: 0, day7: 0, day30: 0 };
  const eligible = { day1: 0, day7: 0, day30: 0 };

  for (const row of cohortRows) {
    const userId = row.user_id;
    const cohortDay = row.day;
    if (!userId || !cohortDay) continue;

    const cohortDate = new Date(`${cohortDay}T00:00:00Z`);
    const daysSince = Math.floor((now.getTime() - cohortDate.getTime()) / 86400000);
    const userActivity = activityByUser.get(userId) || new Set();

    if (daysSince >= 1) {
      eligible.day1 += 1;
      const target = new Date(cohortDate);
      target.setUTCDate(target.getUTCDate() + 1);
      if (userActivity.has(target.toISOString().slice(0, 10))) retention.day1 += 1;
    }
    if (daysSince >= 7) {
      eligible.day7 += 1;
      const target = new Date(cohortDate);
      target.setUTCDate(target.getUTCDate() + 7);
      if (userActivity.has(target.toISOString().slice(0, 10))) retention.day7 += 1;
    }
    if (daysSince >= 30) {
      eligible.day30 += 1;
      const target = new Date(cohortDate);
      target.setUTCDate(target.getUTCDate() + 30);
      if (userActivity.has(target.toISOString().slice(0, 10))) retention.day30 += 1;
    }
  }

  return {
    day1: eligible.day1 ? (retention.day1 / eligible.day1) * 100 : 0,
    day7: eligible.day7 ? (retention.day7 / eligible.day7) * 100 : 0,
    day30: eligible.day30 ? (retention.day30 / eligible.day30) * 100 : 0,
    eligible
  };
}

export async function initAnalyticsDb() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS analytics_events (
      id SERIAL PRIMARY KEY,
      event_type TEXT NOT NULL,
      user_id TEXT,
      match_id TEXT,
      sponsor_id TEXT,
      value NUMERIC,
      metadata JSONB,
      timestamp TIMESTAMP DEFAULT NOW()
    );
  `);
  await pool.query('CREATE INDEX IF NOT EXISTS idx_event_type ON analytics_events(event_type);');
  await pool.query('CREATE INDEX IF NOT EXISTS idx_timestamp ON analytics_events(timestamp);');
  await pool.query('CREATE INDEX IF NOT EXISTS idx_user_id ON analytics_events(user_id);');
}

export async function logAnalyticsEvent(payload = {}) {
  const eventType = sanitizeString(payload.event_type || payload.eventType, 80);
  if (!eventType) {
    return { ok: false, error: 'event_type is required' };
  }

  const userId = sanitizeString(payload.user_id || payload.userId, 120) || null;
  const matchId = sanitizeString(payload.match_id || payload.matchId, 120) || null;
  const sponsorId = sanitizeString(payload.sponsor_id || payload.sponsorId, 120) || null;
  const valueRaw = Number(payload.value);
  const value = Number.isFinite(valueRaw) ? valueRaw : null;
  const metadata = sanitizeMetadata(payload.metadata);
  const timestamp = normalizeTimestamp(payload.timestamp);

  const result = await pool.query(
    `
      INSERT INTO analytics_events
        (event_type, user_id, match_id, sponsor_id, value, metadata, timestamp)
      VALUES ($1, $2, $3, $4, $5, $6, $7)
      RETURNING id, timestamp
    `,
    [eventType, userId, matchId, sponsorId, value, metadata, timestamp]
  );

  return { ok: true, id: result.rows[0]?.id, timestamp: result.rows[0]?.timestamp };
}

async function getDailyCounts({ eventTypes, startIso, endIso, aggregate = 'count', distinctUser = false }) {
  const selectValue = aggregate === 'sum'
    ? 'SUM(COALESCE(value, 0))'
    : distinctUser
      ? 'COUNT(DISTINCT user_id)'
      : 'COUNT(*)';

  const result = await pool.query(
    `
      SELECT to_char("timestamp" AT TIME ZONE 'UTC', 'YYYY-MM-DD') as day, ${selectValue} as total
      FROM analytics_events
      WHERE "timestamp" >= $1 AND "timestamp" <= $2
        AND event_type = ANY($3)
      GROUP BY day
      ORDER BY day
    `,
    [startIso, endIso, eventTypes]
  );

  return result.rows;
}

export async function getAnalyticsSummary({ start, end } = {}) {
  const { start: startIso, end: endIso } = toIsoRange(start, end);
  const days = buildDayList(startIso, endIso);

  const dauRows = await getDailyCounts({ eventTypes: ACTIVE_EVENT_TYPES, startIso, endIso, distinctUser: true });
  const dauSeries = fillSeries(days, dauRows);
  const dau = dauSeries.length ? dauSeries[dauSeries.length - 1].value : 0;

  const matchesCreatedSeries = fillSeries(
    days,
    await getDailyCounts({ eventTypes: ['match_created'], startIso, endIso })
  );
  const matchesToday = matchesCreatedSeries.length ? matchesCreatedSeries[matchesCreatedSeries.length - 1].value : 0;

  const totalUsersResult = await pool.query(
    `
      SELECT COUNT(DISTINCT user_id) as total
      FROM analytics_events
      WHERE user_id IS NOT NULL AND user_id != ''
    `
  );
  const totalUsers = Number(totalUsersResult.rows[0]?.total || 0);

  const newUsersSeries = fillSeries(
    days,
    await getDailyCounts({ eventTypes: ['user_registered'], startIso, endIso, distinctUser: true })
  );

  const uniqueUsersSeries = fillSeries(
    days,
    await getDailyCounts({ eventTypes: ACTIVE_EVENT_TYPES, startIso, endIso, distinctUser: true })
  );

  const lastIndex = days.length - 1;
  const todayUsers = uniqueUsersSeries[lastIndex]?.value || 0;
  const yesterdayUsers = uniqueUsersSeries[lastIndex - 1]?.value || 0;
  const dailyUserGrowthRate = computeGrowthRate(todayUsers, yesterdayUsers);

  const last7Start = new Date(endIso);
  last7Start.setUTCDate(last7Start.getUTCDate() - 6);
  const prev7Start = new Date(endIso);
  prev7Start.setUTCDate(prev7Start.getUTCDate() - 13);
  const prev7End = new Date(endIso);
  prev7End.setUTCDate(prev7End.getUTCDate() - 7);
  const mauStart = new Date(endIso);
  mauStart.setUTCDate(mauStart.getUTCDate() - 29);

  const weeklyCurrent = await pool.query(
    `
      SELECT COUNT(DISTINCT user_id) as total
      FROM analytics_events
      WHERE "timestamp" >= $1 AND "timestamp" <= $2
        AND event_type = ANY($3)
        AND user_id IS NOT NULL AND user_id != ''
    `,
    [last7Start.toISOString(), endIso, ACTIVE_EVENT_TYPES]
  );

  const weeklyPrevious = await pool.query(
    `
      SELECT COUNT(DISTINCT user_id) as total
      FROM analytics_events
      WHERE "timestamp" >= $1 AND "timestamp" <= $2
        AND event_type = ANY($3)
        AND user_id IS NOT NULL AND user_id != ''
    `,
    [prev7Start.toISOString(), prev7End.toISOString(), ACTIVE_EVENT_TYPES]
  );

  const weeklyGrowthRate = computeGrowthRate(
    Number(weeklyCurrent.rows[0]?.total || 0),
    Number(weeklyPrevious.rows[0]?.total || 0)
  );

  const matchCreatedCurrent = await pool.query(
    `
      SELECT COUNT(*) as total
      FROM analytics_events
      WHERE event_type = 'match_created' AND "timestamp" >= $1 AND "timestamp" <= $2
    `,
    [last7Start.toISOString(), endIso]
  );

  const matchCreatedPrevious = await pool.query(
    `
      SELECT COUNT(*) as total
      FROM analytics_events
      WHERE event_type = 'match_created' AND "timestamp" >= $1 AND "timestamp" <= $2
    `,
    [prev7Start.toISOString(), prev7End.toISOString()]
  );

  const matchCreationGrowthRate = computeGrowthRate(
    Number(matchCreatedCurrent.rows[0]?.total || 0),
    Number(matchCreatedPrevious.rows[0]?.total || 0)
  );

  const matchesFinishedResult = await pool.query(
    `
      SELECT COUNT(*) as total
      FROM analytics_events
      WHERE event_type = 'match_finished' AND "timestamp" >= $1 AND "timestamp" <= $2
    `,
    [startIso, endIso]
  );

  const matchesStartedResult = await pool.query(
    `
      SELECT COUNT(*) as total
      FROM analytics_events
      WHERE event_type = 'match_started' AND "timestamp" >= $1 AND "timestamp" <= $2
    `,
    [startIso, endIso]
  );

  const matchCompletionRate = Number(matchesStartedResult.rows[0]?.total || 0)
    ? (Number(matchesFinishedResult.rows[0]?.total || 0) / Number(matchesStartedResult.rows[0]?.total || 0)) * 100
    : 0;

  const matchPlayersResult = await pool.query(
    `
      SELECT match_id, COUNT(DISTINCT user_id) as players
      FROM analytics_events
      WHERE event_type = 'match_joined'
        AND match_id IS NOT NULL AND match_id != ''
        AND user_id IS NOT NULL AND user_id != ''
      GROUP BY match_id
    `
  );

  const avgPlayersPerMatch = matchPlayersResult.rows.length
    ? matchPlayersResult.rows.reduce((sum, row) => sum + Number(row.players || 0), 0) / matchPlayersResult.rows.length
    : 0;

  const matchesPerUserResult = await pool.query(
    `
      SELECT COUNT(*) as total, COUNT(DISTINCT user_id) as users
      FROM analytics_events
      WHERE event_type = 'match_joined'
        AND user_id IS NOT NULL AND user_id != ''
    `
  );

  const matchesPerUser = Number(matchesPerUserResult.rows[0]?.users || 0)
    ? Number(matchesPerUserResult.rows[0]?.total || 0) / Number(matchesPerUserResult.rows[0]?.users || 0)
    : 0;

  const rewardsTotalResult = await pool.query(
    `
      SELECT SUM(COALESCE(value, 0)) as total
      FROM analytics_events
      WHERE event_type = 'reward_paid'
    `
  );

  const rewardsSeries = fillSeries(
    days,
    await getDailyCounts({ eventTypes: ['reward_paid'], startIso, endIso, aggregate: 'sum' })
  );

  const rewardsTotal = Number(rewardsTotalResult.rows[0]?.total || 0);
  const rewardsPerMatch = Number(matchesFinishedResult.rows[0]?.total || 0)
    ? rewardsTotal / Number(matchesFinishedResult.rows[0]?.total || 0)
    : 0;

  const topWinnersResult = await pool.query(
    `
      SELECT user_id, SUM(COALESCE(value, 0)) as total
      FROM analytics_events
      WHERE event_type = 'reward_paid' AND user_id IS NOT NULL AND user_id != ''
      GROUP BY user_id
      ORDER BY total DESC
      LIMIT 5
    `
  );

  const sponsorCountResult = await pool.query(
    `
      SELECT COUNT(DISTINCT sponsor_id) as total
      FROM analytics_events
      WHERE sponsor_id IS NOT NULL AND sponsor_id != ''
    `
  );

  const sponsoredMatchesResult = await pool.query(
    `
      SELECT COUNT(*) as total
      FROM analytics_events
      WHERE event_type = 'sponsor_match_created'
    `
  );

  const sponsorFundingResult = await pool.query(
    `
      SELECT SUM(COALESCE(value, 0)) as total
      FROM analytics_events
      WHERE event_type = 'sponsor_match_created'
    `
  );

  const totalSponsors = Number(sponsorCountResult.rows[0]?.total || 0);
  const sponsorFundingVolume = Number(sponsorFundingResult.rows[0]?.total || 0);
  const avgSponsorValue = totalSponsors ? sponsorFundingVolume / totalSponsors : 0;

  const activeMatchesResult = await pool.query(
    `
      SELECT match_id,
        MAX(CASE WHEN event_type = 'match_started' THEN "timestamp" END) as started_at,
        MAX(CASE WHEN event_type = 'match_finished' THEN "timestamp" END) as finished_at
      FROM analytics_events
      WHERE match_id IS NOT NULL AND match_id != ''
      GROUP BY match_id
    `
  );

  const matchesCurrentlyActive = activeMatchesResult.rows.filter((row) => {
    if (!row.started_at) return false;
    if (!row.finished_at) return true;
    return row.finished_at < row.started_at;
  }).length;

  const returningUsers = Math.max(todayUsers - (newUsersSeries[lastIndex]?.value || 0), 0);
  const gamesPlayedPerUser = Number(matchesFinishedResult.rows[0]?.total || 0)
    ? Number(matchesFinishedResult.rows[0]?.total || 0) / Math.max(todayUsers, 1)
    : 0;

  const sessionRowsResult = await pool.query(
    `
      SELECT event_type, metadata, "timestamp"
      FROM analytics_events
      WHERE event_type IN ('session_started', 'session_ended')
        AND "timestamp" >= $1 AND "timestamp" <= $2
    `,
    [startIso, endIso]
  );

  const sessionStarts = new Map();
  const sessionDurations = [];

  for (const row of sessionRowsResult.rows) {
    const meta = row.metadata || {};
    const sessionId = meta?.session_id;
    if (!sessionId) continue;
    if (row.event_type === 'session_started') {
      sessionStarts.set(sessionId, row.timestamp);
    } else if (row.event_type === 'session_ended') {
      const started = sessionStarts.get(sessionId);
      if (started) {
        const duration = new Date(row.timestamp).getTime() - new Date(started).getTime();
        if (Number.isFinite(duration) && duration >= 0) {
          sessionDurations.push(duration / 1000);
        }
      }
    }
  }

  const avgSessionDuration = sessionDurations.length
    ? sessionDurations.reduce((sum, value) => sum + value, 0) / sessionDurations.length
    : 0;

  const cohortRowsResult = await pool.query(
    `
      SELECT user_id, to_char("timestamp" AT TIME ZONE 'UTC', 'YYYY-MM-DD') as day
      FROM analytics_events
      WHERE event_type = 'user_registered'
    `
  );

  const activityRowsResult = await pool.query(
    `
      SELECT user_id, to_char("timestamp" AT TIME ZONE 'UTC', 'YYYY-MM-DD') as day
      FROM analytics_events
      WHERE event_type = ANY($1)
        AND user_id IS NOT NULL AND user_id != ''
    `,
    [ACTIVE_EVENT_TYPES]
  );

  const retention = computeRetention(cohortRowsResult.rows, activityRowsResult.rows);

  const mauResult = await pool.query(
    `
      SELECT COUNT(DISTINCT user_id) as total
      FROM analytics_events
      WHERE "timestamp" >= $1 AND "timestamp" <= $2
        AND event_type = ANY($3)
        AND user_id IS NOT NULL AND user_id != ''
    `,
    [mauStart.toISOString(), endIso, ACTIVE_EVENT_TYPES]
  );

  return {
    range: { start: startIso, end: endIso },
    overview: {
      dailyActiveUsers: dau,
      totalUsers,
      matchesToday,
      totalRewardsDistributed: rewardsTotal,
      totalSponsors
    },
    userMetrics: {
      dau,
      wau: Number(weeklyCurrent.rows[0]?.total || 0),
      mau: Number(mauResult.rows[0]?.total || 0),
      totalUsers,
      newUsersPerDay: newUsersSeries[lastIndex]?.value || 0,
      uniqueUsersPerDay: todayUsers
    },
    growthMetrics: {
      dailyUserGrowthRate,
      weeklyGrowthRate,
      matchCreationGrowthRate
    },
    gameMetrics: {
      matchesCreatedPerDay: matchesCreatedSeries[lastIndex]?.value || 0,
      matchesCompleted: Number(matchesFinishedResult.rows[0]?.total || 0),
      matchesCurrentlyActive,
      averagePlayersPerMatch: avgPlayersPerMatch,
      matchCompletionRate,
      matchesPerUser
    },
    economyMetrics: {
      totalRewardsDistributed: rewardsTotal,
      rewardsDistributedPerDay: rewardsSeries[lastIndex]?.value || 0,
      averageRewardPerMatch: rewardsPerMatch,
      totalRewardVolume: rewardsTotal,
      topWinningPlayers: topWinnersResult.rows
    },
    sponsorMetrics: {
      totalSponsors,
      matchesSponsored: Number(sponsoredMatchesResult.rows[0]?.total || 0),
      sponsorFundingVolume,
      averageSponsorValue: avgSponsorValue
    },
    engagementMetrics: {
      averageSessionDuration: avgSessionDuration,
      returningUsers,
      newUsers: newUsersSeries[lastIndex]?.value || 0,
      gamesPlayedPerUser,
      playerRetention: {
        day1: retention.day1,
        day7: retention.day7,
        day30: retention.day30
      }
    },
    retentionMetrics: {
      day1: retention.day1,
      day7: retention.day7,
      day30: retention.day30,
      eligibleUsers: retention.eligible
    },
    grantMetrics: {
      dailyActiveUsers: dau,
      totalUsers,
      totalMatchesPlayed: Number(matchesFinishedResult.rows[0]?.total || 0),
      totalRewardsDistributed: rewardsTotal,
      numberOfSponsors: totalSponsors,
      averageMatchesPerUser: matchesPerUser,
      userGrowthRate: dailyUserGrowthRate,
      matchGrowthRate: matchCreationGrowthRate,
      day7Retention: retention.day7
    }
  };
}

export async function getAnalyticsTimeseries({ start, end } = {}) {
  const { start: startIso, end: endIso } = toIsoRange(start, end);
  const days = buildDayList(startIso, endIso);

  const dauSeries = fillSeries(
    days,
    await getDailyCounts({ eventTypes: ACTIVE_EVENT_TYPES, startIso, endIso, distinctUser: true })
  );
  const newUsersSeries = fillSeries(
    days,
    await getDailyCounts({ eventTypes: ['user_registered'], startIso, endIso, distinctUser: true })
  );
  const matchesCreatedSeries = fillSeries(
    days,
    await getDailyCounts({ eventTypes: ['match_created'], startIso, endIso })
  );
  const rewardsSeries = fillSeries(
    days,
    await getDailyCounts({ eventTypes: ['reward_paid'], startIso, endIso, aggregate: 'sum' })
  );

  const sponsorRowsResult = await pool.query(
    `
      SELECT to_char("timestamp" AT TIME ZONE 'UTC', 'YYYY-MM-DD') as day,
        COUNT(DISTINCT sponsor_id) as total
      FROM analytics_events
      WHERE event_type = 'sponsor_added'
        AND sponsor_id IS NOT NULL AND sponsor_id != ''
        AND "timestamp" >= $1 AND "timestamp" <= $2
      GROUP BY day
      ORDER BY day
    `,
    [startIso, endIso]
  );

  const sponsorSeries = fillSeries(days, sponsorRowsResult.rows);

  const cumulativeUsers = [];
  let total = 0;
  for (const point of newUsersSeries) {
    total += point.value;
    cumulativeUsers.push({ date: point.date, value: total });
  }

  const sponsorCumulative = [];
  let sponsorTotal = 0;
  for (const point of sponsorSeries) {
    sponsorTotal += point.value;
    sponsorCumulative.push({ date: point.date, value: sponsorTotal });
  }

  const matchesPerUserSeries = days.map((day, idx) => {
    const matches = matchesCreatedSeries[idx]?.value || 0;
    const users = dauSeries[idx]?.value || 0;
    return { date: day, value: users ? matches / users : 0 };
  });

  const cohortRowsResult = await pool.query(
    `
      SELECT user_id, to_char("timestamp" AT TIME ZONE 'UTC', 'YYYY-MM-DD') as day
      FROM analytics_events
      WHERE event_type = 'user_registered'
    `
  );

  const activityRowsResult = await pool.query(
    `
      SELECT user_id, to_char("timestamp" AT TIME ZONE 'UTC', 'YYYY-MM-DD') as day
      FROM analytics_events
      WHERE event_type = ANY($1)
        AND user_id IS NOT NULL AND user_id != ''
    `,
    [ACTIVE_EVENT_TYPES]
  );

  const retention = computeRetention(cohortRowsResult.rows, activityRowsResult.rows);

  return {
    range: { start: startIso, end: endIso },
    series: {
      dailyActiveUsers: dauSeries,
      userGrowth: cumulativeUsers,
      matchesCreated: matchesCreatedSeries,
      rewardsDistributed: rewardsSeries,
      sponsorGrowth: sponsorCumulative,
      matchesPerUser: matchesPerUserSeries
    },
    retention: {
      day1: retention.day1,
      day7: retention.day7,
      day30: retention.day30
    }
  };
}

export async function exportAnalyticsEvents({ start, end, format }) {
  const { start: startIso, end: endIso } = toIsoRange(start, end);
  const rowsResult = await pool.query(
    `
      SELECT id, event_type, user_id, match_id, sponsor_id, value, metadata, "timestamp"
      FROM analytics_events
      WHERE "timestamp" >= $1 AND "timestamp" <= $2
      ORDER BY "timestamp" ASC
    `,
    [startIso, endIso]
  );

  const rows = rowsResult.rows;

  if (format === 'csv') {
    const headers = ['id', 'event_type', 'user_id', 'match_id', 'sponsor_id', 'value', 'metadata', 'timestamp'];
    const lines = [headers.join(',')];
    for (const row of rows) {
      const values = headers.map((key) => {
        const value = row[key] ?? '';
        const str = typeof value === 'string' ? value.replace(/"/g, '""') : JSON.stringify(value);
        return `"${str}"`;
      });
      lines.push(values.join(','));
    }
    return { contentType: 'text/csv', body: lines.join('\n') };
  }

  return { contentType: 'application/json', body: JSON.stringify({ events: rows }) };
}
