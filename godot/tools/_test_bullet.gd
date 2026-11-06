# Checks the offline bullet: the scene carries the Bullet script, it leaves the
# muzzle, it ignores the shooter, and it removes health from whatever it hits.
#   Godot_v4.8-beta1_win64_console.exe --headless --path godot --script res://tools/_test_bullet.gd
extends SceneTree

const BULLET_SCENE := "res://scenes/props/bullet.tscn"

var failures: int = 0
var _started: bool = false


## A body that can be shot: records what the bullet did to it.
class Target extends CharacterBody3D:
	var hits: int = 0
	var total: float = 0.0
	var last_source: Node = null

	func take_damage(amount: float, source: Node = null) -> void:
		hits += 1
		total += amount
		last_source = source


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

	# The shooter exists only so the bullet can be told to ignore it.
	var shooter := CharacterBody3D.new()
	world.add_child(shooter)

	var target := Target.new()
	var target_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	target_shape.shape = box
	target.add_child(target_shape)
	world.add_child(target)
	target.global_position = Vector3(0.0, 0.0, -6.0)

	var packed: PackedScene = load(BULLET_SCENE)
	_check("bullet.tscn loads", packed != null)
	if packed == null:
		_finish()
		return
	var bullet: Node = packed.instantiate()
	_check("bullet.tscn carries the Bullet script", bullet.has_method("launch"))
	world.add_child(bullet)
	_check("bullet is a RigidBody3D", bullet is RigidBody3D)
	bullet.call("launch", Vector3.ZERO, Vector3(0.0, 0.0, -1.0), 130.0, 24.0, shooter)
	_check("bullet ignores its shooter",
			shooter in (bullet as RigidBody3D).get_collision_exceptions())

	for _i in 12:
		await physics_frame

	_check("an unobstructed shot reaches the target", target.hits == 1, str(target.hits))
	_check("damage matches the shot", is_equal_approx(target.total, 24.0), str(target.total))
	_check("the hit reports the shooter", target.last_source == shooter)
	_check("the bullet frees itself on impact", not is_instance_valid(bullet))

	# Slow-motion debug shot: gravity has to pull it down, it has to come to rest
	# on the floor, and it must linger there instead of vanishing on contact -
	# that resting bullet is the user's proof the projectile is real.
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(20.0, 0.2, 20.0)
	ground_shape.shape = ground_box
	ground.add_child(ground_shape)
	world.add_child(ground)
	ground.global_position = Vector3(0.0, -0.1, 0.0)

	var lobbed: Node = packed.instantiate()
	lobbed.set("linger_after_hit", 2.0)
	world.add_child(lobbed)
	(lobbed as RigidBody3D).gravity_scale = 1.0
	lobbed.call("launch", Vector3(0.0, 1.4, 0.0), Vector3(0.0, 0.0, -1.0), 6.0, 24.0, shooter)

	for _i in 60:
		await physics_frame
	_check("a slow shot drops under gravity", lobbed.global_position.y < 0.35,
			str(lobbed.global_position.y))
	_check("the landed bullet stops dead",
			(lobbed as RigidBody3D).linear_velocity.length() < 0.01)
	_check("the landed bullet is still there to be seen", is_instance_valid(lobbed))

	for _i in 120:
		await physics_frame
	_check("the landed bullet frees itself after lingering", not is_instance_valid(lobbed))

	_finish()


func _finish() -> void:
	print("bullet selftest: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  ", what)
		return
	failures += 1
	print("FAIL  ", what, "" if detail == "" else "  (got %s)" % detail)
