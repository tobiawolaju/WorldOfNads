@tool
extends Node3D
## Observation Wheel / Millennium Wheel controller
## Handles seat rotation around the hub + support strut alignment tuning.
## Attach this to the central hub Node3D.

# --- SEATS ---
@export_group("Seats")
@export var seat1: Node3D
@export var seat2: Node3D
@export var seat3: Node3D
@export var seat4: Node3D
@export var seat5: Node3D
@export var seat6: Node3D
@export var seat7: Node3D
@export var seat8: Node3D

@export var radius: float = 10.0
@export var rotation_speed: float = 0.2  # radians/sec

var seats: Array[Node3D] = []
var seat_base_angles: Array[float] = []
var wheel_angle: float = 0.0

# --- SUPPORT STRUCTURES ---
@export_group("Support Structures")
@export var support_structures: Array[MeshInstance3D] = []

## Position offset applied to every support mesh, relative to its own base position.
@export var position_tuning: Vector3 = Vector3.ZERO:
	set(value):
		position_tuning = value
		_apply_support_tuning()

## Rotation tuning in degrees (converted to radians internally).
@export var rotation_tuning_degrees: Vector3 = Vector3.ZERO:
	set(value):
		rotation_tuning_degrees = value
		_apply_support_tuning()

var support_base_positions: Array[Vector3] = []
var support_base_rotations: Array[Vector3] = []
var _supports_initialized: bool = false


func _ready() -> void:
	seats = [seat1, seat2, seat3, seat4, seat5, seat6, seat7, seat8]
	var angle_step := TAU / seats.size()
	for i in seats.size():
		seat_base_angles.append(i * angle_step)
	_update_seats()

	_cache_support_base_transforms()
	_apply_support_tuning()


func _process(delta: float) -> void:
	# Seats only need to move during actual gameplay, not in the editor.
	if Engine.is_editor_hint():
		return
	wheel_angle += rotation_speed * delta
	_update_seats()


func _update_seats() -> void:
	for i in seats.size():
		var seat := seats[i]
		if seat == null:
			continue

		var current_angle := seat_base_angles[i] + wheel_angle
		var local_offset := Vector3(sin(current_angle) * radius, cos(current_angle) * radius, 0.0)

		# Use the hub's global transform so every seat traces the exact
		# same world-space circle, regardless of what it's nested under.
		seat.global_position = global_transform.origin + (global_transform.basis * local_offset)


func _cache_support_base_transforms() -> void:
	support_base_positions.clear()
	support_base_rotations.clear()
	for mesh in support_structures:
		if mesh == null:
			support_base_positions.append(Vector3.ZERO)
			support_base_rotations.append(Vector3.ZERO)
			continue
		support_base_positions.append(mesh.position)
		support_base_rotations.append(mesh.rotation)
	_supports_initialized = true


func _apply_support_tuning() -> void:
	# Guard: base transforms must be cached first, or every edit would
	# stack on top of the previous one instead of tuning from a fixed start.
	if not _supports_initialized:
		return

	var rot_rad := Vector3(
		deg_to_rad(rotation_tuning_degrees.x),
		deg_to_rad(rotation_tuning_degrees.y),
		deg_to_rad(rotation_tuning_degrees.z)
	)

	for i in support_structures.size():
		var mesh := support_structures[i]
		if mesh == null:
			continue
		mesh.position = support_base_positions[i] + position_tuning
		mesh.rotation = support_base_rotations[i] + rot_rad
