@tool
extends MeshInstance3D

#
# =========================================================
# PROCEDURAL TERRAIN BIOME POPULATOR
# =========================================================
#
# Attach this script to the terrain MeshInstance3D.
#
# Features:
# - editor-time generation with @tool
# - automatic MultiMeshInstance3D creation/reuse
# - height-based biome scattering
# - raycast-based terrain surface placement
# - inspector buttons for generate / clear
# - optional slope alignment, slope filtering, and deterministic seeds
#
# The terrain is expected to already have collision in the scene.
#
# =========================================================


const BIOME_SNOW := "SnowMMI"
const BIOME_ROCK := "RockMMI"
const BIOME_GRASS := "GrassMMI"
const BIOME_LOW := "LowMMI"


#
# =========================================================
# BIOME 1: SNOW
# =========================================================
#

@export_group("Snow Biome")

@export var snow_mesh: Mesh
@export var snow_material: Material
@export_range(0, 100000, 1) var snow_instance_count := 100
@export var snow_min_height := 45.0
@export var snow_max_height := 999999.0


#
# =========================================================
# BIOME 2: ROCK
# =========================================================
#

@export_group("Rock Biome")

@export var rock_mesh: Mesh
@export var rock_material: Material
@export_range(0, 100000, 1) var rock_instance_count := 100
@export var rock_min_height := 22.0
@export var rock_max_height := 45.0


#
# =========================================================
# BIOME 3: GRASS
# =========================================================
#

@export_group("Grass Biome")

@export var grass_mesh: Mesh
@export var grass_material: Material
@export_range(0, 100000, 1) var grass_instance_count := 100
@export var grass_min_height := 6.0
@export var grass_max_height := 22.0


#
# =========================================================
# BIOME 4: LOW
# =========================================================
#

@export_group("Low Biome")

@export var low_mesh: Mesh
@export var low_material: Material
@export_range(0, 100000, 1) var low_instance_count := 100
@export var low_min_height := -999999.0
@export var low_max_height := 6.0


#
# =========================================================
# DISTRIBUTION / RANDOMIZATION
# =========================================================
#

@export_group("Distribution")

@export_range(0.0, 10.0, 0.01) var density_multiplier := 1.0
@export_range(0.0, 1000.0, 0.1) var terrain_bounds_padding := 0.0
@export_range(1, 500, 1) var max_attempts_per_instance := 50
@export var terrain_world_offset := Vector3.ZERO


@export_group("Randomization")

@export var random_y_rotation := true
@export var random_uniform_scale := true
@export_range(0.01, 100.0, 0.01) var min_scale := 0.8
@export_range(0.01, 100.0, 0.01) var max_scale := 1.3
@export var use_deterministic_seed := false
@export var random_seed := 1337


#
# =========================================================
# SURFACE FITTING
# =========================================================
#

@export_group("Surface Fitting")

@export var align_to_surface_normal := false
@export var enable_slope_filter := false
@export_range(0.0, 89.9, 0.1) var max_slope_degrees := 45.0
@export_range(-10.0, 10.0, 0.01) var surface_height_offset := 0.0


#
# =========================================================
# RAYCAST CONTROL
# =========================================================
#

@export_group("Raycast")

@export_range(0.0, 100000.0, 0.1) var raycast_margin := 2000.0
@export_range(0, 4294967295, 1) var collision_mask_override := 0
@export var raycast_exclude_paths: Array[NodePath] = []


#
# =========================================================
# EDITOR ACTIONS
# =========================================================
#

@export_group("Actions")

@export var auto_generate_on_ready := true

@export var generate_button := false:
	set(value):
		if value:
			_schedule_editor_refresh(true)
	get:
		return false

@export var clear_button := false:
	set(value):
		if value:
			_clear_all_instances(true)
	get:
		return false


var _snow_mmi: MultiMeshInstance3D
var _rock_mmi: MultiMeshInstance3D
var _grass_mmi: MultiMeshInstance3D
var _low_mmi: MultiMeshInstance3D

