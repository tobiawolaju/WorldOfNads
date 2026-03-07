# WorldManager.gd
extends Node3D

# --- SERVER URLS ---
const LIVE_URL = "wss://worldofnads.onrender.com/"
const LOCAL_URL = "ws://localhost:8080"

@export var player_scene: PackedScene = preload("res://scenes/components/Player.tscn")
@export var myplayerswpanpoint: Marker3D

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

# --- FALLBACK LOGIC ---
var is_connecting_to_live = true
var connection_attempted = false
@onready var fallback_timer: Timer = $FallbackTimer

func _ready():
	fallback_timer.timeout.connect(_on_fallback_timer_timeout)
	_attempt_connection()
	_cache_chicken_node()

func _attempt_connection():
	var url_to_try = LIVE_URL if is_connecting_to_live else LOCAL_URL
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
				print("My player ID:", player_id)
				_spawn_player(player_id, true)

			"state":
				if data.has("players"):
					_update_world_state(data["players"])
				if data.has("chicken"):
					_update_chicken_state(data["chicken"])


# --- WORLD STATE UPDATE ---
func _update_world_state(players_state):
	var received_ids = []

	for p_state in players_state:
		var id = p_state["id"]
		received_ids.append(id)

		if id == player_id:
			continue

		var server_pos = Vector3(p_state["x"], p_state["y"], p_state["z"])
		var server_rot_y = p_state["rotationY"]
		var server_anim = p_state["animation"]

		# Spawn if new
		if not players.has(id):
			_spawn_player(id, false)
			players[id].global_position = server_pos  # FIX: spawn at correct position

		var node = players[id]

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
	var target_pos = server_target_pos
	var target_rot_y = server_target_rot_y

	# Visual attachment: while held, render chicken from holder transform so it stays locked to player.
	var holder_node = _get_player_node_by_id(chicken_holder_id)
	if chicken_is_held and holder_node != null:
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
