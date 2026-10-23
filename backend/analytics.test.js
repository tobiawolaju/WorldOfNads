// Tests for the admin analytics maths. No Firebase, no ethers, no network:
// `analyticsMetrics.js` takes the four nodes as plain objects, which is the
// whole reason it is a separate module.
//
// Run with: node --test backend/analytics.test.js

import test from 'node:test';
import assert from 'node:assert/strict';

import { computeAnalyticsReport, buildDayList, toRangeDates } from './analyticsMetrics.js';

const NOW = Date.parse('2026-10-20T12:00:00.000Z');

function report(options = {}) {
  return computeAnalyticsReport({
    events: [],
    users: {},
    matches: {},
    rewards: {},
    start: '2026-10-01',
    end: '2026-10-20',
    now: NOW,
    ...options
  });
}

function match(overrides = {}) {
  return {
    matchId: 'match-a',
    status: 'completed',
    sponsor: 'Alice',
    prizeAmount: 5,
    createdAt: '2026-10-05T10:00:00.000Z',
    startTime: Math.floor(Date.parse('2026-10-05T10:00:00.000Z') / 1000),
    ...overrides
  };
}

function event(overrides = {}) {
  return {
    event_type: 'session_started',
    user_id: 'did:privy:a',
    timestamp: '2026-10-05T10:00:00.000Z',
    metadata: { username: 'alice' },
    ...overrides
  };
}

test('the range scopes money and matches, which used to be all-time', () => {
  const { summary } = report({
    matches: {
      old: match({
        matchId: 'match-old',
        createdAt: '2026-09-01T10:00:00.000Z',
        startTime: Math.floor(Date.parse('2026-09-01T10:00:00.000Z') / 1000)
      }),
      recent: match({ matchId: 'match-recent' })
    },
    rewards: {
      old: { matchId: 'match-old', amountMon: 2, createdAt: '2026-09-15T10:00:00.000Z', username: 'alice' },
      recent: { matchId: 'match-recent', amountMon: 3, createdAt: '2026-10-06T10:00:00.000Z', username: 'bob' }
    }
  });

  assert.equal(summary.economyMetrics.totalRewardsDistributed, 3, 'only the in-range reward');
  assert.equal(summary.overview.totalRewardsDistributed, 3);
  assert.equal(summary.gameMetrics.matchesCreatedInRange, 1);
  assert.equal(summary.gameMetrics.matchesCompleted, 1, 'only the match that started in range');
  assert.equal(summary.economyMetrics.totalRewardVolume, 5, 'the prize escrowed in range');
  assert.deepEqual(summary.economyMetrics.topWinningPlayers, [{ user_id: 'bob', total: 3 }]);
});

test('one person with several profile records counts once', () => {
  const { summary } = report({
    users: {
      alice: { username: 'alice', privyId: 'did:privy:a', wallet: '0xAbC0000000000000000000000000000000000001' },
      '0xAbC0000000000000000000000000000000000001': {
        username: '0xAbC0000000000000000000000000000000000001',
        privyId: 'did:privy:a',
        wallet: '0xAbC0000000000000000000000000000000000001'
      },
      Anon: { username: 'Anon', privyId: 'did:privy:a' }
    },
    events: [event({ timestamp: '2026-10-20T09:00:00.000Z' })]
  });

  assert.equal(summary.overview.totalUsers, 1, 'privyId is the identity');
  assert.equal(summary.userMetrics.dau, 1);
  assert.equal(summary.userMetrics.activeUsersInRange, 1);
});

test('a person only ever seen in events still counts, by username', () => {
  const { summary } = report({
    events: [
      event({ user_id: 'did:privy:ghost', metadata: { username: 'Ghost' }, timestamp: '2026-10-20T09:00:00.000Z' }),
      event({ user_id: 'did:privy:ghost', metadata: { username: 'Ghost' }, timestamp: '2026-10-20T10:00:00.000Z' })
    ]
  });

  assert.equal(summary.overview.totalUsers, 1);
  assert.equal(summary.userMetrics.dau, 1);
});

