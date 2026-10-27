# Checks the resume record PlayerManager uses to make a leave-and-rejoin land on the
# SAME room player. Without it a rejoin opens a second connection under a brand-new
# id: the old player survives as a frozen ghost for the reconnect grace window, the
# room counts two players, and the start countdown fires.
#   Godot_v4.8-beta1_win64_console.exe --headless --path godot --script res://tools/_test_rejoin_resume.gd
extends SceneTree

var failures: int = 0


func _initialize() -> void:
	_clear_record()

	# Nothing is added to the tree: the helpers only touch members and user://.
	var manager := PlayerManager.new()
	manager.local_match_id = "match-alpha"

	_check("a fresh install has nothing to resume", manager._remembered_resume_id() == "")
	_check(
		"and the connect URL carries no resume",
		not manager._build_ws_url_with_username("ws://room").contains("resume=")
	)

	manager._remember_player_id("player-123")
	_check("the record round-trips", manager._remembered_resume_id() == "player-123")
	_check(
		"the same room resumes that player",
		manager._build_ws_url_with_username("ws://room").contains("resume=player-123")
	)

	manager.local_match_id = "match-beta"
	_check("a different room does not resume it", manager._remembered_resume_id() == "")
	_check(
		"and its connect URL stays clean",
		not manager._build_ws_url_with_username("ws://room").contains("resume=")
	)

	# A live id (first connect, or an in-session reconnect) always wins over the file.
	manager.player_id = "live-id"
	_check(
		"a live id beats the record",
		manager._build_ws_url_with_username("ws://room").contains("resume=live-id")
	)
	manager.player_id = ""

	manager.local_match_id = ""
	_check("no match id means the default room", manager._resume_room_key() == "default")
	manager._remember_player_id("player-999")
	_check("the default room resumes too", manager._remembered_resume_id() == "player-999")

	manager._remember_player_id("")
	_check("an empty id never overwrites the record", manager._remembered_resume_id() == "player-999")

	# The room half is compared exactly: a record for "default" must not be handed
	# to "default2" or to a match whose id merely starts the same way.
	manager.local_match_id = "default2"
	_check("a longer room id is not a match", manager._remembered_resume_id() == "")

	_clear_record()
	manager.free()

	print("rejoin resume selftest: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func _clear_record() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove(PlayerManager.RESUME_STORE_PATH.get_file())


func _check(what: String, ok: bool) -> void:
	if ok:
		print("PASS  ", what)
		return
	failures += 1
	print("FAIL  ", what)
