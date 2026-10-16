//! WebSocket/HTTP transport: upgrades `/` (and any non-`/events` path) to the
//! game socket and `/events` to the events feed. Mirrors the Node server's
//! upgrade routing so the Godot client connects unchanged.

use std::borrow::Cow;
use std::collections::HashMap;
use std::sync::atomic::{AtomicI64, AtomicUsize, Ordering};
use std::sync::atomic::AtomicU64;
use std::sync::Arc;
use std::time::Duration;

use axum::extract::ws::{close_code, CloseFrame, Message, WebSocket, WebSocketUpgrade};
use axum::extract::{Query, State};
use axum::http::HeaderMap;
use axum::response::IntoResponse;
use axum::routing::get;
use axum::Router;
use futures_util::stream::SplitSink;
use futures_util::{SinkExt, StreamExt};
use serde_json::Value;
use tokio::sync::{mpsc, Mutex};

use crate::config::*;
use crate::auth::verify_session_token;
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

/// One shardable arena: its own simulation, its own clients, its own `/events` feed.
/// Rooms live behind an `Arc` so the per-room tick task and the connection handlers can
/// share it without holding the global room map lock during simulation.
pub struct RoomHandle {
    pub name: String,
    pub room: Mutex<Room>,
    pub clients: Mutex<HashMap<String, ClientTx>>,
    pub events_clients: Mutex<Vec<ClientTx>>,
    /// Last time a player connected or left; drives idle-room cleanup.
    pub last_active_ms: AtomicI64,
}

impl RoomHandle {
    fn new(name: &str) -> Self {
        RoomHandle {
            name: name.to_string(),
            room: Mutex::new(Room::new()),
            clients: Mutex::new(HashMap::new()),
            events_clients: Mutex::new(Vec::new()),
            last_active_ms: AtomicI64::new(now_ms()),
        }
    }
}

/// Room ids are client-supplied, so they are sanitized to a safe charset and the total
/// number of live rooms is capped to keep an abusive client from allocating unbounded
/// simulation state.
pub const DEFAULT_ROOM: &str = "default";
const MAX_ROOMS: usize = 64;
/// An empty non-default room is dropped after this long so churn does not leak rooms.
const ROOM_IDLE_TTL_MS: i64 = 120_000;

pub struct AppState {
    pub rooms: Mutex<HashMap<String, Arc<RoomHandle>>>,
    pub bans: Mutex<HashMap<String, i64>>,
    pub rate_limits: Mutex<HashMap<u64, RateLimitEntry>>,
}

#[derive(Clone)]
pub struct RateLimitEntry {
    window_start: i64,
    count: u32,
}

impl AppState {
    pub fn new() -> Self {
        AppState {
            rooms: Mutex::new(HashMap::new()),
            bans: Mutex::new(HashMap::new()),
            rate_limits: Mutex::new(HashMap::new()),
        }
    }
}

/// Coerce a client-supplied room id into a safe key. Empty/missing falls back to the
/// default room, which matches the single-room behavior clients had before sharding.
fn sanitize_room_id(raw: &str) -> String {
    let cleaned: String = raw
        .trim()
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || *c == '-' || *c == '_')
        .take(64)
        .collect();
    if cleaned.is_empty() {
        DEFAULT_ROOM.to_string()
    } else {
        cleaned
    }
}

/// Look up a room, creating (and spawning a tick task for) it on first use.
async fn get_or_create_room(state: &Arc<AppState>, name: &str) -> Option<Arc<RoomHandle>> {
    {
        let rooms = state.rooms.lock().await;
        if let Some(handle) = rooms.get(name) {
            return Some(handle.clone());
        }
    }

    let mut rooms = state.rooms.lock().await;
    // Re-check under the write lock: another connection may have created it meanwhile.
    if let Some(handle) = rooms.get(name) {
        return Some(handle.clone());
    }
    if rooms.len() >= MAX_ROOMS {
        tracing::warn!("room limit reached ({}); rejecting room {}", MAX_ROOMS, name);
        return None;
    }
    let handle = Arc::new(RoomHandle::new(name));
    rooms.insert(name.to_string(), handle.clone());
    drop(rooms);

    let tick_state = state.clone();
    let tick_handle = handle.clone();
    tokio::spawn(async move { run_room_tick(tick_state, tick_handle).await });
    tracing::info!("created room {}", name);
    Some(handle)
}

static NEXT_CONN_ID: AtomicU64 = AtomicU64::new(1);

