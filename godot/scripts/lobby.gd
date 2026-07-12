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

const DEFAULT_SKIN_NAME := "s-default"
const SKIN_SCENE: PackedScene = preload("res://scenes/skin.tscn")
const API_BASE: String = "https://worldofnads.onrender.com"
const SKIN_NAME_ALIASES := {
	"s-default": "s-default",
	"s-default-unshaded": "s-default-unshaded",
}

static var _skin_applier: SkinApplier = SkinApplier.new()



func _ready():
	_stress_rng.randomize()
	_fetch_skin_data()
	_spawn_local_player()
	_spawn_lobby_stress_agents()
	_assign_camera()

func _fetch_skin_data() -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_skin_data_fetched.bind(http))
	http.request("%s/api/skins" % API_BASE)

func _on_skin_data_fetched(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	if http != null and is_instance_valid(http):
		http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		print("SkinApplier (lobby): API fetch failed (%d %d), using bundled fallback." % [result, response_code])
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Dictionary and parsed.get("ok") == true:
		var skins_array = parsed.get("skins")
		if skins_array is Array:
			SkinApplier.seed_from_api(skins_array)
			print("SkinApplier (lobby): Cached %d skins from API." % skins_array.size())


func _spawn_local_player():
	var skin_name := _resolve_local_skin_name()

	local_player = SKIN_SCENE.instantiate()
	_skin_applier.apply_skin(local_player, skin_name)
	add_child(local_player)

	local_player.is_local = true
	local_player.add_to_group("local_player")
	local_player.player_id = "PLAYER_1"
	print("Local player skin:", skin_name)

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
	var skin_names: Array = SKIN_NAME_ALIASES.values()
	var unique_skins: Array[String] = []
	for s in skin_names:
		if not unique_skins.has(s):
			unique_skins.append(s)

	for i in range(lobby_stress_agent_count):
		var skin_name := str(unique_skins[i % unique_skins.size()])

		var bot = SKIN_SCENE.instantiate()
		_skin_applier.apply_skin(bot, skin_name)
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

		if bot.has_method("disable_character_shadows"):
			bot.disable_character_shadows()

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

func _normalize_skin_name(raw_skin: String) -> String:
	var key := str(raw_skin).strip_edges().to_lower()
	while key.find("  ") != -1:
		key = key.replace("  ", " ")
	if SKIN_NAME_ALIASES.has(key):
		return str(SKIN_NAME_ALIASES[key])
	return key if key != "" else DEFAULT_SKIN_NAME
