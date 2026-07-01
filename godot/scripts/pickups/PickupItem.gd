extends RigidBody3D

signal picked_up

@export var can_be_picked: bool = true
@export var wiggle_radius: float = 0.15
@export var wiggle_speed: float = 4.0
@export var mesh_offset_y: float = 0.07:
	set(value):
		mesh_offset_y = value
		if is_node_ready():
			_update_mesh_offset()

var wiggle_angle: float = 0.0
var wiggle_center: Vector3
var is_held: bool = false
var network_authoritative: bool = false

func _ready() -> void:
	wiggle_center = global_transform.origin
	freeze = true
	add_to_group("pickup_items")
	_update_mesh_offset()

func _update_mesh_offset() -> void:
	var mesh_node: MeshInstance3D
	for child in get_children():
		if child is MeshInstance3D:
			mesh_node = child
			break
	if mesh_node:
		mesh_node.position.y = mesh_offset_y

func pick():
	if not can_be_picked:
		return

	is_held = true
	emit_signal("picked_up", self)

var _wiggle_timer: float = 0.0
const WIGGLE_INTERVAL: float = 0.05

func _physics_process(delta: float) -> void:
	if network_authoritative:
		return

	if is_held:
		# While held, keep the center at current position
		if get_parent():
			wiggle_center = global_transform.origin
		return

	# Small jitter/wiggle movement - Optimized to run less often
	_wiggle_timer += delta
	if _wiggle_timer >= WIGGLE_INTERVAL:
		_wiggle_timer = 0.0
		wiggle_angle += wiggle_speed * WIGGLE_INTERVAL
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

	var lerp_weight := 0.85 if held else 0.5
	global_position = global_position.lerp(target_pos, lerp_weight)
	var rot = global_rotation
	rot.y = lerp_angle(rot.y, target_rot_y, lerp_weight)
	global_rotation = rot

	if not held:
		wiggle_center = target_pos
