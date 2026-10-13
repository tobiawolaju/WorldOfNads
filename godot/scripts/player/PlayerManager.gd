# PlayerManager.gd
extends Node3D
class_name PlayerManager

static var instance: PlayerManager

# --- SERVER URLS ---
const LIVE_URL: String = "wss://worldofnads.onrender.com"
const LOCAL_URL: String = "ws://localhost:8080"
const DEFAULT_SKIN_NAME: String = "s-default"
const SKIN_SCENE_PATH: String = "res://scenes/skin.tscn"

static var _skin_applier: SkinApplier = SkinApplier.new()
const SKIN_NAME_ALIASES: Dictionary = {
	"s-default": "s-default",
	"s-default-unshaded": "s-default-unshaded",
}

@export var player_scene: PackedScene 
@export var myplayerswpanpoint: Marker3D
@export var countdown_label_path: NodePath
@export var world_environment_path: NodePath = NodePath("WorldEnvironment")
@export var camera_block_path: NodePath = NodePath("CAMERABlock")

# --- NETWORK & STATE VARIABLES ---
var ws: WebSocketPeer = WebSocketPeer.new()
var connected: bool = false
var player_id: String = ""
var players: Dictionary = {}
var is_local: bool = false
var root: Node = null
const CHICKEN_HOLD_DISTANCE: float = 0.9
const CHICKEN_HOLD_HEIGHT: float = 1.0
const POS_SCALE: float = 100.0
const ROT_SCALE: float = 1000.0
const ANIM_ID_TO_NAME: Dictionary = {
	0: "idle",
	1: "running",
	2: "runningjump",
	3: "falling",
	4: "runningslide"
}
# Interpolation buffer. Delay sits slightly BELOW the server's per-player update
# interval so render_time routinely reaches the newest snapshot; the gap is then
# bridged by velocity extrapolation (REMOTE_MAX_EXTRAPOLATE_MS) instead of a
# freeze-and-teleport. Keeps remote motion smooth even while packets are late.
const REMOTE_INTERP_BACKTIME_MS: float = 80.0
const REMOTE_MIN_INTERP_BACKTIME_MS: float = 40.0
const REMOTE_MAX_INTERP_BACKTIME_MS: float = 180.0
const REMOTE_MAX_EXTRAPOLATE_MS: float = 100.0
# Remote avatars are carried forward (extrapolated) from the last two snapshots.
# When a burst of deltas lands in the same frame the gap between them collapses
# to ~1 ms, which inflates the derived velocity ~50x; a single late packet then
# flings the avatar across the map. Floor the interval and clamp the velocity so
# that can never happen.
const REMOTE_MIN_SNAPSHOT_DT_MS: float = 16.0
const REMOTE_MAX_EXTRAP_SPEED: float = 14.0
const REMOTE_ANIMATION_LOD_DISTANCE: float = 20.0
const REMOTE_ANIMATION_LOD_DISTANCE_SQ: float = REMOTE_ANIMATION_LOD_DISTANCE * REMOTE_ANIMATION_LOD_DISTANCE
const REMOTE_PLAYER_SCRIPT := preload("res://scripts/player/RemotePlayer.gd")

# --- CHICKEN AUTHORITY STATE ---
var chicken_node: RigidBody3D = null
var chicken_is_held: bool = false
var chicken_holder_id: String = ""
var events_bridge: Node = null
var _last_chicken_is_held: bool = false
var _last_chicken_holder_id: String = ""

# --- LOOTBOX AUTHORITY STATE ---
var lootbox_node: RigidBody3D = null
var lootbox_is_held: bool = false
var lootbox_holder_id: String = ""
var _last_lootbox_is_held: bool = false
var _last_lootbox_holder_id: String = ""

# --- SERVER-AUTHORITATIVE ITEM STATE (power-ups p1..p5) ---
# The five power-ups share the chicken/lootbox protocol: the server owns each
# item's spawn spot and who holds it. These mirror the last snapshot so the
# per-frame pass can hide carried power-ups and seat released ones.
const POWER_UP_ITEM_IDS: Array[String] = ["p1", "p2", "p3", "p4", "p5"]
var item_nodes: Dictionary = {}       # item id -> Node3D
var item_is_held: Dictionary = {}     # item id -> bool (server state)
var item_holder: Dictionary = {}      # item id -> holder player id
var item_local_held: String = ""      # item id the LOCAL player is carrying (or "")
var _remote_lod_timer: float = 0.0
const REMOTE_LOD_INTERVAL: float = 0.15 # Check distance 6 times per second
var _storm_env_node: Node = null
var local_username: String = ""
# Hand-off from the screens that lead into a match (dshbord -> lobby -> here).
# Written before _ready() by SceneTransition.change_scene(); empty falls back to
# ?skin= on the URL, which is how the frontend's /play page enters the game.
@export var selected_match_id: String = ""
@export var selected_skin_id: String = ""
var local_skin_name: String = DEFAULT_SKIN_NAME
var local_display_name: String = "player"
var _skin_cycle_index: int = -1
var player_display_names: Dictionary = {}
var player_skin_names: Dictionary = {}
var remote_snapshots: Dictionary = {}
var countdown_label: Label = null

# --- OBJECT POOLING ---
var _remote_player_pool: Array[Node3D] = []
const POOL_SIZE: int = 12

func _init_player_pool():
	for i in range(POOL_SIZE):
		var dummy_node = _instantiate_remote_player_for_skin(DEFAULT_SKIN_NAME)
		dummy_node.visible = false
		dummy_node.process_mode = PROCESS_MODE_DISABLED
		dummy_node.name = "PooledPlayer_%d" % i
		add_child(dummy_node)
		_remote_player_pool.append(dummy_node)

func _get_player_from_pool() -> Node3D:
	for p in _remote_player_pool:
		if p.process_mode == PROCESS_MODE_DISABLED:
			p.process_mode = PROCESS_MODE_INHERIT
			return p
	# Cap growth: recycle the first non-local inactive player instead of allocating
	for p in _remote_player_pool:
		var pid := ""
		for id in players:
			if players[id] == p:
				pid = id
				break
		if pid != "" and pid != player_id:
			players.erase(pid)
			remote_snapshots.erase(pid)
			p.visible = true
			p.process_mode = PROCESS_MODE_INHERIT
			return p
	var new_p = _instantiate_remote_player_for_skin(DEFAULT_SKIN_NAME)
	add_child(new_p)
	_remote_player_pool.append(new_p)
	return new_p

func _return_player_to_pool(player: Node3D):
	player.visible = false
	player.process_mode = PROCESS_MODE_DISABLED
	player.global_position = Vector3(0, -100, 0)
	if player.has_method("set_mesh_lod_enabled"):
		player.set_mesh_lod_enabled(true)
	if player.has_method("set_animation_lod_enabled"):
		player.set_animation_lod_enabled(true)
	if player.has_method("cache_animation_state"):
		player.cache_animation_state("idle")
var world_environment: WorldEnvironment = null
var camera_block: Node3D = null
var _world_env_duplicated: bool = false
var match_duration_seconds: float = 180.0
var match_time_left: float = 180.0
var match_is_running: bool = false
var min_players_to_start: int = 0
var max_players: int = 0
var connected_player_count: int = 0
var start_countdown_sec: int = 0
var _match_clock_anchor_ms: float = 0.0
var _match_clock_anchor_time_left: float = 180.0


# --- XP & LEVEL VARIABLES ---
static var local_base_xp: int = 0
static var session_earned_xp: float = 0.0

# --- MATCH REWARDS ---
# Rewards are computed on the SERVER now (proximity to the chicken -> XP,
# holding the lootbox -> MON) and pushed down via "reward_update". The client
# only displays what the server sends, so there is no local accrual to
# double-count.
var session_earned_mon: float = 0.0

# --- FALLBACK LOGIC ---
var is_connecting_to_live: bool = true
var connection_attempted: bool = false
@onready var fallback_timer: Timer = $FallbackTimer

var _ui_update_timer: float = 0.0
const UI_UPDATE_INTERVAL: float = 0.2
var _last_countdown_text: String = ""

const API_BASE: String = "https://worldofnads.onrender.com"

func _ready():
	instance = self
	add_to_group("player_manager")
	_resolve_local_username()
	_resolve_local_skin_name()
	_pre_seed_from_session_storage()
	_update_debug_skin()
	_fetch_skin_data()
	_fetch_skin_index()
	_init_player_pool()
	fallback_timer.timeout.connect(_on_fallback_timer_timeout)
	_attempt_connection()
	_cache_chicken_node()
	_resolve_events_bridge()
	_resolve_ui_nodes()
	_update_match_ui()

