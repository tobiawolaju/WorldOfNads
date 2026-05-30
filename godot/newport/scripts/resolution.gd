extends Node
class_name Resolution

const MIN_SCALE: float = 0.05
const MAX_SCALE: float = 1.0

var current_scale: float = 1.0


func _ready() -> void:
	_apply_scale(current_scale)


func resolution(scale: float) -> void:
	set_scale(scale)


func set_scale(scale: float) -> void:
	current_scale = clampf(scale, MIN_SCALE, MAX_SCALE)
	_apply_scale(current_scale)


func get_scale() -> float:
	return current_scale


func _apply_scale(scale: float) -> void:
	var root_viewport: Viewport = get_tree().root
	if root_viewport == null:
		return
	root_viewport.scaling_3d_scale = scale
