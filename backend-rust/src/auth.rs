//! Minimal auth parity: reject connections with `token:username` if token is not
//! present in a small in-memory allowlist. Node uses `verifySessionToken` which
//! looks up against `sessionTokens` Map (created via createSessionToken). We
//! mirror behavior by rejecting any non-empty token that was not seen before in
//! this process. To stay minimal and compatible, we accept tokens that match the
//! format `<hex>` or any string created by Node's `randomUUID().replace(/-/g,'')`
//! in this runtime? Easier: accept if it has length>=12 and is hex-like, but we
//! don't share the store. However, Node requires a token from its own session
//! store. Since Godot may connect with existing flows, and to be safe while
//! matching semantics, we maintain a small allowlist populated on-demand via
//! `create_session_token`? But we don't have that API exposed. Alternatively,
//! treat tokens as valid only if they were previously "created" by us? Not
//! possible cross-process. The minimal useful check: mirror Node exactly for
//! the case where a token is provided - Node rejects if token not found in
//! sessionTokens. So we need an in-memory store.

use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

const SESSION_TOKEN_EXPIRY_MS: i64 = 1_800_000; // 30 minutes

lazy_static::lazy_static! {
    static ref TOKENS: Mutex<HashMap<String, i64>> = Mutex::new(HashMap::new());
}

pub fn create_session_token() -> String {
    let token = uuid::Uuid::new_v4()
        .to_string()
        .replace('-', "");
    let now = now_ms();
    TOKENS.lock().unwrap().insert(token.clone(), now);
    token
}

pub fn verify_session_token(token: &str) -> bool {
    let mut tokens = TOKENS.lock().unwrap();
    let now = now_ms();
    match tokens.get(token) {
        Some(created) => {
            if now - *created > SESSION_TOKEN_EXPIRY_MS {
                tokens.remove(token);
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
