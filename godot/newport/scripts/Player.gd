extends CharacterBody3D


# Skin mapping lives in the spawners:
# defaultnad = skin1.tscn
# Hellion = skin2.tscn
# Seraphim = skin3.tscn
# Abbss = skin4.tscn
# buggy = skin5.tscn
# john deo = skin6.tscn
# Aurum = skin7.tscn
# mouch = skin8.tscn











# --- CONSTANTS ---
const GRAVITY: float = 9.8
const JUMP_VELOCITY: float = 4.5
const SPEED: float = 4.5
const DEADZONE: float = 0.12
const PICKUP_REQUEST_COOLDOWN_MS: int = 150
const STEAL_RADIUS: float = 2.5
const POS_SCALE: float = 100.0
const ROT_SCALE: float = 1000.0
const DEFAULT_MAX_JUMP_HEIGHT: float = (JUMP_VELOCITY * JUMP_VELOCITY) / (2.0 * GRAVITY)
const SLIDE_DURATION: float = 0.55
const SLIDE_SPEED_MULTIPLIER: float = 1.5
const ANIM_NAME_TO_ID: Dictionary = {
	"idle": 0,
	"running": 1,
	"runningjump": 2,
	"falling": 3,
	"runningslide": 4
}

# --- INPUT VARIABLES ---
var gamepad_index: int = 0

# --- PICKUP VARIABLES ---
var held_object: RigidBody3D = null
@export var hold_distance: float = 0.25
@export var hold_height: float = 1.5
var last_pickup_request_ms: int = 0

# --- CAMERA & ZOOM SETTINGS ---
@export var camera_distance: float = 2.0
@export var camera_screen_offset: Vector2 = Vector2(0.0,0.25) # x: -1 (left) to 1 (right), y: -1 (bottom) to 1 (top)
@export var camera_smoothness: float = 8.0
@export var min_pitch: float = deg_to_rad(0.0)
@export var max_pitch: float = deg_to_rad(60.0)
@export var min_zoom: float = 1.5
@export var max_zoom: float = 2.5
@export var altitude_zoom_factor: float = 0.0
@export var touch_orbit_sensitivity: float = 0.024
@export var joystick_orbit_sensitivity: float = 0.003
@export var joystick_orbit_clamp: float = 40.0
@export var joystick_orbit_invert_x: bool = false
@export var joystick_orbit_invert_y: bool = false
@export var swipe_down_threshold: float = 20.0
@export var swipe_up_threshold: float = 70.0
@export var swipe_x_tolerance: float = 80.0
@export var swipe_max_duration_ms: int = 450

# --- NODE REFERENCES ---
@onready var camera: Camera3D = get_node("../Camera3D")

# [CHANGED] Replaced RayCast3D with Area3D
@onready var pickup_area: Area3D = $Area3D

@onready var name_label: Label3D = $Label3D
@onready var anim_run: AnimationPlayer = $running
@onready var anim_idle: AnimationPlayer = $idle
@onready var anim_jump: AnimationPlayer = $runningjump
@onready var anim_slide: AnimationPlayer = $runningslide
@onready var anim_fall: AnimationPlayer = $falling
@onready var mesh: Skeleton3D = $Skeleton3D

# --- STATE VARIABLES ---
var root: Node = null
var is_local: bool = false
var velocity_y: float = 0.0
var cam_rot_x: float = deg_to_rad(30)
var cam_rot_y: float = 0.0
var current_animation: String = "idle"
var camera_distance_current: float = 0.0
var camera_distance_bias: float = 0.0
var camera_is_airborne: bool = false
var camera_is_moving: bool = false
@export var max_jump_height: float = DEFAULT_MAX_JUMP_HEIGHT
var _last_world_y: float = 0.0
var _airborne_start_y: float = 0.0
var _was_on_floor: bool = true
var _slide_timer: float = 0.0
var _is_sliding: bool = false
var _slide_direction: Vector3 = Vector3.ZERO

var touch_joystick: Node = null
var network_tick_timer: float = 0.0
var network_heartbeat_timer: float = 0.0
const NETWORK_TICK_ACTIVE: float = 0.066
const NETWORK_TICK_IDLE: float = 0.33
const NETWORK_HEARTBEAT: float = 1.0
var _last_payload_signature: String = ""

