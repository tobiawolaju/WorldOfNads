# Headless selftest for the ECS-lite layer (scripts/ecs) and the first migrated
# component (StaminaComponent).
#   Godot_v4.8-beta1_win64_console.exe --headless --path godot --script res://tools/_test_ecs.gd
# Prints FAIL lines for every broken expectation and exits non-zero if any fail.
extends SceneTree

var failures := 0


class ProbeComponent extends Component:
	var ticks: int = 0
	var attaches: int = 0
	var detaches: int = 0

	func _on_attach() -> void:
		attaches += 1

	func _on_detach() -> void:
		detaches += 1

	func tick(_delta: float) -> void:
		ticks += 1


class OtherComponent extends Component:
	pass


class CountSystem extends System:
	var seen: int = 0

	func _init() -> void:
		super(ProbeComponent)

	func run(tree: SceneTree, _delta: float) -> void:
		seen += entities(tree).size()


func _initialize() -> void:
	var host := Node.new()
	host.name = "EntityA"
	root.add_child(host)
	var other_host := Node.new()
	other_host.name = "EntityB"
	root.add_child(other_host)

	var probe := ProbeComponent.new()
	Entity.attach(host, probe)
	_check("a component attaches", probe.attaches == 1 and probe.entity == host)
	_check("get_component finds it by class", Entity.get_component(host, ProbeComponent) == probe)
	_check("has_component is true", Entity.has_component(host, ProbeComponent))
	_check("a different class is missing", Entity.get_component(host, OtherComponent) == null)

	Entity.tick(host, 0.016)
	Entity.tick(host, 0.016)
	_check("tick reaches the component", probe.ticks == 2)
	_check("tick does not leak to other entities", Entity.has_component(other_host, ProbeComponent) == false)

	# Queries see exactly the entities that own the component.
	var other_probe := ProbeComponent.new()
	Entity.attach(other_host, other_probe)
	var matches := Entity.query(self, ProbeComponent)
	_check("query sees both entities", matches.size() == 2 and matches.has(host) and matches.has(other_host))

	var counter := CountSystem.new()
	counter.run(self, 0.016)
	_check("a system runs over the queried entities", counter.seen == 2)
	Entity.detach_component(other_host, ProbeComponent)
	counter.run(self, 0.016)
	_check("detaching shrinks the query", counter.seen == 3)

	# Replacing a component detaches the previous instance instead of leaking it.
	var replacement := ProbeComponent.new()
	Entity.attach(host, replacement)
	_check("replacing detaches the old component", probe.entity == null and probe.detaches == 1)
	_check("the replacement is the live one", Entity.get_component(host, ProbeComponent) == replacement)
	_check("the replacement ticks", _tick_once(host) and replacement.ticks == 1)

	Entity.detach_component(host, ProbeComponent)
	_check("detach clears the entity reference", replacement.entity == null and replacement.detaches == 1)
	_check("detached components are no longer found", Entity.has_component(host, ProbeComponent) == false)

	# --- StaminaComponent -----------------------------------------------------
	var stamina := StaminaComponent.new()
	_check("a fresh pool is full", is_equal_approx(stamina.stamina, StaminaComponent.MAX))
	_check("a fresh pool is not throttled", not stamina.is_throttled())
	_check("fresh multipliers are neutral", stamina.speed_multiplier() == 1.0 and stamina.jump_multiplier() == 1.0)

	_drive(stamina, 1.0, true, true, 1.0)
	_check("carrying while moving drains", absf(stamina.stamina - (StaminaComponent.MAX - StaminaComponent.DRAIN_RATE)) < 0.6)

	var light := StaminaComponent.new()
	_drive(light, 1.0, true, true, StaminaComponent.DRAIN_MIN_MULT)
	_check("light input drains less", light.stamina > stamina.stamina)

	var idle := StaminaComponent.new()
	idle.stamina = 50.0
	_drive(idle, 1.0, false, false, 0.0)
	_check("standing still regenerates", idle.stamina > 50.0)
	var moving := StaminaComponent.new()
	moving.stamina = 50.0
	_drive(moving, 1.0, true, false, 1.0)
	_check("idle regen is faster than moving regen", idle.stamina > moving.stamina)

	var empty := StaminaComponent.new()
	_drive(empty, 7.2, true, true, 1.0)
	_check("the pool stops at zero", is_zero_approx(empty.stamina))
	_check("empty latches the throttle", empty.is_throttled())
	_check("the throttle slows movement", is_equal_approx(empty.speed_multiplier(), StaminaComponent.EMPTY_SPEED_MULT))
	_check("the throttle shortens jumps", is_equal_approx(empty.jump_multiplier(), StaminaComponent.EMPTY_JUMP_MULT))

	empty.reset()
	_check("reset refills the pool", is_equal_approx(empty.stamina, StaminaComponent.MAX))
	_check("reset clears the throttle", not empty.is_throttled() and empty.speed_multiplier() == 1.0)

	# --- HealthComponent ------------------------------------------------------
	var hp := HealthComponent.new()
	_check("a fresh health pool is full", is_equal_approx(hp.health, HealthComponent.MAX))
	_check("a fresh health pool is not critical", not hp.is_critical())
	_check("a fresh health pool is not depleted", not hp.is_depleted())
	hp.apply_damage(30.0)
	_check("damage reduces health", is_equal_approx(hp.health, 70.0))
	_check("damage resets regen delay", is_equal_approx(hp.regen_timer, HealthComponent.REGEN_DELAY))
	_drive_health(hp, 3.1, false)
	_check("health regenerates after delay", hp.health > 70.0)
	var dead_hp := HealthComponent.new()
	dead_hp.dead = true
	dead_hp.health = 50.0
	dead_hp.regen_timer = 0.0
	_drive_health(dead_hp, 2.0, true)
	_check("dead health does not regenerate", is_equal_approx(dead_hp.health, 50.0))
	var crit := HealthComponent.new()
	crit.apply_damage(96.0)
	_check("low health is critical", crit.is_critical())
	crit.apply_damage(10.0)
	_check("empty health is depleted", crit.is_depleted())
	crit.reset()
	_check("reset refills health", is_equal_approx(crit.health, HealthComponent.MAX) and is_equal_approx(crit.regen_timer, 0.0) and not crit.dead)

	print("ecs selftest: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


## Ticks `seconds` of a 60 fps loop with the given intent.
func _drive(stamina: StaminaComponent, seconds: float, moving: bool, holding: bool, effort: float) -> void:
	stamina.moving = moving
	stamina.holding = holding
	stamina.effort = effort
	var steps := int(round(seconds * 60.0))
	for _i in steps:
		stamina.tick(1.0 / 60.0)


func _tick_once(host: Node) -> bool:
	Entity.tick(host, 0.016)
	return true


## Ticks `seconds` of a 60 fps loop with the given dead intent.
func _drive_health(hp: HealthComponent, seconds: float, dead: bool) -> void:
	hp.dead = dead
	var steps := int(round(seconds * 60.0))
	for _i in steps:
		hp.tick(1.0 / 60.0)


func _check(what: String, condition: bool) -> void:
	if condition:
		print("PASS  ", what)
		return
	failures += 1
	print("FAIL  ", what)
