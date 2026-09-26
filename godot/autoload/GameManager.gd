extends Node

## GameManager Autoload
## Provides global access to game-wide settings and controls.

const PIXEL_BUDGET_DESKTOP := 200_000
const PIXEL_BUDGET_MOBILE := 200_000
const SCALE_STEPS: Array[float] = [1.0, 0.9, 0.8, 0.7, 0.6, 0.5, 0.45, 0.4, 0.35]
const RESIZE_DEBOUNCE_SEC := 0.3

var _resize_debounce := 0.0

## Minimap snapshot stored after loading
var minimap_texture: Texture2D = null
var minimap_world_size: Vector2 = Vector2(70, 70) # Default for 35x35 grid with 2.0 chunk size
var minimap_origin: Vector2 = Vector2.ZERO

func _ready() -> void:
	# Ensure time_scale is reset to 1.0 when starting
	Engine.time_scale = 1.0
	# Force a responsive frame loop for the live 3D game (low_processor_mode is
	# a battery-saver meant for static UI and throttles the frame rate hard).
	#Engine.low_processor_mode = false
	Engine.max_fps = 30

	get_tree().root.size_changed.connect(_on_root_size_changed)
	_apply_3d_scale(_compute_3d_scale())

func _process(delta: float) -> void:
	if _resize_debounce <= 0.0:
		return
	_resize_debounce -= delta
	if _resize_debounce <= 0.0:
		_apply_3d_scale(_compute_3d_scale())

func _on_root_size_changed() -> void:
	_resize_debounce = RESIZE_DEBOUNCE_SEC

func _is_mobile() -> bool:
	return (
		OS.has_feature("mobile")
		or OS.has_feature("web_android")
		or OS.has_feature("web_ios")
	)

func _compute_3d_scale() -> float:
	var window_size := get_tree().root.size
	var pixels := float(window_size.x) * float(window_size.y)
	if pixels <= 0.0:
		return 1.0
	var budget := float(PIXEL_BUDGET_MOBILE if _is_mobile() else PIXEL_BUDGET_DESKTOP)
	for step in SCALE_STEPS:
		if pixels * step * step <= budget:
			return step
	return SCALE_STEPS[SCALE_STEPS.size() - 1]

func _apply_3d_scale(scale: float) -> void:
	get_tree().root.scaling_3d_scale = scale

## Sets the game speed (time scale).
## 1.0 = Normal speed
## 0.5 = Half speed
## 2.0 = Double speed
func set_speed(value: float) -> void:
	Engine.time_scale = value
	print("Game speed set to: ", value)

## Returns the current game speed.
func get_speed() -> float:
	return Engine.time_scale
