extends RigidBody3D
class_name LocalPickup
## Client-side only pickup item.
##
## Behaves like the chicken / lootbox holds (grab it when close, drop it any time)
## but nothing is sent to the server, so every client owns its own copy of the item.
##
## Falling and resting are left entirely to the physics engine. The body is only
## frozen while it is being carried; the moment it is dropped it is unfrozen and
## Jolt simulates the fall, so the item lands on the terrain and stays there.
##
## player.gd finds these through the "local_pickup_items" group and never sends a
## pickup_request for them, so they must NOT be added to the "pickup_items" group
## (that group is reserved for the server-synced chicken and lootbox).

signal picked_up(item: RigidBody3D)
signal dropped(item: RigidBody3D)

const GROUP: String = "local_pickup_items"

## Power-up roster — foundation only, no activation mechanics yet. Set this on
## each pickup instance in the editor. When a pickup with a non-NONE mode is
## picked up, player.gd shows its label in the HUD Action button.
enum PowerUpMode {
	NONE,
	SPEED_BURST,    # ~4s of boosted run speed
	THROWABLE,      # throw an object; a hit knocks the target down
	SMOKE_GRENADE,  # temporary smoke cloud that blocks vision
	BOXING_GLOVE,   # lunge punch; one hit drops the target and their chicken
	MEGA_LEAP       # one super high jump, consumed on use
}

const POWER_UP_LABELS := {
	PowerUpMode.SPEED_BURST: "RUSH",
	PowerUpMode.THROWABLE: "TOSS",
	PowerUpMode.SMOKE_GRENADE: "SMOG",
	PowerUpMode.BOXING_GLOVE: "FIST",
	PowerUpMode.MEGA_LEAP: "LEAP",
}

## One color per power-up. Drives both the pickup's mesh tint and the HUD Action
## caption color, so an item and its on-screen text always match.
const POWER_UP_COLORS := {
	PowerUpMode.SPEED_BURST: Color(0.25, 0.55, 1.0),   # blue
	PowerUpMode.THROWABLE: Color(1.0, 0.85, 0.15),     # yellow
	PowerUpMode.SMOKE_GRENADE: Color(0.45, 0.8, 0.4),  # smoke green
	PowerUpMode.BOXING_GLOVE: Color(1.0, 0.2, 0.2),    # red
	PowerUpMode.MEGA_LEAP: Color(0.65, 0.3, 1.0),      # purple
}

@export var power_up_mode: PowerUpMode = PowerUpMode.NONE

func power_up_label() -> String:
	return POWER_UP_LABELS.get(power_up_mode, "")

func power_up_color() -> Color:
	return POWER_UP_COLORS.get(power_up_mode, Color.WHITE)

## Godot's default 3D gravity. GRAVITY_SCALE is derived from the player so the item
## falls at the same rate the player does.
const DEFAULT_GRAVITY: float = 9.8
## GRAVITY in player.gd.
const GAME_GRAVITY: float = 18.0
const GRAVITY_SCALE: float = GAME_GRAVITY / DEFAULT_GRAVITY

## Where a carried item parents itself to on the holder. Defined in skin.tscn as a
## BoneAttachment3D on mixamorig_Spine1 plus an offset Node3D, so it rides the back
## of both the local player and every remote player.
const ATTACH_PATH: String = "Skeleton3D/Back/offset"
## Drops are capped so the item lands nearby instead of shooting across the map.
const MAX_DROP_SPEED: float = 4.0

## A consumed power-up teleports to a random spot at least this far (world units)
## from the holder, so it can never be re-grabbed immediately.
const RESPAWN_MIN_DISTANCE: float = 22.0
## Random probes attempted before falling back to the farthest valid point found.
const RESPAWN_TRIES: int = 32
const RESPAWN_PROBE_HEIGHT: float = 80.0
const RESPAWN_PROBE_DEPTH: float = 160.0
## Keeps respawns inside the minimap bounds so their pointers stay on the map.
const RESPAWN_EDGE_MARGIN: float = 5.0
const RESPAWN_GROUND_OFFSET: float = 1.0

@export var can_be_picked: bool = true
@export var mesh_offset_y: float = 0.25:
	set(value):
		mesh_offset_y = value
		if is_node_ready():
			_apply_mesh_offset()

var is_held: bool = false
var holder: Node3D = null

