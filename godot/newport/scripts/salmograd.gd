extends Node3D

@export var camera: Camera3D

# =========================
# CHUNK SCENE
# =========================

@export var chunk_scene: PackedScene

# =========================
# GRID SETTINGS
# =========================

@export var grid_width: int = 50
@export var grid_height: int = 50

@export var chunk_size: float = 4.0

# =========================
# STREAMING SETTINGS
# =========================

@export var load_distance: float = 40.0
@export var unload_distance: float = 55.0

# =========================
# INTERNAL STORAGE
# =========================

var loaded_chunks = {}
var _last_camera_chunk: Vector2i = Vector2i(2147483647, 2147483647)
var _grid_origin_x: float = 0.0
var _grid_origin_z: float = 0.0
var _chunk_scan_radius: int = 0

func _process(_delta):

	if camera == null:
		return

	var cam_pos = camera.global_transform.origin
	var current_chunk := Vector2i(
		floori((cam_pos.x + _grid_origin_x) / chunk_size),
		floori((cam_pos.z + _grid_origin_z) / chunk_size)
	)

	if current_chunk == _last_camera_chunk:
		return

	_last_camera_chunk = current_chunk
	_refresh_chunks(cam_pos, false)


func _ready() -> void:
	_grid_origin_x = (grid_width * chunk_size) * 0.5
	_grid_origin_z = (grid_height * chunk_size) * 0.5
	_chunk_scan_radius = int(ceil(unload_distance / chunk_size))
	if camera == null:
		return
	var initial_cam_pos := Vector3.ZERO
	initial_cam_pos = camera.global_transform.origin
	_last_camera_chunk = Vector2i(
		floori((initial_cam_pos.x + _grid_origin_x) / chunk_size),
		floori((initial_cam_pos.z + _grid_origin_z) / chunk_size)
	)
	_refresh_chunks(initial_cam_pos, false)


func _refresh_chunks(cam_pos: Vector3, force_full_scan: bool) -> void:
	if chunk_scene == null:
		return

	var visible_chunks := {}
	var min_x := maxi(0, _last_camera_chunk.x - _chunk_scan_radius)
	var max_x := mini(grid_width - 1, _last_camera_chunk.x + _chunk_scan_radius)
	var min_z := maxi(0, _last_camera_chunk.y - _chunk_scan_radius)
	var max_z := mini(grid_height - 1, _last_camera_chunk.y + _chunk_scan_radius)

	if force_full_scan:
		min_x = 0
		max_x = grid_width - 1
		min_z = 0
		max_z = grid_height - 1

	for x in range(min_x, max_x + 1):
		for z in range(min_z, max_z + 1):
			var chunk_name := str(x, "_", z)
			visible_chunks[chunk_name] = true
			var chunk_pos := Vector3(
				(x * chunk_size) - _grid_origin_x,
				0.0,
				(z * chunk_size) - _grid_origin_z
			)
			handle_chunk(chunk_scene, chunk_pos, chunk_name, cam_pos)

	for chunk_name in loaded_chunks.keys():
		if not visible_chunks.has(chunk_name):
			loaded_chunks[chunk_name].queue_free()
			loaded_chunks.erase(chunk_name)


func handle_chunk(scene: PackedScene, chunk_pos: Vector3, chunk_name: String, cam_pos: Vector3):

	if scene == null:
		return

	var distance = cam_pos.distance_to(chunk_pos)

	# =========================
	# LOAD
	# =========================

	if distance <= load_distance:

		if not loaded_chunks.has(chunk_name):

			var chunk_instance = scene.instantiate()
			add_child(chunk_instance)

			chunk_instance.global_position = chunk_pos

			loaded_chunks[chunk_name] = chunk_instance

	# =========================
	# UNLOAD
	# =========================

	elif distance > unload_distance:

		if loaded_chunks.has(chunk_name):

			loaded_chunks[chunk_name].queue_free()
			loaded_chunks.erase(chunk_name)
