# WorldManager.gd
extends Node3D

# --- SERVER URLS ---
const LIVE_URL = "wss://worldofnads.onrender.com"
const LOCAL_URL = "ws://localhost:8080"

@export var player_scene: PackedScene 
@export var myplayerswpanpoint: Marker3D
@export var countdown_label_path: NodePath
@export var world_environment_path: NodePath = NodePath("WorldEnvironment")
@export var camera_block_path: NodePath = NodePath("CAMERABlock")

# --- PARALLAX BACKGROUND NODES ---
@export_group("Parallax Background")
@export var parallax_layer_1: ParallaxLayer
@export var parallax_layer_2: ParallaxLayer
@export var parallax_layer_3: ParallaxLayer

# --- NETWORK & STATE VARIABLES ---
var ws := WebSocketPeer.new()
var connected := false
var player_id := ""
var players := {}
var is_local: bool
var root: Node
const CHICKEN_HOLD_DISTANCE := 0.9
const CHICKEN_HOLD_HEIGHT := 1.0
const POS_SCALE := 100.0
const ROT_SCALE := 1000.0
const ANIM_ID_TO_NAME := {
	0: "idle",
	1: "running"
}
const REMOTE_INTERP_BACKTIME_MS := 120.0
const REMOTE_MAX_EXTRAPOLATE_MS := 0.0

# --- CHICKEN AUTHORITY STATE ---
var chicken_node: RigidBody3D = null
var chicken_is_held := false
var chicken_holder_id := ""
var events_bridge: Node = null
var _last_chicken_is_held := false
var _last_chicken_holder_id := ""
var local_username := ""
var local_display_name := "player"
var player_display_names := {}
var remote_snapshots := {}
var countdown_label: Label = null
var world_environment: WorldEnvironment = null
var camera_block: Node3D = null
var _world_env_duplicated := false
var match_duration_seconds := 180.0
var match_time_left := 180.0
var match_is_running := false
var fog_start_color: Color =  Color8(202, 189, 240)
var fog_end_color: Color = Color8(255, 100, 215)

# --- FALLBACK LOGIC ---
var is_connecting_to_live = true
var connection_attempted = false
@onready var fallback_timer: Timer = $FallbackTimer

func _ready():
	_resolve_local_username()
	fallback_timer.timeout.connect(_on_fallback_timer_timeout)
	_attempt_connection()
	_cache_chicken_node()
	_resolve_events_bridge()
	_resolve_ui_nodes()
	_update_match_ui()

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

func _process(_delta):
	if events_bridge == null or not is_instance_valid(events_bridge):
		_resolve_events_bridge()

	if not connection_attempted:
		return

	ws.poll()
	var state = ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN and not connected:
		connected = true
		var server_type = "LIVE" if is_connecting_to_live else "LOCAL"
		print("✅ Connected to %s server!" % server_type)

	elif state == WebSocketPeer.STATE_CLOSED:
		if connected:
			print("❌ Disconnected from server.")
			connected = false
			connection_attempted = false
		elif is_connecting_to_live:
			print("❌ Live server connection failed.")
			_trigger_fallback()

	if connected:
		_receive_messages()
		_apply_remote_interpolation()

func _trigger_fallback():
	is_connecting_to_live = false
	connection_attempted = false
	print("⏳ Starting fallback to local server in 1 second...")
	fallback_timer.start(1.0)

func _on_fallback_timer_timeout():
	_attempt_connection()

