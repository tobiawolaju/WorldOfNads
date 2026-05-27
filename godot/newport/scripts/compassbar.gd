extends TextureRect

@export var camera: Camera3D

@export_group("Compass")
@export var px_per_degree: float = 4.0
@export var bar_height: float = 48.0
@export var tick_spacing_deg: float = 5.0
@export var label_offset_y: float = 10.0
@export var label_font_size: int = 18
@export var fade_width: float = 96.0
@export var pointer_width: float = 14.0
@export var pointer_height: float = 10.0

@export_group("Colors")
@export var background_color: Color = Color(0.05, 0.05, 0.05, 0.55)
@export var fade_color: Color = Color(0.0, 0.0, 0.0, 0.35)
@export var minor_tick_color: Color = Color(1.0, 1.0, 1.0, 0.45)
@export var medium_tick_color: Color = Color(1.0, 1.0, 1.0, 0.70)
@export var cardinal_tick_color: Color = Color(1.0, 1.0, 1.0, 1.00)
@export var label_color: Color = Color(0.96, 0.96, 0.96, 0.95)
@export var north_label_color: Color = Color(1.0, 0.45, 0.20, 1.0)
@export var pointer_color: Color = Color(1.0, 1.0, 1.0, 0.95)

var _font: Font
var _current_angle: float = 0.0
var _last_drawn_angle: float = 99999.0
var _control_size: Vector2 = Vector2.ZERO
var _half_visible_degrees: float = 0.0
var _label_width: float = 0.0
var _fade_rect_width: float = 0.0
var _tick_small_height: float = 0.0
var _tick_medium_height: float = 0.0
var _tick_tall_height: float = 0.0
var _tick_center_x: float = 0.0
var _bar_top_y: float = 0.0
var _bar_bottom_y: float = 0.0
var _label_y: float = 0.0
var _pointer_tip_y: float = 0.0
var _pointer_base_y: float = 0.0


func _ready() -> void:
	texture = null
	_font = ThemeDB.fallback_font
	_rebuild_cached_metrics()
	_current_angle = _get_camera_heading_degrees()
	_last_drawn_angle = _current_angle + 1.0


func _process(_delta: float) -> void:
	if camera == null:
		camera = get_viewport().get_camera_3d()
	if camera == null:
		return

	var new_angle: float = _get_camera_heading_degrees()
	if absf(angle_difference(deg_to_rad(_last_drawn_angle), deg_to_rad(new_angle))) > deg_to_rad(0.5):
		_current_angle = new_angle
		_last_drawn_angle = new_angle
		queue_redraw()


func _draw() -> void:
	_rebuild_cached_metrics()

	draw_rect(Rect2(Vector2.ZERO, _control_size), background_color, true)

	var left_fade_rect := Rect2(Vector2.ZERO, Vector2(_fade_rect_width, _control_size.y))
	var right_fade_rect := Rect2(Vector2(_control_size.x - _fade_rect_width, 0.0), Vector2(_fade_rect_width, _control_size.y))
	draw_rect(left_fade_rect, fade_color, true)
	draw_rect(right_fade_rect, fade_color, true)

	var start_deg: float = _current_angle - _half_visible_degrees
	var end_deg: float = _current_angle + _half_visible_degrees
	var tick_deg: float = floor(start_deg / tick_spacing_deg) * tick_spacing_deg
	var tick_color: Color
	var tick_height: float
	var tick_x: float
	var label_text: String
	var label_color_to_use: Color

	while tick_deg <= end_deg:
		tick_x = _tick_center_x + ((tick_deg - _current_angle) * px_per_degree)
		if tick_x >= -_fade_rect_width and tick_x <= (_control_size.x + _fade_rect_width):
			tick_color = minor_tick_color
			tick_height = _tick_small_height
			if _is_cardinal_tick(tick_deg):
				tick_color = cardinal_tick_color
				tick_height = _tick_tall_height
			elif _is_major_tick(tick_deg):
				tick_color = medium_tick_color
				tick_height = _tick_medium_height

			draw_line(
				Vector2(tick_x, _bar_bottom_y),
				Vector2(tick_x, _bar_bottom_y - tick_height),
				tick_color,
				2.0
			)

			if _is_label_tick(tick_deg):
				label_text = _get_cardinal_label(tick_deg)
				label_color_to_use = north_label_color if label_text == "N" else label_color
				draw_string(
					_font,
					Vector2(tick_x - _label_width * 0.5, _label_y),
					label_text,
					HORIZONTAL_ALIGNMENT_CENTER,
					_label_width,
					label_font_size,
					label_color_to_use
				)
		tick_deg += tick_spacing_deg

	draw_line(
		Vector2(_tick_center_x, _pointer_base_y),
		Vector2(_tick_center_x - pointer_width * 0.5, _pointer_tip_y),
		pointer_color,
		2.5
	)
	draw_line(
		Vector2(_tick_center_x - pointer_width * 0.5, _pointer_tip_y),
		Vector2(_tick_center_x + pointer_width * 0.5, _pointer_tip_y),
		pointer_color,
		2.5
	)
	draw_line(
		Vector2(_tick_center_x + pointer_width * 0.5, _pointer_tip_y),
		Vector2(_tick_center_x, _pointer_base_y),
		pointer_color,
		2.5
	)


func _rebuild_cached_metrics() -> void:
	_control_size = size
	if _control_size.x <= 0.0 or _control_size.y <= 0.0:
		return

	_half_visible_degrees = (_control_size.x * 0.5) / maxf(px_per_degree, 0.001)
	_label_width = maxf(48.0, label_font_size * 3.5)
	_fade_rect_width = minf(fade_width, _control_size.x * 0.5)
	_tick_small_height = maxf(8.0, _control_size.y * 0.22)
	_tick_medium_height = maxf(14.0, _control_size.y * 0.42)
	_tick_tall_height = maxf(20.0, _control_size.y * 0.68)
	_tick_center_x = _control_size.x * 0.5
	_bar_bottom_y = _control_size.y - 4.0
	_bar_top_y = maxf(0.0, _bar_bottom_y - bar_height)
	_label_y = maxf(0.0, _bar_top_y - label_offset_y - float(label_font_size))
	_pointer_tip_y = _control_size.y - 2.0
	_pointer_base_y = _pointer_tip_y - pointer_height


func _get_camera_heading_degrees() -> float:
	var active_camera: Camera3D = camera
	if active_camera == null:
		active_camera = get_viewport().get_camera_3d()
	if active_camera == null:
		return 0.0
	return wrapf(rad_to_deg(active_camera.global_rotation.y), 0.0, 360.0)


func _is_major_tick(deg_value: float) -> bool:
	var wrapped_value: float = fposmod(deg_value, 45.0)
	return is_zero_approx(wrapped_value)


func _is_cardinal_tick(deg_value: float) -> bool:
	var wrapped_value: float = fposmod(deg_value, 90.0)
	return is_zero_approx(wrapped_value)


func _is_label_tick(deg_value: float) -> bool:
	var wrapped_value: float = fposmod(deg_value, 45.0)
	return is_zero_approx(wrapped_value)


func _get_cardinal_label(deg_value: float) -> String:
	var wrapped_deg: float = wrapf(deg_value, 0.0, 360.0)
	var index: int = int(round(wrapped_deg / 45.0)) % 8
	match index:
		0:
			return "N"
		1:
			return "NE"
		2:
			return "E"
		3:
			return "SE"
		4:
			return "S"
		5:
			return "SW"
		6:
			return "W"
		_:
			return "NW"
