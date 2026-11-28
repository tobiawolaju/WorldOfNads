extends Node
class_name Events

const LIVE_EVENTS_URL := "wss://worldofnads.onrender.com/events"
# Events feed for the Rust room server, kept in step with PlayerManager.ROOM_URL
# while the room server is under test — otherwise the game socket talks to Rust
# while chat/event toasts still come from Node, and nothing lines up.
const ROOM_EVENTS_URL := "wss://wons-room-server.onrender.com/events"
const GAMEOVER_SCENE := preload("res://scenes/gameover.tscn")
const FX3D_SCRIPT: GDScript = preload("res://scripts/fx/fx3d.gd")
const FX3D_SCENE: PackedScene = preload("res://scenes/fx3d.tscn")

## Rows kept in the feed. Enough to follow what the room is doing, few enough to
## stay readable over gameplay.
const MAX_FEED_ROWS := 5
const AVATAR_SIZE := 20.0
const FEED_FADE_SEC := 0.18
const FEED_NAME_ALPHA := 1.0
const FEED_TEXT_ALPHA := 0.94
const FEED_SYSTEM_ALPHA := 0.62

## Inline emotes, Twitch-style: `:name:` tokens become small images sitting on the
## text baseline. The built-ins reuse art the game already ships; any extra
## PNG/WebP dropped into `res://assets/emotes/` becomes `:<file name>:` with no
## code change, so custom emotes are an art drop, not a feature request.
const EMOTES_DIR := "res://assets/emotes"
const EMOTE_SIZE := 20
const SKULL_ICON_PATH := "res://assets/img/skull.png"
const BUILTIN_EMOTES := {
	"chicken": "res://assets/img/chick.png",
	"gem": "res://assets/img/gem.png",
	"mon": "res://assets/img/mon.png",
	"loot": "res://assets/img/loot.png",
	"star": "res://assets/img/star.png",
	"energy": "res://assets/img/energy.png",
}

# Contextual emote selection: pick an emote that fits the event, not a random
# reaction. The 10 curated emotes live in assets/emotes/; we map by the token
# (lowercased basename) so filename-based tokens keep working.
const EMOTE_HYPERKEKW := "hyperkekw"
const EMOTE_POGGERS := "poggers"
const EMOTE_MONKAS := "monkas"
const EMOTE_PEPELAUGH := "pepelaugh"
const EMOTE_SADGE := "sadge"
const EMOTE_GIGACHAD := "gigachad"
const EMOTE_COPIUM := "copium"
const EMOTE_HYPERCLAP := "hyperclap"
const EMOTE_PEPEHANDS := "pepehands"
const EMOTE_5HEAD := "5head"

## Events that should never get an auto emote (system noise, countdown-like, etc.).
const NO_EMOTE_PHRASES := [
	"connecting events stream",
	"events live",
	"events disconnected",
	"live events unavailable",
	"wins in ",
]

var _emotes: Dictionary = {}
var _emote_pattern: RegEx = RegEx.create_from_string(":([A-Za-z0-9_+\\-]+):")
## Avoid repeating the same auto emote in consecutive event lines.
var _recent_auto_emotes: Array[String] = []
const RECENT_AUTO_EMOTE_LIMIT := 3

# The avatar directory lives on the Node backend: the Rust room server knows
# nothing about Privy, so there is nothing to ask it. The beta talks to the
# remote backend only, so there is no local endpoint to fall back to.
const LIVE_API_URL := "https://worldofnads.onrender.com"

@export var feed_path: NodePath = NodePath("CanvasLayer/BoxContainer/Node2/EventFeedPanel/EventFeed")
@export var username_label_path: NodePath = NodePath("CanvasLayer/BoxContainer/Node2/BoxContainer2/username")

var ws := WebSocketPeer.new()
var connected := false
var tried_live := false
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
## Chat panel around the rows: auto-sizes to the messages, hidden when the feed is
## empty so the HUD does not carry an empty dark box.
var _feed_panel: Control = null
## Pinned holder/countdown row above the chat. It never enters the history, so a
## long hold cannot scroll the round's messages away.
var _countdown_row: Dictionary = {}
## Countdown state for chicken holder chat messages (progress bar removed).
var _countdown_holder_name: String = ""
var _countdown_last_seconds: int = -999
## colour hex -> StyleBoxFlat, so the badge disc is not rebuilt on every render.
var _disc_styles: Dictionary = {}
var _local_player_id := ""
var _navigated_to_gameover := false
## Dedupe for visual replication events (fx/powerup). The same event can arrive
## over both the /events feed and the game socket; spawning it twice would create
## duplicate smoke clouds or restart a decoy timer.
var _seen_replicated_event_ids: Dictionary = {}
const SEEN_REPLICATED_EVENT_MAX := 128

