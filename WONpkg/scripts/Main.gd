# Main.gd (Corrected)
# Manages the world, server connection, and spawning/updating players.

extends Node3D

@export var server_url := "ws://localhost:8080"
@export var player_scene: PackedScene = preload("res://scenes/components/Player.tscn")

var ws := WebSocketPeer.new()
var connected := false
var player_id := ""
var players := {} # Dictionary to store player nodes by their ID
var local_player: Node3D

# --- FIX #2: ADD A THRESHOLD FOR SERVER RECONCILIATION ---
# We only correct the local player if they are out of sync by this much.
const CORRECTION_THRESHOLD = 0.1 # 10 cm

func _ready():
	print("🌐 Connecting to server...")
	var err = ws.connect_to_url(server_url)
	if err != OK:
		push_error("Failed to connect: %s" % err)
	else:
		print("Connecting...")

func _process(delta):
	if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		return

	ws.poll()

	var state = ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN and not connected:
		print("✅ Connected to server!")
		connected = true
	
	_receive_messages()

func _receive_messages():
	while ws.get_available_packet_count() > 0:
		var raw_packet = ws.get_packet()
		if raw_packet.is_empty(): continue
		var raw_string = raw_packet.get_string_from_utf8()
		var data = JSON.parse_string(raw_string)
		if typeof(data) != TYPE_DICTIONARY: continue

		match data.get("type"):
			"connect":
				player_id = data["id"]
				print("My player ID:", player_id)
				_spawn_player(player_id, true)
			"state":
				if data.has("players"):
					_update_world_state(data["players"])

func _update_world_state(players_state):
	var received_ids = []
	for p_state in players_state:
		var id = p_state["id"]
		received_ids.append(id)
		
		var server_pos = Vector3(p_state["x"], p_state["y"], p_state["z"])
		var server_rot_y = p_state["rotationY"]

		# --- FIX #3: IMPLEMENT SERVER RECONCILIATION FOR THE LOCAL PLAYER ---
		if id == player_id:
			if local_player:
				var client_pos = local_player.global_transform.origin
				var distance = client_pos.distance_to(server_pos)
				
				# If the client has drifted too far from the server's reality...
				if distance > CORRECTION_THRESHOLD:
					# ...smoothly pull them back to the correct position.
					local_player.global_transform.origin = client_pos.lerp(server_pos, 0.1)
			continue # Done with local player, move to the next one.

		# --- Logic for REMOTE players remains the same ---
		if not players.has(id):
			_spawn_player(id, false)

		if players.has(id):
			var node = players[id]
			
			# --- FIX #4: USE A SOFTER LERP FOR SMOOTHER REMOTE PLAYERS ---
			node.global_transform.origin = node.global_transform.origin.lerp(server_pos, 0.3)
			node.rotation.y = lerp_angle(node.rotation.y, server_rot_y, 0.3)

	# Remove disconnected players
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

	if is_local:
		local_player = player
		print("🧍 Local player spawned:", id)
	else:
		print("👤 Remote player spawned:", id)
	players[id] = player

func _remove_player(id: String):
	if players.has(id):
		players[id].queue_free()
		players.erase(id)
		print("💀 Player removed:", id)