func _show_json_on(label_method: String, json_data) -> void:
	var json_str = JSON.stringify(json_data, "  ", false) if json_data else "{}"
	var events_node = get_tree().get_first_node_in_group("events_bridge")
	if events_node != null and events_node.has_method(label_method):
		events_node.call(label_method, json_str)

func _update_debug_skin() -> void:
	var data = SkinApplier.get_skin_data(local_skin_name)
	_show_json_on("set_debug_text", data)

func _update_debug2_cache() -> void:
	var cache = SkinApplier._api_cache.duplicate(true)
	_show_json_on("set_debug2_text", cache)

func _cycle_skin() -> void:
	var keys := SkinApplier._api_cache.keys()
	if keys.is_empty():
		return
	_skin_cycle_index = (_skin_cycle_index + 1) % keys.size()
	var chosen := str(keys[_skin_cycle_index])
	print("[CYCLE] Applying skin #%d: '%s'" % [_skin_cycle_index, chosen])
	local_skin_name = chosen
	_update_debug_skin()
	var p = players.get(player_id)
	if p != null:
		_skin_applier.apply_skin(p, chosen)

func _fetch_skin_data() -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_skin_data_fetched.bind(http))
	http.request("%s/api/skins" % API_BASE)

func _on_skin_data_fetched(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	if http != null and is_instance_valid(http):
		http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Dictionary and parsed.get("ok") == true:
		var skins_array = parsed.get("skins")
		if skins_array is Array:
			SkinApplier.seed_from_api(skins_array)
			_update_debug2_cache()
			_update_debug_skin()
			_reapply_skins()

func _fetch_skin_index() -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_skin_index_fetched.bind(http))
	http.request("%s/api/skin-combos" % API_BASE)


