extends RigidBody3D
class_name LocalPickup
## Pickup item: the power-ups and the objective items (chicken / lootbox).
##
## The SERVER owns every item's spawn spot and who is carrying it. Clients mirror
## the server position (apply_server_spawn) and hide a power-up while it is in
## someone's inventory; the server re-rolls the spot when a power-up is used and
## drops the item where its holder died or disconnected.
##
## The local copy still drives the two things physics needs to feel right: a
## carried item rides its holder (the local player's own copy is driven here, a
## remote holder's copy by PlayerManager) and a dropped item falls and rests on
## the terrain. Only the LOCAL holder reports grabs / drops / uses to the server,
## which then mirrors the claim to everyone else.
##
## Falling and resting are left to the physics engine. The body is frozen while it
## is being carried or held remotely; the moment it is released it is unfrozen and
## Jolt simulates the fall, so the item lands on the terrain and stays there.
##
## player.gd finds these through the "local_pickup_items" group. They must NOT be
## added to the "pickup_items" group (that group was reserved for the old
## server-synced chicken and lootbox).

signal picked_up(item: RigidBody3D)
signal dropped(item: RigidBody3D)

const GROUP: String = "local_pickup_items"

## Power-up roster — foundation only, no activation mechanics yet. Set this on
## each pickup instance in the editor. When a pickup with a non-NONE mode is
## picked up, player.gd shows its label in the HUD Action button.
enum PowerUpMode {
	NONE,
	SPEED_BURST,    # 8s of boosted run speed
	TWIN,           # spawn a decoy clone that mirrors your movement for 8s
	SMOKE_GRENADE,  # temporary smoke cloud that blocks vision
	MEGA_LEAP,      # one super high jump, consumed on use
	CHICKEN,        # the objective chicken — server tracks its holder (winner)
	LOOTBOX         # the objective lootbox — server tracks its holder (2nd place)
}

const POWER_UP_LABELS := {
	PowerUpMode.SPEED_BURST: "RUSH",
	PowerUpMode.TWIN: "TWIN",
	PowerUpMode.SMOKE_GRENADE: "SMOG",
	PowerUpMode.MEGA_LEAP: "LEAP",
	PowerUpMode.CHICKEN: "CHICKEN",
	PowerUpMode.LOOTBOX: "LOOTBOX",
}

## One color per power-up. Drives both the pickup's mesh tint and the HUD Action
## caption color, so an item and its on-screen text always match.
const POWER_UP_COLORS := {
	PowerUpMode.SPEED_BURST: Color(0.25, 0.55, 1.0),   # blue
	PowerUpMode.TWIN: Color(1.0, 0.85, 0.15),          # yellow
	PowerUpMode.SMOKE_GRENADE: Color(0.45, 0.8, 0.4),  # smoke green
	PowerUpMode.MEGA_LEAP: Color(0.65, 0.3, 1.0),      # purple
	PowerUpMode.CHICKEN: Color(0.98, 0.8, 0.3),        # gold
	PowerUpMode.LOOTBOX: Color(0.35, 0.68, 1.0),       # blue
}

## Mesh tints while an objective item is being carried. The chicken rides the
## back in yellow, the lootbox in purple; both return to white on release.
const HELD_CHICKEN_TINT := Color(1.0, 0.9, 0.1)
const HELD_LOOTBOX_TINT := Color(0.65, 0.3, 1.0)

@export var power_up_mode: PowerUpMode = PowerUpMode.NONE

func power_up_label() -> String:
	return POWER_UP_LABELS.get(power_up_mode, "")

func power_up_color() -> Color:
	return POWER_UP_COLORS.get(power_up_mode, Color.WHITE)


# Objective items (chicken / lootbox) report their hold state to the server so
# it can resolve the match winner. Returns the item id string the server's
# pickup_request / drop_request protocol understands, or "" for normal pickups.
func objective_item_id() -> String:
	match power_up_mode:
		PowerUpMode.CHICKEN:
			return "Chicken"
		PowerUpMode.LOOTBOX:
			return "LootBox"
	return ""


func is_objective_item() -> bool:
	return objective_item_id() != ""


# The item id the server tracks this pickup under. Objective items report their
# dedicated ids; the power-ups report their node name (p1, p2, p3, p5 -- p4 is
# retired along with the removed HOOK power-up). Returns "" for any pickup the
# server does not know about, so unsynced items stay silent.
func server_item_id() -> String:
	if is_objective_item():
		return objective_item_id()
	var pickup_name := String(name)
	if pickup_name in ["p1", "p2", "p3", "p5"]:
		return pickup_name
	return ""


