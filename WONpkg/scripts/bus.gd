extends CharacterBody3D

@export var point_a: Vector3 = Vector3(20, 12, 0)
@export var point_b: Vector3 = Vector3(-20, 12, 0)
@export var speed: float = 1.0
@export var arrive_distance: float = 0.5
@export var turn_speed: float = 3.0 # higher = faster rotation

var target: Vector3
var target_rotation_y: float

func _ready():
	# Initialize position and rotation
	global_position = point_a
	target = point_b
	target_rotation_y = 180.0

func _physics_process(delta):
	var direction = target - global_position
	var distance = direction.length()

	# Switch direction if close enough
	if distance <= arrive_distance:
		target = point_a if target == point_b else point_b
		target_rotation_y = 0.0 if target_rotation_y == 180.0 else 180.0

	# Move toward the target
	if distance > 0:
		velocity = direction.normalized() * speed
	else:
		velocity = Vector3.ZERO
	move_and_slide()

	# Smoothly rotate toward movement direction
	rotation.y = lerp_angle(
		rotation.y,
		deg_to_rad(target_rotation_y),
		delta * turn_speed
	)
