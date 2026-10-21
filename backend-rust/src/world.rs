//! The single-room arena simulation. Mirrors `backend/index.js` behaviour
//! (AOI replication, movement validation, storm, rewards, item holds, match
//! lifecycle) so the produced frames match the Node server.

use std::collections::{HashMap, HashSet};

use chrono;
use rand::Rng;
use serde_json::{json, Value};

use crate::config::*;
use crate::protocol::*;

#[derive(Clone)]
pub struct Reward {
    pub accumulated_xp: f64,
    pub accumulated_mon: f64,
    pub chicken_hold_time: i64,
}

#[derive(Clone)]
pub struct Player {
    pub id: String,
    pub username: String,
    pub skin: String,
    pub x: f64,
    pub y: f64,
    pub z: f64,
    pub rotation_y: f64,
    pub animation: String,
    pub xp: i64,
    pub last_update_ms: i64,
    pub cell_key: String,
    pub conn_id: u64,
    pub orphaned_at: Option<i64>,
    pub reward: Reward,
    // New possession-time tracking (authoritative on server).
    pub accumulated_possession: f64,     // Total seconds this player has held the chicken.
    pub is_current_holder: bool,         // Whether this player currently holds the chicken.
}

#[derive(Clone)]
pub struct Item {
    pub id: String,
    pub x: f64,
    pub y: f64,
    pub z: f64,
    pub rotation_y: f64,
    pub is_held: bool,
    pub holder_id: Option<String>,
    pub vx: f64,
    pub vy: f64,
    pub vz: f64,
}

impl Item {
    fn new(id: &str) -> Self {
        Item {
            id: id.to_string(),
            x: 0.0,
            y: FLOOR_Y,
            z: 0.0,
            rotation_y: 0.0,
            is_held: false,
            holder_id: None,
            vx: 0.0,
            vy: 0.0,
            vz: 0.0,
        }
    }
}

pub struct RecipientState {
    pub last_sent_players: HashMap<String, PlayerNet>,
    pub last_sent_player_at: HashMap<String, i64>,
    pub last_sent_chicken: Option<ItemNet>,
    pub last_sent_lootbox: Option<ItemNet>,
    pub last_sent_items: Option<Vec<ItemNet>>,
    pub last_sent_match: Option<MatchNet>,
    pub last_full_snapshot_at: i64,
    pub last_match_heartbeat_at: i64,
}

impl RecipientState {
    fn new() -> Self {
        RecipientState {
            last_sent_players: HashMap::new(),
            last_sent_player_at: HashMap::new(),
            last_sent_chicken: None,
            last_sent_lootbox: None,
            last_sent_items: None,
            last_sent_match: None,
            last_full_snapshot_at: 0,
            last_match_heartbeat_at: 0,
        }
    }
}

#[derive(Default)]
pub struct TickOutput {
    /// (recipient player id, msgpack bytes)
    pub messages: Vec<(String, Vec<u8>)>,
    /// Ready-to-send JSON strings for the `/events` feed.
    pub events: Vec<String>,
    pub close_all: bool,
}

pub struct Room {
    pub players: HashMap<String, Player>,
    pub chicken: Item,
    pub lootbox: Item,
    pub power_ups: HashMap<String, Item>,
    pub player_cell_index: HashMap<String, String>,
    pub cell_occupants: HashMap<String, HashSet<String>>,
    pub recipient_state: HashMap<String, RecipientState>,
    pub event_history: Vec<Value>,
    pub event_sequence: i64,
    pub pending_events: Vec<String>,
    pub pending_reward_msgs: Vec<(String, Vec<u8>)>,
    pub match_time_left: f64,
    pub match_running: bool,
    pub match_started_this_round: bool,
    pub min_players_to_start: usize,
    pub max_players: Option<usize>,
    pub match_start_countdown: f64,
    pub storm_radius: f64,
    pub storm_shrink_timer: f64,
    pub storm_is_shrinking: bool,
    pub storm_shrink_progress: f64,
    pub storm_start_radius: f64,
    pub storm_target_radius: f64,
    pub reward_accumulator: f64,
    pub batch_reset_until_ms: i64,
    pub pending_close_all: bool,
}

impl Room {
    pub fn new() -> Self {
        let mut power_ups = HashMap::new();
        for id in POWER_UP_IDS {
            power_ups.insert(id.to_string(), Item::new(id));
        }
        let mut room = Room {
            players: HashMap::new(),
            chicken: Item::new("Chicken"),
            lootbox: Item::new("LootBox"),
            power_ups,
            player_cell_index: HashMap::new(),
            cell_occupants: HashMap::new(),
            recipient_state: HashMap::new(),
            event_history: Vec::new(),
            event_sequence: 0,
            pending_events: Vec::new(),
            pending_reward_msgs: Vec::new(),
            match_time_left: MATCH_DURATION_SECONDS,
            match_running: false,
            match_started_this_round: false,
            min_players_to_start: DEFAULT_MIN_PLAYERS_TO_START,
            // Node keeps one `currentMaxPlayers` for both the connect-time guard and
            // `buildMatchState().maxPlayers`; read it once so the two stay in step.
            // Unset or `unlimited` means no cap, which is Node's default.
            max_players: max_players(),
            match_start_countdown: -1.0,
            storm_radius: STORM_START_RADIUS,
            storm_shrink_timer: 0.0,
            storm_is_shrinking: false,
            storm_shrink_progress: 0.0,
            storm_start_radius: STORM_START_RADIUS,
            storm_target_radius: STORM_START_RADIUS,
            reward_accumulator: 0.0,
            batch_reset_until_ms: 0,
            pending_close_all: false,
        };
        room.randomize_all_item_spawns();
        room
    }

    pub fn player_count(&self) -> usize {
        self.players.values().filter(|p| p.orphaned_at.is_none()).count()
    }