@onready var _feed: VBoxContainer = get_node_or_null(feed_path)
@onready var username_label: Label = get_node_or_null(username_label_path)
@onready var _callout_fx2: RichTextLabel = get_node_or_null("TextFX2")
var _skull_texture: Texture2D = null

@onready var xp_stream_label: Label = get_node_or_null("XPstream")
@onready var mon_stream_label: Label = get_node_or_null("MONstream")
@onready var prize_pool_label: Label = get_node_or_null("PrizePool")
@onready var _debug_label: Label
@onready var _debug2_label: Label

# Possession progress UI removed: chicken status is shown in the event feed/chat.

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
	_build_emotes()
	_setup_debug_labels()
	_cache_reward_colors()
	_try_set_username_from_web_query()
	_try_set_username_from_auth()
	_resolve_room_query()
	tried_live = true
	var err = ws.connect_to_url(ROOM_EVENTS_URL + _room_query)
	if err != OK:
		_show_local_status("Live events unavailable")
	else:
		_show_local_status("Connecting events stream...")

var _events_poll_accum: float = 0.0
const EVENTS_POLL_INTERVAL: float = 0.05 # 20Hz; events feed isn't input-critical

func _process(delta: float) -> void:
	_events_poll_accum += delta
	if _events_poll_accum < EVENTS_POLL_INTERVAL:
		return
	_events_poll_accum = 0.0
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
		elif tried_live:
			_show_local_status("Live events unavailable")

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


func show_game_callout(text: String, color: Color = Color(1.0, 0.9, 0.2, 1.0)) -> void:
	# Big gameplay callout on TextFX2 (hud.tscn), e.g. DOUBLE KILL.
	if _callout_fx2 == null:
		_callout_fx2 = get_node_or_null("TextFX2")
	if _callout_fx2 == null:
		return
	_callout_fx2.clear()
	_callout_fx2.push_color(color)
	_callout_fx2.add_text(text)
	_callout_fx2.pop()
	_play_callout()

## Kill callout: a skull with the streak multiplier, not a sentence. One kill is
## the skull alone; x2/x3 sit next to it in small type so the icon carries the
## moment and the number only adds the streak.
func show_kill_callout(count: int, color: Color = Color(1.0, 0.9, 0.2, 1.0)) -> void:
	if _callout_fx2 == null:
		_callout_fx2 = get_node_or_null("TextFX2")
	if _callout_fx2 == null:
		return
	if _skull_texture == null:
		_skull_texture = load(SKULL_ICON_PATH) as Texture2D
	_callout_fx2.clear()
	if _skull_texture != null:
		_callout_fx2.add_image(_skull_texture, 46, 46, color)
	if count > 1:
		_callout_fx2.push_font_size(28)
		_callout_fx2.push_color(color)
		_callout_fx2.add_text(" x%d" % count)
		_callout_fx2.pop()
		_callout_fx2.pop()
	_play_callout()

func _play_callout() -> void:
	if _callout_fx2 == null:
		return
	_callout_fx2.visible = true
	if _callout_fx2.has_method("play"):
		_callout_fx2.call("play")
	else:
		_callout_fx2.modulate.a = 1.0

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

