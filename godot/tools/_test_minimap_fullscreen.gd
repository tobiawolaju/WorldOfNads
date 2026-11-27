# Headless selftest for the expanded minimap chrome:
#   * the event feed stays above the fullscreen map,
#   * the action buttons are hidden while the map is open,
#   * any screen press (mouse or touch) closes the map,
#   * closing restores the feed z-order and button visibility.
#   Godot_v4.8-beta1_win64_console.exe --headless --path godot --script res://tools/_test_minimap_fullscreen.gd
extends SceneTree

var failures := 0
var hud: Node = null
var minimap = null
var feed_panel = null
var buttons = null
var chog = null
var button_layer = null

func _initialize() -> void:
	var packed := load("res://scenes/hud.tscn") as PackedScene
	_check("hud scene loads", packed != null)
	if packed == null:
		quit(1)
		return

	hud = packed.instantiate()
	root.add_child(hud)
	await process_frame
	await process_frame

	minimap = hud.get_node_or_null("CanvasLayer/BoxContainer/Node2/Minimap")
	feed_panel = hud.get_node_or_null("CanvasLayer/BoxContainer/Node2/EventFeedPanel")
	buttons = hud.get_node_or_null("Node3/CanvasLayer/buttons_holder")
	chog = hud.get_node_or_null("Node3/CanvasLayer/Chog")
	button_layer = hud.get_node_or_null("Node3/CanvasLayer")

	_check("minimap exists", minimap != null)
	_check("event feed panel exists", feed_panel != null)
	_check("action buttons exist", buttons != null)
	_check("chog button exists", chog != null)
	_check("button layer exists", button_layer != null)
	if minimap == null or feed_panel == null or buttons == null or chog == null or button_layer == null:
		print("minimap fullscreen selftest: setup failed")
		quit(1)
		return

	_check("feed resolves as minimap sibling", minimap._event_feed_panel == feed_panel)
	_check("button layer is hidden-when-expanded", minimap._hide_controls.has(button_layer))
	_check("event feed starts behind the map", feed_panel.z_index < 100)
	_check("action buttons start visible", button_layer.visible)
	var chog_was_visible: bool = chog.visible

	# Tap the minimap: it expands through the normal GUI path.
	minimap._gui_input(_mouse_press())
	_check("tap opens the map", minimap._is_fullscreen)
	_check(
		"event feed draws above the expanded map",
		feed_panel.z_index > minimap.z_index + 20
	)
	_check("action buttons hidden while expanded", not button_layer.visible)
	_check("action buttons off-screen while expanded", not buttons.is_visible_in_tree())
	_check("chog hidden while expanded", not chog.is_visible_in_tree())

	# A press anywhere else closes it and restores the HUD.
	minimap._opened_at_ms = Time.get_ticks_msec() - 1000
	minimap._input(_mouse_press())
	_check("any press closes the map", not minimap._is_fullscreen)
	_check("event feed z-order restored", feed_panel.z_index == 0)
	_check("action buttons restored", button_layer.visible)
	_check("chog visibility restored", chog.visible == chog_was_visible)

	# Touch input takes the same close path.
	minimap._set_fullscreen(true)
	minimap._opened_at_ms = Time.get_ticks_msec() - 1000
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	minimap._input(touch)
	_check("a screen touch closes the map", not minimap._is_fullscreen)

	# The opening gesture cannot immediately close the map again.
	minimap._gui_input(_mouse_press())
	_check("the map can be reopened", minimap._is_fullscreen)
	minimap._input(_mouse_press())
	_check("opening tap does not instantly close the map", minimap._is_fullscreen)

	# Clean up: close it once more.
	minimap._opened_at_ms = Time.get_ticks_msec() - 1000
	minimap._input(_mouse_press())
	_check("map closes again", not minimap._is_fullscreen)

	print("minimap fullscreen selftest: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func _mouse_press() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event


func _check(name: String, condition: bool) -> void:
	if condition:
		print("PASS  ", name)
	else:
		failures += 1
		print("FAIL  ", name)
