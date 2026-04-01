extends CharacterBody3D

# --- CONSTANTS ---
const GRAVITY: float = 9.8
const JUMP_VELOCITY: float = 4.5
const SPEED: float = 4.5
const DEADZONE := 0.12
const PICKUP_REQUEST_COOLDOWN_MS := 150
const STEAL_RADIUS := 2.5
const POS_SCALE := 100.0
const ROT_SCALE := 1000.0
const ANIM_NAME_TO_ID := {
	"idle": 0,
	"running": 1
}

# --- INPUT VARIABLES ---
var gamepad_index := 0

# --- PICKUP VARIABLES ---
var held_object: RigidBody3D = null
@export var hold_distance: float = 0.25
@export var hold_height: float = 1.5
var last_pickup_request_ms: int = 0

# --- CAMERA & ZOOM SETTINGS ---
@export var camera_distance: float = 4.0
@export var camera_smoothness: float = 8.0
@export var min_pitch: float = deg_to_rad(0.0)
@export var max_pitch: float = deg_to_rad(60.0)
@export var min_zoom: float = 2.0
@export var max_zoom: float = 10.0
@export var altitude_zoom_factor: float = 1.5

# --- NODE REFERENCES ---
@onready var camera: Camera3D = get_node("../Camera3D")

# [CHANGED] Replaced RayCast3D with Area3D
@onready var pickup_area: Area3D = $Area3D

@onready var name_label: Label3D = $Label3D
@onready var anim_run: AnimationPlayer = $running
@onready var anim_idle: AnimationPlayer = $idle
@onready var mesh: Skeleton3D = $Skeleton3D

# --- STATE VARIABLES ---
var root: Node = null
var is_local: bool = false
var velocity_y: float = 0.0
var cam_rot_x: float = deg_to_rad(30)
var cam_rot_y: float = 0.0
var current_animation: String = "idle"
var ignored_touch_indices := {}
var active_camera_index := -1
var touch_joystick: Node = null
var network_tick_timer: float = 0.0
var network_heartbeat_timer: float = 0.0
const NETWORK_TICK_ACTIVE: float = 0.10
const NETWORK_TICK_IDLE: float = 0.33
const NETWORK_HEARTBEAT: float = 1.0
var _last_payload_signature := ""

var player_id: String = "" :
	set(new_id):
		player_id = new_id
		_refresh_name_label()

var display_name: String = "" :
	set(new_name):
		display_name = new_name.strip_edges()
		_refresh_name_label()

func _ready() -> void:
	camera_distance = clamp(camera_distance, min_zoom, max_zoom)
	_play_idle()
	_refresh_touch_joystick()

	if not pickup_area:
		print("ERROR: $Area3D node not found! Please add an Area3D with a CollisionShape to the player.")

func _process(delta: float):
	_refresh_name_label()
	_update_local_chicken_visual(delta)

func _refresh_name_label() -> void:
	if not name_label:
		return
	var resolved_name = display_name
	if resolved_name == "":
		resolved_name = player_id.substr(0, 8)
	name_label.text = resolved_name

func _input(event: InputEvent) -> void:
	if not is_local:
		return

	# --- 1. MOUSE CAMERA CONTROLS ---
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not DisplayServer.is_touchscreen_available():
		cam_rot_y -= event.relative.x * 0.005
		cam_rot_x = clamp(cam_rot_x + event.relative.y * 0.005, min_pitch, max_pitch)

	# Mouse Wheel Zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera_distance = clamp(camera_distance - 0.5, min_zoom, max_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera_distance = clamp(camera_distance + 0.5, min_zoom, max_zoom)

	# --- 2. PICKUP CONTROLS ---
	if _is_movement_allowed() and event.is_action_pressed("pickup"):
		if _is_local_holding_chicken():
			_drop_object()
		else:
			_try_pickup()

func _unhandled_input(event: InputEvent) -> void:
	if not is_local:
		return

	if touch_joystick == null:
		_refresh_touch_joystick()

	var viewport = get_viewport().get_visible_rect()
	var size = viewport.size

	if event is InputEventScreenTouch:
		if touch_joystick and touch_joystick.call("claims_touch", event.index):
			return
		if event.pressed:
			if _is_touch_on_joystick_area(event.position, size):
				ignored_touch_indices[event.index] = true
				return
			if active_camera_index == -1:
				active_camera_index = event.index
		else:
			if ignored_touch_indices.has(event.index):
				ignored_touch_indices.erase(event.index)
				return
			if event.index == active_camera_index:
				active_camera_index = -1
		return

	if event is InputEventScreenDrag:
		if ignored_touch_indices.has(event.index):
			return
		if touch_joystick and touch_joystick.call("claims_touch", event.index):
			return
		# Claim camera on first valid drag too (some devices skip touch-start to _unhandled_input).
		if active_camera_index == -1:
			active_camera_index = event.index
		elif event.index != active_camera_index:
			return
		cam_rot_y -= event.relative.x * 0.0045
		cam_rot_x = clamp(cam_rot_x + event.relative.y * 0.0045, min_pitch, max_pitch)