var player_id: String = "" :
	set(new_id):
		player_id = new_id
		_refresh_name_label()

var display_name: String = "" :
	set(new_name):
		display_name = new_name.strip_edges()
		_refresh_name_label()

var active_touches: int = 0
var touch_orbit_pending: Vector2 = Vector2.ZERO
var joystick_orbit_pending: Vector2 = Vector2.ZERO
var _touch_slide_start_pos: Vector2 = Vector2.ZERO
var _touch_slide_start_time_ms: int = 0
var _touch_slide_start_cam_rot_x: float = 0.0
var _touch_slide_start_cam_rot_y: float = 0.0
var _slide_requested: bool = false
var _slide_camera_restore_active: bool = false
var _cached_viewport_size: Vector2 = Vector2.ZERO
var _camera_ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _camera_ray_exclude: Array = []
var _cached_shader_player_pos: Vector3 = Vector3.INF
var _cached_chicken_node: RigidBody3D = null

func _ready() -> void:
	camera_distance = clamp(camera_distance, min_zoom, max_zoom)
	camera_distance_current = camera_distance
	cam_rot_x = min_pitch
	cam_rot_y = deg_to_rad(90.0)
	_last_world_y = global_position.y
	_airborne_start_y = global_position.y
	_was_on_floor = is_on_floor()
	_slide_timer = 0.0
	_is_sliding = false
	_cached_viewport_size = get_viewport().get_visible_rect().size
	_play_idle()
	_refresh_name_label()
	_refresh_touch_joystick()
	_connect_joystick_signals()
	_update_global_player_shader_pos(true)

	if not pickup_area:
		print("ERROR: $Area3D node not found! Please add an Area3D with a CollisionShape to the player.")

func _refresh_name_label() -> void:
	if not name_label:
		return
	var resolved_name = display_name
	if resolved_name == "":
		resolved_name = player_id.substr(0, 8)
	name_label.text = resolved_name

func _input(event: InputEvent) -> void:
	if not is_local:
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			active_touches += 1
			_touch_slide_start_pos = event.position
			_touch_slide_start_time_ms = Time.get_ticks_msec()
			_touch_slide_start_cam_rot_x = cam_rot_x
			_touch_slide_start_cam_rot_y = cam_rot_y
		else:
			var swipe_vector: Vector2 = event.position - _touch_slide_start_pos
			var swipe_duration: int = Time.get_ticks_msec() - _touch_slide_start_time_ms
			if swipe_vector.y > swipe_down_threshold and absf(swipe_vector.x) < swipe_x_tolerance and swipe_duration <= swipe_max_duration_ms:
				_slide_requested = true
			active_touches = max(0, active_touches - 1)

	# --- 1. MOUSE CAMERA CONTROLS ---
	# Skip mouse controls if we have an active touch (prevents emulated mouse double-rotation)
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if active_touches > 0 or DisplayServer.is_touchscreen_available():
			return
		cam_rot_y -= event.relative.x * 0.005
		cam_rot_x = clamp(cam_rot_x + event.relative.y * 0.005, min_pitch, max_pitch)

	# Mouse Wheel Zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera_distance_bias = clamp(camera_distance_bias - 0.5, -(max_zoom - min_zoom), (max_zoom - min_zoom))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera_distance_bias = clamp(camera_distance_bias + 0.5, -(max_zoom - min_zoom), (max_zoom - min_zoom))

	# --- 2. PICKUP CONTROLS ---
	if _is_movement_allowed() and event.is_action_pressed("pickup"):
		if _is_local_holding_chicken():
			_drop_object()
		else:
			_try_pickup()

