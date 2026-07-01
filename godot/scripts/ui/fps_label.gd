extends Label

@export var prefix: String = "FPS: "
@export var use_instant_fps: bool = true

func _process(delta: float) -> void:
	var current_fps := _get_current_fps(delta)
	text = "%s%d" % [prefix, int(round(current_fps))]

func _get_current_fps(delta: float) -> float:
	if use_instant_fps:
		var frame_time := maxf(delta, 0.000001)
		return 1.0 / frame_time
	return float(Engine.get_frames_per_second())
