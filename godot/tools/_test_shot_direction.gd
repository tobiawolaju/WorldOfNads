# Checks that a bullet follows the muzzle marker and nothing else: rotating the
# marker in the rig is the only thing that aims, and the camera has no say.
#   Godot_v4.8-beta1_win64_console.exe --headless --path godot --script res://tools/_test_shot_direction.gd
extends SceneTree

const SKIN_SCENE := "res://scenes/skin.tscn"
const GLOCK := 3
const MUZZLE_PATH := "Skeleton3D/Marker3D"

var failures: int = 0
var _started: bool = false


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	_run()  # async, not awaited: _process must keep running for physics to tick
	return false


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world

	# The player resolves a Camera3D from the tree; it must not matter to shots.
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	world.add_child(camera)
	camera.global_transform = Transform3D(Basis(), Vector3(0.0, 1.6, 6.0))
	camera.current = true

	var player: Node = (load(SKIN_SCENE) as PackedScene).instantiate()
	world.add_child(player)
	await process_frame
	player.set("is_local", true)
	player.set("held_weapon_kind", GLOCK)
	# No gravity: this suite is about direction only.
	player.set("bullet_gravity_scale", 0.0)

	var marker := player.get_node_or_null(MUZZLE_PATH) as Node3D
	_check("the rig has a muzzle marker", marker != null)
	if marker == null:
		_finish()
		return

	# Markers inherit the hand bone, so turn it from wherever the pose left it.
	marker.rotation = Vector3.ZERO
	marker.rotate_y(deg_to_rad(35.0))
	var expected := -marker.global_transform.basis.z.normalized()
	var first := _fire(player, world)
	_check("a shot spawns a bullet", first != null)
	if first == null:
		_finish()
		return
	_check("the bullet leaves along the marker's -Z",
			first.linear_velocity.normalized().dot(expected) > 0.999,
			"dot=%.5f" % first.linear_velocity.normalized().dot(expected))

	# The camera is decoration: pointing it somewhere else changes nothing.
	camera.global_transform = Transform3D(
			Basis(Vector3.UP, deg_to_rad(-130.0)), Vector3(-6.0, 2.5, 1.0))
	var second := _fire(player, world)
	_check("moving the camera does not change the shot",
			second != null and second.linear_velocity.normalized().dot(expected) > 0.999,
			"dot=%.5f" % (second.linear_velocity.normalized().dot(expected) if second != null else 0.0))

	# Turning the marker is the aim.
	marker.rotate_y(deg_to_rad(-70.0))
	var expected2 := -marker.global_transform.basis.z.normalized()
	var third := _fire(player, world)
	_check("turning the marker turns the shot",
			third != null and third.linear_velocity.normalized().dot(expected2) > 0.999,
			"dot=%.5f" % (third.linear_velocity.normalized().dot(expected2) if third != null else 0.0))
	_check("the marker really is turned away from the camera",
			expected2.dot(Vector3(0.0, 0.0, -1.0)) < 0.99,
			"dot=%.5f" % expected2.dot(Vector3(0.0, 0.0, -1.0)))

	# A rig without a marker still fires, along the character's facing: never at
	# the camera, never at the floor.
	var skeleton := player.get_node("Skeleton3D") as Node3D
	# This rig is authored facing +Z (left foot on +X), and mesh.rotation.y puts that
	# +Z on the movement direction, so +Z is the character's forward.
	var body := skeleton.global_transform.basis.z.normalized()
	marker.name = "Marker3D_hidden"
	var fallback: Vector3 = player.call("_shot_direction")
	_check("without a marker the shot follows the character facing",
			fallback.dot(body) > 0.999, "dot=%.5f" % fallback.dot(body))
	marker.name = "Marker3D"

	# The debug line draws whatever the marker says, so it can be checked by eye.
	player.set("show_shot_line", true)
	var guard := 0
	while player.get_node_or_null("ShotLine") == null and guard < 120:
		guard += 1
		await physics_frame
	var line := player.get_node_or_null("ShotLine") as MeshInstance3D
	_check("the aim line is built while checking", line != null and line.visible)
	if line != null:
		_check("the aim line carries vertices",
				(line.mesh as ImmediateMesh).get_surface_count() > 0)
		_check("the aim line is drawn in world space", line.top_level)

	_finish()


## Fires one shot and returns the bullet it spawned, so the launch velocity can be
## read before gravity or a collision can touch it.
func _fire(player: Node, world: Node) -> RigidBody3D:
	var before: Dictionary = {}
	for child in world.get_children():
		before[child.get_instance_id()] = true
	player.call("_fire_bullet", {"damage": 24.0, "bullet_speed": 130.0})
	for child in world.get_children():
		if child is RigidBody3D and child.has_method("launch") \
				and not before.has(child.get_instance_id()):
			return child
	return null


func _finish() -> void:
	print("shot direction selftest: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  ", what)
		return
	failures += 1
	print("FAIL  ", what, "" if detail == "" else "  (got %s)" % detail)