## Chicken holder/countdown as a pinned chat row above the history (progress bar
## UI removed). Keeping it out of `_entries` means the one-second tick cannot
## flush the round's chat.
func update_chicken_countdown(holder_name: String, seconds_left: int) -> void:
	if _feed == null:
		_feed = get_node_or_null(feed_path) as VBoxContainer
	if _feed == null:
		return

	var display_name := holder_name.strip_edges()
	if seconds_left < 0 or display_name == "":
		_countdown_holder_name = ""
		_countdown_last_seconds = -999
		if not _countdown_row.is_empty():
			(_countdown_row["root"] as Control).visible = false
		_sync_feed_panel()
		return

	if _countdown_row.is_empty():
		_countdown_row = _create_row(MAX_FEED_ROWS)
		(_countdown_row["root"] as Control).name = "CountdownRow"
		_feed.move_child(_countdown_row["root"], 0)
	elif _feed.get_child(0) != _countdown_row["root"]:
		_feed.move_child(_countdown_row["root"], 0)

	if display_name != _countdown_holder_name:
		_countdown_holder_name = display_name
		_countdown_last_seconds = -999

	var row_visible := (_countdown_row["root"] as Control).visible
	if seconds_left == _countdown_last_seconds and row_visible:
		return
	_countdown_last_seconds = seconds_left
	_countdown_row["seq"] = -1
	_apply_row(_countdown_row, {
		"actor": display_name,
		"message": "wins in %ds" % seconds_left,
		"seq": -1,
	})
	(_countdown_row["root"] as Control).visible = true
	_sync_feed_panel()

func update_possession_display(_possession_seconds: int, _victory_target: int) -> void:
	# Progress bar UI intentionally removed; countdown is shown in the event feed.
	pass

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

# Local events fallback removed for public/live testing: events come from the
# live room server and the avatars from the live backend.

## True while the room's event stream is open. Callers that also send a
## client_event use this to skip their own local echo: the room republishes the
## event to every stream, including the sender's.
func is_stream_connected() -> bool:
	return ws.get_ready_state() == WebSocketPeer.STATE_OPEN

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
	var event_type := str(event_data.get("eventType", ""))
	if event_type == "fx":
		# World effects are rebuilt, never printed: a "smoke" feed row would be
		# noise. Snapshot entries are ignored so a late joiner does not spawn a
		# cloud that already expired; `can_navigate` is true only for live events.
		if can_navigate:
			handle_replicated_event(event_data)
		return
	if event_type == "powerup":
		# Aura/decoy state is rebuilt from the sender's event, like fx. Snapshot
		# entries are ignored: a timed aura from the history has already expired
		# (or is about to), so a late joiner must not inherit a stale one.
		if can_navigate:
			handle_replicated_event(event_data)
		return
	var message = str(event_data.get("message", ""))
	if message.strip_edges() == "":
		return
	var parsed = _split_message_actor_and_text(message)
	var actor = _resolve_event_actor(event_data, parsed["actor"])
	_push_event_line(actor, parsed["message"], true, event_type, event_data)

	if can_navigate and str(event_data.get("eventType", "")) == "match_winner":
		_handle_match_winner_event(event_data)


## Handles a live fx/powerup replication event from either the /events feed or
## the game socket. Dedupe by event id so dual delivery never spawns twice.
func handle_replicated_event(event_data: Dictionary) -> void:
	var event_id := str(event_data.get("id", ""))
	if event_id != "":
		if _seen_replicated_event_ids.has(event_id):
			return
		_seen_replicated_event_ids[event_id] = true
		if _seen_replicated_event_ids.size() > SEEN_REPLICATED_EVENT_MAX:
			_seen_replicated_event_ids.clear()
			_seen_replicated_event_ids[event_id] = true
	var event_type := str(event_data.get("eventType", ""))
	if event_type == "fx":
		_spawn_fx_event(event_data)
	elif event_type == "powerup":
		_apply_powerup_event(event_data)


# Rebuilds an effect another player triggered. The thrower already spawned it
# locally and its own event comes back on this feed, so drop the echo by
# playerId or it would get two overlapping clouds.
func _spawn_fx_event(event_data: Dictionary) -> void:
	if str(event_data.get("playerId", "")).strip_edges() == _local_player_id:
		return
	var fx = FX3D_SCRIPT.ensure(null, FX3D_SCENE)
	if fx == null:
		return
	fx.spawn_from_event(event_data)


# Rebuilds another player's timed power-up aura (and TWIN decoy) on their remote
# avatar. The sender already shows its own aura locally, so drop the echo.
func _apply_powerup_event(event_data: Dictionary) -> void:
	var owner_id := str(event_data.get("playerId", "")).strip_edges()
	if owner_id == "" or owner_id == _local_player_id:
		return
	if typeof(event_data.get("meta", null)) != TYPE_DICTIONARY:
		return
	var meta: Dictionary = event_data["meta"]
	var pm = get_tree().get_first_node_in_group("player_manager")
	if pm == null:
		return
	var roster = pm.get("players")
	if typeof(roster) != TYPE_DICTIONARY:
		return
	var node = roster.get(owner_id)
	if node == null or not is_instance_valid(node):
		return
	if not node.has_method("apply_remote_powerup"):
		return
	var duration := float(int(meta.get("dur", 0))) / 1000.0
	node.call(
		"apply_remote_powerup",
		int(meta.get("mode", 0)),
		duration,
		int(meta.get("on", 0)) == 1)


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

