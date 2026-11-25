class_name StaminaComponent
extends Component
## Stamina pool, drain/regen cycle and the "empty" throttle latch.
##
## The entity reports three facts each physics frame — moving, holding an item,
## and how hard the stick is pushed — then ticks the component. Everything else
## (rates, the 5 s held-empty lockout, the speed/jump penalties) stays here.
##
## `player.gd` keeps a `stamina` property as a thin proxy so the HUD and older
## call sites keep reading one value without knowing about components.

const MAX: float = 100.0
## Full bar drains in ~7 s of sprinting while carrying something.
const DRAIN_RATE: float = MAX / 7.0
## Light analog input drains at this fraction of the full rate.
const DRAIN_MIN_MULT: float = 0.25
const REGEN_DELAY: float = 1.0
## Empty to full in ~8 s while still moving, half that standing still.
const REGEN_RATE: float = MAX / 8.0
const REGEN_IDLE_MULT: float = 2.0
## After hitting zero while still holding input, drain stays locked for this
## long so tapping the stick cannot instantly resume full-speed carrying.
const HELD_PENALTY: float = 5.0
const EMPTY_SPEED_MULT: float = 0.4
const EMPTY_JUMP_MULT: float = 0.6
## The throttle lifts only after the bar refills past this fraction (or the
## player stops), so creeping does not silently restore full speed.
const RECOVERY_FRACTION: float = 0.25

var stamina: float = MAX

## Intent for the current frame, set by the entity before `tick`.
var moving: bool = false
var holding: bool = false
var effort: float = 1.0

var _regen_timer: float = 0.0
var _held_empty: bool = false
var _empty_timer: float = 0.0
var _throttled: bool = false


func tick(delta: float) -> void:
	# Releasing input breaks the held-empty lockout immediately.
	if _held_empty and not moving:
		_held_empty = false

	# Throttle latches on hitting zero and only lifts when the player stops
	# moving or refills past the recovery threshold. Resolved before the drain
	# below so the latch takes effect the same frame it is set.
	if stamina <= 0.0:
		_throttled = true
	elif not moving or stamina >= MAX * RECOVERY_FRACTION:
		_throttled = false
		# Recovery is done, so the re-drain lockout has served its purpose.
		# Clearing it here lets drain resume the moment the throttle lifts.
		_held_empty = false

	# Drain and regen are mutually exclusive: while genuinely draining, stamina
	# only falls. Any other situation regenerates instead, which is what lets a
	# player who has dropped the item refill again while they keep running.
	var draining := moving and holding and stamina > 0.0 and not _held_empty and not _throttled
	if draining:
		# Scale by how hard the player is actually pushing, so analog input has
		# a cost gradient. Keyboard/gamepad digital input reports 1.0.
		stamina = maxf(0.0, stamina - DRAIN_RATE * clampf(effort, DRAIN_MIN_MULT, 1.0) * delta)
		_regen_timer = REGEN_DELAY

	# Just hit zero — check if input is still held.
	if stamina <= 0.0 and moving and holding:
		_held_empty = true
		_empty_timer = HELD_PENALTY

	# Held-penalty countdown (ignores movement for 5 s).
	if _held_empty:
		_empty_timer = maxf(0.0, _empty_timer - delta)
		if _empty_timer <= 0.0:
			_held_empty = false

	# Regen runs whenever the player is not actively draining, moving or not,
	# so stamina can never get stuck at zero. Standing still doubles the rate.
	if not draining:
		_regen_timer = maxf(0.0, _regen_timer - delta)
		if _regen_timer <= 0.0:
			var rate := REGEN_RATE * (1.0 if moving else REGEN_IDLE_MULT)
			stamina = minf(MAX, stamina + rate * delta)


## Back to a fresh round: full bar, no throttle, no lockout.
func reset() -> void:
	stamina = MAX
	_regen_timer = 0.0
	_held_empty = false
	_empty_timer = 0.0
	_throttled = false


## Movement multiplier while exhausted: a tired player is slowed, not stopped.
func speed_multiplier() -> float:
	return EMPTY_SPEED_MULT if _throttled else 1.0


## Jump multiplier while exhausted, so a tired player also jumps shorter.
func jump_multiplier() -> float:
	return EMPTY_JUMP_MULT if _throttled else 1.0


func is_throttled() -> bool:
	return _throttled
