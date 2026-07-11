extends Node

@onready var progress_bar: ProgressBar = $"CanvasLayer/BoxContainer/Node/ProgressBar"

var _total_resources: int = 0
var _loaded_resources: int = 0
var _is_loading: bool = false

# These are the big assets that usually cause stutter
var _assets_to_load = [
	"res://scenes/lobby.tscn",
	"res://scenes/gameplay.tscn",
	"res://scenes/skin1.tscn",
	"res://scenes/skin2.tscn",
	"res://scenes/skin3.tscn",
	"res://scenes/skin4.tscn",
	"res://scenes/skin5.tscn",
	"res://scenes/skin6.tscn",
	"res://scenes/skin7.tscn",
	"res://scenes/skin8.tscn",
	"res://scenes/maps/salmograd.tscn",
	"res://scenes/props/enviroment/bus.tscn",
	"res://scenes/waypoint.tscn"
]

func _ready() -> void:
	_total_resources = _assets_to_load.size()
	_start_async_load()

func _start_async_load() -> void:
	_is_loading = true
	for path in _assets_to_load:
		ResourceLoader.load_threaded_request(path)

func _process(_delta: float) -> void:
	if not _is_loading:
		return
		
	var total_progress: float = 0.0
	var finished_count: int = 0
	
	for path in _assets_to_load:
		var progress = []
		var status = ResourceLoader.load_threaded_get_status(path, progress)
		
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			finished_count += 1
			total_progress += 1.0
		elif status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			total_progress += progress[0]
		elif status == ResourceLoader.THREAD_LOAD_FAILED:
			print("Failed to load: ", path)
			finished_count += 1 # Skip it
			
	_loaded_resources = finished_count
	progress_bar.value = (total_progress / _total_resources) * 100
	
	if finished_count == _total_resources:
		_on_loading_complete()

func _on_loading_complete() -> void:
	_is_loading = false
	print("All resources pre-loaded. Starting shader compilation...")
	
	# Trigger shader caching and wait for it
	if has_node("/root/ShaderCache"):
		var sc = get_node("/root/ShaderCache")
		sc.pre_cache_shaders()
		# ShaderCache takes 2 frames, let's wait a bit more just in case
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
	
	print("Shader compilation complete. Capturing minimap snapshot...")
	await _capture_minimap()
	
	print("Loading complete. Entering lobby.")
	TransitionScreen.change_scene("res://scenes/lobby.tscn")

func _capture_minimap() -> void:
	# 1. Instantiate the map
	var map_scene = load("res://scenes/maps/salmograd.tscn")
	if not map_scene:
		return
	var map = map_scene.instantiate()
	
	# 2. Create a temporary viewport
	var viewport = SubViewport.new()
	viewport.size = Vector2i(1024, 1024) if (OS.has_feature("mobile") or OS.has_feature("web")) else Vector2i(2048, 2048)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS # Force update
	viewport.transparent_bg = false # Use environment background
	add_child(viewport)
	viewport.add_child(map)
	
	# 2.5 Setup Environment & Light for consistent capture
	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("9d3eff") # Vibrant Purple/Pink
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.5
	env_node.environment = env
	viewport.add_child(env_node)
	
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-90, 0, 0) # Straight down
	light.light_energy = 1.2
	viewport.add_child(light)
	
	# 3. Setup a top-down orthogonal camera
	var cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	
	# Use terrain size from the PlaneMesh (80x80)
	var world_size := 80.0
	cam.size = world_size
	
	var center := Vector3(0, 0, 0)
	
	cam.position = Vector3(center.x, 150.0, center.z)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	viewport.add_child(cam)
	
	# 5. Wait for the engine to render the scene
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	
	# 6. Capture the texture
	var tex = viewport.get_texture()
	var img = tex.get_image()
	if img:
		GameManager.minimap_texture = ImageTexture.create_from_image(img)
		GameManager.minimap_world_size = Vector2(world_size, world_size)
		GameManager.minimap_origin = Vector2.ZERO
		print("Minimap snapshot captured (Full Arena). Size: ", GameManager.minimap_world_size)
	
	# 7. Cleanup
	viewport.queue_free()
