# Verifies the cylinder line-of-sight damage (aim assist) and distance falloff.
#   Godot_v4.8-beta1_win64_console.exe --headless --path godot --script res://tools/_test_los_damage.gd
extends SceneTree

var failures: int = 0
var _started: bool = false


## Minimal damageable target for the resolver's group fallback.
class Target extends Node3D:
	var hits: int = 0
	var total: float = 0.0
	var last_source: Node = null
	var bullet_hits: int = 0
	var hp: float = 100.0
	func take_damage(amount: float, source: Node = null, is_bullet: bool = false) -> void:
		hits += 1
		total += amount
		hp -= amount
		last_source = source
		if is_bullet:
			bullet_hits += 1
	func get_los_center() -> Vector3:
		return global_position + Vector3.UP * 1.0
	func is_remote_player() -> bool:
		return true


class Wall extends StaticBody3D:
	func _init() -> void:
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(4.0, 4.0, 0.5)
		col.shape = box
		add_child(col)


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	_run()
	return false


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var shooter := Node3D.new()
	world.add_child(shooter)
	shooter.global_position = Vector3.ZERO

	await physics_frame
	await physics_frame

	# 1) Direct hit inside the cylinder.
	var t1 := Target.new()
	t1.add_to_group("los_target")
	t1.global_position = Vector3(0.4, 0.0, -10.0) # 0.4 m off the -Z aim line
	world.add_child(t1)
	var hit = Bullet.resolve_los_damage(shooter, Vector3(0, 1, 0), Vector3(0, 0, -1),
			40.0, 60.0, 0.6, 10.0, 50.0, 0.4)
	_check("a target inside the aim cylinder is hit", hit == t1)
	_check("base damage applies inside the falloff-free range", t1.hits == 1 and is_equal_approx(t1.total, 40.0), str(t1.total))

	# 2) Outside the cylinder: no hit.
	var t2 := Target.new()
	t2.add_to_group("los_target")
	t2.global_position = Vector3(1.2, 0.0, -10.0) # 1.2 m off axis > 0.6 radius
	world.add_child(t2)
	var hit2 = Bullet.resolve_los_damage(shooter, Vector3(0, 1, 0), Vector3(0, 0, -1),
			40.0, 60.0, 0.6, 10.0, 50.0, 0.4)
	_check("a target outside the aim cylinder is missed", hit2 != t2 and t2.hits == 0)

	# 3) Distance falloff: far target takes reduced damage.
	var t3 := Target.new()
	t3.add_to_group("los_target")
	t3.global_position = Vector3(0.0, 0.0, -50.0) # at falloff_end
	world.add_child(t3)
	Bullet.resolve_los_damage(shooter, Vector3(0, 1, 0), Vector3(0, 0, -1),
			100.0, 80.0, 0.8, 10.0, 50.0, 0.4)
	_check("damage falls off with distance", t3.hits == 1 and t3.total < 50.0 and t3.total > 30.0, str(t3.total))
	_check("far damage reaches the minimum multiplier", is_equal_approx(t3.total, 40.0), str(t3.total))

	# 4) Occlusion: a wall blocks the shot.
	var wall := Wall.new()
	wall.global_position = Vector3(0.0, 1.0, -5.0)
	world.add_child(wall)
	await physics_frame
	await physics_frame
	var t4 := Target.new()
	t4.add_to_group("los_target")
	t4.global_position = Vector3(0.0, 0.0, -12.0)
	world.add_child(t4)
	var hit4 = Bullet.resolve_los_damage(shooter, Vector3(0, 1, 0), Vector3(0, 0, -1),
			40.0, 60.0, 0.8, 10.0, 50.0, 0.4)
	_check("a wall occludes the cylinder shot", hit4 != t4 and t4.hits == 0)

	# 5) Shooter is never hit by their own cylinder.
	# The shooter is excluded even if they stand in their own cylinder.
	var self_t := Target.new()
	self_t.add_to_group("los_target")
	self_t.global_position = Vector3(0.0, 0.0, -3.0)
	world.add_child(self_t)
	# Fire with self_t as shooter: resolver excludes shooter.
	Bullet.resolve_los_damage(self_t, self_t.get_los_center(), Vector3(0, 0, -1),
			40.0, 60.0, 0.8, 10.0, 50.0, 0.4)
	_check("the shooter is excluded from their own shot", self_t.hits == 0)

	if failures == 0:
		print("-- _test_los_damage: all checks passed --")
	else:
		print("-- _test_los_damage: %d FAILURE(S) --" % failures)
	quit(failures)


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  %s" % label)
	else:
		failures += 1
		var msg := "FAIL  %s" % label
		if detail != "":
			msg += " (%s)" % detail
		print(msg)


