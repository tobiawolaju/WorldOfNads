import { db } from './firebaseClient.js';
import { ref, push, set, get } from 'firebase/database';
import { computeAnalyticsReport, toRangeDates } from './analyticsMetrics.js';

const MAX_METADATA_KEYS = 64;
const MAX_METADATA_STRING = 200;

/**
 * How long one snapshot of the four nodes may be reused.
 *
 * The admin tab loads the summary and the timeseries in two requests; without a
 * cache that downloaded `analytics/events` twice, and the events node is by far
 * the largest thing here. 30 s keeps the two half-pages consistent and still
 * means "refresh" shows new data.
 */
const SNAPSHOT_TTL_MS = 30_000;

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
  // `push()` only reserves a key; without this `set()` the event was written at
  // a *different* generated key and the returned id was wrong.
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

  await set(newEventRef, eventData);

  invalidateAnalyticsSnapshot();
  return { ok: true, id: newEventRef.key, timestamp: timestamp };
}

let snapshotCache = null;
let snapshotFetchedAt = 0;

function invalidateAnalyticsSnapshot() {
  snapshotCache = null;
  snapshotFetchedAt = 0;
}

async function readNode(path) {
  const snapshot = await get(ref(db, path));
  return snapshot.exists() ? snapshot.val() : null;
}

/**
 * One read of every node the metrics need.
 *
 * Earlier versions queried `analytics/events` about eight times per request
 * (once per metric group) and scanned the whole node three more times, so a
 * single page load could download several megabytes and still disagree with
 * itself if an event landed between two queries.
 */
async function loadSnapshot(now = Date.now()) {
  if (snapshotCache && now - snapshotFetchedAt < SNAPSHOT_TTL_MS) {
    return snapshotCache;
  }

  const [eventsNode, users, matches, rewards] = await Promise.all([
    readNode('analytics/events'),
    readNode('users'),
    readNode('matches'),
    readNode('rewards')
  ]);

  snapshotCache = {
    // Keep the push key: it is the only stable id an event has, and the CSV
    // export used to drop it even though it was in the header row.
    events: eventsNode
      ? Object.entries(eventsNode).map(([id, event]) => ({ ...event, id }))
      : [],
    users: users || {},
    matches: matches || {},
    rewards: rewards || {}
  };
  snapshotFetchedAt = now;
  return snapshotCache;
}

async function buildReport({ start, end, now = Date.now() } = {}) {
  const snapshot = await loadSnapshot(now);
  return computeAnalyticsReport({ ...snapshot, start, end, now });
}

export async function getAnalyticsSummary({ start, end } = {}) {
  const report = await buildReport({ start, end });
  return report.summary;
}

export async function getAnalyticsTimeseries({ start, end } = {}) {
  const report = await buildReport({ start, end });
  return report.timeseries;
}

export async function exportAnalyticsEvents({ start, end, format }) {
  const { start: startDate, end: endDate } = toRangeDates(start, end);
  const startIso = startDate.toISOString();
  const endIso = endDate.toISOString();
  const snapshot = await loadSnapshot();

  const rows = snapshot.events
    .filter((event) => {
      const t = Date.parse(event?.timestamp);
      return Number.isFinite(t) && t >= Date.parse(startIso) && t <= Date.parse(endIso);
    })
    .sort((a, b) => String(a.timestamp).localeCompare(String(b.timestamp)));

  if (format === 'csv') {
    const headers = ['id', 'event_type', 'user_id', 'match_id', 'sponsor_id', 'value', 'metadata', 'timestamp'];
    const lines = [headers.join(',')];
    for (const row of rows) {
      const values = headers.map((key) => {
        const value = key === 'id' ? row.id ?? '' : row[key] ?? '';
        const str = typeof value === 'string' ? value.replace(/"/g, '""') : JSON.stringify(value);
        return `"${str}"`;
      });
      lines.push(values.join(','));
    }
    return { contentType: 'text/csv', body: lines.join('\n') };
  }

  return { contentType: 'application/json', body: JSON.stringify({ events: rows }) };
}
