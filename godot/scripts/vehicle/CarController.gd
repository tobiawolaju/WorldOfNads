extends RigidBody3D
class_name CarController
## Arcade raycast vehicle controller for a single RigidBody3D chassis.
##
## The chassis is the only physics body. Each RayCast3D child that carries a
## [CarSuspensionWheel] applies its own spring/damper force, and this script
## feeds the contact patches engine, brake, handbrake and lateral grip forces.
## Nothing here writes transforms or velocities directly, so the solver keeps
## full control and the chassis pitches/rolls from the suspension itself.
##
## Controls: W accelerate, S reverse/brake, A/D steer, Space handbrake.

@export_group("Engine")
@export var engine_force: float = 8000.0
@export var reverse_force: float = 4000.0
## Forward speed cap in m/s. Engine force fades out over the last 10%.
@export var max_speed: float = 35.0

@export_group("Steering")
## Front-axle agility. 5.0 is neutral; lower values understeer, higher values
## make the front turn in harder by raising the front tyres' cornering force.
@export var steering_strength: float = 5.0
@export var max_steering_angle: float = 30.0
## How quickly the steering angle follows the key press (1/s).
@export var steering_response: float = 6.0

@export_group("Braking")
@export var brake_strength: float = 6000.0
@export var handbrake_strength: float = 4000.0

@export_group("Traction")
## Lateral cornering stiffness per wheel in N per (m/s) of sideways slip.
@export var tire_stiffness: float = 6000.0
## Friction coefficient. Caps lateral force at tire_friction * suspension load.
@export var tire_friction: float = 1.1
## Rolling resistance per wheel as a fraction of its load. Real tyres resist
## rolling, which is what keeps a parked van from creeping downhill. 0.08 also
## gives a gentle coast-down.
@export var rolling_friction: float = 0.08

@export_group("Vehicle")
## Applied to RigidBody3D.mass on ready. The van model is ~4.3 m long.
@export var vehicle_mass: float = 1400.0
## Local centre of mass. Kept low and mid-wheelbase so the van rides level and
## does not nose-dive. The auto-computed centre sits too far forward because the
## imported cab mesh carries most of the collision volume.
@export var center_of_mass_offset: Vector3 = Vector3(0.0, 0.85, 0.0)
## Local direction the nose points. This van's cab sits on +Z.
@export var forward_axis: Vector3 = Vector3(0.0, 0.0, 1.0)
## Quadratic drag so the car does not coast forever at top speed.
@export var air_drag: float = 0.6

@export_group("Input")
@export var input_enabled: bool = true
## Only the rider drives. With this on, the van ignores the controls until the
## local player is on board (and stops taking input again when they step out).
@export var require_rider_for_input: bool = true
## Drives the vehicle forward: the same button the player jumps with.
@export var forward_action: StringName = &"jump"
## Drives the vehicle in reverse: the same button the player slides with.
@export var reverse_action: StringName = &"slide"
## The player's own left/right movement actions steer the vehicle, so the arrow
## keys and the on-screen joystick work exactly like they do on foot.
@export var steer_left_action: StringName = &"move_left"
@export var steer_right_action: StringName = &"move_right"
## Handbrake on top of the brake, for the rear axle.
@export var handbrake_action: StringName = &"car_handbrake"

@export_group("Ride")
## Marker the rider is parked on while inside the van.
@export var ride_marker_path: NodePath = ^"ride"
## Marker the rider is placed on when they step out again.
@export var exit_marker_path: NodePath = ^"exit"
## How close the player has to stand for the RIDE prompt.
@export var ride_radius: float = 3.2
## Group used to find this vehicle from the player. Local play only for now.
@export var ride_group: StringName = &"rideable"

# --- Live state (read-only) ---
## Signed forward speed in m/s.
var forward_speed: float = 0.0
## Current steering angle in radians.
var steer_angle: float = 0.0
## Wheels with a valid ground contact this tick.
var grounded_wheel_count: int = 0

