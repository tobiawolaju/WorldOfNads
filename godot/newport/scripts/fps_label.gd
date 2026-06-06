extends Label

@export var prefix: String = "FPS: "
@export var use_instant_fps: bool = true
@export var target_minimum_fps: float = 100.0
@export var minimum_resolution_scale: float = 0.6
@export var maximum_resolution_scale: float = 1.0
@export var auto_adjust_resolution: bool = true

var _last_resolution_scale: float = -1.0


func _process(delta: float) -> void:
	var current_fps := _get_current_fps(delta)
	text = "%s%d" % [prefix, int(round(current_fps))]

	if auto_adjust_resolution and target_minimum_fps > 0.0:
		var resolution_scale := clampf(
			current_fps / target_minimum_fps,
			minimum_resolution_scale,
			maximum_resolution_scale
		)
		if not is_equal_approx(resolution_scale, _last_resolution_scale):
			_last_resolution_scale = resolution_scale
			resolution.set_resolution(resolution_scale)


func _get_current_fps(delta: float) -> float:
	if use_instant_fps:
		var frame_time := maxf(delta, 0.000001)
		return 1.0 / frame_time
	return float(Engine.get_frames_per_second())
