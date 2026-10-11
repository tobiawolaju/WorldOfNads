extends Node3D

# Godot port of the frontend `/dashboard` page (frontend/src/pages/Dashboard.tsx
# + Dashboard.css). Owns the tab / filter state, the match carousel, the store
# grid, the reward list, the rotating 3D skin preview and the play countdown.
#
# Sizing note. Dashboard.css lays the right panel out at a 1280px reference
# width and relies on --fs-zoom to shrink it, while this project runs a 500x500
# base viewport. Every dimension inside `.right-info-section` is therefore the
# CSS value multiplied by 500 / 1280 = 0.390625, which the scene bakes in for
# the static chrome and this script applies to the generated cards. Because the
# panel is 35% of the window, that base size only fills it at the 500px base
# viewport, so _layout_panel_zoom() rescales the whole panel content by
# `panel_width / 175` (see BASE_PANEL_WIDTH). Two things stay at native CSS size
# instead: `position: fixed` chrome (the play button, the footer buttons) and the
# stat rail, which both sit outside the zoomed panel, matching the frontend where
# --fs-zoom only scales `.right-info-zoom`.
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
# artwork is a child and therefore cannot be sheared at draw time; that card is
# drawn by assets/shaders/match_card.gdshader, which bakes the scale, the skew,
# the radial dissolve, the halftone rim and the overlay into the artwork.

const API_BASE: String = "https://worldofnads.onrender.com"
const SKIN_SCENE: PackedScene = preload("res://scenes/skin.tscn")
const LOBBY_SCENE: String = "res://scenes/lobby.tscn"

const FONT_UI: Font = preload("res://assets/fonts/font1.ttf")
const FONT_TAB: Font = preload("res://assets/fonts/font2.ttf")
const MATCH_SRC: Texture2D = preload("res://assets/img/lobbybg.jpeg")
const MATCH_CARD_SHADER: Shader = preload("res://assets/shaders/match_card.gdshader")
const STORE_PLATE: Texture2D = preload("res://assets/img/store_info_plate.png")
const SKIN_DIR: String = "res://assets/img/skins/"
# Flatten filter for the shaded/flat toggle's flat square, ported from
# `.skin-preview__variant.is-flat .skin-preview__variant-img` in Dashboard.css.
const THUMB_FLAT_SHADER: Shader = preload("res://assets/shaders/thumb_flat.gdshader")
# Fallback avatar when Privy has no profile picture, mirroring the frontend's
# `/loadinglogo.png`. The nav badge is native-size chrome, not part of the zoomed
# right panel, so these are authored at CSS pixel values.
const DEFAULT_AVATAR: Texture2D = preload("res://assets/img/logo.png")
# Public Monad testnet RPC, the same endpoint Dashboard.tsx reads MON from.
const MONAD_RPC_URL: String = "https://testnet-rpc.monad.xyz"
const LOGIN_SCENE: String = "res://scenes/login.tscn"

const DEFAULT_SKIN_ID: String = "s-default"
const DEFAULT_ENERGY: int = 4
const PLAY_COUNTDOWN_SECONDS: float = 4.0

# Preview orbit, ported from three's OrbitControls. ThreeScene.tsx mounts drei's
# <OrbitControls> with every default except `target`, `enablePan={false}` and the
# button map, and drei forces enableDamping, so these are that controller's own
# numbers: dampingFactor 0.05, rotateSpeed 1, zoomSpeed 1, getZoomScale() = 0.95,
# minDistance 0 / maxDistance Infinity, minPolarAngle 0 / maxPolarAngle PI.
#
# The damping is the part that actually reads as movement: input accumulates into
# a delta that the camera chases at 5% per frame, so it lags the finger by a hair,
# keeps gliding after release and eases to a stop -- instead of snapping to every
# sample the way the port used to.
const ORBIT_DAMPING_FACTOR: float = 0.05
const ORBIT_ROTATE_SPEED: float = 1.0
const ORBIT_ZOOM_SPEED: float = 1.0
const ORBIT_WHEEL_ZOOM_STEP: float = 0.95
# handleMouseMoveRotate uses `rotateLeft(2 * PI * dx / element.clientHeight)`, i.e.
# one drag across the pane's height is a full turn, so the sensitivity has to track
# the pane instead of being a fixed rad-per-pixel. Three clamps phi to (0, PI) and
# lets the camera swing just past the nad's core to look up from underneath; the
# epsilon keeps that far enough from the poles that look_at() stays well defined.
const ORBIT_PITCH_LIMIT: float = PI * 0.5 - 0.02
# OrbitControls leaves both distances open. These only stop the camera from
# collapsing to radius 0 (inside the nad, where the basis degenerates) or drifting
# so far out that the preview is a speck.
const ORBIT_ZOOM_MIN: float = 0.2
const ORBIT_ZOOM_MAX: float = 6.0
# InputEventPanGesture.delta is in pan units, not pixels; this is roughly how many
# pixels one unit covers before the value is fed to the orbit.
const ORBIT_PAN_UNITS_TO_PIXELS: float = 12.0

# Which stream owns the preview gesture currently in flight.
const PREVIEW_GESTURE_NONE: int = 0
const PREVIEW_GESTURE_MOUSE: int = 1
const PREVIEW_GESTURE_TOUCH: int = 2

# The right panel's static chrome is authored against a 175px-wide panel (35% of
# the 500px base viewport). Dashboard.css lays that panel out at 35% of the window,
# so the content has to grow with the panel or it ends up marooned in a wide empty
# column on anything wider than the base. _layout_panel_zoom scales the whole panel
# content by `panel_width / 175`, which also makes the absolute (native x 500/1280)
# dimensions resolve back to their CSS values once the window reaches 1280px wide.
const BASE_PANEL_WIDTH: float = 175.0

# Godot rasterises glyphs at their nominal font size and then the GPU scales the
# resulting texture. Because the panel content is laid out small and scaled up,
# that leaves text blurry. `FontFile.oversampling` rasterises the glyphs at a
# higher resolution instead (the engine equivalent of authoring the type large
# and scaling it down), so _apply_text_oversampling() tracks the panel's total
# device scale and keeps text crisp. Quantised to whole steps so a continuous
# window drag doesn't rebuild the font cache every frame.
const MAX_TEXT_OVERSAMPLING: float = 8.0

# Dashboard palette (Dashboard.css).
const C_GOLD: Color = Color(1.0, 0.84313726, 0.0, 1.0)
const C_MAGENTA: Color = Color(0.627451, 0.0, 1.0, 1.0)
const C_PIP_ON: Color = Color(0.99215686, 0.8784314, 0.2784314, 1.0)
const C_PIP_OFF: Color = Color(0.72, 0.72, 0.72, 0.2)

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

# The shaded/flat toggle square. `.skin-preview__variant` is a 36px artwork
# (`object-fit: cover`) inside a 2px border, so the button is 40px before the
# panel zoom scales it. These are native chrome sizes, like the preview name.
const VARIANT_THUMB_SIZE: float = 36.0
const VARIANT_BORDER_WIDTH: int = 2

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
@onready var _mon_value: Label = get_node_or_null("CanvasLayer/StatRail/MonPill/Row/MonValue") as Label

