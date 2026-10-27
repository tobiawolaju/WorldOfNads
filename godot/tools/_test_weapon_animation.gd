# Headless selftest for the held-weapon clips (hook / shoot).
#   Godot_v4.8-beta1_win64_console.exe --headless --path godot --script res://tools/_test_weapon_animation.gd
# Prints FAIL lines for every broken expectation and exits non-zero if any fail.
#
# Why this exists: the clips were in the library and `_use_held_weapon()` called
# `anim_player.play("hook")`, but nothing ever moved on screen. The AnimationTree
# built in `_setup_anim_tree()` drives the skeleton, so a clip the state machine
# cannot travel to is written over every frame, and `_handle_animations()` re-picks
# idle/running on the next frame regardless. Both halves are asserted here.
extends SceneTree

var failures := 0

func _initialize() -> void:
	var player := (load("res://scenes/skin.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(player)
	await process_frame
	await process_frame

	_check("the player builds a state machine", player.anim_state_machine != null)
	_check("the library ships a hook clip", player.anim_player.has_animation("hook"))
	_check("the library ships a shoot clip", player.anim_player.has_animation("shoot"))
	# The hook clip is 2.4 s at 1x, which reads as "the swing never starts". The
	# state is retimed with a custom timeline instead (Animation has no speed in
	# Godot 4), and _play_weapon_action locks the pose for that same timeline.
	var hook_state := (player.anim_tree.tree_root as AnimationNodeStateMachine).get_node("hook")
	_check(
		"the hook state is retimed shorter than its 2.4 s clip",
		hook_state is AnimationNodeAnimation
			and hook_state.use_custom_timeline
			and hook_state.timeline_length < player.anim_player.get_animation("hook").length
	)

	var machine := player.anim_tree.tree_root as AnimationNodeStateMachine
	_check("the state machine carries the hook state", machine != null and machine.has_node("hook"))
	_check("the state machine carries the shoot state", machine != null and machine.has_node("shoot"))

	# The tree owns the skeleton, so a state the machine does not carry is never
	# drawn no matter what anim_player.play() is told to do. `travel` returns void
	# in this build, so the state it actually reached is what gets asserted.
	player.anim_state_machine.travel("hook")
	await create_timer(0.3).timeout
	_check("the machine actually reaches the hook state", player.anim_state_machine.get_current_node() == "hook")
	player.anim_state_machine.travel("shoot")
	await create_timer(0.3).timeout
	_check("the machine actually reaches the shoot state", player.anim_state_machine.get_current_node() == "shoot")

	# The clip has to reach the model, not just the state machine's bookkeeping.
	# Bone poses are sampled in idle and again mid-shot; the tree is the only thing
	# driving them, so a difference proves the clip is actually being drawn.
	var skeleton := player.get_node_or_null("Skeleton3D") as Skeleton3D
	player.anim_state_machine.travel("idle")
	await create_timer(0.25).timeout
	var idle_pose := _bone_signature(skeleton)

	# A weapon action has to survive _handle_animations, which re-picks the
	# movement state every physics frame. is_local is toggled only around the
	# synchronous calls: the scene is dressed as a remote player otherwise, and
	# the timer below yields frames that would run the local input path.
	player.is_local = true
	player._set_anim("idle")
	player._play_weapon_action("shoot")
	_check("the action takes the pose", player.current_animation == "shoot")
	_check("the action locks the movement state", player._weapon_action_active)
	player._handle_animations(Vector3.ZERO)
	_check("movement animation stands down during the action", player.current_animation == "shoot")
	player.is_local = false

	await create_timer(0.15).timeout
	_check("the shoot clip moves the skeleton", skeleton != null and absf(_bone_signature(skeleton) - idle_pose) > 0.001)

	# The 0.2 s clip is over by now, but the shot holds its final (aim) pose for
	# SHOOT_END_HOLD longer so the recoil reads instead of flickering.
	await create_timer(0.06).timeout
	_check("the shot holds its pose past the clip", player._weapon_action_active)

	# It releases the pose on its own, so the player is never stuck mid-swing.
	await create_timer(player.SHOOT_END_HOLD + 0.1).timeout
	_check("the action releases the pose", not player._weapon_action_active)
	player.is_local = true
	player._handle_animations(Vector3.ZERO)
	_check("movement animation resumes afterwards", player.current_animation != "shoot")
	player.is_local = false

	# A clip the library does not ship must not lock the player out of movement.
	player._set_anim("idle")
	player._play_weapon_action("does-not-exist")
	_check("a missing clip does not lock movement", not player._weapon_action_active)
	_check("a missing clip leaves the pose alone", player.current_animation == "idle")

	print("weapon animation selftest: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func _check(name: String, condition: bool) -> void:
	if condition:
		print("PASS  ", name)
	else:
		failures += 1
		print("FAIL  ", name)


## Cheap fingerprint of the first few bone rotations. Comparing two samples is
## enough to tell whether the animation tree is writing poses into the skeleton.
func _bone_signature(skeleton: Skeleton3D) -> float:
	if skeleton == null:
		return 0.0
	var total := 0.0
	for i in mini(skeleton.get_bone_count(), 8):
		var q := skeleton.get_bone_pose_rotation(i)
		total += absf(q.x) + absf(q.y) + absf(q.z) + absf(q.w)
	return total
