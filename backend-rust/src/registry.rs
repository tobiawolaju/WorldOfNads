//! Mirrors the control plane's list of *allocated* matches.
//!
//! A room may only exist for a match a host actually created. Hosts create matches
//! through the sponsor dashboard into Firebase; the Node backend exposes that list
//! at `GET /internal/matches` (behind a shared secret), and this registry mirrors
//! it here. A `?room=<id>` that is not in the mirror never spawns its own arena —
//! it either lands in the shared `default` room or is rejected (see `STRICT_ROOMS`).
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

use crate::config::{control_plane_url, internal_secret, MATCH_REGISTRY_TTL_MS};
use crate::protocol::now_ms;

/// Minimum spacing between control-plane fetches. Bounds how often a burst of room
/// lookups (e.g. someone probing random ids) can reach the control plane.
const MIN_REFRESH_INTERVAL_MS: i64 = 2_000;

/// Per-room simulation limits, taken from the match record.
#[derive(Clone, Debug)]
pub struct MatchConfig {
    pub min_players_to_start: usize,
    /// `None` means unlimited, matching Node's `currentMaxPlayers === null`.
    pub max_players: Option<usize>,
}

#[derive(Default)]
struct Snapshot {
    matches: HashMap<String, MatchConfig>,
    fetched_at_ms: i64,
    last_attempt_ms: i64,
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

    /// Config for `id`, or `None` if it is not an allocated match.
    pub async fn lookup(&self, id: &str) -> Option<MatchConfig> {
        self.refresh_if_stale().await;
        if let Some(cfg) = self.snapshot.lock().await.matches.get(id).cloned() {
            return Some(cfg);
        }
        // A miss may be a match created since the last sync; force one refresh.
        self.refresh(true).await;
        self.snapshot.lock().await.matches.get(id).cloned()
    }

    /// Fetch once now (deduplicated), so a match-start burst finds a warm snapshot.
    pub async fn warm(&self) {
        self.refresh(true).await;
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
            if (fresh && !force) || now - snap.last_attempt_ms < MIN_REFRESH_INTERVAL_MS {
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
        if !response.status().is_success() {
            tracing::warn!("match registry fetch returned {}", response.status());
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
            let min = raw.min_players_to_start.unwrap_or(0).max(0) as usize;
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
