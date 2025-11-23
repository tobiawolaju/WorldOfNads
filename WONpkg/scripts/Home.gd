extends Node

@onready var progress_bar: ProgressBar = $"CanvasLayer/BoxContainer/Node/ProgressBar"
var timer: float = 0.0
var duration: float = 10.0  # Time in seconds

func _process(delta: float) -> void:
	if timer < duration:
		timer += delta
		progress_bar.value = (timer / duration) * 100
	else:
		get_tree().change_scene_to_file("res://scenes/lobby.tscn")
		
