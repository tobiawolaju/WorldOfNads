# Headless selftest for the hold-to-reveal extras and the reveal colour
# (SkinApplier.set_hidden_extras_visible / SkinApplier.set_reveal_tint).
#   Godot_v4.8-beta1_win64_console.exe --headless --path godot --script res://tools/_test_hidden_extras.gd
# Prints FAIL lines for every broken expectation and exits non-zero if any fail.
extends SceneTree

var failures := 0

func _initialize() -> void:
	var player := (load("res://scenes/skin.tscn") as PackedScene).instantiate() as Node3D
	var applier := SkinApplier.new()

	# 1. The scene ships the shirt, the wig and the glove switched off.
	_check("shirt starts hidden", not _visible(player, "Skeleton3D/shirt"))
	_check("wigs start hidden", not _visible(player, "Skeleton3D/wigs"))
	_check("glove starts hidden", not _visible(player, "Skeleton3D/glove"))

	# 2. The reveal shows all three.
	SkinApplier.set_hidden_extras_visible(player, true)
	_check("reveal shows shirt", _visible(player, "Skeleton3D/shirt"))
	_check("reveal shows wigs", _visible(player, "Skeleton3D/wigs"))
	_check("reveal shows glove", _visible(player, "Skeleton3D/glove"))

	# 3. Releasing restores exactly the state from before the reveal.
	SkinApplier.set_hidden_extras_visible(player, false)
	_check("release restores shirt", not _visible(player, "Skeleton3D/shirt"))
	_check("release restores wigs", not _visible(player, "Skeleton3D/wigs"))
	_check("release restores glove", not _visible(player, "Skeleton3D/glove"))

	# 4. A part that was hidden before the reveal goes back into hiding, and one
	#    that was visible stays visible.
	(player.get_node("Skeleton3D/shirt") as Node3D).visible = true
	SkinApplier.set_hidden_extras_visible(player, true)
	_check("reveal shows a visible shirt", _visible(player, "Skeleton3D/shirt"))
	SkinApplier.set_hidden_extras_visible(player, false)
	_check("release keeps a visible shirt", _visible(player, "Skeleton3D/shirt"))
	(player.get_node("Skeleton3D/shirt") as Node3D).visible = false

	# 5. The reveal only touches visibility, never the authored placement.
	var shirt := player.get_node("Skeleton3D/shirt") as Node3D
	var shirt_transform := shirt.transform
	SkinApplier.set_hidden_extras_visible(player, true)
	_check("reveal keeps the shirt transform", shirt.transform.is_equal_approx(shirt_transform))
	SkinApplier.set_hidden_extras_visible(player, false)

	# 6. A node that does not have the extras is ignored, not a crash.
	var bare := Node3D.new()
	SkinApplier.set_hidden_extras_visible(bare, true)
	SkinApplier.set_hidden_extras_visible(bare, false)
	_check("missing extras are ignored", true)

	# 7. The reveal survives a skin change: apply_skin never owns these nodes,
	#    so the revealed state is still in place afterwards.
	SkinApplier.set_hidden_extras_visible(player, true)
	applier.apply_skin(player, "s-default")
	_check("reveal survives a skin change", _visible(player, "Skeleton3D/wigs"))
	SkinApplier.set_hidden_extras_visible(player, false)
	_check("release after a skin change hides wigs", not _visible(player, "Skeleton3D/wigs"))

	# 8. The reveal colour paints the character's skin, and releasing it puts
	#    the skin back the way it was. The top piece (body_00) keeps a light
	#    colour of its own, the body itself (body_01) takes the reveal colour.
	var body_top := player.get_node_or_null("Skeleton3D/body_00") as MeshInstance3D
	var body := player.get_node_or_null("Skeleton3D/body_01") as MeshInstance3D
	applier.apply_skin(player, "s-default")
	var skin_color := _albedo(body)
	_check("the skin starts in its own colour", not _is_reveal_color(skin_color))
	SkinApplier.set_reveal_tint(player, true)
	_check("the reveal paints the body", _is_reveal_color(_albedo(body)))
	_check("the reveal lights up the top piece", _is_reveal_top_color(_albedo(body_top)))
	SkinApplier.set_reveal_tint(player, false)
	_check("the release restores the skin colour", _albedo(body).is_equal_approx(skin_color))
	_check("the release restores the top piece", not _is_reveal_top_color(_albedo(body_top)))

	# 9. The reveal colour reaches the cheeks too, in a lighter shade.
	SkinApplier.set_reveal_tint(player, true)
	var cheek := player.get_node_or_null("Skeleton3D/cheek_L") as MeshInstance3D
	_check("the reveal paints the cheek", _is_reveal_cheek_color(_albedo(cheek)))
	_check("the cheek is lighter than the body", _albedo(cheek) != _albedo(body))
	SkinApplier.set_reveal_tint(player, false)

	# 10. A skin change while the reveal is on keeps the colour on and becomes
	#     the skin the release goes back to.
	SkinApplier.set_reveal_tint(player, true)
	applier.apply_skin(player, "s-default-unshaded")
	_check("the colour survives a skin change", _is_reveal_color(_albedo(body)))
	SkinApplier.set_reveal_tint(player, false)
	_check("the release keeps the new skin", not _is_reveal_color(_albedo(body)))
	_check("the release keeps the unshaded shader", _is_unshaded(body))

	# 11. The reveal colour never leaks into the plain skin of another player.
	var other := (load("res://scenes/skin.tscn") as PackedScene).instantiate() as Node3D
	applier.apply_skin(other, "s-default")
	var other_body := other.get_node_or_null("Skeleton3D/body_01") as MeshInstance3D
	var other_top := other.get_node_or_null("Skeleton3D/body_00") as MeshInstance3D
	_check("another player keeps its own colour", not _is_reveal_color(_albedo(other_body)))
	_check("another player keeps its own top piece", not _is_reveal_top_color(_albedo(other_top)))
	other.free()

	# 12. A node without a skin is ignored, not a crash.
	SkinApplier.set_reveal_tint(bare, true)
	SkinApplier.set_reveal_tint(bare, false)
	_check("a missing skin is ignored", true)

	player.free()
	bare.free()
	if failures == 0:
		print("SELFTEST PASS")
		quit(0)
	else:
		print("SELFTEST FAIL: %d failure(s)" % failures)
		quit(1)

