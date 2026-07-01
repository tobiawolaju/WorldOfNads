extends HBoxContainer

const RIGHT_MARGIN := 217.5
const BOTTOM_MARGIN := 217.5
const PORTRAIT_RATIO := 1.4

@export var action_button: Button
@export var jump_button: Button
@export var slide_button: Button

var _touch_indices: Dictionary = {}
var _animating_buttons: Dictionary = {}

func _ready() -> void:
	get_viewport().size_changed.connect(_reposition)
	_reposition()

func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch

		if touch.pressed:
			for entry in [
				[action_button, &"pickup"],
				[jump_button, &"jump"],
				[slide_button, &"slide"]
			]:
				var button: Button = entry[0]
				var action_name: StringName = entry[1]

				if button == null:
					continue

				if _touch_indices.get(action_name, -1) == -1 \
				and button.get_global_rect().has_point(touch.position):

					_touch_indices[action_name] = touch.index

					button.button_pressed = true

					_play_press_animation(button)

					_fire_action(action_name, true)

					get_viewport().set_input_as_handled()
					return

		else:
			for action_name in _touch_indices.keys():
				if _touch_indices.get(action_name) == touch.index:
					var button = _get_button(action_name)

					if button != null:
						button.button_pressed = false
						button.scale = Vector2.ONE

					_touch_indices.erase(action_name)

					_fire_action(action_name, false)

					get_viewport().set_input_as_handled()
					return

	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag

		for action_name in _touch_indices.keys():
			if _touch_indices.get(action_name) == drag.index:

				var button = _get_button(action_name)

				if button == null \
				or not button.get_global_rect().has_point(drag.position):

					if button != null:
						button.button_pressed = false
						button.scale = Vector2.ONE

					_touch_indices.erase(action_name)
					_fire_action(action_name, false)

				return

func _play_press_animation(button: Button) -> void:
	if button == null:
		return

	# Prevent retriggering while already animating
	if _animating_buttons.get(button, false):
		return

	_animating_buttons[button] = true

	button.scale = Vector2.ONE

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_property(
		button,
		"scale",
		Vector2(0.8, 0.8),
		0.08
	)

	tween.tween_property(
		button,
		"scale",
		Vector2.ONE,
		0.12
	)

	tween.finished.connect(func():
		_animating_buttons.erase(button)
		button.scale = Vector2.ONE
	)

func _get_button(action_name: StringName) -> Button:
	match action_name:
		&"pickup":
			return action_button
		&"jump":
			return jump_button
		&"slide":
			return slide_button

	return null

func _fire_action(action_name: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = pressed
	Input.parse_input_event(event)

func _process(_delta: float) -> void:
	var local_player = get_tree().get_first_node_in_group("local_player")

	if local_player != null and action_button != null:
		if local_player.has_method("get_pickup_cooldown") \
		and local_player.get_pickup_cooldown() > 0.0:
			action_button.modulate.a = 0.5
		else:
			action_button.modulate.a = 1.0

func _reposition() -> void:
	var viewport_size := get_viewport().get_visible_rect().size

	var is_portrait := viewport_size.y > viewport_size.x * PORTRAIT_RATIO

	visible = not is_portrait

	if is_portrait:
		return

	var target: Control = self
	var parent_control := get_parent() as Control

	if parent_control != null:
		target = parent_control

	target.set_anchors_preset(Control.PRESET_TOP_LEFT)

	target.position = Vector2(
		viewport_size.x - RIGHT_MARGIN,
		viewport_size.y - BOTTOM_MARGIN
	)
