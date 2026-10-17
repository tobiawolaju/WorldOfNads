//! Session-token parity for the `token:username` connect form.
//!
//! The control plane mints the token (`POST /auth/request-token`) as
//! `<expiresAt>.<hmac(expiresAt)>` keyed by `SESSION_TOKEN_SECRET`, and its own
//! `verifySessionToken` checks that signature. This side verifies the same signature, so
//! one token works on both services and survives a restart of either.
//!
//! The previous implementation kept an in-process store of tokens *it* had minted — and
//! nothing ever called `create_session_token`, so that store was always empty — which
//! meant every token the control plane issued was rejected with `1008 invalid_token`.
//! Web players always carry one (`Play.tsx` requests it before loading the iframe), so
//! every web connect to this server was refused.
//!
//! With `SESSION_TOKEN_SECRET` unset this accepts any token that is shaped like one,
//! matching how the control plane treats an unset `INTERNAL_SECRET`: play keeps working
//! while the two services are not yet configured together, and the boot log says so.

use hmac::{Hmac, Mac};
use sha2::Sha256;

use crate::config::session_token_secret;
use crate::protocol::now_ms;

/// True while `token` is one the control plane could have minted and is unexpired.
///
/// An unset secret short-circuits to acceptance (see the module docs); a token that is
/// not `<decimal ms timestamp>.<64 hex chars>` is rejected either way.
pub fn verify_session_token(token: &str) -> bool {
    let Some(secret) = session_token_secret() else {
        return true;
    };
    let Some((expires_at, signature)) = token.split_once('.') else {
        return false;
    };
    let Ok(expires_at_ms) = expires_at.parse::<i64>() else {
        return false;
    };
    if expires_at_ms < now_ms() {
        return false;
    }
    let Ok(mut mac) = Hmac::<Sha256>::new_from_slice(secret.as_bytes()) else {
        return false;
    };
    // Node signs `String(expiresAt)`, so the signed bytes are the timestamp as text.
    mac.update(expires_at.as_bytes());
    let expected = mac.finalize().into_bytes();
    match decode_hex(signature) {
        Some(decoded) => constant_time_eq(&expected[..], &decoded),
        None => false,
    }
}

fn decode_hex(input: &str) -> Option<Vec<u8>> {
    if input.len() % 2 != 0 {
        return None;
    }
    let bytes = input.as_bytes();
    let mut out = Vec::with_capacity(bytes.len() / 2);
    for pair in bytes.chunks_exact(2) {
        out.push((hex_nibble(pair[0])? << 4) | hex_nibble(pair[1])?);
    }
    Some(out)
}

fn hex_nibble(byte: u8) -> Option<u8> {
    match byte {
        b'0'..=b'9' => Some(byte - b'0'),
        b'a'..=b'f' => Some(byte - b'a' + 10),
        b'A'..=b'F' => Some(byte - b'A' + 10),
        _ => None,
    }
}

/// Compares without short-circuiting, so the comparison itself cannot be timed.
fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut diff = 0u8;
    for (x, y) in a.iter().zip(b.iter()) {
        diff |= x ^ y;
    }
    diff == 0
}
