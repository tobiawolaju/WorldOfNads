extends HBoxContainer

const RIGHT_MARGIN := 217.5
const BOTTOM_MARGIN := 217.5
const PORTRAIT_RATIO := 1.4

@export var action_button: Button
@export var jump_button: Button
@export var slide_button: Button

var _touch_indices: Dictionary = {}
var _animating_buttons: Dictionary = {}
var _cached_local_player: Node = null

# --- POWER-UP RING ---
const RING_WIDTH := 4.0
const RING_MARGIN := 4.0            # how far the ring sits outside the button
const RING_TRACK_ALPHA := 0.12      # faint full circle behind the countdown
const RING_PULSE_SECONDS := 2.0     # pulse the ring during the last seconds

# The visible caption on the Action button is a Label child named "action"
# (the Button's own text property is covered by it). Captured in _ready so the
# authored default can be restored when no power-up is held.
var _action_caption: Label = null
var _action_caption_default: String = ""
var _action_caption_default_color: Color = Color.WHITE

## Radial countdown drawn around the Action button while a timed power-up runs.
var _action_ring: Control = null
var _ring_active: bool = false
var _ring_remaining: float = 0.0
var _ring_duration: float = 0.0
var _ring_color: Color = Color.WHITE

## The power-up the player is HOLDING (label/color), pushed by player.gd.
## Kept so the caption can be rebuilt whenever the running effect starts/ends.
var _held_label: String = ""
var _held_color: Color = Color.WHITE
## How long the held pickup's effect would run (0 when it has no timed effect).
## While > 0 and no effect is running, the ring draws full as a "ready" signal.
var _held_duration: float = 0.0
var _held_active: bool = false
var _hold_pulse: float = 0.0
## The TIMED power-up that is running, polled from the local player each frame.
var _active: Dictionary = {}
## Last written caption, so identical frames don't re-set text/color overrides.
var _last_caption_text: String = ""
var _last_caption_color: Color = Color.WHITE

## Shows the currently held power-up on the Action button, or clears it when the
## label is empty. Called by player.gd whenever a pickup is grabbed or dropped.
## `duration` is how long the held pickup's effect would run; while > 0 the HUD
## draws the countdown ring as a full "ready" ring while it is carried.
func show_power_up(label: String, color: Color, duration: float = 0.0) -> void:
	var became_active := (label != "" and _held_label == "")
	_held_label = label
	_held_color = color
	_held_duration = duration
	_held_active = (label != "")
	_update_active_power_up()
	_refresh_action_caption()
	if became_active:
		_pop_action()

# The caption reflects the held power-up if there is one, otherwise the running
# timed power-up, otherwise the authored default (GRAB).
func _refresh_action_caption() -> void:
	var label := _held_label
	var color := _held_color
	if label == "" and not _active.is_empty():
		label = str(_active.get("label", ""))
		color = _active.get("color", color)
	var text := _action_caption_default if label == "" else _stack_vertically(label)
	var tint := _action_caption_default_color if label == "" else color
	if text == _last_caption_text and tint == _last_caption_color:
		return
	_last_caption_text = text
	_last_caption_color = tint
	if _action_caption != null and is_instance_valid(_action_caption):
		_action_caption.text = text
		_action_caption.add_theme_color_override("font_color", tint)
		return
	if action_button != null:
		action_button.text = text
		action_button.add_theme_color_override("font_color", tint)

