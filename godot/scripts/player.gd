extends CharacterBody3D


# -- CONSTANTS ---
const GRAVITY: float = 19.6 
const JUMP_VELOCITY: float = 9
const SPEED: float = 3.0
const DEADZONE: float = 0.12
const PICKUP_REQUEST_COOLDOWN_MS: int = 150
const STEAL_RADIUS: float = 2.5
const POS_SCALE: float = 100.0
const ROT_SCALE: float = 1000.0
const DEFAULT_MAX_JUMP_HEIGHT: float = (JUMP_VELOCITY * JUMP_VELOCITY) / (2.0 * GRAVITY)
const SLIDE_DURATION: float = 0.8
const SLIDE_SPEED_MULTIPLIER: float = 1.7
const JUMP_BUFFER_TIME: float = 0.12
const COYOTE_TIME: float = 0.10
const DOUBLE_JUMP_MIN_MULTIPLIER: float = 0.3

# --- MOMENTUM CONSTANTS ---
const ACCELERATION: float = 25.0  # How fast you reach max speed (Ground)
const FRICTION: float = 22.0      # How fast you stop (Ground)
const AIR_RESISTANCE: float = 6.0 # (Now bypassed for instant air movement)

# --- SQUASH & STRETCH ---
const SQUASH_SCALE: float = 0.5
const STRETCH_SCALE: float = 1.5
const SQUASH_STRETCH_SPEED: float = 12.0

const AUTO_ORBIT_SPEED: float = 2.5

const AUTO_ORBIT_DEADZONE: float = 0.25
const AUTO_ORBIT_THRESHOLD_RAD: float = 0.43633  # deg_to_rad(25.0)
const AUTO_ORBIT_SHARPNESS_RAD: float = 1.57080  # deg_to_rad(90.0)

const STAMINA_MAX: float = 100.0
const STAMINA_DRAIN_RATE: float = STAMINA_MAX / 7.0
const STAMINA_REGEN_DELAY: float = 1.0
const STAMINA_REGEN_RATE: float = STAMINA_MAX / 8.0
const STAMINA_HELD_PENALTY: float = 5.0

const LANDING_BOB_DURATION: float = 0.14
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
@export var camera_smoothness: float = 18.0
@export var min_pitch: float = deg_to_rad(0.0)
@export var max_pitch: float = deg_to_rad(60.0)
@export var min_zoom: float = 1.8
@export var max_zoom: float = 2.2
@export var altitude_zoom_factor: float = 0.0
@export var bus_zoom: float = 3.0
@export var fov: float = 55.0
@export var touch_orbit_sensitivity: float = 0.032
@export var joystick_orbit_sensitivity: float = 0.003
@export var joystick_orbit_clamp: float = 40.0
@export var joystick_orbit_invert_x: bool = false
@export var joystick_orbit_invert_y: bool = false
@export var swipe_down_threshold: float = 20.0
@export var swipe_up_threshold: float = 70.0
@export var swipe_x_tolerance: float = 80.0
@export var swipe_max_duration_ms: int = 450

# --- DEMO AGENT SETTINGS ---
@export var demo_agent: bool = false
@export var demo_move_speed: float = 3.2
@export var demo_orbit_radius: float = 3.5
@export var demo_orbit_speed: float = 1.1
@export var demo_jump_min_interval: float = 1.5
@export var demo_jump_max_interval: float = 4.5
@export var demo_wobble_amount: float = 0.6

# --- NODE REFERENCES ---
@onready var camera: Camera3D = _resolve_camera_node()

# [CHANGED] Replaced RayCast3D with Area3D
@onready var pickup_area: Area3D = $Area3D

@onready var name_label: Label3D = $Label3D
@onready var anim_player: AnimationPlayer = $animator
@onready var anim_tree: AnimationTree = $AnimationTree
@onready var mesh: Skeleton3D = $Skeleton3D

# --- STATE VARIABLES ---
var root: Node = null
var is_local: bool = false
var velocity_y: float = 0.0
var cam_rot_x: float = deg_to_rad(30)
var cam_rot_y: float = 0.0
var current_animation: String = "idle"
var anim_state_machine: AnimationNodeStateMachinePlayback = null
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
var _air_horizontal_velocity: Vector3 = Vector3.ZERO
var _jump_requested: bool = false
var _last_recovery_ms: int = 0
var _jump_buffer_timer: float = 0.0
var _coyote_timer: float = 0.0
var _double_jump_available: bool = false
var _double_jump_used: bool = false
var _double_jump_air_time: float = 0.0
var stamina: float = STAMINA_MAX
var _stamina_regen_timer: float = 0.0
var _stamina_held_empty: bool = false
var _stamina_empty_timer: float = 0.0
var _prev_joy_a_pressed: bool = false
var _ground_jump_count: int = 0

# Performance optimization variables
var _camera_update_skip_frames: int = 0
var _camera_ray_exclude: Array[RID] = []
var _sin_cam_y: float = 0.0
var _cos_cam_y: float = 0.0
var _sin_cam_x: float = 0.0
var _cos_cam_x: float = 0.0
var _cached_viewport_size: Vector2 = Vector2.ZERO
var _slow_update_timer: float = 0.0
const SLOW_UPDATE_INTERVAL: float = 0.1 # 10 FPS for non-critical updates
var _landing_bob_timer: float = 0.0
var _landing_bob_strength: float = 0.0
var _spawn_flash_done: bool = false
var _squash_stretch_y: float = 1.0
var _squash_stretch_velocity: float = 0.0
var _squash_stretch_target: float = 1.0
var _was_airborne: bool = false
var _jump_peak_reached: bool = false
var _base_scale: Vector3
var _camera_distance_velocity: float = 0.0
var _camera_position_velocity: Vector3 = Vector3.ZERO
var _camera_fov_velocity: float = 0.0
var _mesh_yaw_velocity: float = 0.0
var _camera_collision_distance: float = 0.0
var _camera_collision_hold_timer: float = 0.0
var _camera_base_target_prev: Vector3 = Vector3.ZERO
var _camera_base_target_curr: Vector3 = Vector3.ZERO
var _camera_follow_target: Vector3 = Vector3.ZERO
var _camera_follow_velocity: Vector3 = Vector3.ZERO
var _camera_look_target: Vector3 = Vector3.ZERO
var _camera_look_target_velocity: Vector3 = Vector3.ZERO
var _demo_home_center: Vector3 = Vector3.ZERO
var _demo_orbit_angle: float = 0.0
var _demo_orbit_direction: float = 1.0
var _demo_jump_timer: float = 0.0
var _demo_wobble_phase: float = 0.0
var _demo_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _demo_last_safe_position: Vector3 = Vector3.ZERO
var _demo_offground_timer: float = 0.0

