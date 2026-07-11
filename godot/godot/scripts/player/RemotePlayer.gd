extends Node3D

var root: Node = null
var player_id: String = ""
var is_local: bool = false
var animation_lod_enabled: bool = true
var mesh_lod_enabled: bool = true

var display_name: String = "" :
	set(new_name):
		display_name = new_name.strip_edges()
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

func _setup_anim_tree() -> void:
	var state_machine := AnimationNodeStateMachine.new()
	var state_names := ["idle", "running", "runningjump", "falling", "runningslide"]
	for state_name in state_names:
		var node := AnimationNodeAnimation.new()
		node.animation = state_name
		state_machine.add_node(state_name, node)
	for from_name in state_names:
		for to_name in state_names:
			if from_name != to_name:
				var trans := AnimationNodeStateMachineTransition.new()
				trans.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_SYNC
				trans.xfade_time = 0.12
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
	visible = enabled

func refresh_animation_state() -> void:
	if not animation_lod_enabled:
		return
	_apply_animation_state(current_animation)

func _apply_animation_state(new_state: String) -> void:
	_play_anim(new_state)

func _stop_all_animations() -> void:
	if anim_player:
		anim_player.stop()
