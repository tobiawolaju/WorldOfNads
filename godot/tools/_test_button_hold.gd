# Verifies the HUD touch buttons sink on press, STAY sunk while the finger is
# held, and only spring back on release. Also covers the drag-off release and
# the hold/release signals gameplay can listen to.
#   Godot_v4.8-beta1_win64_console.exe --headless --path godot --script res://tools/_test_button_hold.gd
extends SceneTree

const PRESS_SCALE := 0.8

var failures: int = 0
var _buttons: Node = null
var _action: Button = null
var _held: Array = []
var _released: Array = []


func _initialize() -> void:
	var holder := HBoxContainer.new()
	holder.name = "Buttons"
	holder.set_script(load("res://scripts/ui/buttons.gd"))
	_buttons = holder

	_action = _make_button("Action")
	var jump := _make_button("Jump")
	var slide := _make_button("Slide")
	holder.add_child(_action)
	holder.add_child(jump)
	holder.add_child(slide)

	var chog := _make_button("Chog")
	chog.position = Vector2(600, 600)
	root.add_child(chog)

	holder.action_button = _action
	holder.chog_button = chog
	holder.jump_button = jump
	holder.slide_button = slide
	holder.action_held.connect(func(action_name: StringName) -> void: _held.append(action_name))
	holder.action_released.connect(func(action_name: StringName) -> void: _released.append(action_name))
	root.add_child(holder)
	await process_frame
	await process_frame

	var rect := _action.get_global_rect()
	_check("the action button has a touchable rect", rect.size.x > 0.0 and rect.size.y > 0.0)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		_finish()
		return
	var center := rect.get_center()

	# --- PRESS AND HOLD -----------------------------------------------------
	_touch(0, true, center)
	await create_timer(0.2).timeout
	_check("a press is reported as held", _buttons.is_action_held(&"pickup"))
	_check("a press sinks the button", _approx(_action.scale.x, PRESS_SCALE))
	await create_timer(0.3).timeout
	_check("a held button stays sunk", _approx(_action.scale.x, PRESS_SCALE))
	_check("holding keeps the action down", _buttons.is_action_held(&"pickup"))

	# --- RELEASE ------------------------------------------------------------
	_touch(0, false, center)
	await create_timer(0.3).timeout
	_check("release clears the held state", not _buttons.is_action_held(&"pickup"))
	_check("release springs the button back", _approx(_action.scale.x, 1.0))

	# --- TAP (press and release in the same breath) -------------------------
	_touch(0, true, center)
	_touch(0, false, center)
	await create_timer(0.3).timeout
	_check("a tap leaves no held state", not _buttons.is_action_held(&"pickup"))
	_check("a tap returns the button to full size", _approx(_action.scale.x, 1.0))

	# --- DRAG OFF -----------------------------------------------------------
	_touch(0, true, center)
	await create_timer(0.15).timeout
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = center + Vector2(500.0, 500.0)
	_buttons._input(drag)
	await create_timer(0.3).timeout
	_check("dragging off the button releases it", not _buttons.is_action_held(&"pickup"))
	_check("dragging off springs the button back", _approx(_action.scale.x, 1.0))

	# --- EDGE HOLD ----------------------------------------------------------
	# The button shrinks under the finger while held. The touch target must stay
	# its full size, or a small drag near the edge would silently drop the action.
	var edge_rect := _action.get_global_rect()
	var edge := Vector2(edge_rect.end.x - 4.0, edge_rect.get_center().y)
	_touch(0, true, edge)
	await create_timer(0.2).timeout
	_check("a press near the edge can be held", _buttons.is_action_held(&"pickup"))
	var nudge := InputEventScreenDrag.new()
	nudge.index = 0
	nudge.position = Vector2(edge_rect.end.x - 2.0, edge_rect.get_center().y)
	_buttons._input(nudge)
	await create_timer(0.1).timeout
	_check("a small edge drag keeps the hold", _buttons.is_action_held(&"pickup"))
	_touch(0, false, nudge.position)
	await create_timer(0.3).timeout

	# --- SIGNALS ------------------------------------------------------------
	_check("held/released are reported once per press", _held.size() == 4 and _released.size() == 4)
	if _held.size() > 0:
		_check("the held signal names the action", StringName(_held[0]) == &"pickup")

	_finish()


func _make_button(button_name: String) -> Button:
	var button := Button.new()
	button.name = button_name
	button.custom_minimum_size = Vector2(80, 80)
	return button


func _touch(index: int, pressed: bool, at: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = at
	_buttons._input(event)


func _approx(value: float, expected: float) -> bool:
	return absf(value - expected) <= 0.02


func _check(what: String, condition: bool) -> void:
	if condition:
		print("PASS  ", what)
		return
	failures += 1
	print("FAIL  ", what)


func _finish() -> void:
	print("button hold selftest: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
