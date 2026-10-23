// Pure analytics maths: no Firebase, no network, no clock of its own.
//
// `analyticsService.js` fetches the four nodes this needs (`analytics/events`,
// `users`, `matches`, `rewards`) and hands them in. Keeping the maths separate
// is what makes it testable without an `npm install` (see AGENTS.md), and it is
// also why every number on the admin tab has exactly one definition.
//
// Why the numbers are built the way they are:
//
// * The event stream is not a ledger. `reward_paid` is never written by the
//   settlement path, `user_registered` only exists for a handful of accounts and
//   `match_started`/`match_finished` are emitted by the status worker, not by a
//   round. So users come from `users`, matches from `matches` and money from
//   `rewards`; events are only used for activity, sessions and join counts.
// * Every event carries the Privy DID as `user_id` and the username in
//   `metadata.username`. Counting `user_id` alone splits one person into two or
//   three identities and counts sponsor accounts as players. Identities are
//   resolved against the roster, and the roster is de-duplicated by `privyId`.
// * There is no registration date on a user record, so "new" means "first seen
//   in the event stream". That covers every account instead of the nine that
//   happen to have a `user_registered` event, and it is measured against the
//   same clock as activity, so the two can be compared.
// * A date range means the same thing everywhere: a metric without "all time"
//   in its name describes the selected range only. The one deliberate exception
//   is retention, which needs cohorts from before the range to be meaningful.

