extends Node

# --- Owned nodes (children Game creates itself, not separate autoloads) ---
var transition_layer: SceneTransition

# --- Former GameManager state ---
var minimap_texture: ImageTexture
var minimap_world_size: Vector2
var minimap_origin: Vector2

func _ready() -> void:
	transition_layer = SceneTransition.new()
	add_child(transition_layer)
