extends Sprite2D

signal joystick_moved
signal joystick_released

var radiusJoyStick
var radiusJoyBase
var maxRadius
var touchInsideJoystick = false
var return_to_center = true
var keys_pressed = {
	"move_forward": false,
	"move_back": false,
	"move_left": false,
	"move_right": false,
	"jump": false
}

var up_direction_time = 0.0
var up_direction_threshold = 2.5

# Double-tap detection
var last_tap_time = 0.0
var double_tap_interval = 0.3  # Seconds between taps
var last_tap_position = Vector2.ZERO

func _ready():
	var viewport_size = get_viewport().get_visible_rect().size
	var center_x = viewport_size.x / 2
	var bottom_y = viewport_size.y - 150

	var touch_joystick = get_node("../../TouchJoyStick")
	touch_joystick.position = Vector2(center_x, bottom_y)
	touch_joystick.scale = Vector2(0.8, 0.8)

	radiusJoyStick = global_scale.x * texture.get_size().x / 2
	radiusJoyBase = get_node("../JoyBase").global_scale.x * $"../JoyBase".texture.get_size().x / 2
	maxRadius = radiusJoyBase - radiusJoyStick


func _input(event):
	if event is InputEventScreenDrag:
		if touchInsideJoystick:
			position += event.relative
			if position.length() > maxRadius:
				position = position.normalized() * maxRadius
			emit_signal("joystick_moved", position)

			# Re-enable return to center once joystick is being used
			if not return_to_center:
				return_to_center = true

			# Simulate movement input actions
			_update_input_from_joystick(position)

	elif event is InputEventScreenTouch:
		if event.pressed:
			touchInsideJoystick = (event.position - global_position).length() <= radiusJoyStick
			_check_double_tap(event.position)
		else:
			if return_to_center:
				position = Vector2.ZERO
				_release_all_keys()
			emit_signal("joystick_released")


func _process(delta):
	# Track time spent moving up
	if position.y < 0:
		up_direction_time += delta
		if up_direction_time >= up_direction_threshold:
			return_to_center = false
	else:
		up_direction_time = 0.0

	if return_to_center and position == Vector2.ZERO:
		_release_all_keys()


func _update_input_from_joystick(pos: Vector2):
	# Reset first
	_release_all_keys()

	if abs(pos.x) > abs(pos.y):
		if pos.x > 0:
			_press_key("move_right")
		else:
			_press_key("move_left")
	else:
		if pos.y < 0:
			_press_key("move_forward")
		else:
			_press_key("move_back")


func _press_key(action: String):
	if !keys_pressed[action]:
		Input.action_press(action)
		keys_pressed[action] = true


func _release_key(action: String):
	if keys_pressed[action]:
		Input.action_release(action)
		keys_pressed[action] = false


func _release_all_keys():
	for key in keys_pressed.keys():
		_release_key(key)


# === DOUBLE TAP DETECTION ===
func _check_double_tap(tap_pos: Vector2):
	var now = Time.get_ticks_msec() / 1000.0
	if (now - last_tap_time) <= double_tap_interval and (tap_pos - last_tap_position).length() < 80.0:
		# Detected a double tap -> jump
		_press_key("jump")
		await get_tree().create_timer(0.2).timeout
		_release_key("jump")
	last_tap_time = now
	last_tap_position = tap_pos
