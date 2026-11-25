# Regression: a lobby bot kill must not crash when the player's `root` is the
# lobby instead of PlayerManager. The lobby has no `connected` property, so the
# old `bool(root.get("connected"))` threw "Nonexistent 'bool' constructor" and
# swallowed the kill line.
#   Godot_v4.8-beta1_win64_console.exe --headless --path godot --script res://tools/_test_lobby_kill.gd
extends SceneTree

var failures: int = 0


class ProbeBridge extends Node:
	var lines: Array = []

	func show_local_event(message: String) -> void:
		lines.append(message)


func _initialize() -> void:
	var packed := load("res://scenes/skin.tscn") as PackedScene
	if packed == null:
		print("FAIL  the player scene loads")
		print("lobby kill selftest: 1 failure(s)")
		quit(1)
		return
	var player = packed.instantiate()
	root.add_child(player)
	await process_frame
	await process_frame

	var bridge := ProbeBridge.new()
	bridge.name = "ProbeEventsBridge"
	bridge.add_to_group("events_bridge")
	root.add_child(bridge)

	# Stand-in for Lobby: a plain node with no `connected` and no
	# `send_client_event`, exactly what lobby.gd assigns to `player.root`.
	var lobby := Node.new()
	lobby.name = "LobbyStandIn"
	root.add_child(lobby)
	await process_frame

	player.root = lobby
	player.display_name = "tester"
	player._register_local_kill("test bot")
	await process_frame

	_check("the lobby kill reaches the feed", bridge.lines.size() == 1)
	if bridge.lines.size() == 1:
		_check("the line names killer and victim", String(bridge.lines[0]) == "tester eliminated test bot")

	print("lobby kill selftest: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func _check(what: String, condition: bool) -> void:
	if condition:
		print("PASS  ", what)
		return
	failures += 1
	print("FAIL  ", what)
