extends TextureButton

func _ready():
	# Connect the pressed signal
	pressed.connect(_on_pressed)

	# Move the button to the center of the bottom-right quadrant
	var viewport_size = get_viewport().get_visible_rect().size
	global_position = Vector2(
		viewport_size.x * 3/4,  # Center of right half
		viewport_size.y * 3/4   # Center of bottom half
	)

func _on_pressed():
	var ev := InputEventAction.new()
	ev.action = "pickup"
	ev.pressed = true
	Input.parse_input_event(ev)
