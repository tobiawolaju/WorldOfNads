class_name FXLibrary
extends RefCounted

## Catalog of world effects spawned through [FX3D].
##
## One entry per effect id. `scene` is instantiated on demand, `cap` is the
## maximum number of simultaneous instances for that id across the whole world
## (the oldest is recycled beyond it), `radius` is the default size passed to a
## scene's optional `setup(radius, seed)` method, and `sound` is the audio id
## [FX3D] asks the Audio autoload to play at the spawn position.
##
## Adding an effect: drop its scene under `scenes/fx/` (or reuse an existing
## one), add an entry here, then call `FX3D.spawn("id", position, opts)` from the
## gameplay code. No scene edits, no per-site instantiation.
##
## Scenes are held as preloads, not paths: Godot's exporter only follows real
## resource dependencies, so an effect referenced by a string would be silently
## missing from the pck (the same trap that removed assets/img/lobbybg earlier).

const EFFECTS := {
	"smoke": {
		"scene": preload("res://scenes/smoke_cloud.tscn"),
		# Per world now, not per player: four players dropping clouds at the old
		# 6-each cap would be 24 soft billboards overdrawing the web renderer.
		"cap": 8,
		"radius": 7.0,
		"sound": "",
	},
}


static func get_effect(id: String) -> Dictionary:
	return EFFECTS.get(id, {})