func _visible(player: Node, path: String) -> bool:
	var n := player.get_node_or_null(path)
	if n == null:
		_check("missing node " + path, false)
		return false
	return (n as Node3D).visible

# The colour the mesh is drawn in: a flat material exposes its albedo, the
# unshaded edition carries the same colour in its shader.
func _albedo(mesh: MeshInstance3D) -> Color:
	if mesh == null:
		_check("missing mesh", false)
		return Color(0.0, 0.0, 0.0, 0.0)
	var mat := mesh.material_override
	if mat is BaseMaterial3D:
		return (mat as BaseMaterial3D).albedo_color
	if mat is ShaderMaterial:
		var value: Variant = (mat as ShaderMaterial).get_shader_parameter("albedo")
		if value is Color:
			return value
	return Color(0.0, 0.0, 0.0, 0.0)

func _is_reveal_color(color: Color) -> bool:
	return color.is_equal_approx(SkinApplier.REVEAL_TINT)

func _is_reveal_top_color(color: Color) -> bool:
	return color.is_equal_approx(SkinApplier.REVEAL_TOP_COLOR)

func _is_reveal_cheek_color(color: Color) -> bool:
	return color.is_equal_approx(SkinApplier.REVEAL_TINT.lightened(SkinApplier.REVEAL_CHEEK_LIGHTEN))

func _is_unshaded(mesh: MeshInstance3D) -> bool:
	return mesh != null and mesh.material_override is ShaderMaterial

func _check(label: String, ok: bool) -> void:
	if ok:
		print("PASS  " + label)
	else:
		failures += 1
		print("FAIL  " + label)