const DEMO_RECOVERY_FALL_DISTANCE: float = 8.0
const DEMO_RECOVERY_OFFGROUND_TIME: float = 1.25
const DEMO_RECOVERY_RAISE_OFFSET: float = 1.0

const CAMERA_COLLISION_MARGIN: float = 0.18
const CAMERA_COLLISION_HOLD_TIME: float = 0.08
const CAMERA_COLLISION_RECOVERY_SPEED: float = 10.0
const SPRING_SETTLE_EPSILON: float = 0.0005
const SPRING_SETTLE_VELOCITY_EPSILON: float = 0.0005

var touch_joystick: Node = null
var network_tick_timer: float = 0.0
var network_heartbeat_timer: float = 0.0
const NETWORK_TICK_ACTIVE: float = 0.066
const NETWORK_TICK_IDLE: float = 0.33
const NETWORK_HEARTBEAT: float = 1.0
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
var _camera_ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _camera_ray_layer_set: bool = false
var _cached_shader_player_pos: Vector3 = Vector3.INF
var _cached_chicken_node: RigidBody3D = null
var _cached_lootbox_node: RigidBody3D = null
var _bus_node: Node3D = null
var _bus_last_pos: Vector3 = Vector3.ZERO
var _is_riding_bus: bool = false

func _resolve_camera_node() -> Camera3D:
	var parent_node: Node = get_parent()
	while parent_node != null:
		var direct_camera := parent_node.get_node_or_null("PlayerManager/Camera3D")
		if direct_camera is Camera3D:
			return direct_camera
		direct_camera = parent_node.get_node_or_null("Camera3D")
		if direct_camera is Camera3D:
			return direct_camera
		parent_node = parent_node.get_parent()

	var scene_root := get_tree().root if get_tree() != null else null
	if scene_root != null:
		var cameras := scene_root.find_children("*", "Camera3D", true, false)
		for candidate in cameras:
			if candidate is Camera3D:
				return candidate
	return null

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
	_setup_anim_tree()
	_play_anim("idle")
	_refresh_name_label()
	_refresh_touch_joystick()
	_connect_joystick_signals()
	_update_global_player_shader_pos(true)
func _setup_anim_tree() -> void:
	var state_machine := AnimationNodeStateMachine.new()
	var state_names := ["idle", "running", "runningjump", "falling", "runningslide"]
	for state_name in state_names:
		var node := AnimationNodeAnimation.new()
		node.animation = state_name
		state_machine.add_node(state_name, node)
	for from_name in state_names:
		for to_name in state_names:
			if from_name != to_name:
				var trans := AnimationNodeStateMachineTransition.new()
				trans.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_SYNC
				trans.xfade_time = 0.12
				state_machine.add_transition(from_name, to_name, trans)
	anim_tree.tree_root = state_machine
	anim_tree.active = true
	anim_state_machine = anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	_camera_collision_distance = camera_distance
	_camera_base_target_prev = global_transform.origin + Vector3(0, 1.5, 0)
	_camera_base_target_curr = _camera_base_target_prev
	_camera_follow_target = _camera_base_target_curr
	_camera_look_target = _camera_follow_target
	_demo_home_center = global_position
	_demo_last_safe_position = global_position
	_demo_wobble_phase = randf_range(0.0, TAU)
	_base_scale = mesh.scale

	if not pickup_area:
		print("ERROR: $Area3D node not found! Please add an Area3D with a CollisionShape to the player.")

func configure_demo_agent(
	home_center: Vector3,
	orbit_radius: float = 3.5,
	orbit_speed: float = 1.1,
	orbit_phase: float = 0.0,
	orbit_direction: float = 1.0,
	jump_min_interval: float = 1.5,
	jump_max_interval: float = 4.5,
	wobble_amount: float = 0.6
) -> void:
	demo_agent = true
	_demo_home_center = home_center
	demo_orbit_radius = maxf(0.25, orbit_radius)
	demo_orbit_speed = maxf(0.05, orbit_speed)
	_demo_orbit_angle = orbit_phase
	_demo_orbit_direction = -1.0 if orbit_direction < 0.0 else 1.0
	demo_jump_min_interval = maxf(0.2, jump_min_interval)
	demo_jump_max_interval = maxf(demo_jump_min_interval, jump_max_interval)
	demo_wobble_amount = maxf(0.0, wobble_amount)
	_demo_rng.randomize()
	_demo_jump_timer = _demo_rng.randf_range(demo_jump_min_interval, demo_jump_max_interval)
	_demo_wobble_phase = _demo_rng.randf_range(0.0, TAU)
	_demo_last_safe_position = home_center + Vector3(0, DEMO_RECOVERY_RAISE_OFFSET, 0)
	_demo_offground_timer = 0.0

func _process(delta: float) -> void:
	if not is_local:
		return
	_update_camera_visual(delta)

func _refresh_name_label() -> void:
	if not name_label:
		return
	var resolved_name = display_name
	if resolved_name == "":
		resolved_name = player_id.substr(0, 8)
	name_label.text = resolved_name

func request_jump() -> void:
	if not _is_movement_allowed():
		return
	_jump_buffer_timer = JUMP_BUFFER_TIME
	if is_on_floor():
		velocity_y = JUMP_VELOCITY
		_jump_requested = false
		if not _double_jump_available:
			_ground_jump_count += 1
			if _ground_jump_count >= 2:
				_double_jump_available = true
				_ground_jump_count = 0
	else:
		_jump_requested = true

