class_name HealthComponent
extends Component
## Health pool, damage/regen, and death threshold state.
##
## The entity sets `dead` before ticking so regen stays frozen while dead.
## `player.gd` keeps health/get_health/get_max_health/take_damage APIs as thin
## proxies/wrappers so HUD and older call sites keep working.

const MAX: float = 100.0
const REGEN_DELAY: float = 3.0
const REGEN_RATE: float = 15.0
## At or below this fraction the player is in the near-death critical range.
const CRITICAL_FRACTION: float = 0.05

var health: float = MAX
var regen_timer: float = 0.0
## Intent for the current frame, set by the entity before `tick`.
var dead: bool = false


func tick(delta: float) -> void:
	if dead:
		return
	regen_timer = maxf(0.0, regen_timer - delta)
	if regen_timer <= 0.0 and health < MAX:
		health = minf(MAX, health + REGEN_RATE * delta)


## Applies damage, resets the regen delay, and returns remaining health.
func apply_damage(amount: float) -> float:
	health = maxf(0.0, health - amount)
	regen_timer = REGEN_DELAY
	return health


func reset() -> void:
	health = MAX
	regen_timer = 0.0
	dead = false


func is_depleted() -> bool:
	return health <= 0.0


func is_critical() -> bool:
	return health > 0.0 and health <= MAX * CRITICAL_FRACTION
