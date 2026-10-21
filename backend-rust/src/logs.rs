//! A tiny in-memory ring buffer of recent server events.
//!
//! Render does not expose the container logs through an API, so the room server
//! keeps its own short history of the things that matter operationally (client
//! connects, round ends, writer failures, disconnects) and serves it at
//! `/debug/logs`.
//!
//! This is deliberately not a tracing layer: it only records the few events that
//! explain a client-visible problem, so it stays small and cheap on a throttled
//! instance.

use std::collections::VecDeque;
use std::sync::Mutex;

/// How many lines are kept. A round plus its cleanup fits comfortably.
const CAPACITY: usize = 500;

static LOGS: Mutex<VecDeque<String>> = Mutex::new(VecDeque::new());

/// Append a line to the ring buffer.
pub fn push(line: impl Into<String>) {
    let mut logs = LOGS.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    if logs.len() >= CAPACITY {
        logs.pop_front();
    }
    logs.push_back(line.into());
}

/// The buffered lines, oldest first.
pub fn snapshot() -> Vec<String> {
    let logs = LOGS.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    logs.iter().cloned().collect()
}
