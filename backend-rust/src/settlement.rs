//! Reports a finished round to the control plane.
//!
//! The room server owns the simulation; the control plane owns the ledger:
//! Firebase holds the match record, the on-chain escrow holds the prize. When a
//! round ends, the room posts the outcome to the control plane, which writes the
//! result, credits the players and - for a round with a single winner - settles
//! the prize on-chain.
//!
//! The report is deliberately *not* awaited by the tick: a round end must never
//! stall the simulation, so the result is handed to an in-process outbox that
//! retries it until the control plane accepts it. A result is only ever dropped
//! when the control plane rejects it permanently (a 4xx: a malformed payload or a
//! wrong `INTERNAL_SECRET`), and then the full payload is written to
//! `/debug/logs` so the round can still be re-posted by hand.
//!
//! The backlog is in memory only, so a redeploy or a crash of this process still
//! loses whatever is queued. What it does buy is the far more common failure: the
//! control plane sleeping, restarting or redeploying for a few minutes while this
//! process keeps running.

use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::OnceLock;
use std::time::Duration;

use serde::Serialize;
use tokio::sync::mpsc;

use crate::config::{control_plane_url, internal_secret};
use crate::logs;

/// Timeout of a single report request.
const REPORT_TIMEOUT_S: u64 = 10;
/// Pause before the first retry of a report the control plane could not take.
/// Doubles per round up to [`OUTBOX_MAX_DELAY_S`].
const OUTBOX_FIRST_DELAY_S: u64 = 10;
/// Upper bound on the wait between two rounds of retries.
const OUTBOX_MAX_DELAY_S: u64 = 120;
/// How many unreported rounds are held. An unbounded queue would be a memory
/// leak during a long outage; this is far more rounds than a free instance sees.
const OUTBOX_CAPACITY: usize = 64;

/// A player as it appears in the round result.
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlayerResult {
    pub player_id: String,
    pub player_name: String,
    /// Whole seconds of chicken possession. Floored so the ledger and the result
    /// screen can never disagree on a split.
    pub possession_seconds: f64,
    /// XP accrued during the round.
    pub xp: f64,
    /// MON accrued during the round.
    pub mon: f64,
}

/// One player's share of the prize.
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Share {
    pub player_id: String,
    pub player_name: String,
    /// Possession seconds the share was derived from.
    pub seconds: f64,
    /// Fraction of the prize, 0..1. A split's shares always add up to 1.
    pub share: f64,
}

/// The reward split of the round.
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Split {
    /// True when the prize is shared between two players.
    pub is_split: bool,
    pub shares: Vec<Share>,
}

/// A player referenced by id and name only.
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlayerRef {
    pub player_id: String,
    pub player_name: String,
}

/// The winner of the round.
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Winner {
    pub player_id: String,
    pub player_name: String,
    pub possession_seconds: f64,
}

/// The outcome of a round.
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RoundResult {
    /// `instant` (60 s of possession) or `buzzer` (the global timer ran out).
    pub reason: String,
    /// When the round ended, in milliseconds since the epoch.
    pub ended_at: i64,
    pub winner: Option<Winner>,
    pub split: Split,
    pub players: Vec<PlayerResult>,
    /// Who was carrying the lootbox when the round ended.
    pub lootbox_holder: Option<PlayerRef>,
    /// How many times the lootbox changed hands during the round. Each steal
    /// burns `GAS_PER_STEAL` out of the pool on-chain, so the control plane
    /// needs the count to reconcile the box before it settles the match.
    pub lootbox_steals: u32,
}

/// The body posted to the control plane.
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ResultReport {
    /// The allocated match id. Equal to the room id for a sponsored match.
    pub match_id: String,
    pub room: String,
    #[serde(flatten)]
    pub result: RoundResult,
}

/// What a successful report produced.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ReportOutcome {
    /// The control plane took the result.
    Settled,
    /// There is no match record for this room (the shared training lobby), so
    /// there is nothing to settle. Not an error.
    NothingToSettle,
}

