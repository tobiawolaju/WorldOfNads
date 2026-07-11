@tool
extends MeshInstance3D
class_name GolfTerrainGenerator

## Turns this MeshInstance3D into a subdivided, height-varied golf terrain.
## Attach to a MeshInstance3D, tweak params in the inspector, then either
## check "Regenerate" in the editor or call generate() at runtime.

@export var width: float = 100.0          # terrain size on X
@export var length: float = 200.0         # terrain size on Z (fairway direction)
@export var subdivisions_x: int = 60      # more subdivisions = smoother hills
@export var subdivisions_z: int = 120

@export_group("Height Shaping")
@export var noise_seed: int = 0
@export var hill_height: float = 4.0      # max height of rolling hills
@export var hill_frequency: float = 0.03  # lower = broader hills
@export var detail_height: float = 0.4    # small bumps on top of hills
@export var detail_frequency: float = 0.15

@export_group("Golf Features")
@export var flatten_tee: bool = true
@export var tee_z_position: float = -90.0 # near start of length (adjust to your -Z/+Z convention)
@export var tee_radius: float = 8.0

@export var flatten_green: bool = true
@export var green_z_position: float = 90.0
@export var green_radius: float = 12.0

@export var add_bunker: bool = true
@export var bunker_z_position: float = 60.0
@export var bunker_x_offset: float = 15.0
@export var bunker_radius: float = 6.0
@export var bunker_depth: float = 1.2

@export_group("Collision")
@export var generate_collision: bool = true

@export_group("Actions")
@export var regenerate: bool = false:
	set(value):
		if value:
			generate()
		regenerate = false

var _noise: FastNoiseLite
var _detail_noise: FastNoiseLite


func generate() -> void:
	_setup_noise()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var verts_x := subdivisions_x + 1
	var verts_z := subdivisions_z + 1
	var step_x := width / subdivisions_x
	var step_z := length / subdivisions_z

	var heights := []
	heights.resize(verts_x * verts_z)

	# First pass: compute height for every vertex
	for zi in range(verts_z):
		for xi in range(verts_x):
			var x := -width * 0.5 + xi * step_x
			var z := -length * 0.5 + zi * step_z
			heights[zi * verts_x + xi] = _height_at(x, z)

	# Second pass: build triangles with proper normals via SurfaceTool
	for zi in range(subdivisions_z):
		for xi in range(subdivisions_x):
			var i00 := zi * verts_x + xi
			var i10 := zi * verts_x + (xi + 1)
			var i01 := (zi + 1) * verts_x + xi
			var i11 := (zi + 1) * verts_x + (xi + 1)

			var x0 := -width * 0.5 + xi * step_x
			var x1 := -width * 0.5 + (xi + 1) * step_x
			var z0 := -length * 0.5 + zi * step_z
			var z1 := -length * 0.5 + (zi + 1) * step_z

			var p00 := Vector3(x0, heights[i00], z0)
			var p10 := Vector3(x1, heights[i10], z0)
			var p01 := Vector3(x0, heights[i01], z1)
			var p11 := Vector3(x1, heights[i11], z1)

			var uv00 := Vector2(float(xi) / subdivisions_x, float(zi) / subdivisions_z)
			var uv10 := Vector2(float(xi + 1) / subdivisions_x, float(zi) / subdivisions_z)
			var uv01 := Vector2(float(xi) / subdivisions_x, float(zi + 1) / subdivisions_z)
			var uv11 := Vector2(float(xi + 1) / subdivisions_x, float(zi + 1) / subdivisions_z)

			# Triangle 1
			_add_tri(st, p00, p10, p01, uv00, uv10, uv01)
			# Triangle 2
			_add_tri(st, p10, p11, p01, uv10, uv11, uv01)

	st.generate_normals()
	st.generate_tangents()

	mesh = st.commit()

	if generate_collision:
		_rebuild_collision()


func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	st.set_uv(ua)
	st.add_vertex(a)
	st.set_uv(ub)
	st.add_vertex(b)
	st.set_uv(uc)
	st.add_vertex(c)


func _setup_noise() -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = noise_seed
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency = hill_frequency

	_detail_noise = FastNoiseLite.new()
	_detail_noise.seed = noise_seed + 1
	_detail_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_detail_noise.frequency = detail_frequency


func _height_at(x: float, z: float) -> float:
	var h := _noise.get_noise_2d(x, z) * hill_height
	h += _detail_noise.get_noise_2d(x, z) * detail_height

	# Flatten tee box
	if flatten_tee:
		var d := Vector2(x, z).distance_to(Vector2(0.0, tee_z_position))
		if d < tee_radius:
			var t := _smooth(d / tee_radius)
			h = lerp(0.0, h, t)

	# Flatten green
	if flatten_green:
		var d := Vector2(x, z).distance_to(Vector2(0.0, green_z_position))
		if d < green_radius:
			var t := _smooth(d / green_radius)
			h = lerp(0.0, h, t)

	# Carve a bunker (depression)
	if add_bunker:
		var d := Vector2(x, z).distance_to(Vector2(bunker_x_offset, bunker_z_position))
		if d < bunker_radius:
			var t := _smooth(d / bunker_radius)
			h = lerp(h - bunker_depth, h, t)

	return h


func _smooth(t: float) -> float:
	t = clamp(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _rebuild_collision() -> void:
	# Remove old collision sibling if present
	var existing := get_node_or_null("TerrainCollision")
	if existing:
		existing.queue_free()

	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	add_child(body)
	if Engine.is_editor_hint():
		body.owner = get_tree().edited_scene_root

	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	if Engine.is_editor_hint():
		shape.owner = get_tree().edited_scene_root
