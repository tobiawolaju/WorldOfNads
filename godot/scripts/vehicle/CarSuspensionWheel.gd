extends RayCast3D
class_name CarSuspensionWheel
## One raycast suspension corner.
##
## Attach to a RayCast3D that is a child of the vehicle's RigidBody3D and points
## along the chassis' local -Y axis (the RayCast's default target). The corner
## owns its own spring/damper state and pushes the chassis up from the ray hit
## point every physics tick, so the body pitches and rolls naturally when the
## corners compress by different amounts.
##
## The spring can only push. It is clamped to [0, max_suspension_force], so an
## over-extended or airborne wheel never drags the chassis towards the ground.

@export_group("Suspension")
## Spring rate in N/m. Static compression = (mass * gravity / 4) / spring_strength.
@export var spring_strength: float = 35000.0
## Damper rate in N/(m/s). Higher values settle the chassis faster.
@export var damping: float = 4500.0
## Distance from the ray origin to the wheel centre when the spring is relaxed.
@export var rest_length: float = 0.45
## Shortest allowed suspension length (full bump).
@export var min_length: float = 0.20
## Longest allowed suspension length (full droop).
@export var max_length: float = 0.65
## Radius of the tyre. The ray is shortened by this much to find the wheel centre.
@export var wheel_radius: float = 0.25

@export_group("Force Limits")
## Per-wheel ceiling. Four wheels at 12 000 N hold ~4.9 t, so this also caps
## how hard the chassis can be launched off a ramp.
@export var max_suspension_force: float = 12000.0

@export_group("Axle")
## Auto reads the wheel's position along CarController.forward_axis.
@export_enum("Auto", "Front", "Rear") var axle: int = 0

## Resolved by CarController. Only used for the handbrake / drive split.
var is_front: bool = true

# --- Runtime state (read-only, useful for debugging and tyre forces) ---
## Distance from the ray origin to the wheel centre this tick.
var current_length: float = 0.0
## Same value from the previous tick.
var previous_length: float = 0.0
## rest_length - current_length. Positive while compressed.
var compression: float = 0.0
## Spring part of the force, before clamping.
var spring_force: float = 0.0
## Damper part of the force, before clamping.
var damping_force: float = 0.0
## Force actually applied to the chassis this tick.
var suspension_force: float = 0.0
## Compression rate along the ground normal (m/s). Negative while the corner
## is being compressed, positive while it extends.
var suspension_velocity: float = 0.0
## True when the ray hits drivable ground within suspension reach.
var is_grounded: bool = false
var contact_point: Vector3 = Vector3.ZERO
var contact_normal: Vector3 = Vector3.UP

## Normals tilted further than ~78 degrees from the chassis up axis are treated
## as walls, not ground, so side hits cannot fake a contact.
const MAX_GROUND_TILT_DOT := 0.2

var _body: RigidBody3D = null
var _up_axis: Vector3 = Vector3.UP
var _down_axis: Vector3 = Vector3.DOWN


func _ready() -> void:
	_body = _find_rigid_body()
	if _body == null:
		push_warning("%s: no RigidBody3D ancestor, suspension disabled." % name)
		set_physics_process(false)
		return

	# The chassis must never block its own suspension ray. exclude_parent only
	# covers the direct parent (usually the Suspension pivot), so add the body.
	add_exception(_body)

	# Long enough to reach full droop plus the tyre, with a little slack.
	var reach: float = maxf(max_length, min_length) + wheel_radius + 0.15
	target_position = Vector3(0.0, -reach, 0.0)

	current_length = rest_length
	previous_length = rest_length


func _physics_process(_delta: float) -> void:
	_up_axis = global_transform.basis.y.normalized()
	_down_axis = -_up_axis

	# Re-cast against the pose the chassis has right now instead of relying on
	# the physics server's cached result from the previous step.
	force_raycast_update()

	previous_length = current_length

	if not _sample_ground():
		_reset_airborne_state()
		return

	_update_spring()
	_apply_suspension_force()


## Velocity of the chassis at the contact point (linear + angular).
func get_point_velocity() -> Vector3:
	if _body == null:
		return Vector3.ZERO
	var offset: Vector3 = contact_point - _body.global_position
	return _body.linear_velocity + _body.angular_velocity.cross(offset)


## Contact point as an offset from the body origin, ready for apply_force().
func get_contact_offset() -> Vector3:
	if _body == null:
		return Vector3.ZERO
	return contact_point - _body.global_position


## Current normal load, i.e. how hard this corner is pressed into the ground.
func get_normal_load() -> float:
	return suspension_force if is_grounded else 0.0


func _find_rigid_body() -> RigidBody3D:
	var node: Node = get_parent()
	while node != null:
		if node is RigidBody3D:
			return node
		node = node.get_parent()
	return null


## Fills the contact state. Returns false when there is no usable ground.
func _sample_ground() -> bool:
	contact_normal = Vector3.UP
	contact_point = Vector3.ZERO
	is_grounded = false

	if not is_colliding():
		return false

	var hit: Vector3 = get_collision_point()
	var normal: Vector3 = get_collision_normal()

	# Steep hits (walls, kerbs, the side of a ramp) are not ground.
	if normal.dot(_up_axis) < MAX_GROUND_TILT_DOT:
		return false

	# Measure along the suspension axis, not along the ray vector, so a tilted
	# chassis still reports a sane travel distance.
	var distance: float = (hit - global_position).dot(_down_axis)
	var length: float = distance - wheel_radius

	# Ground is there but out of reach: the corner is hanging in the air.
	if length > maxf(max_length, min_length):
		return false

	contact_point = hit
	contact_normal = normal
	is_grounded = true
	current_length = clampf(length, minf(min_length, max_length), maxf(min_length, max_length))
	return true


func _reset_airborne_state() -> void:
	# Hanging at rest length keeps the corner neutral for the next landing and
	# guarantees no force is left over from the last grounded tick.
	current_length = rest_length
	previous_length = rest_length
	compression = 0.0
	spring_force = 0.0
	damping_force = 0.0
	suspension_force = 0.0
	suspension_velocity = 0.0


func _update_spring() -> void:
	compression = rest_length - current_length

	# Damping uses the chassis velocity at the corner measured along the ground
	# normal. Measuring along the strut instead would count the forward motion of
	# a pitched chassis as compression (at 12 m/s and 2 degrees of pitch that is
	# ~0.4 m/s of phantom compression) and stiffen the springs at speed.
	var offset: Vector3 = global_position - _body.global_position
	var point_velocity: Vector3 = _body.linear_velocity + _body.angular_velocity.cross(offset)
	suspension_velocity = point_velocity.dot(contact_normal)

	spring_force = compression * spring_strength
	damping_force = -suspension_velocity * damping

	# Never negative: the suspension pushes, it does not pull. The clamp also
	# keeps a bad landing from catapulting the chassis.
	suspension_force = clampf(spring_force + damping_force, 0.0, max_suspension_force)


func _apply_suspension_force() -> void:
	if suspension_force <= 0.0:
		return
	# Push along the ground normal, not the chassis up axis: on a tilted chassis
	# an up-axis push has a horizontal component that would drive the car
	# forwards on flat ground and can even flip it while braking.
	# Applying at the contact offset is what produces the natural pitch/roll:
	# a compressed front corner lifts the nose, a compressed corner on one side
	# rolls the chassis that way.
	_body.apply_force(contact_normal * suspension_force, contact_point - _body.global_position)
