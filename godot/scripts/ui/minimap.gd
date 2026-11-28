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
# Inner clip for the panning background; pointers stay outside it so they can
# overflow the minimap edge without being cut off.
var _map_clip: Control = null

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
var _original_clip_contents: bool = true
# Storm overlay (fullscreen only): it normally fills the map square, but in
# fullscreen it expands across the whole screen so the storm tint is not
# limited to the square map area.
var _storm_anchors: Vector4
var _storm_offsets: Vector4

# --- FULLSCREEN CHROME ---
## The event feed stays readable over the expanded map, so it is pushed above
## the map's z-index instead of being hidden behind it.
var _event_feed_panel: Control = null
var _event_feed_z_index: int = 0
## HUD nodes that would otherwise draw over the fullscreen map (the action
## buttons live on a later CanvasLayer, so z_index alone cannot put the map
## above them). CanvasLayer is not a CanvasItem, so store plain Nodes and use
## their `visible` property.
var _hide_controls: Array[Node] = []
var _hide_controls_visible: Array[bool] = []
## A tap opens the map on press; ignore presses for a moment afterwards so the
## same gesture cannot immediately close it again.
const CLOSE_GRACE_MS := 150
var _opened_at_ms: int = 0

## Fullscreen "shade": the shde ColorRect in the HUD fades in behind the map
## while it is expanded, and fades back out when the map is closed.
@export var shade_overlay: CanvasItem
@export var shade_fade_duration: float = 0.4
var _shade_tween: Tween = null

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
	_original_clip_contents = minimap_container.clip_contents
	
	if storm_overlay:
		_storm_anchors = Vector4(storm_overlay.anchor_left, storm_overlay.anchor_top, storm_overlay.anchor_right, storm_overlay.anchor_bottom)
		_storm_offsets = Vector4(storm_overlay.offset_left, storm_overlay.offset_top, storm_overlay.offset_right, storm_overlay.offset_bottom)

	_ensure_pointer_overflow()
	_resolve_expanded_chrome()

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


## The minimap background pans/zooms and must be clipped to the map, but edge
## pointers should stay fully visible instead of being cut off. Wrap the clipped
## map layers in an inner clip container and keep pointers as direct children of
## the non-clipping minimap.
func _ensure_pointer_overflow() -> void:
	minimap_container.clip_contents = false
	_map_clip = Control.new()
	_map_clip.name = "MapClip"
	_map_clip.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_clip.clip_contents = true
	_map_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_container.add_child(_map_clip)
	minimap_container.move_child(_map_clip, 0)
	for node_name in ["ColorRect", "MinimapBackground", "StormOverlay", "BusPath"]:
		var n := minimap_container.get_node_or_null(NodePath(node_name))
		if n != null and n != _map_clip:
			n.reparent(_map_clip, false)


func _gui_input(event: InputEvent) -> void:
	if _is_fullscreen:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_set_fullscreen(true)


## While the map is expanded, any press on the screen closes it. Handling it in
## _input (before GUI) means buttons under the tap cannot also fire, and a tap
## on the map itself closes instead of being swallowed by the map control.
func _input(event: InputEvent) -> void:
	if not _is_fullscreen:
		return
	if Time.get_ticks_msec() - _opened_at_ms < CLOSE_GRACE_MS:
		return
	if not _is_close_press(event):
		return
	get_viewport().set_input_as_handled()
	_set_fullscreen(false)


