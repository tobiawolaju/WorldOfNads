@tool
extends RigidBody3D
class_name LocalPickup2
## Weapon pickup: sword / AK47 / glock / knife / RPG.
##
## This is the weapon sibling of LocalPickup.gd (power-ups + objective items).
## A pickup named after a server id (w1..w5, see SERVER_WEAPON_KINDS) is
## SERVER-AUTHORITATIVE, exactly like a power-up: the server owns its spawn spot
## and who carries it, mirrors both to every client, and re-rolls the spot when
## the last charge is spent. Any other copy (e.g. one placed in a scene by hand)
## stays a local-only prop that recycles itself.
##
## Behaviour:
##   * One weapon model is shown on the ground, chosen by `weapon_kind`.
##   * A player grabs it like any other local pickup. The ground model disappears
##     and the matching mesh in skin.tscn is carried on the back
##     (`Skeleton3D/BackBoneAttachment3D/<name>`) — on every client, because the
##     holder is part of the server's item state. A swing/shot moves it to the
##     hand slot (`Skeleton3D/BoneAttachment3D`) for the clip and back again.
##   * Instead of a timer, a weapon has `uses` charges. Every press of the Action
##     button spends one, and the HUD ring drains 1/uses per press.
##   * When the last charge is spent both meshes are hidden again and the pickup
##     moves to a fresh far-away spot on the map, ready to be found.
##
## Physics (falling, resting, respawn probing) mirrors LocalPickup.gd so both
## pickup families feel identical in the hand and on the ground.

signal picked_up(item: RigidBody3D)
signal depleted(item: RigidBody3D)

## The group player.gd scans for weapon pickups. Kept separate from LocalPickup's
## "local_pickup_items" because a weapon is grabbed and spent differently.
const GROUP: String = "local_weapon_pickups"
## Also listed in the minimap's pickup group so weapons get a white map pointer.
const MINIMAP_GROUP: String = "local_pickup_items"

## Weapon roster. The names below are the ones authored in pickup2.tscn and in
## skin.tscn under Skeleton3D/BoneAttachment3D.
enum WeaponKind {
	NONE,
	SWORD,
	AK47,
	GLOCK,
	KNIFE,
	RPG
}

## The Action caption shown while a weapon is held. It is one shared 4-letter
## word (like the power-ups' GRAB / RUSH / TWIN) so it stacks in the same 4-line
## HUD caption, with the shared ACTION_COLOR below.
const ACTION_CAPTION: String = "FIRE"

## The Action button caption + ring colour for every weapon pickup (#ff6cff).
## One shared colour instead of per-weapon colours: it matches the pink weapon
## materials authored in pickup2.tscn / skin.tscn.
const ACTION_COLOR := Color(1.0, 0.42352942, 1.0)

## Node names under skin.tscn's two weapon slots - Skeleton3D/BoneAttachment3D
## (hand, drawn) and Skeleton3D/BackBoneAttachment3D (back, carried). These are
## also the model node names in pickup2.tscn, so one table drives all three.
const WEAPON_NODE_NAMES := {
	WeaponKind.SWORD: "sword",
	WeaponKind.AK47: "ak47",
	WeaponKind.GLOCK: "glock",
	WeaponKind.KNIFE: "Knife",
	WeaponKind.RPG: "rpg",
}

## The server-tracked weapon ids and the weapon each one spawns as. Mirrors the
## server's WEAPON_IDS roster (config.rs), so every client shows the same weapon
## at the same spot. A pickup whose node name is one of these ids is
## server-authoritative: the server owns its spot and who carries it, exactly like
## the power-ups (LocalPickup). Any other pickup stays a local-only prop.
const SERVER_WEAPON_KINDS := {
	"w1": WeaponKind.SWORD,
	"w2": WeaponKind.AK47,
	"w3": WeaponKind.GLOCK,
	"w4": WeaponKind.KNIFE,
	"w5": WeaponKind.RPG,
}

## How many Action presses a fresh weapon lasts.
const DEFAULT_USES: int = 8


