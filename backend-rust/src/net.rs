//! WebSocket/HTTP transport: upgrades `/` (and any non-`/events` path) to the
//! game socket and `/events` to the events feed. Mirrors the Node server's
//! upgrade routing so the Godot client connects unchanged.

use std::borrow::Cow;
use std::collections::HashMap;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Duration;

use axum::extract::ws::{close_code, CloseFrame, Message, WebSocket, WebSocketUpgrade};
use axum::extract::{Query, State};
use axum::response::IntoResponse;
use axum::routing::get;
use axum::Router;
use futures_util::stream::SplitSink;
use futures_util::{SinkExt, StreamExt};
use serde_json::Value;
use tokio::sync::{mpsc, Mutex};

use crate::config::*;
use crate::protocol::*;
use crate::world::{sanitize_meta, Room};

/// Frames that count against a client's byte budget. Control frames (ping/pong/close)
/// are exempt so keepalives and shutdown always get through a saturated socket.
fn is_bulk(msg: &Message) -> bool {
    matches!(msg, Message::Text(_) | Message::Binary(_))
}

fn frame_len(msg: &Message) -> usize {
    match msg {
        Message::Text(text) => text.len(),
        Message::Binary(data) | Message::Ping(data) | Message::Pong(data) => data.len(),
        Message::Close(_) => 0,
    }
}

/// Per-client outbound queue with a byte budget.
///
/// Node guards every write with
/// `client.readyState === 1 && client.bufferedAmount < MAX_CLIENT_BUFFERED_BYTES` and
/// simply *skips* a backed-up client, so one slow reader cannot grow server memory
/// without bound. `queued` counts the bytes handed to this client's writer task but not
/// yet flushed, and `send` drops bulk frames once that budget is spent: the same
/// guarantee, with the same "skip the frame, keep the session" semantics.
#[derive(Clone)]
struct ClientTx {
    tx: mpsc::UnboundedSender<Message>,
    queued: Arc<AtomicUsize>,
}

impl ClientTx {
    fn new(tx: mpsc::UnboundedSender<Message>, queued: Arc<AtomicUsize>) -> Self {
        Self { tx, queued }
    }

    /// Reserve `len` bytes of the budget, or report that the client is backed up.
    fn reserve(&self, len: usize) -> bool {
        let mut queued = self.queued.load(Ordering::Relaxed);
        loop {
            if queued >= MAX_CLIENT_BUFFERED_BYTES {
                return false;
            }
            match self.queued.compare_exchange_weak(
                queued,
                queued + len,
                Ordering::Relaxed,
                Ordering::Relaxed,
            ) {
                Ok(_) => return true,
                Err(actual) => queued = actual,
            }
        }
    }

    /// Mirrors Node's buffered-amount guard. Returns `false` when the frame was
    /// dropped because the client is too far behind (or the socket is gone).
    fn send(&self, msg: Message) -> bool {
        let bulk = is_bulk(&msg);
        let len = frame_len(&msg);
        if bulk && !self.reserve(len) {
            return false;
        }
        if self.tx.send(msg).is_err() {
            if bulk {
                self.queued.fetch_sub(len, Ordering::Relaxed);
            }
            return false;
        }
        true
    }

    fn is_closed(&self) -> bool {
        self.tx.is_closed()
    }

    fn same_channel(&self, other: &Self) -> bool {
        self.tx.same_channel(&other.tx)
    }
}

/// Drain a client's queue into its socket, returning budget as frames flush out.
async fn drain(
    mut sender: SplitSink<WebSocket, Message>,
    mut rx: mpsc::UnboundedReceiver<Message>,
    queued: Arc<AtomicUsize>,
) {
    while let Some(msg) = rx.recv().await {
        let bulk = is_bulk(&msg);
        let len = frame_len(&msg);
        if sender.send(msg).await.is_err() {
            // The socket is gone; the connection is being torn down, so the budget
            // for whatever is still queued no longer matters.
            break;
        }
        if bulk {
            queued.fetch_sub(len, Ordering::Relaxed);
        }
    }
}

