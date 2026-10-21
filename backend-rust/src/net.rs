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
use serde_json::{json, Value};
use tokio::sync::{mpsc, Mutex};

use crate::config::*;
use crate::auth::verify_session_token;
use crate::protocol::*;
use crate::registry::{MatchConfig, MatchLookup, MatchRegistry};
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

    /// Bytes handed to the writer task that have not been flushed yet.
    fn queued_bytes(&self) -> usize {
        self.queued.load(Ordering::Relaxed)
    }

    fn same_channel(&self, other: &Self) -> bool {
        self.tx.same_channel(&other.tx)
    }
}

/// Drain a client's queue into its socket, returning budget as frames flush out.
///
/// The counters are diagnostics only (see `/debug/rooms`): `drain_exits` counts the
/// writer tasks that stopped, `drain_write_errors` the ones that failed to hand a
/// frame to the socket. A writer that dies before the round-end close is queued
/// silently swallows that close, so both numbers are needed to tell "the close was
/// never queued" apart from "the close was queued into a dead socket".
async fn drain(
    mut sender: SplitSink<WebSocket, Message>,
    mut rx: mpsc::UnboundedReceiver<Message>,
    queued: Arc<AtomicUsize>,
    drain_exits: Arc<AtomicU64>,
    drain_write_errors: Arc<AtomicU64>,
) {
    while let Some(msg) = rx.recv().await {
        let bulk = is_bulk(&msg);
        let len = frame_len(&msg);
        if sender.send(msg).await.is_err() {
            // The socket is gone; the connection is being torn down, so the budget
            // for whatever is still queued no longer matters.
            drain_write_errors.fetch_add(1, Ordering::Relaxed);
            break;
        }
        if bulk {
            queued.fetch_sub(len, Ordering::Relaxed);
        }
    }
    drain_exits.fetch_add(1, Ordering::Relaxed);
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
    // Diagnostics, surfaced by `/debug/rooms`. Render does not expose the container
    // logs through an API, so these counters are the only way to see on a live
    // instance whether the round-end close was queued and whether the writer tasks
    // were still alive when it was.
    /// How many times the room asked every client to close.
    pub close_all_calls: AtomicU64,
    /// How many clients were connected when `close_all` ran.
    pub close_all_clients: AtomicU64,
    /// How many close frames were queued into a client channel.
    pub close_all_queued: AtomicU64,
    /// How many writer tasks stopped (socket gone or queue drained).
    pub drain_exits: AtomicU64,
    /// How many writer tasks failed to hand a frame to the socket.
    pub drain_write_errors: AtomicU64,
}