## Shows exactly the weapon model of `kind` in one attachment slot of a skin rig
## (NONE hides the slot and every model in it). Both slots - the hand
## (Skeleton3D/BoneAttachment3D) and the back (Skeleton3D/BackBoneAttachment3D) -
## hold the same roster, so one call serves the local player, a remote copy and
## the lobby bots. A rig without that slot is left alone.
static func show_weapon_in_slot(rig: Node, slot_path: String, kind: int) -> void:
	if rig == null:
		return
	var slot := rig.get_node_or_null(slot_path) as Node3D
	if slot == null:
		return
	var wanted := String(WEAPON_NODE_NAMES.get(kind, ""))
	for node_name in WEAPON_NODE_NAMES.values():
		var node := slot.get_node_or_null(String(node_name)) as Node3D
		if node != null:
			node.visible = String(node_name) == wanted
	if wanted != "":
		# Both slots are weapon slots, so a slot that shows a weapon shows
		# nothing else. skin.tscn keeps a shield in each of them, and it must
		# not pop into the hand just because a swing made the slot visible.
		for child in slot.get_children():
			if child is Node3D and not WEAPON_NODE_NAMES.values().has(String(child.name)):
				(child as Node3D).visible = false
	slot.visible = wanted != ""


@export var weapon_kind: WeaponKind = WeaponKind.SWORD:
	set(value):
		weapon_kind = value
		_apply_weapon_visual()

@export_range(1, 99, 1) var uses: int = DEFAULT_USES

@export var can_be_picked: bool = true

## Extra height for the model above the body origin. The models in pickup2.tscn
## are already authored at ground level, so this only lifts them if a level needs
## it; the idle bob is added on top in _start_idle_anim().
@export var mesh_offset_y: float = 0.0:
	set(value):
		mesh_offset_y = value
		if is_node_ready():
			_apply_mesh_offset()

## Godot's default 3D gravity. GRAVITY_SCALE is derived from the player so the
## item falls at the same rate the player does.
const DEFAULT_GRAVITY: float = 9.8
## GRAVITY in player.gd.
const GAME_GRAVITY: float = 18.0
const GRAVITY_SCALE: float = GAME_GRAVITY / DEFAULT_GRAVITY

## A used-up weapon teleports at least this far from the player, so it can never
## be re-grabbed on the spot.
const RESPAWN_MIN_DISTANCE: float = 22.0
const RESPAWN_TRIES: int = 32
const RESPAWN_PROBE_HEIGHT: float = 80.0
const RESPAWN_PROBE_DEPTH: float = 160.0
## Keeps respawns inside the minimap bounds so their pointers stay on the map.
const RESPAWN_EDGE_MARGIN: float = 5.0
const RESPAWN_GROUND_OFFSET: float = 1.0
## Extra height above the terrain a server-placed weapon is dropped from, so it
## lands on uneven ground instead of spawning inside or under it.
const SPAWN_DROP_HEIGHT: float = 2.0

var is_held: bool = false
var holder: Node3D = null
## True while the ground model is out of play: the SERVER says another player is
## carrying it. Hidden and not grabbable.
var remote_held: bool = false
## True while the pickup is being re-seated (the last charge was spent, or the
## server picked a new spot) and must not be grabbed yet.
var respawning: bool = false

## Runtime pivot the weapon models are parented to, so the idle bob moves them as
## one unit without touching the physics body's transform.
var _pivot: Node3D = null
var _model_nodes: Dictionary = {}
var _idle_tween: Tween = null

## Cached local player for the collision exception (same trick as LocalPickup).
var _ignored_local_player: Node = null
var _local_player_exception_active: bool = false


# --- META ---------------------------------------------------------------
## The Action caption for any weapon (4 letters, see ACTION_CAPTION).
func weapon_label() -> String:
	return ACTION_CAPTION


func weapon_color() -> Color:
	return ACTION_COLOR


## Node name in skin.tscn this weapon shows while carried, or "" for NONE.
func weapon_node_name() -> String:
	return WEAPON_NODE_NAMES.get(weapon_kind, "")


## Lets player.gd tell a weapon pickup apart from a LocalPickup in the shared
## minimap group.
func is_weapon_pickup() -> bool:
	return true