# Polls the local player for the running timed power-up and picks what the ring
# should show: the depleting countdown of a running effect, or a full "ready"
# ring while a pickup with a timed effect is being held.
func _update_active_power_up() -> void:
	_active = {}
	if _cached_local_player != null \
	and is_instance_valid(_cached_local_player) \
	and _cached_local_player.has_method("get_active_power_up"):
		_active = _cached_local_player.get_active_power_up()

	var was_active := _ring_active
	if not _active.is_empty():
		# A timed effect is running: its countdown takes priority over held.
		_ring_remaining = float(_active.get("remaining", 0.0))
		_ring_duration = maxf(float(_active.get("duration", 0.0)), 0.0001)
		_ring_color = _active.get("color", Color.WHITE)
		_ring_active = true
	elif _held_duration > 0.0:
		# Holding a pickup whose effect is timed: full ring as "ready to use".
		_ring_remaining = _held_duration
		_ring_duration = _held_duration
		_ring_color = _held_color
		_ring_active = true
	else:
		_ring_remaining = 0.0
		_ring_duration = 0.0
		_ring_active = false
	# Redraw while running (for the pulse) and once more when it ends to clear.
	if _action_ring != null and (_ring_active or was_active):
		_action_ring.queue_redraw()

# Draws the countdown ring around the Action button. The button is a rounded
# rectangle (its styleboxes have corner_radius 50 and the container can stretch
# it), so instead of a perfect circle this draws the same rounded-rect outline,
# depleting clockwise from the top and pulsing as it runs out. No textures.
func _draw_action_ring() -> void:
	# Draw nothing when idle; the final redraw clears the ring.
	if _action_ring == null or not _ring_active:
		return
	var ring_rect := _ring_outline_rect()
	if ring_rect.size.x <= 0.0 or ring_rect.size.y <= 0.0:
		return
	var points := _rounded_ring_points(ring_rect, _ring_outline_corner())
	if points.size() < 2:
		return
	# Faint full outline as the track.
	var track := points.duplicate()
	track.append(points[0])
	_action_ring.draw_polyline(track, Color(1.0, 1.0, 1.0, RING_TRACK_ALPHA), RING_WIDTH, true)
	var fraction := clampf(_ring_remaining / _ring_duration, 0.0, 1.0)
	if fraction <= 0.0:
		return
	var color := _ring_color
	if _ring_remaining <= RING_PULSE_SECONDS:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.02)
		color.a = lerpf(0.35, 1.0, pulse)
	# Only the portion of the outline that is still left, from the top-center.
	var count := int(round(points.size() * fraction))
	if count <= 0:
		return
	_action_ring.draw_polyline(points.slice(0, count + 1), color, RING_WIDTH, true)

# Centerline of the ring stroke: the ring Control's rect, inset by half the
# stroke width so the outline itself sits just outside the button.
func _ring_outline_rect() -> Rect2:
	var inset := RING_WIDTH * 0.5
	return Rect2(Vector2(inset, inset), _action_ring.size - Vector2(RING_WIDTH, RING_WIDTH))

# Corner radius for the outline: the button's corner radius grown by the ring
# margin so it stays parallel to the button edges, clamped so the corners can
# never overlap. On a (stretched) round button this collapses to a circle,
# matching the visible button shape.
func _ring_outline_corner() -> float:
	var rect := _ring_outline_rect()
	var corner := _button_corner_radius() + RING_MARGIN - RING_WIDTH * 0.5
	return clampf(corner, 0.0, minf(rect.size.x, rect.size.y) * 0.5)

# Reads the corner radius the Action button actually draws with, so the ring
# follows the same shape even if the button gets resized by its container.
func _button_corner_radius() -> float:
	if action_button == null:
		return 0.0
	var sb := action_button.get_theme_stylebox("normal")
	if sb is StyleBoxFlat:
		return float(sb.corner_radius_top_left)
	return 0.0

