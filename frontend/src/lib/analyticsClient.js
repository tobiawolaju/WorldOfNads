const API_BASE = import.meta.env.VITE_ANALYTICS_API_URL || "";

const sessionId = `session-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;

function buildUrl(path) {
  if (!API_BASE) return path;
  return `${API_BASE}${path}`;
}

function sendEvent(payload, useBeacon = false) {
  const body = JSON.stringify(payload);

  if (useBeacon && navigator?.sendBeacon) {
    const blob = new Blob([body], { type: "application/json" });
    return navigator.sendBeacon(buildUrl("/analytics/events"), blob);
  }

  fetch(buildUrl("/analytics/events"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body,
    keepalive: useBeacon
  }).catch(() => {});
  return true;
}

export function trackEvent(payload) {
  if (!payload || !payload.eventType) return;
  sendEvent({
    event_type: payload.eventType,
    user_id: payload.userId,
    match_id: payload.matchId,
    sponsor_id: payload.sponsorId,
    value: payload.value,
    metadata: payload.metadata
  });
}

export function trackSessionStarted({ userId, metadata } = {}) {
  trackEvent({
    eventType: "session_started",
    userId,
    metadata: { session_id: sessionId, ...metadata }
  });
}

export function trackSessionEnded({ userId, metadata } = {}) {
  sendEvent({
    event_type: "session_ended",
    user_id: userId,
    metadata: { session_id: sessionId, ...metadata }
  }, true);
}

export function trackUserRegistered({ userId, metadata } = {}) {
  trackEvent({
    eventType: "user_registered",
    userId,
    metadata
  });
}

export function trackUserJoined({ userId, metadata } = {}) {
  trackEvent({
    eventType: "user_joined",
    userId,
    metadata
  });
}

export function trackMatchCreated({ userId, matchId, sponsorId, value, metadata } = {}) {
  trackEvent({
    eventType: "match_created",
    userId,
    matchId,
    sponsorId,
    value,
    metadata
  });
}

export function trackMatchJoined({ userId, matchId, sponsorId, metadata } = {}) {
  trackEvent({
    eventType: "match_joined",
    userId,
    matchId,
    sponsorId,
    metadata
  });
}

export function trackSponsorAdded({ sponsorId, value, metadata } = {}) {
  trackEvent({
    eventType: "sponsor_added",
    sponsorId,
    value,
    metadata
  });
}

export function trackSponsorMatchCreated({ userId, matchId, sponsorId, value, metadata } = {}) {
  trackEvent({
    eventType: "sponsor_match_created",
    userId,
    matchId,
    sponsorId,
    value,
    metadata
  });
}

export function getAnalyticsSessionId() {
  return sessionId;
}
