extends Sprite2D

signal joystick_moved
signal joystick_released
signal camera_dragged(relative: Vector2)

# --- VISUAL SETTINGS ---
@export var min_opacity: float = 0.2
@export var max_opacity: float = 1.0
@export var sprite_rotation_offset_degrees: float = 0.0
@export var auto_lock_hold_seconds: float = 3.0
@export var auto_lock_forward_min_strength: float = 0.6

var radiusJoyStick
var radiusJoyBase
var maxRadius
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

# --- MULTI-TOUCH TRACKING ---
var active_joystick_index := -1
var active_camera_index := -1
var touchInsideJoystick = false
var is_auto_locked := false
var forward_hold_elapsed := 0.0

func _ready():
	add_to_group("touch_joystick")
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
			if is_auto_locked and _is_touch_on_knob(event.position):
				_unlock_auto_move()
				_start_joystick_touch(event.position, event.index, touch_joystick)
				get_viewport().set_input_as_handled()
				return

			if event.index == active_joystick_index or event.index == active_camera_index:
				return
			# --- Joystick touch ---
			if _is_joystick_area(event.position, viewport_size) and active_joystick_index == -1:
				_start_joystick_touch(event.position, event.index, touch_joystick)
				get_viewport().set_input_as_handled()
			# --- Camera touch ---
			elif _is_camera_area(event.position, viewport_size) and active_camera_index == -1:
				active_camera_index = event.index
				emit_signal("camera_dragged", Vector2.ZERO)
		else:
			if event.index == active_joystick_index:
				if return_to_center and not is_auto_locked:
					position = Vector2.ZERO
					_release_all_keys()
					forward_hold_elapsed = 0.0
					_update_visuals()
				emit_signal("joystick_released")
				if not is_auto_locked:
					touch_joystick.visible = false
				touchInsideJoystick = false
				active_joystick_index = -1
				get_viewport().set_input_as_handled()
			elif event.index == active_camera_index:
				active_camera_index = -1

	elif event is InputEventScreenDrag:
		if event.index == active_joystick_index:
			var local_pos = event.position - touch_joystick.global_position
			if local_pos.length() > maxRadius:
				local_pos = local_pos.normalized() * maxRadius
			position = local_pos
			emit_signal("joystick_moved", position)
			touch_joystick.visible = true
			_update_input_from_joystick(position)
			_update_visuals()
			get_viewport().set_input_as_handled()
		elif event.index == active_camera_index:
			emit_signal("camera_dragged", event.relative)

func _process(delta):
	if not is_auto_locked and active_joystick_index != -1 and _is_forward_lock_candidate():
		forward_hold_elapsed += delta
		if forward_hold_elapsed >= auto_lock_hold_seconds:
			_lock_auto_move()
	else:
		if not is_auto_locked:
			forward_hold_elapsed = 0.0

	if return_to_center and position == Vector2.ZERO:
		_release_all_keys()
		modulate.a = lerp(modulate.a, min_opacity, delta * 10)

func _update_visuals():
	if position.length_squared() > 10.0:
		rotation = position.angle() + deg_to_rad(sprite_rotation_offset_degrees)
	if is_auto_locked:
		modulate.a = 0.5
		return
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

func claims_touch(touch_index: int) -> bool:
	return touch_index == active_joystick_index

func _start_joystick_touch(touch_pos: Vector2, touch_index: int, touch_joystick: Node):
	active_joystick_index = touch_index
	touchInsideJoystick = true
	touch_joystick.position = touch_pos
	global_position = touch_pos
	touch_joystick.visible = true
	_check_double_tap(touch_pos)
	_update_visuals()

func _is_forward_lock_candidate() -> bool:
	if maxRadius <= 0.0:
		return false
	var normalized_pos = position / maxRadius
	return normalized_pos.y <= -auto_lock_forward_min_strength and abs(normalized_pos.y) >= abs(normalized_pos.x)

func _lock_auto_move():
	is_auto_locked = true
	forward_hold_elapsed = 0.0
	active_joystick_index = -1
	touchInsideJoystick = false
	modulate.a = 0.5

func _unlock_auto_move():
	is_auto_locked = false
	forward_hold_elapsed = 0.0
	position = Vector2.ZERO
	_release_all_keys()
	modulate.a = 1.0
	_update_visuals()

func _is_touch_on_knob(touch_pos: Vector2) -> bool:
	return touch_pos.distance_to(global_position) <= radiusJoyStick * 1.35
