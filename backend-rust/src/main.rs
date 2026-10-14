//! World of Nads realtime arena room server (Rust).
//!
//! Phase 1 spike: one room, wire-compatible with the Node game server
//! (`backend/index.js`). The Godot client connects unchanged.

#![allow(dead_code)]

mod config;
mod net;
mod protocol;
mod world;

use std::net::SocketAddr;
use std::sync::Arc;

use crate::config::PORT;
use crate::net::{router, run_tick, AppState};

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "room_server=info".into()),
        )
        .init();

    let state = Arc::new(AppState::new());

    let tick_state = state.clone();
    tokio::spawn(async move { run_tick(tick_state).await });

    let app = router(state);
    // Render (and most PaaS) convention: honor $PORT when present. The Dockerfile
    // also EXPOSEs 8080, so either detection method routes to the same port.
    let port: u16 = std::env::var("PORT")
        .ok()
        .and_then(|value| value.trim().parse().ok())
        .unwrap_or(PORT);
    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .unwrap_or_else(|e| panic!("failed to bind {}: {}", addr, e));

    tracing::info!("room-server listening on {}", addr);
    axum::serve(listener, app)
        .await
        .unwrap_or_else(|e| panic!("server error: {}", e));
}
