//! Mirrors the control plane's list of *allocated* matches.
//!
//! A room may only exist for a match a host actually created. Hosts create matches
//! through the sponsor dashboard into Firebase; the Node backend exposes that list
//! at `GET /internal/matches` (behind a shared secret), and this registry mirrors
//! it here. A `?room=<id>` that is not in the mirror never spawns its own arena: an id
//! the mirror knows is unallocated is refused, and an id it cannot judge (no data yet)
//! falls back to `default` unless `STRICT_ROOMS` is set.
//!
//! The mirror is refreshed lazily: a lookup that finds the snapshot stale (or empty)
//! re-fetches, and a lookup that misses forces one refresh so a match created a
//! moment ago is picked up on its first join. Failures keep the last good snapshot
//! rather than emptying it, so a brief control-plane outage does not evict live
//! matches.

use std::collections::HashMap;
use std::time::Duration;

use serde::Deserialize;
use tokio::sync::Mutex;

use crate::config::{
    control_plane_url, internal_secret, DEFAULT_MIN_PLAYERS_TO_START, MATCH_REGISTRY_TTL_MS,
};
use crate::protocol::now_ms;

/// Minimum spacing between control-plane fetches. Bounds how often a burst of room
/// lookups (e.g. someone probing random ids) can reach the control plane.
const MIN_REFRESH_INTERVAL_MS: i64 = 2_000;

/// How many times `warm()` fetches before giving up, sleeping 2 s, 4 s, 8 s, 16 s and
/// 32 s between attempts.
const WARM_ATTEMPTS: u32 = 5;

/// Backoff after a 429 that carries no `Retry-After`. Long enough that `warm()`'s later
/// attempts land after it rather than burning themselves against it.
const RATE_LIMIT_BACKOFF_S: u64 = 30;

/// Per-room simulation limits, taken from the match record.
#[derive(Clone, Debug)]
pub struct MatchConfig {
    pub min_players_to_start: usize,
    /// `None` means unlimited, matching Node's `currentMaxPlayers === null`.
    pub max_players: Option<usize>,
}

/// Outcome of resolving a match id against the mirror.
pub enum MatchLookup {
    /// The id is an allocated match, with its limits.
    Allocated(MatchConfig),
    /// The mirror is populated but does not contain the id: an id no host created.
    Missing,
    /// The mirror holds no data (never synced, or the control plane is unreachable),
    /// so the id cannot be judged either way.
    Unverified,
}

#[derive(Default)]
struct Snapshot {
    matches: HashMap<String, MatchConfig>,
    fetched_at_ms: i64,
    last_attempt_ms: i64,
    /// Do not contact the control plane before this. Set when it answers 429, so a
    /// throttled control plane is not hammered by every connect.
    backoff_until_ms: i64,
}

pub struct MatchRegistry {
    snapshot: Mutex<Snapshot>,
    /// Held only across a fetch so concurrent connects trigger a single request.
    refreshing: Mutex<()>,
    client: reqwest::Client,
}

#[derive(Deserialize)]
struct InternalMatchesResponse {
    #[serde(default)]
    matches: HashMap<String, RawMatchConfig>,
}

#[derive(Deserialize)]
struct RawMatchConfig {
    #[serde(rename = "minPlayersToStart", default)]
    min_players_to_start: Option<i64>,
    #[serde(rename = "maxPlayers", default)]
    max_players: Option<i64>,
}

