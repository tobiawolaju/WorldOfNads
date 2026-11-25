class_name Entity
extends RefCounted
## ECS-lite facade over ordinary Godot nodes.
##
## Godot already owns every gameplay object's identity, transform and lifecycle,
## so in this project the entity *is* the node. Entity only adds a component bag
## stored in the node's metadata:
##
##   * components are RefCounted objects, so they are freed with their host;
##   * there is no global registry to clean up between matches or rooms;
##   * two components of the same class cannot share one entity (address them by
##     class), which keeps queries unambiguous.
##
## Usage in an entity script:
## [codeblock]
## var _stamina: StaminaComponent = null
##
## func _ready() -> void:
##     _stamina = StaminaComponent.new()
##     Entity.attach(self, _stamina)
##
## func _physics_process(delta: float) -> void:
##     _stamina.moving = ...
##     Entity.tick(self, delta)
## [/codeblock]
##
## Cross-entity logic uses [method query] and lives in a [System], not here.

const COMPONENTS_META := &"_ecs_components"


## Attaches `component` to `host` and returns it. Attaching another component of
## the same class detaches the previous one, so a re-initialised entity does not
## silently keep stale state.
static func attach(host: Node, component: Component) -> Component:
	if host == null or component == null:
		return null
	var key := _key_of(component)
	if key == &"":
		push_error("Entity.attach: could not resolve the component class")
		return null
	var components := _components(host)
	var previous: Component = components.get(key, null)
	if previous == component:
		return component
	if previous != null:
		previous.detach()
	components[key] = component
	component.attach(host)
	return component


## Returns the component of `type` (a GDScript class such as
## `StaminaComponent`), or null. Cache the result in the entity instead of
## looking it up every frame.
static func get_component(host: Node, type: GDScript) -> Component:
	if host == null:
		return null
	return _components(host).get(_key_of_class(type), null)


static func has_component(host: Node, type: GDScript) -> bool:
	return get_component(host, type) != null


## Detaches and forgets the component of `type`. The component's `_on_detach`
## runs before its entity reference is cleared.
static func detach_component(host: Node, type: GDScript) -> void:
	if host == null:
		return
	var components := _components(host)
	var key := _key_of_class(type)
	var component: Component = components.get(key, null)
	if component == null:
		return
	components.erase(key)
	component.detach()


## Ticks every attached component in attachment order.
static func tick(host: Node, delta: float) -> void:
	if host == null:
		return
	for component in _components(host).values():
		if component != null:
			component.tick(delta)


## Every entity in `tree` that currently owns a component of `type`. The walk
## visits every node (metadata can sit on any node), so call it from a [System]
## on its schedule, not from a per-frame hot path.
static func query(tree: SceneTree, type: GDScript) -> Array:
	var found: Array = []
	if tree == null:
		return found
	var key := _key_of_class(type)
	if key == &"":
		return found
	_collect(tree.root, key, found)
	return found


static func _collect(node: Node, key: StringName, found: Array) -> void:
	if node.has_meta(COMPONENTS_META):
		var components: Dictionary = node.get_meta(COMPONENTS_META)
		if components.has(key):
			found.append(node)
	for child in node.get_children():
		_collect(child, key, found)


static func _components(host: Node) -> Dictionary:
	if not host.has_meta(COMPONENTS_META):
		host.set_meta(COMPONENTS_META, {})
	var components: Variant = host.get_meta(COMPONENTS_META)
	if typeof(components) != TYPE_DICTIONARY:
		components = {}
		host.set_meta(COMPONENTS_META, components)
	return components


static func _key_of(component: Component) -> StringName:
	return _key_of_class(component.get_script() as GDScript)


static func _key_of_class(type: GDScript) -> StringName:
	if type == null:
		return &""
	var global_name := type.get_global_name()
	if global_name != "":
		return StringName(global_name)
	# Inner classes have no global name. Their script object is stable for the
	# lifetime of the class and unique per class, unlike resource_path (which is
	# shared by every inner class in the same file).
	return StringName(str(type.get_instance_id()))
