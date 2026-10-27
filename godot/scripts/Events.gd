extends Node
class_name Events

const LIVE_EVENTS_URL := "wss://worldofnads.onrender.com/events"
# Events feed for the Rust room server, kept in step with PlayerManager.ROOM_URL
# while the room server is under test — otherwise the game socket talks to Rust
# while chat/event toasts still come from Node, and nothing lines up.
const ROOM_EVENTS_URL := "wss://wons-room-server.onrender.com/events"
const LOCAL_EVENTS_URL := "ws://localhost:8080/events"
const GAMEOVER_SCENE := preload("res://scenes/gameover.tscn")

## Rows kept in the feed. Enough to follow what the room is doing, few enough to
## stay readable over gameplay.
const MAX_FEED_ROWS := 5
const AVATAR_SIZE := 20.0
const FEED_FADE_SEC := 0.18
const FEED_NAME_ALPHA := 1.0
const FEED_TEXT_ALPHA := 0.94
const FEED_SYSTEM_ALPHA := 0.62

# The avatar directory lives on the Node backend: the Rust room server knows
# nothing about Privy, so there is nothing to ask it. Mirrors
# `PlayerManager.API_BASE` (and its localhost fallback) so a local run resolves
# local avatars instead of reaching for production.
const LIVE_API_URL := "https://worldofnads.onrender.com"
const LOCAL_API_URL := "http://localhost:8080"

@export var feed_path: NodePath = NodePath("CanvasLayer/BoxContainer/Node2/EventFeed")
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
## Logical feed history, oldest first. Rows are a fixed pool rendered from this,
## so a burst of events never allocates nodes.
var _entries: Array[Dictionary] = []
var _entry_seq := 0
var _rows: Array[Dictionary] = []
var _avatars: AvatarLoader = null
## The pinned "wins in N" row for the chicken holder, kept out of `_rows` so the
## event history never pushes it out.
var _countdown_row: Dictionary = {}
## colour hex -> StyleBoxFlat, so the badge disc is not rebuilt on every render.
var _disc_styles: Dictionary = {}
var _local_player_id := ""
var _navigated_to_gameover := false

@onready var _feed: VBoxContainer = get_node_or_null(feed_path)
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
	_setup_avatar_loader()
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
	if pool_remaining <= 0.0:
		# A room without a match (the shared practice lobby) has no escrow behind
		# it, so it has no prize pool. Say so instead of streaming MON that will
		# never be paid out.
		if mon_stream_label:
			mon_stream_label.text = ""
			_last_mon_shown = -1.0
		if prize_pool_label:
			prize_pool_label.text = "No prize pool"
		return
	if mon_stream_label:
		# 3 decimals so the lootbox stream (a few thousandths per second) is
		# visible ticking up.
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
		elif pool_remaining >= 100.0 or is_equal_approx(pool_remaining, round(pool_remaining)):
			prize_pool_label.text = "%d MON pool" % int(pool_remaining)
		else:
			# The pool is 0.18 x the prize, so it usually has cents: show them.
			prize_pool_label.text = "%.2f MON pool" % pool_remaining

## Pinned countdown row above the chat rows: "<name> wins in 43s" for whoever is
## carrying the chicken, rewritten in place as possession ticks. A chat line per
## second would flush the five-row feed within five seconds of a pickup, and the
## countdown is a status, not an event.
func update_chicken_countdown(holder_name: String, seconds_left: int) -> void:
	var display_name := holder_name.strip_edges()
	if seconds_left < 0 or display_name == "":
		if not _countdown_row.is_empty():
			(_countdown_row["root"] as Control).visible = false
		return
	_ensure_feed_rows()
	if _feed == null:
		return
	if _countdown_row.is_empty():
		_countdown_row = _create_row(-1)
		(_countdown_row["root"] as Control).name = "CountdownRow"
		# Above the chat rows: it is always-on status, not part of the history.
		_feed.move_child(_countdown_row["root"], 0)
	(_countdown_row["root"] as Control).visible = true
	# seq -1 (the row's initial value) keeps _apply_row from replaying the fade on
	# every tick: the row only ever changes its text.
	_apply_row(_countdown_row, {
		"actor": display_name,
		"message": "wins in %ds" % seconds_left,
		"seq": -1,
	})

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
	# Avatars follow the same host as the feed, otherwise a local run would keep
	# asking production for pictures of local players who are not there.
	if _avatars != null and is_instance_valid(_avatars):
		_avatars.configure(LOCAL_API_URL)
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
	var safe_actor := actor.strip_edges()
	var safe_message := message.strip_edges()
	if safe_message == "":
		return
	if safe_actor == "":
		safe_actor = "system"

	_entry_seq += 1
	_entries.append({
		"actor": safe_actor,
		"message": safe_message,
		"seq": _entry_seq,
	})
	while _entries.size() > MAX_FEED_ROWS:
		_entries.pop_front()

	_render_feed()

# ---------------------------------------------------------------------------
# Stream-chat feed
# ---------------------------------------------------------------------------
#
# One row per event: avatar, coloured name, message. The rows are a fixed pool
# built once and re-textured on each event, so a noisy room does not churn the
# scene tree. Everything here is driven by an event arriving, never by a frame.

func _setup_avatar_loader() -> void:
	_avatars = AvatarLoader.new()
	_avatars.name = "AvatarLoader"
	_avatars.configure(LIVE_API_URL)
	_avatars.avatar_ready.connect(_on_avatar_ready)
	_avatars.avatar_missing.connect(_on_avatar_missing)
	add_child(_avatars)

func _on_avatar_ready(_username: String, _texture: Texture2D) -> void:
	# A picture landed for a name already on screen: repaint so every row showing
	# that player picks up the real avatar instead of the badge.
	_render_feed()

