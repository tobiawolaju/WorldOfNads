# NPCplayer.gd
extends CharacterBody3D

# --------------------------------------------------------
#          PLAYER / NPC IDENTIFICATION
# --------------------------------------------------------
var is_local: bool = false       # true = controlled by the user
var player_id: String = ""       # unique id (NPC_2, PLAYER_1...)
var camera: Node = null          # assigned only to local player

# --------------------------------------------------------
#          MOVEMENT SETTINGS (local only)
# --------------------------------------------------------
@export var speed: float = 6.0
@export var jump_force: float = 4.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


# --------------------------------------------------------
#          SYNC VARIABLES FOR NPC MODE
# --------------------------------------------------------
var target_position: Vector3 = Vector3.ZERO
var target_rotation: Vector3 = Vector3.ZERO
var lerp_speed := 6.0            # how fast NPCs interpolate

# --------------------------------------------------------
#          OPTIONAL ANIMATION (plug in your animator)
# --------------------------------------------------------
var animator: AnimationPlayer = null


func _ready():
	# Auto-detect animation player if exists
	if has_node("AnimationPlayer"):
		animator = $AnimationPlayer

	print("Spawned: ", player_id, " | local =", is_local)


# --------------------------------------------------------
#               LOCAL INPUT MOVEMENT
# --------------------------------------------------------
func _physics_process(delta):
	if is_local:
		_local_movement(delta)
	else:
		_npc_interpolation(delta)


# --------------------------------------------------------
#               LOCAL PLAYER MOVEMENT
# --------------------------------------------------------
func _local_movement(delta):
	var input_vector = Vector2.ZERO
	input_vector.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input_vector.y = Input.get_action_strength("move_backward") - Input.get_action_strength("move_forward")

	var direction = (transform.basis * Vector3(input_vector.x, 0, input_vector.y)).normalized()

	if direction.length() > 0:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = lerp(velocity.x, 0.0, 0.2)
		velocity.z = lerp(velocity.z, 0.0, 0.2)

	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_force

	move_and_slide()

	# Camera follows
	if camera:
		camera.global_position = global_position + Vector3(0, 1.6, 0)


# --------------------------------------------------------
#               NPC AUTO-SMOOTH MOVEMENT
# --------------------------------------------------------
func _npc_interpolation(delta):
	# If no remote data yet, do nothing
	if target_position == Vector3.ZERO:
		return

	# Smoothly move NPCs
	global_position = global_position.lerp(target_position, delta * lerp_speed)

	# Smooth rotation
	rotation = rotation.lerp(target_rotation, delta * lerp_speed)


# --------------------------------------------------------
#               REMOTE UPDATE (USED BY SERVER)
# --------------------------------------------------------
func apply_remote_update(pos: Vector3, rot: Vector3):
	target_position = pos
	target_rotation = rot

	# Optional: update NPC animation state
	if animator:
		animator.play("Run")
