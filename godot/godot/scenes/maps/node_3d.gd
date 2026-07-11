extends Node3D

@export var target_mesh: MeshInstance3D
@export var source_mesh: Mesh

@export var output_multimesh: MultiMeshInstance3D

@export var instance_count := 100
@export var instance_scale := 0.9

@export var ray_height := 200.0
@export var ray_depth := 500.0


func _ready():
	update_foliage()


func update_foliage():

	if target_mesh == null or source_mesh == null:
		return

	if output_multimesh == null:
		return

	create_multimesh()
	spawn_instances()


# ======================================================
# MULTIMESH SETUP
# ======================================================

func create_multimesh():

	var mm = MultiMesh.new()
	mm.mesh = source_mesh
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = instance_count

	output_multimesh.multimesh = mm


# ======================================================
# SURFACE SPAWN (REAL FIX)
# ======================================================

func spawn_instances():

	var mm = output_multimesh.multimesh
	var space = get_world_3d().direct_space_state

	var aabb = target_mesh.get_aabb()

	var placed := 0

	while placed < instance_count:

		var x = randf_range(aabb.position.x, aabb.position.x + aabb.size.x)
		var z = randf_range(aabb.position.z, aabb.position.z + aabb.size.z)

		var from = Vector3(x, ray_height, z)
		var to = Vector3(x, -ray_depth, z)

		var query = PhysicsRayQueryParameters3D.create(from, to)
		var hit = space.intersect_ray(query)

		if hit.is_empty():
			continue

		var pos = hit.position
		var normal = hit.normal

		# optional: slope filter
		if normal.y < 0.6:
			continue

		var t = Transform3D()
		t.origin = pos + normal * 0.02  # prevents z-fighting

		# align to ground optional (good for rocks)
		var up = Vector3.UP
		var axis = up.cross(normal).normalized()
		var angle = acos(up.dot(normal))

		if axis.length() > 0.001:
			t.basis = Basis(axis, angle)

		t.basis = t.basis.scaled(Vector3.ONE * instance_scale)

		mm.set_instance_transform(placed, t)
		placed += 1
