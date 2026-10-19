extends SceneTree
# Diagnostic: does apply_skin actually toggle attachments per id, and what
# happens for ids that are not in the API cache?

func _init() -> void:
	var scene: PackedScene = load("res://scenes/skin.tscn")
	var nad: Node3D = scene.instantiate()
	root.add_child(nad)
	var applier := SkinApplier.new()

	# Two entries as if they came from /api/skins.
	SkinApplier.seed_single_from_api("6", {"skinConfig": {"attachments": ["burgr", "duck"]}})
	SkinApplier.seed_single_from_api("7", {"skinConfig": {"attachments": ["hedset", "duck"]}})

	# Index as if it came from /api/skin-combos: combo 0 -> ids 1,2; combo 1 -> ids 3,4.
	SkinApplier.seed_index_from_api({
		"combos": [
			{"attachments": ["linnconcap", "duck"]},
			{"attachments": ["hair_001", "duck"]},
		],
		"defaults": {"s-default": [], "s-default-unshaded": []},
	})

	_dump(nad, applier, "6")        # seeded -> burger + duck
	_dump(nad, applier, "7")        # seeded -> headset + duck
	_dump(nad, applier, "0001")     # index combo 0 -> cap + duck
	_dump(nad, applier, "0002")     # index combo 0 -> cap + duck (unshaded)
	_dump(nad, applier, "0003")     # index combo 1 -> hair_001 + duck
	_dump(nad, applier, "0004")     # index combo 1 -> hair_001 + duck (unshaded)
	_dump(nad, applier, "9999")     # no index -> fallback
	_dump(nad, applier, "s-default")

	quit()

func _dump(nad: Node3D, applier, id: String) -> void:
	applier.apply_skin(nad, id)
	var data := SkinApplier.get_skin_data(id)
	var visible := PackedStringArray()
	for slot_path in SkinApplier.ATTACHMENT_SLOTS:
		var slot := nad.get_node_or_null(slot_path)
		if slot == null:
			continue
		for c in slot.get_children():
			if c is Node3D and (c as Node3D).visible:
				visible.append(String(c.name))
	print("id=%-10s shader=%-10s visible=%s" % [id, str(data.get("shader", "?")), ", ".join(visible)])