    pub fn event_history_snapshot(&self) -> Value {
        json!({ "type": "events_snapshot", "events": self.event_history })
    }

    // -- players -----------------------------------------------------------

    pub fn add_player(&mut self, id: &str, username: &str, skin: &str, xp: i64, conn_id: u64) {
        let player = Player {
            id: id.to_string(),
            username: username.to_string(),
            skin: skin.to_string(),
            x: 0.0,
            y: 0.0,
            z: 0.0,
            rotation_y: 0.0,
            animation: "idle".to_string(),
            xp,
            last_update_ms: now_ms(),
            cell_key: String::new(),
            conn_id,
            orphaned_at: None,
            reward: Reward {
                accumulated_xp: 0.0,
                accumulated_mon: 0.0,
                chicken_hold_time: 0,
            },
            accumulated_possession: 0.0,
            is_current_holder: false,
        };
        self.players.insert(id.to_string(), player);
        self.update_player_cell_index(id);
        self.recipient_state
            .insert(id.to_string(), RecipientState::new());
    }

    pub fn maybe_start_countdown(&mut self) {
        if !self.match_running
            && self.match_start_countdown < 0.0
            && self.player_count() >= self.min_players_to_start
        {
            self.match_start_countdown = MATCH_START_COUNTDOWN_SECONDS;
        }
    }

    /// Returns a `state_delta { removed: [...] }` frame to broadcast, or `None`
    /// during a batch reset (everyone is being closed anyway).
    pub fn remove_player(&mut self, id: &str, now: i64) -> Option<Vec<u8>> {
        if !self.players.contains_key(id) {
            return None;
        }
        self.drop_held_items_at_player(id);
        let player = self.players.remove(id).unwrap();
        self.remove_from_cell_index(id);
        self.recipient_state.remove(id);

        if now < self.batch_reset_until_ms {
            return None;
        }

        self.publish_event(
            "player_left",
            &format!("{} left the game", player.username),
            id,
            &json!({}),
        );

        for state in self.recipient_state.values_mut() {
            state.last_sent_players.remove(id);
            state.last_sent_player_at.remove(id);
        }

        if !self.match_started_this_round && self.player_count() < self.min_players_to_start {
            self.match_running = false;
            self.match_time_left = MATCH_DURATION_SECONDS;
            self.match_start_countdown = -1.0;
        }

        let delta = StateDelta {
            msg_type: "state_delta",
            q: 1,
            removed: Some(vec![id.to_string()]),
            ..Default::default()
        };
        Some(encode(&delta))
    }

    // -- cell index --------------------------------------------------------

    fn update_player_cell_index(&mut self, id: &str) {
        let player = match self.players.get(id) {
            Some(p) => p,
            None => return,
        };
        let (cx, cz) = get_cell_coords(player.x, player.z);
        let next_key = get_cell_key(cx, cz);
        let previous = self.player_cell_index.get(id).cloned();

        if previous.as_deref() == Some(next_key.as_str()) {
            return;
        }
        if let Some(prev) = previous {
            if let Some(occupants) = self.cell_occupants.get_mut(&prev) {
                occupants.remove(id);
                if occupants.is_empty() {
                    self.cell_occupants.remove(&prev);
                }
            }
        }
        self.cell_occupants
            .entry(next_key.clone())
            .or_default()
            .insert(id.to_string());
        self.player_cell_index
            .insert(id.to_string(), next_key.clone());
        if let Some(p) = self.players.get_mut(id) {
            p.cell_key = next_key;
        }
    }

    fn remove_from_cell_index(&mut self, id: &str) {
        if let Some(previous) = self.player_cell_index.remove(id) {
            if let Some(occupants) = self.cell_occupants.get_mut(&previous) {
                occupants.remove(id);
                if occupants.is_empty() {
                    self.cell_occupants.remove(&previous);
                }
            }
        }
    }

    // -- items -------------------------------------------------------------

    fn item_mut(&mut self, item_id: &str) -> Option<&mut Item> {
        if item_id == "Chicken" {
            return Some(&mut self.chicken);
        }
        if item_id == "LootBox" {
            return Some(&mut self.lootbox);
        }
        if POWER_UP_IDS.iter().any(|x| *x == item_id) {
            return self.power_ups.get_mut(item_id);
        }
        None
    }

    fn place_item_at_random_spawn(item: &mut Item) {
        let (x, y, z, rot) = random_item_spawn_point();
        item.x = x;
        item.y = y;
        item.z = z;
        item.rotation_y = rot;
        item.vx = 0.0;
        item.vy = 0.0;
        item.vz = 0.0;
    }

    fn randomize_all_item_spawns(&mut self) {
        for id in POWER_UP_IDS {
            if let Some(item) = self.power_ups.get_mut(id) {
                item.is_held = false;
                item.holder_id = None;
                Self::place_item_at_random_spawn(item);
            }
        }
        self.chicken.is_held = false;
        self.chicken.holder_id = None;
        Self::place_item_at_random_spawn(&mut self.chicken);
        self.lootbox.is_held = false;
        self.lootbox.holder_id = None;
        Self::place_item_at_random_spawn(&mut self.lootbox);
    }

    fn reset_chicken_state(&mut self) {
        self.chicken.is_held = false;
        self.chicken.holder_id = None;
        self.chicken.vx = 0.0;
        self.chicken.vy = 0.0;
        self.chicken.vz = 0.0;
    }

    fn reset_lootbox_state(&mut self) {
        self.lootbox.is_held = false;
        self.lootbox.holder_id = None;
        self.lootbox.vx = 0.0;
        self.lootbox.vy = 0.0;
        self.lootbox.vz = 0.0;
    }