func request_slide() -> void:
	_slide_requested = true

func request_pickup() -> void:
	if not _is_movement_allowed():
		return
	call_deferred("_perform_pickup_request")

func _perform_pickup_request() -> void:
	if not _is_movement_allowed():
		return
	if _is_local_holding_chicken() or _is_local_holding_lootbox():
		_drop_object()
	else:
		_try_pickup()

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
		_perform_pickup_request()

func _physics_process(delta: float) -> void:
	if demo_agent and not is_local:
		_update_demo_agent(delta)
		return
	if not is_local:
		return

	_check_map_recovery()
	_update_camera_collision_logic(delta)
	_landing_bob_timer = maxf(0.0, _landing_bob_timer - delta)

	var input_dir := Vector2.ZERO
	var movement_allowed := _is_movement_allowed()
	var is_falling_anim_playing := current_animation == "falling"
	var was_on_floor_before_move := is_on_floor()
	var vertical_speed_before_move := velocity_y

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
	var input_strength := minf(input_dir.length(), 1.0)
	if input_strength > 0.0:
		input_dir = input_dir.normalized() * input_strength
	
	if movement_allowed and input_dir.length_squared() > 0.05 and touch_orbit_pending == Vector2.ZERO and joystick_orbit_pending == Vector2.ZERO:
		var move_angle := atan2(input_dir.x, input_dir.y)
		if abs(move_angle) > AUTO_ORBIT_THRESHOLD_RAD:
			var turn_sharpness := clampf(abs(move_angle) / AUTO_ORBIT_SHARPNESS_RAD, 0.0, 1.0)
			cam_rot_y += -sign(move_angle) * turn_sharpness * AUTO_ORBIT_SPEED * delta

	_apply_touch_orbit()

	if not is_on_floor():
		_double_jump_air_time += delta

	var jump_requested_now := false
	if not is_on_floor():
		var gravity_scale: float = 0.5 if is_falling_anim_playing else 1.0
		velocity_y -= GRAVITY * gravity_scale * delta
	else:
		jump_requested_now = _jump_requested or Input.is_action_just_pressed("jump") or Input.is_joy_button_pressed(gamepad_index, JOY_BUTTON_A)
		_jump_requested = false
		if movement_allowed and jump_requested_now:
			velocity_y = JUMP_VELOCITY
			if not _double_jump_available:
				_ground_jump_count += 1
				if _ground_jump_count >= 2:
					_double_jump_available = true
					_ground_jump_count = 0
		else:
			velocity_y = 0

	var move_basis := Basis(Vector3.UP, cam_rot_y)
	var forward = -move_basis.z
	var right = move_basis.x
	forward.y = 0
	right.y = 0
	forward = forward.normalized()
	right = right.normalized()

	var move_direction = forward * input_dir.y + right * input_dir.x
	if move_direction.length_squared() > 1.0:
		move_direction = move_direction.normalized()

	var slide_requested_now := Input.is_action_just_pressed("slide") or _slide_requested
	if slide_requested_now:
		var slide_from_touch: bool = _slide_requested
		if movement_allowed and is_on_floor() and move_direction.length_squared() > 0.01 and not _is_sliding:
			_slide_requested = false
			_start_slide(move_direction, slide_from_touch)
		else:
			_slide_requested = false

	if is_on_floor():
		_coyote_timer = COYOTE_TIME
	else:
		_coyote_timer = maxf(0.0, _coyote_timer - delta)

	var jump_just_pressed := Input.is_action_just_pressed("jump")
	var jump_joy_held := Input.is_joy_button_pressed(gamepad_index, JOY_BUTTON_A)
	var jump_joy_just_pressed := jump_joy_held and not _prev_joy_a_pressed
	_prev_joy_a_pressed = jump_joy_held
	var jump_any_held_or_pressed := jump_just_pressed or jump_joy_held
	if jump_any_held_or_pressed:
		_jump_buffer_timer = JUMP_BUFFER_TIME
		if not is_on_floor() and _double_jump_available and not _double_jump_used and (jump_just_pressed or jump_joy_just_pressed):
			var apex_time := JUMP_VELOCITY / GRAVITY
			var progress := clampf(_double_jump_air_time / apex_time, 0.0, 1.0)
			var smooth := progress * progress * (3.0 - 2.0 * progress)
			velocity_y = JUMP_VELOCITY * lerpf(DOUBLE_JUMP_MIN_MULTIPLIER, 1.0, smooth)
			_double_jump_used = true
			_double_jump_available = false
			_jump_buffer_timer = 0.0
	else:
		_jump_buffer_timer = maxf(0.0, _jump_buffer_timer - delta)

	if is_on_floor():
		var buffered_jump := movement_allowed and (_jump_buffer_timer > 0.0) and (jump_requested_now or _coyote_timer > 0.0)
		if buffered_jump:
			velocity_y = JUMP_VELOCITY
			_jump_buffer_timer = 0.0
			if not _double_jump_available and not jump_requested_now:
				_ground_jump_count += 1
				if _ground_jump_count >= 2:
					_double_jump_available = true
					_ground_jump_count = 0

	# --- STAMINA ---
	var is_moving_input := move_direction.length_squared() > 0.05

	# Break the held-penalty if player released input
	if _stamina_held_empty and not is_moving_input:
		_stamina_held_empty = false

	# Drain (skip if held-penalized — movement already zeroed)
	if is_moving_input and stamina > 0.0 and not _stamina_held_empty:
		stamina = maxf(0.0, stamina - STAMINA_DRAIN_RATE * delta)
		_stamina_regen_timer = STAMINA_REGEN_DELAY

	# Just hit zero — check if input still held
	if stamina <= 0.0 and is_moving_input:
		_stamina_held_empty = true
		_stamina_empty_timer = STAMINA_HELD_PENALTY

	# Held-penalty countdown (ignores movement for 5 sec)
	if _stamina_held_empty:
		_stamina_empty_timer = maxf(0.0, _stamina_empty_timer - delta)
		if _stamina_empty_timer <= 0.0:
			_stamina_held_empty = false

	# Regen when not draining
	if not is_moving_input or _stamina_held_empty:
		_stamina_regen_timer = maxf(0.0, _stamina_regen_timer - delta)
		if _stamina_regen_timer <= 0.0:
			stamina = minf(STAMINA_MAX, stamina + STAMINA_REGEN_RATE * delta)

	# Zero movement when empty or held-penalized
	if stamina <= 0.0 or _stamina_held_empty:
		move_direction = Vector3.ZERO
		input_dir = Vector2.ZERO

	# --- MOMENTUM CALCULATION ---
	if movement_allowed:
		var target_vel = move_direction * SPEED

		# [MOMENTUM UPDATE] If we are in the air, use max speed instantly (no acceleration)
		if is_on_floor():
			var accel_to_use = ACCELERATION
			var friction_to_use = FRICTION
			var weight = accel_to_use if move_direction.length_squared() > 0.0 else friction_to_use
			velocity.x = move_toward(velocity.x, target_vel.x, weight * delta)
			velocity.z = move_toward(velocity.z, target_vel.z, weight * delta)
		else:
			# Snap to max speed instantly in the air
			velocity.x = target_vel.x
			velocity.z = target_vel.z
	else:
		velocity.x = move_toward(velocity.x, 0, FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0, FRICTION * delta)
		velocity_y = 0.0

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

	if is_on_floor() and not was_on_floor_before_move:
		_start_landing_bob(vertical_speed_before_move)
		_double_jump_available = false
		_double_jump_used = false
		_double_jump_air_time = 0.0
		max_zoom = min_zoom
	_apply_bus_riding()

	# Squash & stretch on jump/land
	var on_floor_now := is_on_floor()
	if on_floor_now:
		if _was_airborne:
			_squash_stretch_target = SQUASH_SCALE
		else:
			_squash_stretch_target = 1.0
		_was_airborne = false
	else:
		if not _was_airborne:
			_squash_stretch_target = SQUASH_SCALE
			_jump_peak_reached = false
		elif velocity_y > 0 and not _jump_peak_reached:
			_squash_stretch_target = STRETCH_SCALE
		elif velocity_y < 0:
			_jump_peak_reached = true
			_squash_stretch_target = 1.0
		_was_airborne = true

	var ss_result := _spring_float(_squash_stretch_y, _squash_stretch_velocity, _squash_stretch_target, SQUASH_STRETCH_SPEED, delta)
	_squash_stretch_y = ss_result[0]
	_squash_stretch_velocity = ss_result[1]
	mesh.scale.y = _base_scale.y * _squash_stretch_y

	camera_is_airborne = not is_on_floor()
	camera_is_moving = velocity.x * velocity.x + velocity.z * velocity.z > 0.01
	_camera_base_target_prev = _camera_base_target_curr
	_camera_base_target_curr = global_transform.origin + Vector3(0, 1.5, 0)

	if move_direction.length_squared() > 0.0025:
		var target_yaw := atan2(move_direction.x, move_direction.z)
		var yaw_result := _spring_angle(mesh.rotation.y, _mesh_yaw_velocity, target_yaw, 20.0, delta)
		mesh.rotation.y = yaw_result[0]
		_mesh_yaw_velocity = yaw_result[1]

	_handle_animations(move_direction)
	_handle_camera_gamepad(delta)

	var net_active: bool = (move_direction.length_squared() > 0.0025) or _is_local_holding_chicken() or (current_animation == "running")
	if current_animation == "runningjump" or current_animation == "falling" or current_animation == "runningslide":
		net_active = true

	var now_ms := float(Time.get_ticks_msec())
	if _last_real_net_ms == 0.0:
		_last_real_net_ms = now_ms
	var real_delta := (now_ms - _last_real_net_ms) / 1000.0
	_last_real_net_ms = now_ms

	network_tick_timer += real_delta
	network_heartbeat_timer += real_delta
	var tick_window := NETWORK_TICK_ACTIVE if net_active else NETWORK_TICK_IDLE
	var force_heartbeat := network_heartbeat_timer >= NETWORK_HEARTBEAT
	if network_tick_timer >= tick_window or force_heartbeat:
		_send_state_to_server(force_heartbeat)
		network_tick_timer = 0.0
		if force_heartbeat:
			network_heartbeat_timer = 0.0

	_update_local_chicken_visual(delta)
	_update_local_lootbox_visual(delta)

	_slow_update_timer += real_delta
	if _slow_update_timer >= SLOW_UPDATE_INTERVAL:
		_slow_update_timer = 0.0
		_update_global_player_shader_pos()
		_refresh_name_label()