# Tells the server this item was just grabbed (holding) or released. Every item
# is server-authoritative now, so both power-ups and objective items report the
# claim. Only copies held by the LOCAL player report anything — every client owns
# its own copy, and only the local copy ever has a local holder.
func _notify_server_hold(holding: bool, holder_node: Node3D = null) -> void:
	# Never fall back to a freed holder reference: by the time a claim is over
	# (drop / scene teardown / network loss) the claimant node may be gone.
	var claimant: Node3D = null
	if holder_node != null and is_instance_valid(holder_node):
		claimant = holder_node
	elif is_instance_valid(holder):
		claimant = holder
	if claimant == null or not claimant.is_in_group("local_player"):
		return
	var item_id := server_item_id()
	if item_id == "":
		return
	var pm := get_tree().get_first_node_in_group("player_manager")
	if pm == null or not (pm.has_method("notify_item_held") and pm.has_method("notify_item_dropped")):
		return
	if holding:
		pm.call("notify_item_held", item_id)
	else:
		pm.call("notify_item_dropped", item_id)


# Tells the server a carried power-up was USED, so it can re-roll a new spot.
func _notify_server_used(holder_node: Node3D = null) -> void:
	var claimant: Node3D = null
	if holder_node != null and is_instance_valid(holder_node):
		claimant = holder_node
	elif is_instance_valid(holder):
		claimant = holder
	if claimant == null or not claimant.is_in_group("local_player"):
		return
	var item_id := server_item_id()
	if item_id == "":
		return
	var pm := get_tree().get_first_node_in_group("player_manager")
	if pm != null and pm.has_method("notify_item_used"):
		pm.call("notify_item_used", item_id)

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
## Extra height above the terrain that a server-placed item is dropped from, so it
## lands on uneven ground instead of spawning inside or under it.
const SPAWN_DROP_HEIGHT: float = 2.0

@export var can_be_picked: bool = true
@export var mesh_offset_y: float = 0.25:
	set(value):
		mesh_offset_y = value
		if is_node_ready():
			_apply_mesh_offset()

var is_held: bool = false
var holder: Node3D = null
# True while the SERVER says another player is carrying this item. Only the local
# holder gets is_held; remote holders are tracked here so the node cannot be
# grabbed locally and drops off the minimap while it rides someone else.
var remote_held: bool = false
# True between "the local player used this power-up" and the server handing back
# the item's new spot. Blocks a re-grab at the old (consumed) position.
var _awaiting_server_spawn: bool = false

var _mesh: MeshInstance3D = null
# Every mesh child of the pickup, so a while-held tint covers all of them. Each
# gets its own material copy (see _ready) because the scene sub-resources are
# shared by every pickup instance.
var _mesh_instances: Array[MeshInstance3D] = []
var _attach_node: Node3D = null

# The local player body (layer 1, same as the world). Cached once so the pickup
# only scans for it one time after spawn.
var _ignored_local_player: Node = null
# True once add_collision_exception_with() has run for the cached body, so the
# physics-server call happens once per player node instead of every _process tick.
var _local_player_exception_active: bool = false


var _idle_tween: Tween = null

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
	_apply_mode_visual()
	# Copy the materials so a tint never mutates the shared scene sub-resource
	# (every pickup instance references the same StandardMaterial3D otherwise).
	for child in get_children():
		if child is MeshInstance3D:
			_mesh_instances.append(child)
			if child.material_override != null:
				child.material_override = child.material_override.duplicate()
	_apply_glow()
	_start_idle_anim()


func _find_mesh() -> MeshInstance3D:
	for child in get_children():
		if child is MeshInstance3D:
			return child
	return null


# True for the modes that are carried and used as a power-up (everything except
# NONE and the two objective items).
func is_power_up_item() -> bool:
	match power_up_mode:
		PowerUpMode.SPEED_BURST, PowerUpMode.TWIN, PowerUpMode.SMOKE_GRENADE, \
		PowerUpMode.MEGA_LEAP:
			return true
	return false


