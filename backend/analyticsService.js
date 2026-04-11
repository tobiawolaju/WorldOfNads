import { db } from './firebaseClient.js';
import { ref, push, get, query, orderByChild, startAt, endAt } from "firebase/database";

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
  // No-op for Firebase RTDB as it's schemaless
  console.log('[Analytics] Firebase RTDB connected');
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

  const eventsRef = ref(db, 'analytics/events');
  const newEventRef = push(eventsRef);
  
  const eventData = {
    event_type: eventType,
    user_id: userId,
    match_id: matchId,
    sponsor_id: sponsorId,
    value: value,
    metadata: metadata,
    timestamp: timestamp
  };

  await push(eventsRef, eventData);

  return { ok: true, id: newEventRef.key, timestamp: timestamp };
}

async function getEventsInRange(startIso, endIso) {
  try {
    const eventsRef = ref(db, 'analytics/events');
    const q = query(eventsRef, orderByChild('timestamp'), startAt(startIso), endAt(endIso));
    const snapshot = await get(q);
    if (!snapshot.exists()) return [];
    return Object.values(snapshot.val());
  } catch (error) {
    if (error.message.includes('Index not defined')) {
      console.error('[Analytics] MISSING INDEX: Please add ".indexOn": "timestamp" to your Firebase RTDB rules for path /analytics/events');
    } else {
      console.error('[Analytics] Query failed:', error);
    }
    return [];
  }
}

async function getDailyCounts({ eventTypes, startIso, endIso, aggregate = 'count', distinctUser = false }) {
  const events = await getEventsInRange(startIso, endIso);
  const filtered = events.filter(e => eventTypes.includes(e.event_type));
  
  const dayGroups = {};
  filtered.forEach(e => {
    const day = e.timestamp.slice(0, 10);
    if (!dayGroups[day]) dayGroups[day] = [];
    dayGroups[day].push(e);
  });
  
  return Object.entries(dayGroups).map(([day, dayEvents]) => {
    let total = 0;
    if (aggregate === 'sum') {
      total = dayEvents.reduce((sum, e) => sum + (Number(e.value) || 0), 0);
    } else if (distinctUser) {
      total = new Set(dayEvents.map(e => e.user_id).filter(id => !!id)).size;
    } else {
      total = dayEvents.length;
    }
    return { day, total };
  }).sort((a, b) => a.day.localeCompare(b.day));
}

