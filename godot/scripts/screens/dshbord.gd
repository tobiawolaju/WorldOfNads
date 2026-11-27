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
# The shared training arena maps to the room server's `default` room rather than a
# match id, because it is not a host-created match and must never be treated as one.
const TRAINING_MATCH_ID: String = "default"
# The second permanent room. Like training it has no Firebase match record, entry fee
# or prize pool, but it is a room of its own: the room server always accepts it
# (`CHOG_ROOM` in backend-rust/src/net.rs).
const CHOG_MATCH_ID: String = "match-chog-world-order"
const SKIN_SCENE: PackedScene = preload("res://scenes/skin.tscn")
const LOBBY_SCENE: String = "res://scenes/lobby.tscn"

const FONT_UI: Font = preload("res://assets/fonts/font1.ttf")
const FONT_TAB: Font = preload("res://assets/fonts/font2.ttf")
const MATCH_SRC: Texture2D = preload("res://assets/img/lobbybg.jpeg")
const MATCH_CARD_SHADER: Shader = preload("res://assets/shaders/match_card.gdshader")
# Match-card stat glyphs (filled heart, filled people). The Godot project ships no
# icon font, so both silhouettes live in one shader and `shape` picks which to draw.
const MATCH_STAT_ICON_SHADER: Shader = preload("res://assets/shaders/match_stat_icon.gdshader")
const STAT_SHAPE_HEART: int = 0
const STAT_SHAPE_PEOPLE: int = 1
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

# --- Party / friend invites -------------------------------------------------
# Both dashboards poll the Node backend, which owns the short-lived squad state:
# up to four players, one shared match, an accept/reject popup, per-member ready
# and a synchronised 5s launch countdown. The match itself is unchanged.
const PARTY_POLL_SECONDS: float = 1.5
const PARTY_SEARCH_DELAY: float = 0.3
const PARTY_MAX_MEMBERS: int = 4
const PARTY_UI_BG := Color(0.075, 0.05, 0.16, 0.94)
const PARTY_UI_BORDER := Color(1.0, 1.0, 1.0, 0.16)
const PARTY_ACCENT := Color(1.0, 0.84, 0.0, 1.0)
const PARTY_STALE_LAUNCH_MS: int = 15000
# `.party-results { max-height: 230px; overflow-y: auto }` in PartyBar.css: the
# list hugs its rows and only starts scrolling once it reaches the cap.
const PARTY_RESULTS_MAX_HEIGHT: float = 230.0

# Preview orbit, ported from three's OrbitControls. ThreeScene.tsx mounts drei's
# <OrbitControls> with every default except `target`, `enablePan={false}`, the
# button map and the zoom-distance clamp, and drei forces enableDamping, so these
# are that controller's own numbers: dampingFactor 0.05, rotateSpeed 1, zoomSpeed
# 1, getZoomScale() = 0.95, minPolarAngle 0 / maxPolarAngle PI.
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
# the pane instead of being a fixed rad-per-pixel.
# Subtle vertical orbit range around the framed elevation (Three.js-like feel, no zoom).
const ORBIT_PITCH_DEFAULT: float = 0.0799  # atan(0.08)
const ORBIT_PITCH_MIN: float = -0.12
const ORBIT_PITCH_MAX: float = 0.28
# Zoom disabled for the dashboard preview.
const ORBIT_ZOOM_MIN: float = 1.0
const ORBIT_ZOOM_MAX: float = 1.0
# InputEventPanGesture.delta is in pan units, not pixels; this is roughly how many
# pixels one unit covers before the value is fed to the orbit.
const ORBIT_PAN_UNITS_TO_PIXELS: float = 12.0

# Random full-body flourishes for the 3D preview. Every clip ships in
# resources/PlayerAnimations.tres; the dashboard plays one through
# player.gd::play_emote(), waits for the clip to end plus a breathing gap, then
# picks a different one. That keeps the passive nad from reading as a mannequin.
const PREVIEW_EMOTES: Array[String] = ["battlecry", "emote", "emote2", "emote3", "hook"]
const PREVIEW_EMOTE_FIRST_DELAY: float = 1.5
const PREVIEW_EMOTE_GAP_MIN: float = 3.0
const PREVIEW_EMOTE_GAP_MAX: float = 7.0

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

const TAB_EVENTS: String = "events"
const TAB_REWARDS: String = "rewards"
const TAB_STORE: String = "store"
const TAB_ORDER := [TAB_EVENTS, TAB_REWARDS, TAB_STORE]

const EVENT_STATUSES := ["upcoming", "live", "completed"]
const STORE_TIERS := ["all", "common", "rare", "epic", "legendary"]
const DEFAULT_OWNED_IDS := ["s-default", "s-default-unshaded"]

# Match-card stat counts. Placeholders until the match payload carries real likes and
# player counts: the same pools and the same salted-hash idea as Dashboard.tsx, so a
# card keeps its numbers instead of reshuffling on every rebuild. The web seed is
# `matchId-contractId`; the Godot match dict has no contract id, so match_id alone is
# the seed and the two screens may pick different pools for the same card.
const DUMMY_PLAYER_COUNTS := [37, 128, 363, 942, 1500, 3700, 12300, 37000]
const DUMMY_HEART_COUNTS := [12, 48, 96, 240, 512, 1200, 3400, 8600]

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
@onready var _lobby_bg_current: TextureRect = get_node_or_null("CanvasLayer/LobbyBg/Current") as TextureRect
@onready var _lobby_bg_prev: TextureRect = get_node_or_null("CanvasLayer/LobbyBg/Prev") as TextureRect
@onready var _stat_rail: Control = get_node_or_null("CanvasLayer/StatRail") as Control
@onready var _energy_pips: HBoxContainer = get_node_or_null("CanvasLayer/StatRail/EnergyPill/EnergyPips") as HBoxContainer
@onready var _mon_pill: Control = get_node_or_null("CanvasLayer/StatRail/MonPill") as Control
@onready var _level_pill: Control = get_node_or_null("CanvasLayer/StatRail/LevelPill") as Control
@onready var _level_value: Label = get_node_or_null("CanvasLayer/StatRail/LevelPill/Row/LevelValue") as Label
@onready var _level_row: HBoxContainer = get_node_or_null("CanvasLayer/StatRail/LevelPill/Row") as HBoxContainer
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
@onready var _event_preview: Control = get_node_or_null("CanvasLayer/EventPreview") as Control
@onready var _event_preview_desc: Label = get_node_or_null("CanvasLayer/EventPreview/Desc") as Label

@onready var _right_panel: Control = get_node_or_null("CanvasLayer/RightPanel") as Control
@onready var _panel_margin: Control = get_node_or_null("CanvasLayer/RightPanel/Margin") as Control

@onready var _tabs: HBoxContainer = get_node_or_null("CanvasLayer/RightPanel/Margin/Column/TabsMargin/Tabs") as HBoxContainer
@onready var _tab_badge: Label = get_node_or_null("CanvasLayer/RightPanel/Margin/Column/TabsMargin/Tabs/TabStore/Badge") as Label
@onready var _filters_events: HBoxContainer = get_node_or_null("CanvasLayer/RightPanel/Margin/Column/FiltersMargin/FiltersEvents") as HBoxContainer
@onready var _filters_store: HFlowContainer = get_node_or_null("CanvasLayer/RightPanel/Margin/Column/FiltersMargin/FiltersStore") as HFlowContainer

@onready var _match_scroll: ScrollContainer = get_node_or_null("CanvasLayer/RightPanel/Margin/Column/Content/MatchScroll") as ScrollContainer
@onready var _match_cards: HBoxContainer = get_node_or_null("CanvasLayer/RightPanel/Margin/Column/Content/MatchScroll/MatchMargin/MatchCards") as HBoxContainer
@onready var _reward_scroll: ScrollContainer = get_node_or_null("CanvasLayer/RightPanel/Margin/Column/Content/RewardScroll") as ScrollContainer
@onready var _reward_list: VBoxContainer = get_node_or_null("CanvasLayer/RightPanel/Margin/Column/Content/RewardScroll/RewardMargin/RewardList") as VBoxContainer
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
var _preview_chickens: Array[MeshInstance3D] = []
var _preview_chickens_mat: ShaderMaterial = null
var _preview_chickens_tween: Tween = null
var _preview_chickens_showing: bool = true
# Countdown to the preview's next random emote. It starts short so the first
# flourish lands before the user has finished reading the dashboard.
var _preview_emote_timer: float = PREVIEW_EMOTE_FIRST_DELAY
var _preview_emote_last: String = ""
var _skin_applier: SkinApplier = SkinApplier.new()
# Hold this key to show the preview nad's skin parts that sit outside the
# regular look (the shirt, the wig and the glove). Toggled by the "chog"
# input action.

# True while the reveal action is active, so the handler acts on press edges only
# and key-repeat events cannot overwrite the "before" state.
var _preview_hidden_extras_revealed: bool = false
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

# Sliding lobby backdrop (Dashboard.tsx: prev/current layers + directional slide).
var _bg_current_key: String = ""
var _bg_prev_tab: String = TAB_EVENTS
var _bg_prev_match_id: String = ""
var _bg_tween: Tween = null
var _plate_gradient: GradientTexture2D = null
var _plate_gradient_gray: GradientTexture2D = null

var tab: String = TAB_EVENTS
var filter: String = "live"
var store_filter: String = "all"

var matches: Array[Dictionary] = []
var _match_join_totals: Dictionary = {}
var store_items: Array[Dictionary] = []
var owned_ids: Array[String] = []
var equipped_skin_id: String = DEFAULT_SKIN_ID
var selected_match_id: String = ""
var selected_store_id: String = ""
# Which edition of each skin the store grid shows: a random roll per group,
# re-rolled every time the Store tab opens, so the grid lists one card per skin
# instead of both shaded/unshaded editions (Dashboard.tsx storeVariantPicks).
var _store_variant_picks: Dictionary = {}

# In-app minting: the backend signs mintSkin with the linked player key, so
# these two requests are the whole client-side flow (see walletService.js).
var _mint_in_flight: bool = false
var _wallet_link_dialog: PanelContainer = null
var _wallet_link_input: LineEdit = null
var _wallet_link_status: Label = null
var _pending_mint_skin_id: String = ""
var _last_inventory_payload: Dictionary = {}

var energy: int = DEFAULT_ENERGY
var xp: float = 0.0
# Human-formatted MON balance, or empty until the RPC call returns.
var _mon_balance: String = ""

var _is_counting: bool = false
var _elapsed: float = 0.0
var _navigating: bool = false
var _font_oversampling: float = -1.0

# Party state polled from the Node backend. `_party_state` is the caller's party
# (or empty) and `_party_invites` holds pending invites addressed to them.
var _party_http: HTTPRequest = null
var _party_busy: bool = false
var _party_request_kind: String = ""
var _party_queue: Array = []
var _party_poll_accum: float = 0.0
var _party_state: Dictionary = {}
var _party_invites: Array = []
var _party_server_offset_ms: int = 0
var _party_launched_id: String = ""
var _party_last_invite: String = ""
var _party_overlay: Control = null
var _party_leave: Button = null
var _party_slots: Array = []
var _party_slot_names: Array = []
var _party_slot_dot_phase: float = 0.0
var _party_me_leave: Button = null
var _party_slot_plus_style: StyleBoxFlat = null
var _party_slot_plus_hover: StyleBoxFlat = null
var _party_slot_filled_style: StyleBoxFlat = null
var _party_dialog: Control = null
var _party_dialog_status: Label = null
var _party_search: LineEdit = null
var _party_results: VBoxContainer = null
var _party_results_scroll: ScrollContainer = null
var _party_search_timer: Timer = null
var _party_invite_popup: Control = null
var _party_invite_label: Label = null


func _ready() -> void:
	owned_ids.assign(DEFAULT_OWNED_IDS)

	_connect_chrome()
	_hide_scrollbars()
	_seed_local_store()
	# Start from the offline list (the always-playable training arena) so the dashboard
	# is usable immediately, then replace it with the host-created matches from the
	# control plane once GET /matches returns.
	matches = _offline_matches()
	selected_match_id = _fallback_match_id()

	_spawn_preview_player()
	_spawn_preview_chickens()
	_fetch_store_data()
	_fetch_inventory()
	_fetch_matches()
	_fetch_match_join_totals()
	_start_match_join_totals_poll()

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

	_ensure_level_icon()
	_setup_party()


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
	_layout_event_preview()


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
	_sync_party_match()


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
	_sync_party_match()


# ------------------------------------------------------------------ frame loop

