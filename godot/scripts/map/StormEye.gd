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
@export var damage_per_second: float = 2.0  # Health drained per second while outside (was 10, reduced 80%)

@export_category("Storm Warm-up")
## Pre-compile the storm's shader variants and build the night light's shadow
## atlas shortly after the local player joins, instead of the first time they
## actually cross into the storm. Under the GL Compatibility renderer (the web
## build) both of those happen synchronously inside one frame, which reads as a
## multi-hundred-ms freeze mid-fight. Warming up moves that cost to a safe
## moment behind a cover. One-shot per scene instance.
@export var prewarm_on_ready: bool = true
## How long to wait for the join camera-block to clear before warming up anyway.
## The block occludes the whole map, and an occluded viewport compiles nothing.
@export var prewarm_join_timeout: float = 10.0
## Drawn frames to hold the storm look open. Two is plenty; more just lengthens
## the (covered) pause.
@export_range(1, 8) var prewarm_frames: int = 2
## Hide the warm-up behind a full-screen fill for the couple of frames it takes.
@export var prewarm_cover: bool = true

## Matches the scene-transition backdrop, so the cover blends into the fade that
## is usually still on screen at this point.
const COVER_COLOR := Color(0.43137255, 0.32941177, 1.0)

var is_player_outside: bool = false
var _check_accumulator: float = 0.0
## Missing-ref warning is printed once instead of 10x/second forever.
var _missing_refs_warned: bool = false
var _last_real_storm_ms: float = 0.0
var _warming_up: bool = false
var _warmup_done: bool = false

func _ready() -> void:
	if Engine.is_editor_hint():
		return

	add_to_group("storm_eye")

	if world_env and normal_env:
		world_env.environment = normal_env

	if light_normal:
		light_normal.visible = true

	if light_storm:
		light_storm.visible = false

	update_mesh_scales()

	if prewarm_on_ready:
		_run_prewarm.call_deferred()

func set_storm_radius(radius: float) -> void:
	cylinder_radius = radius

func get_storm_center() -> Vector2:
	return Vector2(global_position.x, global_position.z)

func get_storm_radius() -> float:
	return cylinder_radius

func get_damage_per_second() -> float:
	return damage_per_second

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	# The warm-up drives the environment/lights by hand; keep the zone state
	# machine out of the way until it has handed them back.
	if _warming_up:
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

	# Visual effects track CAMERA (what player sees)
	if not camera or not world_env or not light_normal or not light_storm:
		# This runs on a 0.1 s throttle, so warn once instead of 10x/second.
		if not _missing_refs_warned:
			_missing_refs_warned = true
			print("StormEye: Missing camera/world_env/lights")
		return

	var camera_pos_2d = Vector2(camera.global_position.x, camera.global_position.z)
	var cylinder_pos_2d = Vector2(global_position.x, global_position.z)
	var camera_distance = camera_pos_2d.distance_to(cylinder_pos_2d)

	var visual_outside: bool = camera_distance > cylinder_radius

	if visual_outside:
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


# --- STORM WARM-UP ---
# The first swap to storm_env compiles a batch of new shader variants (fog,
# ambient source, the storm light's sky_mode) and builds the night light's
# shadow atlas. On the GL Compatibility renderer that happens synchronously on
# the frame of the swap. Doing it once, early, behind a cover keeps the actual
# first storm entry smooth.
#
# There is no async shader compilation to hook into here, so the "preload" is a
# warm-up frame: draw the storm setup for real, once, while nothing depends on
# the result.

func _run_prewarm() -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return

	# Wait for the local player to join: until the join placeholder plane is
	# hidden the camera sees almost nothing, so the warm-up would compile
	# almost nothing either.
	var block := _camera_block()
	var deadline_ms := Time.get_ticks_msec() + int(maxf(prewarm_join_timeout, 0.0) * 1000.0)
	while is_instance_valid(block) and block.visible and Time.get_ticks_msec() < deadline_ms:
		await get_tree().process_frame
		if not is_inside_tree():
			return

	if not is_inside_tree():
		return
	# Let the now-unblocked view render once so the map is on screen to be
	# compiled by the warm-up frames.
	await get_tree().process_frame
	if not is_inside_tree():
		return

	prewarm_storm_visuals()

## Force the storm look for a few drawn frames, then put it back. Safe to call
## more than once; only the first call does work.
func prewarm_storm_visuals() -> void:
	if _warmup_done or _warming_up:
		return
	if DisplayServer.get_name() == "headless":
		return
	if not is_instance_valid(world_env) or not is_instance_valid(storm_env) or not is_instance_valid(light_storm):
		return

	_warming_up = true

	var cover: CanvasLayer = null
	if prewarm_cover:
		cover = _show_cover()
		# Draw the cover once *before* the swap, so the frame that stalls is a
		# covered frame rather than whatever was on screen.
		await RenderingServer.frame_post_draw
		if not is_inside_tree():
			return

	var prev_env: Environment = world_env.environment
	var prev_normal: bool = light_normal.visible if is_instance_valid(light_normal) else false
	var prev_storm: bool = light_storm.visible

	world_env.environment = storm_env
	if is_instance_valid(light_normal):
		light_normal.visible = false
	light_storm.visible = true

	for _i in range(maxi(1, prewarm_frames)):
		await RenderingServer.frame_post_draw
		if not is_inside_tree():
			return

	if world_env != null and is_instance_valid(world_env):
		world_env.environment = prev_env
	if is_instance_valid(light_normal):
		light_normal.visible = prev_normal
	if light_storm != null and is_instance_valid(light_storm):
		light_storm.visible = prev_storm

	_warming_up = false
	_warmup_done = true

	if cover != null and is_instance_valid(cover):
		cover.queue_free()

func _camera_block() -> Node3D:
	if camera == null or not is_instance_valid(camera):
		return null
	return camera.get_node_or_null(NodePath("CAMERABlock")) as Node3D

func _show_cover() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 101
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = COVER_COLOR
	layer.add_child(rect)
	# Parented to the scene (not root) so it is torn down with it if the match
	# ends mid-warm-up. A CanvasLayer ignores its parent's transform, so this
	# still covers the whole screen.
	add_child(layer)
	return layer
