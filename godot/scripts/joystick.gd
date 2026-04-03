extends Sprite2D

signal joystick_moved
signal joystick_released
signal camera_dragged(relative: Vector2)

# --- VISUAL SETTINGS ---
@export var min_opacity: float = 0.2
@export var max_opacity: float = 1.0
@export var sprite_rotation_offset_degrees: float = 0.0
@export var auto_lock_hold_seconds: float = 0.4
@export var auto_lock_forward_min_strength: float = 0.6
@export var auto_lock_north_distance_multiplier: float = 6.0
@export var portrait_zone_width_ratio: float = 0.5
@export var portrait_zone_height_ratio: float = 0.25
@export var landscape_zone_width_ratio: float = 0.25
@export var landscape_zone_height_ratio: float = 0.25
@export var portrait_visual_y_offset: float = 46.5


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
var north_drag_distance_accumulated := 0.0
var lock_candidate_started_at := -1.0
var last_drag_was_north := false

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
			# Do not start joystick from touches meant for UI controls (buttons, panels, etc).
			if _is_touch_over_ui(event.position):
				return
			# While locked: taps may trigger jump, but must NOT unlock.
			# Lock can only be broken by a drag in joystick zone.
			if is_auto_locked and _is_joystick_area(event.position, viewport_size):
				if _is_double_tap(event.position):
					_press_key("jump")
					await get_tree().create_timer(0.2).timeout
					_release_key("jump")
					last_tap_time = Time.get_ticks_msec() / 1000.0
					last_tap_position = event.position
					get_viewport().set_input_as_handled()
					return
				last_tap_time = Time.get_ticks_msec() / 1000.0
				last_tap_position = event.position
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
					lock_candidate_started_at = -1.0
					north_drag_distance_accumulated = 0.0
					last_drag_was_north = false
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
		if is_auto_locked and _is_joystick_area(event.position, viewport_size):
			_unlock_auto_move()
			_start_joystick_touch(event.position, event.index, touch_joystick)
			var local_pos_unlock = event.position - touch_joystick.global_position
			if local_pos_unlock.length() > maxRadius:
				local_pos_unlock = local_pos_unlock.normalized() * maxRadius
			position = local_pos_unlock
			_update_north_drag_progress_from_screen_drag(event.relative)
			emit_signal("joystick_moved", position)
			touch_joystick.visible = true
			_update_input_from_joystick(position)
			_update_visuals()
			get_viewport().set_input_as_handled()
			return

		if event.index == active_joystick_index:
			var local_pos = event.position - touch_joystick.global_position
			if local_pos.length() > maxRadius:
				local_pos = local_pos.normalized() * maxRadius
			position = local_pos
			_update_north_drag_progress_from_screen_drag(event.relative)
			emit_signal("joystick_moved", position)
			touch_joystick.visible = true
			_update_input_from_joystick(position)
			_update_visuals()
			get_viewport().set_input_as_handled()
		elif event.index == active_camera_index:
			emit_signal("camera_dragged", event.relative)

func _process(delta):
	if not is_auto_locked and active_joystick_index != -1 and _is_forward_lock_candidate():
		var now := Time.get_ticks_msec() / 1000.0
		if lock_candidate_started_at < 0.0:
			lock_candidate_started_at = now
		elif (now - lock_candidate_started_at) >= auto_lock_hold_seconds:
			_lock_auto_move()
	else:
		if not is_auto_locked:
			lock_candidate_started_at = -1.0

	if return_to_center and position == Vector2.ZERO:
		_release_all_keys()
		modulate.a = lerp(modulate.a, min_opacity, delta * 10)

func _update_visuals():
	if position.length_squared() > 10.0:
		# Godot angle 0 points right; add 90deg so an up-facing sprite is 0deg at forward/up drag.
		rotation = position.angle() + PI * 0.5 + deg_to_rad(sprite_rotation_offset_degrees)
	else:
		rotation = deg_to_rad(sprite_rotation_offset_degrees)
	if is_auto_locked:
		modulate.a = 0.5
		return
	var strength = clamp(position.length() / maxRadius, 0.0, 1.0)
	modulate.a = lerp(min_opacity, max_opacity, strength)

# --- QUADRANT CHECKS ---
func _is_joystick_area(pos: Vector2, viewport_size: Vector2) -> bool:
	var is_portrait := viewport_size.y > viewport_size.x
	var zone_width_ratio := portrait_zone_width_ratio if is_portrait else 0.25
	var zone_height_ratio := portrait_zone_height_ratio if is_portrait else 0.25

	var zone_width = viewport_size.x * clamp(zone_width_ratio, 0.05, 1.0)
	var zone_height = viewport_size.y * clamp(zone_height_ratio, 0.05, 1.0)
	var zone_left = (viewport_size.x - zone_width) * 0.5 if is_portrait else 0.0
	var zone_right = zone_left + zone_width

	# Portrait: bottom-center zone. Landscape: bottom-left zone.
	return pos.x >= zone_left and pos.x <= zone_right and pos.y >= (viewport_size.y - zone_height)