func _process(delta: float) -> void:
	_update_preview_camera(delta)
	_tick_preview_emote(delta)
	_party_tick(delta)

	if _is_counting and _party_state.is_empty():
		_elapsed = minf(_elapsed + delta, PLAY_COUNTDOWN_SECONDS)
		if _play_button != null:
			_play_button.text = "%.1fs Cancel" % _elapsed
		if _elapsed >= PLAY_COUNTDOWN_SECONDS:
			_begin_match()
		return

	if tab == TAB_EVENTS:
		_update_play_button_text()


# --------------------------------------------------------------- 3D skin preview

func _spawn_preview_chickens() -> void:
	var parent := get_node_or_null("CanvasLayer/PreviewView/SubViewport")
	if parent == null:
		return
	var chicken_mesh := load("res://assets/Chicken.obj") as Mesh
	if chicken_mesh == null:
		return
	var shader := load("res://assets/shaders/glass_chicken.gdshader") as Shader
	if shader == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("opacity", 1.0)
	_preview_chickens_mat = mat

	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var count := 6
	for i in range(count):
		# Ring around the player, kept in front of the preview camera so every
		# chicken is on screen instead of half of them sitting behind the lens.
		var theta := TAU * float(i) / float(count) + rng.randf_range(-0.18, 0.18)
		var ring_radius := 2.15 + rng.randf_range(-0.15, 0.35)
		var pos := Vector3(
			cos(theta) * ring_radius,
			1.15 + sin(theta) * 0.95,
			-1.75 + rng.randf_range(-0.35, 0.35)
		)
		var mi := MeshInstance3D.new()
		mi.mesh = chicken_mesh
		mi.material_override = mat
		mi.position = pos
		mi.rotation = Vector3(
			rng.randf() * TAU,
			rng.randf() * TAU,
			rng.randf() * TAU
		)
		var s := (0.45 + rng.randf() * 0.35) * 3.0
		mi.scale = Vector3.ONE * s
		mi.set_meta("base_scale", s)
		mi.set_meta("base_pos", pos)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var show_chickens := tab != TAB_STORE
		mi.visible = show_chickens
		parent.add_child(mi)
		_preview_chickens.append(mi)
	_preview_chickens_showing = tab != TAB_STORE
	if not _preview_chickens_showing:
		mat.set_shader_parameter("opacity", 0.0)


func _sync_preview_chickens_visibility() -> void:
	var show_chickens := tab != TAB_STORE
	if show_chickens == _preview_chickens_showing:
		return
	_preview_chickens_showing = show_chickens

	if _preview_chickens_tween != null and _preview_chickens_tween.is_valid():
		_preview_chickens_tween.kill()

	# Slide chickens out of view: left-of-player chickens exit left, right-of-player
	# chickens exit right, while fading.
	var duration := 0.22
	_preview_chickens_tween = create_tween()
	_preview_chickens_tween.set_parallel(true)
	_preview_chickens_tween.set_trans(Tween.TRANS_CUBIC)
	_preview_chickens_tween.set_ease(Tween.EASE_IN if not show_chickens else Tween.EASE_OUT)

	if _preview_chickens_mat != null:
		var target_opacity := 1.0 if show_chickens else 0.0
		_preview_chickens_tween.tween_method(
			func(v: float) -> void: _preview_chickens_mat.set_shader_parameter("opacity", v),
			float(_preview_chickens_mat.get_shader_parameter("opacity")),
			target_opacity,
			duration
		)

	for chicken in _preview_chickens:
		if not is_instance_valid(chicken):
			continue
		var base_pos: Vector3 = chicken.get_meta("base_pos", chicken.position)
		var side := -1.0 if base_pos.x < 0.0 else 1.0
		var offscreen_pos := base_pos + Vector3(side * 10.0, 0.0, 0.0)
		if show_chickens:
			chicken.visible = true
			chicken.position = offscreen_pos
			_preview_chickens_tween.tween_property(chicken, "position", base_pos, duration)
		else:
			_preview_chickens_tween.tween_property(chicken, "position", offscreen_pos, duration)

	if not show_chickens:
		_preview_chickens_tween.chain().tween_callback(func() -> void:
			if _preview_chickens_showing:
				return
			for chicken in _preview_chickens:
				if is_instance_valid(chicken):
					chicken.visible = false
					var base_pos: Vector3 = chicken.get_meta("base_pos", chicken.position)
					chicken.position = base_pos
		)
	else:
		_preview_chickens_tween.chain().tween_callback(func() -> void:
			if not _preview_chickens_showing:
				return
			for chicken in _preview_chickens:
				if is_instance_valid(chicken):
					var base_pos: Vector3 = chicken.get_meta("base_pos", chicken.position)
					chicken.position = base_pos
		)


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


# The preview has no gameplay input to drive its rig, so it would idle forever.
# Fire a full-body flourish every few seconds instead, and wait for the clip to
# finish (play_emote returns its length) before picking the next one. A new clip
# can only start after the old one ended, so two emotes never stack.
func _tick_preview_emote(delta: float) -> void:
	if _navigating or _preview_player == null or not is_instance_valid(_preview_player):
		return
	_preview_emote_timer -= delta
	if _preview_emote_timer > 0.0:
		return
	_play_preview_emote()


func _play_preview_emote() -> void:
	if not _preview_player.has_method("play_emote"):
		_preview_emote_timer = PREVIEW_EMOTE_GAP_MAX
		return
	var choices: Array = PREVIEW_EMOTES.duplicate()
	# Avoid the same flourish twice in a row; with five clips that reads as
	# random rather than as a loop.
	if choices.size() > 1 and _preview_emote_last != "":
		choices.erase(_preview_emote_last)
	var clip := String(choices.pick_random())
	var length := float(_preview_player.call("play_emote", clip))
	if length <= 0.0:
		# Missing clip: still retry later instead of hammering every frame.
		length = 2.0
	_preview_emote_last = clip
	_preview_emote_timer = length + randf_range(PREVIEW_EMOTE_GAP_MIN, PREVIEW_EMOTE_GAP_MAX)


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
			ORBIT_PITCH_MIN, ORBIT_PITCH_MAX)
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

# The preview nad wears the same skin.tscn as the game, so the reveal key works
# here too: holding it shows the parts that ship outside the regular look (the
# shirt, the wig and the glove) and paints the nad's skin in the reveal colour
# while the skin is being inspected, and releasing it puts them back.
# _input rather than _unhandled_input, because the wallet-link
# field can hold the keyboard focus and would swallow the key.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("chog"):
		_set_preview_hidden_extras_revealed(not _preview_hidden_extras_revealed)


# Shows or hides again the preview nad's hidden skin parts and paints its
# skin in the reveal colour. The flag guards the edges: the key-repeat events
# that arrive while the key is held must not re-save the "before" state, or
# the release would restore the revealed state instead of the original one.
func _set_preview_hidden_extras_revealed(revealed: bool) -> void:
	if revealed == _preview_hidden_extras_revealed:
		return
	_preview_hidden_extras_revealed = revealed
	if _preview_player == null:
		return
	SkinApplier.set_hidden_extras_visible(_preview_player, revealed)
	SkinApplier.set_reveal_tint(_preview_player, revealed)


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
# drag right swings the camera left (the model follows the finger), and drag down
# raises the camera (rotateUp lowers phi), which tilts the view down at the nad.
# Vertical orbit is enabled but kept subtle so the nad stays readable.
func _orbit_preview(relative: Vector2) -> void:
	if relative == Vector2.ZERO:
		return
	var per_pixel := TAU * ORBIT_ROTATE_SPEED / _preview_pane_height()
	_preview_delta_yaw -= relative.x * per_pixel
	_preview_delta_pitch += relative.y * per_pixel * 0.35


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
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if _event_in_preview(event.position):
				# Zoom is disabled for the dashboard preview orbit.
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
		# Pinch zoom disabled for the dashboard preview; keep tracking for gesture state.
		_preview_pinch_last = _pinch_distance()
	else:
		_orbit_preview(event.relative)
	get_viewport().set_input_as_handled()


func _handle_preview_magnify(event: InputEventMagnifyGesture) -> void:
	if _event_in_preview(event.position):
		# Zoom is disabled for the dashboard preview orbit.
		get_viewport().set_input_as_handled()


func _handle_preview_pan(event: InputEventPanGesture) -> void:
	if _event_in_preview(event.position):
		_orbit_preview(event.delta * ORBIT_PAN_UNITS_TO_PIXELS)
		get_viewport().set_input_as_handled()


# Dashboard.css keeps the backdrop at a fixed shape: `.lobby-bg img` is width:100%
# with `aspect-ratio: 1216 / 523` and `object-fit: cover`, so every match artwork
# crops to lobbybg's own ratio instead of stretching or changing the height. This
# mirrors that: the TextureRect is pinned to the same constant ratio and uses
# STRETCH_KEEP_ASPECT_COVERED (set on the node) to crop its texture into it.
const LOBBY_BG_ASPECT: float = 1216.0 / 523.0

func _layout_lobby_bg() -> void:
	if _lobby_bg == null:
		return
	var preview_width := get_viewport().get_visible_rect().size.x * 0.65
	if _preview_view != null and _preview_view.size.x > 0.0:
		preview_width = _preview_view.size.x
	var height := preview_width / LOBBY_BG_ASPECT
	_lobby_bg.offset_top = -height * 0.5
	_lobby_bg.offset_bottom = height * 0.5


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
		"image": "/skins_png/1-2.png",
		"tier": "common",
		"required_xp": 0,
		"max_supply": 0,
	})
	store_items.append({
		"id": "s-default-unshaded",
		"name": "Default Nad (Flat)",
		"price": "0 MON",
		"image": "/skins_png/1-2.png",
		"tier": "common",
		"required_xp": 0,
		"max_supply": 0,
	})


func _fetch_store_data() -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_store_data_fetched.bind(http))
	http.request("%s/api/skins" % API_BASE)


func _fetch_inventory(retry: bool = true) -> void:
	if not is_instance_valid(AuthManager) or not AuthManager.is_authenticated():
		if retry:
			await get_tree().create_timer(1.0).timeout
			if is_inside_tree():
				_fetch_inventory(false)
		return
	var response: Dictionary = await AuthManager.request(HTTPClient.METHOD_GET, "/api/skins/inventory")
	if int(response.get("__status", 0)) != 200 or not response.get("ok", false):
		print("Dshbord: inventory fetch failed (%s)" % str(response.get("error", response.get("__status", 0))))
		return
	_apply_inventory_payload(response)


func _apply_inventory_payload(response: Dictionary) -> void:
	_last_inventory_payload = response.duplicate(true)
	var next_owned: Array[String] = []
	for id in DEFAULT_OWNED_IDS:
		next_owned.append(str(id))

	var owned_on_chain: Dictionary = {}
	var raw_on_chain: Variant = response.get("owned_on_chain_ids", [])
	if raw_on_chain is Array:
		for value in raw_on_chain:
			owned_on_chain[ int(value)] = true

	var raw_owned: Variant = response.get("owned_skin_ids", [])
	if raw_owned is Array:
		for value in raw_owned:
			var skin_id := str(value)
			if skin_id != "" and not next_owned.has(skin_id):
				next_owned.append(skin_id)

	# Also mark catalog items whose on-chain id is owned, even if the backend
	# only returned on-chain ids or the skin doc id differs.
	for item in store_items:
		var skin_id := str(item.get("id", ""))
		var on_chain_id := int(item.get("on_chain_id", 0))
		if skin_id == "":
			continue
		if on_chain_id > 0 and owned_on_chain.has(on_chain_id) and not next_owned.has(skin_id):
			next_owned.append(skin_id)

	owned_ids = next_owned

	var equipped := str(response.get("equipped_skin_id", equipped_skin_id)).strip_edges()
	if equipped != "":
		equipped_skin_id = equipped
		# Keep the preview in sync on initial load when nothing specific is selected.
		if tab != TAB_STORE or selected_store_id == "":
			_apply_preview_skin(_displayed_skin_id())

	_refresh_all()


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
		# On-chain id from the skins API; 0 means the item is local-only and
		# cannot be minted (the default-loadout entries).
		var on_chain: Variant = skin.get("onChainId")
		by_id[skin_id] = {
			"id": skin_id,
			"name": str(skin.get("name", "Unknown")),
			"price": str(skin.get("price", "0 MON")),
			"image": str(skin.get("image", "/skins_png/%s.png" % skin_id)),
			"tier": str(skin.get("tier", "common")).to_lower(),
			"required_xp": int(skin.get("requiredXP", 0)),
			"max_supply": int(skin.get("maxSupply", 0)),
			"on_chain_id": int(on_chain) if (on_chain is int or on_chain is float) else 0,
		}

	SkinApplier.seed_from_api(api_skins)

	store_items.clear()
	for key in by_id:
		store_items.append(by_id[key])

	# Store items (and their on-chain ids) changed; re-apply ownership if known.
	if not _last_inventory_payload.is_empty():
		_apply_inventory_payload(_last_inventory_payload)
		return

	_fetch_inventory()
	_apply_preview_skin(_displayed_skin_id())
	_refresh_all()


