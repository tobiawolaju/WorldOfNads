extends RefCounted
class_name SkinApplier

const DEFAULT_SKIN := "s-default"

static var _api_cache: Dictionary = {}

const FALLBACK_SHADED: Dictionary = {
	"palette": {
		"body": [0.988, 0.176, 0.288, 1],
		"body_alt": [0.988, 0.176, 0.288, 1],
		"cheek":  [0.988, 0.294, 0.549, 1],
		"eye": [1.0, 1.0, 1.0, 1],
		"skin": [0.0, 0.0, 0.0, 1.0]
	},
	"outline_color": [0.988, 0.176, 0.288, 1],
	"crown_color": [1.0, 1.0, 0.0, 1],
	"face_texture": "res://assets/img/skins/face1.png",
	"shader": "default",
	"shader_targets": ["body", "cheek", "eye"],
	"attachment": { "shape": "box", "color": [1.0, 0.612, 0.431, 1] }
}

const FALLBACK_UNSHADED: Dictionary = {
	"palette": {
		"body": [0.988, 0.176, 0.288, 1],
		"body_alt": [0.988, 0.176, 0.288, 1],
		"cheek":[0.988, 0.294, 0.549, 1],
		"eye": [1.0, 1.0, 1.0, 1],
		"skin":  [0.0, 0.0, 0.0, 1.0]
	},
	"outline_color": [0.988, 0.0, 0.851, 1],
	"crown_color": [1.0, 1.0, 0.0, 1],
	"face_texture":  "res://assets/img/skins/face1.png",
	"shader": "unshaded",
	"shader_targets": ["body", "cheek", "eye"],
	"attachment": { "shape": "box", "color": [1.0, 0.612, 0.431, 1] }
}

static func seed_from_api(json_array: Array) -> void:
	for entry in json_array:
		if entry is Dictionary:
			var key: String = str(entry.get("id", "")).to_lower()
			if key == "":
				key = str(entry.get("name", "")).to_lower().replace(" ", "-")
			if key == "":
				continue
			var skin_config: Dictionary = entry.get("skinConfig", entry.get("skin_config", {}))
			if skin_config.is_empty():
				continue
			_api_cache[key] = _convert_api_entry(skin_config)

static func seed_single_from_api(skin_id: String, entry: Dictionary) -> void:
	var skin_config: Dictionary = entry.get("skinConfig", entry.get("skin_config", {}))
	if not skin_config.is_empty():
		_api_cache[skin_id.to_lower()] = _convert_api_entry(skin_config)

