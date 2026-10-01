extends Node3D

# Godot port of the frontend `/dashboard` page (frontend/src/pages/Dashboard.tsx
# + Dashboard.css). Owns the tab / filter state, the match carousel, the store
# grid, the reward list, the rotating 3D skin preview and the play countdown.
#
# Sizing note. Dashboard.css lays the right panel out at a 1280px reference
# width and relies on --fs-zoom to shrink it, while this project runs a 500x500
# base viewport. Every dimension inside `.right-info-section` is therefore the
# CSS value multiplied by 500 / 1280 = 0.390625, which the scene bakes in for
# the static chrome and this script applies to the generated cards. Two things
# do not scale: `position: fixed` chrome (the play button, the footer buttons)
# and the stat rail, which both sit outside the zoomed panel and keep their
# native CSS size.
#
# Typography. The frontend picks a different family per surface: `font1`
# (Burbank Big Cd Bk) for the dashboard UI and `font2` (Fortnite) for the tab
# strip. Both are shipped in godot/assets/fonts so this screen can match them.
#
# Skewing note. CSS `transform: skewX()` on a card also shears that card's text,
# which the stylesheets undo with a matching counter-skew on the inner overlay.
# Godot's StyleBoxFlat.skew only shears the drawn box and leaves children alone,
# so shearing the card's stylebox already yields the frontend's net result:
# a slanted card with upright labels. The exception is `.match-card`, whose
# artwork is a child and therefore cannot be sheared at draw time; that skew is
# pre-baked into match_card_bg.png instead (see assets/img/README).

const API_BASE: String = "https://worldofnads.onrender.com"
const SKIN_SCENE: PackedScene = preload("res://scenes/skin.tscn")
const GAMEPLAY_SCENE: String = "res://scenes/gameplay.tscn"

const FONT_UI: Font = preload("res://assets/fonts/font1.ttf")
const FONT_TAB: Font = preload("res://assets/fonts/font2.ttf")
const MATCH_ART: Texture2D = preload("res://assets/img/match_card_bg.png")
const STORE_PLATE: Texture2D = preload("res://assets/img/store_info_plate.png")
const SKIN_DIR: String = "res://assets/img/skins/"

const DEFAULT_SKIN_ID: String = "s-default"
const DEFAULT_ENERGY: int = 4
const PLAY_COUNTDOWN_SECONDS: float = 4.0
const PREVIEW_SPIN_SPEED: float = 0.55

# Dashboard palette (Dashboard.css).
const C_GOLD: Color = Color(1.0, 0.84313726, 0.0, 1.0)
const C_MAGENTA: Color = Color(0.627451, 0.0, 1.0, 1.0)
const C_PIP_ON: Color = Color(0.99215686, 0.8784314, 0.2784314, 1.0)
const C_PIP_OFF: Color = Color(0.72, 0.72, 0.72, 0.2)
# .tab.active { color: var(--primary-light) } and --primary-light is
# hsl(249, 100%, 74%) in frontend/src/index.css.
const C_TAB_ACTIVE: Color = Color(0.55686277, 0.47843137, 1.0, 1.0)

# .store-tier, under `prefers-color-scheme: dark` (the scheme this screen renders).
const TIER_COLORS: Dictionary = {
	"common": Color(0.26666667, 0.26666667, 0.26666667, 1.0),
	"rare": Color(0.10196078, 0.2, 0.33333334, 1.0),
	"epic": Color(0.2, 0.10196078, 0.33333334, 1.0),
	"legendary": Color(0.33333334, 0.26666667, 0.13333334, 1.0),
}
const TIER_FONTS: Dictionary = {
	"common": Color(0.8, 0.8, 0.8, 1.0),
	"rare": Color(0.4, 0.6666667, 1.0, 1.0),
	"epic": Color(0.6666667, 0.4, 1.0, 1.0),
	"legendary": Color(1.0, 0.8, 0.26666667, 1.0),
}

const TAB_EVENTS: String = "events"
const TAB_REWARDS: String = "rewards"
const TAB_STORE: String = "store"

const EVENT_STATUSES := ["upcoming", "live", "completed"]
const STORE_TIERS := ["all", "common", "rare", "epic", "legendary"]
const DEFAULT_OWNED_IDS := ["s-default", "s-default-unshaded"]

@onready var _preview_root: Node3D = get_node_or_null("CanvasLayer/PreviewView/SubViewport/Pivot/PreviewRoot") as Node3D
@onready var _preview_pivot: Node3D = get_node_or_null("CanvasLayer/PreviewView/SubViewport/Pivot") as Node3D
@onready var _preview_view: SubViewportContainer = get_node_or_null("CanvasLayer/PreviewView") as SubViewportContainer
@onready var _preview_viewport: SubViewport = get_node_or_null("CanvasLayer/PreviewView/SubViewport") as SubViewport
@onready var _preview_camera: Camera3D = get_node_or_null("CanvasLayer/PreviewView/SubViewport/Camera3D") as Camera3D
@onready var _lobby_bg: Control = get_node_or_null("CanvasLayer/LobbyBg") as Control
@onready var _stat_rail: Control = get_node_or_null("CanvasLayer/StatRail") as Control
@onready var _energy_pips: HBoxContainer = get_node_or_null("CanvasLayer/StatRail/EnergyPill/EnergyPips") as HBoxContainer
@onready var _mon_pill: Control = get_node_or_null("CanvasLayer/StatRail/MonPill") as Control
@onready var _level_pill: Control = get_node_or_null("CanvasLayer/StatRail/LevelPill") as Control
@onready var _level_value: Label = get_node_or_null("CanvasLayer/StatRail/LevelPill/Row/LevelValue") as Label
@onready var _skin_preview: Control = get_node_or_null("CanvasLayer/SkinPreview") as Control
@onready var _skin_preview_name: Label = get_node_or_null("CanvasLayer/SkinPreview/Name") as Label
@onready var _skin_preview_meta: Label = get_node_or_null("CanvasLayer/SkinPreview/Meta") as Label

@onready var _tabs: HBoxContainer = get_node_or_null("CanvasLayer/RightPanel/Margin/Column/TabsMargin/Tabs") as HBoxContainer
@onready var _tab_badge: Label = get_node_or_null("CanvasLayer/RightPanel/Margin/Column/TabsMargin/Tabs/TabStore/Badge") as Label
@onready var _filters_events: HBoxContainer = get_node_or_null("CanvasLayer/RightPanel/Margin/Column/FiltersMargin/FiltersEvents") as HBoxContainer
@onready var _filters_store: HFlowContainer = get_node_or_null("CanvasLayer/RightPanel/Margin/Column/FiltersMargin/FiltersStore") as HFlowContainer

