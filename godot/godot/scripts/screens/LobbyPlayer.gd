extends CharacterBody3D

const GRAVITY: float = 9.8
const JUMP_VELOCITY: float = 4.5
const SPEED: float = 4.5

# --- GAMEPAD SETTINGS ---
var gamepad_index: int = 0
const DEADZONE: float = 0.12

# --- AFK SETTINGS ---
@export_group("AFK Settings")
@export var afk_radius: float = 5.0
@export var afk_speed: float = 2.0
@export var afk_wait_time: float = 2.0

# --- CAMERA SETTINGS ---
@export_group("Camera Settings")
@export var camera_distance: float = 4.0
@export var camera_smoothness: float = 10.0
@export var min_pitch: float = deg_to_rad(-40.0)
@export var max_pitch: float = deg_to_rad(60.0)
@export var min_zoom: float = 2.0
@export var max_zoom: float = 10.0
@export var altitude_zoom_factor: float = 5.0

# --- DYNAMIC CAMERA SETTINGS (NEW) ---
@export_group("Dynamic Camera")
@export var enable_dynamic_framing: bool = false
@export var drift_intensity: float = 0.05 # Keep idle camera motion very subtle.
@export var look_ahead_factor: float = 0.2 # Keep motion framing restrained.

@onready var camera: Camera3D = get_node("../Camera3D")
@onready var name_label: Label3D = $Label3D
@onready var anim_player: AnimationPlayer = $animator
@onready var anim_tree: AnimationTree = $AnimationTree
var anim_state_machine: AnimationNodeStateMachinePlayback = null
@onready var mesh: Skeleton3D = $Skeleton3D

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

# Internal AFK State
var afk_center_pos: Vector3 = Vector3.ZERO
var afk_target_pos: Vector3 = Vector3.ZERO
var afk_timer: float = 0.0

# Dynamic Camera State
var cam_noise: FastNoiseLite = FastNoiseLite.new()
var cam_noise_time: float = 0.0
var current_framing_offset: Vector3 = Vector3.ZERO
var active_touches: int = 0
var _camera_distance_velocity: float = 0.0
var _camera_position_velocity: Vector3 = Vector3.ZERO
var _framing_velocity: Vector3 = Vector3.ZERO
var _mesh_yaw_velocity: float = 0.0
var _camera_collision_distance: float = 0.0
var _camera_collision_hold_timer: float = 0.0
var _camera_base_target_prev: Vector3 = Vector3.ZERO
var _camera_base_target_curr: Vector3 = Vector3.ZERO
var _camera_follow_target: Vector3 = Vector3.ZERO
var _camera_follow_velocity: Vector3 = Vector3.ZERO
var _camera_look_target: Vector3 = Vector3.ZERO
var _camera_look_target_velocity: Vector3 = Vector3.ZERO

const CAMERA_COLLISION_MARGIN: float = 0.18
const CAMERA_COLLISION_HOLD_TIME: float = 0.08
const CAMERA_COLLISION_RECOVERY_SPEED: float = 10.0
const SPRING_SETTLE_EPSILON: float = 0.0005
const SPRING_SETTLE_VELOCITY_EPSILON: float = 0.0005

var player_id: String = "" :
	set(new_id):
		player_id = new_id
		_refresh_name_label()

func _ready() -> void:
	camera_distance = clamp(camera_distance, min_zoom, max_zoom)
	camera_distance_current = camera_distance
	cam_rot_x = min_pitch
	_setup_anim_tree()
	_play_anim("idle")
	_refresh_name_label()

func _setup_anim_tree() -> void:
	var state_machine := AnimationNodeStateMachine.new()
	var state_names := ["idle", "running"]
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

func _play_anim(anim_name: String) -> void:
	if anim_state_machine:
		anim_state_machine.travel(anim_name)
	
	# Initialize AFK center
	afk_center_pos = global_position
	afk_target_pos = global_position
	
	# Setup Noise for camera drift
	cam_noise.seed = randi()
	cam_noise.frequency = 0.5 # Lower = slower drift
	_camera_collision_distance = camera_distance
	_camera_base_target_prev = global_position + Vector3(0, 1.5, 0)
	_camera_base_target_curr = _camera_base_target_prev
	_camera_follow_target = _camera_base_target_curr
	_camera_look_target = _camera_follow_target

func _process(delta: float) -> void:
	if not is_local:
		return
	_update_camera(delta)

