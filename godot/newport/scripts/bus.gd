extends CharacterBody3D

@export var point_a: Vector3 = Vector3(10, 16, 0)
@export var point_b: Vector3 = Vector3(-20, 14, 0)

# seconds from A → B
@export var travel_time: float = 90.0
@export var rotation_speed: float = 4.0

# If your model faces a different forward axis, tweak this.
# Common values:
#   0   -> model forward aligns with +Z
#  -90  -> model forward aligns with +X (typical for many imports)
#  +90  -> model forward aligns with -X
@export var rotation_offset_degrees: float = -90.0

var _editor_y: float


func _ready():
	# Keep the scene's Y position instead of using the hard-coded path heights.
	_editor_y = global_position.y


func _physics_process(delta):
	# Global time in seconds
	var t = Time.get_ticks_msec() * 0.001

	# Ping-pong phase calculation (0 → 1 → 0 → 1)
	var cycle = travel_time * 2.0
	var normalized = fmod(t, cycle) / cycle
	var phase = abs(normalized * 2.0 - 1.0)

	# Move between A and B on X/Z, but preserve the editor-set Y.
	var pos = point_a.lerp(point_b, phase)
	global_position = Vector3(pos.x, _editor_y, pos.z)

	# Determine horizontal direction to face (ignore Y)
	var dir = (point_b - point_a) if phase < 0.5 else (point_a - point_b)
	var horiz = Vector3(dir.x, 0.0, dir.z)

	if horiz.length_squared() > 0.000001:
		horiz = horiz.normalized()
		# atan2(x, z) gives an angle around Y in Godot when using x,z order
		var target_rot = atan2(horiz.x, horiz.z)
		# apply user-configurable offset (convert degrees -> radians)
		target_rot += deg_to_rad(rotation_offset_degrees)
		rotation.y = lerp_angle(rotation.y, target_rot, delta * rotation_speed)