func _receive_messages():
	while ws.get_available_packet_count() > 0:
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
				player_display_names[player_id] = local_display_name
				print("My player ID:", player_id, "username:", local_display_name)
				_resolve_ui_nodes()
				if camera_block != null:
					camera_block.visible = false
				_spawn_player(player_id, true)
				_set_local_username(local_display_name)
				_set_local_player_id(player_id)
				_emit_player_event(
					"player_joined",
					"%s joined the game" % local_display_name,
					{"playerId": player_id}
				)

			"state":
				if data.has("players"):
					_update_world_state(data["players"], true, false)
				if data.has("chicken"):
					_update_chicken_state(data["chicken"], false)
				if data.has("match") and typeof(data["match"]) == TYPE_DICTIONARY:
					_update_match_state(data["match"], false)
			"state_full":
				var quantized_full := bool(data.get("q", 0)) or bool(data.get("quantized", false))
				if data.has("players"):
					_update_world_state(data["players"], true, quantized_full)
				if data.has("chicken"):
					_update_chicken_state(data["chicken"], quantized_full)
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
				if data.has("match") and typeof(data["match"]) == TYPE_DICTIONARY:
					_update_match_state(data["match"], quantized_delta)


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
	var received_ids := {}
	var now_ms := float(Time.get_ticks_msec())

	for p_state in players_state:
		if typeof(p_state) != TYPE_DICTIONARY:
			continue
		var id = str(p_state.get("id", ""))
		if id == "":
			continue
		received_ids[id] = true
		var resolved_name = _resolve_server_username(p_state, id)
		player_display_names[id] = resolved_name

		if id == player_id:
			if players.has(id):
				players[id].display_name = resolved_name
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
			_spawn_player(id, false)
			players[id].global_position = server_pos  # FIX: spawn at correct position
			remote_snapshots[id] = {
				"prev_pos": server_pos,
				"curr_pos": server_pos,
				"prev_rot": server_rot_y,
				"curr_rot": server_rot_y,
				"prev_t": now_ms,
				"curr_t": now_ms,
				"anim": server_anim
			}

		var node = players[id]
		node.display_name = resolved_name

		# 🚗 Vehicle sync
		if p_state.has("vehicle") and p_state["vehicle"] != null:
			_sync_vehicle_player(node, p_state)
		else:
			_push_remote_snapshot(id, server_pos, server_rot_y, server_anim, now_ms)

		# Visibility (NO RETURN)
		node.visible = node.global_position.y <= 100

	# Remove disconnected players only on full snapshots.
	if is_full:
		for id in players.keys():
			if id != player_id and not received_ids.has(id):
				_remove_player(id)


# --- CHICKEN SYNC ---
func _cache_chicken_node() -> void:
	if chicken_node != null and is_instance_valid(chicken_node):
		return
	var pickup_node = get_tree().get_first_node_in_group("pickup_items")
	if pickup_node != null and pickup_node is RigidBody3D:
		chicken_node = pickup_node

func _update_chicken_state(chicken_state: Dictionary, quantized := false) -> void:
	_cache_chicken_node()
	if chicken_node == null:
		return

	var server_target_pos = Vector3(
		(float(chicken_state.get("x", chicken_node.global_position.x)) / POS_SCALE) if quantized else float(chicken_state.get("x", chicken_node.global_position.x)),
		(float(chicken_state.get("y", chicken_node.global_position.y)) / POS_SCALE) if quantized else float(chicken_state.get("y", chicken_node.global_position.y)),
		(float(chicken_state.get("z", chicken_node.global_position.z)) / POS_SCALE) if quantized else float(chicken_state.get("z", chicken_node.global_position.z))
	)
	var server_target_rot_y = (float(chicken_state.get("r", chicken_node.global_rotation.y)) / ROT_SCALE) if quantized else float(chicken_state.get("rotationY", chicken_node.global_rotation.y))
	chicken_is_held = bool(chicken_state.get("h", chicken_state.get("isHeld", false)))
	chicken_holder_id = str(chicken_state.get("o", chicken_state.get("holderId", "")))
	_handle_chicken_state_event(chicken_is_held, chicken_holder_id)

	# Ignore server chicken pose while local player is holder.
	# Local holder already drives a smoother client-side hold visual in Player.gd.
	if chicken_is_held and chicken_holder_id == player_id:
		return

	var target_pos = server_target_pos
	var target_rot_y = server_target_rot_y

	if chicken_node.has_method("apply_network_state"):
		chicken_node.apply_network_state(target_pos, target_rot_y, chicken_is_held)
	else:
		chicken_node.freeze = true
		chicken_node.global_position = chicken_node.global_position.lerp(target_pos, 0.45)
		var rot = chicken_node.global_rotation
		rot.y = lerp_angle(rot.y, target_rot_y, 0.45)
		chicken_node.global_rotation = rot

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
func _spawn_player(id: String, is_local := false):
	var player = player_scene.instantiate()
	player.name = "Player_%s" % id
	add_child(player)

	player.player_id = id
	player.display_name = _get_player_display_name(id)
	player.is_local = is_local
	player.root = self

	# Inject parallax layers if this is the local player
	if is_local:
		player.parallax_layer_1 = parallax_layer_1
		player.parallax_layer_2 = parallax_layer_2
		player.parallax_layer_3 = parallax_layer_3

	if is_local and myplayerswpanpoint:
		player.global_position = myplayerswpanpoint.global_position
		print("🧍 Local player spawned at spawn point:", id)
	else:
		# Temporary safe height until first state update
		player.global_position = Vector3(0, 2, 0)
		print("👤 Remote player spawned:", id)

	players[id] = player


