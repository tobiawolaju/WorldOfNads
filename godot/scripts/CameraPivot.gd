# CameraPivot.gd (Formerly CameraArm.gd)
# A robust, decoupled third-person camera controller.

extends Node3D

@export var target_node: Node3D = null

@export var camera_smoothness: float = 15.0
@export var min_pitch: float = deg_to_rad(-40.0)
@export var max_pitch: float = deg_to_rad(60.0)

# The SpringArm is now the only thing controlling distance.
@onready var spring_arm: SpringArm3D = $SpringArm3D

# These variables hold the RAW, unsmoothed rotation from player input.
var cam_rot_x: float = deg_to_rad(30)
var cam_rot_y: float = 0.0

func _ready():
	set_as_top_level(true)

func _input(event: InputEvent) -> void:
	# Handle camera rotation input
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		cam_rot_y -= event.relative.x * 0.005
		cam_rot_x = clamp(cam_rot_x + event.relative.y * 0.005, min_pitch, max_pitch)

	# Handle camera zoom input by changing the SpringArm's length
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			spring_arm.spring_length = clamp(spring_arm.spring_length - 0.5, 2.0, 5.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			spring_arm.spring_length = clamp(spring_arm.spring_length + 0.5, 2.0, 5.0)

func _process(delta: float) -> void:
	if not is_instance_valid(target_node):
		return

	# 1. Update the pivot's rotation based on raw input.
	self.rotation.y = cam_rot_y
	self.rotation.x = cam_rot_x
	
	# --- FIX: THE CONFLICTING LINE HAS BEEN REMOVED ---
	# We no longer manually set the camera's position. The SpringArm handles it.
	# REMOVED: camera.position.z = camera_distance
	
	# 2. Smoothly move the entire pivot towards the target's position.
	var target_pos = target_node.global_position + Vector3(0, 1.5, 0)
	self.global_position = self.global_position.lerp(target_pos, delta * camera_smoothness)

# This