# ---------------------------------------------------------------------- matches

func _offline_matches() -> Array[Dictionary]:
	# What the dashboard shows until (or if) GET /matches succeeds. Only the
	# permanent rooms live here; everything else comes from the control plane.
	var out: Array[Dictionary] = []
	out.append(_training_match())
	out.append(_chog_match())
	return out


func _training_match() -> Dictionary:
	return {
		"match_id": TRAINING_MATCH_ID,
		"sponsor": "Training Lobby",
		"prize": "Practice",
		"status": "live",
		"start_time": float(Time.get_unix_time_from_system()),
		"description": "Shared warmup arena. Open to everyone and always playable.",
		"cta_mode": "play",
		# Same default the web dashboard pins on its Training card.
		"lobby_bg": "/lobbybg/lobby (1).jpg",
	}


func _chog_match() -> Dictionary:
	return {
		"match_id": CHOG_MATCH_ID,
		"sponsor": "Chog World Order",
		"prize": "Free play",
		"status": "live",
		"start_time": float(Time.get_unix_time_from_system()),
		"description": "Chog World Order is always open. No entry fee, no prize pool - drop in and hold the point.",
		"cta_mode": "play",
		# The web dashboard gives this room a card image and a different lobby
		# backdrop. `image` feeds the match-card shader; `lobby_bg` is the scene
		# behind the 3D preview.
		"image": "/lobbybg/chogcard.jpg",
		"lobby_bg": "/lobbybg/chogbg.jpg",
	}


func _normalize_api_match(entry: Dictionary) -> Dictionary:
	return {
		"match_id": str(entry.get("match_id", "")),
		"sponsor": str(entry.get("sponsor", "Unknown Sponsor")),
		"prize": str(entry.get("prize", "")),
		"status": str(entry.get("status", "upcoming")),
		"start_time": float(entry.get("start_time", 0.0)),
		"description": str(entry.get("description", "")),
		"cta_mode": str(entry.get("cta_mode", "")),
		"image": str(entry.get("image", "")),
		"lobby_bg": str(entry.get("lobby_bg", "")),
	}


func _fetch_matches() -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_matches_fetched.bind(http))
	http.request("%s/matches" % API_BASE)


func _on_matches_fetched(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	if http != null and is_instance_valid(http):
		http.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		print("Dshbord: matches fetch failed (%d %d), keeping offline list." % [result, response_code])
		return

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary) or parsed.get("ok") != true:
		return
	var api_matches: Variant = parsed.get("matches")
	if not (api_matches is Array):
		return

	var previous_match := selected_match_id
	var merged: Array[Dictionary] = []
	for entry in api_matches:
		if entry is Dictionary:
			var m := _normalize_api_match(entry)
			var bg := str(entry.get("lobby_bg", ""))
			if bg != "":
				m["lobby_bg"] = bg
			merged.append(m)
	# The shared training arena and Chog World Order sit after the real matches: the
	# default selection prefers a real live match and only falls back to a permanent
	# room when there is none.
	merged.append(_training_match())
	merged.append(_chog_match())

	matches = merged
	if previous_match != "" and previous_match != TRAINING_MATCH_ID and _match_exists(previous_match):
		selected_match_id = previous_match
	else:
		selected_match_id = _fallback_match_id()
	_refresh_all()
	_fetch_match_join_totals()


func _start_match_join_totals_poll() -> void:
	var timer := Timer.new()
	timer.wait_time = 30.0
	timer.autostart = true
	timer.timeout.connect(_fetch_match_join_totals)
	add_child(timer)


func _fetch_match_join_totals() -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_match_join_totals_fetched.bind(http))
	http.request("%s/api/matches/players" % API_BASE)


func _on_match_join_totals_fetched(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	if http != null and is_instance_valid(http):
		http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		return
	var counts: Variant = parsed.get("counts")
	if not (counts is Dictionary):
		return
	var next: Dictionary = {}
	for key in counts.keys():
		var value = counts[key]
		var total := int(value)
		if total < 0:
			total = 0
		next[str(key)] = total
	_match_join_totals = next
	_refresh_matches()


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
	_refresh_event_preview()
	_refresh_play_button()
	_refresh_footer()
	_sync_preview_chickens_visibility()
	_refresh_party_ui()
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
	# PASS lets ScrollContainer receive touch drags for scrolling on mobile while
	# still allowing tap selection via gui_input.
	card.mouse_filter = Control.MOUSE_FILTER_PASS
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
	card_material.set_shader_parameter("source_tex", _card_texture(match))
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
	# `.match-card-content` bottom padding went 10px -> 40px in Dashboard.css so the
	# centred sponsor/description clears the likes + player-count row; 40 * 0.9 *
	# 129/330 = 14.07 into this layout.
	padding.add_theme_constant_override("margin_bottom", 14)
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

	# `.match-card-stats` - player count, bottom-left on the card (frontend: people only).
	# `.match-card-overlay` counter-skews the card and so does the stats row's own
	# `skewX(5deg)`, so it stays upright here too.
	var stats := HBoxContainer.new()
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# `.match-card-stats { gap: 10px }` -> 10 * 0.9 * 129/330 = 3.52.
	stats.add_theme_constant_override("separation", 4)
	stats.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	# `left: 10px; bottom: 10px` measured in the 0.9-scaled overlay, so both land at
	# 5% of the slot plus 10 * 0.9 * 129/330 - the same inset the prize pill uses.
	stats.offset_left = 9.97
	stats.offset_bottom = -7.82
	stats.grow_horizontal = Control.GROW_DIRECTION_END
	stats.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.add_child(stats)
	stats.add_child(_build_match_stat(STAT_SHAPE_PEOPLE, _match_player_count(match)))

	card.gui_input.connect(_on_match_card_input.bind(match_id))
	card.mouse_entered.connect(_on_match_card_enter.bind(card))
	card.mouse_exited.connect(_on_match_card_exit.bind(card))
	return card


func _build_match_stat(shape: int, count: int) -> HBoxContainer:
	# One `.match-stat`: a black circle holding the white glyph, then the count.
	var stat := HBoxContainer.new()
	stat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# `.match-stat { gap: 5px }` -> 1.76.
	stat.add_theme_constant_override("separation", 2)

	# `.match-icon-badge` - 22px black badge behind the white glyph.
	var badge := Panel.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.custom_minimum_size = Vector2(7.7, 7.7)
	badge.add_theme_stylebox_override("panel", _match_stat_badge_style())
	stat.add_child(badge)

	# The glyph itself. A Material Symbols glyph at 14px inside the 22px badge leaves
	# 4px a side, so the icon box is inset by 4 * 0.9 * 129/330 = 1.4 on every edge.
	# It is a shader rather than a font because the project ships no icon font: see
	# assets/shaders/match_stat_icon.gdshader.
	var glyph := ColorRect.new()
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph.offset_left = 1.4
	glyph.offset_top = 1.4
	glyph.offset_right = -1.4
	glyph.offset_bottom = -1.4
	glyph.color = Color(1, 1, 1, 1)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glyph_material := ShaderMaterial.new()
	glyph_material.shader = MATCH_STAT_ICON_SHADER
	glyph_material.set_shader_parameter("shape", shape)
	glyph.material = glyph_material
	badge.add_child(glyph)

	# `.match-stat-count` - 0.72rem / 600, white. It stays white on a completed card:
	# the CSS `.grayscale-card` text rule covers the sponsor, reward and details only.
	var label := Label.new()
	label.text = _format_player_count(count)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 4)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_apply_font(label, FONT_UI)
	stat.add_child(label)
	return stat


func _on_match_card_input(event: InputEvent, match_id: String) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		# Select on release (tap/click) so press+drag can scroll the carousel.
		if not mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			selected_match_id = match_id
			filter = str(_selected_match().get("status", filter))
			_refresh_all()
			_sync_party_match()


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

	var found := false
	var target_x := 0
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
			found = true
			break

	if not found:
		return
	# Always apply the target, even when it is negative: that just means the card
	# sits in the left half of the first viewport, so the carousel has to scroll
	# back to its start. The ScrollContainer clamps the upper bound itself.
	# Guarding on `target_x > 0` used to swallow every leftward scroll, so
	# selecting a previous card never moved the carousel.
	_match_scroll.scroll_horizontal = maxi(target_x, 0)


func _refresh_rewards() -> void:
	if _reward_scroll != null:
		_reward_scroll.visible = tab == TAB_REWARDS
	if _reward_list == null:
		return
	if tab == TAB_REWARDS:
		_fetch_rewards()
	_render_rewards()


# --- rewards tab ---------------------------------------------------------------
# The list is the ledger settlement wrote (`rewards/<id>`, read through
# /api/rewards), never a client estimate: a row exists only once the control plane
# has committed that money to this player. Rows are newest first, exactly like
# Dashboard.tsx's Rewards tab.

const REWARD_MAX_ROWS: int = 40
const REWARD_MONTHS: Array[String] = [
	"Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
]
const REWARD_GOLD: Color = Color(1.0, 0.92156863, 0.23137255, 1.0)

var _rewards: Array[Dictionary] = []
var _rewards_for: String = ""
var _rewards_error: String = ""
var _rewards_loading: bool = false


func _fetch_rewards() -> void:
	# One fetch per player per session: the ledger only changes when a round
	# settles, and the list is refetched on the next dashboard open.
	var username := AuthManager.get_username().strip_edges()
	if username == "" or _rewards_loading or _rewards_for == username:
		return
	_rewards_loading = true
	var http := HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	http.request_completed.connect(_on_rewards_fetched.bind(http, username))
	var err := http.request("%s/api/rewards?username=%s" % [API_BASE, username.uri_encode()])
	if err != OK:
		http.queue_free()
		_rewards_loading = false
		_rewards_error = "Couldn't load rewards. Check your connection."
		_render_rewards()


func _on_rewards_fetched(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest, username: String) -> void:
	if http != null and is_instance_valid(http):
		http.queue_free()
	_rewards_loading = false

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_rewards_error = "Couldn't load rewards. Check your connection."
		print("Dshbord: rewards fetch failed (%d %d)." % [result, response_code])
		_render_rewards()
		return

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary) or parsed.get("ok") != true:
		_rewards_error = "Couldn't load rewards. Check your connection."
		_render_rewards()
		return

	var rows: Array[Dictionary] = []
	var raw: Variant = parsed.get("rewards")
	if raw is Array:
		for entry in raw:
			# The API already sorts and caps; this only defends against a shape
			# change, so a bad row can never take the whole tab down.
			if entry is Dictionary:
				rows.append(entry)
			if rows.size() >= REWARD_MAX_ROWS:
				break

	_rewards = rows
	_rewards_error = ""
	_rewards_for = username
	_render_rewards()


func _render_rewards() -> void:
	if _reward_list == null:
		return
	for child in _reward_list.get_children():
		if child == _reward_empty:
			continue
		_reward_list.remove_child(child)
		child.queue_free()

	if _reward_empty != null:
		var empty_text := "No rewards yet. Join a match to win some."
		if _rewards_error != "":
			empty_text = _rewards_error
		elif _rewards.is_empty() and AuthManager.get_username().strip_edges() == "":
			empty_text = "Sign in to see your rewards."
		_reward_empty.visible = _rewards.is_empty()
		var text_node := _reward_empty.get_node_or_null("Text") as Label
		if text_node != null:
			text_node.text = empty_text

	if _rewards.is_empty():
		return
	_reward_list.add_child(_build_reward_summary())
	for row in _rewards:
		_reward_list.add_child(_build_reward_card(row))


func _build_reward_summary() -> Control:
	var total := 0.0
	var pending := 0.0
	for row in _rewards:
		var amount := float(row.get("amountMon", 0.0))
		total += amount
		if bool(row.get("pending", false)):
			pending += amount

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _reward_style(true))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	panel.add_child(column)
	column.add_child(_reward_label("%.2f MON" % total, 11, REWARD_GOLD))
	column.add_child(_reward_label(
		"across %d %s" % [_rewards.size(), "reward" if _rewards.size() == 1 else "rewards"],
		5,
		Color(1, 1, 1, 0.7)
	))
	if pending > 0.0:
		column.add_child(_reward_label("%.2f MON awaiting payout" % pending, 5, Color(1, 1, 1, 0.85)))
	return panel


