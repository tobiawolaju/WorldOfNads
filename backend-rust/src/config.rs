//! Simulation/network constants. These mirror `backend/index.js` exactly so the
//! Rust room server produces byte-compatible frames.

pub const PORT: u16 = 8080;

pub const BROADCAST_RATE: u64 = 20;
pub const FIXED_DT: f64 = 1.0 / 20.0;

// Distance-banded replication rates (players).
pub const NEAR_UPDATE_RATE: f64 = 20.0;
pub const MEDIUM_UPDATE_RATE: f64 = 15.0;
pub const FAR_UPDATE_RATE: f64 = 6.0;
pub const NEAR_UPDATE_DISTANCE: f64 = 12.0;
pub const MEDIUM_UPDATE_DISTANCE: f64 = 28.0;

// Area-of-interest grid.
pub const CELL_SIZE: f64 = 18.0;
pub const CELL_REPLICATION_RADIUS: i32 = 3;

pub const FULL_SNAPSHOT_INTERVAL_MS: i64 = 2000;
pub const MATCH_HEARTBEAT_INTERVAL_MS: i64 = 1000;

// Quantization.
pub const POS_SCALE: f64 = 100.0; // centimeters
pub const ROT_SCALE: f64 = 1000.0; // milliradians

pub const MAX_CLIENT_BUFFERED_BYTES: usize = 512 * 1024;

// Websocket limits.
pub const WS_RATE_LIMIT_WINDOW_MS: i64 = 1000;
pub const WS_RATE_LIMIT_MAX_MESSAGES: u32 = 60;
pub const WS_MAX_MESSAGE_SIZE: usize = 4096;
pub const RATE_LIMIT_BAN_DURATION_MS: i64 = 60000;

// Heartbeat sweep. Node pings each game socket every `GAME_HEARTBEAT_INTERVAL_MS` and
// terminates any socket that missed the previous pong, so a client that disappears
// without a clean close does not linger as a frozen player.
pub const GAME_HEARTBEAT_INTERVAL_MS: u64 = 30_000;

// Reconnect grace. A dropped socket keeps its player for this long, so a client that
// reconnects (Godot reconnects in ~4–9 s) can resume the same entity (same position,
// same held items, same id) instead of arriving as a second player. While the player
// is orphaned, their avatar is hidden from everyone and they are not counted in
// `match.pl`. Node has no equivalent; this is a UX improvement for bad networks.
pub const RECONNECT_GRACE_MS: i64 = 20_000;

// Movement validation.
pub const MAX_PLAYER_SPEED: f64 = 12.0;
pub const MAX_PLAYER_VERTICAL_SPEED: f64 = 36.0;
pub const MAX_THROW_IMPULSE: f64 = 8.0;
pub const CHICKEN_GRAVITY: f64 = 14.0;
pub const FLOOR_Y: f64 = 1.195;

// Match.
pub const MATCH_DURATION_SECONDS: f64 = 180.0;
pub const DEFAULT_MIN_PLAYERS_TO_START: usize = 2;
pub const MATCH_START_COUNTDOWN_SECONDS: f64 = 5.0;

// Storm.
pub const STORM_START_RADIUS: f64 = 20.0;
pub const STORM_SHRINK_INTERVAL: f64 = 20.0;
pub const STORM_SHRINK_DURATION: f64 = 5.0;
pub const STORM_SHRINK_STEP: f64 = 2.0;
pub const STORM_MIN_RADIUS: f64 = 3.0;

// Rewards.
pub const XP_PER_SEC: f64 = 10.0;
pub const XP_CHICKEN_RADIUS: f64 = 8.0;
pub const REWARD_TICK_INTERVAL_SEC: f64 = 1.0;
pub const TOTAL_MON_POOL_PER_MATCH: f64 = 1.0;
pub const MON_PER_SEC: f64 = 0.002;

