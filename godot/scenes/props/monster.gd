@tool
extends Node3D
## Rig-like pose helper for the blocky monster model.
## Explicitly controls imported limb nodes so they can be posed/animated in code.

const MODEL_ROOT_PATH: NodePath = ^"_76"

const DEFAULT_LIMB_PATHS: Array[NodePath] = [
	^"_76/RiteLeg_2",
	^"_76/LeftLeg_5",
	^"_76/RiteLeg_2/shin_r",
	^"_76/LeftLeg_5/shin_l",
	^"_76/bone_11",
	^"_76/bone2_15",
	^"_76/bone3_19",
	^"_76/bone4_29",
	^"_76/bone5_39",
	^"_76/bone6_56",
	^"_76/bone7_60",
	^"_76/RiteLeg_2/shin_r/foot_r",
	^"_76/LeftLeg_5/shin_l/foot_l",
]

# Baseline T-pose offsets applied on top of each limb's rest transform.
# Mapping inferred from mesh bounds/positions (not node names):
#   RiteLeg_2  = right thigh (hip joint)
#   LeftLeg_5  = left thigh (hip joint)
#   shin_r     = right shin (knee joint, child of RiteLeg_2)
#   shin_l     = left shin (knee joint, child of LeftLeg_5)
#   bone_11    = torso/body (large central mass)
#   bone2_15   = left upper arm
#   bone3_19   = right upper arm
#   bone4_29   = left lower arm / hand
#   bone5_39   = right lower arm / hand
#   bone6_56   = head
#   bone7_60   = head top
#   foot_r     = right foot (ankle, child of shin_r)
#   foot_l     = left foot (ankle, child of shin_l)
# Tweak these after in-editor confirmation.
const T_POSE_ROTATION_DEGREES := {
	"RiteLeg_2": Vector3.ZERO,
	"LeftLeg_5": Vector3.ZERO,
	"shin_r": Vector3.ZERO,
	"shin_l": Vector3.ZERO,
	"bone_11": Vector3.ZERO,
	"bone2_15": Vector3(0.0, 0.0, -90.0),   # left upper arm out to side (-X)
	"bone3_19": Vector3(0.0, 0.0, 90.0),    # right upper arm out to side (+X)
	"bone4_29": Vector3(0.0, 0.0, 0.0),     # left lower arm/hand follows upper arm
	"bone5_39": Vector3(0.0, 0.0, 0.0),     # right lower arm/hand follows upper arm
	"bone6_56": Vector3.ZERO,
	"bone7_60": Vector3.ZERO,
	"foot_r": Vector3.ZERO,                 # ankle pivot is the node origin
	"foot_l": Vector3.ZERO,
}

# Optional local-space pivot points for rotating a limb around a joint instead of
# its node origin. Coordinates are in the limb node's local/rest space.
# Derived from manually placed joint Marker3D nodes in the scene (rest pose).
const LIMB_PIVOTS := {
	"RiteLeg_2": Vector3(0.222713, 0.27232, 0.001002),  # joint_hip_r_m
	"LeftLeg_5": Vector3(0.214869, 0.761506, -0.063002),# joint_hip_l_m
	# shin_r / shin_l: knee joint is at the node origin (joint_knee_*_m marker).
	"bone2_15": Vector3(-0.267812, 2.982029, 0.0),      # joint_shoulder_l_m
	"bone3_19": Vector3(0.462308, 2.935738, 0.0),       # joint_shoulder_r_m
	"bone4_29": Vector3(-0.50096, 2.006245, 0.382366),  # joint_elbow_l_m
	"bone5_39": Vector3(-0.661093, 1.994093, 0.164146), # joint_elbow_r_m
	"bone6_56": Vector3(0.0, 0.0, 0.0),                 # joint_neck_m
	"bone_11": Vector3(0.061926, 1.98511, 0.032002),   # waist (midpoint of hip markers)
}

# Shared joint points in _76 parent space (from the manually placed markers).
const SHOULDER_L := Vector3(-0.267812, 2.982029, 0.0)      # joint_shoulder_l_m
const SHOULDER_R := Vector3(0.462308, 2.935738, 0.0)       # joint_shoulder_r_m
const WAIST := Vector3(0.061926, 1.98511, 0.032002)       # midpoint of hip markers
const NECK := Vector3(0.086027, 3.01905, -0.1328125)       # joint_neck_m