## The server id this pickup reports under, or "" when it is a purely local prop.
## PlayerManager renames server-spawned weapons to their id (w1..w5), so the node
## name is the id.
func server_item_id() -> String:
	var pickup_name := String(name)
	if SERVER_WEAPON_KINDS.has(pickup_name):
		return pickup_name
	return ""


## The weapon kind a server id spawns as, or NONE for an unknown id.
static func kind_for_server_id(item_id: String) -> int:
	return int(SERVER_WEAPON_KINDS.get(item_id, WeaponKind.NONE))


## Tells the server this weapon was just grabbed (holding) or released. Only the
## LOCAL holder reports anything: every client owns its own copy, and only that
## copy ever has a local holder.
func _notify_server_hold(holding: bool, holder_node: Node3D = null) -> void:
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
	if pm == null:
		return
	if holding and pm.has_method("notify_item_held"):
		pm.call("notify_item_held", item_id)
	elif not holding and pm.has_method("notify_item_dropped"):
		pm.call("notify_item_dropped", item_id)


## Tells the server the weapon was spent, so it can re-roll a fresh spot.
func _notify_server_used() -> void:
	var item_id := server_item_id()
	if item_id == "":
		return
	var pm := get_tree().get_first_node_in_group("player_manager")
	if pm != null and pm.has_method("notify_item_used"):
		pm.call("notify_item_used", item_id)


# --- LIFECYCLE ----------------------------------------------------------
func _ready() -> void:
	if Engine.is_editor_hint():
		_apply_weapon_visual()
		return

	add_to_group(GROUP)
	add_to_group(MINIMAP_GROUP)
	# Run after the holder's AnimationTree/Skeleton3D, same reason as LocalPickup.
	process_priority = 100
	# Layer 2 so the player Area3D (mask 2) detects it.
	collision_layer = 2
	# Layer 1 is the world/terrain; without it the item falls through the floor.
	collision_mask = 1
	gravity_scale = GRAVITY_SCALE
	continuous_cd = true
	# Weapons rest on the ground without tumbling away.
	axis_lock_angular_x = true
	axis_lock_angular_y = true
	axis_lock_angular_z = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = false
	can_sleep = true

	_build_pivot()
	_apply_weapon_visual()
	_apply_mesh_offset()
	_start_idle_anim()


func _find_model_nodes() -> void:
	_model_nodes.clear()
	# Models live under the root until _build_pivot() runs, then under the pivot.
	var parent: Node = self
	if _pivot != null and is_instance_valid(_pivot):
		parent = _pivot
	for kind in WEAPON_NODE_NAMES.keys():
		var node_name: String = WEAPON_NODE_NAMES[kind]
		var node := parent.get_node_or_null(node_name) as Node3D
		if node != null:
			_model_nodes[kind] = node


## Creates a single pivot under the body and re-parents every weapon model to it,
## so the idle bob moves all of them together while the physics transform stays put.
func _build_pivot() -> void:
	# Resolve the models while they are still direct children of the body.
	_find_model_nodes()
	if _model_nodes.is_empty():
		return
	_pivot = get_node_or_null("WeaponPivot") as Node3D
	if _pivot == null:
		_pivot = Node3D.new()
		_pivot.name = "WeaponPivot"
		add_child(_pivot)
	for kind in _model_nodes.keys():
		var node: Node3D = _model_nodes[kind]
		if node.get_parent() != _pivot and node.get_parent() != null:
			# keep_global_transform = false: the pivot starts at the body origin
			# with an identity transform, so each model keeps its authored local
			# placement instead of being re-offset.
			node.reparent(_pivot, false)


## Shows exactly the model that belongs to this instance's weapon_kind.
func _apply_weapon_visual() -> void:
	_find_model_nodes()
	var wanted := weapon_node_name()
	for kind in _model_nodes.keys():
		var node: Node3D = _model_nodes[kind]
		if node != null and is_instance_valid(node):
			node.visible = WEAPON_NODE_NAMES[kind] == wanted