# Top navbar (user badge + logout menu), matching the frontend TopNavbar.
@onready var _nav_avatar: TextureRect = get_node_or_null("CanvasLayer/TopNav/Badge/Row/Avatar") as TextureRect
@onready var _nav_avatar_hit: Button = get_node_or_null("CanvasLayer/TopNav/Badge/Row/Avatar/Hit") as Button
@onready var _nav_name: Label = get_node_or_null("CanvasLayer/TopNav/Badge/Row/Name") as Label
@onready var _nav_account_menu: Control = get_node_or_null("CanvasLayer/TopNav/AccountMenu") as Control
@onready var _nav_logout: Button = get_node_or_null("CanvasLayer/TopNav/AccountMenu/Logout") as Button
@onready var _nav_dismiss: Button = get_node_or_null("CanvasLayer/NavDismiss") as Button
@onready var _nav_wallet: Button = get_node_or_null("CanvasLayer/TopNav/Badge/Wallet") as Button
@onready var _skin_preview: Control = get_node_or_null("CanvasLayer/SkinPreview") as Control
@onready var _skin_preview_variants_margin: Control = get_node_or_null("CanvasLayer/SkinPreview/VariantsMargin") as Control
@onready var _skin_preview_variants: HBoxContainer = get_node_or_null("CanvasLayer/SkinPreview/VariantsMargin/Variants") as HBoxContainer
@onready var _skin_preview_name: Label = get_node_or_null("CanvasLayer/SkinPreview/Name") as Label
@onready var _skin_preview_meta: Label = get_node_or_null("CanvasLayer/SkinPreview/Meta") as Label

@onready var _right_panel: Control = get_node_or_null("CanvasLayer/RightPanel") as Control
@onready var _panel_margin: Control = get_node_or_null("CanvasLayer/RightPanel/Margin") as Control

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
@onready var _lobby_music: AudioStreamPlayer = get_node_or_null("LobbyMusic") as AudioStreamPlayer
@onready var _footer_buttons: Control = get_node_or_null("CanvasLayer/FooterButtons") as Control
@onready var _mint_button: Button = get_node_or_null("CanvasLayer/FooterButtons/MintButton") as Button
@onready var _equip_button: Button = get_node_or_null("CanvasLayer/FooterButtons/EquipButton") as Button

var _preview_player: Node3D = null
var _skin_applier: SkinApplier = SkinApplier.new()
# 3D preview camera state. `_preview_base_distance` is the auto-framed distance from
# `_frame_preview_camera()`; the live distance is that divided by `_preview_zoom`, and
# the camera is placed on a sphere around `_preview_target` by the orbit angles.
var _preview_target: Vector3 = Vector3.ZERO
var _preview_base_distance: float = 3.0
var _preview_orbit_yaw: float = 0.0
var _preview_orbit_pitch: float = 0.0799  # atan(0.08), the original camera elevation.
var _preview_zoom: float = 1.0
# Pending orbit input, the counterpart of OrbitControls' sphericalDelta and scale:
# drags and zoom steps accumulate here, _update_preview_camera() folds them into
# the angles (damped) and the radius (once), then decays them.
var _preview_delta_yaw: float = 0.0
var _preview_delta_pitch: float = 0.0
var _preview_pending_scale: float = 1.0
# Which input stream owns the current preview gesture. emulate_touch_from_mouse (and
# emulate_mouse_from_touch on touchscreens) can deliver one physical drag as both a
# touch and a mouse stream, so whichever arrives first claims the gesture and the
# other one is ignored -- a drag is never applied twice.
var _preview_gesture: int = PREVIEW_GESTURE_NONE
var _preview_touch_active: bool = false
var _preview_touch_points: Dictionary = {}
var _preview_pinch_last: float = -1.0
var _tab_buttons: Dictionary = {}
var _filter_buttons: Dictionary = {}
var _texture_cache: Dictionary = {}
var _plate_gradient: GradientTexture2D = null
var _plate_gradient_gray: GradientTexture2D = null

var tab: String = TAB_EVENTS
var filter: String = "live"
var store_filter: String = "all"

var matches: Array[Dictionary] = []
var store_items: Array[Dictionary] = []
var owned_ids: Array[String] = []
var equipped_skin_id: String = DEFAULT_SKIN_ID
var selected_match_id: String = ""
var selected_store_id: String = ""
# Which edition of each skin the store grid shows: a random roll per group,
# re-rolled every time the Store tab opens, so the grid lists one card per skin
# instead of both shaded/unshaded editions (Dashboard.tsx storeVariantPicks).
var _store_variant_picks: Dictionary = {}

var energy: int = DEFAULT_ENERGY
var xp: float = 0.0
# Human-formatted MON balance, or empty until the RPC call returns.
var _mon_balance: String = ""

var _is_counting: bool = false
var _elapsed: float = 0.0
var _navigating: bool = false
var _font_oversampling: float = -1.0


func _ready() -> void:
	owned_ids.assign(DEFAULT_OWNED_IDS)

	_connect_chrome()
	_hide_scrollbars()
	_seed_local_store()
	matches = _build_static_matches()
	selected_match_id = _fallback_match_id()

	_spawn_preview_player()
	_fetch_store_data()

	_refresh_all()
	_setup_top_nav()

	if _preview_view != null and not _preview_view.resized.is_connected(_on_preview_resized):
		_preview_view.resized.connect(_on_preview_resized)
	if _right_panel != null and not _right_panel.resized.is_connected(_layout_panel_zoom):
		_right_panel.resized.connect(_layout_panel_zoom)
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_on_viewport_size_changed):
		viewport.size_changed.connect(_on_viewport_size_changed)
	_layout_panel_zoom()


# Dashboard.tsx builds its lobby loop as `new Audio("/lobbysong.mp3")` with
# `loop = true` / `volume = 0.4` and tears it down in the effect cleanup. The
# scene carries the equivalent (an AudioStreamPlayer on `autoplay`, the imported
# stream set to loop and `volume_db = linear_to_db(0.4)`), and leaving the
# dashboard -- starting a match -- has to silence it the same way.
func _exit_tree() -> void:
	if _lobby_music != null:
		_lobby_music.stop()


func _on_viewport_size_changed() -> void:
	_layout_panel_zoom()


func _on_preview_resized() -> void:
	_frame_preview_camera()
	_layout_lobby_bg()


# The panel is 35% of the viewport and its contents are authored for a 175px-wide
# panel, so scaling by `panel_width / 175` keeps them filling the column whatever
# the window size. The content is laid out at `1 / scale` and then scaled back up,
# exactly like `.right-info-zoom` does with --fs-zoom, so the internal anchors keep
# resolving to the same on-screen percentage of the panel.
func _layout_panel_zoom() -> void:
	if _right_panel == null or _panel_margin == null:
		return
	var panel_size := _right_panel.size
	if panel_size.x <= 0.0 or panel_size.y <= 0.0:
		return
	var factor := panel_size.x / BASE_PANEL_WIDTH
	_panel_margin.scale = Vector2(factor, factor)
	_panel_margin.size = Vector2(BASE_PANEL_WIDTH, panel_size.y / factor)
	_panel_margin.position = Vector2.ZERO
	_apply_text_oversampling()