# Simple arm chains: [upper_arm, lower_arm_or_hand, shoulder_point_in_parent_space]
# The lower segment is a sibling node (not a child), so to make it follow the upper
# arm it must be rotated around the SAME shoulder point by the SAME offset.
const ARM_CHAINS := [
	["bone2_15", "bone4_29", SHOULDER_L],
	["bone3_19", "bone5_39", SHOULDER_R],
]

@export var t_pose: bool = false:
	set(value):
		t_pose = value
		_ensure_initialized()
		_apply_pose_state()

@export_group("Limb Nodes")
## Limb/body nodes to control. Leave empty to use the explicit monster limb list.
@export var limb_paths: Array[NodePath] = []

@export_group("Animation")
## Simple procedural walk cycle toggle (applies when t_pose is off).
@export var walk: bool = false:
	set(value):
		walk = value
		_walk_time = 0.0
		if _ready_done and not walk and not t_pose:
			_restore_rest_pose()
## Walk cycle speed multiplier.
@export var walk_speed: float = 4.0
## Limb swing amplitude in degrees.
@export var walk_amplitude: float = 22.0

## Ground-slash attack toggle: wide stance plus a looping claw swipe at the ground.
@export var attack: bool = false:
	set(value):
		attack = value
		_attack_time = 0.0
		if _ready_done and not attack and not walk and not t_pose:
			_restore_rest_pose()
## Attack cycle speed (cycles per second).
@export var attack_speed: float = 1.6
## How far the striking arm reaches, in degrees.
@export var attack_amplitude: float = 60.0
## Leg splay used for the wide attack stance, in degrees. Negative values push the knees wider apart for this rig.
@export var attack_stance_degrees: float = -26.0

@export_group("Debug")
## Preview poses/walk/attack in the editor. The rest pose is auto-restored on save,
## so enabling this never bakes a pose into the scene file.
@export var editor_preview: bool = true
## Extra rotation applied to every assigned limb when t_pose is enabled (for visibility/testing).
@export var t_pose_debug_extra_rotation: Vector3 = Vector3.ZERO
## Toggle on to recapture the current limb transforms as the new rest pose baseline.
@export var recapture_rest_pose: bool = false:
	set(value):
		if value:
			_ensure_initialized(true)
			_cache_rest_transforms(true)
			if t_pose:
				_apply_t_pose()
			elif not walk:
				_restore_rest_pose()
		recapture_rest_pose = false

var _rest_transforms: Dictionary = {} # instance_id -> Transform3D
var _limb_nodes: Array[Node3D] = []
var _limbs_by_name: Dictionary = {} # String -> Node3D
var _initialized: bool = false
var _ready_done: bool = false
var _walk_time: float = 0.0
var _attack_time: float = 0.0

func _ready() -> void:
	_ready_done = true
	_ensure_initialized(true)
	_apply_pose_state()
	set_process(true)

func _notification(what: int) -> void:
	# In the editor, always write the rest pose to disk: never bake a pose into the scene.
	# 9001 == NOTIFICATION_EDITOR_PRE_SAVE (Node), used numerically to stay version-safe.
	if not Engine.is_editor_hint():
		return
	if what == 9001:
		if _limb_nodes.is_empty():
			return
		_restore_rest_pose()

func _process(delta: float) -> void:
	if not _ready_done and not Engine.is_editor_hint():
		return
	if Engine.is_editor_hint() and not editor_preview:
		return
	_ensure_initialized()
	if t_pose or _limb_nodes.is_empty():
		return
	if attack:
		_attack_time += delta * attack_speed * TAU
		_apply_attack_cycle(_attack_time)
		return
	if not walk:
		return
	_walk_time += delta * walk_speed
	_apply_walk_cycle(_walk_time)

func _ensure_initialized(force_refresh: bool = false) -> void:
	if not is_inside_tree():
		return
	if _initialized and not force_refresh and not _limb_nodes.is_empty():
		return
	_resolve_limb_nodes()
	_cache_rest_transforms(false)
	_initialized = not _limb_nodes.is_empty()

