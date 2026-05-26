extends CharacterBody3D

const GRAVITY: float = 9.8
const JUMP_VELOCITY: float = 4.5
const SPEED: float = 4.5

# --- GAMEPAD SETTINGS ---
var gamepad_index := 0
const DEADZONE := 0.12

# --- AFK SETTINGS ---
@export_group("AFK Settings")
@export var afk_radius := 5.0      
@export var afk_speed := 2.0       
@export var afk_wait_time := 2.0   

# --- CAMERA SETTINGS ---
@export_group("Camera Settings")
@export var camera_distance: float = 4.0
@export var camera_smoothness: float = 8.0
@export var min_pitch: float = deg_to_rad(-40.0)
@export var max_pitch: float = deg_to_rad(60.0)
@export var min_zoom: float = 2.0
@export var max_zoom: float = 10.0
@export var altitude_zoom_factor: float = 5

# --- DYNAMIC CAMERA SETTINGS (NEW) ---
@export_group("Dynamic Camera")
@export var enable_dynamic_framing: bool = true
@export var drift_intensity: float = 0.5     # How much it floats when idle
@export var look_ahead_factor: float = 1.0   # How much it shifts when running

@onready var camera: Camera3D = get_node("../Camera3D")
@onready var name_label: Label3D = $Label3D
@onready var anim_run: AnimationPlayer = $running
@onready var anim_idle: AnimationPlayer = $idle
@onready var mesh: Skeleton3D = $Skeleton3D

var root: Node = null
var is_local: bool = false
var velocity_y: float = 0.0
var cam_rot_x: float = deg_to_rad(30)
var cam_rot_y: float = 0.0
var current_animation: String = "idle"

# Internal AFK State
var afk_center_pos := Vector3.ZERO
var afk_target_pos := Vector3.ZERO
var afk_timer := 0.0

# Dynamic Camera State
var cam_noise = FastNoiseLite.new()
var cam_noise_time: float = 0.0
var current_framing_offset: Vector3 = Vector3.ZERO
var active_touches: int = 0

var player_id: String = "" :
	set(new_id):
		player_id = new_id
		if name_label:
			name_label.text = new_id.substr(0, 8)

func _ready() -> void:
	camera_distance = clamp(camera_distance, min_zoom, max_zoom)
	_play_idle()
	
	# Initialize AFK center
	afk_center_pos = global_position
	afk_target_pos = global_position
	
	# Setup Noise for camera drift
	cam_noise.seed = randi()
	cam_noise.frequency = 0.5 # Lower = slower drift

func _process(_delta: float):
	if name_label:
		name_label.text = player_id.substr(0, 8)

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
			camera_distance = clamp(camera_distance - 0.5, min_zoom, max_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera_distance = clamp(camera_distance + 0.5, min_zoom, max_zoom)

func _physics_process(delta: float) -> void:
	if not is_local:
		return

	# 1. GATHER INPUT
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("move_forward"): input_dir.y += 1
	if Input.is_action_pressed("move_back"): input_dir.y -= 1
	if Input.is_action_pressed("move_left"): input_dir.x -= 1
	if Input.is_action_pressed("move_right"): input_dir.x += 1

	var lx := Input.get_joy_axis(gamepad_index, JOY_AXIS_LEFT_X)
	var ly := Input.get_joy_axis(gamepad_index, JOY_AXIS_LEFT_Y)

	if abs(lx) > DEADZONE: input_dir.x += lx
	if abs(ly) > DEADZONE: input_dir.y -= ly
	input_dir = input_dir.normalized()
	
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

	if move_direction.length() > 0.05:
		var target_yaw := atan2(move_direction.x, move_direction.z)
		mesh.rotation.y = lerp_angle(mesh.rotation.y, target_yaw, delta * 10.0)

	_handle_camera_gamepad(delta)
	_update_camera(delta)
	_handle_animations(move_direction)
	_send_state_to_server()

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
	var base_target_pos: Vector3 = global_transform.origin + Vector3(0, 1.5, 0)
	cam_rot_x = clamp(cam_rot_x, min_pitch, max_pitch)

	# 2. Dynamic Framing Calculation
	var target_look_offset = Vector3.ZERO
	
	if enable_dynamic_framing:
		cam_noise_time += delta
		
		# A. Idle Drift (Noise) - Makes camera float slightly when still
		var drift_x = cam_noise.get_noise_2d(cam_noise_time, 0) * drift_intensity
		var drift_y = cam_noise.get_noise_2d(0, cam_noise_time) * (drift_intensity * 0.5)
		
		# B. Look Ahead (Velocity) - Shifts camera slightly in direction of movement
		# We project velocity onto camera plane to know "left/right" relative to screen
		var vel_lead = Vector3.ZERO
		if velocity.length() > 0.1:
			vel_lead = velocity.normalized() * look_ahead_factor
			# Dampen Y axis lead (we usually don't want to look up/down based on jump)
			vel_lead.y *= 0.2 
			
		target_look_offset = Vector3(drift_x, drift_y, 0) + vel_lead

	# Smoothly interpolate the offset so it doesn't jitter
	current_framing_offset = current_framing_offset.lerp(target_look_offset, delta * 2.0)

	# 3. Calculate Orbit Position
	var altitude_zoom = clamp(global_transform.origin.y * altitude_zoom_factor, 0.0, max_zoom - min_zoom)
	var effective_camera_distance = clamp(camera_distance + altitude_zoom, min_zoom, max_zoom)

	var cam_offset: Vector3 = Vector3(
		sin(cam_rot_y) * cos(cam_rot_x),
		sin(cam_rot_x),
		cos(cam_rot_y) * cos(cam_rot_x)
	) * effective_camera_distance

	# 4. Collision Check (Raycast)
	var desired_cam_pos: Vector3 = base_target_pos + cam_offset
	var space_state = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(base_target_pos, desired_cam_pos)
	query.exclude = [self]
	var hit = space_state.intersect_ray(query)

	if hit and hit.has("position"):
		desired_cam_pos = hit.position

	# 5. Apply Position and Rotation
	if camera:
		camera.global_position = camera.global_position.lerp(desired_cam_pos, delta * camera_smoothness)
		
		# LOOK AT TARGET: Base Position + Dynamic Offset
		# This ensures the character is not always dead center
		var final_focus_point = base_target_pos + current_framing_offset
		camera.look_at(final_focus_point, Vector3.UP)

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
	if new_state == "running":
		_play_running()
	else:
		_play_idle()

func _handle_animations(move_dir: Vector3) -> void:
	if not is_local: return
	if move_dir.length() > 0.1:
		current_animation = "running"
		_play_running()
	else:
		current_animation = "idle"
		_play_idle()

func _play_running() -> void:
	if anim_idle.is_playing():
		anim_idle.stop()
	if not anim_run.is_playing():
		anim_run.play("running")

func _play_idle() -> void:
	if anim_run.is_playing():
		anim_run.stop()
	if not anim_idle.is_playing():
		anim_idle.play("idle")