func _on_avatar_missing(_username: String) -> void:
	# The badge is already what is on screen; nothing to swap. Kept as a hook so
	# the "loading" state can be cleared if one is ever added.
	pass

func _ensure_feed_rows() -> void:
	if not _rows.is_empty():
		return
	if _feed == null:
		_feed = get_node_or_null(feed_path) as VBoxContainer
	if _feed == null:
		return
	for index in MAX_FEED_ROWS:
		_rows.append(_create_row(index))

func _create_row(index: int) -> Dictionary:
	var row := HBoxContainer.new()
	row.name = "Row%d" % index
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.visible = false
	_feed.add_child(row)

	# The avatar slot is a fixed square; the badge and the photo are both stacked
	# inside it so swapping one for the other never reflows the row.
	var slot := Control.new()
	slot.name = "Avatar"
	slot.custom_minimum_size = Vector2(AVATAR_SIZE, AVATAR_SIZE)
	slot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(slot)

	var disc := Panel.new()
	disc.name = "Disc"
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.add_theme_stylebox_override("panel", _disc_style(Color(0.18, 0.18, 0.18)))
	slot.add_child(disc)
	disc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var photo := TextureRect.new()
	photo.name = "Photo"
	photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	photo.visible = false
	slot.add_child(photo)
	photo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var initial := Label.new()
	initial.name = "Initial"
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	initial.add_theme_font_size_override("font_size", 10)
	initial.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	slot.add_child(initial)
	initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# RichTextLabel rather than Label: the name is coloured per player and the
	# message wraps under it, which two newline-joined Labels could not do.
	var text := RichTextLabel.new()
	text.name = "Text"
	text.bbcode_enabled = false
	text.fit_content = true
	text.scroll_active = false
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_font_size_override("normal_font_size", 12)
	text.add_theme_color_override("default_color", Color(1, 1, 1, FEED_TEXT_ALPHA))
	text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	text.add_theme_constant_override("shadow_outline_size", 1)
	row.add_child(text)

	return {
		"root": row,
		"slot": slot,
		"disc": disc,
		"photo": photo,
		"initial": initial,
		"text": text,
		"seq": -1,
	}

func _render_feed() -> void:
	_ensure_feed_rows()
	if _rows.is_empty():
		return

	for index in _rows.size():
		var row: Dictionary = _rows[index]
		var root: Control = row["root"]
		if index >= _entries.size():
			root.visible = false
			row["seq"] = -1
			continue
		root.visible = true
		_apply_row(row, _entries[index])

func _apply_row(row: Dictionary, entry: Dictionary) -> void:
	var actor := str(entry.get("actor", "system"))
	var message := str(entry.get("message", ""))
	var seq := int(entry.get("seq", 0))
	var is_system := actor == "system"

	# System notices (connection state, round results) get no face: a badge for
	# "system" would put a fake player in the room. The slot itself stays laid
	# out so every row's text starts on the same x.
	var slot: Control = row["slot"]
	slot.visible = true
	if is_system:
		_clear_avatar(row)
	else:
		_apply_avatar(row, actor)

	var text: RichTextLabel = row["text"]
	text.clear()
	if is_system:
		text.push_color(Color(1, 1, 1, FEED_SYSTEM_ALPHA))
		text.add_text(message)
		text.pop()
	else:
		var color := _name_color(actor)
		text.push_color(Color(color.r, color.g, color.b, FEED_NAME_ALPHA))
		text.push_bold()
		text.add_text(actor)
		text.pop()
		text.pop()
		text.push_color(Color(1, 1, 1, FEED_TEXT_ALPHA))
		text.add_text(" " + message)
		text.pop()

	if int(row["seq"]) != seq:
		row["seq"] = seq
		# Only the newest row animates in; the ones shifting up stay put.
		if seq == _entry_seq:
			_play_row_fade(row["root"])

func _clear_avatar(row: Dictionary) -> void:
	var photo: TextureRect = row["photo"]
	var disc: Panel = row["disc"]
	var initial: Label = row["initial"]
	photo.visible = false
	disc.visible = false
	initial.visible = false

func _apply_avatar(row: Dictionary, actor: String) -> void:
	var photo: TextureRect = row["photo"]
	var disc: Panel = row["disc"]
	var initial: Label = row["initial"]

	var texture: Texture2D = _avatars.get_avatar(actor) if _avatars != null else null
	if texture != null:
		photo.texture = texture
		photo.visible = true
		disc.visible = false
		initial.visible = false
		return

	# Badge: the first letter on a darkened name colour. A saturated fill at 20px
	# competes with the message, so the badge stays dark and the letter carries
	# the colour. Square, like the photos: the feed reads as stream chat, not as a
	# list of round avatars.
	var base := _name_color(actor)
	disc.add_theme_stylebox_override("panel", _disc_style(base.darkened(0.5)))
	disc.visible = true
	photo.visible = false
	initial.text = _avatars.initial(actor) if _avatars != null else "?"
	initial.visible = true

func _play_row_fade(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	control.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(control, "modulate:a", 1.0, FEED_FADE_SEC) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _name_color(actor: String) -> Color:
	if _avatars != null and is_instance_valid(_avatars):
		return _avatars.name_color(actor)
	return Color(0.45, 0.78, 1.0)

func _disc_style(color: Color) -> StyleBoxFlat:
	var key := color.to_html(true)
	var cached = _disc_styles.get(key)
	if cached is StyleBoxFlat:
		return cached
	var style := StyleBoxFlat.new()
	style.bg_color = color
	# No corner radius: profile pictures are square, so the badge is too.
	_disc_styles[key] = style
	return style

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