func _resolve_limb_nodes() -> void:
	_limb_nodes.clear()
	_limbs_by_name.clear()

	var paths := limb_paths
	if paths.is_empty():
		paths = DEFAULT_LIMB_PATHS.duplicate()

	for p in paths:
		var n := _find_limb_node(p)
		if n:
			_limb_nodes.append(n)
			_limbs_by_name[n.name] = n
		else:
			push_warning("Monster rig: limb node not found: %s" % [str(p)])

	if _limb_nodes.is_empty():
		var model_root := get_node_or_null(MODEL_ROOT_PATH)
		if model_root == null:
			model_root = find_child("_76", true, false)
		if model_root:
			for child in model_root.get_children():
				if child is Node3D:
					_limb_nodes.append(child)
					_limbs_by_name[child.name] = child

func _find_limb_node(path_or_name: NodePath) -> Node3D:
	var n := get_node_or_null(path_or_name)
	if n is Node3D:
		return n
	var s := String(path_or_name)
	var leaf := s.get_file() if s.get_file() != "" else s
	var found := find_child(leaf, true, false)
	if found is Node3D:
		return found
	return null

func _cache_rest_transforms(force: bool = false) -> void:
	if not force and not _rest_transforms.is_empty():
		return
	_rest_transforms.clear()
	for n in _limb_nodes:
		if is_instance_valid(n):
			_rest_transforms[n.get_instance_id()] = n.transform

func _apply_pose_state() -> void:
	if Engine.is_editor_hint() and not editor_preview:
		return
	_ensure_initialized()
	if _limb_nodes.is_empty():
		return
	if t_pose:
		_apply_t_pose()
	else:
		_restore_rest_pose()

func _apply_t_pose() -> void:
	# Start from rest pose for all controlled limbs.
	for n in _limb_nodes:
		if not is_instance_valid(n):
			continue
		var rest: Transform3D = _rest_transforms.get(n.get_instance_id(), n.transform)
		n.transform = rest

	var posed := {}

	# Pose arm chains so lower arm/hand follows upper arm and stays connected.
	for chain in ARM_CHAINS:
		var upper_name: String = chain[0]
		var lower_name: String = chain[1]
		var shoulder_parent: Vector3 = chain[2]
		var upper := get_limb_node(upper_name)
		var lower := get_limb_node(lower_name)
		var upper_offset: Vector3 = T_POSE_ROTATION_DEGREES.get(upper_name, Vector3.ZERO) + t_pose_debug_extra_rotation
		if upper and is_instance_valid(upper):
			_apply_rotation_offset(upper, upper_offset)
			posed[upper_name] = true
		if upper and lower and is_instance_valid(upper) and is_instance_valid(lower):
			# Rigidly follow the upper arm: rotate the lower segment around the SAME
			# shoulder point by the SAME offset (both nodes are siblings under _76).
			# Then apply the lower segment's own elbow offset (0 for a straight T-pose).
			_rotate_around_parent_point(lower, shoulder_parent, upper_offset)
			var lower_offset: Vector3 = T_POSE_ROTATION_DEGREES.get(lower_name, Vector3.ZERO) + t_pose_debug_extra_rotation
			_apply_rotation_offset(lower, lower_offset)
			posed[lower_name] = true
		elif lower and is_instance_valid(lower):
			var lower_offset: Vector3 = T_POSE_ROTATION_DEGREES.get(lower_name, Vector3.ZERO) + t_pose_debug_extra_rotation
			_apply_rotation_offset(lower, lower_offset)
			posed[lower_name] = true

	# Pose remaining limbs independently.
	for n in _limb_nodes:
		if not is_instance_valid(n):
			continue
		if posed.has(n.name):
			continue
		var offset_deg: Vector3 = T_POSE_ROTATION_DEGREES.get(n.name, Vector3.ZERO) + t_pose_debug_extra_rotation
		_apply_rotation_offset(n, offset_deg)