func _input(event: InputEvent) -> void:
	if not is_local:
		return

	var viewport = get_viewport().get_visible_rect()
	var size = viewport.size
	var portrait = size.y > size.x

	# Track active touches 
	if event is InputEventScreenTouch:
		if event.pressed:
			active_touches += 1
		else:
			active_touches = max(0, active_touches - 1)

	# Touch Zones
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if portrait:
			if event.position.y > size.y * 0.5:
				return
		else:
			if event.position.x < size.x * 0.5:
				return

	# Touch Camera Rotation
	if event is InputEventScreenDrag:
		cam_rot_y -= event.relative.x * 0.0045
		cam_rot_x = clamp(cam_rot_x + event.relative.y * 0.0045, min_pitch, max_pitch)

	# Mouse Camera Rotation (prevent firing alongside emulated touches)
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if active_touches > 0:
			return
		cam_rot_y -= event.relative.x * 0.005
		cam_rot_x = clamp(cam_rot_x + event.relative.y * 0.005, min_pitch, max_pitch)

	# Zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera_distance_bias = clamp(camera_distance_bias - 0.5, -(max_zoom - min_zoom), (max_zoom - min_zoom))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera_distance_bias = clamp(camera_distance_bias + 0.5, -(max_zoom - min_zoom), (max_zoom - min_zoom))

func _physics_process(delta: float) -> void:
	if not is_local:
		return

	# 1. GATHER INPUT
	var input_dir := Vector2.ZERO
	input_dir.y += Input.get_action_strength("move_forward")
	input_dir.y -= Input.get_action_strength("move_back")
	input_dir.x -= Input.get_action_strength("move_left")
	input_dir.x += Input.get_action_strength("move_right")

	var lx := Input.get_joy_axis(gamepad_index, JOY_AXIS_LEFT_X)
	var ly := Input.get_joy_axis(gamepad_index, JOY_AXIS_LEFT_Y)

	if abs(lx) > DEADZONE: input_dir.x += lx
	if abs(ly) > DEADZONE: input_dir.y -= ly
	var input_strength := minf(input_dir.length(), 1.0)
	if input_strength > 0.0:
		input_dir = input_dir.normalized() * input_strength
	
	var is_jumping_input = Input.is_action_just_pressed("jump") or Input.is_joy_button_pressed(gamepad_index, JOY_BUTTON_A)

	# 2. DETERMINE MOVEMENT (Player Controlled vs AFK)
	var move_direction := Vector3.ZERO
	var current_speed := SPEED
	
	if input_dir.length() > 0 or is_jumping_input:
		afk_center_pos = global_position
		afk_timer = 0.0
		
		var cam_basis = camera.global_transform.basis
		var forward = -cam_basis.z
		var right = cam_basis.x
		forward.y = 0
		right.y = 0
		forward = forward.normalized()
		right = right.normalized()

		move_direction = forward * input_dir.y + right * input_dir.x
	else:
		move_direction = _get_afk_movement_direction(delta)
		current_speed = afk_speed

	# 3. APPLY GRAVITY & JUMP
	if not is_on_floor():
		velocity_y -= GRAVITY * delta
	else:
		velocity_y = 0
		if is_jumping_input:
			velocity_y = JUMP_VELOCITY

	velocity.x = move_direction.x * current_speed
	velocity.z = move_direction.z * current_speed
	velocity.y = velocity_y
	move_and_slide()
	camera_is_airborne = not is_on_floor()
	camera_is_moving = Vector2(velocity.x, velocity.z).length() > 0.1
	_camera_base_target_prev = _camera_base_target_curr
	_camera_base_target_curr = global_position + Vector3(0, 1.5, 0)

	if move_direction.length() > 0.05:
		var target_yaw := atan2(move_direction.x, move_direction.z)
		var yaw_result := _spring_angle(mesh.rotation.y, _mesh_yaw_velocity, target_yaw, 14.0, delta)
		mesh.rotation.y = yaw_result[0]
		_mesh_yaw_velocity = yaw_result[1]

	_handle_camera_gamepad(delta)
	_handle_animations(move_direction)
	_send_state_to_server()

func _refresh_name_label() -> void:
	if name_label:
		name_label.text = player_id.substr(0, 8)

# --- AFK LOGIC ---
func _get_afk_movement_direction(delta: float) -> Vector3:
	afk_timer -= delta
	var dist_to_target = global_position.distance_to(afk_target_pos)
	
	if dist_to_target < 0.5 or afk_timer <= 0:
		var random_angle = randf() * TAU
		var random_dist = randf() * afk_radius
		var offset = Vector3(sin(random_angle), 0, cos(random_angle)) * random_dist
		afk_target_pos = afk_center_pos + offset
		afk_timer = afk_wait_time + randf() * 2.0
		
	if afk_timer > 2.0: 
		return Vector3.ZERO
		
	return (afk_target_pos - global_position).normalized()

