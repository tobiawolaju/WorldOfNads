# WorldManager.gd
extends Node3D

const SERVER_URL = "ws://127.0.0.1:8080" # Change to your Render URL
@export var player_scene: PackedScene

var ws := WebSocketPeer.new()
var connected := false
var my_id: int = -1
var players := {} # Map<int, Node>

func _ready():
	print("Connecting to server...")
	ws.connect_to_url(SERVER_URL)

func _process(delta):
	ws.poll()
	var state = ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not connected:
			connected = true
			print("✅ Socket Connected!")
		_handle_packets()
	
	elif state == WebSocketPeer.STATE_CLOSED:
		if connected:
			print("❌ Disconnected")
			connected = false

func _handle_packets():
	while ws.get_available_packet_count() > 0:
		var packet = ws.get_packet()
		_parse_binary(packet)

func _parse_binary(data: PackedByteArray):
	var buffer = StreamPeerBuffer.new()
	buffer.data_array = data
	
	# First byte is always Packet TYPE
	var type = buffer.get_u8()
	
	match type:
		0: # HANDSHAKE
			my_id = buffer.get_u8()
			print("🔑 My Player ID is: ", my_id)
			_spawn_player(my_id, true)
			
		2: # PLAYER LEFT
			var target_id = buffer.get_u8()
			if players.has(target_id):
				print("💀 Player left: ", target_id)
				players[target_id].queue_free()
				players.erase(target_id)
				
		3: # WORLD STATE
			var count = buffer.get_u8() # How many players
			
			for i in range(count):
				var p_id = buffer.get_u8()
				var p_x = buffer.get_float()
				var p_y = buffer.get_float()
				var p_z = buffer.get_float()
				var p_rot = buffer.get_float()
				var p_anim = buffer.get_u8()
				
				if p_id == my_id: continue # Skip myself (Client prediction)
				
				if not players.has(p_id):
					_spawn_player(p_id, false)
				
				# Update Remote Player Data
				if players.has(p_id):
					var node = players[p_id]
					node.target_pos = Vector3(p_x, p_y, p_z)
					node.target_rot = p_rot
					node.set_anim_byte(p_anim)

func _spawn_player(id: int, is_local: bool):
	var p = player_scene.instantiate()
	p.name = str(id)
	add_child(p)
	p.setup(id, is_local, self) # We pass 'self' as the world_manager
	players[id] = p