# Keeps the two dashboard fonts rasterised at (at least) their final on-screen
# size. The panel scales by `factor` and the viewport stretch scales by
# `content_scale`, so the total device scale is their product; rounding up means
# the glyph texture is never stretched past its raster resolution. This is the
# Godot counterpart of the frontend rendering type large and scaling it down:
# without it the 3-7px base font is rasterised tiny and then magnified, which is
# what made every label look soft before and after resizing.
func _apply_text_oversampling() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var content_scale := viewport.get_final_transform().get_scale().y
	if content_scale <= 0.0:
		content_scale = 1.0
	var panel_factor := 1.0
	if _panel_margin != null:
		panel_factor = maxf(1.0, _panel_margin.scale.y)
	var target := clampf(ceilf(panel_factor * content_scale), 1.0, MAX_TEXT_OVERSAMPLING)
	if is_equal_approx(target, _font_oversampling):
		return
	_font_oversampling = target
	for font in [FONT_UI, FONT_TAB]:
		var file := font as FontFile
		if file != null:
			file.oversampling = target


# Dashboard.css hides every scrollbar (`scrollbar-width: none` + the
# `::-webkit-scrollbar { display: none }` rules). An empty stylebox drops the
# ScrollBar's minimum size to zero, so the bar both disappears and stops eating a
# strip off the content edge.
func _hide_scrollbars() -> void:
	for scroll in [_match_scroll, _reward_scroll, _store_scroll]:
		if scroll == null:
			continue
		for bar in [scroll.get_h_scroll_bar(), scroll.get_v_scroll_bar()]:
			if bar == null:
				continue
			bar.add_theme_stylebox_override("scroll", _empty_style())
			bar.add_theme_stylebox_override("grabber", _empty_style())
			bar.add_theme_stylebox_override("grabber_highlight", _empty_style())
			bar.add_theme_stylebox_override("grabber_pressed", _empty_style())


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
			# Pin every interaction state white so hovering doesn't flip the status/tier
			# labels dark. _set_filter_active() refreshes font_color on each tab change.
			filter_button.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
			filter_button.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
			filter_button.add_theme_color_override("font_focus_color", Color(1, 1, 1, 1))
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

	if tab == TAB_STORE:
		# Dashboard.tsx re-rolls each skin's shaded/flat variant whenever the
		# Store tab opens, so the grid gets one card per skin.
		_reroll_store_variants()

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
	_update_preview_camera(delta)

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


# The nad's real bounds are needed to frame it: skinned meshes follow the Skeleton3D's
# bones (and the skeleton carries a 0.25 scale), so a mesh-space AABB under-reports the
# character and leaves it a speck. Measuring the posed bones instead keeps the whole
# body framed and re-fits when the pane is resized. The 75deg field of view is
# ThreeScene's, so the perspective distortion matches the frontend.
func _frame_preview_camera() -> void:
	if _preview_camera == null or _preview_player == null:
		return

	var box := _preview_model_bounds()
	if box.size.length_squared() <= 0.0:
		return

	# The nad's core is the centre of its true bounds. Both the camera focus and the
	# pivot the model hangs from use it, so orbiting turns the camera around the
	# body's middle rather than around its feet.
	var target := box.get_center()
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

	_preview_target = target
	_preview_base_distance = distance
	# Park the Pivot on the core and shift the model below it by the same amount, so
	# the node the orbit pivots around sits at the nad's middle while the body keeps
	# its place in the frame.
	if _preview_pivot != null:
		_preview_pivot.position = target
	if _preview_root != null:
		_preview_root.position = -target
	_update_preview_camera()


# Measures the preview model in its own local space. Skinned meshes follow the
# Skeleton3D bones, so a mesh-space AABB under-reports them (the skeleton alone carries
# a 0.25 scale, and the bind pose differs from the posed mesh); sampling the posed bones
# captures the real character. Accessories hang off BoneAttachment3D, so their world
# transforms are already correct and are merged in as unskinned meshes.
func _preview_model_bounds() -> AABB:
	var box := AABB()
	var ready := false
	if _preview_player == null:
		return box
	var to_local := _preview_player.global_transform.affine_inverse()

	var skel := _preview_player.get_node_or_null("Skeleton3D") as Skeleton3D
	if skel != null:
		for i in skel.get_bone_count():
			# Helper "_end" bones poke past the mesh (head/toe tips); skip them so the
			# box matches the visible body.
			if String(skel.get_bone_name(i)).ends_with("_end"):
				continue
			var world_point: Vector3 = to_local * (skel.global_transform * skel.get_bone_global_pose(i).origin)
			if ready:
				box = box.expand(world_point)
			else:
				box = AABB(world_point, Vector3.ZERO)
				ready = true

	for node in _preview_player.find_children("*", "MeshInstance3D", true):
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null or not mesh_node.is_visible_in_tree():
			continue
		if not mesh_node.skeleton.is_empty():
			continue
		var piece: AABB = to_local * (mesh_node.global_transform * mesh_node.get_aabb())
		if ready:
			box = box.merge(piece)
		else:
			box = piece
			ready = true

	if ready:
		# Bones sit inside the body, so grow a little to reach the mesh surface.
		box = box.grow(0.08)
	return box


# OrbitControls.update(), one frame of it. Input handlers only accumulate deltas;
# every frame this folds the pending yaw/pitch into the angles scaled by
# dampingFactor, applies the one-shot zoom scale to the radius and then decays the
# leftovers by (1 - dampingFactor), which is what produces the glide and the
# ease-out. `delta` of 0 re-places the camera without touching that state, which is
# what _frame_preview_camera() wants after it re-derives the base distance.
#
# The camera then sits on a sphere around `_preview_target`, level (look_at with UP).
# At the default angles (yaw 0, pitch atan(0.08)) this resolves to the same transform
# _frame_preview_camera() used before orbiting existed: target + (0, distance*0.08, distance).
func _update_preview_camera(delta: float = 0.0) -> void:
	if _preview_camera == null:
		return
	if delta > 0.0:
		_preview_orbit_yaw = wrapf(
			_preview_orbit_yaw + _preview_delta_yaw * ORBIT_DAMPING_FACTOR, -PI, PI)
		_preview_orbit_pitch = clampf(
			_preview_orbit_pitch + _preview_delta_pitch * ORBIT_DAMPING_FACTOR,
			-ORBIT_PITCH_LIMIT, ORBIT_PITCH_LIMIT)
		_preview_delta_yaw *= 1.0 - ORBIT_DAMPING_FACTOR
		_preview_delta_pitch *= 1.0 - ORBIT_DAMPING_FACTOR
	if not is_equal_approx(_preview_pending_scale, 1.0):
		_preview_zoom = clampf(
			_preview_zoom * _preview_pending_scale, ORBIT_ZOOM_MIN, ORBIT_ZOOM_MAX)
		_preview_pending_scale = 1.0
	var distance := _preview_base_distance / maxf(_preview_zoom, 0.01)
	var direction := Vector3(
		sin(_preview_orbit_yaw) * cos(_preview_orbit_pitch),
		sin(_preview_orbit_pitch),
		cos(_preview_orbit_yaw) * cos(_preview_orbit_pitch),
	)
	_preview_camera.position = _preview_target + direction * distance
	_preview_camera.look_at(_preview_target, Vector3.UP)


