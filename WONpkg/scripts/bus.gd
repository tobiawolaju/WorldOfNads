extends CharacterBody3D

@export var point_a: Vector3 = Vector3(10, 16, 0)
@export var point_b: Vector3 = Vector3(-20, 14, 0)

# seconds from A → B
@export var travel_time: float = 90.0
@export var rotation_speed: float = 4.0

func _physics_process(delta):
	# Global time in seconds
	var t = Time.get_ticks_msec() * 0.001

	# Ping-pong phase calculation (0 → 1 → 0 → 1)
	var cycle = travel_time * 2.0
	var normalized = fmod(t, cycle) / cycle
	var phase = abs(normalized * 2.0 - 1.0)

	# Move between A and B
	global_position = point_a.lerp(point_b, phase)

	# Determine direction
	var dir = (point_b - point_a) if phase < 0.5 else (point_a - point_b)
	var target_rot = atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, target_rot, delta * rotation_speed)