func _build_reward_card(row: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _reward_style(false))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	panel.add_child(column)

	column.add_child(_reward_label(_reward_title(row), 7, Color(1, 1, 1, 1)))

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 3)
	column.add_child(line)
	line.add_child(_reward_label(_reward_amount(row), 9, REWARD_GOLD))
	var source := _reward_label(
		"from %s" % str(row.get("source", "WorldOfNads")),
		5,
		Color(1, 1, 1, 0.6)
	)
	source.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	source.clip_text = true
	line.add_child(source)

	var meta := _reward_meta(row)
	if meta != "":
		var meta_label := _reward_label(meta, 5, Color(1, 1, 1, 0.45))
		meta_label.clip_text = true
		column.add_child(meta_label)
	return panel


# Which pot the row came out of, in the same words as the web dashboard.
func _reward_title(row: Dictionary) -> String:
	var kind := str(row.get("kind", ""))
	if kind == "lootbox" or str(row.get("category", "")) == "lootbox":
		return "Lootbox pool"
	if kind == "stream":
		return "Lootbox stream"
	return "Match prize"


func _reward_amount(row: Dictionary) -> String:
	# Newer rows carry the formatted string; older ones only the number.
	var text := str(row.get("amount", "")).strip_edges()
	if text != "":
		return text
	return "%.4f MON" % float(row.get("amountMon", 0.0))


func _reward_meta(row: Dictionary) -> String:
	var parts: Array[String] = []
	var date := _reward_date(str(row.get("createdAt", "")))
	if date != "":
		parts.append(date)
	var match_id := str(row.get("matchId", "")).strip_edges()
	if match_id != "":
		parts.append(match_id)
	if bool(row.get("pending", false)):
		parts.append("pending")
	elif str(row.get("txHash", "")).strip_edges() != "":
		parts.append("paid")
	return " ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· ".join(parts)


# ISO timestamp -> "13 Nov 2026". Deliberately string-only: the rows mix ISO
# strings with legacy `date` values, and the day is all the tab shows.
func _reward_date(value: String) -> String:
	var date_part := value.substr(0, 10)
	var pieces := date_part.split("-")
	if pieces.size() != 3 or pieces[0].length() != 4 or pieces[2].length() != 2:
		return ""
	var month := int(pieces[1])
	if month < 1 or month > 12:
		return ""
	return "%d %s %s" % [int(pieces[2]), REWARD_MONTHS[month - 1], pieces[0]]


func _reward_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	_apply_font(label, FONT_UI)
	return label