# ----------------------------------------------------------- preview touch/mouse

# The preview pane has no interactive chrome of its own (the stat pills and skin
# captions are not focusable), so unhandled input over its rect is free to drive the
# camera. Using _unhandled_input keeps the right panel, play button and footer
# buttons working: their GUI controls consume their own events first.
func _unhandled_input(event: InputEvent) -> void:
	if _preview_view == null:
		return
	if event is InputEventScreenTouch:
		_handle_preview_screen_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_preview_screen_drag(event as InputEventScreenDrag)
	elif event is InputEventMouseButton:
		_handle_preview_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_preview_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventMagnifyGesture:
		_handle_preview_magnify(event as InputEventMagnifyGesture)
	elif event is InputEventPanGesture:
		_handle_preview_pan(event as InputEventPanGesture)


func _event_in_preview(event_position: Vector2) -> bool:
	return _preview_view.get_global_rect().has_point(event_position)


# The height three divides by is the canvas' clientHeight, which here is the
# preview pane. Falling back keeps the sensitivity sane before the first layout.
func _preview_pane_height() -> float:
	if _preview_view != null and _preview_view.size.y > 0.0:
		return _preview_view.size.y
	if _preview_viewport != null and _preview_viewport.size.y > 0.0:
		return _preview_viewport.size.y
	return 500.0


# Queue a drag the way handleMouseMoveRotate does. Directions match OrbitControls:
# drag right swings the camera left (the model follows the finger), drag down lifts
# the camera so more of the crown is visible.
func _orbit_preview(relative: Vector2) -> void:
	if relative == Vector2.ZERO:
		return
	var per_pixel := TAU * ORBIT_ROTATE_SPEED / _preview_pane_height()
	_preview_delta_yaw -= relative.x * per_pixel
	_preview_delta_pitch += relative.y * per_pixel


# Queue a zoom step. `factor` above 1 moves in; the wheel, pinch and magnify all
# multiply into the same pending scale that the next update applies once to the
# radius, mirroring OrbitControls' `scale`.
func _zoom_preview(factor: float) -> void:
	if factor <= 0.0:
		return
	_preview_pending_scale *= factor


func _pinch_distance() -> float:
	var indices := _preview_touch_points.keys()
	if indices.size() < 2:
		return -1.0
	var first: Vector2 = _preview_touch_points[indices[0]]
	var second: Vector2 = _preview_touch_points[indices[1]]
	return first.distance_to(second)


func _handle_preview_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				if _event_in_preview(event.position):
					_preview_gesture = PREVIEW_GESTURE_MOUSE
					get_viewport().set_input_as_handled()
			elif _preview_gesture == PREVIEW_GESTURE_MOUSE:
				_preview_gesture = PREVIEW_GESTURE_NONE
				get_viewport().set_input_as_handled()
		MOUSE_BUTTON_WHEEL_UP:
			if _event_in_preview(event.position):
				# dollyIn(getZoomScale()) -- one notch is 5% of the radius.
				_zoom_preview(1.0 / ORBIT_WHEEL_ZOOM_STEP)
				get_viewport().set_input_as_handled()
		MOUSE_BUTTON_WHEEL_DOWN:
			if _event_in_preview(event.position):
				_zoom_preview(ORBIT_WHEEL_ZOOM_STEP)
				get_viewport().set_input_as_handled()


func _handle_preview_mouse_motion(event: InputEventMouseMotion) -> void:
	if _preview_gesture != PREVIEW_GESTURE_MOUSE:
		return
	_orbit_preview(event.relative)
	get_viewport().set_input_as_handled()


func _handle_preview_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if not _event_in_preview(event.position):
			return
		_preview_gesture = PREVIEW_GESTURE_TOUCH
		_preview_touch_active = true
		_preview_touch_points[event.index] = event.position
		_preview_pinch_last = _pinch_distance()
		get_viewport().set_input_as_handled()
		return

	if not _preview_touch_points.has(event.index):
		return
	_preview_touch_points.erase(event.index)
	if _preview_touch_points.is_empty():
		_preview_touch_active = false
		_preview_gesture = PREVIEW_GESTURE_NONE
		_preview_pinch_last = -1.0
	else:
		_preview_pinch_last = _pinch_distance()
	get_viewport().set_input_as_handled()


func _handle_preview_screen_drag(event: InputEventScreenDrag) -> void:
	if _preview_gesture != PREVIEW_GESTURE_TOUCH:
		return
	if not _preview_touch_points.has(event.index):
		return
	_preview_touch_points[event.index] = event.position
	if _preview_touch_points.size() >= 2:
		# handleTouchMoveDolly: the radius scales by
		# (separation_last / separation_now) ^ zoomSpeed, and pan stays off because
		# the frontend sets enablePan={false}.
		var separation := _pinch_distance()
		if _preview_pinch_last > 0.0 and separation > 0.0:
			_zoom_preview(pow(_preview_pinch_last / separation, ORBIT_ZOOM_SPEED))
		_preview_pinch_last = separation
	else:
		_orbit_preview(event.relative)
	get_viewport().set_input_as_handled()


func _handle_preview_magnify(event: InputEventMagnifyGesture) -> void:
	if _event_in_preview(event.position):
		_zoom_preview(event.factor)
		get_viewport().set_input_as_handled()