var _editor_refresh_pending := false
var _editor_refresh_scheduled := false
var _is_generating := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if Engine.is_editor_hint():
		if auto_generate_on_ready:
			_schedule_editor_refresh(false)
		elif _editor_refresh_pending:
			_schedule_editor_refresh(false)


#
# =========================================================
# PUBLIC ENTRY POINTS
# =========================================================
#

func _schedule_editor_refresh(force: bool) -> void:
	if not Engine.is_editor_hint():
		return

	if not is_inside_tree():
		_editor_refresh_pending = true
		return

	if _editor_refresh_scheduled and not force:
		return

	_editor_refresh_pending = false
	_editor_refresh_scheduled = true
	call_deferred("_refresh_now")


func _refresh_now() -> void:
	_editor_refresh_scheduled = false

	if not Engine.is_editor_hint():
		return

	if not is_inside_tree():
		_editor_refresh_pending = true
		return

	_generate_all_biomes()


func _clear_all_instances(_from_button: bool = false) -> void:
	_ensure_biome_nodes()

	_clear_mmi_instances(_snow_mmi)
	_clear_mmi_instances(_rock_mmi)
	_clear_mmi_instances(_grass_mmi)
	_clear_mmi_instances(_low_mmi)


func _generate_all_biomes() -> void:
	if _is_generating:
		return
	if not Engine.is_editor_hint():
		return

	_is_generating = true

	_ensure_biome_nodes()
	_clear_all_instances()
	_seed_rng()

	_generate_biome(
		_snow_mmi,
		snow_mesh,
		snow_material,
		snow_instance_count,
		snow_min_height,
		snow_max_height
	)

	_generate_biome(
		_rock_mmi,
		rock_mesh,
		rock_material,
		rock_instance_count,
		rock_min_height,
		rock_max_height
	)

	_generate_biome(
		_grass_mmi,
		grass_mesh,
		grass_material,
		grass_instance_count,
		grass_min_height,
		grass_max_height
	)

	_generate_biome(
		_low_mmi,
		low_mesh,
		low_material,
		low_instance_count,
		low_min_height,
		low_max_height
	)

	_is_generating = false


#
# =========================================================
# NODE MANAGEMENT
# =========================================================
#

func _ensure_biome_nodes() -> void:
	_snow_mmi = _get_or_create_biome_node(BIOME_SNOW)
	_rock_mmi = _get_or_create_biome_node(BIOME_ROCK)
	_grass_mmi = _get_or_create_biome_node(BIOME_GRASS)
	_low_mmi = _get_or_create_biome_node(BIOME_LOW)


func _get_or_create_biome_node(node_name: String) -> MultiMeshInstance3D:
	var existing := _find_existing_biome_node(node_name)
	if existing != null:
		_ensure_unique_multimesh(existing)
		return existing

	var parent_node := _get_biome_parent()
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = _create_multimesh()

	parent_node.add_child(mmi)

	var root := get_tree().edited_scene_root if get_tree() != null else null
	if root != null:
		mmi.owner = root

	return mmi


func _find_existing_biome_node(node_name: String) -> MultiMeshInstance3D:
	var root := get_tree().edited_scene_root if get_tree() != null else null
	if root != null:
		var candidate := root.find_child(node_name, true, false)
		if candidate is MultiMeshInstance3D:
			return candidate

	var local_candidate := get_node_or_null(node_name)
	if local_candidate is MultiMeshInstance3D:
		return local_candidate

	return null


func _get_biome_parent() -> Node:
	if get_tree() != null and get_tree().edited_scene_root != null:
		return get_tree().edited_scene_root

	var parent_node := get_parent()
	if parent_node != null:
		return parent_node

	return self


func _ensure_unique_multimesh(mmi: MultiMeshInstance3D) -> void:
	mmi.multimesh = _create_multimesh()


