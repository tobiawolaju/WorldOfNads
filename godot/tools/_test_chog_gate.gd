# Headless selftest for the Chog Genesis gate.
#   Godot_v4.8-beta1_win64_console.exe --headless --path godot --script res://tools/_test_chog_gate.gd
# Prints FAIL lines for every broken expectation and exits non-zero if any fail.
#
# Covers the deny-by-default state machine, room gating, TTL/account invalidation
# and the input path being a no-op outside a CHOG room. The network call itself
# is covered by backend/chogNft.test.js.
extends SceneTree

var failures := 0

class FakeRoot extends Node:
	var local_match_id: String = ""


func _initialize() -> void:
	_test_state_machine()
	_test_player_room_gate()
	if failures > 0:
		print("FAILED: %d expectation(s)" % failures)
		quit(1)
	else:
		print("OK: all Chog gate expectations passed")
		quit(0)


func _check(label: String, condition: bool) -> void:
	if condition:
		print("ok   - ", label)
	else:
		failures += 1
		print("FAIL - ", label)


func _test_state_machine() -> void:
	var gate := ChogEligibility.new()

	_check("starts UNKNOWN", gate.state() == ChogEligibility.State.UNKNOWN)
	_check("UNKNOWN denies", not gate.can_activate(true, "won:a", 1_000))
	_check("UNKNOWN needs a check", gate.needs_check("won:a", 1_000))
	_check("empty identity needs no check", not gate.needs_check("", 1_000))

	gate.resolve(200, true, "won:a", 1_000)
	_check("ELIGIBLE in a CHOG room allows", gate.can_activate(true, "won:a", 1_000))
	_check("ELIGIBLE outside a CHOG room denies", not gate.can_activate(false, "won:a", 1_000))
	_check("another account denies", not gate.can_activate(true, "won:b", 1_000))
	_check(
		"expired result denies",
		not gate.can_activate(true, "won:a", 1_000 + ChogEligibility.RESULT_TTL_MS + 1)
	)
	_check(
		"expired result needs a check",
		gate.needs_check("won:a", 1_000 + ChogEligibility.RESULT_TTL_MS + 1)
	)

	gate.resolve(200, false, "won:a", 2_000)
	_check("INELIGIBLE denies", not gate.can_activate(true, "won:a", 2_000))
	_check("a fresh INELIGIBLE needs no immediate re-check", not gate.needs_check("won:a", 2_000))

	gate.resolve(503, false, "won:a", 3_000)
	_check("ERROR denies", not gate.can_activate(true, "won:a", 3_000))
	_check(
		"a fresh ERROR is left to the player's retry window",
		not gate.needs_check("won:a", 3_000)
	)

	gate.resolve(200, true, "won:a", 4_000)
	gate.reset()
	_check("reset goes back to UNKNOWN", gate.state() == ChogEligibility.State.UNKNOWN)
	_check("reset denies", not gate.can_activate(true, "won:a", 4_000))

	# A late response for account A while account B is signed in must not
	# authorise A (or B) until B's own check lands.
	gate.resolve(200, true, "won:a", 5_000)
	_check("A is eligible while A is current", gate.can_activate(true, "won:a", 5_000))
	_check("A is not eligible while B is current", not gate.can_activate(true, "won:b", 5_000))


func _test_player_room_gate() -> void:
	var player_script := load("res://tools/_chog_test_player.gd")
	if player_script == null:
		_check("test player script loads", false)
		return
	var player = player_script.new()
	var fake := FakeRoot.new()
	player.set("root", fake)
	player.set("is_local", true)

	var now := Time.get_ticks_msec()
	var gate: ChogEligibility = player.get("_chog_eligibility")

	fake.local_match_id = ""
	_check("default room is not a CHOG room", not bool(player.call("_is_chog_room")))

	fake.local_match_id = ChogEligibility.CHOG_ROOM_ID
	_check("chog world order is a CHOG room", bool(player.call("_is_chog_room")))

	gate.resolve(200, true, "won:test", now)
	_check("ELIGIBLE in a CHOG room allows the input", bool(player.call("_chog_can_activate")))

	fake.local_match_id = ""
	_check(
		"ELIGIBLE outside a CHOG room is rejected",
		not bool(player.call("_chog_can_activate"))
	)

	fake.local_match_id = ChogEligibility.CHOG_ROOM_ID
	player.set("test_identity", "won:other")
	_check(
		"a different authenticated account cannot reuse the result",
		not bool(player.call("_chog_can_activate"))
	)

	player.set("test_identity", "won:test")
	gate.resolve(200, false, "won:test", Time.get_ticks_msec())
	_check("INELIGIBLE is rejected", not bool(player.call("_chog_can_activate")))

	gate.resolve(503, false, "won:test", Time.get_ticks_msec())
	_check("ERROR is rejected", not bool(player.call("_chog_can_activate")))

	gate.reset()
	_check("UNKNOWN is rejected", not bool(player.call("_chog_can_activate")))

	# UNKNOWN + CHOG room: the press must be ignored and leave the reveal off.
	var event := InputEventAction.new()
	event.action = &"chog"
	event.pressed = true
	player.call("_input", event)
	_check("chog input with no verdict is ignored", not bool(player.get("_hidden_extras_revealed")))

	# ELIGIBLE + CHOG room: the existing reveal path runs. A held power-up keeps
	# this branch off the HUD, so the test needs no scene tree.
	gate.resolve(200, true, "won:test", Time.get_ticks_msec())
	player.set("held_power_up_mode", 1) # any non-NONE mode
	player.call("_input", event)
	_check(
		"ELIGIBLE in a CHOG room activates the existing reveal",
		bool(player.get("_hidden_extras_revealed"))
	)
	player.set("held_power_up_mode", 0)
	player.set("_hidden_extras_revealed", false)

	# Non-CHOG room: even a positive cached result must not authorise the input.
	gate.resolve(200, true, "won:test", Time.get_ticks_msec())
	fake.local_match_id = ""
	player.call("_input", event)
	_check("chog input outside a CHOG room is ignored", not bool(player.get("_hidden_extras_revealed")))

	player.free()
	fake.free()
