# Headless selftest for the stream-chat event feed (Events.gd + AvatarLoader).
#   Godot_v4.8-beta1_win64_console.exe --headless --path godot --script res://tools/_test_event_feed.gd
# Prints FAIL lines for every broken expectation and exits non-zero if any fail.
extends SceneTree

var failures := 0
var hud: Node = null
var feed: VBoxContainer = null

func _initialize() -> void:
	var packed := load("res://scenes/hud.tscn") as PackedScene
	_check("hud scene loads", packed != null)
	if packed == null:
		quit(1)
		return

	hud = packed.instantiate()
	root.add_child(hud)
	await process_frame

	# 1. The scene ships the feed container where Events.gd expects it, and the
	#    old two-label renderer is gone.
	var node := hud.get_node_or_null("CanvasLayer/BoxContainer/Node2/EventFeed")
	_check("EventFeed node exists", node is VBoxContainer)
	_check("old status label removed", hud.get_node_or_null("CanvasLayer/BoxContainer/Node2/BoxContainer3") == null)
	if not (node is VBoxContainer):
		quit(1)
		return
	feed = node as VBoxContainer
	_check("feed ignores the mouse", feed.mouse_filter == Control.MOUSE_FILTER_IGNORE)

	# 2. No avatar traffic during the test: an empty endpoint makes the loader a
	#    pure badge renderer, so the assertions never depend on the network.
	hud._avatars.configure("")
	_check("avatar endpoint can be cleared", hud._avatars.get_avatar("alice") == null)

	# `_ready` already posted a "Connecting events stream..." system row, so start
	# from a known empty feed before asserting on row positions.
	hud._entries.clear()
	hud._entry_seq = 0
	hud._render_feed()

	# 3. Rows are a fixed pool, built once and reused.
	_check("row pool is built", hud._rows.size() == hud.MAX_FEED_ROWS)
	_check("rows start hidden", _visible_rows() == 0)

	# 4. One player event renders avatar + name + message in one row.
	hud._push_event_line("alice", "joined the game")
	_check("one event shows one row", _visible_rows() == 1)
	var row: Dictionary = hud._rows[0]
	_check("row is visible", (row["root"] as Control).visible)
	_check("row shows the badge disc", (row["disc"] as Panel).visible)
	_check("row shows the initial", (row["initial"] as Label).visible)
	_check("badge uses the name initial", (row["initial"] as Label).text == "A")
	_check("row hides the photo until it resolves", not (row["photo"] as TextureRect).visible)
	_check("row text carries the message", _row_text(row).contains("joined the game"))
	_check("row text carries the name", _row_text(row).contains("alice"))
	_check("avatar slot keeps its footprint", (row["slot"] as Control).visible)

	# 5. System notices keep the slot laid out but draw no face, so every row's
	#    text starts on the same x.
	hud._push_event_line("system", "Connecting events stream...")
	_check("system event shows a row", _visible_rows() == 2)
	var system_row: Dictionary = hud._rows[1]
	_check("system row keeps the slot", (system_row["slot"] as Control).visible)
	_check("system row hides the disc", not (system_row["disc"] as Panel).visible)
	_check("system row hides the initial", not (system_row["initial"] as Label).visible)
	_check("system row text is the message", _row_text(system_row).contains("Connecting"))

	# 6. The feed is capped: oldest entries scroll out, newest stay.
	for index in 10:
		hud._push_event_line("p%d" % index, "said hi")
	_check("entries are capped", hud._entries.size() == hud.MAX_FEED_ROWS)
	_check("rows are capped", _visible_rows() == hud.MAX_FEED_ROWS)
	_check("oldest entry was dropped", str(hud._entries[0]["actor"]) == "p5")
	_check("newest entry is last", str(hud._entries[hud._entries.size() - 1]["actor"]) == "p9")
	_check("newest row shows newest text", _row_text(hud._rows[hud.MAX_FEED_ROWS - 1]).contains("p9"))

	# 7. The room server mints `player-xxxxxxxx` for a nameless client; the badge
	#    must not collapse every anonymous player to a lone "P".
	_check("anonymous id badges on the suffix", hud._avatars.initial("player-1a2b3c4d") == "1A")
	_check("ordinary name badges on the first letter", hud._avatars.initial("bob") == "B")
	_check("empty name is handled", hud._avatars.initial("   ") == "?")

	# 8. Name colours are stable per name and spread across the palette, so two
	#    clients render the same player the same way without coordinating.
	_check("colour is deterministic", hud._avatars.name_color("alice") == hud._avatars.name_color("alice"))
	_check("colour is case-insensitive", hud._avatars.name_color("Alice") == hud._avatars.name_color("alice"))
	_check("colour differs between names", hud._avatars.name_color("alice") != hud._avatars.name_color("bob"))

	# 8b. The Twitch property that actually matters: nobody in the session wears
	#     a colour someone else already has, even when their hashes collide.
	var fresh := AvatarLoader.new()
	var distinct: Dictionary = {}
	for index in AvatarLoader.NAME_COLORS.size():
		distinct[fresh.name_color("chatter%d" % index).to_html(true)] = true
	_check(
		"a full palette of players gets distinct colours",
		distinct.size() == AvatarLoader.NAME_COLORS.size()
	)
	fresh.free()

	# 8c. A colour is a session-long identity, not a property of the current row:
	#     meeting someone new must not repaint an existing name.
	var alice_color: Color = hud._avatars.name_color("alice")
	hud._avatars.name_color("someone-brand-new")
	_check("colour survives later arrivals", hud._avatars.name_color("alice") == alice_color)

	# 9. A missing picture never blocks the feed: the row still renders, and the
	#    name is not marked settled until the backend has actually answered.
	_check("an unresolved name is not settled", not hud._avatars.is_settled("alice"))
	_check("row text still renders without a photo", _row_text(hud._rows[0]).length() > 0)

	# 10. Rendering is idempotent — a repaint must not duplicate text or rows.
	var before := _row_text(hud._rows[0])
	hud._render_feed()
	_check("repaint does not duplicate text", _row_text(hud._rows[0]) == before)
	_check("repaint does not add rows", _visible_rows() == hud.MAX_FEED_ROWS)

	# 11. The chicken countdown is a pinned row: it updates in place above the chat
	#     rows and never enters the history, so a 60-second hold cannot flush it.
	hud.update_chicken_countdown("alice", 43)
	_check("countdown creates a row", not hud._countdown_row.is_empty())
	var countdown: Dictionary = hud._countdown_row
	_check("countdown row is visible", (countdown["root"] as Control).visible)
	_check("countdown row sits above the chat", feed.get_child(0) == countdown["root"])
	_check("countdown names the holder", _row_text(countdown).contains("alice"))
	_check("countdown shows the seconds left", _row_text(countdown).contains("wins in 43s"))
	_check("countdown is not part of the history", not hud._rows.has(countdown))
	var feed_children := feed.get_child_count()
	hud.update_chicken_countdown("alice", 42)
	_check("countdown updates in place", hud._countdown_row["root"] == countdown["root"])
	_check("countdown does not add a row", feed.get_child_count() == feed_children)
	_check("countdown shows the new second", _row_text(countdown).contains("wins in 42s"))
	_check("countdown text is not duplicated", not _row_text(countdown).contains("43"))
	hud.update_chicken_countdown("", -1)
	_check("countdown hides when nobody holds it", not (countdown["root"] as Control).visible)
	hud.update_chicken_countdown("bob", 0)
	_check("countdown comes back for a new holder", (countdown["root"] as Control).visible)
	_check("countdown switches holder", _row_text(countdown).contains("bob"))
	_check("countdown at zero reads zero", _row_text(countdown).contains("wins in 0s"))

	print("event feed selftest: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)

func _visible_rows() -> int:
	var count := 0
	for row in hud._rows:
		if (row["root"] as Control).visible:
			count += 1
	return count

func _row_text(row: Dictionary) -> String:
	var label := row["text"] as RichTextLabel
	return label.get_parsed_text() if label != null else ""

func _check(name: String, condition: bool) -> void:
	if condition:
		print("PASS  ", name)
	else:
		failures += 1
		print("FAIL  ", name)
