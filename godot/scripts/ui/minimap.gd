extends Node

# === REFERENCES ===
@export var background_texture: TextureRect

@export var minimap_container: Control
@export var player_pointer: TextureRect
@export var chicken_pointer: TextureRect
@export var lootbox_pointer: TextureRect
@export var storm_overlay: TextureRect
@export var enabled: bool = true
@export var disable_on_mobile: bool = false
@export var disable_on_web: bool = false
@export var minimum_fps_to_enable: float = 0.0

var local_player: Node3D = null
var local_camera: Camera3D = null
var chicken_target: Node3D = null
var player_manager: Node = null
var lootbox_target: Node3D = null
var _storm_eye_node: Node3D = null

var _last_real_minimap_ms: float = 0.0

# === SETTINGS ===
@export var rotate_pointer: bool = true
@export var update_interval: float = 0.03 # Updates at ~33 FPS for smooth following
@export var zoom_level: float = 7.0

var _update_timer: float = 0.0
var _last_fps_check: float = 0.0

# --- FULLSCREEN MAP VARIABLES ---
var _is_fullscreen: bool = false
var _original_anchors: Vector4
var _original_offsets: Vector4
var _original_z_index: int

func _ready() -> void:
	# Initialize with snapshot from GameManager
	if background_texture:
		background_texture.texture = GameManager.minimap_texture
		background_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		background_texture.stretch_mode = TextureRect.STRETCH_SCALE
	
	# Store original layout for toggle
	_original_anchors = Vector4(minimap_container.anchor_left, minimap_container.anchor_top, minimap_container.anchor_right, minimap_container.anchor_bottom)
	_original_offsets = Vector4(minimap_container.offset_left, minimap_container.offset_top, minimap_container.offset_right, minimap_container.offset_bottom)
	_original_z_index = minimap_container.z_index

	# Center the pointer automatically
	_setup_pointer(player_pointer)
	_setup_pointer(chicken_pointer)
	_setup_pointer(lootbox_pointer)
	_refresh_targets()

	_apply_visibility()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_toggle_fullscreen()

func _toggle_fullscreen() -> void:
	_is_fullscreen = !_is_fullscreen
	if _is_fullscreen:
		minimap_container.z_index = 100 # Put on top
		_update_fullscreen_layout()
		# Reset background for full view
		background_texture.position = Vector2.ZERO
		background_texture.size = minimap_container.size
	else:
		minimap_container.z_index = _original_z_index
		minimap_container.anchor_left = _original_anchors.x
		minimap_container.anchor_top = _original_anchors.y
		minimap_container.anchor_right = _original_anchors.z
		minimap_container.anchor_bottom = _original_anchors.w
		minimap_container.offset_left = _original_offsets.x
		minimap_container.offset_top = _original_offsets.y
		minimap_container.offset_right = _original_offsets.z
		minimap_container.offset_bottom = _original_offsets.w

func _update_fullscreen_layout() -> void:
	var viewport_size = get_viewport().get_visible_rect().size
	var map_side = min(viewport_size.x, viewport_size.y)
	
	minimap_container.anchor_left = 0.5
	minimap_container.anchor_top = 0.5
	minimap_container.anchor_right = 0.5
	minimap_container.anchor_bottom = 0.5
	
	minimap_container.offset_left = -map_side * 0.5
	minimap_container.offset_top = -map_side * 0.5
	minimap_container.offset_right = map_side * 0.5
	minimap_container.offset_bottom = map_side * 0.5

func _handle_fullscreen_input() -> void:
	# Placeholder for any specific fullscreen input logic
	pass

func _process(_delta: float) -> void:
	if not enabled:
		_apply_visibility()
		return
	
	if _is_fullscreen:
		_handle_fullscreen_input()

	# Auto-correct delta for game speed to keep minimap updates in real-time
	var now_ms := float(Time.get_ticks_msec())
	if _last_real_minimap_ms == 0.0:
		_last_real_minimap_ms = now_ms
	
	var real_delta := (now_ms - _last_real_minimap_ms) / 1000.0
	_last_real_minimap_ms = now_ms

	_update_timer += real_delta
	if update_interval > 0.0 and _update_timer < update_interval:
		return
	_update_timer = 0.0

	_refresh_targets()
	if !local_player:
		return

	if minimum_fps_to_enable > 0.0:
		var fps := Engine.get_frames_per_second()
		_last_fps_check = fps
		if fps > 0 and fps < minimum_fps_to_enable:
			_apply_visibility(false)
			return

	_apply_visibility(true)

	var mm_size: Vector2 = minimap_container.size
	var player_uv: Vector2 = _get_world_uv(local_player.global_position)

	if _is_fullscreen:
		# Static Full View: background covers the container, doesn't move.
		background_texture.size = mm_size
		background_texture.position = Vector2.ZERO
		if player_pointer:
			player_pointer.position = (player_uv * mm_size) - (player_pointer.size * 0.5)
	else:
		# Zoomed Following Logic: background is larger and centered on player.
		var current_zoom = zoom_level
		var scaled_size = mm_size * current_zoom
		background_texture.size = scaled_size
		
		# Offset background to center player
		var pixel_pos_on_scaled = player_uv * scaled_size
		background_texture.position = (mm_size * 0.5) - pixel_pos_on_scaled
		
		# Player pointer is fixed at center
		if player_pointer:
			player_pointer.position = (mm_size * 0.5) - (player_pointer.size * 0.5)

	# Rotate player pointer
	if player_pointer and rotate_pointer:
		var heading_source: Camera3D = local_camera if local_camera != null and is_instance_valid(local_camera) else null
		if heading_source != null:
			player_pointer.rotation = -heading_source.global_rotation.y
		else:
			player_pointer.rotation = -local_player.global_rotation.y

	if chicken_pointer:
		_update_chicken_pointer()

	if lootbox_pointer:
		_update_lootbox_pointer()

	if storm_overlay:
		_update_storm_overlay()

