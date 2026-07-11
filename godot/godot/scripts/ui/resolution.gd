extends Node
class_name Resolution

@export var enabled: bool = true
@export var default_scale: float = 0.6
@export var min_scale: float = 0.1
@export var max_scale: float = 2.0
@export var reference_window_size: Vector2i = Vector2i(500, 500)
@export var good_target_fps: float = 45.0
@export var medium_target_fps: float = 30.0
@export var performance_target_fps: float = 25.0
@export var good_min_scale: float = 0.88
@export var good_max_scale: float = 1.00
@export var medium_min_scale: float = 0.68
@export var medium_max_scale: float = 0.85
@export var performance_min_scale: float = 0.50
@export var performance_max_scale: float = 0.65

var current_scale: float = 1.0

# --- DYNAMIC FPS MONITORING ---
var _fps_samples: Array[float] = []
var _fps_sample_count: int = 0
const SAMPLE_WINDOW: int = 30
const ADJUST_INTERVAL: int = 60
var _frame_counter: int = 0
var _avg_fps: float = 60.0

enum QualityPreset {
	PERFORMANCE,
	MEDIUM,
	GOOD,
}


func _ready() -> void:
	if not enabled:
		return
	_fps_samples.resize(SAMPLE_WINDOW)
	# Lower default on mobile
	if OS.has_feature("mobile") or OS.has_feature("web"):
		default_scale = minf(default_scale, 0.6)
	set_resolution(default_scale)


func _process(delta: float) -> void:
	if not enabled:
		return
	# Rolling FPS average
	var instant_fps := 1.0 / maxf(delta, 0.000001)
	_fps_samples[_sample_count] = instant_fps
	_sample_count = (_sample_count + 1) % SAMPLE_WINDOW
	_fps_sample_count = mini(_fps_sample_count + 1, SAMPLE_WINDOW)

	# Adjust every 60 frames (~1s at 60fps)
	_frame_counter += 1
	if _frame_counter >= ADJUST_INTERVAL:
		_frame_counter = 0
		# Compute average
		var total: float = 0.0
		for i in _fps_sample_count:
			total += _fps_samples[i]
		_avg_fps = total / float(maxf(_fps_sample_count, 1))
		apply_calibrated_quality(_avg_fps)


func resolution(scale: float) -> void:
	if not enabled:
		return
	set_resolution(scale)


func set_resolution(scale: float) -> void:
	if not enabled:
		return
	var clamped_scale := clampf(scale, min_scale, max_scale)
	if is_equal_approx(clamped_scale, current_scale):
		return
	current_scale = clamped_scale
	_apply_scale(current_scale)


func get_scale() -> float:
	return current_scale


func choose_quality_preset(average_fps: float, window_size: Vector2i = Vector2i.ZERO) -> QualityPreset:
	var adjusted_fps := _adjusted_fps_for_window_size(average_fps, window_size)

	if adjusted_fps >= good_target_fps:
		return QualityPreset.GOOD
	if adjusted_fps >= medium_target_fps:
		return QualityPreset.MEDIUM
	return QualityPreset.PERFORMANCE


func apply_quality_preset(preset: QualityPreset, average_fps: float, min_scale_override: float = -1.0, max_scale_override: float = -1.0) -> void:
	var target_fps := _get_preset_target_fps(preset)
	var min_allowed_scale := maxf(_get_preset_min_scale(preset), min_scale)
	var max_allowed_scale := minf(_get_preset_max_scale(preset), max_scale)

	if min_scale_override >= 0.0:
		min_allowed_scale = maxf(min_allowed_scale, min_scale_override)
	if max_scale_override >= 0.0:
		max_allowed_scale = minf(max_allowed_scale, max_scale_override)
	if max_allowed_scale < min_allowed_scale:
		max_allowed_scale = min_allowed_scale

	var next_scale := clampf(average_fps / maxf(target_fps, 0.001), min_allowed_scale, max_allowed_scale)
	next_scale = minf(next_scale, 1.0)
	set_resolution(next_scale)


func apply_calibrated_quality(average_fps: float, window_size: Vector2i = Vector2i.ZERO, min_scale_override: float = -1.0, max_scale_override: float = -1.0) -> QualityPreset:
	var preset := choose_quality_preset(average_fps, window_size)
	apply_quality_preset(preset, average_fps, min_scale_override, max_scale_override)
	return preset


func _apply_scale(scale: float) -> void:
	var root_viewport: Viewport = get_tree().root
	if root_viewport == null:
		return
	root_viewport.scaling_3d_scale = scale
	root_viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR


func _adjusted_fps_for_window_size(average_fps: float, window_size: Vector2i) -> float:
	var effective_window_size := window_size
	if effective_window_size == Vector2i.ZERO:
		effective_window_size = _get_window_size()

	var current_area := float(maxf(effective_window_size.x, 1.0) * maxf(effective_window_size.y, 1.0))
	var reference_area := float(maxf(reference_window_size.x, 1) * maxf(reference_window_size.y, 1))
	var screen_load := sqrt(current_area / reference_area)
	return average_fps / maxf(screen_load, 1.0)


func _get_preset_target_fps(preset: QualityPreset) -> float:
	match preset:
		QualityPreset.GOOD:
			return good_target_fps
		QualityPreset.MEDIUM:
			return medium_target_fps
		_:
			return performance_target_fps


func _get_preset_min_scale(preset: QualityPreset) -> float:
	match preset:
		QualityPreset.GOOD:
			return good_min_scale
		QualityPreset.MEDIUM:
			return medium_min_scale
		_:
			return performance_min_scale


func _get_preset_max_scale(preset: QualityPreset) -> float:
	match preset:
		QualityPreset.GOOD:
			return good_max_scale
		QualityPreset.MEDIUM:
			return medium_max_scale
		_:
			return performance_max_scale


func _get_window_size() -> Vector2i:
	var root_viewport: Viewport = get_tree().root
	if root_viewport != null:
		return Vector2i(root_viewport.get_visible_rect().size)
	return Vector2i.ZERO


# --- VAR DECLARATIONS FOR PROCESS LOOP ---
var _sample_count: int = 0
