extends RefCounted
class_name SkinApplier

const DEFAULT_SKIN := "s-default"

static var _api_cache: Dictionary = {}
# id -> attachments resolved from the shared index (GET /api/skin-combos). Used
# when a skin's own config does not pin an attachments list, so any numbered id
# resolves its combo at runtime without needing a per-skin document.
static var _index_cache: Dictionary = {}

const FALLBACK_SHADED: Dictionary = {
	"palette": {
		"body":  [0.988, 0.176, 0.532, 1],
		"body_alt": [0.988, 0.176, 0.532, 1],
		"cheek":  [0.988, 0.294, 0.549, 1],
		"eye": [1.0, 1.0, 1.0, 1],
		"skin": [0.0, 0.0, 0.0, 1.0]
	},
	"outline_color": [0.988, 0.176, 0.532, 1],
	"crown_color": [1.0, 1.0, 0.0, 1],
	"shader": "default",
	"shader_targets": ["body", "cheek"],
	"attachment": { "shape": "box", "color": [1.0, 0.612, 0.431, 1] },
	# Which attachment nodes this skin wears (see ATTACHMENT_SLOTS). Keeps the
	# default nad looking exactly like skin.tscn ships: Lincoln cap + hip duck.
	"attachments": ["linnconcap", "duck"]
}