var _spring_rv: Array = [0.0, 0.0]
var _spring_rv3: Array = [Vector3.ZERO, Vector3.ZERO]

func _spring_float(current: float, velocity: float, target: float, sharpness: float, delta: float) -> Array:
	if absf(current - target) <= SPRING_SETTLE_EPSILON and absf(velocity) <= SPRING_SETTLE_VELOCITY_EPSILON:
		_spring_rv[0] = target; _spring_rv[1] = 0.0
		return _spring_rv
	var omega := maxf(sharpness, 0.001)
	var x := current - target
	var exp_factor := exp(-omega * delta)
	var temp := (velocity + omega * x) * delta
	var next_value := target + (x + temp) * exp_factor
	var next_velocity := (velocity - omega * temp) * exp_factor
	if absf(next_value - target) <= SPRING_SETTLE_EPSILON and absf(next_velocity) <= SPRING_SETTLE_VELOCITY_EPSILON:
		_spring_rv[0] = target; _spring_rv[1] = 0.0
		return _spring_rv
	_spring_rv[0] = next_value; _spring_rv[1] = next_velocity
	return _spring_rv

func _spring_vec3(current: Vector3, velocity: Vector3, target: Vector3, sharpness: float, delta: float) -> Array:
	var eps2 := SPRING_SETTLE_EPSILON * SPRING_SETTLE_EPSILON
	if current.distance_squared_to(target) <= eps2 and velocity.length_squared() <= SPRING_SETTLE_VELOCITY_EPSILON * SPRING_SETTLE_VELOCITY_EPSILON:
		_spring_rv3[0] = target; _spring_rv3[1] = Vector3.ZERO
		return _spring_rv3
	var omega := maxf(sharpness, 0.001)
	var x := current - target
	var exp_factor := exp(-omega * delta)
	var temp := (velocity + omega * x) * delta
	var next_value := target + (x + temp) * exp_factor
	var next_velocity := (velocity - omega * temp) * exp_factor
	if next_value.distance_squared_to(target) <= eps2 and next_velocity.length_squared() <= SPRING_SETTLE_VELOCITY_EPSILON * SPRING_SETTLE_VELOCITY_EPSILON:
		_spring_rv3[0] = target; _spring_rv3[1] = Vector3.ZERO
		return _spring_rv3
	_spring_rv3[0] = next_value; _spring_rv3[1] = next_velocity
	return _spring_rv3

func _spring_angle(current: float, velocity: float, target: float, sharpness: float, delta: float) -> Array:
	var wrapped_target := current + angle_difference(current, target)
	return _spring_float(current, velocity, wrapped_target, sharpness, delta)

# --- CAMERA LOGIC ---
func _handle_camera_gamepad(delta: float) -> void:
	var rx := Input.get_joy_axis(gamepad_index, JOY_AXIS_RIGHT_X)
	var ry := Input.get_joy_axis(gamepad_index, JOY_AXIS_RIGHT_Y)

	if abs(rx) > DEADZONE:
		cam_rot_y -= rx * 0.05 * delta * 60
	if abs(ry) > DEADZONE:
		cam_rot_x = clamp(cam_rot_x + ry * 0.05 * delta * 60, min_pitch, max_pitch)

