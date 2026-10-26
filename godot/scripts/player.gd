extends CharacterBody3D


# -- CONSTANTS ---
const GRAVITY: float = 18
const JUMP_VELOCITY: float = 6
const SPEED: float = 4.00
const DEADZONE: float = 0.12
const PICKUP_REQUEST_COOLDOWN_MS: int = 150
## How close the chicken/lootbox must be before a pickup_request is even sent.
## Mirrors the server's PICKUP_RADIUS so every press we send is one the server
## will honour (its old 1.1 radius silently rejected grabs the client signalled
## as available from its 2.0 grab area — the "can't pick the chicken" feel).
## The server still validates distances authority-side.
const ITEM_PICKUP_RADIUS: float = 2.2
const LOCAL_PICKUP_RADIUS: float = 2.5
const LOCAL_PICKUP_THROW_STRENGTH: float = 4.0
const POS_SCALE: float = 100.0
const ROT_SCALE: float = 1000.0
const DEFAULT_MAX_JUMP_HEIGHT: float = (JUMP_VELOCITY * JUMP_VELOCITY) / (2.0 * GRAVITY)
const SLIDE_DURATION: float = 0.8
const SLIDE_SPEED_MULTIPLIER: float = 1.7
const JUMP_BUFFER_TIME: float = 0.12
const COYOTE_TIME: float = 0.10
const DOUBLE_JUMP_MIN_MULTIPLIER: float = 0.3

# --- POWER-UP EFFECTS ---
## SPEED_BURST (RUSH): multiply run speed for a few seconds when used.
const SPEED_BURST_MULT: float = 2.0
const SPEED_BURST_DURATION: float = 8.0
## MEGA_LEAP (LEAP): super jumps at this multiple of the normal jump force for
## MEGA_LEAP_DURATION seconds.
const MEGA_LEAP_MULT: float = 4.0
const MEGA_LEAP_DURATION: float = 8.0
## TWIN: spawns a decoy clone that mirrors the player's movement for
## TWIN_DURATION seconds. Client-side and visual-only, like the other power-ups.
const TWIN_DURATION: float = 8.0
## The decoy stands beside the player at a random distance in this range
## (metres), so it reads as a separate body rather than a copy glued on.
const TWIN_DECOY_DISTANCE_MIN: float = 1.2
const TWIN_DECOY_DISTANCE_MAX: float = 1.8
## How far the decoy may drift forward/back from straight to the side (degrees).
const TWIN_BEARING_JITTER_DEG: float = 30.0
## Fallback scene for the decoy when the local player's own scene path is unknown.
const TWIN_SKIN_SCENE_PATH: String = "res://scenes/skin.tscn"
## Lightweight visual-only node the decoy's character parts are re-parented onto.
const REMOTE_PLAYER_SCRIPT := preload("res://scripts/player/RemotePlayer.gd")
## SMOKE_GRENADE (SMOG): for SMOKE_DURATION seconds, pressing Action drops a
## stationary smoke cloud at the player's feet. Each cloud then lives for its own
## SMOKE_CLOUD_LIFETIME. Purely visual and client-side for now, like the others.
const SMOKE_DURATION: float = 8.0
## Half-width of a dropped cloud in metres (~8x the player's size across).
const SMOKE_CLOUD_RADIUS: float = 7.0
## Minimum seconds between drops while the SMOG window is running.
const SMOKE_DROP_COOLDOWN: float = 0.6
## Hard cap on simultaneous clouds; the oldest is recycled beyond this.
const MAX_SMOKE_CLOUDS: int = 6
## The standalone cloud prefab. Spawned under the scene root (not the player) so
## it stays put, and so multiplayer can replicate it by position + seed.
const SMOKE_CLOUD_SCENE := preload("res://scenes/smoke_cloud.tscn")
## Ground dust kicked up on take-off and landing. Purely visual, spawned under
## the scene root so it stays where it was raised.
const DUST_BURST_SCENE := preload("res://scenes/dust_burst.tscn")
## Hard cap on simultaneous puffs; the oldest is recycled beyond this.
const MAX_DUST_BURSTS: int = 6
## Shared empty result from get_active_power_up(), so the idle case allocates nothing.
const NO_ACTIVE_POWER_UP := {}
## powerup.gdshader: an animated, additive glow drawn around the player for the
## whole power-up usage window. It is a billboarded quad that wraps the character
## (see _ensure_aura_node), so it reads as an aura surrounding the player instead
## of an outline hugging its silhouette.
const POWERUP_SHADER := preload("res://assets/shaders/powerup.gdshader")
## Tint and strength pushed into the aura material; both are also tunable in
## powerup.gdshader itself.
const POWERUP_TINT := Color(1.0, 1.0, 1.0, 1.0)
const POWERUP_AURA_PROGRESS: float = 1.0
## World-space size (metres) of the aura quad. The character is ~1m tall, so this
## leaves a visible band of glow all the way around it.
const POWERUP_AURA_SIZE := Vector2(2.0, 2.0)
## Local height the aura is centred on - the player's mid-body (the capsule sits
## at y 0.2, spanning roughly -0.3..0.7).
const POWERUP_AURA_HEIGHT: float = 0.25

# --- STORM DAMAGE ---
@export var storm_center: Vector2 = Vector2(0, 0)
@export var storm_radius: float = 10.0
@export var storm_damage_per_second: float = 10.0
var _storm_damage_accumulator: float = 0.0
var _storm_check_timer: float = 0.0
const STORM_CHECK_INTERVAL: float = 0.1
var _storm_eye: Node = null

# --- MOMENTUM CONSTANTS ---
const ACCELERATION: float = 25.0  # How fast you reach max speed (Ground)
const FRICTION: float = 22.0      # How fast you stop (Ground)
const AIR_RESISTANCE: float = 6.0 # (Now bypassed for instant air movement)

# --- SQUASH & STRETCH ---
const SQUASH_SCALE: float = 0.5
const STRETCH_SCALE: float = 1.5
const SQUASH_STRETCH_SPEED: float = 12.0

# --- RUN BOUNCE ---
const RUN_BOUNCE_HEIGHT: float = 0.12
const RUN_BOUNCE_SPEED: float = 18.0
const RUN_BOUNCE_SQUASH: float = 0.08
const RUN_BOUNCE_WOBBLE: float = 0.06

const AUTO_ORBIT_DEADZONE: float = 0.25
const AUTO_ORBIT_SHARPNESS_RAD: float = 1.57080  # deg_to_rad(90.0)
const RETREAT_ZOOM_SMOOTHNESS: float = 4.0

const STAMINA_MAX: float = 100.0
## Drain per second at full analog input. Actual drain is this scaled by how far the
## stick or key is pushed, so a light joystick touch costs far less than a full sprint.
const STAMINA_DRAIN_RATE: float = STAMINA_MAX / 7.0
## Drain multiplier applied at the very lightest movement. Without a floor, barely
## nudging the stick would cost almost nothing and let a player creep forever.
const STAMINA_DRAIN_MIN_MULT: float = 0.25
const STAMINA_REGEN_DELAY: float = 1.0
const STAMINA_REGEN_RATE: float = STAMINA_MAX / 8.0
## Standing still regenerates at this multiple of the rate you get while still
## moving, so stopping is always the faster way back to full stamina.
const STAMINA_REGEN_IDLE_MULT: float = 2.0
const STAMINA_HELD_PENALTY: float = 5.0
## Running out of stamina throttles movement instead of stopping it, so the player
## keeps moving under their own input, just very slowly.
const STAMINA_EMPTY_SPEED_MULT: float = 0.4
## The throttle stays on while the player keeps running, and only lifts once they
## stop or refill past this fraction of the bar.
const STAMINA_RECOVERY_FRACTION: float = 0.25
## Jump strength while throttled, as a fraction of the normal jump velocity.
const STAMINA_EMPTY_JUMP_MULT: float = 0.6

# --- HEALTH ---
const MAX_HEALTH: float = 100.0
const HEALTH_REGEN_DELAY: float = 3.0
const HEALTH_REGEN_RATE: float = 15.0
const RESPAWN_DELAY: float = 2.0

const LANDING_BOB_DURATION: float = 0.14
## How fast the landing FOV punch decays back to the base FOV (higher = shorter flash).
const LANDING_FOV_DECAY: float = 14.0

# --- CLIMBING (attachable surfaces: scripts/environment/ClimbableSurface.gd) ---
## Up/down and sideways speed while attached to a surface (m/s).
const CLIMB_SPEED: float = 2.6
## How hard the capsule hugs the face while climbing, so move_and_slide keeps it
## in contact with the surface instead of drifting off it (m/s toward the wall).
const CLIMB_STICK_SPEED: float = 1.2
## Horizontal push away from the face when jumping off a surface (m/s).
const CLIMB_JUMP_AWAY_SPEED: float = 4.5
## Horizontal push toward the face when a climb ends without a jump, so topping
## out on a ledge steps onto it instead of dropping straight back down the face.
const CLIMB_VAULT_SPEED: float = 3.0
## How long the launch vector (jump-off / vault) owns horizontal velocity before
## normal air control starts following input again.
const CLIMB_PUSH_TIME: float = 0.18
## Re-grab delay after letting go, so jumping off does not re-attach instantly
## while the player is still standing inside the trigger volume.
const CLIMB_REATTACH_COOLDOWN: float = 0.5
## Yaw offset (rad) added to the mesh while climbing. The climb clip swings the
## body the opposite way round from the run/idle clips, so the whole model needs
## half a turn to keep the chest and hands on the wall.
const CLIMB_MESH_YAW_OFFSET: float = PI

const ANIM_NAME_TO_ID: Dictionary = {
	"idle": 0,
	"running": 1,
	"runningjump": 2,
	"falling": 3,
	"runningslide": 4,
	"climb": 5
}

# --- CHOG GENESIS GATE ---
## Backend endpoint that verifies the authenticated wallet on Monad mainnet.
const CHOG_OWNERSHIP_PATH: String = "/api/nft/chog-genesis/ownership"
## Retry delay after a failed/unknown ownership check.
const CHOG_OWNERSHIP_RETRY_MS: int = 30000
## sessionStorage key the React /play hand-off writes the Privy access token to.
const CHOG_WEB_TOKEN_KEY: String = "wons_privy_token"
## How often the gate re-evaluates whether a check is needed. Cheap: it only
## performs a request when the TTL lapsed, the account changed or a retry is due.
const CHOG_GATE_POLL_INTERVAL: float = 5.0

# --- INPUT VARIABLES ---
var gamepad_index: int = 0

## Toggle the skin parts that sit outside the regular look (the shirt, the wig
## and the glove) and paint the character's skin in the reveal colour with the
## "chog" input action. See SkinApplier.set_hidden_extras_visible() and
## SkinApplier.set_reveal_tint().

## True while the reveal action is active. The flag makes the handler act on the
## press edges only, so key-repeat events cannot overwrite the "before" state
## the reveal restores.
var _hidden_extras_revealed: bool = false

## Deny-by-default Chog Genesis eligibility. Only a fresh ELIGIBLE verdict from
## the backend, for the current account, inside a CHOG room authorises the input.
var _chog_eligibility := ChogEligibility.new()
var _chog_check_in_flight: bool = false
## Identity the in-flight request was sent for (see _chog_identity_key()).
var _chog_check_identity: String = ""
var _chog_next_check_at_ms: int = 0
var _chog_gate_poll: float = 0.0
var _dev_cheat_unlocked: bool = false
var _dev_cheat_buffer: String = ""
var _dev_cheat_last_time: int = 0


## HOOK punch: how long the punch plays when the HOOK power-up is used. Read from
## the hook animation's own length when available; this is the fallback.
const HOOK_FALLBACK_DURATION: float = 2.4
## HOOK punch: the punch animation plays at this speed multiplier. Doubled from
## the original 3x to 6x so the full swing reads as a quicker jab.
const PUNCH_SPEED_MULT: float = 6.0
## HOOK punch: for HOOK_DURATION seconds after use, the Action button fires the
## punch (repeatable — each swing finishes before the next starts), with an
## immediate first punch on use.
const HOOK_DURATION: float = 8.0
## Health fraction (of MAX_HEALTH) at or below which the near-death fall animation
## plays once, right before the health bar empties.
const HEALTH_CRITICAL_FRACTION: float = 0.05
## Fallback length of the near-death fall animation, if the clip cannot be read.
const CRITICAL_FALL_FALLBACK: float = 2.5

# --- PICKUP VARIABLES ---
var held_object: RigidBody3D = null
@export var hold_distance: float = 0.25
@export var hold_height: float = 1.5
var last_pickup_request_ms: int = 0
var held_local_pickup: RigidBody3D = null
## The power-up granted by the currently carried pickup (LocalPickup.PowerUpMode).
var held_power_up_mode: int = LocalPickup.PowerUpMode.NONE
## Timed power-up that is currently running (LocalPickup.PowerUpMode), or NONE.
## Only one runs at a time; using another replaces it.
var _active_power_up_mode: int = LocalPickup.PowerUpMode.NONE
## Seconds left on the running timed power-up.
var _active_power_up_remaining: float = 0.0
## Total duration of the running timed power-up, for the HUD's progress ring.
var _active_power_up_duration: float = 0.0
## Shared powerup.gdshader material, built once (in _ready, with a lazy fallback)
## and handed to the aura quad.
var _powerup_material: ShaderMaterial = null
## The billboarded quad the aura is drawn on. Built once, then shown/hidden and
## re-aimed at the camera while an effect runs, so a later power-up never
## reconstructs anything.
var _powerup_aura: MeshInstance3D = null
## True while the aura quad is showing.
var _powerup_visual_active: bool = false
## Camera the aura billboards towards, cached so the per-frame aim never has to
## ask the viewport for it again.
var _powerup_camera: Camera3D = null
## Last (quad position, camera position) the aura was aimed with. Standing still
## changes neither, so those frames skip the billboard write altogether.
var _powerup_aim_from := Vector3.ZERO
var _powerup_aim_at := Vector3.ZERO
var _powerup_aim_valid: bool = false
## One-shot per process: the aura shader has had a real drawn frame to compile.
static var _powerup_prewarmed: bool = false
## Set when MEGA_LEAP (LEAP) is used; consumed in the next physics step to launch.
var _mega_leap_pending: bool = false
## The TWIN decoy clone while the effect is running, or null.
var _twin_decoy: Node3D = null
## The decoy's Skeleton3D, mirrored directly (the root must not carry the
## skeleton's scale again, or the clone shrinks to a fraction of the size).
var _twin_decoy_mesh: Node3D = null
## The decoy's random per-spawn world-space offset, frozen at spawn so the clone
## keeps its distance and never swings around the player when they turn. Its
## rotation still tracks the player each step, spinning about its own axis.
var _twin_world_offset: Vector3 = Vector3.ZERO
## Seconds until the next SMOG cloud may be dropped.
var _smoke_drop_cooldown: float = 0.0
## Live smog clouds this player spawned, for the concurrent-cloud cap.
var _smoke_clouds: Array = []
## Set once the SMOG effect's sprite + shader have been warmed up, so respawns and
## later matches in the same process don't pay to build them again.
static var _smoke_prewarmed: bool = false
## Live dust puffs this player spawned, for the concurrent-burst cap.
var _dust_bursts: Array = []
## Same one-shot warm-up rule as the SMOG cloud, for the jump/landing dust.
static var _dust_prewarmed: bool = false
## Cached once; avoids a tree search every pickup/drop.
var _cached_buttons_hud: Node = null
## HOOK punch: while true, the run/idle animation states stay suppressed and the
## punch (hook) animation plays once to completion.
var _is_punching: bool = false
## Seconds left on the punch; the run/idle states resume when it hits zero.
var _punch_timer: float = 0.0
## Near-death fall: while true, the run/idle animation states stay suppressed and
## the "fall" animation plays once after health drops to the critical threshold.
var _is_dying_fall: bool = false
## Seconds left on the near-death fall; the run/idle states resume at zero.
var _critical_fall_timer: float = 0.0

# --- CAMERA & ZOOM SETTINGS ---
@export var camera_distance: float = 2.0
@export var camera_screen_offset: Vector2 = Vector2(0.0,0.25) # x: -1 (left) to 1 (right), y: -1 (bottom) to 1 (top)
@export var camera_smoothness: float = 18.0
@export var follow_sharpness: float = 24.0 # how hard the camera locks on (steady-state lag = speed / value)
@export var follow_sharpness_retreat: float = 34.0 # tighter lock while strafing/backpedaling
@export var auto_orbit_speed: float = 1.1
@export var auto_orbit_threshold_deg: float = 40.0 # deadzone before the camera chases the move direction
@export var min_pitch: float = deg_to_rad(0.0)
@export var max_pitch: float = deg_to_rad(60.0)
@export var min_zoom: float = 1.8
@export var max_zoom: float = 2.2
@export var move_zoom_out: float = 0.5 # subtle pull-back while running left/right/back (costly: shows more geometry)
@export var max_zoom_ceiling: float = 6.5 # absolute hard cap for the move_zoom_out boost
@export var altitude_zoom_factor: float = 0.0
@export var bus_zoom: float = 3.0
@export var bus_camera_look_target: Vector2 = Vector2(0.0, 0.0) # xz point the camera self-adjusts toward while riding the bus
@export var bus_camera_recenter_speed: float = 1.4 # higher = pulls back to the look target faster, 0 = disabled
@export var bus_camera_height_offset: float = 0.5 # lifts the camera while riding the bus
@export_range(0.0, 40.0, 0.5) var dive_ramp_low: float = 15.0 # below this altitude (y) the dive camera blend is fully off
@export_range(0.0, 200.0, 0.5) var dive_ramp_high: float = 55.0 # at/above this altitude (y) the dive camera blend is full while falling
@export_range(0.5, 20.0, 0.5) var dive_ramp_speed: float = 5.0 # how quickly the dive blend eases to its target (higher = snappier)
@export_range(0.0, 20.0, 0.5) var dive_fov_boost_max: float = 8.0 # extra FOV while diving at full speed
@export_range(5.0, 100.0, 1.0) var dive_fov_ref_speed: float = 35.0 # fall speed (m/s) that reaches the full dive FOV boost
@export_range(0.0, 15.0, 0.5) var landing_fov_kick_max: float = 6.0 # FOV flash on a hard landing
@export var fov: float = 70.0
@export var touch_orbit_sensitivity: float = 0.032
@export var joystick_orbit_sensitivity: float = 0.003
@export var joystick_orbit_clamp: float = 40.0
@export var joystick_orbit_invert_x: bool = false
@export var joystick_orbit_invert_y: bool = false
@export var touch_edge_ignore_margin: float = 32.0 # Ignore touches that START within this many px of a screen edge
@export var low_pitch_ease_speed: float = 2.5 # While moving below the movement pitch mark, ease pitch up to it (0 = off)
@export var movement_pitch_raise_fraction: float = 0.25 # While moving, raise the orbital pitch floor to min_pitch + this fraction of the pitch range (1/4: a -0.4..1 range raises the floor from -0.4 to -0.05, almost level, so the camera cannot dip under the map while running)
@export var swipe_down_threshold: float = 20.0
@export var swipe_up_threshold: float = 70.0
@export var swipe_x_tolerance: float = 80.0
@export var swipe_max_duration_ms: int = 450

