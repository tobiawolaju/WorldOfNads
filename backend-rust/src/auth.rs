//! Minimal auth parity for the `token:username` connect form.
//!
//! Node issues a session token (`createSessionToken`) and rejects a connect whose token
//! is unknown or older than `SESSION_TOKEN_EXPIRY_MS` with `1008 invalid_token`. The room
//! server keeps the same contract with a small in-process store: a token minted here
//! validates for 30 minutes, anything else is rejected. When the control plane later
//! shares tokens (shared secret / JWKS), only `verify_session_token` needs to change.

use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};
use std::time::{SystemTime, UNIX_EPOCH};

const SESSION_TOKEN_EXPIRY_MS: i64 = 1_800_000; // 30 minutes

fn tokens() -> &'static Mutex<HashMap<String, i64>> {
    static TOKENS: OnceLock<Mutex<HashMap<String, i64>>> = OnceLock::new();
    TOKENS.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Mint a session token (hex, no dashes) valid for 30 minutes.
pub fn create_session_token() -> String {
    let token = uuid::Uuid::new_v4().to_string().replace('-', "");
    let now = now_ms();
    if let Ok(mut store) = tokens().lock() {
        store.insert(token.clone(), now);
    }
    token
}

/// True while `token` is known and unexpired. An expired token is dropped on sight.
pub fn verify_session_token(token: &str) -> bool {
    let now = now_ms();
    let Ok(mut store) = tokens().lock() else {
        return false;
    };
    match store.get(token) {
        Some(created) => {
            if now - *created > SESSION_TOKEN_EXPIRY_MS {
                store.remove(token);
                false
            } else {
                true
            }
        }
        None => false,
    }
}

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64
}