# --- REMOVE ---
func _remove_player(id: String):
	if players.has(id):
		if players[id].is_queued_for_deletion():
			return
		players[id].queue_free()
		players.erase(id)
	player_display_names.erase(id)
	remote_snapshots.erase(id)

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
			"anim": anim
		}
		return

	snap["prev_pos"] = snap["curr_pos"]
	snap["curr_pos"] = pos
	snap["prev_rot"] = snap["curr_rot"]
	snap["curr_rot"] = rot_y
	snap["prev_t"] = snap["curr_t"]
	snap["curr_t"] = now_ms
	snap["anim"] = anim
	remote_snapshots[id] = snap

func _apply_remote_interpolation() -> void:
	var render_time := float(Time.get_ticks_msec()) - REMOTE_INTERP_BACKTIME_MS
	for id in players.keys():
		if id == player_id:
			continue
		if not remote_snapshots.has(id):
			continue
		var node = players[id]
		if node == null:
			continue
		var snap: Dictionary = remote_snapshots[id]
		var prev_t := float(snap.get("prev_t", render_time))
		var curr_t := float(snap.get("curr_t", prev_t))
		var prev_pos: Vector3 = snap.get("prev_pos", node.global_position)
		var curr_pos: Vector3 = snap.get("curr_pos", prev_pos)
		var prev_rot := float(snap.get("prev_rot", node.rotation.y))
		var curr_rot := float(snap.get("curr_rot", prev_rot))

		var dt := maxf(1.0, curr_t - prev_t)
		var t := clampf((render_time - prev_t) / dt, 0.0, 1.0)
		var out_pos := prev_pos.lerp(curr_pos, t)
		var out_rot := lerp_angle(prev_rot, curr_rot, t)

		# If we're beyond newest snapshot, apply a tiny extrapolation window.
		if render_time > curr_t:
			var late_ms := minf(render_time - curr_t, REMOTE_MAX_EXTRAPOLATE_MS)
			if late_ms > 0.0:
				var velocity := (curr_pos - prev_pos) / (dt / 1000.0)
				out_pos = curr_pos + (velocity * (late_ms / 1000.0))
				out_rot = curr_rot

		node.global_position = node.global_position.lerp(out_pos, 0.55)
		node.rotation.y = lerp_angle(node.rotation.y, out_rot, 0.55)
		node.set_animation_state(str(snap.get("anim", "idle")))

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

func _update_match_state(match_state: Dictionary, quantized := false) -> void:
	if quantized:
		match_duration_seconds = maxf(1.0, float(match_state.get("d", int(match_duration_seconds * 100.0))) / 100.0)
		match_time_left = clampf(float(match_state.get("t", int(match_time_left * 100.0))) / 100.0, 0.0, match_duration_seconds)
		match_is_running = bool(match_state.get("r", 0))
	else:
		match_duration_seconds = maxf(1.0, float(match_state.get("durationSeconds", match_duration_seconds)))
		match_time_left = clampf(float(match_state.get("timeLeft", match_time_left)), 0.0, match_duration_seconds)
		match_is_running = bool(match_state.get("isRunning", false))
	_update_match_ui()

func is_match_running() -> bool:
	return match_is_running

func is_waiting_for_players() -> bool:
	return not match_is_running

func _update_match_ui() -> void:
	_resolve_ui_nodes()
	if countdown_label != null:
		if match_is_running:
			var whole_seconds := maxi(0, int(ceil(match_time_left)))
			var minutes = whole_seconds / 60
			var seconds = whole_seconds % 60
			countdown_label.text = "%02d:%02d" % [minutes, seconds]
		else:
			countdown_label.text = "Waiting for players"

	# Keep camera blocker hidden after joining the server.
	if camera_block != null and player_id != "":
		camera_block.visible = false

	if world_environment == null or world_environment.environment == null:
		return

	var ratio := 1.0 - (match_time_left / match_duration_seconds)
	var current_color = fog_start_color.lerp(fog_end_color, clampf(ratio, 0.0, 1.0))
	#world_environment.environment.fog_light_color = current_color
	#world_environment.environment.volumetric_fog_albedo = current_color

func _set_local_username(name_text: String) -> void:
	if events_bridge != null and is_instance_valid(events_bridge) and events_bridge.has_method("set_local_username"):
		events_bridge.set_local_username(name_text)

func _set_local_player_id(id_text: String) -> void:
	if events_bridge != null and is_instance_valid(events_bridge) and events_bridge.has_method("set_local_player_id"):
		events_bridge.set_local_player_id(id_text)

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

func _build_ws_url_with_username(base_url: String) -> String:
	if local_username == "":
		return base_url
	var joiner = "&" if base_url.find("?") != -1 else "?"
	return "%s%susername=%s" % [base_url, joiner, local_username.uri_encode()]

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
