extends CharacterBody3D

# ===========================================================
# CONSTANTS
# ===========================================================
const GRAVITY := 9.8
const JUMP_VELOCITY := 4.5
const SPEED := 4.5

const BUS_ZOOM_MULTIPLIER := 3.0
const NORMAL_ZOOM_MULTIPLIER := 1.0

# ===========================================================
# NODES
# ===========================================================
@onready var camera: Camera3D = get_node("../Camera3D")
@onready var name_label: Label3D = $Label3D
@onready var anim_run: AnimationPlayer = $running
@onready var anim_idle: AnimationPlayer = $idle
@onready var mesh: Skeleton3D = $Skeleton3D

# ===========================================================
# BUS REFS
# ===========================================================
@export var bus_node: Node3D
@export var bus_move_speed: float = 2.0
@export var bus_move_direction: Vector3 = Vector3(0, 0, -1)
@export var bus_offset: Vector3 = Vector3(0, 1.5, 0)

@export var bus_auto_stop_distance: float = 18000.0
@export var bus_continue_after_exit: bool = true

var bus_has_stopped := false
var total_bus_distance := 0.0

# ===========================================================
# CAMERA SETTINGS
# ===========================================================
@export var camera_distance := 4.0
@export var camera_smoothness := 8.0
@export var min_pitch := deg_to_rad(-40.0)
@export var max_pitch := deg_to_rad(60.0)
@export var min_zoom := 2.0
@export var max_zoom := 5.0

# ===========================================================
# STATE
# ===========================================================
var root: Node
var is_local: bool = false
var on_bus: bool = true
var exited_bus := false
var velocity_y := 0.0
var cam_rot_x := deg_to_rad(30)
var cam_rot_y := 0.0
var current_animation := "idle"

# ===========================================================
# PLAYER ID
# ===========================================================
var player_id: String = ""

func set_player_id(new_id: String):
	player_id = new_id
	if name_label:
		name_label.text = new_id.substr(0, 8)

# ===========================================================
# READY
# ===========================================================
func _ready():
	_play_idle()

	# --- CRITICAL: LOCAL PLAYER NEVER FALLS FROM BUS ---
	if is_local and on_bus and bus_node:
		_lock_to_bus()

	camera_distance = clamp(camera_distance, min_zoom, max_zoom)

# ===========================================================
# PROCESS
# ===========================================================
func _process(delta):
	name_label.text = player_id.substr(0, 8)

	if is_local:
		if on_bus:
			_move_bus(delta)
			_update_camera_on_bus(delta)
		else:
			_update_camera(delta)

# ===========================================================
# MAKE PLAYER STICK
# ===========================================================
func _lock_to_bus():
	if not bus_node:
		return
	global_transform.origin = bus_node.global_transform.origin + bus_offset
	velocity = Vector3.ZERO

# ===========================================================
# BUS MOVEMENT (ONLY LOCAL HOST)
# ===========================================================
func _move_bus(delta):
	if not bus_node or bus_has_stopped:
		return

	# Move bus
	var step = bus_move_direction.normalized() * bus_move_speed * delta
	bus_node.global_transform.origin += step
	total_bus_distance += step.length()

	# Lock player to bus
	if on_bus:
		_lock_to_bus()

	if total_bus_distance >= bus_auto_stop_distance:
		bus_has_stopped = true
		print("🚌 BUS STOPPED")

# ===========================================================
# INPUT
# ===========================================================
func _input(event):
	if not is_local:
		return

	# Camera look
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		cam_rot_y -= event.relative.x * 0.005
		cam_rot_x = clamp(cam_rot_x + event.relative.y * 0.005, min_pitch, max_pitch)

	# Zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera_distance = clamp(camera_distance - 0.5, min_zoom, max_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera_distance = clamp(camera_distance + 0.5, min_zoom, max_zoom)

	# FIRST INPUT = EXIT BUS
	if not exited_bus and event.is_pressed():
		exit_bus()

