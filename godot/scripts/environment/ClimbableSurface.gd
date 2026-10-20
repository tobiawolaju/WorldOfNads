extends StaticBody3D

## Climbable surface: attach this script to any StaticBody3D (a ladder, a wall, a
## shipping container, ...) and the local player can climb it.
##
## Walking into the body stops the player against its collision, and once the
## player is inside the trigger volume they attach to the face, start the "climb"
## animation and can move on the object: forward/back climbs up and down, strafe
## shuffles sideways along it. Press jump to let go and push off the face, or
## simply climb out of the side of the volume to drop off. The volume stops at
## the body's roof, so climbing up ends the moment the player's feet clear the
## top and vault_on_exit steps them onto the ledge instead of letting them
## climb the air above it.
##
## The trigger volume is grown from the body's own collision shapes, so it works
## with whatever geometry you already gave the StaticBody3D. Hand it an explicit
## size in the inspector if the auto box is not right for the prop.
class_name ClimbableSurface

## Chest height used when probing the face (metres above the player's origin).
const CLIMB_CHEST_HEIGHT: float = 0.9
## How far the probe ray travels from the chest toward this body's face (m).
const CLIMB_PROBE_REACH: float = 4.0
## Reject faces steeper than this from vertical (|normal.y|): floors and roofs are
## not climbable, so standing on top of a body never attaches you sideways to it.
const CLIMB_MAX_NORMAL_Y: float = 0.45
## Minimum agreement (dot product) between a probed face normal and "toward the
## structure" before the face is trusted. Below this the nearest-point direction
## is used instead, so a stray triangle (a rung end, a trimesh sliver) cannot
## swing the climb sideways.
const CLIMB_MIN_FACE_AGREEMENT: float = 0.5
## Fallback box when the body has no collision shapes at all (size, metres).
const DEFAULT_BOX_SIZE: Vector3 = Vector3(2.0, 2.0, 2.0)
## Slack (m) around the body's vertical span when deciding that a player standing
## on the roof / floating under the prop is not in front of a climbable face.
const VERTICAL_BAND_SLACK: float = 0.5

@export_group("Trigger")
## How far (m) the auto-built trigger box extends past the body's collision
## shapes on the sides and the bottom — never above its roof, so climbing always
## ends as soon as the player's feet clear the top instead of climbing the air
## above it. The player has to be inside the box to attach, so keep this above
## the capsule radius (~0.4 m) if you want "close enough" to grab.
@export_range(0.0, 8.0, 0.05) var trigger_padding: float = 1.0
## Explicit trigger size in this body's local space. Leave at ZERO to build the
## box from the collision shapes plus trigger_padding.
@export var trigger_size: Vector3 = Vector3.ZERO
## Explicit trigger centre in local space. Leave at ZERO to use the centre of the
## collision shapes (or of trigger_size when a size is given).
@export var trigger_center: Vector3 = Vector3.ZERO

@export_group("Face")
## Pins the face normal (outward, pointing back at the player). Leave at ZERO to
## probe this body's surface toward the player when they enter the volume. A pin
## aimed the wrong way is flipped back around; the roof / under-prop guards still
## apply.
@export var surface_normal: Vector3 = Vector3.ZERO
## Nudge the player toward the face when they climb out of the volume, so topping
## out on a ledge steps onto it instead of dropping straight back down the wall.
@export var vault_on_exit: bool = true

@export_group("Re-grab")
## Seconds between re-checks of who is inside the volume. body_entered only fires
## on the edge, so this catches a player who jumps off (or is pushed out) and then
## climbs back in while still overlapping the volume.
@export_range(0.05, 2.0, 0.05) var regrab_check_interval: float = 0.25

var _trigger: Area3D = null
var _regrab_timer: float = 0.0
## The local player is inside the volume, so the periodic overlap re-check is worth
## running; cleared again — along with this prop's per-frame processing — once no
## climber is left inside.
var _occupied: bool = false