var _last_real_net_ms: float = 0.0

func _update_demo_agent(delta: float) -> void:
	if _demo_should_recover():
		_recover_demo_agent()
		return

	_demo_orbit_angle = wrapf(_demo_orbit_angle + (delta * demo_orbit_speed * _demo_orbit_direction), 0.0, TAU)

	var orbit_offset := Vector3(cos(_demo_orbit_angle), 0.0, sin(_demo_orbit_angle)) * demo_orbit_radius
	var wobble_offset := Vector3(
		sin((_demo_orbit_angle * 1.7) + _demo_wobble_phase),
		0.0,
		cos((_demo_orbit_angle * 1.3) + _demo_wobble_phase)
	) * demo_wobble_amount
	var target_pos := _demo_home_center + orbit_offset + wobble_offset
	var move_direction := target_pos - global_position
	move_direction.y = 0.0
	if move_direction.length_squared() > 0.001:
		move_direction = move_direction.normalized()
	else:
		move_direction = Vector3.ZERO

	if not is_on_floor():
		velocity_y -= GRAVITY * delta
	else:
		velocity_y = 0.0
		_demo_jump_timer -= delta
		if _demo_jump_timer <= 0.0:
			velocity_y = JUMP_VELOCITY * _demo_rng.randf_range(0.85, 1.15)
			_demo_jump_timer = _demo_rng.randf_range(demo_jump_min_interval, demo_jump_max_interval)

	# Apply momentum to demo agent
	var demo_target_vel = move_direction * demo_move_speed
	
	if is_on_floor():
		velocity.x = move_toward(velocity.x, demo_target_vel.x, ACCELERATION * delta)
		velocity.z = move_toward(velocity.z, demo_target_vel.z, ACCELERATION * delta)
	else:
		# Demo agent also snaps in air
		velocity.x = demo_target_vel.x
		velocity.z = demo_target_vel.z
		
	velocity.y = velocity_y
	move_and_slide()
	_apply_bus_riding()

	var on_floor_demo := is_on_floor()
	if on_floor_demo:
		if _was_airborne:
			_squash_stretch_target = SQUASH_SCALE
		else:
			_squash_stretch_target = 1.0
		_was_airborne = false
	else:
		if not _was_airborne:
			_squash_stretch_target = SQUASH_SCALE
			_jump_peak_reached = false
		elif velocity_y > 0 and not _jump_peak_reached:
			_squash_stretch_target = STRETCH_SCALE
		elif velocity_y < 0:
			_jump_peak_reached = true
			_squash_stretch_target = 1.0
		_was_airborne = true

	var ss_demo := _spring_float(_squash_stretch_y, _squash_stretch_velocity, _squash_stretch_target, SQUASH_STRETCH_SPEED, delta)
	_squash_stretch_y = ss_demo[0]
	_squash_stretch_velocity = ss_demo[1]
	mesh.scale.y = _base_scale.y * _squash_stretch_y

	camera_is_airborne = not is_on_floor()
	camera_is_moving = velocity.x * velocity.x + velocity.z * velocity.z > 0.01
	_camera_base_target_prev = _camera_base_target_curr
	_camera_base_target_curr = global_transform.origin + Vector3(0, 1.5, 0)

	if move_direction.length_squared() > 0.0025:
		var target_yaw := atan2(move_direction.x, move_direction.z)
		var yaw_result := _spring_angle(mesh.rotation.y, _mesh_yaw_velocity, target_yaw, 14.0, delta)
		mesh.rotation.y = yaw_result[0]
		_mesh_yaw_velocity = yaw_result[1]

	if camera_is_airborne:
		if velocity_y < 0.0:
			current_animation = "falling"
			_play_anim("falling")
		else:
			current_animation = "runningjump"
			_play_anim("runningjump")
	elif camera_is_moving:
		current_animation = "running"
		_play_anim("running")
	else:
		current_animation = "idle"
		_play_anim("idle")

	if is_on_floor():
		_demo_last_safe_position = global_position
		_demo_offground_timer = 0.0
	else:
		_demo_offground_timer += delta

