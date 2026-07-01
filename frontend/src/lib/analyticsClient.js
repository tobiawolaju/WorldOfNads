const API_BASE = import.meta.env.VITE_ANALYTICS_API_URL || "";
const GA_MEASUREMENT_ID = import.meta.env.VITE_GA_MEASUREMENT_ID || "";
const ENABLE_GA = false;

const sessionId = `session-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
let gaInitialized = false;

function buildUrl(path) {
  if (!API_BASE) return path;
  return `${API_BASE}${path}`;
}

function safeStringify(value, maxLength = 500) {
  try {
    const serialized = JSON.stringify(value);
    if (typeof serialized !== "string") return "";
    return serialized.length > maxLength ? `${serialized.slice(0, maxLength)}...` : serialized;
  } catch (error) {
    return "";
  }
}

function pruneEmpty(values) {
  return Object.fromEntries(
    Object.entries(values).filter(([, value]) => value !== undefined && value !== null && value !== "")
  );
}

function sendToGoogleAnalytics(payload) {
  if (!gaInitialized || typeof window === "undefined" || typeof window.gtag !== "function") return;

  const metadata = payload?.metadata || {};
  const params = pruneEmpty({
    user_id: payload.user_id,
    match_id: payload.match_id,
    sponsor_id: payload.sponsor_id,
    value: payload.value,
    session_id: metadata.session_id,
    username: metadata.username,
    metadata: Object.keys(metadata).length ? safeStringify(metadata) : undefined
  });

  window.gtag("event", payload.event_type, params);
}

export function initGoogleAnalytics() {
  if (!ENABLE_GA || !GA_MEASUREMENT_ID || gaInitialized || typeof window === "undefined") return false;

  if (!window.dataLayer) {
    window.dataLayer = [];
  }
  if (typeof window.gtag !== "function") {
    window.gtag = function gtag() {
      window.dataLayer.push(arguments);
    };
  }

  window.gtag("js", new Date());
  window.gtag("config", GA_MEASUREMENT_ID, {
    send_page_view: false
  });

  if (!document.querySelector(`script[src*="googletagmanager.com/gtag/js?id=${GA_MEASUREMENT_ID}"]`)) {
    const script = document.createElement("script");
    script.async = true;
    script.src = `https://www.googletagmanager.com/gtag/js?id=${GA_MEASUREMENT_ID}`;
    document.head.appendChild(script);
  }

  gaInitialized = true;
  return true;
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

  sendToGoogleAnalytics(payload);
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