/// Why a report failed, and whether another attempt could help.
#[derive(Clone, Debug)]
pub struct ReportError {
    pub message: String,
    pub retryable: bool,
}

impl ReportError {
    fn permanent(message: impl Into<String>) -> Self {
        ReportError {
            message: message.into(),
            retryable: false,
        }
    }
}

/// A finished round waiting to be accepted by the control plane.
struct PendingReport {
    room: String,
    result: RoundResult,
}

/// The outbox sender, created on the first round that needs reporting.
static OUTBOX: OnceLock<mpsc::UnboundedSender<PendingReport>> = OnceLock::new();
/// How many reports are queued or in flight, so the backlog stays bounded.
static OUTBOX_DEPTH: AtomicUsize = AtomicUsize::new(0);

/// Hand a finished round to the outbox.
///
/// Returns immediately: the tick loop must keep its cadence whether or not the
/// control plane is reachable. The worker retries until the report is accepted.
pub fn queue_round_result(room: String, result: RoundResult) {
    if OUTBOX_DEPTH.fetch_add(1, Ordering::Relaxed) >= OUTBOX_CAPACITY {
        OUTBOX_DEPTH.fetch_sub(1, Ordering::Relaxed);
        logs::push(format!(
            "room {room}: settlement backlog is full ({OUTBOX_CAPACITY} rounds); this result was NOT queued"
        ));
        tracing::error!(room = %room, "settlement backlog full, dropping the round result");
        return;
    }

    let sender = OUTBOX.get_or_init(|| {
        let (tx, rx) = mpsc::unbounded_channel();
        tokio::spawn(outbox_worker(rx));
        tx
    });

    if sender.send(PendingReport { room: room.clone(), result }).is_err() {
        OUTBOX_DEPTH.fetch_sub(1, Ordering::Relaxed);
        logs::push(format!(
            "room {room}: the settlement worker is gone; this result was NOT queued"
        ));
    }
}

/// Drain the outbox one round at a time, oldest first.
///
/// Serial is deliberate: a backlog only exists while the control plane is
/// unreachable, and then every job is aimed at the same failing endpoint.
async fn outbox_worker(mut rx: mpsc::UnboundedReceiver<PendingReport>) {
    let client = match reqwest::Client::builder()
        .timeout(Duration::from_secs(REPORT_TIMEOUT_S))
        .build()
    {
        Ok(client) => client,
        Err(err) => {
            // No http client at all: keep the results in the queue so nothing is
            // lost, and say so. This cannot really happen, but it must not panic.
            tracing::error!("could not build the settlement http client: {err}");
            logs::push(format!(
                "settlement: could not build the http client ({err}); results stay queued"
            ));
            while let Some(job) = rx.recv().await {
                OUTBOX_DEPTH.fetch_sub(1, Ordering::Relaxed);
                tracing::error!(room = %job.room, "dropping round result: no http client");
            }
            return;
        }
    };
    let secret = internal_secret();

    while let Some(job) = rx.recv().await {
        let body = ResultReport {
            match_id: job.room.clone(),
            room: job.room.clone(),
            result: job.result,
        };
        let url = format!("{}/internal/matches/{}/result", control_plane_url(), body.room);

        let outcome = deliver(
            &body,
            &client,
            &url,
            &secret,
            Duration::from_secs(OUTBOX_FIRST_DELAY_S),
            usize::MAX,
        )
        .await;

        match outcome {
            Ok(ReportOutcome::Settled) => logs::push(format!(
                "room {}: round result reported to the control plane",
                job.room
            )),
            Ok(ReportOutcome::NothingToSettle) => logs::push(format!(
                "room {}: no match record for this room, nothing to settle",
                job.room
            )),
            Err(err) => {
                // Permanent: a malformed payload or a wrong shared secret. Keep the
                // whole report so it can be re-posted by hand once the cause is fixed.
                let payload = serde_json::to_string(&body)
                    .unwrap_or_else(|_| "<the payload could not be serialised>".to_string());
                logs::push(format!(
                    "room {}: round result NOT settled ({}). Re-post with: \
                     curl -X POST {url} -H 'content-type: application/json' \
                     -H 'x-internal-secret: <INTERNAL_SECRET>' -d '{payload}'",
                    job.room, err.message
                ));
                tracing::error!(
                    room = %job.room,
                    "round result rejected permanently: {}",
                    err.message
                );
            }
        }
        OUTBOX_DEPTH.fetch_sub(1, Ordering::Relaxed);
    }
}

