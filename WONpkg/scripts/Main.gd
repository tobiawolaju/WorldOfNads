# WorldManager.gd
extends Node3D

const LIVE_URL := "wss://worldofnads.onrender.com/"

@export var player_scene: PackedScene = preload("res://scenes/components/Player.tscn")

var ws := WebSocketPeer.new()
var connected := false
var player_id := 0
var players := {} # id → node

var connection_attempted := false

func _ready():
	_attempt_connection()

func _attempt_connection():
	print("Connecting to LIVE server:", LIVE_URL)
	var err = ws.connect_to_url(LIVE_URL)

	if err != OK:
		push_error("Failed to initiate connection: %s" % err)
	else:
		connection_attempted = true

func _process(delta):
	if not connection_attempted:
		return

	ws.poll()
	var state = ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN and not connected:
		connected = true
		print("✅ Connected to LIVE server")

	elif state == WebSocketPeer.STATE_CLOSED:
		if connected:
			print("❌ Disconnected from LIVE server.")
			connected = false
		connection_attempted = false

	if connected:
		_receive_messages()

func _receive_messages():
	while ws.get_available_packet_count() > 0:
		var packet = ws.get_packet()
		if packet.empty(): 
			continue

		var text := packet.get_string_from_utf8()
		var json = JSON.parse_string(text)
		if json.error != OK: 
			continue

		var data = json.result
		if typeof(data) != TYPE_DICTIONARY: 
			continue

		match data.get("type", ""):
			"connect":
				_handle_connect(data)
			"state":
				_handle_full_state(data)
			"state_delta":
				_handle_delta_state(data)

func _handle_connect(data):
	player_id = int(data.get("id", 0))
	print("My player ID:", player_id)
	_spawn_player(player_id, true)

func _handle_full_state(data):
	var p = data.get("players", [])
	if p:
		_update_world_full(p)

func _handle_delta_state(data):
	var updated = data.get("players", [])
	var removed = data.get("removed", [])

	if updated:
		_update_world_delta(updated)
	for rid in removed:
		_remove_player(int(rid))

func _update_world_full(players_state):
	var received_ids = []

	for p in players_state:
		if p.size() < 6: 
			continue

		var id = int(p[0])
		received_ids.append(id)

		if id == player_id:
			continue

		if not players.has(id):
			_spawn_player(id, false)

		var node = players[id]
		var pos = Vector3(float(p[1]), float(p[2]), float(p[3]))
		var rot_y = float(p[4])
		var anim = int(p[5])

		node.global_transform.origin = node.global_transform.origin.lerp(pos, 0.3)
		node.rotation.y = lerp_angle(node.rotation.y, rot_y, 0.3)
		node.set_animation_state(_anim_index_to_name(anim))

	# remove players no longer in the state
	for id in players.keys():
		if id != player_id and not received_ids.has(id):
			_remove_player(id)

func _update_world_delta(updated_list):
	for p in updated_list:
		if p.size() < 6: continue

		var id = int(p[0])
		if id == player_id: continue

		if not players.has(id):
			_spawn_player(id, false)

		var node = players[id]
		var pos = Vector3(float(p[1]), float(p[2]), float(p[3]))
		var rot_y = float(p[4])
		var anim = int(p[5])

		node.global_transform.origin = node.global_transform.origin.lerp(pos, 0.3)
		node.rotation.y = lerp_angle(node.rotation.y, rot_y, 0.3)
		node.set_animation_state(_anim_index_to_name(anim))

func _anim_index_to_name(idx: int) -> String:
	return "running" if idx == 1 else "idle"

func _spawn_player(id: int, is_local := false):
	var player = player_scene.instantiate()
	player.name = "Player_%d" % id
	add_child(player)

	player.player_id = id
	player.is_local = is_local
	player.root = self

	players[id] = player

	print("Local player spawned: %d" % id if is_local else "Remote player spawned: %d" % id)


func _remove_player(id: int):
	if players.has(id):
		if not players[id].is_queued_for_deletion():
			players[id].queue_free()
		players.erase(id)