## steering_strength is normalised against this value, so 5.0 is the neutral
## setup and the knob still reads as a 0..10 strength.
const NEUTRAL_STEERING_STRENGTH := 5.0

## Input actions created on ready when missing. Existing bindings for these
## names are never modified.
const CAR_ACTIONS := {
	"car_handbrake": KEY_CTRL,
}

var _wheels: Array[CarSuspensionWheel] = []
var _grounded: Array[CarSuspensionWheel] = []
var _steer_target: float = 0.0
## The player currently riding this vehicle, if any.
var rider: Node3D = null


func _ready() -> void:
	_ensure_input_actions()

	# vehicle_mass is authoritative. The imported scene shipped with the
	# RigidBody3D default of 1 kg, which is far too light for a 4.3 m chassis
	# and would turn the springs into a catapult.
	mass = maxf(vehicle_mass, 0.001)

	# The imported cab carries most of the collision volume, so the automatic
	# centre of mass lands ahead of the front axle and the van permanently
	# nose-dives. Move it to a low, mid-wheelbase point instead.
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = center_of_mass_offset

	if not ride_group.is_empty():
		add_to_group(ride_group)

	_collect_wheels()


func _physics_process(delta: float) -> void:
	if _wheels.is_empty():
		return

	var throttle: float = 0.0
	var steer_input: float = 0.0
	var handbrake: bool = false
	# The vehicle only answers to its rider: while nobody is on board the keys
	# drive the player on foot instead of the van.
	var can_drive: bool = input_enabled and (not require_rider_for_input or has_rider())
	if can_drive:
		# Forward/reverse are the player's own jump and slide buttons, the
		# steering reuses the player's left/right direction (arrow keys and the
		# on-screen joystick).
		throttle = Input.get_action_strength(forward_action) - Input.get_action_strength(reverse_action)
		steer_input = Input.get_action_strength(steer_left_action) - Input.get_action_strength(steer_right_action)
		handbrake = Input.is_action_pressed(handbrake_action)

	var forward: Vector3 = get_forward_direction()
	forward_speed = linear_velocity.dot(forward)

	_update_steering(steer_input, delta)

	# The wheel components already ran (or will run) their own suspension step;
	# this only reads their contact state. One tick of latency at worst.
	_refresh_grounded_wheels()

	_apply_drive_and_brakes(throttle, handbrake, forward)
	_apply_lateral_grip(handbrake, forward)
	_apply_rolling_resistance(forward)
	_apply_air_drag()


## Chassis forward direction in world space.
func get_forward_direction() -> Vector3:
	return (global_transform.basis * forward_axis).normalized()


# --- RIDING (local play only) ---------------------------------------------
## Marker the rider is parked on while inside the van.
func get_ride_marker() -> Marker3D:
	return get_node_or_null(ride_marker_path) as Marker3D


## Marker the rider is placed on when they step out again.
func get_exit_marker() -> Marker3D:
	return get_node_or_null(exit_marker_path) as Marker3D


## True while somebody is riding this vehicle.
func has_rider() -> bool:
	return rider != null and is_instance_valid(rider)


## True when this player may climb in.
func can_ride(player: Node3D) -> bool:
	if has_rider() or player == null or not is_instance_valid(player):
		return false
	return player.global_position.distance_to(global_position) <= ride_radius


## Park the player on the ride marker and hand them over to the vehicle.
func ride(player: Node3D) -> bool:
	if not can_ride(player):
		return false
	rider = player
	var marker := get_ride_marker()
	if marker != null:
		player.global_position = marker.global_position
	if player.has_method("enter_vehicle"):
		player.call("enter_vehicle", self)
	return true


## Put the rider back on the exit marker and hand control back to them.
func exit_ride() -> void:
	if not has_rider():
		return
	var player := rider
	rider = null
	if player != null and is_instance_valid(player):
		var marker := get_exit_marker()
		if marker != null:
			player.global_position = marker.global_position
		if player.has_method("exit_vehicle"):
			player.call("exit_vehicle")


