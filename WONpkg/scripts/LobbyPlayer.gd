extends CharacterBody3D

const GRAVITY = 9.8
const JUMP_VELOCITY = 4.5
const SPEED = 4.5

# --- NEW AFK VARIABLES ---
@export var afk_radius := 5.0      # How far they can wander from where they stopped
@export var afk_speed := 2.0       # Slower speed for wandering
@export var afk_wait_time := 2.0   # How long to wait before picking a new spot

@export var camera_distance := 4.0
@export var camera_smoothness := 8.0
@export var min_pitch := deg_to_rad(-40)
@export var max_pitch := deg_to_rad(60)
@export var min_zoom := 2.0
@export var max_zoom := 3.5

@onready var name_label: Label3D = $Label3D
@onready var anim_run: AnimationPlayer = $running
@onready var anim_idle: AnimationPlayer = $idle
@onready var mesh: Skeleton3D = $Skeleton3D

var camera: Camera3D
var is_local := false
var player_id := ""
var velocity_y := 0.0
var cam_rot_x := deg_to_rad(30)
var cam_rot_y := 0.0
var current_animation := "idle"

# Internal AFK State
var afk_center_pos := Vector3.ZERO
var afk_target_pos := Vector3.ZERO
var afk_timer := 0.0
var is_wandering := false

func _ready():
	if name_label:
		name_label.text = player_id
	_play_idle()
	
	# Initialize AFK center
	afk_center_pos = global_position
	afk_target_pos = global_position

func _input(event):
	if not is_local or camera == null:
		return

	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		cam_rot_y -= event.relative.x * 0.005
		cam_rot_x = clamp(cam_rot_x + event.relative.y * 0.005, min_pitch, max_pitch)

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera_distance = clamp(camera_distance - 0.5, min_zoom, max_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera_distance = clamp(camera_distance + 0.5, min_zoom, max_zoom)


func _physics_process(delta):
	if not is_local:
		return

	# 1. Check for Player Input
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("move_forward"): input_dir.y += 1
	if Input.is_action_pressed("move_back"): input_dir.y -= 1
	if Input.is_action_pressed("move_left"): input_dir.x -= 1
	if Input.is_action_pressed("move_right"): input_dir.x += 1
	input_dir = input_dir.normalized()
	
	var move_dir = Vector3.ZERO
	var current_speed = SPEED

	# 2. Logic: If Player is Inputting vs AFK
	if input_dir != Vector2.ZERO or Input.is_action_just_pressed("jump"):
		# PLAYER IS CONTROLLING
		is_wandering = false
		afk_center_pos = global_position # Reset the "center" to where we currently are
		afk_timer = 0.0 # Reset timer
		
		# Calculate Move Direction based on Camera
		var cam_basis = camera.global_transform.basis if camera else Basis()
		var forward = -cam_basis.z
		var right = cam_basis.x
		forward.y = 0
		right.y = 0
		forward = forward.normalized()
		right = right.normalized()
		
		move_dir = forward * input_dir.y + right * input_dir.x
		
	else:
		# PLAYER IS NOT INPUTTING (AFK MODE)
		move_dir = _get_afk_movement_direction(delta)
		current_speed = afk_speed # Use slower speed for wandering

	# 3. Apply Gravity
	if not is_on_floor():
		velocity_y -= GRAVITY * delta
	else:
		velocity_y = 0
		if Input.is_action_just_pressed("jump"):
			velocity_y = JUMP_VELOCITY

	# 4. Apply Velocity
	velocity.x = move_dir.x * current_speed
	velocity.z = move_dir.z * current_speed
	velocity.y = velocity_y

	move_and_slide()

	# 5. Rotate Character to face movement
	if move_dir.length() > 0.05:
		mesh.rotation.y = lerp_angle(mesh.rotation.y, atan2(move_dir.x, move_dir.z), delta * 10)

	_update_camera(delta)
	_handle_animations(move_dir)

# --- NEW FUNCTION: Calculates random wandering ---
func _get_afk_movement_direction(delta) -> Vector3:
	afk_timer -= delta
	
	# If we reached the target OR timer ran out, pick a new spot
	var dist_to_target = global_position.distance_to(afk_target_pos)
	
	if dist_to_target < 0.5 or afk_timer <= 0:
		# Pick a new random angle and distance
		var random_angle = randf() * TAU # TAU is 2*PI (360 degrees)
		var random_dist = randf() * afk_radius
		
		# Calculate offset from the CENTER position (where player stopped)
		var offset = Vector3(sin(random_angle), 0, cos(random_angle)) * random_dist
		afk_target_pos = afk_center_pos + offset
		
		# Reset wait timer (wait a bit before moving to next spot or move immediately)
		afk_timer = afk_wait_time + randf() * 2.0 # Wait 2-4 seconds between moves
		
	# If we are supposed to be waiting (timer is high), don't move
	if afk_timer > 2.0: 
		return Vector3.ZERO
		
	# Otherwise, move towards target
	var direction = (afk_target_pos - global_position).normalized()
	return direction


func _update_camera(delta):
	if camera == null:
		return

	var target_pos = global_transform.origin + Vector3(0, 1.5, 0)
	var cam_offset = Vector3(
		sin(cam_rot_y) * cos(cam_rot_x),
		sin(cam_rot_x),
		cos(cam_rot_y) * cos(cam_rot_x)
	) * camera_distance

	var desired = target_pos + cam_offset

	camera.global_position = camera.global_position.lerp(desired, delta * camera_smoothness)
	camera.look_at(target_pos, Vector3.UP)


func _handle_animations(move_dir):
	if move_dir.length() > 0.1:
		_play_running()
	else:
		_play_idle()


func _play_running():
	if anim_idle.is_playing():
		anim_idle.stop()
	if not anim_run.is_playing():
		anim_run.play("running")


func _play_idle():
	if anim_run.is_playing():
		anim_run.stop()
	if not anim_idle.is_playing():
		anim_idle.play("idle")
