# Player.gd
extends CharacterBody3D

# === CONSTANTS ===
const GRAVITY: float = 9.8
const JUMP_VELOCITY: float = 4.5
const SPEED: float = 4.5

# === EXPORTS ===
@onready var camera: Camera3D = get_node("../Camera3D")
@onready var name_label: Label3D = $Label3D
@onready var anim_run: AnimationPlayer = $running
@onready var anim_idle: AnimationPlayer = $idle
@onready var mesh: Skeleton3D = $Skeleton3D

@export var camera_distance: float = 4.0
@export var camera_smoothness: float = 8.0
@export var min_pitch: float = deg_to_rad(-40.0)
@export var max_pitch: float = deg_to_rad(60.0)
@export var min_zoom: float = 2.0
@export var max_zoom: float = 5.0

# === VARIABLES ===
var root: Node = null
var is_local: bool = false
var velocity_y: float = 0.0
var cam_rot_x: float = deg_to_rad(30)
var cam_rot_y: float = 0.0

var player_id: String = "" :
	set(new_id):
		player_id = new_id
		if name_label:
			name_label.text = new_id.substr(0, 8)

func _ready() -> void:
	camera_distance = clamp(camera_distance, min_zoom, max_zoom)
	_play_idle()

func _process(delta: float):
	name_label.text = player_id.substr(0, 8)

func _input(event: InputEvent) -> void:
	if not is_local:
		return

	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		cam_rot_y -= event.relative.x * 0.005
		cam_rot_x = clamp(cam_rot_x + event.relative.y * 0.005, min_pitch, max_pitch)

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera_distance = clamp(camera_distance - 0.5, min_zoom, max_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera_distance = clamp(camera_distance + 0.5, min_zoom, max_zoom)

func _physics_process(delta: float) -> void:
	if not is_local:
		return

	# === Handle Input ===
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("move_forward"): input_dir.y += 1
	if Input.is_action_pressed("move_back"): input_dir.y -= 1
	if Input.is_action_pressed("move_left"): input_dir.x -= 1
	if Input.is_action_pressed("move_right"): input_dir.x += 1
	input_dir = input_dir.normalized()

	# === Apply gravity & jump ===
	if not is_on_floor():
		velocity_y -= GRAVITY * delta
	else:
		velocity_y = 0
		if Input.is_action_just_pressed("jump"):
			velocity_y = JUMP_VELOCITY

	# === Calculate Movement ===
	var cam_basis = camera.global_transform.basis
	var forward = -cam_basis.z
	var right = cam_basis.x
	forward.y = 0.0
	right.y = 0.0
	forward = forward.normalized()
	right = right.normalized()

	var move_direction = (forward * input_dir.y + right * input_dir.x)
	velocity.x = move_direction.x * SPEED
	velocity.z = move_direction.z * SPEED
	velocity.y = velocity_y

	move_and_slide()

	# === Make mesh face direction of movement ===
	if move_direction.length() > 0.05:
		var target_yaw = atan2(move_direction.x, move_direction.z)
		mesh.rotation.y = lerp_angle(mesh.rotation.y, target_yaw, delta * 10.0)

	_update_camera(delta)
	_send_state_to_server()
	_handle_animations(move_direction)

func _update_camera(delta: float) -> void:
	var target_pos: Vector3 = global_transform.origin + Vector3(0, 1.5, 0)
	cam_rot_x = clamp(cam_rot_x, deg_to_rad(-35), deg_to_rad(60))

	var cam_target_offset: Vector3 = Vector3(
		sin(cam_rot_y) * cos(cam_rot_x),
		sin(cam_rot_x),
		cos(cam_rot_y) * cos(cam_rot_x)
	) * camera_distance

	var desired_cam_pos: Vector3 = target_pos + cam_target_offset

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(target_pos, desired_cam_pos)
	query.exclude = [self]
	var result = space_state.intersect_ray(query)

	if result and result.has("position"):
		desired_cam_pos = result.position

	camera.global_position = camera.global_position.lerp(desired_cam_pos, delta * camera_smoothness)
	camera.look_at(target_pos, Vector3.UP)

# --- NETWORK FUNCTION ---
func _send_state_to_server() -> void:
	if not root or not root.ws:
		return
	if root.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var data = {
			"type": "update_state",
			"player_id": player_id,
			"x": global_transform.origin.x,
			"y": global_transform.origin.y,
			"z": global_transform.origin.z,
			# This is the corrected line:
			"rotation_y": mesh.rotation.y
		}
		root.ws.send_text(JSON.stringify(data))

# === Animation Handlers ===
func _handle_animations(move_dir: Vector3) -> void:
	if move_dir.length() > 0.1:
		_play_running()
	else:
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
