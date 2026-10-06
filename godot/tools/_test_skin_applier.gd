# Headless selftest for SkinApplier's attachment lists + odd/even shading rule.
#   Godot_v4.7-stable_win64_console.exe --headless --path godot --script res://tools/_test_skin_applier.gd
# Prints FAIL lines for every broken expectation and exits non-zero if any fail.
extends SceneTree

var failures := 0

func _initialize() -> void:
	var applier := SkinApplier.new()
	var player := (load("res://scenes/skin.tscn") as PackedScene).instantiate() as Node3D

	# 1. Named default skins keep the scene's default loadout.
	applier.apply_skin(player, "s-default")
	_check("s-default wears linnconcap", _visible(player, "Skeleton3D/heddds/offset/linnconcap"))
	_check("s-default wears duck", _visible(player, "Skeleton3D/hips/duck"))
	_check("s-default hides hair", not _visible(player, "Skeleton3D/heddds/offset/hair"))
	_check("s-default body stays shaded", not _is_unshaded_body(player))

	applier.apply_skin(player, "s-default-unshaded")
	_check("s-default-unshaded wears linnconcap", _visible(player, "Skeleton3D/heddds/offset/linnconcap"))
	_check("s-default-unshaded body is unshaded", _is_unshaded_body(player))

	# 2. Numeric ids pick shading by parity; named ids keep their config.
	_check("odd id is shaded", str(SkinApplier.get_skin_data("0003").get("shader")) == "default")
	_check("even id is unshaded", str(SkinApplier.get_skin_data("0002").get("shader")) == "unshaded")
	_check("zero-padded id parses", str(SkinApplier.get_skin_data("0007").get("shader")) == "default")
	_check("named id keeps config shader",
		str(SkinApplier.get_skin_data("s-default-unshaded").get("shader")) == "unshaded")

	# 3. An api-seeded skin: parity overrides the configured shader, and the
	#    attachment list is honoured exactly (unknown names never crash).
	SkinApplier.seed_single_from_api("1002", { "skinConfig": {
		"palette": { "body": "#ff0000" },
		"shader": "ghost",
		"attachments": ["hair_001", "duck", "not_a_node"],
	} })
	var data := SkinApplier.get_skin_data("1002")
	_check("even seeded id forced unshaded over ghost", str(data.get("shader")) == "unshaded")
	_check("cached config not mutated by parity",
		str(SkinApplier._api_cache["1002"].get("shader")) == "ghost")
	_check("fallback not mutated by parity",
		str(SkinApplier.FALLBACK_SHADED.get("shader")) == "default")

	var cap_path := "Skeleton3D/heddds/offset/linnconcap"
	var cap_before: Transform3D = (player.get_node(cap_path) as Node3D).transform
	applier.apply_skin(player, "1002")
	_check("1002 shows hair_001", _visible(player, "Skeleton3D/heddds/offset/hair_001"))
	_check("1002 shows duck", _visible(player, "Skeleton3D/hips/duck"))
	_check("1002 hides linnconcap", not _visible(player, cap_path))
	_check("1002 hides burger group", not _visible(player, "Skeleton3D/heddds/offset/burgr"))
	_check("1002 body material unshaded", _is_unshaded_body(player))
	_check("toggling never touches transforms",
		(player.get_node(cap_path) as Node3D).transform.is_equal_approx(cap_before))

	# 4. Explicit empty list means "wears nothing".
	SkinApplier.seed_single_from_api("1004", { "skinConfig": {
		"palette": { "body": "#00ff00" },
		"attachments": [],
	} })
	applier.apply_skin(player, "1004")
	_check("1004 hides linnconcap", not _visible(player, cap_path))
	_check("1004 hides duck", not _visible(player, "Skeleton3D/hips/duck"))
	_check("1004 hides all hats", not _visible(player, "Skeleton3D/heddds/offset/strawhat"))

	# 5. A skin without an attachments key wears nothing (deterministic - the
	#    same rule the web preview applies, and no state leaks from the skin
	#    that was applied before it).
	SkinApplier.seed_single_from_api("1006", { "skinConfig": { "palette": { "body": "#0000ff" } } })
	applier.apply_skin(player, "1006")
	_check("no attachments key wears no cap", not _visible(player, cap_path))
	_check("no attachments key wears no duck", not _visible(player, "Skeleton3D/hips/duck"))

	player.free()
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

func _is_unshaded_body(player: Node) -> bool:
	var mat := (player.get_node("Skeleton3D/body_00") as MeshInstance3D).material_override
	if not (mat is ShaderMaterial):
		return false
	return (mat as ShaderMaterial).shader == load("res://assets/shaders/skin_unshaded.gdshader")

func _check(label: String, ok: bool) -> void:
	if ok:
		print("PASS  " + label)
	else:
		failures += 1
		print("FAIL  " + label)