func _demo_should_recover() -> bool:
	if global_position.y < _demo_home_center.y - DEMO_RECOVERY_FALL_DISTANCE:
		return true
	if _demo_offground_timer >= DEMO_RECOVERY_OFFGROUND_TIME and not is_on_floor():
		return true
	return false

func _recover_demo_agent() -> void:
	var recovery_pos := _demo_last_safe_position
	if recovery_pos == Vector3.ZERO:
		recovery_pos = _demo_home_center
	recovery_pos.y = maxf(recovery_pos.y, _demo_home_center.y) + DEMO_RECOVERY_RAISE_OFFSET

	global_position = recovery_pos
	velocity = Vector3.ZERO
	velocity_y = 0.0
	_demo_jump_timer = _demo_rng.randf_range(demo_jump_min_interval, demo_jump_max_interval)
	_demo_offground_timer = 0.0
	camera_is_airborne = false
	camera_is_moving = false
	current_animation = "idle"
	_play_anim("idle")

func _check_map_recovery() -> void:
	if global_position.y >= -5.0:
		return

	var now_ms := Time.get_ticks_msec()
	if now_ms - _last_recovery_ms < 750:
		return

	_last_recovery_ms = now_ms
	_is_sliding = false
	_slide_timer = 0.0
	_slide_direction = Vector3.ZERO
	_slide_camera_restore_active = false
	_jump_requested = false
	_air_horizontal_velocity = Vector3.ZERO
	velocity = Vector3.ZERO
	velocity_y = 0.0
	cam_rot_x = clamp(cam_rot_x, min_pitch, max_pitch)
	current_animation = "idle"
	_play_anim("idle")

	if root and root.has_method("get_local_spawn_position"):
		global_position = root.get_local_spawn_position()
	else:
		global_position = Vector3(0, 2, 0)

	_last_world_y = global_position.y
	_airborne_start_y = global_position.y
	_was_on_floor = true
	_update_global_player_shader_pos(true)
	_send_state_to_server(true)

func _start_landing_bob(fall_velocity: float) -> void:
	var impact_speed := absf(fall_velocity)
	if impact_speed < 4.5:
		return
	_landing_bob_strength = clamp((impact_speed - 4.5) / 12.0, 0.0, 1.0)
	_landing_bob_timer = LANDING_BOB_DURATION

func _try_pickup():
	if not pickup_area:
		return
	var now = Time.get_ticks_msec()
	if now - last_pickup_request_ms < PICKUP_REQUEST_COOLDOWN_MS:
		return
	last_pickup_request_ms = now
	var bodies = pickup_area.get_overlapping_bodies()
	var best_target: RigidBody3D = null
	var shortest_dist: float = 999.0
	for body in bodies:
		if body is RigidBody3D and body != self and body.is_in_group("pickup_items"):
			var dist = global_position.distance_to(body.global_position)
			if dist < shortest_dist:
				shortest_dist = dist
				best_target = body
	if best_target == null:
		var entities: Array[RigidBody3D] = [
			_get_cached_chicken_node(),
			_get_cached_lootbox_node(),
		]
		var fallback_dist: float = STEAL_RADIUS
		for entity in entities:
			if entity != null and entity.is_in_group("pickup_items"):
				var dist = global_position.distance_to(entity.global_position)
				if dist < fallback_dist:
					fallback_dist = dist
					best_target = entity
	if best_target and root and root.ws and root.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		root.ws.send(MsgPack.pack({
			"type": "pickup_request",
			"item_id": best_target.name
		}))