@onready var _match_scroll: ScrollContainer = get_node_or_null("CanvasLayer/RightPanel/Margin/Column/Content/MatchScroll") as ScrollContainer
@onready var _match_cards: HBoxContainer = get_node_or_null("CanvasLayer/RightPanel/Margin/Column/Content/MatchScroll/MatchMargin/MatchCards") as HBoxContainer
@onready var _reward_scroll: ScrollContainer = get_node_or_null("CanvasLayer/RightPanel/Margin/Column/Content/RewardScroll") as ScrollContainer
@onready var _reward_empty: Control = get_node_or_null("CanvasLayer/RightPanel/Margin/Column/Content/RewardScroll/RewardMargin/RewardList/RewardEmpty") as Control
@onready var _store_scroll: ScrollContainer = get_node_or_null("CanvasLayer/RightPanel/Margin/Column/Content/StoreScroll") as ScrollContainer
@onready var _store_grid: GridContainer = get_node_or_null("CanvasLayer/RightPanel/Margin/Column/Content/StoreScroll/StoreMargin/StoreGrid") as GridContainer
@onready var _fade_left: Control = get_node_or_null("CanvasLayer/RightPanel/Margin/Column/Content/FadeLeft") as Control
@onready var _fade_right: Control = get_node_or_null("CanvasLayer/RightPanel/Margin/Column/Content/FadeRight") as Control

@onready var _play_button: Button = get_node_or_null("CanvasLayer/PlayButton") as Button
@onready var _footer_buttons: Control = get_node_or_null("CanvasLayer/FooterButtons") as Control
@onready var _mint_button: Button = get_node_or_null("CanvasLayer/FooterButtons/MintButton") as Button
@onready var _equip_button: Button = get_node_or_null("CanvasLayer/FooterButtons/EquipButton") as Button

var _preview_player: Node3D = null
var _skin_applier: SkinApplier = SkinApplier.new()
var _tab_buttons: Dictionary = {}
var _filter_buttons: Dictionary = {}
var _texture_cache: Dictionary = {}
var _plate_gradient: GradientTexture2D = null

var tab: String = TAB_EVENTS
var filter: String = "live"
var store_filter: String = "all"

var matches: Array[Dictionary] = []
var store_items: Array[Dictionary] = []
var owned_ids: Array[String] = []
var equipped_skin_id: String = DEFAULT_SKIN_ID
var selected_match_id: String = ""
var selected_store_id: String = ""

var energy: int = DEFAULT_ENERGY
var xp: float = 0.0

var _is_counting: bool = false
var _elapsed: float = 0.0
var _navigating: bool = false


func _ready() -> void:
	owned_ids.assign(DEFAULT_OWNED_IDS)

	_connect_chrome()
	_seed_local_store()
	matches = _build_static_matches()
	selected_match_id = _fallback_match_id()

	_spawn_preview_player()
	_fetch_store_data()

	_refresh_all()

	if _preview_view != null and not _preview_view.resized.is_connected(_on_preview_resized):
		_preview_view.resized.connect(_on_preview_resized)


func _on_preview_resized() -> void:
	_frame_preview_camera()
	_layout_lobby_bg()


# ---------------------------------------------------------------- chrome wiring

func _connect_chrome() -> void:
	if _tabs != null:
		_tab_buttons = {
			TAB_EVENTS: _tabs.get_node_or_null("TabEvents"),
			TAB_REWARDS: _tabs.get_node_or_null("TabRewards"),
			TAB_STORE: _tabs.get_node_or_null("TabStore"),
		}
		for key in _tab_buttons:
			var button: Button = _tab_buttons[key]
			if button != null:
				button.pressed.connect(_on_tab_pressed.bind(str(key)))

	if _filters_events != null:
		_filter_buttons.merge({
			"upcoming": _filters_events.get_node_or_null("FilterUpcoming"),
			"live": _filters_events.get_node_or_null("FilterLive"),
			"completed": _filters_events.get_node_or_null("FilterCompleted"),
		}, true)
	if _filters_store != null:
		_filter_buttons.merge({
			"all": _filters_store.get_node_or_null("StoreAll"),
			"common": _filters_store.get_node_or_null("StoreCommon"),
			"rare": _filters_store.get_node_or_null("StoreRare"),
			"epic": _filters_store.get_node_or_null("StoreEpic"),
			"legendary": _filters_store.get_node_or_null("StoreLegendary"),
		}, true)

	for key in _filter_buttons:
		var filter_button: Button = _filter_buttons[key]
		if filter_button != null:
			filter_button.pressed.connect(_on_filter_pressed.bind(key))

	if _play_button != null:
		_play_button.pressed.connect(_on_play_pressed)
	if _mint_button != null:
		_mint_button.pressed.connect(_on_mint_pressed)
	if _equip_button != null:
		_equip_button.pressed.connect(_on_equip_pressed)


func _on_tab_pressed(next_tab: String) -> void:
	if tab == next_tab:
		return
	var previous_tab := tab
	var previous_match := selected_match_id
	tab = next_tab
	selected_match_id = ""
	selected_store_id = ""

	if tab == TAB_EVENTS:
		if previous_tab == TAB_STORE:
			# Leaving the store auto-scrolls the carousel back to the first live match.
			filter = "live"
		selected_match_id = previous_match if _match_exists(previous_match) else _fallback_match_id()

	_refresh_all()


func _on_filter_pressed(next_filter: String) -> void:
	if next_filter in STORE_TIERS:
		store_filter = next_filter
	else:
		# Mirrors jumpToStatus(): jump to the first card of that status, and fall back to
		# the filter's first match when the carousel holds none.
		filter = next_filter
		var jump_target := _first_match_id_with_status(next_filter)
		selected_match_id = jump_target if jump_target != "" else _fallback_match_id()
	_refresh_all()


# ------------------------------------------------------------------ frame loop