func _apply_rotation_offset(node: Node3D, euler_degrees: Vector3) -> void:
	if node == null or not is_instance_valid(node):
		return
	var pivot = LIMB_PIVOTS.get(node.name, null)
	if pivot is Vector3:
		_rotate_around_local_pivot(node, pivot, euler_degrees)
	else:
		node.rotate_object_local(Vector3.RIGHT, deg_to_rad(euler_degrees.x))
		node.rotate_object_local(Vector3.UP, deg_to_rad(euler_degrees.y))
		node.rotate_object_local(Vector3.FORWARD, deg_to_rad(euler_degrees.z))

func _rotate_around_parent_point(node: Node3D, pivot_in_parent_space: Vector3, euler_degrees: Vector3) -> void:
	# Upper/lower limb nodes are siblings under the same model root (_76).
	# Convert the shared parent-space joint point into this node's local space.
	var pivot_local := node.transform.affine_inverse() * pivot_in_parent_space
	_rotate_around_local_pivot(node, pivot_local, euler_degrees)

func _restore_rest_pose() -> void:
	for n in _limb_nodes:
		if not is_instance_valid(n):
			continue
		var rest = _rest_transforms.get(n.get_instance_id(), null)
		if rest is Transform3D:
			n.transform = rest

func _apply_walk_cycle(t: float) -> void:
	# Reset to rest, then apply a simple procedural walk on top.
	for n in _limb_nodes:
		if not is_instance_valid(n):
			continue
		var rest: Transform3D = _rest_transforms.get(n.get_instance_id(), n.transform)
		n.transform = rest

	var swing := sin(t) * walk_amplitude

	# Legs (thighs): the left thigh has a 180-degree-Y rest basis, so the SAME local
	# angle produces opposite world-space swings -> a proper alternating gait.
	_apply_rotation_offset(get_limb_node("RiteLeg_2"), Vector3(swing, 0.0, 0.0))
	_apply_rotation_offset(get_limb_node("LeftLeg_5"), Vector3(swing, 0.0, 0.0))

	# Knees: flex the trailing/back leg a bit so it bends naturally.
	var knee_r := maxf(-swing, 0.0) * 0.55
	var knee_l := maxf(swing, 0.0) * 0.55
	_apply_rotation_offset(get_limb_node("shin_r"), Vector3(knee_r, 0.0, 0.0))
	_apply_rotation_offset(get_limb_node("shin_l"), Vector3(knee_l, 0.0, 0.0))

	# Ankles: counter-rotate the feet a little so they stay closer to flat on the ground.
	_apply_rotation_offset(get_limb_node("foot_r"), Vector3(-swing * 0.35, 0.0, 0.0))
	_apply_rotation_offset(get_limb_node("foot_l"), Vector3(-swing * 0.35, 0.0, 0.0))

	# Arms (chains): swing opposite to the legs, lower segments follow rigidly.
	# Left arm forward (+X swing) while the right leg is forward, and vice versa.
	var bob := sin(t * 2.0) * (walk_amplitude * 0.08)
	var lean := Vector3(bob, 0.0, 0.0)
	_pose_arm_chain_walk("bone2_15", "bone4_29", SHOULDER_L, Vector3(swing * 0.8, 0.0, 0.0), Vector3(swing * 0.2, 0.0, 0.0), lean)
	_pose_arm_chain_walk("bone3_19", "bone5_39", SHOULDER_R, Vector3(-swing * 0.8, 0.0, 0.0), Vector3(-swing * 0.2, 0.0, 0.0), lean)

	# Subtle body/head bob at twice the step frequency.
	_pose_upper_body(bob, -bob * 1.2)

