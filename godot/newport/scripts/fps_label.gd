extends Label

@export var prefix: String = "FPS: "
@export var use_instant_fps: bool = true
@export var target_minimum_fps: float = 45
@export var fps_margin: float = 5.0
@export var minimum_resolution_scale: float = 0.5
@export var maximum_resolution_scale: float = 2.0
@export var scale_update_interval: float = 0.5
@export var fps_smoothing: float = 0.2
@export var downscale_step: float = 0.12
@export var upscale_step: float = 0.06
@export var auto_adjust_resolution: bool = true

var _smoothed_fps: float = 0.0
var _update_timer: float = 0.0


func _process(delta: float) -> void:
	var current_fps := _get_current_fps(delta)
	text = "%s%d" % [prefix, int(round(current_fps))]

	if not auto_adjust_resolution or target_minimum_fps <= 0.0:
		return

	if _smoothed_fps <= 0.0:
		_smoothed_fps = current_fps
	else:
		_smoothed_fps = lerpf(_smoothed_fps, current_fps, clampf(fps_smoothing, 0.01, 1.0))

	_update_timer += delta
	if _update_timer < scale_update_interval:
		return
	_update_timer = 0.0

	var lower_bound := target_minimum_fps - fps_margin
	var upper_bound := target_minimum_fps + fps_margin
	var current_scale := resolution.get_scale()
	var next_scale := current_scale

	if _smoothed_fps < lower_bound:
		var severity := clampf((lower_bound - _smoothed_fps) / maxf(target_minimum_fps, 0.001), 0.0, 1.0)
		next_scale = current_scale * (1.0 - downscale_step * severity)
	elif _smoothed_fps > upper_bound:
		var severity := clampf((_smoothed_fps - upper_bound) / maxf(target_minimum_fps, 0.001), 0.0, 1.0)
		next_scale = current_scale * (1.0 + upscale_step * severity)
	else:
		return

	next_scale = clampf(next_scale, minimum_resolution_scale, maximum_resolution_scale)
	if not is_equal_approx(next_scale, current_scale):
		resolution.set_resolution(next_scale)


func _get_current_fps(delta: float) -> float:
	if use_instant_fps:
		var frame_time := maxf(delta, 0.000001)
		return 1.0 / frame_time
	return float(Engine.get_frames_per_second())
