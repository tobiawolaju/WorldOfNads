extends SceneTree

## Headless regression check for the FX3D world-effect host.
##
##   godot --headless --path godot --script res://tools/fx3d_check.gd
##
## Verifies that ensure() is idempotent, that spawn() builds effects, that the
## per-id cap recycles the oldest, and that unknown ids fail soft instead of
## throwing. Excluded from export (tools/*), so it costs the pck nothing.

const FX3D_SCRIPT: GDScript = preload("res://scripts/fx/fx3d.gd")


func _initialize() -> void:
	var failures: Array[String] = []

	var host := Node3D.new()
	host.name = "TestWorld"
	root.add_child(host)
	# Let the host finish its _ready(); ensure() adds immediately to a ready
	# parent and defers while a scene root is still setting up children.
	await process_frame

	var first = FX3D_SCRIPT.ensure(host)
	var second = FX3D_SCRIPT.ensure(host)
	if first == null:
		failures.append("ensure() returned null")
	elif first != second:
		failures.append("ensure() created a duplicate host")
	elif host.get_children().size() != 1:
		failures.append("host should have exactly one child, has %d" % host.get_children().size())

	var effects: Node3D = first.get_node_or_null("Effects") as Node3D
	if effects == null:
		failures.append("FX3D has no Effects child")
		_finish(failures)
		return

	var cloud = first.spawn("smoke", Vector3(1, 0, 2), {"seed": 7})
	if cloud == null:
		failures.append("spawn('smoke') returned null")
	elif not effects.get_children().has(cloud):
		failures.append("spawned cloud is not under Effects")

	if first.spawn("does_not_exist", Vector3.ZERO) != null:
		failures.append("unknown effect id should return null")

	# Cap is 8 for smoke: ten spawns must leave at most eight alive.
	for i in 10:
		first.spawn("smoke", Vector3(i, 0, 0), {"seed": i})
	var alive := 0
	for child in effects.get_children():
		if not child.is_queued_for_deletion():
			alive += 1
	if alive > 8:
		failures.append("smoke cap not enforced, %d alive" % alive)

	var from_event = first.spawn_from_event({
		"meta": {"fx": "smoke", "x": 3, "y": 1, "z": 4, "seed": 11},
	})
	if from_event == null:
		failures.append("spawn_from_event() returned null")
	elif not is_equal_approx(from_event.global_position.x, 3.0) or not is_equal_approx(from_event.global_position.z, 4.0):
		failures.append("spawn_from_event() placed the effect at %s" % from_event.global_position)

	if first.spawn_from_event({"meta": {"x": 1, "y": 2, "z": 3}}) != null:
		failures.append("event without an effect id should return null")

	_finish(failures)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("FX3D check: OK")
		quit(0)
		return
	for failure in failures:
		printerr("FX3D check FAILED: " + failure)
	quit(1)
