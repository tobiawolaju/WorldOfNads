extends Node
class_name Events

const LIVE_EVENTS_URL := "wss://worldofnads.onrender.com/events"
# Events feed for the Rust room server, kept in step with PlayerManager.ROOM_URL
# while the room server is under test — otherwise the game socket talks to Rust
# while chat/event toasts still come from Node, and nothing lines up.
const ROOM_EVENTS_URL := "wss://wons-room-server.onrender.com/events"
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
# `?room=...` suffix for the events feed. The Rust room server keeps a per-room
# feed, so a special match's chat/join toasts only line up when we subscribe to
# the same room the game socket joined. Empty means the shared default room.
var _room_query := ""

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

# Possession progress UI (created programmatically).
var possession_progress_bar: ProgressBar = null
var possession_label: Label = null

# --- REWARD COUNTER JUICE ---
# When the XP / MON stream counters tick up we punch the label: a quick scale
# pop plus a white flash that fades back to the label's normal colour. This
# only runs on a value increase (about once a second, driven by the server's
# reward_update), never per frame, so it stays off the performance hot path.
const REWARD_POP_DURATION := 0.30
const REWARD_POP_SCALE := 1.35
const REWARD_FLASH_COLOR := Color(1, 1, 1, 1)

var _xp_base_color: Color = Color(1, 1, 0, 1)
var _mon_base_color: Color = Color(0.8235294, 0, 1, 1)
var _xp_pop_tween: Tween = null
var _mon_pop_tween: Tween = null
var _last_xp_shown: int = -1
var _last_mon_shown: float = -1.0

func _ready() -> void:
	add_to_group("events_bridge")
	_setup_debug_labels()
	_cache_reward_colors()
	_try_set_username_from_web_query()
	_resolve_room_query()
	tried_live = true
	var err = ws.connect_to_url(ROOM_EVENTS_URL + _room_query)
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
		if _last_xp_shown >= 0 and total_xp > _last_xp_shown:
			_xp_pop_tween = _play_reward_pop(xp_stream_label, _xp_base_color, _xp_pop_tween)
		_last_xp_shown = total_xp

func update_mon_display(earned_mon: float, pool_remaining: float) -> void:
	if mon_stream_label:
		# 3 decimals so the lootbox stream (0.002 MON/sec) is visible ticking up.
		mon_stream_label.text = "+ %.3f MON" % earned_mon
		if _last_mon_shown >= 0.0 and earned_mon > _last_mon_shown + 0.0005:
			_mon_pop_tween = _play_reward_pop(mon_stream_label, _mon_base_color, _mon_pop_tween)
		_last_mon_shown = earned_mon
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

func update_possession_display(possession_seconds: int, victory_target: int) -> void:
	# Create possession progress UI if not exists.
	if possession_progress_bar == null:
		_create_possession_ui()
	if possession_progress_bar:
		possession_progress_bar.max_value = float(victory_target)
		possession_progress_bar.value = float(possession_seconds)
		var pct = float(possession_seconds) / float(victory_target) * 100.0 if victory_target > 0 else 0.0
		if possession_label:
			possession_label.text = "Chicken: %ds / %ds (%.0f%%)" % [possession_seconds, victory_target, pct]
		# Visual feedback when close to victory.
		if possession_seconds >= victory_target - 5 and possession_seconds < victory_target:
			possession_progress_bar.add_theme_color_override("fill_color", Color(1.0, 0.8, 0.0, 1.0))  # Yellow warning
		elif possession_seconds >= victory_target:
			possession_progress_bar.add_theme_color_override("fill_color", Color(0.0, 1.0, 0.5, 1.0))  # Green victory
		else:
			possession_progress_bar.add_theme_color_override("fill_color", Color(0.98, 0.8, 0.3, 1.0))  # Normal gold

# --- POSSESSION UI CREATION ---
func _create_possession_ui() -> void:
	var canvas = get_node_or_null("CanvasLayer")
	if canvas == null:
		return
	
	# Container for possession UI at top-center.
	var container = HBoxContainer.new()
	container.name = "PossessionUI"
	container.set_anchors_preset(Control.PRESET_TOP_WIDE)
	container.offset_left = -150
	container.offset_top = 10
	container.offset_right = 150
	container.offset_bottom = 50
	container.add_theme_constant_override("separation", 8)
	canvas.add_child(container)
	
	# Label.
	possession_label = Label.new()
	possession_label.text = "Chicken: 0s / 60s"
	possession_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	possession_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	possession_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	possession_label.add_theme_constant_override("outline_size", 2)
	possession_label.add_theme_font_size_override("font_size", 16)
	container.add_child(possession_label)
	
	# Progress bar.
	possession_progress_bar = ProgressBar.new()
	possession_progress_bar.min_value = 0.0
	possession_progress_bar.max_value = 60.0
	possession_progress_bar.value = 0.0
	possession_progress_bar.custom_minimum_size = Vector2(200, 20)
	possession_progress_bar.theme_override_styles = {
		"background": StyleBoxFlat.new(),
		"fill": StyleBoxFlat.new(),
	}
	# Style the progress bar.
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0, 0, 0, 0.5)
	bg_style.corner_radius_top_left = 4
	bg_style.corner_radius_top_right = 4
	bg_style.corner_radius_bottom_left = 4
	bg_style.corner_radius_bottom_right = 4
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = Color(0.98, 0.8, 0.3, 1.0)  # Gold
	fill_style.corner_radius_top_left = 4
	fill_style.corner_radius_top_right = 4
	fill_style.corner_radius_bottom_left = 4
	fill_style.corner_radius_bottom_right = 4
	possession_progress_bar.add_theme_stylebox_override("background", bg_style)
	possession_progress_bar.add_theme_stylebox_override("fill", fill_style)
	container.add_child(possession_progress_bar)
	
	# Target label.
	var target_label = Label.new()
	target_label.text = "WIN at 60s"
	target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	target_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	target_label.add_theme_constant_override("outline_size", 1)
	target_label.add_theme_font_size_override("font_size", 12)
	container.add_child(target_label)

