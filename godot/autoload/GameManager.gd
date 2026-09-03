extends Node

## GameManager Autoload
## Provides global access to game-wide settings and controls.

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
	Engine.max_fps = 24
	
	# On web (Android Chrome etc.) render 3D at a fraction of the window
	# resolution; the browser upscales. Massive fill-rate win on low-end GPUs.
	if OS.has_feature("web"):
		get_viewport().scaling_3d_scale = 0.7
	get_viewport().scaling_3d_scale = 1.0

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