impl RoomHandle {
    fn new(name: &str, config: Option<MatchConfig>) -> Self {
        let mut room = Room::new();
        // A match room inherits the match's limits; the default room keeps the
        // process-wide defaults from `Room::new`.
        if let Some(config) = config {
            room.min_players_to_start = config.min_players_to_start;
            room.max_players = config.max_players;
        }
        RoomHandle {
            name: name.to_string(),
            room: Mutex::new(room),
            clients: Mutex::new(HashMap::new()),
            events_clients: Mutex::new(Vec::new()),
            last_active_ms: AtomicI64::new(now_ms()),
            close_all_calls: AtomicU64::new(0),
            close_all_clients: AtomicU64::new(0),
            close_all_queued: AtomicU64::new(0),
            drain_exits: AtomicU64::new(0),
            drain_write_errors: AtomicU64::new(0),
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
    /// Allocated-match mirror; a room is only created for an id found here.
    pub registry: MatchRegistry,
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
            registry: MatchRegistry::new(),
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

/// Resolve a requested room id to the room the client will actually join.
///
/// `default` always resolves to itself. Any other id is only honoured when it is an
/// allocated match (present in the registry). An id the registry can judge and finds
/// unallocated is refused; an id the registry cannot judge at all (no data yet — a cold
/// start, or a control-plane outage) falls back to `default` unless `STRICT_ROOMS` is
/// set. This is what stops an arbitrary `?room=<anything>` from spawning its own arena.
///
/// Returns `None` when the connection must be refused.
async fn resolve_room(state: &Arc<AppState>, requested: &str) -> Option<(String, Option<MatchConfig>)> {
    if requested == DEFAULT_ROOM {
        return Some((DEFAULT_ROOM.to_string(), None));
    }
    match state.registry.lookup(requested).await {
        MatchLookup::Allocated(config) => Some((requested.to_string(), Some(config))),
        // The mirror is authoritative and says no host created this id: refuse it.
        MatchLookup::Missing => {
            tracing::warn!(
                "match id {:?} is not an allocated match; refusing connection",
                requested
            );
            None
        }
        // We could not consult the mirror. Fall back so matches stay playable through a
        // cold start or a brief control-plane outage; STRICT_ROOMS refuses instead.
        MatchLookup::Unverified => {
            if strict_rooms() {
                tracing::warn!(
                    "match registry unavailable; refusing {:?} (STRICT_ROOMS)",
                    requested
                );
                None
            } else {
                tracing::warn!(
                    "match registry unavailable; routing {:?} to the {} room",
                    requested,
                    DEFAULT_ROOM
                );
                Some((DEFAULT_ROOM.to_string(), None))
            }
        }
    }
}

/// Look up a room, creating (and spawning a tick task for) it on first use.
async fn get_or_create_room(
    state: &Arc<AppState>,
    name: &str,
    config: Option<MatchConfig>,
) -> Option<Arc<RoomHandle>> {
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
    let handle = Arc::new(RoomHandle::new(name, config));
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
        .route("/debug/rooms", get(debug_rooms))
        .fallback(get(ws_game))
        .with_state(state)
}

/// Liveness probe. The first line is kept byte-identical to the old response so
/// existing checks keep working; the commit tells us which build is actually
/// serving (Render injects `RENDER_GIT_COMMIT`).
async fn health() -> String {
    let commit = std::env::var("RENDER_GIT_COMMIT").unwrap_or_else(|_| "unknown".to_string());
    format!("Server is alive and healthy!\ncommit: {}\n", commit)
}

/// Live diagnostics for the room server.
///
/// Render does not expose the container logs through an API, so this endpoint is the
/// only way to inspect a live instance: which rooms exist, who holds the chicken and
/// how much possession they have banked, whether the writer tasks are still alive,
/// and whether the round-end close was actually queued to the clients.
///
/// It exposes no secrets (ids, names and counters only) but it is not authenticated,
/// so it is a diagnostics tool for the operator - not something to expose publicly.
async fn debug_rooms(State(state): State<Arc<AppState>>) -> String {
    let mut rooms_out: Vec<Value> = Vec::new();
    let rooms = state.rooms.lock().await;
    for (name, handle) in rooms.iter() {
        // The room state is copied out before the client map is locked: the two locks
        // are never held in the opposite order anywhere else, but keeping the nesting
        // one-directional removes the question entirely.
        let room_view = {
            let room = handle.room.lock().await;
            let players: Vec<Value> = room
                .players
                .values()
                .map(|p| {
                    json!({
                        "id": p.id,
                        "name": p.username,
                        "holder": p.is_current_holder,
                        "possession_s": p.accumulated_possession,
                        "orphaned": p.orphaned_at.is_some(),
                    })
                })
                .collect();
            json!({
                "players": players,
                "match_running": room.match_running,
                "match_time_left": room.match_time_left,
                "pending_close_all": room.pending_close_all,
                "chicken_holder": room.chicken.holder_id,
            })
        };
        let client_view = {
            let clients = handle.clients.lock().await;
            let list: Vec<Value> = clients
                .iter()
                .map(|(id, tx)| {
                    json!({
                        "id": id,
                        "writer_alive": !tx.is_closed(),
                        "queued_bytes": tx.queued_bytes(),
                    })
                })
                .collect();
            json!({ "count": clients.len(), "clients": list })
        };

        let mut view = json!({
            "room": name,
            "close_all_calls": handle.close_all_calls.load(Ordering::Relaxed),
            "close_all_clients": handle.close_all_clients.load(Ordering::Relaxed),
            "close_all_queued": handle.close_all_queued.load(Ordering::Relaxed),
            "drain_exits": handle.drain_exits.load(Ordering::Relaxed),
            "drain_write_errors": handle.drain_write_errors.load(Ordering::Relaxed),
        });
        merge(&mut view, &room_view);
        merge(&mut view, &client_view);
        rooms_out.push(view);
    }
    json!({ "rooms": rooms_out }).to_string()
}

/// Merge a JSON object into another one (shallow, string keys).
fn merge(target: &mut Value, extra: &Value) {
    if let (Some(target), Some(extra)) = (target.as_object_mut(), extra.as_object()) {
        for (key, value) in extra {
            target.insert(key.clone(), value.clone());
        }
    }
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
    // `room` is the canonical param; `match` is accepted too so the Godot client
    // (which already carries `?match=<id>`) can be pointed at a room without a
    // second parameter round-trip.
    let room_id = sanitize_room_id(
        params
            .get("room")
            .or_else(|| params.get("match"))
            .map(|s| s.as_str())
            .unwrap_or(""),
    );
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
    // `room` is the canonical param; `match` is accepted too so the Godot client
    // (which already carries `?match=<id>`) can be pointed at a room without a
    // second parameter round-trip.
    let requested_room = sanitize_room_id(
        params
            .get("room")
            .or_else(|| params.get("match"))
            .map(|s| s.as_str())
            .unwrap_or(""),
    );
    // Only an allocated match (or `default`) may open a room. `resolve_room` returns
    // `None` for an unknown match id when `STRICT_ROOMS` is set; otherwise it routes
    // the client to `default`, so an arbitrary `?room=` never spawns its own arena.
    let (room_id, room_config) = match resolve_room(&state, &requested_room).await {
        Some(resolved) => resolved,
        None => {
            let _ = socket
                .send(Message::Close(Some(CloseFrame {
                    code: close_code::POLICY,
                    reason: Cow::Borrowed("unknown_match"),
                })))
                .await;
            return;
        }
    };
    let handle = match get_or_create_room(&state, &room_id, room_config).await {
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
    let writer = tokio::spawn(drain(
        sender,
        rx,
        queued,
        handle.drain_exits.clone(),
        handle.drain_write_errors.clone(),
    ));

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
                room.pickup_request(player_id, item_id, now_ms());
            }
        }
        "use_request" => {
            if let Some(item_id) = data.get("item_id").and_then(|v| v.as_str()) {
                room.use_request(player_id, item_id);
            }
        }
        "drop_request" => {
            if let Some(item_id) = data.get("item_id").and_then(|v| v.as_str()) {
                room.drop_request(player_id, item_id, now_ms());
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
            // Handle player elimination (death/respawn) -> reset possession time.
            if event_type == "eliminated" {
                room.handle_player_eliminated(player_id);
            }
        }
        _ => {}
    }
}

async fn handle_events(socket: WebSocket, state: Arc<AppState>, room_id: String) {
    let (room_id, config) = match resolve_room(&state, &room_id).await {
        Some(resolved) => resolved,
        None => return,
    };
    let handle = match get_or_create_room(&state, &room_id, config).await {
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
    let writer = tokio::spawn(drain(
        sender,
        rx,
        queued,
        handle.drain_exits.clone(),
        handle.drain_write_errors.clone(),
    ));

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
    handle.close_all_calls.fetch_add(1, Ordering::Relaxed);
    handle
        .close_all_clients
        .store(clients.len() as u64, Ordering::Relaxed);
    let mut queued = 0u64;
    for tx in clients.values() {
        // Node closes the round with code 1000 and the reason `round_finished`
        // (`backend/index.js`: `client.close(1000, 'round_finished')`), so the
        // Godot client sees the same thing it saw against the Node server.
        if tx.send(Message::Close(Some(CloseFrame {
            code: close_code::NORMAL,
            reason: Cow::Borrowed("round_finished"),
        }))) {
            queued += 1;
        }
    }
    handle.close_all_queued.store(queued, Ordering::Relaxed);
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

#[cfg(test)]
mod tests {
    use super::*;
    use futures_util::StreamExt;
    use tokio::net::TcpStream;
    use tokio_tungstenite::connect_async;
    use tokio_tungstenite::tungstenite::Message as WsMessage;
    use tokio_tungstenite::{MaybeTlsStream, WebSocketStream};

    type TestSocket = WebSocketStream<MaybeTlsStream<TcpStream>>;

    /// Read frames until the server closes the socket; return the close frame.
    async fn wait_for_close(socket: &mut TestSocket, timeout: Duration) -> Option<(u16, String)> {
        let deadline = tokio::time::Instant::now() + timeout;
        while tokio::time::Instant::now() < deadline {
            match tokio::time::timeout(timeout, socket.next()).await {
                Ok(Some(Ok(WsMessage::Close(frame)))) => {
                    return frame.map(|f| (u16::from(f.code), f.reason.to_string()));
                }
                Ok(Some(Ok(_))) => continue,
                Ok(Some(Err(err))) => panic!("websocket error while waiting for close: {}", err),
                Ok(None) => return None,
                Err(_) => return None,
            }
        }
        None
    }

    /// The server greets every game socket with the msgpack `connect` frame.
    async fn expect_connect(socket: &mut TestSocket) {
        let first = tokio::time::timeout(Duration::from_secs(5), socket.next())
            .await
            .expect("connect frame timeout")
            .expect("the socket ended early")
            .expect("websocket error");
        assert!(
            matches!(first, WsMessage::Binary(_)),
            "expected the msgpack connect frame"
        );
    }

    /// A finished round must actually reach the client as a close frame.
    ///
    /// Node closes every game socket with code 1000 and the reason
    /// `round_finished` when the round ends, and the Godot client relies on
    /// that to leave the finished round instead of sitting in a ghost session
    /// with a socket the server no longer knows about.
    #[tokio::test]
    async fn closing_the_room_reaches_the_client_as_a_close_frame() {
        let state = Arc::new(AppState::new());
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app = router(state.clone());
        tokio::spawn(async move {
            let _ = axum::serve(listener, app).await;
        });

        let (mut socket, _) = connect_async(format!(
            "ws://{}/?room=default&username=tester&skin=s-default",
            addr
        ))
        .await
        .expect("the client must connect");

        // The server greets with the msgpack `connect` frame.
        let first = tokio::time::timeout(Duration::from_secs(5), socket.next())
            .await
            .expect("connect frame timeout")
            .expect("the socket ended early")
            .expect("websocket error");
        assert!(
            matches!(first, WsMessage::Binary(_)),
            "expected the msgpack connect frame"
        );

        let handle = {
            let rooms = state.rooms.lock().await;
            rooms.get(DEFAULT_ROOM).cloned().expect("room handle")
        };

        // Wait until the client is registered in the room's client map.
        let mut registered = false;
        for _ in 0..200 {
            if !handle.clients.lock().await.is_empty() {
                registered = true;
                break;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        assert!(registered, "the client must be registered in the room");

        close_all(&handle).await;

        // The client must see the close frame, with Node's code and reason.
        let mut closed = false;
        let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
        while tokio::time::Instant::now() < deadline {
            match tokio::time::timeout(Duration::from_secs(2), socket.next()).await {
                Ok(Some(Ok(WsMessage::Close(frame)))) => {
                    if let Some(frame) = frame {
                        assert_eq!(u16::from(frame.code), 1000);
                        assert_eq!(frame.reason, "round_finished");
                    }
                    closed = true;
                    break;
                }
                Ok(Some(Ok(_))) => continue,
                Ok(Some(Err(err))) => panic!("websocket error while waiting for close: {}", err),
                Ok(None) => break,
                Err(_) => continue,
            }
        }
        assert!(closed, "the client must receive a close frame when the round ends");
    }

    /// The whole round-end path, end to end.
    ///
    /// The test above covers `close_all` in isolation. This one drives the real
    /// path: two clients join, the room starts a match, a player banks enough
    /// possession to win it, and the room tick must then close BOTH sockets with
    /// Node's code and reason. A close that is only queued but never reaches the
    /// socket (a dead writer task, a saturated queue) is invisible to the unit
    /// test, so this is the regression that actually matters for the client.
    #[tokio::test]
    async fn a_won_round_closes_every_connected_client() {
        let state = Arc::new(AppState::new());
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let app = router(state.clone());
        tokio::spawn(async move {
            let _ = axum::serve(listener, app).await;
        });

        let (mut alpha, _) = connect_async(format!(
            "ws://{}/?room=default&username=alpha&skin=s-default",
            addr
        ))
        .await
        .expect("alpha must connect");
        let (mut bravo, _) = connect_async(format!(
            "ws://{}/?room=default&username=bravo&skin=s-default",
            addr
        ))
        .await
        .expect("bravo must connect");
        expect_connect(&mut alpha).await;
        expect_connect(&mut bravo).await;

        let handle = {
            let rooms = state.rooms.lock().await;
            rooms.get(DEFAULT_ROOM).cloned().expect("room handle")
        };

        // Two players, then the start countdown, then the match.
        let mut started = false;
        for _ in 0..600 {
            {
                let room = handle.room.lock().await;
                if room.match_running && room.player_count() >= 2 {
                    started = true;
                }
            }
            if started {
                break;
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
        assert!(started, "the match must start once two players are in the room");

        // Bank almost a full minute of possession for one player; the next reward
        // tick pushes it over the 60 second victory line.
        {
            let mut room = handle.room.lock().await;
            let pid = room.players.keys().next().cloned().expect("a player");
            let player = room.players.get_mut(&pid).expect("the player");
            player.is_current_holder = true;
            player.accumulated_possession = 59.5;
            player.possession_since_ms = Some(now_ms());
            room.chicken.is_held = true;
            room.chicken.holder_id = Some(pid);
        }

        // Both sockets must be closed by the server.
        let (code, reason) = wait_for_close(&mut alpha, Duration::from_secs(30))
            .await
            .expect("alpha must be closed when the round ends");
        assert_eq!(code, 1000);
        assert_eq!(reason, "round_finished");
        let (code, reason) = wait_for_close(&mut bravo, Duration::from_secs(30))
            .await
            .expect("bravo must be closed when the round ends");
        assert_eq!(code, 1000);
        assert_eq!(reason, "round_finished");

        // And the close must have been queued to every connected client.
        assert_eq!(handle.close_all_calls.load(Ordering::Relaxed), 1);
        assert_eq!(handle.close_all_clients.load(Ordering::Relaxed), 2);
        assert_eq!(handle.close_all_queued.load(Ordering::Relaxed), 2);
        assert_eq!(
            handle.drain_write_errors.load(Ordering::Relaxed),
            0,
            "no writer task may fail to hand the close to the socket"
        );
    }
}
