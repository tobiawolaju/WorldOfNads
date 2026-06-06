extends Node
class_name Resolution

@export var default_scale: float = 1.0
@export var min_scale: float = 0.1
@export var max_scale: float = 2.0

var current_scale: float = 1.0


func _ready() -> void:
	set_resolution(default_scale)


func resolution(scale: float) -> void:
	set_resolution(scale)


func set_resolution(scale: float) -> void:
	current_scale = clampf(scale, min_scale, max_scale)
	_apply_scale(current_scale)


func get_scale() -> float:
	return current_scale


func _apply_scale(scale: float) -> void:
	var root_viewport: Viewport = get_tree().root
	if root_viewport == null:
		return
	root_viewport.scaling_3d_scale = scale
