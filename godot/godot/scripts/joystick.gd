extends Sprite2D

signal joystick_moved
signal joystick_released
signal camera_dragged(relative: Vector2)

# --- VISUAL SETTINGS ---
@export var min_opacity: float = 0.0
@export var max_opacity: float = 0.25
@export var sprite_rotation_offset_degrees: float = 0.0
@export var auto_lock_hold_seconds: float = 0.4
@export var auto_lock_forward_min_strength: float = 0.6
@export var auto_lock_north_distance_multiplier: float = 6.0
@export var disable_joystick_lock: bool = false
@export var portrait_zone_width_ratio: float = 0.5
@export var portrait_zone_height_ratio: float = 0.25
@export var landscape_zone_width_ratio: float = 0.25
@export var landscape_zone_height_ratio: float = 0.25
@export var portrait_visual_y_offset: float = 46.5
@export var swipe_jump_threshold: float = 250.0
@export var swipe_jump_horizontal_tolerance: float = 120.0
@export var jump_press_duration: float = 0.2

var radiusJoyStick: float = 0.0
var radiusJoyBase: float = 0.0
var maxRadius: float = 0.0
var lock_target_position: Vector2 = Vector2.ZERO # The shared overlap point
var return_to_center: bool = true
var keys_pressed: Dictionary = {
	"move_forward": false,
	"move_back": false,
	"move_left": false,
	"move_right": false,
	"jump": false
}

var last_tap_time: float = 0.0
var double_tap_interval: float = 0.3
var last_tap_position: Vector2 = Vector2.ZERO
var screen_orientation: String = "portrait"

# --- MULTI-TOUCH TRACKING ---
var active_joystick_index: int = -1
var active_camera_index: int = -1
var touchInsideJoystick: bool = false
var is_auto_locked: bool = false
var north_drag_distance_accumulated: float = 0.0
var lock_candidate_started_at: float = -1.0
var last_drag_was_north: bool = false
var auto_lock_touch_index: int = -1
var active_camera_last_position: Vector2 = Vector2.ZERO
var active_camera_start_position: Vector2 = Vector2.ZERO
var active_camera_swipe_jump_triggered: bool = false
var jump_release_token: int = 0

@onready var touch_joystick_node: Node = get_node_or_null("../../TouchJoyStick")
@onready var joy_base_node: Node = get_node_or_null("../JoyBase")
@export var joy_lock: Sprite2D 

func _ready():
	add_to_group("touch_joystick")
	var viewport_size = get_viewport().get_visible_rect().size
	screen_orientation = "portrait" if viewport_size.y > viewport_size.x else "landscape"

	radiusJoyStick = global_scale.x * texture.get_size().x / 2
	if joy_base_node != null:
		radiusJoyBase = joy_base_node.global_scale.x * joy_base_node.texture.get_size().x / 2
	
	# Consistency: Set max radius and the lock overlap point
	maxRadius = radiusJoyBase + ((radiusJoyStick * 1)-radiusJoyStick)
	lock_target_position = Vector2(0, -((maxRadius * 0.9) * auto_lock_north_distance_multiplier )) # Adjust 0.9 to change how far up it locks
	
	modulate.a = min_opacity
	
	# Initialize Lock Indicator Visuals
	if joy_lock:
		joy_lock.visible = false
		joy_lock.modulate.a = 0.0
		# Set lock to the exact same local position as the knob's snap point
		joy_lock.position = lock_target_position 
	
