extends MeshInstance3D
## Makes the bee mesh buzz around its placed position like a hovering bee.

@export var hover_radius: float = 0.35
@export var hover_height: float = 0.18
@export var move_speed: float = 2.6
@export var bob_speed: float = 5.5
@export var bob_amount: float = 0.06
@export var jitter_amount: float = 0.015
@export var turn_speed: float = 8.0

var _home_position: Vector3
var _home_basis: Basis
var _time: float = 0.0
var _seed: float = 0.0


func _ready() -> void:
	_home_position = position
	_home_basis = basis
	_seed = float(get_instance_id() % 997) * 0.37
	_time = _seed
	set_process(true)


func _process(delta: float) -> void:
	_time += delta

	# Wander in a lazy loop around the home point.
	var t := _time * move_speed + _seed
	var wander := Vector3(
		sin(t) * hover_radius + sin(t * 1.7 + _seed) * hover_radius * 0.35,
		sin(t * bob_speed * 0.35 + _seed * 1.3) * hover_height + sin(t * bob_speed) * bob_amount,
		cos(t * 0.9) * hover_radius + cos(t * 1.3 + _seed) * hover_radius * 0.3
	)
	# Small rapid jitter for a buzzing feel.
	var buzz := Vector3(
		sin(_time * 23.0 + _seed) * jitter_amount,
		cos(_time * 27.0 + _seed) * jitter_amount,
		sin(_time * 19.0 + _seed * 0.5) * jitter_amount
	)

	var target_pos := _home_position + wander + buzz
	var velocity := target_pos - position
	position = target_pos

	# Face/tilt in the direction of motion for a lively bee look.
	if velocity.length() > 0.0005:
		var dir := velocity.normalized()
		var yaw := atan2(dir.x, dir.z)
		var tilt := clampf(-dir.y * 0.9, -0.5, 0.5)
		var roll := clampf(-dir.x * 0.35, -0.35, 0.35)
		var target_basis := Basis.from_euler(Vector3(tilt, yaw, roll))
		basis = basis.slerp(target_basis, clampf(turn_speed * delta, 0.0, 1.0))
	else:
		basis = basis.slerp(_home_basis, clampf(turn_speed * delta * 0.3, 0.0, 1.0))
