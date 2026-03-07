extends TextureButton

func _ready():
	pressed.connect(_on_pressed)

func _on_pressed():
	var ev := InputEventAction.new()
	ev.action = "pickup"
	ev.pressed = true
	Input.parse_input_event(ev)
