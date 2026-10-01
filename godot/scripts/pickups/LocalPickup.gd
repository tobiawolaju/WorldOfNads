extends RigidBody3D
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


func _find_mesh() -> MeshInstance3D:
	for child in get_children():
		if child is MeshInstance3D:
			return child
	return null


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


# Resolves the holder's back attachment. Remote players are instances of the same
# skin scene, so this resolves for them too.
func _resolve_attach_node() -> void:
	_attach_node = null
	if not is_instance_valid(holder):
		return
	_attach_node = holder.get_node_or_null(ATTACH_PATH) as Node3D


# --- TICK ---
# Deliberately _process, not _physics_process. The holder's bone pose is written
# during the animation/skeleton pass of the idle frame, so reading it from the
# physics step returned last frame's bone and the flag visibly trailed the player
# at 30 Hz. Following once per rendered frame keeps it welded to the back with no
# extra interpolation.
func _process(_delta: float) -> void:
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