func _reward_style(summary: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if summary:
		# `.reward-summary`: the accent plate that totals the list.
		style.bg_color = Color(REWARD_GOLD.r, REWARD_GOLD.g, REWARD_GOLD.b, 0.14)
		style.border_color = Color(REWARD_GOLD.r, REWARD_GOLD.g, REWARD_GOLD.b, 0.45)
	else:
		# `.reward-item`: a translucent card on the panel.
		style.bg_color = Color(1, 1, 1, 0.08)
		style.border_color = Color(1, 1, 1, 0.16)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 5.0
	style.content_margin_top = 4.0
	style.content_margin_right = 5.0
	style.content_margin_bottom = 4.0
	return style


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
	# PASS lets ScrollContainer receive touch drags for scrolling on mobile while
	# still allowing tap selection via gui_input.
	card.mouse_filter = Control.MOUSE_FILTER_PASS
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
	art.texture = _skin_texture(item)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(art)

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

	card.gui_input.connect(_on_store_card_input.bind(item_id))
	card.mouse_entered.connect(_on_store_card_enter.bind(card))
	card.mouse_exited.connect(_on_store_card_exit.bind(card))
	return cell


func _on_store_card_input(event: InputEvent, item_id: String) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		# Select on release (tap/click) so press+drag can scroll the grid/container.
		if not mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
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
func _ensure_level_icon() -> void:
	if _level_row == null or _level_row.get_node_or_null("LevelIcon") != null:
		return
	var tex: Texture2D = load("res://assets/img/star.png")
	if tex == null:
		return
	var icon := TextureRect.new()
	icon.name = "LevelIcon"
	icon.custom_minimum_size = Vector2(16, 16)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = tex
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_level_row.add_child(icon)
	_level_row.move_child(icon, 0)


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
	if data.size() < 12:
		return false
	return (
		data[0] == 0x52 and data[1] == 0x49 and data[2] == 0x46 and data[3] == 0x46
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
	# Dashboard.tsx always renders the lobby backdrop: store/rewards use fixed art,
	# events follows the selected match. Transitions slide like the frontend.
	if _lobby_bg != null:
		_lobby_bg.visible = true
	_update_lobby_bg()
	_build_skin_variants()
	if not visible:
		return

	var item := _selected_store_item()
	if _skin_preview_name != null:
		_skin_preview_name.text = _skin_base_name(str(item.get("name", "")))
	if _skin_preview_meta != null:
		_skin_preview_meta.text = "Owned" if _is_owned(item) else str(item.get("price", ""))


func _refresh_event_preview() -> void:
	_layout_event_preview()
	var match := _selected_match()
	var desc := str(match.get("description", "")).strip_edges()
	var show := tab == TAB_EVENTS and not match.is_empty() and desc != ""
	if _event_preview != null:
		_event_preview.visible = show
	if not show:
		return
	if _event_preview_desc != null:
		_event_preview_desc.text = desc


# The web dashboard caps the description at `min(420px, 100% - 56px)` so it stays
# a readable column on wide windows; anchors alone would let it grow with the
# 65%-wide preview area.
func _layout_event_preview() -> void:
	if _event_preview == null:
		return
	var view_w := get_viewport().get_visible_rect().size.x
	if view_w <= 0.0:
		return
	var max_width := minf(420.0, view_w * 0.65 - 38.0)
	_event_preview.offset_right = 28.0 + max_width - view_w * 0.65


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
	image.texture = _skin_texture(item)
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
	var in_party := not _party_state.is_empty()
	if _play_button != null:
		_play_button.visible = show_button
		if in_party:
			var party_countdown := str(_party_state.get("status", "")) == "countdown"
			_play_button.disabled = (not _can_play()) or party_countdown or _party_busy
		else:
			_play_button.disabled = not _can_play()
		# .play-fixed.disabled dims the whole button to 0.5 on top of its white ring.
		_play_button.modulate = Color(1, 1, 1, 0.5) if _play_button.disabled else Color(1, 1, 1, 1)
	_update_play_button_text()
	if _party_leave != null:
		_party_leave.visible = false


func _update_play_button_text() -> void:
	if _play_button == null:
		return

	if not _party_state.is_empty():
		if str(_party_state.get("status", "")) == "countdown":
			var end := int(_party_state.get("countdownEnd", 0))
			_play_button.text = "%.1fs" % maxf(0.0, float(end - _party_now_ms()) / 1000.0)
			return
		var username := _party_username()
		var me_ready := false
		var members_value: Variant = _party_state.get("members", [])
		if typeof(members_value) == TYPE_ARRAY:
			for member in members_value:
				if typeof(member) == TYPE_DICTIONARY and str(member.get("username", "")) == username:
					me_ready = bool(member.get("ready", false))
					break
		_play_button.text = "CANCEL" if me_ready else "READY!"
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
	if not _party_state.is_empty():
		if str(_party_state.get("status", "")) == "countdown":
			return
		_on_party_ready_pressed()
		return

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
		#
		# Every other parameter is kept intact. This used to rewrite the query to
		# `?match=...&skin=...`, which threw away ?username= - and with it the
		# session token that rides in front of it. The game then joined with no
		# name at all and the room server displayed its `player-<id>` fallback
		# instead of the signed-in username.
		var js_match := selected_match_id.replace("\\", "\\\\").replace("'", "\\'")
		var js_skin := skin_id.replace("\\", "\\\\").replace("'", "\\'")
		JavaScriptBridge.eval(
			(
				"(() => { const p = new URLSearchParams(window.location.search);"
				+ " p.set('match', '%s'); p.set('skin', '%s');"
				+ " window.history.replaceState({}, '', window.location.pathname + '?' + p.toString()); })();"
			) % [js_match, js_skin]
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
		_mint_button.disabled = _mint_in_flight or (not owned and xp < required_xp)
		if _mint_in_flight:
			_mint_button.text = "MINTING..."
		elif owned:
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
	if item.is_empty() or _mint_in_flight:
		return
	if _is_owned(item):
		_equip_selected_skin()
		return
	if int(item.get("on_chain_id", 0)) <= 0:
		# Local-only items (default loadout) are not on-chain mintable.
		return
	_start_mint(str(item.get("id", "")))


func _start_mint(skin_id: String) -> void:
	_mint_in_flight = true
	if _mint_button != null:
		_mint_button.disabled = true
		_mint_button.text = "MINTING..."
	_run_mint_request(skin_id)


func _run_mint_request(skin_id: String) -> void:
	# The backend re-checks supply and XP, signs mintSkin with the linked
	# player key, and returns the tx hash. The wallet pays price + gas.
	var response: Dictionary = await AuthManager.request(
		HTTPClient.METHOD_POST,
		"/api/skins/mint",
		{"skin_id": skin_id, "amount": 1}
	)
	if int(response.get("__status", 0)) == 200 and response.get("ok", false):
		if not owned_ids.has(skin_id):
			owned_ids.append(skin_id)
		_mint_in_flight = false
		_refresh_all()
		return

	_mint_in_flight = false
	var error_code := str(response.get("error", "mint_failed"))
	var detail := str(response.get("detail", ""))
	if detail != "":
		print("Dshbord: mint failed (%s): %s" % [error_code, detail])
	else:
		print("Dshbord: mint failed (%s)" % error_code)
	if error_code == "wallet_not_linked":
		# First mint on this account: link the key once, then retry.
		_open_wallet_link_dialog(skin_id)
		return
	_refresh_footer()
	_flash_mint_error(_mint_error_text(error_code))


func _mint_error_text(code: String) -> String:
	match code:
		"supply_exhausted":
			return "SOLD OUT"
		"insufficient_xp":
			return "NEED MORE XP"
		"mint_cooldown":
			return "ONE MOMENT"
		"not_on_chain":
			return "NOT MINTABLE"
		"wallet_enc_not_configured":
			return "MINT UNAVAILABLE"
		"wallet_decrypt_failed", "key_wallet_mismatch":
			return "RELINK WALLET"
		"no_wallet_on_account":
			return "NO WALLET"
		"skin_not_found":
			return "SKIN UNAVAILABLE"
		_:
			return "MINT FAILED"


func _flash_mint_error(text: String) -> void:
	if _mint_button == null:
		return
	_mint_button.text = text
	_mint_button.disabled = true
	await get_tree().create_timer(2.5).timeout
	_refresh_footer()


# ------------------------------------------------------------- wallet link

func _open_wallet_link_dialog(skin_id: String) -> void:
	_pending_mint_skin_id = skin_id
	if _wallet_link_dialog != null:
		_wallet_link_dialog.visible = true
		if _wallet_link_status != null:
			_wallet_link_status.text = "Paste your exported wallet key to enable minting."
		return

	var layer := get_node_or_null("CanvasLayer") as CanvasLayer
	if layer == null:
		return

	var panel := PanelContainer.new()
	panel.name = "WalletLinkDialog"
	panel.custom_minimum_size = Vector2(420, 0)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	var title := Label.new()
	title.text = "LINK WALLET"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = "Minting is an on-chain purchase, so it must be signed by your wallet. Paste your wallet's private key once (export it from the web dashboard via Export Wallet). It is sent over HTTPS, stored encrypted on the server, and used only to sign mints for this account."
	body.modulate = Color(1, 1, 1, 0.7)
	column.add_child(body)

	_wallet_link_input = LineEdit.new()
	_wallet_link_input.secret = true
	_wallet_link_input.placeholder_text = "0xÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¦ private key"
	_wallet_link_input.text_changed.connect(func(_text: String) -> void:
		if _wallet_link_status != null:
			_wallet_link_status.text = "")
	column.add_child(_wallet_link_input)

	_wallet_link_status = Label.new()
	_wallet_link_status.text = ""
	_wallet_link_status.modulate = Color(1, 0.6, 0.6)
	_wallet_link_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_wallet_link_status)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)

	var cancel := Button.new()
	cancel.text = "CANCEL"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(_close_wallet_link_dialog)
	buttons.add_child(cancel)

	var link := Button.new()
	link.text = "LINK & MINT"
	link.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	link.pressed.connect(_on_wallet_link_submitted)
	buttons.add_child(link)

	layer.add_child(panel)
	_wallet_link_dialog = panel
	_wallet_link_input.grab_focus()


func _close_wallet_link_dialog() -> void:
	_pending_mint_skin_id = ""
	if _wallet_link_input != null:
		_wallet_link_input.text = ""
	if _wallet_link_dialog != null:
		_wallet_link_dialog.visible = false
	_refresh_footer()


func _on_wallet_link_submitted() -> void:
	if _wallet_link_input == null or _wallet_link_status == null:
		return
	var key := _wallet_link_input.text.strip_edges()
	if key.is_empty():
		_wallet_link_status.text = "Paste your exported private key first."
		return
	_wallet_link_status.text = "Linking wallet..."
	var response: Dictionary = await AuthManager.request(
		HTTPClient.METHOD_POST,
		"/api/wallet/link",
		{"private_key": key}
	)
	# The key only ever lives in this one request; clear the field no matter
	# what happens next.
	_wallet_link_input.text = ""
	if int(response.get("__status", 0)) == 200 and response.get("ok", false):
		var skin_id := _pending_mint_skin_id
		_pending_mint_skin_id = ""
		if _wallet_link_dialog != null:
			_wallet_link_dialog.visible = false
		if not skin_id.is_empty():
			_start_mint(skin_id)
		return
	_wallet_link_status.text = _wallet_link_error_text(str(response.get("error", "")))


func _wallet_link_error_text(code: String) -> String:
	match code:
		"key_wallet_mismatch":
			return "That key belongs to a different wallet than this account."
		"invalid_private_key", "private_key_required":
			return "That doesn't look like a private key."
		"no_wallet_on_account":
			return "This account has no wallet yet. Log in on the web first."
		"mint_cooldown":
			return "One moment ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â a mint just started."
		_:
			return "Linking failed. Try again."


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
	_save_equipped_skin(item_id)


func _save_equipped_skin(skin_id: String) -> void:
	if not is_instance_valid(AuthManager) or not AuthManager.is_authenticated():
		return
	var response: Dictionary = await AuthManager.request(
		HTTPClient.METHOD_POST,
		"/api/skins/equip",
		{"skin_id": skin_id}
	)
	if int(response.get("__status", 0)) != 200 or not response.get("ok", false):
		print("Dshbord: equip save failed (%s)" % str(response.get("error", response.get("__status", 0))))


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
	# Store artwork ships as one render per store *card*, named after the two
	# catalog slots it covers (<lo>-<hi>.png): the default pair owns 1-2.png, then
	# the numeric combos follow, their ids pairing as 2n+1 (shaded) / 2n+2
	# (unshaded). Mirrors skinArtworkFileName() in frontend/src/lib/skinMapping.ts.
	# The filename is derived from the id rather than the item's `image` so a
	# stale document (or the API's /skins_png/<id>.png default) cannot point at
	# artwork that is not in the folder.
	var item_id := str(item.get("id", "")).strip_edges()
	if item_id.is_valid_int() and item_id.to_int() >= 1:
		var combo := floori((item_id.to_int() - 1) / 2.0)
		var lo := 2 * (combo + 2) - 1
		return "%d-%d" % [lo, lo + 1]
	if item_id.replace("-unshaded", "").to_lower() == "s-default":
		return "1-2"
	# Named skin outside the catalog artwork folder: keep whatever it authored.
	var image := str(item.get("image", ""))
	if image != "":
		var base := image.get_file().get_basename()
		if base != "":
			return base
	return item_id


func _skin_texture(item: Dictionary) -> Texture2D:
	var base := _skin_basename(item)
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


# The sponsor-picked lobby backdrop. The form stores `lobbyBg` on the match
# record ("/lobbybg/lobby (7).jpg"), `GET /matches` forwards it as `lobby_bg`,
# and each of the nine images is bundled at res://assets/img/lobbybg/<filename>
# so this stays synchronous and works offline. A record with no stored choice
# falls back to the same stable hash the web dashboard uses
# (frontend/src/data/lobbyBackgrounds.js) - never a random image.
const LOBBY_BG_COUNT := 9
const STORE_BG_PATH: String = "res://assets/img/lobbybg/storebg.jpg"
const REWARDS_BG_PATH: String = "res://assets/img/lobbybg/rewrdsbg.jpg"
const LOBBY_BG_SLIDE_DURATION: float = 0.45
const LOBBY_BG_SLIDE_OFFSET: float = 0.3

func _stable_lobby_bg(match_id: String) -> String:
	if match_id.is_empty() or LOBBY_BG_COUNT <= 0:
		return "lobby (1).jpg"
	var h := 0
	for i in match_id.length():
		h = ((h * 31) + match_id.unicode_at(i)) & 0xFFFFFFFF
	return "lobby (%d).jpg" % ((h % LOBBY_BG_COUNT) + 1)


const LOBBY_BG_BASE_ALPHA := 0.5


func _lobby_bg_target_alpha() -> float:
	return 0.0 if tab == TAB_STORE else LOBBY_BG_BASE_ALPHA


func _lobby_bg_texture(match: Dictionary) -> Texture2D:
	var bg := str(match.get("lobby_bg", ""))
	if bg.is_empty():
		bg = _stable_lobby_bg(str(match.get("match_id", "")))
	var texture := _load_texture("res://assets/img/lobbybg/%s" % bg.get_file())
	return texture if texture != null else MATCH_SRC


# The active backdrop, mirroring Dashboard.tsx: store/rewards use fixed art,
# events follows the selected match (its chosen `lobby_bg`, or a stable hash).
func _active_lobby_bg() -> Dictionary:
	if tab == TAB_STORE:
		return {"key": "tab:store", "texture": _load_texture(STORE_BG_PATH)}
	if tab == TAB_REWARDS:
		return {"key": "tab:rewards", "texture": _load_texture(REWARDS_BG_PATH)}
	var match := _selected_match()
	var match_id := str(match.get("match_id", selected_match_id))
	var bg_name := str(match.get("lobby_bg", ""))
	if bg_name.is_empty():
		bg_name = _stable_lobby_bg(match_id)
	return {
		"key": "match:%s:%s" % [match_id, bg_name.get_file()],
		"texture": _lobby_bg_texture(match),
	}


func _tab_index(t: String) -> int:
	return TAB_ORDER.find(t)


func _match_index(match_id: String) -> int:
	for i in matches.size():
		if str(matches[i].get("match_id", "")) == match_id:
			return i
	return -1


# Slide the lobby backdrop when the active image changes (tab switch or selected
# match), matching the frontend's 0.45s directional enter/exit transition.
func _update_lobby_bg() -> void:
	if _lobby_bg_current == null or _lobby_bg == null:
		return
	var target: Dictionary = _active_lobby_bg()
	var next_key := str(target.get("key", ""))
	var next_tex: Texture2D = target.get("texture", null)
	if next_tex == null:
		next_tex = MATCH_SRC

	# First paint: show the image without a transition, like Dashboard.tsx's
	# initial currentBgSrc.
	if _bg_current_key == "":
		_bg_current_key = next_key
		_bg_prev_tab = tab
		_bg_prev_match_id = selected_match_id
		_apply_bg_layer(_lobby_bg_current, next_tex, 0.0, _lobby_bg_target_alpha())
		_apply_bg_layer(_lobby_bg_prev, null, 0.0, 0.0)
		if _lobby_bg_prev != null:
			_lobby_bg_prev.visible = false
		return

	if next_key == _bg_current_key:
		# State (e.g. the selected match's metadata) may have refreshed without
		# changing the image; keep the texture in sync but do not re-animate.
		_lobby_bg_current.texture = next_tex
		_bg_prev_tab = tab
		_bg_prev_match_id = selected_match_id
		return

	var direction := "right"
	if _bg_prev_tab != tab:
		direction = "right" if _tab_index(tab) >= _tab_index(_bg_prev_tab) else "left"
	elif tab == TAB_EVENTS and _bg_prev_match_id != selected_match_id:
		var prev_idx := _match_index(_bg_prev_match_id)
		var next_idx := _match_index(selected_match_id)
		if prev_idx != -1 and next_idx != -1:
			direction = "right" if next_idx >= prev_idx else "left"
	_bg_prev_tab = tab
	_bg_prev_match_id = selected_match_id

	var old_tex: Texture2D = _lobby_bg_current.texture
	var old_offset := _lobby_bg_current.position.x
	var old_alpha := _lobby_bg_current.modulate.a
	_bg_current_key = next_key

	if _bg_tween != null and _bg_tween.is_valid():
		_bg_tween.kill()

	var vp_w := float(ProjectSettings.get_setting("display/window/size/viewport_width", 500))
	if is_inside_tree():
		var vp := get_viewport()
		if vp != null and vp.get_visible_rect().size.x >= 50.0:
			vp_w = vp.get_visible_rect().size.x
	var width := _lobby_bg.get_rect().size.x
	if width < 50.0:
		width = _lobby_bg.size.x
	if width < 50.0:
		width = vp_w * 0.65
	width = maxf(width, 1.0)
	var enter_from := width * LOBBY_BG_SLIDE_OFFSET if direction == "right" else -width * LOBBY_BG_SLIDE_OFFSET
	var exit_to := -width * LOBBY_BG_SLIDE_OFFSET if direction == "right" else width * LOBBY_BG_SLIDE_OFFSET

	# Previous layer exits opposite the movement; current layer enters from it.
	if _lobby_bg_prev != null:
		_lobby_bg_prev.visible = true
		_lobby_bg_prev.texture = old_tex
		_lobby_bg_prev.position.x = old_offset
		_lobby_bg_prev.modulate.a = old_alpha

	_lobby_bg_current.texture = next_tex
	_lobby_bg_current.position.x = enter_from
	_lobby_bg_current.modulate.a = 0.0
	_lobby_bg_current.visible = true

	_bg_tween = create_tween()
	_bg_tween.set_parallel(true)
	_bg_tween.set_trans(Tween.TRANS_CUBIC)
	_bg_tween.set_ease(Tween.EASE_OUT)
	_bg_tween.tween_property(_lobby_bg_current, "position:x", 0.0, LOBBY_BG_SLIDE_DURATION)
	_bg_tween.tween_property(_lobby_bg_current, "modulate:a", _lobby_bg_target_alpha(), LOBBY_BG_SLIDE_DURATION)
	if _lobby_bg_prev != null:
		_bg_tween.tween_property(_lobby_bg_prev, "position:x", exit_to, LOBBY_BG_SLIDE_DURATION)
		_bg_tween.tween_property(_lobby_bg_prev, "modulate:a", 0.0, LOBBY_BG_SLIDE_DURATION)
	_bg_tween.set_parallel(false)
	_bg_tween.tween_callback(_finish_lobby_bg_transition)


func _apply_bg_layer(layer: TextureRect, texture: Texture2D, offset_x: float, alpha: float) -> void:
	if layer == null:
		return
	layer.texture = texture
	layer.position.x = offset_x
	var c := layer.modulate
	c.a = alpha
	layer.modulate = c
	layer.visible = texture != null and alpha > 0.0


func _finish_lobby_bg_transition() -> void:
	var target_alpha := _lobby_bg_target_alpha()
	if _lobby_bg_current != null:
		_lobby_bg_current.position.x = 0.0
		_lobby_bg_current.modulate.a = target_alpha
		_lobby_bg_current.visible = _lobby_bg_current.texture != null
	if _lobby_bg_prev != null:
		_lobby_bg_prev.position.x = 0.0
		_lobby_bg_prev.modulate.a = 0.0
		_lobby_bg_prev.texture = null
		_lobby_bg_prev.visible = false


# The match-card shader's artwork. It is the record's `image` when it has one
# (the web dashboard's card image), otherwise the lobby backdrop, which is what
# every card used before card art and backdrop could differ.
func _card_texture(match: Dictionary) -> Texture2D:
	var image := str(match.get("image", ""))
	if not image.is_empty():
		var card := _load_texture("res://assets/img/lobbybg/%s" % image.get_file())
		if card != null:
			return card
	return _lobby_bg_texture(match)


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


# --- Match card counts (placeholders) ----------------------------------------
# Ported from Dashboard.tsx. See DUMMY_PLAYER_COUNTS for why the seed is match_id.


func _match_hash_seed(seed: String, salt: int) -> int:
	# `hash * 31 + charCode` masked back to 32 bits, standing in for the TSX
	# helper's `>>> 0` (GDScript ints are 64-bit, so the mask does that job).
	var h := salt & 0xFFFFFFFF
	for i in seed.length():
		h = (h * 31 + seed.unicode_at(i)) & 0xFFFFFFFF
	return h


func _match_player_count(match: Dictionary) -> int:
	# Prefer real backend values. /api/matches/players gives join totals keyed by
	# match id, which is the same source the frontend uses for the people count.
	var match_id := str(match.get("match_id", ""))
	var total := 0
	if match_id != "" and _match_join_totals.has(match_id):
		total = maxi(total, int(_match_join_totals.get(match_id, 0)))
	var alt_id := str(match.get("id", ""))
	if alt_id != "" and _match_join_totals.has(alt_id):
		total = maxi(total, int(_match_join_totals.get(alt_id, 0)))
	for key in ["player_count", "players", "joined", "participant_count", "join_total", "sponsor_player_count"]:
		if match.has(key):
			total = maxi(total, int(match.get(key, 0)))
	return maxi(total, 0)


func _format_player_count(count: int) -> String:
	# formatPlayerCount(): under 1000 verbatim, one decimal up to 10k (dropping a
	# trailing .0), whole thousands above that. `roundf` (not the Variant-returning
	# `round`) so both `:=` declarations keep a static type.
	if count < 1000:
		return str(count)
	var thousands := float(count) / 1000.0
	if thousands >= 10.0:
		return "%dk" % int(roundf(thousands))
	var tenths := roundf(thousands * 10.0) / 10.0
	if is_equal_approx(tenths, roundf(tenths)):
		return "%dk" % int(roundf(tenths))
	return "%sk" % tenths


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


func _match_stat_badge_style() -> StyleBoxFlat:
	# Match stat badge: black background, no rounded corners.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 1)
	style.set_corner_radius_all(0)
	style.content_margin_left = 0.0
	style.content_margin_top = 0.0
	style.content_margin_right = 0.0
	style.content_margin_bottom = 0.0
	return style


func _match_card_style(selected: bool) -> StyleBoxFlat:
	# .match-card draws no box of its own - the artwork is the card, and the white
	# frame `.match-card` now carries is drawn by the match-card shader (it has to
	# sit over the art, and it has to dissolve with it). So this only carries the
	# selected card's purple glow. The scale and skew live in the
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
	# Match the frontend card's square edges.
	style.set_corner_radius_all(0)
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


# ------------------------------------------------------- party / friend invites
#
# The native dashboard is the only place the Android build can invite friends
# before a match, so the squad strip lives here rather than in the game HUD.
# It polls the Node backend (the web dashboard writes the same party state) and
# mirrors the React component: one slot left of the player, two right, an
# accept/reject popup for incoming invites, per-member ready and a 5s launch
# countdown shared by every client.

func _setup_party() -> void:
	_party_http = HTTPRequest.new()
	_party_http.timeout = 8.0
	_party_http.request_completed.connect(_on_party_http_completed)
	add_child(_party_http)

	_party_search_timer = Timer.new()
	_party_search_timer.one_shot = true
	_party_search_timer.wait_time = PARTY_SEARCH_DELAY
	_party_search_timer.timeout.connect(_on_party_search_timeout)
	add_child(_party_search_timer)

	_build_party_ui()
	_build_party_dialogs()
	_fetch_party_state()


func _party_username() -> String:
	var name := ""
	if AuthManager != null and AuthManager.is_authenticated():
		name = str(AuthManager.get_username()).strip_edges()
	if name == "" and OS.has_feature("web"):
		var raw: Variant = JavaScriptBridge.eval(
			"new URLSearchParams(window.location.search).get('username') || ''"
		)
		if typeof(raw) == TYPE_STRING:
			name = str(raw).strip_edges()
			# The legacy web session rides in front of the name as `<token>:<name>`.
			var colon := name.find(":")
			if colon >= 0:
				name = name.substr(colon + 1).strip_edges()
	return name


func _party_now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0) + _party_server_offset_ms


