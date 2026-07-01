@tool # Allows the radius changes to update visually inside the editor inspector
extends Node3D

@export_category("Nodes")
@export var world_env: WorldEnvironment
@export var light_normal: DirectionalLight3D
@export var light_storm: DirectionalLight3D
@export var camera: Camera3D
@export var zone_mesh: MeshInstance3D # Your Cylinder MeshInstance3D

@export_category("Resources")
@export var normal_env: Environment
@export var storm_env: Environment

@export_category("Zone Settings")
@export var cylinder_radius: float = 10.0:
	set(value):
		cylinder_radius = value
		update_mesh_scale()

@export var check_interval: float = 0.1

# Track player state to avoid running logic every frame
var is_player_outside: bool = false
var _check_accumulator: float = 0.0

func _ready() -> void:
	# Always set visual scale at launch
	update_mesh_scale()
	
	# Do not run game/player tracking logic inside the editor
	if Engine.is_editor_hint():
		return
		
	# Set up the initial "Inside Safe Zone" state safely
	if world_env and normal_env:
		world_env.environment = normal_env
	
	if light_normal:
		light_normal.visible = true
		
	if light_storm:
		light_storm.visible = false

func _process(_delta: float) -> void:
	# Prevent the distance checking math from running in the editor
	if Engine.is_editor_hint():
		return

	_check_accumulator += _delta
	if _check_accumulator < check_interval:
		return
	_check_accumulator = 0.0

	# Safety check to prevent errors if references are missing
	if not camera or not world_env or not light_normal or not light_storm:
		return

	# Calculate distance on a flat 2D plane (X and Z), ignoring height (Y)
	var camera_pos_2d = Vector2(camera.global_position.x, camera.global_position.z)
	var cylinder_pos_2d = Vector2(global_position.x, global_position.z)
	var current_distance = camera_pos_2d.distance_to(cylinder_pos_2d)

	# Check boundary crossing
	if current_distance > cylinder_radius:
		if not is_player_outside:
			enter_storm()
	else:
		if is_player_outside:
			enter_safe_zone()

func update_mesh_scale() -> void:
	if zone_mesh:
		# Scale X and Z based on radius. Keep Y (height) at its original scale.
		zone_mesh.scale = Vector3(cylinder_radius, zone_mesh.scale.y, cylinder_radius)

func enter_storm() -> void:
	is_player_outside = true
	
	# Swap environment and flip lights instantly
	world_env.environment = storm_env
	light_normal.visible = false
	light_storm.visible = true
	print("Player entered the Storm Zone!")

func enter_safe_zone() -> void:
	is_player_outside = false
	
	# Swap environment and flip lights instantly
	world_env.environment = normal_env
	light_normal.visible = true
	light_storm.visible = false
	print("Player returned to the Safe Zone!")
