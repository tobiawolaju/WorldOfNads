extends Node
class_name Resolution

const MIN_SCALE: float = 1.0
const MAX_SCALE: float = 1.0

var current_scale: float = 1.0
var auto_mode: bool = true
var _viewport_connected: bool = false


func _ready() -> void:
	_connect_viewport_signal()
	apply_dynamic_scale()


func resolution(scale: float) -> void:
	set_scale(scale)


func set_scale(scale: float) -> void:
	auto_mode = false
	current_scale = clampf(scale, MIN_SCALE, MAX_SCALE)
	_apply_scale(current_scale)


func apply_dynamic_scale() -> void:
	auto_mode = true
	current_scale = _compute_dynamic_scale()
	_apply_scale(current_scale)


func get_scale() -> float:
	return current_scale


func _connect_viewport_signal() -> void:
	if _viewport_connected:
		return
	var root_viewport: Viewport = get_tree().root
	if root_viewport == null:
		return
	if not root_viewport.size_changed.is_connected(_on_viewport_size_changed):
		root_viewport.size_changed.connect(_on_viewport_size_changed)
	_viewport_connected = true


func _on_viewport_size_changed() -> void:
	if auto_mode:
		current_scale = _compute_dynamic_scale()
		_apply_scale(current_scale)


func _compute_dynamic_scale() -> float:
	# Keep 3D rendering at full resolution to avoid softness from dynamic downscaling.
	return 1.0


func _apply_scale(scale: float) -> void:
	var root_viewport: Viewport = get_tree().root
	if root_viewport == null:
		return
	root_viewport.scaling_3d_scale = scale