    fn drop_held_items_at_player(&mut self, holder_id: &str) {
        let (px, py, pz) = match self.players.get(holder_id) {
            Some(p) => (p.x, p.y, p.z),
            None => (0.0, 0.0, 0.0),
        };
        let holder_exists = self.players.contains_key(holder_id);
        let mut ids: Vec<String> = vec!["Chicken".to_string(), "LootBox".to_string()];
        for id in POWER_UP_IDS {
            ids.push(id.to_string());
        }
        for id in ids {
            let matches_holder = self
                .item_mut(&id)
                .map(|item| item.holder_id.as_deref() == Some(holder_id))
                .unwrap_or(false);
            if !matches_holder {
                continue;
            }
            if let Some(item) = self.item_mut(&id) {
                // Chicken holder dies/disconnects -> reset their accumulated possession.
                if id == "Chicken" {
                    if let Some(holder) = self.players.get_mut(holder_id) {
                        holder.accumulated_possession = 0.0;
                        holder.is_current_holder = false;
                    }
                }
                item.is_held = false;
                item.holder_id = None;
                if holder_exists {
                    item.x = px;
                    item.y = py;
                    item.z = pz;
                }
                item.vx = 0.0;
                item.vy = 0.0;
                item.vz = 0.0;
            }
        }
    }

    // -- client messages ---------------------------------------------------

    pub fn owns_player(&self, id: &str, conn_id: u64) -> bool {
        self.players.get(id).map(|p| p.orphaned_at.is_none() && p.conn_id == conn_id).unwrap_or(false)
    }

    pub fn orphan_player(&mut self, id: &str, conn_id: u64, now: i64) -> bool {
        let owns = match self.players.get(id) {
            Some(p) => p.orphaned_at.is_none() && p.conn_id == conn_id,
            None => return false,
        };
        if !owns {
            return false;
        }
        self.drop_held_items_at_player(id);
        self.remove_from_cell_index(id);
        if let Some(p) = self.players.get_mut(id) {
            p.orphaned_at = Some(now + RECONNECT_GRACE_MS);
            p.animation = "idle".to_string();
        }
        true
    }

    pub fn resume_player(&mut self, id: &str, username: &str, skin: &str, conn_id: u64, now: i64) -> bool {
        match self.players.get_mut(id) {
            Some(p) => {
                if !username.is_empty() {
                    p.username = username.to_string();
                }
                if !skin.is_empty() {
                    p.skin = skin.to_string();
                }
                p.conn_id = conn_id;
                p.orphaned_at = None;
                p.last_update_ms = now;
            }
            None => return false,
        }
        self.update_player_cell_index(id);
        true
    }

    pub fn player_identity(&self, id: &str) -> Option<(String, String, i64)> {
        self.players.get(id).map(|p| (p.username.clone(), p.skin.clone(), p.xp))
    }

    pub fn apply_update_state(&mut self, id: &str, data: &Value) {
        if !self.players.contains_key(id) {
            return;
        }
        let has_q = data.get("qx").and_then(|v| v.as_f64()).is_some()
            && data.get("qy").and_then(|v| v.as_f64()).is_some()
            && data.get("qz").and_then(|v| v.as_f64()).is_some();

        let nx = if has_q {
            dequantize_position(data.get("qx").and_then(|v| v.as_f64()).unwrap_or(f64::NAN))
        } else {
            data.get("x").and_then(|v| v.as_f64()).unwrap_or(f64::NAN)
        };
        let ny = if has_q {
            dequantize_position(data.get("qy").and_then(|v| v.as_f64()).unwrap_or(f64::NAN))
        } else {
            data.get("y").and_then(|v| v.as_f64()).unwrap_or(f64::NAN)
        };
        let nz = if has_q {
            dequantize_position(data.get("qz").and_then(|v| v.as_f64()).unwrap_or(f64::NAN))
        } else {
            data.get("z").and_then(|v| v.as_f64()).unwrap_or(f64::NAN)
        };

        let nrot = if let Some(qrot) = data.get("qrot").and_then(|v| v.as_f64()) {
            dequantize_rotation(qrot)
        } else {
            data.get("rotation_y")
                .and_then(|v| v.as_f64())
                .unwrap_or(f64::NAN)
        };

        if !nx.is_finite() || !ny.is_finite() || !nz.is_finite() || !nrot.is_finite() {
            return;
        }

        let anim_id = normalize_anim_id(data);
        let is_sliding = data.get("slide").and_then(|v| v.as_bool()).unwrap_or(false)
            || anim_id == 4
            || data
                .get("animation")
                .and_then(|v| v.as_str())
                .map(|a| a.trim().to_lowercase() == "runningslide")
                .unwrap_or(false);

        let now = now_ms();
        let player = self.players.get_mut(id).unwrap();
        let elapsed = ((now - player.last_update_ms) as f64 / 1000.0).min(0.5);
        player.last_update_ms = now;

        let dx = nx - player.x;
        let dy = ny - player.y;
        let dz = nz - player.z;
        let step_scale = elapsed.max(FIXED_DT);
        let max_horizontal = MAX_PLAYER_SPEED * step_scale * if is_sliding { 1.75 } else { 1.0 };
        let max_vertical = MAX_PLAYER_VERTICAL_SPEED * step_scale;

        let horizontal_dist = (dx * dx + dz * dz).sqrt();
        if horizontal_dist <= max_horizontal || horizontal_dist == 0.0 {
            player.x = nx;
            player.z = nz;
        } else {
            let scale = max_horizontal / horizontal_dist;
            player.x += dx * scale;
            player.z += dz * scale;
        }

        if dy.abs() <= max_vertical || dy == 0.0 {
            player.y = ny;
        } else {
            player.y += dy.signum() * max_vertical;
        }

        player.rotation_y = nrot;
        player.animation = anim_id_to_name(anim_id).to_string();
        if let Some(skin) = data.get("skin").and_then(|v| v.as_str()) {
            player.skin = resolve_skin_name(skin);
        }

        self.update_player_cell_index(id);
    }