func _ready() -> void:
	add_to_group("climbable")
	_trigger = _build_trigger()
	add_child(_trigger)
	# The overlap re-check below is the only per-frame work here, and it is only
	# useful while something is inside the volume. Keeping it off until then means
	# idle props cost nothing per frame even with this script on many bodies.
	set_physics_process(false)

func _physics_process(delta: float) -> void:
	if _trigger == null or not _occupied:
		return
	_regrab_timer += delta
	if _regrab_timer < regrab_check_interval:
		return
	_regrab_timer = 0.0
	# Only a body that can actually climb keeps this prop awake. The prop's own
	# collision shape sits inside its own volume, so counting every overlapping
	# body would leave this pass running forever on every prop.
	var climber_present := false
	for body in _trigger.get_overlapping_bodies():
		if not _is_climber(body):
			continue
		climber_present = true
		_try_attach(body)
	if not climber_present:
		_occupied = false
		set_physics_process(false)

# --- SIGNALS -----------------------------------------------------------------

func _on_body_entered(body: Node3D) -> void:
	if not _is_climber(body):
		return
	_occupied = true
	set_physics_process(true)
	_try_attach(body)

func _on_body_exited(body: Node3D) -> void:
	# Force at least one overlap re-check: the volume may still hold someone else,
	# and the periodic pass is what notices a player who never actually left.
	if _is_climber(body):
		_occupied = true
		set_physics_process(true)
	if body.has_method("end_climb"):
		body.call("end_climb", self, false, vault_on_exit)

# --- ATTACH ------------------------------------------------------------------

## True for the local player, the only body that drives its own climb. Everything
## else that overlaps the volume (loot, chickens, other clients' avatars, and this
## prop's own collision) is ignored — including when deciding whether this prop
## still needs its per-frame re-check.
func _is_climber(body: Node3D) -> bool:
	return body != null and body.has_method("begin_climb") and body.get("is_local") == true

## Attach the local player if this body is one, and confirm they are really inside
## the volume before grabbing them.
func _try_attach(body: Node3D) -> void:
	if not _is_climber(body):
		return
	# The overlap list can lag a frame behind a body that was repositioned, and a
	# stale entry would let the wall grab someone standing well outside the volume,
	# so confirm the player really is inside it before attaching.
	if not _transform_box(_trigger_box(), global_transform).has_point(body.global_position):
		return
	var normal := face_normal_for(body)
	if normal.length_squared() < 0.0001:
		return
	body.call("begin_climb", self, normal)