# --- DEMO AGENT SETTINGS ---
@export var demo_agent: bool = false
@export var demo_move_speed: float = 3.2
@export var demo_orbit_radius: float = 3.5
@export var demo_orbit_speed: float = 1.1
@export var demo_jump_min_interval: float = 1.5
@export var demo_jump_max_interval: float = 4.5
@export var demo_wobble_amount: float = 0.6

# --- NODE REFERENCES ---
@onready var camera: Camera3D = _resolve_camera_node()

# [CHANGED] Replaced RayCast3D with Area3D
@onready var pickup_area: Area3D = $Area3D

@onready var name_label: Label3D = $Label3D
@onready var anim_player: AnimationPlayer = $animator
@onready var anim_tree: AnimationTree = $AnimationTree
@onready var mesh: Skeleton3D = $Skeleton3D

# --- STATE VARIABLES ---
var root: Node = null
var is_local: bool = false
var velocity_y: float = 0.0
var cam_rot_x: float = deg_to_rad(30)
var cam_rot_y: float = 0.0
var current_animation: String = "idle"
var anim_state_machine: AnimationNodeStateMachinePlayback = null
var camera_distance_current: float = 0.0
var camera_distance_bias: float = 0.0
var camera_is_airborne: bool = false
var camera_is_moving: bool = false
var camera_retreat_axis: float = 0.0 # 1.0 when running left/right/back, 0.0 when running forward
var _camera_retreat_smooth: float = 0.0
var _camera_retreat_velocity: float = 0.0
var _zoom_cap_override: float = -1.0 # < 0 means "use the authored max_zoom"
var _effective_camera_distance: float = 0.0
# Temporary movement pitch auto-raise. While moving, the pitch floor is eased up
# to min_pitch + movement_pitch_raise_fraction of the pitch range so the camera
# near plane never cuts the floor. The raise is temporary: once the player stops
# moving, the pitch eases back to the angle it had before the raise kicked in.
var _movement_pitch_ease_active: bool = false
var _pitch_before_movement_ease: float = -1.0
@export var max_jump_height: float = DEFAULT_MAX_JUMP_HEIGHT
var _last_world_y: float = 0.0
var _airborne_start_y: float = 0.0
var _was_on_floor: bool = true
var _slide_timer: float = 0.0
var _is_sliding: bool = false
var _slide_direction: Vector3 = Vector3.ZERO
var _air_horizontal_velocity: Vector3 = Vector3.ZERO
var _jump_requested: bool = false
var _last_recovery_ms: int = 0
var _jump_buffer_timer: float = 0.0
var _coyote_timer: float = 0.0
var _double_jump_available: bool = false
var _double_jump_used: bool = false
var _double_jump_air_time: float = 0.0

# --- CLIMB STATE (set by ClimbableSurface.gd, see the climb API near the bottom) ---
var _is_climbing: bool = false
var _climb_surface: Node3D = null
## Outward normal of the face being climbed: horizontal, pointing back at the player.
var _climb_normal: Vector3 = Vector3.ZERO
## Counts down while a jump-off / vault vector is in charge of horizontal velocity.
var _climb_push_timer: float = 0.0
var _climb_reattach_cooldown: float = 0.0

var stamina: float = STAMINA_MAX
var _stamina_regen_timer: float = 0.0
var _stamina_held_empty: bool = false
var _stamina_empty_timer: float = 0.0
## Latched once stamina bottoms out. Keeps the throttle on while the player keeps
## running, so creeping does not silently restore full speed.
var _stamina_throttled: bool = false

# --- HEALTH STATE ---
var health: float = MAX_HEALTH
var _health_regen_timer: float = 0.0
var _is_dead: bool = false
var _respawn_timer: float = 0.0
var _cached_health_bar: Node = null  # Cached once; avoid per-hit tree scans

var _prev_joy_a_pressed: bool = false
var _ground_jump_count: int = 0

# Performance optimization variables
var _camera_update_skip_frames: int = 0
var _camera_ray_exclude: Array[RID] = []
var _sin_cam_y: float = 0.0
var _cos_cam_y: float = 0.0
var _sin_cam_x: float = 0.0
var _cos_cam_x: float = 0.0
var _cached_viewport_size: Vector2 = Vector2.ZERO
var _slow_update_timer: float = 0.0
const SLOW_UPDATE_INTERVAL: float = 0.1 # 10 FPS for non-critical updates
var _landing_bob_timer: float = 0.0
var _landing_bob_strength: float = 0.0
## 0 on the ground, ramps to 1 while airborne and falling from altitude. Drives
## the dive camera blend (zoom, stiffness, FOV) so jumping off the bus eases in
## and out instead of switching at a hard height.
var _dive_level: float = 0.0
## Temporary FOV punch after a hard landing; decays back to zero over ~0.4s.
var _landing_fov_kick: float = 0.0
var _spawn_flash_done: bool = false
var _squash_stretch_y: float = 1.0
var _squash_stretch_velocity: float = 0.0
var _squash_stretch_target: float = 1.0
var _run_bounce_time: float = 0.0
var _was_airborne: bool = false
var _jump_peak_reached: bool = false
var _base_scale: Vector3
var _camera_distance_velocity: float = 0.0
var _camera_position_velocity: Vector3 = Vector3.ZERO
var _camera_fov_velocity: float = 0.0
var _mesh_yaw_velocity: float = 0.0
var _camera_collision_distance: float = 0.0
var _camera_collision_hold_timer: float = 0.0
var _camera_base_target_prev: Vector3 = Vector3.ZERO
var _camera_base_target_curr: Vector3 = Vector3.ZERO
var _camera_follow_target: Vector3 = Vector3.ZERO
var _camera_follow_velocity: Vector3 = Vector3.ZERO
var _camera_look_target: Vector3 = Vector3.ZERO
var _camera_look_target_velocity: Vector3 = Vector3.ZERO
var _demo_home_center: Vector3 = Vector3.ZERO
var _demo_orbit_angle: float = 0.0
var _demo_orbit_direction: float = 1.0
var _demo_jump_timer: float = 0.0
var _demo_wobble_phase: float = 0.0
var _demo_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _demo_last_safe_position: Vector3 = Vector3.ZERO
var _demo_offground_timer: float = 0.0

const DEMO_RECOVERY_FALL_DISTANCE: float = 8.0
const DEMO_RECOVERY_OFFGROUND_TIME: float = 1.25
const DEMO_RECOVERY_RAISE_OFFSET: float = 1.0

const CAMERA_COLLISION_MARGIN: float = 0.18
const CAMERA_COLLISION_HOLD_TIME: float = 0.08
const CAMERA_COLLISION_RECOVERY_SPEED: float = 10.0
const SPRING_SETTLE_EPSILON: float = 0.0005
const SPRING_SETTLE_VELOCITY_EPSILON: float = 0.0005

var touch_joystick: Node = null
var network_tick_timer: float = 0.0
var network_heartbeat_timer: float = 0.0
const NETWORK_TICK_ACTIVE: float = 0.05 # 20 Hz while moving (matches server BROADCAST_RATE)
const NETWORK_TICK_IDLE: float = 0.33
const NETWORK_HEARTBEAT: float = 1.0
var player_id: String = "" :
	set(new_id):
		player_id = new_id
		_refresh_name_label()

var display_name: String = "" :
	set(new_name):
		display_name = new_name.strip_edges()
		_refresh_name_label()

var active_touches: int = 0
var touch_orbit_pending: Vector2 = Vector2.ZERO
var joystick_orbit_pending: Vector2 = Vector2.ZERO
var _touch_slide_start_pos: Vector2 = Vector2.ZERO
var _touch_slide_start_time_ms: int = 0
var _touch_slide_start_cam_rot_x: float = 0.0
var _edge_ignored_touch_indices: Dictionary = {} # Finger indices whose press landed in the edge dead zone
var _touch_slide_start_cam_rot_y: float = 0.0
var _slide_requested: bool = false
var _slide_camera_restore_active: bool = false
var _camera_ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _camera_ray_layer_set: bool = false
var _cached_shader_player_pos: Vector3 = Vector3.INF
var _cached_chicken_node: RigidBody3D = null
var _cached_lootbox_node: RigidBody3D = null
## How long to wait before re-scanning the "bus" group after a miss (see
## _apply_bus_riding): one immediate lookup, then at most once a second.
const BUS_LOOKUP_RETRY_MSEC: int = 1000

var _bus_node: Node3D = null
var _bus_last_pos: Vector3 = Vector3.ZERO
var _bus_lookup_retry_at_msec: int = 0
var _is_riding_bus: bool = false

func _resolve_camera_node() -> Camera3D:
	var parent_node: Node = get_parent()
	while parent_node != null:
		var direct_camera := parent_node.get_node_or_null("PlayerManager/Camera3D")
		if direct_camera is Camera3D:
			return direct_camera
		direct_camera = parent_node.get_node_or_null("Camera3D")
		if direct_camera is Camera3D:
			return direct_camera
		parent_node = parent_node.get_parent()

	var scene_root := get_tree().root if get_tree() != null else null
	if scene_root != null:
		var cameras := scene_root.find_children("*", "Camera3D", true, false)
		for candidate in cameras:
			if candidate is Camera3D:
				return candidate
	return null

func _ready() -> void:
	camera_distance = clamp(camera_distance, min_zoom, _zoom_cap_base())
	camera_distance_current = camera_distance
	cam_rot_x = min_pitch
	cam_rot_y = deg_to_rad(90.0)
	_last_world_y = global_position.y
	_airborne_start_y = global_position.y
	_was_on_floor = is_on_floor()
	_slide_timer = 0.0
	_is_sliding = false
	
	# Initialize health
	health = MAX_HEALTH
	_health_regen_timer = 0.0
	_is_dead = false
	_respawn_timer = 0.0
	_cached_health_bar = _find_health_bar()  # One-time lookup, avoids per-hit tree scans
	
	# Auto-detect StormEye for damage zone
	_storm_eye = get_tree().get_first_node_in_group("storm_eye")
	if _storm_eye:
		if _storm_eye.has_method("get_storm_center"):
			storm_center = _storm_eye.get_storm_center()
		elif _storm_eye.has_property("global_position"):
			storm_center = Vector2(_storm_eye.global_position.x, _storm_eye.global_position.z)
		if _storm_eye.has_method("get_storm_radius"):
			storm_radius = _storm_eye.get_storm_radius()
		elif _storm_eye.has_property("cylinder_radius"):
			storm_radius = _storm_eye.cylinder_radius
		if _storm_eye.has_method("get_damage_per_second"):
			storm_damage_per_second = _storm_eye.get_damage_per_second()
		elif _storm_eye.has_property("damage_per_second"):
			storm_damage_per_second = _storm_eye.damage_per_second
	else:
		print("Player: No StormEye found in group 'storm_eye', using defaults")

	# SMOG warm-up: build the smoke cloud's sprite + shader now (off the first
	# drop). Only in matches (the lobby/preview has no storm), and only once per
	# process, so a respawn or a later match does not repeat it.
	if _storm_eye != null and not _smoke_prewarmed:
		_prewarm_smoke_cloud.call_deferred()

	_cached_viewport_size = get_viewport().get_visible_rect().size
	_setup_anim_tree()
	_play_anim("idle")
	_refresh_name_label()
	_refresh_touch_joystick()
	_connect_joystick_signals()
	_update_global_player_shader_pos(true)
	# Power-up aura warm-up: build the quad + material and give the shader one
	# real drawn frame now, so the first pickup use neither allocates nor stutters
	# on a shader compile. Same one-shot-per-process rule as the smoke cloud.
	if _storm_eye != null and not _powerup_prewarmed:
		_prewarm_powerup_aura.call_deferred()
	# Death dissolve warm-up: same idea, so the first death does not stutter on a
	# shader compile. Death can happen in any scene, so this one is unconditional.
	_prewarm_death_dissolve.call_deferred()
	# Jump/landing dust: same one-shot rule. The first jump can happen seconds
	# after spawn, so this one is unconditional too (unlike the SMOG cloud, which
	# only exists in a match).
	_prewarm_jump_dust.call_deferred()

	# The reveal key may already be down when this player spawns (the scene
	# changed while it was held), so the extras follow the key itself and not
	# only the key events this node happened to see.
	call_deferred("_reveal_if_key_held")
	# `root`/`is_local` are assigned after add_child(), so the Chog gate starts
	# on the next idle frame, when the room and the local flag are known.
	call_deferred("_init_chog_gate")

func _setup_anim_tree() -> void:
	var state_machine := AnimationNodeStateMachine.new()
	var state_names := ["idle", "running", "runningjump", "falling", "runningslide", "hook", "fall", "climb"]
	for state_name in state_names:
		var node := AnimationNodeAnimation.new()
		node.animation = state_name
		if state_name == "hook":
			# Play a faster copy of the punch (PUNCH_SPEED_MULT) so the one-shot
			# reads as a quick jab.
			node.animation = _ensure_fast_hook_animation(PUNCH_SPEED_MULT)
		state_machine.add_node(state_name, node)
	for from_name in state_names:
		for to_name in state_names:
			if from_name != to_name:
				var trans := AnimationNodeStateMachineTransition.new()
				trans.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_SYNC
				trans.xfade_time = 0.06 if to_name == "idle" else 0.12  # idle settles faster; 0.12 s held the run cycle past the stop
				state_machine.add_transition(from_name, to_name, trans)
	anim_tree.tree_root = state_machine
	anim_tree.active = true
	anim_state_machine = anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	_camera_collision_distance = camera_distance
	_camera_base_target_prev = global_transform.origin + Vector3(0, 1.5, 0)
	_camera_base_target_curr = _camera_base_target_prev
	_camera_follow_target = _camera_base_target_curr
	_camera_look_target = _camera_follow_target
	_demo_home_center = global_position
	_demo_last_safe_position = global_position
	_demo_wobble_phase = randf_range(0.0, TAU)
	_base_scale = mesh.scale

	if not pickup_area:
		print("ERROR: $Area3D node not found! Please add an Area3D with a CollisionShape to the player.")

func configure_demo_agent(
	home_center: Vector3,
	orbit_radius: float = 3.5,
	orbit_speed: float = 1.1,
	orbit_phase: float = 0.0,
	orbit_direction: float = 1.0,
	jump_min_interval: float = 1.5,
	jump_max_interval: float = 4.5,
	wobble_amount: float = 0.6
) -> void:
	demo_agent = true
	_demo_home_center = home_center
	demo_orbit_radius = maxf(0.25, orbit_radius)
	demo_orbit_speed = maxf(0.05, orbit_speed)
	_demo_orbit_angle = orbit_phase
	_demo_orbit_direction = -1.0 if orbit_direction < 0.0 else 1.0
	demo_jump_min_interval = maxf(0.2, jump_min_interval)
	demo_jump_max_interval = maxf(demo_jump_min_interval, jump_max_interval)
	demo_wobble_amount = maxf(0.0, wobble_amount)
	_demo_rng.randomize()
	_demo_jump_timer = _demo_rng.randf_range(demo_jump_min_interval, demo_jump_max_interval)
	_demo_wobble_phase = _demo_rng.randf_range(0.0, TAU)
	_demo_last_safe_position = home_center + Vector3(0, DEMO_RECOVERY_RAISE_OFFSET, 0)
	_demo_offground_timer = 0.0
	
	# Initialize health for demo agent
	health = MAX_HEALTH
	_health_regen_timer = 0.0
	_is_dead = false
	_respawn_timer = 0.0

func _process(delta: float) -> void:
	if not is_local:
		return
	_update_camera_visual(delta)
	# Re-evaluate the CHOG gate periodically. `_refresh_chog_eligibility` is a
	# no-op unless a check is actually due, so this never hits the network per
	# frame.
	_chog_gate_poll -= delta
	if _chog_gate_poll <= 0.0:
		_chog_gate_poll = CHOG_GATE_POLL_INTERVAL
		_refresh_chog_eligibility()

func _refresh_name_label() -> void:
	if not name_label:
		return
	var resolved_name = display_name
	if resolved_name == "":
		resolved_name = player_id.substr(0, 8)
	name_label.text = resolved_name

func request_jump() -> void:
	if not _is_movement_allowed():
		return
	if _is_climbing:
		# Jumping while attached means "let go and push off the face". Flagged here
		# and consumed on the next physics tick, where the launch vector, the face
		# detach and the animation change all land together.
		_jump_requested = true
		return
	_jump_buffer_timer = JUMP_BUFFER_TIME
	if is_on_floor():
		velocity_y = _current_jump_velocity()
		_jump_requested = false
		if not _double_jump_available:
			_ground_jump_count += 1
			if _ground_jump_count >= 2:
				_double_jump_available = true
				_ground_jump_count = 0
	else:
		_jump_requested = true

func request_slide() -> void:
	_slide_requested = true

func request_pickup() -> void:
	if not _is_movement_allowed():
		return
	call_deferred("_perform_pickup_request")

func _perform_pickup_request() -> void:
	if not _is_movement_allowed():
		return
	# While the LEAP power-up is running, the Action (GRAB) button is the mega
	# jump button — but only while grounded: mid-air presses are ignored so LEAP
	# can't be chained into an infinite double-jump. The normal jump is unaffected.
	if _is_mega_leap_active():
		_trigger_mega_leap()
		return
	# While the SMOG power-up is running, the Action button drops smoke clouds.
	if _is_smoke_active():
		_try_drop_smoke_cloud()
		return
	# While the HOOK power-up is running, the Action button fires a punch.
	if _is_hook_active():
		_start_punch()
		return
	# A held power-up counts as "carried" even without a pickup instance (the
	# reveal action can grant one directly), so the Action button uses it too.
	if _is_local_holding_pickup() or held_power_up_mode != LocalPickup.PowerUpMode.NONE:
		# A held power-up is USED, not dropped: it vanishes and recycles to a
		# random far-away spot on the map (effects are not implemented yet).
		# Objective items (chicken / lootbox) and plain NONE-mode pickups are
		# dropped instead.
		if _is_objective_item_mode(held_power_up_mode):
			_drop_local_pickup()
		elif held_power_up_mode != LocalPickup.PowerUpMode.NONE:
			_use_held_power_up()
		else:
			_drop_local_pickup()
		return
	if _is_local_holding_chicken() or _is_local_holding_lootbox():
		_drop_object()
		return
	if _try_pickup_local():
		return
	_try_pickup()