impl MatchRegistry {
    pub fn new() -> Self {
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(5))
            .build()
            .unwrap_or_default();
        MatchRegistry {
            snapshot: Mutex::new(Snapshot::default()),
            refreshing: Mutex::new(()),
            client,
        }
    }

    /// Resolve `id`: its limits if allocated, or why it could not be confirmed.
    pub async fn lookup(&self, id: &str) -> MatchLookup {
        self.refresh_if_stale().await;
        if let Some(cfg) = self.snapshot.lock().await.matches.get(id).cloned() {
            return MatchLookup::Allocated(cfg);
        }
        // A miss may be a match created since the last sync; force one refresh.
        self.refresh(true).await;
        let snap = self.snapshot.lock().await;
        if let Some(cfg) = snap.matches.get(id) {
            return MatchLookup::Allocated(cfg.clone());
        }
        // Distinguish "we have a mirror and the id is not in it" from "we have no mirror
        // to consult": only the former is a trustworthy rejection.
        if snap.matches.is_empty() {
            MatchLookup::Unverified
        } else {
            MatchLookup::Missing
        }
    }

    /// Fetch until the mirror has data, so a match-start burst finds a warm snapshot.
    ///
    /// A cold start that misses — a sleeping control plane, or a transient throttle —
    /// would otherwise leave the mirror empty until some client asked for a non-default
    /// room, which silently routes real matches to `default`. Keep trying instead.
    pub async fn warm(&self) {
        for attempt in 0..WARM_ATTEMPTS {
            self.refresh(true).await;
            if !self.snapshot.lock().await.matches.is_empty() {
                return;
            }
            tokio::time::sleep(Duration::from_millis(2_000_u64 << attempt.min(4))).await;
        }
        tracing::warn!(
            "match registry still empty after {} warm attempts; room ids fall back to `default`",
            WARM_ATTEMPTS
        );
    }

    async fn refresh_if_stale(&self) {
        let stale = {
            let snap = self.snapshot.lock().await;
            snap.matches.is_empty() || now_ms() - snap.fetched_at_ms >= MATCH_REGISTRY_TTL_MS
        };
        if stale {
            self.refresh(false).await;
        }
    }

    async fn refresh(&self, force: bool) {
        // Serialize refreshes: a caller that arrives while a fetch is in flight waits
        // for it and then reuses the result (via the throttle below) instead of racing
        // to a second request. This is what keeps a burst of match-start connects on a
        // single snapshot, so none of them miss and fall back to `default`.
        let _guard = self.refreshing.lock().await;

        let now = now_ms();
        {
            let mut snap = self.snapshot.lock().await;
            let fresh =
                !snap.matches.is_empty() && now - snap.fetched_at_ms < MATCH_REGISTRY_TTL_MS;
            if now < snap.backoff_until_ms
                || (fresh && !force)
                || now - snap.last_attempt_ms < MIN_REFRESH_INTERVAL_MS
            {
                return;
            }
            snap.last_attempt_ms = now;
        }

        match self.fetch().await {
            Some(matches) => {
                let mut snap = self.snapshot.lock().await;
                snap.matches = matches;
                snap.fetched_at_ms = now_ms();
                tracing::info!(
                    "match registry synced: {} allocated match(es)",
                    snap.matches.len()
                );
            }
            None => {
                let mut snap = self.snapshot.lock().await;
                // Mark stale but keep the last good list so live matches survive.
                snap.fetched_at_ms = 0;
                tracing::warn!(
                    "match registry refresh failed; keeping {} cached match(es)",
                    snap.matches.len()
                );
            }
        }
    }

    async fn fetch(&self) -> Option<HashMap<String, MatchConfig>> {
        let url = format!("{}/internal/matches", control_plane_url());
        let response = match self
            .client
            .get(url.as_str())
            .header("x-internal-secret", internal_secret())
            .send()
            .await
        {
            Ok(response) => response,
            Err(err) => {
                tracing::warn!("match registry fetch failed: {}", err);
                return None;
            }
        };
        let status = response.status();
        if status == reqwest::StatusCode::TOO_MANY_REQUESTS {
            // The control plane is throttling us (a free instance under sustained
            // polling). Back off rather than hammering it: honour `Retry-After` when it
            // sends one, otherwise wait out `RATE_LIMIT_BACKOFF_S`. The last good
            // snapshot is kept throughout, so live matches stay joinable.
            let retry_after = response
                .headers()
                .get(reqwest::header::RETRY_AFTER)
                .and_then(|value| value.to_str().ok())
                .and_then(|value| value.trim().parse::<u64>().ok())
                .filter(|value| *value > 0)
                .unwrap_or(RATE_LIMIT_BACKOFF_S);
            let mut snap = self.snapshot.lock().await;
            snap.backoff_until_ms = now_ms() + (retry_after as i64) * 1_000;
            tracing::warn!(
                "match registry rate-limited; backing off {}s (keeping {} cached match(es))",
                retry_after,
                snap.matches.len()
            );
            return None;
        }
        if !status.is_success() {
            tracing::warn!("match registry fetch returned {}", status);
            return None;
        }
        let body: InternalMatchesResponse = match response.json().await {
            Ok(body) => body,
            Err(err) => {
                tracing::warn!("match registry parse failed: {}", err);
                return None;
            }
        };

        let mut out = HashMap::with_capacity(body.matches.len());
        for (id, raw) in body.matches {
            // A match that predates per-match limits (or omits them) falls back to the
            // same default Node uses, not to 0, so a room never starts on one player.
            let min = raw
                .min_players_to_start
                .filter(|v| *v > 0)
                .map(|v| v as usize)
                .unwrap_or(DEFAULT_MIN_PLAYERS_TO_START);
            let mut max = raw.max_players.filter(|v| *v > 0).map(|v| v as usize);
            // Never cap below the start threshold, mirroring Node's normalize.
            if let Some(m) = max {
                if m < min {
                    max = Some(min);
                }
            }
            out.insert(
                id,
                MatchConfig {
                    min_players_to_start: min,
                    max_players: max,
                },
            );
        }
        Some(out)
    }
}
