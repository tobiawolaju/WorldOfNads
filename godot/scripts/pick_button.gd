extends TextureButton

func _ready():
	# Connect the pressed signal
	pressed.connect(_on_pressed)

	# Position button 100px above bottom and 100px left from right edge
	var viewport_size = get_viewport().get_visible_rect().size
	global_position = Vector2(
		viewport_size.x - 150,   # 100px left from right edge
		viewport_size.y - 150    # 100px above bottom edge
	)

func _on_pressed():
	var ev := InputEventAction.new()
	ev.action = "pickup"
	ev.pressed = true
	Input.parse_input_event(ev)

func _input(event):
	if event is InputEventScreenTouch and event.pressed:
		if get_global_rect().has_point(event.position):
			_on_pressed()
