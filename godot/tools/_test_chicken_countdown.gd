# Checks the chicken-hold countdown: the mapping PlayerManager feeds the HUD with,
# and the Label3D that rides the carried chicken. Both have to work for OTHER
# players' holds, not just the local one.
#   Godot_v4.8-beta1_win64_console.exe --headless --path godot --script res://tools/_test_chicken_countdown.gd
extends SceneTree

var failures: int = 0


## Stand-in for PlayerManager. The pickup reads these three properties off the node
## in the "player_manager" group, so the test never opens a socket.
class FakeManager extends Node:
	var chicken_holder_id: String = ""
	var player_possession_time: Dictionary = {}
	var victory_target_seconds: int = 60


func _initialize() -> void:
	_test_state_mapping()
	await _test_chicken_label()

	print("chicken countdown selftest: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func _test_state_mapping() -> void:
	# Nothing is added to the tree: chicken_countdown_state() only reads members.
	var manager := PlayerManager.new()
	manager.player_display_names = {"player-1": "alice"}
	manager.victory_target_seconds = 60

	_check("nobody holding means hide", int(manager.chicken_countdown_state()["seconds"]) == -1)

	manager.chicken_is_held = true
	manager.chicken_holder_id = "player-1"
	manager.player_possession_time = {"player-1": 0}
	var state := manager.chicken_countdown_state()
	_check("a fresh hold starts at the full target", int(state["seconds"]) == 60)
	_check("the row names the holder", str(state["name"]) == "alice")

	manager.player_possession_time = {"player-1": 17}
	_check("possession counts the target down", int(manager.chicken_countdown_state()["seconds"]) == 43)

	manager.player_possession_time = {"player-1": 59}
	_check("59 seconds of possession leaves one", int(manager.chicken_countdown_state()["seconds"]) == 1)

	manager.player_possession_time = {"player-1": 75}
	_check("past the target clamps at zero", int(manager.chicken_countdown_state()["seconds"]) == 0)

	# A holder the snapshot has not named yet: id prefix, not a blank row.
	manager.player_display_names = {}
	manager.chicken_holder_id = "player-2"
	manager.player_possession_time = {"player-2": 5}
	_check("an unnamed holder falls back to the id prefix", str(manager.chicken_countdown_state()["name"]) == "player-2")

	# The target is server-driven, not hard-coded at 60.
	manager.victory_target_seconds = 30
	manager.chicken_holder_id = "player-1"
	manager.player_display_names = {"player-1": "alice"}
	manager.player_possession_time = {"player-1": 5}
	_check("the target comes from the server", int(manager.chicken_countdown_state()["seconds"]) == 25)

	# Holding is what gates the countdown: a dropped chicken has no holder, even if
	# the last id is still lying around.
	manager.chicken_is_held = false
	_check("a dropped chicken hides the row", int(manager.chicken_countdown_state()["seconds"]) == -1)
	manager.free()


func _test_chicken_label() -> void:
	var packed := load("res://scenes/pickup.tscn") as PackedScene
	_check("pickup scene loads", packed != null)
	if packed == null:
		return

	var manager := FakeManager.new()
	manager.name = "FakePlayerManager"
	manager.add_to_group("player_manager")
	root.add_child(manager)

	var chicken := packed.instantiate()
	# 5 = LocalPickup.PowerUpMode.CHICKEN. Spelled out because naming the global
	# class here makes the test script's own compile pull LocalPickup.gd in before
	# the GameManager autoload exists, which fails under --script.
	chicken.power_up_mode = 5
	root.add_child(chicken)
	await process_frame

	var label := chicken.get_node_or_null("chick/Label3D") as Label3D
	_check("the chicken ships a Label3D", label != null)
	if label == null:
		manager.free()
		chicken.free()
		return
	_check("the label starts hidden", not label.visible)

	chicken.set_remote_held(true)
	manager.chicken_holder_id = "player-1"
	manager.player_possession_time = {"player-1": 17}
	await process_frame
	_check("a carried chicken shows the countdown", label.visible)
	_check("the label counts down", label.text == "43s")

	manager.player_possession_time = {"player-1": 18}
	await process_frame
	_check("the label follows possession", label.text == "42s")

	chicken.set_remote_held(false)
	await process_frame
	_check("a dropped chicken hides the label", not label.visible)

	manager.free()
	chicken.free()


func _check(what: String, ok: bool) -> void:
	if ok:
		print("PASS  ", what)
		return
	failures += 1
	print("FAIL  ", what)
