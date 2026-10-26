# Checks player.has_pickable_in_range(), which the HUD Action button uses to choose
# between PUMP and GRAB. Runs against the real player scene so the grab area's layer
# mask and the local-pickup radius are the ones the game actually uses.
#   Godot_v4.8-beta1_win64_console.exe --headless --path godot --script res://tools/_test_pickup_range.gd
extends SceneTree

var failures: int = 0


## A local power-up pickup: player.gd only considers group members that say yes.
class ProbeLocalPickup extends RigidBody3D:
	func can_pick_up() -> bool:
		return true


func _initialize() -> void:
	var packed := load("res://scenes/skin.tscn") as PackedScene
	if packed == null:
		print("FAIL  the player scene loads")
		print("pickup range selftest: 1 failure(s)")
		quit(1)
		return
	var player := packed.instantiate()
	root.add_child(player)
	for _i in 5:
		await process_frame
	await physics_frame

	_check("the player exposes has_pickable_in_range()", player.has_method("has_pickable_in_range"))
	_check("nothing in reach reports nothing", player.call("has_pickable_in_range") == false)

	# Server-side items are found through the grab area, which only sees layer 2.
	var server_item := RigidBody3D.new()
	server_item.name = "ProbeServerPickup"
	server_item.add_to_group("pickup_items")
	server_item.collision_layer = 2
	server_item.freeze = true
	var server_shape := CollisionShape3D.new()
	server_shape.shape = SphereShape3D.new()
	server_item.add_child(server_shape)
	root.add_child(server_item)
	server_item.global_position = player.global_position + Vector3(0.4, 0.0, 0.0)
	await _physics_frames(8)
	_check("a server pickup underfoot is in reach", player.call("has_pickable_in_range") == true)

	server_item.global_position = player.global_position + Vector3(8.0, 0.0, 0.0)
	await _physics_frames(8)
	_check("a server pickup far away is not in reach", player.call("has_pickable_in_range") == false)

	# Local power-up pickups are found by group and distance, not by the area.
	var local_item := ProbeLocalPickup.new()
	local_item.name = "ProbeLocalPickup"
	local_item.add_to_group("local_pickup_items")
	local_item.freeze = true
	root.add_child(local_item)
	local_item.global_position = player.global_position + Vector3(1.0, 0.0, 0.0)
	await _physics_frames(4)
	_check("a local power-up nearby is in reach", player.call("has_pickable_in_range") == true)

	local_item.global_position = player.global_position + Vector3(9.0, 0.0, 0.0)
	await _physics_frames(4)
	_check("a local power-up out of range is not in reach", player.call("has_pickable_in_range") == false)

	print("pickup range selftest: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func _physics_frames(count: int) -> void:
	for _i in count:
		await physics_frame


func _check(what: String, ok: bool) -> void:
	if ok:
		print("PASS  ", what)
		return
	failures += 1
	print("FAIL  ", what)