func _input(event: InputEvent) -> void:
	if not is_local:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var key := OS.get_keycode_string(event.keycode).to_upper()
		if key.length() == 1:
			var now := Time.get_ticks_msec()
			if _dev_cheat_last_time == 0 or now - _dev_cheat_last_time > 1500:
				_dev_cheat_buffer = ""
			_dev_cheat_buffer += key
			if _dev_cheat_buffer.length() > 7:
				_dev_cheat_buffer = _dev_cheat_buffer.substr(_dev_cheat_buffer.length() - 7)
			_dev_cheat_last_time = now
			if _dev_cheat_buffer == "CHOGDEV":
				_dev_cheat_buffer = ""
				_dev_cheat_unlocked = true

	# --- CHOG REVEAL (Chog Genesis holders in a CHOG room only) ---

	# The same `chog` action drives the hidden extras and the random power-up
	# grant. Both are gated on a mainnet ownership verdict from the backend; a
	# press outside a CHOG room, before a verdict, or by a non-holder does
	# nothing (deny by default).
	if event.is_action_pressed("chog"):
		if _hidden_extras_revealed:
			# Turning it off is always allowed; otherwise an expiring verdict
			# could leave the extras stuck visible.
			_set_hidden_extras_revealed(false)
		elif _chog_can_activate():
			_set_hidden_extras_revealed(true)
			_maybe_grant_random_powerup_on_reveal()
		else:
			_refresh_chog_eligibility()

	if event is InputEventScreenTouch:
		if event.pressed:
			# Dead zone along the screen edges so system gestures / accidental touches
			# near the frame never hijack the slide detection.
			if _is_touch_in_edge_margin(event.position):
				_edge_ignored_touch_indices[event.index] = true
				return
			active_touches += 1
			_touch_slide_start_pos = event.position
			_touch_slide_start_time_ms = Time.get_ticks_msec()
			_touch_slide_start_cam_rot_x = cam_rot_x
			_touch_slide_start_cam_rot_y = cam_rot_y
		else:
			if _edge_ignored_touch_indices.erase(event.index):
				return
			var swipe_vector: Vector2 = event.position - _touch_slide_start_pos
			var swipe_duration: int = Time.get_ticks_msec() - _touch_slide_start_time_ms
			if swipe_vector.y > swipe_down_threshold and absf(swipe_vector.x) < swipe_x_tolerance and swipe_duration <= swipe_max_duration_ms:
				_slide_requested = true
			active_touches = max(0, active_touches - 1)

	# --- 1. MOUSE CAMERA CONTROLS ---
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if active_touches > 0 or DisplayServer.is_touchscreen_available():
			return
		cam_rot_y -= event.relative.x * 0.005
		cam_rot_x = clamp(cam_rot_x + event.relative.y * 0.005, _effective_min_pitch(), max_pitch)

	# Mouse Wheel Zoom
	if event is InputEventMouseButton:
		var zoom_range: float = _zoom_cap_base() - min_zoom
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera_distance_bias = clamp(camera_distance_bias - 0.5, -zoom_range, zoom_range)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera_distance_bias = clamp(camera_distance_bias + 0.5, -zoom_range, zoom_range)

	# --- 2. PICKUP CONTROLS ---
	if _is_movement_allowed() and event.is_action_pressed("pickup"):
		_perform_pickup_request()

# Shows or hides again the skin parts that sit outside the regular look (the
# shirt, the wig and the glove) and paints the character's skin in the reveal
# colour while the key is held. SkinApplier remembers the state each part had
# before the reveal and the skin the player wore, so switching it back off
# restores that state instead of a hard-coded one. The flag guards the edges:
# the key-repeat events that arrive while the key is held must not re-save the
# "before" state, or the release would restore the revealed state instead of
# the original one.
func _set_hidden_extras_revealed(revealed: bool) -> void:
	if revealed == _hidden_extras_revealed:
		return
	_hidden_extras_revealed = revealed
	SkinApplier.set_hidden_extras_visible(self, revealed)
	SkinApplier.set_reveal_tint(self, revealed)

# Reveals the extras and the reveal colour when the reveal key is already held
# as this player spawns. Deferred from _ready, because the spawn code only
# marks the local player as local right after it enters the tree - so the flag
# is only known a frame later, and the remote players must not be touched.
func _reveal_if_key_held() -> void:
	if not is_local:
		return
	if Input.is_action_pressed("chog") and _chog_can_activate():
		_set_hidden_extras_revealed(true)

# Invisible dead zone along all four screen edges. Any touch that STARTS here is
# ignored entirely (no orbit, no slide, no joystick) because OS/browser gestures
# live at the frame - home indicator, notch, notification shade, swipe-backs.
func _is_touch_in_edge_margin(touch_pos: Vector2) -> bool:
	if touch_edge_ignore_margin <= 0.0:
		return false
	var vp := get_viewport().get_visible_rect().size
	return touch_pos.x < touch_edge_ignore_margin \
		or touch_pos.y < touch_edge_ignore_margin \
		or touch_pos.x > vp.x - touch_edge_ignore_margin \
		or touch_pos.y > vp.y - touch_edge_ignore_margin

func _physics_process(delta: float) -> void:
	if demo_agent and not is_local:
		_update_demo_agent(delta)
		return
	if not is_local:
		return

	_check_map_recovery()
	_update_camera_zoom(delta)
	_update_camera_collision_logic(delta)
	_landing_bob_timer = maxf(0.0, _landing_bob_timer - delta)
	# Climb timers tick here, before the climb branch can take over the frame, so
	# the re-grab cooldown and the launch window always run down.
	_climb_reattach_cooldown = maxf(0.0, _climb_reattach_cooldown - delta)
	_climb_push_timer = maxf(0.0, _climb_push_timer - delta)
	if _active_power_up_remaining > 0.0:
		_active_power_up_remaining = maxf(0.0, _active_power_up_remaining - delta)
		if _active_power_up_remaining <= 0.0:
			# Timed effect ran out.
			if _active_power_up_mode == LocalPickup.PowerUpMode.TWIN:
				_despawn_twin_decoy()
			_active_power_up_mode = LocalPickup.PowerUpMode.NONE
			_active_power_up_duration = 0.0
			# Put the original materials back now that usage time is over.
			apply_powerup_visual(false)
			if is_local and _hidden_extras_revealed:
				_set_hidden_extras_revealed(false)
		else:
			# Keep the aura aimed at the camera while the effect runs. Cheap:
			# one visibility check and one look_at on the aura quad.
			_maintain_powerup_visual()

	if _smoke_drop_cooldown > 0.0:
		_smoke_drop_cooldown = maxf(0.0, _smoke_drop_cooldown - delta)

	if _is_punching:
		_punch_timer = maxf(0.0, _punch_timer - delta)
		if _punch_timer <= 0.0:
			_is_punching = false

	if _is_dying_fall:
		_critical_fall_timer = maxf(0.0, _critical_fall_timer - delta)
		if _critical_fall_timer <= 0.0:
			_is_dying_fall = false

	var input_dir := Vector2.ZERO
	var movement_allowed := _is_movement_allowed()
	var is_falling_anim_playing := current_animation == "falling"
	var was_on_floor_before_move := is_on_floor()
	var vertical_speed_before_move := velocity_y

	if movement_allowed:
		input_dir.y += Input.get_action_strength("move_forward")
		input_dir.y -= Input.get_action_strength("move_back")
		input_dir.x -= Input.get_action_strength("move_left")
		input_dir.x += Input.get_action_strength("move_right")

	var lx := Input.get_joy_axis(gamepad_index, JOY_AXIS_LEFT_X)
	var ly := Input.get_joy_axis(gamepad_index, JOY_AXIS_LEFT_Y)

	if movement_allowed:
		if abs(lx) > DEADZONE: input_dir.x += lx
		if abs(ly) > DEADZONE: input_dir.y -= ly
	var input_strength := minf(input_dir.length(), 1.0)
	if input_strength > 0.0:
		input_dir = input_dir.normalized() * input_strength
	
	# Anything that has to end the climb (death, a blocked match, the punch /
	# near-death fall lock) is resolved before the climb branch claims the frame.
	if _is_climbing and (_is_dead or _is_action_locked() or _is_riding_bus or not _is_movement_allowed()):
		end_climb(_climb_surface, false)

	if _is_climbing:
		_physics_process_climb(delta, input_dir)
		return

	if movement_allowed and not _is_riding_bus and input_dir.length_squared() > 0.05 and touch_orbit_pending == Vector2.ZERO and joystick_orbit_pending == Vector2.ZERO:
		# The orbit demand is a *relative* turn away from the current camera heading, not an
		# absolute world yaw. Using an absolute target made the camera chase a heading that
		# ignored where it already was, so holding forward from any starting angle swung the
		# camera to a fixed world direction instead of leaving it alone.
		# Backward input is clamped away: it would flip the sign of the turn every frame and
		# vibrate the camera, so backpedaling deliberately leaves the view where it is.
		var orbit_turn := atan2(input_dir.x, maxf(input_dir.y, 0.0))
		if absf(orbit_turn) > deg_to_rad(auto_orbit_threshold_deg):
			var turn_sharpness := clampf(absf(orbit_turn) / AUTO_ORBIT_SHARPNESS_RAD, 0.0, 1.0)
			# Positive input_dir.x means "strafe right", which should rotate the view to the
			# right, so the turn is negated to match the other cam_rot_y writers above.
			cam_rot_y -= signf(orbit_turn) * turn_sharpness * auto_orbit_speed * delta

	_apply_touch_orbit()

	if not is_on_floor():
		_double_jump_air_time += delta

	var jump_requested_now := false
	if not is_on_floor():
		var gravity_scale: float = 0.5 if is_falling_anim_playing else 1.0
		velocity_y -= GRAVITY * gravity_scale * delta
	else:
		jump_requested_now = _jump_requested or Input.is_action_just_pressed("jump") or Input.is_joy_button_pressed(gamepad_index, JOY_BUTTON_A)
		_jump_requested = false
		if movement_allowed and jump_requested_now:
			velocity_y = _current_jump_velocity()
			if not _double_jump_available:
				_ground_jump_count += 1
				if _ground_jump_count >= 2:
					_double_jump_available = true
					_ground_jump_count = 0
		else:
			velocity_y = 0

	var move_basis := Basis(Vector3.UP, cam_rot_y)
	var forward = -move_basis.z
	var right = move_basis.x
	forward.y = 0
	right.y = 0
	forward = forward.normalized()
	right = right.normalized()

	var move_direction = forward * input_dir.y + right * input_dir.x
	if move_direction.length_squared() > 1.0:
		move_direction = move_direction.normalized()

	var slide_requested_now := Input.is_action_just_pressed("slide") or _slide_requested
	if slide_requested_now:
		var slide_from_touch: bool = _slide_requested
		if movement_allowed and is_on_floor() and move_direction.length_squared() > 0.01 and not _is_sliding and not _is_action_locked():
			_slide_requested = false
			_start_slide(move_direction, slide_from_touch)
		else:
			_slide_requested = false

	if is_on_floor():
		_coyote_timer = COYOTE_TIME
	else:
		_coyote_timer = maxf(0.0, _coyote_timer - delta)

	var jump_just_pressed := Input.is_action_just_pressed("jump")
	var jump_joy_held := Input.is_joy_button_pressed(gamepad_index, JOY_BUTTON_A)
	var jump_joy_just_pressed := jump_joy_held and not _prev_joy_a_pressed
	_prev_joy_a_pressed = jump_joy_held
	var jump_any_held_or_pressed := jump_just_pressed or jump_joy_held
	if jump_any_held_or_pressed:
		_jump_buffer_timer = JUMP_BUFFER_TIME
		if not is_on_floor() and _double_jump_available and not _double_jump_used and (jump_just_pressed or jump_joy_just_pressed):
			var jump_velocity := _current_jump_velocity()
			# Apex time scales with the jump, otherwise the falloff curve runs off the
			# end of a shorter jump and the double jump never reaches full strength.
			var apex_time := jump_velocity / GRAVITY
			var progress := clampf(_double_jump_air_time / apex_time, 0.0, 1.0)
			var smooth := progress * progress * (3.0 - 2.0 * progress)
			velocity_y = jump_velocity * lerpf(DOUBLE_JUMP_MIN_MULTIPLIER, 1.0, smooth)
			_double_jump_used = true
			_double_jump_available = false
			_jump_buffer_timer = 0.0
	else:
		_jump_buffer_timer = maxf(0.0, _jump_buffer_timer - delta)

	if is_on_floor():
		var buffered_jump := movement_allowed and (_jump_buffer_timer > 0.0) and (jump_requested_now or _coyote_timer > 0.0)
		if buffered_jump:
			velocity_y = _current_jump_velocity()
			_jump_buffer_timer = 0.0
			if not _double_jump_available and not jump_requested_now:
				_ground_jump_count += 1
				if _ground_jump_count >= 2:
					_double_jump_available = true
					_ground_jump_count = 0

	# --- STAMINA ---
	var is_moving_input := move_direction.length_squared() > 0.05

	# Break the held-penalty if player released input
	if _stamina_held_empty and not is_moving_input:
		_stamina_held_empty = false

	# Throttle latches on hitting zero and only lifts when the player stops moving or
	# refills past the recovery threshold. Creeping alone never restores full speed.
	# Resolved before the drain below so the latch takes effect the same frame it is set.
	var stamina_empty := stamina <= 0.0
	if stamina_empty:
		_stamina_throttled = true
	elif not is_moving_input or stamina >= STAMINA_MAX * STAMINA_RECOVERY_FRACTION:
		_stamina_throttled = false
		# Recovery is done, so the re-drain lockout has served its purpose. Clearing it
		# here is what lets drain resume the moment the throttle lifts, instead of the
		# player sitting at the threshold doing nothing until the penalty times out.
		_stamina_held_empty = false
	var speed_to_use := SPEED * (STAMINA_EMPTY_SPEED_MULT if _stamina_throttled else 1.0)
	# RUSH: while the burst is active, run at a multiple of the normal speed.
	if _active_power_up_mode == LocalPickup.PowerUpMode.SPEED_BURST and _active_power_up_remaining > 0.0:
		speed_to_use *= SPEED_BURST_MULT

	# Drain and regen are mutually exclusive: while the player is genuinely draining,
	# stamina only falls. Any other situation regenerates instead, which is what lets a
	# player who has dropped the item refill again while they keep running.
	var is_holding := _is_local_holding_chicken() or _is_local_holding_lootbox() or _is_local_holding_pickup()
	var is_draining := is_moving_input and is_holding and stamina > 0.0 and not _stamina_held_empty and not _stamina_throttled
	if is_draining:
		# Scale drain by how hard the player is actually pushing, so analog input has a
		# cost gradient: full tilt drains fastest, a light touch drains at the floor rate.
		# Keyboard and gamepad digital input reports strength 1.0 and are unaffected.
		var effort := clampf(input_strength, STAMINA_DRAIN_MIN_MULT, 1.0)
		stamina = maxf(0.0, stamina - STAMINA_DRAIN_RATE * effort * delta)
		_stamina_regen_timer = STAMINA_REGEN_DELAY

	# Just hit zero — check if input still held
	if stamina <= 0.0 and is_moving_input and is_holding:
		_stamina_held_empty = true
		_stamina_empty_timer = STAMINA_HELD_PENALTY

	# Held-penalty countdown (ignores movement for 5 sec)
	if _stamina_held_empty:
		_stamina_empty_timer = maxf(0.0, _stamina_empty_timer - delta)
		if _stamina_empty_timer <= 0.0:
			_stamina_held_empty = false

	# Regen: runs whenever the player is not actively draining, whether they are moving
	# or standing, so stamina can never get stuck at zero and the throttle can always be
	# recovered from. Never stopping gets the slow rate; stopping doubles it, which makes
	# standing still the faster way back to full.
	if not is_draining:
		_stamina_regen_timer = maxf(0.0, _stamina_regen_timer - delta)
		if _stamina_regen_timer <= 0.0:
			var regen_rate := STAMINA_REGEN_RATE * (1.0 if is_moving_input else STAMINA_REGEN_IDLE_MULT)
			stamina = minf(STAMINA_MAX, stamina + regen_rate * delta)

	# --- HEALTH REGEN ---
	if not _is_dead:
		_health_regen_timer = maxf(0.0, _health_regen_timer - delta)
		if _health_regen_timer <= 0.0 and health < MAX_HEALTH:
			health = minf(MAX_HEALTH, health + HEALTH_REGEN_RATE * delta)
	elif _is_dead:
		_respawn_timer = maxf(0.0, _respawn_timer - delta)
		if _respawn_timer <= 0.0:
			respawn_at_spawn_point()

	# --- STORM DAMAGE (check every 0.1s) ---
	_update_storm_damage(delta)

	# --- MOMENTUM CALCULATION ---
	if _climb_push_timer > 0.0:
		# Launching off a climb surface: the away/vault vector owns horizontal
		# velocity for its short window instead of being snapped to the input.
		pass
	elif movement_allowed and not _is_action_locked():
		var target_vel = move_direction * speed_to_use

		# [MOMENTUM UPDATE] If we are in the air, use max speed instantly (no acceleration)
		if is_on_floor():
			var accel_to_use = ACCELERATION
			var friction_to_use = FRICTION
			var weight = accel_to_use if move_direction.length_squared() > 0.0 else friction_to_use
			velocity.x = move_toward(velocity.x, target_vel.x, weight * delta)
			velocity.z = move_toward(velocity.z, target_vel.z, weight * delta)
		else:
			# Snap to max speed instantly in the air
			velocity.x = target_vel.x
			velocity.z = target_vel.z
	else:
		velocity.x = move_toward(velocity.x, 0, FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0, FRICTION * delta)
		# The HOOK punch / near-death fall lock the player in place, so no glide
		# under the animation — but unlike a blocked match they still fall while
		# airborne.
		if not _is_action_locked():
			velocity_y = 0.0

	if _mega_leap_pending:
		# Applied here (not from input) so the grounded "velocity_y = 0" above
		# cannot wipe it before it reaches velocity.y.
		_mega_leap_pending = false
		velocity_y = _current_jump_velocity() * MEGA_LEAP_MULT

	velocity.y = velocity_y

	if _is_sliding:
		_slide_timer = maxf(0.0, _slide_timer - delta)
		if not _is_action_locked():
			var slide_speed := speed_to_use * SLIDE_SPEED_MULTIPLIER
			velocity.x = _slide_direction.x * slide_speed
			velocity.z = _slide_direction.z * slide_speed
		_apply_slide_camera_restore(delta)
		if _slide_timer <= 0.0 or not is_on_floor():
			_stop_slide()

	move_and_slide()

	if is_on_floor() and not was_on_floor_before_move:
		_start_landing_bob(vertical_speed_before_move)
		_spawn_landing_dust(vertical_speed_before_move)
		# Landing re-arms the double jump: the earned charge carries over until it is
		# actually used, so the HUD can show "double available" while grounded.
		_double_jump_used = false
		_double_jump_air_time = 0.0
		_zoom_cap_override = -1.0
	elif was_on_floor_before_move and not is_on_floor():
		# Left the ground this frame: a jump, a MEGA_LEAP, or simply walking off a
		# ledge. velocity_y still holds whatever impulse was applied above, so the
		# puff sizes itself from the jump instead of needing a call per jump site.
		_spawn_takeoff_dust()
	_apply_bus_riding()

	# Squash & stretch on jump/land
	var on_floor_now := is_on_floor()
	if on_floor_now:
		if _was_airborne:
			_squash_stretch_target = SQUASH_SCALE
		else:
			_squash_stretch_target = 1.0
		_was_airborne = false
	else:
		if not _was_airborne:
			_squash_stretch_target = SQUASH_SCALE
			_jump_peak_reached = false
		elif velocity_y > 0 and not _jump_peak_reached:
			_squash_stretch_target = STRETCH_SCALE
		elif velocity_y < 0:
			_jump_peak_reached = true
			_squash_stretch_target = 1.0
		_was_airborne = true

	var ss_result := _spring_float(_squash_stretch_y, _squash_stretch_velocity, _squash_stretch_target, SQUASH_STRETCH_SPEED, delta)
	_squash_stretch_y = ss_result[0]
	_squash_stretch_velocity = ss_result[1]

	# --- RUN BOUNCE ---
	var is_running := current_animation == "running" and is_on_floor() and not _is_sliding
	if is_running:
		_run_bounce_time += delta * RUN_BOUNCE_SPEED
		var bounce_sin := sin(_run_bounce_time)
		var bounce_y := absf(bounce_sin) * RUN_BOUNCE_HEIGHT
		var step_squash := 1.0 - RUN_BOUNCE_SQUASH * absf(bounce_sin)
		var step_wobble := RUN_BOUNCE_WOBBLE * sin(_run_bounce_time * 2.0)
		mesh.scale.y = _base_scale.y * _squash_stretch_y * step_squash
		mesh.scale.x = _base_scale.x * (1.0 + RUN_BOUNCE_SQUASH * 0.5 * absf(bounce_sin))
		mesh.scale.z = _base_scale.z * (1.0 + RUN_BOUNCE_SQUASH * 0.5 * absf(bounce_sin))
		mesh.position.y = bounce_y
		mesh.rotation.z = step_wobble
	else:
		_run_bounce_time = 0.0
		mesh.scale.y = _base_scale.y * _squash_stretch_y
		mesh.scale.x = _base_scale.x
		mesh.scale.z = _base_scale.z
		mesh.position.y = lerp(mesh.position.y, 0.0, delta * 15.0)
		mesh.rotation.z = lerp(mesh.rotation.z, 0.0, delta * 15.0)

	camera_is_airborne = not is_on_floor()
	camera_is_moving = velocity.x * velocity.x + velocity.z * velocity.z > 0.01
	camera_retreat_axis = maxf(-input_dir.y, absf(input_dir.x)) if movement_allowed else 0.0
	_camera_base_target_prev = _camera_base_target_curr
	_camera_base_target_curr = _camera_base_target()

	if move_direction.length_squared() > 0.0025:
		var target_yaw := atan2(move_direction.x, move_direction.z)
		var yaw_result := _spring_angle(mesh.rotation.y, _mesh_yaw_velocity, target_yaw, 20.0, delta)
		mesh.rotation.y = yaw_result[0]
		_mesh_yaw_velocity = yaw_result[1]

	_handle_animations(move_direction)
	_handle_camera_gamepad(delta)
	_mirror_twin_decoy()

	var net_active: bool = (move_direction.length_squared() > 0.0025) or _is_local_holding_chicken() or _is_local_holding_pickup() or (current_animation == "running")
	if current_animation == "runningjump" or current_animation == "falling" or current_animation == "runningslide":
		net_active = true

	# Only send network updates in gameplay (root is PlayerManager with WebSocket);
	# the root check itself lives inside _frame_ticks.
	_frame_ticks(net_active)

