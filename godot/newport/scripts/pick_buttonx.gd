extends Button

@export var input_action: StringName = &"pickup"

func _ready():
	# Connect the pressed signal
	pressed.connect(_on_pressed)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _on_pressed():
	if DisplayServer.is_touchscreen_available():
		return
	_emit_action(true)
	_emit_action(false)

func _on_button_down():
	if not DisplayServer.is_touchscreen_available():
		return
	_trigger_local_pickup()

func _on_button_up():
	if not DisplayServer.is_touchscreen_available():
		return
	return

func _emit_action(pressed: bool):
	var ev := InputEventAction.new()
	ev.action = input_action
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _trigger_local_pickup() -> void:
	var local_player := get_tree().get_first_node_in_group("local_player")
	if local_player != null and local_player.has_method("request_pickup"):
		local_player.call("request_pickup")
