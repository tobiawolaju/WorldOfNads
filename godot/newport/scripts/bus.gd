extends CharacterBody3D

@export var point_a: Vector3 = Vector3(10, 16, 0)
@export var point_b: Vector3 = Vector3(-20, 14, 0)

@export var travel_time: float = 36.0
@export var rotation_speed: float = 4.0
@export var rotation_offset_degrees: float = -90.0

@export var arc_height: float = 6.0
@export var curve_strength: float = 10.0

var _t: float = 0.0
var _dir: int = 1
var _editor_y: float


func _ready():
	_editor_y = global_position.y


func _physics_process(delta):
	# ---------------- TIME ----------------
	_t += delta * _dir

	if _t >= travel_time:
		_t = travel_time
		_dir = -1
	elif _t <= 0.0:
		_t = 0.0
		_dir = 1

	var alpha = _t / travel_time

	# smooth acceleration (important for “vehicle feel”)
	alpha = alpha * alpha * (3.0 - 2.0 * alpha)

	# ---------------- BUILD ORBIT PLANE ----------------
	var a = point_a
	var b = point_b

	var center = (a + b) * 0.5
	var forward = (b - a)
	forward.y = 0.0
	forward = forward.normalized()

	var right = forward.cross(Vector3.UP).normalized()

	# half distance = radius base
	var distance = a.distance_to(b) * 0.5

	# ---------------- TRUE ELLIPSE PARAMETER ----------------
	var angle = lerp(-PI, PI, alpha)

	# elliptical orbit (horizontal curve)
	var x = cos(angle) * distance
	var z = sin(angle) * distance * curve_strength * 0.1

	# vertical arc
	var y = sin(alpha * PI) * arc_height

	var pos = center + right * x + forward * z
	pos.y += y

	global_position = Vector3(pos.x, _editor_y + pos.y, pos.z)

	# ---------------- TRUE TANGENT ROTATION ----------------
	var angle_next = angle + 0.01 * _dir

	var x2 = cos(angle_next) * distance
	var z2 = sin(angle_next) * distance * curve_strength * 0.1
	var y2 = sin(clamp(alpha + 0.01, 0.0, 1.0) * PI) * arc_height

	var pos_next = center + right * x2 + forward * z2
	pos_next.y += y2

	var dir = (pos_next - pos)
	dir.y = 0.0

	if dir.length_squared() > 0.000001:
		dir = dir.normalized()

		var target_rot = atan2(dir.x, dir.z)
		target_rot += deg_to_rad(rotation_offset_degrees)

		rotation.y = lerp_angle(rotation.y, target_rot, delta * rotation_speed)
