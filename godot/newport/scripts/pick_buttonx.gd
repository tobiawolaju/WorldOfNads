extends Button

@export var input_action: StringName = &"pickup"

var _active_touch_index: int = -1

func _ready():
	pressed.connect(_on_pressed)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	gui_input.connect(_on_gui_input)

func _on_pressed():
	if DisplayServer.is_touchscreen_available():
		return
	_emit_action(true)
	_emit_action(false)

func _on_gui_input(event: InputEvent):
	if not DisplayServer.is_touchscreen_available():
		return

	if event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed:
			_active_touch_index = touch_event.index
			_trigger_local_pickup()
			accept_event()
		elif _active_touch_index == touch_event.index:
			_active_touch_index = -1
			accept_event()
	elif event is InputEventScreenDrag:
		var drag_event := event as InputEventScreenDrag
		if _active_touch_index == drag_event.index:
			if not get_global_rect().has_point(drag_event.position):
				_active_touch_index = -1
			accept_event()

func _emit_action(pressed: bool):
	var ev := InputEventAction.new()
	ev.action = input_action
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _trigger_local_pickup() -> void:
	var local_player := get_tree().get_first_node_in_group("local_player")
	if local_player != null and local_player.has_method("request_pickup"):
		local_player.call("request_pickup")