    pub fn pickup_request(&mut self, id: &str, item_id: &str) {
        let id = id.to_string();
        // First, get the item and check if it's already held by this player.
        let (prev_holder_id, already_held_by_this_player) = {
            let item = match self.item_mut(item_id) {
                Some(item) => item,
                None => return,
            };
            if item.is_held && item.holder_id.as_deref() == Some(id.as_str()) {
                return;
            }
            (item.holder_id.clone(), false)
        };

        // Handle chicken holder transfer - update previous holder.
        if item_id == "Chicken" {
            if let Some(prev_holder_id) = prev_holder_id {
                if let Some(prev) = self.players.get_mut(&prev_holder_id) {
                    prev.is_current_holder = false;
                }
            }
            // Start accumulation for new holder.
            if let Some(new_holder) = self.players.get_mut(&id) {
                new_holder.is_current_holder = true;
            }
        }

        // Now update the item state.
        if let Some(item) = self.item_mut(item_id) {
            item.is_held = true;
            item.holder_id = Some(id);
        }
    }

    pub fn use_request(&mut self, id: &str, item_id: &str) {
        if !POWER_UP_IDS.iter().any(|x| *x == item_id) {
            return;
        }
        let allowed = self
            .power_ups
            .get(item_id)
            .map(|item| item.is_held && item.holder_id.as_deref() == Some(id))
            .unwrap_or(false);
        if !allowed {
            return;
        }
        if let Some(item) = self.power_ups.get_mut(item_id) {
            item.is_held = false;
            item.holder_id = None;
            Self::place_item_at_random_spawn(item);
        }
    }

    pub fn drop_request(&mut self, id: &str, item_id: &str) {
        let (px, py, pz) = match self.players.get(id) {
            Some(p) => (p.x, p.y, p.z),
            None => return,
        };
        
        // Check if allowed first (without holding the item mutably).
        let allowed = {
            let item = match self.item_mut(item_id) {
                Some(item) => item,
                None => return,
            };
            item.is_held && item.holder_id.as_deref() == Some(id)
        };
        if !allowed {
            return;
        }

        // Handle chicken holder drop - update player state.
        if item_id == "Chicken" {
            if let Some(holder) = self.players.get_mut(id) {
                holder.is_current_holder = false;
            }
        }

        // Now update the item state.
        if let Some(item) = self.item_mut(item_id) {
            item.is_held = false;
            item.holder_id = None;
            item.x = px;
            item.y = py;
            item.z = pz;
            item.vx = 0.0;
            item.vy = 0.0;
            item.vz = 0.0;
        }
    }

    /// Called when a player is eliminated (dies and respawns).
    /// Resets their accumulated possession time to zero per the new rules.
    pub fn handle_player_eliminated(&mut self, player_id: &str) {
        if let Some(player) = self.players.get_mut(player_id) {
            player.accumulated_possession = 0.0;
            // If they were holding the chicken, drop it.
            if player.is_current_holder {
                player.is_current_holder = false;
                if self.chicken.is_held && self.chicken.holder_id.as_deref() == Some(player_id) {
                    self.reset_chicken_state();
                }
            }
        }
    }

    pub fn request_full_state(&mut self, id: &str) {
        if let Some(state) = self.recipient_state.get_mut(id) {
            state.last_full_snapshot_at = 0;
        }
    }

    // -- events ------------------------------------------------------------

