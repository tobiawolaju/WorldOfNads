# Checks the melee swing: knife/sword damage is real, range is limited, a spam
# press during the swing does not hit twice, and each weapon keeps its own number.
#   Godot_v4.8-beta1_win64_console.exe --headless --path godot --script res://tools/_test_melee.gd
extends SceneTree

const SKIN_SCENE := "res://scenes/skin.tscn"
const SWORD := 1
const KNIFE := 4

var failures: int = 0
var _started: bool = false


## A body that can be hit: records what took the damage.
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

	var player: Node = (load(SKIN_SCENE) as PackedScene).instantiate()
	world.add_child(player)
	await process_frame
	player.set("is_local", true)

	# This rig faces +Z (its left foot sits on +X), so "in front" is +Z. Both
	# targets sit on that axis: one out of reach, one inside the knife's 1.6 m.
	var far := _target_at(Vector3(0.0, 1.0, 4.0))
	world.add_child(far)
	_equip(player, KNIFE)
	player.call("_use_held_weapon")
	await physics_frame
	await physics_frame
	_check("a swing misses a target out of reach", far.hits == 0, str(far.hits))

	# Skip the 1.3 s swing lock the way real play would.
	player.set("_weapon_action_active", false)

	var near := _target_at(Vector3(0.0, 1.0, 1.8))
	world.add_child(near)
	_equip(player, KNIFE)
	player.call("_use_held_weapon")
	# Second press lands while the swing clip is still playing: melee is one at a
	# time, so it must be dropped.
	player.call("_use_held_weapon")
	await physics_frame
	await physics_frame
	_check("a knife swing hits a target in reach", near.hits == 1, str(near.hits))
	_check("the knife deals its own damage", is_equal_approx(near.total, 34.0), str(near.total))
	_check("the hit reports the player", near.last_source == player)
	_check("a spam press during the swing does not hit twice", near.hits == 1, str(near.hits))

	player.set("_weapon_action_active", false)
	_equip(player, SWORD)
	player.call("_use_held_weapon")
	await physics_frame
	await physics_frame
	_check("the sword hits harder than the knife",
			is_equal_approx(near.total, 34.0 + 46.0), str(near.total))

	_finish()


func _target_at(at: Vector3) -> Target:
	var target := Target.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	shape.shape = box
	target.add_child(shape)
	target.position = at
	return target


func _equip(player: Node, kind: int) -> void:
	player.set("held_weapon_kind", kind)
	player.set("held_weapon_max_uses", 5)
	player.set("held_weapon_uses", 5)


func _finish() -> void:
	print("melee selftest: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  ", what)
		return
	failures += 1
	print("FAIL  ", what, "" if detail == "" else "  (got %s)" % detail)