func _ensure_input_actions() -> void:
	for action: String in CAR_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)

		var keycode: int = CAR_ACTIONS[action]
		var already_bound: bool = false
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey and (event as InputEventKey).physical_keycode == keycode:
				already_bound = true
				break

		if not already_bound:
			var key := InputEventKey.new()
			key.physical_keycode = keycode
			InputMap.action_add_event(action, key)


func _collect_wheels() -> void:
	_wheels.clear()
	for node: Node in find_children("*", "RayCast3D", true, false):
		if node is CarSuspensionWheel:
			_wheels.append(node as CarSuspensionWheel)

	if _wheels.is_empty():
		push_warning("%s: no CarSuspensionWheel RayCast3D children found." % name)
		return

	# Classify front/rear from the geometry instead of from node names, so the
	# setup still works if the model faces a different axis.
	var forward_local: Vector3 = forward_axis.normalized()
	for wheel: CarSuspensionWheel in _wheels:
		if wheel.axle == 1:
			wheel.is_front = true
		elif wheel.axle == 2:
			wheel.is_front = false
		else:
			wheel.is_front = wheel.position.dot(forward_local) > 0.0


func _update_steering(steer_input: float, delta: float) -> void:
	var speed: float = absf(forward_speed)
	# Full lock at a crawl, noticeably less at top speed so the van does not
	# snap sideways on the motorway.
	var speed_attenuation: float = lerpf(1.0, 0.4, clampf(speed / maxf(max_speed, 0.001), 0.0, 1.0))
	_steer_target = deg_to_rad(max_steering_angle) * steer_input * speed_attenuation
	steer_angle = lerpf(steer_angle, _steer_target, clampf(steering_response * delta, 0.0, 1.0))


func _refresh_grounded_wheels() -> void:
	_grounded.clear()
	for wheel: CarSuspensionWheel in _wheels:
		if wheel.is_grounded:
			_grounded.append(wheel)
	grounded_wheel_count = _grounded.size()


## Engine and brake forces. Both are applied along the ground plane under each
## contact patch, which keeps a ramp launch level instead of firing the car
## straight into the sky.
func _apply_drive_and_brakes(throttle: float, handbrake: bool, forward: Vector3) -> void:
	if _grounded.is_empty():
		return

	var drive: float = 0.0
	var brake: float = 0.0

	if throttle > 0.01:
		if forward_speed < -0.5:
			brake = brake_strength * throttle
		else:
			drive = engine_force * throttle * _speed_factor(forward_speed, max_speed)
	elif throttle < -0.01:
		var reverse_input: float = -throttle
		if forward_speed > 0.5:
			brake = brake_strength * reverse_input
		else:
			drive = -reverse_force * reverse_input * _speed_factor(-forward_speed, max_speed * 0.4)

	var motion_sign: float = signf(forward_speed) if absf(forward_speed) > 0.05 else 0.0

	if handbrake:
		_apply_handbrake(forward, motion_sign)

	if is_zero_approx(drive) and is_zero_approx(brake):
		return

	var share: float = 1.0 / float(_grounded.size())
	for wheel: CarSuspensionWheel in _grounded:
		var normal: Vector3 = wheel.contact_normal
		var ground_forward: Vector3 = _flatten(forward, normal)
		if ground_forward == Vector3.ZERO:
			continue

		var offset: Vector3 = wheel.get_contact_offset()
		if not is_zero_approx(drive):
			apply_force(ground_forward * drive * share, offset)
		if brake > 0.0 and not is_zero_approx(motion_sign):
			apply_force(ground_forward * (-brake * share * motion_sign), offset)


## Rear-only handbrake so the nose keeps rolling and the back can step out.
func _apply_handbrake(forward: Vector3, motion_sign: float) -> void:
	if is_zero_approx(motion_sign):
		return

	# Count the rear wheels first instead of collecting them in a temporary
	# array: this runs every physics tick.
	var rear_count: int = 0
	for wheel: CarSuspensionWheel in _grounded:
		if not wheel.is_front:
			rear_count += 1

	var wheel_count: int = rear_count if rear_count > 0 else _grounded.size()
	if wheel_count == 0:
		return

	var share: float = 1.0 / float(wheel_count)
	for wheel: CarSuspensionWheel in _grounded:
		if rear_count > 0 and wheel.is_front:
			continue
		var ground_forward: Vector3 = _flatten(forward, wheel.contact_normal)
		if ground_forward == Vector3.ZERO:
			continue
		apply_force(
			ground_forward * (-handbrake_strength * share * motion_sign),
			wheel.get_contact_offset()
		)


