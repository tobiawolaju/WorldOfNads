# Exports every equippable attachment from skin.tscn as an individual GLB plus a
# manifest.json into frontend/public/attachments/. The web store preview
# (frontend/src/components/ThreeScene.tsx) reads the manifest and dresses the
# nad with the same nodes - and the same authored transforms - as the game.
#
# Re-run this whenever attachments change in skin.tscn:
#   Godot_v4.7-stable_win64_console.exe --headless --path godot --script res://tools/export_attachments.gd
#
# skinConfig.attachments references these by node name, so adding a new
# attachment in the future = drop the node under a slot in skin.tscn, re-run
# this script, and list the name in the skin config. Nothing else changes.
#
# Placement contract (verified with tools/_probe_bone_attachment.gd): at runtime
# a BoneAttachment3D overwrites its own transform with the bone's pose, so the
# slot children are stored in pure bone space. The exporter therefore wraps each
# node in an identity root, which makes the GLB's transform chain exactly the
# bone-local transform three.js needs to re-parent under the same bone.
extends SceneTree

const SKIN_SCENE := "res://scenes/skin.tscn"

# Mirrors SkinApplier.ATTACHMENT_SLOTS - keep in sync when slots change.
const SLOTS: Array[String] = [
	"Skeleton3D/heddds/offset",
	"Skeleton3D/hips",
	"Skeleton3D/Back/offset",
]

# Lives in Vite's public/ folder, served at /attachments/*.
const OUT_DIR := "res://../frontend/public/attachments"

func _initialize() -> void:
	quit(0 if _run() == OK else 1)

func _run() -> Error:
	var packed := load(SKIN_SCENE) as PackedScene
	if packed == null:
		push_error("export_attachments: cannot load " + SKIN_SCENE)
		return ERR_CANT_OPEN
	var scene := packed.instantiate()

	var out_dir := ProjectSettings.globalize_path(OUT_DIR)
	if not DirAccess.dir_exists_absolute(out_dir):
		var mk := DirAccess.make_dir_recursive_absolute(out_dir)
		if mk != OK:
			push_error("export_attachments: cannot create " + out_dir)
			scene.free()
			return mk

	var manifest := {}
	var exported := 0

	for slot_path in SLOTS:
		var slot := scene.get_node_or_null(slot_path) as Node3D
		if slot == null:
			push_warning("export_attachments: slot not found in skin.tscn: " + slot_path)
			continue
		# The bone comes from the slot's BoneAttachment3D. Usually the slot is an
		# "offset" child of the attachment (heddds/offset, Back/offset), but the
		# hips slot has no offset node, so the slot itself is the attachment.
		var bone := ""
		var host: Node = slot if slot is BoneAttachment3D else slot.get_parent()
		if host is BoneAttachment3D:
			bone = (host as BoneAttachment3D).bone_name
		for child in slot.get_children():
			if not (child is Node3D):
				continue
			var attachment_name := String(child.name)
			var file_name := attachment_name + ".glb"
			var err := _export_node(child as Node3D, out_dir.path_join(file_name))
			if err != OK:
				push_error("export_attachments: %s failed: %s" % [attachment_name, error_string(err)])
				continue
			manifest[attachment_name] = { "file": file_name, "bone": bone }
			exported += 1

	scene.free()

	var manifest_file := FileAccess.open(out_dir.path_join("manifest.json"), FileAccess.WRITE)
	if manifest_file == null:
		return FileAccess.get_open_error()
	manifest_file.store_string(JSON.stringify(manifest, "\t"))
	manifest_file.close()

	print("export_attachments: exported %d attachments to %s" % [exported, out_dir])
	print(JSON.stringify(manifest, "\t"))
	return OK

func _export_node(node: Node3D, path: String) -> Error:
	# Wrap the node in an identity root so its own local transform survives the
	# round-trip as a child transform (a root node's transform is the one thing
	# exporters may bake or drop). The wrapper is dropped again implicitly: the
	# GLB's scene root ends up identity with the attachment below it.
	var wrapper := Node3D.new()
	var clone := node.duplicate() as Node3D
	if clone == null:
		wrapper.free()
		return ERR_INVALID_DATA
	clone.visible = true
	wrapper.add_child(clone)
	clone.owner = wrapper

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(wrapper, state)
	if err == OK:
		var buffer := doc.generate_buffer(state)
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			err = FileAccess.get_open_error()
		else:
			file.store_buffer(buffer)
			file.close()
	wrapper.free()
	return err