## Outward normal of the face this player is standing against (horizontal, points
## back at the player). Vector3.ZERO means "no climbable face here" — a roof, the
## floor under a floating prop, or nothing to probe against.
func face_normal_for(player: Node3D) -> Vector3:
	# "Toward this structure" axis, measured from the nearest point of the body's
	# own collision out to the player. Imported props often carry their origin off
	# to one side (or inside the geometry), so aiming the probe at the origin made
	# it miss and the fallback face sideways or straight into the wall — which is
	# what put the player's back or side to the structure while climbing.
	var world_box := _transform_box(_auto_box(), global_transform)
	var outward := _outward_toward(player.global_position, world_box)
	if outward.length_squared() < 0.0001:
		# Inside the body's footprint (on its roof, under it, or wedged into its
		# geometry): none of those is a face to climb.
		return Vector3.ZERO
	if _player_is_standing_on(player):
		return Vector3.ZERO
	var player_y := player.global_position.y
	if player_y >= world_box.end.y - 0.1 or player_y < world_box.position.y - VERTICAL_BAND_SLACK:
		return Vector3.ZERO

	if surface_normal.length_squared() > 0.0001:
		# Pinned by hand: honoured, but a vertical pin still means "no face", and a
		# pin aimed into the structure is flipped back around so the climb never
		# puts the player's back to the wall.
		var pinned := Vector3(surface_normal.x, 0.0, surface_normal.z)
		if pinned.length_squared() < 0.0001 or absf(surface_normal.y) > CLIMB_MAX_NORMAL_Y:
			return Vector3.ZERO
		pinned = pinned.normalized()
		if pinned.dot(outward) < 0.0:
			pinned = -pinned
		return pinned

	# Probe straight at the face from chest height: whatever the ray hits is the
	# wall (or rung, or container side) the player is standing against.
	var from := player.global_position + Vector3.UP * CLIMB_CHEST_HEIGHT
	if player is CollisionObject3D:
		var collider := player as CollisionObject3D
		var exclude: Array[RID] = [collider.get_rid()]
		var query := PhysicsRayQueryParameters3D.create(
			from,
			from - outward * CLIMB_PROBE_REACH,
			collider.collision_mask,
			exclude
		)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.get("collider") == self:
			var hit_normal: Vector3 = hit.get("normal", Vector3.ZERO)
			if absf(hit_normal.y) > CLIMB_MAX_NORMAL_Y:
				# The ray found a floor/roof face: the player is on top of (or
				# under) the prop, not in front of a climbable wall.
				return Vector3.ZERO
			hit_normal.y = 0.0
			if hit_normal.length_squared() > 0.0001:
				hit_normal = hit_normal.normalized()
				# Concave (mesh) colliders hand back the triangle's own winding
				# normal, which can point *into* the geometry; anything that does
				# not look back at the player is flipped.
				if hit_normal.dot(outward) < 0.0:
					hit_normal = -hit_normal
				# A face that barely agrees with "toward the structure" would
				# swing the climb sideways; face the structure instead.
				if hit_normal.dot(outward) >= CLIMB_MIN_FACE_AGREEMENT:
					return hit_normal
	# Nothing usable to probe: face straight out of the nearest point of the body,
	# which is still "toward the structure" wherever its origin happens to sit.
	return outward