func _handle_preview_pan(event: InputEventPanGesture) -> void:
	if _event_in_preview(event.position):
		_orbit_preview(event.delta * ORBIT_PAN_UNITS_TO_PIXELS)
		get_viewport().set_input_as_handled()


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

	# `.match-card` is 330x220 in the CSS, laid out at 129x86 here and then drawn
	# through the match-card shader, which applies the card's `scale: 0.9` and
	# `skewX(-5deg)` itself. A Panel (not a PanelContainer) is used so the artwork
	# can sit behind the plate, which pins to the bottom edge.
	var card := Panel.new()
	card.set_meta("match_id", match_id)
	card.custom_minimum_size = Vector2(129, 86)
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", _match_card_style(selected))

	# The artwork is a canvas shader (assets/shaders/match_card.gdshader) rather than
	# a baked texture so the dissolve and the halftone rim stay crisp when the panel
	# zoom scales the card up. It samples the same cover image the frontend uses.
	var art := ColorRect.new()
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.color = Color(1, 1, 1, 1)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card_material := ShaderMaterial.new()
	card_material.shader = MATCH_CARD_SHADER
	card_material.set_shader_parameter("source_tex", MATCH_SRC)
	card_material.set_shader_parameter("dot_opacity", 0.9 if selected else 0.6)
	card_material.set_shader_parameter("neon_opacity", 1.0 if selected else 0.8)
	card_material.set_shader_parameter("grayscale_amount", 1.0 if status == "completed" else 0.0)
	card_material.set_shader_parameter("brightness_amount", 0.7 if status == "completed" else 1.0)
	art.material = card_material
	card.set_meta("card_material", card_material)
	card.add_child(art)

	# `.match-reward` - dark prize pill pinned to the top-right corner. It renders
	# upright because .match-card-overlay counter-skews the card, so it is left
	# unskewed here too. `.match-card-overlay` carries the card's `scale: 0.9`, so
	# `top/right: 10px` is measured in the overlay and then scaled: the pill's
	# top-right lands at 0.05 + 10 * 0.9 / 330 = 0.0773 across, not 0.05 + 10/330.
	var prize := Label.new()
	prize.text = str(match.get("prize", "")).to_upper()
	prize.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	prize.offset_left = -10.055
	prize.offset_top = 7.813
	prize.offset_right = -10.055
	prize.offset_bottom = 7.813
	prize.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	prize.grow_vertical = Control.GROW_DIRECTION_END
	prize.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prize.add_theme_font_size_override("font_size", 4)
	prize.add_theme_color_override("font_color", text_color)
	prize.add_theme_stylebox_override("normal", _prize_style())
	_apply_font(prize, FONT_UI)
	card.add_child(prize)

	# `.match-card-content` - purple gradient plate along the bottom edge. It sits
	# inside `.match-card-overlay`, which scales the whole overlay to 0.9, so the
	# plate is inset 5% on each side and its bottom rests 5% up from the card edge.
	var plate := PanelContainer.new()
	plate.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	plate.anchor_left = 0.05
	plate.anchor_right = 0.95
	plate.offset_top = -4.3
	plate.offset_bottom = -4.3
	plate.grow_vertical = Control.GROW_DIRECTION_BEGIN
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel", _empty_style())
	card.add_child(plate)

	# The linear-gradient(to top, rgba(160,0,255,.75) ...) sits behind the text and
	# spans the whole plate, so it is a sibling drawn first.
	var plate_bg := TextureRect.new()
	plate_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plate_bg.texture = _get_plate_gradient(status == "completed")
	plate_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate_bg.stretch_mode = TextureRect.STRETCH_SCALE
	plate_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(plate_bg)

	var padding := MarginContainer.new()
	padding.mouse_filter = Control.MOUSE_FILTER_IGNORE
	padding.add_theme_constant_override("margin_left", 5)
	padding.add_theme_constant_override("margin_top", 7)
	padding.add_theme_constant_override("margin_right", 5)
	padding.add_theme_constant_override("margin_bottom", 5)
	plate.add_child(padding)

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 1)
	padding.add_child(content)

	# `.match-card` rests at opacity 0.5; the selected card lifts to 1. The
	# grayscale/brightness filter for a completed card lives in the shader so it
	# leaves no colour behind in the artwork.
	if not selected:
		card.modulate = Color(1, 1, 1, 0.5)

	if selected:
		# Selected cards swap the sponsor for the description (see Dashboard.tsx).
		var desc := Label.new()
		desc.text = str(match.get("description", ""))
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.max_lines_visible = 5
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# `.match-details-inner { line-height: 1.2 }` -> 12px * 1.2 = 14.4px, which is
		# 14.4 * 500/1280 * 0.9 = 5.06px here. Manrope's own line box at size 4 is 7px,
		# so the leading is pulled back by ~2px to keep the plate the CSS height.
		desc.add_theme_constant_override("line_spacing", -2)
		desc.add_theme_font_size_override("font_size", 4)
		desc.add_theme_color_override("font_color", text_color if status == "completed" else Color(1, 1, 1, 0.9))
		_apply_font(desc, FONT_UI)
		content.add_child(desc)
	else:
		var sponsor := Label.new()
		sponsor.text = str(match.get("sponsor", "")).to_upper()
		sponsor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sponsor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sponsor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
	# `.match-card:hover` lifts to full opacity, brightens the halftone rim and the
	# neon overlay, and scales to 1.08 about its centre.
	card.modulate.a = 1.0
	card.pivot_offset = card.size * 0.5
	card.scale = Vector2(1.08, 1.08)
	_set_match_card_glow(card, true)


func _on_match_card_exit(card: Control) -> void:
	card.scale = Vector2.ONE
	# `.match-card` rests at opacity 0.5 whether or not it is a completed match.
	if str(card.get_meta("match_id", "")) != selected_match_id:
		card.modulate.a = 0.5
	_set_match_card_glow(card, false)


func _set_match_card_glow(card: Control, hovered: bool) -> void:
	var material := card.get_meta("card_material", null) as ShaderMaterial
	if material == null:
		return
	var selected := str(card.get_meta("match_id", "")) == selected_match_id
	material.set_shader_parameter("dot_opacity", 0.9 if hovered or selected else 0.6)
	material.set_shader_parameter("neon_opacity", 1.0 if hovered or selected else 0.8)


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
			# get_global_rect() is in screen space, so the delta has to come back
			# through the panel scale before it can drive scroll_horizontal, which
			# is measured in the scroll's (unscaled) local units.
			var scale := _panel_margin.scale.x if _panel_margin != null else 1.0
			scale = maxf(scale, 0.0001)
			var delta_global := card_rect.position.x - scroll_rect.position.x \
				+ card_rect.size.x * 0.5 - scroll_rect.size.x * 0.5
			target_x = int(_match_scroll.scroll_horizontal + delta_global / scale)
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

	# One card per skin (group), showing the shaded or flat edition rolled for
	# this store open, exactly like Dashboard.tsx's storeGroups.
	for group: Dictionary in _store_groups():
		var pick: Dictionary = group.get("pick", {})
		if store_filter != "all" and str(pick.get("tier", "")) != store_filter:
			continue
		_store_grid.add_child(_build_store_card(group))


func _build_store_card(group: Dictionary) -> Control:
	var item: Dictionary = group.get("pick", {})
	var item_id: String = str(item.get("id", ""))
	var tier: String = str(item.get("tier", "common"))
	# Selection is group-level: the card stays selected while either edition is
	# picked, and a card is "owned" when either edition is held.
	var selected := _group_selected(group)
	var owned := _group_owned(group)

	# `.store-grid` is three 1fr tracks with a 10px gap, and the card carries a 5px
	# margin, so each 51px track here holds a 47x43 card.
	var card := Panel.new()
	card.set_meta("item_id", item_id)
	card.set_meta("selected", selected)
	card.set_meta("owned", owned)
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
	name_label.text = _skin_base_name(str(item.get("name", "")))
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
			_select_store_item(item_id)