func _push_event_line(actor: String, message: String, randomize_emote: bool = true, event_type: String = "", event_data: Dictionary = {}) -> void:
	var safe_actor := actor.strip_edges()
	var safe_message := message.strip_edges()
	if safe_message == "":
		return
	if safe_actor == "":
		safe_actor = "system"
	if randomize_emote and safe_actor != "system":
		safe_message = _with_contextual_emote(safe_message, event_type, safe_actor, event_data)

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


## Loads the emote palette once. Built-ins are art the game already ships; the
## folder scan is what makes custom emotes a pure asset drop.
func _build_emotes() -> void:
	for key in BUILTIN_EMOTES:
		var builtin := load(str(BUILTIN_EMOTES[key])) as Texture2D
		if builtin != null:
			_emotes[key] = builtin
	var dir := DirAccess.open(EMOTES_DIR)
	if dir == null:
		return
	for file in dir.get_files():
		var ext := file.get_extension().to_lower()
		var resource_name := file
		if ext == "import":
			# In exports, packed resources show up as *.png.import / *.webp.import.
			var base := file.get_basename()
			var base_ext := base.get_extension().to_lower()
			if base_ext != "png" and base_ext != "webp":
				continue
			resource_name = base
		elif ext != "png" and ext != "webp":
			continue
		var texture := load(EMOTES_DIR.path_join(resource_name)) as Texture2D
		if texture != null:
			_emotes[resource_name.get_basename().to_lower()] = texture


## Appends a contextual emote to a player line when the event clearly calls for
## one. No random spam: the emote must match the event, and we avoid repeating the
## same auto emote in consecutive lines. Manual :token: emotes are never overridden.
func _with_contextual_emote(message: String, event_type: String = "", actor: String = "", event_data: Dictionary = {}) -> String:
	if _emotes.is_empty() or _emote_pattern.search(message) != null:
		return message
	if actor == "system":
		return message
	var lower := message.to_lower()
	for phrase in NO_EMOTE_PHRASES:
		if lower.contains(phrase):
			return message
	var emote := _pick_contextual_emote(lower, event_type, event_data)
	if emote == "":
		return message
	if not _emotes.has(emote):
		return message
	_recent_auto_emotes.append(emote)
	while _recent_auto_emotes.size() > RECENT_AUTO_EMOTE_LIMIT:
		_recent_auto_emotes.pop_front()
	return "%s :%s:" % [message, emote]


func _pick_contextual_emote(lower: String, event_type: String, event_data: Dictionary) -> String:
	# Explicit excuses/denial in the message itself: COPIUM only.
	if _looks_like_excuse(lower):
		return _choose_fresh([EMOTE_COPIUM])

	# Match/round win.
	if event_type == "match_winner" or lower.contains("won the round") or lower.contains("won the match"):
		return _choose_fresh([EMOTE_HYPERCLAP, EMOTE_POGGERS])

	# Join / presence.
	if lower.contains("joined the party") or lower.contains("joined the game") or lower.contains("joined the match"):
		return _choose_fresh([EMOTE_POGGERS])

	# Chicken/loot steals and pickups.
	if lower.contains("stole the chicken") or lower.contains("stole the lootbox"):
		return _choose_fresh([EMOTE_PEPELAUGH, EMOTE_POGGERS])
	if lower.contains("picked the chicken") or lower.contains("picked up the chicken") or lower.contains("picked the lootbox") or lower.contains("picked up the lootbox"):
		return _choose_fresh([EMOTE_POGGERS])

	# Drops/losses of objective items.
	if lower.contains("dropped the chicken") or lower.contains("lost the chicken") \
			or lower.contains("dropped the lootbox") or lower.contains("lost the lootbox"):
		return _choose_fresh([EMOTE_PEPEHANDS, EMOTE_SADGE])

	# Eliminations / deaths.
	if lower.contains("was eliminated") or lower.contains(" eliminated "):
		# Only use HYPERKEKW when the event/message clearly signals a goofy mistake.
		if _looks_like_embarrassing_elimination(lower, event_data):
			return _choose_fresh([EMOTE_HYPERKEKW])
		return _choose_fresh([EMOTE_SADGE, EMOTE_PEPEHANDS])

	# Last survivor / clutch tension - only when the event text actually says so.
	if lower.contains("last survivor") or lower.contains("final survivor") or lower.contains("last one standing"):
		return _choose_fresh([EMOTE_MONKAS, EMOTE_GIGACHAD])

	# Survived with very little health - only when explicitly reported.
	if _looks_like_low_hp_survival(lower, event_data):
		return _choose_fresh([EMOTE_GIGACHAD])

	# Clever escape/outplay - only when explicitly reported.
	if _looks_like_clever_play(lower):
		return _choose_fresh([EMOTE_5HEAD])

	# Impressive play / outplayed - only when explicitly reported.
	if lower.contains("impressive play") or lower.contains("insane play") or lower.contains("crazy play"):
		return _choose_fresh([EMOTE_POGGERS])
	if lower.contains("got outplayed") or lower.contains("outplayed by"):
		return _choose_fresh([EMOTE_HYPERKEKW, EMOTE_SADGE])

	return ""