func _apply_mesh_offset() -> void:
	if _pivot != null and is_instance_valid(_pivot):
		_pivot.position.y = mesh_offset_y


# --- PLAYER.GD API ------------------------------------------------------
func can_pick_up() -> bool:
	return can_be_picked and not is_held and not remote_held and not respawning \
		and weapon_kind != WeaponKind.NONE


func is_being_held() -> bool:
	return (is_held and is_instance_valid(holder)) or remote_held


## Grab: the ground model vanishes and player.gd reveals the hand mesh.
func pick_up(by: Node3D) -> bool:
	if by == null or not can_pick_up():
		return false
	holder = by
	is_held = true
	visible = false
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	emit_signal("picked_up", self)
	_notify_server_hold(true)
	return true


## Every uses charge is spent: recycle the pickup so a fresh weapon can be found
## elsewhere on the map.
##
## A server-tracked weapon (w1..w5) is re-rolled by the SERVER: this only releases
## the hold, hides the model and reports the use, then waits for the new spot to
## arrive through apply_server_spawn(). A local-only prop still picks its own spot.
func deplete_and_respawn(from_position: Vector3) -> void:
	if is_held:
		is_held = false
		holder = null
	# Frozen while teleporting so Jolt never drags the body across the map.
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	if server_item_id() != "":
		# Hidden and un-grabbable until the server hands back a new position.
		# notify_item_used() also clears the local hold, so no separate drop
		# message is sent.
		respawning = true
		visible = false
		_notify_server_used()
		emit_signal("depleted", self)
		return
	# Visible again and parked until the new spot has been chosen. Still out of
	# play so the old spot cannot be re-grabbed in the frame between here and the
	# probe below.
	respawning = true
	visible = true
	# The spot probe needs the physics space, and this runs from an idle-frame
	# resume (the weapon clip's timer) as often as from a physics step. Jolt
	# refuses the query while the space is stepping, so probe on the next physics
	# frame instead of spamming "space state is inaccessible" and silently falling
	# back to the far-away default.
	await get_tree().physics_frame
	if not is_instance_valid(self) or not is_inside_tree():
		return
	global_position = _pick_respawn_point(from_position)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	respawning = false
	freeze = false
	_apply_mesh_offset()
	_start_idle_anim()
	emit_signal("depleted", self)


## Applies a spot chosen by the SERVER (round start, re-roll after the last
## charge, drop on death). The server only owns x/z: its y is a flat constant
## below the hilly terrain, so the model is seated on the ground at that x/z and
## left to settle.
func apply_server_spawn(target: Vector3) -> void:
	# Out of play until it is actually seated: the old spot may be right under a
	# player, and a visible-but-hidden-for-a-frame copy would flicker there.
	respawning = true
	visible = false
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	# Same space-state rule as deplete_and_respawn: this is reached from the
	# message pump, not from a physics step.
	await get_tree().physics_frame
	if not is_instance_valid(self) or not is_inside_tree():
		return
	global_position = _grounded_spawn_point(target)
	remote_held = false
	respawning = false
	visible = true
	freeze = false
	_apply_mesh_offset()
	_start_idle_anim()


## The SERVER says another player is carrying this weapon: hide the ground model
## so it cannot be grabbed twice. The carrier's hand mesh is driven by
## PlayerManager (player.show_remote_weapon), not here.
func set_remote_held(value: bool) -> void:
	if value == remote_held:
		return
	remote_held = value
	if value:
		visible = false
		freeze = true
		freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	else:
		freeze = false


## Drops a local hold WITHOUT telling the server (the server already decided who
## has this weapon). Hidden until the new spot arrives.
func release_silently() -> void:
	is_held = false
	holder = null
	remote_held = true
	visible = false
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