func _process(delta: float) -> void:
	if _preview_pivot != null:
		_preview_pivot.rotate_y(delta * PREVIEW_SPIN_SPEED)

	if _is_counting:
		_elapsed = minf(_elapsed + delta, PLAY_COUNTDOWN_SECONDS)
		if _play_button != null:
			_play_button.text = "%.1fs Cancel" % _elapsed
		if _elapsed >= PLAY_COUNTDOWN_SECONDS:
			_begin_match()
		return

	if tab == TAB_EVENTS:
		_update_play_button_text()


# --------------------------------------------------------------- 3D skin preview

func _spawn_preview_player() -> void:
	if _preview_root == null:
		return

	_preview_player = SKIN_SCENE.instantiate()
	# Set before entering the tree: player.gd skips camera and input handling for
	# non-local players, which is exactly what a passive preview wants.
	_preview_player.is_local = false
	_preview_player.display_name = ""
	_preview_root.add_child(_preview_player)

	if _preview_player.has_method("disable_character_shadows"):
		_preview_player.disable_character_shadows()

	var name_label := _preview_player.get_node_or_null("Label3D") as Label3D
	if name_label != null:
		name_label.visible = false

	_apply_preview_skin(equipped_skin_id)
	_frame_preview_camera()


# The nad is ~1.6 units tall and the preview pane is portrait, so a hand-placed camera
# transform either crops the crown or leaves the character a speck. Measuring the loaded
# mesh instead keeps the whole body framed and re-fits when the pane is resized. The 75deg
# field of view is ThreeScene's, so the perspective distortion matches the frontend.
func _frame_preview_camera() -> void:
	if _preview_camera == null or _preview_player == null:
		return

	var box := AABB()
	var has_box := false
	for node in _preview_player.find_children("*", "MeshInstance3D", true):
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		var piece: AABB = mesh_node.transform * mesh_node.get_aabb()
		if has_box:
			box = box.merge(piece)
		else:
			box = piece
			has_box = true
	if not has_box or box.size.length_squared() <= 0.0:
		return

	var center := box.get_center()
	# ThreeScene looks slightly above the model's centre (the orbit target sits at
	# eye height), which leaves headroom under the crown.
	var target := center + Vector3(0.0, box.size.y * 0.08, 0.0)
	var radius := box.size.length() * 0.5
	# _ready() runs before the first layout pass, so the pane can still be unsized here.
	# _on_preview_resized() re-frames once the container settles.
	var pane_size := Vector2(325, 500)
	if _preview_viewport != null:
		var measured := Vector2(_preview_viewport.size)
		if measured.x > 0.0 and measured.y > 0.0:
			pane_size = measured
	# Camera3D.keep_aspect defaults to KEEP_HEIGHT, so on a portrait pane the vertical
	# FOV is the one that runs out first. Both limits are floored so a degenerate pane
	# cannot collapse the distance to zero.
	var half_vertical := deg_to_rad(_preview_camera.fov * 0.5)
	var half_horizontal := atan(tan(half_vertical) * clampf(pane_size.x / pane_size.y, 0.1, 10.0))
	var limiting := maxf(minf(half_vertical, half_horizontal), deg_to_rad(5.0))
	var distance := radius / sin(limiting) * 1.15

	_preview_camera.position = target + Vector3(0.0, distance * 0.08, distance)
	_preview_camera.look_at(target, Vector3.UP)


# `.lobby-bg img` is width:100% with a height derived from the source aspect, centred
# vertically in the pane. Mirroring that here keeps the art from stretching.
func _layout_lobby_bg() -> void:
	if _lobby_bg == null:
		return
	var rect := _lobby_bg as TextureRect
	var preview_width := get_viewport().get_visible_rect().size.x * 0.65
	if _preview_view != null and _preview_view.size.x > 0.0:
		preview_width = _preview_view.size.x
	if rect == null or rect.texture == null:
		return
	var tex := rect.texture
	var height := preview_width * float(tex.get_height()) / float(maxi(tex.get_width(), 1))
	rect.offset_top = -height * 0.5
	rect.offset_bottom = height * 0.5


func _apply_preview_skin(skin_id: String) -> void:
	if _preview_player == null:
		return
	_skin_applier.apply_skin(_preview_player, skin_id)


# ------------------------------------------------------------------- store data

func _seed_local_store() -> void:
	# Mirrors frontend/src/data/items.json, the local fallback the dashboard shows
	# until GET /api/skins resolves.
	store_items.clear()
	store_items.append({
		"id": "s-default",
		"name": "Default Nad",
		"price": "0 MON",
		"image": "/skins_png/s-default.png",
		"tier": "common",
		"required_xp": 0,
		"max_supply": 0,
	})
	store_items.append({
		"id": "s-default-unshaded",
		"name": "Default Nad (Flat)",
		"price": "0 MON",
		"image": "/skins_png/s-default.png",
		"tier": "common",
		"required_xp": 0,
		"max_supply": 0,
	})


func _fetch_store_data() -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_store_data_fetched.bind(http))
	http.request("%s/api/skins" % API_BASE)


func _on_store_data_fetched(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	if http != null and is_instance_valid(http):
		http.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		print("Dshbord: store API fetch failed (%d %d), keeping bundled fallback." % [result, response_code])
		return

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary) or parsed.get("ok") != true:
		return
	var api_skins: Variant = parsed.get("skins")
	if not (api_skins is Array):
		return

	var by_id: Dictionary = {}
	for item in store_items:
		by_id[item.get("id", "")] = item

	for skin in api_skins:
		if not (skin is Dictionary):
			continue
		var skin_id: String = str(skin.get("id", ""))
		if skin_id == "":
			continue
		by_id[skin_id] = {
			"id": skin_id,
			"name": str(skin.get("name", "Unknown")),
			"price": str(skin.get("price", "0 MON")),
			"image": str(skin.get("image", "/skins_png/%s.png" % skin_id)),
			"tier": str(skin.get("tier", "common")).to_lower(),
			"required_xp": int(skin.get("requiredXP", 0)),
			"max_supply": int(skin.get("maxSupply", 0)),
		}

	SkinApplier.seed_from_api(api_skins)

	store_items.clear()
	for key in by_id:
		store_items.append(by_id[key])

	_apply_preview_skin(_displayed_skin_id())
	_refresh_all()


# ---------------------------------------------------------------------- matches