func _drop_object():
	if not _is_local_holding_chicken() and not _is_local_holding_lootbox():
		return
	if not root or not root.ws:
		return
	if root.ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var item_id = "Chicken" if _is_local_holding_chicken() else "LootBox"
	var throw_dir = -camera.global_transform.basis.z
	root.ws.send(MsgPack.pack({
		"type": "drop_request",
		"item_id": item_id,
		"throw_x": throw_dir.x * 5.0,
		"throw_y": max(1.0, throw_dir.y * 5.0),
		"throw_z": throw_dir.z * 5.0
	}))

func _is_local_holding_chicken() -> bool:
	if not root or not root.has_method("is_local_player_holding_chicken"):
		return false
	return root.is_local_player_holding_chicken()

func _is_local_holding_lootbox() -> bool:
	if not root or not root.has_method("is_local_player_holding_lootbox"):
		return false
	return root.is_local_player_holding_lootbox()

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

func _update_local_lootbox_visual(delta: float) -> void:
	if not is_local or not _is_local_holding_lootbox():
		return
	var lootbox: RigidBody3D = _get_cached_lootbox_node()
	if lootbox == null:
		return
	var forward = -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	var target_pos = global_position + (forward * hold_distance)
	target_pos.y += hold_height
	lootbox.global_position = lootbox.global_position.lerp(target_pos, min(1.0, 16.0 * delta))

var _spring_rv: Array = [0.0, 0.0]
var _spring_rv3: Array = [Vector3.ZERO, Vector3.ZERO]

func _spring_float(current: float, vel: float, target: float, sharpness: float, delta: float) -> Array:
	if absf(current - target) <= SPRING_SETTLE_EPSILON and absf(vel) <= SPRING_SETTLE_VELOCITY_EPSILON:
		_spring_rv[0] = target; _spring_rv[1] = 0.0
		return _spring_rv
	var omega := maxf(sharpness, 0.001)
	var x := current - target
	var exp_factor := exp(-omega * delta)
	var temp := (vel + omega * x) * delta
	var next_value := target + (x + temp) * exp_factor
	var next_velocity := (vel - omega * temp) * exp_factor
	if absf(next_value - target) <= SPRING_SETTLE_EPSILON and absf(next_velocity) <= SPRING_SETTLE_VELOCITY_EPSILON:
		_spring_rv[0] = target; _spring_rv[1] = 0.0
		return _spring_rv
	_spring_rv[0] = next_value; _spring_rv[1] = next_velocity
	return _spring_rv

func _spring_vec3(current: Vector3, vel: Vector3, target: Vector3, sharpness: float, delta: float) -> Array:
	var eps2 := SPRING_SETTLE_EPSILON * SPRING_SETTLE_EPSILON
	if current.distance_squared_to(target) <= eps2 and vel.length_squared() <= SPRING_SETTLE_VELOCITY_EPSILON * SPRING_SETTLE_VELOCITY_EPSILON:
		_spring_rv3[0] = target; _spring_rv3[1] = Vector3.ZERO
		return _spring_rv3
	var omega := maxf(sharpness, 0.001)
	var x := current - target
	var exp_factor := exp(-omega * delta)
	var temp := (vel + omega * x) * delta
	var next_value := target + (x + temp) * exp_factor
	var next_velocity := (vel - omega * temp) * exp_factor
	if next_value.distance_squared_to(target) <= eps2 and next_velocity.length_squared() <= SPRING_SETTLE_VELOCITY_EPSILON * SPRING_SETTLE_VELOCITY_EPSILON:
		_spring_rv3[0] = target; _spring_rv3[1] = Vector3.ZERO
		return _spring_rv3
	_spring_rv3[0] = next_value; _spring_rv3[1] = next_velocity
	return _spring_rv3

func _apply_bus_riding() -> void:
	if _bus_node == null:
		_bus_node = get_tree().get_first_node_in_group("bus")
		if _bus_node:
			_bus_last_pos = _bus_node.global_position
	if _bus_node == null:
		return
	var bus_pos := _bus_node.global_position
	var bus_delta := bus_pos - _bus_last_pos
	_bus_last_pos = bus_pos
	var to_bus := global_position - bus_pos
	var on_bus: bool = abs(to_bus.y) < 10.0 and Vector2(to_bus.x, to_bus.z).length() < 35.0
	if _is_riding_bus:
		global_position += bus_delta
		if not on_bus: 
			_is_riding_bus = false
	elif on_bus:
		_is_riding_bus = true
		max_zoom = bus_zoom
		global_position += bus_delta

func _spring_angle(current: float, vel: float, target: float, sharpness: float, delta: float) -> Array:
	var wrapped_target := current + angle_difference(current, target)
	return _spring_float(current, vel, wrapped_target, sharpness, delta)

func _handle_camera_gamepad(delta: float) -> void:
	var rx := Input.get_joy_axis(gamepad_index, JOY_AXIS_RIGHT_X)
	var ry := Input.get_joy_axis(gamepad_index, JOY_AXIS_RIGHT_Y)
	if abs(rx) > DEADZONE:
		cam_rot_y -= rx * 0.05 * delta * 60
	if abs(ry) > DEADZONE:
		cam_rot_x = clamp(cam_rot_x + ry * 0.05 * delta * 60, min_pitch, max_pitch)

