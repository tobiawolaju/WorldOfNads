extends Node3D

## The two weapon slots skin.tscn ships: the hand (drawn for a swing/shot) and
## the back (carried). A remote carries its weapon on the back like the local
## player does between shots; the server forwards weapon actions (`act`/`aseq`)
## and play_action() draws it into the hand for that clip only.
const WEAPON_HAND_ATTACH_PATH: String = "Skeleton3D/BoneAttachment3D"
const WEAPON_BACK_ATTACH_PATH: String = "Skeleton3D/BackBoneAttachment3D"
const WEAPON_MUZZLE_PATH: String = "Skeleton3D/Marker3D"
const MUZZLE_FLASH_SCENE_PATH: String = "res://scenes/fx/muzzle_flash.tscn"

## Action kinds the server forwards in `act` (player.gd's ACTION_KIND_*).
const ACTION_NONE: int = 0
const ACTION_SHOOT: int = 1
const ACTION_HOOK: int = 2

## Keep in step with player.gd: a shot holds its aim pose a beat after the clip,
## and the hook clip is retimed onto a shorter timeline.
const SHOOT_END_HOLD: float = 0.16
const HOOK_PLAYBACK_SECONDS: float = 1.3

## Muzzle-flash size per weapon kind. Mirrors WEAPON_FIRE_FX.flash_scale in
## player.gd - that script already preloads this one, so loading it back here
## would be a preload cycle.
const WEAPON_FLASH_SCALE: Dictionary = {
	LocalPickup2.WeaponKind.GLOCK: 0.7,
	LocalPickup2.WeaponKind.AK47: 1.3,
	LocalPickup2.WeaponKind.RPG: 2.0,
}

## Bones the weapon OneShot owns (mirrors player.gd). Legs are deliberately not
## filtered, so a remote keeps running/sliding while its torso fires or swings.
const ACTION_HIPS_FILTER_PATH: String = "Skeleton3D:mixamorig_Hips"
const UPPER_BODY_FILTER_PATHS: Array[String] = [
	ACTION_HIPS_FILTER_PATH,
	"Skeleton3D:mixamorig_Spine", "Skeleton3D:mixamorig_Spine1", "Skeleton3D:mixamorig_Spine2",
	"Skeleton3D:mixamorig_Neck", "Skeleton3D:mixamorig_Head",
	"Skeleton3D:mixamorig_LeftShoulder", "Skeleton3D:mixamorig_LeftArm",
	"Skeleton3D:mixamorig_LeftForeArm", "Skeleton3D:mixamorig_LeftHand",
	"Skeleton3D:mixamorig_LeftHandIndex1", "Skeleton3D:mixamorig_LeftHandIndex2",
	"Skeleton3D:mixamorig_LeftHandIndex3",
	"Skeleton3D:mixamorig_RightShoulder", "Skeleton3D:mixamorig_RightArm",
	"Skeleton3D:mixamorig_RightForeArm", "Skeleton3D:mixamorig_RightHand",
	"Skeleton3D:mixamorig_RightHandIndex1", "Skeleton3D:mixamorig_RightHandIndex2",
	"Skeleton3D:mixamorig_RightHandIndex3",
]

## Local-only combat state for testing the LOS cylinder (the server is
## authoritative in a real match; this only makes hits visible in-editor).
const MAX_HEALTH: float = 100.0
const TEST_RESPAWN_DELAY: float = 2.5

var root: Node = null
var player_id: String = ""
var is_local: bool = false
var animation_lod_enabled: bool = true
var mesh_lod_enabled: bool = true
var health: float = MAX_HEALTH
var _is_dead: bool = false
## Kind of the weapon the server says this player carries, so a skin swap can put
## it back on the fresh skeleton (see refresh_mesh_lod).
var shown_weapon_kind: int = LocalPickup2.WeaponKind.NONE
## True while a forwarded weapon clip owns the hand. The generation counter lets
## a newer action win, exactly like player.gd's _weapon_action_generation.
var _action_active: bool = false
var _action_generation: int = 0
var _action_oneshot: AnimationNodeOneShot = null
var _muzzle_flash: Node = null
var _muzzle_flash_checked: bool = false
var _muzzle_flash_scene_cache: PackedScene = null

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
var action_playback: AnimationNodeStateMachinePlayback = null