func _build_static_matches() -> Array[Dictionary]:
	# Port of frontend/src/pages/staticMatches.js. The JS derives start times from
	# Date.now(), so they are re-derived here against the system clock.
	var now := float(Time.get_unix_time_from_system())
	var out: Array[Dictionary] = []
	out.append({
		"match_id": "match-champions-cup",
		"sponsor": "WONs Major",
		"prize": "10K WONs",
		"status": "upcoming",
		"start_time": now + 172800.0,
		"description": "The WONs Major Championship Cup. Winner takes home 10K WONs.",
		"cta_mode": "countdown",
	})
	out.append({
		"match_id": "match-training-lobby",
		"sponsor": "Training Lobby",
		"prize": "Practice",
		"status": "live",
		"start_time": now,
		"description": "Training Lobby is open for warmup runs and should always be playable.",
		"cta_mode": "play",
	})
	out.append({
		"match_id": "match-sunset-showdown",
		"sponsor": "NadCity Arena",
		"prize": "1.5K WONs",
		"status": "live",
		"start_time": now + 300.0,
		"description": "Sunset Showdown at NadCity Arena. First to flag takes the 1.5K WONs pot.",
		"cta_mode": "countdown",
	})
	out.append({
		"match_id": "match-weekend-clash",
		"sponsor": "Monad Labs",
		"prize": "3K WONs",
		"status": "live",
		"start_time": now + 1800.0,
		"description": "The Weekend Clash is live. Cash prizes for the top 3 flags planted.",
		"cta_mode": "countdown",
	})
	out.append({
		"match_id": "match-alpha-sprint",
		"sponsor": "Alpha Sprint",
		"prize": "500 WONs",
		"status": "completed",
		"start_time": now - 172800.0,
		"description": "Alpha Sprint is done - check the leaderboard for the final standings.",
		"cta_mode": "countdown",
	})
	# The frontend sorts the carousel by status order (upcoming, live, completed) and then
	# by start time, so the matches above are appended in the order they should display.
	return out


func _match_exists(match_id: String) -> bool:
	return match_id != "" and not _selected_match_of(match_id).is_empty()


func _selected_match_of(match_id: String) -> Dictionary:
	for match in matches:
		if str(match.get("match_id", "")) == match_id:
			return match
	return {}


func _first_match_id_with_status(status: String) -> String:
	for match in matches:
		if str(match.get("status", "")) == status:
			return str(match.get("match_id", ""))
	return ""


func _fallback_match_id() -> String:
	var candidate := _first_match_id_with_status(filter)
	if candidate != "":
		return candidate
	if not matches.is_empty():
		return str(matches[0].get("match_id", ""))
	return ""


func _selected_match() -> Dictionary:
	return _selected_match_of(selected_match_id)


# ---------------------------------------------------------------------- refresh

func _refresh_all() -> void:
	_refresh_tabs()
	_refresh_filters()
	_refresh_matches()
	_refresh_rewards()
	_refresh_store()
	_refresh_stat_rail()
	_refresh_skin_preview()
	_refresh_play_button()
	_refresh_footer()
	_layout_lobby_bg()


func _refresh_tabs() -> void:
	for key in _tab_buttons:
		_set_tab_active(_tab_buttons[key], str(key) == tab)
	if _tab_badge != null:
		_tab_badge.text = str(_new_store_item_count())


func _new_store_item_count() -> int:
	# Dashboard.tsx counts everything the player does not already hold.
	var count := 0
	for item in store_items:
		if not _is_owned(item):
			count += 1
	return count


func _refresh_filters() -> void:
	var events_visible := tab == TAB_EVENTS
	var store_visible := tab == TAB_STORE
	if _filters_events != null:
		_filters_events.visible = events_visible
	if _filters_store != null:
		_filters_store.visible = store_visible

	if events_visible:
		for status in EVENT_STATUSES:
			_set_filter_active(_filter_buttons.get(status), str(filter) == status)
	else:
		for tier in STORE_TIERS:
			_set_filter_active(_filter_buttons.get(tier), str(store_filter) == tier)


func _refresh_matches() -> void:
	var showing := tab == TAB_EVENTS
	if _match_scroll != null:
		_match_scroll.visible = showing
	# `.matches-wrapper` (and its edge fades) only wraps the events carousel.
	if _fade_left != null:
		_fade_left.visible = showing
	if _fade_right != null:
		_fade_right.visible = showing
	if _match_cards == null:
		return

	for child in _match_cards.get_children():
		_match_cards.remove_child(child)
		child.queue_free()

	for match in matches:
		_match_cards.add_child(_build_match_card(match))

	_center_selected_card_deferred()


