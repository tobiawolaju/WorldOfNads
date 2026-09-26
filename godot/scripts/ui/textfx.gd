extends Label

@export var fade_out_on_ready: bool = false
@export var fade_out_delay: float = 1.0
@export var fade_out_duration: float = 0.8

func _ready() -> void:
	if not fade_out_on_ready:
		return
	if fade_out_delay > 0.0:
		await get_tree().create_timer(fade_out_delay).timeout
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, fade_out_duration)
	await tween.finished
	visible = false
