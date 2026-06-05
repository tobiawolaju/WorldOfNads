extends VBoxContainer

const RIGHT_MARGIN := 217.5
const BOTTOM_MARGIN := 57.5

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
	if not button.pressed.is_connected(_on_button_pressed.bind(action_name)):
		button.pressed.connect(_on_button_pressed.bind(action_name))

func _on_button_pressed(action_name: StringName) -> void:
	var press_event := InputEventAction.new()
	press_event.action = action_name
	press_event.pressed = true
	Input.parse_input_event(press_event)

	var release_event := InputEventAction.new()
	release_event.action = action_name
	release_event.pressed = false
	Input.parse_input_event(release_event)