func _update_camera_collision_logic(delta: float) -> void:
	_camera_update_skip_frames += 1
	if _camera_update_skip_frames < 3:
		return
	_camera_update_skip_frames = 0
	var holding_chicken := _is_local_holding_chicken()
	var above_12 := global_position.y > 12.0
	var movement_allowed := _is_movement_allowed()
	var vehicle_zoom_cap: float = max_zoom
	if above_12:
		vehicle_zoom_cap = max_zoom * 2.0
	var ground_zoom: float = lerp(min_zoom, vehicle_zoom_cap, 0.5)
	var state_zoom: float = min_zoom
	if above_12:
		state_zoom = vehicle_zoom_cap
	elif current_animation == "falling":
		state_zoom = min_zoom
	elif camera_is_airborne:
		state_zoom = max_zoom
	elif camera_is_moving:
		state_zoom = ground_zoom
	elif not movement_allowed and root and root.has_method("is_waiting_for_players") and root.is_waiting_for_players():
		state_zoom = max_zoom
	var target_distance: float = min_zoom if current_animation == "falling" else clamp(state_zoom + camera_distance_bias, min_zoom, vehicle_zoom_cap)
	if _is_riding_bus:
		target_distance = bus_zoom
	var distance_result := _spring_float(camera_distance_current, _camera_distance_velocity, target_distance, camera_smoothness, delta * 2.0)
	camera_distance_current = distance_result[0]
	_camera_distance_velocity = distance_result[1]
	var altitude_zoom: float = clamp(global_transform.origin.y * altitude_zoom_factor, 0.0, vehicle_zoom_cap - min_zoom)
	var effective_camera_distance: float = clamp(camera_distance_current + altitude_zoom, min_zoom, vehicle_zoom_cap)
	_sin_cam_y = sin(cam_rot_y)
	_cos_cam_y = cos(cam_rot_y)
	_sin_cam_x = sin(cam_rot_x)
	_cos_cam_x = cos(cam_rot_x)
	var target_pos: Vector3 = _camera_follow_target
	var cam_offset: Vector3 = Vector3(_sin_cam_y * _cos_cam_x, _sin_cam_x, _cos_cam_y * _cos_cam_x) * effective_camera_distance
	var desired_pos: Vector3 = target_pos + cam_offset
	if above_12:
		_camera_collision_hold_timer = 0.0
		_camera_collision_distance = move_toward(_camera_collision_distance, effective_camera_distance, delta * CAMERA_COLLISION_RECOVERY_SPEED * 8.0)
	else:
		var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		_camera_ray_query.from = target_pos
		_camera_ray_query.to = desired_pos
		if not _camera_ray_layer_set:
			_camera_ray_query.collision_mask = 1
			_camera_ray_layer_set = true
		if _camera_ray_exclude.is_empty():
			_camera_ray_exclude.append(get_rid())
		if holding_chicken:
			var chicken_node: RigidBody3D = _get_cached_chicken_node()
			if chicken_node and _camera_ray_exclude.size() == 1:
				_camera_ray_exclude.append(chicken_node.get_rid())
		elif _camera_ray_exclude.size() > 1:
			_camera_ray_exclude.resize(1)
		_camera_ray_query.exclude = _camera_ray_exclude
		var hit: Dictionary = space_state.intersect_ray(_camera_ray_query)
		var target_collision_distance := effective_camera_distance
		if hit and hit.has("position"):
			var hit_distance := target_pos.distance_to(hit.position)
			target_collision_distance = maxf(0.05, hit_distance - CAMERA_COLLISION_MARGIN)
			_camera_collision_hold_timer = CAMERA_COLLISION_HOLD_TIME
			if _camera_collision_distance <= 0.0:
				_camera_collision_distance = target_collision_distance
			else:
				_camera_collision_distance = minf(_camera_collision_distance, target_collision_distance)
		else:
			_camera_collision_hold_timer = maxf(0.0, _camera_collision_hold_timer - delta * 2.0)
			if _camera_collision_hold_timer <= 0.0:
				_camera_collision_distance = move_toward(_camera_collision_distance, target_collision_distance, delta * 2.0 * CAMERA_COLLISION_RECOVERY_SPEED)

func _update_camera_visual(delta: float) -> void:
	var interp := Engine.get_physics_interpolation_fraction()
	var raw_target_pos: Vector3 = _camera_base_target_prev.lerp(_camera_base_target_curr, interp)
	var above_12 := global_position.y > 12.0
	var follow_sharpness := 80.0 if above_12 else 9.0
	var pos_smoothness := camera_smoothness * 5.0 if above_12 else camera_smoothness
	var look_smoothness := camera_smoothness * 0.85 * 5.0 if above_12 else camera_smoothness * 0.85
	var follow_result := _spring_vec3(_camera_follow_target, _camera_follow_velocity, raw_target_pos, follow_sharpness, delta)
	_camera_follow_target = follow_result[0]
	_camera_follow_velocity = follow_result[1]
	var target_pos: Vector3 = _camera_follow_target
	cam_rot_x = clamp(cam_rot_x, min_pitch, max_pitch)
	var holding_chicken := _is_local_holding_chicken()
	var cam_offset: Vector3 = Vector3(_sin_cam_y * _cos_cam_x, _sin_cam_x, _cos_cam_y * _cos_cam_x) 
	var camera_direction := cam_offset 
	if camera_direction.length_squared() < 0.0001:
		camera_direction = Vector3.FORWARD
	var desired_pos := target_pos + camera_direction * _camera_collision_distance
	if _landing_bob_timer > 0.0:
		var landing_progress: float = 1.0 - (_landing_bob_timer / LANDING_BOB_DURATION)
		var landing_t := 1.0 - landing_progress
		var landing_offset: float = _landing_bob_strength * 0.18 * landing_t * landing_t
		desired_pos.y -= landing_offset
	var position_result := _spring_vec3(camera.global_position, _camera_position_velocity, desired_pos, pos_smoothness, delta)
	camera.global_position = position_result[0]
	_camera_position_velocity = position_result[1]
	var look_result := _spring_vec3(_camera_look_target, _camera_look_target_velocity, target_pos, look_smoothness, delta)
	_camera_look_target = look_result[0]
	_camera_look_target_velocity = look_result[1]
	camera.look_at(_camera_look_target, Vector3.UP)
	var target_fov := 125.0 if holding_chicken else 95.0
	var fov_result := _spring_float(camera.fov, _camera_fov_velocity, target_fov, camera_smoothness * 1.1, delta)
	camera.fov = fov_result[0]
	_camera_fov_velocity = fov_result[1]
	var dist_to_target: float = maxf(camera_distance_current, 0.001)
	var v_fov_rad: float = deg_to_rad(camera.fov)
	if _cached_viewport_size == Vector2.ZERO:
		_cached_viewport_size = get_viewport().get_visible_rect().size
	var aspect: float = _cached_viewport_size.x / max(1.0, _cached_viewport_size.y)
	var half_height: float = dist_to_target * tan(v_fov_rad / 2.0)
	var half_width: float = half_height * aspect
	camera.h_offset = -camera_screen_offset.x * half_width
	camera.v_offset = -camera_screen_offset.y * half_height

