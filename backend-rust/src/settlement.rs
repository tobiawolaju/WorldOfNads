//! Reports a finished round to the control plane.
//!
//! The room server owns the simulation; the control plane owns the ledger:
//! Firebase holds the match record, the on-chain escrow holds the prize. When a
//! round ends, the room posts the outcome to the control plane, which writes the
//! result, credits the players and - for a round with a single winner - settles
//! the prize on-chain.
//!
//! The report is deliberately *not* awaited by the tick: a round end must never
//! stall the simulation, so the post runs in its own task and retries a couple of
//! times before giving up. Nothing is lost when it fails - the result stays in the
//! room's event history and the control plane can be re-fed by hand.

use std::time::Duration;

use serde::Serialize;

use crate::config::{control_plane_url, internal_secret};
use crate::logs;

/// How many times a report is attempted before it is given up on.
///
/// The control plane answers 503 when it cannot read the escrow: that keeps the
/// result in its ledger but leaves the chain leg for a retry, so the window has
/// to be wide enough to ride out a short RPC wobble (~14 s in total).
const REPORT_ATTEMPTS: usize = 4;
/// Timeout of a single report request.
const REPORT_TIMEOUT_S: u64 = 10;
/// Base pause between two attempts (grows with the attempt number).
const REPORT_BACKOFF_S: u64 = 2;

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

/// Post the result of a round to the control plane.
///
/// Never blocks the caller for long and never panics: a failed report is logged
/// into the ring buffer so it can be seen at `/debug/logs`.
pub async fn report_round_result(room: &str, result: RoundResult) -> Result<ReportOutcome, ReportError> {
    let url = format!("{}/internal/matches/{}/result", control_plane_url(), room);
    let body = ResultReport {
        match_id: room.to_string(),
        room: room.to_string(),
        result,
    };

    let client = match reqwest::Client::builder()
        .timeout(Duration::from_secs(REPORT_TIMEOUT_S))
        .build()
    {
        Ok(client) => client,
        Err(err) => {
            return Err(ReportError::permanent(format!(
                "could not build the http client: {err}"
            )))
        }
    };
    let secret = internal_secret();

    let mut last: Option<ReportError> = None;
    for attempt in 1..=REPORT_ATTEMPTS {
        match post_once(&client, &url, &secret, &body).await {
            Ok(outcome) => {
                match outcome {
                    ReportOutcome::Settled => {
                        logs::push(format!(
                            "room {room}: round result reported to the control plane"
                        ));
                    }
                    ReportOutcome::NothingToSettle => {
                        logs::push(format!(
                            "room {room}: no match record for this room, nothing to settle"
                        ));
                    }
                }
                return Ok(outcome);
            }
            Err(err) => {
                logs::push(format!(
                    "room {room}: result report attempt {attempt}/{REPORT_ATTEMPTS} failed: {}",
                    err.message
                ));
                tracing::warn!(
                    room = %room,
                    attempt,
                    "round result report failed: {}",
                    err.message
                );
                if !err.retryable {
                    return Err(err);
                }
                last = Some(err);
                if attempt < REPORT_ATTEMPTS {
                    tokio::time::sleep(Duration::from_secs(REPORT_BACKOFF_S * attempt as u64)).await;
                }
            }
        }
    }

    Err(last.unwrap_or_else(|| ReportError::permanent("the result report failed")))
}

/// Post the result once.
///
/// Split out of [`report_round_result`] so a test can point it at a local server
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
}
