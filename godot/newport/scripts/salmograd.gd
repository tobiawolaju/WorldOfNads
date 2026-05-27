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

func _process(_delta):

	if camera == null:
		return

	var cam_pos = camera.global_transform.origin

	# Center the world around origin
	var offset_x = (grid_width * chunk_size) * 0.5
	var offset_z = (grid_height * chunk_size) * 0.5

	for x in range(grid_width):
		for z in range(grid_height):

			var chunk_name = str(x, "_", z)

			var chunk_pos = Vector3(
				(x * chunk_size) - offset_x,
				0,
				(z * chunk_size) - offset_z
			)

			handle_chunk(chunk_scene, chunk_pos, chunk_name, cam_pos)


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