func _looks_like_excuse(lower: String) -> bool:
	for token in ["lag", "lagged", "desync", "ping", "excuse", "copium", "blame", "cheater", "hacker", "rigged", "bugged"]:
		if lower.contains(token):
			return true
	return false


func _looks_like_embarrassing_elimination(lower: String, event_data: Dictionary) -> bool:
	for token in ["fell off", "fell into", "missed", "oops", "accident", "clumsy", "embarrass", "own goal", "self"]:
		if lower.contains(token):
			return true
	var reason := str(event_data.get("reason", "")).to_lower()
	for token in ["fall", "void", "oops", "self"]:
		if reason.contains(token):
			return true
	return false


func _looks_like_low_hp_survival(lower: String, event_data: Dictionary) -> bool:
	if lower.contains("1 hp") or lower.contains("low hp") or lower.contains("barely survived") \
			or lower.contains("survived with"):
		return true
	var hp = event_data.get("hp", null)
	if typeof(hp) == TYPE_INT or typeof(hp) == TYPE_FLOAT:
		return float(hp) <= 1.0
	return false


func _looks_like_clever_play(lower: String) -> bool:
	for token in ["clever escape", "clever outplay", "outsmart", "outplayed", "juked", "big brain", "5head"]:
		if lower.contains(token):
			# "got outplayed" is negative, handled above; positive cleverness only.
			if lower.contains("got outplayed"):
				return false
			return true
	return false


## Picks the first candidate not used recently; if all were recent, allow the first.
func _choose_fresh(candidates: Array[String]) -> String:
	for c in candidates:
		if not _emotes.has(c):
			continue
		if not _recent_auto_emotes.has(c):
			return c
	for c in candidates:
		if _emotes.has(c):
			return c
	return ""

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
	text.add_theme_font_size_override("normal_font_size", 13)
	text.add_theme_constant_override("line_separation", 2)
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
	_sync_feed_panel()


## The chat panel hugs its messages and disappears when there is nothing to say,
## like a stream overlay that only exists while chat is moving.
func _sync_feed_panel() -> void:
	if _feed_panel == null and _feed != null:
		_feed_panel = _feed.get_parent() as Control
	if _feed_panel == null:
		return
	var countdown_visible := not _countdown_row.is_empty() \
		and (_countdown_row["root"] as Control).visible
	_feed_panel.visible = not _entries.is_empty() or countdown_visible

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
		_add_message_with_emotes(text, message, Color(1, 1, 1, FEED_SYSTEM_ALPHA))
	else:
		var color := _name_color(actor)
		text.push_color(Color(color.r, color.g, color.b, FEED_NAME_ALPHA))
		text.push_bold()
		text.add_text(actor + ":")
		text.pop()
		text.pop()
		_add_message_with_emotes(text, " " + message, Color(1, 1, 1, FEED_TEXT_ALPHA))

	if int(row["seq"]) != seq:
		row["seq"] = seq
		# Only the newest row animates in; the ones shifting up stay put.
		if seq == _entry_seq:
			_play_row_fade(row["root"])
	_fit_row_height(row)


