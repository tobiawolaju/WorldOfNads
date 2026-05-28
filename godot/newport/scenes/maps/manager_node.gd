extends Node3D

@export var terrain_mesh: MeshInstance3D

@export var grass_mesh: Mesh
@export var rock_mesh: Mesh
@export var snow_mesh: Mesh

@export var grass_mm: MultiMeshInstance3D
@export var rock_mm: MultiMeshInstance3D
@export var snow_mm: MultiMeshInstance3D

@export var instance_count := 100
@export var instance_scale := 0.9

@export var ray_origin_height := 200.0
@export var ray_length := 500.0


func _ready():
	setup_multimeshes()
	spawn_all()


# ======================================================
# MULTIMESH INIT
# ======================================================

func setup_multimeshes():

	grass_mm.multimesh = create_multimesh(grass_mesh)
	rock_mm.multimesh = create_multimesh(rock_mesh)
	snow_mm.multimesh = create_multimesh(snow_mesh)


func create_multimesh(mesh: Mesh) -> MultiMesh:

	var mm = MultiMesh.new()
	mm.mesh = mesh
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = instance_count

	return mm


# ======================================================
# SPAWN
# ======================================================

func spawn_all():

	var aabb = terrain_mesh.get_aabb()

	spawn_layer(grass_mm.multimesh, aabb)
	spawn_layer(rock_mm.multimesh, aabb)
	spawn_layer(snow_mm.multimesh, aabb)


func spawn_layer(mm: MultiMesh, aabb: AABB):

	for i in mm.instance_count:

		var x = randf_range(
			aabb.position.x,
			aabb.position.x + aabb.size.x
		)

		var z = randf_range(
			aabb.position.z,
			aabb.position.z + aabb.size.z
		)

		var pos = get_terrain_hit(Vector3(x, ray_origin_height, z))

		if pos == null:
			continue

		var world_pos = pos.position

		var t = Transform3D()
		t.origin = world_pos

		t.basis = Basis().scaled(Vector3.ONE * instance_scale)

		mm.set_instance_transform(i, t)


# ======================================================
# RAYCAST HEIGHT FIX
# ======================================================

func get_terrain_hit(from_pos: Vector3):

	var space_state = get_world_3d().direct_space_state

	var query = PhysicsRayQueryParameters3D.new()
	query.from = from_pos
	query.to = from_pos - Vector3.UP * ray_length

	var result = space_state.intersect_ray(query)

	if result.is_empty():
		return null

	return result