func _party_tick(delta: float) -> void:
	_party_poll_accum += delta
	if _party_poll_accum >= PARTY_POLL_SECONDS:
		_party_poll_accum = 0.0
		if not _party_busy:
			_fetch_party_state()
	_party_slot_dot_phase += delta
	var dots := ".".repeat(int(fmod(_party_slot_dot_phase * 2.0, 4.0)))
	for label in _party_slot_names:
		var nl := label as Label
		if nl != null and nl.visible and bool(nl.get_meta("pending", false)):
			nl.text = str(nl.get_meta("base_name", "")) + dots
	_update_party_countdown_text()
	_maybe_launch_party()


func _fetch_party_state() -> void:
	var username := _party_username()
	if username == "":
		return
	_party_request(
		"state",
		"/api/party/state?username=%s" % username.uri_encode(),
		HTTPClient.METHOD_GET
	)


func _party_request(kind: String, path: String, method: int, body: Dictionary = {}) -> void:
	if _party_busy:
		# Polls are disposable, user actions are not: keep the action for the end
		# of the in-flight request instead of dropping the tap.
		if kind != "state" and _party_queue.size() < 8:
			_party_queue.append([kind, path, method, body])
		return
	_party_start_request(kind, path, method, body)


func _party_start_request(kind: String, path: String, method: int, body: Dictionary) -> void:
	if _party_http == null:
		return
	var payload := ""
	var headers := PackedStringArray()
	if method == HTTPClient.METHOD_POST:
		payload = JSON.stringify(body)
		headers.append("Content-Type: application/json")
	_party_busy = true
	_party_request_kind = kind
	var err := _party_http.request(API_BASE + path, headers, method, payload)
	if err != OK:
		_party_busy = false
		_party_request_kind = ""


func _on_party_http_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	var kind := _party_request_kind
	_party_busy = false
	_party_request_kind = ""

	var parsed: Variant = null
	if result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300:
		parsed = JSON.parse_string(body.get_string_from_utf8())

	if typeof(parsed) == TYPE_DICTIONARY and bool(parsed.get("ok", false)):
		if kind == "search":
			_show_party_search_results(parsed.get("users", []))
		else:
			_apply_party_payload(parsed)
			if kind == "invite":
				_show_party_dialog_status(
					"Invite sent to %s." % _party_last_invite, false
				)
				if _party_search != null:
					_party_search.text = ""
				_clear_party_results()
			elif kind == "respond":
				if _party_invite_popup != null:
					_party_invite_popup.visible = false
	elif typeof(parsed) == TYPE_DICTIONARY:
		_party_show_error(str(parsed.get("error", "")))
	elif kind != "state":
		_party_show_error("offline")

	if not _party_queue.is_empty():
		var next: Array = _party_queue.pop_front()
		_party_start_request(str(next[0]), str(next[1]), int(next[2]), next[3])


func _apply_party_payload(data: Dictionary) -> void:
	var party_value: Variant = data.get("party", null)
	_party_state = party_value if typeof(party_value) == TYPE_DICTIONARY else {}
	var invites_value: Variant = data.get("invites", [])
	_party_invites = invites_value if typeof(invites_value) == TYPE_ARRAY else []

	var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
	var server_now := int(data.get("serverNow", now_ms))
	_party_server_offset_ms = server_now - now_ms

	_adopt_party_match()
	_refresh_party_ui()
	_refresh_party_invite_popup()


# Guests follow the party's match (the host picked it when inviting). On the
# host the two already agree; if a stale poll arrives mid-selection it settles
# when the POST /api/party/match response lands.
func _adopt_party_match() -> void:
	var match_id := str(_party_state.get("matchId", ""))
	if match_id == "" or match_id == selected_match_id:
		return
	# The host's card selection drives the party (see _sync_party_match), so only
	# guests snap to the stored match.
	if str(_party_state.get("host", "")) == _party_username():
		return
	if not _match_exists(match_id):
		return
	selected_match_id = match_id
	filter = str(_selected_match().get("status", filter))
	_refresh_all()


func _sync_party_match() -> void:
	if _party_state.is_empty():
		return
	var username := _party_username()
	if username == "" or str(_party_state.get("host", "")) != username:
		return
	var match_id := selected_match_id
	if match_id == "" or match_id == str(_party_state.get("matchId", "")):
		return
	_party_request(
		"match",
		"/api/party/match",
		HTTPClient.METHOD_POST,
		{"username": username, "matchId": match_id}
	)


func _maybe_launch_party() -> void:
	if _party_state.is_empty() or _navigating:
		return
	if str(_party_state.get("status", "")) != "countdown":
		return
	var end := int(_party_state.get("countdownEnd", 0))
	if end <= 0:
		return
	var now := _party_now_ms()
	if now < end:
		return
	var party_id := str(_party_state.get("id", ""))
	if party_id == "" or _party_launched_id == party_id:
		return
	# A dashboard opened long after the launch must not yank the player into a
	# match everyone else already left. Drop the dead squad instead of showing a
	# 0.0s countdown until the server prunes it.
	if now - end > PARTY_STALE_LAUNCH_MS:
		_party_launched_id = party_id
		_party_state = {}
		_party_invites = []
		_refresh_party_ui()
		_party_request(
			"leave",
			"/api/party/leave",
			HTTPClient.METHOD_POST,
			{"username": _party_username()}
		)
		return
	var match_id := str(_party_state.get("matchId", ""))
	if match_id == "":
		return
	_party_launched_id = party_id
	selected_match_id = match_id
	_begin_match()


func _party_match_label(match_id: String) -> String:
	var match_data := _selected_match_of(match_id)
	if match_data.is_empty():
		return match_id
	return str(match_data.get("sponsor", match_id))


func _update_party_countdown_text() -> void:
	if _party_state.is_empty():
		return
	if str(_party_state.get("status", "")) != "countdown":
		return
	_update_play_button_text()


func _tween_party_ctrl(ctrl: Control, hidden: bool, dir: float, show_alpha: float = 1.0) -> void:
	if ctrl == null:
		return
	var base_left := float(ctrl.get_meta("base_offset_left", ctrl.offset_left))
	var base_right := float(ctrl.get_meta("base_offset_right", ctrl.offset_right))
	var base_top := float(ctrl.get_meta("base_offset_top", ctrl.offset_top))
	var base_bottom := float(ctrl.get_meta("base_offset_bottom", ctrl.offset_bottom))
	var key := "rewards_hidden"
	var already := ctrl.has_meta(key) and bool(ctrl.get_meta(key)) == hidden
	if already:
		var active: Variant = ctrl.get_meta("hide_tween", false)
		if active is Tween and (active as Tween).is_valid():
			return
		if not hidden:
			ctrl.visible = true
			ctrl.modulate.a = show_alpha
			ctrl.offset_left = base_left
			ctrl.offset_right = base_right
			ctrl.offset_top = base_top
			ctrl.offset_bottom = base_bottom
			return
		ctrl.visible = false
		ctrl.modulate.a = 0.0
		return
	ctrl.set_meta(key, hidden)
	var existing: Variant = ctrl.get_meta("hide_tween", false)
	if existing is Tween and (existing as Tween).is_valid():
		(existing as Tween).kill()
	var tween := create_tween()
	ctrl.set_meta("hide_tween", tween)
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN if hidden else Tween.EASE_OUT)
	var slide := dir * 140.0
	var target_left := base_left + (slide if hidden else 0.0)
	var target_right := base_right + (slide if hidden else 0.0)
	var target_alpha := 0.0 if hidden else show_alpha
	if not hidden:
		ctrl.visible = true
		ctrl.modulate.a = 0.0
		ctrl.offset_left = base_left + slide
		ctrl.offset_right = base_right + slide
		ctrl.offset_top = base_top
		ctrl.offset_bottom = base_bottom
	tween.tween_property(ctrl, "offset_left", target_left, 0.22)
	tween.tween_property(ctrl, "offset_right", target_right, 0.22)
	tween.tween_property(ctrl, "modulate:a", target_alpha, 0.22)
	if hidden:
		tween.chain().tween_callback(func() -> void:
			if bool(ctrl.get_meta("rewards_hidden", false)):
				ctrl.visible = false
		)


