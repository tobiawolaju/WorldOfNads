extends Node3D

# --------------------------------------------
# MATCHMAKER CONFIG
# --------------------------------------------
const MATCHMAKER_URL := "https://matchmaker-rd5j.onrender.com/find-match"

@export var player_scene: PackedScene

var ws := WebSocketPeer.new()
var connected := false
var player_id := ""
var players := {}

var http: HTTPRequest
var retry_timer := Timer.new()


func _ready():
	# HTTP client for matchmaker
	http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_matchmaker_response)

	# retry timer
	retry_timer.one_shot = true
	add_child(retry_timer)
	retry_timer.timeout.connect(_retry_matchmaker)

	print("🌐 Requesting match from matchmaker...")
	_request_server()


# --------------------------------------------
# 1) QUERY MATCHMAKER
# --------------------------------------------
func _request_server():
	var err = http.request(
		MATCHMAKER_URL,
		[],
		HTTPClient.METHOD_GET
	)

	if err != OK:
		push_error("Matchmaker request failed to start.")
		_retry_matchmaker()


func _on_matchmaker_response(result, code, headers, body):
	var text = ""
	if typeof(body) == TYPE_PACKED_BYTE_ARRAY:
		text = body.get_string_from_utf8()
	else:
		text = str(body)

	if code < 200 or code >= 300:
		push_error("Matchmaker error %s" % code)
		_retry_matchmaker()
		return

	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Invalid matchmaker JSON: %s" % text)
		_retry_matchmaker()
		return

	match data.get("status", ""):
		"ready":
			var url = data.get("serverUrl", "")
			if url == "":
				push_error("Matchmaker returned READY with no serverUrl.")
				_retry_matchmaker()
				return

			if url.begins_with("http://"):
				url = url.replace("http://", "ws://")
			elif url.begins_with("https://"):
				url = url.replace("https://", "wss://")

			print("✅ Server ready! Connecting:", url)
			_connect_ws(url)

		"waking_up":
			var retry_after := int(data.get("retryAfter", 5000)) / 1000.0
			print("⏳ Server waking up. Retrying in %s seconds..." % retry_after)
			retry_timer.start(retry_after)

		_:
			push_error("Unknown matchmaker status: %s" % str(data))
			_retry_matchmaker()


func _retry_matchmaker():
	print("🔁 Retrying matchmaker...")
	_request_server()


# --------------------------------------------
# 2) CONNECT TO WEBSOCKET SERVER
# --------------------------------------------
func _connect_ws(url: String):
	var err = ws.connect_to_url(url)
	if err != OK:
		push_error("Failed WS connect: %s" % err)
		_retry_matchmaker()


func _process(delta):
	ws.poll()
	var state = ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN and not connected:
		connected = true
		print("✅ Connected to game server!")

	elif state == WebSocketPeer.STATE_CLOSED:
		if connected:
			print("❌ Disconnected from server")
		else:
			print("❌ WS connection failed before open")

		connected = false
		_retry_matchmaker()

	if connected:
		_read_packets()


# --------------------------------------------
# 3) RECEIVE GAME STATE
# --------------------------------------------
func _read_packets():
	while ws.get_available_packet_count() > 0:
		var raw = ws.get_packet()
		if raw.is_empty():
			continue

		var json = JSON.parse_string(raw.get_string_from_utf8())
		if typeof(json) != TYPE_DICTIONARY:
			continue

		match json.get("type", ""):
			"connect":
				_handle_connect(json)

			"state":
				_handle_state(json)


func _handle_connect(msg):
	player_id = msg["id"]
	print("🧍 Local player ID:", player_id)
	_spawn_player(player_id, true)


func _handle_state(msg):
	if not msg.has("players"):
		return

	var received := []

	for p in msg["players"]:
		var id = p["id"]
		received.append(id)

		if id == player_id:
			continue

		if not players.has(id):
			_spawn_player(id, false)

		var node = players[id]
		var target_pos = Vector3(p["x"], p["y"], p["z"])
		var target_rot = p["rotationY"]
		var anim = p["animation"]

		node.global_transform.origin = node.global_transform.origin.lerp(target_pos, 0.3)
		node.rotation.y = lerp_angle(node.rotation.y, target_rot, 0.3)

		if node.has_method("set_animation_state"):
			node.set_animation_state(anim)

	# remove vanished players
	for id in players.keys():
		if id != player_id and id not in received:
			_remove_player(id)


# --------------------------------------------
# SPAWN / REMOVE PLAYERS
# --------------------------------------------
func _spawn_player(id: String, is_local := false):
	var p = player_scene.instantiate()
	p.name = "Player_%s" % id
	p.player_id = id
	if p.has_variable("is_local"):
		p.is_local = is_local
	else:
		p.set("is_local", is_local)

	add_child(p)
	players[id] = p

	if is_local:
		print("🧍 Local player spawned.")
	else:
		print("👤 Remote player spawned:", id)


func _remove_player(id: String):
	if players.has(id):
		players[id].queue_free()
		players.erase(id)
