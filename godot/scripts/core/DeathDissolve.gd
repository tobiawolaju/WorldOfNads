extends RefCounted
class_name DeathDissolve

## Burns a player model away using `death_dissolve.gdshader`.
##
## Two things drive the burn:
##
##  * `sync_health()` — called every frame with the player's health, so the body
##    erodes as damage accumulates. The point is that you can see yourself dying:
##    the health bar says "31%", the model says "I am coming apart".
##  * `begin()` — called on death, and runs the burn the rest of the way to gone.
##
## The effect works by swapping each mesh's `material_override` for a
## per-instance dissolve material and tweening all of them together. Swapping
## rather than editing is not a style preference: `SkinApplier` hands the *same*
## material instance to every player wearing a skin, so mutating one in place
## would dissolve the entire room.
##
## `begin()` is idempotent per death and `restore()` is idempotent per respawn,
## and the skin is snapshotted by reference rather than rebuilt, so a respawn
## cannot come back wearing the wrong skin.
##
## This is presentation only. It never touches health, death timing or anything
## the server is told about.

const SHADER := preload("res://assets/shaders/death_dissolve.gdshader")

## Seconds the burn takes by default. `die()` spends most of `RESPAWN_DELAY`
## here so the body is fully gone before the player pops back in.
const DEFAULT_DURATION := 1.4

## Warm ember edge, as authored. Kept here so retinting the effect to the game's
## pink is a one-line change rather than a shader edit.
const EDGE_COLOR := Color(1.0, 0.45, 0.1, 1.0)

## Health fraction below which the body starts to come apart. A graze should not
## visibly wound the model, and the first thing the noise eats is the mouth, which
## reads as a hole in the face.
const HEALTH_DISSOLVE_START := 0.75

## How far the body is eaten away by health alone. Death carries on from here to a
## full burn, so the two effects join instead of restarting. Stopping short of 1.0
## matters: a living player you cannot see is a gameplay problem, not a mood.
const HEALTH_DISSOLVE_MAX := 0.6

## Seconds a health-driven change takes to catch up. Long enough to read as a burn
## creeping, short enough that a hit lands on the same beat as the health bar.
const HEALTH_TWEEN_TIME := 0.18

## Ignore health changes too small to see. Without this, slow regeneration would
## create a fresh Tween every frame for sub-pixel differences.
const HEALTH_RETARGET_EPSILON := 0.004

const _DISSOLVE_META := "_death_dissolve_material"
const _ORIGINAL_META := "_death_dissolve_original"
const _LABEL_META := "_death_dissolve_label_modulate"
const _TWEEN_META := "_death_dissolve_tween"
const _SWAPPED_META := "_death_dissolve_swapped"
const _DEATH_META := "_death_dissolve_death"
const _TARGET_META := "_death_dissolve_target"

## True once this process has drawn the dissolve program at least once.
static var _prewarmed := false


## Draws the dissolve material for a single real frame so the shader program is
## compiled before anyone dies.
##
## Godot compiles a shader the first time a material is actually *drawn*, not
## when it is created or assigned. Without this, the very first death hitches for
## a frame or two at exactly the moment the effect has to be immediate — the
## opening of the burn is when a stutter is most obvious.
##
## The probe is drawn at `dissolve = 1.0`, which discards every fragment, so it
## is invisible even though the draw happens. Same one-shot-per-process rule as
## the smoke cloud and the power-up aura in `player.gd`.
static func prewarm(player: Node3D) -> void:
	if _prewarmed:
		return
	# Nothing is rendered headless, so there is no program to compile.
	if DisplayServer.get_name() == "headless":
		return
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return
	# Bailing before claiming the flag lets a later player retry, in case the
	# camera has not been created yet when the first one spawns.
	var camera := player.get_viewport().get_camera_3d()
	if camera == null:
		return
	_prewarmed = true

	var probe := MeshInstance3D.new()
	probe.name = "DeathDissolvePrewarm"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.002, 0.002)
	probe.mesh = quad
	probe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := _build_material(null)
	material.set_shader_parameter("dissolve", 1.0)
	probe.material_override = material
	# Half a metre in front of the camera: inside the frustum, so it is drawn,
	# and in the same viewport and lighting as the death will be.
	probe.position = Vector3(0.0, 0.0, -0.5)
	camera.add_child(probe)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if is_instance_valid(probe):
		probe.queue_free()