# A grid card picks that group's rolled edition; a preview toggle square picks
# the other edition of the same skin. Both land here.
func _select_store_item(item_id: String) -> void:
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
	# `.store-card.selected` keeps scale(1.1); selection is group-level so a card
	# stays selected while either of its editions is picked in the toggle.
	if bool(card.get_meta("selected", false)):
		return Vector2(1.1, 1.1)
	return Vector2.ONE


func _on_store_card_enter(card: Control) -> void:
	# `.store-card:hover` lifts to full opacity and scales to 1.05, but a selected
	# card keeps the higher `scale(1.1)` from `.store-card.selected`.
	card.modulate.a = 1.0
	card.pivot_offset = card.size * 0.5
	if bool(card.get_meta("selected", false)):
		card.scale = Vector2(1.1, 1.1)
	else:
		card.scale = Vector2(1.05, 1.05)


func _on_store_card_exit(card: Control) -> void:
	card.pivot_offset = card.size * 0.5
	card.scale = _store_card_rest_scale(card)
	if bool(card.get_meta("selected", false)):
		card.modulate.a = 1.0
		return
	# `.store-card` rests at opacity 0.7 and `.unowned` pulls it to 0.62. A group
	# is owned when either of its editions is held.
	card.modulate.a = 0.7 if bool(card.get_meta("owned", false)) else 0.62


func _is_owned(item: Dictionary) -> bool:
	return owned_ids.has(str(item.get("id", "")))


# --------------------------------------------------------------------- top nav

# Ports the frontend TopNavbar user badge: avatar, username, wallet address and,
# behind the caret, the logout action. Everything here reads from AuthManager,
# which is the only source of identity.
func _setup_top_nav() -> void:
	var username := AuthManager.get_username()
	if _nav_name != null:
		_nav_name.text = username if not username.is_empty() else "Player"

	var address := AuthManager.get_wallet_address()
	if _nav_wallet != null:
		var short := AuthManager.get_short_wallet_address()
		_nav_wallet.text = short
		_nav_wallet.visible = not short.is_empty()
		_nav_wallet.tooltip_text = address
		if not _nav_wallet.pressed.is_connected(_on_wallet_pressed):
			_nav_wallet.pressed.connect(_on_wallet_pressed)

	# Clicking the avatar toggles the account menu (Logout). The menu is a plain
	# control rather than a popup so its button can carry the same pink skew
	# style as the login screen's Cancel button.
	if _nav_avatar_hit != null and not _nav_avatar_hit.pressed.is_connected(_on_nav_avatar_pressed):
		_nav_avatar_hit.pressed.connect(_on_nav_avatar_pressed)
	if _nav_logout != null and not _nav_logout.pressed.is_connected(_on_logout_pressed):
		_nav_logout.pressed.connect(_on_logout_pressed)
	if _nav_dismiss != null and not _nav_dismiss.pressed.is_connected(_close_account_menu):
		_nav_dismiss.pressed.connect(_close_account_menu)
	_set_account_menu_visible(false)

	_load_profile_picture()
	_fetch_mon_balance()

func _on_nav_avatar_pressed() -> void:
	_set_account_menu_visible(_nav_account_menu == null or not _nav_account_menu.visible)

func _close_account_menu() -> void:
	_set_account_menu_visible(false)

func _set_account_menu_visible(shown: bool) -> void:
	if _nav_account_menu != null:
		_nav_account_menu.visible = shown
	if _nav_dismiss != null:
		_nav_dismiss.visible = shown

func _on_wallet_pressed() -> void:
	var address := AuthManager.get_wallet_address()
	if address.is_empty():
		return
	DisplayServer.clipboard_set(address)
	if _nav_wallet != null:
		_nav_wallet.text = "Copied!"
		var timer := get_tree().create_timer(1.5)
		timer.timeout.connect(_restore_wallet_label)

func _restore_wallet_label() -> void:
	if _nav_wallet != null:
		_nav_wallet.text = AuthManager.get_short_wallet_address()

func _on_logout_pressed() -> void:
	_set_account_menu_visible(false)
	AuthManager.logout("user_requested")
	# The login screen re-runs the device flow, so the next player on this
	# install gets a fresh QR code instead of the previous session.
	if Game.transition_layer != null:
		Game.transition_layer.change_scene(LOGIN_SCENE)
	else:
		get_tree().change_scene_to_file(LOGIN_SCENE)

# Avatar is a remote URL, so it is fetched at runtime. Any failure (offline,
# unknown content type) falls back to the bundled logo rather than leaving an
# empty square. The format is sniffed from the bytes so a decode is only ever
# attempted with the matching loader, instead of probing every loader and
# letting the misses print engine errors.
func _load_profile_picture() -> void:
	var url := AuthManager.get_profile_picture_url()
	if url.is_empty():
		if _nav_avatar != null:
			_nav_avatar.texture = DEFAULT_AVATAR
		return

	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	if http.request(url) != OK:
		http.queue_free()
		if _nav_avatar != null:
			_nav_avatar.texture = DEFAULT_AVATAR
		return

	var result: Array = await http.request_completed
	http.queue_free()

	var code := int(result[1])
	var body: PackedByteArray = result[3]
	var image := Image.new()
	var loaded := false
	if code == 200:
		if _bytes_are_png(body):
			loaded = image.load_png_from_buffer(body) == OK
		elif _bytes_are_jpeg(body):
			loaded = image.load_jpg_from_buffer(body) == OK
		elif _bytes_are_webp(body):
			loaded = image.load_webp_from_buffer(body) == OK
	if _nav_avatar != null:
		_nav_avatar.texture = ImageTexture.create_from_image(image) if loaded else DEFAULT_AVATAR

func _bytes_are_png(data: PackedByteArray) -> bool:
	return (
		data.size() >= 8
		and data[0] == 0x89 and data[1] == 0x50 and data[2] == 0x4E and data[3] == 0x47
	)

func _bytes_are_jpeg(data: PackedByteArray) -> bool:
	return data.size() >= 3 and data[0] == 0xFF and data[1] == 0xD8 and data[2] == 0xFF

func _bytes_are_webp(data: PackedByteArray) -> bool:
	return (
		data.size() >= 12
		and data[0] == 0x52 and data[1] == 0x49 and data[2] == 0x46 and data[3] == 0x46
		and data[8] == 0x57 and data[9] == 0x45 and data[10] == 0x42 and data[11] == 0x50
	)

