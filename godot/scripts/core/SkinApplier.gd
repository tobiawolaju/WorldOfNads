extends RefCounted
class_name SkinApplier

const SKIN_DATA_PATH := "res://assets/data/skindata.json"
const DEFAULT_SKIN := "defaultnad"

var _cache: Dictionary = {}

func _init() -> void:
	_load_data()

func _load_data() -> void:
	var file := FileAccess.open(SKIN_DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("SkinApplier: Could not open %s" % SKIN_DATA_PATH)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	_cache = parsed as Dictionary if parsed is Dictionary else {}

func get_skin_data(skin_name: String) -> Dictionary:
	var d = _cache.get(skin_name, _cache.get(DEFAULT_SKIN, {}))
	return (d as Dictionary).duplicate() if d is Dictionary else {}

func apply_skin(player: Node3D, skin_name: String) -> void:
	var data := get_skin_data(skin_name)
	if data.is_empty():
		return

	var outline_shader := preload("res://assets/shaders/outline.gdshader")
	var face_shader := preload("res://assets/shaders/face.gdshader")
	var outline_color := _c(data.get("outline_color", [1, 0, 1, 1]))

	var face_tex: Texture2D = null
	var face_path := str(data.get("face_texture", ""))
	if face_path != "":
		face_tex = load(face_path) as Texture2D

	var palette := PackedColorArray([
		_c(data.get("body_color", [1, 1, 1, 1])),
		_c(data.get("body_alt_color", [1, 1, 1, 1])),
		_c(data.get("body_alt2_color", [1, 1, 1, 1])),
		_c(data.get("body_white_color", [1, 1, 1, 1])),
		_c(data.get("skin_color", [1, 1, 1, 1])),
	])

	var meshes: Array[MeshInstance3D] = []
	for c in player.find_children("*", "MeshInstance3D", true):
		if c is MeshInstance3D:
			meshes.append(c as MeshInstance3D)
	for mi in meshes:

		if mi.name == "face":
			var mat := ShaderMaterial.new()
			mat.shader = face_shader
			mi.material_override = mat
			continue

		if mi.name == "crown":
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = outline_color
			mat.metallic = 0.8
			mat.roughness = 0.2
			mi.material_override = mat
			continue

		var idx := int(mi.name.trim_prefix("Cube").trim_prefix("_")) % palette.size()
		var col := palette[idx]

		var body_mat := StandardMaterial3D.new()
		body_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		body_mat.albedo_color = col
		body_mat.roughness = 0.5

		var outline_mat := ShaderMaterial.new()
		outline_mat.shader = outline_shader
		outline_mat.set_shader_parameter("color", outline_color)
		outline_mat.set_shader_parameter("size", 1.04)
		body_mat.next_pass = outline_mat

		mi.material_override = body_mat

static func _c(v: Variant) -> Color:
	var arr: Array = v if v is Array else [1, 1, 1, 1]
	var a: float = arr[3] if arr.size() > 3 else 1.0
	return Color(arr[0], arr[1], arr[2], a)