    pub fn publish_event(
        &mut self,
        event_type: &str,
        message: &str,
        player_id: &str,
        meta: &Value,
    ) {
        self.event_sequence += 1;
        let event = json!({
            "id": self.event_sequence,
            "eventType": event_type,
            "message": message,
            "playerId": player_id,
            "timestamp": chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true),
            "meta": meta,
        });
        self.event_history.push(event.clone());
        if self.event_history.len() > MAX_EVENT_HISTORY {
            self.event_history.remove(0);
        }
        let wrapped = json!({ "type": "event", "event": event });
        self.pending_events.push(wrapped.to_string());
    }

    // -- simulation --------------------------------------------------------

    fn simulate(&mut self, now: i64) {
        if self.match_running {
            self.match_time_left -= FIXED_DT;

            if self.storm_is_shrinking {
                self.storm_shrink_progress += FIXED_DT;
                let t = (self.storm_shrink_progress / STORM_SHRINK_DURATION).min(1.0);
                let smooth = t * t * (3.0 - 2.0 * t);
                self.storm_radius = self.storm_start_radius
                    + (self.storm_target_radius - self.storm_start_radius) * smooth;
                if self.storm_shrink_progress >= STORM_SHRINK_DURATION {
                    self.storm_is_shrinking = false;
                    self.storm_shrink_timer = 0.0;
                    self.storm_radius = self.storm_target_radius;
                }
            } else {
                self.storm_shrink_timer += FIXED_DT;
                if self.storm_shrink_timer >= STORM_SHRINK_INTERVAL {
                    self.storm_start_radius = self.storm_radius;
                    self.storm_target_radius =
                        (self.storm_start_radius - STORM_SHRINK_STEP).max(STORM_MIN_RADIUS);
                    if self.storm_target_radius < self.storm_start_radius {
                        self.storm_is_shrinking = true;
                        self.storm_shrink_progress = 0.0;
                    }
                }
            }

            self.reward_accumulator += FIXED_DT;
            if self.reward_accumulator >= REWARD_TICK_INTERVAL_SEC {
                self.reward_accumulator = 0.0;
                self.run_reward_tick(now);
            }

            // Only check global timeout if the match hasn't already ended via instant victory.
            // The instant victory path calls finish_round_with_instant_victory which sets
            // pending_close_all = true, so we can check that flag.
            if self.match_time_left <= 0.0 && !self.pending_close_all {
                self.finish_round(now);
            }
        } else if !self.match_started_this_round {
            self.match_time_left = MATCH_DURATION_SECONDS;
            if self.match_start_countdown >= 0.0 {
                self.match_start_countdown -= FIXED_DT;
                if self.match_start_countdown <= 0.0 {
                    self.match_start_countdown = -1.0;
                    self.match_running = true;
                    self.match_started_this_round = true;
                    self.randomize_all_item_spawns();
                }
            } else if self.player_count() >= self.min_players_to_start {
                self.match_start_countdown = MATCH_START_COUNTDOWN_SECONDS;
            }
        }
    }

    fn run_reward_tick(&mut self, now: i64) {
        let (chicken_x, chicken_z) = if self.chicken.is_held {
            match self
                .chicken
                .holder_id
                .as_ref()
                .and_then(|hid| self.players.get(hid))
            {
                Some(holder) => (holder.x, holder.z),
                None => (self.chicken.x, self.chicken.z),
            }
        } else {
            (self.chicken.x, self.chicken.z)
        };
        let lootbox_held = self.lootbox.is_held;
        let lootbox_holder = self.lootbox.holder_id.clone();

        let ids: Vec<String> = self.players.keys().cloned().collect();
        for pid in ids {
            if let Some(player) = self.players.get_mut(&pid) {
                if player.orphaned_at.is_some() {
                    continue;
                }
                let dx = chicken_x - player.x;
                let dz = chicken_z - player.z;
                let dist = (dx * dx + dz * dz).sqrt();
                if dist <= XP_CHICKEN_RADIUS {
                    let proximity = 1.0 - (dist / XP_CHICKEN_RADIUS);
                    player.reward.accumulated_xp += XP_PER_SEC * proximity;
                    if proximity >= 0.999 {
                        player.reward.chicken_hold_time += 1;
                    }
                }
                // NEW: Only the current chicken holder accumulates possession time.
                if player.is_current_holder {
                    player.accumulated_possession += FIXED_DT;
                    // Instant victory check: first to 60 seconds wins.
                    if player.accumulated_possession >= VICTORY_POSSESSION_SECONDS {
                        self.finish_round_with_instant_victory(now, &pid);
                        return;
                    }
                }
                if lootbox_held && lootbox_holder.as_deref() == Some(pid.as_str()) {
                    player.reward.accumulated_mon += MON_PER_SEC;
                }
            }
        }

        let pool = round6(TOTAL_MON_POOL_PER_MATCH);
        let ids: Vec<String> = self.players.keys().cloned().collect();
        for pid in ids {
            let reward = &self.players[&pid].reward;
            let msg = RewardUpdate {
                msg_type: "reward_update",
                xp: reward.accumulated_xp.floor() as i64,
                mon: round6(reward.accumulated_mon),
                pool,
                hold_time: reward.chicken_hold_time,
                // New fields for possession progress HUD.
                possession_time: self.players[&pid].accumulated_possession.floor() as i64,
                victory_target: VICTORY_POSSESSION_SECONDS as i64,
            };
            self.pending_reward_msgs.push((pid, encode(&msg)));
        }
    }

    fn resolve_round_winner(&self) -> (Option<String>, String, Option<String>, String) {
        let mut winner_id = None;
        let mut winner_name = "No one".to_string();
        let mut second_id = None;
        let mut second_name = String::new();

        if self.chicken.is_held {
            if let Some(holder) = self
                .chicken
                .holder_id
                .as_ref()
                .and_then(|h| self.players.get(h))
            {
                winner_id = Some(holder.id.clone());
                winner_name = holder.username.clone();
            }
        }
        if self.lootbox.is_held {
            if let Some(holder) = self
                .lootbox
                .holder_id
                .as_ref()
                .and_then(|h| self.players.get(h))
            {
                second_id = Some(holder.id.clone());
                second_name = holder.username.clone();
            }
        }

        (winner_id, winner_name, second_id, second_name)
    }

    /// Called when a player reaches 60s possession time — instant victory.
    fn finish_round_with_instant_victory(&mut self, now: i64, victor_id: &str) {
        let victor_name = self
            .players
            .get(victor_id)
            .map(|p| p.username.clone())
            .unwrap_or_else(|| "Unknown".to_string());

        let meta = json!({
            "winnerId": victor_id,
            "winnerName": victor_name,
            "secondId": Value::Null,
            "secondName": "",
            "victoryType": "instant", // 60s possession reached
        });
        self.publish_event(
            "match_winner",
            &format!("{} reached 60s possession and wins!", victor_name),
            victor_id,
            &meta,
        );

        self.reset_round_for_next_batch(now);
    }

    fn finish_round(&mut self, _now: i64) {
        // Buzzer resolution: global timer expired.
        let (holder_id, holder_name, holder_possession) = if self.chicken.is_held {
            if let Some(holder) = self
                .chicken
                .holder_id
                .as_ref()
                .and_then(|h| self.players.get(h))
            {
                (Some(holder.id.clone()), holder.username.clone(), holder.accumulated_possession)
            } else {
                (None, "No one".to_string(), 0.0)
            }
        } else {
            (None, "No one".to_string(), 0.0)
        };

        // Find eligible player with highest accumulated possession.
        let mut best_id = None;
        let mut best_name = "No one".to_string();
        let mut best_possession = 0.0;

        for player in self.players.values() {
            if player.orphaned_at.is_some() {
                continue; // Eliminated players are not eligible.
            }
            if player.accumulated_possession > best_possession {
                best_possession = player.accumulated_possession;
                best_id = Some(player.id.clone());
                best_name = player.username.clone();
            } else if player.accumulated_possession == best_possession && best_possession > 0.0 {
                // Deterministic tie-break: lower player id wins (stable ordering).
                if let Some(ref current_best) = best_id {
                    if player.id < *current_best {
                        best_id = Some(player.id.clone());
                        best_name = player.username.clone();
                    }
                }
            }
        }

        let (winner_id, winner_name, split_meta) = match (holder_id.clone(), best_id.clone()) {
            (Some(h_id), Some(b_id)) if h_id == b_id => {
                // Current holder is also the highest-progress player.
                (Some(h_id), holder_name, json!({
                    "split": false,
                    "holderShare": 1.0,
                    "progressShare": 0.0,
                }))
            }
            (Some(h_id), Some(b_id)) => {
                // Different players: split reward proportionally to accumulated possession.
                let holder_time = holder_possession;
                let progress_time = best_possession;
                let total = holder_time + progress_time;
                let (holder_share, progress_share) = if total > 0.0 {
                    (holder_time / total, progress_time / total)
                } else {
                    (0.5, 0.5) // Safe fallback if both zero.
                };
                // Winner for event purposes is the holder (they have the chicken).
                // But we record the split in meta for the client.
                (Some(h_id), holder_name, json!({
                    "split": true,
                    "holderId": h_id,
                    "holderName": holder_name,
                    "holderTime": holder_time,
                    "holderShare": holder_share,
                    "progressId": b_id,
                    "progressName": best_name,
                    "progressTime": progress_time,
                    "progressShare": progress_share,
                }))
            }
            (Some(h_id), None) => {
                // Holder exists but no other eligible player with possession.
                // Holder wins 100%.
                (Some(h_id), holder_name, json!({
                    "split": false,
                    "holderShare": 1.0,
                    "progressShare": 0.0,
                }))
            }
            (None, Some(b_id)) => {
                // No current holder; best possession player wins.
                (Some(b_id), best_name, json!({
                    "split": false,
                    "holderShare": 0.0,
                    "progressShare": 1.0,
                }))
            }
            (None, None) => {
                // No holder, no eligible player with possession.
                // Deterministic fallback: first player by id (stable ordering).
                let mut fallback_id = None;
                let mut fallback_name = "No one".to_string();
                let mut player_ids: Vec<String> = self.players.keys().cloned().collect();
                player_ids.sort();
                if let Some(id) = player_ids.first() {
                    if let Some(p) = self.players.get(id) {
                        if p.orphaned_at.is_none() {
                            fallback_id = Some(p.id.clone());
                            fallback_name = p.username.clone();
                        }
                    }
                }
                (fallback_id, fallback_name, json!({
                    "split": false,
                    "holderShare": 0.0,
                    "progressShare": 0.0,
                    "fallback": true,
                }))
            }
        };

        if let Some(ref wid) = winner_id {
            let message = format!("{} won the match", winner_name);
            let mut meta = split_meta;
            meta["winnerId"] = json!(wid);
            meta["winnerName"] = json!(winner_name);
            meta["victoryType"] = json!("buzzer");
            self.publish_event("match_winner", &message, wid, &meta);
        } else {
            let message = "No winner this match".to_string();
            let mut meta = json!({
                "winnerId": Value::Null,
                "winnerName": "No one",
                "victoryType": "buzzer",
                "split": false,
            });
            self.publish_event("match_winner", &message, "", &meta);
        }

        self.reset_round_for_next_batch(now);
    }

    fn reset_round_for_next_batch(&mut self, now: i64) {
        self.pending_close_all = true;

        self.players.clear();
        self.player_cell_index.clear();
        self.cell_occupants.clear();
        self.recipient_state.clear();
        self.pending_reward_msgs.clear();
        self.reward_accumulator = 0.0;

        self.reset_chicken_state();
        self.reset_lootbox_state();
        self.randomize_all_item_spawns();

        self.match_running = false;
        self.match_time_left = MATCH_DURATION_SECONDS;
        self.match_started_this_round = false;
        self.match_start_countdown = -1.0;

        self.storm_radius = STORM_START_RADIUS;
        self.storm_shrink_timer = 0.0;
        self.storm_is_shrinking = false;
        self.storm_shrink_progress = 0.0;
        self.storm_start_radius = STORM_START_RADIUS;
        self.storm_target_radius = STORM_START_RADIUS;

        self.batch_reset_until_ms = now + 500;
    }

    fn build_encoded_match(&self) -> MatchNet {
        let countdown = if self.match_start_countdown >= 0.0 {
            self.match_start_countdown.ceil().max(0.0) as i64
        } else {
            0
        };
        MatchNet {
            t: (self.match_time_left * 100.0).round() as i64,
            r: if self.match_running { 1 } else { 0 },
            d: (MATCH_DURATION_SECONDS * 100.0).round() as i64,
            min: self.min_players_to_start as i64,
            max: self.max_players.map(|m| m as i64),
            sr: (self.storm_radius * 100.0).round() as i64,
            pl: self.player_count() as i64,
            c: countdown,
        }
    }

    pub fn tick(&mut self, now: i64) -> TickOutput {
        self.simulate(now);

        let mut out = TickOutput::default();
        out.events = std::mem::take(&mut self.pending_events);

        if self.pending_close_all {
            self.pending_close_all = false;
            out.close_all = true;
            return out;
        }

        // Expire orphaned players whose reconnect grace window has passed.
        let expired: Vec<String> = self
            .players
            .values()
            .filter(|p| p.orphaned_at.map(|t| t <= now).unwrap_or(false))
            .map(|p| p.id.clone())
            .collect();
        for id in expired {
            let _ = self.remove_player(&id, now);
        }

        let current_players: HashMap<String, PlayerNet> = self
            .players
            .values()
            .map(|p| (p.id.clone(), encode_player(p)))
            .collect();
        let current_chicken = encode_item(&self.chicken);
        let current_lootbox = encode_item(&self.lootbox);
        let current_items: Vec<ItemNet> = POWER_UP_IDS
            .iter()
            .map(|id| encode_item(&self.power_ups[*id]))
            .collect();
        let current_match = self.build_encoded_match();

        let recipient_ids: Vec<String> = self
            .players
            .values()
            .filter(|p| p.orphaned_at.is_none())
            .map(|p| p.id.clone())
            .collect();
        let mut messages = std::mem::take(&mut self.pending_reward_msgs);

        for recipient_id in recipient_ids {
            if let Some(bytes) = build_recipient_payload(
                &self.players,
                &self.cell_occupants,
                &mut self.recipient_state,
                &recipient_id,
                &current_players,
                &current_chicken,
                &current_lootbox,
                &current_match,
                &current_items,
                now,
            ) {
                messages.push((recipient_id, bytes));
            }
        }

        out.messages = messages;
        out
    }
}

