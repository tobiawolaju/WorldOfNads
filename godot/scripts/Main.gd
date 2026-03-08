# WorldManager.gd
extends Node3D

# --- SERVER URLS ---
const LIVE_URL = "wss://worldofnads.onrender.com/"
const LOCAL_URL = "ws://localhost:8080"

@export var player_scene: PackedScene = preload("res://scenes/components/Player.tscn")
@export var myplayerswpanpoint: Marker3D
@export var countdown_label_path: NodePath
@export var world_environment_path: NodePath = NodePath("WorldEnvironment")

# --- NETWORK & STATE VARIABLES ---
var ws := WebSocketPeer.new()
var connected := false
var player_id := ""
var players := {}
var is_local: bool
var root: Node
const CHICKEN_HOLD_DISTANCE := 0.9
const CHICKEN_HOLD_HEIGHT := 1.0

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
var countdown_label: Label = null
var world_environment: WorldEnvironment = null
var _world_env_duplicated := false
var match_duration_seconds := 180.0
var match_time_left := 180.0
var match_is_running := false
var fog_start_color: Color = Color8(152, 227, 254)
var fog_end_color: Color = Color8(241, 118, 254)

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

		var raw_string = raw_packet.get_string_from_utf8()
		var data = JSON.parse_string(raw_string)

		if typeof(data) != TYPE_DICTIONARY:
			continue

		match data.get("type"):
			"connect":
				player_id = data["id"]
				local_display_name = _resolve_server_username(data, player_id)
				player_display_names[player_id] = local_display_name
				print("My player ID:", player_id, "username:", local_display_name)
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
					_update_world_state(data["players"])
				if data.has("chicken"):
					_update_chicken_state(data["chicken"])
				if data.has("match") and typeof(data["match"]) == TYPE_DICTIONARY:
					_update_match_state(data["match"])


# --- WORLD STATE UPDATE ---
func _update_world_state(players_state):
	var received_ids = []

	for p_state in players_state:
		var id = p_state["id"]
		received_ids.append(id)
		var resolved_name = _resolve_server_username(p_state, id)
		player_display_names[id] = resolved_name

		if id == player_id:
			if players.has(id):
				players[id].display_name = resolved_name
			continue

		var server_pos = Vector3(p_state["x"], p_state["y"], p_state["z"])
		var server_rot_y = p_state["rotationY"]
		var server_anim = p_state["animation"]

		# Spawn if new
		if not players.has(id):
			_spawn_player(id, false)
			players[id].global_position = server_pos  # FIX: spawn at correct position

		var node = players[id]
		node.display_name = resolved_name

		# 🚗 Vehicle sync
		if p_state.has("vehicle") and p_state["vehicle"] != null:
			_sync_vehicle_player(node, p_state)
		else:
			# Smooth movement
			node.global_position = node.global_position.lerp(server_pos, 0.3)
			node.rotation.y = lerp_angle(node.rotation.y, server_rot_y, 0.3)
			node.set_animation_state(server_anim)

		# Visibility (NO RETURN)
		node.visible = node.global_position.y <= 100

	# Remove disconnected players
	for id in players.keys():
		if id != player_id and not id in received_ids:
			_remove_player(id)


# --- CHICKEN SYNC ---
func _cache_chicken_node() -> void:
	if chicken_node != null and is_instance_valid(chicken_node):
		return
	var pickup_nodes = get_tree().get_nodes_in_group("pickup_items")
	if pickup_nodes.size() > 0 and pickup_nodes[0] is RigidBody3D:
		chicken_node = pickup_nodes[0]

func _update_chicken_state(chicken_state: Dictionary) -> void:
	_cache_chicken_node()
	if chicken_node == null:
		return

	var server_target_pos = Vector3(
		float(chicken_state.get("x", chicken_node.global_position.x)),
		float(chicken_state.get("y", chicken_node.global_position.y)),
		float(chicken_state.get("z", chicken_node.global_position.z))
	)
	var server_target_rot_y = float(chicken_state.get("rotationY", chicken_node.global_rotation.y))
	chicken_is_held = bool(chicken_state.get("isHeld", false))
	chicken_holder_id = str(chicken_state.get("holderId", ""))
	_handle_chicken_state_event(chicken_is_held, chicken_holder_id)
	var target_pos = server_target_pos
	var target_rot_y = server_target_rot_y

	# Visual attachment only for local holder to remove perceived self-lag.
	# Remote clients must stay on server pose to keep one shared world state.
	var holder_node = _get_player_node_by_id(chicken_holder_id)
	if chicken_is_held and chicken_holder_id == player_id and holder_node != null:
		target_pos = _build_hold_target_for_player(holder_node)
		target_rot_y = holder_node.rotation.y

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
	var target_pos = player_pos + (view_forward * CHICKEN_HOLD_DISTANCE)
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

func _resolve_events_bridge() -> void:
	var bridges = get_tree().get_nodes_in_group("events_bridge")
	if bridges.size() > 0:
		events_bridge = bridges[0]

func _resolve_ui_nodes() -> void:
	if countdown_label == null and countdown_label_path != NodePath():
		countdown_label = get_node_or_null(countdown_label_path)
	if world_environment == null and world_environment_path != NodePath():
		world_environment = get_node_or_null(world_environment_path)
	if world_environment != null and world_environment.environment and not _world_env_duplicated:
		world_environment.environment = world_environment.environment.duplicate()
		_world_env_duplicated = true

func _update_match_state(match_state: Dictionary) -> void:
	match_duration_seconds = maxf(1.0, float(match_state.get("durationSeconds", match_duration_seconds)))
	match_time_left = clampf(float(match_state.get("timeLeft", match_time_left)), 0.0, match_duration_seconds)
	match_is_running = bool(match_state.get("isRunning", false))
	_update_match_ui()

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

	if world_environment == null or world_environment.environment == null:
		return

	var ratio := 1.0 - (match_time_left / match_duration_seconds)
	var current_color = fog_start_color.lerp(fog_end_color, clampf(ratio, 0.0, 1.0))
	world_environment.environment.fog_light_color = current_color
	world_environment.environment.volumetric_fog_albedo = current_color

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
		ws.send_text(JSON.stringify({
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
	var candidate := str(data.get("username", "")).strip_edges()
	if candidate != "":
		return candidate
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