func _build_match_card(match: Dictionary) -> Control:
	var match_id: String = str(match.get("match_id", ""))
	var status: String = str(match.get("status", "live"))
	var selected := match_id == selected_match_id
	# `.grayscale-card .match-sponsor / .match-reward / .match-details-inner` all drop
	# to black on a completed card.
	var text_color := Color(0, 0, 0, 1) if status == "completed" else Color(1, 1, 1, 1)

	# `.match-card` is 330x220 in the CSS and carries `scale: 0.9`, so the layout
	# slot is 129x86 here while the art it draws is 116x77. A Panel (not a
	# PanelContainer) is used so the artwork can centre itself in the slot while
	# the content plate pins to the bottom edge.
	var card := Panel.new()
	card.set_meta("match_id", match_id)
	card.custom_minimum_size = Vector2(129, 86)
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", _match_card_style(selected))

	var art := TextureRect.new()
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.texture = MATCH_ART
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(art)

	# `.match-reward` - dark prize pill pinned to the top-right corner. It renders
	# upright because .match-card-overlay counter-skews the card, so it is left
	# unskewed here too.
	var prize := Label.new()
	prize.text = str(match.get("prize", ""))
	prize.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	prize.offset_left = -4.0
	prize.offset_top = 4.0
	prize.offset_right = -4.0
	prize.offset_bottom = 4.0
	prize.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	prize.grow_vertical = Control.GROW_DIRECTION_END
	prize.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prize.add_theme_font_size_override("font_size", 4)
	prize.add_theme_color_override("font_color", text_color)
	prize.add_theme_stylebox_override("normal", _prize_style())
	_apply_font(prize, FONT_UI)
	card.add_child(prize)

	# `.match-card-content` - purple gradient plate along the bottom edge.
	var plate := PanelContainer.new()
	plate.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	plate.offset_top = 0.0
	plate.offset_bottom = 0.0
	plate.grow_vertical = Control.GROW_DIRECTION_BEGIN
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel", _empty_style())
	card.add_child(plate)

	# The linear-gradient(to top, rgba(160,0,255,.75) ...) sits behind the text and
	# spans the whole plate, so it is a sibling drawn first.
	var plate_bg := TextureRect.new()
	plate_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plate_bg.texture = _get_plate_gradient()
	plate_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate_bg.stretch_mode = TextureRect.STRETCH_SCALE
	plate_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(plate_bg)

	var padding := MarginContainer.new()
	padding.mouse_filter = Control.MOUSE_FILTER_IGNORE
	padding.add_theme_constant_override("margin_left", 5)
	padding.add_theme_constant_override("margin_top", 7)
	padding.add_theme_constant_override("margin_right", 5)
	padding.add_theme_constant_override("margin_bottom", 4)
	plate.add_child(padding)

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 1)
	padding.add_child(content)

	if status == "completed":
		# `.match-card[data-status="completed"]` is grayscale(100%) brightness(0.7),
		# which a modulate approximates for the artwork and the text alike.
		card.modulate = Color(0.7, 0.7, 0.7, 0.5 if not selected else 1.0)
	elif not selected:
		# `.match-card` rests at opacity 0.5; the selected card lifts to 1.
		card.modulate = Color(1, 1, 1, 0.5)

	if selected:
		# Selected cards swap the sponsor for the description (see Dashboard.tsx).
		var desc := Label.new()
		desc.text = str(match.get("description", ""))
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.max_lines_visible = 5
		desc.add_theme_font_size_override("font_size", 4)
		desc.add_theme_color_override("font_color", text_color if status == "completed" else Color(1, 1, 1, 0.9))
		_apply_font(desc, FONT_UI)
		content.add_child(desc)
	else:
		var sponsor := Label.new()
		sponsor.text = str(match.get("sponsor", "")).to_upper()
		sponsor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sponsor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sponsor.add_theme_font_size_override("font_size", 6)
		sponsor.add_theme_color_override("font_color", text_color)
		_apply_font(sponsor, FONT_UI)
		content.add_child(sponsor)

	card.gui_input.connect(_on_match_card_input.bind(match_id))
	card.mouse_entered.connect(_on_match_card_enter.bind(card))
	card.mouse_exited.connect(_on_match_card_exit.bind(card))
	return card


func _on_match_card_input(event: InputEvent, match_id: String) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			selected_match_id = match_id
			filter = str(_selected_match().get("status", filter))
			_refresh_all()


func _on_match_card_enter(card: Control) -> void:
	# `.match-card:hover` lifts to full opacity and scales to 1.08 about its centre.
	card.modulate.a = 1.0
	card.pivot_offset = card.size * 0.5
	card.scale = Vector2(1.08, 1.08)


func _on_match_card_exit(card: Control) -> void:
	card.scale = Vector2.ONE
	# `.match-card` rests at opacity 0.5 whether or not it is a completed match.
	if str(card.get_meta("match_id", "")) != selected_match_id:
		card.modulate.a = 0.5


func _center_selected_card_deferred() -> void:
	# Cards are freed with queue_free() and the containers only settle their layout
	# on the following frames, so wait for the tree to drain before measuring.
	await get_tree().process_frame
	await get_tree().process_frame
	if _match_scroll == null or _match_cards == null:
		return

	var target_x := -1
	for child in _match_cards.get_children():
		var control := child as Control
		if control == null:
			continue
		if str(control.get_meta("match_id", "")) == selected_match_id:
			var scroll_rect := _match_scroll.get_global_rect()
			var card_rect := control.get_global_rect()
			var leading := card_rect.position.x - scroll_rect.position.x + _match_scroll.scroll_horizontal
			target_x = int(leading + card_rect.size.x * 0.5 - scroll_rect.size.x * 0.5)
			break

	if target_x > 0:
		_match_scroll.scroll_horizontal = target_x


func _refresh_rewards() -> void:
	if _reward_scroll != null:
		_reward_scroll.visible = tab == TAB_REWARDS
	if _reward_empty != null:
		_reward_empty.visible = true


func _refresh_store() -> void:
	if _store_scroll != null:
		_store_scroll.visible = tab == TAB_STORE
	if _store_grid == null:
		return

	for child in _store_grid.get_children():
		_store_grid.remove_child(child)
		child.queue_free()

	for item in store_items:
		if store_filter != "all" and str(item.get("tier", "")) != store_filter:
			continue
		_store_grid.add_child(_build_store_card(item))


