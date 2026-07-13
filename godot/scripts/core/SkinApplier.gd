extends RefCounted
class_name SkinApplier

const DEFAULT_SKIN := "s-default"

static var _api_cache: Dictionary = {}

const FALLBACK_SHADED: Dictionary = {
	"palette": {
		"body": [0.988, 0.176, 0.588, 1],
		"body_alt": [0.988, 0.294, 0.549, 1],
		"cheek": [0.988, 0.416, 0.608, 1],
		"eye": [0.906, 0.906, 0.906, 1],
		"skin": [1.0, 0.612, 0.431, 1]
	},
	"outline_color": [0.988, 0.0, 0.851, 1],
	"crown_color": [0.988, 0.0, 0.851, 1],
	"face_texture": "",
	"shader": "default",
	"shader_targets": ["body", "cheek", "eye"],
	"attachment": { "shape": "box", "color": [1.0, 0.612, 0.431, 1] }
}

const FALLBACK_UNSHADED: Dictionary = {
	"palette": {
		"body": [0.988, 0.176, 0.588, 1],
		"body_alt": [0.988, 0.294, 0.549, 1],
		"cheek": [0.988, 0.416, 0.608, 1],
		"eye": [0.906, 0.906, 0.906, 1],
		"skin": [1.0, 0.612, 0.431, 1]
	},
	"outline_color": [0.988, 0.0, 0.851, 1],
	"crown_color": [0.988, 0.0, 0.851, 1],
	"face_texture": "",
	"shader": "unshaded",
	"shader_targets": ["body", "cheek", "eye"],
	"attachment": { "shape": "box", "color": [1.0, 0.612, 0.431, 1] }
}

static func seed_from_api(json_array: Array) -> void:
	print("[HEX_TEST] test conversion: _hex2rgba('#ff8c00') = %s" % JSON.stringify(_hex2rgba("#ff8c00")))
	for entry in json_array:
		if entry is Dictionary:
			var key: String = str(entry.get("id", ""))
			if key == "":
				key = str(entry.get("name", "")).to_lower().replace(" ", "-")
			if key == "":
				continue
			var skin_config: Dictionary = entry.get("skinConfig", entry.get("skin_config", {}))
			if skin_config.is_empty():
				continue
			if skin_config.has("palette") and skin_config["palette"] is Dictionary:
				var raw_body = str(skin_config["palette"].get("body", ""))
				print("[SEED] skin='%s' raw palette['body']='%s' length=%d" % [key, raw_body, len(raw_body)])
			_api_cache[key] = _convert_api_entry(skin_config)

static func seed_single_from_api(skin_id: String, entry: Dictionary) -> void:
	var skin_config: Dictionary = entry.get("skinConfig", entry.get("skin_config", {}))
	if not skin_config.is_empty():
		_api_cache[skin_id] = _convert_api_entry(skin_config)

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
		print("[HEX] not a string, type=%d" % typeof(hex))
		return [1.0, 1.0, 1.0, 1.0]
	var s: String = str(hex).strip_edges().trim_prefix("#")
	if s.length() < 6:
		print("[HEX] short hex '%s' len=%d" % [s, s.length()])
		return [1.0, 1.0, 1.0, 1.0]
	var r_val := s.substr(0, 2).hex_to_int()
	var g_val := s.substr(2, 2).hex_to_int()
	var b_val := s.substr(4, 2).hex_to_int()
	var r := float(r_val) / 255.0
	var g := float(g_val) / 255.0
	var b := float(b_val) / 255.0
	if r_val == 0 and g_val == 0 and b_val == 0:
		print("[HEX] WARNING: all-zero from input='%s' strip='%s' parts=[%s,%s,%s]" % [str(hex), s, s.substr(0,2), s.substr(2,2), s.substr(4,2)])
	var a := 1.0
	if s.length() >= 8:
		a = float(s.substr(6, 2).hex_to_int()) / 255.0
	return [r, g, b, a]

static func get_skin_data(skin_name: String) -> Dictionary:
	var key := str(skin_name).strip_edges().to_lower()
	# Default skins ALWAYS use hardcoded fallback — never read from cache
	match key:
		DEFAULT_SKIN:
			return FALLBACK_SHADED.duplicate(true)
		"s-default-unshaded":
			return FALLBACK_UNSHADED.duplicate(true)
	if _api_cache.has(key):
		var cached = _api_cache[key].duplicate(true)
		# Validate: if palette has all-zero colors, cache is corrupt — use fallback
		if _is_all_black(cached):
			print("[SKIN_DEBUG] get_skin_data('%s') -> CACHE CORRUPT (all black), fallback" % key)
			return FALLBACK_SHADED.duplicate(true)
		print("[SKIN_DEBUG] get_skin_data('%s') -> CACHE HIT" % key)
		return cached
	print("[SKIN_DEBUG] get_skin_data('%s') -> CACHE MISS, fallback" % key)
	return FALLBACK_SHADED.duplicate(true)

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
		if mi.material_override != null:
			mi.material_override = null

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

			"unshaded":
				var mat := ShaderMaterial.new()
				mat.shader = skin_unshaded
				mat.set_shader_parameter("albedo", color)
				var outline_mat := ShaderMaterial.new()
				outline_mat.shader = outline_shader
				outline_mat.set_shader_parameter("color", Color(0, 0, 0, 1))
				outline_mat.set_shader_parameter("size", 1.04)
				mat.next_pass = outline_mat
				mi.material_override = mat
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
	if typeof(v) == TYPE_STRING:
		return _c(_hex2rgba(v))
	var arr: Array = v if v is Array else [1, 1, 1, 1]
	var a: float = arr[3] if arr.size() > 3 else 1.0
	return Color(arr[0], arr[1], arr[2], a)
