extends Node3D

# === PLAYER & NPC EXPORTS ===
@export var local_player_scene: PackedScene
@export var camera_node: NodePath

# 👉 NEW: spawn point reference
@export var spawn_point: Node3D
@export var spawn_lobby_stress_agents: bool = false
@export var lobby_stress_agent_count: int = 100


var local_player
var npcs := []
var _stress_rng: RandomNumberGenerator = RandomNumberGenerator.new()

const DEFAULT_SKIN_NAME := "defaultnad"
const SKIN_SCENE_PATHS := {
	"defaultnad": "res://scenes/skin1.tscn",
	"Hellion": "res://scenes/skin2.tscn",
	"Seraphim": "res://scenes/skin3.tscn",
	"Abbss": "res://scenes/skin4.tscn",
	"buggy": "res://scenes/skin5.tscn",
	"john deo": "res://scenes/skin6.tscn",
	"Aurum": "res://scenes/skin7.tscn",
	"mouch": "res://scenes/skin8.tscn"
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
	#GameManager.set_speed(1)
	resolution.set_resolution(resolution.default_scale)
	_stress_rng.randomize()
	_spawn_local_player()
	_spawn_lobby_stress_agents()
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
	local_player.add_to_group("local_player")
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

func _spawn_lobby_stress_agents() -> void:
	if not spawn_lobby_stress_agents or lobby_stress_agent_count <= 0:
		return
	if spawn_point == null:
		return

	var base_pos := spawn_point.global_position
	var scene_paths: Array = SKIN_SCENE_PATHS.values()
	if scene_paths.is_empty():
		return

	for i in range(lobby_stress_agent_count):
		var skin_scene_path := str(scene_paths[i % scene_paths.size()])
		var bot_scene := load(skin_scene_path) as PackedScene
		if bot_scene == null:
			continue

		var bot = bot_scene.instantiate()
		add_child(bot)
		npcs.append(bot)

		var ring_index := int(floor(sqrt(float(i))))
		var ring_radius := 2.0 + (ring_index * 1.5)
		var ring_angle := (TAU * float(i)) / maxf(1.0, float(lobby_stress_agent_count))
		var spawn_offset := Vector3(cos(ring_angle), 0.0, sin(ring_angle)) * ring_radius
		var home_center := base_pos + spawn_offset

		bot.is_local = false
		bot.player_id = "BOT_%03d" % (i + 1)
		bot.display_name = "BOT %03d" % (i + 1)
		bot.global_position = home_center

		if bot.has_method("configure_demo_agent"):
			var orbit_radius := _stress_rng.randf_range(0.9, 3.5)
			var orbit_speed := _stress_rng.randf_range(0.55, 1.6)
			var orbit_phase := _stress_rng.randf_range(0.0, TAU)
			var orbit_direction := -1.0 if _stress_rng.randi_range(0, 1) == 0 else 1.0
			var jump_min := _stress_rng.randf_range(0.8, 2.4)
			var jump_max := _stress_rng.randf_range(2.5, 5.5)
			var wobble := _stress_rng.randf_range(0.2, 1.1)
			bot.configure_demo_agent(
				home_center,
				orbit_radius,
				orbit_speed,
				orbit_phase,
				orbit_direction,
				jump_min,
				jump_max,
				wobble
			)

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
	var scene := load(scene_path) as PackedScene
	if scene != null:
		return scene
	var default_path = SKIN_SCENE_PATHS.get(DEFAULT_SKIN_NAME, "")
	if default_path == "":
		return null
	return load(default_path) as PackedScene

func _normalize_skin_name(raw_skin: String) -> String:
	var key := str(raw_skin).strip_edges().to_lower()
	while key.find("  ") != -1:
		key = key.replace("  ", " ")
	if SKIN_NAME_ALIASES.has(key):
		return str(SKIN_NAME_ALIASES[key])
	return key if key != "" else DEFAULT_SKIN_NAME
