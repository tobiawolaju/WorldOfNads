@tool
extends RigidBody3D
class_name LocalPickup2
## Local-only WEAPON pickup: sword / AK47 / glock / knife / RPG.
##
## This is the weapon sibling of LocalPickup.gd (power-ups + objective items).
## It is deliberately client-side only for now: nothing is sent to the server, so
## every player picks up and spends their own weapons.
##
## Behaviour:
##   * One weapon model is shown on the ground, chosen by `weapon_kind`.
##   * A player grabs it like any other local pickup. The ground model disappears
##     and the matching mesh in skin.tscn (`Skeleton3D/BoneAttachment3D/<name>`)
##     becomes visible in the left hand.
##   * Instead of a timer, a weapon has `uses` charges. Every press of the Action
##     button spends one, and the HUD ring drains 1/uses per press.
##   * When the last charge is spent the hand mesh is hidden again and the pickup
##     is teleported to a fresh far-away spot on the map, ready to be found.
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

## Node names under Skeleton3D/BoneAttachment3D (skin.tscn). These are also the
## model node names in pickup2.tscn, so one table drives both scenes.
const WEAPON_NODE_NAMES := {
	WeaponKind.SWORD: "sword",
	WeaponKind.AK47: "ak47",
	WeaponKind.GLOCK: "glock",
	WeaponKind.KNIFE: "Knife",
	WeaponKind.RPG: "rpg",
}

## How many Action presses a fresh weapon lasts.
const DEFAULT_USES: int = 8

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

var is_held: bool = false
var holder: Node3D = null

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
	return can_be_picked and not is_held and weapon_kind != WeaponKind.NONE


func is_being_held() -> bool:
	return is_held and is_instance_valid(holder)


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
	return true


## Every uses charge is spent: recycle the pickup to a far-away spot so a fresh
## weapon can be found elsewhere on the map.
func deplete_and_respawn(from_position: Vector3) -> void:
	if is_held:
		is_held = false
		holder = null
	# Visible again and parked until the new spot has been chosen.
	visible = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	# Frozen while teleporting so Jolt never drags the body across the map.
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	global_position = _pick_respawn_point(from_position)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = false
	_apply_mesh_offset()
	_start_idle_anim()
	emit_signal("depleted", self)


# --- PHYSICS ------------------------------------------------------------
## Picks a valid standing spot inside the minimap bounds, preferring one that is
## at least RESPAWN_MIN_DISTANCE away from the player.
func _pick_respawn_point(from_position: Vector3) -> Vector3:
	var world_size: Vector2 = GameManager.minimap_world_size
	var world_origin: Vector2 = GameManager.minimap_origin
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
