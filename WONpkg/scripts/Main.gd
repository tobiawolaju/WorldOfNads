extends Node3D
















# --- SERVER URLS ---
const LIVE_URL = "wss://worldofnads.onrender.com/"
const LOCAL_URL = "ws://localhost:8080"


# --- EXPORTS ---
@export var player_scene: PackedScene = preload("res://scenes/components/Player.tscn")
@export var bus_node: Node3D # assign bus mesh in editor

# --- NETWORK & STATE VARIABLES ---
var ws := WebSocketPeer.new()
var connected := false
var player_id := ""
var players := {}

# --- FALLBACK LOGIC ---
var is_connecting_to_live = true
var connection_attempted = false
@onready var fallback_timer: Timer = $FallbackTimer



@export var username_label :Label




func _ready():
	if Engine.has_singleton("JavaScript"):
		var js = Engine.get_singleton("JavaScript")
		js.connect("message", Callable(self, "_on_js_message"))
	
	
	# Spawn local player immediately on bus
	_spawn_player_local()

	# Connect to server asynchronously after 10s delay
	_connect_to_server_delayed()


func _on_js_message(message):
	# Check if it's the username message
	if typeof(message) == TYPE_DICTIONARY and message.has("type") and message["type"] == "set_username":
		var username = str(message["value"])
		username_label.text = "Player: " + username

func _spawn_player_local():
	var player = player_scene.instantiate()
	player.name = "Player_local"
	add_child(player)

	player.player_id = "local"
	player.is_local = true
	player.root = self
	player.bus_node = bus_node
	player.on_bus = true

	if bus_node:
		player.global_transform.origin = bus_node.global_transform.origin + Vector3(0, 1.5, 0)
		player.velocity = Vector3.ZERO # freeze movement

	players["local"] = player
	print("🧍 Local player spawned immediately on bus")

func _connect_to_server_delayed() -> void:
	var t = get_tree().create_timer(10.0)
	t.timeout.connect(_attempt_connection)

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

	ws.poll()
	var state = ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN and not connected:
		connected = true
		var server_type = "LIVE" if is_connecting_to_live else "LOCAL"
		print("✅ Connected to %s server!" % server_type)
		_on_connected()
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
		if raw_packet.is_empty(): continue
		var raw_string = raw_packet.get_string_from_utf8()
		var data = JSON.parse_string(raw_string)
		if typeof(data) != TYPE_DICTIONARY: continue

		match data.get("type"):
			"connect":
				player_id = data["id"]
				print("My player ID:", player_id)

				# Assign server ID to the already spawned local player
				var local_player = players.get("local", null)
				if local_player:
					local_player.player_id = player_id
					players.erase("local")
					players[player_id] = local_player
					_on_connected()
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
	player.bus_node = bus_node # assign bus reference to player

	# Place player on bus if assigned
	if bus_node:
		player.global_transform.origin = bus_node.global_transform.origin + Vector3(0, 1.5, 0)
		player.on_bus = true

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

func _on_connected():
	if players.has(player_id):
		var p = players[player_id]
		if p.on_bus:
			p.on_bus = false
			p.get_parent().remove_child(p)
			add_child(p) # Re-parent to world
			p.velocity.y = 0.1 # small nudge to fall naturally
			
