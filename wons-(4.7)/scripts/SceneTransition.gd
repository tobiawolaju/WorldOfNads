class_name SceneTransition
extends CanvasLayer

const BACKDROP_COLOR := Color(0.43137255, 0.32941177, 1.0, 1.0) # #6e54ff
const FLASH_COLOR := Color(0.85882354, 0.0, 0.42745098, 1.0) # #db006d
const LOGO_TEXTURE := preload("res://assets/img/logo.png")

var backdrop: ColorRect
var flash: ColorRect
var logo: Sprite2D
var tween: Tween
var is_transitioning := false
var logo_base_scale := 1.0
var _pending_scene := ""
var _pending_payload := {}

func _ready() -> void:
	layer = 100
	_build_nodes()
	_layout_nodes()

func _build_nodes() -> void:
	backdrop = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.color = BACKDROP_COLOR
	backdrop.modulate.a = 0.0
	add_child(backdrop)
	flash = ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.color = FLASH_COLOR
	flash.modulate.a = 0.0
	add_child(flash)
	logo = Sprite2D.new()
	logo.texture = LOGO_TEXTURE
	logo.centered = true
	logo.modulate = Color(1.0, 1.0, 1.0, 0.0)
	logo.z_index = 1
	add_child(logo)

func _layout_nodes() -> void:
	if logo == null or logo.texture == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var texture_size := logo.texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		logo_base_scale = 1.0
	else:
		var fit_scale := minf(viewport_size.x / texture_size.x, viewport_size.y / texture_size.y)
		logo_base_scale = fit_scale * 0.82
	var start_y := -texture_size.y * logo_base_scale * 0.85
	logo.position = Vector2(viewport_size.x * 0.5, start_y)
	logo.scale = Vector2.ONE * maxf(0.05, logo_base_scale * 0.72)
	logo.rotation = -0.18

## Fades out, swaps in `target_scene` and fades back in. `payload` is an optional
## dictionary of exported properties to write on the incoming scene *before* its
## _ready() runs, which is how a screen hands the next one what it needs (the
## dashboard passes the queued match and the chosen skin to the lobby) instead of
## leaving the values somewhere global for the next scene to go and look for.
func change_scene(target_scene: String, payload: Dictionary = {}) -> void:
	if is_transitioning:
		return
	is_transitioning = true
	_pending_scene = target_scene
	_pending_payload = payload
	_layout_nodes()
	backdrop.modulate.a = 0.0
	flash.modulate.a = 0.0
	logo.modulate.a = 0.0
	if tween:
		tween.kill()
	tween = create_tween()
	tween.set_parallel(false)

	var viewport_size := get_viewport().get_visible_rect().size
	var center_y := viewport_size.y * 0.5
	var exit_y := viewport_size.y + (logo.texture.get_size().y * logo_base_scale)

	tween.set_parallel(true)
	tween.tween_property(backdrop, "modulate:a", 0.96, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(logo, "modulate:a", 1.0, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(logo, "position:y", center_y, 0.55).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_property(logo, "scale", Vector2.ONE * logo_base_scale, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(logo, "rotation", 0.0, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)

	tween.tween_callback(_on_flash_impact)
	tween.tween_property(flash, "modulate:a", 0.0, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_on_swap_scene)

	tween.tween_interval(0.12)
	tween.set_parallel(true)
	tween.tween_property(logo, "position:y", exit_y, 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(logo, "rotation", 0.28, 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(logo, "scale", Vector2.ONE * (logo_base_scale * 1.12), 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(logo, "modulate:a", 0.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(backdrop, "modulate:a", 0.0, 0.30).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.set_parallel(false)
	tween.tween_callback(_on_transition_finished)

func _on_flash_impact() -> void:
	flash.modulate.a = 0.35

func _on_swap_scene() -> void:
	if _pending_payload.is_empty():
		get_tree().change_scene_to_file(_pending_scene)
		return
	# A payload has to land before _ready(), and change_scene_to_file() instantiates
	# the scene itself, so the swap is done by hand here instead.
	var packed: PackedScene = load(_pending_scene)
	if packed == null:
		push_warning("SceneTransition: could not load %s, changing scene without its payload." % _pending_scene)
		get_tree().change_scene_to_file(_pending_scene)
		return
	_swap_in.call_deferred(packed.instantiate(), _pending_payload)

func _swap_in(instance: Node, payload: Dictionary) -> void:
	for key in payload:
		# A key is either "property" for the scene root or "Node/Path/property" for a
		# child -- the gameplay scene drives itself from a PlayerManager node rather
		# than from its root, so a bare name is not always enough.
		var address := str(key)
		var target := instance
		var property := address
		var slash := address.rfind("/")
		if slash != -1:
			target = instance.get_node_or_null(NodePath(address.substr(0, slash)))
			property = address.substr(slash + 1)
		if target == null or not _has_property(target, property):
			push_warning("SceneTransition: %s cannot receive '%s'." % [_pending_scene, address])
			continue
		target.set(property, payload[key])
	var previous := get_tree().current_scene
	get_tree().root.add_child(instance)
	get_tree().current_scene = instance
	if previous != null and previous != instance:
		previous.queue_free()

func _has_property(node: Object, property: String) -> bool:
	for info in node.get_property_list():
		if str(info.get("name", "")) == property:
			return true
	return false

func _on_transition_finished() -> void:
	is_transitioning = false
