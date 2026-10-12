extends Control

# === REFERENCES ===
@export var background_texture: TextureRect

@export var minimap_container: Control
@export var player_pointer: TextureRect
@export var chicken_pointer: TextureRect
@export var lootbox_pointer: TextureRect
@export var pickup_pointer: TextureRect # Template; one clone is spawned per pickup
@export var storm_overlay: TextureRect
@export var bus_path_overlay: BusPathOverlay # Draws the white bus-route circle above the background
@export var enabled: bool = true
@export var disable_on_mobile: bool = false
@export var disable_on_web: bool = false
@export var minimum_fps_to_enable: float = 0.0

# --- BUS PATH OVERLAY ---
@export var show_bus_path: bool = true
@export var bus_path_color: Color = Color(1, 1, 1, 1)
@export var bus_path_width: float = 2.0

var local_player: Node3D = null
var local_camera: Camera3D = null
var chicken_target: Node3D = null
var player_manager: Node = null
var lootbox_target: Node3D = null
var _storm_eye_node: Node3D = null

# One white pointer per pickup in the "local_pickup_items" group.
var _pickup_targets: Dictionary = {}  # instance_id -> Node3D
var _pickup_pointers: Dictionary = {} # instance_id -> TextureRect
var _last_pickup_rescan_ms: int = -100000 # rescan immediately on first frame

var _bus_node: Node3D = null

# --- BUS PATH OVERLAY CACHE ---
# The bus route is a static circle; only its screen projection changes. We
# cache the world->uv samples (computed only when the bus or map config
# changes) and reuse a preallocated point buffer, so a normal update tick is a
# handful of multiply-adds instead of trig + GameManager reads every 33 ms.
const BUS_PATH_STEPS := 96
const BUS_PATH_MIN_MOVE_PX := 1.0 # only re-upload when the projection moved this much

var _bus_circle_uvs := PackedVector2Array() # BUS_PATH_STEPS uv samples, built once
var _bus_circle_points := PackedVector2Array() # reusable output buffer (BUS_PATH_STEPS + 1)
var _bus_circle_world_size := Vector2.ZERO # map config the uv cache was built from
var _bus_circle_world_origin := Vector2.ZERO
var _last_bus_fullscreen := false
var _last_bus_offset := Vector2(INF, INF) # forces the very first upload

var _last_real_minimap_ms: float = 0.0
var _last_storm_center: Vector2 = Vector2.ZERO
var _last_storm_radius: float = -1.0
var _storm_params_valid: bool = false

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
	if pickup_pointer:
		# The template never shows; clones are created for each pickup.
		pickup_pointer.visible = false
	_setup_pointer(pickup_pointer)
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
	_update_bus_path_overlay()

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

	if pickup_pointer and _pickup_targets.size() > 0:
		_update_pickup_pointers()

	if storm_overlay:
		_update_storm_overlay()

	if show_bus_path:
		_update_bus_path_overlay()

func _get_world_uv(world_pos: Vector3) -> Vector2:
	var world_size = GameManager.minimap_world_size
	var world_origin = GameManager.minimap_origin
	if world_size.x == 0 or world_size.y == 0:
		return Vector2(0.5, 0.5)
	var rel_x = world_pos.x - world_origin.x
	var rel_z = world_pos.z - world_origin.y
	return Vector2((rel_x / world_size.x) + 0.5, (rel_z / world_size.y) + 0.5)

func _update_bus_path_overlay() -> void:
	# Feed the white bus-route circle to the overlay node (which is a sibling
	# above the background texture). The overlay draws in its own local space,
	# and it is anchored to fill the minimap, so its coordinates match
	# _world_to_minimap() output.
	if not is_instance_valid(bus_path_overlay) or not enabled or not show_bus_path:
		return
	if not is_instance_valid(background_texture):
		return
	if _bus_node == null or not is_instance_valid(_bus_node):
		_bus_node = get_tree().get_first_node_in_group("bus")
	if _bus_node == null or not is_instance_valid(_bus_node):
		return

	# Rebuild the static circle samples only when the bus or map config changes.
	if (
		GameManager.minimap_world_size != _bus_circle_world_size
		or GameManager.minimap_origin != _bus_circle_world_origin
	):
		_bus_circle_uvs = PackedVector2Array() # invalidate
	if _bus_circle_uvs.is_empty():
		_build_bus_circle_uvs()
		if _bus_circle_uvs.is_empty():
			return

	# The circle is static; skip the per-tick upload + redraw unless the
	# projection actually moved (fullscreen flip, or the zoomed background
	# tracked the player by more than a pixel).
	if (
		_is_fullscreen == _last_bus_fullscreen
		and absf(background_texture.position.x - _last_bus_offset.x) < BUS_PATH_MIN_MOVE_PX
		and absf(background_texture.position.y - _last_bus_offset.y) < BUS_PATH_MIN_MOVE_PX
	):
		return
	_last_bus_fullscreen = _is_fullscreen
	_last_bus_offset = background_texture.position

	var mm := minimap_container.size
	var pts := _bus_circle_points
	if _is_fullscreen:
		for i in BUS_PATH_STEPS:
			pts[i] = _bus_circle_uvs[i] * mm
	else:
		var scaled := mm * zoom_level
		var off := background_texture.position
		for i in BUS_PATH_STEPS:
			pts[i] = _bus_circle_uvs[i] * scaled + off
	pts[BUS_PATH_STEPS] = pts[0] # close the loop
	bus_path_overlay.set_path(pts, bus_path_color, bus_path_width)