func _input(event):
	var viewport_size = get_viewport().get_visible_rect().size

	if event is InputEventScreenTouch:
		if event.pressed:
			if is_auto_locked:
				if auto_lock_touch_index == -1 and touch_joystick_node != null and event.position.distance_to(touch_joystick_node.global_position) <= radiusJoyBase * 2.5:
					auto_lock_touch_index = event.index
					if _is_double_tap(event.position):
						_queue_jump_press()
					last_tap_time = Time.get_ticks_msec() / 1000.0
					last_tap_position = event.position
				elif active_camera_index == -1:
					active_camera_index = event.index
					active_camera_last_position = event.position
					active_camera_start_position = event.position
					active_camera_swipe_jump_triggered = false
					emit_signal("camera_dragged", Vector2.ZERO)
				return

			if event.index == active_joystick_index or event.index == active_camera_index:
				return
			
			if active_joystick_index == -1 and _is_joystick_area(event.position, viewport_size):
				_start_joystick_touch(event.position, event.index, touch_joystick_node)
			elif active_camera_index == -1:
				active_camera_index = event.index
				active_camera_last_position = event.position
				emit_signal("camera_dragged", Vector2.ZERO)
		else:
			if event.index == active_joystick_index:
				if return_to_center and not is_auto_locked:
					position = Vector2.ZERO
					_release_all_keys()
					lock_candidate_started_at = -1.0
					north_drag_distance_accumulated = 0.0
					last_drag_was_north = false
				
				emit_signal("joystick_released")
				if not is_auto_locked:
					if touch_joystick_node: touch_joystick_node.visible = false
				touchInsideJoystick = false
				active_joystick_index = -1
				_update_visuals()
			elif event.index == active_camera_index:
				active_camera_index = -1
				active_camera_last_position = Vector2.ZERO
				active_camera_start_position = Vector2.ZERO
				active_camera_swipe_jump_triggered = false
			if event.index == auto_lock_touch_index:
				auto_lock_touch_index = -1

	elif event is InputEventScreenDrag:
		if is_auto_locked and event.index == auto_lock_touch_index:
			_unlock_auto_move()
			_start_joystick_touch(event.position, event.index, touch_joystick_node)
			_process_joystick_drag(event)
			return

		if event.index == active_joystick_index:
			_process_joystick_drag(event)
		elif event.index == active_camera_index:
			_process_camera_drag(event)

func _process_joystick_drag(event):
	var local_pos = event.position - touch_joystick_node.global_position
	if local_pos.length() > maxRadius:
		local_pos = local_pos.normalized() * maxRadius
	position = local_pos
	_update_north_drag_progress_from_screen_drag(event.relative)
	emit_signal("joystick_moved", position)
	touch_joystick_node.visible = true
	_update_input_from_joystick(position)
	_update_visuals()
	get_viewport().set_input_as_handled()

func _process_camera_drag(event):
	get_viewport().set_input_as_handled()
	var camera_delta: Vector2 = event.position - active_camera_last_position
	active_camera_last_position = event.position
	camera_delta.x = clamp(camera_delta.x, -64.0, 64.0)
	camera_delta.y = clamp(camera_delta.y, -64.0, 64.0)
	if camera_delta.length_squared() > 0.0:
		emit_signal("camera_dragged", camera_delta)
	if not active_camera_swipe_jump_triggered and _can_swipe_jump():
		var total_delta :Vector2 = event.position - active_camera_start_position
		if -total_delta.y >= swipe_jump_threshold and abs(total_delta.x) <= swipe_jump_horizontal_tolerance:
			active_camera_swipe_jump_triggered = true
			_queue_jump_press()

func _process(delta):
	if not disable_joystick_lock and not is_auto_locked and active_joystick_index != -1 and _is_forward_lock_candidate():
		var now := Time.get_ticks_msec() / 1000.0
		if lock_candidate_started_at < 0.0:
			lock_candidate_started_at = now
		elif (now - lock_candidate_started_at) >= auto_lock_hold_seconds:
			_lock_auto_move()
	else:
		if not is_auto_locked:
			lock_candidate_started_at = -1.0

	if return_to_center and position == Vector2.ZERO and not is_auto_locked:
		_release_all_keys()
		modulate.a = lerp(modulate.a, min_opacity, delta * 10)
	
	_update_lock_indicator_visuals(delta)

func _update_visuals():
	if position.length_squared() > 10.0:
		rotation = position.angle() + PI * 0.5 + deg_to_rad(sprite_rotation_offset_degrees)
	else:
		rotation = deg_to_rad(sprite_rotation_offset_degrees)
		
	if is_auto_locked:
		modulate.a = 0.5
		return
		
	var strength = clamp(position.length() / maxRadius, 0.0, 1.0)
	modulate.a = lerp(min_opacity, max_opacity, strength)

func _update_lock_indicator_visuals(delta):
	if not joy_lock: return
	
	if is_auto_locked:
		joy_lock.visible = true
		joy_lock.modulate.a = lerp(joy_lock.modulate.a, 1.0, delta * 10)
		var pulse = 1.0 + (sin(Time.get_ticks_msec() * 0.01) * 0.05)
		joy_lock.scale = Vector2.ONE * pulse
		return

	var is_forward = position.y < -maxRadius * 0.4
	var required_north = float(maxRadius) * max(auto_lock_north_distance_multiplier, 0.1)
	var drag_progress = clamp(north_drag_distance_accumulated / required_north, 0.0, 1.0)
	
	if active_joystick_index != -1 and is_forward:
		joy_lock.visible = true
		joy_lock.modulate.a = lerp(joy_lock.modulate.a, clamp(drag_progress, 0.1, 0.6), delta * 5)
		# Slightly scale up as we get closer to locking
		joy_lock.scale = Vector2.ONE * lerp(0.8, 1.0, drag_progress)
	else:
		joy_lock.modulate.a = lerp(joy_lock.modulate.a, 0.0, delta * 10)
		if joy_lock.modulate.a < 0.01:
			joy_lock.visible = false