var _mesh: MeshInstance3D = null
var _attach_node: Node3D = null

# The local player body (layer 1, same as the world). Cached once so the pickup
# only scans for it one time after spawn.
var _ignored_local_player: Node = null
# True once add_collision_exception_with() has run for the cached body, so the
# physics-server call happens once per player node instead of every _process tick.
var _local_player_exception_active: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	# Run after the holder's AnimationTree and Skeleton3D, which both sit at the
	# default priority of 0. Without this the copy can read the bone pose before
	# it has been rewritten for this frame and the item trails by one frame.
	process_priority = 100
	# Layer 2 so the player Area3D (mask 2) detects it, like the chicken and lootbox.
	collision_layer = 2
	# Layer 1 is the world/terrain. The mask has to include it or the item falls
	# straight through the floor.
	collision_mask = 1
	# Match the player fall rate instead of Godot's default 9.8.
	gravity_scale = GRAVITY_SCALE
	# 30 physics ticks per second plus a 4 m/s drop is enough to tunnel a thin floor.
	continuous_cd = true
	# Never rotates. Locking all three angular axes stops Jolt from tumbling the item
	# while it falls, and keeps it facing the same way the whole time it is carried.
	axis_lock_angular_x = true
	axis_lock_angular_y = true
	axis_lock_angular_z = true
	# Kinematic so a carried item follows the player instead of being blocked by them.
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	# Falls from the moment the scene loads, before anything is picked up.
	freeze = false
	can_sleep = true
	_mesh = _find_mesh()
	_apply_mesh_offset()
	_apply_power_up_color()


func _find_mesh() -> MeshInstance3D:
	for child in get_children():
		if child is MeshInstance3D:
			return child
	return null


# Tints every mesh child with the power-up color. The scene's material_overrides
# are shared across instances, so each mesh gets its own duplicated material -
# otherwise coloring one pickup would recolor them all.
func _apply_power_up_color() -> void:
	var color := power_up_color()
	for child in get_children():
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		var base_mat := mi.material_override
		if base_mat is StandardMaterial3D:
			var mat: StandardMaterial3D = (base_mat as StandardMaterial3D).duplicate()
			mat.albedo_color = color
			mi.material_override = mat
		else:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = color
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mi.material_override = mat


func _apply_mesh_offset() -> void:
	if _mesh == null:
		_mesh = _find_mesh()
	if _mesh:
		_mesh.position.y = mesh_offset_y


# --- PLAYER.GD API ---
func can_pick_up() -> bool:
	return can_be_picked and not is_held


func is_being_held() -> bool:
	return is_held and is_instance_valid(holder)


func pick_up(by: Node3D) -> bool:
	if by == null or not can_pick_up():
		return false
	holder = by
	is_held = true
	# Carried items are invisible; the HUD indicator is the only feedback.
	visible = false
	# Frozen while carried so the player pose drives the item, not gravity.
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	# Drop back to a full body once released, so a re-drop simulates normally.
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	_resolve_attach_node()
	emit_signal("picked_up", self)
	return true


func drop(impulse: Vector3 = Vector3.ZERO) -> void:
	if not is_held:
		return
	is_held = false
	holder = null
	_attach_node = null
	visible = true
	var capped := impulse
	if capped.length() > MAX_DROP_SPEED:
		capped = capped.normalized() * MAX_DROP_SPEED
	# Never hand the engine a downward start, that would begin the item inside the floor.
	linear_velocity = Vector3(capped.x, maxf(capped.y, 1.0), capped.z)
	angular_velocity = Vector3.ZERO
	# Back to a normal dynamic body: Jolt takes the fall and rests it on the ground.
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = false
	emit_signal("dropped", self)


## Called when the holder USES the power-up. Instead of dropping the item at the
## player's feet, it is released and teleported to a random point on the map that
## is far from the holder, then dropped so it falls and rests there. No power-up
## effect is applied yet - this only recycles the pickup and frees the HUD slot.
func consume_and_respawn(from_position: Vector3) -> void:
	is_held = false
	holder = null
	_attach_node = null
	visible = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	var target := _pick_respawn_point(from_position)
	# Frozen while teleporting so Jolt never drags the body across the map.
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	global_position = target
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = false
	emit_signal("dropped", self)