fn next_conn_id() -> u64 {
    NEXT_CONN_ID.fetch_add(1, Ordering::Relaxed)
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
    headers: HeaderMap,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_game(socket, state, params, headers))
}

async fn ws_events(
    ws: WebSocketUpgrade,
    State(state): State<Arc<AppState>>,
    Query(params): Query<HashMap<String, String>>,
) -> impl IntoResponse {
    let room_id = sanitize_room_id(params.get("room").map(|s| s.as_str()).unwrap_or(""));
    ws.on_upgrade(move |socket| handle_events(socket, state, room_id))
}

/// `username` query param is either `<token>:<username>` or a bare `<username>`.
fn parse_username_with_token(raw: &str, token: &mut Option<String>) -> String {
    let raw = raw.trim();
    if raw.is_empty() {
        return String::new();
    }
    if let Some(idx) = raw.find(':') {
        if idx > 0 {
            let token_part = &raw[..idx];
            let name_part = &raw[idx + 1..];
            if !token_part.is_empty() {
                *token = Some(token_part.to_string());
            }
            return sanitize_username(name_part);
        }
    }
    sanitize_username(raw)
}

fn peer_ip(headers: &HeaderMap) -> String {
    if let Some(v) = headers.get("x-forwarded-for") {
        if let Ok(s) = v.to_str() {
            if let Some(first) = s.split(',').next() {
                let t = first.trim();
                if !t.is_empty() {
                    return t.to_string();
                }
            }
        }
    }
    if let Some(v) = headers.get("x-real-ip") {
        if let Ok(s) = v.to_str() {
            let t = s.trim();
            if !t.is_empty() {
                return t.to_string();
            }
        }
    }
    "unknown".to_string()
}

/// Returns `true` when the connection should be closed: either the peer IP is inside a
/// ban window, or this message pushed it past `WS_RATE_LIMIT_MAX_MESSAGES` (which also
/// starts a ban). Mirrors Node's `isRateLimited`.
async fn check_rate_limit(state: &Arc<AppState>, conn_id: u64, ip: &str) -> bool {
    let now = now_ms();
    let banned = {
        let mut bans = state.bans.lock().await;
        match bans.get(ip) {
            Some(exp) if *exp > now => true,
            Some(_) => { bans.remove(ip); false }
            None => false
        }
    };
    if banned {
        return true;
    }
    let mut limits = state.rate_limits.lock().await;
    let entry = limits.entry(conn_id).or_insert_with(|| RateLimitEntry { window_start: now, count: 0 });
    if now - entry.window_start > WS_RATE_LIMIT_WINDOW_MS {
        entry.window_start = now;
        entry.count = 0;
    }
    entry.count += 1;
    if entry.count > WS_RATE_LIMIT_MAX_MESSAGES {
        let mut bans = state.bans.lock().await;
        bans.insert(ip.to_string(), now + RATE_LIMIT_BAN_DURATION_MS);
        tracing::warn!("rate limit exceeded; banning {} for {}ms", ip, RATE_LIMIT_BAN_DURATION_MS);
        true
    } else {
        false
    }
}

