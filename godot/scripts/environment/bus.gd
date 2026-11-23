extends Node3D

@export_group("Circular Path")
@export var center: Vector3 = Vector3(0, 60, 0)
@export var radius: float = 25.0
@export var speed: float = -0.2
@export var rotation_offset_degrees: float = -90.0
## In a match, derive the route angle from the shared match clock instead of
## this client's own uptime. Without that, every client starts the bus at a
## different phase and players sent over the network appear detached from the
## bus the other clients render.
@export var sync_to_match: bool = true

var _angle: float = 0.0
var _rotation_offset_rad: float = 0.0
var _player_manager: Node = null
var _manager_lookup_at_msec: int = 0

func _ready() -> void:
	add_to_group("bus")
	_rotation_offset_rad = deg_to_rad(rotation_offset_degrees)
	# Adopt the shared angle immediately so a mid-match join does not render
	# one frame at the route origin.
	_sync_angle_from_match()
	_update_bus_transform(_angle)

func _process(delta: float) -> void:
	if _sync_angle_from_match():
		_update_bus_transform(_angle)
		return
	# No PlayerManager in the tree (e.g. the lobby preview): keep the old
	# local orbit for decorative buses.
	_angle += delta * speed
	_update_bus_transform(_angle)

## Returns true when the angle came from the shared match clock. Reads 0 before
## the match starts, so the bus waits at the route origin for every client.
func _sync_angle_from_match() -> bool:
	if not sync_to_match:
		return false
	if _player_manager == null or not is_instance_valid(_player_manager):
		var now := Time.get_ticks_msec()
		if now < _manager_lookup_at_msec:
			return false
		_manager_lookup_at_msec = now + 1000
		_player_manager = get_tree().get_first_node_in_group("player_manager")
		if _player_manager == null:
			return false
	if not _player_manager.has_method("get_match_elapsed_seconds"):
		return false
	var elapsed: float = float(_player_manager.call("get_match_elapsed_seconds"))
	_angle = elapsed * speed
	return true

func _update_bus_transform(angle: float) -> void:
	var x = cos(angle) * radius
	var z = sin(angle) * radius
	global_position = center + Vector3(x, 0, z)
	global_rotation.y = -angle + _rotation_offset_rad
