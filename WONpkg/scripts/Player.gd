extends CharacterBody3D

# --- CONSTANTS ---
const GRAVITY: float = 9.8
const JUMP_VELOCITY: float = 4.5
const SPEED: float = 4.5
const DEADZONE := 0.12

# --- INPUT VARIABLES ---
var gamepad_index := 0

# --- PICKUP VARIABLES ---
var held_object: RigidBody3D = null
@export var hold_distance: float = 0.5
@export var hold_height: float = 1.5

# --- CAMERA & ZOOM SETTINGS ---
@export var camera_distance: float = 4.0
@export var camera_smoothness: float = 8.0
@export var min_pitch: float = deg_to_rad(-40.0)
@export var max_pitch: float = deg_to_rad(60.0)
@export var min_zoom: float = 2.0
@export var max_zoom: float = 10.0
@export var altitude_zoom_factor: float = 5

# --- NODE REFERENCES ---
@onready var camera: Camera3D = get_node("../Camera3D")

# [CHANGED] Replaced RayCast3D with Area3D
@onready var pickup_area: Area3D = $Area3D 

@onready var name_label: Label3D = $Label3D
@onready var anim_run: AnimationPlayer = $running
@onready var anim_idle: AnimationPlayer = $idle
@onready var mesh: Skeleton3D = $Skeleton3D

# --- STATE VARIABLES ---
var root: Node = null
var is_local: bool = false
var velocity_y: float = 0.0
var cam_rot_x: float = deg_to_rad(30)
var cam_rot_y: float = 0.0
var current_animation: String = "idle"

var player_id: String = "" :
	set(new_id):
		player_id = new_id
		if name_label:
			name_label.text = new_id.substr(0, 8)

func _ready() -> void:
	camera_distance = clamp(camera_distance, min_zoom, max_zoom)
	_play_idle()
	
	if not pickup_area:
		print("ERROR: $Area3D node not found! Please add an Area3D with a CollisionShape to the player.")

func _process(delta: float):
	name_label.text = player_id.substr(0, 8)
	
	# Handle holding the object (Smoothly move it to front of camera)
	if held_object:
		var target_pos = global_position + (global_transform.basis.z * -hold_distance)
		target_pos.y += hold_height * 0.5 
		held_object.global_position = held_object.global_position.lerp(target_pos, 10.0 * delta)
		held_object.global_rotation.y = lerp_angle(held_object.global_rotation.y, rotation.y, 10.0 * delta)

func _input(event: InputEvent) -> void:
	if not is_local:
		return

	# --- 1. MOUSE & TOUCH CAMERA CONTROLS ---
	var viewport = get_viewport().get_visible_rect()
	var size = viewport.size
	var portrait = size.y > size.x

	# Avoid moving camera if touching the virtual joystick area
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if portrait:
			if event.position.y > size.y * 0.5:
				return
		else:
			if event.position.x < size.x * 0.5:
				return

	# Touch Drag
	if event is InputEventScreenDrag:
		cam_rot_y -= event.relative.x * 0.0045
		cam_rot_x = clamp(cam_rot_x + event.relative.y * 0.0045, min_pitch, max_pitch)

	# Mouse Drag
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		cam_rot_y -= event.relative.x * 0.005
		cam_rot_x = clamp(cam_rot_x + event.relative.y * 0.005, min_pitch, max_pitch)

	# Mouse Wheel Zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera_distance = clamp(camera_distance - 0.5, min_zoom, max_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera_distance = clamp(camera_distance + 0.5, min_zoom, max_zoom)

	# --- 2. PICKUP CONTROLS ---
	if event.is_action_pressed("pickup"):
		if held_object == null:
			_try_pickup()
		else:
			_drop_object()

func _physics_process(delta: float) -> void:
	if not is_local:
		return

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

	if not is_on_floor():
		velocity_y -= GRAVITY * delta
	else:
		velocity_y = 0
		if Input.is_action_just_pressed("jump") or Input.is_joy_button_pressed(gamepad_index, JOY_BUTTON_A):
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

	velocity.x = move_direction.x * SPEED
	velocity.z = move_direction.z * SPEED
	velocity.y = velocity_y
	move_and_slide()

	if move_direction.length() > 0.05:
		var target_yaw := atan2(move_direction.x, move_direction.z)
		mesh.rotation.y = lerp_angle(mesh.rotation.y, target_yaw, delta * 10.0)

	_handle_camera_gamepad(delta)
	_update_camera(delta)
	_handle_animations(move_direction)
	_send_state_to_server()

# --- PICKUP LOGIC (USING AREA3D) ---
func _try_pickup():
	if not pickup_area:
		return

	# 1. Get all overlapping bodies in the area
	var bodies = pickup_area.get_overlapping_bodies()
	var best_target: RigidBody3D = null
	var shortest_dist: float = 999.0

	# 2. Iterate to find the closest valid object
	for body in bodies:
		# Must be a RigidBody, and cannot be the player itself
		if body is RigidBody3D and body != self:
			
			# Optional: Ignore ground
			if "GroundMesh" in body.name:
				continue
			
			var dist = global_position.distance_to(body.global_position)
			if dist < shortest_dist:
				shortest_dist = dist
				best_target = body
	
	# 3. If we found a target, pick it up
	if best_target:
		held_object = best_target
		held_object.freeze = true
		
		# Turn off collisions with player so it doesn't push you
		held_object.set_collision_mask_value(1, false)
		held_object.set_collision_layer_value(1, false)
		print("Picked up: ", held_object.name)
	else:
		print("Nothing to pick up nearby.")

func _drop_object():
	if not held_object:
		return
	
	held_object.freeze = false
	held_object.set_collision_mask_value(1, true)
	held_object.set_collision_layer_value(1, true)
	
	# Throw it slightly
	var throw_dir = -camera.global_transform.basis.z
	held_object.apply_central_impulse(throw_dir * 5.0)
	
	held_object = null

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

	var altitude_zoom = clamp(global_transform.origin.y * altitude_zoom_factor, 0.0, max_zoom - min_zoom)
	var effective_camera_distance = clamp(camera_distance + altitude_zoom, min_zoom, max_zoom)

	var cam_offset: Vector3 = Vector3(
		sin(cam_rot_y) * cos(cam_rot_x),
		sin(cam_rot_x),
		cos(cam_rot_y) * cos(cam_rot_x)
	) * effective_camera_distance

	var desired_pos: Vector3 = target_pos + cam_offset

	var space_state = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(target_pos, desired_pos)
	query.exclude = [self]
	var hit = space_state.intersect_ray(query)

	if hit and hit.has("position"):
		desired_pos = hit.position

	camera.global_position = camera.global_position.lerp(desired_pos, delta * camera_smoothness)
	camera.look_at(target_pos, Vector3.UP)

# --- ANIMATION & NETWORK ---
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