var _last_real_net_ms: float = 0.0
# Set by _set_anim when the pose actually changes, so the send block in
# _physics_process can emit it on that frame instead of waiting for the (much
# slower) idle tick window. The frame that flips to "idle" is also the frame that
# clears `net_active`, so without this the stop transition used to sit in the queue
# for up to NETWORK_TICK_IDLE (0.33 s) and remote clients kept showing the run loop.
var _anim_state_dirty: bool = false

# ---------------------------------------------------------------------------
# Frame ticks
# ---------------------------------------------------------------------------
## Network send window + slow periodic ticks, extracted from _physics_process so
## the climb branch (which bypasses the rest of the movement code) keeps the same
## send cadence and keeps the shared player-position shader fed.
func _frame_ticks(net_active: bool) -> void:
	# Only send network updates in gameplay (root is PlayerManager with WebSocket)
	if not (root and root.has_method("send_xp_update")):
		net_active = false

	var now_ms := float(Time.get_ticks_msec())
	if _last_real_net_ms == 0.0:
		_last_real_net_ms = now_ms
	var real_delta := (now_ms - _last_real_net_ms) / 1000.0
	_last_real_net_ms = now_ms

	network_tick_timer += real_delta
	network_heartbeat_timer += real_delta
	var tick_window := NETWORK_TICK_ACTIVE if net_active else NETWORK_TICK_IDLE
	var force_heartbeat := network_heartbeat_timer >= NETWORK_HEARTBEAT
	# An animation change is an event, not a periodic sample, so send it on this frame:
	# the frame that flips to "idle" also clears `net_active`, which used to leave the
	# stop transition sitting behind the 0.33 s idle window.
	var anim_changed := _anim_state_dirty
	if network_tick_timer >= tick_window or force_heartbeat or anim_changed:
		_send_state_to_server(force_heartbeat)
		_anim_state_dirty = false
		network_tick_timer = 0.0
		if force_heartbeat:
			network_heartbeat_timer = 0.0

	_slow_update_timer += real_delta
	if _slow_update_timer >= SLOW_UPDATE_INTERVAL:
		_slow_update_timer = 0.0
		_update_global_player_shader_pos()
		_refresh_name_label()

## Ring-of-death damage tick, shared by the normal path and the climb branch so
## hanging off a wall inside the storm does not make the player storm-proof.
## Skipped while dead: the dead body is about to respawn, and accumulating storm
## damage there would leave a leftover chunk that fires the instant they come back.
func _update_storm_damage(delta: float) -> void:
	if _is_dead:
		return
	_storm_check_timer += delta
	if _storm_check_timer < STORM_CHECK_INTERVAL:
		return
	_storm_check_timer = 0.0
	_refresh_storm_zone()
	var player_pos_2d := Vector2(global_position.x, global_position.z)
	var dist := player_pos_2d.distance_to(storm_center)
	if dist > storm_radius:
		_storm_damage_accumulator += storm_damage_per_second * STORM_CHECK_INTERVAL
		if _storm_damage_accumulator >= 1.0:
			var dmg := int(_storm_damage_accumulator)
			_storm_damage_accumulator -= dmg
			take_damage(dmg, self)
	else:
		_storm_damage_accumulator = 0.0

# ---------------------------------------------------------------------------
# Climb API (called by scripts/environment/ClimbableSurface.gd)
# ---------------------------------------------------------------------------
## Attach the local player to a climbable surface. `normal` is the surface's own
## outward face normal (pointing back at the player); pass Vector3.ZERO and it is
## worked out from where the player stands relative to the surface origin.
func begin_climb(surface: Node3D, normal: Vector3 = Vector3.ZERO) -> void:
	if not is_local or surface == null or _is_climbing:
		return
	# Refuse while dead, locked into a punch / near-death fall, sliding, riding the
	# bus, during a blocked match, or during the re-grab delay after letting go.
	if _is_dead or _is_action_locked() or _is_sliding or _is_riding_bus:
		return
	if not _is_movement_allowed() or _climb_reattach_cooldown > 0.0:
		return

	_is_climbing = true
	_climb_surface = surface
	_climb_normal = _resolve_climb_normal(surface, normal)
	if _climb_normal.length_squared() < 0.0001:
		# No climbable face here (nothing to stand against, or a floor-ish normal
		# the caller already rejected): back out instead of attaching to a wall.
		_is_climbing = false
		_climb_surface = null
		return

	# Stop dead and square up to the face: climbing is a controlled attachment,
	# not a slide down it. Jump/run pose leftovers are cleared so the climb loop
	# starts from the model's rest pose.
	velocity = Vector3.ZERO
	velocity_y = 0.0
	_stop_slide()
	_slide_requested = false
	_jump_requested = false
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0
	_double_jump_available = false
	_double_jump_used = false
	_double_jump_air_time = 0.0
	_squash_stretch_y = 1.0
	_squash_stretch_velocity = 0.0
	_squash_stretch_target = 1.0
	_run_bounce_time = 0.0
	_mesh_yaw_velocity = 0.0
	mesh.position.y = 0.0
	mesh.rotation.z = 0.0
	mesh.scale = _base_scale
	# Face the wall straight away; the run/idle yaw spring is bypassed while attached.
	mesh.rotation.y = atan2(-_climb_normal.x, -_climb_normal.z) + CLIMB_MESH_YAW_OFFSET
	# Airborne bookkeeping restarts from here, so detaching mid-wall is classified
	# as a fall from the detach point instead of from the last time we touched floor.
	_was_on_floor = false
	_airborne_start_y = global_position.y
	_last_world_y = global_position.y
	_set_anim("climb")

## Let go of the surface. `jump_off` launches away from the face (jump pressed),
## `vault` nudges toward it so exiting over the top edge lands on the ledge.
## `surface` is a guard: a body_exited from some other volume is ignored.
func end_climb(surface: Node3D = null, jump_off: bool = false, vault: bool = false) -> void:
	if not _is_climbing:
		return
	if surface != null and surface != _climb_surface:
		return

	_is_climbing = false
	_climb_surface = null
	_climb_reattach_cooldown = CLIMB_REATTACH_COOLDOWN
	var normal := _climb_normal
	_climb_normal = Vector3.ZERO

	if jump_off:
		# Push away from the face and hop off. The push owns horizontal velocity
		# for CLIMB_PUSH_TIME so the first frames of air control cannot cancel it.
		velocity = normal * CLIMB_JUMP_AWAY_SPEED
		velocity_y = _current_jump_velocity()
		_double_jump_available = false
		_double_jump_used = false
		_double_jump_air_time = 0.0
		_climb_push_timer = CLIMB_PUSH_TIME
	elif vault:
		velocity.x = -normal.x * CLIMB_VAULT_SPEED
		velocity.z = -normal.z * CLIMB_VAULT_SPEED
		velocity.y = 0.0
		velocity_y = 0.0
		_climb_push_timer = CLIMB_PUSH_TIME
	else:
		# Simple let-go (out of the volume, or the climb was cancelled): gravity
		# takes over on the next frame's normal path.
		velocity.y = 0.0
		velocity_y = 0.0

## Outward normal of the face being climbed: horizontal, pointing back at the
## player. Vector3.ZERO means "no climbable face here".
func _resolve_climb_normal(surface: Node3D, normal: Vector3) -> Vector3:
	normal.y = 0.0
	if normal.length_squared() > 0.0001:
		return normal.normalized()
	# Straight line from the surface origin back out to the player.
	var fallback := global_position - surface.global_position
	fallback.y = 0.0
	if fallback.length_squared() > 0.0001:
		return fallback.normalized()
	return Vector3.ZERO

## One physics frame of climbing: look-around, jump-off, movement on the face and
## the network send. Returns to _physics_process, which skips its normal path.
func _physics_process_climb(delta: float, input_dir: Vector2) -> void:
	# Camera look-around and follow keep working while attached; gravity, stamina,
	# slide, momentum and _handle_animations are all bypassed on purpose.
	_apply_touch_orbit()
	_handle_camera_gamepad(delta)
	_update_storm_damage(delta)
	_slide_requested = false
	_jump_buffer_timer = 0.0

	# Jump (keyboard / touch button / gamepad A) = let go and push off the face.
	var jump_joy_held := Input.is_joy_button_pressed(gamepad_index, JOY_BUTTON_A)
	var jump_joy_just := jump_joy_held and not _prev_joy_a_pressed
	_prev_joy_a_pressed = jump_joy_held
	if Input.is_action_just_pressed("jump") or _jump_requested or jump_joy_just:
		_jump_requested = false
		end_climb(_climb_surface, true)
		return

	var normal := _climb_normal
	var right := Vector3.UP.cross(normal)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized()

	# Forward/back (input_dir.y) climbs up and down the face, strafe (input_dir.x)
	# shuffles sideways along it, and a constant hug toward the wall keeps the
	# capsule in contact with the surface.
	var horizontal := right * (input_dir.x * CLIMB_SPEED) - normal * CLIMB_STICK_SPEED
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	velocity.y = input_dir.y * CLIMB_SPEED
	velocity_y = velocity.y

	move_and_slide()

	# Hold the face yaw and the climb loop; the run/idle yaw spring stays bypassed.
	mesh.rotation.y = atan2(-normal.x, -normal.z) + CLIMB_MESH_YAW_OFFSET
	_set_anim("climb")
	_mirror_twin_decoy()

	camera_is_airborne = not is_on_floor()
	camera_is_moving = input_dir.length_squared() > 0.05
	camera_retreat_axis = maxf(-input_dir.y, absf(input_dir.x))
	_camera_base_target_prev = _camera_base_target_curr
	_camera_base_target_curr = _camera_base_target()

	_frame_ticks(input_dir.length_squared() > 0.0025)

func _update_demo_agent(delta: float) -> void:
	if _demo_should_recover():
		_recover_demo_agent()
		return

	_demo_orbit_angle = wrapf(_demo_orbit_angle + (delta * demo_orbit_speed * _demo_orbit_direction), 0.0, TAU)

	var orbit_offset := Vector3(cos(_demo_orbit_angle), 0.0, sin(_demo_orbit_angle)) * demo_orbit_radius
	var wobble_offset := Vector3(
		sin((_demo_orbit_angle * 1.7) + _demo_wobble_phase),
		0.0,
		cos((_demo_orbit_angle * 1.3) + _demo_wobble_phase)
	) * demo_wobble_amount
	var target_pos := _demo_home_center + orbit_offset + wobble_offset
	var move_direction := target_pos - global_position
	move_direction.y = 0.0
	if move_direction.length_squared() > 0.001:
		move_direction = move_direction.normalized()
	else:
		move_direction = Vector3.ZERO

	if not is_on_floor():
		velocity_y -= GRAVITY * delta
	else:
		velocity_y = 0.0
		_demo_jump_timer -= delta
		if _demo_jump_timer <= 0.0:
			velocity_y = JUMP_VELOCITY * _demo_rng.randf_range(0.85, 1.15)
			_demo_jump_timer = _demo_rng.randf_range(demo_jump_min_interval, demo_jump_max_interval)

	# Apply momentum to demo agent
	var demo_target_vel = move_direction * demo_move_speed
	
	if is_on_floor():
		velocity.x = move_toward(velocity.x, demo_target_vel.x, ACCELERATION * delta)
		velocity.z = move_toward(velocity.z, demo_target_vel.z, ACCELERATION * delta)
	else:
		# Demo agent also snaps in air
		velocity.x = demo_target_vel.x
		velocity.z = demo_target_vel.z
		
	velocity.y = velocity_y
	move_and_slide()
	_apply_bus_riding()

	var on_floor_demo := is_on_floor()
	if on_floor_demo:
		if _was_airborne:
			_squash_stretch_target = SQUASH_SCALE
		else:
			_squash_stretch_target = 1.0
		_was_airborne = false
	else:
		if not _was_airborne:
			_squash_stretch_target = SQUASH_SCALE
			_jump_peak_reached = false
		elif velocity_y > 0 and not _jump_peak_reached:
			_squash_stretch_target = STRETCH_SCALE
		elif velocity_y < 0:
			_jump_peak_reached = true
			_squash_stretch_target = 1.0
		_was_airborne = true

	var ss_demo := _spring_float(_squash_stretch_y, _squash_stretch_velocity, _squash_stretch_target, SQUASH_STRETCH_SPEED, delta)
	_squash_stretch_y = ss_demo[0]
	_squash_stretch_velocity = ss_demo[1]

	# --- RUN BOUNCE (DEMO) ---
	var is_running_demo := current_animation == "running" and is_on_floor() and not _is_sliding
	if is_running_demo:
		_run_bounce_time += delta * RUN_BOUNCE_SPEED
		var bounce_sin_d := sin(_run_bounce_time)
		var bounce_y_d := absf(bounce_sin_d) * RUN_BOUNCE_HEIGHT
		var step_squash_d := 1.0 - RUN_BOUNCE_SQUASH * absf(bounce_sin_d)
		var step_wobble_d := RUN_BOUNCE_WOBBLE * sin(_run_bounce_time * 2.0)
		mesh.scale.y = _base_scale.y * _squash_stretch_y * step_squash_d
		mesh.scale.x = _base_scale.x * (1.0 + RUN_BOUNCE_SQUASH * 0.5 * absf(bounce_sin_d))
		mesh.scale.z = _base_scale.z * (1.0 + RUN_BOUNCE_SQUASH * 0.5 * absf(bounce_sin_d))
		mesh.position.y = bounce_y_d
		mesh.rotation.z = step_wobble_d
	else:
		_run_bounce_time = 0.0
		mesh.scale.y = _base_scale.y * _squash_stretch_y
		mesh.scale.x = _base_scale.x
		mesh.scale.z = _base_scale.z
		mesh.position.y = lerp(mesh.position.y, 0.0, delta * 15.0)
		mesh.rotation.z = lerp(mesh.rotation.z, 0.0, delta * 15.0)

	camera_is_airborne = not is_on_floor()
	camera_is_moving = velocity.x * velocity.x + velocity.z * velocity.z > 0.01
	_camera_base_target_prev = _camera_base_target_curr
	_camera_base_target_curr = _camera_base_target()

	if move_direction.length_squared() > 0.0025:
		var target_yaw := atan2(move_direction.x, move_direction.z)
		var yaw_result := _spring_angle(mesh.rotation.y, _mesh_yaw_velocity, target_yaw, 14.0, delta)
		mesh.rotation.y = yaw_result[0]
		_mesh_yaw_velocity = yaw_result[1]

	if camera_is_airborne:
		if velocity_y < 0.0:
			current_animation = "falling"
			_play_anim("falling")
		else:
			current_animation = "runningjump"
			_play_anim("runningjump")
	elif camera_is_moving:
		current_animation = "running"
		_play_anim("running")
	else:
		current_animation = "idle"
		_play_anim("idle")

	if is_on_floor():
		_demo_last_safe_position = global_position
		_demo_offground_timer = 0.0
	else:
		_demo_offground_timer += delta

func _demo_should_recover() -> bool:
	if global_position.y < _demo_home_center.y - DEMO_RECOVERY_FALL_DISTANCE:
		return true
	if _demo_offground_timer >= DEMO_RECOVERY_OFFGROUND_TIME and not is_on_floor():
		return true
	return false