# Samples the rounded-rect perimeter clockwise starting at the top-center, so
# the remaining-time slice can be carved off the front of the array.
func _rounded_ring_points(rect: Rect2, corner: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var top_mid := Vector2((rect.position.x + rect.end.x) * 0.5, rect.position.y)
	pts.append(top_mid)
	if corner <= 0.0:
		_line_samples(pts, top_mid, Vector2(rect.end.x, rect.position.y), 4.0)
		_line_samples(pts, Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.end.y), 4.0)
		_line_samples(pts, Vector2(rect.end.x, rect.end.y), Vector2(rect.position.x, rect.end.y), 4.0)
		_line_samples(pts, Vector2(rect.position.x, rect.end.y), Vector2(rect.position.x, rect.position.y), 4.0)
		_line_samples(pts, Vector2(rect.position.x, rect.position.y), top_mid, 4.0)
		return pts
	var x0 := rect.position.x
	var y0 := rect.position.y
	var x1 := rect.end.x
	var y1 := rect.end.y
	_line_samples(pts, top_mid, Vector2(x1 - corner, y0), 4.0)
	_arc_samples(pts, Vector2(x1 - corner, y0 + corner), corner, -PI * 0.5, 0.0)
	_line_samples(pts, Vector2(x1, y0 + corner), Vector2(x1, y1 - corner), 4.0)
	_arc_samples(pts, Vector2(x1 - corner, y1 - corner), corner, 0.0, PI * 0.5)
	_line_samples(pts, Vector2(x1 - corner, y1), Vector2(x0 + corner, y1), 4.0)
	_arc_samples(pts, Vector2(x0 + corner, y1 - corner), corner, PI * 0.5, PI)
	_line_samples(pts, Vector2(x0, y1 - corner), Vector2(x0, y0 + corner), 4.0)
	_arc_samples(pts, Vector2(x0 + corner, y0 + corner), corner, PI, PI * 1.5)
	_line_samples(pts, Vector2(x0 + corner, y0), top_mid, 4.0)
	return pts

# Appends points along a straight segment; `from` is already in the list and
# `to` is appended. Zero-length segments are skipped (overlapping corners).
func _line_samples(pts: PackedVector2Array, from: Vector2, to: Vector2, max_step: float) -> void:
	var dist := from.distance_to(to)
	if dist <= 0.0:
		return
	var n := maxi(1, int(ceil(dist / max_step)))
	for i in range(1, n + 1):
		pts.append(from.lerp(to, float(i) / float(n)))

# Appends points along a quarter-circle corner arc, same angular direction as
# draw_arc (clockwise on screen, starting at `from_angle`).
func _arc_samples(pts: PackedVector2Array, center: Vector2, radius: float, from_angle: float, to_angle: float) -> void:
	var steps := 12
	for i in range(1, steps + 1):
		var a := lerpf(from_angle, to_angle, float(i) / float(steps))
		pts.append(center + Vector2(cos(a), sin(a)) * radius)

# Puts every non-space character on its own line so a name like "SPEED" renders
# as a vertical stack matching the scene's authored "G\nR\nA\nB".
func _stack_vertically(text: String) -> String:
	var lines := PackedStringArray()
	for i in text.length():
		var c: String = text[i]
		if c.strip_edges() != "":
			lines.append(c)
	return "\n".join(lines)

func _ready() -> void:
	get_viewport().size_changed.connect(_reposition)
	_reposition()
	if action_button != null:
		_action_caption = action_button.get_node_or_null("action") as Label
		if _action_caption != null:
			_action_caption_default = _action_caption.text
			_action_caption_default_color = _action_caption.get_theme_color("font_color")
		_create_action_ring()
		action_button.pivot_offset = action_button.size * 0.5

# Builds the countdown ring and parents it to the Action button. Created in code
# so hud.tscn needs no new node and the ring inherits the button's placement.
func _create_action_ring() -> void:
	if _action_ring != null:
		return
	_action_ring = Control.new()
	_action_ring.name = "PowerUpRing"
	_action_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_action_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_action_ring.offset_left = -RING_MARGIN
	_action_ring.offset_top = -RING_MARGIN
	_action_ring.offset_right = RING_MARGIN
	_action_ring.offset_bottom = RING_MARGIN
	_action_ring.draw.connect(_draw_action_ring)
	action_button.add_child(_action_ring)

