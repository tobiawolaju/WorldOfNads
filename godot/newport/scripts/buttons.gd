extends VBoxContainer

const RIGHT_MARGIN := 237.5
const BOTTOM_MARGIN := 157.5

@export var action_button: Button
@export var jump_button: Button
@export var slide_button: Button

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
	if not button.pressed.is_connected(_on_button_pressed.bind(action_name)):
		button.pressed.connect(_on_button_pressed.bind(action_name))
	if not button.button_down.is_connected(_on_button_down.bind(action_name)):
		button.button_down.connect(_on_button_down.bind(action_name))
	if not button.button_up.is_connected(_on_button_up.bind(action_name)):
		button.button_up.connect(_on_button_up.bind(action_name))

func _on_button_pressed(action_name: StringName) -> void:
	if DisplayServer.is_touchscreen_available():
		return
	_emit_action(action_name, true)
	_emit_action(action_name, false)

func _on_button_down(action_name: StringName) -> void:
	if not DisplayServer.is_touchscreen_available():
		return
	if action_name == &"pickup":
		_trigger_local_action(action_name)
		return
	_emit_action(action_name, true)
	_trigger_local_action(action_name)

func _on_button_up(action_name: StringName) -> void:
	if not DisplayServer.is_touchscreen_available():
		return
	if action_name == &"pickup":
		return
	_emit_action(action_name, false)

func _emit_action(action_name: StringName, pressed: bool) -> void:
	if pressed:
		Input.action_press(action_name)
	else:
		Input.action_release(action_name)

	var action_event := InputEventAction.new()
	action_event.action = action_name
	action_event.pressed = pressed
	Input.parse_input_event(action_event)

func _trigger_local_action(action_name: StringName) -> void:
	var local_player := get_tree().get_first_node_in_group("local_player")
	if local_player == null:
		return

	if action_name == &"jump" and local_player.has_method("request_jump"):
		local_player.call("request_jump")
	elif action_name == &"slide" and local_player.has_method("request_slide"):
		local_player.call("request_slide")
	elif action_name == &"pickup" and local_player.has_method("request_pickup"):
		local_player.call("request_pickup")
