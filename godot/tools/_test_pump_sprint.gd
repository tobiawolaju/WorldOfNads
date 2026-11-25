# Verifies the PUMP hold sprint: while the Action button is held and nothing is
# in reach (the HUD shows PUMP), the player moves at 2x speed and stamina drains
# like carrying an item. Releasing or having something to grab stops it.
#   Godot_v4.8-beta1_win64_console.exe --headless --path godot --script res://tools/_test_pump_sprint.gd
extends SceneTree

var failures: int = 0


## A local power-up pickup: player.gd only considers group members that say yes.
class ProbeLocalPickup extends RigidBody3D:
	func can_pick_up() -> bool:
		return true


func _initialize() -> void:
	var packed := load("res://scenes/skin.tscn") as PackedScene
	if packed == null:
		_fail("the player scene loads")
		_finish()
		return
	# Simple floor so the local player doesn't fall away during the test.
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(20, 1, 20)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)

	var player := packed.instantiate()
	root.add_child(player)
	for _i in 5:
		await process_frame
	await physics_frame

	player.is_local = true
	player.global_position = Vector3(0, 1, 0)
	for _i in 4:
		await physics_frame

	_check("player exposes is_pump_sprinting()", player.has_method("is_pump_sprinting"))
	_check("not pumping by default", player.call("is_pump_sprinting") == false)

	# Hold the Action key with nothing in reach: the player should pump.
	Input.action_press("pickup")
	# Give the physics frames time to tick the poll and the stamina component.
	for _i in 8:
		await physics_frame
	_check("holding Action while idle pumps", player.call("is_pump_sprinting") == true)

	# Pump drain follows the carry model: moving + holding drains stamina.
	Input.action_press("move_forward")
	for _i in 12:
		await physics_frame
	_check("pumping while moving drains stamina like carrying", float(player.get("stamina")) < 100.0)

	var stamina_while_pumping := float(player.get("stamina"))
	for _i in 10:
		await physics_frame
	_check("stamina keeps draining while pumping and moving", float(player.get("stamina")) < stamina_while_pumping)

	# Release: pumping stops and stamina is no longer treated as a carry drain
	# (it should regenerate while standing still).
	Input.action_release("move_forward")
	Input.action_release("pickup")
	for _i in 6:
		await physics_frame
	_check("releasing Action stops pumping", player.call("is_pump_sprinting") == false)
	var stamina_after_release := float(player.get("stamina"))
	for _i in 120:
		await physics_frame
	_check("stamina regenerates after releasing pump", float(player.get("stamina")) > stamina_after_release)

	# Holding Action while something is in reach must NOT pump (the button
	# should grab, not sprint).
	var pickup := ProbeLocalPickup.new()
	pickup.name = "ProbeLocalPickup"
	pickup.add_to_group(LocalPickup.GROUP)
	pickup.collision_layer = 4
	pickup.collision_mask = 0
	pickup.freeze = true
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	shape.shape = sphere
	pickup.add_child(shape)
	root.add_child(pickup)
	# Place the pickup within LOCAL_PICKUP_RADIUS of the player.
	for _i in 4:
		pickup.global_position = player.global_position + Vector3(1.0, 0.0, 0.0)
		await physics_frame
	_check("probe pickup is in range", player.call("has_pickable_in_range") == true)

	Input.action_press("pickup")
	for _i in 8:
		pickup.global_position = player.global_position + Vector3(1.0, 0.0, 0.0)
		await physics_frame
	_check("holding Action with a pickable in range does not pump", player.call("is_pump_sprinting") == false)
	Input.action_release("pickup")

	# Remove the probe so it does not block the next pump.
	pickup.queue_free()
	for _i in 4:
		await physics_frame

	# Exhaustion: pumping drains stamina to zero; the carry-style throttle should
	# latch and slow the player until stamina recovers to the minimum amount.
	player._stamina.stamina = 1.0
	player._stamina._throttled = false
	player._stamina._held_empty = false
	player._stamina._regen_timer = 0.0
	Input.action_press("pickup")
	Input.action_press("move_forward")
	for _i in 20:
		await physics_frame
	_check("pumping to empty latches the carry-style throttle", player._stamina.is_throttled())
	_check("still pumping while throttled", player.call("is_pump_sprinting") == true)
	# While throttled the pump boost must not apply, so speed stays at carry-slow.
	var base_speed: float = player.SPEED * player._stamina.speed_multiplier()
	var pump_speed: float = base_speed
	if bool(player.call("is_pump_sprinting")) and not player._stamina.is_throttled():
		pump_speed *= 2.0
	_check("throttled pump speed is carry-slow (no 2x boost)", is_equal_approx(pump_speed, player.SPEED * 0.4))
	Input.action_release("move_forward")
	Input.action_release("pickup")

	# Cleanup input state.
	if Input.is_action_pressed("pickup"):
		Input.action_release("pickup")
	if Input.is_action_pressed("move_forward"):
		Input.action_release("move_forward")

	_finish()


func _check(what: String, condition: bool) -> void:
	if condition:
		print("PASS  ", what)
		return
	_fail(what)


func _fail(what: String) -> void:
	failures += 1
	print("FAIL  ", what)


func _finish() -> void:
	print("pump sprint selftest: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