test('training-lobby joins are not matches played with other people', () => {
  const users = {
    alice: { username: 'alice', privyId: 'did:privy:a' },
    bob: { username: 'bob', privyId: 'did:privy:b' }
  };
  const joins = [
    event({ event_type: 'match_joined', match_id: 'match-a', sponsor_id: 'Alice' }),
    event({ event_type: 'match_joined', match_id: 'match-a', sponsor_id: 'Alice', user_id: 'did:privy:b', metadata: { username: 'bob' } }),
    event({ event_type: 'match_joined', match_id: 'match-a', sponsor_id: 'Alice' }), // same person twice
    ...Array.from({ length: 40 }, () =>
      event({ event_type: 'match_joined', match_id: 'match-training-lobby', sponsor_id: 'Training Lobby' })
    )
  ];

  const { summary } = report({ users, matches: { a: match() }, events: joins });

  assert.equal(summary.gameMetrics.averagePlayersPerMatch, 2, 'two distinct people on the real match');
  assert.equal(summary.gameMetrics.playersTracked, 2);
  assert.equal(summary.gameMetrics.matchesPerUser, 0.5, 'one match between two players');
});

test('a match is live because the clock says so, not because a stale record says live', () => {
  const nowSeconds = NOW / 1000;
  const { summary } = report({
    matches: {
      stale: match({ matchId: 'match-stale', status: 'live', startTime: nowSeconds - 7200 }),
      starting: match({ matchId: 'match-starting', status: 'upcoming', startTime: nowSeconds - 60 }),
      later: match({ matchId: 'match-later', status: 'upcoming', startTime: nowSeconds + 600 })
    }
  });

  assert.equal(summary.gameMetrics.matchesCurrentlyActive, 1, 'only the round inside its window');
});

test('sponsor growth carries sponsors from before the range instead of restarting at zero', () => {
  const { summary, timeseries } = report({
    start: '2026-10-01',
    end: '2026-10-05',
    matches: {
      old: match({
        matchId: 'match-old',
        sponsor: 'Alice',
        createdAt: '2026-09-01T10:00:00.000Z',
        startTime: Math.floor(Date.parse('2026-09-01T10:00:00.000Z') / 1000)
      }),
      recent: match({ matchId: 'match-recent', sponsor: 'Bob', createdAt: '2026-10-03T10:00:00.000Z' })
    }
  });

  assert.deepEqual(
    timeseries.series.sponsorGrowth.map((point) => point.value),
    [1, 1, 2, 2, 2],
    'Alice before the range, Bob added on the 3rd'
  );
  assert.equal(summary.sponsorMetrics.totalSponsors, 2);
  assert.equal(summary.sponsorMetrics.matchesSponsored, 1);
  assert.equal(summary.sponsorMetrics.sponsorFundingVolume, 5);
  assert.equal(summary.sponsorMetrics.averageSponsorValue, 5);
});

test('new means first seen, and returning means active but not new', () => {
  const { summary } = report({
    users: {
      old: { username: 'old', privyId: 'did:privy:old' },
      fresh: { username: 'fresh', privyId: 'did:privy:fresh' }
    },
    events: [
      event({ user_id: 'did:privy:old', metadata: { username: 'old' }, timestamp: '2026-09-20T09:00:00.000Z' }),
      event({ user_id: 'did:privy:old', metadata: { username: 'old' }, timestamp: '2026-10-02T09:00:00.000Z' }),
      event({ user_id: 'did:privy:old', metadata: { username: 'old' }, timestamp: '2026-10-20T09:00:00.000Z' }),
      event({ user_id: 'did:privy:fresh', metadata: { username: 'fresh' }, timestamp: '2026-10-03T09:00:00.000Z' })
    ]
  });

  assert.equal(summary.userMetrics.newUsersInRange, 1);
  assert.equal(summary.engagementMetrics.newUsers, 1);
  assert.equal(summary.engagementMetrics.returningUsers, 1);
  assert.equal(summary.userMetrics.newUsersPerDay, 0, 'nobody first appeared on the end day');
  assert.equal(summary.userMetrics.dau, 1);
});

test('sessions are paired on their id and averaged in seconds', () => {
  const { summary } = report({
    events: [
      event({ timestamp: '2026-10-05T10:00:00.000Z', metadata: { username: 'alice', session_id: 's1' } }),
      event({ event_type: 'session_ended', timestamp: '2026-10-05T10:05:00.000Z', metadata: { username: 'alice', session_id: 's1' } }),
      event({ timestamp: '2026-10-05T11:00:00.000Z', metadata: { username: 'alice', session_id: 's2' } })
    ]
  });

  assert.equal(summary.engagementMetrics.averageSessionDuration, 300);
});