func _create_multimesh() -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	return mm


#
# =========================================================
# BIOME GENERATION
# =========================================================
#

func _generate_biome(
	mmi: MultiMeshInstance3D,
	mesh: Mesh,
	material: Material,
	instance_count: int,
	min_height: float,
	max_height: float
) -> void:
	if mmi == null:
		return

	_ensure_unique_multimesh(mmi)

	var multimesh := mmi.multimesh
	multimesh.mesh = mesh
	mmi.material_override = material

	var effective_count := maxi(0, roundi(float(instance_count) * density_multiplier))
	if mesh == null or effective_count == 0:
		multimesh.instance_count = 0
		multimesh.visible_instance_count = 0
		return

	var height_range := _normalize_height_range(min_height, max_height)
	var world_aabb := _get_world_aabb()
	if world_aabb.size == Vector3.ZERO:
		multimesh.instance_count = 0
		multimesh.visible_instance_count = 0
		return

	multimesh.instance_count = effective_count
	multimesh.visible_instance_count = 0

	var placed := 0
	var attempts := 0
	var max_attempts := maxi(1, effective_count * max_attempts_per_instance)
	var slope_limit := cos(deg_to_rad(max_slope_degrees))

	while placed < effective_count and attempts < max_attempts:
		attempts += 1

		var sample := _random_world_xz_in_bounds(world_aabb)
		var hit := _raycast_terrain(sample.x, sample.y)
		if hit.is_empty():
			continue

		var hit_position: Vector3 = hit["position"]
		var hit_normal: Vector3 = hit.get("normal", Vector3.UP).normalized()

		if hit_position.y < height_range.x or hit_position.y > height_range.y:
			continue

		if enable_slope_filter and hit_normal.dot(Vector3.UP) < slope_limit:
			continue

		var basis := _build_instance_basis(hit_normal)
		var scale_value := _get_instance_scale()

		if random_y_rotation:
			var yaw_axis := hit_normal if align_to_surface_normal else Vector3.UP
			basis = basis.rotated(yaw_axis, _rng.randf_range(0.0, TAU))

		basis = basis.scaled(Vector3.ONE * scale_value)

		var transform := Transform3D(
			basis,
			hit_position + terrain_world_offset + Vector3.UP * surface_height_offset
		)

		multimesh.set_instance_transform(placed, transform)
		placed += 1

	if placed <= 0:
		multimesh.instance_count = 0
		multimesh.visible_instance_count = 0
		return

	if placed < effective_count:
		multimesh.instance_count = placed

	multimesh.visible_instance_count = placed


func _normalize_height_range(min_height: float, max_height: float) -> Vector2:
	if min_height <= max_height:
		return Vector2(min_height, max_height)
	return Vector2(max_height, min_height)


func _get_instance_scale() -> float:
	if not random_uniform_scale:
		return 1.0
	return _rng.randf_range(min_scale, max_scale)


func _build_instance_basis(surface_normal: Vector3) -> Basis:
	if not align_to_surface_normal:
		return Basis.IDENTITY

	var up := surface_normal.normalized()
	if up.length_squared() <= 0.000001:
		up = Vector3.UP

	var reference := Vector3.FORWARD
	if absf(up.dot(reference)) > 0.98:
		reference = Vector3.RIGHT

	var right := reference.cross(up).normalized()
	var forward := up.cross(right).normalized()

	return Basis(right, up, forward)


#
# =========================================================
# TERRAIN SAMPLING / RAYCAST
# =========================================================
#

