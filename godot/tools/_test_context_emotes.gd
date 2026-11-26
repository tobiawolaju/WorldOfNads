# Quick selftest for contextual event-feed emotes.
#   Godot_v4.8-beta1_win64_console.exe --headless --path godot --script res://tools/_test_context_emotes.gd
extends SceneTree

var failures := 0
var hud: Node = null


func _initialize() -> void:
	var packed := load("res://scenes/hud.tscn") as PackedScene
	if packed == null:
		_fail("hud scene loads")
		_finish()
		return
	hud = packed.instantiate()
	root.add_child(hud)
	await process_frame
	hud._avatars.configure("")
	hud._entries.clear()
	hud._entry_seq = 0
	hud._recent_auto_emotes.clear()
	hud._render_feed()

	# 1. All 10 curated emotes discovered.
	for key in ["5head", "copium", "gigachad", "hyperclap", "hyperkekw", "monkas", "pepehands", "pepelaugh", "poggers", "sadge"]:
		_check("emote discovered: %s" % key, hud._emotes.has(key))

	# 2. Contextual mappings.
	_check("join gets poggers", _emote_for("alice", "joined the game") == "poggers")
	_check("picked chicken gets poggers", _emote_for("alice", "picked the chicken") == "poggers")
	_check("steal gets pepelaugh/poggers", _emote_for("alice", "stole the chicken from bob") in ["pepelaugh", "poggers"])
	_check("eliminated gets sadge/pepehands", _emote_for("alice", "was eliminated") in ["sadge", "pepehands"])
	_check("won round gets hyperclap/poggers", _emote_for("alice", "won the round") in ["hyperclap", "poggers"])
	_check("dropped chicken gets pepehands/sadge", _emote_for("alice", "dropped the chicken") in ["pepehands", "sadge"])

	# 3. Manual token preserved (no auto append).
	hud._recent_auto_emotes.clear()
	var msg: String = hud._with_contextual_emote("nice one :poggers:", "", "alice", {})
	_check("manual emote not overridden", msg == "nice one :poggers:")

	# 4. System/unknown should not get emotes.
	_check("system gets no emote", hud._with_contextual_emote("Events live", "", "system", {}) == "Events live")
	hud._recent_auto_emotes.clear()
	_check("unknown event gets no emote", hud._with_contextual_emote("moved around", "", "alice", {}) == "moved around")

	# 5. COPIUM only on excuse/denial.
	hud._recent_auto_emotes.clear()
	_check("lag excuse gets copium", _emote_for("alice", "lag killed me") == "copium")
	hud._recent_auto_emotes.clear()
	_check("normal elimination not copium", _emote_for("alice", "was eliminated") != "copium")

	# 6. 5HEAD only for explicit clever play.
	hud._recent_auto_emotes.clear()
	_check("clever escape gets 5head", _emote_for("alice", "executed a clever escape") == "5head")

	# 7. No consecutive repeat when alternatives exist.
	hud._recent_auto_emotes.clear()
	var e1 := _emote_for("alice", "stole the chicken from bob")
	var e2 := _emote_for("bob", "stole the chicken from alice")
	_check("steal emotes vary", e1 != "" and e2 != "" and e1 != e2)

	# 8. Built-in emotes still present.
	for key in ["chicken", "gem", "mon", "loot", "star", "energy"]:
		_check("builtin emote present: %s" % key, hud._emotes.has(key))

	_finish()


func _emote_for(actor: String, message: String, event_type: String = "") -> String:
	var out: String = hud._with_contextual_emote(message, event_type, actor, {})
	# extract :token: at end
	var rx := RegEx.create_from_string(":([A-Za-z0-9_+\\-]+):$")
	var m := rx.search(out)
	return m.get_string(1).to_lower() if m != null else ""


func _check(name: String, condition: bool) -> void:
	if condition:
		print("PASS  ", name)
	else:
		_fail(name)


func _fail(name: String) -> void:
	failures += 1
	print("FAIL  ", name)


func _finish() -> void:
	print("context emotes selftest: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
