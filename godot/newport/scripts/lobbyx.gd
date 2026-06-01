extends Node3D

# === PLAYER & NPC EXPORTS ===
@export var local_player_scene: PackedScene
@export var camera_node: NodePath

# 👉 NEW: spawn point reference
@export var spawn_point: Node3D


var local_player
var npcs := []



func _ready():
	resolution.set_scale(1.0) 
	_spawn_local_player()
	_assign_camera()


func _spawn_local_player():

	if not local_player_scene:
		push_error("No LOCAL PLAYER scene assigned!")
		return

	local_player = local_player_scene.instantiate()
	add_child(local_player)

	local_player.is_local = true
	local_player.player_id = "PLAYER_1"

	# 👉 NEW: use spawn point transform
	if spawn_point:
		local_player.global_transform = spawn_point.global_transform
	else:
		local_player.global_position = global_position


func _assign_camera():

	if not camera_node:
		return

	var cam = get_node(camera_node)

	if cam and local_player:
		local_player.camera = cam