async fn handle_game(mut socket: WebSocket, state: Arc<AppState>, params: HashMap<String, String>, headers: HeaderMap) {
    // Identity first: `username` may be `<token>:<name>`, and the token half must be
    // validated before any room state is touched.
    let raw_username = params.get("username").cloned().unwrap_or_default();
    let mut token: Option<String> = None;
    let mut username = parse_username_with_token(&raw_username, &mut token);
    if let Some(ref t) = token {
        if !verify_session_token(t) {
            tracing::warn!("invalid session token; rejecting");
            let _ = socket
                .send(Message::Close(Some(CloseFrame {
                    code: close_code::POLICY,
                    reason: Cow::Borrowed("invalid_token"),
                })))
                .await;
            return;
        }
    }

    let skin_param = params
        .get("skin")
        .or_else(|| params.get("skinId"))
        .cloned()
        .unwrap_or_default();
    let requested_skin = resolve_skin_name(&skin_param);

    // Pick (or lazily create) the shard this client belongs to. One process serves many
    // rooms; a client never crosses rooms because every lookup below goes through `handle`.
    let room_id = sanitize_room_id(params.get("room").map(|s| s.as_str()).unwrap_or(""));
    let handle = match get_or_create_room(&state, &room_id).await {
        Some(handle) => handle,
        None => {
            tracing::warn!("rejecting connection: room capacity exhausted");
            let _ = socket
                .send(Message::Close(Some(CloseFrame {
                    code: close_code::POLICY,
                    reason: Cow::Borrowed("server_full"),
                })))
                .await;
            return;
        }
    };

    let resume_target = params
        .get("resume")
        .map(|v| v.trim().to_string())
        .filter(|v| !v.is_empty());

    let conn_id = next_conn_id();
    let now = now_ms();
    let mut player_id = String::new();
    let mut resumed = false;

    if let Some(ref target) = resume_target {
        let ok = {
            let mut room = handle.room.lock().await;
            room.resume_player(target, &username, &requested_skin, conn_id, now)
        };
        if ok {
            player_id = target.clone();
            resumed = true;
        }
    }

    if !resumed {
        player_id = uuid::Uuid::new_v4().to_string();
        if username.is_empty() {
            username = format!("player-{}", &player_id[..8]);
        }
        // Node rejects the connection outright when the room is at capacity
        // (`currentMaxPlayers !== null && getPlayerCount() >= currentMaxPlayers`), using
        // the same value it reports as `match.maxPlayers`. `player_count` excludes
        // orphaned (resumable) players, matching the live count.
        let (full, max) = {
            let room = handle.room.lock().await;
            (room.player_count(), room.max_players)
        };
        if let Some(max) = max {
            if full >= max {
                tracing::info!("rejecting connection: room full ({}/{})", full, max);
                let _ = socket
                    .send(Message::Close(Some(CloseFrame {
                        code: close_code::POLICY,
                        reason: Cow::Borrowed("match_full"),
                    })))
                    .await;
                return;
            }
        }
        {
            let mut room = handle.room.lock().await;
            room.add_player(&player_id, &username, &requested_skin, 0, conn_id);
        }
    }

    {
        let mut clients = handle.clients.lock().await;
        if let Some(previous) = clients.remove(&player_id) {
            let _ = previous.send(Message::Close(None));
        }
    }

    let (raw_tx, rx) = mpsc::unbounded_channel::<Message>();
    let queued = Arc::new(AtomicUsize::new(0));
    let tx = ClientTx::new(raw_tx, queued.clone());

    let (connect_bytes, display_name, display_skin) = {
        let mut room = handle.room.lock().await;
        room.maybe_start_countdown();
        let (name, skin, xp) = room.player_identity(&player_id).unwrap_or_else(|| (username.clone(), requested_skin.clone(), 0));
        let bytes = encode(&ConnectMsg {
            msg_type: "connect",
            id: player_id.clone(),
            username: name.clone(),
            skin: skin.clone(),
            xp,
        });
        (bytes, name, skin)
    };
    let _ = tx.send(Message::Binary(connect_bytes));
    {
        let mut clients = handle.clients.lock().await;
        clients.insert(player_id.clone(), tx.clone());
    }
    handle.last_active_ms.store(now_ms(), Ordering::Relaxed);

    tracing::info!(
        "player {}: {} ({}) skin={} room={}{}",
        if resumed { "resumed" } else { "connected" },
        player_id,
        display_name,
        display_skin,
        handle.name,
        if resumed { " [resume]" } else { "" }
    );

    let (sender, mut receiver) = socket.split();
    let writer = tokio::spawn(drain(sender, rx, queued));

    let ip = peer_ip(&headers);

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
                        if bytes.len() > WS_MAX_MESSAGE_SIZE {
                            let _ = tx.send(Message::Close(Some(CloseFrame {
                                code: close_code::SIZE,
                                reason: Cow::Borrowed("message_too_large"),
                            })));
                            break;
                        }
                        if check_rate_limit(&state, conn_id, &ip).await {
                            let _ = tx.send(Message::Close(Some(CloseFrame {
                                code: close_code::POLICY,
                                reason: Cow::Borrowed("rate_limited"),
                            })));
                            break;
                        }
                        handle_client_message(&handle, &player_id, conn_id, &bytes).await;
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
        let mut clients = handle.clients.lock().await;
        clients.remove(&player_id);
    }
    {
        let mut rate_limits = state.rate_limits.lock().await;
        rate_limits.remove(&conn_id);
    }
    let orphaned = {
        let mut room = handle.room.lock().await;
        room.orphan_player(&player_id, conn_id, now_ms())
    };
    if !orphaned {
        let removed = {
            let mut room = handle.room.lock().await;
            room.remove_player(&player_id, now_ms())
        };
        if let Some(payload) = removed {
            broadcast_bytes(&handle, &payload).await;
        }
        tracing::info!("player disconnected: {} (room {})", player_id, handle.name);
    } else {
        tracing::info!("player disconnected, holding for resume: {} (room {})", player_id, handle.name);
    }
    handle.last_active_ms.store(now_ms(), Ordering::Relaxed);
}

