extends Node3D
# Skin test preview — scene: res://scenes/preview.tscn
#
# Type a skin id (e.g. 0002), press Enter or Apply:
#   * fetches GET /api/skins first so live Firebase skins resolve
#     (falls back to the local defaults when offline)
#   * SkinApplier.apply_skin() dresses the nad exactly like the game does
#   * the readout shows the resolved shader (odd id = shaded, even id =
#     unshaded), where the data came from, and the attachments being worn
#
# Run from the editor (open preview.tscn, F6) or:
#   Godot --path godot res://scenes/preview.tscn

const SKIN_SCENE: PackedScene = preload("res://scenes/skin.tscn")
const API_BASE: String = "https://worldofnads.onrender.com"
const FONT: Font = preload("res://assets/fonts/font1.ttf")

var applier := SkinApplier.new()
var nad: Node3D
var edit: LineEdit
var info_label: Label
var status_label: Label
var current_id: String = "s-default"


func _ready() -> void:
	_build_world()
	nad = SKIN_SCENE.instantiate()
	add_child(nad)
	_build_ui()
	_fetch_index()
	_fetch_skins()
	apply(current_id)


# ---------------------------------------------------------------- environment

func _build_world() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -30.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.07, 0.05, 0.12)
	sky_mat.sky_horizon_color = Color(0.28, 0.12, 0.3)
	sky_mat.ground_bottom_color = Color(0.05, 0.04, 0.08)
	sky_mat.ground_horizon_color = Color(0.2, 0.1, 0.22)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.4
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# player.gd (skin.tscn root) finds this camera and drives it with the
	# game's own third-person rig — same framing as the dashboard preview.
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.position = Vector3(0.0, 1.5, 3.0)
	add_child(cam)


# ----------------------------------------------------------------------- UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var box := VBoxContainer.new()
	box.position = Vector2(16.0, 16.0)
	box.add_theme_constant_override("separation", 8)
	layer.add_child(box)

	box.add_child(_label("SKIN PREVIEW", 22, Color(1, 1, 1)))
	box.add_child(_label("odd id = shaded, even id = unshaded; missing/empty attachments = bare nad", 12, Color(0.72, 0.72, 0.78)))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)

	edit = LineEdit.new()
	edit.custom_minimum_size = Vector2(260.0, 0.0)
	edit.placeholder_text = "skin id, e.g. 0002"
	edit.text = current_id
	edit.add_theme_font_override("font", FONT)
	edit.text_submitted.connect(_on_submit)
	row.add_child(edit)

	var apply_btn := Button.new()
	apply_btn.text = "Apply"
	apply_btn.pressed.connect(func() -> void: apply(edit.text))
	row.add_child(apply_btn)

	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 6)
	box.add_child(presets)
	for preset_id: String in ["s-default", "s-default-unshaded", "0001", "0002", "0003", "0004"]:
		var b := Button.new()
		b.text = preset_id
		b.pressed.connect(func() -> void: apply(preset_id))
		presets.add_child(b)

	info_label = _label("", 15, Color(1, 0.82, 0.95))
	box.add_child(info_label)
	status_label = _label("API: connecting…", 13, Color(0.65, 0.65, 0.72))
	box.add_child(status_label)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _on_submit(text: String) -> void:
	apply(text)


# ------------------------------------------------------------------- apply

func apply(id: String) -> void:
	var key := id.strip_edges()
	if key.is_empty():
		return
	current_id = key
	applier.apply_skin(nad, key)

	var data := SkinApplier.get_skin_data(key)

	var source := "local fallback"
	if SkinApplier._api_cache.has(key):
		source = "API (GET /api/skins)"
	elif SkinApplier._index_cache.has(key):
		source = "index (GET /api/skin-combos)"
	elif key == SkinApplier.DEFAULT_SKIN or key == "s-default-unshaded":
		source = "local default"

	var numeric := key.is_valid_int()
	var shader := str(data.get("shader", "default"))
	var parity_note := ""
	if numeric:
		var parity := "odd" if int(key) % 2 != 0 else "even"
		parity_note = "   <- parity: %s id -> %s" % [parity, shader]

	var attachments: Variant = data.get("attachments", [])
	var worn := "nothing"
	if attachments is Array and not attachments.is_empty():
		var names := PackedStringArray()
		for a: Variant in attachments:
			names.append(str(a))
		worn = ", ".join(names)
	elif attachments is Array:
		worn = "nothing (empty list)"
	else:
		worn = "nothing (no attachments key)"

	info_label.text = "id: %s\nsource: %s\nshader: %s%s\nattachments: %s" % [
		key, source, shader, parity_note, worn
	]
	edit.text = key


# ---------------------------------------------------------------- API seed

func _fetch_skins() -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_skins_fetched.bind(http))
	var err := http.request("%s/api/skins" % API_BASE)
	if err != OK:
		http.queue_free()
		status_label.text = "API: request could not start (%d) — local fallback data" % err


func _on_skins_fetched(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	if http != null and is_instance_valid(http):
		http.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		status_label.text = "API: offline (result %d, http %d) — local fallback data" % [result, response_code]
		return

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary) or parsed.get("ok") != true or not (parsed.get("skins") is Array):
		status_label.text = "API: unexpected response — local fallback data"
		return

	var skins: Array = parsed.get("skins")
	SkinApplier.seed_from_api(skins)
	status_label.text = "API: %d live skins loaded" % skins.size()
	apply(current_id)


func _fetch_index() -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_index_fetched.bind(http))
	http.request("%s/api/skin-combos" % API_BASE)


func _on_index_fetched(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	if http != null and is_instance_valid(http):
		http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary) or parsed.get("ok") != true:
		return
	SkinApplier.seed_index_from_api(parsed)
	var combos: Variant = parsed.get("combos", [])
	if combos is Array:
		status_label.text = "API: index loaded (%d combos -> ids 1..%d)" % [combos.size(), combos.size() * 2]
	apply(current_id)