// Item spawns.
pub const ARENA_HALF_SIZE: f64 = 35.0;
pub const ITEM_SPAWN_MARGIN: f64 = 4.0;

// Events feed.
pub const MAX_EVENT_HISTORY: usize = 100;

pub const POWER_UP_IDS: [&str; 5] = ["p1", "p2", "p3", "p4", "p5"];

/// Capacity of the room, mirroring Node's `currentMaxPlayers`.
///
/// `None` means unlimited, which is Node's default (`let currentMaxPlayers = null`).
/// Set `MAX_PLAYERS=N` to reject further connections with a `1008 match_full` close
/// (Node takes this value from its matchmaker/DB instead of the environment);
/// `MAX_PLAYERS=unlimited`, or leaving it unset, keeps the room open.
pub fn max_players() -> Option<usize> {
    let raw = std::env::var("MAX_PLAYERS").ok()?;
    let value = raw.trim();
    if value.is_empty() || value.eq_ignore_ascii_case("unlimited") {
        return None;
    }
    match value.parse::<usize>() {
        Ok(parsed) if parsed > 0 => Some(parsed),
        _ => {
            tracing::warn!(
                "ignoring invalid MAX_PLAYERS={:?} (expected a positive integer or \"unlimited\")",
                raw
            );
            None
        }
    }
}

// ─── Allocated-match registry ───
//
// A room may only exist for a match a host actually created. Hosts create matches
// in the control plane (sponsor dashboard -> Firebase); the Node backend mirrors
// that list at `GET /internal/matches`, and this room server pulls it so that an
// arbitrary `?room=<anything>` cannot spawn an arena. See `registry.rs`.

/// Control-plane (Node) base URL the registry is mirrored from.
pub fn control_plane_url() -> String {
    std::env::var("CONTROL_PLANE_URL")
        .ok()
        .map(|v| v.trim().trim_end_matches('/').to_string())
        .filter(|v| !v.is_empty())
        .unwrap_or_else(|| "https://worldofnads.onrender.com".to_string())
}

/// Shared secret for the control plane's `/internal/*` endpoints. When the control
/// plane leaves its own `INTERNAL_SECRET` unset it accepts any value, so an empty
/// secret still works in development; set the same value on both services to lock
/// the endpoint down.
pub fn internal_secret() -> String {
    std::env::var("INTERNAL_SECRET").unwrap_or_default()
}

/// Shared secret the control plane signs session tokens with. `None` means this side
/// accepts any well-formed token (see `auth.rs`), matching how the control plane treats
/// an unset `INTERNAL_SECRET`: play keeps working while the two services are not yet
/// configured together. Set the same value on both services to actually enforce it.
pub fn session_token_secret() -> Option<String> {
    std::env::var("SESSION_TOKEN_SECRET")
        .ok()
        .map(|v| v.trim().to_string())
        .filter(|v| !v.is_empty())
}

/// How long a mirrored match-list snapshot is trusted before it is re-fetched.
///
/// A short TTL means the control plane is polled constantly (15 s worked out at ~5.8k
/// requests a day, which drew a 429 from the free instance). A join for an id the mirror
/// does not know forces a refresh immediately regardless, so a freshly created match is
/// still joinable within seconds; this only bounds how long a *limit change* takes to
/// land.
pub const MATCH_REGISTRY_TTL_MS: i64 = 60_000;

/// When the registry cannot judge a `room` id at all (it holds no data yet — e.g. right
/// after a cold start, or during a control-plane outage), `false` routes the client to
/// the shared `default` room and `true` refuses the connection. An id the registry *can*
/// judge and finds unallocated is always refused. Either way a non-existent match id can
/// never spawn its own room.
pub fn strict_rooms() -> bool {
    std::env::var("STRICT_ROOMS")
        .map(|v| matches!(v.trim().to_ascii_lowercase().as_str(), "1" | "true" | "yes"))
        .unwrap_or(false)
}