/** Events that mean "this person was here". */
export const ACTIVE_EVENT_TYPES = [
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

/** The round is live from 5 minutes before its start until 60 s after it ends. */
export const MATCH_LIVE_WINDOW_SECONDS = 360;
const DAY_MS = 86400000;

const TRAINING_LOBBY_NAMES = new Set(['training lobby', 'training-lobby', 'default']);
const NOT_A_SPONSOR = new Set(['training lobby', 'training-lobby', 'default', '']);

function round6(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return 0;
  return Math.round(n * 1e6) / 1e6;
}

function sanitizeString(value, max = 160) {
  if (typeof value !== 'string') return '';
  return value.trim().slice(0, max);
}

function timeOf(value) {
  if (!value) return null;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function dayOf(value) {
  const t = timeOf(value);
  return t === null ? null : new Date(t).toISOString().slice(0, 10);
}

function isTrainingLobby(matchId, sponsorId) {
  const id = typeof matchId === 'string' ? matchId.trim().toLowerCase() : '';
  const sponsor = typeof sponsorId === 'string' ? sponsorId.trim().toLowerCase() : '';
  if (TRAINING_LOBBY_NAMES.has(id)) return true;
  if (id.startsWith('match-training-lobby') || id.startsWith('training-lobby')) return true;
  // The join events the Godot client sends carry the lobby name as `sponsor_id`.
  return TRAINING_LOBBY_NAMES.has(sponsor) && id.startsWith('match-');
}

export function parseDateInput(input, defaultValue, isEnd = false) {
  if (!input) return defaultValue;
  if (typeof input === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(input)) {
    return new Date(`${input}T${isEnd ? '23:59:59.999' : '00:00:00.000'}Z`);
  }
  const direct = new Date(input);
  if (!Number.isNaN(direct.getTime())) return direct;
  return defaultValue;
}

/**
 * The selected range as UTC instants. Both ends are inclusive, and the whole of
 * the end day is included so an "end" date of today means "up to now today".
 */
export function toRangeDates(startInput, endInput, now = Date.now()) {
  const nowDate = new Date(now);
  const defaultStart = new Date(nowDate.getTime() - 30 * DAY_MS);
  const start = parseDateInput(startInput, defaultStart, false);
  const end = parseDateInput(endInput, nowDate, true);
  if (start > end) return { start: end, end: start };
  return { start, end };
}

export function buildDayList(startIso, endIso) {
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

function computeGrowthRate(current, previous) {
  if (previous === 0) return current > 0 ? 100 : 0;
  return ((current - previous) / previous) * 100;
}

function rewardAmountMon(row) {
  if (!row || typeof row !== 'object') return 0;
  const direct = Number(row.amountMon);
  if (Number.isFinite(direct)) return direct;
  // Older rows store only "3.6000 MON".
  const parsed = Number(String(row.amount || '').replace(/[^0-9.-]/g, ''));
  return Number.isFinite(parsed) ? parsed : 0;
}

/**
 * One key per person, and one display name per key.
 *
 * A person can appear as `users/<username>`, `users/<wallet>` and `users/Anon`
 * (all sharing a `privyId`), while events use the DID. `privyId` is therefore
 * the identity; the nicest username on any of that person's records is the label.
 */
function buildDirectory(users) {
  const records = [];
  for (const [key, user] of Object.entries(users || {})) {
    if (!user || typeof user !== 'object') continue;
    const username = sanitizeString(user.username) || sanitizeString(key);
    if (!username) continue;
    records.push({
      key,
      username,
      privyId: sanitizeString(user.privyId),
      wallets: [user.wallet, user.ethAddress]
        .map((value) => sanitizeString(value))
        .filter(Boolean)
    });
  }

  const keyForPrivyId = new Map();
  const keyForWallet = new Map();
  const keyForName = new Map();
  const nameFor = new Map();
  const accounts = new Set();

  const isPlaceholder = (name) => /^0x[0-9a-f]{40}$/i.test(name) || name.toLowerCase() === 'anon';

  for (const record of records) {
    const identityKey = record.privyId
      ? `did:${record.privyId}`
      : record.wallets.length
        ? `wallet:${record.wallets[0].toLowerCase()}`
        : `name:${record.username.toLowerCase()}`;

    accounts.add(identityKey);
    if (record.privyId) keyForPrivyId.set(record.privyId, identityKey);
    for (const wallet of record.wallets) keyForWallet.set(wallet.toLowerCase(), identityKey);
    keyForName.set(record.username.toLowerCase(), identityKey);
    for (const wallet of record.wallets) keyForName.set(wallet.toLowerCase(), identityKey);

    const current = nameFor.get(identityKey);
    if (!current || (isPlaceholder(current) && !isPlaceholder(record.username))) {
      nameFor.set(identityKey, record.username);
    }
  }

  return {
    accounts,
    keyForPrivyId,
    keyForWallet,
    keyForName,
    nameFor,
    /** Resolves any event to the person behind it, or null for anonymous noise. */
    keyOf(event) {
      const userId = sanitizeString(event?.user_id);
      if (userId) {
        const direct =
          keyForPrivyId.get(userId) ||
          keyForWallet.get(userId.toLowerCase()) ||
          keyForName.get(userId.toLowerCase());
        if (direct) return direct;
      }
      const metaName = sanitizeString(event?.metadata?.username);
      if (metaName) {
        const known = keyForName.get(metaName.toLowerCase());
        if (known) return known;
        return `name:${metaName.toLowerCase()}`;
      }
      return userId ? `id:${userId}` : null;
    },
    nameOf(key) {
      const name = nameFor.get(key);
      if (name) return name;
      return String(key || '').replace(/^(did|wallet|name|id):/, '');
    }
  };
}

function emptySets() {
  return new Map();
}

function addToSetMap(map, key, value) {
  if (!map.has(key)) map.set(key, new Set());
  map.get(key).add(value);
}

function unionOfDays(setOfSets, days) {
  const union = new Set();
  for (const day of days) {
    const set = setOfSets.get(day);
    if (set) for (const value of set) union.add(value);
  }
  return union;
}

function isPlayedMatch(match) {
  const status = sanitizeString(match?.status).toLowerCase();
  const settlement = sanitizeString(match?.settlement?.status).toLowerCase();
  if (status === 'cancelled' || settlement === 'refunded' || settlement === 'cancelled') return false;
  return status === 'settled' || status === 'completed' || settlement === 'settled_onchain';
}

function isCancelledMatch(match) {
  const status = sanitizeString(match?.status).toLowerCase();
  const settlement = sanitizeString(match?.settlement?.status).toLowerCase();
  return status === 'cancelled' || settlement === 'refunded' || settlement === 'cancelled';
}

function startSecondsOf(match) {
  const seconds = Number(match?.startTime);
  return Number.isFinite(seconds) && seconds > 0 ? seconds : null;
}

function prizeOf(match) {
  const prize = Number(match?.prizeAmount);
  if (Number.isFinite(prize) && prize > 0) return prize;
  const parsed = Number(String(match?.prize || '').replace(/[^0-9.-]/g, ''));
  return Number.isFinite(parsed) ? parsed : 0;
}

/**
 * Computes both halves of the admin tab from one pass over the data.
 *
 * Returning the summary and the timeseries together is deliberate: they used to
 * be computed by two functions with two different notions of "the range", which
 * is how the same page could disagree with itself.
 */
export function computeAnalyticsReport({
  events = [],
  users = {},
  matches = {},
  rewards = {},
  start,
  end,
  now = Date.now()
} = {}) {
  const nowDate = new Date(now);
  const range = toRangeDates(start, end, nowDate.getTime());
  const startIso = range.start.toISOString();
  const endIso = range.end.toISOString();
  const startMs = range.start.getTime();
  const endMs = range.end.getTime();
  const days = buildDayList(startIso, endIso);
  const startDay = days[0];
  const endDay = days[days.length - 1];
  const daySet = new Set(days);

  const inRangeTime = (t) => t !== null && t >= startMs && t <= endMs;
  const inRangeDay = (day) => !!day && daySet.has(day);

  const list = Array.isArray(events) ? events.filter((event) => event && typeof event === 'object') : [];
  const directory = buildDirectory(users);

  // ---- Activity -----------------------------------------------------------
  // One pass builds: who was seen, when they were first seen, which days each
  // person was active, and which people were active on each day.
  const firstSeen = new Map();
  const activityDaysOfUser = emptySets();
  const activeUsersOnDay = new Map();

  for (const event of list) {
    const person = directory.keyOf(event);
    if (!person) continue;
    const t = timeOf(event.timestamp);
    if (t === null) continue;
    const iso = new Date(t).toISOString();
    const day = iso.slice(0, 10);

    const known = firstSeen.get(person);
    if (!known || t < timeOf(known)) firstSeen.set(person, iso);

    if (ACTIVE_EVENT_TYPES.includes(event.event_type)) {
      addToSetMap(activityDaysOfUser, person, day);
      addToSetMap(activeUsersOnDay, day, person);
    }
  }

  const activeOn = (day) => activeUsersOnDay.get(day) || new Set();
  const lastDay = days[days.length - 1];
  const previousDay = days.length > 1 ? days[days.length - 2] : null;

  // Everyone the system knows about: the roster plus anyone only ever seen in
  // an event. Accounts with no first-seen day are counted as "before the range"
  // rather than dropped from the cumulative curve.
  const universe = new Set([...directory.accounts, ...firstSeen.keys()]);
  const firstDayOf = new Map();
  for (const person of universe) {
    const first = firstSeen.get(person);
    firstDayOf.set(person, first ? first.slice(0, 10) : null);
  }
  const firstDayCounts = new Map();
  for (const day of firstDayOf.values()) {
    if (day) firstDayCounts.set(day, (firstDayCounts.get(day) || 0) + 1);
  }

  const totalUsers = universe.size;
  const activeUsersInRange = unionOfDays(activeUsersOnDay, days);
  const newUsersInRange = days.reduce((sum, day) => sum + (firstDayCounts.get(day) || 0), 0);
  const returningUsers = [...activeUsersInRange].filter((person) => {
    const first = firstDayOf.get(person);
    return !first || first < startDay;
  }).length;

  const last7 = days.slice(-7);
  const previous7 = days.slice(-14, -7);
  const last30 = days.slice(-30);
  const wau = unionOfDays(activeUsersOnDay, last7).size;
  const mau = unionOfDays(activeUsersOnDay, last30).size;
  const previousWau = unionOfDays(activeUsersOnDay, previous7).size;

  const dau = activeOn(lastDay).size;
  const previousDau = previousDay ? activeOn(previousDay).size : 0;
  const newUsersPerDay = firstDayCounts.get(lastDay) || 0;

  // ---- Matches (records are the truth, not events) ------------------------
  const matchList = Object.values(matches || {}).filter((match) => match && typeof match === 'object');
  const createdInRange = matchList.filter((match) => inRangeDay(dayOf(match.createdAt)));
  const startedInRange = matchList.filter((match) => {
    const seconds = startSecondsOf(match);
    return seconds !== null && inRangeTime(seconds * 1000);
  });
  const playedInRange = startedInRange.filter(isPlayedMatch);

  const nowSeconds = nowDate.getTime() / 1000;
  const matchesCurrentlyActive = matchList.filter((match) => {
    const seconds = startSecondsOf(match);
    if (seconds === null || isCancelledMatch(match) || isPlayedMatch(match)) return false;
    const status = sanitizeString(match.status).toLowerCase();
    if (status === 'settled') return false;
    return nowSeconds >= seconds && nowSeconds < seconds + MATCH_LIVE_WINDOW_SECONDS;
  }).length;

  const matchesCreatedOnLastDay = createdInRange.filter(
    (match) => dayOf(match.createdAt) === lastDay
  ).length;

  const matchCompletionRate = startedInRange.length
    ? (playedInRange.length / startedInRange.length) * 100
    : 0;

  // ---- Sessions -----------------------------------------------------------
  const sessionStartedAt = new Map();
  const sessionDurations = [];
  for (const event of list) {
    const sessionId = sanitizeString(event?.metadata?.session_id);
    if (!sessionId) continue;
    if (event.event_type === 'session_started') {
      const t = timeOf(event.timestamp);
      if (t !== null && inRangeTime(t)) sessionStartedAt.set(sessionId, t);
    } else if (event.event_type === 'session_ended') {
      const started = sessionStartedAt.get(sessionId);
      const ended = timeOf(event.timestamp);
      if (started !== undefined && ended !== null && ended >= started) {
        sessionDurations.push((ended - started) / 1000);
        sessionStartedAt.delete(sessionId);
      }
    }
  }
  const averageSessionDuration = sessionDurations.length
    ? sessionDurations.reduce((sum, value) => sum + value, 0) / sessionDurations.length
    : 0;

  // ---- Participation (joins, training lobby excluded) ---------------------
  const joinPairs = new Map(); // matchId -> Set(identity)
  for (const event of list) {
    if (event.event_type !== 'match_joined') continue;
    if (isTrainingLobby(event.match_id, event.sponsor_id)) continue;
    const t = timeOf(event.timestamp);
    if (!inRangeTime(t)) continue;
    const person = directory.keyOf(event);
    const matchId = sanitizeString(event.match_id);
    if (!person || !matchId) continue;
    addToSetMap(joinPairs, matchId, person);
  }
  const joinedMatches = [...joinPairs.values()].filter((players) => players.size > 0);
  const averagePlayersPerMatch = joinedMatches.length
    ? joinedMatches.reduce((sum, players) => sum + players.size, 0) / joinedMatches.length
    : 0;
  const joinedPeople = new Set();
  for (const players of joinedMatches) for (const person of players) joinedPeople.add(person);
  const matchesPerUser = joinedPeople.size ? joinedMatches.length / joinedPeople.size : 0;
  const gamesPlayedPerUser = activeUsersInRange.size
    ? playedInRange.length / activeUsersInRange.size
    : 0;

  // ---- Money (the rewards ledger, not the event stream) -------------------
  const rewardRows = Object.values(rewards || {}).filter((row) => row && typeof row === 'object');
  const rewardsByDay = new Map();
  let paidInRange = 0;
  let pendingInRange = 0;
  const winners = new Map();

  for (const row of rewardRows) {
    const day = dayOf(row.createdAt || row.timestamp);
    if (!inRangeDay(day)) continue;
    const amount = rewardAmountMon(row);
    if (row.pending === true) {
      pendingInRange += amount;
    } else {
      paidInRange += amount;
      const winner = sanitizeString(row.username) || sanitizeString(row.user_id) || 'unknown';
      winners.set(winner, (winners.get(winner) || 0) + amount);
    }
    rewardsByDay.set(day, (rewardsByDay.get(day) || 0) + (row.pending === true ? 0 : amount));
  }

  const topWinningPlayers = [...winners.entries()]
    .map(([user_id, total]) => ({ user_id, total: round6(total) }))
    .sort((a, b) => b.total - a.total)
    .slice(0, 5);

  const rewardedMatches = new Set();
  for (const row of rewardRows) {
    const day = dayOf(row.createdAt || row.timestamp);
    if (inRangeDay(day) && row.pending !== true && sanitizeString(row.matchId)) {
      rewardedMatches.add(sanitizeString(row.matchId));
    }
  }
  const averageRewardPerMatch = rewardedMatches.size ? paidInRange / rewardedMatches.size : 0;

  const prizeVolumeInRange = createdInRange.reduce((sum, match) => sum + prizeOf(match), 0);
  const rewardsOnLastDay = rewardsByDay.get(lastDay) || 0;

  // "Reward volume" is the money that was on the table; "rewards distributed"
  // is the money that actually reached players. They used to be the same card.
  const totalRewardVolume = prizeVolumeInRange;

  // ---- Sponsors -----------------------------------------------------------
  const sponsorFirstDay = new Map();
  const noteSponsor = (sponsor, day) => {
    const name = sanitizeString(sponsor);
    if (!name || NOT_A_SPONSOR.has(name.toLowerCase())) return;
    const current = sponsorFirstDay.get(name);
    if (!current || (day && day < current)) sponsorFirstDay.set(name, day || startDay);
  };
  for (const match of matchList) noteSponsor(match.sponsor, dayOf(match.createdAt));
  for (const event of list) {
    if (event.event_type !== 'sponsor_added') continue;
    noteSponsor(event.sponsor_id, dayOf(event.timestamp));
  }

  const totalSponsors = sponsorFirstDay.size;
  const sponsorsInRange = new Set();
  for (const match of createdInRange) {
    const name = sanitizeString(match.sponsor);
    if (name && !NOT_A_SPONSOR.has(name.toLowerCase())) sponsorsInRange.add(name);
  }
  for (const [name, day] of sponsorFirstDay) if (inRangeDay(day)) sponsorsInRange.add(name);

  const sponsorFundingVolume = prizeVolumeInRange;
  const averageSponsorValue = sponsorsInRange.size ? sponsorFundingVolume / sponsorsInRange.size : 0;

  // ---- Retention ----------------------------------------------------------
  // Cohorts are first-seen days and activity is any active event, both from the
  // full history: a day-30 rate needs cohorts from a month before the range.
  const endDayMs = Date.parse(`${endDay}T00:00:00Z`);
  const retention = { day1: 0, day7: 0, day30: 0 };
  const eligible = { day1: 0, day7: 0, day30: 0 };
  for (const person of universe) {
    const day = firstDayOf.get(person);
    if (!day) continue;
    const cohortMs = Date.parse(`${day}T00:00:00Z`);
    const activeDays = activityDaysOfUser.get(person) || new Set();
    for (const offset of [1, 7, 30]) {
      const targetMs = cohortMs + offset * DAY_MS;
      if (targetMs > endDayMs) continue;
      const targetDay = new Date(targetMs).toISOString().slice(0, 10);
      eligible[`day${offset}`] += 1;
      if (activeDays.has(targetDay)) retention[`day${offset}`] += 1;
    }
  }
  const retentionPct = {
    day1: eligible.day1 ? (retention.day1 / eligible.day1) * 100 : 0,
    day7: eligible.day7 ? (retention.day7 / eligible.day7) * 100 : 0,
    day30: eligible.day30 ? (retention.day30 / eligible.day30) * 100 : 0
  };

  // ---- Series -------------------------------------------------------------
  const matchesByDay = new Map();
  for (const match of createdInRange) {
    const day = dayOf(match.createdAt);
    matchesByDay.set(day, (matchesByDay.get(day) || 0) + 1);
  }

  const joinsByDay = new Map();
  for (const event of list) {
    if (event.event_type !== 'match_joined') continue;
    if (isTrainingLobby(event.match_id, event.sponsor_id)) continue;
    const day = dayOf(event.timestamp);
    if (!inRangeDay(day)) continue;
    const person = directory.keyOf(event);
    const matchId = sanitizeString(event.match_id);
    if (!person || !matchId) continue;
    if (!joinsByDay.has(day)) joinsByDay.set(day, new Set());
    joinsByDay.get(day).add(`${matchId}|${person}`);
  }

  const dailyActiveUsers = days.map((day) => ({ date: day, value: activeOn(day).size }));

  // Cumulative figures are seeded from everything that happened before the
  // range, so the curve does not restart at zero when the range moves.
  let runningUsers = 0;
  for (const person of universe) {
    const day = firstDayOf.get(person);
    if (!day || day < startDay) runningUsers += 1;
  }
  const userGrowth = days.map((day) => {
    runningUsers += firstDayCounts.get(day) || 0;
    return { date: day, value: runningUsers };
  });

  let runningSponsors = 0;
  for (const day of sponsorFirstDay.values()) if (!day || day < startDay) runningSponsors += 1;
  const sponsorGrowth = days.map((day) => {
    for (const day2 of sponsorFirstDay.values()) if (day2 === day) runningSponsors += 1;
    return { date: day, value: runningSponsors };
  });

  const matchesPerUserSeries = days.map((day) => {
    const usersToday = activeOn(day).size;
    const joinsToday = joinsByDay.get(day)?.size || 0;
    return { date: day, value: usersToday ? joinsToday / usersToday : 0 };
  });

  const timeseries = {
    series: {
      dailyActiveUsers,
      userGrowth,
      matchesCreated: days.map((day) => ({ date: day, value: matchesByDay.get(day) || 0 })),
      rewardsDistributed: days.map((day) => ({ date: day, value: round6(rewardsByDay.get(day) || 0) })),
      sponsorGrowth,
      matchesPerUser: matchesPerUserSeries
    },
    retention: retentionPct
  };

  // ---- Summary ------------------------------------------------------------
  const summary = {
    range: {
      start: startIso,
      end: endIso,
      startDay,
      endDay,
      days: days.length
    },
    overview: {
      dailyActiveUsers: dau,
      totalUsers,
      matchesToday: matchesCreatedOnLastDay,
      totalRewardsDistributed: round6(paidInRange),
      totalSponsors,
      matchesInRange: createdInRange.length,
      activeUsersInRange: activeUsersInRange.size,
      pendingRewards: round6(pendingInRange)
    },
    growthMetrics: {
      dailyUserGrowthRate: computeGrowthRate(dau, previousDau),
      weeklyGrowthRate: computeGrowthRate(wau, previousWau),
      matchCreationGrowthRate: computeGrowthRate(
        days.slice(-7).reduce((sum, day) => sum + (matchesByDay.get(day) || 0), 0),
        days.slice(-14, -7).reduce((sum, day) => sum + (matchesByDay.get(day) || 0), 0)
      )
    },
    userMetrics: {
      dau,
      wau,
      mau,
      totalUsers,
      newUsersPerDay,
      uniqueUsersPerDay: dau,
      newUsersInRange,
      activeUsersInRange: activeUsersInRange.size
    },
    gameMetrics: {
      matchesCreatedPerDay: matchesCreatedOnLastDay,
      matchesCompleted: playedInRange.length,
      matchesCurrentlyActive,
      averagePlayersPerMatch,
      matchCompletionRate,
      matchesPerUser,
      matchesCreatedInRange: createdInRange.length,
      matchesPlayedInRange: playedInRange.length,
      playersTracked: joinedPeople.size
    },
    economyMetrics: {
      totalRewardsDistributed: round6(paidInRange),
      rewardsDistributedPerDay: round6(rewardsOnLastDay),
      averageRewardPerMatch: round6(averageRewardPerMatch),
      totalRewardVolume: round6(totalRewardVolume),
      pendingRewards: round6(pendingInRange),
      topWinningPlayers
    },
    sponsorMetrics: {
      totalSponsors,
      matchesSponsored: createdInRange.length,
      sponsorFundingVolume: round6(sponsorFundingVolume),
      averageSponsorValue: round6(averageSponsorValue)
    },
    engagementMetrics: {
      averageSessionDuration,
      returningUsers,
      newUsers: newUsersInRange,
      gamesPlayedPerUser,
      pairedSessions: sessionDurations.length,
      playerRetention: {
        day1: retentionPct.day1,
        day7: retentionPct.day7,
        day30: retentionPct.day30
      }
    },
    retentionMetrics: {
      day1: retentionPct.day1,
      day7: retentionPct.day7,
      day30: retentionPct.day30,
      eligibleUsers: eligible
    },
    grantMetrics: {
      dailyActiveUsers: dau,
      totalUsers,
      totalMatchesPlayed: playedInRange.length,
      totalRewardsDistributed: round6(paidInRange),
      numberOfSponsors: totalSponsors,
      averageMatchesPerUser: matchesPerUser,
      userGrowthRate: computeGrowthRate(dau, previousDau),
      matchGrowthRate: computeGrowthRate(
        days.slice(-7).reduce((sum, day) => sum + (matchesByDay.get(day) || 0), 0),
        days.slice(-14, -7).reduce((sum, day) => sum + (matchesByDay.get(day) || 0), 0)
      ),
      day7Retention: retentionPct.day7
    }
  };

  return { summary, timeseries };
}
