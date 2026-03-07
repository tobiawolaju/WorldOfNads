extends Node

const LIVE_EVENTS_URL := "wss://worldofnads.onrender.com/events"
const LOCAL_EVENTS_URL := "ws://localhost:8080/events"
const MAX_STATUS_LINES := 4

@export var status_label_path: NodePath = NodePath("CanvasLayer/BoxContainer/Node2/BoxContainer3/status")
@export var username_label_path: NodePath = NodePath("CanvasLayer/BoxContainer/Node2/BoxContainer2/username")

var ws := WebSocketPeer.new()
var connected := false
var tried_live := false
var fallback_started := false

var _status_lines: Array[String] = []

@onready var status_label: Label = get_node_or_null(status_label_path)
@onready var username_label: Label = get_node_or_null(username_label_path)

func _ready() -> void:
	add_to_group("events_bridge")
	tried_live = true
	var err = ws.connect_to_url(LIVE_EVENTS_URL)
	if err != OK:
		_start_local_fallback("Could not start live events stream")
	else:
		_show_local_status("Connecting events stream...")

func _process(_delta: float) -> void:
	ws.poll()

	var state = ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not connected:
			connected = true
			_show_local_status("Events live")
		_read_packets()
	elif state == WebSocketPeer.STATE_CLOSED:
		if connected:
			connected = false
			_show_local_status("Events disconnected")
		if tried_live and not fallback_started:
			_start_local_fallback("Falling back to local events")

#func set_local_username(id: String) -> void:
	#if username_label == null:
		#return
	#username_label.text = id

func show_local_event(message: String) -> void:
	_push_status_line(message)

func _start_local_fallback(reason: String) -> void:
	fallback_started = true
	_show_local_status(reason)
	var err = ws.connect_to_url(LOCAL_EVENTS_URL)
	if err != OK:
		_show_local_status("Events offline")

func _read_packets() -> void:
	while ws.get_available_packet_count() > 0:
		var raw = ws.get_packet()
		if raw.is_empty():
			continue

		var payload = JSON.parse_string(raw.get_string_from_utf8())
		if typeof(payload) != TYPE_DICTIONARY:
			continue

		match payload.get("type", ""):
			"event":
				if payload.has("event") and typeof(payload["event"]) == TYPE_DICTIONARY:
					_render_event(payload["event"])
			"events_snapshot":
				if payload.has("events") and typeof(payload["events"]) == TYPE_ARRAY:
					_render_snapshot(payload["events"])

func _render_snapshot(events: Array) -> void:
	if events.is_empty():
		return
	var start := maxi(0, events.size() - 2)
	for i in range(start, events.size()):
		var item = events[i]
		if typeof(item) == TYPE_DICTIONARY:
			_render_event(item)

func _render_event(event_data: Dictionary) -> void:
	var message = str(event_data.get("message", ""))
	if message.strip_edges() == "":
		return
	_push_status_line(message)

func _show_local_status(text: String) -> void:
	_push_status_line(text)

func _push_status_line(line: String) -> void:
	if status_label == null:
		status_label = get_node_or_null(status_label_path)
	if status_label == null:
		return

	_status_lines.append(line)
	if _status_lines.size() > MAX_STATUS_LINES:
		_status_lines.pop_front()

	status_label.text = "\n".join(_status_lines)
