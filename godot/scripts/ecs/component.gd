class_name Component
extends RefCounted
## Base class for ECS-lite components.
##
## A component is plain data + behaviour attached to a Node "entity" (the
## player, a pickup, a vehicle). It is deliberately *not* a SceneTree node:
## attaching one costs no allocation beyond the object itself, it does not add a
## per-frame `_process` callback, and the entity decides where in its own update
## the component ticks. Queries go through [Entity].

## The node this component is attached to. Set by [Entity.attach]; null while
## detached.
var entity: Node = null


## Called by [Entity.attach]. Prefer overriding `_on_attach` so the entity
## reference is always set before component code runs.
func attach(host: Node) -> void:
	entity = host
	_on_attach()


## Called by [Entity.detach] and when a component of the same class replaces
## this one.
func detach() -> void:
	if entity == null:
		return
	_on_detach()
	entity = null


## Per-frame update, driven by [Entity.tick]. `delta` is in seconds.
func tick(_delta: float) -> void:
	pass


func _on_attach() -> void:
	pass


func _on_detach() -> void:
	pass
