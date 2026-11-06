class_name Bullet
extends RigidBody3D
## Offline projectile for the handheld weapons. Attach to
## res://scenes/props/bullet.tscn (a plain RigidBody3D) and let player.gd spawn it
## from the muzzle Marker3D.
##
## Offline only: the hit is resolved here, on the machine that fired the shot.
## When the server owns damage, drop the take_damage() call in _on_body_entered
## and feed `hit` into the network instead; nothing else has to change.
##
## The scene needs nothing but the body itself. CCD, contact reporting and the
## lifetime are configured in _ready(), so re-authoring bullet.tscn (new mesh, new
## shape) cannot silently break hits.

## Emitted once, on the first thing the bullet touches. `at` is where it landed.
signal hit(target: Node, at: Vector3)

## Metres per second out of the muzzle. player.gd overwrites this per weapon from
## WEAPON_FIRE_FX, so the export is only the value used by a hand-placed bullet.
@export var speed: float = 120.0
@export var damage: float = 20.0
## Seconds before a bullet that hit nothing removes itself.
@export var lifetime: float = 2.5
## Push applied to a RigidBody3D it hits (crates, props). 0 leaves physics alone.
@export var impact_impulse: float = 0.0
## Seconds a spent bullet stays where it landed before it is removed. 0 frees it
## on the frame it hits. player.gd raises this for slow-motion debug shots so the
## projectile leaves visible evidence on the floor.
@export var linger_after_hit: float = 0.0
## Debug: print the spawn point and whatever the bullet hits. player.gd switches
## this on together with bullet_speed_scale, so a slow-motion test explains itself
## in the Output panel instead of just vanishing.
@export var debug: bool = false

var _shooter: Node = null
var _spent: bool = false
## Set by hit/expire so _exit_tree can tell "freed by something else" apart.
var _freed_reason: String = ""


func _ready() -> void:
	# Forward speed comes from launch(); the drop comes from gravity_scale, which
	# player.gd sets per shot. No tumbling, and never allowed to fall asleep mid-air.
	can_sleep = false
	# body_entered only exists when contact reporting is on. Without these two the
	# bullet would pass through the world and deal no damage, silently.
	contact_monitor = true
	max_contacts_reported = 4
	# Ray CCD every physics step: at 120 m/s a bullet covers 2 m per tick, wider
	# than most targets, so discrete collision would tunnel straight through.
	continuous_cd = true
	body_entered.connect(_on_body_entered)
	if lifetime > 0.0:
		var timer := get_tree().create_timer(lifetime)
		timer.timeout.connect(_expire)


## Sends the bullet on its way. Call it AFTER add_child(): global_position needs a
## parent in the tree to be resolved against.
func launch(from: Vector3, direction: Vector3, shot_speed: float, shot_damage: float, shooter: Node = null) -> void:
	_shooter = shooter
	if shot_speed > 0.0:
		speed = shot_speed
	if shot_damage > 0.0:
		damage = shot_damage
	var dir := direction.normalized() if direction.length_squared() > 0.000001 else Vector3.FORWARD
	global_position = from
	linear_velocity = dir * speed
	# Never collide with the player who pulled the trigger: the muzzle sits inside
	# their capsule, so the first physics tick would read as a self-hit.
	if shooter is CollisionObject3D:
		add_collision_exception_with(shooter)
	if debug:
		var host := get_parent()
		print("[bullet] spawn %s | parent=%s | speed=%.1f dmg=%.0f" % [
			from, host.name if host != null else "<no parent>", speed, damage])


func _expire() -> void:
	if not _spent and is_instance_valid(self):
		if debug:
			print("[bullet] expired at %s (nothing in %ds)" % [global_position, int(lifetime)])
		_freed_reason = "expired"
		queue_free()


func _exit_tree() -> void:
	# Debug only: if a live bullet leaves the tree without a hit or a timeout,
	# something above it was deleted or hidden away. That is the one case where
	# the projectile really can "pop out of existence" mid-flight.
	if debug and _freed_reason == "":
		print("[bullet] removed mid-flight at %s (nothing hit, not expired)" % global_position)


func _on_body_entered(body: Node) -> void:
	if _spent or body == null or body == _shooter:
		return
	_spent = true
	_freed_reason = "hit"
	# The body may be a hitbox rather than the actor: walk up until something
	# accepts damage, the same way the storm ticks the player.
	var target := _damage_target(body)
	if debug:
		print("[bullet] hit %s%s at %s" % [
			body.get_path(),
			" (damage target: %s)" % target.get_path() if target != null else " (no damage target)",
			global_position])
	if target != null:
		target.call("take_damage", damage, _shooter)
	if impact_impulse > 0.0 and body is RigidBody3D and body != self:
		(body as RigidBody3D).apply_central_impulse(linear_velocity.normalized() * impact_impulse)
	hit.emit(target if target != null else body, global_position)
	if linger_after_hit > 0.0:
		# Debug: stop dead where it landed and stay visible for a moment, so a
		# slow shot leaves proof on the floor instead of blinking out of view.
		freeze = true
		linear_velocity = Vector3.ZERO
		# Deferred: contact monitoring cannot be turned off inside its own callback.
		set_deferred("contact_monitor", false)
		get_tree().create_timer(linger_after_hit).timeout.connect(queue_free)
		return
	queue_free()


## Nearest node at or above `node` that owns a take_damage() method, or null.
func _damage_target(node: Node) -> Node:
	var current := node
	while current != null:
		if current.has_method("take_damage"):
			return current
		current = current.get_parent()
	return null
