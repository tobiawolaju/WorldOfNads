extends Node
class_name Events

const LIVE_EVENTS_URL := "wss://worldofnads.onrender.com/events"
const LOCAL_EVENTS_URL := "ws://localhost:8080/events"
const GAMEOVER_SCENE := preload("res://scenes/gameover.tscn")
const MAX_STATUS_LINES := 4

@export var status_label_path: NodePath = NodePath("CanvasLayer/BoxContainer/Node2/BoxContainer3/status")
@export var status2_label_path: NodePath = NodePath("CanvasLayer/BoxContainer/Node2/BoxContainer3/status2")
@export var username_label_path: NodePath = NodePath("CanvasLayer/BoxContainer/Node2/BoxContainer2/username")

var ws := WebSocketPeer.new()
var connected := false
var tried_live := false
var fallback_started := false

var _username_locked := false
var _actor_lines: Array[String] = []
var _message_lines: Array[String] = []
var _local_player_id := ""
var _navigated_to_gameover := false

@onready var status_label: Label = get_node_or_null(status_label_path)
@onready var status_username: Label = get_node_or_null(status2_label_path)
@onready var username_label: Label = get_node_or_null(username_label_path)

@onready var xp_stream_label: Label = get_node_or_null("XPstream")
@onready var mon_stream_label: Label = get_node_or_null("MONstream")
@onready var prize_pool_label: Label = get_node_or_null("PrizePool")
@onready var _debug_label: Label
@onready var _debug2_label: Label

func _ready() -> void:
	add_to_group("events_bridge")
	_setup_debug_labels()
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

func set_local_player_id(id: String) -> void:
	_local_player_id = id.strip_edges()

func show_local_event(message: String) -> void:
	var parsed = _split_message_actor_and_text(message)
	_push_event_line(parsed["actor"], parsed["message"])

func update_xp_display(total_xp: int) -> void:
	if xp_stream_label:
		xp_stream_label.text = "+ %d XP" % total_xp

func update_mon_display(earned_mon: float, pool_remaining: float) -> void:
	if mon_stream_label:
		mon_stream_label.text = "+ %d MON" % int(earned_mon)
	if prize_pool_label:
		pool_remaining = maxf(0.0, pool_remaining)
		if pool_remaining >= 1000.0:
			var k_val = pool_remaining / 1000.0
			if is_equal_approx(k_val, floor(k_val)):
				prize_pool_label.text = "%dk MON pool" % int(k_val)
			else:
				prize_pool_label.text = "%.1fk MON pool" % k_val
		else:
			prize_pool_label.text = "%d MON pool" % int(pool_remaining)

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
					_render_event(payload["event"], true)
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
			_render_event(item, false)

func _render_event(event_data: Dictionary, can_navigate: bool) -> void:
	var message = str(event_data.get("message", ""))
	if message.strip_edges() == "":
		return
	var parsed = _split_message_actor_and_text(message)
	var actor = _resolve_event_actor(event_data, parsed["actor"])
	_push_event_line(actor, parsed["message"])

	if can_navigate and str(event_data.get("eventType", "")) == "match_winner":
		_handle_match_winner_event(event_data)

func _handle_match_winner_event(event_data: Dictionary) -> void:
	if _navigated_to_gameover:
		return

	var winner_id := str(event_data.get("playerId", "")).strip_edges()
	var winner_name := ""

	if event_data.has("meta") and typeof(event_data["meta"]) == TYPE_DICTIONARY:
		var meta := event_data["meta"] as Dictionary
		var meta_winner_id := str(meta.get("winnerId", "")).strip_edges()
		if meta_winner_id != "":
			winner_id = meta_winner_id
		winner_name = str(meta.get("winnerName", "")).strip_edges()

	var did_win := winner_id != "" and winner_id == _local_player_id
	get_tree().set_meta("match_result_won", did_win)
	get_tree().set_meta("match_result_winner_id", winner_id)
	get_tree().set_meta("match_result_winner_name", winner_name)
	_navigated_to_gameover = true
	_show_gameover_overlay()