func _apply_attack_cycle(t: float) -> void:
	# Reset to rest, then apply the attack pose on top.
	for n in _limb_nodes:
		if not is_instance_valid(n):
			continue
		var rest: Transform3D = _rest_transforms.get(n.get_instance_id(), n.transform)
		n.transform = rest

	var phase := fmod(t, TAU) / TAU
	var phases := _attack_phases(phase)
	var raising: float = phases.x   # 1 = arm wound up behind
	var striking: float = phases.y  # 1 = arm slammed down in front
	var amp := attack_amplitude

	# --- Very wide, balanced stance (knees wide apart, feet planted) ---
	# Both thighs take the same local Z/X: LeftLeg_5 has a 180-degree-Y rest basis, so
	# the same local angles splay outward in world space on both sides. Bending the knees
	# (shin joints) lowers the body; minimal shin counter-splay keeps the knees pushed wide.
	var splay := attack_stance_degrees
	var crouch := 20.0 + 6.0 * striking
	_apply_rotation_offset(get_limb_node("RiteLeg_2"), Vector3(crouch * 0.5, 0.0, splay))
	_apply_rotation_offset(get_limb_node("LeftLeg_5"), Vector3(crouch * 0.5, 0.0, splay))
	_apply_rotation_offset(get_limb_node("shin_r"), Vector3(-crouch, 0.0, -splay * 0.05))
	_apply_rotation_offset(get_limb_node("shin_l"), Vector3(-crouch, 0.0, -splay * 0.05))
	# Counter the knee bend and a bit of splay so the soles stay closer to flat on the ground.
	_apply_rotation_offset(get_limb_node("foot_r"), Vector3(crouch * 0.5, 0.0, -splay * 0.55))
	_apply_rotation_offset(get_limb_node("foot_l"), Vector3(crouch * 0.5, 0.0, -splay * 0.55))

	# --- Torso pitches into the slash; head and arms are carried along ---
	var lean_degrees := 7.0 * raising - 12.0 * striking
	var nod := -6.0 * raising + 9.0 * striking
	var lean := Vector3(lean_degrees, 0.0, 0.0)
	_pose_upper_body(lean_degrees, nod)

	# --- Slashing right arm: cocked up/back, then snapped down and across ---
	var upper := Vector3(
		-amp * 0.70 * raising + amp * 0.50 * striking,
		0.0,
		amp * 0.25 * raising - amp * 0.25 * striking)
	var wrist := Vector3(20.0 * raising, 0.0, 0.0)
	_pose_arm_chain_walk("bone3_19", "bone5_39", SHOULDER_R, upper, wrist, lean)

	# --- Left arm counter-swings for balance ---
	var left := Vector3(-18.0 * raising - 12.0 * striking, 0.0, -12.0 * raising)
	var left_wrist := Vector3(8.0 * striking, 0.0, 0.0)
	_pose_arm_chain_walk("bone2_15", "bone4_29", SHOULDER_L, left, left_wrist, lean)

## Attack timing: returns (raise, strike) both in 0..1.
## Wind up slowly, snap through the strike, then recover.
func _attack_phases(phase: float) -> Vector2:
	if phase < 0.38:
		return Vector2(_ease01(phase / 0.38), 0.0)
	if phase < 0.56:
		var k := _ease01((phase - 0.38) / 0.18)
		return Vector2(1.0 - k, k)
	return Vector2(0.0, 1.0 - _ease01((phase - 0.56) / 0.44))

