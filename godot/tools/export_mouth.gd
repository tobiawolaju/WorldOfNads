# Exports the mouth mesh from skin.tscn as a GLB for web use.
# Run with: Godot_v4.7-stable_win64_console.exe --headless --path godot --script res://tools/export_mouth.gd

extends SceneTree

const SKIN_SCENE := "res://scenes/skin.tscn"
const OUT_DIR := "res://../frontend/public/attachments"
const MOUTH_NODE_PATH := "Skeleton3D/mouth"
const MOUTH_FILE_NAME := "mouth.glb"

func _initialize() -> void:
	quit(0 if _run() == OK else 1)

func _run() -> Error:
	var packed := load(SKIN_SCENE) as PackedScene
	if packed == null:
		push_error("export_mouth: cannot load " + SKIN_SCENE)
		return ERR_CANT_OPEN
	var scene := packed.instantiate()

	var out_dir := ProjectSettings.globalize_path(OUT_DIR)
	if not DirAccess.dir_exists_absolute(out_dir):
		var mk := DirAccess.make_dir_recursive_absolute(out_dir)
		if mk != OK:
			push_error("export_mouth: cannot create " + out_dir)
			scene.free()
			return mk

	var mouth_node := scene.get_node_or_null(MOUTH_NODE_PATH) as Node3D
	if mouth_node == null:
		push_error("export_mouth: mouth node not found at " + MOUTH_NODE_PATH)
		scene.free()
		return ERR_FILE_NOT_FOUND

	var file_name := MOUTH_FILE_NAME
	var err := _export_node(mouth_node as Node3D, out_dir.path_join(file_name))
	if err != OK:
		push_error("export_mouth: %s failed: %s" % [MOUTH_NODE_PATH, error_string(err)])
		scene.free()
		return err

	scene.free()
	print("export_mouth: exported mouth to %s" % [out_dir.path_join(file_name)])
	return OK

func _export_node(node: Node3D, path: String) -> Error:
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