func _get_world_aabb() -> AABB:
	var local_aabb := get_aabb()
	if local_aabb.size == Vector3.ZERO:
		return AABB()

	var xform := global_transform
	var min_v := Vector3(INF, INF, INF)
	var max_v := Vector3(-INF, -INF, -INF)

	for x in [0.0, local_aabb.size.x]:
		for y in [0.0, local_aabb.size.y]:
			for z in [0.0, local_aabb.size.z]:
				var corner := local_aabb.position + Vector3(x, y, z)
				var world_corner := xform * corner

				min_v.x = minf(min_v.x, world_corner.x)
				min_v.y = minf(min_v.y, world_corner.y)
				min_v.z = minf(min_v.z, world_corner.z)

				max_v.x = maxf(max_v.x, world_corner.x)
				max_v.y = maxf(max_v.y, world_corner.y)
				max_v.z = maxf(max_v.z, world_corner.z)

	return AABB(min_v, max_v - min_v)


func _random_world_xz_in_bounds(world_aabb: AABB) -> Vector2:
	var min_x := world_aabb.position.x + terrain_bounds_padding
	var max_x := world_aabb.position.x + world_aabb.size.x - terrain_bounds_padding
	var min_z := world_aabb.position.z + terrain_bounds_padding
	var max_z := world_aabb.position.z + world_aabb.size.z - terrain_bounds_padding

	if max_x <= min_x:
		min_x = world_aabb.position.x
		max_x = world_aabb.position.x + world_aabb.size.x

	if max_z <= min_z:
		min_z = world_aabb.position.z
		max_z = world_aabb.position.z + world_aabb.size.z

	return Vector2(
		_rng.randf_range(min_x, max_x),
		_rng.randf_range(min_z, max_z)
	)


func _raycast_terrain(world_x: float, world_z: float) -> Dictionary:
	var world := get_world_3d()
	if world == null:
		return {}

	var terrain_aabb := _get_world_aabb()
	if terrain_aabb.size == Vector3.ZERO:
		return {}

	var top_y := terrain_aabb.position.y + terrain_aabb.size.y + raycast_margin
	var bottom_y := terrain_aabb.position.y - raycast_margin

	var from := Vector3(world_x, top_y, world_z) + terrain_world_offset
	var to := Vector3(world_x, bottom_y, world_z) + terrain_world_offset

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.hit_from_inside = false
	query.collision_mask = _get_raycast_collision_mask()

	var exclusions := _get_raycast_exclusions()
	var terrain_body := _find_terrain_collision_object()
	var safety_passes := 0

	while safety_passes < 16:
		safety_passes += 1
		query.exclude = exclusions

		var result := world.direct_space_state.intersect_ray(query)
		if result.is_empty():
			return {}

		var collider := result.get("collider")
		if terrain_body == null or collider == terrain_body:
			return result

		if collider is CollisionObject3D:
			exclusions.append(collider.get_rid())
		query.set("from", result["position"] + Vector3.DOWN * 0.01)

	return {}


func _get_raycast_collision_mask() -> int:
	if collision_mask_override != 0:
		return collision_mask_override

	var terrain_body := _find_terrain_collision_object()
	if terrain_body != null and terrain_body.collision_layer != 0:
		return terrain_body.collision_layer

	return 0xFFFFFFFF


func _find_terrain_collision_object() -> CollisionObject3D:
	var current := get_parent()
	while current != null:
		if current is CollisionObject3D:
			return current
		current = current.get_parent()
	return null


func _get_raycast_exclusions() -> Array[RID]:
	var exclusions: Array[RID] = []

	for path in raycast_exclude_paths:
		if path.is_empty():
			continue
		var node := get_node_or_null(path)
		if node is CollisionObject3D:
			exclusions.append(node.get_rid())

	return exclusions


#
# =========================================================
# CLEARING
# =========================================================
#

func _clear_mmi_instances(mmi: MultiMeshInstance3D) -> void:
	if mmi == null:
		return
	if mmi.multimesh == null:
		mmi.multimesh = _create_multimesh()

	mmi.multimesh.instance_count = 0
	mmi.multimesh.visible_instance_count = 0


#
# =========================================================
# RNG
# =========================================================
#

func _seed_rng() -> void:
	if use_deterministic_seed:
		_rng.seed = random_seed
	else:
		_rng.randomize()
