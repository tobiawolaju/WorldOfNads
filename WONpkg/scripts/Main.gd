extends Node3D

# --- CONFIGURATION ---
const MATCHMAKER_URL = "https://matchmaker-rd5j.onrender.com"
const LOCAL_URL = "ws://localhost:8080"

# Set this to TRUE in the Inspector if you are testing offline
@export var use_localhost: bool = false 
@export var player_scene: PackedScene = preload("res://scenes/components/Player.tscn")

# --- NODES ---
# Make sure you add an HTTPRequest node to your scene tree as a child of this node!
@onready var http_request: HTTPRequest = $MatchmakerRequest 

# --- NETWORK STATE ---
var ws := WebSocketPeer.new()
var connected := false
var player_id := ""
var players := {}
var connection_in_progress := false

func _ready():
	# Connect the HTTP request signal to our function
	http_request.request_completed.connect(_on_matchmaker_response)
	
	# Start the process
	_find_server()

# --- STEP 1: ASK MATCHMAKER ---
func _find_server():
	if use_localhost:
		print("🏠 Localhost mode enabled. Skipping matchmaker.")
		_connect_to_websocket(LOCAL_URL)
		return

	print("🔎 Contacting Matchmaker at: %s/find-match" % MATCHMAKER_URL)
	var error = http_request.request(MATCHMAKER_URL + "/find-match")
	if error != OK:
		push_error("❌ Failed to send HTTP request to matchmaker.")

# --- STEP 2: HANDLE MATCHMAKER RESPONSE ---
func _on_matchmaker_response(result, response_code, headers, body):
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("❌ Matchmaker unreachable. Code: %s" % response_code)
		return

	var json_string = body.get_string_from_utf8()
	var response = JSON.parse_string(json_string)

	if response == null:
		push_error("❌ Failed to parse Matchmaker JSON.")
		return

	print("📋 Matchmaker says: ", response)

	# SCENARIO A: Server is Ready
	if response.has("status") and response["status"] == "ready":
		var target_url = response["serverUrl"]
		print("✅ Match found! Connecting to: ", target_url)
		_connect_to_websocket(target_url)

	# SCENARIO B: Server is Sleeping (Spinning Up)
	elif response.has("status") and response["status"] == "waking_up":
		var wait_time_ms = response["retryAfter"]
		var wait_time_sec = wait_time_ms / 1000.0
		print("💤 Server is sleeping. Retrying in %s seconds..." % wait_time_sec)
		
		# Create a temporary timer to wait, then try again
		await get_tree().create_timer(wait_time_sec).timeout
		_find_server() # Recursive call to try again
		
	else:
		push_error("❌ Unexpected response from matchmaker: " + str(response))

# --- STEP 3: CONNECT WEBSOCKET ---
func _connect_to_websocket(url):
	print("🔌 connecting WebSocket to: ", url)
	var err = ws.connect_to_url(url)
	if err != OK:
		push_error("Failed to connect to WebSocket: %s" % err)
		return
	connection_in_progress = true

# --- GAME LOOP (Standard WebSocket Handling) ---
func _process(delta):
	ws.poll()
	var state = ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not connected:
			connected = true
			connection_in_progress = false
			print("🎉 WEBSOCKET CONNECTED! You are in the game.")
		_receive_messages()
	
	elif state == WebSocketPeer.STATE_CLOSED:
		if connected:
			print("❌ Disconnected from server.")
			connected = false
		elif connection_in_progress:
			print("❌ Connection failed.")
			connection_in_progress = false

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
		
		if id == player_id:
			continue

		if not players.has(id):
			_spawn_player(id, false)

		if players.has(id):
			var node = players[id]
			var server_pos = Vector3(p_state["x"], p_state["y"], p_state["z"])
			var server_rot_y = p_state["rotationY"]
			var server_anim = p_state["animation"]

			# Interpolation for smooth movement
			node.global_transform.origin = node.global_transform.origin.lerp(server_pos, 0.3)
			node.rotation.y = lerp_angle(node.rotation.y, server_rot_y, 0.3)
			
			# Update animation if your player scene has this method
			if node.has_method("set_animation_state"):
				node.set_animation_state(server_anim)

	# Remove players who are no longer in the state data
	for id in players.keys():
		if id != player_id and not id in received_ids:
			_remove_player(id)

# --- PLAYER MANAGEMENT ---
func _spawn_player(id: String, is_local := false):
	if players.has(id): return # Prevent duplicates
	
	var player = player_scene.instantiate()
	player.name = "Player_%s" % id
	add_child(player)

	# Assuming your Player script has these variables
	if "player_id" in player: player.player_id = id
	if "is_local" in player: player.is_local = is_local
	if "root" in player: player.root = self

	if is_local:
		print("🧍 Local player spawned:", id)
	else:
		print("👤 Remote player spawned:", id)
	players[id] = player

func _remove_player(id: String):
	if players.has(id):
		if is_instance_valid(players[id]):
			players[id].queue_free()
		players.erase(id)
