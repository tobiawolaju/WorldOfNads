//! WebSocket/HTTP transport: upgrades `/` (and any non-`/events` path) to the
//! game socket and `/events` to the events feed. Mirrors the Node server's
//! upgrade routing so the Godot client connects unchanged.

use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::{Query, State};
use axum::response::IntoResponse;
use axum::routing::get;
use axum::Router;
use futures_util::{SinkExt, StreamExt};
use serde_json::Value;
use tokio::sync::{mpsc, Mutex};

use crate::config::*;
use crate::protocol::*;
use crate::world::{sanitize_meta, Room};

pub struct AppState {
    pub room: Mutex<Room>,
    pub clients: Mutex<HashMap<String, mpsc::UnboundedSender<Message>>>,
    pub events_clients: Mutex<Vec<mpsc::UnboundedSender<Message>>>,
}

impl AppState {
    pub fn new() -> Self {
        AppState {
            room: Mutex::new(Room::new()),
            clients: Mutex::new(HashMap::new()),
            events_clients: Mutex::new(Vec::new()),
        }
    }
}

pub fn router(state: Arc<AppState>) -> Router {
    Router::new()
        .route("/", get(ws_game))
        .route("/events", get(ws_events))
        .route("/health", get(health))
        .fallback(get(ws_game))
        .with_state(state)
}

async fn health() -> &'static str {
    "Server is alive and healthy!\n"
}

async fn ws_game(
    ws: WebSocketUpgrade,
    State(state): State<Arc<AppState>>,
    Query(params): Query<HashMap<String, String>>,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_game(socket, state, params))
}

async fn ws_events(ws: WebSocketUpgrade, State(state): State<Arc<AppState>>) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_events(socket, state))
}

/// `username` is either `<token>:<username>` or a bare `<username>`.
/// Token verification against the control plane is a TODO (Phase 2); for now the
/// username part is accepted, matching Node's no-colon fallback path.
fn parse_username(raw: &str) -> String {
    let raw = raw.trim();
    if raw.is_empty() {
        return String::new();
    }
    if let Some(idx) = raw.find(':') {
        if idx > 0 {
            return parse_username(&raw[idx + 1..]);
        }
    }
    sanitize_username(raw)
}

async fn handle_game(socket: WebSocket, state: Arc<AppState>, params: HashMap<String, String>) {
    let raw_username = params.get("username").cloned().unwrap_or_default();
    let skin_param = params
        .get("skin")
        .or_else(|| params.get("skinId"))
        .cloned()
        .unwrap_or_default();
    let requested_skin = resolve_skin_name(&skin_param);

    let player_id = uuid::Uuid::new_v4().to_string();

    let mut username = parse_username(&raw_username);
    if username.is_empty() {
        username = format!("player-{}", &player_id[..8]);
    }

    let (tx, rx) = mpsc::unbounded_channel::<Message>();

    {
        let mut room = state.room.lock().await;
        room.add_player(&player_id, &username, &requested_skin, 0);
        room.maybe_start_countdown();
        let hello = encode(&ConnectMsg {
            msg_type: "connect",
            id: player_id.clone(),
            username: username.clone(),
            skin: requested_skin.clone(),
            xp: 0,
        });
        let _ = tx.send(Message::Binary(hello));
        tracing::info!(
            "player connected: {} ({}) skin={}",
            player_id,
            username,
            requested_skin
        );
    }
    {
        let mut clients = state.clients.lock().await;
        clients.insert(player_id.clone(), tx.clone());
    }

    // Keep the socket warm through proxies (Godot answers pings automatically).
    let hb_tx = tx.clone();
    let heartbeat = tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_millis(30_000));
        interval.tick().await;
        loop {
            interval.tick().await;
            if hb_tx.send(Message::Ping(Vec::new())).is_err() {
                break;
            }
        }
    });

    let (mut sender, mut receiver) = socket.split();
    let writer = tokio::spawn(async move {
        let mut rx = rx;
        while let Some(msg) = rx.recv().await {
            if sender.send(msg).await.is_err() {
                break;
            }
        }
    });

    let mut window_start = now_ms();
    let mut msg_count: u32 = 0;

    while let Some(incoming) = receiver.next().await {
        let msg = match incoming {
            Ok(m) => m,
            Err(_) => break,
        };
        match msg {
            Message::Binary(bytes) => {
                let now = now_ms();
                if now - window_start > WS_RATE_LIMIT_WINDOW_MS {
                    window_start = now;
                    msg_count = 0;
                }
                msg_count += 1;
                if msg_count > WS_RATE_LIMIT_MAX_MESSAGES || bytes.len() > WS_MAX_MESSAGE_SIZE {
                    break;
                }
                handle_client_message(&state, &player_id, &bytes).await;
            }
            Message::Ping(payload) => {
                let _ = tx.send(Message::Pong(payload));
            }
            Message::Close(_) => break,
            _ => {}
        }
    }

    heartbeat.abort();
    writer.abort();

    {
        let mut clients = state.clients.lock().await;
        clients.remove(&player_id);
    }

    let removed = {
        let mut room = state.room.lock().await;
        room.remove_player(&player_id, now_ms())
    };
    if let Some(payload) = removed {
        broadcast_bytes(&state, &payload).await;
    }
    tracing::info!("player disconnected: {}", player_id);
}

