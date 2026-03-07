extends RigidBody3D

signal picked_up

@export var can_be_picked: bool = true
@export var wiggle_radius: float = 0.15   # very small movement
@export var wiggle_speed: float = 4.0     # faster for jitter effect

var wiggle_angle: float = 0.0
var wiggle_center: Vector3
var is_held: bool = false
var network_authoritative: bool = false

func _ready() -> void:
	wiggle_center = global_transform.origin
	freeze = true
	add_to_group("pickup_items") # IMPORTANT

func pick():
	if not can_be_picked:
		return

	is_held = true
	emit_signal("picked_up", self)

func _physics_process(delta: float) -> void:
	if network_authoritative:
		return

	if is_held:
		# While held, keep the center at current position
		if get_parent():
			wiggle_center = global_transform.origin
		return

	# Small jitter/wiggle movement
	wiggle_angle += wiggle_speed * delta
	var x = wiggle_center.x + cos(wiggle_angle) * wiggle_radius
	var z = wiggle_center.z + sin(wiggle_angle) * wiggle_radius
	global_transform.origin.x = x
	global_transform.origin.z = z

func update_circle_center(new_center: Vector3) -> void:
	wiggle_center = new_center

func apply_network_state(target_pos: Vector3, target_rot_y: float, held: bool) -> void:
	network_authoritative = true
	is_held = held
	freeze = true

	global_position = global_position.lerp(target_pos, 0.5)
	var rot = global_rotation
	rot.y = lerp_angle(rot.y, target_rot_y, 0.5)
	global_rotation = rot

	if not held:
		wiggle_center = target_pos