# --- PHYSICS ------------------------------------------------------------
## Picks a valid standing spot inside the minimap bounds, preferring one that is
## at least RESPAWN_MIN_DISTANCE away from the player.
func _pick_respawn_point(from_position: Vector3) -> Vector3:
	# Read the map bounds through the autoload NODE, not the `GameManager`
	# identifier: this script is parsed by headless --script tests before the
	# project's autoloads are registered, and a global identifier reference there
	# fails the whole file (and every script that depends on it) to compile.
	var manager := get_node_or_null("/root/GameManager")
	var world_size: Vector2 = Vector2(70.0, 70.0)
	var world_origin: Vector2 = Vector2.ZERO
	if manager != null:
		world_size = manager.get("minimap_world_size")
		world_origin = manager.get("minimap_origin")
	if world_size.x <= 0.0 or world_size.y <= 0.0:
		world_size = Vector2(70.0, 70.0)
	var half_x: float = maxf(world_size.x * 0.5 - RESPAWN_EDGE_MARGIN, 1.0)
	var half_z: float = maxf(world_size.y * 0.5 - RESPAWN_EDGE_MARGIN, 1.0)
	# Guaranteed fallback even if no probe can run (headless / no physics space).
	var best: Vector3 = from_position + Vector3(half_x, 0.0, 0.0)
	var world := get_world_3d()
	if world == null:
		return best
	var space := world.direct_space_state
	if space == null:
		return best
	var min_sq: float = RESPAWN_MIN_DISTANCE * RESPAWN_MIN_DISTANCE
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


## Picks a point above the terrain at the server's x/z so the model drops onto the
## ground instead of spawning inside or under it.
func _grounded_spawn_point(target: Vector3) -> Vector3:
	var world := get_world_3d()
	if world == null:
		return Vector3(target.x, target.y + SPAWN_DROP_HEIGHT, target.z)
	var space := world.direct_space_state
	if space == null:
		return Vector3(target.x, target.y + SPAWN_DROP_HEIGHT, target.z)
	var ground: Variant = _probe_ground(
		Vector3(target.x, target.y + RESPAWN_PROBE_HEIGHT, target.z), space
	)
	if ground == null:
		# Nothing below (over water/void, or the map has not streamed in yet):
		# keep the server's x/z and still drop from above.
		return Vector3(target.x, target.y + SPAWN_DROP_HEIGHT, target.z)
	var point: Vector3 = ground
	return Vector3(target.x, point.y + SPAWN_DROP_HEIGHT, target.z)


## Casts straight down and returns the first world-layer (1) surface hit, raised
## so the item drops onto it rather than spawning inside it.
func _probe_ground(from: Vector3, space: PhysicsDirectSpaceState3D) -> Variant:
	var exclude: Array[RID] = [get_rid()]
	var query := PhysicsRayQueryParameters3D.create(
		from, from - Vector3(0.0, RESPAWN_PROBE_DEPTH, 0.0), 1, exclude
	)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null
	return hit.position + Vector3(0.0, RESPAWN_GROUND_OFFSET, 0.0)


## Same one-pair collision exception LocalPickup uses: the ground and the player
## both live on layer 1, so without this the player would shove resting pickups.
func _ensure_local_player_exception() -> void:
	if _ignored_local_player != null and not is_instance_valid(_ignored_local_player):
		_ignored_local_player = null
		_local_player_exception_active = false
	if _ignored_local_player == null:
		_ignored_local_player = get_tree().get_first_node_in_group("local_player")
		if _ignored_local_player == null:
			return
		_local_player_exception_active = false
	if not _local_player_exception_active and _ignored_local_player is CollisionObject3D:
		add_collision_exception_with(_ignored_local_player)
		_local_player_exception_active = true


# --- TICK ---------------------------------------------------------------
func _start_idle_anim() -> void:
	if _pivot == null or not is_instance_valid(_pivot):
		return
	if _idle_tween != null and _idle_tween.is_valid():
		_idle_tween.kill()
	_idle_tween = create_tween()
	_idle_tween.set_loops()
	_idle_tween.tween_property(_pivot, "position:y", mesh_offset_y + 0.12, 0.9)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.tween_property(_pivot, "position:y", mesh_offset_y, 0.9)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.tween_interval(0.4)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_ensure_local_player_exception()
	if is_held:
		if _idle_tween != null and _idle_tween.is_valid():
			_idle_tween.kill()
			_idle_tween = null
		return
	if _idle_tween == null or not _idle_tween.is_valid():
		_start_idle_anim()