# Shows the one authored model that belongs to this pickup's mode in pickup.tscn:
# "chick" for the objective chicken, "loot" for the objective lootbox and
# "powerup" for any of the four power-ups. The other two stay hidden, including
# for NONE pickups.
func _apply_mode_visual() -> void:
	var chick_visual := get_node_or_null("chick") as Node3D
	var loot_visual := get_node_or_null("loot") as Node3D
	var powerup_visual := get_node_or_null("powerup") as Node3D
	if chick_visual != null:
		chick_visual.visible = power_up_mode == PowerUpMode.CHICKEN
	if loot_visual != null:
		loot_visual.visible = power_up_mode == PowerUpMode.LOOTBOX
	if powerup_visual != null:
		powerup_visual.visible = is_power_up_item()


func _apply_mesh_offset() -> void:
	if _mesh == null:
		_mesh = _find_mesh()
	if _mesh:
		_mesh.position.y = mesh_offset_y


# Tints every mesh child's material. Materials were duplicated per-instance in
# _ready, so only this pickup's copy is affected.
func _tint_mesh(color: Color) -> void:
	for mi in _mesh_instances:
		if mi == null or not is_instance_valid(mi):
			continue
		var mat := mi.material_override
		if mat is StandardMaterial3D:
			mat.albedo_color = color


# Yellow while the chicken is carried, purple while the lootbox is carried.
func _held_tint_color() -> Color:
	match power_up_mode:
		PowerUpMode.CHICKEN:
			return HELD_CHICKEN_TINT
		PowerUpMode.LOOTBOX:
			return HELD_LOOTBOX_TINT
	return Color.WHITE


# --- PLAYER.GD API ---
func can_pick_up() -> bool:
	if not can_be_picked or is_held or _awaiting_server_spawn:
		return false
	# Objective items (chicken / lootbox) can be snatched off another player, so a
	# remote hold does not block them. A carried power-up is "in inventory" and
	# cannot be grabbed from its carrier.
	if remote_held and not is_objective_item():
		return false
	return true


func is_being_held() -> bool:
	return (is_held and is_instance_valid(holder)) or remote_held


func pick_up(by: Node3D) -> bool:
	if by == null or not can_pick_up():
		return false
	holder = by
	is_held = true
	# Ordinary pickups hide while carried (the HUD indicator is the only
	# feedback); objective items (chicken / lootbox) stay visible so the holder
	# sees them riding on their back, tinted yellow (chicken) or purple (lootbox).
	if not is_objective_item():
		visible = false
	else:
		_tint_mesh(_held_tint_color())
	# Frozen while carried so the player pose drives the item, not gravity.
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	# Drop back to a full body once released, so a re-drop simulates normally.
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	_resolve_attach_node()
	emit_signal("picked_up", self)
	_notify_server_hold(true)
	return true


func drop(impulse: Vector3 = Vector3.ZERO) -> void:
	if not is_held:
		return
	var dropped_by := holder
	is_held = false
	holder = null
	_attach_node = null
	visible = true
	_tint_mesh(Color.WHITE)
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
	# The holder may already be freed (player removed on network loss / scene
	# teardown); passing it here crashes the typed call, so pass no claim then.
	_notify_server_hold(false, dropped_by if is_instance_valid(dropped_by) else null)


## Called when the holder USES the power-up. Instead of dropping the item at the
## player's feet, it is released and teleported to a random point on the map that
## is far from the holder, then dropped so it falls and rests there. No power-up
## effect is applied yet - this only recycles the pickup and frees the HUD slot.
func consume_and_respawn(from_position: Vector3) -> void:
	var released_by := holder
	is_held = false
	holder = null
	_attach_node = null
	visible = true
	_tint_mesh(Color.WHITE)
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
	# Same freed-holder guard as drop(): release claims nothing if the holder
	# (e.g. local player) was already destroyed.
	_notify_server_hold(false, released_by if is_instance_valid(released_by) else null)


## Server-authoritative consume: the local player used this power-up. Unlike
## consume_and_respawn() the new spot is chosen by the SERVER, so this only
## releases the hold and hides the item until the server hands back a new
## position (apply_server_spawn). No local random respawn is performed.
func consume_for_server() -> void:
	var released_by := holder
	is_held = false
	holder = null
	_attach_node = null
	remote_held = false
	_awaiting_server_spawn = true
	# Hidden and parked until the server assigns the new spot.
	visible = false
	_tint_mesh(Color.WHITE)
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	emit_signal("dropped", self)
	_notify_server_used(released_by if is_instance_valid(released_by) else null)


