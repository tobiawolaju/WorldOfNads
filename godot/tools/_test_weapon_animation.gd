# Headless selftest for the held-weapon clips (hook / shoot).
#   Godot_v4.8-beta1_win64_console.exe --headless --path godot --script res://tools/_test_weapon_animation.gd
# Prints FAIL lines for every broken expectation and exits non-zero if any fail.
#
# Architecture: the AnimationTree root is a BlendTree containing:
#   movement (StateMachine)  → OneShot("action_shot") ← actions (StateMachine)
# The OneShot is filtered to upper-body bones so weapon clips only override the
# torso/arms while legs keep playing the movement animation.
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

	# The tree root is now a BlendTree wrapping a OneShot.
	var blend_tree := player.anim_tree.tree_root as AnimationNodeBlendTree
	_check("the tree root is a BlendTree", blend_tree != null)

	# The movement machine is inside the BlendTree.
	var movement_machine := blend_tree.get_node("movement") as AnimationNodeStateMachine if blend_tree else null
	_check("the BlendTree has a movement machine", movement_machine != null)

	# The action machine holds hook/shoot.
	var action_machine := blend_tree.get_node("actions") as AnimationNodeStateMachine if blend_tree else null
	_check("the BlendTree has an action machine", action_machine != null)
	_check("the action machine has hook", action_machine != null and action_machine.has_node("hook"))
	_check("the action machine has shoot", action_machine != null and action_machine.has_node("shoot"))

	# The hook clip is retimed with a custom timeline.
	var hook_state := action_machine.get_node("hook") if action_machine else null
	_check(
		"the hook state is retimed shorter than its 2.4 s clip",
		hook_state is AnimationNodeAnimation
			and hook_state.use_custom_timeline
			and hook_state.timeline_length < player.anim_player.get_animation("hook").length
	)

	# The movement machine should NOT have hook/shoot (they live in the action machine).
	_check("movement machine has no hook state", movement_machine != null and not movement_machine.has_node("hook"))
	_check("movement machine has no shoot state", movement_machine != null and not movement_machine.has_node("shoot"))

	# Verify movement states exist.
	_check("movement machine has idle", movement_machine != null and movement_machine.has_node("idle"))
	_check("movement machine has running", movement_machine != null and movement_machine.has_node("running"))

	# The movement playback should be reachable.
	player.anim_state_machine.travel("idle")
	await create_timer(0.25).timeout
	_check("movement machine reaches idle", player.anim_state_machine.get_current_node() == "idle")

	# The clip has to reach the model, not just the state machine's bookkeeping.
	# Bone poses are sampled in idle and again mid-shot; the tree is the only thing
	# driving them, so a difference proves the clip is actually being drawn.
	var skeleton := player.get_node_or_null("Skeleton3D") as Skeleton3D
	var idle_pose := _bone_signature(skeleton)

	# A weapon action has to survive _handle_animations, which re-picks the
	# movement state every physics frame. is_local is toggled only around the
	# synchronous calls: the scene is dressed as a remote player otherwise, and
	# the timer below yields frames that would run the local input path.
	player.is_local = true
	player._set_anim("idle")
	player._play_weapon_action("shoot")
	_check("the action locks the movement state", player._weapon_action_active)
	# With the OneShot architecture, movement animations should keep updating
	# (no early return in _handle_animations).
	player._handle_animations(Vector3.ZERO)
	# current_animation is set to "shoot" by _play_weapon_action for network sync,
	# but _handle_animations may update it to idle — that's fine because the
	# movement machine stays on idle (legs). The upper body is driven by the OneShot.
	_check("the action still active after handle_animations", player._weapon_action_active)
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
	# After the action ends, movement should resume: current_animation is a
	# movement state (not "shoot") since _handle_animations ran.
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