func _recover_demo_agent() -> void:
	var recovery_pos := _demo_last_safe_position
	if recovery_pos == Vector3.ZERO:
		recovery_pos = _demo_home_center
	recovery_pos.y = maxf(recovery_pos.y, _demo_home_center.y) + DEMO_RECOVERY_RAISE_OFFSET

	global_position = recovery_pos
	velocity = Vector3.ZERO
	velocity_y = 0.0
	_demo_jump_timer = _demo_rng.randf_range(demo_jump_min_interval, demo_jump_max_interval)
	_demo_offground_timer = 0.0
	camera_is_airborne = false
	camera_is_moving = false
	current_animation = "idle"
	_play_anim("idle")
	
	# Reset health on recovery
	health = MAX_HEALTH
	_health_regen_timer = 0.0
	_is_dead = false
	_respawn_timer = 0.0
	# A recovery is a revive like any other: make sure a burn in progress cannot
	# leave the model invisible or invisible-but-solid.
	DeathDissolve.restore(self)

func _check_map_recovery() -> void:
	if global_position.y >= -5.0:
		return

	var now_ms := Time.get_ticks_msec()
	if now_ms - _last_recovery_ms < 750:
		return

	_last_recovery_ms = now_ms
	_is_punching = false
	_punch_timer = 0.0
	_is_dying_fall = false
	_critical_fall_timer = 0.0
	_is_sliding = false
	_slide_timer = 0.0
	_slide_direction = Vector3.ZERO
	_slide_camera_restore_active = false
	_jump_requested = false
	_air_horizontal_velocity = Vector3.ZERO
	velocity = Vector3.ZERO
	velocity_y = 0.0
	cam_rot_x = clamp(cam_rot_x, min_pitch, max_pitch)
	_movement_pitch_ease_active = false
	_pitch_before_movement_ease = -1.0
	_dive_level = 0.0
	_landing_fov_kick = 0.0
	current_animation = "idle"
	_play_anim("idle")

	# Break the hold so a respawn does not drag the item across the map.
	if _is_local_holding_pickup():
		_drop_local_pickup()

	# Reset health on map recovery (fell off world)
	health = MAX_HEALTH
	_health_regen_timer = 0.0
	_is_dead = false
	_respawn_timer = 0.0
	DeathDissolve.restore(self)

	# Get spawn position - try root first, then search scene for spawn marker
	var spawn_pos: Vector3
	if root and root.has_method("get_local_spawn_position"):
		spawn_pos = root.get_local_spawn_position()
	else:
		# Search for myplayerswpanpoint marker in scene (PlayerManager export)
		var player_manager = get_tree().get_first_node_in_group("player_manager")
		if player_manager and player_manager.has_method("get_local_spawn_position"):
			spawn_pos = player_manager.get_local_spawn_position()
		else:
			spawn_pos = Vector3(0, 2, 0)
	
	global_position = spawn_pos

	_last_world_y = global_position.y
	_airborne_start_y = global_position.y
	_was_on_floor = true
	_update_global_player_shader_pos(true)
	_send_state_to_server(true)

func _start_landing_bob(fall_velocity: float) -> void:
	var impact_speed := absf(fall_velocity)
	if impact_speed < 4.5:
		return
	_landing_bob_strength = clamp((impact_speed - 4.5) / 12.0, 0.0, 1.0)
	_landing_bob_timer = LANDING_BOB_DURATION
	# Short FOV punch on hard landings: the harder the impact, the bigger the
	# flash, decaying back to normal over a fraction of a second in
	# _update_camera_visual.
	_landing_fov_kick = landing_fov_kick_max * (0.35 + 0.65 * _landing_bob_strength)

func _try_pickup():
	if not pickup_area:
		return
	var now = Time.get_ticks_msec()
	if now - last_pickup_request_ms < PICKUP_REQUEST_COOLDOWN_MS:
		return
	last_pickup_request_ms = now
	var bodies = pickup_area.get_overlapping_bodies()
	var best_target: RigidBody3D = null
	var shortest_dist: float = 999.0
	for body in bodies:
		if body is RigidBody3D and body != self and body.is_in_group("pickup_items"):
			var dist = global_position.distance_to(body.global_position)
			if dist < shortest_dist:
				shortest_dist = dist
				best_target = body
	if best_target == null:
		var entities: Array[RigidBody3D] = [
			_get_cached_chicken_node(),
			_get_cached_lootbox_node(),
		]
		var fallback_dist: float = ITEM_PICKUP_RADIUS
		for entity in entities:
			if entity != null and entity.is_in_group("pickup_items"):
				var dist = global_position.distance_to(entity.global_position)
				if dist < fallback_dist:
					fallback_dist = dist
					best_target = entity
	if best_target and root and root.ws and root.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		root.ws.send(MsgPack.pack({
			"type": "pickup_request",
			"item_id": best_target.name
		}))

func _drop_object():
	if not _is_local_holding_chicken() and not _is_local_holding_lootbox():
		return
	if not root or not root.ws:
		return
	if root.ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var item_id = "Chicken" if _is_local_holding_chicken() else "LootBox"
	var throw_dir = -camera.global_transform.basis.z
	root.ws.send(MsgPack.pack({
		"type": "drop_request",
		"item_id": item_id,
		"throw_x": throw_dir.x * 5.0,
		"throw_y": max(1.0, throw_dir.y * 5.0),
		"throw_z": throw_dir.z * 5.0
	}))

func _is_local_holding_pickup() -> bool:
	return held_local_pickup != null and is_instance_valid(held_local_pickup) and held_local_pickup.has_method("is_being_held") and held_local_pickup.is_being_held()

# Objective items (chicken / lootbox) are carried and dropped like a plain
# pickup — they are never consumed as a power-up.
func _is_objective_item_mode(mode: int) -> bool:
	return mode == LocalPickup.PowerUpMode.CHICKEN or mode == LocalPickup.PowerUpMode.LOOTBOX

func _find_nearest_local_pickup() -> RigidBody3D:
	var best: RigidBody3D = null
	var best_dist: float = LOCAL_PICKUP_RADIUS
	for node in get_tree().get_nodes_in_group("local_pickup_items"):
		if not (node is RigidBody3D) or not is_instance_valid(node):
			continue
		if not node.has_method("can_pick_up") or not node.can_pick_up():
			continue
		var dist: float = global_position.distance_to(node.global_position)
		if dist < best_dist:
			best_dist = dist
			best = node
	return best

# LocalPickup items are never sent to the server, they are grabbed client side only.
func _try_pickup_local() -> bool:
	# One carried item at a time: holding anything blocks another pickup. A
	# reveal-granted power-up has no pickup instance, so its mode is checked too.
	if _is_local_holding_pickup() or held_power_up_mode != LocalPickup.PowerUpMode.NONE:
		return false
	var now := Time.get_ticks_msec()
	if now - last_pickup_request_ms < PICKUP_REQUEST_COOLDOWN_MS:
		return false
	var target := _find_nearest_local_pickup()
	if target == null:
		return false
	# A running timed power-up effect only blocks a new POWER-UP pickup.
	# Objective items (chicken / lootbox) can still be grabbed mid-effect.
	var target_mode_value = target.get("power_up_mode")
	var target_mode := int(target_mode_value) if target_mode_value != null else LocalPickup.PowerUpMode.NONE
	if _active_power_up_remaining > 0.0 and not _is_objective_item_mode(target_mode):
		return false
	if not target.has_method("pick_up") or not target.pick_up(self):
		return false
	held_local_pickup = target
	last_pickup_request_ms = now
	# Remember the mode and surface it in the HUD Action button. Objective items
	# (chicken / lootbox) show their caption here too.
	var mode_value = target.get("power_up_mode")
	held_power_up_mode = int(mode_value) if mode_value != null else LocalPickup.PowerUpMode.NONE
	_update_hud_power_up()
	return true

func _drop_local_pickup() -> void:
	var item := held_local_pickup
	held_local_pickup = null
	held_power_up_mode = LocalPickup.PowerUpMode.NONE
	_update_hud_power_up()
	if item == null or not is_instance_valid(item):
		return
	if not item.has_method("drop"):
		return
	var throw_dir := Vector3.ZERO
	if camera != null:
		throw_dir = -camera.global_transform.basis.z
	if throw_dir.length_squared() < 0.0001:
		throw_dir = -global_transform.basis.z
	item.drop(throw_dir * LOCAL_PICKUP_THROW_STRENGTH)

# On death, an unused power-up is left exactly where the player fell, so it can
# be recovered on the spot. Unlike a manual drop it is not thrown along the
# camera direction, and unlike a used power-up it is never recycled to a random
# map spot. The holder is stripped of the pickup and its HUD slot.
func _drop_power_up_at_death() -> void:
	var item := held_local_pickup
	held_local_pickup = null
	held_power_up_mode = LocalPickup.PowerUpMode.NONE
	_update_hud_power_up()
	if item == null or not is_instance_valid(item):
		return
	if not item.has_method("drop"):
		return
	# Drop straight down from the death position so it rests exactly there.
	item.global_position = global_position
	item.drop(Vector3.ZERO)

# The server-tracked id of the pickup the local player is carrying, or "".
func _held_local_item_id() -> String:
	if held_local_pickup == null or not is_instance_valid(held_local_pickup):
		return ""
	if held_local_pickup.has_method("server_item_id"):
		return String(held_local_pickup.call("server_item_id"))
	return ""

# The server says another player now holds the item we were carrying (it was
# snatched). Drop the local claim silently — no drop_request, the server already
# decided who has it, and it will broadcast the item's new spot.
func release_item_if_holding(item_id: String) -> void:
	if held_local_pickup == null or not is_instance_valid(held_local_pickup):
		return
	if _held_local_item_id() != item_id:
		return
	var item := held_local_pickup
	held_local_pickup = null
	held_power_up_mode = LocalPickup.PowerUpMode.NONE
	_update_hud_power_up()
	if item.has_method("release_silently"):
		item.call("release_silently")

# Uses the held power-up pickup: it is consumed here and teleports to a random
# far-away spot on the map instead of being dropped at the player's feet, then
# its effect is applied.
func _use_held_power_up() -> void:
	var mode := held_power_up_mode
	var item := held_local_pickup
	held_local_pickup = null
	held_power_up_mode = LocalPickup.PowerUpMode.NONE
	# Activate before refreshing the HUD so the caption can switch straight to the
	# running effect instead of flashing GRAB for a frame.
	_activate_power_up(mode)
	_update_hud_power_up()
	if item == null or not is_instance_valid(item):
		return
	# The SERVER owns where a used power-up reappears, so this only releases the
	# hold and tells the server to re-roll; the new spot arrives via the item
	# snapshot. Falls back to a local respawn for any unsynced pickup.
	if item.has_method("consume_for_server"):
		item.call("consume_for_server")
	elif item.has_method("consume_and_respawn"):
		item.call("consume_and_respawn", global_position)

# Applies the one-shot effect for a consumed power-up. Modes without an effect
# yet simply do nothing (the pickup is still consumed and recycled).
func _activate_power_up(mode: int) -> void:
	match mode:
		LocalPickup.PowerUpMode.SPEED_BURST:
			# RUSH: 2x run speed for 8 seconds.
			_start_timed_power_up(LocalPickup.PowerUpMode.SPEED_BURST, SPEED_BURST_DURATION)
		LocalPickup.PowerUpMode.TWIN:
			# TWIN: spawn a decoy clone that mirrors movement for 8 seconds.
			_start_timed_power_up(LocalPickup.PowerUpMode.TWIN, TWIN_DURATION)
			_spawn_twin_decoy()
		LocalPickup.PowerUpMode.SMOKE_GRENADE:
			# SMOG: 8 seconds during which the Action button drops smoke clouds.
			# Drop the first cloud immediately, right where the player used it.
			_start_timed_power_up(LocalPickup.PowerUpMode.SMOKE_GRENADE, SMOKE_DURATION)
			_smoke_drop_cooldown = 0.0
			_try_drop_smoke_cloud()
		LocalPickup.PowerUpMode.MEGA_LEAP:
			# LEAP: 8 seconds during which the Action button launches 4x jumps,
			# plus an immediate launch on use.
			_start_timed_power_up(LocalPickup.PowerUpMode.MEGA_LEAP, MEGA_LEAP_DURATION)
			_trigger_mega_leap()
		LocalPickup.PowerUpMode.HOOK:
			# HOOK: an 8s window during which the Action button fires the punch,
			# with an immediate first punch on use. Each punch plays to completion
			# before another can be fired.
			_start_timed_power_up(LocalPickup.PowerUpMode.HOOK, HOOK_DURATION)
			_start_punch()
		_:
			pass

# True while the timed MEGA_LEAP effect is still running.
func _is_mega_leap_active() -> bool:
	return _active_power_up_mode == LocalPickup.PowerUpMode.MEGA_LEAP and _active_power_up_remaining > 0.0

# True while the timed HOOK punch window is still running.
func _is_hook_active() -> bool:
	return _active_power_up_mode == LocalPickup.PowerUpMode.HOOK and _active_power_up_remaining > 0.0

# Launches a 4x mega jump, one per time the player leaves the ground. The launch
# is deferred to the next physics step so the grounded "velocity_y = 0" reset
# can't cancel it. Mid-air presses during the LEAP window are ignored, so the
# player must land before the Action button launches another mega jump.
func _trigger_mega_leap() -> void:
	if not is_on_floor():
		return
	_mega_leap_pending = true

# Returns the name of a PUNCH_SPEED_MULT-faster copy of the hook punch animation,
# creating and registering it in the animator's library on first call. The
# original clip is left untouched; the state machine's "hook" state plays the copy.
func _ensure_fast_hook_animation(speed_mult: float) -> StringName:
	var fast_name := &"hook_fast"
	if anim_player.has_animation(fast_name):
		return fast_name
	var src := anim_player.get_animation("hook") as Animation
	if src == null:
		return &"hook"
	var fast := src.duplicate() as Animation
	for track in fast.get_track_count():
		var key_count := fast.track_get_key_count(track)
		for key in key_count:
			fast.track_set_key_time(track, key, fast.track_get_key_time(track, key) / speed_mult)
	fast.length = src.length / speed_mult
	var lib := anim_player.get_animation_library(&"") as AnimationLibrary
	if lib == null:
		lib = AnimationLibrary.new()
		anim_player.add_animation_library(&"", lib)
	lib.add_animation(fast_name, fast)
	return fast_name

# Plays the HOOK punch animation once, locking the run/idle animation states for
# the animation's duration so a moving player punches in place instead of running.
func _start_punch() -> void:
	# A punch already in flight is left alone to finish: the Action button can be
	# pressed as often as you like during the HOOK window, but each swing has to
	# play to the end before the next one starts, so spamming never restarts the
	# clip mid-swing (which also keeps the movement lock from being held forever).
	if _is_punching:
		return
	_is_punching = true
	var duration := HOOK_FALLBACK_DURATION / PUNCH_SPEED_MULT
	var punch_anim := anim_player.get_animation("hook") as Animation
	if punch_anim != null:
		duration = punch_anim.length / PUNCH_SPEED_MULT
	_punch_timer = duration
	if current_animation == "hook":
		# Rare: the state is still on "hook" (held past the clip), so restart it
		# from the top rather than being skipped by _set_anim's same-state guard.
		if anim_state_machine:
			anim_state_machine.start(&"hook", true)
		return
	_set_anim("hook")

# Plays the near-death fall animation once when health drops to the critical
# threshold (5% of max), right before the health bar empties.
func _start_critical_fall() -> void:
	if _is_dying_fall or _is_action_locked():
		return
	_is_dying_fall = true
	var duration := CRITICAL_FALL_FALLBACK
	var fall_anim := anim_player.get_animation("fall") as Animation
	if fall_anim != null:
		duration = fall_anim.length
	_critical_fall_timer = duration
	_set_anim("fall")

# --- TWIN DECOY ---
# Spawns the TWIN decoy. It is a visual-only copy of the local player: the same
# skin scene is instanced, its physics nodes are stripped, and its visual children
# are re-parented onto a lightweight RemotePlayer node. That gives us an animated
# character we drive ourselves without it running player.gd's gameplay logic.
func _spawn_twin_decoy() -> void:
	_despawn_twin_decoy()
	if not is_inside_tree():
		return
	_roll_twin_randomness()
	var scene := _resolve_decoy_scene()
	if scene == null:
		return
	var source := scene.instantiate() as Node3D
	if source == null:
		return
	var applier := SkinApplier.new()
	applier.apply_skin(source, _resolve_decoy_skin_name())
	_strip_decoy_physics(source)
	var decoy: Node3D = REMOTE_PLAYER_SCRIPT.new()
	decoy.name = "TwinDecoy"
	for child in source.get_children():
		source.remove_child(child)
		child.owner = null
		decoy.add_child(child)
	source.queue_free()
	# Parent to the scene root so it lives and dies with the current scene and
	# never shows up where gameplay code expects an actual player node.
	var parent := get_tree().current_scene
	if parent == null:
		parent = get_parent()
	if parent == null:
		decoy.queue_free()
		return
	parent.add_child(decoy)
	decoy.set("display_name", "")  # no floating name over the decoy
	_twin_decoy = decoy
	_twin_decoy_mesh = decoy.get_node_or_null("Skeleton3D") as Node3D
	_mirror_twin_decoy()


func _despawn_twin_decoy() -> void:
	if _twin_decoy != null and is_instance_valid(_twin_decoy):
		_twin_decoy.queue_free()
	_twin_decoy = null
	_twin_decoy_mesh = null


# Follows the player with a world-space offset frozen at spawn, and mirrors the
# player's rotation live so the clone faces the same way - spinning about its own
# axis rather than swinging around the player. Its animation state is kept in
# sync each step. Mirrors the decoy's own Skeleton3D (not the root) so the
# skeleton's authored scale is not applied a second time.
func _mirror_twin_decoy() -> void:
	if _twin_decoy == null or not is_instance_valid(_twin_decoy):
		_twin_decoy = null
		_twin_decoy_mesh = null
		return
	if _twin_decoy_mesh == null or not is_instance_valid(_twin_decoy_mesh):
		_twin_decoy_mesh = _twin_decoy.get_node_or_null("Skeleton3D") as Node3D
		if _twin_decoy_mesh == null:
			return
	var src := mesh.global_transform
	_twin_decoy_mesh.global_transform = Transform3D(src.basis, src.origin + _twin_world_offset)
	if _twin_decoy.has_method("set_animation_state"):
		_twin_decoy.call("set_animation_state", current_animation)


# Rolls the decoy's random side distance and bearing once per spawn and freezes
# the resulting world-space offset, so the clone keeps its distance and never
# swings around the player. Facing is mirrored live, not rolled.
func _roll_twin_randomness() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var distance := rng.randf_range(TWIN_DECOY_DISTANCE_MIN, TWIN_DECOY_DISTANCE_MAX)
	var bearing := deg_to_rad(rng.randf_range(-TWIN_BEARING_JITTER_DEG, TWIN_BEARING_JITTER_DEG))
	var local_offset := Vector3(cos(bearing) * distance, 0.0, sin(bearing) * distance)
	_twin_world_offset = mesh.global_transform.basis.orthonormalized() * local_offset