func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch

		if touch.pressed:
			for entry in [
				[action_button, &"pickup"],
				[jump_button, &"jump"],
				[slide_button, &"slide"]
			]:
				var button: Button = entry[0]
				var action_name: StringName = entry[1]

				if button == null:
					continue

				if _touch_indices.get(action_name, -1) == -1 \
				and button.get_global_rect().has_point(touch.position):

					_touch_indices[action_name] = touch.index

					button.button_pressed = true

					_play_press_animation(button)

					_fire_action(action_name, true)

					get_viewport().set_input_as_handled()
					return

		else:
			for action_name in _touch_indices:
				if _touch_indices.get(action_name) == touch.index:
					var button = _get_button(action_name)

					if button != null:
						button.button_pressed = false
						button.scale = Vector2.ONE

					_touch_indices.erase(action_name)

					_fire_action(action_name, false)

					get_viewport().set_input_as_handled()
					return

	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag

		for action_name in _touch_indices:
			if _touch_indices.get(action_name) == drag.index:

				var button = _get_button(action_name)

				if button == null \
				or not button.get_global_rect().has_point(drag.position):

					if button != null:
						button.button_pressed = false
						button.scale = Vector2.ONE

					_touch_indices.erase(action_name)
					_fire_action(action_name, false)

				return

func _play_press_animation(button: Button) -> void:
	if button == null:
		return

	# Prevent retriggering while already animating
	if _animating_buttons.get(button, false):
		return

	_animating_buttons[button] = true

	button.scale = Vector2.ONE

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_property(
		button,
		"scale",
		Vector2(0.8, 0.8),
		0.08
	)

	tween.tween_property(
		button,
		"scale",
		Vector2.ONE,
		0.12
	)

	tween.finished.connect(func():
		_animating_buttons.erase(button)
		button.scale = Vector2.ONE
	)

func _get_button(action_name: StringName) -> Button:
	match action_name:
		&"pickup":
			return action_button
		&"jump":
			return jump_button
		&"slide":
			return slide_button

	return null

func _fire_action(action_name: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = pressed
	Input.parse_input_event(event)

func _process(_delta: float) -> void:
	if action_button == null:
		return
	if _cached_local_player == null or not is_instance_valid(_cached_local_player):
		_cached_local_player = get_tree().get_first_node_in_group("local_player")

	var target_alpha := 0.5
	if _cached_local_player != null \
	and _cached_local_player.has_method("get_pickup_cooldown") \
	and _cached_local_player.get_pickup_cooldown() <= 0.0:
		target_alpha = 1.0

	# self_modulate (not modulate): the button's own drawing fades, but the
	# child caption label keeps full opacity instead of fading with it.
	if action_button.self_modulate.a != target_alpha:
		action_button.self_modulate.a = target_alpha

	_update_active_power_up()
	_refresh_action_caption()

	if action_button != null and _held_active and not _ring_active:
		_hold_pulse += _delta * 3.0
		var t := 0.4 + 0.2 * sin(_hold_pulse)
		action_button.modulate = Color(_held_color.r, t, _held_color.b, t)
	else:
		if action_button != null:
			action_button.modulate = Color.WHITE

func _pop_action() -> void:
	if action_button == null:
		return
	var tw := create_tween()
	tw.tween_property(action_button, "scale", Vector2(1.08, 1.08), 0.05).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(action_button, "scale", Vector2.ONE, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _reposition() -> void:
	var viewport_size := get_viewport().get_visible_rect().size

	var is_portrait := viewport_size.y > viewport_size.x * PORTRAIT_RATIO

	visible = not is_portrait

	if is_portrait:
		return

	var target: Control = self
	var parent_control := get_parent() as Control

	if parent_control != null:
		target = parent_control

	target.set_anchors_preset(Control.PRESET_TOP_LEFT)

	target.position = Vector2(
		viewport_size.x - RIGHT_MARGIN,
		viewport_size.y - BOTTOM_MARGIN
	)
