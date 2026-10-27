//! Wire protocol: MessagePack-encoded, `type`-tagged messages plus the shared
//! helpers used by the simulation. Field names match the Node server so the
//! Godot client is unchanged.

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::config::{POS_SCALE, ROT_SCALE};

// ---------------------------------------------------------------------------
// Encoding helpers
// ---------------------------------------------------------------------------

/// MessagePack-encode a struct as a map with named keys.
/// (`@msgpack/msgpack` encodes JS objects as maps, so `to_vec_named` matches.)
pub fn encode<T: Serialize>(v: &T) -> Vec<u8> {
    rmp_serde::to_vec_named(v).expect("msgpack encode")
}

pub fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

pub fn quantize_position(v: f64) -> i64 {
    (v * POS_SCALE).round() as i64
}

pub fn quantize_rotation(v: f64) -> i64 {
    (v * ROT_SCALE).round() as i64
}

pub fn dequantize_position(v: f64) -> f64 {
    v / POS_SCALE
}

pub fn dequantize_rotation(v: f64) -> f64 {
    v / ROT_SCALE
}

pub fn length3(x: f64, y: f64, z: f64) -> f64 {
    (x * x + y * y + z * z).sqrt()
}

/// Node: `String(value||'').trim().toLowerCase().replace(/\s+/g,' ')`, default `s-default`.
pub fn resolve_skin_name(value: &str) -> String {
    let key: String = value
        .trim()
        .to_lowercase()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");
    if key.is_empty() {
        "s-default".to_string()
    } else {
        key
    }
}

/// Node: `String(value||'').trim().replace(/\s+/g,' ').slice(0,24)`.
pub fn sanitize_username(value: &str) -> String {
    let cleaned: String = value
        .trim()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");
    cleaned.chars().take(24).collect()
}

/// Node: `String(value||'').trim().slice(0,220)`.
pub fn sanitize_message(value: &str) -> String {
    value.trim().chars().take(220).collect()
}

// Animation ids (server stores the name, encodes the id).
pub const ANIM_IDLE: i64 = 0;

pub fn anim_name_to_id(name: &str) -> Option<i64> {
    match name {
        "idle" => Some(0),
        "running" => Some(1),
        "runningjump" => Some(2),
        "falling" => Some(3),
        "runningslide" => Some(4),
        "climb" => Some(5),
        _ => None,
    }
}

pub fn anim_id_to_name(id: i64) -> &'static str {
    match id {
        1 => "running",
        2 => "runningjump",
        3 => "falling",
        4 => "runningslide",
        5 => "climb",
        _ => "idle",
    }
}

/// Node `normalizeAnimId`: prefer an explicit `anim_id` in 0..=5, else an
/// `animation` name, else idle.
pub fn normalize_anim_id(data: &Value) -> i64 {
    if let Some(raw) = data.get("anim_id").and_then(|v| v.as_f64()) {
        if raw.is_finite() {
            let n = raw.floor() as i64;
            if (0..=5).contains(&n) {
                return n;
            }
        }
    }
    if let Some(name) = data.get("animation").and_then(|v| v.as_str()) {
        let key = name.trim().to_lowercase();
        if let Some(id) = anim_name_to_id(&key) {
            return id;
        }
    }
    ANIM_IDLE
}

/// Match Node's `parseFloat(x.toFixed(6))` for reward floats.
pub fn round6(v: f64) -> f64 {
    format!("{:.6}", v).parse::<f64>().unwrap_or(v)
}

// ---------------------------------------------------------------------------
// Server -> client payloads
// ---------------------------------------------------------------------------

#[derive(Serialize, Clone)]
pub struct PlayerNet {
    pub id: String,
    pub x: i64,
    pub y: i64,
    pub z: i64,
    pub r: i64,
    pub a: i64,
    pub skin: String,
    /// Whole seconds of chicken possession this round. Every client needs it, not
    /// just the holder: the feed counts down "wins in N" for whoever is carrying
    /// the chicken, and the chicken label above the item shows it too.
    pub ps: i64,
    /// Username is only present in full snapshots.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub u: Option<String>,
}