async fn handle_client_message(handle: &RoomHandle, player_id: &str, conn_id: u64, bytes: &[u8]) {
    let data: Value = match rmp_serde::from_slice(bytes) {
        Ok(v) => v,
        Err(_) => return,
    };
    let msg_type = match data.get("type").and_then(|v| v.as_str()) {
        Some(t) => t.to_string(),
        None => return,
    };

    let mut room = handle.room.lock().await;
    if !room.owns_player(player_id, conn_id) {
        return;
    }
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

async fn handle_events(socket: WebSocket, state: Arc<AppState>, room_id: String) {
    let handle = match get_or_create_room(&state, &room_id).await {
        Some(handle) => handle,
        None => return,
    };

    let (raw_tx, rx) = mpsc::unbounded_channel::<Message>();
    let queued = Arc::new(AtomicUsize::new(0));
    let tx = ClientTx::new(raw_tx, queued.clone());

    let snapshot = {
        let room = handle.room.lock().await;
        room.event_history_snapshot().to_string()
    };
    tx.send(Message::Text(snapshot));

    {
        let mut events = handle.events_clients.lock().await;
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
    let mut events = handle.events_clients.lock().await;
    events.retain(|client| !client.same_channel(&tx));
}

async fn broadcast_messages(handle: &RoomHandle, messages: Vec<(String, Vec<u8>)>) {
    let clients = handle.clients.lock().await;
    for (player_id, bytes) in messages {
        if let Some(tx) = clients.get(&player_id) {
            tx.send(Message::Binary(bytes));
        }
    }
}

async fn broadcast_bytes(handle: &RoomHandle, bytes: &[u8]) {
    let clients = handle.clients.lock().await;
    for tx in clients.values() {
        tx.send(Message::Binary(bytes.to_vec()));
    }
}

async fn broadcast_events(handle: &RoomHandle, events: Vec<String>) {
    if events.is_empty() {
        return;
    }
    let mut clients = handle.events_clients.lock().await;
    // Sockets that went away leave their sender behind; sweep them here as well so the
    // list cannot grow with every reconnect.
    clients.retain(|client| !client.is_closed());
    for event in events {
        for tx in clients.iter() {
            tx.send(Message::Text(event.clone()));
        }
    }
}

async fn close_all(handle: &RoomHandle) {
    let mut clients = handle.clients.lock().await;
    for tx in clients.values() {
        tx.send(Message::Close(None));
    }
    clients.clear();
}

/// Drive one room's simulation loop. Each room gets its own task (and its own fixed-rate
/// timer), so a slow room cannot stall another room's tick — the isolation a single
/// global loop could not give.
pub async fn run_room_tick(state: Arc<AppState>, handle: Arc<RoomHandle>) {
    let mut interval = tokio::time::interval(Duration::from_millis(1000 / BROADCAST_RATE));
    loop {
        interval.tick().await;
        let now = now_ms();
        let output = {
            let mut room = handle.room.lock().await;
            room.tick(now)
        };

        if !output.messages.is_empty() {
            broadcast_messages(&handle, output.messages).await;
        }
        if !output.events.is_empty() {
            broadcast_events(&handle, output.events).await;
        }
        if output.close_all {
            tracing::info!("room {}: round finished: closing all clients", handle.name);
            close_all(&handle).await;
        }

        // Retire empty non-default rooms so client churn cannot leak simulation state.
        // `players` still holds orphans until their grace expires, which the tick above
        // reaps, so `is_empty()` only becomes true once a room is genuinely idle.
        if handle.name != DEFAULT_ROOM {
            let empty = {
                let room = handle.room.lock().await;
                room.players.is_empty()
            };
            let idle =
                now - handle.last_active_ms.load(Ordering::Relaxed) >= ROOM_IDLE_TTL_MS;
            if empty && idle {
                let mut rooms = state.rooms.lock().await;
                let ours = rooms
                    .get(&handle.name)
                    .map(|existing| Arc::ptr_eq(existing, &handle))
                    .unwrap_or(false);
                if ours {
                    rooms.remove(&handle.name);
                    tracing::info!("room {} idle; removed", handle.name);
                    return;
                }
            }
        }
    }
}