func _is_close_press(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	if event is InputEventScreenTouch:
		return event.pressed
	return false


func _toggle_fullscreen() -> void:
	_set_fullscreen(not _is_fullscreen)


func _set_fullscreen(expanded: bool) -> void:
	if _is_fullscreen == expanded:
		return
	_is_fullscreen = expanded
	if _is_fullscreen:
		_opened_at_ms = Time.get_ticks_msec()
		minimap_container.z_index = 100 # Put on top
		_update_fullscreen_layout()
		# Let the storm overlay extend beyond the square map, across the screen.
		minimap_container.clip_contents = false
		if _map_clip != null:
			_map_clip.clip_contents = false
		_layout_fullscreen_storm_overlay()
		# Reset background for full view
		background_texture.position = Vector2.ZERO
		background_texture.size = minimap_container.size
		_fade_shade(true)
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
		minimap_container.clip_contents = false
		if _map_clip != null:
			_map_clip.clip_contents = true
		_restore_storm_overlay_layout()
		_fade_shade(false)
	_apply_expanded_chrome(_is_fullscreen)
	_update_bus_path_overlay()


## Resolve the HUD pieces the fullscreen map has to cover/keep visible. The
## event feed is a sibling of the map; the action buttons live on a later
## CanvasLayer, which draws above the map regardless of z_index.
func _resolve_expanded_chrome() -> void:
	_event_feed_panel = get_node_or_null("../EventFeedPanel") as Control
	if _event_feed_panel != null:
		_event_feed_z_index = _event_feed_panel.z_index

	_hide_controls.clear()
	for path in [
		# Whole action-button layer: hides Action/Jump/Slide, Chog and the ammo
		# label even if buttons.gd toggles Chog's own visibility while open.
		"../../../../Node3/CanvasLayer",
	]:
		var node := get_node_or_null(path)
		if node != null:
			_hide_controls.append(node)
	_hide_controls_visible.resize(_hide_controls.size())
	_hide_controls_visible.fill(true)


func _apply_expanded_chrome(expanded: bool) -> void:
	if _event_feed_panel != null and is_instance_valid(_event_feed_panel):
		# The map's own pointers use z_index 10-11 relative to the map's 100, so
		# sit well above map+1; go far enough to clear those children too.
		_event_feed_panel.z_index = (
			minimap_container.z_index + 100 if expanded else _event_feed_z_index
		)
	for index in _hide_controls.size():
		var control := _hide_controls[index]
		if control == null or not is_instance_valid(control):
			continue
		if expanded:
			_hide_controls_visible[index] = bool(control.get("visible"))
			control.set("visible", false)
		else:
			control.set("visible", _hide_controls_visible[index])
	_sync_pointer_labels()

func _fade_shade(should_show: bool) -> void:
	if shade_overlay == null or not is_instance_valid(shade_overlay):
		return
	if _shade_tween and is_instance_valid(_shade_tween):
		_shade_tween.kill()
	shade_overlay.visible = true
	_shade_tween = create_tween()
	if should_show:
		shade_overlay.modulate.a = 0.0
		_shade_tween.tween_property(shade_overlay, "modulate:a", 1.0, shade_fade_duration)
	else:
		shade_overlay.modulate.a = 1.0
		_shade_tween.tween_property(shade_overlay, "modulate:a", 0.0, shade_fade_duration)
		_shade_tween.finished.connect(func(): shade_overlay.visible = false)

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

## Stretch the storm tint over the entire screen while the map is expanded.
## The shader maps its UVs back onto the centred square map via `map_rect`,
## so the storm eye circle keeps its position and size on the map.
func _layout_fullscreen_storm_overlay() -> void:
	if storm_overlay == null or not is_instance_valid(storm_overlay):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var map_side := minf(viewport_size.x, viewport_size.y)
	var map_offset := (viewport_size - Vector2(map_side, map_side)) * 0.5
	storm_overlay.anchor_left = 0.0
	storm_overlay.anchor_top = 0.0
	storm_overlay.anchor_right = 0.0
	storm_overlay.anchor_bottom = 0.0
	storm_overlay.offset_left = -map_offset.x
	storm_overlay.offset_top = -map_offset.y
	storm_overlay.offset_right = -map_offset.x + viewport_size.x
	storm_overlay.offset_bottom = -map_offset.y + viewport_size.y
	if storm_overlay.material is ShaderMaterial:
		storm_overlay.material.set_shader_parameter("map_rect", Vector4(
			map_offset.x / viewport_size.x,
			map_offset.y / viewport_size.y,
			map_side / viewport_size.x,
			map_side / viewport_size.y
		))

func _restore_storm_overlay_layout() -> void:
	if storm_overlay == null or not is_instance_valid(storm_overlay):
		return
	storm_overlay.anchor_left = _storm_anchors.x
	storm_overlay.anchor_top = _storm_anchors.y
	storm_overlay.anchor_right = _storm_anchors.z
	storm_overlay.anchor_bottom = _storm_anchors.w
	storm_overlay.offset_left = _storm_offsets.x
	storm_overlay.offset_top = _storm_offsets.y
	storm_overlay.offset_right = _storm_offsets.z
	storm_overlay.offset_bottom = _storm_offsets.w
	if storm_overlay.material is ShaderMaterial:
		storm_overlay.material.set_shader_parameter("map_rect", Vector4(0.0, 0.0, 1.0, 1.0))

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
		var target_pos = (mm_size * 0.5) - pixel_pos_on_scaled
		# Near the map edge the snapshot used to slide past the control and
		# expose the purple panel behind it. Clamp so the map always fills the
		# minimap window instead of showing a coloured border.
		target_pos.x = clampf(target_pos.x, mm_size.x - scaled_size.x, 0.0)
		target_pos.y = clampf(target_pos.y, mm_size.y - scaled_size.y, 0.0)
		background_texture.position = target_pos
		
		# Player pointer sits on the player's actual pixel; that is the centre
		# until the clamp above kicks in at the map edge.
		if player_pointer:
			var player_px = target_pos + pixel_pos_on_scaled
			player_pointer.position = player_px - (player_pointer.size * 0.5)

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
	_update_pointer_label(pointer, "")


func _sync_pointer_labels() -> void:
	_update_pointer_label(chicken_pointer, "Chicken")
	_update_pointer_label(lootbox_pointer, "Lootbox")
	for id in _pickup_pointers:
		var ptr: TextureRect = _pickup_pointers.get(id)
		if ptr != null and is_instance_valid(ptr):
			var node: Node3D = _pickup_targets.get(id)
			_update_pointer_label(ptr, _pickup_display_name(node))


func _update_pointer_label(pointer: TextureRect, text: String) -> void:
	if pointer == null:
		return
	var lbl := pointer.get_node_or_null("Label") as Label
	if lbl == null:
		return
	if text != "":
		lbl.text = text
	lbl.visible = _is_fullscreen and pointer.visible and lbl.text != ""
	if lbl.visible:
		_style_pointer_label(lbl, pointer)


func _style_pointer_label(lbl: Label, pointer: TextureRect) -> void:
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.size = Vector2(90, 20)
	lbl.position = Vector2((pointer.size.x - lbl.size.x) * 0.5, pointer.size.y - 2)


func _pickup_display_name(node: Node) -> String:
	if node == null or not is_instance_valid(node):
		return "Item"
	if node.has_method("power_up_label"):
		var mode = int(node.get("power_up_mode"))
		match mode:
			LocalPickup.PowerUpMode.TWIN:
				return "Twin"
			LocalPickup.PowerUpMode.SPEED_BURST:
				return "Rush"
			LocalPickup.PowerUpMode.SMOKE_GRENADE:
				return "Smog"
			LocalPickup.PowerUpMode.MEGA_LEAP:
				return "Leap"
			LocalPickup.PowerUpMode.CHICKEN:
				return "Chicken"
			LocalPickup.PowerUpMode.LOOTBOX:
				return "Lootbox"
			_:
				var lbl_text = str(node.call("power_up_label"))
				return lbl_text.capitalize() if lbl_text != "" else "Item"
	var weapon_kind = node.get("weapon_kind")
	if weapon_kind != null:
		match int(weapon_kind):
			LocalPickup2.WeaponKind.SWORD:
				return "Sword"
			LocalPickup2.WeaponKind.AK47:
				return "AK47"
			LocalPickup2.WeaponKind.GLOCK:
				return "Glock"
			LocalPickup2.WeaponKind.KNIFE:
				return "Knife"
			LocalPickup2.WeaponKind.RPG:
				return "RPG"
		return "Weapon"
	return "Item"

func _refresh_pickup_targets() -> void:
	# Rescanning the "local_pickup_items" group is a full scene-tree walk, so
	# throttle it to ~2 Hz instead of every 33 ms update tick. Pointer positions
	# still track live each tick; only the set of pickups refreshes slowly.
	var now_ms := Time.get_ticks_msec()
	if now_ms - _last_pickup_rescan_ms < 500:
		return
	_last_pickup_rescan_ms = now_ms

	# One pointer per pickup currently in the world. Held/local items are skipped
	# so a carried pickup stops showing up while it rides on the player. Objective
	# items (chicken/lootbox) are skipped too: they have their own dedicated
	# pointers, so a generic white pickup pointer would overlap them.
	var current: Array[Node] = get_tree().get_nodes_in_group("local_pickup_items")
	var seen := {}
	for node in current:
		if not node is Node3D or not is_instance_valid(node):
			continue
		if node.has_method("is_being_held") and node.is_being_held():
			continue
		if node.has_method("is_objective_item") and node.is_objective_item():
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
	for id in _pickup_targets:  # iterating the dict directly yields keys, no copy
		var node: Node3D = _pickup_targets[id]
		var ptr: TextureRect = _pickup_pointers.get(id)
		if not is_instance_valid(node) or not is_instance_valid(ptr):
			continue
		var mm_pos: Vector2 = _world_to_minimap(node.global_position)
		var mm_size: Vector2 = minimap_container.size
		var half: Vector2 = ptr.size * 0.5
		# Clamp the center to the map edge so half the marker can sit outside the
		# minimap, making edge targets read as on top of the map border.
		var clamped := Vector2(
			clampf(mm_pos.x, 0.0, mm_size.x),
			clampf(mm_pos.y, 0.0, mm_size.y)
		)
		ptr.visible = true
		ptr.position = clamped - half
		ptr.rotation = 0.0
		_update_pointer_label(ptr, _pickup_display_name(node))

func _update_chicken_pointer() -> void:
	if chicken_target == null or not is_instance_valid(chicken_target):
		chicken_pointer.visible = false
		_update_pointer_label(chicken_pointer, "Chicken")
		return

	var mm_pos: Vector2 = _world_to_minimap(chicken_target.global_position)
	var mm_size: Vector2 = minimap_container.size
	
	var half_pointer: Vector2 = chicken_pointer.size * 0.5
	# Clamp the center to the map edge so half the marker can sit outside the
	# minimap, making edge targets read as on top of the map border.
	var clamped_pos := Vector2(
		clampf(mm_pos.x, 0.0, mm_size.x),
		clampf(mm_pos.y, 0.0, mm_size.y)
	)
	
	chicken_pointer.visible = true
	chicken_pointer.position = clamped_pos - half_pointer
	chicken_pointer.rotation = 0.0
	_update_pointer_label(chicken_pointer, "Chicken")


func _update_lootbox_pointer() -> void:
	if lootbox_target == null or not is_instance_valid(lootbox_target):
		lootbox_pointer.visible = false
		_update_pointer_label(lootbox_pointer, "Lootbox")
		return

	var mm_pos: Vector2 = _world_to_minimap(lootbox_target.global_position)
	var mm_size: Vector2 = minimap_container.size

	var half_pointer: Vector2 = lootbox_pointer.size * 0.5
	# Clamp the center to the map edge so half the marker can sit outside the
	# minimap, making edge targets read as on top of the map border.
	var clamped_pos := Vector2(
		clampf(mm_pos.x, 0.0, mm_size.x),
		clampf(mm_pos.y, 0.0, mm_size.y)
	)

	lootbox_pointer.visible = true
	lootbox_pointer.position = clamped_pos - half_pointer
	lootbox_pointer.rotation = 0.0
	_update_pointer_label(lootbox_pointer, "Lootbox")

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
