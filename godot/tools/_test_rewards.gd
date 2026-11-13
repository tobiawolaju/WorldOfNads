# Headless selftest for the reward flow's client half (Events.gd HUD labels,
# the gameover result screen, and the wire fields PlayerManager reads).
#   node --test backend/settlement.test.js                 # server ledger half
#   Godot_v4.7.2-stable_win64_console.exe --headless --path godot --script res://tools/_test_rewards.gd
# Prints FAIL lines for every broken expectation and exits non-zero if any fail.
extends SceneTree

var failures := 0
var _checks := 0


func _initialize() -> void:
	await _test_hud_counters()
	await _test_event_feed_countdown()
	await _test_gameover_split()
	await _test_wire_contract()

	print("")
	if failures == 0:
		print("REWARD TESTS OK (%d checks)" % _checks)
	else:
		print("REWARD TESTS FAILED (%d/%d checks)" % [failures, _checks])
	quit(1 if failures > 0 else 0)


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		failures += 1
		print("FAIL: %s" % label)


# --- 1. HUD counters (the labels reward_update drives) ------------------------

func _test_hud_counters() -> void:
	var hud := await _spawn_hud()
	if hud == null:
		return

	var xp_label: Label = hud.get_node_or_null("XPstream") as Label
	var mon_label: Label = hud.get_node_or_null("MONstream") as Label
	var pool_label: Label = hud.get_node_or_null("PrizePool") as Label
	_check("HUD has the XP counter", xp_label != null)
	_check("HUD has the MON counter", mon_label != null)
	_check("HUD has the prize-pool label", pool_label != null)
	if xp_label == null or mon_label == null or pool_label == null:
		hud.queue_free()
		return

	# XP: plain integer, with a pop only when it actually grows.
	hud.update_xp_display(0)
	_check("0 XP renders", xp_label.text == "+ 0 XP")
	_check("no pop on the first value", hud._xp_pop_tween == null)
	hud.update_xp_display(125)
	_check("125 XP renders", xp_label.text == "+ 125 XP")
	_check("a gain pops the counter", hud._xp_pop_tween != null and hud._xp_pop_tween.is_valid())
	hud.update_xp_display(125)
	_check("a repeated value does not re-render", xp_label.text == "+ 125 XP")

	# MON: three decimals, because the lootbox stream ticks in thousandths.
	hud.update_mon_display(0.0042, 18.0)
	_check("MON stream renders 3 decimals", mon_label.text == "+ 0.004 MON")
	_check("whole MON pool renders without decimals", pool_label.text == "18 MON pool")
	hud.update_mon_display(0.5, 1000.0)
	_check("k-suffixed pool", pool_label.text == "1k MON pool")
	hud.update_mon_display(0.5, 1500.0)
	_check("fractional k-suffixed pool", pool_label.text == "1.5k MON pool")
	hud.update_mon_display(18.4213, 18.4213)
	_check("fractional MON pool keeps cents", pool_label.text == "18.42 MON pool")

	# A room with no match has no escrow: say so instead of streaming fake MON.
	hud.update_mon_display(0.0, 0.0)
	_check("no-pool room hides the MON stream", mon_label.text == "")
	_check("no-pool room says so", pool_label.text == "No prize pool")

	# The possession bar was removed; the call must stay a harmless no-op.
	hud.update_possession_display(30, 60)
	_check("possession display is a no-op", true)

	hud.queue_free()
	await process_frame


# --- 2. Chicken countdown rows in the feed -----------------------------------

func _test_event_feed_countdown() -> void:
	var hud := await _spawn_hud()
	if hud == null:
		return

	hud._entries.clear()
	hud._entry_seq = 0
	hud._render_feed()

	hud.update_chicken_countdown("alice", 42)
	# Two rows: the holder announcement, then the countdown itself.
	_check("holder row is pushed", hud._entries.size() == 2)
	_check("holder row names the holder", _feed_text(hud).contains("alice"))
	_check("countdown row shows the seconds", _feed_text(hud).contains("wins in 42s"))

	var before: int = hud._entries.size()
	hud.update_chicken_countdown("alice", 42)
	_check("an unchanged countdown does not spam the feed", hud._entries.size() == before)

	hud.update_chicken_countdown("alice", 41)
	_check("a ticking countdown pushes a new row", hud._entries.size() == before + 1)

	hud.update_chicken_countdown("bob", 60)
	_check("a new holder announces the handover", _feed_text(hud).contains("is holding the chicken"))

	hud.update_chicken_countdown("", -1)
	_check("clearing the countdown is silent", hud._countdown_holder_name == "")

	hud.queue_free()
	await process_frame