func _get_world_uv(world_pos: Vector3) -> Vector2:
	var world_size = GameManager.minimap_world_size
	var world_origin = GameManager.minimap_origin
	if world_size.x == 0 or world_size.y == 0:
		return Vector2(0.5, 0.5)
	var rel_x = world_pos.x - world_origin.x
	var rel_z = world_pos.z - world_origin.y
	return Vector2((rel_x / world_size.x) + 0.5, (rel_z / world_size.y) + 0.5)

func _world_to_minimap(world_pos: Vector3) -> Vector2:
	var uv = _get_world_uv(world_pos)
	
	if _is_fullscreen:
		return uv * minimap_container.size
		
	var current_zoom = zoom_level
	# Return position relative to the minimap container, accounting for current zoom and background offset
	var scaled_pos = uv * (minimap_container.size * current_zoom)
	return background_texture.position + scaled_pos

func _refresh_targets() -> void:
	if local_player == null or not is_instance_valid(local_player):
		local_player = get_tree().get_first_node_in_group("local_player")
		local_camera = null

	if local_player != null and is_instance_valid(local_player) and local_camera == null:
		var camera_candidate: Variant = local_player.get("camera")
		if camera_candidate is Camera3D:
			local_camera = camera_candidate

	if chicken_target == null or not is_instance_valid(chicken_target):
		player_manager = _find_player_manager()
		if player_manager != null and player_manager.has_method("get_chicken_node"):
			chicken_target = player_manager.call("get_chicken_node")

	if lootbox_target == null or not is_instance_valid(lootbox_target):
		player_manager = _find_player_manager()
		if player_manager != null and player_manager.has_method("get_lootbox_node"):
			lootbox_target = player_manager.call("get_lootbox_node")

	if _storm_eye_node == null or not is_instance_valid(_storm_eye_node):
		_storm_eye_node = get_tree().root.find_child("env", true, false)
		if _storm_eye_node == null:
			_storm_eye_node = get_tree().root.find_child("enviroment", true, false)

func _find_player_manager() -> Node:
	var tree := get_tree()
	if tree == null:
		return null

	if tree.current_scene != null:
		var current_scene_manager := tree.current_scene.find_child("PlayerManager", true, false)
		if current_scene_manager != null and current_scene_manager.has_method("get_chicken_node"):
			return current_scene_manager

	var root_manager := tree.root.find_child("PlayerManager", true, false)
	if root_manager != null and root_manager.has_method("get_chicken_node"):
		return root_manager

	return null

func _setup_pointer(pointer: TextureRect) -> void:
	if pointer == null:
		return

	pointer.pivot_offset = pointer.size * 0.5

func _update_chicken_pointer() -> void:
	if chicken_target == null or not is_instance_valid(chicken_target):
		chicken_pointer.visible = false
		return

	var mm_pos: Vector2 = _world_to_minimap(chicken_target.global_position)
	var mm_size: Vector2 = minimap_container.size
	
	var half_pointer: Vector2 = chicken_pointer.size * 0.5
	var min_pos: Vector2 = half_pointer
	var max_pos: Vector2 = mm_size - half_pointer
	
	# Clamp to edges so it shows which direction the chicken is if off-map
	var clamped_pos := Vector2(
		clampf(mm_pos.x, min_pos.x, max_pos.x),
		clampf(mm_pos.y, min_pos.y, max_pos.y)
	)
	
	chicken_pointer.visible = true
	chicken_pointer.position = clamped_pos - half_pointer
	chicken_pointer.rotation = 0.0


func _update_lootbox_pointer() -> void:
	if lootbox_target == null or not is_instance_valid(lootbox_target):
		lootbox_pointer.visible = false
		return

	var mm_pos: Vector2 = _world_to_minimap(lootbox_target.global_position)
	var mm_size: Vector2 = minimap_container.size

	var half_pointer: Vector2 = lootbox_pointer.size * 0.5
	var min_pos: Vector2 = half_pointer
	var max_pos: Vector2 = mm_size - half_pointer

	var clamped_pos := Vector2(
		clampf(mm_pos.x, min_pos.x, max_pos.x),
		clampf(mm_pos.y, min_pos.y, max_pos.y)
	)

	lootbox_pointer.visible = true
	lootbox_pointer.position = clamped_pos - half_pointer
	lootbox_pointer.rotation = 0.0

func _update_storm_overlay() -> void:
	if not _is_fullscreen:
		storm_overlay.visible = false
		return

	if _storm_eye_node == null or not is_instance_valid(_storm_eye_node):
		storm_overlay.visible = false
		return

	var storm_world = _storm_eye_node.global_position
	var storm_radius: float = _storm_eye_node.get("cylinder_radius")
	if storm_radius == null or storm_radius <= 0:
		storm_overlay.visible = false
		return

	var world_size = GameManager.minimap_world_size
	if world_size.x <= 0 or world_size.y <= 0:
		storm_overlay.visible = false
		return

	var storm_uv = _get_world_uv(storm_world)
	var center_uv = storm_uv
	var radius_uv = storm_radius / world_size.x

	var mat = storm_overlay.material
	if mat is ShaderMaterial:
		mat.set_shader_parameter("storm_center", center_uv)
		mat.set_shader_parameter("storm_radius", radius_uv)
		storm_overlay.visible = true

func _apply_visibility(force_visible: bool = true) -> void:
	var should_show := enabled and force_visible
	if disable_on_mobile and OS.has_feature("mobile"):
		should_show = false
	if disable_on_web and OS.has_feature("web"):
		should_show = false

	if minimap_container:
		minimap_container.visible = should_show
