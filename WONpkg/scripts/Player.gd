# Player.gd
extends CharacterBody3D

# === CONSTANTS ===
const GRAVITY: float = 9.8
const JUMP_VELOCITY: float = 4.5
const SPEED: float = 4.5

# === NODES ===
# (Adjust paths based on your actual scene structure)
@onready var camera: Camera3D = get_node_or_null("../Camera3D") 
@onready var name_label: Label3D = $Label3D
@onready var anim_run: AnimationPlayer = $running
@onready var anim_idle: AnimationPlayer = $idle
@onready var mesh: Skeleton3D = $Skeleton3D

# === NETWORK VARS ===
var world_manager: Node = null
var is_local: bool = false
var short_id: int = 0
var current_anim_byte: int = 0 # 0=Idle, 1=Run, 2=Jump

# === INTERPOLATION (REMOTE ONLY) ===
var target_pos: Vector3
var target_rot: float

# === LOCAL CAMERA VARS ===
var cam_rot_x: float = 0.0
var cam_rot_y: float = 0.0
var camera_distance: float = 4.0

func setup(_id: int, _local: bool, _wm: Node):
	short_id = _id
	is_local = _local
	world_manager = _wm
	target_pos = global_position
	
	if name_label:
		name_label.text = "ID: " + str(short_id)

func _ready():
	_play_idle()

func _input(event: InputEvent) -> void:
	if not is_local or not camera: return

	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		cam_rot_y -= event.relative.x * 0.005
		cam_rot_x = clamp(cam_rot_x + event.relative.y * 0.005, deg_to_rad(-40), deg_to_rad(60))

func _physics_process(delta: float) -> void:
	if is_local:
		_handle_local_movement(delta)
		_send_binary_state() # Send data to server
	else:
		_handle_remote_interpolation(delta)

# ---------------------------------------------------------
# LOCAL PLAYER LOGIC
# ---------------------------------------------------------
func _handle_local_movement(delta: float):
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY

	var input_dir = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var direction = Vector3.ZERO

	if camera:
		var cam_basis = camera.global_transform.basis
		var forward = -cam_basis.z
		forward.y = 0
		var right = cam_basis.x
		right.y = 0
		direction = (forward.normalized() * input_dir.y + right.normalized() * input_dir.x)

	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
		# Face movement
		var target_ang = atan2(direction.x, direction.z)
		mesh.rotation.y = lerp_angle(mesh.rotation.y, target_ang, delta * 10.0)
		_play_running()
		current_anim_byte = 1
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		_play_idle()
		current_anim_byte = 0
	
	move_and_slide()
	_update_camera_pos(delta)

func _update_camera_pos(delta):
	if not camera: return
	var target = global_position + Vector3(0, 1.5, 0)
	var offset = Vector3(
		sin(cam_rot_y) * cos(cam_rot_x),
		sin(cam_rot_x),
		cos(cam_rot_y) * cos(cam_rot_x)
	) * camera_distance
	camera.global_position = camera.global_position.lerp(target + offset, delta * 8.0)
	camera.look_at(target)

# ---------------------------------------------------------
# REMOTE PLAYER LOGIC
# ---------------------------------------------------------
func _handle_remote_interpolation(delta: float):
	# Smoothly move remote player to the position received from server
	global_position = global_position.lerp(target_pos, delta * 10.0)
	mesh.rotation.y = lerp_angle(mesh.rotation.y, target_rot, delta * 10.0)

# Called by WorldManager when it receives a packet
func set_anim_byte(val: int):
	if is_local: return
	if val == 0: _play_idle()
	elif val == 1: _play_running()

# ---------------------------------------------------------
# NETWORKING
# ---------------------------------------------------------
func _send_binary_state():
	if world_manager.ws.get_ready_state() != WebSocketPeer.STATE_OPEN: return
	
	# Packet Format: [Type 1] [X] [Y] [Z] [Rot] [Anim]
	var buf = StreamPeerBuffer.new()
	buf.put_u8(1) # Type 1: Update
	buf.put_float(global_position.x)
	buf.put_float(global_position.y)
	buf.put_float(global_position.z)
	buf.put_float(mesh.rotation.y)
	buf.put_u8(current_anim_byte)
	
	world_manager.ws.send(buf.data_array)

# ---------------------------------------------------------
# ANIMATIONS
# ---------------------------------------------------------
func _play_running():
	if anim_idle.is_playing(): anim_idle.stop()
	if not anim_run.is_playing(): anim_run.play("running")

func _play_idle():
	if anim_run.is_playing(): anim_run.stop()
	if not anim_idle.is_playing(): anim_idle.play("idle")