// ---------------------------------------------------------------------------
// Free helpers (kept separate to keep field borrows disjoint)
// ---------------------------------------------------------------------------

fn get_cell_coords(x: f64, z: f64) -> (i32, i32) {
    (
        (x / CELL_SIZE).floor() as i32,
        (z / CELL_SIZE).floor() as i32,
    )
}

fn get_cell_key(cx: i32, cz: i32) -> String {
    format!("{}:{}", cx, cz)
}

fn encode_player(player: &Player) -> PlayerNet {
    PlayerNet {
        id: player.id.clone(),
        x: quantize_position(player.x),
        y: quantize_position(player.y),
        z: quantize_position(player.z),
        r: quantize_rotation(player.rotation_y),
        a: anim_name_to_id(&player.animation).unwrap_or(0),
        skin: if player.skin.is_empty() {
            "defaultnad".to_string()
        } else {
            player.skin.clone()
        },
        u: None,
    }
}

fn encode_item(item: &Item) -> ItemNet {
    ItemNet {
        i: item.id.clone(),
        x: quantize_position(item.x),
        y: quantize_position(item.y),
        z: quantize_position(item.z),
        r: quantize_rotation(item.rotation_y),
        h: if item.is_held { 1 } else { 0 },
        o: item.holder_id.clone().unwrap_or_default(),
    }
}