## True when this player has this body right under their feet: they are on top of
## the prop (or on its floor), so there is no vertical face for them to hug.
func _player_is_standing_on(player: Node3D) -> bool:
	if not (player is CollisionObject3D):
		return false
	var collider := player as CollisionObject3D
	var exclude: Array[RID] = [collider.get_rid()]
	var query := PhysicsRayQueryParameters3D.create(
		player.global_position + Vector3.UP * 0.2,
		player.global_position - Vector3.UP * 1.2,
		collider.collision_mask,
		exclude
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.get("collider") == self

## Horizontal direction from the nearest point of `box` out to `point`: what
## "toward this structure" means no matter where the body's origin sits.
func _outward_toward(point: Vector3, box: AABB) -> Vector3:
	var nearest := point
	nearest.x = clampf(nearest.x, box.position.x, box.end.x)
	nearest.z = clampf(nearest.z, box.position.z, box.end.z)
	return _horizontal_from(point - nearest)

## `vector` flattened to the horizontal plane and normalised; ZERO when the
## horizontal part is negligible.
func _horizontal_from(vector: Vector3) -> Vector3:
	vector.y = 0.0
	if vector.length_squared() < 0.0001:
		return Vector3.ZERO
	return vector.normalized()

# --- TRIGGER VOLUME ----------------------------------------------------------

## Builds the detection box: a child Area3D covering this body's collision shapes
## grown by trigger_padding on the sides and bottom, up to the body's roof (or an
## explicit size from the inspector).
func _build_trigger() -> Area3D:
	var box := _trigger_box()
	var area := Area3D.new()
	area.name = "ClimbTrigger"
	# The trigger only watches — it must never block anything. The mask covers all
	# layers so a player on a custom collision layer is still picked up; _try_attach
	# is what decides who may actually climb.
	area.collision_layer = 0
	area.collision_mask = 0xFFFFFFFF

	var shape_node := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box.size
	shape_node.shape = box_shape
	shape_node.position = box.get_center()
	area.add_child(shape_node)

	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	return area

## Trigger box in this body's local space.
func _trigger_box() -> AABB:
	if trigger_size.length_squared() > 0.0001:
		var center := trigger_center
		if center.length_squared() < 0.0001:
			center = _auto_box().get_center()
		return AABB(center - trigger_size * 0.5, trigger_size)
	var box := _auto_box()
	# Padding stops at the body's roof: a volume that floated above it let a
	# climber keep going once their feet were over the top, which reads as
	# hovering in mid-air. Sides and bottom keep the full padding.
	var roof := box.end.y
	if trigger_center.length_squared() > 0.0001:
		var shifted := box.position + (trigger_center - box.get_center())
		box.position = shifted
	box = box.grow(trigger_padding)
	if box.end.y > roof:
		box.size.y = maxf(roof - box.position.y, 0.1)
	return box

## Union of every collision shape on this body, in local space.
func _auto_box() -> AABB:
	var box := AABB()
	var found := false
	for owner_id in get_shape_owners():
		var owner_xform := shape_owner_get_transform(owner_id)
		for shape_index in shape_owner_get_shape_count(owner_id):
			var shape := shape_owner_get_shape(owner_id, shape_index)
			if shape == null:
				continue
			var shape_box := _transform_box(_shape_box(shape), owner_xform)
			if found:
				box = box.merge(shape_box)
			else:
				box = shape_box
				found = true
	if not found:
		return AABB(-DEFAULT_BOX_SIZE * 0.5, DEFAULT_BOX_SIZE)
	return box

## Local-space AABB of a single collision shape. Shape3D exposes no get_aabb()
## here, so each primitive derives its box from its own properties; polygon
## shapes are measured from their vertex list; anything else falls back to
## DEFAULT_BOX_SIZE around this body's origin.
func _shape_box(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		var size: Vector3 = (shape as BoxShape3D).size
		return AABB(-size * 0.5, size)
	if shape is SphereShape3D:
		var radius := (shape as SphereShape3D).radius
		return AABB(Vector3.ONE * -radius, Vector3.ONE * radius * 2.0)
	if shape is CapsuleShape3D:
		# height is the full height, hemispheres included.
		var capsule := shape as CapsuleShape3D
		var capsule_radius := capsule.radius
		return AABB(
			Vector3(-capsule_radius, -capsule.height * 0.5, -capsule_radius),
			Vector3(capsule_radius * 2.0, capsule.height, capsule_radius * 2.0))
	if shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		var cylinder_radius := cylinder.radius
		return AABB(
			Vector3(-cylinder_radius, -cylinder.height * 0.5, -cylinder_radius),
			Vector3(cylinder_radius * 2.0, cylinder.height, cylinder_radius * 2.0))
	# Polygon shapes: whichever accessor this build carries (guarded so a missing
	# one degrades to the default box instead of erroring at runtime).
	var vertices := PackedVector3Array()
	if shape.has_method("get_faces"):
		var faces = shape.call("get_faces")
		if faces is PackedVector3Array:
			vertices = faces
	if vertices.is_empty() and shape.has_method("get_points"):
		var points = shape.call("get_points")
		if points is PackedVector3Array:
			vertices = points
	if vertices.is_empty():
		return AABB(-DEFAULT_BOX_SIZE * 0.5, DEFAULT_BOX_SIZE)
	var box := AABB(vertices[0], Vector3.ZERO)
	for i in range(1, vertices.size()):
		box = box.expand(vertices[i])
	return box

## Re-encloses `box` after applying `by` to its eight corners. Done by hand
## because AABB exposes no transformed() in this Godot build.
func _transform_box(box: AABB, by: Transform3D) -> AABB:
	var result := AABB()
	var started := false
	for ix in 2:
		for iy in 2:
			for iz in 2:
				var local := box.position + Vector3(box.size.x * ix, box.size.y * iy, box.size.z * iz)
				var corner := by * local
				if not started:
					result = AABB(corner, Vector3.ZERO)
					started = true
				else:
					result = result.merge(AABB(corner, Vector3.ZERO))
	return result
