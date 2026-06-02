extends Button

@export var input_action: StringName = &"pickup"

func _ready():
	# Connect the pressed signal
	pressed.connect(_on_pressed)

func _on_pressed():
	var ev := InputEventAction.new()
	ev.action = input_action
	ev.pressed = true
	Input.parse_input_event(ev)

func _input(event):
	if event is InputEventScreenTouch and event.pressed:
		var local_pos := get_global_transform_with_canvas().affine_inverse() * event.position
		if Rect2(Vector2.ZERO, size).has_point(local_pos):
			_on_pressed()
