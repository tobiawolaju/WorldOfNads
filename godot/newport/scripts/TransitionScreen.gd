extends CanvasLayer

const BACKDROP_COLOR := Color(0.43137255, 0.32941177, 1.0, 1.0) # #6e54ff
const FLASH_COLOR := Color(0.85882354, 0.0, 0.42745098, 1.0) # #db006d
const LOGO_TEXTURE := preload("res://assets/images/logo.png")

var backdrop: ColorRect
var flash: ColorRect
var logo: Sprite2D
var tween: Tween
var is_transitioning := false
var logo_base_scale := 1.0


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


func change_scene(target_scene: String) -> void:
	if is_transitioning:
		return

	is_transitioning = true
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

	# Phase 1: the logo drops in and the backdrop fills.
	tween.set_parallel(true)
	tween.tween_property(backdrop, "modulate:a", 0.96, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(logo, "modulate:a", 1.0, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(logo, "position:y", center_y, 0.55).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_property(logo, "scale", Vector2.ONE * logo_base_scale, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(logo, "rotation", 0.0, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)

	# A quick impact flash adds punch without a shader.
	tween.tween_callback(func():
		flash.modulate.a = 0.35
	)
	tween.tween_property(flash, "modulate:a", 0.0, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Switch scenes while the screen is fully covered.
	tween.tween_callback(func():
		get_tree().change_scene_to_file(target_scene)
	)

	# Phase 2: gravity carries the logo down and everything fades out.
	tween.tween_interval(0.12)
	tween.set_parallel(true)
	tween.tween_property(logo, "position:y", exit_y, 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(logo, "rotation", 0.28, 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(logo, "scale", Vector2.ONE * (logo_base_scale * 1.12), 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(logo, "modulate:a", 0.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(backdrop, "modulate:a", 0.0, 0.30).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.set_parallel(false)

	tween.tween_callback(func():
		is_transitioning = false
	)
