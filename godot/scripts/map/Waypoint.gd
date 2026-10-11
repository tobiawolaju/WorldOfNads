extends Control


## Some margin to keep the marker away from the screen's corners.
const MARGIN = 8

## The waypoint's text.
@export var text: String = "Waypoint":
	set(value):
		text = value
		if label != null:
			label.text = value

## If `true`, the waypoint sticks to the viewport's edges when moving off-screen.
@export var sticky: bool = true

@export var camera :Camera3D
@onready var parent := get_parent()
@onready var label: Label = $Label
@onready var marker: TextureRect = $Marker

var _last_camera_position: Vector3 = Vector3.INF
var _last_parent_position: Vector3 = Vector3.INF
var _last_camera_basis_z: Vector3 = Vector3.INF
var _last_viewport_size: Vector2i = Vector2i.ZERO

var _update_timer: float = 0.0
const UPDATE_INTERVAL: float = 0.066 # ~15 FPS for UI labels


func _ready() -> void:
	self.text = text
	assert(parent is Node3D, "The waypoint's parent node must inherit from Node3D.")


func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer < UPDATE_INTERVAL:
		return
	_update_timer = 0.0

	if camera == null or not is_instance_valid(camera) or not camera.current:
		# If the camera we have isn't the current one, get the current camera.
		camera = get_viewport().get_camera_3d()
	
	if camera == null:
		return

	var parent_position: Vector3 = parent.global_transform.origin
	var camera_transform := camera.global_transform
	var camera_position := camera_transform.origin
	var viewport_base_size: Vector2i = get_viewport().size
	var camera_basis_z := camera_transform.basis.z

	if parent_position.distance_squared_to(_last_parent_position) < 0.000001 \
			and camera_position.distance_squared_to(_last_camera_position) < 0.000001 \
			and camera_basis_z.distance_squared_to(_last_camera_basis_z) < 0.000001 \
			and viewport_base_size == _last_viewport_size:
		return

	_last_parent_position = parent_position
	_last_camera_position = camera_position
	_last_camera_basis_z = camera_basis_z
	_last_viewport_size = viewport_base_size

	# We would use "camera.is_position_behind(parent_position)", except
	# that it also accounts for the near clip plane, which we don't want.
	var is_behind := camera_basis_z.dot(parent_position - camera_position) > 0

	# Fade the waypoint when the camera gets close.
	var distance := camera_position.distance_to(parent_position)
	modulate.a = clamp(remap(distance, 0, 2, 0, 1), 0, 1 )

	var unprojected_position := camera.unproject_position(parent_position)
	if not sticky:
		# For non-sticky waypoints, we don't need to clamp and calculate
		# the position if the waypoint goes off screen.
		position = unprojected_position
		visible = not is_behind
		return

	# We need to handle the axes differently.
	# For the screen's X axis, the projected position is useful to us
	# but we need to force it to the side if it's also behind.
	if is_behind:
		if unprojected_position.x < viewport_base_size.x / 2.0:
			unprojected_position.x = viewport_base_size.x - MARGIN
		else:
			unprojected_position.x = MARGIN

	# For the screen's Y axis, the projected position is NOT useful to us
	# because we don't want to indicate to the user that they need to look
	# up or down to see something behind them. Instead we derive the Y from
	# the waypoint's camera-relative direction with the same planar
	# perspective projection that unproject_position uses: the waypoint's
	# height above the camera's forward axis over its forward distance, scaled
	# by the focal length. This makes the marker slide along the top/bottom
	# edges (and into the corners) exactly like the X slides along the
	# left/right edges, so it tracks vertical offsets instead of only moving
	# sideways. The signed forward distance keeps behind targets bounded near
	# the centre instead of exploding to an edge.
	var to_parent := parent_position - camera_position
	var cam_up := camera_transform.basis.y
	var cam_forward := -camera_basis_z
	var focal := (viewport_base_size.y * 0.5) / tan(_vertical_fov_rad(viewport_base_size) * 0.5)
	var fwd := to_parent.dot(cam_forward)
	var denom := fwd if absf(fwd) > 0.0001 else 0.0001
	unprojected_position.y = viewport_base_size.y * 0.5 - (to_parent.dot(cam_up) / denom) * focal

	position = Vector2(
			clamp(unprojected_position.x, MARGIN, viewport_base_size.x - MARGIN),
			clamp(unprojected_position.y, MARGIN, viewport_base_size.y - MARGIN)
		)

	label.visible = true
	rotation = 0
	# Used to display a diagonal arrow when the waypoint is displayed in
	# one of the screen corners.
	var overflow := 0

	if position.x <= MARGIN:
		# Left overflow.
		overflow = int(-TAU / 8.0)
		label.visible = false
		rotation = TAU / 4.0
	elif position.x >= viewport_base_size.x - MARGIN:
		# Right overflow.
		overflow = int(TAU / 8.0)
		label.visible = false
		rotation = TAU * 3.0 / 4.0

	if position.y <= MARGIN:
		# Top overflow.
		label.visible = false
		rotation = TAU / 2.0 + overflow
	elif position.y >= viewport_base_size.y - MARGIN:
		# Bottom overflow.
		label.visible = false
		rotation = -overflow


# The camera's vertical field of view in radians. Godot's `fov` property is the
# vertical FOV when keep_aspect is KEEP_HEIGHT and the horizontal FOV when it is
# KEEP_WIDTH, so this normalises it to the vertical value the planar projection
# above needs.
func _vertical_fov_rad(viewport_size: Vector2i) -> float:
	var fov_rad := deg_to_rad(camera.fov)
	if camera.keep_aspect == Camera3D.KEEP_HEIGHT:
		return fov_rad
	var aspect := float(viewport_size.x) / maxf(float(viewport_size.y), 1.0)
	return 2.0 * atan(tan(fov_rad * 0.5) / aspect)