fn random_item_spawn_point() -> (f64, f64, f64, f64) {
    let mut rng = rand::thread_rng();
    let half = (ARENA_HALF_SIZE - ITEM_SPAWN_MARGIN).max(1.0);
    (
        rng.gen_range(-half..half),
        FLOOR_Y,
        rng.gen_range(-half..half),
        rng.gen_range(0.0..(std::f64::consts::PI * 2.0)),
    )
}

fn update_rate_for_distance(distance: f64) -> f64 {
    if distance <= NEAR_UPDATE_DISTANCE {
        NEAR_UPDATE_RATE
    } else if distance <= MEDIUM_UPDATE_DISTANCE {
        MEDIUM_UPDATE_RATE
    } else {
        FAR_UPDATE_RATE
    }
}

fn collect_visible_player_ids(
    players: &HashMap<String, Player>,
    cell_occupants: &HashMap<String, HashSet<String>>,
    recipient_id: &str,
) -> Vec<String> {
    let recipient = match players.get(recipient_id) {
        Some(p) => p,
        None => return vec![],
    };
    let (cx, cz) = get_cell_coords(recipient.x, recipient.z);
    let mut ids: HashSet<String> = HashSet::new();
    for dx in -CELL_REPLICATION_RADIUS..=CELL_REPLICATION_RADIUS {
        for dz in -CELL_REPLICATION_RADIUS..=CELL_REPLICATION_RADIUS {
            let key = get_cell_key(cx + dx, cz + dz);
            if let Some(occupants) = cell_occupants.get(&key) {
                for id in occupants {
                    ids.insert(id.clone());
                }
            }
        }
    }
    ids.insert(recipient_id.to_string());
    ids.into_iter().collect()
}

