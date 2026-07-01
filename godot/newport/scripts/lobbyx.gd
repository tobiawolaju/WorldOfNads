extends Node3D

# === PLAYER & NPC EXPORTS ===
@export var local_player_scene: PackedScene
@export var camera_node: NodePath

# 👉 NEW: spawn point reference
@export var spawn_point: Node3D


var local_player
var npcs := []

const DEFAULT_SKIN_NAME := "defaultnad"
const SKIN_SCENE_PATHS := {
	"defaultnad": "res://newport/scenes/skin1.tscn",
	"Hellion": "res://newport/scenes/skin2.tscn",
	"Seraphim": "res://newport/scenes/skin3.tscn",
	"Abbss": "res://newport/scenes/skin4.tscn",
	"buggy": "res://newport/scenes/skin5.tscn",
	"john deo": "res://newport/scenes/skin6.tscn",
	"Aurum": "res://newport/scenes/skin7.tscn",
	"mouch": "res://newport/scenes/skin8.tscn"
}
const SKIN_NAME_ALIASES := {
	"s-default": "defaultnad",
	"s0": "buggy",
	"s1": "Aurum",
	"s2": "Abbss",
	"s3": "Hellion",
	"s4": "Seraphim",
	"s5": "mouch",
	"s6": "john deo",
	"defaultnad": "defaultnad",
	"buggy": "buggy",
	"aurum": "Aurum",
	"abbss": "Abbss",
	"abyss": "Abbss",
	"hellion": "Hellion",
	"seraphim": "Seraphim",
	"mouch": "mouch",
	"john deo": "john deo",
	"johndeo": "john deo"
}



func _ready():
	_spawn_local_player()
	_assign_camera()


func _spawn_local_player():
	var skin_name := _resolve_local_skin_name()
	var resolved_scene := _get_skin_scene(skin_name)
	if resolved_scene == null:
		if not local_player_scene:
			push_error("No LOCAL PLAYER scene assigned!")
			return
		resolved_scene = local_player_scene
		print("No skin scene found for '%s', using exported local player scene." % skin_name)

	local_player = resolved_scene.instantiate()
	add_child(local_player)

	local_player.is_local = true
	local_player.player_id = "PLAYER_1"
	print("Local player skin:", skin_name)

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

func _resolve_local_skin_name() -> String:
	if OS.has_feature("web"):
		var raw_skin = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('skin') || ''")
		if typeof(raw_skin) == TYPE_STRING:
			var skin_name := str(raw_skin).strip_edges()
			if skin_name != "":
				return _normalize_skin_name(skin_name)
	return DEFAULT_SKIN_NAME

func _get_skin_scene(skin_name: String) -> PackedScene:
	var resolved_name := _normalize_skin_name(skin_name)
	var scene_path = SKIN_SCENE_PATHS.get(resolved_name, "")
	if scene_path == "":
		return null
	return load(scene_path) as PackedScene

func _normalize_skin_name(raw_skin: String) -> String:
	var key := str(raw_skin).strip_edges().to_lower()
	while key.find("  ") != -1:
		key = key.replace("  ", " ")
	if SKIN_NAME_ALIASES.has(key):
		return str(SKIN_NAME_ALIASES[key])
	return key if key != "" else DEFAULT_SKIN_NAME