## A RichTextLabel with autowrap reports a one-line minimum height until it has
## been laid out at its final width, which would let wrapped chat lines spill out
## of the panel. Feed the measured height back into the row so the panel hugs the
## real content, Twitch-style.
func _fit_row_height(row: Dictionary) -> void:
	await get_tree().process_frame
	var text := row.get("text") as RichTextLabel
	var root := row.get("root") as Control
	if text == null or root == null:
		return
	if not is_instance_valid(text) or not is_instance_valid(root):
		return
	if text.size.x <= 0.0:
		await get_tree().process_frame
		if not is_instance_valid(text) or not is_instance_valid(root):
			return
	var height := maxf(text.get_content_height(), AVATAR_SIZE)
	if not is_equal_approx(root.custom_minimum_size.y, height):
		root.custom_minimum_size.y = height


## Writes `message` into the row, swapping `:token:` emotes for inline images.
## Unknown tokens stay as typed text so a stray colon pair is never swallowed.
func _add_message_with_emotes(text: RichTextLabel, message: String, color: Color) -> void:
	text.push_color(color)
	var cursor := 0
	for found in _emote_pattern.search_all(message):
		var start := found.get_start(0)
		if start > cursor:
			text.add_text(message.substr(cursor, start - cursor))
		var texture := _emotes.get(found.get_string(1).to_lower()) as Texture2D
		if texture != null:
			text.add_image(texture, EMOTE_SIZE, EMOTE_SIZE)
		else:
			text.add_text(found.get_string(0))
		cursor = found.get_end(0)
	if cursor < message.length():
		text.add_text(message.substr(cursor))
	text.pop()

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
	if control.size.x <= 0.0:
		return
	# The container owns position/size, so a short scale from the right edge is
	# what reads as a chat line sliding in.
	control.pivot_offset = Vector2(control.size.x, control.size.y * 0.5)
	control.scale = Vector2(0.97, 1.0)
	var slide := create_tween()
	slide.tween_property(control, "scale", Vector2.ONE, FEED_FADE_SEC) \
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

	# Kill/steal lines are written by the player who did it, with their own name
	# in front ("tobi eliminated alice", "tobi stole the chicken from alice").
	# Split on the verb so the feed can colour the name and keep the sentence.
	var verb_splits := [
		" eliminated ",
		" stole the chicken from ",
		" stole the lootbox from ",
	]
	for sep in verb_splits:
		var idx := safe_message.find(sep)
		if idx > 0:
			var verb_actor := safe_message.substr(0, idx).strip_edges()
			var verb_rest := safe_message.substr(idx + 1).strip_edges()
			if verb_actor != "" and verb_rest != "":
				return {"actor": verb_actor, "message": verb_rest}

	# A death notice is written by the victim: "tobi was eliminated".
	if safe_message.ends_with(" was eliminated"):
		var fallen := safe_message.trim_suffix(" was eliminated").strip_edges()
		if fallen != "":
			return {"actor": fallen, "message": "was eliminated"}

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


func _try_set_username_from_auth() -> void:
	# The authenticated WON username must be used for join/display instead of the
	# server's fallback. On web the entry URL wins when it carried a name, because
	# that is what the room socket itself sends; the account is the fallback when
	# the URL did not carry one.
	if _username_locked:
		return
	if not is_instance_valid(AuthManager) or not AuthManager.is_authenticated():
		return
	var name := AuthManager.get_username().strip_edges()
	if name == "":
		return
	_username_locked = true
	set_local_username(name, true)

# Keep the events subscription in step with PlayerManager: prefer web URL match,
# else fall back to the match id handed to PlayerManager (native lobby flow/editor).
func _resolve_room_query() -> void:
	var match_id := ""
	if OS.has_feature("web"):
		var raw_match = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('match') || ''")
		if typeof(raw_match) == TYPE_STRING:
			match_id = str(raw_match).strip_edges()
	if match_id == "":
		var pm = get_tree().get_first_node_in_group("player_manager")
		if pm != null:
			match_id = str(pm.get("local_match_id")).strip_edges()
			if match_id == "":
				match_id = str(pm.get("selected_match_id")).strip_edges()
	# "default" is the shared/default room: subscribe without room filter.
	if match_id == "default":
		match_id = ""
	if match_id != "":
		_room_query = "?room=%s" % match_id.uri_encode()