/// Post one report until it is accepted, backing off between rounds.
///
/// `max_rounds` exists for tests; the worker passes [`usize::MAX`].
pub(crate) async fn deliver(
    body: &ResultReport,
    client: &reqwest::Client,
    url: &str,
    secret: &str,
    first_delay: Duration,
    max_rounds: usize,
) -> Result<ReportOutcome, ReportError> {
    let mut round = 0usize;
    loop {
        round += 1;
        match post_once(client, url, secret, body).await {
            Ok(outcome) => return Ok(outcome),
            Err(err) => {
                // 4xx (other than 404, handled as NothingToSettle) means the request
                // itself is wrong; repeating it would only repeat the mistake.
                if !err.retryable || round >= max_rounds {
                    return Err(err);
                }
                if round == 1 || round % 10 == 0 {
                    logs::push(format!(
                        "room {}: report still failing after {round} attempt(s): {}",
                        body.room, err.message
                    ));
                }
                tracing::warn!(
                    room = %body.room,
                    round,
                    "round result report failed: {}",
                    err.message
                );
                tokio::time::sleep(next_delay(first_delay, round)).await;
            }
        }
    }
}

/// Exponential backoff: `first`, `2x`, `4x`, ... capped at [`OUTBOX_MAX_DELAY_S`].
fn next_delay(first: Duration, round: usize) -> Duration {
    let doublings = round.saturating_sub(1).min(8) as u32;
    first
        .saturating_mul(1u32 << doublings)
        .min(Duration::from_secs(OUTBOX_MAX_DELAY_S))
}