# --- LOGIC HELPERS ---

func _is_joystick_area(pos: Vector2, viewport_size: Vector2) -> bool:
	if viewport_size.y > viewport_size.x * 1.4: # Portrait
		return pos.y >= viewport_size.y * 0.5
	return pos.x <= viewport_size.x * 0.5 # Landscape

func _update_input_from_joystick(pos: Vector2):
	_release_all_keys()
	var npos = pos / maxRadius
	var deadzone = 0.05
	if npos.x > deadzone: _press_key("move_right", npos.x)
	elif npos.x < -deadzone: _press_key("move_left", -npos.x)
	if npos.y < -deadzone: _press_key("move_forward", -npos.y)
	elif npos.y > deadzone: _press_key("move_back", npos.y)

func _press_key(action: String, strength: float = 1.0):
	Input.action_press(action, strength)
	keys_pressed[action] = true

func _release_key(action: String):
	if keys_pressed[action]:
		Input.action_release(action)
		keys_pressed[action] = false

func _release_all_keys():
	for key in keys_pressed.keys():
		_release_key(key)

func _is_double_tap(tap_pos: Vector2) -> bool:
	var now = Time.get_ticks_msec() / 1000.0
	return (now - last_tap_time) <= double_tap_interval and (tap_pos - last_tap_position).length() < 80.0

func _start_joystick_touch(touch_pos: Vector2, touch_index: int, touch_joystick: Node):
	active_joystick_index = touch_index
	touchInsideJoystick = true
	north_drag_distance_accumulated = 0.0
	lock_candidate_started_at = -1.0
	last_drag_was_north = false
	touch_joystick.position = touch_pos
	global_position = touch_pos
	touch_joystick.visible = true
	
	if _is_double_tap(touch_pos):
		_queue_jump_press()
		if not disable_joystick_lock and _is_joystick_actively_moving():
			_lock_auto_move_from_current(touch_joystick)
			
	last_tap_time = Time.get_ticks_msec() / 1000.0
	last_tap_position = touch_pos
	_update_visuals()

func _is_forward_lock_candidate() -> bool:
	if maxRadius <= 0.0: return false
	var normalized_pos = position / maxRadius
	var required_north = float(maxRadius) * max(auto_lock_north_distance_multiplier, 0.0)
	return normalized_pos.y <= -auto_lock_forward_min_strength and \
		   abs(normalized_pos.y) >= abs(normalized_pos.x) and \
		   north_drag_distance_accumulated >= required_north and last_drag_was_north

func _lock_auto_move():
	is_auto_locked = true
	lock_candidate_started_at = -1.0
	active_joystick_index = -1
	touchInsideJoystick = false
	auto_lock_touch_index = -1
	# SNAP knob exactly to the lock icon position
	position = lock_target_position
	_update_input_from_joystick(position)

func _lock_auto_move_from_current(touch_joystick: Node) -> void:
	_lock_auto_move()
	if touch_joystick: touch_joystick.visible = true

func _is_joystick_actively_moving() -> bool:
	return (position.length() / maxRadius) >= 0.25

func _unlock_auto_move():
	is_auto_locked = false
	lock_candidate_started_at = -1.0
	north_drag_distance_accumulated = 0.0
	last_drag_was_north = false
	auto_lock_touch_index = -1
	position = Vector2.ZERO
	_release_all_keys()
	_update_visuals()

func _can_swipe_jump() -> bool:
	return active_joystick_index != -1 or is_auto_locked

func _queue_jump_press(duration: float = jump_press_duration) -> void:
	jump_release_token += 1
	var token = jump_release_token
	_press_key("jump")
	await get_tree().create_timer(duration).timeout
	if token == jump_release_token:
		_release_key("jump")

func _update_north_drag_progress_from_screen_drag(drag_relative: Vector2) -> void:
	var north_progress = drag_relative.dot(Vector2.UP)
	if north_progress > 0.0:
		last_drag_was_north = true
		north_drag_distance_accumulated += north_progress
	else:
		last_drag_was_north = false
		north_drag_distance_accumulated = max(0.0, north_drag_distance_accumulated + north_progress * 2.0)