func _build_store_card(item: Dictionary) -> Control:
	var item_id: String = str(item.get("id", ""))
	var tier: String = str(item.get("tier", "common"))
	var selected := item_id == selected_store_id
	var owned := _is_owned(item)

	# `.store-grid` is three 1fr tracks with a 10px gap, and the card carries a 5px
	# margin, so each 51px track here holds a 47x43 card.
	var card := Panel.new()
	card.set_meta("item_id", item_id)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", _store_card_style(selected))
	# The 5px CSS margin lives on a MarginContainer cell so GridContainer can fit the
	# cell to the whole track. A plain Control sits between the cell and the card:
	# Container::fit_child_in_rect resets the direct child's scale on every layout
	# pass, which would otherwise wipe `.store-card.selected`'s scale(1.1).
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(47, 43)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cell := MarginContainer.new()
	cell.add_theme_constant_override("margin_left", 2)
	cell.add_theme_constant_override("margin_top", 2)
	cell.add_theme_constant_override("margin_right", 2)
	cell.add_theme_constant_override("margin_bottom", 2)
	cell.add_child(holder)
	holder.add_child(card)
	# `.store-card` rests at opacity 0.7 and `.unowned` pulls it to 0.62; the
	# selected card is forced back to 1 regardless of ownership.
	if not selected:
		card.modulate = Color(1, 1, 1, 0.62 if not owned else 0.7)
	# `.store-card.selected` rests at scale(1.1) and, being declared after
	# `:hover` at equal specificity, outranks the hover scale too. `resized` can
	# already have fired while the card was mounted into the cell, so resolve the
	# resting transform once eagerly as well.
	card.resized.connect(_apply_store_card_rest.bind(card))
	_apply_store_card_rest(card)

	# `.store-card-image` is height:100% with background-size: contain, so the
	# sprite fills the card's height and the caption is laid over its bottom half.
	var art := TextureRect.new()
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.texture = _skin_texture(item, not owned)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(art)

	# `.item-badge.badge-store` - the "new" flag, top-right, only while unowned.
	if not owned:
		var badge := Label.new()
		badge.text = "NEW"
		badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		badge.offset_left = -3.0
		badge.offset_top = 3.0
		badge.offset_right = -3.0
		badge.offset_bottom = 3.0
		badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		badge.grow_vertical = Control.GROW_DIRECTION_END
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_font_size_override("font_size", 3)
		badge.add_theme_color_override("font_color", Color(0, 0, 0, 1))
		badge.add_theme_stylebox_override("normal", _store_badge_style())
		_apply_font(badge, FONT_UI)
		card.add_child(badge)

	# `.store-card-info` - the angled caption plate along the bottom edge. Its
	# clip-path and gradient are pre-baked into store_info_plate.png; the node
	# itself only carries the padding.
	var info := PanelContainer.new()
	info.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	info.offset_top = 0.0
	info.offset_bottom = 0.0
	info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_theme_stylebox_override("panel", _empty_style())
	card.add_child(info)

	var plate := TextureRect.new()
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plate.texture = STORE_PLATE
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.stretch_mode = TextureRect.STRETCH_SCALE
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(plate)

	var padding := MarginContainer.new()
	padding.mouse_filter = Control.MOUSE_FILTER_IGNORE
	padding.add_theme_constant_override("margin_left", 2)
	padding.add_theme_constant_override("margin_top", 5)
	padding.add_theme_constant_override("margin_right", 2)
	padding.add_theme_constant_override("margin_bottom", 2)
	info.add_child(padding)

	var caption := VBoxContainer.new()
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.alignment = BoxContainer.ALIGNMENT_END
	caption.add_theme_constant_override("separation", 0)
	padding.add_child(caption)

	var name_label := Label.new()
	name_label.text = str(item.get("name", ""))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", 4)
	name_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_apply_font(name_label, FONT_UI)
	caption.add_child(name_label)

	# `.store-card-info p` - "Owned" in place of the price once the skin is held. The
	# dark colour scheme overrides the #ff2496 pink to white.
	var price_label := Label.new()
	price_label.text = "OWNED" if owned else str(item.get("price", "")).to_upper()
	price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_label.clip_text = true
	price_label.add_theme_font_size_override("font_size", 4)
	price_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_apply_font(price_label, FONT_UI)
	caption.add_child(price_label)

	if tier != "":
		var tier_label := Label.new()
		tier_label.text = tier.to_upper()
		tier_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tier_label.add_theme_font_size_override("font_size", 3)
		tier_label.add_theme_color_override("font_color", TIER_FONTS.get(tier, Color.WHITE))
		tier_label.add_theme_stylebox_override("normal", _tier_style(tier))
		_apply_font(tier_label, FONT_UI)
		caption.add_child(tier_label)

	# `.xp-requirement` - "Lvl N required", shown only while the skin is unowned and
	# the requirement is above zero.
	var required_xp := int(item.get("required_xp", 0))
	if required_xp > 0 and not owned:
		var xp_label := Label.new()
		xp_label.text = "Lvl %d required" % _level_for_xp(required_xp)
		xp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		xp_label.clip_text = true
		xp_label.add_theme_font_size_override("font_size", 3)
		var xp_met := xp >= float(required_xp)
		xp_label.add_theme_color_override("font_color", C_GOLD if xp_met else Color(1, 1, 1, 0.7))
		_apply_font(xp_label, FONT_UI)
		caption.add_child(xp_label)

	card.gui_input.connect(_on_store_card_input.bind(item_id))
	card.mouse_entered.connect(_on_store_card_enter.bind(card))
	card.mouse_exited.connect(_on_store_card_exit.bind(card))
	return cell


func _on_store_card_input(event: InputEvent, item_id: String) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			selected_store_id = item_id
			_apply_preview_skin(item_id)
			_refresh_store()
			_refresh_skin_preview()
			_refresh_footer()


func _apply_store_card_rest(card: Control) -> void:
	# `resized` also fires on the very first layout pass, which is the only moment
	# the half-size pivot can be resolved.
	card.pivot_offset = card.size * 0.5
	card.scale = _store_card_rest_scale(card)


func _store_card_rest_scale(card: Control) -> Vector2:
	if str(card.get_meta("item_id", "")) == selected_store_id:
		return Vector2(1.1, 1.1)
	return Vector2.ONE


func _on_store_card_enter(card: Control) -> void:
	# `.store-card:hover` lifts to full opacity and scales to 1.05, but a selected
	# card keeps the higher `scale(1.1)` from `.store-card.selected`.
	card.modulate.a = 1.0
	card.pivot_offset = card.size * 0.5
	if str(card.get_meta("item_id", "")) == selected_store_id:
		card.scale = Vector2(1.1, 1.1)
	else:
		card.scale = Vector2(1.05, 1.05)


func _on_store_card_exit(card: Control) -> void:
	var item_id := str(card.get_meta("item_id", ""))
	card.pivot_offset = card.size * 0.5
	card.scale = _store_card_rest_scale(card)
	if item_id == selected_store_id:
		card.modulate.a = 1.0
		return
	# `.store-card` rests at opacity 0.7 and `.unowned` pulls it to 0.62.
	card.modulate.a = 0.7 if owned_ids.has(item_id) else 0.62


func _is_owned(item: Dictionary) -> bool:
	return owned_ids.has(str(item.get("id", "")))


# ------------------------------------------------------------------- stat rail

func _refresh_stat_rail() -> void:
	if _energy_pips != null:
		var pips := _energy_pips.get_children()
		for i in pips.size():
			var pip := pips[i] as TextureRect
			if pip == null:
				continue
			# `.stat-pip.filled` is a saturated gold filter; unfilled pips drop to
			# opacity 0.2, go grayscale and shrink to 85%.
			if i < energy:
				pip.modulate = C_PIP_ON
				pip.scale = Vector2.ONE
			else:
				pip.modulate = C_PIP_OFF
				pip.scale = Vector2(0.85, 0.85)

	if _level_value != null:
		_level_value.text = str(_level_from_xp(xp))

	# Dashboard.tsx only renders the rail outside the store tab, and only inside it when a
	# MON balance exists to show. There is no wallet here, so the store tab hides it.
	if _mon_pill != null:
		_mon_pill.visible = false
	if _level_pill != null:
		_level_pill.visible = true
	if _stat_rail != null:
		_stat_rail.visible = tab != TAB_STORE