func _refresh_party_ui() -> void:
	if _party_slots.is_empty():
		return

	# A party in progress owns the launch flow; cancel any solo local countdown.
	if not _party_state.is_empty():
		_is_counting = false
		_elapsed = 0.0

	var username := _party_username()
	var has_party := not _party_state.is_empty()
	var me_ready := false
	var others: Array = []

	if has_party:
		var members_value: Variant = _party_state.get("members", [])
		if typeof(members_value) == TYPE_ARRAY:
			for member in members_value:
				if typeof(member) != TYPE_DICTIONARY:
					continue
				var member_name := str(member.get("username", ""))
				if member_name == "":
					continue
				if member_name == username:
					me_ready = bool(member.get("ready", false))
				else:
					others.append({
						"kind": "member",
						"name": member_name,
						"ready": bool(member.get("ready", false))
					})
		var pending_value: Variant = _party_state.get("pending", [])
		if typeof(pending_value) == TYPE_ARRAY:
			for pending in pending_value:
				if typeof(pending) != TYPE_DICTIONARY:
					continue
				var invited_name := str(pending.get("to", ""))
				if invited_name != "":
					others.append({
						"kind": "pending",
						"name": invited_name,
						"ready": false
					})

	while others.size() < 3:
		others.append({})

	for index in range(_party_slots.size()):
		var slot: Button = _party_slots[index]
		var name_label: Label = _party_slot_names[index] if index < _party_slot_names.size() else null
		var dir := -1.0 if index == 0 else 1.0
		var row: Dictionary = others[index]
		if row.is_empty():
			# Store focuses on skin preview; Rewards hides party UI but keeps chickens.
			var show_invite_slot := tab == TAB_EVENTS
			_tween_party_ctrl(slot, not show_invite_slot, dir)
			if name_label != null:
				_tween_party_ctrl(name_label, true, dir)
			slot.text = "+"
			slot.set_meta("slot_kind", "empty")
			slot.tooltip_text = "Invite a friend"
			slot.set_meta("base_offset_left", -22.0)
			slot.set_meta("base_offset_right", 22.0)
			slot.set_meta("base_offset_top", -22.0)
			slot.set_meta("base_offset_bottom", 22.0)
			if _party_slot_plus_style != null:
				for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
					slot.add_theme_stylebox_override(
						state_name,
						_party_slot_plus_hover if state_name == "hover" and _party_slot_plus_hover != null else _party_slot_plus_style
					)
			slot.add_theme_color_override("font_color", Color(1, 1, 1, 1))
			slot.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
			slot.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
			slot.add_theme_font_size_override("font_size", 22)
			if name_label != null:
				name_label.text = ""
		elif str(row.get("kind", "")) == "pending":
			var invited_name := str(row.get("name", ""))
			var show_slot := tab != TAB_REWARDS
			_tween_party_ctrl(slot, not show_slot, dir, 0.82)
			slot.text = invited_name.substr(0, 2).to_upper()
			slot.set_meta("slot_kind", "pending")
			slot.set_meta("slot_name", invited_name)
			slot.tooltip_text = "%s (pending)" % invited_name
			slot.set_meta("base_offset_left", -22.0)
			slot.set_meta("base_offset_right", 22.0)
			slot.set_meta("base_offset_top", -22.0)
			slot.set_meta("base_offset_bottom", 22.0)
			if _party_slot_filled_style != null:
				for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
					slot.add_theme_stylebox_override(state_name, _party_slot_filled_style)
			slot.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
			slot.add_theme_color_override("font_hover_color", Color(1, 1, 1, 0.9))
			slot.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 0.9))
			slot.add_theme_font_size_override("font_size", 10)
			if name_label != null:
				_tween_party_ctrl(name_label, not show_slot, dir)
				name_label.set_meta("pending", true)
				name_label.set_meta("base_name", invited_name)
		else:
			var member_name := str(row.get("name", ""))
			var ready := bool(row.get("ready", false))
			var show_slot := tab != TAB_REWARDS
			_tween_party_ctrl(slot, not show_slot, dir)
			slot.text = member_name.substr(0, 2).to_upper()
			slot.set_meta("slot_kind", "member")
			slot.set_meta("slot_name", member_name)
			slot.tooltip_text = member_name
			slot.set_meta("base_offset_left", -22.0)
			slot.set_meta("base_offset_right", 22.0)
			slot.set_meta("base_offset_top", -22.0)
			slot.set_meta("base_offset_bottom", 22.0)
			var member_style := _party_slot_filled_style
			if ready and _party_slot_filled_style != null:
				var ready_style := _party_slot_filled_style.duplicate() as StyleBoxFlat
				if ready_style != null:
					ready_style.border_color = PARTY_ACCENT
					member_style = ready_style
			if member_style != null:
				for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
					slot.add_theme_stylebox_override(state_name, member_style)
			var member_color := PARTY_ACCENT if ready else Color(1, 1, 1, 0.95)
			slot.add_theme_color_override("font_color", member_color)
			slot.add_theme_color_override("font_hover_color", member_color)
			slot.add_theme_color_override("font_pressed_color", member_color)
			slot.add_theme_font_size_override("font_size", 10)
			if name_label != null:
				_tween_party_ctrl(name_label, not show_slot, dir)
				name_label.set_meta("pending", false)
				name_label.text = member_name
				name_label.add_theme_color_override("font_color", PARTY_ACCENT if ready else Color(1, 1, 1, 0.9))

	if _party_me_leave != null:
		_tween_party_ctrl(_party_me_leave, not (has_party and tab != TAB_REWARDS), -1.0)
		_party_me_leave.disabled = _party_busy

	_refresh_play_button()


func _refresh_party_invite_popup() -> void:
	if _party_invite_popup == null or _party_invite_label == null:
		return
	if not _party_state.is_empty() or _party_invites.is_empty():
		_party_invite_popup.visible = false
		return
	var invite: Variant = _party_invites[0]
	if typeof(invite) != TYPE_DICTIONARY:
		_party_invite_popup.visible = false
		return
	_party_invite_label.text = "%s invited you to %s." % [
		str(invite.get("from", "")),
		_party_match_label(str(invite.get("matchId", "")))
	]
	_party_invite_popup.visible = true


func _show_party_dialog_status(text: String, is_error: bool) -> void:
	if _party_dialog_status == null:
		return
	_party_dialog_status.text = text
	# The frontend only renders the notice/error when there is one, so an empty
	# status must not leave a blank line behind.
	_party_dialog_status.visible = text != ""
	_party_dialog_status.add_theme_color_override(
		"font_color",
		Color(1.0, 0.52, 0.52) if is_error else Color(0.52, 0.95, 0.7)
	)


func _party_show_error(code: String) -> void:
	var text := "Something went wrong. Try again."
	match code:
		"unknown_user":
			text = "No player with that username."
		"already_in_party":
			text = "That player is already in a party."
		"party_full":
			text = "That party is full (4 players max)."
		"already_member":
			text = "They are already in your party."
		"cannot_invite_self":
			text = "You cannot invite yourself."
		"invite_expired":
			text = "That invite has expired."
		"offline":
			text = "Party service unreachable. Check your connection."
	if _party_dialog != null and _party_dialog.visible:
		_show_party_dialog_status(text, true)


# --------------------------------------------------------- party UI construction

func _party_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PARTY_UI_BG
	style.border_color = PARTY_UI_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


func _party_button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	return style


func _make_leave_icon() -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var w := Color(1, 1, 1, 1)
	for y in range(7, 25):
		img.set_pixel(8, y, w)
		img.set_pixel(18, y, w)
	for x in range(8, 19):
		img.set_pixel(x, 7, w)
		img.set_pixel(x, 24, w)
	for y in range(14, 18):
		img.set_pixel(18, y, Color(0, 0, 0, 0))
	for x in range(14, 25):
		img.set_pixel(x, 16, w)
		img.set_pixel(x, 15, w)
	for i in range(5):
		img.set_pixel(20 + i, 11 + i, w)
		img.set_pixel(20 + i, 12 + i, w)
		img.set_pixel(20 + i, 20 - i, w)
		img.set_pixel(20 + i, 19 - i, w)
	return ImageTexture.create_from_image(img)


func _build_party_ui() -> void:
	var layer := get_node_or_null("CanvasLayer") as CanvasLayer
	if layer == null:
		return

	# Plus buttons: white "+" on a black rounded background, floating over the 3D preview.
	_party_slot_plus_style = StyleBoxFlat.new()
	_party_slot_plus_style.bg_color = Color(0, 0, 0, 1)
	_party_slot_plus_style.set_corner_radius_all(14)
	_party_slot_plus_style.set_border_width_all(0)

	_party_slot_plus_hover = _party_slot_plus_style.duplicate() as StyleBoxFlat
	if _party_slot_plus_hover != null:
		_party_slot_plus_hover.bg_color = Color(0.12, 0.12, 0.12, 1)

	_party_slot_filled_style = StyleBoxFlat.new()
	_party_slot_filled_style.bg_color = Color(0, 0, 0, 0.78)
	_party_slot_filled_style.set_corner_radius_all(14)
	_party_slot_filled_style.set_border_width_all(1)
	_party_slot_filled_style.border_color = Color(1, 1, 1, 0.14)
	_party_slot_filled_style.content_margin_left = 6
	_party_slot_filled_style.content_margin_right = 6
	_party_slot_filled_style.content_margin_top = 4
	_party_slot_filled_style.content_margin_bottom = 4

	_party_overlay = Control.new()
	_party_overlay.name = "PartyOverlay"
	_party_overlay.anchor_left = 0.0
	_party_overlay.anchor_top = 0.0
	_party_overlay.anchor_right = 0.65
	_party_overlay.anchor_bottom = 1.0
	_party_overlay.offset_left = 0.0
	_party_overlay.offset_top = 0.0
	_party_overlay.offset_right = 0.0
	_party_overlay.offset_bottom = 0.0
	# Ignore so the 3D preview drag still works everywhere except on the slot buttons.
	_party_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_party_overlay)

	_party_slots.clear()
	_party_slot_names.clear()
	var slot_positions := [Vector2(0.22, 0.42), Vector2(0.72, 0.42), Vector2(0.86, 0.38)]
	for index in range(slot_positions.size()):
		var pos: Vector2 = slot_positions[index]
		var slot := Button.new()
		slot.anchor_left = pos.x
		slot.anchor_top = pos.y
		slot.anchor_right = pos.x
		slot.anchor_bottom = pos.y
		slot.offset_left = -22.0
		slot.offset_top = -22.0
		slot.offset_right = 22.0
		slot.offset_bottom = 22.0
		slot.set_meta("base_offset_left", slot.offset_left)
		slot.set_meta("base_offset_right", slot.offset_right)
		slot.set_meta("base_offset_top", slot.offset_top)
		slot.set_meta("base_offset_bottom", slot.offset_bottom)
		slot.custom_minimum_size = Vector2(44, 44)
		slot.text = "+"
		slot.set_meta("slot_kind", "empty")
		slot.add_theme_font_override("font", FONT_UI)
		slot.add_theme_font_size_override("font_size", 22)
		slot.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		slot.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
		slot.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
		if _party_slot_plus_style != null:
			for state_name in ["normal", "pressed", "disabled", "focus"]:
				slot.add_theme_stylebox_override(state_name, _party_slot_plus_style)
		if _party_slot_plus_hover != null:
			slot.add_theme_stylebox_override("hover", _party_slot_plus_hover)
		slot.pressed.connect(_on_party_slot_pressed.bind(index))
		_party_overlay.add_child(slot)
		_party_slots.append(slot)

		var name_label := Label.new()
		name_label.anchor_left = pos.x
		name_label.anchor_top = pos.y
		name_label.anchor_right = pos.x
		name_label.anchor_bottom = pos.y
		name_label.offset_left = -40.0
		name_label.offset_top = 24.0
		name_label.offset_right = 40.0
		name_label.offset_bottom = 38.0
		name_label.set_meta("base_offset_left", name_label.offset_left)
		name_label.set_meta("base_offset_right", name_label.offset_right)
		name_label.set_meta("base_offset_top", name_label.offset_top)
		name_label.set_meta("base_offset_bottom", name_label.offset_bottom)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.add_theme_font_override("font", FONT_UI)
		name_label.add_theme_font_size_override("font_size", 7)
		name_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		name_label.visible = false
		_party_overlay.add_child(name_label)
		_party_slot_names.append(name_label)

	_party_me_leave = Button.new()
	_party_me_leave.anchor_left = 0.5
	_party_me_leave.anchor_top = 0.32
	_party_me_leave.anchor_right = 0.5
	_party_me_leave.anchor_bottom = 0.32
	_party_me_leave.offset_left = -22.0
	_party_me_leave.offset_top = -22.0
	_party_me_leave.offset_right = 22.0
	_party_me_leave.offset_bottom = 22.0
	_party_me_leave.set_meta("base_offset_left", _party_me_leave.offset_left)
	_party_me_leave.set_meta("base_offset_right", _party_me_leave.offset_right)
	_party_me_leave.set_meta("base_offset_top", _party_me_leave.offset_top)
	_party_me_leave.set_meta("base_offset_bottom", _party_me_leave.offset_bottom)
	_party_me_leave.visible = false
	_party_me_leave.tooltip_text = "Leave party"
	_party_me_leave.icon = _make_leave_icon()
	_party_me_leave.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_party_me_leave.expand_icon = true
	var leave_center_style := StyleBoxFlat.new()
	leave_center_style.bg_color = Color(1.0, 0.14117648, 0.5882353, 1.0)
	leave_center_style.set_corner_radius_all(0)
	leave_center_style.skew = Vector2(0.24, 0)
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		_party_me_leave.add_theme_stylebox_override(state_name, leave_center_style)
	_party_me_leave.pressed.connect(_on_party_leave_pressed)
	_party_overlay.add_child(_party_me_leave)

	# Leave button is rendered as the center overlay on the player (see _party_me_leave).

	_refresh_party_ui()