#[allow(clippy::too_many_arguments)]
fn build_recipient_payload(
    players: &HashMap<String, Player>,
    cell_occupants: &HashMap<String, HashSet<String>>,
    recipient_state: &mut HashMap<String, RecipientState>,
    recipient_id: &str,
    current_players: &HashMap<String, PlayerNet>,
    current_chicken: &ItemNet,
    current_lootbox: &ItemNet,
    current_match: &MatchNet,
    current_items: &[ItemNet],
    now: i64,
) -> Option<Vec<u8>> {
    let recipient = players.get(recipient_id)?;
    let state = recipient_state
        .entry(recipient_id.to_string())
        .or_insert_with(RecipientState::new);

    let should_full = (now - state.last_full_snapshot_at) >= FULL_SNAPSHOT_INTERVAL_MS;
    let should_heartbeat = (now - state.last_match_heartbeat_at) >= MATCH_HEARTBEAT_INTERVAL_MS;

    let visible_ids = collect_visible_player_ids(players, cell_occupants, recipient_id);
    let mut visible: HashMap<String, PlayerNet> = HashMap::new();
    for id in &visible_ids {
        if let Some(encoded) = current_players.get(id) {
            visible.insert(id.clone(), encoded.clone());
        }
    }

    if should_full {
        let mut full: Vec<PlayerNet> = Vec::with_capacity(visible.len());
        for encoded in visible.values() {
            let mut entry = encoded.clone();
            entry.u = players.get(&encoded.id).map(|src| src.username.clone());
            full.push(entry);
        }

        state.last_sent_players = visible.clone();
        state.last_sent_player_at = visible.keys().map(|id| (id.clone(), now)).collect();
        state.last_sent_chicken = Some(current_chicken.clone());
        state.last_sent_lootbox = Some(current_lootbox.clone());
        state.last_sent_items = Some(current_items.to_vec());
        state.last_sent_match = Some(current_match.clone());
        state.last_full_snapshot_at = now;
        state.last_match_heartbeat_at = now;

        let msg = StateFull {
            msg_type: "state_full",
            q: 1,
            players: full,
            chicken: current_chicken.clone(),
            lootbox: current_lootbox.clone(),
            items: current_items.to_vec(),
            match_state: current_match.clone(),
        };
        return Some(encode(&msg));
    }

    let mut delta = StateDelta {
        msg_type: "state_delta",
        q: 1,
        ..Default::default()
    };

    let mut changed_players: Vec<PlayerNet> = Vec::new();
    for (id, encoded) in visible.iter() {
        let current = match players.get(id) {
            Some(p) => p,
            None => continue,
        };
        let distance = length3(
            current.x - recipient.x,
            current.y - recipient.y,
            current.z - recipient.z,
        );
        let last_sent_at = *state.last_sent_player_at.get(id).unwrap_or(&0);
        let interval_ms = 1000.0 / update_rate_for_distance(distance);
        if (now - last_sent_at) as f64 >= interval_ms {
            changed_players.push(encoded.clone());
            state.last_sent_players.insert(id.clone(), encoded.clone());
            state.last_sent_player_at.insert(id.clone(), now);
        }
    }

    let mut removed: Vec<String> = Vec::new();
    let tracked: Vec<String> = state.last_sent_players.keys().cloned().collect();
    for id in tracked {
        if !visible.contains_key(&id) {
            removed.push(id.clone());
            state.last_sent_players.remove(&id);
            state.last_sent_player_at.remove(&id);
        }
    }

    let chicken_changed = state.last_sent_chicken.as_ref() != Some(current_chicken);
    let lootbox_changed = state.last_sent_lootbox.as_ref() != Some(current_lootbox);
    let items_changed = state.last_sent_items.as_deref() != Some(current_items);
    let match_changed = state.last_sent_match.as_ref() != Some(current_match);

    if !changed_players.is_empty() {
        delta.players = Some(changed_players);
    }
    if !removed.is_empty() {
        delta.removed = Some(removed);
    }
    if chicken_changed || should_heartbeat {
        delta.chicken = Some(current_chicken.clone());
        state.last_sent_chicken = Some(current_chicken.clone());
    }
    if lootbox_changed || should_heartbeat {
        delta.lootbox = Some(current_lootbox.clone());
        state.last_sent_lootbox = Some(current_lootbox.clone());
    }
    if items_changed || should_heartbeat {
        delta.items = Some(current_items.to_vec());
        state.last_sent_items = Some(current_items.to_vec());
    }
    if match_changed || should_heartbeat {
        delta.match_state = Some(current_match.clone());
        state.last_sent_match = Some(current_match.clone());
        state.last_match_heartbeat_at = now;
    }

    if delta.players.is_none()
        && delta.removed.is_none()
        && delta.chicken.is_none()
        && delta.lootbox.is_none()
        && delta.items.is_none()
        && delta.match_state.is_none()
    {
        return None;
    }

    Some(encode(&delta))
}

/// Node `sanitizeMeta`: keep string/number/bool/null values with short keys.
pub fn sanitize_meta(value: Option<&Value>) -> Value {
    let mut out = serde_json::Map::new();
    if let Some(Value::Object(map)) = value {
        for (key, val) in map {
            if key.chars().count() > 40 {
                continue;
            }
            match val {
                Value::String(_) | Value::Number(_) | Value::Bool(_) | Value::Null => {
                    out.insert(key.clone(), val.clone());
                }
                _ => {}
            }
        }
    }
    Value::Object(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn connect_message_encodes_as_map() {
        let bytes = encode(&ConnectMsg {
            msg_type: "connect",
            id: "abc".into(),
            username: "bob".into(),
            skin: "s-default".into(),
            xp: 0,
        });
        let v: Value = rmp_serde::from_slice(&bytes).unwrap();
        assert_eq!(v["type"], "connect");
        assert_eq!(v["username"], "bob");
        assert_eq!(v["xp"], 0);
    }

    #[test]
    fn full_snapshot_has_expected_shape() {
        let mut room = Room::new();
        room.add_player("p1", "alice", "s-default", 0, 1);
        room.add_player("p2", "bob", "s-default", 0, 2);

        let out = room.tick(1_000_000_000_000);
        let (_, bytes) = out.messages.iter().find(|(id, _)| id == "p1").unwrap();
        let v: Value = rmp_serde::from_slice(bytes).unwrap();

        assert_eq!(v["type"], "state_full");
        assert_eq!(v["q"], 1);
        assert_eq!(v["players"].as_array().unwrap().len(), 2);
        assert_eq!(v["match"]["pl"], 2);
        assert_eq!(v["chicken"]["i"], "Chicken");
        assert_eq!(v["lootbox"]["i"], "LootBox");
        assert_eq!(v["items"].as_array().unwrap().len(), 5);
        assert!(v["players"].as_array().unwrap()[0]["u"].is_string());
    }

    #[test]
    fn movement_is_clamped() {
        let mut room = Room::new();
        room.add_player("p1", "alice", "s-default", 0, 1);
        let data = serde_json::json!({
            "type": "update_state",
            "qx": 100000, "qy": 0, "qz": 0, "qrot": 0, "anim_id": 1
        });
        room.apply_update_state("p1", &data);
        let player = room.players.get("p1").unwrap();
        assert!(player.x <= MAX_PLAYER_SPEED * 0.5 + 0.001, "x={}", player.x);
        assert_eq!(player.animation, "running");
    }

    #[test]
    fn pickup_sets_authoritative_holder() {
        let mut room = Room::new();
        room.add_player("p1", "alice", "s-default", 0, 1);
        room.pickup_request("p1", "Chicken");
        assert!(room.chicken.is_held);
        assert_eq!(room.chicken.holder_id.as_deref(), Some("p1"));

        // A second player can steal it (last claim wins).
        room.add_player("p2", "bob", "s-default", 0, 2);
        room.pickup_request("p2", "Chicken");
        assert_eq!(room.chicken.holder_id.as_deref(), Some("p2"));
    }
}
