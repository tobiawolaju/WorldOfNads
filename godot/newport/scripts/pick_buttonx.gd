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
		if get_global_rect().has_point(event.position):
			_on_pressed()
