extends Node

# === REFERENCES ===
@export var minimap_camera: Camera3D
@export var minimap_viewport: SubViewport

@export var minimap_container: Control
@export var player_pointer: TextureRect

@export var player: Node3D

# === SETTINGS ===
@export var camera_height: float = 100.0
@export var follow_player: bool = true
@export var rotate_pointer: bool = true
@export var rotate_map: bool = false

func _ready() -> void:
	# Center the pointer automatically
	if player_pointer and minimap_container:
		player_pointer.anchor_left = 0.5
		player_pointer.anchor_right = 0.5
		player_pointer.anchor_top = 0.5
		player_pointer.anchor_bottom = 0.5

		player_pointer.position = minimap_container.size / 2


func _process(_delta: float) -> void:
	if !player:
		return

	# Follow player with minimap camera
	if minimap_camera and follow_player:
		var pos := player.global_position

		minimap_camera.global_position = Vector3(
			pos.x,
			pos.y + camera_height,
			pos.z
		)

		minimap_camera.rotation_degrees = Vector3(-90, 0, 0)

	# Rotate player pointer
	if player_pointer and rotate_pointer:
		player_pointer.rotation = -player.rotation.y

	# Optional rotating minimap
	if minimap_container and rotate_map:
		minimap_container.rotation = player.rotation.y
