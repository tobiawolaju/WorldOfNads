# Headless selftest for the death dissolve (DeathDissolve + death_dissolve.gdshader).
#   Godot_v4.8-beta1_win64_console.exe --headless --path godot --script res://tools/_test_death_dissolve.gd
# Prints FAIL lines for every broken expectation and exits non-zero if any fail.
extends SceneTree

const TWEEN_META := "_death_dissolve_tween"
const ORIGINAL_META := "_death_dissolve_original"

var failures := 0

func _initialize() -> void:
	var player := (load("res://scenes/skin.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(player)
	await process_frame

	# Dress the player the way the game does, so the dissolve is tested against
	# the real skin materials rather than the scene's authored defaults.
	SkinApplier.new().apply_skin(player, "s-default")
	await process_frame

	# `s-default` dresses the body in StandardMaterial3D, so the shader-colour
	# paths would otherwise go untested. These probes use the real face shaders
	# with their real colour uniforms: a vec4 `albedo`, a vec3 `eye_color` and a
	# vec4 `mouth_color`. Getting any of them wrong shows as a grey face mid-burn.
	_add_probe_mesh(player, "ProbeAlbedo", "res://assets/shaders/skin_shaded.gdshader", {
		"albedo": Color(0.2, 0.4, 0.6, 1.0),
	})
	_add_probe_mesh(player, "ProbeEye", "res://assets/shaders/eye.gdshader", {
		"eye_color": Vector3(0.9, 0.8, 0.1),
	})
	_add_probe_mesh(player, "ProbeMouth", "res://assets/shaders/mouth_wobble.gdshader", {
		"mouth_color": Color(0.1, 0.05, 0.02, 1.0),
	})

	var meshes := _meshes(player)
	_check("player has meshes to dissolve", meshes.size() > 0)

	# Reference the skin materials as they are now. The dissolve must swap them
	# out, never edit them: one instance is shared by every player on that skin.
	var shared: Array[Material] = []
	for mesh in meshes:
		shared.append(mesh.material_override)

	var with_materials := 0
	for material in shared:
		if material != null:
			with_materials += 1
	_check("the model ships materials to preserve", with_materials > 0)

	var label := _first_label(player)
	var label_alpha_before := label.modulate.a if label != null else 1.0

	# 1. Every mesh moves onto the dissolve shader.
	DeathDissolve.begin(player, 0.05)
	_check("every mesh uses the dissolve shader", _count_on_dissolve(meshes) == meshes.size())

	# 2. The shared skin materials are untouched, so no other player dissolves.
	var shared_untouched := 0
	for material in shared:
		if not (material is ShaderMaterial) or (material as ShaderMaterial).shader != DeathDissolve.SHADER:
			shared_untouched += 1
	_check("shared skin materials are not mutated", shared_untouched == shared.size())

	# 3. The effect starts solid, so the first frame of death looks like the
	#    player standing there and not like a half-eaten body.
	_check("dissolve starts at 0", _count_with_dissolve_at_least(meshes, 0.0, 0.001) == meshes.size())

	# 4. Every colour convention the face and body shaders use survives the swap;
	#    otherwise the character pops grey for the frame before the burn bites in.
	_check("vec4 albedo is carried over", _probe_albedo_matches(player, "ProbeAlbedo", Color(0.2, 0.4, 0.6, 1.0)))
	_check("vec3 eye colour is carried over", _probe_albedo_matches(player, "ProbeEye", Color(0.9, 0.8, 0.1, 1.0)))
	_check("mouth colour is carried over", _probe_albedo_matches(player, "ProbeMouth", Color(0.1, 0.05, 0.02, 1.0)))
	_check("body colour is carried into the dissolve material", _body_colour_matches(meshes))

	# 5. The dissolve is animated, not instantaneous.
	var tween: Tween = player.get_meta(TWEEN_META, null)
	_check("a tween drives the dissolve", tween is Tween)
	if tween is Tween:
		await (tween as Tween).finished
	_check("dissolve reaches fully gone", _count_with_dissolve_at_least(meshes, 0.999, 1.0) == meshes.size())

	# 6. The floating name tag goes with the body instead of hanging over a hole.
	if label != null:
		_check("name tag fades out with the body", label.modulate.a <= 0.01)

	# 7. Restore puts back the exact same material instances, so the player comes
	#    back wearing the skin they had and not a rebuilt approximation of it.
	DeathDissolve.restore(player)
	_check("restore returns the original material instances", _count_same_material(meshes, shared) == meshes.size())
	if label != null:
		_check("name tag comes back", is_equal_approx(label.modulate.a, label_alpha_before))

	# 8. A second begin() must not snapshot the dissolve material as the
	#    "original", which would leave the player invisible forever.
	DeathDissolve.begin(player, 0.05)
	DeathDissolve.begin(player, 0.05)
	DeathDissolve.restore(player)
	_check("a repeated begin does not lose the skin", _count_same_material(meshes, shared) == meshes.size())

	# 9. Restoring when nothing is dissolving is a no-op, so every revive path can
	#    call it unconditionally.
	DeathDissolve.restore(player)
	_check("restore outside a dissolve is a no-op", _count_same_material(meshes, shared) == meshes.size())

	# 10. A player outside the scene tree has nothing to render and no Tween to
	#     attach to; begin() must shrug instead of erroring.
	var orphan := (load("res://scenes/skin.tscn") as PackedScene).instantiate() as Node3D
	DeathDissolve.begin(orphan, 0.05)
	_check("begin outside the tree is skipped", not orphan.has_meta(TWEEN_META))
	orphan.free()

	# 11. The real wiring: dying is what starts the burn.
	DeathDissolve.begin(player, 0.05)
	DeathDissolve.restore(player)
	player.die()
	_check("die() starts the dissolve", player.has_meta(TWEEN_META))
	_check("die() puts the model on the dissolve shader", _count_on_dissolve(meshes) == meshes.size())
	DeathDissolve.restore(player)
	_check("dying is reversible", _count_same_material(meshes, shared) == meshes.size())

	# 12. The burn must be under way almost immediately. A slow-start curve (the
	#     first version used EASE_IN) reads as a delay: the body stands untouched
	#     for a moment and then pops out of existence.
	DeathDissolve.begin(player, 1.0)
	var burn: Tween = player.get_meta(TWEEN_META, null)
	if burn is Tween:
		(burn as Tween).custom_step(0.2)
	_check("the burn is under way within 20% of its duration", _min_dissolve(meshes) >= 0.25)
	DeathDissolve.restore(player)

	# 13. Warm-up: the shader is compiled by drawing it for one frame before
	#     anyone dies. Nothing renders headless, so there is no program to compile
	#     and the warm-up must stay out of the way instead of allocating probes.
	DeathDissolve.prewarm(player)
	_check("warm-up does not run headless", not DeathDissolve.is_prewarmed())
	_check("warm-up leaves no probe behind", _find_probe(root) == null)

	print("death dissolve selftest: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func _find_probe(node: Node) -> Node:
	for child in node.get_children():
		if child.name == "DeathDissolvePrewarm":
			return child
		var found := _find_probe(child)
		if found != null:
			return found
	return null


func _meshes(player: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child in player.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh != null:
			result.append(mesh)
	return result


func _first_label(player: Node3D) -> Label3D:
	for child in player.find_children("*", "Label3D", true, false):
		var label := child as Label3D
		if label != null:
			return label
	return null


func _count_on_dissolve(meshes: Array[MeshInstance3D]) -> int:
	var count := 0
	for mesh in meshes:
		var material := mesh.material_override as ShaderMaterial
		if material != null and material.shader == DeathDissolve.SHADER:
			count += 1
	return count


## Lowest dissolve value across the model, used to prove the burn is already
## under way early in the tween rather than stalling at zero.
func _min_dissolve(meshes: Array[MeshInstance3D]) -> float:
	var lowest := 1.0
	for mesh in meshes:
		var material := mesh.material_override as ShaderMaterial
		if material == null:
			continue
		lowest = minf(lowest, float(material.get_shader_parameter("dissolve")))
	return lowest


func _count_with_dissolve_at_least(meshes: Array[MeshInstance3D], minimum: float, maximum: float) -> int:
	var count := 0
	for mesh in meshes:
		var material := mesh.material_override as ShaderMaterial
		if material == null:
			continue
		var value := float(material.get_shader_parameter("dissolve"))
		if value >= minimum and value <= maximum:
			count += 1
	return count


func _count_same_material(meshes: Array[MeshInstance3D], expected: Array[Material]) -> int:
	var count := 0
	for index in meshes.size():
		if is_same(meshes[index].material_override, expected[index]):
			count += 1
	return count


## True when at least one dissolve material carries the colour of the material it
## replaced. Handles both material kinds the player ships with: an applied skin is
## a ShaderMaterial, while an unskinned mesh keeps the scene's StandardMaterial3D.
func _body_colour_matches(meshes: Array[MeshInstance3D]) -> bool:
	for mesh in meshes:
		var original: Variant = mesh.get_meta(ORIGINAL_META, null)
		var expected := Color(0.8, 0.8, 0.85, 1.0)
		var known := false
		if original is StandardMaterial3D:
			expected = (original as StandardMaterial3D).albedo_color
			known = true
		elif original is ShaderMaterial:
			var value: Variant = (original as ShaderMaterial).get_shader_parameter("albedo")
			if value is Color:
				expected = value
				known = true
		if not known:
			continue
		var dissolve := mesh.material_override as ShaderMaterial
		if dissolve == null:
			continue
		var actual: Variant = dissolve.get_shader_parameter("albedo")
		if not (actual is Color):
			return false
		return (actual as Color).is_equal_approx(expected)
	return false


## How many meshes are wearing a real skin shader, so the "shared materials are
## not mutated" assertion cannot pass by testing nothing at all.
func _count_skin_shader_materials(meshes: Array[MeshInstance3D]) -> int:
	var count := 0
	for mesh in meshes:
		var material := mesh.material_override as ShaderMaterial
		if material != null and material.get_shader_parameter("albedo") is Color:
			count += 1
	return count


## Adds a throwaway mesh driven by a real game shader, so the colour-copy path
## for each uniform convention can be asserted directly.
func _add_probe_mesh(player: Node3D, node_name: String, shader_path: String, params: Dictionary) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	mesh.mesh = SphereMesh.new()
	var material := ShaderMaterial.new()
	material.shader = load(shader_path)
	for key in params:
		material.set_shader_parameter(key, params[key])
	mesh.material_override = material
	player.add_child(mesh)


func _probe_albedo_matches(player: Node3D, node_name: String, expected: Color) -> bool:
	var mesh := player.get_node_or_null(node_name) as MeshInstance3D
	if mesh == null:
		return false
	var material := mesh.material_override as ShaderMaterial
	if material == null:
		return false
	var actual: Variant = material.get_shader_parameter("albedo")
	return actual is Color and (actual as Color).is_equal_approx(expected)


func _check(name: String, condition: bool) -> void:
	if condition:
		print("PASS  ", name)
	else:
		failures += 1
		print("FAIL  ", name)
