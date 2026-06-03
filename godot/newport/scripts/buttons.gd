extends VBoxContainer

const RIGHT_MARGIN := 237.5
const BOTTOM_MARGIN := 157.5
const JUMP_KEY := KEY_SPACE
const PICKUP_KEY := KEY_P
const SLIDE_KEY := KEY_C

@export var action_button: Button
@export var jump_button: Button
@export var slide_button: Button

var _touch_claims: Dictionary = {}

func _ready() -> void:
	# This node is inside a Container; move the parent holder (if present),
	# otherwise move self.
	get_viewport().size_changed.connect(_reposition)
	_reposition()
	_bind_button(action_button, &"pickup")
	_bind_button(jump_button, &"jump")
	_bind_button(slide_button, &"slide")

func _reposition() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var target: Control = self
	var parent_control := get_parent() as Control
	if parent_control != null:
		target = parent_control

	# Always position on the right side.
	target.set_anchors_preset(Control.PRESET_TOP_LEFT)
	target.position = Vector2(
		viewport_size.x - RIGHT_MARGIN,
		viewport_size.y - BOTTOM_MARGIN
	)

func _bind_button(button: Button, action_name: StringName) -> void:
	if button == null:
		return
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.focus_mode = Control.FOCUS_NONE
	if not button.gui_input.is_connected(_on_button_gui_input.bind(button, action_name)):
		button.gui_input.connect(_on_button_gui_input.bind(button, action_name))

func _on_button_gui_input(event: InputEvent, button: Button, action_name: StringName) -> void:
	if event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed:
			_touch_claims[action_name] = touch_event.index
			_handle_button_press(action_name)
			button.accept_event()
		else:
			if _touch_claims.get(action_name, -1) != touch_event.index:
				return
			_touch_claims.erase(action_name)
			_handle_button_release(action_name)
			button.accept_event()
	elif event is InputEventScreenDrag:
		var drag_event := event as InputEventScreenDrag
		if _touch_claims.get(action_name, -1) != drag_event.index:
			return
		if not button.get_global_rect().has_point(drag_event.position):
			_touch_claims.erase(action_name)
			_handle_button_release(action_name)
			button.accept_event()
			return
		button.accept_event()
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_event.pressed:
			_handle_button_press(action_name)
		else:
			_handle_button_release(action_name)
		button.accept_event()

func _handle_button_press(action_name: StringName) -> void:
	_set_button_visual_state(action_name, true)
	if action_name == &"jump":
		_emit_key(JUMP_KEY, true)
	elif action_name == &"pickup":
		_emit_key(PICKUP_KEY, true)
	elif action_name == &"slide":
		_emit_key(SLIDE_KEY, true)

func _handle_button_release(action_name: StringName) -> void:
	_set_button_visual_state(action_name, false)
	if action_name == &"jump":
		_emit_key(JUMP_KEY, false)
	elif action_name == &"pickup":
		_emit_key(PICKUP_KEY, false)
	elif action_name == &"slide":
		_emit_key(SLIDE_KEY, false)

func _set_button_visual_state(action_name: StringName, pressed: bool) -> void:
	var button: Button = null
	if action_name == &"pickup":
		button = action_button
	elif action_name == &"jump":
		button = jump_button
	elif action_name == &"slide":
		button = slide_button
	if button != null:
		button.set_pressed_no_signal(pressed)

func _emit_key(keycode: Key, pressed: bool) -> void:
	var key_event := InputEventKey.new()
	key_event.keycode = keycode
	key_event.physical_keycode = keycode
	key_event.pressed = pressed
	key_event.echo = false
	Input.parse_input_event(key_event)