func _build_bus_circle_uvs() -> void:
	var bus_center: Variant = _bus_node.get("center")
	var bus_radius: Variant = _bus_node.get("radius")
	if not bus_center is Vector3 or bus_radius <= 0.0:
		return
	_bus_circle_world_size = GameManager.minimap_world_size
	_bus_circle_world_origin = GameManager.minimap_origin
	_bus_circle_uvs = PackedVector2Array()
	_bus_circle_uvs.resize(BUS_PATH_STEPS)
	for i in BUS_PATH_STEPS:
		var angle := TAU * float(i) / float(BUS_PATH_STEPS)
		var wp: Vector3 = bus_center + Vector3(cos(angle) * bus_radius, 0.0, sin(angle) * bus_radius)
		_bus_circle_uvs[i] = _get_world_uv(wp)
	_bus_circle_points.resize(BUS_PATH_STEPS + 1)

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

	# Resolve the manager once and reuse it. It is a persistent node, so a
	# tree-wide find_child on every ~33 Hz update (while the chicken/lootbox
	# have not spawned yet) is pure waste.
	if player_manager == null or not is_instance_valid(player_manager):
		player_manager = _find_player_manager()

	if chicken_target == null or not is_instance_valid(chicken_target):
		if player_manager != null and player_manager.has_method("get_chicken_node"):
			chicken_target = player_manager.call("get_chicken_node")

	if lootbox_target == null or not is_instance_valid(lootbox_target):
		if player_manager != null and player_manager.has_method("get_lootbox_node"):
			lootbox_target = player_manager.call("get_lootbox_node")

	if pickup_pointer:
		_refresh_pickup_targets()

	if _storm_eye_node == null or not is_instance_valid(_storm_eye_node):
		# Prefer the group StormEye registers itself in; the node names below are
		# only a fallback for scenes that predate it.
		_storm_eye_node = get_tree().get_first_node_in_group("storm_eye") as Node3D
		if _storm_eye_node == null:
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

func _refresh_pickup_targets() -> void:
	# Rescanning the "local_pickup_items" group is a full scene-tree walk, so
	# throttle it to ~2 Hz instead of every 33 ms update tick. Pointer positions
	# still track live each tick; only the set of pickups refreshes slowly.
	var now_ms := Time.get_ticks_msec()
	if now_ms - _last_pickup_rescan_ms < 500:
		return
	_last_pickup_rescan_ms = now_ms

	# One pointer per pickup currently in the world. Held/local items are skipped
	# so a carried pickup stops showing up while it rides on the player.
	var current: Array[Node] = get_tree().get_nodes_in_group("local_pickup_items")
	var seen := {}
	for node in current:
		if not node is Node3D or not is_instance_valid(node):
			continue
		if node.has_method("is_being_held") and node.is_being_held():
			continue
		seen[node.get_instance_id()] = node

	# Free pointers whose pickup was removed or got picked up.
	for id in _pickup_pointers.keys():
		if not seen.has(id):
			var ptr: TextureRect = _pickup_pointers[id]
			if ptr != null and is_instance_valid(ptr):
				ptr.queue_free()
			_pickup_pointers.erase(id)

	# Give new pickups their own pointer.
	for id in seen.keys():
		if not _pickup_pointers.has(id):
			_pickup_pointers[id] = _make_pickup_pointer()

	_pickup_targets = seen

func _make_pickup_pointer() -> TextureRect:
	var ptr := pickup_pointer.duplicate() as TextureRect
	pickup_pointer.get_parent().add_child(ptr)
	_setup_pointer(ptr)
	ptr.visible = false
	return ptr

func _update_pickup_pointers() -> void:
	for id in _pickup_targets.keys():
		var node: Node3D = _pickup_targets[id]
		var ptr: TextureRect = _pickup_pointers.get(id)
		if not is_instance_valid(node) or not is_instance_valid(ptr):
			continue
		var mm_pos: Vector2 = _world_to_minimap(node.global_position)
		var mm_size: Vector2 = minimap_container.size
		var half: Vector2 = ptr.size * 0.5
		var clamped := Vector2(
			clampf(mm_pos.x, half.x, mm_size.x - half.x),
			clampf(mm_pos.y, half.y, mm_size.y - half.y)
		)
		ptr.visible = true
		ptr.position = clamped - half
		ptr.rotation = 0.0

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
		# Only push uniforms when the storm actually moved/shrank. The storm eye
		# is static most of the time, so this skips nearly all redundant
		# set_shader_parameter calls (each one dirties the material).
		var changed := not _storm_params_valid
		if not changed:
			changed = not _last_storm_center.is_equal_approx(center_uv)
		if not changed:
			changed = not is_equal_approx(_last_storm_radius, radius_uv)
		if changed:
			mat.set_shader_parameter("storm_center", center_uv)
			mat.set_shader_parameter("storm_radius", radius_uv)
			_last_storm_center = center_uv
			_last_storm_radius = radius_uv
			_storm_params_valid = true
		storm_overlay.visible = true

func _apply_visibility(force_visible: bool = true) -> void:
	var should_show := enabled and force_visible
	if disable_on_mobile and OS.has_feature("mobile"):
		should_show = false
	if disable_on_web and OS.has_feature("web"):
		should_show = false

	if minimap_container:
		minimap_container.visible = should_show