func _physics_process(delta: float) -> void:
	if not is_local:
		return

	var input_dir := Vector2.ZERO
	var movement_allowed := _is_movement_allowed()

	if movement_allowed:
		if Input.is_action_pressed("move_forward"): input_dir.y += 1
		if Input.is_action_pressed("move_back"): input_dir.y -= 1
		if Input.is_action_pressed("move_left"): input_dir.x -= 1
		if Input.is_action_pressed("move_right"): input_dir.x += 1

	var lx := Input.get_joy_axis(gamepad_index, JOY_AXIS_LEFT_X)
	var ly := Input.get_joy_axis(gamepad_index, JOY_AXIS_LEFT_Y)

	if movement_allowed:
		if abs(lx) > DEADZONE: input_dir.x += lx
		if abs(ly) > DEADZONE: input_dir.y -= ly
	input_dir = input_dir.normalized()

	if not is_on_floor():
		velocity_y -= GRAVITY * delta
	else:
		velocity_y = 0
		if movement_allowed and (Input.is_action_just_pressed("jump") or Input.is_joy_button_pressed(gamepad_index, JOY_BUTTON_A)):
			velocity_y = JUMP_VELOCITY

	# Movement direction relative to Camera
	var cam_basis = camera.global_transform.basis
	var forward = -cam_basis.z
	var right = cam_basis.x

	forward.y = 0
	right.y = 0
	forward = forward.normalized()
	right = right.normalized()

	var move_direction = forward * input_dir.y + right * input_dir.x

	velocity.x = move_direction.x * SPEED
	velocity.z = move_direction.z * SPEED
	velocity.y = velocity_y
	move_and_slide()

	if move_direction.length() > 0.05:
		var target_yaw := atan2(move_direction.x, move_direction.z)
		mesh.rotation.y = lerp_angle(mesh.rotation.y, target_yaw, delta * 10.0)

	_handle_camera_gamepad(delta)
	_update_camera(delta)
	_handle_animations(move_direction)

	var net_active: bool = (move_direction.length() > 0.05) or _is_local_holding_chicken() or (current_animation == "running")
	network_tick_timer += delta
	network_heartbeat_timer += delta
	var tick_window := NETWORK_TICK_ACTIVE if net_active else NETWORK_TICK_IDLE
	var force_heartbeat := network_heartbeat_timer >= NETWORK_HEARTBEAT
	if network_tick_timer >= tick_window or force_heartbeat:
		_send_state_to_server(force_heartbeat)
		network_tick_timer = 0.0
		if force_heartbeat:
			network_heartbeat_timer = 0.0

# --- PICKUP LOGIC (USING AREA3D) ---
func _try_pickup():
	if not pickup_area:
		return

	var now = Time.get_ticks_msec()
	if now - last_pickup_request_ms < PICKUP_REQUEST_COOLDOWN_MS:
		return
	last_pickup_request_ms = now

	# Try Area3D overlap first (works when chicken is on the ground).
	var bodies = pickup_area.get_overlapping_bodies()
	var best_target: RigidBody3D = null
	var shortest_dist: float = 999.0

	for body in bodies:
		if body is RigidBody3D and body != self and body.is_in_group("pickup_items"):
			var dist = global_position.distance_to(body.global_position)
			if dist < shortest_dist:
				shortest_dist = dist
				best_target = body

	# Fallback: when the chicken is held by someone else, its frozen RigidBody3D
	# may not register in Area3D overlaps.  Do a direct distance check instead.
	if best_target == null and root and root.has_method("get_chicken_node"):
		var chicken = root.get_chicken_node()
		if chicken != null and chicken.is_in_group("pickup_items"):
			var dist = global_position.distance_to(chicken.global_position)
			if dist <= STEAL_RADIUS:
				best_target = chicken

	if best_target and root and root.ws and root.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		root.ws.send(MsgPack.pack({
			"type": "pickup_request",
			"item_id": best_target.name
		}))

func _drop_object():
	if not _is_local_holding_chicken():
		return
	if not root or not root.ws:
		return
	if root.ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	var throw_dir = -camera.global_transform.basis.z
	root.ws.send(MsgPack.pack({
		"type": "drop_request",
		"throw_x": throw_dir.x * 5.0,
		"throw_y": max(1.0, throw_dir.y * 5.0),
		"throw_z": throw_dir.z * 5.0
	}))

func _is_local_holding_chicken() -> bool:
	if not root or not root.has_method("is_local_player_holding_chicken"):
		return false
	return root.is_local_player_holding_chicken()

func _update_local_chicken_visual(delta: float) -> void:
	if not is_local or not _is_local_holding_chicken():
		return
	if not root or not root.has_method("get_chicken_node"):
		return

	var chicken = root.get_chicken_node()
	if chicken == null:
		return

	var target_pos = global_position + (-camera.global_transform.basis.z * 0.9)
	target_pos.y += 1.0
	chicken.global_position = chicken.global_position.lerp(target_pos, min(1.0, 16.0 * delta))