export async function getAnalyticsSummary({ start, end } = {}) {
  const { start: startIso, end: endIso } = toIsoRange(start, end);
  const days = buildDayList(startIso, endIso);

  // Fetch all events needed for the current range once to optimize
  const allEventsInRange = await getEventsInRange(startIso, endIso);

  // Helper for in-memory counting
  const countEvents = (events, types, distinct = false) => {
    const filtered = events.filter(e => types.includes(e.event_type));
    if (distinct) return new Set(filtered.map(e => e.user_id).filter(id => !!id)).size;
    return filtered.length;
  };

  const dauRows = await getDailyCounts({ eventTypes: ACTIVE_EVENT_TYPES, startIso, endIso, distinctUser: true });
  const dauSeries = fillSeries(days, dauRows);
  const dau = dauSeries.length ? dauSeries[dauSeries.length - 1].value : 0;

  const matchesCreatedSeries = fillSeries(
    days,
    await getDailyCounts({ eventTypes: ['match_created'], startIso, endIso })
  );
  const matchesToday = matchesCreatedSeries.length ? matchesCreatedSeries[matchesCreatedSeries.length - 1].value : 0;

  // Total users (across all time is harder without full scan, but we can do a broad scan or use range)
  // For simplicity since we moved to RTDB, we scan all analytics/events for now or broad range
  const totalUsersEventsSnapshot = await get(ref(db, 'analytics/events'));
  const allEvents = totalUsersEventsSnapshot.exists() ? Object.values(totalUsersEventsSnapshot.val()) : [];
  const totalUsers = new Set(allEvents.map(e => e.user_id).filter(id => !!id)).size;

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

  const weeklyCurrentEvents = await getEventsInRange(last7Start.toISOString(), endIso);
  const weeklyCurrentTotal = new Set(weeklyCurrentEvents.filter(e => ACTIVE_EVENT_TYPES.includes(e.event_type) && !!e.user_id).map(e => e.user_id)).size;

  const weeklyPreviousEvents = await getEventsInRange(prev7Start.toISOString(), prev7End.toISOString());
  const weeklyPreviousTotal = new Set(weeklyPreviousEvents.filter(e => ACTIVE_EVENT_TYPES.includes(e.event_type) && !!e.user_id).map(e => e.user_id)).size;

  const weeklyGrowthRate = computeGrowthRate(weeklyCurrentTotal, weeklyPreviousTotal);

  const matchCreatedCurrent = allEventsInRange.filter(e => e.event_type === 'match_created' && e.timestamp >= last7Start.toISOString()).length;
  const matchCreatedPrevious = allEvents.filter(e => e.event_type === 'match_created' && e.timestamp >= prev7Start.toISOString() && e.timestamp <= prev7End.toISOString()).length;

  const matchCreationGrowthRate = computeGrowthRate(matchCreatedCurrent, matchCreatedPrevious);

  const matchesFinishedCount = allEventsInRange.filter(e => e.event_type === 'match_finished').length;
  const matchesStartedCount = allEventsInRange.filter(e => e.event_type === 'match_started').length;

  const matchCompletionRate = matchesStartedCount ? (matchesFinishedCount / matchesStartedCount) * 100 : 0;

  const matchPlayersMap = new Map();
  allEvents.filter(e => e.event_type === 'match_joined' && !!e.match_id && !!e.user_id).forEach(e => {
    if (!matchPlayersMap.has(e.match_id)) matchPlayersMap.set(e.match_id, new Set());
    matchPlayersMap.get(e.match_id).add(e.user_id);
  });

  const avgPlayersPerMatch = matchPlayersMap.size 
    ? Array.from(matchPlayersMap.values()).reduce((sum, set) => sum + set.size, 0) / matchPlayersMap.size 
    : 0;

  const matchUserJoins = allEvents.filter(e => e.event_type === 'match_joined' && !!e.user_id);
  const distinctMatchUsers = new Set(matchUserJoins.map(e => e.user_id)).size;
  const matchesPerUser = distinctMatchUsers ? matchUserJoins.length / distinctMatchUsers : 0;

  const rewardsEvents = allEvents.filter(e => e.event_type === 'reward_paid');
  const rewardsTotal = rewardsEvents.reduce((sum, e) => sum + (Number(e.value) || 0), 0);
  const rewardsSeries = fillSeries(
    days,
    await getDailyCounts({ eventTypes: ['reward_paid'], startIso, endIso, aggregate: 'sum' })
  );

  const rewardsPerMatch = matchesFinishedCount ? rewardsTotal / matchesFinishedCount : 0;

  const winnerRewards = new Map();
  rewardsEvents.filter(e => !!e.user_id).forEach(e => {
    winnerRewards.set(e.user_id, (winnerRewards.get(e.user_id) || 0) + (Number(e.value) || 0));
  });
  const topWinners = Array.from(winnerRewards.entries())
    .map(([user_id, total]) => ({ user_id, total }))
    .sort((a,b) => b.total - a.total)
    .slice(0, 5);

  const totalSponsors = new Set(allEvents.map(e => e.sponsor_id).filter(id => !!id)).size;
  const sponsoredMatchesCount = allEvents.filter(e => e.event_type === 'sponsor_match_created').length;
  const sponsorFundingVolume = allEvents.filter(e => e.event_type === 'sponsor_match_created').reduce((sum, e) => sum + (Number(e.value) || 0), 0);
  const avgSponsorValue = totalSponsors ? sponsorFundingVolume / totalSponsors : 0;

  const activeMatchesMap = new Map();
  allEvents.filter(e => !!e.match_id).forEach(e => {
    if (!activeMatchesMap.has(e.match_id)) activeMatchesMap.set(e.match_id, { started: null, finished: null });
    if (e.event_type === 'match_started') activeMatchesMap.get(e.match_id).started = e.timestamp;
    if (e.event_type === 'match_finished') activeMatchesMap.get(e.match_id).finished = e.timestamp;
  });

  const matchesCurrentlyActive = Array.from(activeMatchesMap.values()).filter(m => m.started && (!m.finished || m.finished < m.started)).length;

  const returningUsers = Math.max(todayUsers - (newUsersSeries[lastIndex]?.value || 0), 0);
  const gamesPlayedPerUser = matchesFinishedCount ? matchesFinishedCount / Math.max(todayUsers, 1) : 0;

  const sessionStarts = new Map();
  const sessionDurations = [];
  allEventsInRange.filter(e => e.event_type === 'session_started' || e.event_type === 'session_ended').forEach(e => {
    const sessionId = e.metadata?.session_id;
    if (!sessionId) return;
    if (e.event_type === 'session_started') sessionStarts.set(sessionId, e.timestamp);
    else if (e.event_type === 'session_ended') {
      const started = sessionStarts.get(sessionId);
      if (started) {
        const dur = new Date(e.timestamp).getTime() - new Date(started).getTime();
        if (dur >= 0) sessionDurations.push(dur / 1000);
      }
    }
  });

  const avgSessionDuration = sessionDurations.length ? sessionDurations.reduce((s,v) => s+v, 0) / sessionDurations.length : 0;

  const cohortEvents = allEvents.filter(e => e.event_type === 'user_registered').map(e => ({ user_id: e.user_id, day: e.timestamp.slice(0, 10) }));
  const activityEvents = allEvents.filter(e => ACTIVE_EVENT_TYPES.includes(e.event_type) && !!e.user_id).map(e => ({ user_id: e.user_id, day: e.timestamp.slice(0, 10) }));
  const retention = computeRetention(cohortEvents, activityEvents);

  const mauEvents = await getEventsInRange(mauStart.toISOString(), endIso);
  const mauTotal = new Set(mauEvents.filter(e => ACTIVE_EVENT_TYPES.includes(e.event_type) && !!e.user_id).map(e => e.user_id)).size;

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
      wau: weeklyCurrentTotal,
      mau: mauTotal,
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
      matchesCompleted: matchesFinishedCount,
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
      topWinningPlayers: topWinners
    },
    sponsorMetrics: {
      totalSponsors,
      matchesSponsored: sponsoredMatchesCount,
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
      totalMatchesPlayed: matchesFinishedCount,
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

  const totalUsersEventsSnapshot = await get(ref(db, 'analytics/events'));
  const allEvents = totalUsersEventsSnapshot.exists() ? Object.values(totalUsersEventsSnapshot.val()) : [];

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

  const sponsorHistory = allEvents.filter(e => e.event_type === 'sponsor_added' && !!e.sponsor_id && e.timestamp >= startIso && e.timestamp <= endIso);
  const sponsorDayGroups = {};
  sponsorHistory.forEach(e => {
    const day = e.timestamp.slice(0, 10);
    if (!sponsorDayGroups[day]) sponsorDayGroups[day] = new Set();
    sponsorDayGroups[day].add(e.sponsor_id);
  });
  const sponsorRows = Object.entries(sponsorDayGroups).map(([day, set]) => ({ day, total: set.size }));
  const sponsorSeries = fillSeries(days, sponsorRows);

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

  const cohortEvents = allEvents.filter(e => e.event_type === 'user_registered').map(e => ({ user_id: e.user_id, day: e.timestamp.slice(0, 10) }));
  const activityEvents = allEvents.filter(e => ACTIVE_EVENT_TYPES.includes(e.event_type) && !!e.user_id).map(e => ({ user_id: e.user_id, day: e.timestamp.slice(0, 10) }));

  const retention = computeRetention(cohortEvents, activityEvents);

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
  const rows = await getEventsInRange(startIso, endIso);

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
