extends Label

@export var prefix: String = "FPS: "
@export var use_instant_fps: bool = true
@export_range(0.0, 2.0, 0.05) var update_interval: float = 0.25

var _update_timer: float = 0.0

func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer < update_interval:
		return
	_update_timer = 0.0
	var current_fps := _get_current_fps(delta)
	text = "%s%d" % [prefix, int(round(current_fps))]

func _get_current_fps(delta: float) -> float:
	if use_instant_fps:
		var frame_time := maxf(delta, 0.000001)
		return 1.0 / frame_time
	return float(Engine.get_frames_per_second())