func _show_gameover_overlay() -> void:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return

	var hud := current_scene.get_node_or_null("Hud")
	if hud is CanvasItem:
		(hud as CanvasItem).visible = false

	if current_scene.has_node("GameoverOverlay"):
		var existing_overlay := current_scene.get_node_or_null("GameoverOverlay")
		if existing_overlay is CanvasItem:
			(existing_overlay as CanvasItem).visible = true
		return

	var overlay := GAMEOVER_SCENE.instantiate()
	overlay.name = "GameoverOverlay"
	current_scene.add_child(overlay)

func _show_local_status(text: String, actor: String = "system") -> void:
	_push_event_line(actor, text)

func _push_event_line(actor: String, message: String) -> void:
	if status_label == null:
		status_label = get_node_or_null(status_label_path)
	if status_username == null:
		status_username = get_node_or_null(status2_label_path)
	if status_label == null:
		return
	if status_username == null:
		return

	var safe_actor := actor.strip_edges()
	var safe_message := message.strip_edges()
	if safe_message == "":
		return
	if safe_actor == "":
		safe_actor = "system"

	_actor_lines.append(safe_actor)
	_message_lines.append(safe_message)
	if _actor_lines.size() > MAX_STATUS_LINES:
		_actor_lines.pop_front()
	if _message_lines.size() > MAX_STATUS_LINES:
		_message_lines.pop_front()

	status_username.text = "\n".join(_actor_lines)
	status_label.text = "\n".join(_message_lines)

func _resolve_event_actor(event_data: Dictionary, fallback_actor: String) -> String:
	var candidate = str(event_data.get("username", "")).strip_edges()
	if candidate != "":
		return candidate
	if event_data.has("meta") and typeof(event_data["meta"]) == TYPE_DICTIONARY:
		var meta := event_data["meta"] as Dictionary
		candidate = str(meta.get("username", "")).strip_edges()
		if candidate != "":
			return candidate

	if fallback_actor != "":
		return fallback_actor

	var player_id = str(event_data.get("playerId", "")).strip_edges()
	if player_id != "":
		return player_id.substr(0, 8)

	return "system"

func _split_message_actor_and_text(message: String) -> Dictionary:
	var safe_message := message.strip_edges()
	if safe_message == "":
		return {"actor": "system", "message": ""}

	var split_patterns = [
		" joined the game",
		" joined the match",
		" left the game",
		" left the match",
		" picked the chicken",
		" dropped the chicken",
		" won the round"
	]
	for suffix in split_patterns:
		if safe_message.ends_with(suffix):
			var actor = safe_message.trim_suffix(suffix).strip_edges()
			if actor != "":
				var parts = actor.split(" ", false)
				if parts.size() > 1:
					actor = parts[parts.size() - 1]
				return {"actor": actor, "message": suffix.strip_edges()}

	return {"actor": "system", "message": safe_message}

func set_debug_text(text: String) -> void:
	if _debug_label != null:
		_debug_label.text = text

func set_debug2_text(text: String) -> void:
	if _debug2_label != null:
		_debug2_label.text = text

func _setup_debug_labels() -> void:
	var canvas := get_node_or_null("CanvasLayer")
	if canvas == null:
		return
	_debug_label = _ensure_debug_label(canvas, "debug", Color(0, 1, 0.5, 1))
	_debug_label.offset_top = 60
	_debug2_label = _ensure_debug_label(canvas, "debug2", Color(0.5, 1, 1, 1))
	_debug2_label.offset_top = 140

func _ensure_debug_label(parent: Node, name: String, color: Color) -> Label:
	var label := parent.get_node_or_null(name) as Label
	if label == null:
		label = Label.new()
		label.name = name
		parent.add_child(label)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.offset_left = 4.0
	label.offset_right = -4.0
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_outline_size", 1)
	label.add_theme_font_size_override("font_size", 11)
	if not label.gui_input.is_connected(_on_debug_click):
		label.gui_input.connect(_on_debug_click.bind(label))
	return label

func _on_debug_click(event: InputEvent, label: Label) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var text := label.text
		if text.is_empty():
			return
		if OS.has_feature("web"):
			JavaScriptBridge.eval("navigator.clipboard.writeText('%s')" % text.replace("'", "\\'"))
		else:
			DisplayServer.clipboard_set(text)

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
