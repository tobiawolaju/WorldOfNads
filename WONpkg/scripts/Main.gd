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

# --- FALLBACK LOGIC ---
var is_connecting_to_live = true
var connection_attempted = false
@onready var fallback_timer: Timer = $FallbackTimer

func _ready():
	# connect fallback timer and start initial attempt
	fallback_timer.timeout.connect(_on_fallback_timer_timeout)
	_attempt_connection()

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

func _process(delta):
	if not connection_attempted:
		return

	# Poll the socket and handle state
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
		# The parse result in your previous code assumed a dictionary directly.
		# Keep the same check to avoid breaking existing workflow:
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

func _update_world_state(players_state):
	var received_ids := []
	for p_state in players_state:
		var id = p_state["id"]
		received_ids.append(id)
		
		# Important: don't overwrite the local player's transform from server state
		if id == player_id:
			continue

		if not players.has(id):
			_spawn_player(id, false)

		if players.has(id):
			var node = players[id]
			var server_pos = Vector3(p_state["x"], p_state["y"], p_state["z"])
			var server_rot_y = p_state["rotationY"]
			var server_anim = p_state["animation"]

			# Smoothly interpolate remote player to server position/rotation
			node.global_transform.origin = node.global_transform.origin.lerp(server_pos, 0.3)
			node.rotation.y = lerp_angle(node.rotation.y, server_rot_y, 0.3)
			# Update animation on the remote player's script (expected method on player)
			if node.has_method("set_animation_state"):
				node.set_animation_state(server_anim)

	# Remove players that disappeared
	for id in players.keys():
		if id != player_id and not id in received_ids:
			_remove_player(id)

func _spawn_player(id: String, is_local := false):
	var player = player_scene.instantiate()
	player.name = "Player_%s" % id
	add_child(player)

	player.player_id = id
	player.is_local = is_local
	player.root = self

	# --- LOCAL PLAYER SPAWN POINT ---
	if is_local and myplayerswpanpoint:
		# Place local player at the marker position
		player.global_position = myplayerswpanpoint.global_position

		# IMPORTANT: copy only the yaw (rotation.y) so forward/right stay consistent
		var current_rot :Vector3 = player.global_rotation
		current_rot.y = myplayerswpanpoint.global_rotation.y
		player.global_rotation = current_rot

		print("🧍 Local player spawned at custom spawn point:", id)
	else:
		print("👤 Remote player spawned:", id)
	
	players[id] = player

func _remove_player(id: String):
	if players.has(id):
		if players[id].is_queued_for_deletion():
			return
		players[id].queue_free()
		players.erase(id)
