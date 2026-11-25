# ECS-lite layer

The game does not use a data-oriented ECS. Godot already gives every gameplay
object identity, transform, collision and a lifecycle, so the **node is the
entity**. This folder adds the two pieces Godot lacks: a typed component bag and
a way to query entities by component.

## The three pieces

| Piece | File | What it is |
| --- | --- | --- |
| `Entity` | `entity.gd` | Static helpers. Stores components in the node's metadata. |
| `Component` | `component.gd` | `RefCounted` base class: `_on_attach`, `_on_detach`, `tick(delta)`. |
| `System` | `system.gd` | `RefCounted` base class for logic that spans entities. |

Components are **not** nodes. Attaching one allocates a single object, adds no
`_process` callback, and cannot outlive its host: the component dictionary is
metadata on the entity, so it is freed with the node.

## Rules of thumb

- **Per-entity state and behaviour** → component (`StaminaComponent`).
- **Interaction between entities, or entity ↔ world** → `System` + `Entity.query`.
- **Presentation, physics, animation, input** → stay on the node. Do not move
  `CharacterBody3D` movement or `AnimationTree` driving into components; Godot's
  node model is already the right tool there.
- One component per class per entity. If an entity needs two of something, put
  an array inside one component.
- Cache the component reference on the entity (`var _stamina: StaminaComponent`)
  instead of calling `Entity.get_component` every frame.

## Example

`scripts/player/components/stamina_component.gd` is the reference migration:

```gdscript
# player.gd
var _stamina: StaminaComponent = null

func _ready() -> void:
    _stamina = StaminaComponent.new()
    Entity.attach(self, _stamina)

func _physics_process(delta: float) -> void:
    _stamina.moving = ...
    _stamina.holding = ...
    _stamina.effort = input_strength
    Entity.tick(self, delta)
    var speed := SPEED * _stamina.speed_multiplier()
```

`player.stamina` remains a property proxy so the HUD and legacy code keep
working. That is the pattern for every migration: move the rule into the
component, keep the old public surface as a thin delegate, then delete call
sites in a separate change.

## Testing

`tools/_test_ecs.gd` covers attach/detach/replace, tick order, queries, systems
and the stamina rules:

```powershell
Godot_v4.8-beta1_win64_console.exe --headless --path godot --script res://tools/_test_ecs.gd
```