func _physics_process(delta: float) -> void:
	if not is_local:
		return

	var input_dir := Vector2.ZERO
	var movement_allowed := _is_movement_allowed()
	var is_falling_anim_playing := current_animation == "falling" or (anim_fall != null and anim_fall.is_playing())

	if movement_allowed:
		input_dir.y += Input.get_action_strength("move_forward")
		input_dir.y -= Input.get_action_strength("move_back")
		input_dir.x -= Input.get_action_strength("move_left")
		input_dir.x += Input.get_action_strength("move_right")

	var lx := Input.get_joy_axis(gamepad_index, JOY_AXIS_LEFT_X)
	var ly := Input.get_joy_axis(gamepad_index, JOY_AXIS_LEFT_Y)

	if movement_allowed:
		if abs(lx) > DEADZONE: input_dir.x += lx
		if abs(ly) > DEADZONE: input_dir.y -= ly
	input_dir = input_dir.normalized()

	_apply_touch_orbit()

	if not is_on_floor():
		var gravity_scale: float = 0.5 if is_falling_anim_playing else 1.0
		velocity_y -= GRAVITY * gravity_scale * delta
	else:
		velocity_y = 0
		if movement_allowed and (Input.is_action_just_pressed("jump") or Input.is_joy_button_pressed(gamepad_index, JOY_BUTTON_A)):
			velocity_y = JUMP_VELOCITY

	# Movement direction relative to Camera
	var cam_basis = camera.global_transform.basis
	var forward = -cam_basis.z
	var right = cam_basis.x

	forward.y = 0
	right.y = 0
	forward = forward.normalized()
	right = right.normalized()

	var move_direction = forward * input_dir.y + right * input_dir.x

	var slide_requested_now := Input.is_action_just_pressed("slide") or _slide_requested
	if slide_requested_now:
		var slide_from_touch: bool = _slide_requested
		if movement_allowed and is_on_floor() and move_direction.length() > 0.1 and not _is_sliding:
			_slide_requested = false
			_start_slide(move_direction, slide_from_touch)
		else:
			_slide_requested = false

	velocity.x = move_direction.x * SPEED
	velocity.z = move_direction.z * SPEED
	velocity.y = velocity_y
	if _is_sliding:
		_slide_timer = maxf(0.0, _slide_timer - delta)
		var slide_speed := SPEED * SLIDE_SPEED_MULTIPLIER
		velocity.x = _slide_direction.x * slide_speed
		velocity.z = _slide_direction.z * slide_speed
		_apply_slide_camera_restore(delta)
		if _slide_timer <= 0.0 or not is_on_floor():
			_stop_slide()
	move_and_slide()
	camera_is_airborne = not is_on_floor()
	camera_is_moving = Vector2(velocity.x, velocity.z).length() > 0.1

	if move_direction.length() > 0.05:
		var target_yaw := atan2(move_direction.x, move_direction.z)
		mesh.rotation.y = lerp_angle(mesh.rotation.y, target_yaw, delta * 10.0)

	_handle_animations(move_direction)
	_handle_camera_gamepad(delta)
	_update_camera(delta)

	var net_active: bool = (move_direction.length() > 0.05) or _is_local_holding_chicken() or (current_animation == "running")
	if current_animation == "runningjump" or current_animation == "falling" or current_animation == "runningslide":
		net_active = true
	network_tick_timer += delta
	network_heartbeat_timer += delta
	var tick_window := NETWORK_TICK_ACTIVE if net_active else NETWORK_TICK_IDLE
	var force_heartbeat := network_heartbeat_timer >= NETWORK_HEARTBEAT
	if network_tick_timer >= tick_window or force_heartbeat:
		_send_state_to_server(force_heartbeat)
		network_tick_timer = 0.0
		if force_heartbeat:
			network_heartbeat_timer = 0.0

	_update_local_chicken_visual(delta)
	_update_global_player_shader_pos()

# --- PICKUP LOGIC (USING AREA3D) ---
func _try_pickup():
	if not pickup_area:
		return

	var now = Time.get_ticks_msec()
	if now - last_pickup_request_ms < PICKUP_REQUEST_COOLDOWN_MS:
		return
	last_pickup_request_ms = now

	# Try Area3D overlap first (works when chicken is on the ground).
	var bodies = pickup_area.get_overlapping_bodies()
	var best_target: RigidBody3D = null
	var shortest_dist: float = 999.0

	for body in bodies:
		if body is RigidBody3D and body != self and body.is_in_group("pickup_items"):
			var dist = global_position.distance_to(body.global_position)
			if dist < shortest_dist:
				shortest_dist = dist
				best_target = body

	# Fallback: when the chicken is held by someone else, its frozen RigidBody3D
	# may not register in Area3D overlaps.  Do a direct distance check instead.
	if best_target == null:
		var chicken: RigidBody3D = _get_cached_chicken_node()
		if chicken != null and chicken.is_in_group("pickup_items"):
			var dist = global_position.distance_to(chicken.global_position)
			if dist <= STEAL_RADIUS:
				best_target = chicken

	if best_target and root and root.ws and root.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		root.ws.send(MsgPack.pack({
			"type": "pickup_request",
			"item_id": best_target.name
		}))

