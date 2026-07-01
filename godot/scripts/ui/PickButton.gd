extends Button

const PICKUP_KEY := KEY_P

var _active_touch_index: int = -1

func _ready():
	pressed.connect(_on_pressed)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	gui_input.connect(_on_gui_input)

func _on_pressed():
	if DisplayServer.is_touchscreen_available():
		return
	_emit_key(true)
	_emit_key(false)

func _on_gui_input(event: InputEvent):
	if not DisplayServer.is_touchscreen_available():
		return

	if event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed:
			_active_touch_index = touch_event.index
			_emit_key(true)
			accept_event()
		elif _active_touch_index == touch_event.index:
			_active_touch_index = -1
			_emit_key(false)
			accept_event()
	elif event is InputEventScreenDrag:
		var drag_event := event as InputEventScreenDrag
		if _active_touch_index == drag_event.index:
			if not get_global_rect().has_point(drag_event.position):
				_active_touch_index = -1
				_emit_key(false)
			accept_event()

func _emit_key(pressed: bool) -> void:
	var key_event := InputEventKey.new()
	key_event.keycode = PICKUP_KEY
	key_event.physical_keycode = PICKUP_KEY
	key_event.pressed = pressed
	key_event.echo = false
	Input.parse_input_event(key_event)