func _update_camera(delta: float) -> void:
	# 1. Base Target (Player Head)
	var interp := Engine.get_physics_interpolation_fraction()
	var raw_target_pos: Vector3 = _camera_base_target_prev.lerp(_camera_base_target_curr, interp)
	var follow_result := _spring_vec3(_camera_follow_target, _camera_follow_velocity, raw_target_pos, 8.0, delta)
	_camera_follow_target = follow_result[0]
	_camera_follow_velocity = follow_result[1]
	var base_target_pos: Vector3 = _camera_follow_target
	cam_rot_x = clamp(cam_rot_x, min_pitch, max_pitch)

	# 2. Dynamic Framing Calculation
	var target_look_offset := Vector3.ZERO
	if enable_dynamic_framing:
		cam_noise_time += delta
		var drift_x := cam_noise.get_noise_2d(cam_noise_time, 0) * drift_intensity
		var drift_y := cam_noise.get_noise_2d(0, cam_noise_time) * (drift_intensity * 0.5)
		var vel_lead := Vector3.ZERO
		if velocity.length() > 0.1:
			vel_lead = velocity.normalized() * look_ahead_factor
			vel_lead.y *= 0.15
		target_look_offset = Vector3(drift_x, drift_y, 0) + vel_lead
	var framing_result := _spring_vec3(current_framing_offset, _framing_velocity, target_look_offset, 8.0, delta)
	current_framing_offset = framing_result[0]
	_framing_velocity = framing_result[1]

	# 3. Calculate Orbit Position
	var ground_zoom: float = lerp(min_zoom, max_zoom, 0.5)
	var state_zoom: float = min_zoom
	if camera_is_airborne:
		state_zoom = max_zoom
	elif camera_is_moving:
		state_zoom = ground_zoom
	var target_distance: float = clamp(state_zoom + camera_distance_bias, min_zoom, max_zoom)
	var distance_result := _spring_float(camera_distance_current, _camera_distance_velocity, target_distance, camera_smoothness, delta)
	camera_distance_current = distance_result[0]
	_camera_distance_velocity = distance_result[1]

	var altitude_zoom: float = clamp(global_transform.origin.y * altitude_zoom_factor, 0.0, max_zoom - min_zoom)
	var effective_camera_distance: float = clamp(camera_distance_current + altitude_zoom, min_zoom, max_zoom)

	var cam_offset: Vector3 = Vector3(
		sin(cam_rot_y) * cos(cam_rot_x),
		sin(cam_rot_x),
		cos(cam_rot_y) * cos(cam_rot_x)
	) * effective_camera_distance

	# 4. Collision Check (Raycast)
	var desired_cam_pos: Vector3 = base_target_pos + cam_offset
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(base_target_pos, desired_cam_pos)
	query.exclude = [self]
	var hit: Dictionary = space_state.intersect_ray(query)

	var target_collision_distance := effective_camera_distance
	if hit and hit.has("position"):
		var hit_distance := base_target_pos.distance_to(hit.position)
		target_collision_distance = maxf(0.05, hit_distance - CAMERA_COLLISION_MARGIN)
		_camera_collision_hold_timer = CAMERA_COLLISION_HOLD_TIME
		if _camera_collision_distance <= 0.0:
			_camera_collision_distance = target_collision_distance
		else:
			_camera_collision_distance = minf(_camera_collision_distance, target_collision_distance)
	else:
		_camera_collision_hold_timer = maxf(0.0, _camera_collision_hold_timer - delta)
		if _camera_collision_hold_timer <= 0.0:
			_camera_collision_distance = move_toward(_camera_collision_distance, target_collision_distance, delta * CAMERA_COLLISION_RECOVERY_SPEED)

	var camera_direction := cam_offset.normalized()
	if camera_direction.length_squared() < 0.0001:
		camera_direction = Vector3.FORWARD
	desired_cam_pos = base_target_pos + camera_direction * _camera_collision_distance

	# 5. Apply Position and Rotation
	if camera:
		var position_result := _spring_vec3(camera.global_position, _camera_position_velocity, desired_cam_pos, camera_smoothness, delta)
		camera.global_position = position_result[0]
		_camera_position_velocity = position_result[1]
		
		# LOOK AT TARGET: Base Position + Dynamic Offset
		# This ensures the character is not always dead center
		var final_focus_point: Vector3 = base_target_pos + current_framing_offset
		var look_result := _spring_vec3(_camera_look_target, _camera_look_target_velocity, final_focus_point, camera_smoothness * 0.85, delta)
		_camera_look_target = look_result[0]
		_camera_look_target_velocity = look_result[1]
		camera.look_at(_camera_look_target, Vector3.UP)

func _send_state_to_server() -> void:
	if not root or not root.ws:
		return
	if root.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		root.ws.send_text(JSON.stringify({
			"type": "update_state",
			"player_id": player_id,
			"x": global_transform.origin.x,
			"y": global_transform.origin.y,
			"z": global_transform.origin.z,
			"rotation_y": mesh.rotation.y,
			"animation": current_animation
		}))

func set_animation_state(new_state: String):
	if is_local: return
	if new_state == current_animation: return
	current_animation = new_state
	_play_anim(new_state)

func _handle_animations(move_dir: Vector3) -> void:
	if not is_local: return
	if move_dir.length() > 0.1:
		current_animation = "running"
		_play_anim("running")
	else:
		current_animation = "idle"
		_play_anim("idle")
