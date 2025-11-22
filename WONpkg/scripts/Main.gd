extends Node3D

# ---------------------------------------------------------
# CONFIG
# ---------------------------------------------------------
const MATCHMAKER_URL = "https://worldofnads-matchmaker.onrender.com/find-match"
const LOCAL_MATCHMAKER_URL = "http://localhost:3000/find-match"
const REQUEST_TIMEOUT = 30 # seconds

@export var use_localhost := false
@export var player_scene: PackedScene = preload("res://scenes/components/Player.tscn")

# ---------------------------------------------------------
# NODES & STATE
# ---------------------------------------------------------
var http_req: HTTPRequest
var ws := WebSocketPeer.new()
var status_label: Label = null   # optional UI label

var connected := false
var player_id := ""
var players := {}
var is_matchmaking := false

# ---------------------------------------------------------
# READY
# ---------------------------------------------------------
func _ready():
	http_req = HTTPRequest.new()
	add_child(http_req)
	http_req.request_completed.connect(_on_matchmaker_response)

	_find_match()


# ---------------------------------------------------------
# PART 1 — MATCHMAKING (Long polling)
# ---------------------------------------------------------
func _find_match():
	if is_matchmaking: 
		return

	is_matchmaking = true

	var url = LOCAL_MATCHMAKER_URL if use_localhost else MATCHMAKER_URL

	print("🔎 Finding a match… (long polling)")
	if status_label: status_label.text = "Finding a match..."

	http_req.set_timeout(REQUEST_TIMEOUT)

	var err = http_req.request(url)
	if err != OK:
		push_error("Failed to start HTTP request.")
		is_matchmaking = false
		if status_label: status_label.text = "Error starting matchmaking."
		return


func _on_matchmaker_response(result, response_code, headers, body):
	is_matchmaking = false

	if result != HTTPRequest.RESULT_SUCCESS:
		print("❌ Matchmaker request failed: ", result)
		if status_label: status_label.text = "Matchmaker failed."
		return

	if response_code != 200:
		print("❌ Matchmaker error code: ", response_code)
		if status_label: status_label.text = "Servers full. Try again."
		return

	var json = JSON.parse_string(body.get_string_from_utf8())
	if json == null:
		print("❌ Invalid JSON from matchmaker.")
		if status_label: status_label.text = "Invalid matchmaker data."
		return

	var data = json as Dictionary
	if data.get("status") == "ready":
		var target_url = data.get("serverUrl")
		print("🚀 Match found! Connecting to: ", target_url)
		if status_label: status_label.text = "Connecting..."
		_connect_to_game_server(target_url)
	else:
		print("❓ Unknown matchmaker response: ", data)


# ---------------------------------------------------------
# PART 2 — CONNECT TO GAME WEBSOCKET
# ---------------------------------------------------------
func _connect_to_game_server(url):
	var err = ws.connect_to_url(url)
	if err != OK:
		print("❌ Failed to connect to game server.")
		if status_label: status_label.text = "Failed to connect."
		get_tree().create_timer(5.0).timeout.connect(_find_match)
		return

	print("🌐 Connection initiated…")


# ---------------------------------------------------------
# PROCESS LOOP
# ---------------------------------------------------------
func _process(delta):
	var state = ws.get_ready_state()

	# Closed / disconnected
	if state == WebSocketPeer.STATE_CLOSED:
		if connected:
			print("❌ Lost connection to game server.")
			if status_label: status_label.text = "Disconnected."
			connected = false
			_clear_world()
			get_tree().create_timer(3.0).timeout.connect(_find_match)
		return

	ws.poll()

	# Open and ready
	if state == WebSocketPeer.STATE_OPEN:
		if not connected:
			connected = true
			print("✅ Connected to Game Server!")
			if status_label: status_label.text = "Connected!"
		_receive_messages()


# ---------------------------------------------------------
# PART 3 — WEBSOCKET MESSAGE HANDLING
# ---------------------------------------------------------
func _receive_messages():
	while ws.get_available_packet_count() > 0:
		var msg = ws.get_packet().get_string_from_utf8()
		_process_message(msg)


func _process_message(msg):
	var json = JSON.parse_string(msg)
	if json == null:
		print("❌ Bad JSON from server: ", msg)
		return

	var data = json as Dictionary
	var type = data.get("type", "")

	match type:
		"welcome":
			player_id = data.get("id", "")
			print("Player ID assigned: ", player_id)

		"state":
			_update_world_state(data)

		_:
			print("Unknown WS message: ", data)


# ---------------------------------------------------------
# PART 4 — WORLD UPDATING
# ---------------------------------------------------------
func _update_world_state(data):
	var server_players = data.get("players", {})

	# Add or update players
	for id in server_players.keys():
		var player_data = server_players[id]

		if not players.has(id):
			_spawn_player(id)

		if players.has(id):
			var pos = player_data.get("pos", Vector3.ZERO)
			players[id].global_transform.origin = pos

	# Remove players that disappeared from server
	for id in players.keys():
		if not server_players.has(id):
			players[id].queue_free()
			players.erase(id)


func _spawn_player(id):
	var p = player_scene.instantiate()
	add_child(p)
	players[id] = p
	print("Spawned player: ", id)


# ---------------------------------------------------------
# CLEANUP
# ---------------------------------------------------------
func _clear_world():
	for id in players.keys():
		if is_instance_valid(players[id]):
			players[id].queue_free()

	players.clear()
	player_id = ""