# --- CAMERA LOGIC ---
func _handle_camera_gamepad(delta: float) -> void:
	var rx := Input.get_joy_axis(gamepad_index, JOY_AXIS_RIGHT_X)
	var ry := Input.get_joy_axis(gamepad_index, JOY_AXIS_RIGHT_Y)

	if abs(rx) > DEADZONE:
		cam_rot_y -= rx * 0.05 * delta * 60
	if abs(ry) > DEADZONE:
		cam_rot_x = clamp(cam_rot_x + ry * 0.05 * delta * 60, min_pitch, max_pitch)

func _update_camera(delta: float) -> void:
	var target_pos: Vector3 = global_transform.origin + Vector3(0, 1.5, 0)
	cam_rot_x = clamp(cam_rot_x, min_pitch, max_pitch)

	var altitude_zoom = clamp(global_transform.origin.y * altitude_zoom_factor, 0.0, max_zoom - min_zoom)
	var effective_camera_distance = clamp(camera_distance + altitude_zoom, min_zoom, max_zoom)

	var cam_offset: Vector3 = Vector3(
		sin(cam_rot_y) * cos(cam_rot_x),
		sin(cam_rot_x),
		cos(cam_rot_y) * cos(cam_rot_x)
	) * effective_camera_distance

	var desired_pos: Vector3 = target_pos + cam_offset

	var space_state = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(target_pos, desired_pos)
	query.exclude = [self]
	var hit = space_state.intersect_ray(query)

	if hit and hit.has("position"):
		desired_pos = hit.position

	camera.global_position = camera.global_position.lerp(desired_pos, delta * camera_smoothness)
	camera.look_at(target_pos, Vector3.UP)

# --- ANIMATION & NETWORK ---
func _quantize_pos(value: float) -> int:
	return int(round(value * POS_SCALE))

func _quantize_rot(value: float) -> int:
	return int(round(value * ROT_SCALE))

func _build_payload_signature(payload: Dictionary) -> String:
	return JSON.stringify(payload)

func _send_state_to_server(force_send := false) -> void:
	if not root or not root.ws:
		return
	if root.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var payload = {
			"type": "update_state",
			"qx": _quantize_pos(global_transform.origin.x),
			"qy": _quantize_pos(global_transform.origin.y),
			"qz": _quantize_pos(global_transform.origin.z),
			"qrot": _quantize_rot(mesh.rotation.y),
			"anim_id": int(ANIM_NAME_TO_ID.get(current_animation, 0))
		}

		# Only holder is allowed to stream chicken pose to server.
		if _is_local_holding_chicken() and root.has_method("build_local_chicken_payload"):
			var chicken_payload = root.build_local_chicken_payload(global_position, -camera.global_transform.basis.z, mesh.rotation.y)
			if chicken_payload != null:
				payload["chicken"] = {
					"qx": _quantize_pos(float(chicken_payload.get("x", 0.0))),
					"qy": _quantize_pos(float(chicken_payload.get("y", 0.0))),
					"qz": _quantize_pos(float(chicken_payload.get("z", 0.0))),
					"qrot": _quantize_rot(float(chicken_payload.get("rotation_y", 0.0)))
				}

		var signature = _build_payload_signature(payload)
		if not force_send and signature == _last_payload_signature:
			return
		_last_payload_signature = signature
		root.ws.send(MsgPack.pack(payload))

func set_animation_state(new_state: String):
	if is_local: return
	if new_state == current_animation: return
	current_animation = new_state
	if new_state == "running":
		_play_running()
	else:
		_play_idle()

func _handle_animations(move_dir: Vector3) -> void:
	if not is_local: return
	if not _is_movement_allowed():
		current_animation = "idle"
		_play_idle()
		return
	if move_dir.length() > 0.1:
		current_animation = "running"
		_play_running()
	else:
		current_animation = "idle"
		_play_idle()

func _is_movement_allowed() -> bool:
	if root and root.has_method("is_match_running"):
		return root.is_match_running()
	return true

func _play_running() -> void:
	if anim_idle.is_playing():
		anim_idle.stop()
	if not anim_run.is_playing():
		anim_run.play("running")

func _play_idle() -> void:
	if anim_run.is_playing():
		anim_run.stop()
	if not anim_idle.is_playing():
		anim_idle.play("idle")

func _is_touch_on_joystick_area(pos: Vector2, size: Vector2) -> bool:
	# Always use joystick script's own zone config to avoid mismatches.
	if touch_joystick and touch_joystick.has_method("is_joystick_area_screen"):
		return bool(touch_joystick.call("is_joystick_area_screen", pos, size))
	# Fallback: bottom-center half width, quarter height.
	var is_portrait := size.y > size.x
	var zone_width := size.x * 0.5
	var zone_height := size.y * (0.25 if is_portrait else 0.25)
	var zone_left := (size.x - zone_width) * 0.5
	var zone_right := zone_left + zone_width
	return pos.x >= zone_left and pos.x <= zone_right and pos.y >= (size.y - zone_height)

func _refresh_touch_joystick() -> void:
	touch_joystick = get_tree().get_first_node_in_group("touch_joystick")