func _ready() -> void:
	_refresh_name_label()
	_setup_anim_tree()
	_play_anim("idle")
	# The rig ships every weapon model, and the back slot authors a knife and an
	# RPG as visible: an unarmed copy has to clear both slots explicitly.
	_apply_weapon_visual()
	# Keep the hit-confetti hidden until an actual bullet hit plays it.
	var fx := find_child("HitConfetti", true, false) as GPUParticles3D
	if fx != null:
		fx.emitting = false
		fx.one_shot = true


## Shows the weapon this remote player is carrying, from the server's item state.
## It rides the back between actions; play_action() moves it to the hand for the
## duration of a forwarded shot/swing.
func show_remote_weapon(kind: int) -> void:
	if kind == shown_weapon_kind:
		return
	shown_weapon_kind = kind
	_apply_weapon_visual()


func _apply_weapon_visual() -> void:
	# Mid-clip the hand owns the model: a skin swap or a kind change must not snap
	# the weapon back to the spine until the action ends.
	if _action_active:
		_set_weapon_drawn(true)
		return
	var carried_on_back := get_node_or_null(WEAPON_BACK_ATTACH_PATH) != null
	LocalPickup2.show_weapon_in_slot(self, WEAPON_BACK_ATTACH_PATH, shown_weapon_kind)
	# A rig without a back slot (an older skin scene) keeps the weapon in the hand.
	LocalPickup2.show_weapon_in_slot(self, WEAPON_HAND_ATTACH_PATH, LocalPickup2.WeaponKind.NONE if carried_on_back else shown_weapon_kind)


## Draws/holsters the carried weapon for a weapon clip. Mirrors player.gd's
## _set_weapon_drawn, reading `shown_weapon_kind` instead of a held-weapon field.
func _set_weapon_drawn(drawn: bool) -> void:
	# Nothing to swap on a rig without a back slot: the hand already carries it.
	if get_node_or_null(WEAPON_BACK_ATTACH_PATH) == null:
		return
	LocalPickup2.show_weapon_in_slot(self, WEAPON_BACK_ATTACH_PATH,
			LocalPickup2.WeaponKind.NONE if drawn else shown_weapon_kind)
	LocalPickup2.show_weapon_in_slot(self, WEAPON_HAND_ATTACH_PATH,
			shown_weapon_kind if drawn else LocalPickup2.WeaponKind.NONE)