func _refresh_skin_preview() -> void:
	var visible := tab == TAB_STORE and selected_store_id != ""
	if _skin_preview != null:
		_skin_preview.visible = visible
	# `{tab !== "store" && <div className="lobby-bg">}` - the backdrop only shows
	# while the preview pane is showing the gallery background.
	if _lobby_bg != null:
		_lobby_bg.visible = tab != TAB_STORE
	if not visible:
		return

	var item := _selected_store_item()
	if _skin_preview_name != null:
		_skin_preview_name.text = str(item.get("name", ""))
	if _skin_preview_meta != null:
		_skin_preview_meta.text = "Owned" if _is_owned(item) else str(item.get("price", ""))


# ---------------------------------------------------------------- play + footer

func _refresh_play_button() -> void:
	var show_button := tab == TAB_EVENTS and selected_match_id != ""
	if _play_button != null:
		_play_button.visible = show_button
		_play_button.disabled = not _can_play()
		# .play-fixed.disabled dims the whole button to 0.5 on top of its white ring.
		_play_button.modulate = Color(1, 1, 1, 0.5) if _play_button.disabled else Color(1, 1, 1, 1)
	_update_play_button_text()


func _update_play_button_text() -> void:
	if _play_button == null:
		return
	if _is_counting:
		_play_button.text = "%.1fs Cancel" % _elapsed
		return

	var match := _selected_match()
	if match.is_empty():
		_play_button.text = "READY!"
		return

	var start_time := float(match.get("start_time", 0.0))
	var remaining := start_time - float(Time.get_unix_time_from_system())

	if str(match.get("cta_mode", "")) == "play":
		_play_button.text = "READY!"
	elif remaining > 0.0:
		_play_button.text = "Starts in: %s" % _format_countdown(remaining)
	else:
		_play_button.text = "Not Live"


func _can_play() -> bool:
	# Mirrors canPlay from Dashboard.tsx: the training lobby is always playable, anything
	# else once its start time has passed. A completed match never becomes playable, even
	# though its start time is in the past.
	var match := _selected_match()
	if match.is_empty():
		return false
	if str(match.get("cta_mode", "")) == "play":
		return true
	if str(match.get("status", "")) == "completed":
		return false
	return float(Time.get_unix_time_from_system()) >= float(match.get("start_time", 0.0))


func _on_play_pressed() -> void:
	if _is_counting:
		_is_counting = false
		_elapsed = 0.0
		_update_play_button_text()
		return
	if not _can_play() or selected_match_id == "":
		return

	_is_counting = true
	_elapsed = 0.0
	_update_play_button_text()


func _begin_match() -> void:
	if _navigating:
		return
	_navigating = true
	_is_counting = false

	var skin_id := _displayed_skin_id()
	get_tree().set_meta("selected_match_id", selected_match_id)
	get_tree().set_meta("selected_skin_id", skin_id)

	if OS.has_feature("web"):
		# lobby.gd reads ?skin= straight off window.location, so mirror the
		# frontend's /play?match=...&skin=... hand-off without reloading the page.
		JavaScriptBridge.eval(
			"window.history.replaceState({}, '', window.location.pathname + '?match=%s&skin=%s');"
			% [selected_match_id.uri_encode(), skin_id.uri_encode()]
		)

	Game.transition_layer.change_scene(GAMEPLAY_SCENE)


func _refresh_footer() -> void:
	var show_footer := tab == TAB_STORE and selected_store_id != ""
	if _footer_buttons != null:
		_footer_buttons.visible = show_footer
	if not show_footer:
		return

	var item := _selected_store_item()
	var owned := _is_owned(item)
	var required_xp := float(item.get("required_xp", 0))

	if _mint_button != null:
		_mint_button.visible = true
		_mint_button.disabled = not owned and xp < required_xp
		if owned:
			_mint_button.text = "EQUIP"
		elif xp >= required_xp:
			_mint_button.text = "MINT"
		else:
			_mint_button.text = "Need Lvl %d" % _level_for_xp(required_xp)

	if _equip_button != null:
		_equip_button.visible = owned
		_equip_button.disabled = not owned


func _on_mint_pressed() -> void:
	var item := _selected_store_item()
	if item.is_empty():
		return
	if _is_owned(item):
		_equip_selected_skin()
		return
	# Minting is an on-chain transaction and is out of scope for the Godot port;
	# the button stays disabled until XP meets the requirement.
	_mint_button.disabled = true


func _on_equip_pressed() -> void:
	_equip_selected_skin()


func _equip_selected_skin() -> void:
	var item := _selected_store_item()
	if item.is_empty():
		return
	var item_id := str(item.get("id", ""))
	if not owned_ids.has(item_id):
		owned_ids.append(item_id)
	equipped_skin_id = item_id
	selected_store_id = ""
	_apply_preview_skin(item_id)
	_refresh_all()


# ------------------------------------------------------------------- skin state

func _selected_store_item() -> Dictionary:
	for item in store_items:
		if str(item.get("id", "")) == selected_store_id:
			return item
	return {}


func _displayed_skin_id() -> String:
	if tab == TAB_STORE and selected_store_id != "":
		return selected_store_id
	return equipped_skin_id


# ---------------------------------------------------------------- skin artwork

func _skin_basename(item: Dictionary) -> String:
	# getStoreImageUrl() falls back to /skins_png/<id>.png, and the API serves
	# /skins_png/<file>.png, so both routes reduce to the same lookup here.
	var image := str(item.get("image", ""))
	if image != "":
		var base := image.get_file().get_basename()
		if base != "":
			return base
	return str(item.get("id", ""))


func _skin_texture(item: Dictionary, grayscale: bool) -> Texture2D:
	var base := _skin_basename(item)
	if grayscale:
		var gray := _load_texture(SKIN_DIR + base + "_gray.png")
		if gray != null:
			return gray
	return _load_texture(SKIN_DIR + base + ".png")


func _load_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		var loaded: Resource = load(path)
		if loaded is Texture2D:
			texture = loaded as Texture2D
	_texture_cache[path] = texture
	return texture


