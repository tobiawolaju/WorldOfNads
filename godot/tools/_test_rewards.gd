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
	await _test_gameover_mon()
	await _test_dashboard_rewards()
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


# --- 4. The money line on the result screen -----------------------------------

func _test_gameover_mon() -> void:
	set_meta("match_result_won", true)
	set_meta("match_result_victory_type", "buzzer")
	set_meta("match_result_split_info", {})
	var screen := await _spawn_gameover()
	if screen == null:
		return

	var label: Label = screen.mon_earned_label
	_check("result screen has the MON line", label != null)
	if label != null:
		# A room with no escrow must not imply that money is coming.
		screen._apply_mon_line(0.0, 0.0)
		_check("no-pool room says so on the result screen", label.text == "No prize pool in this room")
		_check("the no-money line is visible", label.visible)
		_check("the no-money line is muted", label.get_theme_color("font_color").a < 0.9)

		screen._apply_mon_line(1.23456, 12.0)
		_check("earned MON is shown with 4 decimals", label.text == "+ 1.2346 MON")
		_check("earned MON is gold", label.get_theme_color("font_color").is_equal_approx(screen.MON_COLOR))

		screen._apply_mon_line(0.0, 12.0)
		_check("a funded room with nothing earned says so", label.text == "No MON this round")

		# The real path: read the session values the player manager recorded.
		var values: Vector2 = screen._session_mon()
		_check("no player manager reads as nothing earned", values == Vector2.ZERO)

	screen.queue_free()
	await process_frame

	for key in ["match_result_won", "match_result_victory_type", "match_result_split_info"]:
		if has_meta(key):
			remove_meta(key)


# --- 5. The dashboard's rewards tab -------------------------------------------

func _test_dashboard_rewards() -> void:
	var script: GDScript = load("res://scripts/screens/dshbord.gd")
	_check("dashboard script loads", script != null)
	if script == null:
		return
	var dashboard: Node = script.new()

	var rows: Array[Dictionary] = [
		{
			"id": "settlement-match-42-alice-prize",
			"username": "alice",
			"matchId": "match-42",
			"source": "Acme",
			"category": "earned",
			"kind": "prize",
			"amount": "7.2000 MON",
			"amountMon": 7.2,
			"pending": false,
			"txHash": "0xabc",
			"createdAt": "2026-11-13T10:20:30.000Z",
		},
		{
			"id": "settlement-match-42-alice-lootbox",
			"username": "alice",
			"matchId": "match-42",
			"source": "Acme",
			"category": "lootbox",
			"kind": "lootbox",
			"amount": "1.0500 MON",
			"amountMon": 1.05,
			"pending": true,
			"createdAt": "2026-11-12T08:00:00.000Z",
		},
	]

	# Formatting helpers.
	_check("ISO dates render as a day", dashboard._reward_date("2026-11-13T10:20:30.000Z") == "13 Nov 2026")
	_check("a missing date renders as nothing", dashboard._reward_date("") == "")
	_check("a broken date renders as nothing", dashboard._reward_date("not-a-date") == "")
	_check("legacy rows without a formatted amount still show one", dashboard._reward_amount({"amountMon": 3.5}) == "3.5000 MON")
	_check("a formatted amount is shown as written", dashboard._reward_amount(rows[0]) == "7.2000 MON")
	_check("a stream row is named", dashboard._reward_title({"kind": "stream"}) == "Lootbox stream")
	_check("a lootbox row is named", dashboard._reward_title(rows[1]) == "Lootbox pool")
	_check("a prize row is named", dashboard._reward_title(rows[0]) == "Match prize")
	_check("paid rows say paid", dashboard._reward_meta(rows[0]) == "13 Nov 2026 · match-42 · paid")
	_check("pending rows say pending", dashboard._reward_meta(rows[1]) == "12 Nov 2026 · match-42 · pending")

	# The summary totals what the ledger paid, and calls out what is still owed.
	dashboard._rewards = rows
	var summary: Control = dashboard._build_reward_summary()
	var summary_text := "\n".join(_label_texts(summary))
	_check("the summary totals the rows", summary_text.contains("8.25 MON"))
	_check("the summary counts the rows", summary_text.contains("across 2 rewards"))
	_check("the summary names the pending MON", summary_text.contains("1.05 MON awaiting payout"))

	# A row shows the pot, the amount, the sponsor and its date.
	var card_text := "\n".join(_label_texts(dashboard._build_reward_card(rows[0])))
	_check("the card names the pot", card_text.contains("Match prize"))
	_check("the card shows the amount", card_text.contains("7.2000 MON"))
	_check("the card names the sponsor", card_text.contains("from Acme"))
	_check("the card shows the date and the match", card_text.contains("13 Nov 2026 · match-42"))

	# One reward is not "rewards".
	dashboard._rewards = [rows[0]] as Array[Dictionary]
	var single_text := "\n".join(_label_texts(dashboard._build_reward_summary()))
	_check("a single reward is counted in the singular", single_text.contains("across 1 reward"))
	_check("a paid row shows no pending line", not single_text.contains("awaiting payout"))

	# The renderer swaps the empty card for the rows. It only needs the list and
	# the empty card, so the test builds those instead of mounting the whole
	# dashboard (which would hit the network and build the 3D preview).
	var list := VBoxContainer.new()
	var empty := PanelContainer.new()
	var empty_text := Label.new()
	empty_text.name = "Text"
	empty.add_child(empty_text)
	list.add_child(empty)
	dashboard._reward_list = list
	dashboard._reward_empty = empty
	dashboard._rewards = rows
	dashboard._rewards_error = ""
	dashboard._render_rewards()
	_check("the empty card hides once rows exist", not empty.visible)
	_check("the list holds the summary and one card per reward", list.get_child_count() == 4)

	var none: Array[Dictionary] = []
	dashboard._rewards = none
	dashboard._rewards_error = "Couldn't load rewards. Check your connection."
	dashboard._render_rewards()
	_check("an error drops the rows", list.get_child_count() == 1)
	_check("the error replaces the empty copy", empty_text.text == "Couldn't load rewards. Check your connection.")

	dashboard._rewards_error = ""
	dashboard._render_rewards()
	# Signed out (the headless case) the tab asks for a sign-in; signed in it
	# invites the player to win something. Looked up through the tree because the
	# AuthManager autoload name is not resolvable from this entry script.
	var auth: Node = root.get_node_or_null("/root/AuthManager")
	var signed_in := auth != null and str(auth.call("get_username")).strip_edges() != ""
	var expected_empty := "Sign in to see your rewards." if not signed_in else "No rewards yet. Join a match to win some."
	_check("no rows falls back to the empty copy", empty_text.text == expected_empty)
	_check("the empty card is visible again", empty.visible)

	list.free()
	dashboard.free()



# --- 6. Wire contract: the fields the server sends are the ones read ----------

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

func _label_texts(node: Node) -> PackedStringArray:
	var texts := PackedStringArray()
	if node is Label:
		texts.append((node as Label).text)
	for child in node.get_children():
		texts.append_array(_label_texts(child))
	return texts


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