func _on_skin_index_fetched(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	if http != null and is_instance_valid(http):
		http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Dictionary and parsed.get("ok") == true:
		SkinApplier.seed_index_from_api(parsed)
		_reapply_skins()


func _reapply_skins() -> void:
	var count := 0
	for id in players:
		var p = players.get(id)
		if p == null or not (p is Node3D):
			continue
		var node: Node3D = p
		var skin_name = player_skin_names.get(id, DEFAULT_SKIN_NAME)
		if id == player_id:
			_skin_applier.apply_skin(node, skin_name)
		else:
			_update_remote_player_skin(node, skin_name)
		count += 1
	if count > 0:
		_update_debug_skin()

func _attempt_connection():
	var base_url = LIVE_URL if is_connecting_to_live else LOCAL_URL
	var url_to_try = _build_ws_url_with_username(base_url)
	var server_type = "LIVE" if is_connecting_to_live else "LOCAL"

	print("🌐 Attempting to connect to %s server: %s" % [server_type, url_to_try])
	var err = ws.connect_to_url(url_to_try)

	if err != OK:
		push_error("Failed to initiate connection: %s" % err)
		if is_connecting_to_live:
			_trigger_fallback()
	else:
		connection_attempted = true

var _last_real_delta_ms: float = 0.0
var _msg_process_timer: float = 0.0
const MSG_PROCESS_INTERVAL: float = 0.033
const MAX_PACKETS_PER_FRAME: int = 30
var _cleanup_timer: float = 0.0
const CLEANUP_INTERVAL: float = 5.0
var _received_ids_cache: Dictionary = {}
var _cached_skin_scene: PackedScene = null
var _cached_local_player: Node3D = null

# --- RECONNECTION ---
var _reconnecting: bool = false
var _reconnect_phase: String = ""
var _reconnect_attempts: int = 0
var _reconnect_timer: float = 0.0
var _reconnect_delay: float = 1.0
var _reconnect_dot_timer: float = 0.0
var _reconnect_dots: int = 0
var _reconnect_countdown: int = 0
var _subtitle_label: Label = null
var _reconnect_target_url: String = ""
var _last_server_position: Vector3 = Vector3.ZERO
const RECONNECT_DOT_INTERVAL: float = 0.5
const RECONNECT_MAX_DELAY: float = 8.0
const RECONNECT_INITIAL_DELAY: float = 1.0
const RECONNECT_GRACE_TIME: float = 0.5
const RECONNECT_COUNTDOWN_STEPS: int = 3
var _waiting_for_connect: bool = false

# Liveness watchdog: the server only broadcasts while a match runs, so if we are
# in a match and hear nothing for this long the link has silently died. A silent
# network drop leaves WebSocketPeer reporting OPEN, which never reaches the
# STATE_CLOSED branch, so the client would sit in a ghost session forever.
var _last_rx_ms: float = 0.0
const LIVENESS_TIMEOUT_MS: float = 5000.0

# Local player node kept alive across a reconnect. Freeing it (the old behaviour)
# destroyed the only object driving the camera, so the view froze and the player
# vanished mid-match. We now reuse this node instead of respawning it.
var _preserved_local_node: Node3D = null
var _preserved_local_id: String = ""

func _input(event: InputEvent):
	if event is InputEventKey and event.keycode == KEY_T and event.pressed and not event.echo:
		_cycle_skin()

func _process(_delta: float):
	var now_ms := float(Time.get_ticks_msec())
	if _last_real_delta_ms == 0.0:
		_last_real_delta_ms = now_ms
	
	var real_delta := (now_ms - _last_real_delta_ms) / 1000.0
	_last_real_delta_ms = now_ms

	if match_is_running:
		if _match_clock_anchor_ms == 0.0:
			_match_clock_anchor_ms = now_ms
			_match_clock_anchor_time_left = match_time_left
		match_time_left = maxf(0.0, _match_clock_anchor_time_left - ((now_ms - _match_clock_anchor_ms) / 1000.0))
		if events_bridge == null or not is_instance_valid(events_bridge):
			_resolve_events_bridge()
		_update_match_ui()
	else:
		_ui_update_timer += real_delta
		if _ui_update_timer >= UI_UPDATE_INTERVAL:
			_ui_update_timer = 0.0
			if events_bridge == null or not is_instance_valid(events_bridge):
				_resolve_events_bridge()
			_update_match_ui()

	# Seat shared items: hide power-ups a remote player is carrying and weld an
	# objective item onto a remote holder's back so it is visible to everyone.
	_update_item_hold_visuals()

	if not connection_attempted and not _reconnecting:
		_apply_remote_interpolation()
		return

	_cleanup_timer += real_delta
	if _cleanup_timer >= CLEANUP_INTERVAL:
		_cleanup_timer = 0.0
		_cleanup_stale_remote_players(now_ms)

	_update_reconnection(real_delta)

	_msg_process_timer += real_delta
	if _msg_process_timer < MSG_PROCESS_INTERVAL:
		_apply_remote_interpolation()
		return
	_msg_process_timer = 0.0

	ws.poll()
	var state = ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN and not connected:
		_on_reconnect_success()
		var server_type = "LIVE" if is_connecting_to_live else "LOCAL"
		print("✅ Connected to %s server!" % server_type)

	elif state == WebSocketPeer.STATE_CLOSED:
		if connected:
			print("❌ Disconnected from server.")
			connected = false
			connection_attempted = false
			_start_reconnection()
		elif not _reconnecting and is_connecting_to_live:
			print("❌ Live server connection failed.")
			_start_reconnection()

	if connected:
		_receive_messages()
	_check_server_liveness(now_ms)
	_apply_remote_interpolation()

func _check_server_liveness(now_ms: float) -> void:
	# Only meaningful while a match is live, since that's the only time the
	# server pushes state at ~20 Hz. A longer silence means the link died.
	if not connected or _reconnecting or not match_is_running:
		return
	if _last_rx_ms <= 0.0:
		_last_rx_ms = now_ms
		return
	if now_ms - _last_rx_ms > LIVENESS_TIMEOUT_MS:
		_force_reconnect_now()

func _force_reconnect_now() -> void:
	if _reconnecting:
		return
	print("[Net] No server traffic for %.0fs; forcing reconnect." % (LIVENESS_TIMEOUT_MS / 1000.0))
	# A half-open WebSocketPeer (link dropped but the peer still reports OPEN)
	# cannot be reused for connect_to_url, so discard it and open a fresh one.
	if ws != null:
		ws.close()
	ws = WebSocketPeer.new()
	connected = false
	connection_attempted = false
	_last_rx_ms = 0.0
	_start_reconnection()

func _trigger_fallback():
	is_connecting_to_live = false
	connection_attempted = false
	print("⏳ Starting fallback to local server in 1 second...")
	fallback_timer.start(1.0)

func _on_fallback_timer_timeout():
	_attempt_connection()

# --- RECONNECTION ---
func _start_reconnection():
	if _reconnecting:
		return
	_reconnecting = true
	_reconnect_phase = "grace"
	_reconnect_attempts = 0
	_reconnect_delay = RECONNECT_INITIAL_DELAY
	_reconnect_timer = RECONNECT_GRACE_TIME
	_reconnect_dots = 0
	_reconnect_dot_timer = 0.0
	_reconnect_countdown = 0
	_reconnect_target_url = LIVE_URL if is_connecting_to_live else LOCAL_URL
	_resolve_subtitle_label()
	_update_subtitle_text("Disconnected! Check your internet.")
	print("🔄 Auto-reconnect started")

func _update_reconnection(real_delta: float):
	if not _reconnecting:
		return

	_reconnect_timer -= real_delta

	if _reconnect_phase == "grace":
		if _reconnect_timer <= 0.0:
			_reconnect_phase = "countdown"
			_reconnect_countdown = RECONNECT_COUNTDOWN_STEPS
			_reconnect_timer = 1.0
			_update_subtitle_text("Reconnecting in %d..." % _reconnect_countdown)
		return

	if _reconnect_phase == "countdown":
		if _reconnect_timer <= 0.0:
			_reconnect_countdown -= 1
			if _reconnect_countdown <= 0:
				_reconnect_phase = "connecting"
				_reconnect_timer = _reconnect_delay
				return
			_reconnect_timer = 1.0
			_update_subtitle_text("Reconnecting in %d..." % _reconnect_countdown)
		return

	if _reconnect_phase == "connecting":
		_reconnect_dot_timer += real_delta
		if _reconnect_dot_timer >= RECONNECT_DOT_INTERVAL:
			_reconnect_dot_timer = 0.0
			_reconnect_dots = (_reconnect_dots + 1) % 4
			var status := "Reconnecting"
			for _i in range(_reconnect_dots):
				status += "."
			status += " (%d)" % (_reconnect_attempts + 1)
			_update_subtitle_text(status)

		if _reconnect_timer <= 0.0:
			_reconnect_timer = _reconnect_delay
			_reconnect_delay = minf(_reconnect_delay * 1.5, RECONNECT_MAX_DELAY)
			_reconnect_attempts += 1
			_attempt_reconnection()

func _attempt_reconnection():
	if not _reconnecting:
		return
	var cur_state = ws.get_ready_state()
	if cur_state == WebSocketPeer.STATE_OPEN or cur_state == WebSocketPeer.STATE_CONNECTING:
		return
	if _reconnect_target_url == "":
		_reconnect_target_url = LIVE_URL if is_connecting_to_live else LOCAL_URL
	var url = _build_ws_url_with_username(_reconnect_target_url)
	var err = ws.connect_to_url(url)
	if err != OK:
		push_error("Reconnection attempt failed: %s" % err)
	else:
		connection_attempted = true
		print("🔄 Reconnection attempt %d..." % _reconnect_attempts)

func _on_reconnect_success():
	connected = true
	_last_rx_ms = float(Time.get_ticks_msec())
	var was_reconnecting := _reconnecting
	_reconnecting = false
	_reconnect_attempts = 0
	_set_subtitle_visible(false)

	if was_reconnecting:
		print("✅ Reconnected to server!")
		_update_subtitle_text("Connected!")
		_clear_players_for_reconnect()
		_waiting_for_connect = true
		print("⏳ Waiting for 'connect' message from server...")

func _clear_players_for_reconnect():
	var old_id := player_id
	# The server drops anything we were carrying when the socket closed, so our
	# local hold is stale. Forget it; the post-reconnect snapshots re-seat items.
	if item_local_held != "":
		_release_local_item_hold(item_local_held)
	for id in players:
		var p = players[id]
		if p.is_local:
			# Keep the local node (and the camera it drives) alive. Only the
			# remote avatars are recycled; the local player keeps rendering and
			# stays controllable while the socket is down.
			_preserved_local_node = p
			_preserved_local_id = id
			_last_server_position = p.global_position
			p.visible = true
		else:
			_return_player_to_pool(p)
	players.clear()
	player_display_names.clear()
	player_skin_names.clear()
	remote_snapshots.clear()
	# Re-register the preserved node under its old key so local lookups
	# (get_local_player_node / minimap / HUD) keep working during the outage.
	if _preserved_local_node != null and is_instance_valid(_preserved_local_node):
		players[_preserved_local_id] = _preserved_local_node
		player_id = _preserved_local_id
		_cached_local_player = _preserved_local_node
	else:
		_preserved_local_node = null
		_cached_local_player = null
		player_id = ""
	events_bridge = null
	_resolve_events_bridge()
	print("🗑️ Cleared remote players for reconnect (kept local %s)" % old_id)

# Reuse the local player node preserved through a reconnect instead of spawning a
# fresh one, so the camera never stops following and the avatar never blinks out.
# The server may hand out a new id, so the node is re-keyed. Returns true when an
# existing node was adopted.
func _adopt_preserved_local_player(new_id: String, _skin_name: String) -> bool:
	if _preserved_local_node == null or not is_instance_valid(_preserved_local_node):
		_preserved_local_node = null
		return false
	var p := _preserved_local_node
	_preserved_local_node = null
	# Drop stale keys (the server may issue a different id) before re-keying.
	for existing_id in players.keys():
		if players[existing_id] == p:
			players.erase(existing_id)
	players[new_id] = p
	p.name = "Player_%s" % new_id
	p.player_id = new_id
	p.display_name = _get_player_display_name(new_id)
	p.is_local = true
	p.root = self
	p.visible = true
	if not p.is_in_group("local_player"):
		p.add_to_group("local_player")
	_cached_local_player = p
	_preserved_local_id = ""
	print("♻️ Reused local player node across reconnect (id %s)" % new_id)
	return true

func _resync_after_reconnect():
	if player_id == "":
		return
	var local_node: Node3D = _get_local_player_node()
	if local_node == null:
		return
	var bus_node = get_tree().get_first_node_in_group("bus")
	if bus_node:
		local_node.global_position = bus_node.global_position + Vector3(0, 2, 0)
	else:
		local_node.global_position = get_local_spawn_position()
	local_node.visible = true
	var payload = {
		"type": "update_state",
		"qx": int(round(local_node.global_position.x * POS_SCALE)),
		"qy": int(round(local_node.global_position.y * POS_SCALE)),
		"qz": int(round(local_node.global_position.z * POS_SCALE)),
		"qrot": int(round(local_node.rotation.y * ROT_SCALE))
	}
	ws.send(MsgPack.pack(payload))
	ws.send(MsgPack.pack({"type": "request_full_state"}))
	_update_subtitle_text("Back on the bus!")
	await get_tree().create_timer(2.0).timeout
	_set_subtitle_visible(false)

func _resolve_subtitle_label():
	if _subtitle_label != null and is_instance_valid(_subtitle_label):
		return
	var hud := get_tree().root.find_child("Hud", true, false)
	if hud == null:
		return
	var candidate := hud.get_node_or_null("CanvasLayer/BoxContainer/Node2/subtitle")
	if candidate is Label:
		_subtitle_label = candidate
		_subtitle_label.visible = false

func _update_subtitle_text(text: String):
	_resolve_subtitle_label()
	if _subtitle_label == null:
		return
	_set_subtitle_visible(true)
	_subtitle_label.text = text

func _set_subtitle_visible(is_visible: bool):
	if _subtitle_label == null:
		return
	_subtitle_label.visible = is_visible

func _receive_messages():
	var packets_processed := 0
	while ws.get_available_packet_count() > 0 and packets_processed < MAX_PACKETS_PER_FRAME:
		packets_processed += 1
		_last_rx_ms = float(Time.get_ticks_msec())
		var raw_packet = ws.get_packet()
		if raw_packet.is_empty():
			continue

		var data = MsgPack.unpack(raw_packet)

		if typeof(data) != TYPE_DICTIONARY:
			continue

		match data.get("type"):
			"connect":
				player_id = data["id"]
				local_display_name = _resolve_server_username(data, player_id)
				local_skin_name = _resolve_server_skin(data, player_id, local_skin_name)
				_update_debug_skin()
				local_base_xp = int(data.get("xp", 0))
				session_earned_xp = 0.0
				
				player_display_names[player_id] = local_display_name
				player_skin_names[player_id] = local_skin_name
				print("My player ID:", player_id, "username:", local_display_name, "XP:", local_base_xp)
				print("My player skin:", local_skin_name)
				_resolve_ui_nodes()
				if camera_block != null:
					camera_block.visible = false
				if not _adopt_preserved_local_player(player_id, local_skin_name):
					_spawn_player(player_id, true, local_skin_name)
				_set_local_username(local_display_name)
				_set_local_player_id(player_id)
				_emit_player_event(
					"player_joined",
					"%s joined the game" % local_display_name,
					{"playerId": player_id}
				)
				if _waiting_for_connect:
					_waiting_for_connect = false
					print("✅ Received connect after reconnect, resyncing...")
					call_deferred("_resync_after_reconnect")

			"state":
				if data.has("players"):
					_update_world_state(data["players"], true, false)
				if data.has("chicken"):
					_update_chicken_state(data["chicken"], false)
				if data.has("lootbox"):
					_update_lootbox_state(data["lootbox"], false)
				if data.has("items"):
					_update_item_states(data["items"], true)
				if data.has("match") and typeof(data["match"]) == TYPE_DICTIONARY:
					_update_match_state(data["match"], false)
			"state_full":
				var quantized_full := bool(data.get("q", 0)) or bool(data.get("quantized", false))
				if data.has("players"):
					_update_world_state(data["players"], true, quantized_full)
				if data.has("chicken"):
					_update_chicken_state(data["chicken"], quantized_full, true)
				if data.has("lootbox"):
					_update_lootbox_state(data["lootbox"], quantized_full, true)
				if data.has("items"):
					_update_item_states(data["items"], true)
				if data.has("match") and typeof(data["match"]) == TYPE_DICTIONARY:
					_update_match_state(data["match"], quantized_full)
			"state_delta":
				var quantized_delta := bool(data.get("q", 0)) or bool(data.get("quantized", false))
				if data.has("players"):
					_update_world_state(data["players"], false, quantized_delta)
				if data.has("removed") and typeof(data["removed"]) == TYPE_ARRAY:
					_remove_disconnected_players(data["removed"])
				if data.has("chicken"):
					_update_chicken_state(data["chicken"], quantized_delta)
				if data.has("lootbox"):
					_update_lootbox_state(data["lootbox"], quantized_delta)
				if data.has("items"):
					_update_item_states(data["items"], true)
				if data.has("match") and typeof(data["match"]) == TYPE_DICTIONARY:
					_update_match_state(data["match"], quantized_delta)
			"reward_update":
				var earned_xp := int(data.get("xp", 0))
				var earned_mon := float(data.get("mon", 0.0))
				var pool_total := float(data.get("pool", 0.0))
				session_earned_xp = float(earned_xp)
				session_earned_mon = earned_mon
				var events_node = events_bridge
				if events_node == null or not is_instance_valid(events_node):
					events_node = get_tree().get_first_node_in_group("events_bridge")
				if events_node != null:
					if events_node.has_method("update_xp_display"):
						events_node.call("update_xp_display", earned_xp)
					if events_node.has_method("update_mon_display"):
						events_node.call("update_mon_display", earned_mon, pool_total)


# --- CLIENT-SIDE REWARDS ---
# Removed: reward accrual lives on the server now. The HUD is driven purely by
# the server's "reward_update" messages (see the message handler above).


# --- WORLD STATE UPDATE ---
func _decode_pos(p_state: Dictionary, key: String, quantized: bool) -> float:
	if quantized:
		return float(p_state.get(key, 0)) / POS_SCALE
	return float(p_state.get(key, 0.0))

func _decode_rot(p_state: Dictionary, key: String, quantized: bool) -> float:
	if quantized:
		return float(p_state.get(key, 0)) / ROT_SCALE
	return float(p_state.get(key, 0.0))

func _remove_disconnected_players(removed_ids: Array) -> void:
	for item in removed_ids:
		var removed_id := str(item)
		if removed_id != "" and removed_id != player_id:
			_remove_player(removed_id)

func _update_world_state(players_state, is_full := true, quantized := false):
	if _waiting_for_connect:
		return
	_received_ids_cache.clear()
	var received_ids := _received_ids_cache
	var now_ms := float(Time.get_ticks_msec())

	for p_state in players_state:
		if typeof(p_state) != TYPE_DICTIONARY:
			continue
		var id = str(p_state.get("id", ""))
		if id == "":
			continue
		received_ids[id] = true
		var resolved_name = _resolve_server_username(p_state, id)
		var previous_skin := str(player_skin_names.get(id, "")).strip_edges()
		var resolved_skin = _resolve_server_skin(p_state, id, player_skin_names.get(id, DEFAULT_SKIN_NAME))
		var skin_changed := previous_skin != "" and previous_skin != resolved_skin
		player_display_names[id] = resolved_name
		player_skin_names[id] = resolved_skin

		if id == player_id:
			local_skin_name = resolved_skin
			if players.has(id):
				players[id].display_name = resolved_name
				if skin_changed:
					_skin_applier.apply_skin(players[id], resolved_skin)
			continue

		var server_pos = Vector3(
			_decode_pos(p_state, "x", quantized),
			_decode_pos(p_state, "y", quantized),
			_decode_pos(p_state, "z", quantized)
		)
		var server_rot_y = _decode_rot(p_state, "r" if quantized else "rotationY", quantized)
		var anim_id = int(p_state.get("a", p_state.get("anim_id", 0)))
		var server_anim = str(ANIM_ID_TO_NAME.get(anim_id, "idle"))

		# Spawn if new
		if not players.has(id):
			_spawn_player(id, false, resolved_skin)
			players[id].global_position = server_pos  # FIX: spawn at correct position

		var node = players[id]
		node.display_name = resolved_name
		if skin_changed:
			_update_remote_player_skin(node, resolved_skin)

		# 🚗 Vehicle sync (passenger is locked to its seat; not interpolated).
		if p_state.has("vehicle") and p_state["vehicle"] != null:
			_sync_vehicle_player(node, p_state)
		else:
			# _push_remote_snapshot is the ONLY writer of the interpolation buffer.
			# Writing it here too double-shifted prev/curr to the same value, which
			# silently killed interpolation — remote players snapped at the raw
			# server update rate instead of lerping smoothly.
			_push_remote_snapshot(id, server_pos, server_rot_y, server_anim, now_ms)

		# Visibility (NO RETURN)
		node.visible = node.global_position.y <= 100

	# Remove disconnected players only on full snapshots.
	if is_full:
		for id in players:
			if id != player_id and not received_ids.has(id):
				_remove_player(id)


# --- CHICKEN SYNC ---
func _cache_chicken_node() -> void:
	if chicken_node != null and is_instance_valid(chicken_node):
		return
	var pickup_nodes = get_tree().get_nodes_in_group("pickup_items")
	for node in pickup_nodes:
		if node is RigidBody3D and node.name == "Chicken":
			chicken_node = node
			return
	chicken_node = get_tree().root.find_child("Chicken", true, false) as RigidBody3D

func _update_chicken_state(chicken_state: Dictionary, _quantized := false, _snap := false) -> void:
	# The server owns the chicken's spot and who holds it. While it is carried the
	# holder's back drives the visual (see _update_item_hold_visuals / LocalPickup),
	# otherwise the authoritative position below is applied. Positions are always
	# quantized by the server.
	chicken_is_held = bool(chicken_state.get("h", chicken_state.get("isHeld", false)))
	chicken_holder_id = str(chicken_state.get("o", chicken_state.get("holderId", "")))
	var has_pos := chicken_state.has("x")
	var pos := Vector3(
		_decode_pos(chicken_state, "x", true),
		_decode_pos(chicken_state, "y", true),
		_decode_pos(chicken_state, "z", true)
	)
	_set_item_server_state("Chicken", chicken_is_held, chicken_holder_id, pos, has_pos)
	_handle_chicken_state_event(chicken_is_held, chicken_holder_id)

func is_local_player_holding_chicken() -> bool:
	return chicken_is_held and chicken_holder_id == player_id

func get_chicken_node() -> RigidBody3D:
	_cache_chicken_node()
	return chicken_node

func _get_player_node_by_id(id: String) -> Node3D:
	if id == "":
		return null
	if players.has(id):
		return players[id]
	return null

func _build_hold_target_for_player(player_node: Node3D) -> Vector3:
	var forward = -player_node.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	var target_pos = player_node.global_position + (forward * CHICKEN_HOLD_DISTANCE)
	target_pos.y += CHICKEN_HOLD_HEIGHT
	return target_pos

func build_local_chicken_payload(player_pos: Vector3, view_forward: Vector3, visual_rot_y: float):
	if not is_local_player_holding_chicken():
		return null
	var forward = view_forward
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	var target_pos = player_pos + (forward * CHICKEN_HOLD_DISTANCE)
	target_pos.y += CHICKEN_HOLD_HEIGHT
	return {
		"x": target_pos.x,
		"y": target_pos.y,
		"z": target_pos.z,
		"rotation_y": visual_rot_y
	}


# --- LOOTBOX SYNC ---
func _cache_lootbox_node() -> void:
	if lootbox_node != null and is_instance_valid(lootbox_node):
		return
	var pickup_nodes = get_tree().get_nodes_in_group("pickup_items")
	for node in pickup_nodes:
		if node is RigidBody3D and node.name == "LootBox":
			lootbox_node = node
			return
	lootbox_node = get_tree().root.find_child("LootBox", true, false) as RigidBody3D

func _update_lootbox_state(lootbox_state: Dictionary, _quantized := false, _snap := false) -> void:
	# Same server-authoritative model as the chicken: the server owns the spot and
	# the holder; a carried lootbox rides the holder's back. Positions are always
	# quantized by the server.
	lootbox_is_held = bool(lootbox_state.get("h", lootbox_state.get("isHeld", false)))
	lootbox_holder_id = str(lootbox_state.get("o", lootbox_state.get("holderId", "")))
	var has_pos := lootbox_state.has("x")
	var pos := Vector3(
		_decode_pos(lootbox_state, "x", true),
		_decode_pos(lootbox_state, "y", true),
		_decode_pos(lootbox_state, "z", true)
	)
	_set_item_server_state("LootBox", lootbox_is_held, lootbox_holder_id, pos, has_pos)
	_handle_lootbox_state_event(lootbox_is_held, lootbox_holder_id)

func is_local_player_holding_lootbox() -> bool:
	return lootbox_is_held and lootbox_holder_id == player_id

func get_lootbox_node() -> RigidBody3D:
	_cache_lootbox_node()
	return lootbox_node


# Called by a local pickup right after it is grabbed or released. The hold is
# recorded optimistically here so the HUD and minimap react instantly, then the
# server is told so it can mirror the claim to everyone else.
func notify_item_held(item_id: String) -> void:
	item_local_held = item_id
	item_is_held[item_id] = true
	item_holder[item_id] = player_id
	if item_id == "Chicken":
		chicken_is_held = true
		chicken_holder_id = player_id
		_handle_chicken_state_event(chicken_is_held, chicken_holder_id)
	elif item_id == "LootBox":
		lootbox_is_held = true
		lootbox_holder_id = player_id
		_handle_lootbox_state_event(lootbox_is_held, lootbox_holder_id)
	_send_item_hold_message("pickup_request", item_id)


func notify_item_dropped(item_id: String) -> void:
	if item_local_held == item_id:
		item_local_held = ""
	item_is_held[item_id] = false
	item_holder[item_id] = ""
	if item_id == "Chicken":
		chicken_is_held = false
		chicken_holder_id = ""
		_handle_chicken_state_event(chicken_is_held, chicken_holder_id)
	elif item_id == "LootBox":
		lootbox_is_held = false
		lootbox_holder_id = ""
		_handle_lootbox_state_event(lootbox_is_held, lootbox_holder_id)
	_send_item_hold_message("drop_request", item_id)


# The local player USED a carried power-up. The server picks its new spot and
# broadcasts it back; locally it just hides until that arrives.
func notify_item_used(item_id: String) -> void:
	if item_local_held == item_id:
		item_local_held = ""
	item_is_held[item_id] = false
	item_holder[item_id] = ""
	_send_item_hold_message("use_request", item_id)


func _send_item_hold_message(msg_type: String, item_id: String) -> void:
	if player_id == "" or ws == null:
		return
	if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	ws.send(MsgPack.pack({"type": msg_type, "item_id": item_id}))


# --- SERVER-AUTHORITATIVE ITEM APPLICATION ---

func _is_objective_item_id(item_id: String) -> bool:
	return item_id == "Chicken" or item_id == "LootBox"


func _is_known_item_id(item_id: String) -> bool:
	return _is_objective_item_id(item_id) or POWER_UP_ITEM_IDS.has(item_id)


# Resolves (and caches) the world node for an item id. Only the local scene's own
# copies are resolved — every client has its own copy of every item.
func _get_item_node(item_id: String) -> Node3D:
	var cached = item_nodes.get(item_id)
	if cached != null and is_instance_valid(cached):
		return cached
	var found: Node3D = null
	for node in get_tree().get_nodes_in_group("local_pickup_items"):
		if node is Node3D and String(node.name) == item_id:
			found = node
			break
	if found == null:
		found = get_tree().root.find_child(item_id, true, false) as Node3D
	if found != null:
		item_nodes[item_id] = found
	return found


# Applies the server's hold/position state for one item. When held, the per-frame
# pass (remote holder) or LocalPickup (local holder) drives the visual; when free
# the authoritative spot is seated.
func _set_item_server_state(item_id: String, held: bool, holder: String, server_pos: Vector3, has_pos: bool) -> void:
	if not _is_known_item_id(item_id):
		return
	var was_held := bool(item_is_held.get(item_id, false))
	item_is_held[item_id] = held
	item_holder[item_id] = holder
	if held:
		if holder != player_id and item_local_held == item_id:
			# Snatched off us: drop the local claim without echoing to the server.
			_release_local_item_hold(item_id)
		return
	# Free: clear any stale remote-hold flag before seating, so a just-released
	# item is grabbable again even if its spot did not move.
	var node := _get_item_node(item_id)
	if node != null and is_instance_valid(node) and node.has_method("set_remote_held"):
		node.call("set_remote_held", false)
	if has_pos:
		# Force the seat when the item was just released, or when our copy is still
		# hidden (e.g. a used power-up the server re-rolled to a nearby spot), so it
		# always reappears instead of staying invisible.
		var hidden := node != null and is_instance_valid(node) and not node.visible
		_apply_item_spawn(item_id, server_pos, was_held or hidden)


func _update_item_states(items_state, quantized := true) -> void:
	if typeof(items_state) != TYPE_ARRAY:
		return
	for entry in items_state:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var item_id := str(entry.get("i", entry.get("id", "")))
		if item_id == "":
			continue
		var held := int(entry.get("h", entry.get("isHeld", 0))) != 0
		var holder := str(entry.get("o", entry.get("holderId", "")))
		var pos := Vector3(
			_decode_pos(entry, "x", quantized),
			_decode_pos(entry, "y", quantized),
			_decode_pos(entry, "z", quantized)
		)
		_set_item_server_state(item_id, held, holder, pos, true)


func _apply_item_spawn(item_id: String, pos: Vector3, force := false) -> void:
	if item_local_held == item_id:
		return
	var node := _get_item_node(item_id)
	if node == null or not is_instance_valid(node):
		return
	# Already at the server's spot (physics settled it there, or the same snapshot
	# is being repeated on the heartbeat)? Leave it alone so nothing jitters.
	if not force and node.global_position.distance_to(pos) < 0.4:
		return
	if node.has_method("apply_server_spawn"):
		node.call("apply_server_spawn", pos)
	elif node is RigidBody3D:
		var body := node as RigidBody3D
		body.freeze = true
		body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		body.global_position = pos
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.freeze = false


func _release_local_item_hold(item_id: String) -> void:
	if item_local_held == item_id:
		item_local_held = ""
	var local := players.get(player_id) as Node3D
	if local != null and local.has_method("release_item_if_holding"):
		local.call("release_item_if_holding", item_id)


# Back-of-the-holder offset for a carried item. The chicken and lootbox use their
# own distances/heights so a carried item sits the way the holder sees it.
func _build_item_hold_target(item_id: String, player_node: Node3D) -> Vector3:
	var forward = -player_node.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	var dist := LOOTBOX_HOLD_DISTANCE if item_id == "LootBox" else CHICKEN_HOLD_DISTANCE
	var height := LOOTBOX_HOLD_HEIGHT if item_id == "LootBox" else CHICKEN_HOLD_HEIGHT
	var target_pos = player_node.global_position + (forward * dist)
	target_pos.y += height
	return target_pos


# Per-frame visual pass for items carried by OTHER players: power-ups are hidden,
# objective items ride the holder's back (so everyone sees the chicken/lootbox).
# The local holder is left alone — LocalPickup drives its own copy.
func _update_item_hold_visuals() -> void:
	for item_id in item_is_held.keys():
		if not bool(item_is_held[item_id]):
			continue
		var holder := str(item_holder.get(item_id, ""))
		if holder == "" or holder == player_id:
			continue
		var node := _get_item_node(item_id)
		if node == null or not is_instance_valid(node):
			continue
		var is_objective := _is_objective_item_id(item_id)
		var pnode := _get_player_node_by_id(holder)
		if is_objective and pnode != null and is_instance_valid(pnode):
			if node.has_method("set_remote_held"):
				node.call("set_remote_held", true)
			node.visible = true
			node.global_position = _build_item_hold_target(item_id, pnode)
		else:
			if node.has_method("set_remote_held"):
				node.call("set_remote_held", true)
			node.visible = false


const LOOTBOX_HOLD_DISTANCE: float = 1.0
const LOOTBOX_HOLD_HEIGHT: float = 0.75

func build_local_lootbox_payload(player_pos: Vector3, view_forward: Vector3, visual_rot_y: float):
	if not is_local_player_holding_lootbox():
		return null
	var forward = view_forward
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	var target_pos = player_pos + (forward * LOOTBOX_HOLD_DISTANCE)
	target_pos.y += LOOTBOX_HOLD_HEIGHT
	return {
		"x": target_pos.x,
		"y": target_pos.y,
		"z": target_pos.z,
		"rotation_y": visual_rot_y
	}


# --- VEHICLE SYNC ---
func _sync_vehicle_player(player_node: Node3D, p_state):
	var vehicle_name = p_state["vehicle"]
	var seat_index = int(p_state.get("seat", 0))

	var vehicle = get_node_or_null("/root/World/%s" % vehicle_name)
	if vehicle == null:
		return

	var seats = vehicle.get_node_or_null("Seats")
	if seats == null:
		return

	var seat = seats.get_child(seat_index)
	if seat == null:
		return

	if player_node.get_parent() != vehicle:
		player_node.get_parent().remove_child(player_node)
		vehicle.add_child(player_node)

	player_node.global_position = seat.global_position
	player_node.global_rotation = seat.global_rotation


# --- SPAWN ---
func _spawn_player(id: String, p_is_local := false, skin_name: String = DEFAULT_SKIN_NAME):
	_update_debug_skin()
	var player: Node3D
	if p_is_local:
		player = _instantiate_player_scene_for_skin(skin_name)
		add_child(player)
		player.add_to_group("local_player")
		_skin_applier.apply_skin(player, skin_name)
	else:
		player = _get_player_from_pool()
		_update_remote_player_skin(player, skin_name)
		player.visible = true

	player.name = "Player_%s" % id
	player.player_id = id
	player.display_name = _get_player_display_name(id)
	player.is_local = p_is_local
	player.root = self

	if p_is_local and myplayerswpanpoint:
		player.global_position = myplayerswpanpoint.global_position
		print("🧍 Local player spawned at spawn point:", id)
		player._spawn_flash()
	else:
		# Temporary safe height until first state update
		player.global_position = Vector3(0, 2, 0)
		print("👤 Remote player spawned:", id)

	players[id] = player

const _KEPT_NODE_NAMES: Array[String] = ["animator", "AnimationTree", "Label3D"]

func _update_remote_player_skin(player: Node3D, skin_name: String):
	var scene := _get_skin_scene(skin_name)
	if scene == null: return
	
	# Track current skin to avoid redundant swaps
	var current_skin: String = player.get_meta("current_skin", "")
	if current_skin == skin_name:
		return
	player.set_meta("current_skin", skin_name)
	
	# Strip old visuals — keep animation infrastructure alive so @onready
	# references in RemotePlayer.gd don't go stale.
	var kept := {}
	for kept_name in _KEPT_NODE_NAMES:
		var child = player.get_node_or_null(kept_name)
		if child != null:
			player.remove_child(child)
			kept[kept_name] = child
	for child in player.get_children():
		player.remove_child(child)
		child.queue_free()
	for kept_name in _KEPT_NODE_NAMES:
		var child = kept.get(kept_name)
		if child != null:
			player.add_child(child)
	
	# Add new visuals
	var source = scene.instantiate()
	_strip_physics_nodes(source)
	_skin_applier.apply_skin(source, skin_name)
	for child in source.get_children():
		if child.name in _KEPT_NODE_NAMES:
			child.queue_free()
			continue
		source.remove_child(child)
		child.owner = null
		player.add_child(child)
	# Record applied skin on the player so TWIN decoys can match
	_skin_applier.apply_skin(player, skin_name)
	player.set_meta(SkinApplier.APPLIED_SKIN_META, skin_name)
	source.queue_free()

	# The new Skeleton3D starts visible; re-apply LOD so a distant player
	# doesn't pop its mesh back in until the next LOD tick.
	if player.has_method("refresh_mesh_lod"):
		player.refresh_mesh_lod()

func get_local_spawn_position() -> Vector3:
	if myplayerswpanpoint:
		return myplayerswpanpoint.global_position
	return Vector3(0, 2, 0)

func _instantiate_player_scene_for_skin(skin_name: String) -> Node3D:
	var scene := _get_skin_scene(skin_name)
	if scene != null:
		var player := scene.instantiate()
		_skin_applier.apply_skin(player, skin_name)
		return player
	if player_scene != null:
		return player_scene.instantiate()
	push_error("No player scene available for skin '%s'." % skin_name)
	return Node3D.new()

func _instantiate_remote_player_for_skin(skin_name: String) -> Node3D:
	var source: Node = null
	var scene := _get_skin_scene(skin_name)
	if scene != null:
		source = scene.instantiate()
	elif player_scene != null:
		source = player_scene.instantiate()
	else:
		push_error("No remote player scene available for skin '%s'." % skin_name)
		return Node3D.new()

	return _convert_scene_to_remote_player(source)

func _convert_scene_to_remote_player(source: Node) -> Node3D:
	var remote_player: Node3D = REMOTE_PLAYER_SCRIPT.new()
	remote_player.name = source.name

	_strip_physics_nodes(source)

	for child in source.get_children():
		source.remove_child(child)
		child.owner = null
		remote_player.add_child(child)

	source.queue_free()
	return remote_player

func _strip_physics_nodes(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionObject3D or child is CollisionShape3D or child is Area3D or child is RayCast3D:
			node.remove_child(child)
			child.queue_free()
			continue
		_strip_physics_nodes(child)


# --- REMOVE ---
func _remove_player(id: String):
	if players.has(id):
		var p = players[id]
		if p.is_local:
			p.queue_free()
		else:
			_return_player_to_pool(p)
		players.erase(id)
		player_display_names.erase(id)
		player_skin_names.erase(id)
		if id == player_id:
			_cached_local_player = null
	remote_snapshots.erase(id)

func _cleanup_stale_remote_players(now_ms: float) -> void:
	var stale := PackedStringArray()
	for id in players:
		if id == player_id:
			continue
		var node: Node3D = players.get(id) as Node3D
		if node == null:
			stale.append(id)
			continue
		# Vehicle passengers are locked to a seat and have no interpolation buffer;
		# full snapshots keep them alive, so lack of a buffer is not staleness.
		if node.get_parent() != self:
			continue
		var snap = remote_snapshots.get(id)
		if snap == null:
			stale.append(id)
			continue
		var last_t := float(snap.get("curr_t", 0.0))
		if now_ms - last_t > 10000.0:
			stale.append(id)
	for id in stale:
		_remove_player(id)

func _push_remote_snapshot(id: String, pos: Vector3, rot_y: float, anim: String, now_ms: float) -> void:
	var snap = remote_snapshots.get(id, null)
	if snap == null:
		remote_snapshots[id] = {
			"prev_pos": pos,
			"curr_pos": pos,
			"prev_rot": rot_y,
			"curr_rot": rot_y,
			"prev_t": now_ms,
			"curr_t": now_ms,
			"interp_delay_ms": REMOTE_INTERP_BACKTIME_MS,
			"prev_vel": Vector3.ZERO,
			"curr_vel": Vector3.ZERO,
			"rot_vel": 0.0,
			"anim": anim
		}
		return

	snap["prev_pos"] = snap["curr_pos"]
	snap["curr_pos"] = pos
	snap["prev_rot"] = snap["curr_rot"]
	snap["curr_rot"] = rot_y
	snap["prev_t"] = snap["curr_t"]
	snap["curr_t"] = now_ms
	# Floor at one frame: a burst of deltas delivered in the same frame would
	# otherwise yield a ~1 ms interval, inflating the derived velocity ~50x and
	# (through extrapolation) teleporting the avatar on the next late packet.
	var pos_dt := maxf(REMOTE_MIN_SNAPSHOT_DT_MS, snap["curr_t"] - snap["prev_t"])
	var prev_interp_delay := float(snap.get("interp_delay_ms", REMOTE_INTERP_BACKTIME_MS))
	# Delay slightly UNDER the observed interval: render_time crosses curr_t each
	# cycle and the leftover gap is bridged by extrapolation (see
	# _apply_remote_interpolation), so dropped/late packets don't freeze-then-jump.
	var target_interp_delay := clampf(pos_dt * 0.9, REMOTE_MIN_INTERP_BACKTIME_MS, REMOTE_MAX_INTERP_BACKTIME_MS)
	snap["interp_delay_ms"] = lerpf(prev_interp_delay, target_interp_delay, 0.35)
	snap["prev_vel"] = snap.get("curr_vel", Vector3.ZERO)
	var from_pos: Vector3 = snap["prev_pos"]
	var to_pos: Vector3 = snap["curr_pos"]
	var vel: Vector3 = (to_pos - from_pos) / (pos_dt / 1000.0)
	if vel.length() > REMOTE_MAX_EXTRAP_SPEED:
		vel = vel.normalized() * REMOTE_MAX_EXTRAP_SPEED
	snap["curr_vel"] = vel
	snap["rot_vel"] = angle_difference(snap["curr_rot"], snap["prev_rot"]) / (pos_dt / 1000.0)
	snap["anim"] = anim
	remote_snapshots[id] = snap

func _smoothstep01(t: float) -> float:
	var clamped := clampf(t, 0.0, 1.0)
	return clamped * clamped * (3.0 - 2.0 * clamped)

func _hermite_vec3(p0: Vector3, p1: Vector3, m0: Vector3, m1: Vector3, t: float, dt_seconds: float) -> Vector3:
	var tt := clampf(t, 0.0, 1.0)
	var tt2 := tt * tt
	var tt3 := tt2 * tt
	var h00 := 2.0 * tt3 - 3.0 * tt2 + 1.0
	var h10 := tt3 - 2.0 * tt2 + tt
	var h01 := -2.0 * tt3 + 3.0 * tt2
	var h11 := tt3 - tt2
	return (p0 * h00) + (m0 * (dt_seconds * h10)) + (p1 * h01) + (m1 * (dt_seconds * h11))

func _apply_remote_interpolation() -> void:
	var delta := get_process_delta_time()
	_remote_lod_timer += delta
	var do_lod_check := false
	if _remote_lod_timer >= REMOTE_LOD_INTERVAL:
		_remote_lod_timer = 0.0
		do_lod_check = true

	var now_ms := float(Time.get_ticks_msec())
	if players.size() <= 1:
		return
	var local_player_node: Node3D = _get_local_player_node()
	var local_pos := local_player_node.global_position if local_player_node else Vector3.ZERO

	for id in players:
		if id == player_id:
			continue
		var node = players[id]
		if node == null:
			continue
		# Vehicle passengers are locked to their seat by _sync_vehicle_player and
		# are not part of the positional interpolation buffer.
		if node.get_parent() != self:
			continue
		if not remote_snapshots.has(id):
			continue

		var dist_sq := local_pos.distance_squared_to(node.global_position)

		# Aggressive Cull: Hide players very far away
		if do_lod_check:
			var is_near := dist_sq < 2500.0 # 50 meters
			node.visible = is_near
			if not is_near:
				continue
		elif not node.visible:
			continue

		var snap: Dictionary = remote_snapshots[id]
		var render_time := now_ms - float(snap.get("interp_delay_ms", REMOTE_INTERP_BACKTIME_MS))
		var prev_t := float(snap.get("prev_t", render_time))
		var curr_t := float(snap.get("curr_t", prev_t))
		
		var dt := maxf(REMOTE_MIN_SNAPSHOT_DT_MS, curr_t - prev_t)
		var t := clampf((render_time - prev_t) / dt, 0.0, 1.0)
		
		# Simpler math for mobile: Use Lerp instead of Hermite for all players
		var prev_pos: Vector3 = snap.get("prev_pos", node.global_position)
		var curr_pos: Vector3 = snap.get("curr_pos", prev_pos)
		node.global_position = prev_pos.lerp(curr_pos, t)

		# Extrapolation: when the next snapshot hasn't arrived yet (jitter or packet
		# loss), keep drifting with the last known velocity instead of freezing and
		# later teleporting. Capped so we never run ahead of the latest data; the
		# next snapshot resumes the lerp seamlessly.
		var render_error_ms := render_time - curr_t
		if render_error_ms > 0.0:
			var extrap_sec := minf(render_error_ms / 1000.0, REMOTE_MAX_EXTRAPOLATE_MS / 1000.0)
			var pos_vel: Vector3 = snap.get("curr_vel", Vector3.ZERO)
			if pos_vel.length() > REMOTE_MAX_EXTRAP_SPEED:
				pos_vel = pos_vel.normalized() * REMOTE_MAX_EXTRAP_SPEED
			node.global_position = curr_pos + pos_vel * extrap_sec

		var prev_rot := float(snap.get("prev_rot", node.rotation.y))
		var curr_rot := float(snap.get("curr_rot", prev_rot))
		node.rotation.y = lerp_angle(prev_rot, curr_rot, t)

		if do_lod_check:
			var anim_state := str(snap.get("anim", "idle"))
			var should_animate := dist_sq <= REMOTE_ANIMATION_LOD_DISTANCE_SQ
			if node.has_method("set_animation_lod_enabled"):
				node.set_animation_lod_enabled(should_animate)
			if node.has_method("set_mesh_lod_enabled"):
				node.set_mesh_lod_enabled(should_animate)
			if should_animate and node.has_method("set_animation_state"):
				node.set_animation_state(anim_state)

func _get_local_player_node() -> Node3D:
	if _cached_local_player != null and is_instance_valid(_cached_local_player):
		return _cached_local_player
	if player_id == "":
		return null
	if players.has(player_id):
		var player_node: Node3D = players[player_id]
		if player_node is Node3D:
			_cached_local_player = player_node
			return player_node
	_cached_local_player = null
	return null

func _resolve_events_bridge() -> void:
	events_bridge = get_tree().get_first_node_in_group("events_bridge")

func _resolve_ui_nodes() -> void:
	if countdown_label == null and countdown_label_path != NodePath():
		countdown_label = get_node_or_null(countdown_label_path)
	if world_environment == null and world_environment_path != NodePath():
		world_environment = get_node_or_null(world_environment_path)
	if camera_block == null and camera_block_path != NodePath():
		camera_block = get_node_or_null(camera_block_path)
	if world_environment != null and world_environment.environment and not _world_env_duplicated:
		world_environment.environment = world_environment.environment.duplicate()
		_world_env_duplicated = true

# Null-safe integer read for match/player state. MsgPack delivers JSON null
# (e.g. "max" is null while no active match caps players) and int(null) throws
# "Nonexistent 'int' constructor"; fall back to the default instead.
func _match_int(match_state: Dictionary, key: String, default: int) -> int:
	var v: Variant = match_state.get(key, default)
	if v is int:
		return v
	if v is float:
		return int(v)
	if v is bool:
		return 1 if v else 0
	return default

func _update_match_state(match_state: Dictionary, quantized := false) -> void:
	var now_ms := float(Time.get_ticks_msec())
	if quantized:
		match_duration_seconds = maxf(1.0, float(match_state.get("d", int(match_duration_seconds * 100.0))) / 100.0)
		match_time_left = clampf(float(match_state.get("t", int(match_time_left * 100.0))) / 100.0, 0.0, match_duration_seconds)
		match_is_running = bool(match_state.get("r", 0))
		var sr: int = match_state.get("sr", -1)
		if sr >= 0:
			_apply_storm_radius(float(sr) / 100.0)
		connected_player_count = maxi(0, _match_int(match_state, "pl", connected_player_count))
		min_players_to_start = maxi(0, _match_int(match_state, "min", min_players_to_start))
		max_players = maxi(0, _match_int(match_state, "max", max_players))
		start_countdown_sec = maxi(0, _match_int(match_state, "c", 0))
	else:
		match_duration_seconds = maxf(1.0, float(match_state.get("durationSeconds", match_duration_seconds)))
		match_time_left = clampf(float(match_state.get("timeLeft", match_time_left)), 0.0, match_duration_seconds)
		match_is_running = bool(match_state.get("isRunning", false))
		var sr: float = match_state.get("stormRadius", -1.0)
		if sr >= 0:
			_apply_storm_radius(sr)
		connected_player_count = maxi(0, _match_int(match_state, "playerCount", connected_player_count))
		min_players_to_start = maxi(0, _match_int(match_state, "minPlayersToStart", min_players_to_start))
		max_players = maxi(0, _match_int(match_state, "maxPlayers", max_players))
		start_countdown_sec = maxi(0, _match_int(match_state, "startCountdown", 0))

	if match_is_running:
		# Anchor the HUD clock to real time so it stays synced even if gameplay speed changes.
		_match_clock_anchor_ms = now_ms
		_match_clock_anchor_time_left = match_time_left
	else:
		_match_clock_anchor_ms = 0.0
		_match_clock_anchor_time_left = match_time_left
	_update_match_ui()

func is_match_running() -> bool:
	return match_is_running

func is_waiting_for_players() -> bool:
	return not match_is_running

func _update_match_ui() -> void:
	_resolve_ui_nodes()
	if countdown_label != null:
		var new_text: String
		if match_is_running:
			var whole_seconds := maxi(0, int(ceil(match_time_left)))
			var minutes = int(whole_seconds / 60.0)
			var seconds = whole_seconds % 60
			new_text = "%02d:%02d" % [minutes, seconds]
		else:
			# Pre-match lobby polish: show a live start countdown once enough
			# players are connected, otherwise how many more are needed. If the
			# server hasn't reported the live count yet (pre-/old build), fall back
			# to counting ourselves rather than printing a bogus "N more".
			if start_countdown_sec > 0:
				new_text = "Match starts in %d…" % start_countdown_sec
			elif min_players_to_start > 0:
				var count := connected_player_count
				if count <= 0 and connected and player_id != "":
					count = 1  # we can at least count ourselves
				var need := maxi(0, min_players_to_start - count)
				if count <= 0:
					new_text = "Waiting for players…"
				elif need > 0:
					var plural := "s" if need != 1 else ""
					new_text = "Waiting for %d more player%s…" % [need, plural]
				else:
					new_text = "Match starting…"
			else:
				new_text = "Waiting for players"
		if new_text != _last_countdown_text:
			_last_countdown_text = new_text
			countdown_label.text = new_text

	# Keep camera blocker hidden after joining the server.
	if camera_block != null and player_id != "":
		camera_block.visible = false



func _apply_storm_radius(radius: float) -> void:
	if _storm_env_node == null or not is_instance_valid(_storm_env_node):
		# The storm node is named "env" in gameplay.tscn; look it up by the group
		# StormEye registers itself in so a rename can't silently break this again.
		_storm_env_node = get_tree().get_first_node_in_group("storm_eye")
		if _storm_env_node == null:
			_storm_env_node = get_tree().root.find_child("env", true, false)
		if _storm_env_node == null:
			_storm_env_node = get_tree().root.find_child("enviroment", true, false)
	if _storm_env_node and _storm_env_node.has_method("set_storm_radius"):
		_storm_env_node.set_storm_radius(radius)

func _set_local_username(name_text: String) -> void:
	if events_bridge != null and is_instance_valid(events_bridge) and events_bridge.has_method("set_local_username"):
		events_bridge.set_local_username(name_text)

func _set_local_player_id(id_text: String) -> void:
	if events_bridge != null and is_instance_valid(events_bridge) and events_bridge.has_method("set_local_player_id"):
		events_bridge.set_local_player_id(id_text)

func send_xp_update(total_xp: int) -> void:
	if connected and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send(MsgPack.pack({
			"type": "update_xp",
			"xp": total_xp
		}))

static func send_xp_update_static(total_xp: int) -> void:
	if instance:
		instance.send_xp_update(total_xp)

func _show_local_event(message: String) -> void:
	if events_bridge != null and is_instance_valid(events_bridge) and events_bridge.has_method("show_local_event"):
		events_bridge.show_local_event(message)

func _emit_player_event(event_type: String, message: String, meta: Dictionary = {}) -> void:
	_show_local_event(message)
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send(MsgPack.pack({
			"type": "client_event",
			"eventType": event_type,
			"message": message,
			"meta": meta
		}))

func _format_player_short_name(id: String) -> String:
	if id == "":
		return "player"
	return id.substr(0, 8)

func _get_player_display_name(id: String) -> String:
	var candidate = str(player_display_names.get(id, "")).strip_edges()
	if candidate != "":
		return candidate
	return _format_player_short_name(id)

func _resolve_local_username() -> void:
	if not OS.has_feature("web"):
		return
	var raw_username = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('username') || ''")
	if typeof(raw_username) != TYPE_STRING:
		return
	local_username = str(raw_username).strip_edges()

func _resolve_local_skin_name() -> void:
	if selected_skin_id.strip_edges() != "":
		local_skin_name = _normalize_skin_name(selected_skin_id)
		return
	if not OS.has_feature("web"):
		return
	var raw_skin = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('skin') || ''")
	if typeof(raw_skin) != TYPE_STRING:
		return
	var skin_name := str(raw_skin).strip_edges()
	if skin_name != "":
		local_skin_name = _normalize_skin_name(skin_name)

func _pre_seed_from_session_storage() -> void:
	if not OS.has_feature("web"):
		return
	var raw = JavaScriptBridge.eval("sessionStorage.getItem('wons_skin_cache') || ''")
	if typeof(raw) != TYPE_STRING or raw.is_empty():
		return
	var parsed = JSON.parse_string(raw)
	if parsed is Array:
		SkinApplier.seed_from_api(parsed)
		_update_debug2_cache()
		_update_debug_skin()

func _get_skin_scene(_skin_name: String) -> PackedScene:
	if _cached_skin_scene == null:
		_cached_skin_scene = load(SKIN_SCENE_PATH) as PackedScene
	return _cached_skin_scene

func _resolve_server_skin(data: Dictionary, fallback_id: String, fallback_skin: String = DEFAULT_SKIN_NAME) -> String:
	for key in ["skin", "skinName", "skin_name", "skinId", "skin_id", "s"]:
		var candidate := str(data.get(key, "")).strip_edges()
		if candidate != "":
			return _normalize_skin_name(candidate)
	var cached := str(player_skin_names.get(fallback_id, "")).strip_edges()
	if cached != "":
		return _normalize_skin_name(cached)
	if fallback_skin != "":
		return _normalize_skin_name(fallback_skin)
	return DEFAULT_SKIN_NAME

func _normalize_skin_name(raw_skin: String) -> String:
	var key := str(raw_skin).strip_edges().to_lower()
	while key.find("  ") != -1:
		key = key.replace("  ", " ")
	if SKIN_NAME_ALIASES.has(key):
		return str(SKIN_NAME_ALIASES[key])
	return key if key != "" else DEFAULT_SKIN_NAME

func _build_ws_url_with_username(base_url: String) -> String:
	if local_username == "":
		return base_url
	var joiner = "&" if base_url.find("?") != -1 else "?"
	var skin_param := ""
	if local_skin_name != "":
		skin_param = "&skin=%s" % local_skin_name.uri_encode()
	return "%s%susername=%s%s" % [base_url, joiner, local_username.uri_encode(), skin_param]

func _resolve_server_username(data: Dictionary, fallback_id: String) -> String:
	var candidate := str(data.get("u", data.get("username", ""))).strip_edges()
	if candidate != "":
		return candidate
	var cached := str(player_display_names.get(fallback_id, "")).strip_edges()
	if cached != "":
		return cached
	return _format_player_short_name(fallback_id)

func _handle_chicken_state_event(current_is_held: bool, current_holder_id: String) -> void:
	var holder_name = _get_player_display_name(current_holder_id)
	var local_name = _get_player_display_name(player_id)

	if not _last_chicken_is_held and current_is_held and current_holder_id == player_id:
		_emit_player_event(
			"chicken_picked",
			"%s picked the chicken" % holder_name,
			{"item": "chicken", "action": "pick"}
		)

	if _last_chicken_is_held and _last_chicken_holder_id == player_id and not current_is_held:
		_emit_player_event(
			"chicken_dropped",
			"%s dropped the chicken" % local_name,
			{"item": "chicken", "action": "drop"}
		)

	_last_chicken_is_held = current_is_held
	_last_chicken_holder_id = current_holder_id

func _handle_lootbox_state_event(current_is_held: bool, current_holder_id: String) -> void:
	var holder_name = _get_player_display_name(current_holder_id)
	var local_name = _get_player_display_name(player_id)

	if not _last_lootbox_is_held and current_is_held and current_holder_id == player_id:
		_emit_player_event(
			"lootbox_picked",
			"%s picked the lootbox" % holder_name,
			{"item": "lootbox", "action": "pick"}
		)

	if _last_lootbox_is_held and _last_lootbox_holder_id == player_id and not current_is_held:
		_emit_player_event(
			"lootbox_dropped",
			"%s dropped the lootbox" % local_name,
			{"item": "lootbox", "action": "drop"}
		)

	_last_lootbox_is_held = current_is_held
	_last_lootbox_holder_id = current_holder_id