# Picks a valid standing spot inside the minimap bounds, preferring one that is
# at least RESPAWN_MIN_DISTANCE away from the holder. Falls back to the farthest
# valid point if no probe clears the distance.
func _pick_respawn_point(from_position: Vector3) -> Vector3:
	var world_size: Vector2 = GameManager.minimap_world_size
	var world_origin: Vector2 = GameManager.minimap_origin
	if world_size.x <= 0.0 or world_size.y <= 0.0:
		world_size = Vector2(70.0, 70.0)
	var half_x: float = maxf(world_size.x * 0.5 - RESPAWN_EDGE_MARGIN, 1.0)
	var half_z: float = maxf(world_size.y * 0.5 - RESPAWN_EDGE_MARGIN, 1.0)
	var space := get_world_3d().direct_space_state
	var min_sq: float = RESPAWN_MIN_DISTANCE * RESPAWN_MIN_DISTANCE
	# Guaranteed fallback even if every probe misses (should not happen on land).
	var best: Vector3 = from_position + Vector3(half_x, 0.0, 0.0)
	var best_sq: float = -1.0
	for _i in RESPAWN_TRIES:
		var x: float = world_origin.x + randf_range(-half_x, half_x)
		var z: float = world_origin.y + randf_range(-half_z, half_z)
		var probe_start := Vector3(x, from_position.y + RESPAWN_PROBE_HEIGHT, z)
		var ground: Variant = _probe_ground(probe_start, space)
		if ground == null:
			continue
		var point: Vector3 = ground
		var dx: float = point.x - from_position.x
		var dz: float = point.z - from_position.z
		var d_sq: float = dx * dx + dz * dz
		if d_sq >= min_sq:
			return point
		if d_sq > best_sq:
			best_sq = d_sq
			best = point
	return best


# Casts straight down and returns the first world-layer (1) surface hit, raised a
# little so the item drops onto it rather than spawning inside it.
func _probe_ground(from: Vector3, space: PhysicsDirectSpaceState3D) -> Variant:
	var exclude: Array[RID] = [get_rid()]
	var query := PhysicsRayQueryParameters3D.create(
		from, from - Vector3(0.0, RESPAWN_PROBE_DEPTH, 0.0), 1, exclude
	)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null
	return hit.position + Vector3(0.0, RESPAWN_GROUND_OFFSET, 0.0)


# Resolves the holder's back attachment. Remote players are instances of the same
# skin scene, so this resolves for them too.
func _resolve_attach_node() -> void:
	_attach_node = null
	if not is_instance_valid(holder):
		return
	_attach_node = holder.get_node_or_null(ATTACH_PATH) as Node3D


# The player capsule and the world floor both live on collision layer 1, so no
# layer split can make the flag rest on the ground without also being shoved by
# the player. A collision exception removes exactly that one pair: the flag still
# falls and rests on the terrain, but walking into it never pushes it around.
# Area3D pickup detection (mask 2) is unaffected, so nearby grab still works.
func _ensure_local_player_exception() -> void:
	if _ignored_local_player != null and not is_instance_valid(_ignored_local_player):
		_ignored_local_player = null
		_local_player_exception_active = false
	if _ignored_local_player == null:
		_ignored_local_player = get_tree().get_first_node_in_group("local_player")
		if _ignored_local_player == null:
			return  # Player not spawned yet - try again next frame.
		_local_player_exception_active = false
	if not _local_player_exception_active and _ignored_local_player is CollisionObject3D:
		add_collision_exception_with(_ignored_local_player)
		_local_player_exception_active = true


# --- TICK ---
# Deliberately _process, not _physics_process. The holder's bone pose is written
# during the animation/skeleton pass of the idle frame, so reading it from the
# physics step returned last frame's bone and the flag visibly trailed the player
# at 30 Hz. Following once per rendered frame keeps it welded to the back with no
# extra interpolation.
func _process(_delta: float) -> void:
	_ensure_local_player_exception()
	if not is_held:
		# Dropped: the engine owns the transform, nothing to drive.
		return
	if not is_instance_valid(holder):
		# Holder was removed (player left, scene changed) - release the item.
		drop()
		return
	if _attach_node == null or not is_instance_valid(_attach_node):
		_resolve_attach_node()
	if _attach_node != null and is_instance_valid(_attach_node):
		# Only the position is copied. The item's own rotation is left completely
		# alone, so it does not turn with the player it is riding on.
		global_position = _attach_node.global_position