/// Post the result once.
///
/// Split out of the retry loop so a test can point it at a local server
/// instead of the live control plane.
pub async fn post_once(
    client: &reqwest::Client,
    url: &str,
    secret: &str,
    body: &ResultReport,
) -> Result<ReportOutcome, ReportError> {
    let response = client
        .post(url)
        .header("x-internal-secret", secret)
        .header("content-type", "application/json")
        .json(body)
        .send()
        .await
        .map_err(|err| ReportError {
            message: err.to_string(),
            retryable: true,
        })?;

    let status = response.status();
    if status.is_success() {
        return Ok(ReportOutcome::Settled);
    }

    let text = response.text().await.unwrap_or_default();
    let message = format!(
        "the control plane returned {status}: {}",
        text.chars().take(200).collect::<String>()
    );

    // A room without a match record (the shared training lobby) has nothing to
    // settle. That is not a failure, and repeating the request would not change it.
    if status == reqwest::StatusCode::NOT_FOUND {
        return Ok(ReportOutcome::NothingToSettle);
    }

    // Every other 4xx is a request we made wrong: the payload or the secret.
    // Retrying it would only repeat the mistake.
    if status.is_client_error() {
        return Err(ReportError::permanent(message));
    }

    Err(ReportError {
        message,
        retryable: true,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::extract::{Path, State};
    use axum::http::HeaderMap;
    use axum::routing::post;
    use axum::Router;
    use std::sync::Arc;
    use tokio::sync::Mutex;

    /// What the fake control plane saw, and how it answered.
    #[derive(Clone, Debug)]
    struct Captured {
        match_id: String,
        secret: String,
        body: String,
        status: axum::http::StatusCode,
    }

    impl Default for Captured {
        fn default() -> Self {
            Captured {
                match_id: String::new(),
                secret: String::new(),
                body: String::new(),
                status: axum::http::StatusCode::OK,
            }
        }
    }

    async fn capture(
        State(state): State<Arc<Mutex<Captured>>>,
        Path(match_id): Path<String>,
        headers: HeaderMap,
        body: String,
    ) -> (axum::http::StatusCode, &'static str) {
        let mut slot = state.lock().await;
        slot.match_id = match_id;
        slot.secret = headers
            .get("x-internal-secret")
            .and_then(|value| value.to_str().ok())
            .unwrap_or("")
            .to_string();
        slot.body = body;
        (slot.status, "ok")
    }

    /// A control plane that answers the report route with `status` and anything
    /// else with 404 (the "no match record for this room" case).
    async fn spawn_server(status: axum::http::StatusCode) -> (String, Arc<Mutex<Captured>>) {
        let state = Arc::new(Mutex::new(Captured {
            status,
            ..Captured::default()
        }));
        let app = Router::new()
            .route("/internal/matches/:match_id/result", post(capture))
            .fallback(|| async { axum::http::StatusCode::NOT_FOUND })
            .with_state(state.clone());
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        tokio::spawn(async move {
            axum::serve(listener, app).await.unwrap();
        });
        (format!("http://{addr}"), state)
    }

    /// A control plane that refuses the first `failures` requests with `failure`
    /// and then accepts, counting how many requests it saw.
    #[derive(Clone)]
    struct CountingState {
        seen: Arc<AtomicUsize>,
        failures: usize,
        failure: axum::http::StatusCode,
    }

    async fn counting(State(state): State<CountingState>) -> axum::http::StatusCode {
        let n = state.seen.fetch_add(1, Ordering::SeqCst) + 1;
        if n <= state.failures {
            state.failure
        } else {
            axum::http::StatusCode::OK
        }
    }

    async fn spawn_counting_server(
        failures: usize,
        failure: axum::http::StatusCode,
    ) -> (String, Arc<AtomicUsize>) {
        let seen = Arc::new(AtomicUsize::new(0));
        let state = CountingState {
            seen: seen.clone(),
            failures,
            failure,
        };
        let app = Router::new()
            .route("/internal/matches/:match_id/result", post(counting))
            .with_state(state);
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        tokio::spawn(async move {
            axum::serve(listener, app).await.unwrap();
        });
        (format!("http://{addr}"), seen)
    }

    fn sample_report() -> ResultReport {
        ResultReport {
            match_id: "match-42".to_string(),
            room: "match-42".to_string(),
            result: RoundResult {
                reason: "buzzer".to_string(),
                ended_at: 1_700_000_000_000,
                winner: Some(Winner {
                    player_id: "p1".to_string(),
                    player_name: "alice".to_string(),
                    possession_seconds: 42.0,
                }),
                split: Split {
                    is_split: true,
                    shares: vec![
                        Share {
                            player_id: "p1".to_string(),
                            player_name: "alice".to_string(),
                            seconds: 42.0,
                            share: 0.5,
                        },
                        Share {
                            player_id: "p2".to_string(),
                            player_name: "bob".to_string(),
                            seconds: 42.0,
                            share: 0.5,
                        },
                    ],
                },
                players: vec![PlayerResult {
                    player_id: "p1".to_string(),
                    player_name: "alice".to_string(),
                    possession_seconds: 42.0,
                    xp: 120.5,
                    mon: 0.25,
                }],
                lootbox_holder: Some(PlayerRef {
                    player_id: "p2".to_string(),
                    player_name: "bob".to_string(),
                }),
                lootbox_steals: 3,
            },
        }
    }

    #[tokio::test]
    async fn the_result_is_posted_to_the_control_plane_with_the_secret() {
        let (base, captured) = spawn_server(axum::http::StatusCode::OK).await;
        let client = reqwest::Client::new();
        let body = sample_report();

        let outcome = post_once(
            &client,
            &format!("{base}/internal/matches/match-42/result"),
            "s3cret",
            &body,
        )
        .await
        .unwrap();

        assert_eq!(outcome, ReportOutcome::Settled);

        let slot = captured.lock().await;
        assert_eq!(slot.match_id, "match-42");
        assert_eq!(slot.secret, "s3cret");

        let parsed: serde_json::Value = serde_json::from_str(&slot.body).unwrap();
        assert_eq!(parsed["matchId"], "match-42");
        assert_eq!(parsed["room"], "match-42");
        assert_eq!(parsed["reason"], "buzzer");
        assert_eq!(parsed["winner"]["playerId"], "p1");
        assert_eq!(parsed["winner"]["playerName"], "alice");
        assert_eq!(parsed["split"]["isSplit"], true);
        assert_eq!(parsed["split"]["shares"].as_array().unwrap().len(), 2);
        assert_eq!(parsed["split"]["shares"][0]["share"], 0.5);
        assert_eq!(parsed["players"][0]["playerName"], "alice");
        assert_eq!(parsed["players"][0]["possessionSeconds"], 42.0);
        assert_eq!(parsed["players"][0]["xp"], 120.5);
        assert_eq!(parsed["players"][0]["mon"], 0.25);
        assert_eq!(parsed["lootboxHolder"]["playerName"], "bob");
    }

    #[tokio::test]
    async fn a_room_without_a_match_record_is_not_an_error() {
        let (base, _captured) = spawn_server(axum::http::StatusCode::NOT_FOUND).await;
        let client = reqwest::Client::new();

        // A 404 is the "no match record for this room" case (the shared training
        // lobby), which is not a failure.
        let outcome = post_once(
            &client,
            &format!("{base}/internal/matches/default/result"),
            "",
            &sample_report(),
        )
        .await
        .unwrap();

        assert_eq!(outcome, ReportOutcome::NothingToSettle);
    }

    #[tokio::test]
    async fn a_rejected_request_is_not_retried() {
        let (base, _captured) = spawn_server(axum::http::StatusCode::FORBIDDEN).await;
        let client = reqwest::Client::new();

        let err = post_once(
            &client,
            &format!("{base}/internal/matches/match-42/result"),
            "wrong",
            &sample_report(),
        )
        .await
        .unwrap_err();

        assert!(!err.retryable, "a rejected request must not be retried");
    }

    #[tokio::test]
    async fn a_report_the_control_plane_cannot_take_yet_is_retried_until_it_can() {
        let (base, seen) =
            spawn_counting_server(2, axum::http::StatusCode::SERVICE_UNAVAILABLE).await;
        let client = reqwest::Client::new();
        let body = sample_report();

        let outcome = deliver(
            &body,
            &client,
            &format!("{base}/internal/matches/match-42/result"),
            "s3cret",
            Duration::from_millis(5),
            5,
        )
        .await
        .unwrap();

        assert_eq!(outcome, ReportOutcome::Settled);
        assert_eq!(
            seen.load(Ordering::SeqCst),
            3,
            "two refusals, then the accepted post"
        );
    }

    #[tokio::test]
    async fn a_permanently_rejected_report_is_not_retried() {
        let (base, seen) =
            spawn_counting_server(usize::MAX, axum::http::StatusCode::FORBIDDEN).await;
        let client = reqwest::Client::new();

        let err = deliver(
            &sample_report(),
            &client,
            &format!("{base}/internal/matches/match-42/result"),
            "wrong",
            Duration::from_millis(5),
            6,
        )
        .await
        .unwrap_err();

        assert!(!err.retryable, "a 403 is a configuration error, not a wobble");
        assert_eq!(seen.load(Ordering::SeqCst), 1, "a permanent rejection is final");
    }

    #[test]
    fn the_outbox_backoff_grows_and_caps() {
        let first = Duration::from_secs(10);
        assert_eq!(next_delay(first, 1), Duration::from_secs(10));
        assert_eq!(next_delay(first, 2), Duration::from_secs(20));
        assert_eq!(next_delay(first, 3), Duration::from_secs(40));
        assert_eq!(next_delay(first, 4), Duration::from_secs(80));
        assert_eq!(
            next_delay(first, 5),
            Duration::from_secs(120),
            "the wait is capped at two minutes"
        );
        assert_eq!(next_delay(first, 99), Duration::from_secs(120));
    }
}