## Test hook: reports whether this process has warmed the dissolve program.
static func is_prewarmed() -> bool:
	return _prewarmed


## How far the body should be eaten away at a given health fraction, 0..1.
static func dissolve_for_health(fraction: float) -> float:
	var missing := 1.0 - clampf(fraction, 0.0, 1.0)
	var past := missing - (1.0 - HEALTH_DISSOLVE_START)
	if past <= 0.0:
		return 0.0
	return HEALTH_DISSOLVE_MAX * clampf(past / HEALTH_DISSOLVE_START, 0.0, 1.0)


## Points the burn at the player's current health, so damage shows on the body as
## it happens instead of only once the player is already dead.
##
## Called every frame from `player._process`, so it leaves in one comparison when
## nothing has changed.
static func sync_health(player: Node3D, health: float, max_health: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if not player.is_inside_tree() or max_health <= 0.0:
		return
	# Death owns the burn from `die()` until the respawn puts the skin back.
	if player.has_meta(_DEATH_META):
		return

	var target := dissolve_for_health(health / max_health)

	# Fully recovered: hand the real skin back, so a player who took one hit at
	# the start of the match is not stuck on the burn material afterwards. The
	# swap happens once the burn has faded to nothing, so it is invisible.
	#
	# This must be checked *before* the retarget epsilon below. Health regenerates
	# continuously, so the target creeps down to zero in steps far smaller than the
	# epsilon, and a guard that swallowed that last step would leave the player on
	# the burn material indefinitely. That is nearly invisible on the body, because
	# dissolve 0 looks like the skin — but the eyes lose their camera-facing dot,
	# the mouth loses its interior and cosmetics lose their authored shading. Only
	# dying cleared it, because respawn calls restore() directly.
	if target <= 0.0:
		if not player.has_meta(_SWAPPED_META):
			return
		if player.has_meta(_TARGET_META) and is_zero_approx(float(player.get_meta(_TARGET_META))):
			return
		player.set_meta(_TARGET_META, 0.0)
		_tween_dissolve(player, 0.0, true)
		return

	if player.has_meta(_TARGET_META):
		var previous := float(player.get_meta(_TARGET_META))
		if absf(previous - target) < HEALTH_RETARGET_EPSILON:
			return

	if _ensure_swapped(player).is_empty():
		return
	player.set_meta(_TARGET_META, target)
	_tween_dissolve(player, target)


## Starts the death burn, carrying on from wherever health left the body. Safe to
## call on a player that is already dissolving.
static func begin(player: Node3D, duration: float = DEFAULT_DURATION) -> void:
	if player == null or not is_instance_valid(player):
		return
	# A Tween needs a scene tree, and a player outside one is not being rendered
	# anyway.
	if not player.is_inside_tree():
		return
	# One death burn per death. Running twice would snapshot the burn material as
	# the "original" and the player would never get their skin back.
	if player.has_meta(_DEATH_META):
		return

	var materials := _ensure_swapped(player)
	if materials.is_empty():
		return

	_kill_tween(player)
	player.set_meta(_DEATH_META, true)
	player.set_meta(_TARGET_META, 1.0)

	var tween := player.create_tween()
	tween.set_parallel(true)
	for material in materials:
		# Ease *out*, not in. With EASE_IN a quadratic curve keeps `dissolve` at
		# ~0 for the first 40% of the duration, which reads as a delay: the body
		# stands there untouched and then suddenly vanishes. EASE_OUT front-loads
		# the burn so it responds on the frame you die and leaves embers behind.
		tween.tween_property(material, "shader_parameter/dissolve", 1.0, duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# The floating name tag is not a mesh, so without this it would hang in the
	# air over an empty spot for the length of the respawn.
	_fade_name_tags(player, tween, duration * 0.6)

	player.set_meta(_TWEEN_META, tween)


## Puts the player's real materials back. Safe to call when not dissolving, which
## is what lets every respawn/teleport path call it unconditionally.
static func restore(player: Node3D) -> void:
	if player == null or not is_instance_valid(player):
		return

	_kill_tween(player)
	player.remove_meta(_DEATH_META)
	player.remove_meta(_SWAPPED_META)
	player.remove_meta(_TARGET_META)

	for child in player.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh == null or not mesh.has_meta(_DISSOLVE_META):
			continue
		if mesh.has_meta(_ORIGINAL_META):
			mesh.material_override = mesh.get_meta(_ORIGINAL_META) as Material
			mesh.remove_meta(_ORIGINAL_META)
		mesh.remove_meta(_DISSOLVE_META)

	for child in player.find_children("*", "Label3D", true, false):
		var label := child as Label3D
		if label == null or not label.has_meta(_LABEL_META):
			continue
		var saved: Color = label.get_meta(_LABEL_META)
		label.modulate = saved
		label.remove_meta(_LABEL_META)


# ---------------------------------------------------------------------------
# Swapping and tweening
# ---------------------------------------------------------------------------

## Swaps every mesh onto the burn material, once. Meshes already swapped keep the
## material they have, so an in-progress burn is never reset back to solid.
static func _ensure_swapped(player: Node3D) -> Array[ShaderMaterial]:
	var materials: Array[ShaderMaterial] = []
	for child in player.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh == null:
			continue
		if mesh.has_meta(_DISSOLVE_META):
			materials.append(mesh.get_meta(_DISSOLVE_META) as ShaderMaterial)
			continue

		# `material_override` may be null on a mesh that relies on its surface
		# material. That null is what has to be restored later, but the surface
		# material is what has to be read for the colour.
		var override_material := mesh.material_override
		var source := override_material
		if source == null:
			source = _surface_material(mesh)

		var dissolve := _build_material(source)
		mesh.set_meta(_ORIGINAL_META, override_material)
		mesh.set_meta(_DISSOLVE_META, dissolve)
		mesh.material_override = dissolve
		materials.append(dissolve)

	if not materials.is_empty():
		player.set_meta(_SWAPPED_META, true)
	return materials


## The burn materials currently on the player, or an empty list if the skin is
## still in place.
static func _current_materials(player: Node3D) -> Array[ShaderMaterial]:
	var materials: Array[ShaderMaterial] = []
	for child in player.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh == null or not mesh.has_meta(_DISSOLVE_META):
			continue
		materials.append(mesh.get_meta(_DISSOLVE_META) as ShaderMaterial)
	return materials


static func _kill_tween(player: Node3D) -> void:
	if not player.has_meta(_TWEEN_META):
		return
	# `get_meta` with a null default still logs "no meta with key" in this build,
	# so check first: this runs on every retarget, i.e. throughout regeneration.
	var running: Variant = player.get_meta(_TWEEN_META)
	if running is Tween and (running as Tween).is_valid():
		(running as Tween).kill()
	player.remove_meta(_TWEEN_META)


## Moves every burn material to `target`. With `restore_when_done`, the skin is
## handed back once the burn has faded out completely.
static func _tween_dissolve(player: Node3D, target: float, restore_when_done := false) -> void:
	var materials := _current_materials(player)
	if materials.is_empty():
		return

	_kill_tween(player)
	var tween := player.create_tween()
	tween.set_parallel(true)
	for material in materials:
		tween.tween_property(material, "shader_parameter/dissolve", target, HEALTH_TWEEN_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if restore_when_done:
		tween.chain().tween_callback(func() -> void: _restore_after_heal(player))
	player.set_meta(_TWEEN_META, tween)


static func _restore_after_heal(player: Node3D) -> void:
	if player == null or not is_instance_valid(player):
		return
	# Died during the fade out; the death burn owns the model now.
	if player.has_meta(_DEATH_META):
		return
	player.remove_meta(_TWEEN_META)
	restore(player)


# ---------------------------------------------------------------------------
# Material construction
# ---------------------------------------------------------------------------

## Mirrors whatever the mesh was drawn with, because the swap happens on screen
## and a colour change at t=0 would read as a glitch rather than an effect.
static func _build_material(source: Material) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER

	var albedo := Color(0.8, 0.8, 0.85, 1.0)
	var roughness := 0.5
	var metallic := 0.0
	var albedo_texture: Texture2D = null

	if source is StandardMaterial3D:
		var standard := source as StandardMaterial3D
		albedo = standard.albedo_color
		roughness = standard.roughness
		metallic = standard.metallic
		albedo_texture = standard.albedo_texture
	elif source is ShaderMaterial:
		# The skin shaders spell their one colour `albedo`; the face, eye and mouth
		# shaders each use their own name, so probe the plausible ones rather than
		# assuming. Getting this wrong shows up as a grey face during the burn.
		var shader_material := source as ShaderMaterial
		albedo = _first_color(shader_material, [
			"albedo", "albedo_color", "color", "eye_color", "mouth_color", "base_color"
		], albedo)
		roughness = _first_float(shader_material, ["roughness_val", "roughness"], roughness)
		metallic = _first_float(shader_material, ["metalness_val", "metallic", "metallic_val"], metallic)
		albedo_texture = _first_texture(shader_material, ["albedo_texture", "albedo_tex", "texture"])

	material.set_shader_parameter("albedo", albedo)
	material.set_shader_parameter("roughness", roughness)
	material.set_shader_parameter("metallic", metallic)
	material.set_shader_parameter("edge_color", EDGE_COLOR)
	# Start solid; the tween does the rest.
	material.set_shader_parameter("dissolve", 0.0)
	if albedo_texture != null:
		material.set_shader_parameter("albedo_texture", albedo_texture)

	return material


static func _surface_material(mesh: MeshInstance3D) -> Material:
	if mesh.mesh == null or mesh.mesh.get_surface_count() == 0:
		return null
	return mesh.mesh.surface_get_material(0)


static func _first_color(source: ShaderMaterial, names: Array, fallback: Color) -> Color:
	for name in names:
		var value: Variant = source.get_shader_parameter(name)
		if value is Color:
			return value
		# `eye_color` is declared `vec3`, which comes back as a Vector3 rather
		# than a Color.
		if value is Vector3:
			return Color(value.x, value.y, value.z, 1.0)
	return fallback


static func _first_float(source: ShaderMaterial, names: Array, fallback: float) -> float:
	for name in names:
		var value: Variant = source.get_shader_parameter(name)
		if value is float or value is int:
			return float(value)
	return fallback


static func _first_texture(source: ShaderMaterial, names: Array) -> Texture2D:
	for name in names:
		var value: Variant = source.get_shader_parameter(name)
		if value is Texture2D:
			return value
	return null


# ---------------------------------------------------------------------------
# Name tags
# ---------------------------------------------------------------------------

## Fades the floating name tag out with the body, remembering its current value
## so a tag that was already dimmed for another reason comes back unchanged.
static func _fade_name_tags(player: Node3D, tween: Tween, duration: float) -> void:
	for child in player.find_children("*", "Label3D", true, false):
		var label := child as Label3D
		if label == null:
			continue
		if not label.has_meta(_LABEL_META):
			label.set_meta(_LABEL_META, label.modulate)
		var faded: Color = label.modulate
		faded.a = 0.0
		tween.tween_property(label, "modulate", faded, duration)
