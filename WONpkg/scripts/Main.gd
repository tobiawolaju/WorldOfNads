# WorldManager.gd
extends Node3D

# --- CONFIGURATION ---
# The URL of your Matchmaker (NOT the game servers)
const MATCHMAKER_URL = "https://matchmaker-rd5j.onrender.com/find-match"
const LOCAL_MATCHMAKER_URL = "http://localhost:3000/find-match"

@export var use_localhost := false
@export var player_scene: PackedScene = preload("res://scenes/components/Player.tscn")

# --- NODES ---
var http_req: HTTPRequest
var ws := WebSocketPeer.new()

# --- STATE ---
var connected := false
var player_id := ""
var players := {}
var is_connecting := false

func _ready():
	# Create HTTP Request node dynamically for the Matchmaker
	http_req = HTTPRequest.new()
	add_child(http_req)
	http_req.request_completed.connect(_on_matchmaker_response)
	
	# Start the process
	_request_matchmaking()

# ---------------------------------------------------------
# PART 1: MATCHMAKING (HTTP)
# ---------------------------------------------------------
func _request_matchmaking():
	if is_connecting: return
	is_connecting = true
	
	var url = LOCAL_MATCHMAKER_URL if use_localhost else MATCHMAKER_URL
	print("🔎 Looking for a match via: %s" % url)
	
	var error = http_req.request(url)
	if error != OK:
		push_error("Failed to create HTTP request.")
		is_connecting = false

func _on_matchmaker_response(result, response_code, headers, body):
	is_connecting = false
	
	if result != HTTPRequest.RESULT_SUCCESS:
		print("❌ Matchmaker unavailable. Retrying in 3s...")
		get_tree().create_timer(3.0).timeout.connect(_request_matchmaking)
		return

	if response_code != 200:
		print("❌ Matchmaker Error Code: %s" % response_code)
		# If 503 (All full), retry slower
		get_tree().create_timer(5.0).timeout.connect(_request_matchmaking)
		return

	# Parse JSON
	var json = JSON.new()
	var parse_err = json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		print("❌ JSON Parse Error")
		return
		
	var data = json.get_data()
	
	# --- HANDLE MATCHMAKER LOGIC ---
	
	# CASE 1: Server is Waking Up
	if data.get("status") == "waking_up":
		var wait_time = data.get("retryAfter", 5000) / 1000.0 # Convert ms to seconds
		print("💤 Server is sleeping. Waking it up... Retrying in %s seconds." % wait_time)
		# Wait and try again
		get_tree().create_timer(wait_time).timeout.connect(_request_matchmaking)
		
	# CASE 2: Ready to Play
	elif data.get("status") == "ready":
		var target_url = data.get("serverUrl")
		print("🚀 Match found! Connecting to: %s" % target_url)
		_connect_to_game_server(target_url)
	
	# CASE 3: Unknown
	else:
		print("❓ Unknown response: ", data)
		get_tree().create_timer(3.0).timeout.connect(_request_matchmaking)

# ---------------------------------------------------------
# PART 2: GAME LOOP (WEBSOCKET)
# ---------------------------------------------------------
func _connect_to_game_server(url):
	var err = ws.connect_to_url(url)
	if err != OK:
		print("❌ Failed to connect to Game Server. Restarting matchmaking...")
		_request_matchmaking()
		return

func _process(delta):
	ws.poll()
	var state = ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not connected:
			connected = true
			print("✅ Connected to Game Server!")
		_receive_messages()
		
	elif state == WebSocketPeer.STATE_CLOSED:
		if connected:
			print("❌ Disconnected from Game Server.")
			connected = false
			_clear_world()
			# Optionally: Go back to matchmaking
			# _request_matchmaking()

func _receive_messages():
	while ws.get_available_packet_count() > 0:
		var raw_packet = ws.get_packet()
		var raw_string = raw_packet.get_string_from_utf8()
		var data = JSON.parse_string(raw_string)
		
		if data == null: continue

		match data.get("type"):
			"connect":
				player_id = data["id"]
				print("My player ID:", player_id)
				_spawn_player(player_id, true)
			"state":
				if data.has("players"):
					_update_world_state(data["players"])

# ---------------------------------------------------------
# PART 3: GAMEPLAY LOGIC
# ---------------------------------------------------------
func _update_world_state(players_state):
	var received_ids = []
	for p_state in players_state:
		var id = p_state["id"]
		received_ids.append(id)
		
		if id == player_id: continue # Ignore self

		if not players.has(id):
			_spawn_player(id, false)

		if players.has(id):
			var node = players[id]
			# Interpolation Logic
			var server_pos = Vector3(p_state["x"], p_state["y"], p_state["z"])
			var server_rot_y = p_state["rotationY"]
			var server_anim = p_state["animation"]

			node.global_transform.origin = node.global_transform.origin.lerp(server_pos, 0.3)
			node.rotation.y = lerp_angle(node.rotation.y, server_rot_y, 0.3)
			
			if node.has_method("set_animation_state"):
				node.set_animation_state(server_anim)

	# Despawn disconnected players
	for id in players.keys():
		if id != player_id and not id in received_ids:
			_remove_player(id)

func _spawn_player(id: String, is_local := false):
	if players.has(id): return
	
	var player = player_scene.instantiate()
	player.name = "Player_%s" % id
	add_child(player)

	# Assume your player script has these vars
	if "player_id" in player: player.player_id = id
	if "is_local" in player: player.is_local = is_local
	if "root" in player: player.root = self

	players[id] = player

func _remove_player(id: String):
	if players.has(id):
		players[id].queue_free()
		players.erase(id)

func _clear_world():
	for id in players.keys():
		_remove_player(id)
	players.clear()
