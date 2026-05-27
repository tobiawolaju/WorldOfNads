extends Node3D

# === PLAYER & NPC EXPORTS ===
@export var local_player_scene: PackedScene
@export var camera_node: NodePath



var local_player
var npcs := []


func _ready():
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



func _assign_camera():
	if not camera_node:
		return

	var cam = get_node(camera_node)
	if cam and local_player:
		local_player.camera = cam
