extends RigidBody3D

@export var can_be_picked: bool = true
@export var circle_radius: float = 2.0
@export var circle_speed: float = 1.0

var circle_angle: float = 0.0
var circle_center: Vector3
var is_held: bool = false

func _ready() -> void:
	circle_center = global_transform.origin

func _physics_process(delta: float) -> void:
	if is_held:
		# While held, move the circle center to match player position
		if get_parent(): # assuming player is parent temporarily or passed reference
			circle_center = global_transform.origin
		return

	# Update circular movement
	circle_angle += circle_speed * delta
	var x = circle_center.x + cos(circle_angle) * circle_radius
	var z = circle_center.z + sin(circle_angle) * circle_radius
	global_transform.origin.x = x
	global_transform.origin.z = z

func update_circle_center(new_center: Vector3) -> void:
	circle_center = new_center
