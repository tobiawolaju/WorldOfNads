# Extends CanvasItem rather than Label so the effect can be attached to any node that
# draws, not just text. It only touches visible, modulate.a and position, which Control
# and Node2D both have. Attach it to a Label for the text case, or to a ColorRect to
# fade a panel.
extends CanvasItem

signal text_finished

@export var play_on_ready: bool = true
@export var fade_in_duration: float = 0.6
@export var fade_out_delay: float = 5.0 # seconds the text stays fully visible before fading out
@export var fade_out_duration: float = 0.8

## Seconds the slide takes. Kept separate from fade_in_duration so the travel can be
## slower or faster than the fade. Set to 0 to run the slide in step with the fade.
@export_range(0.0, 5.0, 0.05) var slide_duration: float = 0.0

## Easing curve for the slide. TRANS_BACK overshoots the target and settles back, which
## is what produces the bounce on arrival. TRANS_ELASTIC oscillates several times instead.
## TRANS_CUBIC is a smooth decelerate with no overshoot.
@export var slide_transition: Tween.TransitionType = Tween.TRANS_BACK
@export var slide_ease: Tween.EaseType = Tween.EASE_OUT

## Distance and direction the node travels while fading in, in pixels. Positive Y slides
## up from below, negative Y drops in from above, negative X slides in from the left. Set
## to (0, 0) to disable.
@export var slide_offset: Vector2 = Vector2(0, 60)

## When enabled, slide_offset is treated as a fraction of the viewport instead of a pixel
## count, which is what you want for an entrance that must start fully off screen
## regardless of resolution. A value of -1 on X means "one full screen width to the left",
## so the node begins out of view at any window size. Ignored when off, in which case
## slide_offset is used as raw pixels.
@export var slide_offset_is_screen_fraction: bool = false

## The slide only animates nodes that actually have a position. CanvasItem does not
## require one, so this is checked rather than assumed.
var _slide_supported: bool = false

func _ready() -> void:
	_slide_supported = "position" in self
	if not play_on_ready:
		return
	play()

func play() -> void:
	visible = true
	modulate.a = 0.0

	# Remember where the node lives in the scene so the slide always starts relative to
	# its real resting place. Captured on the first play only, otherwise a replay would
	# treat the already-offset position as the new rest and the node would drift.
	if not has_meta("textfx_rest_position"):
		set_meta("textfx_rest_position", _get_position())

	var rest: Vector2 = get_meta("textfx_rest_position")
	var offset := _resolve_slide_offset()
	var start: Vector2 = rest + offset
	_set_position(start)

	if fade_in_duration > 0.0:
		var fade_in := create_tween()
		fade_in.set_parallel(true)
		fade_in.tween_property(self, "modulate:a", 1.0, fade_in_duration)
		if _slide_supported and offset != Vector2.ZERO:
			# slide_duration of 0 means "match the fade", so the slide still stays in step
			# by default. Running them as parallel tweeners on one tween means the pair
			# cannot drift apart even when their durations differ.
			var travel_time := slide_duration if slide_duration > 0.0 else fade_in_duration
			fade_in.tween_property(self, "position", rest, travel_time) \
				.set_trans(slide_transition).set_ease(slide_ease)
		await fade_in.finished
	else:
		modulate.a = 1.0
		_set_position(rest)

	if fade_out_delay > 0.0:
		await get_tree().create_timer(fade_out_delay).timeout
	if fade_out_duration > 0.0:
		var fade_out := create_tween()
		fade_out.tween_property(self, "modulate:a", 0.0, fade_out_duration)
		await fade_out.finished
	visible = false
	text_finished.emit()

# Turns slide_offset into pixels. In screen-fraction mode the value is scaled by the
# viewport size, so -1.0 on X puts the node exactly one screen width to the left and it
# starts out of view at any resolution. The viewport is only read when that mode is on,
# so the common pixel case costs nothing.
func _resolve_slide_offset() -> Vector2:
	if not slide_offset_is_screen_fraction:
		return slide_offset
	var viewport_size := get_viewport_rect().size
	return Vector2(slide_offset.x * viewport_size.x, slide_offset.y * viewport_size.y)

# position is declared on Control and Node2D, not on CanvasItem, so naming it directly
# would not compile against this base class even behind a runtime check. GDScript
# resolves identifiers when the script is parsed, so the guard cannot hide it. These two
# helpers go through Object.get/set with the name as a string instead, which is resolved
# at runtime and is a no-op on a CanvasItem that has no position.
func _get_position() -> Vector2:
	return get("position") if _slide_supported else Vector2.ZERO

func _set_position(value: Vector2) -> void:
	if _slide_supported:
		set("position", value)