func _drop_object():
	if not _is_local_holding_chicken():
		return
	if not root or not root.ws:
		return
	if root.ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	var throw_dir = -camera.global_transform.basis.z
	root.ws.send(MsgPack.pack({
		"type": "drop_request",
		"throw_x": throw_dir.x * 5.0,
		"throw_y": max(1.0, throw_dir.y * 5.0),
		"throw_z": throw_dir.z * 5.0
	}))

func _is_local_holding_chicken() -> bool:
	if not root or not root.has_method("is_local_player_holding_chicken"):
		return false
	return root.is_local_player_holding_chicken()

func _update_local_chicken_visual(delta: float) -> void:
	if not is_local or not _is_local_holding_chicken():
		return
	var chicken: RigidBody3D = _get_cached_chicken_node()
	if chicken == null:
		return

	var forward = -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()

	var target_pos = global_position + (forward * hold_distance)
	target_pos.y += hold_height
	chicken.global_position = chicken.global_position.lerp(target_pos, min(1.0, 16.0 * delta))

# --- CAMERA LOGIC ---
func _handle_camera_gamepad(delta: float) -> void:
	var rx := Input.get_joy_axis(gamepad_index, JOY_AXIS_RIGHT_X)
	var ry := Input.get_joy_axis(gamepad_index, JOY_AXIS_RIGHT_Y)

	if abs(rx) > DEADZONE:
		cam_rot_y -= rx * 0.05 * delta * 60
	if abs(ry) > DEADZONE:
		cam_rot_x = clamp(cam_rot_x + ry * 0.05 * delta * 60, min_pitch, max_pitch)

func _update_camera(delta: float) -> void:
	var target_pos: Vector3 = global_transform.origin + Vector3(0, 1.5, 0)
	cam_rot_x = clamp(cam_rot_x, min_pitch, max_pitch)
	var holding_chicken := _is_local_holding_chicken()
	var movement_allowed := _is_movement_allowed()
	var on_bus := _is_on_bus()

	var vehicle_zoom_cap: float = max_zoom
	if on_bus:
		vehicle_zoom_cap = max_zoom * 2.5

	var ground_zoom: float = lerp(min_zoom, vehicle_zoom_cap, 0.5)
	var state_zoom: float = min_zoom
	if anim_fall != null and anim_fall.is_playing():
		state_zoom = min_zoom
	elif camera_is_airborne:
		state_zoom = max_zoom
	elif on_bus and not movement_allowed:
		state_zoom = vehicle_zoom_cap
	elif camera_is_moving:
		state_zoom = ground_zoom
	elif not movement_allowed and root and root.has_method("is_waiting_for_players") and root.is_waiting_for_players():
		state_zoom = max_zoom
	var target_distance: float = min_zoom if (anim_fall != null and anim_fall.is_playing()) else clamp(state_zoom + camera_distance_bias, min_zoom, vehicle_zoom_cap)
	camera_distance_current = lerp(camera_distance_current, target_distance, delta * camera_smoothness)

	var altitude_zoom: float = clamp(global_transform.origin.y * altitude_zoom_factor, 0.0, vehicle_zoom_cap - min_zoom)
	var effective_camera_distance: float = clamp(camera_distance_current + altitude_zoom, min_zoom, vehicle_zoom_cap)

	var cam_offset: Vector3 = Vector3(
		sin(cam_rot_y) * cos(cam_rot_x),
		sin(cam_rot_x),
		cos(cam_rot_y) * cos(cam_rot_x)
	) * effective_camera_distance

	var desired_pos: Vector3 = target_pos + cam_offset

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	_camera_ray_query.from = target_pos
	_camera_ray_query.to = desired_pos
	_camera_ray_exclude.clear()
	_camera_ray_exclude.append(self)
	if holding_chicken:
		var chicken_node: RigidBody3D = _get_cached_chicken_node()
		if chicken_node:
			_camera_ray_exclude.append(chicken_node)
	_camera_ray_query.exclude = _camera_ray_exclude
	var hit: Dictionary = space_state.intersect_ray(_camera_ray_query)

	if hit and hit.has("position"):
		desired_pos = hit.position

	camera.global_position = camera.global_position.lerp(desired_pos, delta * camera_smoothness)
	camera.look_at(target_pos, Vector3.UP)
	var target_fov := 125.0 if holding_chicken else 95.0
	camera.fov = lerp(camera.fov, target_fov, delta * camera_smoothness)
	
	# --- SCREEN OFFSET CALCULATION ---
	# We use the distance to the target to calculate the world-unit equivalent of screen-space -1.0 to 1.0
	var dist_to_target: float = camera.global_position.distance_to(target_pos)
	var v_fov_rad: float = deg_to_rad(camera.fov)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size != _cached_viewport_size:
		_cached_viewport_size = viewport_size
	var aspect: float = viewport_size.x / max(1.0, viewport_size.y)
	
	var half_height: float = dist_to_target * tan(v_fov_rad / 2.0)
	var half_width: float = half_height * aspect
	
	# Godot's h_offset > 0 shifts camera Right (moves world Left). 
	# So for camera_screen_offset.x = 1.0 (player on right), we need negative h_offset.
	camera.h_offset = -camera_screen_offset.x * half_width
	camera.v_offset = -camera_screen_offset.y * half_height

