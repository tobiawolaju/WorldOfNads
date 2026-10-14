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