const FALLBACK_UNSHADED: Dictionary = {
	"palette": {
		"body": [0.988, 0.176, 0.532, 1],
		"body_alt": [0.988, 0.176, 0.532, 1],
		"cheek":[0.988, 0.294, 0.549, 1],
		"eye": [1.0, 1.0, 1.0, 1],
		"skin":  [0.0, 0.0, 0.0, 1.0]
	},
	"outline_color": [0.988, 0.0, 0.851, 1],
	"crown_color": [1.0, 1.0, 0.0, 1],
	"shader": "unshaded",
	"shader_targets": ["body", "cheek"],
	"attachment": { "shape": "box", "color": [1.0, 0.612, 0.431, 1] },
	"attachments": ["linnconcap", "duck"]
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
			_api_cache[_index_key(key)] = _convert_api_entry(skin_config)

static func seed_single_from_api(skin_id: String, entry: Dictionary) -> void:
	var skin_config: Dictionary = entry.get("skinConfig", entry.get("skin_config", {}))
	if not skin_config.is_empty():
		_api_cache[_index_key(skin_id)] = _convert_api_entry(skin_config)

# Seeds the id index from GET /api/skin-combos: combo n owns ids 2n+1 (shaded)
# and 2n+2 (unshaded), plus any named ids pinned in "defaults". This is the
# runtime half of backend/skinCombos.json, so the game can dress a numbered id
# that has no document of its own (a new mint, or a preview of an unminted id).
static func seed_index_from_api(payload: Dictionary) -> void:
	_index_cache.clear()
	var combos: Variant = payload.get("combos", [])
	if combos is Array:
		var index := 0
		for combo in combos:
			if combo is Dictionary:
				var atts: Variant = combo.get("attachments", [])
				if atts is Array:
					_index_cache[str(index * 2 + 1)] = atts
					_index_cache[str(index * 2 + 2)] = atts
			index += 1
	var pinned: Variant = payload.get("defaults", {})
	if pinned is Dictionary:
		for id in pinned.keys():
			var atts2: Variant = pinned[id]
			if atts2 is Array:
				_index_cache[str(id).to_lower()] = atts2


# Numeric ids are normalised so "0002", "2" and 2 all resolve to the same key.
static func _index_key(skin_id: String) -> String:
	var key := str(skin_id).strip_edges().to_lower()
	return str(int(key)) if key.is_valid_int() else key

static func _convert_api_entry(skin_config: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in ["palette", "outline_color", "crown_color", "shader", "shader_targets", "attachment", "attachments"]:
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
	# Drop "eye" from a server-supplied shader_targets list. The eye meshes own their own
	# material and must not be recoloured by a skin config, or the dot shader is replaced
	# by a flat colour and the pupil disappears.
	if result.has("shader_targets") and result["shader_targets"] is Array:
		var targets: Array = result["shader_targets"]
		targets.erase("eye")
		result["shader_targets"] = targets
	if result.has("attachment") and result["attachment"] is Dictionary:
		var att = result["attachment"]
		if att.has("color") and typeof(att["color"]) == TYPE_STRING:
			att["color"] = _hex2rgba(att["color"])
	# Attachment lists are just node names from skin.tscn ("duck", "hair_001", ...).
	# Non-strings are dropped here so apply_skin only ever sees plain names; a
	# malformed value is erased, which - like a missing key - means "wears
	# nothing" (the same thing the web preview does).
	if result.has("attachments"):
		if result["attachments"] is Array:
			var clean: Array = []
			for n in result["attachments"]:
				if typeof(n) == TYPE_STRING and not String(n).is_empty():
					clean.append(String(n))
			result["attachments"] = clean
		else:
			result.erase("attachments")
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
	var key := _index_key(skin_name)
	var cached: Variant = _api_cache.get(key, null)
	var data: Dictionary
	match key:
		DEFAULT_SKIN:
			data = FALLBACK_SHADED
		"s-default-unshaded":
			data = FALLBACK_UNSHADED
		_:
			if cached is Dictionary:
				data = FALLBACK_SHADED if _is_all_black(cached) else cached
			else:
				data = FALLBACK_SHADED
	# The index owns the combo for any id whose own config does not pin an
	# attachments list: a document without one, or a numbered id with no
	# document at all (new mint, preview of an unminted id).
	if _index_cache.has(key) and not (cached is Dictionary and cached.has("attachments")):
		data = data.duplicate()
		data["attachments"] = _index_cache[key]
	return _apply_shading_parity(key, data)

# Numeric skin ids pick their shading by parity: odd ids are the shaded edition,
# even ids the unshaded variant (0001 shaded, 0002 flat, 0003 shaded, ...).
# Named ids (s-default, s-default-unshaded, ...) keep the shader their config
# asks for. The dictionary is duplicated before overriding so the shared
# fallback/cache entries are never mutated.
static func _apply_shading_parity(key: String, data: Dictionary) -> Dictionary:
	if not key.is_valid_int():
		return data
	var wanted := "default" if int(key) % 2 != 0 else "unshaded"
	if str(data.get("shader", "default")) == wanted:
		return data
	var copy := data.duplicate()
	copy["shader"] = wanted
	return copy

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
const SKIN_UNSHADED_SHADER := preload("res://assets/shaders/skin_unshaded.gdshader")

# Records the material an attachment mesh shipped with, captured before the
# first override is ever assigned, so re-applying an unshaded skin can rebuild
# from the authored material instead of from its own previous override.
const AUTHORED_MATERIAL_META := "_skin_authored_material"

static var _skin_material_sets: Dictionary = {}
const MAX_MATERIAL_CACHE: int = 30

# Attachment slots: the direct children of these nodes are the equippable
# attachment units (head hats/hair/burger/headset, hip duck, back items).
# Adding a new bone attachment to skin.tscn only requires adding its slot path
# here - the children themselves are discovered at runtime, so new attachment
# nodes never need a code change.
const ATTACHMENT_SLOTS: Array[String] = [
	"Skeleton3D/heddds/offset",
	"Skeleton3D/hips",
	"Skeleton3D/Back/offset",
]

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
		if String(mi.name).begins_with("eye"):
			_tint_eye(mi, data)
			continue
		var mat: Material = _material_for_name(material_set, mi.name)
		if mat != null:
			mi.material_override = mat

	_apply_attachments(player, data)

# Shows exactly the attachment nodes a skin lists and hides the rest. A skin
# with an empty list - or no "attachments" key at all - wears nothing, which is
# also what the web preview does, so game and web always agree. The default
# loadout is therefore spelled out explicitly in the fallback configs and in
# items.json rather than inherited from the scene. Unknown names are ignored on
# purpose: a skin may name an attachment that only lands in skin.tscn later, and
# a skin may still list a node that was renamed away - neither may break the
# rest of the skin. Only visibility is touched, never transforms, so every
# attachment keeps its authored placement. The shading decision (see
# _apply_attachment_shader) runs over the same units.
static func _apply_attachments(player: Node3D, data: Dictionary) -> void:
	var wanted: Variant = data.get("attachments", [])
	if not wanted is Array:
		wanted = []
	var shader_type := str(data.get("shader", "default"))
	for slot_path in ATTACHMENT_SLOTS:
		var slot := player.get_node_or_null(slot_path) as Node3D
		if slot == null:
			continue
		for child in slot.get_children():
			if child is Node3D:
				child.visible = String(child.name) in wanted
				_apply_attachment_shader(child, shader_type)

# Attachments follow the skin's shading decision. The unshaded edition draws
# the body flat with a black outline pass (see _body_material), so hats/duck
# have to go flat and outlined too or the edition reads half-finished. Each
# mesh keeps its own authored colour and texture - only the lighting model and
# the outline change, never the hue. Every other shader clears the override,
# so toggling back from an unshaded skin restores the authored material
# exactly instead of leaving a stale override behind.
static func _apply_attachment_shader(unit: Node3D, shader_type: String) -> void:
	var targets: Array[MeshInstance3D] = []
	if unit is MeshInstance3D:
		targets.append(unit as MeshInstance3D)
	for node in unit.find_children("*", "MeshInstance3D", true):
		if node is MeshInstance3D:
			targets.append(node as MeshInstance3D)
	for mi in targets:
		# Eyes keep the camera-facing dot shader from skin.tscn, always.
		if String(mi.name).begins_with("eye"):
			continue
		if shader_type != "unshaded":
			mi.material_override = null
			continue
		if not mi.has_meta(AUTHORED_MATERIAL_META):
			# Captured on the first touch, when material_override is still
			# whatever skin.tscn authored (apply_skin never claims these).
			mi.set_meta(AUTHORED_MATERIAL_META, mi.get_active_material(0))
		mi.material_override = _unshaded_attachment_material(mi.get_meta(AUTHORED_MATERIAL_META) as Material)

# The unshaded edition of an attachment: flat (no lighting) with the black
# 1.04 outline pass - the same combination _body_material builds for the body.
# The authored albedo colour and texture carry over, so the duck stays yellow
# and the cap keeps its print; only the shading changes.
static func _unshaded_attachment_material(authored: Material) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if authored is BaseMaterial3D:
		var src := authored as BaseMaterial3D
		mat.albedo_color = src.albedo_color
		mat.albedo_texture = src.albedo_texture
		mat.vertex_color_use_as_albedo = src.vertex_color_use_as_albedo
	elif authored is ShaderMaterial:
		var albedo: Variant = (authored as ShaderMaterial).get_shader_parameter("albedo")
		if albedo is Color:
			mat.albedo_color = albedo
	var outline := ShaderMaterial.new()
	outline.shader = OUTLINE_SHADER
	outline.set_shader_parameter("color", Color(0, 0, 0, 1))
	outline.set_shader_parameter("size", 1.04)
	mat.next_pass = outline
	return mat

# Recolours the eyes without replacing their material. The eye shader draws the
# camera-facing dot, so overwriting material_override here would discard it and leave a
# flat sphere. Instead the skin's eye colour is pushed into the existing ShaderMaterial as
# a uniform, which keeps the dot intact.
static func _tint_eye(mesh: MeshInstance3D, data: Dictionary) -> void:
	var palette: Dictionary = data.get("palette", {})
	if palette.is_empty() or not palette.has("eye"):
		return
	var color := _c(palette["eye"])

	var shader_mat := mesh.material_override as ShaderMaterial
	if shader_mat == null and mesh.get_surface_override_material_count() > 0:
		shader_mat = mesh.get_surface_override_material(0) as ShaderMaterial
	if shader_mat == null:
		return
	shader_mat.set_shader_parameter("eye_color", color)

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
	# "eye" is deliberately absent. The eyes keep the material authored on the mesh in
	# skin.tscn, which is the camera-facing dot shader, so nothing here should claim them.
	var shader_targets: Array = data.get("shader_targets", ["body", "cheek"])
	var attachment_data: Dictionary = data.get("attachment", {})

	return {
		"body": _body_material(_c(palette.get("body", [1, 1, 1, 1])), outline_color, shader_type, shader_targets, "body"),
		"body_01": _body_material(_c(palette.get("body_alt", [1, 1, 1, 1])), outline_color, shader_type, shader_targets, "body"),
		"cheek": _body_material(_c(palette.get("cheek", [1, 1, 1, 1])), outline_color, shader_type, shader_targets, "cheek"),
		"crown": _crown_material(crown_color),
		"attachment": _attachment_material(_c(attachment_data.get("color", [1, 1, 1, 1]))),
	}

static func _material_for_name(material_set: Dictionary, name: String) -> Material:
	if name.begins_with("body"):
		return material_set.get("body_01" if name == "body_01" else "body")
	if name.begins_with("cheek"):
		return material_set.get("cheek")
	# No eye branch on purpose. Returning null makes apply_skin skip the node, so the eye
	# meshes keep the material authored on them in skin.tscn, which is the camera-facing
	# dot shader. Any material returned here would overwrite it with a flat colour.
	if name == "crown_L" or name == "crown_R":
		return material_set.get("cheek")
	if name.begins_with("crown"):
		return material_set.get("crown")
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
				var angel_outline := ShaderMaterial.new()
				angel_outline.shader = OUTLINE_SHADER
				angel_outline.set_shader_parameter("color", outline_color)
				angel_outline.set_shader_parameter("size", 1.04)
				angel_mat.next_pass = angel_outline
				return angel_mat

	var body_mat := StandardMaterial3D.new()
	body_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	body_mat.albedo_color = color
	body_mat.roughness = 0.85
	return body_mat

static func _crown_material(color: Color) -> Material:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.metallic = 0.8
	mat.roughness = 0.2
	return mat

static func _attachment_material(color: Color) -> Material:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.albedo_color = color
	mat.roughness = 0.85
	return mat

static func _c(v: Variant) -> Color:
	if typeof(v) == TYPE_STRING:
		return _c(_hex2rgba(v))
	var arr: Array = v if v is Array else [1, 1, 1, 1]
	var a: float = arr[3] if arr.size() > 3 else 1.0
	return Color(arr[0], arr[1], arr[2], a)