# --- ANIMATION & NETWORK ---
func _quantize_pos(value: float) -> int:
	return int(round(value * POS_SCALE))

func _quantize_rot(value: float) -> int:
	return int(round(value * ROT_SCALE))

func _send_state_to_server(force_send := false) -> void:
	if not root or not root.ws:
		return
	if root.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var qx := _quantize_pos(global_transform.origin.x)
		var qy := _quantize_pos(global_transform.origin.y)
		var qz := _quantize_pos(global_transform.origin.z)
		var qrot := _quantize_rot(mesh.rotation.y)
		var anim_id := int(ANIM_NAME_TO_ID.get(current_animation, 0))

		var payload = {
			"type": "update_state",
			"qx": qx,
			"qy": qy,
			"qz": qz,
			"qrot": qrot,
			"anim_id": anim_id
		}

		var has_chicken := 0
		var cqx := 0
		var cqy := 0
		var cqz := 0
		var cqrot := 0

		# Only holder is allowed to stream chicken pose to server.
		if _is_local_holding_chicken() and root.has_method("build_local_chicken_payload"):
			var chicken_payload = root.build_local_chicken_payload(global_position, -global_transform.basis.z, mesh.rotation.y)
			if chicken_payload != null:
				has_chicken = 1
				cqx = _quantize_pos(float(chicken_payload.get("x", 0.0)))
				cqy = _quantize_pos(float(chicken_payload.get("y", 0.0)))
				cqz = _quantize_pos(float(chicken_payload.get("z", 0.0)))
				cqrot = _quantize_rot(float(chicken_payload.get("rotation_y", 0.0)))
				payload["chicken"] = {
					"qx": cqx,
					"qy": cqy,
					"qz": cqz,
					"qrot": cqrot
				}

		var signature = "%d|%d|%d|%d|%d|%d|%d|%d|%d|%d" % [
			qx, qy, qz, qrot, anim_id,
			has_chicken, cqx, cqy, cqz, cqrot
		]
		if not force_send and signature == _last_payload_signature:
			return
		_last_payload_signature = signature
		root.ws.send(MsgPack.pack(payload))

func _update_global_player_shader_pos(force: bool = false) -> void:
	if not is_local:
		return
	if not force and global_position.distance_squared_to(_cached_shader_player_pos) < 0.0001:
		return
	_cached_shader_player_pos = global_position
	RenderingServer.global_shader_parameter_set("player_pos", global_position)

func set_animation_state(new_state: String):
	if is_local: return
	if new_state == current_animation: return
	current_animation = new_state
	if new_state == "running":
		_play_running()
	elif new_state == "runningslide":
		_play_running_slide()
	elif new_state == "runningjump":
		_play_running_jump()
	elif new_state == "falling":
		_play_falling()
	else:
		_play_idle()

