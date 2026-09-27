extends Label

signal text_finished

@export var play_on_ready: bool = true
@export var fade_in_duration: float = 0.6
@export var fade_out_delay: float = 5.0 # seconds the text stays fully visible before fading out
@export var fade_out_duration: float = 0.8

func _ready() -> void:
	if not play_on_ready:
		return
	play()

func play() -> void:
	visible = true
	modulate.a = 0.0
	if fade_in_duration > 0.0:
		var fade_in := create_tween()
		fade_in.tween_property(self, "modulate:a", 1.0, fade_in_duration)
		await fade_in.finished
	else:
		modulate.a = 1.0
	if fade_out_delay > 0.0:
		await get_tree().create_timer(fade_out_delay).timeout
	if fade_out_duration > 0.0:
		var fade_out := create_tween()
		fade_out.tween_property(self, "modulate:a", 0.0, fade_out_duration)
		await fade_out.finished
	visible = false
	text_finished.emit()
