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
	return (d as Dictionary).duplicate(true) if d is Dictionary else {}

func apply_skin(player: Node3D, skin_name: String) -> void:
	var data := get_skin_data(skin_name)
	if data.is_empty():
		return

	var outline_shader := preload("res://assets/shaders/outline.gdshader")
	var face_shader := preload("res://assets/shaders/face.gdshader")
	var skin_shaded := preload("res://assets/shaders/skin_shaded.gdshader")
	var skin_unshaded := preload("res://assets/shaders/skin_unshaded.gdshader")

	var palette: Dictionary = data.get("palette", {})
	var outline_color := _c(data.get("outline_color", [1, 0, 1, 1]))
	var crown_color := _c(data.get("crown_color", [1, 0, 1, 1]))
	var shader_type := str(data.get("shader", "default"))
	var shader_targets: Array = data.get("shader_targets", ["body", "cheek", "eye"])
	var attachment_data: Dictionary = data.get("attachment", {})

	var face_tex: Texture2D = null
	var face_path := str(data.get("face_texture", ""))
	if face_path != "":
		face_tex = load(face_path) as Texture2D

	var meshes: Array[MeshInstance3D] = []
	for c in player.find_children("*", "MeshInstance3D", true):
		if c is MeshInstance3D:
			meshes.append(c as MeshInstance3D)

	for mi in meshes:
		var name := mi.name

		if name.begins_with("body"):
			var col := _c(palette.get("body", [1, 1, 1, 1]))
			if name == "body_01":
				col = _c(palette.get("body_alt", [1, 1, 1, 1]))
			_assign_body_material(mi, col, outline_color, shader_type, shader_targets, "body", skin_shaded, skin_unshaded, outline_shader)

		elif name.begins_with("cheek"):
			var col := _c(palette.get("cheek", [1, 1, 1, 1]))
			_assign_body_material(mi, col, outline_color, shader_type, shader_targets, "cheek", skin_shaded, skin_unshaded, outline_shader)

		elif name.begins_with("eye"):
			var col := _c(palette.get("eye", [1, 1, 1, 1]))
			_assign_body_material(mi, col, outline_color, shader_type, shader_targets, "eye", skin_shaded, skin_unshaded, outline_shader)

		elif name.begins_with("crown"):
			_assign_crown_material(mi, crown_color)

		elif name == "face":
			var mat := ShaderMaterial.new()
			mat.shader = face_shader
			if face_tex:
				mat.set_shader_parameter("face_tex", face_tex)
			mat.set_shader_parameter("thickness", 0.145)
			mi.material_override = mat

		elif name == "attachment":
			var col := _c(attachment_data.get("color", [1, 1, 1, 1]))
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			mat.albedo_color = col
			mat.roughness = 0.5
			mi.material_override = mat

		else:
			var col := _c(palette.get("skin", [1, 1, 1, 1]))
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

func _assign_body_material(mi: MeshInstance3D, color: Color, outline_color: Color, shader_type: String, shader_targets: Array, target: String, skin_shaded: Shader, skin_unshaded: Shader, outline_shader: Shader) -> void:
	var apply_target := target in shader_targets

	var body_mat: Material
	if apply_target and shader_type != "default":
		match shader_type:
			"ghost":
				body_mat = StandardMaterial3D.new()
				body_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				body_mat.albedo_color = color
				body_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				body_mat.alpha_scissor_threshold = 0.0
				body_mat.alpha_hash_scale = 1.0
				var alpha := 0.6
				body_mat.albedo_color.a = alpha
				mi.material_override = body_mat
				return

			"gold":
				var mat := ShaderMaterial.new()
				mat.shader = skin_unshaded
				mat.set_shader_parameter("albedo", color)
				var outline_mat := ShaderMaterial.new()
				outline_mat.shader = outline_shader
				outline_mat.set_shader_parameter("color", outline_color)
				outline_mat.set_shader_parameter("size", 1.04)
				var base_mat := StandardMaterial3D.new()
				base_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				base_mat.albedo_color = color
				base_mat.metallic = 0.8
				base_mat.roughness = 0.2
				base_mat.next_pass = outline_mat
				mi.material_override = base_mat
				return

			"shadow":
				var mat := ShaderMaterial.new()
				mat.shader = skin_unshaded
				mat.set_shader_parameter("albedo", Color(0, 0, 0, 1))
				mi.material_override = mat
				return

			"void":
				var mat := ShaderMaterial.new()
				mat.shader = skin_unshaded
				mat.set_shader_parameter("albedo", Color(0, 0, 0, 0))
				mi.material_override = mat
				return

			"angel":
				var base_mat := StandardMaterial3D.new()
				base_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
				base_mat.albedo_color = color
				base_mat.roughness = 0.3
				if target == "eye":
					base_mat.emission_enabled = true
					base_mat.emission = color
					base_mat.emission_energy_multiplier = 2.0
				var outline_mat := ShaderMaterial.new()
				outline_mat.shader = outline_shader
				outline_mat.set_shader_parameter("color", outline_color)
				outline_mat.set_shader_parameter("size", 1.04)
				base_mat.next_pass = outline_mat
				mi.material_override = base_mat
				return

	var body_mat2 := StandardMaterial3D.new()
	body_mat2.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	body_mat2.albedo_color = color
	body_mat2.roughness = 0.5

	var outline_mat2 := ShaderMaterial.new()
	outline_mat2.shader = outline_shader
	outline_mat2.set_shader_parameter("color", outline_color)
	outline_mat2.set_shader_parameter("size", 1.04)
	body_mat2.next_pass = outline_mat2

	mi.material_override = body_mat2

func _assign_crown_material(mi: MeshInstance3D, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.metallic = 0.8
	mat.roughness = 0.2
	mi.material_override = mat

static func _c(v: Variant) -> Color:
	var arr: Array = v if v is Array else [1, 1, 1, 1]
	var a: float = arr[3] if arr.size() > 3 else 1.0
	return Color(arr[0], arr[1], arr[2], a)