# Public Monad RPC read, mirroring Dashboard.tsx's ethers getBalance. Display
# only: the balance is never trusted for anything the game acts on.
func _fetch_mon_balance() -> void:
	var address := AuthManager.get_wallet_address()
	if address.is_empty():
		return

	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	var payload := {
		"jsonrpc": "2.0",
		"id": 1,
		"method": "eth_getBalance",
		"params": [address, "latest"]
	}
	var err := http.request(
		MONAD_RPC_URL,
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if err != OK:
		http.queue_free()
		return

	var result: Array = await http.request_completed
	http.queue_free()
	if int(result[1]) != 200:
		return

	var parsed: Variant = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var hex_balance := str((parsed as Dictionary).get("result", ""))
	if hex_balance.is_empty():
		return

	_mon_balance = _format_wei_to_mon(hex_balance)
	_refresh_stat_rail()

# Wei hex -> "0.0000" MON, without ever converting the full integer to a float
# (a balance can exceed Godot's 64-bit int). Decimal is built digit by digit and
# truncated to 4 places, matching the frontend's `toFixed(4)`.
func _format_wei_to_mon(hex_value: String) -> String:
	var hex := hex_value.strip_edges()
	if hex.begins_with("0x") or hex.begins_with("0X"):
		hex = hex.substr(2)
	if hex.is_empty():
		return "0.0000"
	return _format_decimal_18(_hex_to_decimal(hex))

func _hex_to_decimal(hex: String) -> String:
	var digits: Array[int] = [0]
	var alphabet := "0123456789abcdef"
	for i in hex.length():
		var value := alphabet.find(hex[i].to_lower())
		if value < 0:
			continue
		var carry := value
		for j in digits.size():
			var current := digits[j] * 16 + carry
			digits[j] = current % 10
			carry = current / 10
		while carry > 0:
			digits.append(carry % 10)
			carry = carry / 10
	var out := ""
	for i in range(digits.size() - 1, -1, -1):
		out += str(digits[i])
	return out

func _format_decimal_18(decimal: String) -> String:
	while decimal.length() < 19:
		decimal = "0" + decimal
	var whole := decimal.substr(0, decimal.length() - 18)
	var fraction := decimal.substr(decimal.length() - 18, 4)
	return "%s.%s" % [whole, fraction]


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

	if _mon_value != null:
		_mon_value.text = _mon_balance if not _mon_balance.is_empty() else "0.0000"
	# Dashboard.tsx renders the MON pill only once a balance is known.
	if _mon_pill != null:
		_mon_pill.visible = not _mon_balance.is_empty()
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
	_build_skin_variants()
	if not visible:
		return

	var item := _selected_store_item()
	if _skin_preview_name != null:
		_skin_preview_name.text = _skin_base_name(str(item.get("name", "")))
	if _skin_preview_meta != null:
		_skin_preview_meta.text = "Owned" if _is_owned(item) else str(item.get("price", ""))


# ------------------------------------------------------------- shaded/flat toggle

# Builds the `.skin-preview__variants` row above the preview name: one square per
# edition of the selected skin, shaded first then flat. A skin with a single
# edition (or nothing selected) shows no row, matching Dashboard.tsx.
func _build_skin_variants() -> void:
	if _skin_preview_variants == null:
		return
	for child in _skin_preview_variants.get_children():
		_skin_preview_variants.remove_child(child)
		child.queue_free()

	var group := _store_group_for(selected_store_id)
	var items: Array = group.get("items", [])
	# The MarginContainer owns the row's visibility (and its 8px gap): hiding the
	# inner HBox alone would leave the empty margin behind.
	var show := tab == TAB_STORE and selected_store_id != "" and items.size() > 1
	if _skin_preview_variants_margin != null:
		_skin_preview_variants_margin.visible = show
	if not show:
		return

	var variants := items.duplicate()
	variants.sort_custom(_variant_sort)
	for variant: Dictionary in variants:
		_skin_preview_variants.add_child(_build_variant_button(variant))


# Shaded before flat, matching the frontend's ascending isFlatSkinId sort.
func _variant_sort(a: Dictionary, b: Dictionary) -> bool:
	var a_flat := 1 if _is_flat_skin_id(str(a.get("id", ""))) else 0
	var b_flat := 1 if _is_flat_skin_id(str(b.get("id", ""))) else 0
	return a_flat < b_flat


func _build_variant_button(item: Dictionary) -> Button:
	var item_id := str(item.get("id", ""))
	var flat := _is_flat_skin_id(item_id)
	var active := item_id == selected_store_id

	var button := Button.new()
	button.custom_minimum_size = Vector2(
		VARIANT_THUMB_SIZE + VARIANT_BORDER_WIDTH * 2,
		VARIANT_THUMB_SIZE + VARIANT_BORDER_WIDTH * 2,
	)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.tooltip_text = "Flat (unshaded)" if flat else "Shaded"
	button.add_theme_stylebox_override("normal", _variant_style(active))
	button.add_theme_stylebox_override("hover", _variant_style(active))
	button.add_theme_stylebox_override("pressed", _variant_style(active))
	button.add_theme_stylebox_override("focus", _empty_style())

	# `.skin-preview__variant-img`: 36px square, `object-fit: cover`, sitting
	# inside the 2px border.
	var image := TextureRect.new()
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.offset_left = VARIANT_BORDER_WIDTH
	image.offset_top = VARIANT_BORDER_WIDTH
	image.offset_right = -VARIANT_BORDER_WIDTH
	image.offset_bottom = -VARIANT_BORDER_WIDTH
	image.texture = _skin_texture(item, false)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if flat:
		# `.skin-preview__variant.is-flat .skin-preview__variant-img` filter.
		var material := ShaderMaterial.new()
		material.shader = THUMB_FLAT_SHADER
		image.material = material
	button.add_child(image)

	button.pressed.connect(_select_store_item.bind(item_id))
	button.mouse_entered.connect(_on_variant_enter.bind(button))
	button.mouse_exited.connect(_on_variant_exit.bind(button))
	return button


# `.skin-preview__variant:hover { transform: translateY(-1px) }`. The container
# owns each button's laid-out position, so remember it before nudging and put it
# back on exit.
func _on_variant_enter(button: Button) -> void:
	var rest_y := button.position.y
	button.set_meta("rest_y", rest_y)
	button.position.y = rest_y - 1.0


func _on_variant_exit(button: Button) -> void:
	button.position.y = float(button.get_meta("rest_y", button.position.y))


# ------------------------------------------------------------------ store groups

# Group key for a store item, mirroring Dashboard.tsx skinGroupKey(): the combo a
# skin belongs to, so its shaded and unshaded ("Flat") editions collapse into one
# card. Numeric ids pair as 2n+1 (shaded) / 2n+2 (unshaded); named ids pair by
# stripping the "-unshaded" suffix.
func _skin_group_key(item_id: String) -> String:
	var id := item_id.strip_edges()
	if _is_numeric_id(id):
		# GDScript "/" on ints returns a float, and `%d` formatting of a float is
		# not reliably truncating, so floor explicitly -- Math.floor((id - 1) / 2)
		# in skinGroupKey().
		return "combo-%d" % int((int(id) - 1) / 2)
	return "named-" + _strip_unshaded_suffix(id)


# `/^\d+$/` - digits only, so "0001" groups but "s-default" does not.
func _is_numeric_id(id: String) -> bool:
	if id.is_empty():
		return false
	for i in id.length():
		if id[i] < "0" or id[i] > "9":
			return false
	return true


func _strip_unshaded_suffix(id: String) -> String:
	var suffix := "-unshaded"
	if id.to_lower().ends_with(suffix):
		return id.substr(0, id.length() - suffix.length())
	return id


# True for the unshaded ("Flat") edition: even numeric ids and ids ending in
# "-unshaded". Mirrors isFlatSkinId() and SkinApplier's shaded/unshaded parity.
func _is_flat_skin_id(item_id: String) -> bool:
	var id := item_id.strip_edges()
	if _is_numeric_id(id):
		return int(id) % 2 == 0
	return id.to_lower().ends_with("-unshaded")


# Base display name, dropping the " (Flat)" variant suffix (skinBaseName()).
func _skin_base_name(skin_name: String) -> String:
	var trimmed := skin_name.strip_edges()
	var suffix := "(flat)"
	if trimmed.to_lower().ends_with(suffix):
		return trimmed.substr(0, trimmed.length() - suffix.length()).strip_edges()
	return skin_name


# Dashboard.tsx's storeGroups: one entry per skin, carrying its editions and the
# edition rolled for this store open. Insertion order is preserved so the grid
# keeps the store_items order.
func _store_groups() -> Array:
	var order: Array = []
	var map: Dictionary = {}
	for item: Dictionary in store_items:
		var key := _skin_group_key(str(item.get("id", "")))
		if not map.has(key):
			map[key] = []
			order.append(key)
		var list: Array = map[key]
		list.append(item)

	var groups: Array = []
	for key: String in order:
		var items: Array = map[key]
		var pick_index := int(_store_variant_picks.get(key, 0))
		var pick: Dictionary = {}
		if not items.is_empty():
			pick = items[pick_index % items.size()]
		groups.append({"key": key, "items": items, "pick": pick})
	return groups


func _store_group_for(item_id: String) -> Dictionary:
	for group: Dictionary in _store_groups():
		for item: Dictionary in group.get("items", []):
			if str(item.get("id", "")) == item_id:
				return group
	return {}


func _group_owned(group: Dictionary) -> bool:
	for item: Dictionary in group.get("items", []):
		if _is_owned(item):
			return true
	return false


func _group_selected(group: Dictionary) -> bool:
	for item: Dictionary in group.get("items", []):
		if str(item.get("id", "")) == selected_store_id:
			return true
	return false


# Dashboard.tsx re-rolls each skin's shaded/flat variant when the Store tab opens.
func _reroll_store_variants() -> void:
	for item: Dictionary in store_items:
		var key := _skin_group_key(str(item.get("id", "")))
		_store_variant_picks[key] = randi() % 2


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
	if OS.has_feature("web"):
		# The web build can be reloaded at any point, and both the lobby and
		# gameplay read ?match=/?skin= off window.location, so keep the address bar
		# in step with what is handed over below.
		JavaScriptBridge.eval(
			"window.history.replaceState({}, '', window.location.pathname + '?match=%s&skin=%s');"
			% [selected_match_id.uri_encode(), skin_id.uri_encode()]
		)

	# The lobby takes the match that was queued and the nad that is equipped as
	# exported properties, set on the scene before its _ready() runs.
	Game.transition_layer.change_scene(LOBBY_SCENE, {
		"selected_match_id": selected_match_id,
		"selected_skin_id": skin_id,
	})


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


func _get_plate_gradient(completed: bool = false) -> GradientTexture2D:
	if completed:
		if _plate_gradient_gray != null:
			return _plate_gradient_gray
	elif _plate_gradient != null:
		return _plate_gradient
	# .match-card-content background:
	#   linear-gradient(to top, rgba(160,0,255,.75) 0%, rgba(160,0,255,.3) 50%, transparent 100%)
	# `.match-card[data-status="completed"]` filters the whole card to
	# grayscale(100%) brightness(0.7); the shader covers the artwork, so the plate
	# is pre-desaturated to the same grey so it does not stay purple.
	var tint := C_MAGENTA
	if completed:
		var lum := 0.2126 * C_MAGENTA.r + 0.7152 * C_MAGENTA.g + 0.0722 * C_MAGENTA.b
		var gray := lum * 0.7
		tint = Color(gray, gray, gray)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gradient.colors = PackedColorArray([
		Color(tint.r, tint.g, tint.b, 0.75),
		Color(tint.r, tint.g, tint.b, 0.3),
		Color(tint.r, tint.g, tint.b, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 8
	texture.height = 128
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.0, 1.0)
	texture.fill_to = Vector2(0.0, 0.0)
	if completed:
		_plate_gradient_gray = texture
	else:
		_plate_gradient = texture
	return texture


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
	# The CSS active colour is --primary-light, but over this purple backdrop the
	# active tab reads better pure white; the user asked for the active tab to sit at
	# full opacity in white.
	button.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	button.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	button.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
	button.add_theme_color_override("font_focus_color", Color(1, 1, 1, 1))


func _set_filter_active(button: Button, active: bool) -> void:
	if button == null:
		return
	# `.filter { opacity: 0.5 }` with `.filter.active` forced to 1. The CSS active
	# label is dark, but the user wants every status/tier label to stay white (and in
	# particular not flip dark on hover), so all button states are pinned white.
	button.modulate = Color(1, 1, 1, 1) if active else Color(1, 1, 1, 0.5)
	button.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	button.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	button.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
	button.add_theme_color_override("font_focus_color", Color(1, 1, 1, 1))
	button.add_theme_stylebox_override("normal", _filter_style(active))


# --------------------------------------------------------------- style factories

func _empty_style() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


func _variant_style(active: bool) -> StyleBoxFlat:
	# `.skin-preview__variant`: no radius, 2px rgba(128,128,128,.4) border and a
	# transparent fill that the thumbnail's white 0.2 backdrop shows through. The
	# active edition takes a white border (the dark scheme this screen renders).
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.2)
	style.set_border_width_all(VARIANT_BORDER_WIDTH)
	style.border_color = Color(1, 1, 1, 1) if active else Color(0.5, 0.5, 0.5, 0.4)
	style.content_margin_left = 0.0
	style.content_margin_top = 0.0
	style.content_margin_right = 0.0
	style.content_margin_bottom = 0.0
	return style


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
	# carries the selected card's purple glow. The scale and skew live in the
	# match-card shader, not here. The glow therefore has to be inset to the
	# visible 90% card (5% a side) and sheared to match, or it wraps the full
	# layout slot and reads as a rectangle around a smaller, slanted card.
	var style := StyleBoxFlat.new()
	# StyleBoxFlat defaults to an opaque grey fill. The artwork only covers the
	# scaled 90% of the slot, so that fill would show as a straight, unskewed grey
	# rectangle behind the slanted, dissolved card.
	style.draw_center = false
	style.bg_color = Color(0, 0, 0, 0)
	style.expand_margin_left = -6.45
	style.expand_margin_right = -6.45
	style.expand_margin_top = -4.3
	style.expand_margin_bottom = -4.3
	style.skew = Vector2(0.0872665, 0.0)
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
