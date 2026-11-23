extends Node3D

@export_group("Circular Path")
@export var center: Vector3 = Vector3(0, 60, 0)
@export var radius: float = 25.0
@export var speed: float = -0.2
@export var rotation_offset_degrees: float = -90.0
## Use a shared wall-clock phase so every client renders the bus at the same
## point on the route. Local uptime made each client start at angle 0 when it
## loaded the scene, which desynced the bus and left remote riders floating.
@export var sync_to_match: bool = true

var _angle: float = 0.0
var _rotation_offset_rad: float = 0.0

func _ready() -> void:
	add_to_group("bus")
	_rotation_offset_rad = deg_to_rad(rotation_offset_degrees)
	_angle = _synced_angle() if _use_shared_clock() else 0.0
	_update_bus_transform(_angle)

func _process(delta: float) -> void:
	_angle = _synced_angle() if _use_shared_clock() else _angle + delta * speed
	_update_bus_transform(_angle)

func _use_shared_clock() -> bool:
	return sync_to_match and not is_zero_approx(speed)

func _synced_angle() -> float:
	# Wall-clock time is NTP-synced on most devices, so clients agree on the
	# phase. Wrap the time before multiplying to keep double precision tight.
	var period := TAU / absf(speed)
	return fposmod(Time.get_unix_time_from_system(), period) * speed

func _update_bus_transform(angle: float) -> void:
	var x = cos(angle) * radius
	var z = sin(angle) * radius
	global_position = center + Vector3(x, 0, z)
	global_rotation.y = -angle + _rotation_offset_rad
