extends Node3D

@export_group("Circular Path")
@export var center: Vector3 = Vector3(0, 60, 0)
@export var radius: float = 25.0
@export var speed: float = -0.2
@export var rotation_offset_degrees: float = -90.0

var _angle: float = 0.0

func _ready() -> void:
	add_to_group("bus")
	_update_bus_transform(0.0)

func _process(delta: float) -> void:
	_angle += delta * speed
	_update_bus_transform(_angle)

func _update_bus_transform(angle: float) -> void:
	var x = cos(angle) * radius
	var z = sin(angle) * radius
	global_position = center + Vector3(x, 0, z)
	global_rotation.y = -angle + deg_to_rad(rotation_offset_degrees)