# --- REWARD COUNTER JUICE HELPERS ---

func _cache_reward_colors() -> void:
	if xp_stream_label != null:
		_xp_base_color = xp_stream_label.get_theme_color("font_color")
	if mon_stream_label != null:
		_mon_base_color = mon_stream_label.get_theme_color("font_color")

# Reusable one-shot punch: kill any in-flight pop on this label, snap it large
# and white, then ease back to normal size and colour. Returns the new tween so
# the caller can cancel it on the next tick.
func _play_reward_pop(label: Label, base_color: Color, previous: Tween) -> Tween:
	if label == null:
		return previous
	if previous != null and previous.is_valid():
		previous.kill()
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2(REWARD_POP_SCALE, REWARD_POP_SCALE)
	label.add_theme_color_override("font_color", REWARD_FLASH_COLOR)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "scale", Vector2.ONE, REWARD_POP_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_method(_apply_label_color.bind(label), REWARD_FLASH_COLOR, base_color, REWARD_POP_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	return tween

func _apply_label_color(color: Color, label: Label) -> void:
	if label != null and is_instance_valid(label):
		label.add_theme_color_override("font_color", color)

func _start_local_fallback(reason: String) -> void:
	fallback_started = true
	_show_local_status(reason)
	var err = ws.connect_to_url(LOCAL_EVENTS_URL + _room_query)
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
	var victory_type := "legacy"
	var split_info: Dictionary = {}

	if event_data.has("meta") and typeof(event_data["meta"]) == TYPE_DICTIONARY:
		var meta := event_data["meta"] as Dictionary
		var meta_winner_id := str(meta.get("winnerId", "")).strip_edges()
		if meta_winner_id != "":
			winner_id = meta_winner_id
		winner_name = str(meta.get("winnerName", "")).strip_edges()
		victory_type = str(meta.get("victoryType", "legacy"))
		# Extract split info for buzzer resolution.
		if meta.has("split") and meta["split"] == true:
			split_info["split"] = true
			split_info["holderId"] = str(meta.get("holderId", ""))
			split_info["holderName"] = str(meta.get("holderName", ""))
			split_info["holderTime"] = int(meta.get("holderTime", 0))
			split_info["holderShare"] = float(meta.get("holderShare", 0.5))
			split_info["progressId"] = str(meta.get("progressId", ""))
			split_info["progressName"] = str(meta.get("progressName", ""))
			split_info["progressTime"] = int(meta.get("progressTime", 0))
			split_info["progressShare"] = float(meta.get("progressShare", 0.5))

	var did_win := winner_id != "" and winner_id == _local_player_id
	get_tree().set_meta("match_result_won", did_win)
	get_tree().set_meta("match_result_winner_id", winner_id)
	get_tree().set_meta("match_result_winner_name", winner_name)
	get_tree().set_meta("match_result_victory_type", victory_type)
	get_tree().set_meta("match_result_split_info", split_info)
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

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			_copy_label(_debug_label)
		elif event.keycode == KEY_G:
			_copy_label(_debug2_label)

func _copy_label(label: Label) -> void:
	if label == null or label.text.is_empty():
		return
	if OS.has_feature("web"):
		JavaScriptBridge.eval("navigator.clipboard.writeText('%s')" % label.text.replace("'", "\\'"))
	else:
		DisplayServer.clipboard_set(label.text)

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
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_outline_size", 1)
	label.add_theme_font_size_override("font_size", 11)
	return label

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

# Keep the events subscription in step with PlayerManager: on web the selected
# match is on the frame URL, so mirror the game socket's room here. Native builds
# have no URL and subscribe to the default feed (they do not carry the match id).
func _resolve_room_query() -> void:
	if not OS.has_feature("web"):
		return
	var raw_match = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('match') || ''")
	if typeof(raw_match) != TYPE_STRING:
		return
	var match_id := str(raw_match).strip_edges()
	if match_id != "":
		_room_query = "?room=%s" % match_id.uri_encode()