# ===========================================================
# PHYSICS OFF BUS
# ===========================================================
func _physics_process(delta):
	# Remote players never simulate physics
	if not is_local:
		return

	# On bus = NO physics
	if on_bus:
		_lock_to_bus()
		return

	# NORMAL PLAYER MOVEMENT
	var input_dir := Vector2(
		(int(Input.is_action_pressed("move_right")) - int(Input.is_action_pressed("move_left"))),
		(int(Input.is_action_pressed("move_forward")) - int(Input.is_action_pressed("move_back")))
	).normalized()

	# gravity
	if not is_on_floor():
		velocity_y -= GRAVITY * delta
	else:
		if Input.is_action_just_pressed("jump"):
			velocity_y = JUMP_VELOCITY

	var cam_basis = camera.global_transform.basis
	var fwd = -cam_basis.z
	var right = cam_basis.x
	fwd.y = 0
	right.y = 0

	var move_vec = fwd.normalized() * input_dir.y + right.normalized() * input_dir.x

	velocity.x = move_vec.x * SPEED
	velocity.z = move_vec.z * SPEED
	velocity.y = velocity_y

	move_and_slide()

	# Rotate character model
	if move_vec.length() > 0.05:
		mesh.rotation.y = lerp_angle(mesh.rotation.y, atan2(move_vec.x, move_vec.z), delta * 10.0)

	_handle_animations(move_vec)
	_send_state_to_server()

# ===========================================================
# EXIT BUS
# ===========================================================
func exit_bus():
	if exited_bus:
		return

	print("🚪 Player EXITED BUS")
	exited_bus = true
	on_bus = false
	velocity = Vector3.ZERO

# ===========================================================
# CAMERA FOLLOW BUS
# ===========================================================
func _update_camera_on_bus(delta):
	if not bus_node:
		return

	var target = bus_node.global_transform.origin + bus_offset
	var zoom_dist = camera_distance * BUS_ZOOM_MULTIPLIER

	var offset = Vector3(
		sin(cam_rot_y) * cos(cam_rot_x),
		sin(cam_rot_x),
		cos(cam_rot_y) * cos(cam_rot_x)
	) * zoom_dist

	var desired = target + offset

	camera.global_position = camera.global_position.lerp(desired, delta * camera_smoothness)
	camera.look_at(target, Vector3.UP)

# ===========================================================
# CAMERA NORMAL
# ===========================================================
func _update_camera(delta):
	var target = global_transform.origin + Vector3(0, 1.5, 0)
	cam_rot_x = clamp(cam_rot_x, deg_to_rad(-35), deg_to_rad(60))

	var offset = Vector3(
		sin(cam_rot_y) * cos(cam_rot_x),
		sin(cam_rot_x),
		cos(cam_rot_y) * cos(cam_rot_x)
	) * camera_distance

	var desired = target + offset

	var q := PhysicsRayQueryParameters3D.create(target, desired)
	q.exclude = [self]

	var hit = get_world_3d().direct_space_state.intersect_ray(q)
	if hit and hit.has("position"):
		desired = hit.position

	camera.global_position = camera.global_position.lerp(desired, delta * camera_smoothness)
	camera.look_at(target, Vector3.UP)

# ===========================================================
# SEND NETWORK STATE
# ===========================================================
func _send_state_to_server():
	if not root or not root.ws:
		return
	if root.ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	root.ws.send_text(JSON.stringify({
		"type": "update_state",
		"player_id": player_id,
		"x": global_transform.origin.x,
		"y": global_transform.origin.y,
		"z": global_transform.origin.z,
		"rotation_y": mesh.rotation.y,
		"animation": current_animation
	}))

# ===========================================================
# ANIMATIONS
# ===========================================================
func set_animation_state(state: String):
	if is_local:
		return
	if state == current_animation:
		return

	current_animation = state
	if state == "running":
		_play_running()
	else:
		_play_idle()

func _handle_animations(move: Vector3):
	if not is_local:
		return
	if move.length() > 0.1:
		current_animation = "running"
		_play_running()
	else:
		current_animation = "idle"
		_play_idle()

func _play_running():
	if anim_idle.is_playing():
		anim_idle.stop()
	anim_run.play("running")

func _play_idle():
	if anim_run.is_playing():
		anim_run.stop()
	anim_idle.play("idle")