test('retention only counts cohorts old enough to have reached the day', () => {
  const { summary, timeseries } = report({
    users: { alice: { username: 'alice', privyId: 'did:privy:a' } },
    events: [
      event({ timestamp: '2026-10-01T09:00:00.000Z' }),
      event({ timestamp: '2026-10-02T09:00:00.000Z' })
    ],
    start: '2026-10-01',
    end: '2026-10-10'
  });

  assert.equal(summary.retentionMetrics.day1, 100);
  assert.equal(summary.retentionMetrics.eligibleUsers.day1, 1);
  assert.equal(summary.retentionMetrics.day7, 0, 'eligible, but not active on day 7');
  assert.equal(summary.retentionMetrics.eligibleUsers.day7, 1);
  assert.equal(summary.retentionMetrics.eligibleUsers.day30, 0, 'the cohort cannot reach day 30 yet');
  assert.equal(timeseries.retention.day1, 100);
});

test('a reward written as a display string is still money', () => {
  const { summary } = report({
    rewards: { row: { amount: '3.6000 MON', createdAt: '2026-10-06T10:00:00.000Z', username: 'alice', matchId: 'match-a' } }
  });

  assert.equal(summary.economyMetrics.totalRewardsDistributed, 3.6);
  assert.equal(summary.economyMetrics.averageRewardPerMatch, 3.6);
});

test('pending rewards are reported apart from paid ones', () => {
  const { summary } = report({
    rewards: {
      paid: { amountMon: 1, createdAt: '2026-10-06T10:00:00.000Z', username: 'alice', matchId: 'match-a' },
      pending: { amountMon: 2, pending: true, createdAt: '2026-10-06T11:00:00.000Z', username: 'bob', matchId: 'match-b' }
    }
  });

  assert.equal(summary.economyMetrics.totalRewardsDistributed, 1);
  assert.equal(summary.overview.pendingRewards, 2);
  assert.deepEqual(summary.economyMetrics.topWinningPlayers, [{ user_id: 'alice', total: 1 }]);
});

test('the summary and the charts describe the same days', () => {
  const { summary, timeseries } = report({
    events: [event({ timestamp: '2026-10-20T09:00:00.000Z' })],
    users: { alice: { username: 'alice', privyId: 'did:privy:a' } }
  });

  const series = timeseries.series;
  assert.equal(series.dailyActiveUsers.length, summary.range.days);
  assert.equal(series.userGrowth.at(-1).value, summary.overview.totalUsers);
  assert.equal(series.dailyActiveUsers.at(-1).value, summary.overview.dailyActiveUsers);
  assert.equal(series.matchesCreated.length, series.rewardsDistributed.length);
});

test('an empty database produces zeros, never NaN', () => {
  const { summary, timeseries } = report();

  assert.equal(summary.overview.totalUsers, 0);
  assert.equal(summary.gameMetrics.averagePlayersPerMatch, 0);
  assert.equal(summary.economyMetrics.averageRewardPerMatch, 0);
  assert.equal(summary.sponsorMetrics.averageSponsorValue, 0);
  assert.equal(timeseries.series.userGrowth.at(-1).value, 0);
  assert.equal(timeseries.series.dailyActiveUsers.at(-1).value, 0);
  assert.equal(timeseries.retention.day1, 0);

  const numbers = JSON.stringify({ summary, timeseries });
  assert.ok(!numbers.includes('null'), 'a missing value must be 0, not null');
});

test('the range defaults to the last 30 days and survives a start after the end', () => {
  const days = buildDayList('2026-10-01T00:00:00.000Z', '2026-10-03T23:59:59.999Z');
  assert.deepEqual(days, ['2026-10-01', '2026-10-02', '2026-10-03']);

  const swapped = toRangeDates('2026-10-10', '2026-10-01', NOW);
  assert.equal(swapped.start.toISOString(), '2026-10-01T23:59:59.999Z');
  assert.equal(swapped.end.toISOString(), '2026-10-10T00:00:00.000Z');

  const { summary } = report({ start: undefined, end: undefined });
  assert.equal(summary.range.endDay, '2026-10-20');
  assert.equal(summary.range.startDay, '2026-09-20');

  const withHistory = report({
    events: [event({ timestamp: '2026-10-03T09:00:00.000Z' })],
    matches: { a: match({ createdAt: '2026-06-01T10:00:00.000Z' }) }
  });
  assert.equal(withHistory.summary.range.dataStartDay, '2026-06-01', 'the "all time" button needs the first day there is data');
});