func _ease01(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

## Lean the torso about the waist and carry the head pieces with it, then nod.
func _pose_upper_body(lean_degrees: float, nod_degrees: float) -> void:
	var torso := get_limb_node("bone_11")
	var head := get_limb_node("bone6_56")
	var head_top := get_limb_node("bone7_60")
	var lean := Vector3(lean_degrees, 0.0, 0.0)
	var nod := Vector3(nod_degrees, 0.0, 0.0)

	# Torso pivots about the waist (see LIMB_PIVOTS).
	_apply_rotation_offset(torso, lean)

	# Head nodes are siblings of the torso, so orbit them around the waist by the
	# same lean to stay attached, then nod them about the neck.
	for n in [head, head_top]:
		if n and is_instance_valid(n):
			_rotate_around_parent_point(n, WAIST, lean)
	for n in [head, head_top]:
		if n and is_instance_valid(n):
			_rotate_around_parent_point(n, NECK, nod)

func _pose_arm_chain_walk(upper_name: String, lower_name: String, shoulder_parent: Vector3, upper_offset: Vector3, lower_extra_offset: Vector3, lean: Vector3 = Vector3.ZERO) -> void:
	var upper := get_limb_node(upper_name)
	var lower := get_limb_node(lower_name)
	var shoulder := shoulder_parent

	# Carry both segments with the torso lean so the arms stay attached to the body.
	if lean != Vector3.ZERO:
		shoulder = _point_rotated_about(shoulder_parent, WAIST, lean)
		if upper and is_instance_valid(upper):
			_rotate_around_parent_point(upper, WAIST, lean)
		if lower and is_instance_valid(lower):
			_rotate_around_parent_point(lower, WAIST, lean)

	if upper and is_instance_valid(upper):
		_rotate_around_parent_point(upper, shoulder, upper_offset)
	if upper and lower and is_instance_valid(upper) and is_instance_valid(lower):
		_rotate_around_parent_point(lower, shoulder, upper_offset)
		_apply_rotation_offset(lower, lower_extra_offset)
	elif lower and is_instance_valid(lower):
		_apply_rotation_offset(lower, lower_extra_offset)

## Rotate a point around another point using the same Euler convention as the rig.
func _point_rotated_about(point: Vector3, pivot: Vector3, euler_degrees: Vector3) -> Vector3:
	var basis_rot := Basis()
	basis_rot = basis_rot.rotated(Vector3.RIGHT, deg_to_rad(euler_degrees.x))
	basis_rot = basis_rot.rotated(Vector3.UP, deg_to_rad(euler_degrees.y))
	basis_rot = basis_rot.rotated(Vector3.FORWARD, deg_to_rad(euler_degrees.z))
	return pivot + basis_rot * (point - pivot)

func _rotate_around_local_pivot(node: Node3D, pivot_local: Vector3, euler_degrees: Vector3) -> void:
	var basis_rot := Basis()
	basis_rot = basis_rot.rotated(Vector3.RIGHT, deg_to_rad(euler_degrees.x))
	basis_rot = basis_rot.rotated(Vector3.UP, deg_to_rad(euler_degrees.y))
	basis_rot = basis_rot.rotated(Vector3.FORWARD, deg_to_rad(euler_degrees.z))
	# pivot_local is expressed in the node's current (rest) local space.
	# Equivalent to: translate(pivot) * rotate * translate(-pivot) in local space.
	node.transform.origin += node.basis * pivot_local
	node.basis = node.basis * basis_rot
	node.transform.origin -= node.basis * pivot_local

func refresh_limb_cache() -> void:
	_initialized = false
	_ensure_initialized(true)
	_apply_pose_state()

func get_limb_node(limb_name: String) -> Node3D:
	_ensure_initialized()
	return _limbs_by_name.get(limb_name, null)

func get_limb_names() -> PackedStringArray:
	_ensure_initialized()
	var names := PackedStringArray()
	for n in _limb_nodes:
		names.append(n.name)
	return names

func get_limb_nodes() -> Array[Node3D]:
	_ensure_initialized()
	return _limb_nodes.duplicate()

## Set a limb's local rotation as degrees offset from its captured rest pose.
## Uses LIMB_PIVOTS when available to keep joints connected.
func set_limb_rotation_offset(limb_name: String, euler_degrees: Vector3) -> bool:
	_ensure_initialized()
	var n := get_limb_node(limb_name)
	if n == null:
		return false
	var rest: Transform3D = _rest_transforms.get(n.get_instance_id(), n.transform)
	n.transform = rest
	var pivot = LIMB_PIVOTS.get(n.name, null)
	if pivot is Vector3:
		_rotate_around_local_pivot(n, pivot, euler_degrees)
	else:
		n.rotate_object_local(Vector3.RIGHT, deg_to_rad(euler_degrees.x))
		n.rotate_object_local(Vector3.UP, deg_to_rad(euler_degrees.y))
		n.rotate_object_local(Vector3.FORWARD, deg_to_rad(euler_degrees.z))
	return true

## Set a limb's absolute local rotation in degrees (independent of rest pose).
func set_limb_rotation(limb_name: String, euler_degrees: Vector3) -> bool:
	_ensure_initialized()
	var n := get_limb_node(limb_name)
	if n == null:
		return false
	n.rotation_degrees = euler_degrees
	return true

func reset_limb(limb_name: String) -> bool:
	_ensure_initialized()
	var n := get_limb_node(limb_name)
	if n == null:
		return false
	var rest = _rest_transforms.get(n.get_instance_id(), null)
	if rest is Transform3D:
		n.transform = rest
		return true
	return false
