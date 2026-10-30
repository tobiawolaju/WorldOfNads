extends Node3D

## The two weapon slots skin.tscn ships: the hand (drawn for a swing/shot) and
## the back (carried). A remote never swings locally, so its weapon stays on the
## back - the same slot the local player uses between shots.
const WEAPON_HAND_ATTACH_PATH: String = "Skeleton3D/BoneAttachment3D"
const WEAPON_BACK_ATTACH_PATH: String = "Skeleton3D/BackBoneAttachment3D"

var root: Node = null
var player_id: String = ""
var is_local: bool = false
var animation_lod_enabled: bool = true
var mesh_lod_enabled: bool = true
## Kind of the weapon the server says this player carries, so a skin swap can put
## it back on the fresh skeleton (see refresh_mesh_lod).
var shown_weapon_kind: int = LocalPickup2.WeaponKind.NONE

var display_name: String = "" :
	set(new_name):
		# World-state packets re-send every player's name ~20x/s; skipping the
		# unchanged case keeps strip_edges() and the Label3D rewrite off the hot path.
		if new_name == display_name:
			return
		var stripped := new_name.strip_edges()
		if stripped == display_name:
			return
		display_name = stripped
		_refresh_name_label()

var current_animation: String = "idle"

@onready var name_label: Label3D = $Label3D
@onready var anim_player: AnimationPlayer = $animator
@onready var anim_tree: AnimationTree = $AnimationTree
var anim_state_machine: AnimationNodeStateMachinePlayback = null

func _ready() -> void:
	_refresh_name_label()
	_setup_anim_tree()
	_play_anim("idle")
	# The rig ships every weapon model, and the back slot authors a knife and an
	# RPG as visible: an unarmed copy has to clear both slots explicitly.
	_apply_weapon_visual()


## Shows the weapon this remote player is carrying, from the server's item state.
## Only the back slot is used: a remote copy has no charges, HUD or input of its
## own, so it never draws the weapon into its hand.
func show_remote_weapon(kind: int) -> void:
	if kind == shown_weapon_kind:
		return
	shown_weapon_kind = kind
	_apply_weapon_visual()


func _apply_weapon_visual() -> void:
	var carried_on_back := get_node_or_null(WEAPON_BACK_ATTACH_PATH) != null
	LocalPickup2.show_weapon_in_slot(self, WEAPON_BACK_ATTACH_PATH, shown_weapon_kind)
	# A rig without a back slot (an older skin scene) keeps the weapon in the hand.
	LocalPickup2.show_weapon_in_slot(self, WEAPON_HAND_ATTACH_PATH, LocalPickup2.WeaponKind.NONE if carried_on_back else shown_weapon_kind)

func _setup_anim_tree() -> void:
	var state_machine := AnimationNodeStateMachine.new()
	var state_names := ["idle", "running", "runningjump", "falling", "runningslide", "climb"]
	for state_name in state_names:
		var node := AnimationNodeAnimation.new()
		node.animation = state_name
		state_machine.add_node(state_name, node)
	for from_name in state_names:
		for to_name in state_names:
			if from_name != to_name:
				var trans := AnimationNodeStateMachineTransition.new()
				trans.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_SYNC
				trans.xfade_time = 0.06 if to_name == "idle" else 0.12  # idle settles faster, like player.gd
				state_machine.add_transition(from_name, to_name, trans)
	anim_tree.tree_root = state_machine
	anim_tree.active = true
	anim_state_machine = anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback

func _play_anim(anim_name: String) -> void:
	if anim_state_machine:
		anim_state_machine.travel(anim_name)

func _refresh_name_label() -> void:
	if not name_label:
		return
	var resolved_name := display_name
	if resolved_name == "":
		resolved_name = player_id.substr(0, 8)
	name_label.text = resolved_name

func set_animation_state(new_state: String) -> void:
	var changed := new_state != current_animation
	current_animation = new_state
	if not animation_lod_enabled:
		return
	if not changed:
		return
	_apply_animation_state(new_state)

func cache_animation_state(new_state: String) -> void:
	current_animation = new_state

func set_animation_lod_enabled(enabled: bool) -> void:
	if animation_lod_enabled == enabled:
		return
	animation_lod_enabled = enabled
	if animation_lod_enabled:
		_apply_animation_state(current_animation)
	else:
		_stop_all_animations()

func set_mesh_lod_enabled(enabled: bool) -> void:
	if mesh_lod_enabled == enabled:
		return
	mesh_lod_enabled = enabled
	_apply_mesh_lod()

# Toggles only the visual skeleton, never the root node's `visible`.
# PlayerManager owns `visible` for its 50 m cull, and the name label should
# stay readable past the mesh cutoff.
func _apply_mesh_lod() -> void:
	var skeleton := get_node_or_null("Skeleton3D") as Node3D
	if skeleton:
		skeleton.visible = mesh_lod_enabled

# Re-applies the current LOD state to a freshly swapped-in Skeleton3D, since a
# skin change replaces the node and resets its visibility. The same swap brings
# the authored weapon meshes back, so the carried one is re-asserted too.
func refresh_mesh_lod() -> void:
	_apply_mesh_lod()
	_apply_weapon_visual()

func refresh_animation_state() -> void:
	if not animation_lod_enabled:
		return
	_apply_animation_state(current_animation)

func _apply_animation_state(new_state: String) -> void:
	# Re-activate here: LOD-off parks the tree (see _stop_all_animations), and
	# travel() must land on a live tree or the avatar comes back in its old pose.
	if anim_tree and not anim_tree.active:
		anim_tree.active = true
	_play_anim(new_state)

func _stop_all_animations() -> void:
	if anim_player:
		anim_player.stop()
	# Deactivating the AnimationTree is what actually stops the per-avatar cost:
	# while inactive it stops evaluating its 6-state machine and re-posing the
	# Skeleton3D every frame. Safe to park because PlayerManager disables mesh
	# LOD in the same tick, so nothing visible depends on the pose by then.
	if anim_tree:
		anim_tree.active = false
