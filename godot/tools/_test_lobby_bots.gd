# Checks the lobby's test bots. They are supposed to be real remote-player
# avatars (RemotePlayer + skin.tscn visuals, no physics), dressed from the skin
# list the backend returns rather than from the two bundled default aliases, and
# driven with the same animation states a remote player gets from the server.
#   Godot_v4.8-beta1_win64_console.exe --headless --path godot --script res://tools/_test_lobby_bots.gd
extends SceneTree

var failures: int = 0

const BOT_COUNT: int = 6
const VALID_ANIMATIONS: Array[String] = ["idle", "running", "runningjump", "falling", "runningslide", "climb"]


func _initialize() -> void:
	await _test_bots()
	print("lobby bots selftest: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func _test_bots() -> void:
	# Stand in for GET /api/skins: BOT_COUNT skins with distinct ids, none of them
	# a bundled default alias, so the picks have something real to choose from.
	var skins: Array = []
	for i in range(BOT_COUNT):
		skins.append({
			"id": str(900 + i),
			"skinConfig": {
				"palette": { "body": "#%02x1020" % (i * 25 + 10) },
				"attachments": [],
			},
		})
	SkinApplier.seed_from_api(skins)

	# Exports have to be set before the node enters the tree: _ready spawns.
	var lobby_script = load("res://scripts/lobby.gd")
	if lobby_script == null:
		_check("lobby.gd loads", false)
		return
	var lobby = lobby_script.new()
	var spawn := Node3D.new()
	spawn.position = Vector3(0, 1, 0)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	lobby.add_child(spawn)
	lobby.add_child(camera)
	lobby.spawn_point = spawn
	lobby.camera_node = ^"Camera3D"
	lobby.spawn_lobby_stress_agents = true
	lobby.lobby_stress_agent_count = BOT_COUNT
	root.add_child(lobby)
	# _ready (and with it the spawn) lands on the first frame, not inside
	# add_child, so give the tree that frame before looking at the bots.
	await process_frame

	var bots: Array = lobby.npcs
	_check("%d bots spawned" % BOT_COUNT, bots.size() == BOT_COUNT)

	var remote_avatars := true
	var labelled := true
	var collisionless := true
	var real_skins := true
	var worn := {}
	for bot in bots:
		if bot is CharacterBody3D or not bot.has_method("set_animation_state"):
			remote_avatars = false
		if bot.get_node_or_null("Label3D") == null:
			labelled = false
		if not bot.find_children("*", "CollisionShape3D", true).is_empty():
			collisionless = false
		if not bot.find_children("*", "Area3D", true).is_empty():
			collisionless = false
		var skin_name := str(bot.get_meta(SkinApplier.APPLIED_SKIN_META, ""))
		if skin_name == "" or skin_name.begins_with("s-default"):
			real_skins = false
		worn[skin_name] = true

	_check("bots are RemotePlayer avatars, not player bodies", remote_avatars)
	_check("every bot keeps the remote name label", labelled)
	_check("bots carry no collision shapes or areas", collisionless)
	_check("no bot falls back to a bundled default alias", real_skins)
	_check("every bot wears a different skin", worn.size() == BOT_COUNT)

	var first = bots[0]
	_check("bots are named like remotes", str(first.display_name) == "BOT 001")
	_check("bots report a player id", str(first.player_id) == "BOT_001")

	# The lobby stands in for PlayerManager's world-state loop.
	var before: Vector3 = first.global_position
	lobby._drive_lobby_bots(0.5)
	var after: Vector3 = first.global_position
	_check("the lobby moves the bots", before.distance_to(after) > 0.01)
	_check("bots play a real animation state",
		VALID_ANIMATIONS.has(str(first.current_animation)))

	# A bot spawned before the skin list arrived wears an alias; the fetch
	# callback re-dresses exactly those and leaves the others alone.
	first.set_meta(SkinApplier.APPLIED_SKIN_META, "s-default")
	var kept := str(bots[1].get_meta(SkinApplier.APPLIED_SKIN_META, ""))
	lobby._redress_fallback_bots()
	_check("a fallback bot is re-dressed once the skins arrive",
		not str(first.get_meta(SkinApplier.APPLIED_SKIN_META, "")).begins_with("s-default"))
	_check("a bot that already wears a real skin is left alone",
		str(bots[1].get_meta(SkinApplier.APPLIED_SKIN_META, "")) == kept)

	lobby.free()


func _check(what: String, ok: bool) -> void:
	if ok:
		print("PASS  ", what)
		return
	failures += 1
	print("FAIL: " + what)