## Applies a position chosen by the server. Used for match-start spawns,
## respawns after a use, and drops (death / disconnect / manual). Drops the item
## above the terrain at the server's x/z so it settles on the ground, cancels any
## pending consume, and makes it grabbable again.
func apply_server_spawn(target: Vector3) -> void:
	_awaiting_server_spawn = false
	remote_held = false
	visible = true
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	# The server only owns the spot on the HORIZONTAL plane (x/z). Its y is a flat
	# constant that sits below the hilly terrain, so seating the item there buries
	# it or drops it through the map. Spawn it ABOVE the terrain at that x/z and let
	# gravity drop it onto the ground.
	global_position = _grounded_spawn_point(target)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	# Unfreeze so physics can settle it onto the terrain. PlayerManager re-seats
	# only on a horizontal change, so the fall does not fight the heartbeat.
	freeze = false


# Picks a point above the terrain at the server's x/z so the item drops and rests
# on the ground instead of spawning inside or under it.
func _grounded_spawn_point(target: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var ground: Variant = _probe_ground(
		Vector3(target.x, target.y + RESPAWN_PROBE_HEIGHT, target.z), space
	)
	if ground == null:
		# Nothing below (over water/void, or the map has not streamed in yet):
		# keep the server's x/z but still drop from the probe height rather than
		# seat at a flat y that may be under the map.
		return Vector3(target.x, target.y + RESPAWN_PROBE_HEIGHT, target.z)
	var point: Vector3 = ground
	return Vector3(target.x, point.y + SPAWN_DROP_HEIGHT, target.z)


## Marks the item as carried by ANOTHER player (server says so). `by` is the remote
## holder's node whenever the caller knows it: the copy then rides the SAME back
## attachment the local holder uses (`Skeleton3D/Back/offset`), so it lands where the
## item was authored to sit instead of on an offset measured from the holder's feet.
## Without `by` the item is only frozen in place, which is all the hidden power-ups
## need. Visibility stays with PlayerManager.
func set_remote_held(value: bool, by: Node3D = null) -> void:
	# Called every frame for as long as the item is carried, so bail out while
	# nothing about the hold has actually changed (re-tinting each frame is waste).
	if value == remote_held and (not value or by == holder):
		return
	remote_held = value
	if value:
		if not is_held:
			holder = by
		freeze = true
		freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		# Objective items stay visible while carried, so they need the same carried
		# tint their holder sees.
		if is_objective_item():
			_tint_mesh(_held_tint_color())
		_resolve_attach_node()
	else:
		if not is_held:
			holder = null
			_attach_node = null
		freeze = false
		_tint_mesh(Color.WHITE)


## Releases a local hold WITHOUT telling the server (used when the server says
## the item was snatched by someone else). The node is hidden until the server
## announces its new position.
func release_silently() -> void:
	is_held = false
	holder = null
	_attach_node = null
	visible = false
	_tint_mesh(Color.WHITE)
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


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

func _start_idle_anim() -> void:
	if _idle_tween != null and _idle_tween.is_valid():
		_idle_tween.kill()
	_idle_tween = create_tween()
	_idle_tween.set_loops()
	if _mesh != null:
		_idle_tween.tween_property(_mesh, "position:y", mesh_offset_y + 0.12, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_idle_tween.tween_property(_mesh, "position:y", mesh_offset_y, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.tween_interval(0.4)

func _apply_glow() -> void:
	var c := power_up_color()
	if is_objective_item():
		c = c.lightened(0.25)
	for mi in _mesh_instances:
		if mi == null or not is_instance_valid(mi):
			continue
		var mat := mi.material_override
		if mat is StandardMaterial3D:
			mat.emission_enabled = true
			mat.emission = c
			mat.emission_energy_multiplier = 0.6
			mat.emission_operator = BaseMaterial3D.EMISSION_OP_ADD

func _process(_delta: float) -> void:
	_ensure_local_player_exception()
	# A free item spins and bobs where it lies; a carried one rides its holder, local
	# or remote, so it must not spin.
	if not is_held and not remote_held:
		if _mesh != null:
			_mesh.rotate_y(_delta * 0.8)
		if _idle_tween == null or not _idle_tween.is_valid():
			_start_idle_anim()
		return
	if _idle_tween != null and _idle_tween.is_valid():
		_idle_tween.kill()
		_idle_tween = null
		# The bob tween lifts the mesh up to 0.12 above its resting offset; killing it
		# mid-flight would leave the item stuck that far off the holder's back.
		_apply_mesh_offset()
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