func _quantize_pos(value: float) -> int:
	return int(round(value * POS_SCALE))

func _quantize_rot(value: float) -> int:
	return int(round(value * ROT_SCALE))

var _payload: Dictionary = {}
var _chicken_payload: Dictionary = {}
var _lootbox_payload: Dictionary = {}

func _send_state_to_server(_force_send := false) -> void:
	if not root or not root.ws:
		return
	if root.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		root._last_server_position = global_transform.origin
		var qx := _quantize_pos(global_transform.origin.x)
		var qy := _quantize_pos(global_transform.origin.y)
		var qz := _quantize_pos(global_transform.origin.z)
		var qrot := _quantize_rot(mesh.rotation.y)
		var anim_id := int(ANIM_NAME_TO_ID.get(current_animation, 0))
		_payload["type"] = "update_state"
		_payload["qx"] = qx
		_payload["qy"] = qy
		_payload["qz"] = qz
		_payload["qrot"] = qrot
		_payload["anim_id"] = anim_id
		_payload["slide"] = 1 if _is_sliding else 0
		_payload["skin"] = str(root.local_skin_name) if root != null else ""
		_payload.erase("chicken")
		_payload.erase("lootbox")
		if _is_local_holding_chicken() and root.has_method("build_local_chicken_payload"):
			var chicken_payload = root.build_local_chicken_payload(global_position, -global_transform.basis.z, mesh.rotation.y)
			if chicken_payload != null:
				_chicken_payload["qx"] = _quantize_pos(float(chicken_payload.get("x", 0.0)))
				_chicken_payload["qy"] = _quantize_pos(float(chicken_payload.get("y", 0.0)))
				_chicken_payload["qz"] = _quantize_pos(float(chicken_payload.get("z", 0.0)))
				_chicken_payload["qrot"] = _quantize_rot(float(chicken_payload.get("rotation_y", 0.0)))
				_payload["chicken"] = _chicken_payload
		if _is_local_holding_lootbox() and root.has_method("build_local_lootbox_payload"):
			var lootbox_payload = root.build_local_lootbox_payload(global_position, -global_transform.basis.z, mesh.rotation.y)
			if lootbox_payload != null:
				_lootbox_payload["qx"] = _quantize_pos(float(lootbox_payload.get("x", 0.0)))
				_lootbox_payload["qy"] = _quantize_pos(float(lootbox_payload.get("y", 0.0)))
				_lootbox_payload["qz"] = _quantize_pos(float(lootbox_payload.get("z", 0.0)))
				_lootbox_payload["qrot"] = _quantize_rot(float(lootbox_payload.get("rotation_y", 0.0)))
				_payload["lootbox"] = _lootbox_payload
		root.ws.send(MsgPack.pack(_payload))

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
	_play_anim(new_state)

func _handle_animations(_move_dir: Vector3) -> void:
	if not is_local: return
	if not _is_movement_allowed():
		current_animation = "idle"
		_play_anim("idle")
		_was_on_floor = is_on_floor()
		_last_world_y = global_position.y
		return
	if _is_sliding:
		current_animation = "runningslide"
		_play_anim("runningslide")
		_last_world_y = global_position.y
		return
	var on_floor_now := is_on_floor()
	var current_y := global_position.y
	if on_floor_now:
		_was_on_floor = true
		_airborne_start_y = current_y
		_last_world_y = current_y
		var horizontal_speed_sq = velocity.x * velocity.x + velocity.z * velocity.z
		if horizontal_speed_sq > 0.25:
			current_animation = "running"
			_play_anim("running")
		else:
			current_animation = "idle"
			_play_anim("idle")
		return
	if _was_on_floor:
		_airborne_start_y = current_y
	_was_on_floor = false
	var y_delta := current_y - _last_world_y
	var height_from_takeoff := current_y - _airborne_start_y
	var vertical_distance_from_takeoff: float = absf(height_from_takeoff)
	var is_falling: bool = ((velocity_y <= 0.0 and height_from_takeoff < 0.0 and vertical_distance_from_takeoff >= max_jump_height) or (y_delta < -0.01 and height_from_takeoff < 0.0 and vertical_distance_from_takeoff >= max_jump_height))
	if is_falling:
		current_animation = "falling"
		_play_anim("falling")
	else:
		current_animation = "runningjump"
		_play_anim("runningjump")
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

func _get_cached_lootbox_node() -> RigidBody3D:
	if _cached_lootbox_node != null and is_instance_valid(_cached_lootbox_node):
		return _cached_lootbox_node
	if root and root.has_method("get_lootbox_node"):
		var lootbox = root.get_lootbox_node()
		if lootbox is RigidBody3D:
			_cached_lootbox_node = lootbox
			return _cached_lootbox_node
	return null

func _play_anim(anim_name: String) -> void:
	if anim_state_machine:
		anim_state_machine.travel(anim_name)

func _start_slide(move_direction: Vector3, slide_from_touch: bool = false) -> void:
	_is_sliding = true
	_slide_timer = SLIDE_DURATION
	_slide_direction = move_direction.normalized()
	_slide_camera_restore_active = slide_from_touch
	current_animation = "runningslide"
	_play_anim("runningslide")

func _stop_slide() -> void:
	_is_sliding = false
	_slide_timer = 0.0
	_slide_direction = Vector3.ZERO
	_slide_camera_restore_active = false

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
		if joystick_orbit_invert_x: joystick_delta.x = -joystick_delta.x
		if joystick_orbit_invert_y: joystick_delta.y = -joystick_delta.y
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

func disable_character_shadows() -> void:
	for child in find_children("*", "MeshInstance3D", true):
		child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _spawn_flash() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(1, 1, 1, 1)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var viewport := get_viewport()
	if viewport == null:
		return
	overlay.size = viewport.get_visible_rect().size
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	canvas.add_child(overlay)
	viewport.get_camera_3d().add_child(canvas)
	var tween := create_tween()
	tween.tween_property(overlay, "color:a", 0.0, 0.35)
	tween.tween_callback(canvas.queue_free)