func _is_camera_area(pos: Vector2, viewport_size: Vector2) -> bool:
	# Everything outside the joystick rectangle zone
	return not _is_joystick_area(pos, viewport_size)

func is_joystick_area_screen(pos: Vector2, viewport_size: Vector2) -> bool:
	return _is_joystick_area(pos, viewport_size)

func _get_joystick_zone_center(viewport_size: Vector2) -> Vector2:
	var is_portrait := viewport_size.y > viewport_size.x
	var zone_width_ratio := portrait_zone_width_ratio if is_portrait else 0.25
	var zone_height_ratio := portrait_zone_height_ratio if is_portrait else 0.25
	var zone_width = viewport_size.x * clamp(zone_width_ratio, 0.05, 1.0)
	var zone_height = viewport_size.y * clamp(zone_height_ratio, 0.05, 1.0)
	var zone_left = (viewport_size.x - zone_width) * 0.5 if is_portrait else 0.0
	var zone_top = viewport_size.y - zone_height
	var center = Vector2(zone_left + zone_width * 0.5, zone_top + zone_height * 0.5)
	center.y -= portrait_visual_y_offset
	return center

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

func _check_double_tap(tap_pos: Vector2, touch_joystick: Node):
	if _is_double_tap(tap_pos):
		_press_key("jump")
		if _is_joystick_actively_moving():
			_lock_auto_move_from_current(touch_joystick)
		await get_tree().create_timer(0.2).timeout
		_release_key("jump")
	var now = Time.get_ticks_msec() / 1000.0
	last_tap_time = now
	last_tap_position = tap_pos

func _is_double_tap(tap_pos: Vector2) -> bool:
	var now = Time.get_ticks_msec() / 1000.0
	return (now - last_tap_time) <= double_tap_interval and (tap_pos - last_tap_position).length() < 80.0

func claims_touch(touch_index: int) -> bool:
	return touch_index == active_joystick_index

func _start_joystick_touch(touch_pos: Vector2, touch_index: int, touch_joystick: Node):
	active_joystick_index = touch_index
	touchInsideJoystick = true
	north_drag_distance_accumulated = 0.0
	lock_candidate_started_at = -1.0
	last_drag_was_north = false
	var zone_center = _get_joystick_zone_center(get_viewport().get_visible_rect().size)
	touch_joystick.position = zone_center
	global_position = zone_center
	touch_joystick.visible = true
	_check_double_tap(touch_pos, touch_joystick)
	_update_visuals()

func _is_forward_lock_candidate() -> bool:
	if maxRadius <= 0.0:
		return false
	var normalized_pos = position / maxRadius
	var required_north_distance: float = float(maxRadius) * max(auto_lock_north_distance_multiplier, 0.0)
	var has_required_north_drag: bool = north_drag_distance_accumulated >= required_north_distance
	return normalized_pos.y <= -auto_lock_forward_min_strength and abs(normalized_pos.y) >= abs(normalized_pos.x) and has_required_north_drag and last_drag_was_north

func _lock_auto_move():
	is_auto_locked = true
	lock_candidate_started_at = -1.0
	active_joystick_index = -1
	touchInsideJoystick = false
	modulate.a = 0.5

func _lock_auto_move_from_current(touch_joystick: Node) -> void:
	# If user double-taps without a drag delta yet, default to forward lock.
	if position.length_squared() < 1.0:
		position = Vector2(0.0, -maxRadius * 0.92)
	_update_input_from_joystick(position)
	_lock_auto_move()
	if touch_joystick != null:
		touch_joystick.visible = true

func _is_joystick_actively_moving() -> bool:
	if maxRadius <= 0.0:
		return false
	var movement_strength: float = float(position.length()) / float(maxRadius)
	return movement_strength >= 0.25

func _unlock_auto_move():
	is_auto_locked = false
	lock_candidate_started_at = -1.0
	north_drag_distance_accumulated = 0.0
	last_drag_was_north = false
	position = Vector2.ZERO
	_release_all_keys()
	modulate.a = 1.0
	_update_visuals()

func _is_touch_on_knob(touch_pos: Vector2) -> bool:
	return touch_pos.distance_to(global_position) <= radiusJoyStick * 1.35

func _update_north_drag_progress_from_screen_drag(drag_relative: Vector2) -> void:
	var delta := drag_relative
	if delta.length_squared() <= 0.0001:
		last_drag_was_north = false
		return
	var north_progress := delta.dot(Vector2.UP)
	if north_progress > 0.0:
		last_drag_was_north = true
		north_drag_distance_accumulated += north_progress
	else:
		last_drag_was_north = false

func _is_touch_over_ui(screen_pos: Vector2) -> bool:
	var buttons_holder: Control = get_node_or_null("../../../Node3/CanvasLayer/buttons_holder")
	if buttons_holder == null:
		return false
	if not buttons_holder.is_visible_in_tree():
		return false
	return buttons_holder.get_global_rect().has_point(screen_pos)
