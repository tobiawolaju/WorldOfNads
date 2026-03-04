extends Node3D

# === PLAYER & NPC EXPORTS ===
@export var local_player_scene: PackedScene
@export var camera_node: NodePath

# NPCs (you can assign different scenes or the same one)
@export var npc_p2: PackedScene
@export var npc_p3: PackedScene
@export var npc_p4: PackedScene
@export var npc_p5: PackedScene
@export var npc_p6: PackedScene
@export var npc_p7: PackedScene
@export var npc_p8: PackedScene
@export var npc_p9: PackedScene
@export var npc_p10: PackedScene

var local_player
var npcs := []


func _ready():
	_spawn_local_player()
	_spawn_npcs()
	_assign_camera()


func _spawn_local_player():
	if not local_player_scene:
		push_error("No LOCAL PLAYER scene assigned!")
		return

	local_player = local_player_scene.instantiate()
	add_child(local_player)
	local_player.is_local = true
	local_player.player_id = "PLAYER_1"


func _spawn_npcs():
	var npc_list = [
		npc_p2, npc_p3, npc_p4, npc_p5,
		npc_p6, npc_p7, npc_p8, npc_p9, npc_p10
	]

	var index := 2
	for npc_scene in npc_list:
		if npc_scene:
			var npc = npc_scene.instantiate()
			add_child(npc)
			npc.is_local = false
			npc.player_id = "NPC_%s" % index
			npcs.append(npc)
		index += 1


func _assign_camera():
	if not camera_node:
		return

	var cam = get_node(camera_node)
	if cam and local_player:
		local_player.camera = cam
