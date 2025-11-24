extends CharacterBody3D

@export var point_a: Vector3 = Vector3(20, 12, 0)
@export var point_b: Vector3 = Vector3(-20, 12, 0)
@export var speed: float = 1.0
@export var arrive_distance: float = 0.5
@export var turn_speed: float = 1.0 # higher = faster rotation

var target: Vector3
var target_rotation_y: float

func _ready():
	target = point_b
	target_rotation_y = 180.0 # starting direction

func _physics_process(delta):
	var direction = target - global_position

	# switch direction if close enough
	if direction.length() <= arrive_distance:
		target = point_a if target == point_b else point_b
		
		# flip rotation target (0 ↔ 180 degrees)
		target_rotation_y = 0.0 if target_rotation_y == 180.0 else 180.0

	# movement
	velocity = direction.normalized() * speed
	move_and_slide()

	# smooth turning
	rotation.y = lerp_angle(
		rotation.y,
		deg_to_rad(target_rotation_y),
		delta * turn_speed
	)