func _resolve_decoy_scene() -> PackedScene:
	var path := scene_file_path
	if path.is_empty():
		path = TWIN_SKIN_SCENE_PATH
	return load(path) as PackedScene


# Uses the skin this player node actually wears, which apply_skin records on the
# node itself - so the duplicate matches in every flow (gameplay, lobby, skin
# cycled with T), not just where a root node exposes local_skin_name. Falls back
# to the gameplay root's skin name, then the default skin.
func _resolve_decoy_skin_name() -> String:
	var own := str(get_meta(SkinApplier.APPLIED_SKIN_META, ""))
	if own != "":
		return own
	if root != null:
		var skin_name = root.get("local_skin_name")
		if skin_name is String and not (skin_name as String).is_empty():
			return str(skin_name)
	return SkinApplier.DEFAULT_SKIN


# Removes every physics node so the decoy is purely visual and cannot collide,
# push the player, or trigger pickup areas.
func _strip_decoy_physics(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionObject3D or child is CollisionShape3D or child is Area3D or child is RayCast3D:
			node.remove_child(child)
			child.queue_free()
			continue
		_strip_decoy_physics(child)


# --- SMOKE CLOUDS (SMOG) ---
# True while the SMOG effect's 8-second drop window is running.
func _is_smoke_active() -> bool:
	return _active_power_up_mode == LocalPickup.PowerUpMode.SMOKE_GRENADE and _active_power_up_remaining > 0.0


# Builds one throwaway smoke cloud so the first real drop doesn't hitch. The
# first cloud otherwise pays, on the frame Action is pressed, for generating its
# 64x64 noise sprite and for compiling its particle material's shader variant.
# Neither is huge alone, but together they read as a stutter right as the player
# uses the power-up. Off-screen geometry is culled before its material compiles,
# so the warm-up cloud is parked in front of the camera; it is kept fully
# transparent, so nothing shows. One-shot per process.
func _prewarm_smoke_cloud() -> void:
	if _smoke_prewarmed:
		return
	if DisplayServer.get_name() == "headless":
		return
	var camera := _resolve_camera_node()
	if camera == null:
		return
	var cloud := SMOKE_CLOUD_SCENE.instantiate() as Node3D
	if cloud == null:
		return
	_smoke_prewarmed = true
	cloud.call("setup", SMOKE_CLOUD_RADIUS, 1)
	cloud.call("set_warmup")
	var parent := get_tree().current_scene
	if parent == null:
		parent = get_parent()
	if parent == null:
		cloud.queue_free()
		return
	parent.add_child(cloud)
	# Two metres in front of the camera: inside the frustum, so it is drawn.
	cloud.global_position = camera.global_position - camera.global_transform.basis.z * 2.0
	# Give the renderer a couple of drawn frames to compile the material, then drop it.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if is_instance_valid(cloud):
		cloud.queue_free()


# Drops a smog cloud at the player's feet, if the drop cooldown has elapsed.
func _try_drop_smoke_cloud() -> void:
	if _smoke_drop_cooldown > 0.0:
		return
	_smoke_drop_cooldown = SMOKE_DROP_COOLDOWN
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var drop_position := global_position + Vector3(0.0, SMOKE_CLOUD_RADIUS * 0.3, 0.0)
	_spawn_smoke_cloud(drop_position, rng.randi())


# Network seam: today this just spawns the cloud locally. The multiplayer version
# replaces the body with an RPC that broadcasts the same position + seed, so every
# client builds an identical cloud without touching the cloud itself.
func _spawn_smoke_cloud(world_position: Vector3, spawn_seed: int) -> void:
	var cloud := SMOKE_CLOUD_SCENE.instantiate() as Node3D
	if cloud == null:
		return
	cloud.call("setup", SMOKE_CLOUD_RADIUS, spawn_seed)
	var parent := get_tree().current_scene
	if parent == null:
		parent = get_parent()
	if parent == null:
		cloud.queue_free()
		return
	parent.add_child(cloud)
	cloud.global_position = world_position
	_track_smoke_cloud(cloud)


# Keeps at most MAX_SMOKE_CLOUDS alive by recycling the oldest when full. Clouds
# free themselves after their own lifetime, so this only hears about the extras.
func _track_smoke_cloud(cloud: Node3D) -> void:
	var alive: Array = []
	for existing in _smoke_clouds:
		if is_instance_valid(existing) and not existing.is_queued_for_deletion():
			alive.append(existing)
	_smoke_clouds = alive
	while _smoke_clouds.size() >= MAX_SMOKE_CLOUDS:
		var oldest = _smoke_clouds.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	_smoke_clouds.append(cloud)


# --- JUMP / LANDING DUST ---
# A short ground puff on take-off and on landing. Both are detected centrally in
# _physics_process by watching the floor state across move_and_slide(), so every
# jump site (walk, buffered jump, double jump's landing, MEGA_LEAP) is covered
# without repeating a spawn call at each one.

# Builds one throwaway puff so the first real jump doesn't hitch. Same reasoning
# as _prewarm_smoke_cloud: the first burst pays for the shared sprite and for
# compiling the particle material, both of which would land on the frame the
# player presses jump. Off-screen geometry is culled before its material
# compiles, so the warm-up is parked in front of the camera and kept invisible.
func _prewarm_jump_dust() -> void:
	if _dust_prewarmed:
		return
	if DisplayServer.get_name() == "headless":
		return
	var camera := _resolve_camera_node()
	if camera == null:
		return
	var burst := DUST_BURST_SCENE.instantiate() as Node3D
	if burst == null:
		return
	_dust_prewarmed = true
	burst.call("setup", 1.0)
	burst.call("set_warmup")
	var parent := get_tree().current_scene
	if parent == null:
		parent = get_parent()
	if parent == null:
		burst.queue_free()
		return
	parent.add_child(burst)
	burst.global_position = camera.global_position - camera.global_transform.basis.z * 2.0
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if is_instance_valid(burst):
		burst.queue_free()


# Take-off strength comes from the impulse that was just applied, so a MEGA_LEAP
# throws a much bigger puff than a tired hop, and stepping off a ledge (almost no
# vertical speed) barely raises any.
func _spawn_takeoff_dust() -> void:
	_spawn_dust(global_position, absf(velocity_y) / JUMP_VELOCITY)


# Landing strength comes from the speed the player hit the ground with. Small
# drops are ignored: a puff on every kerb step would read as noise.
func _spawn_landing_dust(fall_velocity: float) -> void:
	var impact := absf(fall_velocity)
	if impact < 2.5:
		return
	_spawn_dust(global_position, impact / 8.0)


# Network seam: like the SMOG cloud, this is a local-only visual for now. The
# multiplayer version only needs to replicate the position + strength.
func _spawn_dust(world_position: Vector3, burst_strength: float) -> void:
	if not is_local:
		return
	var burst := DUST_BURST_SCENE.instantiate() as Node3D
	if burst == null:
		return
	burst.call("setup", burst_strength)
	var parent := get_tree().current_scene
	if parent == null:
		parent = get_parent()
	if parent == null:
		burst.queue_free()
		return
	parent.add_child(burst)
	# A few centimetres up so the puffs are not half buried in the ground.
	burst.global_position = world_position + Vector3(0.0, 0.04, 0.0)
	_track_dust_burst(burst)


# Keeps at most MAX_DUST_BURSTS alive by recycling the oldest when full; bursts
# free themselves once their particles have faded.
func _track_dust_burst(burst: Node3D) -> void:
	var alive: Array = []
	for existing in _dust_bursts:
		if is_instance_valid(existing) and not existing.is_queued_for_deletion():
			alive.append(existing)
	_dust_bursts = alive
	while _dust_bursts.size() >= MAX_DUST_BURSTS:
		var oldest = _dust_bursts.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	_dust_bursts.append(burst)


# Starts (or replaces) the single timed power-up the HUD draws a ring for.
func _start_timed_power_up(mode: int, duration: float) -> void:
	# Leaving a TWIN effect for any other effect tears the decoy down.
	if mode != LocalPickup.PowerUpMode.TWIN:
		_despawn_twin_decoy()
	_active_power_up_mode = mode
	_active_power_up_duration = duration
	_active_power_up_remaining = duration
	# Wrap the player in the power-up aura for the whole usage window
	# (idempotent: a replacement effect just keeps the aura on).
	apply_powerup_visual(true)


# --- POWER-UP VISUAL (aura) ---
# Builds the shared powerup material once. Kept lazy-safe so it also works if
# _ready has not run yet or the shader failed to preload at parse time.
func _ensure_powerup_material() -> void:
	if _powerup_material != null:
		return
	var shader := POWERUP_SHADER as Shader
	if shader == null:
		return
	_powerup_material = ShaderMaterial.new()
	_powerup_material.shader = shader
	_powerup_material.set_shader_parameter("tint", POWERUP_TINT)
	_powerup_material.set_shader_parameter("AuraProgres", POWERUP_AURA_PROGRESS)


# Builds the aura quad once and parents it to the player. It is a separate,
# billboarded MeshInstance3D rather than a pass on the body meshes: a glow that
# wraps *around* the character cannot be produced by the character's own
# geometry (that only ever gives an outline). It is named so SkinApplier's
# MeshInstance3D sweep ignores it - that only matches body/cheek/crown/
# attachment/eye names - and is shadow-less, so it never costs an extra pass.
func _ensure_aura_node() -> MeshInstance3D:
	if _powerup_aura != null and is_instance_valid(_powerup_aura):
		return _powerup_aura
	_ensure_powerup_material()
	if _powerup_material == null:
		return null
	var quad := QuadMesh.new()
	quad.size = POWERUP_AURA_SIZE
	var aura := MeshInstance3D.new()
	aura.name = "powerup_aura"
	aura.mesh = quad
	aura.material_override = _powerup_material
	aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	aura.position = Vector3(0.0, POWERUP_AURA_HEIGHT, 0.0)
	aura.visible = false
	add_child(aura)
	_powerup_aura = aura
	return aura


# Compiles the death burn's shader on a throwaway frame, so the first death does
# not eat the stall. Measured on this machine: the first death frame goes from
# ~44-62 ms cold to ~14-24 ms warm, against a ~7-11 ms idle baseline, which keeps
# the stutter inside the 30fps frame budget instead of dropping one.
func _prewarm_death_dissolve() -> void:
	DeathDissolve.prewarm(self)


# Compiles the aura's shader on a throwaway frame, so the first real power-up
# never eats the stall. Same trick as _prewarm_smoke_cloud: culled geometry never
# compiles its material, so the quad is parked in front of the camera at zero
# strength - drawn, but fully transparent, so nothing shows - given two drawn
# frames, then put back on the player. One-shot per process.
func _prewarm_powerup_aura() -> void:
	if _powerup_prewarmed:
		return
	if DisplayServer.get_name() == "headless":
		return
	var aura := _ensure_aura_node()
	if aura == null:
		return
	if not is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	_powerup_prewarmed = true
	_powerup_camera = camera
	_powerup_material.set_shader_parameter("AuraProgres", 0.0)
	aura.visible = true
	# Two metres in front of the camera: inside the frustum, so it is drawn.
	aura.global_position = camera.global_position - camera.global_transform.basis.z * 2.0
	aura.look_at(camera.global_position)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_instance_valid(aura):
		return
	_powerup_material.set_shader_parameter("AuraProgres", POWERUP_AURA_PROGRESS)
	# Put the quad back on the player; the next aim re-orients it.
	aura.position = Vector3(0.0, POWERUP_AURA_HEIGHT, 0.0)
	_powerup_aim_valid = false
	if _powerup_visual_active:
		_aim_aura_at_camera(true)
	else:
		aura.visible = false


# Turns the aura on for the whole usage window and hides it again when the
# effect ends. Entering/leaving only toggles `visible` - the quad and material
# are built once, so a later power-up allocates nothing.
func apply_powerup_visual(active: bool) -> void:
	if active:
		var aura := _ensure_aura_node()
		if aura == null:
			return
		# A prewarm may still be holding the aura at zero strength.
		_powerup_material.set_shader_parameter("AuraProgres", POWERUP_AURA_PROGRESS)
		_powerup_visual_active = true
		# Covers the (rare) case of a use landing mid-prewarm, while the quad is
		# still parked in front of the camera.
		aura.position = Vector3(0.0, POWERUP_AURA_HEIGHT, 0.0)
		aura.visible = true
		_aim_aura_at_camera(true)
	else:
		if not _powerup_visual_active:
			return
		_powerup_visual_active = false
		if _powerup_aura != null and is_instance_valid(_powerup_aura):
			_powerup_aura.visible = false


# Re-aims the aura while the effect runs. Cheap by design: nothing here scans the
# tree, and a frame where neither the player nor the camera moved skips even the
# billboard write.
func _maintain_powerup_visual() -> void:
	if _powerup_visual_active:
		_aim_aura_at_camera()


# Faces the aura at the camera. look_at() points -Z at its target and the
# QuadMesh normal is +Z, so the node's -Z is aimed away from the camera.
func _aim_aura_at_camera(force: bool = false) -> void:
	if _powerup_aura == null or not is_instance_valid(_powerup_aura):
		return
	if not is_inside_tree():
		return
	if _powerup_camera == null or not is_instance_valid(_powerup_camera):
		_powerup_camera = get_viewport().get_camera_3d()
	if _powerup_camera == null:
		return
	var aura_pos := _powerup_aura.global_position
	var camera_pos := _powerup_camera.global_position
	if not force and _powerup_aim_valid \
			and aura_pos.is_equal_approx(_powerup_aim_from) \
			and camera_pos.is_equal_approx(_powerup_aim_at):
		return
	var to_camera := camera_pos - aura_pos
	if to_camera.length_squared() < 0.000001:
		return
	_powerup_aim_from = aura_pos
	_powerup_aim_at = camera_pos
	_powerup_aim_valid = true
	_powerup_aura.look_at(aura_pos - to_camera, Vector3.UP)

# HUD API: describes the running timed power-up, or an empty dictionary when none.
func get_active_power_up() -> Dictionary:
	if _active_power_up_mode == LocalPickup.PowerUpMode.NONE or _active_power_up_remaining <= 0.0:
		return NO_ACTIVE_POWER_UP
	return {
		"label": LocalPickup.POWER_UP_LABELS.get(_active_power_up_mode, ""),
		"color": LocalPickup.POWER_UP_COLORS.get(_active_power_up_mode, Color.WHITE),
		"remaining": _active_power_up_remaining,
		"duration": _active_power_up_duration,
	}

# Shows the carried power-up (if any) on the HUD Action button. `duration` tells
# the HUD how long the held pickup's effect would run, so it can draw the
# countdown ring as a full "ready" ring while the pickup is carried.
func _update_hud_power_up() -> void:
	var buttons := _find_buttons_hud()
	if buttons == null or not buttons.has_method("show_power_up"):
		return
	var label := ""
	var color: Color = Color.WHITE
	var duration := 0.0
	if held_power_up_mode != LocalPickup.PowerUpMode.NONE:
		if _is_objective_item_mode(held_power_up_mode):
			# Objective items (chicken / lootbox) are carried, never used: the
			# Action button is a plain white DROP, with no effect ring.
			label = "DROP"
			color = Color.WHITE
			duration = 0.0
		else:
			if held_local_pickup != null and is_instance_valid(held_local_pickup) and held_local_pickup.has_method("power_up_label"):
				label = str(held_local_pickup.call("power_up_label"))
				color = held_local_pickup.call("power_up_color")
			else:
				label = LocalPickup.POWER_UP_LABELS.get(held_power_up_mode, "")
				color = LocalPickup.POWER_UP_COLORS.get(held_power_up_mode, Color.WHITE)
			duration = _timed_duration_for(held_power_up_mode)
	buttons.call("show_power_up", label, color, duration)

# How long the given power-up's effect runs once used, or 0 for pickups with no
# timed effect (they are consumed without a countdown).
func _timed_duration_for(mode: int) -> float:
	match mode:
		LocalPickup.PowerUpMode.SPEED_BURST:
			return SPEED_BURST_DURATION
		LocalPickup.PowerUpMode.TWIN:
			return TWIN_DURATION
		LocalPickup.PowerUpMode.SMOKE_GRENADE:
			return SMOKE_DURATION
		LocalPickup.PowerUpMode.MEGA_LEAP:
			return MEGA_LEAP_DURATION
		LocalPickup.PowerUpMode.HOOK:
			return HOOK_DURATION
	return 0.0


func _maybe_grant_random_powerup_on_reveal() -> void:
	if not is_local:
		return
	# Defence in depth: the input handler already checks this, but the grant is
	# the one place that hands out a free power-up, so it must never run without
	# a fresh mainnet verdict for the current account in a CHOG room.
	if not _chog_can_activate():
		return
	if _active_power_up_mode != LocalPickup.PowerUpMode.NONE and _active_power_up_remaining > 0.0:
		return
	if held_power_up_mode != LocalPickup.PowerUpMode.NONE:
		return
	var pool: Array = [
		LocalPickup.PowerUpMode.SPEED_BURST,
		LocalPickup.PowerUpMode.TWIN,
		LocalPickup.PowerUpMode.SMOKE_GRENADE,
		LocalPickup.PowerUpMode.HOOK,
		LocalPickup.PowerUpMode.MEGA_LEAP,
	]
	if pool.is_empty():
		return
	pool.shuffle()
	var chosen: int = pool[0]
	held_power_up_mode = chosen
	_update_hud_power_up()

# ---------------------------------------------------------------------------
# CHOG Genesis gate
#
# The backend verdict is the only authority. The client starts in UNKNOWN (the
# input is denied), reads the verdict asynchronously, and re-reads it when the
# TTL lapses or the authenticated account changes. Nothing here trusts a URL
# flag, a room name alone, or a locally-set boolean.
# ---------------------------------------------------------------------------

## Deferred from _ready: `root` and `is_local` are assigned by PlayerManager
## right after add_child(), so they are only reliable on the next idle frame.
func _init_chog_gate() -> void:
	if not is_local:
		return
	var auth = get_node_or_null("/root/AuthManager")
	if auth != null:
		if auth.has_signal("logged_out") and not auth.logged_out.is_connected(_on_chog_session_changed):
			auth.logged_out.connect(_on_chog_session_changed)
		if auth.has_signal("login_completed") and not auth.login_completed.is_connected(_on_chog_login_completed):
			auth.login_completed.connect(_on_chog_login_completed)
		if auth.has_signal("session_refreshed") and not auth.session_refreshed.is_connected(_on_chog_login_completed):
			auth.session_refreshed.connect(_on_chog_login_completed)
	_chog_eligibility.reset()
	_chog_next_check_at_ms = 0
	_chog_gate_poll = CHOG_GATE_POLL_INTERVAL
	_refresh_chog_eligibility(true)

func _on_chog_session_changed(_reason: String) -> void:
	_invalidate_chog_eligibility()

func _on_chog_login_completed(_state: Variant) -> void:
	_invalidate_chog_eligibility()

func _invalidate_chog_eligibility() -> void:
	_chog_eligibility.reset()
	_chog_next_check_at_ms = 0
	# An in-flight request is not cancelled (HTTPRequest has no cancel); its
	# response is discarded by the identity check in _run_chog_ownership_check,
	# and the poll retries for the new account once it lands.
	_refresh_chog_eligibility(true)

## The only predicate the CHOG input and the reveal grant use.
func _chog_can_activate() -> bool:
	if _dev_cheat_unlocked:
		return true
	return _chog_eligibility.can_activate(
		_is_chog_room(),
		_chog_identity_key(),
		Time.get_ticks_msec()
	)

func _is_chog_room() -> bool:
	if root == null:
		return false
	var match_id := str(root.get("local_match_id")).strip_edges()
	return match_id == ChogEligibility.CHOG_ROOM_ID

## Stable key for "which authenticated account produced the cached verdict".
## Native sessions use the verified wallet; the web build has no wallet address
## in the client, so it fingerprints the short-lived Privy token instead. Either
## way a changed account changes the key and invalidates the old result.
func _chog_identity_key() -> String:
	var auth = get_node_or_null("/root/AuthManager")
	if auth != null and auth.is_authenticated():
		var wallet := str(auth.get_wallet_address()).strip_edges().to_lower()
		if wallet != "":
			return "won:%s" % wallet
	var token := _chog_web_privy_token()
	if token != "":
		return "privy:%s" % token.sha256_text()
	return ""

func _chog_web_privy_token() -> String:
	if not OS.has_feature("web"):
		return ""
	var raw: Variant = JavaScriptBridge.eval(
		"sessionStorage.getItem('%s') || ''" % CHOG_WEB_TOKEN_KEY
	)
	if typeof(raw) != TYPE_STRING:
		return ""
	return str(raw).strip_edges()

## Starts a check only when one is actually due. Never called per frame: the
## poll runs every CHOG_GATE_POLL_INTERVAL seconds and the TTL/retry gates keep
## the request rate low. A pending request always leaves the input denied.
func _refresh_chog_eligibility(force: bool = false) -> void:
	if not is_local:
		return
	if not _is_chog_room():
		# Outside a CHOG room no verdict may authorise the input, and none may
		# survive into the next CHOG room.
		_chog_eligibility.reset()
		return
	if _chog_check_in_flight:
		return
	var identity_key := _chog_identity_key()
	if identity_key == "":
		_chog_eligibility.reset()
		return
	var now := Time.get_ticks_msec()
	if now < _chog_next_check_at_ms:
		return
	if not force and not _chog_eligibility.needs_check(identity_key, now):
		return
	_chog_check_in_flight = true
	_chog_check_identity = identity_key
	@warning_ignore("missing_await")
	_run_chog_ownership_check(identity_key)

## Coroutine: asks the backend about the authenticated wallet and stores the
## verdict. A response for an account that is no longer current is discarded.
func _run_chog_ownership_check(identity_key: String) -> void:
	var response := await _request_chog_ownership()
	var now := Time.get_ticks_msec()
	if _chog_check_identity == identity_key:
		_chog_check_in_flight = false
	var current := _chog_identity_key()
	if identity_key == "" or current != identity_key:
		_chog_eligibility.reset()
		_chog_next_check_at_ms = 0
		_refresh_chog_eligibility(true)
		return
	var status := int(response.get("__status", 0))
	var has_nft: bool = response.get("has_chog_nft") == true
	_chog_eligibility.resolve(status, has_nft, identity_key, now)
	if status != 200:
		# Timeout, rate limit, expired token, RPC failure: stay in ERROR and
		# retry later. Never fall back to a previous positive result.
		_chog_next_check_at_ms = now + CHOG_OWNERSHIP_RETRY_MS
	else:
		_chog_next_check_at_ms = 0

## The request itself. Native uses the WON session through AuthManager; the web
## build presents the Privy access token the React /play hand-off stored in
## sessionStorage. No token is ever placed in the URL or logged.
func _request_chog_ownership() -> Dictionary:
	if not is_inside_tree():
		return {"ok": false, "__status": 0}
	var auth = get_node_or_null("/root/AuthManager")
	if auth == null or auth.api == null:
		return {"ok": false, "__status": 0}
	var authenticated: bool = auth.is_authenticated()
	var extra_headers := PackedStringArray()
	if not authenticated:
		var token := _chog_web_privy_token()
		if token == "":
			return {"ok": false, "__status": 0}
		extra_headers.append("Authorization: Bearer %s" % token)
	return await auth.api.request(
		HTTPClient.METHOD_GET,
		CHOG_OWNERSHIP_PATH,
		null,
		authenticated,
		extra_headers
	)


# Finds the HUD node that owns the Action button (buttons.gd). Only scanned once.
func _find_buttons_hud() -> Node:
	if _cached_buttons_hud != null and is_instance_valid(_cached_buttons_hud):
		return _cached_buttons_hud
	_cached_buttons_hud = null
	var hud := get_tree().root.find_child("Hud", true, false)
	if hud == null:
		return null
	var holder := hud.find_child("buttons_holder", true, false)
	if holder == null:
		return null
	for child in holder.get_children():
		if child.has_method("show_power_up"):
			_cached_buttons_hud = child
			break
	return _cached_buttons_hud

# --- STORM ZONE ---
## The server shrinks the storm over the match. The damage zone is simulated
## here, so re-read the live centre/radius from the StormEye instead of trusting
## the values captured at spawn, or the damage boundary would stay at its
## starting size while the visible wall moved.
func _refresh_storm_zone() -> void:
	if _storm_eye == null or not is_instance_valid(_storm_eye):
		_storm_eye = get_tree().get_first_node_in_group("storm_eye")
	if _storm_eye == null:
		return
	if _storm_eye.has_method("get_storm_radius"):
		storm_radius = _storm_eye.get_storm_radius()
	if _storm_eye.has_method("get_storm_center"):
		storm_center = _storm_eye.get_storm_center()

# --- HEALTH SYSTEM ---
func take_damage(amount: float, source: Node = null) -> void:
	if _is_dead:
		return
	health = maxf(0.0, health - amount)
	_health_regen_timer = HEALTH_REGEN_DELAY
	
	# Flash the health bar on damage (cached reference from _ready; no per-hit tree search)
	if _cached_health_bar != null and not is_instance_valid(_cached_health_bar):
		_cached_health_bar = null
	if _cached_health_bar and _cached_health_bar.has_method("_on_damage_taken"):
		_cached_health_bar._on_damage_taken()
	
	if health <= 0.0:
		die()
	elif health <= MAX_HEALTH * HEALTH_CRITICAL_FRACTION:
		_start_critical_fall()

func _find_health_bar() -> Node:
	var hud := get_tree().root.find_child("Hud", true, false)
	if hud == null:
		return null
	return hud.find_child("HealthBar", true, false)

func die() -> void:
	if _is_dead:
		return
	_is_dead = true
	_respawn_timer = RESPAWN_DELAY
	
	# Disable movement and input
	velocity = Vector3.ZERO
	velocity_y = 0.0
	
	# Drop held items
	if _is_local_holding_chicken() or _is_local_holding_lootbox():
		_drop_object()
	if _is_local_holding_pickup():
		# An unused power-up stays where the player died (never recycled to a
		# random spot) and the player is stripped of it.
		_drop_power_up_at_death()
	
	# Burn the body away. The burn takes most of the respawn delay so the model
	# is gone before the player reappears at the spawn point.
	DeathDissolve.begin(self, RESPAWN_DELAY * 0.7)

	# Visual feedback - could add death animation here
	print("Player died! Respawning in ", RESPAWN_DELAY, "s...")

func respawn_at_spawn_point() -> void:
	if not _is_dead:
		return
	
	# Notify server of elimination (death) so it resets possession time.
	if root and root.has_method("send_client_event"):
		root.call("send_client_event", "eliminated", "Player eliminated", {})
	
	# Reset health
	health = MAX_HEALTH
	_health_regen_timer = 0.0
	_is_dead = false
	# Put the skin back before the player is visible again; the dissolve left the
	# model fully discarded.
	DeathDissolve.restore(self)
	
	# Reset stamina
	stamina = STAMINA_MAX
	_stamina_regen_timer = 0.0
	_stamina_throttled = false
	_stamina_held_empty = false
	
	# Reset movement state
	velocity = Vector3.ZERO
	velocity_y = 0.0
	_is_sliding = false
	_slide_timer = 0.0
	_jump_requested = false
	_double_jump_available = false
	_double_jump_used = false
	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0
	
	# Respawn at spawn point
	var spawn_pos: Vector3
	if root and root.has_method("get_local_spawn_position"):
		spawn_pos = root.get_local_spawn_position()
	else:
		# Search for myplayerswpanpoint marker in scene (PlayerManager export)
		var player_manager = get_tree().get_first_node_in_group("player_manager")
		if player_manager and player_manager.has_method("get_local_spawn_position"):
			spawn_pos = player_manager.get_local_spawn_position()
		else:
			spawn_pos = Vector3(0, 2, 0)
	
	global_position = spawn_pos
	_last_world_y = spawn_pos.y
	_airborne_start_y = spawn_pos.y
	_was_on_floor = true
	
	# Reset camera
	cam_rot_x = min_pitch
	cam_rot_y = deg_to_rad(90.0)
	_movement_pitch_ease_active = false
	_pitch_before_movement_ease = -1.0
	camera_distance_current = camera_distance
	_camera_base_target_prev = global_transform.origin + Vector3(0, 1.5, 0)
	_camera_base_target_curr = _camera_base_target_prev
	_camera_follow_target = _camera_base_target_curr
	_camera_look_target = _camera_follow_target
	
	# Reset animation
	_is_punching = false
	_punch_timer = 0.0
	_is_dying_fall = false
	_critical_fall_timer = 0.0
	current_animation = "idle"
	_play_anim("idle")
	
	# Notify server of new position (only if in gameplay with WebSocket)
	if root and root.has_method("send_xp_update"):  # PlayerManager has this method
		_send_state_to_server(true)
	_update_global_player_shader_pos(true)
	
	print("Player respawned at ", spawn_pos)

func _on_damage_taken() -> void:
	# Called by health bar for visual feedback
	pass

func is_dead() -> bool:
	return _is_dead

func get_health() -> float:
	return health

func get_max_health() -> float:
	return MAX_HEALTH

func _is_local_holding_chicken() -> bool:
	if not root or not root.has_method("is_local_player_holding_chicken"):
		return false
	return root.is_local_player_holding_chicken()

func _is_local_holding_lootbox() -> bool:
	if not root or not root.has_method("is_local_player_holding_lootbox"):
		return false
	return root.is_local_player_holding_lootbox()

var _spring_rv: Array = [0.0, 0.0]
var _spring_rv3: Array = [Vector3.ZERO, Vector3.ZERO]

func _spring_float(current: float, vel: float, target: float, sharpness: float, delta: float) -> Array:
	if absf(current - target) <= SPRING_SETTLE_EPSILON and absf(vel) <= SPRING_SETTLE_VELOCITY_EPSILON:
		_spring_rv[0] = target; _spring_rv[1] = 0.0
		return _spring_rv
	var omega := maxf(sharpness, 0.001)
	var x := current - target
	var exp_factor := exp(-omega * delta)
	var temp := (vel + omega * x) * delta
	var next_value := target + (x + temp) * exp_factor
	var next_velocity := (vel - omega * temp) * exp_factor
	if absf(next_value - target) <= SPRING_SETTLE_EPSILON and absf(next_velocity) <= SPRING_SETTLE_VELOCITY_EPSILON:
		_spring_rv[0] = target; _spring_rv[1] = 0.0
		return _spring_rv
	_spring_rv[0] = next_value; _spring_rv[1] = next_velocity
	return _spring_rv

func _spring_vec3(current: Vector3, vel: Vector3, target: Vector3, sharpness: float, delta: float) -> Array:
	var eps2 := SPRING_SETTLE_EPSILON * SPRING_SETTLE_EPSILON
	if current.distance_squared_to(target) <= eps2 and vel.length_squared() <= SPRING_SETTLE_VELOCITY_EPSILON * SPRING_SETTLE_VELOCITY_EPSILON:
		_spring_rv3[0] = target; _spring_rv3[1] = Vector3.ZERO
		return _spring_rv3
	var omega := maxf(sharpness, 0.001)
	var x := current - target
	var exp_factor := exp(-omega * delta)
	var temp := (vel + omega * x) * delta
	var next_value := target + (x + temp) * exp_factor
	var next_velocity := (vel - omega * temp) * exp_factor
	if next_value.distance_squared_to(target) <= eps2 and next_velocity.length_squared() <= SPRING_SETTLE_VELOCITY_EPSILON * SPRING_SETTLE_VELOCITY_EPSILON:
		_spring_rv3[0] = target; _spring_rv3[1] = Vector3.ZERO
		return _spring_rv3
	_spring_rv3[0] = next_value; _spring_rv3[1] = next_velocity
	return _spring_rv3

func _apply_bus_riding() -> void:
	if _bus_node != null and not is_instance_valid(_bus_node):
		_bus_node = null
	if _bus_node == null:
		# A failed "does this map have a bus?" lookup only needs retrying
		# occasionally; scanning the group every physics tick was pure waste on
		# maps that never spawn one.
		var now := Time.get_ticks_msec()
		if now < _bus_lookup_retry_at_msec:
			return
		_bus_lookup_retry_at_msec = now + BUS_LOOKUP_RETRY_MSEC
		_bus_node = get_tree().get_first_node_in_group("bus")
		if _bus_node:
			_bus_last_pos = _bus_node.global_position
	if _bus_node == null:
		return
	var bus_pos := _bus_node.global_position
	var bus_delta := bus_pos - _bus_last_pos
	_bus_last_pos = bus_pos
	var to_bus := global_position - bus_pos
	var on_bus: bool = abs(to_bus.y) < 10.0 and Vector2(to_bus.x, to_bus.z).length() < 35.0
	if _is_riding_bus:
		global_position += bus_delta
		if not on_bus: 
			_is_riding_bus = false
			_zoom_cap_override = -1.0
	elif on_bus:
		_is_riding_bus = true
		_zoom_cap_override = bus_zoom
		global_position += bus_delta

func _zoom_cap_base() -> float:
	return bus_zoom if _zoom_cap_override >= 0.0 else max_zoom

func _camera_base_target() -> Vector3:
	var height: float = 1.5 + (bus_camera_height_offset if _is_riding_bus else 0.0)
	return global_transform.origin + Vector3(0, height, 0)

func _apply_bus_camera_recenter(delta: float) -> void:
	if not _is_riding_bus or bus_camera_recenter_speed <= 0.0:
		return
	var to_target: Vector2 = bus_camera_look_target - Vector2(global_position.x, global_position.z)
	if to_target.length_squared() < 0.0001:
		return
	var target_yaw: float = atan2(-to_target.x, -to_target.y)
	cam_rot_y = lerp_angle(cam_rot_y, target_yaw, clampf(delta * bus_camera_recenter_speed, 0.0, 1.0))

func _spring_angle(current: float, vel: float, target: float, sharpness: float, delta: float) -> Array:
	var wrapped_target := current + angle_difference(current, target)
	return _spring_float(current, vel, wrapped_target, sharpness, delta)

func _handle_camera_gamepad(delta: float) -> void:
	var rx := Input.get_joy_axis(gamepad_index, JOY_AXIS_RIGHT_X)
	var ry := Input.get_joy_axis(gamepad_index, JOY_AXIS_RIGHT_Y)
	if abs(rx) > DEADZONE:
		cam_rot_y -= rx * 0.05 * delta * 60
	if abs(ry) > DEADZONE:
		cam_rot_x = clamp(cam_rot_x + ry * 0.05 * delta * 60, _effective_min_pitch(), max_pitch)

func _update_dive_level(delta: float) -> void:
	# Continuous "skydive" camera blend: 0 on the ground, ramping toward 1 while
	# the player is actually airborne and falling from altitude. Every downstream
	# value (zoom, follow stiffness, FOV) is lerped through this, so leaving the
	# bus and hitting the ground eases instead of snapping at a hard height.
	var dive_target: float = 0.0
	if not is_on_floor() and velocity_y < 0.0:
		var band := maxf(dive_ramp_high - dive_ramp_low, 0.001)
		dive_target = clampf((global_position.y - dive_ramp_low) / band, 0.0, 1.0)
	_dive_level = move_toward(_dive_level, dive_target, delta * dive_ramp_speed)

func _update_camera_zoom(delta: float) -> void:
	_apply_bus_camera_recenter(delta)
	_update_dive_level(delta)
	var movement_allowed := _is_movement_allowed()
	var base_zoom_cap: float = _zoom_cap_base()
	var dive_zoom_cap: float = base_zoom_cap * 2.0
	# Running left/right/back drifts the player toward the near edge of the frame. A short spring
	# on the axis keeps the pull-back from stepping, which is what read as screen shake.
	var raw_retreat: float = 0.0
	if _dive_level <= 0.01 and not _is_riding_bus and current_animation != "falling":
		raw_retreat = camera_retreat_axis
	var retreat_result := _spring_float(_camera_retreat_smooth, _camera_retreat_velocity, raw_retreat, RETREAT_ZOOM_SMOOTHNESS, delta)
	_camera_retreat_smooth = retreat_result[0]
	_camera_retreat_velocity = retreat_result[1]
	var retreat_boost: float = _camera_retreat_smooth * move_zoom_out
	var zoom_ceiling: float = maxf(max_zoom_ceiling, dive_zoom_cap + retreat_boost)
	var ground_zoom: float = lerp(min_zoom, base_zoom_cap, 0.5)
	var state_zoom: float = min_zoom
	if current_animation == "falling":
		# The dive camera: high above the ground the view pulls back to frame the
		# fall (dive_zoom_cap), blending into the tight min_zoom tuck as the
		# player approaches the ground instead of switching at a hard height.
		state_zoom = lerp(min_zoom, dive_zoom_cap, _dive_level)
	elif camera_is_airborne:
		state_zoom = base_zoom_cap
	elif camera_is_moving:
		state_zoom = ground_zoom + retreat_boost
	elif not movement_allowed and root and root.has_method("is_waiting_for_players") and root.is_waiting_for_players():
		state_zoom = base_zoom_cap
	var target_distance: float = clamp(state_zoom + camera_distance_bias, min_zoom, zoom_ceiling)
	if _is_riding_bus:
		target_distance = bus_zoom
	var distance_result := _spring_float(camera_distance_current, _camera_distance_velocity, target_distance, camera_smoothness, delta)
	camera_distance_current = distance_result[0]
	_camera_distance_velocity = distance_result[1]
	var altitude_zoom: float = clamp(global_transform.origin.y * altitude_zoom_factor, 0.0, zoom_ceiling - min_zoom)
	_effective_camera_distance = clamp(camera_distance_current + altitude_zoom, min_zoom, zoom_ceiling)
	_sin_cam_y = sin(cam_rot_y)
	_cos_cam_y = cos(cam_rot_y)
	_sin_cam_x = sin(cam_rot_x)
	_cos_cam_x = cos(cam_rot_x)

func _update_camera_collision_logic(delta: float) -> void:
	_camera_update_skip_frames += 1
	if _camera_update_skip_frames < 3:
		return
	_camera_update_skip_frames = 0
	var holding_chicken := _is_local_holding_chicken()
	var above_12 := global_position.y > 12.0
	var target_pos: Vector3 = _camera_follow_target
	var cam_offset: Vector3 = Vector3(_sin_cam_y * _cos_cam_x, _sin_cam_x, _cos_cam_y * _cos_cam_x) * _effective_camera_distance
	var desired_pos: Vector3 = target_pos + cam_offset
	if above_12:
		_camera_collision_hold_timer = 0.0
		_camera_collision_distance = move_toward(_camera_collision_distance, _effective_camera_distance, delta * CAMERA_COLLISION_RECOVERY_SPEED * 8.0)
	else:
		var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		_camera_ray_query.from = target_pos
		_camera_ray_query.to = desired_pos
		if not _camera_ray_layer_set:
			_camera_ray_query.collision_mask = 1
			_camera_ray_layer_set = true
		if _camera_ray_exclude.is_empty():
			_camera_ray_exclude.append(get_rid())
		if holding_chicken:
			var chicken_node: RigidBody3D = _get_cached_chicken_node()
			if chicken_node and _camera_ray_exclude.size() == 1:
				_camera_ray_exclude.append(chicken_node.get_rid())
		elif _camera_ray_exclude.size() > 1:
			_camera_ray_exclude.resize(1)
		_camera_ray_query.exclude = _camera_ray_exclude
		var hit: Dictionary = space_state.intersect_ray(_camera_ray_query)
		var target_collision_distance := _effective_camera_distance
		if hit and hit.has("position"):
			var hit_distance := target_pos.distance_to(hit.position)
			target_collision_distance = maxf(0.05, hit_distance - CAMERA_COLLISION_MARGIN)
			_camera_collision_hold_timer = CAMERA_COLLISION_HOLD_TIME
			if _camera_collision_distance <= 0.0:
				_camera_collision_distance = target_collision_distance
			else:
				_camera_collision_distance = minf(_camera_collision_distance, target_collision_distance)
		else:
			_camera_collision_hold_timer = maxf(0.0, _camera_collision_hold_timer - delta * 2.0)
			if _camera_collision_hold_timer <= 0.0:
				_camera_collision_distance = move_toward(_camera_collision_distance, target_collision_distance, delta * 2.0 * CAMERA_COLLISION_RECOVERY_SPEED)

# While moving, the pitch floor is raised to the movement pitch mark — the point
# min_pitch + movement_pitch_raise_fraction (1/4 by default) of the pitch range —
# so the camera can never be dragged into the lowest band where its near plane
# clips the floor and the player sees under the map. With min_pitch = -0.4 and
# max_pitch = 1.0, the floor goes from -0.4 (stationary) to -0.05 (moving), which
# is essentially level. The raise is temporary: when the player stops moving, the
# pitch eases back down to the angle they had before the raise kicked in. Manual
# input still wins while pitching above the mark; only below the mark does
# movement nudge the camera up. Set low_pitch_ease_speed to 0 to disable.
func _movement_pitch_mark() -> float:
	var pitch_range := maxf(max_pitch - min_pitch, 0.001)
	return min_pitch + clampf(movement_pitch_raise_fraction, 0.0, 1.0) * pitch_range

# The lowest pitch the orbital controls may currently reach: the plain min_pitch
# while the player stands still, the raised movement mark while they are moving
# (or still unwinding a raise). Every input path clamps through this instead of
# min_pitch directly, so a drag or a flick cannot push the camera back under the
# floor mid-run.
func _effective_min_pitch() -> float:
	if camera_is_moving or _movement_pitch_ease_active:
		return maxf(min_pitch, _movement_pitch_mark())
	return min_pitch

func _apply_movement_pitch_ease(delta: float) -> void:
	if low_pitch_ease_speed <= 0.0:
		return
	# Only do the pitch-mark maths while moving. When idle with no lingering
	# raise left to unwind, this is just a couple of cheap boolean checks.
	if camera_is_moving:
		var movement_pitch_mark := _movement_pitch_mark()
		if not _movement_pitch_ease_active:
			_movement_pitch_ease_active = true
			_pitch_before_movement_ease = cam_rot_x
		if cam_rot_x < movement_pitch_mark:
			cam_rot_x = lerpf(cam_rot_x, movement_pitch_mark, minf(1.0, delta * low_pitch_ease_speed))
	elif _movement_pitch_ease_active and _pitch_before_movement_ease >= 0.0:
		# Not moving: ease back toward the pre-movement pitch every frame until
		# reached, then drop the temporary raise state.
		var restore_target: float = _pitch_before_movement_ease
		if absf(cam_rot_x - restore_target) <= 0.001:
			_movement_pitch_ease_active = false
			_pitch_before_movement_ease = -1.0
		else:
			cam_rot_x = lerpf(cam_rot_x, restore_target, minf(1.0, delta * low_pitch_ease_speed))

func _update_camera_visual(delta: float) -> void:
	var interp := Engine.get_physics_interpolation_fraction()
	var raw_target_pos: Vector3 = _camera_base_target_prev.lerp(_camera_base_target_curr, interp)
	# While skydiving the camera has to track a fast-falling player, so it runs
	# several times stiffer than on the ground. Blended through _dive_level
	# instead of a hard height switch, so the approach to the ground eases off.
	var follow_omega := lerpf(lerpf(follow_sharpness, follow_sharpness_retreat, _camera_retreat_smooth), 80.0, _dive_level)
	var pos_smoothness := lerpf(camera_smoothness, camera_smoothness * 5.0, _dive_level)
	var look_smoothness := lerpf(camera_smoothness * 0.85, camera_smoothness * 0.85 * 5.0, _dive_level)
	var follow_result := _spring_vec3(_camera_follow_target, _camera_follow_velocity, raw_target_pos, follow_omega, delta)
	_camera_follow_target = follow_result[0]
	_camera_follow_velocity = follow_result[1]
	var target_pos: Vector3 = _camera_follow_target
	_apply_movement_pitch_ease(delta)
	cam_rot_x = clamp(cam_rot_x, _effective_min_pitch(), max_pitch)
	_sin_cam_x = sin(cam_rot_x)
	_cos_cam_x = cos(cam_rot_x)
	var cam_offset: Vector3 = Vector3(_sin_cam_y * _cos_cam_x, _sin_cam_x, _cos_cam_y * _cos_cam_x) 
	var camera_direction := cam_offset 
	if camera_direction.length_squared() < 0.0001:
		camera_direction = Vector3.FORWARD
	var desired_pos := target_pos + camera_direction * _camera_collision_distance
	if _landing_bob_timer > 0.0:
		var landing_progress: float = 1.0 - (_landing_bob_timer / LANDING_BOB_DURATION)
		var landing_t := 1.0 - landing_progress
		var landing_offset: float = _landing_bob_strength * 0.18 * landing_t * landing_t
		desired_pos.y -= landing_offset
	var position_result := _spring_vec3(camera.global_position, _camera_position_velocity, desired_pos, pos_smoothness, delta)
	camera.global_position = position_result[0]
	_camera_position_velocity = position_result[1]
	var look_result := _spring_vec3(_camera_look_target, _camera_look_target_velocity, target_pos, look_smoothness, delta)
	_camera_look_target = look_result[0]
	_camera_look_target_velocity = look_result[1]
	camera.look_at(_camera_look_target, Vector3.UP)
	# Dive FOV: falling fast from altitude widens the view (speed-scaled); a hard
	# landing adds a short FOV punch that decays back to the base FOV.
	_landing_fov_kick = maxf(0.0, _landing_fov_kick - delta * LANDING_FOV_DECAY)
	var fall_speed := -minf(velocity_y, 0.0)
	var speed_fraction := clampf(fall_speed / maxf(dive_fov_ref_speed, 0.001), 0.0, 1.0)
	var dive_fov := dive_fov_boost_max * _dive_level * speed_fraction
	var target_fov: float = fov + dive_fov + _landing_fov_kick
	var fov_result := _spring_float(camera.fov, _camera_fov_velocity, target_fov, camera_smoothness * 1.1, delta)
	camera.fov = fov_result[0]
	_camera_fov_velocity = fov_result[1]
	var dist_to_target: float = maxf(camera_distance_current, 0.001)
	var v_fov_rad: float = deg_to_rad(camera.fov)
	if _cached_viewport_size == Vector2.ZERO:
		_cached_viewport_size = get_viewport().get_visible_rect().size
	var aspect: float = _cached_viewport_size.x / max(1.0, _cached_viewport_size.y)
	var half_height: float = dist_to_target * tan(v_fov_rad / 2.0)
	var half_width: float = half_height * aspect
	camera.h_offset = -camera_screen_offset.x * half_width
	camera.v_offset = -camera_screen_offset.y * half_height

func _quantize_pos(value: float) -> int:
	return int(round(value * POS_SCALE))

func _quantize_rot(value: float) -> int:
	return int(round(value * ROT_SCALE))

var _payload: Dictionary = {}
var _chicken_payload: Dictionary = {}
var _lootbox_payload: Dictionary = {}

func _send_state_to_server(_force_send := false) -> void:
	# Only send if root is PlayerManager with active WebSocket
	if not root or not root.has_method("send_xp_update"):
		return
	if root.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		root._last_server_position = global_transform.origin
		var qx := _quantize_pos(global_transform.origin.x)
		var qy := _quantize_pos(global_transform.origin.y)
		var qz := _quantize_pos(global_transform.origin.z)
		var qrot := _quantize_rot(mesh.rotation.y)
		var anim_id := int(ANIM_NAME_TO_ID.get(current_animation, 0))
		_payload["type"] = "update_state"
		_payload["qx"] = qx
		_payload["qy"] = qy
		_payload["qz"] = qz
		_payload["qrot"] = qrot
		_payload["anim_id"] = anim_id
		_payload["slide"] = 1 if _is_sliding else 0
		_payload["skin"] = str(root.local_skin_name) if root != null else ""
		_payload.erase("chicken")
		_payload.erase("lootbox")
		root.ws.send(MsgPack.pack(_payload))

func _update_global_player_shader_pos(force: bool = false) -> void:
	if not is_local:
		return
	if not force and global_position.distance_squared_to(_cached_shader_player_pos) < 0.0001:
		return
	_cached_shader_player_pos = global_position
	RenderingServer.global_shader_parameter_set("player_pos", global_position)

func set_animation_state(new_state: String):
	if is_local: return
	if new_state == current_animation: return
	current_animation = new_state
	_play_anim(new_state)

# True while a non-locomotion animation is playing that must not be interrupted
# (HOOK punch or the near-death fall): the player stops and the run/idle states
# stay suppressed until it completes.
func _is_action_locked() -> bool:
	return _is_punching or _is_dying_fall

func _handle_animations(move_dir: Vector3) -> void:
	if not is_local: return
	if _is_climbing:
		# Attached to a surface: the climb loop owns the pose. The climb branch in
		# _physics_process normally sets this; the guard covers any other caller.
		_set_anim("climb")
		return
	if _is_punching:
		# Hold the punch animation; the run/idle logic below must not override it.
		_set_anim("hook")
		return
	if _is_dying_fall:
		# Nearly dead: hold the fall animation for its full length.
		_set_anim("fall")
		return
	if not _is_movement_allowed():
		_set_anim("idle")
		_was_on_floor = is_on_floor()
		_last_world_y = global_position.y
		return
	if _is_sliding:
		_set_anim("runningslide")
		_last_world_y = global_position.y
		return
	var on_floor_now := is_on_floor()
	var current_y := global_position.y
	if on_floor_now:
		_was_on_floor = true
		_airborne_start_y = current_y
		_last_world_y = current_y
		var horizontal_speed_sq = velocity.x * velocity.x + velocity.z * velocity.z
		# Test movement intent, not just raw speed. A throttled player moves at a fraction
		# of SPEED and can fall under the 0.5 m/s this speed test requires, which would drop
		# them to idle mid-stride while they are clearly driving the character. Input keeps
		# the run loop alive at any throttle strength; the speed test is kept so residual
		# momentum still animates after input is released.
		if move_dir.length_squared() > 0.05 or horizontal_speed_sq > 0.25:
			_set_anim("running")
		else:
			_set_anim("idle")
		return
	if _was_on_floor:
		_airborne_start_y = current_y
	_was_on_floor = false
	var y_delta := current_y - _last_world_y
	var height_from_takeoff := current_y - _airborne_start_y
	var vertical_distance_from_takeoff: float = absf(height_from_takeoff)
	var is_falling: bool = ((velocity_y <= 0.0 and height_from_takeoff < 0.0 and vertical_distance_from_takeoff >= max_jump_height) or (y_delta < -0.01 and height_from_takeoff < 0.0 and vertical_distance_from_takeoff >= max_jump_height))
	if is_falling:
		_set_anim("falling")
	else:
		_set_anim("runningjump")
	_last_world_y = current_y

func _is_movement_allowed() -> bool:
	if root and root.has_method("is_match_running"):
		return root.is_match_running()
	return true

## Jump velocity for the local player, weakened while the stamina throttle is on so a
## tired player also jumps shorter. Read before the stamina block runs, so this uses
## last frame's throttle state, which is a one-frame lag and not worth reordering for.
func _current_jump_velocity() -> float:
	return JUMP_VELOCITY * (STAMINA_EMPTY_JUMP_MULT if _stamina_throttled else 1.0)

func _get_cached_chicken_node() -> RigidBody3D:
	if _cached_chicken_node != null and is_instance_valid(_cached_chicken_node):
		return _cached_chicken_node
	if root and root.has_method("get_chicken_node"):
		var chicken = root.get_chicken_node()
		if chicken is RigidBody3D:
			_cached_chicken_node = chicken
			return _cached_chicken_node
	return null

func _get_cached_lootbox_node() -> RigidBody3D:
	if _cached_lootbox_node != null and is_instance_valid(_cached_lootbox_node):
		return _cached_lootbox_node
	if root and root.has_method("get_lootbox_node"):
		var lootbox = root.get_lootbox_node()
		if lootbox is RigidBody3D:
			_cached_lootbox_node = lootbox
			return _cached_lootbox_node
	return null

func _set_anim(anim_name: String) -> void:
	if current_animation == anim_name:
		return
	current_animation = anim_name
	# Mark it so the next _physics_process sends it right away (see the send block).
	_anim_state_dirty = true
	_play_anim(anim_name)

func _play_anim(anim_name: String) -> void:
	if anim_state_machine:
		anim_state_machine.travel(anim_name)

func _start_slide(move_direction: Vector3, slide_from_touch: bool = false) -> void:
	_is_sliding = true
	_slide_timer = SLIDE_DURATION
	_slide_direction = move_direction.normalized()
	_slide_camera_restore_active = slide_from_touch
	current_animation = "runningslide"
	_anim_state_dirty = true
	_play_anim("runningslide")

func _stop_slide() -> void:
	_is_sliding = false
	_slide_timer = 0.0
	_slide_direction = Vector3.ZERO
	_slide_camera_restore_active = false

func _refresh_touch_joystick() -> void:
	touch_joystick = get_tree().get_first_node_in_group("touch_joystick")

func _connect_joystick_signals() -> void:
	if touch_joystick == null:
		_refresh_touch_joystick()
	if touch_joystick and not touch_joystick.is_connected("camera_dragged", _on_joystick_camera_drag):
		touch_joystick.connect("camera_dragged", _on_joystick_camera_drag)

func _on_joystick_camera_drag(relative: Vector2) -> void:
	if not is_local:
		return
	joystick_orbit_pending += relative

func _apply_touch_orbit() -> void:
	var has_touch_orbit := touch_orbit_pending != Vector2.ZERO
	var has_joystick_orbit := joystick_orbit_pending != Vector2.ZERO
	if not has_touch_orbit and not has_joystick_orbit:
		return
	var touch_delta: Vector2 = touch_orbit_pending
	var joystick_delta: Vector2 = joystick_orbit_pending
	touch_orbit_pending = Vector2.ZERO
	joystick_orbit_pending = Vector2.ZERO
	if has_touch_orbit:
		touch_delta.x = clamp(touch_delta.x, -64.0, 64.0)
		touch_delta.y = clamp(touch_delta.y, -64.0, 64.0)
		cam_rot_y -= touch_delta.x * touch_orbit_sensitivity
		cam_rot_x = clamp(cam_rot_x + touch_delta.y * touch_orbit_sensitivity, _effective_min_pitch(), max_pitch)
	if has_joystick_orbit:
		joystick_delta.x = clamp(joystick_delta.x, -joystick_orbit_clamp, joystick_orbit_clamp)
		joystick_delta.y = clamp(joystick_delta.y, -joystick_orbit_clamp, joystick_orbit_clamp)
		if joystick_orbit_invert_x: joystick_delta.x = -joystick_delta.x
		if joystick_orbit_invert_y: joystick_delta.y = -joystick_delta.y
		cam_rot_y -= joystick_delta.x * joystick_orbit_sensitivity
		cam_rot_x = clamp(cam_rot_x + joystick_delta.y * joystick_orbit_sensitivity, _effective_min_pitch(), max_pitch)

func _apply_slide_camera_restore(delta: float) -> void:
	if not _slide_camera_restore_active:
		return
	var restore_weight: float = clampf(delta * 6.0, 0.0, 1.0)
	cam_rot_y = lerp_angle(cam_rot_y, _touch_slide_start_cam_rot_y, restore_weight)
	cam_rot_x = clampf(lerpf(cam_rot_x, _touch_slide_start_cam_rot_x, restore_weight), _effective_min_pitch(), max_pitch)
	if absf(angle_difference(cam_rot_y, _touch_slide_start_cam_rot_y)) < 0.001 and absf(cam_rot_x - _touch_slide_start_cam_rot_x) < 0.001:
		_slide_camera_restore_active = false

func disable_character_shadows() -> void:
	for child in find_children("*", "MeshInstance3D", true):
		child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _spawn_flash() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var cam = viewport.get_camera_3d()
	if cam == null:
		return
	var old_canvas = cam.get_node_or_null("_spawn_flash_canvas")
	if old_canvas:
		old_canvas.queue_free()
	var overlay := ColorRect.new()
	overlay.color = Color(1, 1, 1, 1)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.size = viewport.get_visible_rect().size
	var canvas := CanvasLayer.new()
	canvas.name = "_spawn_flash_canvas"
	canvas.layer = 100
	canvas.add_child(overlay)
	cam.add_child(canvas)
	var tween := create_tween()
	tween.tween_property(overlay, "color:a", 0.0, 0.35)
	tween.tween_callback(canvas.queue_free)