func _handle_animations(move_dir: Vector3) -> void:
	if not is_local: return
	if not _is_movement_allowed():
		current_animation = "idle"
		_play_idle()
		_was_on_floor = is_on_floor()
		_last_world_y = global_position.y
		return

	if _is_sliding:
		current_animation = "runningslide"
		_play_running_slide()
		_last_world_y = global_position.y
		return

	var on_floor_now := is_on_floor()
	var current_y := global_position.y

	if on_floor_now:
		_was_on_floor = true
		_airborne_start_y = current_y
		_last_world_y = current_y
		if move_dir.length() > 0.1:
			current_animation = "running"
			_play_running()
		else:
			current_animation = "idle"
			_play_idle()
		return

	if _was_on_floor:
		_airborne_start_y = current_y
	_was_on_floor = false

	var y_delta := current_y - _last_world_y
	var height_from_takeoff := current_y - _airborne_start_y
	var vertical_distance_from_takeoff: float = absf(height_from_takeoff)
	var is_falling: bool = (
		(velocity_y <= 0.0 and height_from_takeoff < 0.0 and vertical_distance_from_takeoff >= max_jump_height)
		or (y_delta < -0.01 and height_from_takeoff < 0.0 and vertical_distance_from_takeoff >= max_jump_height)
	)

	if is_falling:
		current_animation = "falling"
		_play_falling()
	else:
		current_animation = "runningjump"
		_play_running_jump()

	_last_world_y = current_y

func _is_movement_allowed() -> bool:
	if root and root.has_method("is_match_running"):
		return root.is_match_running()
	return true

func _get_cached_chicken_node() -> RigidBody3D:
	if _cached_chicken_node != null and is_instance_valid(_cached_chicken_node):
		return _cached_chicken_node
	if root and root.has_method("get_chicken_node"):
		var chicken = root.get_chicken_node()
		if chicken is RigidBody3D:
			_cached_chicken_node = chicken
			return _cached_chicken_node
	return null

func _is_on_bus() -> bool:
	var parent_node: Node = get_parent()
	return parent_node != null and parent_node.name == "Bus"

func _play_running() -> void:
	if anim_slide and anim_slide.is_playing():
		anim_slide.stop()
	if anim_jump and anim_jump.is_playing():
		anim_jump.stop()
	if anim_fall and anim_fall.is_playing():
		anim_fall.stop()
	if anim_idle.is_playing():
		anim_idle.stop()
	if not anim_run.is_playing():
		anim_run.play("running")

func _play_idle() -> void:
	if anim_slide and anim_slide.is_playing():
		anim_slide.stop()
	if anim_jump and anim_jump.is_playing():
		anim_jump.stop()
	if anim_fall and anim_fall.is_playing():
		anim_fall.stop()
	if anim_run.is_playing():
		anim_run.stop()
	if not anim_idle.is_playing():
		anim_idle.play("idle")

func _play_running_jump() -> void:
	if anim_idle and anim_idle.is_playing():
		anim_idle.stop()
	if anim_run and anim_run.is_playing():
		anim_run.stop()
	if anim_slide and anim_slide.is_playing():
		anim_slide.stop()
	if anim_fall and anim_fall.is_playing():
		anim_fall.stop()
	if not anim_jump.is_playing() or anim_jump.current_animation != "runningjump":
		anim_jump.play("runningjump")

func _play_falling() -> void:
	if anim_idle and anim_idle.is_playing():
		anim_idle.stop()
	if anim_run and anim_run.is_playing():
		anim_run.stop()
	if anim_jump and anim_jump.is_playing():
		anim_jump.stop()
	if anim_slide and anim_slide.is_playing():
		anim_slide.stop()
	if not anim_fall.is_playing() or anim_fall.current_animation != "falling":
		anim_fall.play("falling")

func _play_running_slide() -> void:
	if anim_idle and anim_idle.is_playing():
		anim_idle.stop()
	if anim_run and anim_run.is_playing():
		anim_run.stop()
	if anim_jump and anim_jump.is_playing():
		anim_jump.stop()
	if anim_fall and anim_fall.is_playing():
		anim_fall.stop()
	if not anim_slide.is_playing() or anim_slide.current_animation != "runningslide":
		anim_slide.play("runningslide")