pub struct AppState {
    pub room: Mutex<Room>,
    pub clients: Mutex<HashMap<String, ClientTx>>,
    pub events_clients: Mutex<Vec<ClientTx>>,
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

/// `username` query param is either `<token>:<username>` or a bare `<username>`.
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

async fn handle_game(mut socket: WebSocket, state: Arc<AppState>, params: HashMap<String, String>) {
    let raw_username = params.get("username").cloned().unwrap_or_default();
    let skin_param = params
        .get("skin")
        .or_else(|| params.get("skinId"))
        .cloned()
        .unwrap_or_default();
    let requested_skin = resolve_skin_name(&skin_param);

    // Node rejects the connection outright when the room is at capacity
    // (`currentMaxPlayers !== null && getPlayerCount() >= currentMaxPlayers`) and tells
    // the client why with a `1008 match_full` close. The cap is unlimited by default,
    // matching Node.
    if let Some(max_players) = max_players() {
        let player_count = {
            let room = state.room.lock().await;
            room.player_count()
        };
        if player_count >= max_players {
            tracing::info!(
                "rejecting connection: room full ({}/{} players)",
                player_count,
                max_players
            );
            let _ = socket
                .send(Message::Close(Some(CloseFrame {
                    code: close_code::POLICY,
                    reason: Cow::Borrowed("match_full"),
                })))
                .await;
            return;
        }
    }

    let player_id = uuid::Uuid::new_v4().to_string();

    let mut username = parse_username(&raw_username);
    if username.is_empty() {
        username = format!("player-{}", &player_id[..8]);
    }

    let (raw_tx, rx) = mpsc::unbounded_channel::<Message>();
    let queued = Arc::new(AtomicUsize::new(0));
    let tx = ClientTx::new(raw_tx, queued.clone());

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
        tx.send(Message::Binary(hello));
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

    let (sender, mut receiver) = socket.split();
    let writer = tokio::spawn(drain(sender, rx, queued));

    let mut window_start = now_ms();
    let mut msg_count: u32 = 0;
    // Node's `isAlive` sweep: ping every interval, and terminate a socket that never
    // ponged the previous ping. Without it a client that vanishes without a clean close
    // (tab killed, network drop, proxy timeout) lingers in `players` and is broadcast to
    // everyone else at its last position - a frozen player. Godot's WebSocketPeer
    // answers ping frames automatically during poll().
    let mut alive = true;
    let mut heartbeat = tokio::time::interval(Duration::from_millis(GAME_HEARTBEAT_INTERVAL_MS));
    heartbeat.tick().await; // discard the immediate first tick; Node's first ping is one interval in

    loop {
        tokio::select! {
            incoming = receiver.next() => {
                match incoming {
                    Some(Ok(Message::Binary(bytes))) => {
                        let now = now_ms();
                        if now - window_start > WS_RATE_LIMIT_WINDOW_MS {
                            window_start = now;
                            msg_count = 0;
                        }
                        msg_count += 1;
                        if msg_count > WS_RATE_LIMIT_MAX_MESSAGES {
                            tracing::warn!("rate limit exceeded by {}; closing", player_id);
                            break;
                        }
                        if bytes.len() > WS_MAX_MESSAGE_SIZE {
                            tracing::warn!("oversized message from {}; closing", player_id);
                            break;
                        }
                        handle_client_message(&state, &player_id, &bytes).await;
                    }
                    // Only needed for peers that ping us; axum answers a received ping
                    // on its own, but queuing the pong keeps the reply on the same path
                    // as everything else we send.
                    Some(Ok(Message::Ping(payload))) => {
                        tx.send(Message::Pong(payload));
                    }
                    Some(Ok(Message::Pong(_))) => {
                        alive = true;
                    }
                    Some(Ok(Message::Close(_))) | Some(Err(_)) | None => break,
                    Some(Ok(_)) => {}
                }
            }
            _ = heartbeat.tick() => {
                if !alive {
                    // Dropping both halves (and the writer task below) is the abrupt
                    // close `ws.terminate()` performs; the cleanup after the loop still
                    // runs, so the player is removed and everyone is told.
                    tracing::info!("no pong from {}; terminating stale socket", player_id);
                    break;
                }
                alive = false;
                tx.send(Message::Ping(Vec::new()));
            }
        }
    }

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
    let (raw_tx, rx) = mpsc::unbounded_channel::<Message>();
    let queued = Arc::new(AtomicUsize::new(0));
    let tx = ClientTx::new(raw_tx, queued.clone());

    let snapshot = {
        let room = state.room.lock().await;
        room.event_history_snapshot().to_string()
    };
    tx.send(Message::Text(snapshot));

    {
        let mut events = state.events_clients.lock().await;
        events.push(tx.clone());
    }

    let (sender, mut receiver) = socket.split();
    let writer = tokio::spawn(drain(sender, rx, queued));

    while let Some(incoming) = receiver.next().await {
        if incoming.is_err() {
            break;
        }
    }
    writer.abort();

    // Drop this subscriber's handle. Leaving it behind would keep the queue (and every
    // later reconnect's queue) alive for the lifetime of the process.
    let mut events = state.events_clients.lock().await;
    events.retain(|client| !client.same_channel(&tx));
}

async fn broadcast_messages(state: &Arc<AppState>, messages: Vec<(String, Vec<u8>)>) {
    let clients = state.clients.lock().await;
    for (player_id, bytes) in messages {
        if let Some(tx) = clients.get(&player_id) {
            tx.send(Message::Binary(bytes));
        }
    }
}

async fn broadcast_bytes(state: &Arc<AppState>, bytes: &[u8]) {
    let clients = state.clients.lock().await;
    for tx in clients.values() {
        tx.send(Message::Binary(bytes.to_vec()));
    }
}

async fn broadcast_events(state: &Arc<AppState>, events: Vec<String>) {
    if events.is_empty() {
        return;
    }
    let mut clients = state.events_clients.lock().await;
    // Sockets that went away leave their sender behind; sweep them here as well so the
    // list cannot grow with every reconnect.
    clients.retain(|client| !client.is_closed());
    for event in events {
        for tx in clients.iter() {
            tx.send(Message::Text(event.clone()));
        }
    }
}

async fn close_all(state: &Arc<AppState>) {
    let mut clients = state.clients.lock().await;
    for tx in clients.values() {
        tx.send(Message::Close(None));
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
