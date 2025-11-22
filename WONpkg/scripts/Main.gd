# WorldManager.gd - REVISED for Long Polling
extends Node3D

# --- CONFIGURATION ---
const MATCHMAKER_URL = "https://worldofnads-matchmaker.onrender.com/find-match"
const LOCAL_MATCHMAKER_URL = "http://localhost:3000/find-match"
const REQUEST_TIMEOUT = 30 # Seconds to wait for the matchmaker

@export var use_localhost := false
@export var player_scene: PackedScene = preload("res://scenes/components/Player.tscn")

# --- NODES ---
var http_req: HTTPRequest
var ws := WebSocketPeer.new()
var status_label: Label # Optional: A label to show status to the user

# --- STATE ---
var connected := false
var player_id := ""
var players := {}
var is_matchmaking := false

func _ready():
	# Optional: Find a UI label to display status
	# status_label = $Path/To/Your/Label

	# Create HTTP Request node for the Matchmaker
	http_req = HTTPRequest.new()
	add_child(http_req)
	http_req.request_completed.connect(_on_matchmaker_response)

	# Start the process
	_find_match()

# ---------------------------------------------------------
# PART 1: MATCHMAKING (Single, Patient HTTP Request)
# ---------------------------------------------------------
func _find_match():
	if is_matchmaking: return
	is_matchmaking = true

	var url = LOCAL_MATCHMAKER_URL if use_localhost else MATCHMAKER_URL
	print("🔎 Finding a match... This may take a moment.")
	if status_label: status_label.text = "Finding a match..."

	# Set a longer timeout to allow the long poll to complete
	http_req.set_timeout(REQUEST_TIMEOUT)

	var error = http_req.request(url)
	if error != OK:
		push_error("Failed to start HTTP request.")
		is_matchmaking = false
		if status_label: status_label.text = "Error: Could not start search."
		# Optional: Add a button to allow the user to retry manually
		# get_tree().create_timer(5.0).timeout.connect(_find_match)

func _on_matchmaker_response(result, response_code, headers, body):
	is_matchmaking = false

	if result != HTTPRequest.RESULT_SUCCESS:
		print("❌ Matchmaker request failed. Result: %s" % result)
		if status_label: status_label.text = "Error: Connection to matchmaker failed."
		# You might want a "Retry" button here for the user
		return

	if response_code == 200:
		var json = JSON.parse_string(body.get_string_from_utf8())
		if json == null:
			print("❌ Failed to parse JSON from matchmaker.")
			if status_label: status_label.text = "Error: Invalid server response."
			return

		var data = json as Dictionary
		if data.get("status") == "ready":
			var target_url = data.get("serverUrl")
			print("🚀 Match found! Connecting to: %s" % target_url)
			if status_label: status_label.text = "Connecting to server..."
			_connect_to_game_server(target_url)
		else:
			print("❓ Unknown success response: ", data)
	else:
		print("❌ Matchmaker error. Code: %s" % response_code)
		if status_label: status_label.text = "Error: All servers are currently full."
		# Handle specific errors like 503 (all servers full)
		# A "Retry" button would be appropriate here too.


# ---------------------------------------------------------
# PART 2: GAME CONNECTION (WEBSOCKET)
# ---------------------------------------------------------
func _connect_to_game_server(url):
	var err = ws.connect_to_url(url)
	if err != OK:
		print("❌ Failed to initiate connection to Game Server.")
		if status_label: status_label.text = "Error: Could not connect."
		# Connection failed, go back to matchmaking after a delay
		get_tree().create_timer(5.0).timeout.connect(_find_match)
		return
	else:
		print("🌐 Connection to game server initiated...")

func _process(delta):
	if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		if connected:
			print("❌ Disconnected from Game Server.")
			if status_label: status_label.text = "Disconnected."
			connected = false
			_clear_world() # You need to implement this function to remove old players
			# Optional: automatically try to find a new match
			get_tree().create_timer(3.0).timeout.connect(_find_match)
		return

	ws.poll()
	var state = ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not connected:
			connected = true
			print("✅ Connected to Game Server!")
			if status_label: status_label.text = "Connected!"
		_receive_messages()
	# The WebSocketPeer is in STATE_CONNECTING while ws.poll() is working.
	# We don't need to do anything special here; it handles the "waiting" for us.

# (The rest of your _receive_messages, _update_world_state, _spawn_player, etc. can remain the same)

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

			node.global_transform.origin = node.global_transform.origin.lerp(server_pos, 0.3)
			node.rotation.y = lerp_angle(node.rotation.y, server_rot_y, 0.3)
			# Tell the remote player's script to update its animation
			node.set_animation_state(server_anim)

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
		print("🧍 Local player spawned:", id)
	else:
		print("👤 Remote player spawned:", id)
	players[id] = player

func _remove_player(id: String):
	if players.has(id):
		if players[id].is_queued_for_deletion(): return
		players[id].queue_free()
		players.erase(id)

func _clear_world():
	for id in players.keys():
		if is_instance_valid(players[id]):
			players[id].queue_free()
	players.clear()
	player_id = ""