func _start_slide(move_direction: Vector3, slide_from_touch: bool = false) -> void:
	_is_sliding = true
	_slide_timer = SLIDE_DURATION
	_slide_direction = move_direction.normalized()
	_slide_camera_restore_active = slide_from_touch
	current_animation = "runningslide"
	_play_running_slide()

func _stop_slide() -> void:
	_is_sliding = false
	_slide_timer = 0.0
	_slide_direction = Vector3.ZERO
	_slide_camera_restore_active = false

func _is_touch_on_joystick_area(pos: Vector2, size: Vector2) -> bool:
	# Always use joystick script's own zone config to avoid mismatches.
	if touch_joystick and touch_joystick.has_method("is_joystick_area_screen"):
		return bool(touch_joystick.call("is_joystick_area_screen", pos, size))
	# Fallback: portrait uses bottom-center; landscape uses bottom-left (1/4 x 1/4).
	var is_portrait := size.y > size.x
	var zone_width := size.x * (0.5 if is_portrait else 0.25)
	var zone_height := size.y * (0.25 if is_portrait else 0.25)
	var zone_left := (size.x - zone_width) * 0.5 if is_portrait else 0.0
	var zone_right := zone_left + zone_width
	return pos.x >= zone_left and pos.x <= zone_right and pos.y >= (size.y - zone_height)

func _refresh_touch_joystick() -> void:
	touch_joystick = get_tree().get_first_node_in_group("touch_joystick")

func _connect_joystick_signals() -> void:
	if touch_joystick == null:
		_refresh_touch_joystick()
	if touch_joystick and not touch_joystick.is_connected("camera_dragged", _on_joystick_camera_drag):
		touch_joystick.connect("camera_dragged", _on_joystick_camera_drag)

func _on_joystick_camera_drag(relative: Vector2) -> void:
	if not is_local:
		return
	joystick_orbit_pending += relative

func _apply_touch_orbit() -> void:
	var has_touch_orbit := touch_orbit_pending != Vector2.ZERO
	var has_joystick_orbit := joystick_orbit_pending != Vector2.ZERO
	if not has_touch_orbit and not has_joystick_orbit:
		return

	var touch_delta: Vector2 = touch_orbit_pending
	var joystick_delta: Vector2 = joystick_orbit_pending
	touch_orbit_pending = Vector2.ZERO
	joystick_orbit_pending = Vector2.ZERO

	if has_touch_orbit:
		touch_delta.x = clamp(touch_delta.x, -64.0, 64.0)
		touch_delta.y = clamp(touch_delta.y, -64.0, 64.0)
		cam_rot_y -= touch_delta.x * touch_orbit_sensitivity
		cam_rot_x = clamp(cam_rot_x + touch_delta.y * touch_orbit_sensitivity, min_pitch, max_pitch)

	if has_joystick_orbit:
		joystick_delta.x = clamp(joystick_delta.x, -joystick_orbit_clamp, joystick_orbit_clamp)
		joystick_delta.y = clamp(joystick_delta.y, -joystick_orbit_clamp, joystick_orbit_clamp)
		if joystick_orbit_invert_x:
			joystick_delta.x = -joystick_delta.x
		if joystick_orbit_invert_y:
			joystick_delta.y = -joystick_delta.y
		cam_rot_y -= joystick_delta.x * joystick_orbit_sensitivity
		cam_rot_x = clamp(cam_rot_x + joystick_delta.y * joystick_orbit_sensitivity, min_pitch, max_pitch)

func _apply_slide_camera_restore(delta: float) -> void:
	if not _slide_camera_restore_active:
		return

	var restore_weight: float = clampf(delta * 6.0, 0.0, 1.0)
	cam_rot_y = lerp_angle(cam_rot_y, _touch_slide_start_cam_rot_y, restore_weight)
	cam_rot_x = clampf(lerpf(cam_rot_x, _touch_slide_start_cam_rot_x, restore_weight), min_pitch, max_pitch)
	if absf(angle_difference(cam_rot_y, _touch_slide_start_cam_rot_y)) < 0.001 and absf(cam_rot_x - _touch_slide_start_cam_rot_x) < 0.001:
		_slide_camera_restore_active = false