## Replays another player's weapon action, once per new server seq
## (PlayerManager._update_world_state). The clip plays on the same upper-body
## OneShot layer the local player uses, so the legs keep running; the weapon is
## drawn for the clip and a muzzle flash fires on the shot frame.
##
## Purely cosmetic: no bullet, no damage, no sound.
func play_action(kind: int) -> void:
	if kind != ACTION_SHOOT and kind != ACTION_HOOK:
		return
	# Far away the tree is parked and the skeleton hidden: there is nothing to show.
	if not animation_lod_enabled:
		return
	var clip := "hook" if kind == ACTION_HOOK else "shoot"
	if anim_player == null or not anim_player.has_animation(clip):
		return
	_action_generation += 1
	var generation := _action_generation
	_action_active = true
	_set_weapon_drawn(true)
	if kind == ACTION_SHOOT:
		_play_muzzle_flash()
	if anim_tree and not anim_tree.active:
		anim_tree.active = true
	# On a wall the climb clip's Hips are half a turn off every other clip, so the
	# action must not overwrite them (same rule as player.gd's climbing shot).
	if _action_oneshot != null:
		_action_oneshot.set_filter_path(NodePath(ACTION_HIPS_FILTER_PATH), current_animation != "climb")
	if action_playback:
		action_playback.travel(clip)
	anim_tree.set("parameters/action_shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	await get_tree().create_timer(maxf(_action_length(clip), 0.05)).timeout
	# A newer action already owns the hand and its own timer.
	if generation != _action_generation:
		return
	_action_active = false
	_set_weapon_drawn(false)


func _action_length(clip: String) -> float:
	if clip == "hook":
		return HOOK_PLAYBACK_SECONDS
	return anim_player.get_animation(clip).length + SHOOT_END_HOLD


## Restarts this remote's single muzzle flash, if the weapon is a gun. Built and
## parented like the local player's (one node per remote, reused per shot).
func _play_muzzle_flash() -> void:
	var marker := get_node_or_null(WEAPON_MUZZLE_PATH) as Node3D
	if marker == null:
		return
	if _muzzle_flash != null and not is_instance_valid(_muzzle_flash):
		_muzzle_flash = null
	if _muzzle_flash == null:
		var packed := _muzzle_flash_scene()
		if packed == null:
			return
		_muzzle_flash = packed.instantiate()
		marker.add_child(_muzzle_flash)
	(_muzzle_flash as Node3D).scale = Vector3.ONE * maxf(_flash_scale_for_kind(), 0.05)
	if _muzzle_flash.has_method("flash"):
		_muzzle_flash.call("flash")


func _flash_scale_for_kind() -> float:
	var scale_mult: Variant = WEAPON_FLASH_SCALE.get(shown_weapon_kind)
	if scale_mult is float or scale_mult is int:
		return float(scale_mult)
	# A melee weapon (or an unknown kind) keeps the authored size.
	return 1.0


func _muzzle_flash_scene() -> PackedScene:
	if _muzzle_flash_scene_cache != null:
		return _muzzle_flash_scene_cache
	if _muzzle_flash_checked:
		return null
	_muzzle_flash_checked = true
	if not ResourceLoader.exists(MUZZLE_FLASH_SCENE_PATH):
		return null
	_muzzle_flash_scene_cache = load(MUZZLE_FLASH_SCENE_PATH) as PackedScene
	return _muzzle_flash_scene_cache


## Called when this node is recycled through PlayerManager's pool: drop the
## previous occupant's weapon and any action still running so the next player
## starts clean.
func reset_remote_state() -> void:
	_action_generation += 1
	_action_active = false
	shown_weapon_kind = LocalPickup2.WeaponKind.NONE
	health = MAX_HEALTH
	_is_dead = false
	if name_label:
		name_label.modulate = Color.WHITE
	if action_playback and anim_tree and anim_tree.active:
		action_playback.stop()
	_apply_weapon_visual()
	if _muzzle_flash != null and is_instance_valid(_muzzle_flash):
		_muzzle_flash.queue_free()
	_muzzle_flash = null

func _setup_anim_tree() -> void:
	# Same architecture as player.gd: movement on a state machine, weapon actions
	# on a OneShot layer filtered to the upper body (see play_action).
	var blend_tree := AnimationNodeBlendTree.new()

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

	# -- action state machine (hook, shoot) --
	var action_machine := AnimationNodeStateMachine.new()
	var action_names := ["hook", "shoot"]
	for action_name in action_names:
		var action_node := AnimationNodeAnimation.new()
		action_node.animation = action_name
		if action_name == "hook":
			# Same retimed swing as the local player: the raw clip is 2.4 s and
			# its wind-up reads as "never starts".
			action_node.use_custom_timeline = true
			action_node.timeline_length = HOOK_PLAYBACK_SECONDS
			action_node.stretch_time_scale = true
		action_machine.add_node(action_name, action_node)
	for from_name in action_names:
		for to_name in action_names:
			if from_name != to_name:
				var trans := AnimationNodeStateMachineTransition.new()
				trans.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
				trans.xfade_time = 0.04
				action_machine.add_transition(from_name, to_name, trans)

	# -- OneShot: upper-body bone filter --
	var oneshot := AnimationNodeOneShot.new()
	oneshot.filter_enabled = true
	for path in UPPER_BODY_FILTER_PATHS:
		oneshot.set_filter_path(NodePath(path), true)
	oneshot.fadein_time = 0.05
	oneshot.fadeout_time = 0.1
	_action_oneshot = oneshot

	# -- wire BlendTree: movement → OneShot(in) ← actions, OneShot → output --
	blend_tree.add_node("movement", state_machine)
	blend_tree.add_node("actions", action_machine)
	blend_tree.add_node("action_shot", oneshot)
	blend_tree.connect_node("action_shot", 0, "movement")
	blend_tree.connect_node("action_shot", 1, "actions")
	blend_tree.connect_node("output", 0, "action_shot")

	anim_tree.tree_root = blend_tree
	anim_tree.active = true
	anim_state_machine = anim_tree.get("parameters/movement/playback") as AnimationNodeStateMachinePlayback
	action_playback = anim_tree.get("parameters/actions/playback") as AnimationNodeStateMachinePlayback

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
	# A parked avatar must not keep a forward action's weapon in its hand; the
	# timer that would normally holster it is invalidated by the new generation.
	_action_generation += 1
	if _action_active:
		_action_active = false
		_set_weapon_drawn(false)
	if action_playback:
		action_playback.stop()
	# Deactivating the AnimationTree is what actually stops the per-avatar cost:
	# while inactive it stops evaluating the blend tree and re-posing the
	# Skeleton3D every frame. Safe to park because PlayerManager disables mesh
	# LOD in the same tick, so nothing visible depends on the pose by then.
	if anim_tree:
		anim_tree.active = false

# --- LOCAL COMBAT (LOS cylinder testing) ---

## Marker for Bullet._is_player_damage_target / type checks.
func is_remote_player() -> bool:
	return true


## Chest-height point the cylinder aims at. A body is "in the line" when this
## point sits within the aim radius of the shot ray.
func get_los_center() -> Vector3:
	return global_position + Vector3.UP * 1.0


## Muzzle origin and aim direction for a forwarded shot, matching the local
## player's marker-only aim (-Z of the marker). Returns {origin, dir} or empty.
func get_shot_ray() -> Dictionary:
	var marker := get_node_or_null(WEAPON_MUZZLE_PATH) as Node3D
	if marker == null:
		return {}
	return {
		"origin": marker.global_position,
		"dir": (-marker.global_transform.basis.z).normalized(),
	}


## Applies damage from the local client's LOS check (testing only - the server
## does not know about this). A downed remote fades out and pops back after a
## short delay so you can keep shooting at it.
var _hit_confetti: GPUParticles3D = null

func take_damage(amount: float, source: Node = null, is_bullet: bool = false) -> void:
	if _is_dead or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	_flash_damage()
	# Event-driven health burn (no per-frame cost): shows damage in realtime.
	if health > 0.0:
		DeathDissolve.sync_health(self, health, MAX_HEALTH)
	if is_bullet:
		_play_hit_confetti()
	if health <= 0.0:
		DeathDissolve.restore(self)
		_die_local()


func _flash_damage() -> void:
	# Obvious feedback: label shows HP, flashes red, and the avatar punches up.
	if name_label != null:
		var nm := display_name if display_name != "" else player_id
		name_label.text = "%s  %.0f" % [nm, maxf(health, 0.0)]
		name_label.modulate = Color(1.0, 0.2, 0.2, 1.0)
		var t := create_tween()
		t.tween_property(name_label, "modulate", Color.WHITE, 0.35)
		t.tween_callback(_refresh_name_label)
	# Punch the whole avatar so the body flashes even when the label is small/far.
	var base := scale
	scale = base * 1.08
	var ts := create_tween()
	ts.tween_property(self, "scale", base, 0.12)


func _die_local() -> void:
	_is_dead = true
	visible = false
	# Freeze a lobby bot's rig so it stops "working" while dead.
	var p := get_parent()
	if p is CharacterBody3D:
		(p as CharacterBody3D).velocity = Vector3.ZERO
		p.set_meta("combat_dead", true)
	var tree := get_tree()
	if tree == null:
		return
	# Test-only respawn: the server drives the real avatar, so just come back.
	await tree.create_timer(TEST_RESPAWN_DELAY).timeout
	if not is_instance_valid(self):
		return
	health = MAX_HEALTH
	_is_dead = false
	DeathDissolve.restore(self)
	if p != null and is_instance_valid(p) and p is CharacterBody3D:
		p.set_meta("combat_dead", false)
	# Only show again if the pool/server still has us active.
	if process_mode != Node.PROCESS_MODE_DISABLED:
		visible = true
	_refresh_name_label()


## Bullet-hit confetti (white). Uses a GPUParticles3D placed in the skin if one
## exists; otherwise creates one so "target got hit" always reads.
func _play_hit_confetti() -> void:
	var fx := _get_hit_confetti()
	if fx == null:
		return
	_apply_blood_hit_look(fx)
	# Detach so a lethal hit (avatar hides on death) can't hide the burst.
	var scene := get_tree().current_scene if get_tree() else null
	if scene != null and fx.get_parent() != scene:
		if fx.get_parent() == self:
			fx.position = Vector3(0, 1.0, 0)
		fx.reparent(scene)
		fx.global_position = global_position + Vector3(0, 1.0, 0)
	elif fx.get_parent() == self:
		fx.position = Vector3(0, 1.0, 0)
	fx.emitting = false
	fx.restart()
	fx.emitting = true
	if not fx.finished.is_connected(_reclaim_hit_confetti):
		fx.finished.connect(_reclaim_hit_confetti)


func _reclaim_hit_confetti() -> void:
	if _hit_confetti != null and is_instance_valid(_hit_confetti) and is_instance_valid(self):
		if _hit_confetti.get_parent() != self:
			_hit_confetti.reparent(self)
		_hit_confetti.position = Vector3(0, 1.0, 0)


func _get_hit_confetti() -> GPUParticles3D:
	if _hit_confetti != null and is_instance_valid(_hit_confetti):
		return _hit_confetti
	_hit_confetti = get_node_or_null("HitConfetti") as GPUParticles3D
	if _hit_confetti == null:
		_hit_confetti = find_child("HitConfetti", true, false) as GPUParticles3D
	if _hit_confetti == null:
		_hit_confetti = GPUParticles3D.new()
		_hit_confetti.name = "HitConfetti"
		add_child(_hit_confetti)
	_setup_hit_confetti(_hit_confetti)
	_hit_confetti.emitting = false
	return _hit_confetti


func _setup_hit_confetti(fx: GPUParticles3D) -> void:
	# Build resources once (no per-hit allocations) for a low-end/web-friendly burst.
	if fx.has_meta("hit_fx_ready"):
		return
	fx.one_shot = true
	fx.explosiveness = 0.98
	fx.amount = mini(maxi(fx.amount, 36), 48)
	fx.lifetime = 0.42
	fx.local_coords = true
	fx.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(1, 0, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 4.5
	mat.initial_velocity_max = 9.0
	mat.gravity = Vector3(0, -5.0, 0)
	mat.damping_min = 1.0
	mat.damping_max = 3.0
	mat.scale_min = 0.85
	mat.scale_max = 1.6
	fx.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
	var draw := StandardMaterial3D.new()
	draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	draw.vertex_color_use_as_albedo = true
	draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = draw
	fx.draw_pass_1 = quad
	fx.set_meta("hit_fx_ready", true)
	fx.set_meta("hit_mat", mat)
	fx.set_meta("hit_draw", draw)


## Picks a representative color from this character's skin/meshes (cached).
func get_hit_fx_color() -> Color:
	if has_meta("hit_fx_color"):
		return get_meta("hit_fx_color")
	var c := Color(0.9, 0.85, 0.8, 1.0)
	for m in find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi == null or not mi.visible:
			continue
		var smat: Material = mi.material_override
		if smat == null:
			for s in range(mi.get_surface_override_material_count()):
				smat = mi.get_surface_override_material(s)
				if smat != null:
					break
		if smat == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			smat = mi.mesh.surface_get_material(0)
		if smat is BaseMaterial3D:
			var ac: Color = (smat as BaseMaterial3D).albedo_color
			if ac.a > 0.05 and ac.get_luminance() > 0.02:
				c = ac
				break
		elif smat is ShaderMaterial:
			var found := false
			for k in ["albedo_color", "albedo", "base_color", "color", "tint", "skin_color"]:
				var v = (smat as ShaderMaterial).get_shader_parameter(k)
				if v is Color and (v as Color).a > 0.05:
					c = v; found = true; break
			if found: break
	set_meta("hit_fx_color", c)
	return c


func _apply_blood_hit_look(fx: GPUParticles3D) -> void:
	# Recolor only (no allocations): victim's skin + a bit of random variation.
	_setup_hit_confetti(fx)
	var base := get_hit_fx_color()
	var fx_color := base.lerp(base.lightened(randf_range(0.05, 0.45)), randf_range(0.25, 0.7))
	fx_color = (fx_color * Color(1.0, randf_range(0.92, 1.08), randf_range(0.85, 1.1))).clamp()
	fx_color.a = 1.0
	var mat = fx.get_meta("hit_mat") if fx.has_meta("hit_mat") else fx.process_material
	if mat is ParticleProcessMaterial:
		(mat as ParticleProcessMaterial).color = fx_color
	var draw = fx.get_meta("hit_draw") if fx.has_meta("hit_draw") else (fx.draw_pass_1.material if fx.draw_pass_1 is QuadMesh else null)
	if draw is StandardMaterial3D:
		(draw as StandardMaterial3D).albedo_color = fx_color

