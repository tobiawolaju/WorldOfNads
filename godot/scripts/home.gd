extends Node

## Whether native builds must present the device-linking screen before entering
## the game. The web export keeps the existing username-token flow, so the gate
## is deliberately skipped there.
const NATIVE_LOGIN_REQUIRED := true

const LOGIN_SCENE := "res://scenes/login.tscn"
const DASHBOARD_SCENE := "res://scenes/dshbord.tscn"
const LOBBY_SCENE := "res://scenes/lobby.tscn"

@onready var progress_bar: ProgressBar = $"CanvasLayer/BoxContainer/Node/ProgressBar"

func _ready() -> void:
	if _requires_login() and not await AuthManager.await_restore():
		print("No valid session. Showing device login.")
		Game.transition_layer.change_scene(LOGIN_SCENE)
		return

	var bar_tween: Tween
	if progress_bar:
		progress_bar.value = 0
		bar_tween = create_tween()
		bar_tween.tween_property(progress_bar, "value", 100, 3.0)

	print("Capturing minimap snapshot...")
	await _capture_minimap()

	# Let the bar finish its 3s fill even if the capture above was faster.
	if bar_tween and bar_tween.is_running():
		await bar_tween.finished
	if progress_bar:
		progress_bar.value = 100

	# The dashboard scene belongs to the native build: it is the match browser and
	# skin picker for an app that has no website around it. On web the React site
	# already is that dashboard and hands the chosen match/skin over in the frame
	# URL, so the build goes straight into the lobby instead of showing a second,
	# in-engine dashboard on top of it.
	if OS.has_feature("web"):
		print("Loading complete. Entering lobby.")
		Game.transition_layer.change_scene(LOBBY_SCENE, _web_handoff())
		return

	print("Loading complete. Entering dashboard.")
	Game.transition_layer.change_scene(DASHBOARD_SCENE)

## Match/skin handed over by the page that embeds the build (?match=...&skin=...).
## Anything missing is left off the dictionary so the lobby keeps its own default
## instead of being overwritten with an empty string.
func _web_handoff() -> Dictionary:
	var handoff: Dictionary = {}
	var match_id := _web_query("match")
	if match_id != "" and match_id != "default":
		handoff["selected_match_id"] = match_id
	var skin_id := _web_query("skin")
	if skin_id != "":
		handoff["selected_skin_id"] = skin_id
	return handoff


func _web_query(key: String) -> String:
	if not OS.has_feature("web"):
		return ""
	var raw = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('%s') || ''" % key)
	if typeof(raw) != TYPE_STRING:
		return ""
	return str(raw).strip_edges()

## The web build signs in through the legacy /auth/request-token username
## handshake rather than the device-linking flow, so it must not be redirected.
func _requires_login() -> bool:
	if not NATIVE_LOGIN_REQUIRED:
		return false
	return not OS.has_feature("web")

func _capture_minimap() -> void:
	var map_scene = load("res://scenes/busyland.tscn")
	if not map_scene:
		return
	var map = map_scene.instantiate()

	var viewport = SubViewport.new()
	viewport.size = Vector2i(1024, 1024) if (OS.has_feature("mobile") or OS.has_feature("web")) else Vector2i(2048, 2048)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	add_child(viewport)
	viewport.add_child(map)

	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("9d3eff")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.5
	env_node.environment = env
	viewport.add_child(env_node)

	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-90, 0, 0)
	light.light_energy = 1.2
	viewport.add_child(light)

	var cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var world_size := 80.0
	cam.size = world_size
	var center := Vector3(0, 0, 0)
	cam.position = Vector3(center.x, 150.0, center.z)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	viewport.add_child(cam)

	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var tex = viewport.get_texture()
	var img = tex.get_image()
	if img:
		GameManager.minimap_texture = ImageTexture.create_from_image(img)
		GameManager.minimap_world_size = Vector2(world_size, world_size)
		GameManager.minimap_origin = Vector2.ZERO
		print("Minimap snapshot captured (Full Arena). Size: ", GameManager.minimap_world_size)

	viewport.queue_free()
