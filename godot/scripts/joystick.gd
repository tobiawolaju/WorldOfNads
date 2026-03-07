extends Sprite2D

signal joystick_moved
signal joystick_released
signal camera_dragged(relative: Vector2)

# --- VISUAL SETTINGS ---
@export var min_opacity: float = 0.2
@export var max_opacity: float = 1.0
@export var sprite_rotation_offset_degrees: float = 0.0

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

var last_tap_time = 0.0
var double_tap_interval = 0.3
var last_tap_position = Vector2.ZERO
var screen_orientation = "portrait"

func _ready():
	var viewport_size = get_viewport().get_visible_rect().size
	screen_orientation = "portrait" if viewport_size.y > viewport_size.x else "landscape"

	radiusJoyStick = global_scale.x * texture.get_size().x / 2
	radiusJoyBase = get_node("../JoyBase").global_scale.x * $"../JoyBase".texture.get_size().x / 2
	maxRadius = radiusJoyBase - radiusJoyStick
	
	modulate.a = min_opacity

func _input(event):
	var viewport_size = get_viewport().get_visible_rect().size
	var touch_joystick = get_node("../../TouchJoyStick")

	if event is InputEventScreenTouch:
		if event.pressed:
			if _is_joystick_area(event.position, viewport_size):
				touch_joystick.position = event.position
				global_position = event.position
				touchInsideJoystick = true
				touch_joystick.visible = true
				_check_double_tap(event.position)
				_update_visuals()
			elif _is_camera_area(event.position, viewport_size):
				emit_signal("camera_dragged", Vector2.ZERO)
		else:
			if touchInsideJoystick:
				if return_to_center:
					position = Vector2.ZERO
					_release_all_keys()
					_update_visuals()
				emit_signal("joystick_released")
				touch_joystick.visible = false
			touchInsideJoystick = false

	elif event is InputEventScreenDrag:
		if touchInsideJoystick:
			position += event.relative
			if position.length() > maxRadius:
				position = position.normalized() * maxRadius
			
			emit_signal("joystick_moved", position)
			touch_joystick.visible = true
			
			_update_input_from_joystick(position)
			_update_visuals()
		elif _is_camera_area(event.position, viewport_size):
			emit_signal("camera_dragged", event.relative)

func _process(delta):
	if return_to_center and position == Vector2.ZERO:
		_release_all_keys()
		modulate.a = lerp(modulate.a, min_opacity, delta * 10)

func _update_visuals():
	if position.length_squared() > 10.0:
		rotation = position.angle() + deg_to_rad(sprite_rotation_offset_degrees)
	var strength = clamp(position.length() / maxRadius, 0.0, 1.0)
	modulate.a = lerp(min_opacity, max_opacity, strength)

# --- QUADRANT CHECKS ---
func _is_joystick_area(pos: Vector2, viewport_size: Vector2) -> bool:
	# Bottom-left quadrant
	return pos.x <= viewport_size.x / 2 and pos.y >= viewport_size.y / 2

func _is_camera_area(pos: Vector2, viewport_size: Vector2) -> bool:
	# Everything outside bottom-left quadrant
	return not _is_joystick_area(pos, viewport_size)

func _update_input_from_joystick(pos: Vector2):
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

func _check_double_tap(tap_pos: Vector2):
	var now = Time.get_ticks_msec() / 1000.0
	if (now - last_tap_time) <= double_tap_interval and (tap_pos - last_tap_position).length() < 80.0:
		_press_key("jump")
		await get_tree().create_timer(0.2).timeout
		_release_key("jump")
	last_tap_time = now
	last_tap_position = tap_pos
