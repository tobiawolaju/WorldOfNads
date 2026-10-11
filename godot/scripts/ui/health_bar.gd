extends ProgressBar
## Health bar that shows when health is not full.
## Fades in when damaged, fades out when fully healed.

const FADE_TIME: float = 0.3
const LOW_HEALTH_THRESHOLD: float = 0.3  # 30%
const FLASH_SPEED: float = 10.0
const DAMAGE_FLASH_TIME: float = 0.15

var _cached_player: Node = null
var _alpha: float = 0.0
var _last_health: float = -1.0
var _last_value: float = -1.0
var _damage_flash_timer: float = 0.0
var _is_flashing_low: bool = false
var _last_fill_color: Color = Color(-1.0, -1.0, -1.0, -1.0)  # Sentinel = "not applied yet"

func _ready() -> void:
	modulate.a = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	if _cached_player == null or not is_instance_valid(_cached_player):
		_cached_player = get_tree().get_first_node_in_group("local_player")

	if _cached_player == null:
		_set_alpha(0.0, delta)
		return

	var current_health: float = 0.0
	var max_health: float = 100.0
	
	if _cached_player.has_method("get_health"):
		current_health = _cached_player.get_health()
	if _cached_player.has_method("get_max_health"):
		max_health = _cached_player.get_max_health()
	
	# Update bar value — only when the fraction actually changed. Writing value
	# every frame dirties the control for a redraw even when health is static,
	# which is the common case.
	var ratio := (current_health / max_health) * 100.0
	if not is_equal_approx(ratio, _last_value):
		_last_value = ratio
		value = ratio
		max_value = 100.0

	# Detect damage taken (health decreased)
	if _last_health >= 0.0 and current_health < _last_health:
		_damage_flash_timer = DAMAGE_FLASH_TIME
	
	_last_health = current_health

	# Low health pulsing
	var health_pct := current_health / max_health
	_is_flashing_low = health_pct <= LOW_HEALTH_THRESHOLD and current_health > 0.0

	# Show when not at full health
	var show_bar := current_health < max_health

	# Fast path: health unchanged, fade settled, nothing flashing — skip the
	# per-frame modulate / fill-color writes entirely (each one dirties the control).
	var target_alpha := 1.0 if show_bar else 0.0
	if _damage_flash_timer <= 0.0 and not _is_flashing_low \
			and is_equal_approx(_alpha, target_alpha) \
			and is_equal_approx((current_health / max_health) * 100.0, _last_value):
		return

	# Handle damage flash (white flash)
	if _damage_flash_timer > 0.0:
		_damage_flash_timer = maxf(0.0, _damage_flash_timer - delta)
		var flash_intensity := _damage_flash_timer / DAMAGE_FLASH_TIME
		modulate = Color(1.0, 1.0, 1.0, _alpha * flash_intensity + _alpha * (1.0 - flash_intensity))
		# Keep the fill color red during damage flash
		_set_fill_color(Color(1.0, 0.2, 0.2, 1.0))
	elif _is_flashing_low:
		# Pulse red when low health
		var pulse := (sin(Time.get_ticks_msec() * 0.01 * FLASH_SPEED) * 0.5 + 0.5)
		_set_fill_color(Color(1.0, lerpf(0.2, 0.6, pulse), 0.2, 1.0))
		modulate.a = _alpha
	else:
		# Normal health color (green)
		_set_fill_color(Color(0.2, 0.8, 0.2, 1.0))
		modulate.a = _alpha

	# Fade in/out based on whether health is full
	_set_alpha(1.0 if show_bar else 0.0, delta)

func _set_fill_color(color: Color) -> void:
	# Only rebuild the theme override when the color actually changes.
	# add_theme_color_override() every frame is much more expensive than this check.
	if color == _last_fill_color:
		return
	_last_fill_color = color
	add_theme_color_override("fill_color", color)

func _set_alpha(target: float, delta: float) -> void:
	_alpha = move_toward(_alpha, target, delta / FADE_TIME)
	if _damage_flash_timer <= 0.0 and not _is_flashing_low:
		modulate.a = _alpha