#[derive(Serialize, Clone, PartialEq)]
pub struct ItemNet {
    pub i: String,
    pub x: i64,
    pub y: i64,
    pub z: i64,
    pub r: i64,
    pub h: i64,
    pub o: String,
}

#[derive(Serialize, Clone, PartialEq)]
pub struct MatchNet {
    pub t: i64,
    pub r: i64,
    pub d: i64,
    pub min: i64,
    pub max: Option<i64>,
    pub sr: i64,
    pub pl: i64,
    pub c: i64,
}

#[derive(Serialize)]
pub struct StateFull {
    #[serde(rename = "type")]
    pub msg_type: &'static str,
    pub q: i64,
    pub players: Vec<PlayerNet>,
    pub chicken: ItemNet,
    pub lootbox: ItemNet,
    pub items: Vec<ItemNet>,
    #[serde(rename = "match")]
    pub match_state: MatchNet,
}

#[derive(Serialize, Default)]
pub struct StateDelta {
    #[serde(rename = "type")]
    pub msg_type: &'static str,
    pub q: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub players: Option<Vec<PlayerNet>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub removed: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub chicken: Option<ItemNet>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lootbox: Option<ItemNet>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub items: Option<Vec<ItemNet>>,
    #[serde(skip_serializing_if = "Option::is_none", rename = "match")]
    pub match_state: Option<MatchNet>,
}

#[derive(Serialize)]
pub struct ConnectMsg {
    #[serde(rename = "type")]
    pub msg_type: &'static str,
    pub id: String,
    pub username: String,
    pub skin: String,
    pub xp: i64,
}

/// The round-end notice.
///
/// Node ends a round with a WebSocket close frame (`backend/index.js`:
/// `client.close(1000, 'round_finished')`). An HTTP edge proxy in front of the
/// room server terminates the WebSocket session itself and swallows that frame,
/// so the round end is also announced as an ordinary data frame. The Godot
/// client closes its own socket when it sees this message.
#[derive(Serialize)]
pub struct RoundFinishedMsg {
    #[serde(rename = "type")]
    pub msg_type: &'static str,
}

#[derive(Serialize)]
pub struct RewardUpdate {
    #[serde(rename = "type")]
    pub msg_type: &'static str,
    pub xp: i64,
    pub mon: f64,
    pub pool: f64,
    #[serde(rename = "holdTime")]
    pub hold_time: i64,
    #[serde(rename = "possessionTime")]
    pub possession_time: i64,
    #[serde(rename = "victoryTarget")]
    pub victory_target: i64,
}

// ---------------------------------------------------------------------------
// Client -> server payloads
// ---------------------------------------------------------------------------

/// The subset of client messages we care about. Unknown `type`s decode to
/// `Other` and are ignored. Extra fields are tolerated.
#[derive(Deserialize, Debug)]
#[serde(tag = "type")]
pub enum ClientMessage {
    #[serde(rename = "update_state")]
    UpdateState(UpdateState),
    #[serde(rename = "pickup_request")]
    PickupRequest(ItemRequest),
    #[serde(rename = "use_request")]
    UseRequest(ItemRequest),
    #[serde(rename = "drop_request")]
    DropRequest(ItemRequest),
    #[serde(rename = "request_full_state")]
    RequestFullState,
    #[serde(rename = "client_event")]
    ClientEvent(ClientEvent),
    #[serde(other)]
    Other,
}

#[derive(Deserialize, Debug, Default)]
pub struct UpdateState {
    pub qx: Option<f64>,
    pub qy: Option<f64>,
    pub qz: Option<f64>,
    pub qrot: Option<f64>,
    pub x: Option<f64>,
    pub y: Option<f64>,
    pub z: Option<f64>,
    pub rotation_y: Option<f64>,
    pub anim_id: Option<f64>,
    pub animation: Option<String>,
    pub slide: Option<bool>,
    pub skin: Option<String>,
}

#[derive(Deserialize, Debug, Default)]
pub struct ItemRequest {
    pub item_id: Option<String>,
}

#[derive(Deserialize, Debug, Default)]
pub struct ClientEvent {
    pub event_type: Option<String>,
    pub message: Option<String>,
    pub meta: Option<Value>,
}
