extends Node

const LIVE_EVENTS_URL := "wss://worldofnads.onrender.com/events"
const LOCAL_EVENTS_URL := "ws://localhost:8080/events"

@export var status_label_path: NodePath = NodePath("CanvasLayer/BoxContainer/Node2/BoxContainer3/status")
@export var status2_label_path: NodePath = NodePath("CanvasLayer/BoxContainer/Node2/BoxContainer3/status2")

@export var username_label_path: NodePath = NodePath("CanvasLayer/BoxContainer/Node2/BoxContainer2/username")

var ws := WebSocketPeer.new()
var connected := false
var tried_live := false
var fallback_started := false

var _username_locked := false

@onready var status_label: Label = get_node_or_null(status_label_path)
@onready var status_username: Label = get_node_or_null(status2_label_path)
@onready var username_label: Label = get_node_or_null(username_label_path)

func _ready() -> void:
	add_to_group("events_bridge")
	_try_set_username_from_web_query()
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

func set_local_username(id: String, force: bool = false) -> void:
	if username_label == null:
		username_label = get_node_or_null(username_label_path)
	if username_label == null:
		return
	if _username_locked and not force:
		return

	var safe_id := id.strip_edges()
	if safe_id == "":
		return

	username_label.text = safe_id

func show_local_event(message: String) -> void:
	_set_event_display(_extract_actor_from_message(message), message)

func _start_local_fallback(reason: String) -> void:
	fallback_started = true
	_show_local_status(reason)
	var err = ws.connect_to_url(LOCAL_EVENTS_URL)
	if err != OK:
		_show_local_status("Events offline", "system")

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
	var actor = _resolve_event_actor(event_data, message)
	_set_event_display(actor, message)

func _show_local_status(text: String, actor: String = "system") -> void:
	_set_event_display(actor, text)

func _set_event_display(actor: String, message: String) -> void:
	if status_label == null:
		status_label = get_node_or_null(status_label_path)
	if status_username == null:
		status_username = get_node_or_null(status2_label_path)
	if status_label == null:
		return
	if status_username == null:
		return

	status_label.text = message
	status_username.text = actor

func _resolve_event_actor(event_data: Dictionary, message: String) -> String:
	var candidate = str(event_data.get("username", "")).strip_edges()
	if candidate != "":
		return candidate
	if event_data.has("meta") and typeof(event_data["meta"]) == TYPE_DICTIONARY:
		var meta := event_data["meta"] as Dictionary
		candidate = str(meta.get("username", "")).strip_edges()
		if candidate != "":
			return candidate

	var player_id = str(event_data.get("playerId", "")).strip_edges()
	if player_id != "":
		return player_id.substr(0, 8)

	return _extract_actor_from_message(message)

func _extract_actor_from_message(message: String) -> String:
	var safe_message := message.strip_edges()
	if safe_message == "":
		return "system"

	var suffixes = [
		" joined the game",
		" left the game",
		" picked the chicken",
		" dropped the chicken"
	]
	for suffix in suffixes:
		if safe_message.ends_with(suffix):
			var actor = safe_message.trim_suffix(suffix).strip_edges()
			if actor != "":
				return actor

	return "system"

func _try_set_username_from_web_query() -> void:
	if not OS.has_feature("web"):
		return

	var raw_username = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('username') || ''")
	if typeof(raw_username) != TYPE_STRING:
		return

	var parsed_username := str(raw_username).strip_edges()
	if parsed_username == "":
		return

	_username_locked = true
	set_local_username(parsed_username, true)
