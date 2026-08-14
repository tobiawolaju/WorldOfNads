@tool
extends Node3D

@export_category("Nodes")
@export var world_env: WorldEnvironment
@export var light_normal: DirectionalLight3D
@export var light_storm: DirectionalLight3D
@export var camera: Camera3D
@export var cylinder_wall: MeshInstance3D
@export var cylinder_border: MeshInstance3D

@export_category("Resources")
@export var normal_env: Environment
@export var storm_env: Environment

@export_category("Zone Settings")
@export var cylinder_radius: float = 10.0:
	set(value):
		cylinder_radius = value
		update_mesh_scales()

@export var check_interval: float = 0.1

var is_player_outside: bool = false
var _check_accumulator: float = 0.0
var _last_real_storm_ms: float = 0.0

func _ready() -> void:
	if Engine.is_editor_hint():
		return

	if world_env and normal_env:
		world_env.environment = normal_env

	if light_normal:
		light_normal.visible = true

	if light_storm:
		light_storm.visible = false

	update_mesh_scales()

func set_storm_radius(radius: float) -> void:
	cylinder_radius = radius

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	var now_ms := float(Time.get_ticks_msec())
	if _last_real_storm_ms == 0.0:
		_last_real_storm_ms = now_ms

	var real_delta := (now_ms - _last_real_storm_ms) / 1000.0
	_last_real_storm_ms = now_ms

	_check_accumulator += real_delta
	if _check_accumulator < check_interval:
		return
	_check_accumulator = 0.0

	if not camera or not world_env or not light_normal or not light_storm:
		return

	var camera_pos_2d = Vector2(camera.global_position.x, camera.global_position.z)
	var cylinder_pos_2d = Vector2(global_position.x, global_position.z)
	var current_distance = camera_pos_2d.distance_to(cylinder_pos_2d)

	if current_distance > cylinder_radius:
		if not is_player_outside:
			enter_storm()
	else:
		if is_player_outside:
			enter_safe_zone()

func update_mesh_scales() -> void:
	if cylinder_wall:
		cylinder_wall.scale = Vector3(cylinder_radius, cylinder_wall.scale.y, cylinder_radius)
	if cylinder_border:
		cylinder_border.scale = Vector3(cylinder_radius, cylinder_border.scale.y, cylinder_radius)

func enter_storm() -> void:
	is_player_outside = true
	world_env.environment = storm_env
	light_normal.visible = false
	light_storm.visible = true

func enter_safe_zone() -> void:
	is_player_outside = false
	world_env.environment = normal_env
	light_normal.visible = true
	light_storm.visible = false
