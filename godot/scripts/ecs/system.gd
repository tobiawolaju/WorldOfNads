class_name System
extends RefCounted
## Cross-entity logic for the ECS-lite layer.
##
## A [Component] owns one entity's state; a System is stateless code that runs
## over every entity owning a given component. Subclass it, call `super()` with
## the component type, and drive it from whatever owns the schedule (a node's
## `_process`, the room tick, or a test):
## [codeblock]
## class StormDamageSystem extends System:
##     func _init() -> void:
##         super(HealthComponent)
##
##     func run(tree: SceneTree, delta: float) -> void:
##         for entity in entities(tree):
##             var health := Entity.get_component(entity, HealthComponent) as HealthComponent
##             health.damage(STORM_DPS * delta)
## [/codeblock]
##
## Keep per-entity updates in the component's `tick`; reach for a System only
## when two entities (or an entity and the world) interact.

var component_type: GDScript = null


func _init(type: GDScript = null) -> void:
	component_type = type


## Override. Called once per schedule step.
func run(_tree: SceneTree, _delta: float) -> void:
	pass


## Entities this system operates on. Resolution is done per call so a system
## never holds a stale list after a respawn or a room change.
func entities(tree: SceneTree) -> Array:
	return Entity.query(tree, component_type)