## Lateral grip: kills sideways slip at every contact patch. Without this the
## chassis would keep its old velocity vector after a yaw change and slide.
##
## The front tyres are rotated by the steering angle, so steering makes them
## pull the nose around. That is the whole steering model - no torque is ever
## written to the chassis, so a parked van cannot spin on the spot.
func _apply_lateral_grip(handbrake: bool, forward: Vector3) -> void:
	var front_gain: float = maxf(steering_strength, 0.0) / NEUTRAL_STEERING_STRENGTH

	for wheel: CarSuspensionWheel in _wheels:
		if not wheel.is_grounded:
			continue

		var normal: Vector3 = wheel.contact_normal
		var wheel_forward: Vector3 = _flatten(forward, normal)
		if wheel_forward == Vector3.ZERO:
			continue

		if wheel.is_front and not is_zero_approx(steer_angle):
			wheel_forward = _flatten(wheel_forward.rotated(normal, steer_angle), normal)

		var right: Vector3 = wheel_forward.cross(normal).normalized()
		var velocity: Vector3 = wheel.get_point_velocity()
		var sideways_speed: float = (velocity - normal * velocity.dot(normal)).dot(right)

		var grip: float = tire_friction * wheel.get_normal_load()
		var stiffness: float = tire_stiffness
		if wheel.is_front:
			grip *= front_gain
			stiffness *= front_gain
		if handbrake and not wheel.is_front:
			grip *= 0.35  # locked rear wheels slide instead of gripping

		var lateral_force: float = clampf(-sideways_speed * stiffness, -grip, grip)
		if is_zero_approx(lateral_force):
			continue

		apply_force(right * lateral_force, wheel.get_contact_offset())


## Rolling resistance along the wheel's rolling direction. The lateral tyre
## model only stops sideways slip, so without this the van would roll away
## downhill whenever it is parked on a slope.
func _apply_rolling_resistance(forward: Vector3) -> void:
	for wheel: CarSuspensionWheel in _wheels:
		if not wheel.is_grounded:
			continue

		var normal: Vector3 = wheel.contact_normal
		var ground_forward: Vector3 = _flatten(forward, normal)
		if ground_forward == Vector3.ZERO:
			continue

		var velocity: Vector3 = wheel.get_point_velocity()
		var roll_speed: float = (velocity - normal * velocity.dot(normal)).dot(ground_forward)
		if is_zero_approx(roll_speed):
			continue

		# Fade the force out around zero speed so a parked van does not jitter,
		# then push back against the rolling direction, capped by the tyre load.
		var direction: float = signf(roll_speed)
		var fade: float = clampf(absf(roll_speed) / 0.3, 0.0, 1.0)
		var load: float = wheel.get_normal_load()
		var force: float = -direction * rolling_friction * load * fade
		if is_zero_approx(force):
			continue

		apply_force(ground_forward * force, wheel.get_contact_offset())


func _apply_air_drag() -> void:
	var speed: float = linear_velocity.length()
	if speed < 0.01:
		return
	apply_force(-linear_velocity * speed * air_drag)


## Linear fade to zero over the last 10% before the speed cap.
func _speed_factor(speed: float, limit: float) -> float:
	if limit <= 0.0:
		return 0.0
	return clampf((limit - speed) / maxf(limit * 0.1, 0.001), 0.0, 1.0)


static func _flatten(direction: Vector3, normal: Vector3) -> Vector3:
	var flat: Vector3 = direction - normal * direction.dot(normal)
	if flat.length_squared() < 0.0001:
		return Vector3.ZERO
	return flat.normalized()