async fn handle_client_message(state: &Arc<AppState>, player_id: &str, bytes: &[u8]) {
    let data: Value = match rmp_serde::from_slice(bytes) {
        Ok(v) => v,
        Err(_) => return,
    };
    let msg_type = match data.get("type").and_then(|v| v.as_str()) {
        Some(t) => t.to_string(),
        None => return,
    };

    let mut room = state.room.lock().await;
    match msg_type.as_str() {
        "update_state" => room.apply_update_state(player_id, &data),
        "pickup_request" => {
            if let Some(item_id) = data.get("item_id").and_then(|v| v.as_str()) {
                room.pickup_request(player_id, item_id);
            }
        }
        "use_request" => {
            if let Some(item_id) = data.get("item_id").and_then(|v| v.as_str()) {
                room.use_request(player_id, item_id);
            }
        }
        "drop_request" => {
            if let Some(item_id) = data.get("item_id").and_then(|v| v.as_str()) {
                room.drop_request(player_id, item_id);
            }
        }
        "request_full_state" => room.request_full_state(player_id),
        "client_event" => {
            let event_type: String = data
                .get("eventType")
                .and_then(|v| v.as_str())
                .unwrap_or("client_event")
                .chars()
                .take(40)
                .collect();
            let message =
                sanitize_message(data.get("message").and_then(|v| v.as_str()).unwrap_or(""));
            if !message.is_empty() {
                let meta = sanitize_meta(data.get("meta"));
                room.publish_event(&event_type, &message, player_id, &meta);
            }
        }
        _ => {}
    }
}

async fn handle_events(socket: WebSocket, state: Arc<AppState>) {
    let (tx, rx) = mpsc::unbounded_channel::<Message>();

    let snapshot = {
        let room = state.room.lock().await;
        room.event_history_snapshot().to_string()
    };
    let _ = tx.send(Message::Text(snapshot));

    {
        let mut events = state.events_clients.lock().await;
        events.push(tx.clone());
    }

    let (mut sender, mut receiver) = socket.split();
    let writer = tokio::spawn(async move {
        let mut rx = rx;
        while let Some(msg) = rx.recv().await {
            if sender.send(msg).await.is_err() {
                break;
            }
        }
    });

    while let Some(incoming) = receiver.next().await {
        if incoming.is_err() {
            break;
        }
    }

    writer.abort();
    let mut events = state.events_clients.lock().await;
    events.retain(|sender| !sender.is_closed());
}

// ---------------------------------------------------------------------------
// Broadcast + tick loop
// ---------------------------------------------------------------------------

async fn broadcast_messages(state: &Arc<AppState>, messages: Vec<(String, Vec<u8>)>) {
    let clients = state.clients.lock().await;
    for (player_id, bytes) in messages {
        if let Some(tx) = clients.get(&player_id) {
            let _ = tx.send(Message::Binary(bytes));
        }
    }
}

async fn broadcast_bytes(state: &Arc<AppState>, bytes: &[u8]) {
    let clients = state.clients.lock().await;
    for tx in clients.values() {
        let _ = tx.send(Message::Binary(bytes.to_vec()));
    }
}

async fn broadcast_events(state: &Arc<AppState>, events: Vec<String>) {
    if events.is_empty() {
        return;
    }
    let clients = state.events_clients.lock().await;
    for event in events {
        for tx in clients.iter() {
            let _ = tx.send(Message::Text(event.clone()));
        }
    }
}

async fn close_all(state: &Arc<AppState>) {
    let mut clients = state.clients.lock().await;
    for tx in clients.values() {
        let _ = tx.send(Message::Close(None));
    }
    clients.clear();
}

pub async fn run_tick(state: Arc<AppState>) {
    let mut interval = tokio::time::interval(Duration::from_millis(1000 / BROADCAST_RATE));
    loop {
        interval.tick().await;
        let now = now_ms();
        let output = {
            let mut room = state.room.lock().await;
            room.tick(now)
        };

        if !output.messages.is_empty() {
            broadcast_messages(&state, output.messages).await;
        }
        if !output.events.is_empty() {
            broadcast_events(&state, output.events).await;
        }
        if output.close_all {
            tracing::info!("round finished: closing all clients");
            close_all(&state).await;
        }
    }
}