func _get_plate_gradient() -> GradientTexture2D:
	if _plate_gradient != null:
		return _plate_gradient
	# .match-card-content background:
	#   linear-gradient(to top, rgba(160,0,255,.75) 0%, rgba(160,0,255,.3) 50%, transparent 100%)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gradient.colors = PackedColorArray([
		Color(C_MAGENTA.r, C_MAGENTA.g, C_MAGENTA.b, 0.75),
		Color(C_MAGENTA.r, C_MAGENTA.g, C_MAGENTA.b, 0.3),
		Color(C_MAGENTA.r, C_MAGENTA.g, C_MAGENTA.b, 0.0),
	])
	_plate_gradient = GradientTexture2D.new()
	_plate_gradient.gradient = gradient
	_plate_gradient.width = 8
	_plate_gradient.height = 128
	_plate_gradient.fill = GradientTexture2D.FILL_LINEAR
	_plate_gradient.fill_from = Vector2(0.0, 1.0)
	_plate_gradient.fill_to = Vector2(0.0, 0.0)
	return _plate_gradient


# -------------------------------------------------------------------- utilities

func _apply_font(control: Control, font: Font) -> void:
	if font != null:
		control.add_theme_font_override("font", font)


func _level_from_xp(value: float) -> int:
	# Mirrors the Dashboard.tsx level loop: each level segment costs 10 * (n + 1). The
	# segment cost is recomputed per pass, so the loop condition carries the whole body
	# and the return sits outside it (GDScript will not accept `while true` as proof that
	# every path returns).
	var level := 0
	var remaining := value
	while remaining >= 10.0 * (level + 1):
		remaining -= 10.0 * (level + 1)
		level += 1
	return level


func _level_for_xp(value: float) -> int:
	# Mirrors getLevelFromXP() from Dashboard.tsx.
	if value <= 0.0:
		return 1
	return int(floor(sqrt(value / 100.0))) + 1


func _format_countdown(remaining_seconds: float) -> String:
	var total := int(floor(maxf(remaining_seconds, 0.0)))
	var hours := total / 3600
	var minutes := (total % 3600) / 60
	var seconds := total % 60
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, seconds]
	return "%d:%02d" % [minutes, seconds]


func _set_tab_active(button: Button, active: bool) -> void:
	if button == null:
		return
	# .tab { opacity 0.35; scale 0.8 } and .tab.active { opacity 1; scale 1.2 } at a
	# 1.8rem font size. An HBoxContainer owns position and size but not `scale`, and
	# scaling a packed button bleeds over its neighbours, so the emphasis is carried
	# by the font size the two scales resolve to: 28.8 * 0.8 and 28.8 * 1.2 scaled
	# into this viewport.
	button.modulate = Color(1, 1, 1, 1) if active else Color(1, 1, 1, 0.35)
	button.add_theme_font_size_override("font_size", 14 if active else 9)
	button.add_theme_color_override("font_color", C_TAB_ACTIVE if active else Color(1, 1, 1, 1))


func _set_filter_active(button: Button, active: bool) -> void:
	if button == null:
		return
	# .filter { opacity: 0.5 } with .filter.active at 1 plus a #00000020 fill and a
	# dark rgba(0,0,0,0.463) label. Nothing overrides that in dark mode.
	button.modulate = Color(1, 1, 1, 1) if active else Color(1, 1, 1, 0.5)
	button.add_theme_color_override("font_color", Color(0, 0, 0, 0.463) if active else Color(1, 1, 1, 1))
	button.add_theme_stylebox_override("normal", _filter_style(active))


# --------------------------------------------------------------- style factories

func _empty_style() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


func _badge_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.content_margin_left = 2.0
	style.content_margin_right = 2.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	return style


func _store_badge_style() -> StyleBoxFlat:
	# .item-badge.badge-store: gold pill, full radius, 2px 8px padding. It sits in
	# .store-card-image, which counter-skews the card, so it renders upright.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.92156863, 0.23137255, 1.0)
	style.set_corner_radius_all(9)
	style.content_margin_left = 3.0
	style.content_margin_right = 3.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	return style


func _tier_style(tier: String) -> StyleBoxFlat:
	# .store-tier: 0 6px horizontal padding, 2px radius, line-height 1.6. At this
	# scale the 6px padding folds down to a hairline either side of the text.
	var style := StyleBoxFlat.new()
	style.bg_color = TIER_COLORS.get(tier, Color(0, 0, 0, 0.5))
	style.set_corner_radius_all(2)
	style.content_margin_left = 2.0
	style.content_margin_right = 2.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	return style


func _filter_style(active: bool) -> StyleBoxFlat:
	# .filter has no background of its own; only .filter.active fills #00000020.
	# Padding is 2px 5px at the reference width, which lands on 1px/2px here.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.125) if active else Color(0, 0, 0, 0)
	style.content_margin_left = 2.0
	style.content_margin_right = 2.0
	style.content_margin_top = 1.0
	style.content_margin_bottom = 1.0
	return style


func _prize_style() -> StyleBoxFlat:
	# .match-reward: rgba(0,0,0,.55) plate with a 6px radius and 4px 8px padding.
	# It lives inside .match-card-overlay, which counter-skews the card, so unlike
	# the card itself the badge renders upright.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.55)
	style.set_corner_radius_all(2)
	style.content_margin_left = 3.0
	style.content_margin_right = 3.0
	style.content_margin_top = 1.0
	style.content_margin_bottom = 1.0
	return style


func _match_card_style(selected: bool) -> StyleBoxFlat:
	# .match-card draws no box of its own - the artwork is the card - so this only
	# carries the selected card's purple glow. The skew lives in the texture.
	var style := StyleBoxFlat.new()
	if selected:
		style.shadow_color = Color(C_MAGENTA.r, C_MAGENTA.g, C_MAGENTA.b, 0.45)
		style.shadow_size = 8
		style.shadow_offset = Vector2(0.0, 3.0)
	return style


func _store_card_style(selected: bool) -> StyleBoxFlat:
	# .store-card: radius 0, skewX(-5deg) with the image and info counter-skewed by
	# 5deg, which comes free here because Godot only shears the stylebox.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.125)
	style.skew = Vector2(0.0872665, 0.0)
	if selected:
		style.border_color = Color(1, 1, 1, 1)
		style.set_border_width_all(1)
	else:
		style.border_color = Color(1, 1, 1, 0)
		style.set_border_width_all(2)
	return style