func _build_party_dialogs() -> void:
	var layer := get_node_or_null("CanvasLayer") as CanvasLayer
	if layer == null:
		return

	# Invite dialog: username search -> tap a result to send the invite.
	_party_dialog = Control.new()
	_party_dialog.name = "PartyInviteDialog"
	_party_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_party_dialog.visible = false
	layer.add_child(_party_dialog)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.05, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_party_dialog.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_party_dialog.add_child(center)

	var dialog_panel_style := _party_panel_style()
	dialog_panel_style.bg_color = Color(0.39607844, 0.3254902, 0.78039217, 1.0)
	dialog_panel_style.border_color = Color(1, 1, 1, 0.2)
	dialog_panel_style.set_corner_radius_all(0)
	dialog_panel_style.content_margin_left = 14
	dialog_panel_style.content_margin_right = 14
	dialog_panel_style.content_margin_top = 12
	dialog_panel_style.content_margin_bottom = 12

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)
	panel.add_theme_stylebox_override("panel", dialog_panel_style)
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var title := Label.new()
	title.text = "INVITE A FRIEND"
	title.add_theme_font_override("font", FONT_UI)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Up to 4 players. Everyone readies up and launches together."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_override("font", FONT_UI)
	subtitle.add_theme_font_size_override("font_size", 8)
	subtitle.add_theme_color_override("font_color", Color(1, 1, 1, 0.68))
	column.add_child(subtitle)

	var search_style := StyleBoxFlat.new()
	search_style.bg_color = Color(0, 0, 0, 0.18)
	search_style.border_color = Color(1, 1, 1, 0.28)
	search_style.set_border_width_all(1)
	search_style.content_margin_left = 8
	search_style.content_margin_right = 8

	_party_search = LineEdit.new()
	_party_search.placeholder_text = "Enter a username"
	_party_search.custom_minimum_size = Vector2(0, 30)
	_party_search.add_theme_font_override("font", FONT_UI)
	_party_search.add_theme_font_size_override("font_size", 9)
	_party_search.add_theme_stylebox_override("normal", search_style)
	_party_search.add_theme_stylebox_override("focus", search_style)
	_party_search.text_changed.connect(_on_party_query_changed)
	_party_search.text_submitted.connect(_on_party_search_submitted)
	column.add_child(_party_search)

	# The results list is only as tall as its rows (an empty search keeps the
	# dialog short) and starts scrolling past PARTY_RESULTS_MAX_HEIGHT, the same
	# way `.party-results` does in PartyBar.css.
	_party_results_scroll = ScrollContainer.new()
	_party_results_scroll.custom_minimum_size = Vector2(0, 0)
	_party_results_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_party_results_scroll)

	_party_results = VBoxContainer.new()
	_party_results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_party_results.add_theme_constant_override("separation", 3)
	_party_results_scroll.add_child(_party_results)

	_party_dialog_status = Label.new()
	_party_dialog_status.visible = false
	_party_dialog_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_party_dialog_status.add_theme_font_override("font", FONT_UI)
	_party_dialog_status.add_theme_font_size_override("font_size", 8)
	_party_dialog_status.add_theme_color_override("font_color", Color(0.52, 0.95, 0.7))
	column.add_child(_party_dialog_status)

	var close := Button.new()
	close.text = "CLOSE"
	close.custom_minimum_size = Vector2(0, 30)
	close.add_theme_font_override("font", FONT_UI)
	close.add_theme_font_size_override("font_size", 9)
	close.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	close.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	close.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
	var close_style := _party_button_style(Color(1.0, 0.14117648, 0.5882353, 1.0), Color(1.0, 0.14117648, 0.5882353, 1.0))
	close_style.set_corner_radius_all(0)
	close_style.skew = Vector2(0.24, 0)
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		close.add_theme_stylebox_override(state_name, close_style)
	close.pressed.connect(_close_party_dialog)
	column.add_child(close)

	# Incoming invite popup. Added after the dialog so it sits on top if both
	# happen to be visible.
	_party_invite_popup = Control.new()
	_party_invite_popup.name = "PartyInvitePopup"
	_party_invite_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	_party_invite_popup.visible = false
	layer.add_child(_party_invite_popup)

	var popup_dim := ColorRect.new()
	popup_dim.color = Color(0.02, 0.01, 0.05, 0.72)
	popup_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_party_invite_popup.add_child(popup_dim)

	var popup_center := CenterContainer.new()
	popup_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_party_invite_popup.add_child(popup_center)

	var popup_panel_style := _party_panel_style()
	popup_panel_style.bg_color = Color(0.39607844, 0.3254902, 0.78039217, 1.0)
	popup_panel_style.border_color = Color(1, 1, 1, 0.2)
	popup_panel_style.set_corner_radius_all(0)
	popup_panel_style.content_margin_left = 14
	popup_panel_style.content_margin_right = 14
	popup_panel_style.content_margin_top = 12
	popup_panel_style.content_margin_bottom = 12

	var popup_panel := PanelContainer.new()
	popup_panel.custom_minimum_size = Vector2(320, 0)
	popup_panel.add_theme_stylebox_override("panel", popup_panel_style)
	popup_center.add_child(popup_panel)

	var popup_column := VBoxContainer.new()
	popup_column.add_theme_constant_override("separation", 8)
	popup_panel.add_child(popup_column)

	var popup_title := Label.new()
	popup_title.text = "PARTY INVITE"
	popup_title.add_theme_font_override("font", FONT_UI)
	popup_title.add_theme_font_size_override("font_size", 14)
	popup_title.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	popup_column.add_child(popup_title)

	_party_invite_label = Label.new()
	_party_invite_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_party_invite_label.add_theme_font_override("font", FONT_UI)
	_party_invite_label.add_theme_font_size_override("font_size", 9)
	_party_invite_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.78))
	popup_column.add_child(_party_invite_label)

	var popup_actions := HBoxContainer.new()
	popup_actions.add_theme_constant_override("separation", 8)
	popup_column.add_child(popup_actions)

	var accept := Button.new()
	accept.text = "ACCEPT"
	accept.custom_minimum_size = Vector2(0, 32)
	accept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	accept.add_theme_font_override("font", FONT_UI)
	accept.add_theme_font_size_override("font_size", 10)
	accept.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	accept.add_theme_color_override("font_hover_color", Color(0, 0, 0, 1))
	accept.add_theme_color_override("font_pressed_color", Color(0, 0, 0, 1))
	var accept_style := _party_button_style(PARTY_ACCENT, PARTY_ACCENT)
	accept_style.set_corner_radius_all(0)
	accept_style.skew = Vector2(0.24, 0)
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		accept.add_theme_stylebox_override(state_name, accept_style)
	accept.pressed.connect(_on_party_invite_accept)
	popup_actions.add_child(accept)

	var reject := Button.new()
	reject.text = "REJECT"
	reject.custom_minimum_size = Vector2(0, 32)
	reject.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reject.add_theme_font_override("font", FONT_UI)
	reject.add_theme_font_size_override("font_size", 10)
	reject.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	reject.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	reject.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
	var reject_style := _party_button_style(Color(1.0, 0.14117648, 0.5882353, 1.0), Color(1.0, 0.14117648, 0.5882353, 1.0))
	reject_style.set_corner_radius_all(0)
	reject_style.skew = Vector2(0.24, 0)
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		reject.add_theme_stylebox_override(state_name, reject_style)
	reject.pressed.connect(_on_party_invite_reject)
	popup_actions.add_child(reject)


# ------------------------------------------------------------ party UI handlers

func _open_party_dialog() -> void:
	if _party_dialog == null:
		return
	if not _party_state.is_empty():
		var members_value: Variant = _party_state.get("members", [])
		if typeof(members_value) == TYPE_ARRAY and members_value.size() >= PARTY_MAX_MEMBERS:
			_show_party_dialog_status("Your party is full (4 players max).", true)
			return
	_party_dialog.visible = true
	_show_party_dialog_status("", false)
	_clear_party_results()
	if _party_search != null:
		_party_search.text = ""
		_party_search.grab_focus()


func _close_party_dialog() -> void:
	if _party_dialog != null:
		_party_dialog.visible = false
	if _party_search_timer != null:
		_party_search_timer.stop()


func _clear_party_results() -> void:
	if _party_results == null:
		return
	# Remove right away (not just queue_free) so the height fit below measures
	# only the rows that are actually still there.
	for child in _party_results.get_children():
		_party_results.remove_child(child)
		child.queue_free()
	_fit_party_results_height()


# Keeps the results list as short as its rows, growing up to the CSS cap.
func _fit_party_results_height() -> void:
	if _party_results_scroll == null or _party_results == null:
		return
	var content_height := _party_results.get_combined_minimum_size().y
	_party_results_scroll.custom_minimum_size = Vector2(
		0, minf(content_height, PARTY_RESULTS_MAX_HEIGHT)
	)


func _on_party_query_changed(text: String) -> void:
	_show_party_dialog_status("", false)
	if text.strip_edges().length() < 2:
		_clear_party_results()
		if _party_search_timer != null:
			_party_search_timer.stop()
		return
	if _party_search_timer != null:
		_party_search_timer.start()


func _on_party_search_submitted(_text: String) -> void:
	_on_party_search_timeout()


func _on_party_search_timeout() -> void:
	if _party_dialog == null or not _party_dialog.visible or _party_search == null:
		return
	var query := _party_search.text.strip_edges()
	if query.length() < 2:
		return
	_party_request(
		"search",
		"/api/party/search?q=%s" % query.uri_encode(),
		HTTPClient.METHOD_GET
	)


func _show_party_search_results(users: Variant) -> void:
	_clear_party_results()
	if _party_results == null or typeof(users) != TYPE_ARRAY:
		return
	var count := 0
	for user in users:
		if typeof(user) != TYPE_DICTIONARY:
			continue
		var invited_name := str(user.get("username", ""))
		if invited_name == "":
			continue
		var button := Button.new()
		button.text = invited_name
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 28)
		button.add_theme_font_override("font", FONT_UI)
		button.add_theme_font_size_override("font_size", 9)
		button.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		button.add_theme_color_override("font_hover_color", PARTY_ACCENT)
		button.add_theme_color_override("font_pressed_color", PARTY_ACCENT)
		var row_style := _party_button_style(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.1))
		row_style.set_corner_radius_all(0)
		for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
			button.add_theme_stylebox_override(state_name, row_style)
		button.pressed.connect(_on_party_invite_result.bind(invited_name))
		_party_results.add_child(button)
		count += 1
	if count == 0:
		var empty := Label.new()
		empty.text = "No players found."
		empty.add_theme_font_override("font", FONT_UI)
		empty.add_theme_font_size_override("font_size", 8)
		empty.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
		_party_results.add_child(empty)
	_fit_party_results_height()


func _on_party_invite_result(invited_name: String) -> void:
	if selected_match_id == "":
		_show_party_dialog_status("Pick a match first.", true)
		return
	_party_last_invite = invited_name
	var match_id := str(_party_state.get("matchId", selected_match_id))
	if match_id == "":
		match_id = selected_match_id
	_party_request(
		"invite",
		"/api/party/invite",
		HTTPClient.METHOD_POST,
		{
			"from": _party_username(),
			"to": invited_name,
			"matchId": match_id,
			"skin": _displayed_skin_id()
		}
	)


func _on_party_slot_pressed(index: int) -> void:
	if index >= 0 and index < _party_slots.size():
		var slot: Button = _party_slots[index]
		if str(slot.get_meta("slot_kind", "")) == "empty":
			_open_party_dialog()


func _on_party_ready_pressed() -> void:
	if _party_state.is_empty():
		return
	var username := _party_username()
	var ready := false
	var members_value: Variant = _party_state.get("members", [])
	if typeof(members_value) == TYPE_ARRAY:
		for member in members_value:
			if typeof(member) == TYPE_DICTIONARY and str(member.get("username", "")) == username:
				ready = bool(member.get("ready", false))
				break
	_party_request(
		"ready",
		"/api/party/ready",
		HTTPClient.METHOD_POST,
		{"username": username, "ready": not ready}
	)


func _on_party_leave_pressed() -> void:
	_party_request(
		"leave",
		"/api/party/leave",
		HTTPClient.METHOD_POST,
		{"username": _party_username()}
	)


func _on_party_invite_accept() -> void:
	_respond_party(true)


func _on_party_invite_reject() -> void:
	_respond_party(false)


func _respond_party(accept: bool) -> void:
	if _party_invites.is_empty():
		return
	var invite: Variant = _party_invites[0]
	if typeof(invite) != TYPE_DICTIONARY:
		return
	_party_request(
		"respond",
		"/api/party/respond",
		HTTPClient.METHOD_POST,
		{
			"username": _party_username(),
			"inviteId": str(invite.get("id", "")),
			"accept": accept,
			"skin": _displayed_skin_id()
		}
	)