static func _convert_api_entry(skin_config: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in ["palette", "outline_color", "crown_color", "face_texture", "shader", "shader_targets", "attachment"]:
		if skin_config.has(key):
			result[key] = skin_config[key]
	if result.is_empty():
		return {}
	if result.has("palette") and result["palette"] is Dictionary:
		var converted_palette: Dictionary = {}
		for pkey in result["palette"]:
			var raw = result["palette"][pkey]
			converted_palette[pkey] = _hex2rgba(raw) if typeof(raw) == TYPE_STRING else raw
		result["palette"] = converted_palette
	for key in ["outline_color", "crown_color"]:
		if result.has(key):
			var raw = result[key]
			result[key] = _hex2rgba(raw) if typeof(raw) == TYPE_STRING else raw
	if result.has("attachment") and result["attachment"] is Dictionary:
		var att = result["attachment"]
		if att.has("color") and typeof(att["color"]) == TYPE_STRING:
			att["color"] = _hex2rgba(att["color"])
	return result

static func _hex2rgba(hex: Variant) -> Array:
	if typeof(hex) != TYPE_STRING:
		return [1.0, 1.0, 1.0, 1.0]
	var s: String = str(hex).strip_edges().trim_prefix("#")
	if s.length() < 6:
		return [1.0, 1.0, 1.0, 1.0]
	var r_val := s.substr(0, 2).hex_to_int()
	var g_val := s.substr(2, 2).hex_to_int()
	var b_val := s.substr(4, 2).hex_to_int()
	var r := float(r_val) / 255.0
	var g := float(g_val) / 255.0
	var b := float(b_val) / 255.0
	var a := 1.0
	if s.length() >= 8:
		a = float(s.substr(6, 2).hex_to_int()) / 255.0
	return [r, g, b, a]

static func get_skin_data(skin_name: String) -> Dictionary:
	var key := str(skin_name).strip_edges().to_lower()
	match key:
		DEFAULT_SKIN:
			return FALLBACK_SHADED
		"s-default-unshaded":
			return FALLBACK_UNSHADED
	if _api_cache.has(key):
		var cached = _api_cache[key]
		if _is_all_black(cached):
			return FALLBACK_SHADED
		return cached
	return FALLBACK_SHADED

static func _is_all_black(data: Dictionary) -> bool:
	var pal = data.get("palette", {})
	if pal.is_empty():
		return false
	for key in pal:
		var arr = pal.get(key)
		if arr is Array and arr.size() >= 3:
			if arr[0] != 0.0 or arr[1] != 0.0 or arr[2] != 0.0:
				return false
	return true

const OUTLINE_SHADER := preload("res://assets/shaders/outline.gdshader")
const FACE_SHADER := preload("res://assets/shaders/face.gdshader")
const SKIN_UNSHADED_SHADER := preload("res://assets/shaders/skin_unshaded.gdshader")

static var _skin_material_sets: Dictionary = {}
const MAX_MATERIAL_CACHE: int = 30

func apply_skin(player: Node3D, skin_name: String) -> void:
	var data := get_skin_data(skin_name)
	if data.is_empty():
		return

	var material_set := _get_material_set(skin_name, data)

	var meshes: Array[MeshInstance3D] = []
	for c in player.find_children("*", "MeshInstance3D", true):
		if c is MeshInstance3D:
			meshes.append(c as MeshInstance3D)

	for mi in meshes:
		var mat: Material = _material_for_name(material_set, mi.name)
		if mat != null:
			mi.material_override = mat

static func _get_material_set(skin_name: String, data: Dictionary) -> Dictionary:
	if _skin_material_sets.has(skin_name):
		return _skin_material_sets[skin_name]
	if _skin_material_sets.size() >= MAX_MATERIAL_CACHE:
		_skin_material_sets.clear()
	var material_set := _build_material_set(data)
	_skin_material_sets[skin_name] = material_set
	return material_set

static func _build_material_set(data: Dictionary) -> Dictionary:
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

	return {
		"body": _body_material(_c(palette.get("body", [1, 1, 1, 1])), outline_color, shader_type, shader_targets, "body"),
		"body_01": _body_material(_c(palette.get("body_alt", [1, 1, 1, 1])), outline_color, shader_type, shader_targets, "body"),
		"cheek": _body_material(_c(palette.get("cheek", [1, 1, 1, 1])), outline_color, shader_type, shader_targets, "cheek"),
		"eye": _body_material(_c(palette.get("eye", [1, 1, 1, 1])), outline_color, shader_type, shader_targets, "eye"),
		"crown": _crown_material(crown_color),
		"face": _face_material(face_tex),
		"attachment": _attachment_material(_c(attachment_data.get("color", [1, 1, 1, 1]))),
	}

static func _material_for_name(material_set: Dictionary, name: String) -> Material:
	if name.begins_with("body"):
		return material_set.get("body_01" if name == "body_01" else "body")
	if name.begins_with("cheek"):
		return material_set.get("cheek")
	if name.begins_with("eye"):
		return material_set.get("eye")
	if name == "crown_L" or name == "crown_R":
		return material_set.get("cheek")
	if name.begins_with("crown"):
		return material_set.get("crown")
	if name == "face":
		return material_set.get("face")
	if name == "attachment":
		return material_set.get("attachment")
	return null

static func _body_material(color: Color, outline_color: Color, shader_type: String, shader_targets: Array, target: String) -> Material:
	var apply_target := target in shader_targets

	if apply_target and shader_type != "default":
		match shader_type:
			"ghost":
				var ghost_mat := StandardMaterial3D.new()
				ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				ghost_mat.albedo_color = color
				ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				ghost_mat.alpha_scissor_threshold = 0.0
				ghost_mat.alpha_hash_scale = 1.0
				ghost_mat.albedo_color.a = 0.6
				return ghost_mat

			"gold":
				var gold_mat := ShaderMaterial.new()
				gold_mat.shader = SKIN_UNSHADED_SHADER
				gold_mat.set_shader_parameter("albedo", color)
				var gold_outline := ShaderMaterial.new()
				gold_outline.shader = OUTLINE_SHADER
				gold_outline.set_shader_parameter("color", outline_color)
				gold_outline.set_shader_parameter("size", 1.04)
				var gold_base := StandardMaterial3D.new()
				gold_base.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				gold_base.albedo_color = color
				gold_base.metallic = 0.8
				gold_base.roughness = 0.2
				gold_base.next_pass = gold_outline
				return gold_base

			"unshaded":
				var unshaded_mat := ShaderMaterial.new()
				unshaded_mat.shader = SKIN_UNSHADED_SHADER
				unshaded_mat.set_shader_parameter("albedo", color)
				var unshaded_outline := ShaderMaterial.new()
				unshaded_outline.shader = OUTLINE_SHADER
				unshaded_outline.set_shader_parameter("color", Color(0, 0, 0, 1))
				unshaded_outline.set_shader_parameter("size", 1.04)
				unshaded_mat.next_pass = unshaded_outline
				return unshaded_mat

			"shadow":
				var shadow_mat := ShaderMaterial.new()
				shadow_mat.shader = SKIN_UNSHADED_SHADER
				shadow_mat.set_shader_parameter("albedo", Color(0, 0, 0, 1))
				return shadow_mat

			"void":
				var void_mat := ShaderMaterial.new()
				void_mat.shader = SKIN_UNSHADED_SHADER
				void_mat.set_shader_parameter("albedo", Color(0, 0, 0, 0))
				return void_mat

			"angel":
				var angel_mat := StandardMaterial3D.new()
				angel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
				angel_mat.albedo_color = color
				angel_mat.roughness = 0.3
				if target == "eye":
					angel_mat.emission_enabled = true
					angel_mat.emission = color
					angel_mat.emission_energy_multiplier = 2.0
				var angel_outline := ShaderMaterial.new()
				angel_outline.shader = OUTLINE_SHADER
				angel_outline.set_shader_parameter("color", outline_color)
				angel_outline.set_shader_parameter("size", 1.04)
				angel_mat.next_pass = angel_outline
				return angel_mat

	var body_mat := StandardMaterial3D.new()
	body_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	body_mat.albedo_color = color
	body_mat.roughness = 0.5

	var outline_mat := ShaderMaterial.new()
	outline_mat.shader = OUTLINE_SHADER
	outline_mat.set_shader_parameter("color", outline_color)
	outline_mat.set_shader_parameter("size", 1.04)
	body_mat.next_pass = outline_mat
	return body_mat

static func _crown_material(color: Color) -> Material:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.metallic = 0.8
	mat.roughness = 0.2
	return mat

static func _face_material(face_tex: Texture2D) -> Material:
	var mat := ShaderMaterial.new()
	mat.shader = FACE_SHADER
	if face_tex:
		mat.set_shader_parameter("face_tex", face_tex)
	mat.set_shader_parameter("thickness", 0.145)
	return mat

static func _attachment_material(color: Color) -> Material:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.albedo_color = color
	mat.roughness = 0.5
	return mat

static func _c(v: Variant) -> Color:
	if typeof(v) == TYPE_STRING:
		return _c(_hex2rgba(v))
	var arr: Array = v if v is Array else [1, 1, 1, 1]
	var a: float = arr[3] if arr.size() > 3 else 1.0
	return Color(arr[0], arr[1], arr[2], a)