# --- 3. Gameover result screen ------------------------------------------------

func _test_gameover_split() -> void:
	var split := {
		"split": true,
		"holderId": "p1",
		"holderName": "alice",
		"holderTime": 30,
		"holderShare": 0.5,
		"progressId": "p2",
		"progressName": "bob",
		"progressTime": 44,
		"progressShare": 0.5,
	}

	# Split loss: the two halves are described, no winner claimed.
	set_meta("match_result_won", false)
	set_meta("match_result_victory_type", "buzzer")
	set_meta("match_result_split_info", split)
	var screen := await _spawn_gameover()
	if screen != null:
		var details: Label = screen.result_details
		_check("split loss renders a details line", details != null and details.text != "")
		_check("split loss explains the split", details.text == "Reward split between chicken holder and possession leader.")
		screen.queue_free()
		await process_frame

	# Split win: both shares are spelled out with their percentages.
	set_meta("match_result_won", true)
	screen = await _spawn_gameover()
	if screen != null:
		var details: Label = screen.result_details
		_check("split win names the holder", details.text.contains("alice held the chicken (50%)"))
		_check("split win names the progress leader", details.text.contains("bob had most possession (50%)"))
		screen.queue_free()
		await process_frame

	# Instant victory messaging.
	set_meta("match_result_won", true)
	set_meta("match_result_victory_type", "instant")
	set_meta("match_result_split_info", {})
	screen = await _spawn_gameover()
	if screen != null:
		_check("instant victory title", screen.result_title.text == "VICTORY!")
		_check("instant victory subtitle", screen.result_subtitle.text == "60s Possession Reached")
		screen.queue_free()
		await process_frame

	for key in ["match_result_won", "match_result_victory_type", "match_result_split_info"]:
		if has_meta(key):
			remove_meta(key)


# --- 4. Wire contract: the fields the server sends are the ones read ----------

func _test_wire_contract() -> void:
	var pm := _read("res://scripts/player/PlayerManager.gd")
	_check("PlayerManager handles reward_update", pm.contains("\"reward_update\""))
	_check("PlayerManager reads xp", pm.contains("data.get(\"xp\""))
	_check("PlayerManager reads mon", pm.contains("data.get(\"mon\""))
	_check("PlayerManager reads pool", pm.contains("data.get(\"pool\""))
	_check("PlayerManager reads possessionTime", pm.contains("data.get(\"possessionTime\""))
	_check("PlayerManager reads victoryTarget", pm.contains("data.get(\"victoryTarget\""))
	_check("PlayerManager feeds the XP counter", pm.contains("update_xp_display"))
	_check("PlayerManager feeds the MON counter", pm.contains("update_mon_display"))

	var events := _read("res://scripts/Events.gd")
	_check("Events exposes update_xp_display", events.contains("func update_xp_display"))
	_check("Events exposes update_mon_display", events.contains("func update_mon_display"))
	_check("Events exposes the countdown rows", events.contains("func update_chicken_countdown"))
	_check("Events navigates on match_winner", events.contains("\"match_winner\""))


# --- helpers -----------------------------------------------------------------

func _spawn_hud() -> Node:
	var packed := load("res://scenes/hud.tscn") as PackedScene
	_check("hud scene loads", packed != null)
	if packed == null:
		return null
	var hud := packed.instantiate()
	root.add_child(hud)
	await process_frame
	# Keep the avatar loader off the network so the test never depends on HTTP.
	hud._avatars.configure("")
	return hud


func _spawn_gameover() -> Node:
	var packed := load("res://scenes/gameover.tscn") as PackedScene
	_check("gameover scene loads", packed != null)
	if packed == null:
		return null
	var screen := packed.instantiate()
	root.add_child(screen)
	await process_frame
	return screen


func _feed_text(hud: Node) -> String:
	var text := ""
	for entry in hud._entries:
		if entry is Dictionary:
			text += "%s %s\n" % [str(entry.get("actor", "")), str(entry.get("message", ""))]
	return text


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_check("can read %s" % path, false)
		return ""
	var text := file.get_as_text()
	file.close()
	return text
