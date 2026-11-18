extends Node3D
class_name FX3D

## Per-world host for 3D effects (particles + world sounds).
##
## Placement is code-driven and idempotent:
##
##     FX3D_SCRIPT.ensure(self, FX3D_SCENE)   # lobby.gd::_ready()
##     FX3D_SCRIPT.ensure(null, FX3D_SCENE)   # PlayerManager / player.gd
##
## so no scene has to remember to instance it, and calling it twice returns the
## same node instead of stacking duplicates. Callers pass their own preload of
## scenes/fx3d.tscn because the exporter only follows real resource dependencies;
## a path-only reference would be dropped from the pck.
##
## Ownership split:
##   * FX3D owns particle instances, their pooling and their per-id caps.
##   * The Audio autoload owns every AudioStreamPlayer and the global voice
##     budget; FX3D.sound()/attach() are facades over it, so there is only one
##     place that decides which 3D voices may run.
##
## Effects live under the "Effects" child, which keeps them out of the host's
## transform and makes them easy to inspect at runtime.

const SCENE_PATH: String = "res://scenes/fx3d.tscn"
const GROUP: StringName = &"fx3d"
## Stamped on the owning scene root so ensure() can find the host even on the
## frame where its add_child() is still deferred, and so a second call from a
## different script cannot stack a duplicate.
const META_KEY: StringName = &"fx3d_host"
## World position parked on an effect that was spawned before the host entered
## the tree (ensure() defers add_child while a scene root is still setting up).
const POS_META: StringName = &"fx3d_world_pos"
# Preloaded rather than referenced by class name so this script parses even
# before the editor has refreshed its global class cache.
const FX_LIBRARY := preload("res://scripts/fx/fx_library.gd")

static var _instance = null

var _effects_root: Node3D = null
var _scenes: Dictionary = {}
var _active: Dictionary = {}
var _audio: Node = null


func _ready() -> void:
	add_to_group(GROUP)
	_ensure_effects_root()
	_apply_pending_positions()
	_instance = self


func _ensure_effects_root() -> void:
	_effects_root = get_node_or_null("Effects") as Node3D
	if _effects_root == null:
		_effects_root = Node3D.new()
		_effects_root.name = "Effects"
		add_child(_effects_root)


# Applies positions parked while the host was out of the tree. Runs once on
# _ready(), by which point every queued effect is a real Node3D in the world.
func _apply_pending_positions() -> void:
	if _effects_root == null:
		return
	for child in _effects_root.get_children():
		if not child.has_meta(POS_META):
			continue
		var world_position: Vector3 = child.get_meta(POS_META)
		child.remove_meta(POS_META)
		if child is Node3D:
			(child as Node3D).global_position = world_position


func _exit_tree() -> void:
	if _instance == self:
		_instance = null
	var parent := get_parent()
	if parent != null and parent.has_meta(META_KEY) and parent.get_meta(META_KEY) == self:
		parent.remove_meta(META_KEY)


## Returns the world's FX host, creating it under `host` (or the current scene)
## when this is the first call. Safe to call from any node, any number of times.
static func ensure(host: Node = null, packed: PackedScene = null) -> FX3D:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var parent: Node = host
	if parent == null:
		parent = tree.current_scene
	if parent == null:
		return null

	# The scene root remembers its host: covers the frame where add_child() is
	# deferred, and stops a second caller from stacking a second host.
	if parent.has_meta(META_KEY):
		var known = parent.get_meta(META_KEY)
		if is_instance_valid(known):
			_instance = known
			return known
		parent.remove_meta(META_KEY)

	# A scene saved with the node already in it must not get another copy.
	for child in parent.get_children():
		if child is FX3D:
			parent.set_meta(META_KEY, child)
			_instance = child
			return child

	# Callers pass their own preload (lobby.gd / PlayerManager.gd / player.gd) so
	# the exporter tracks this scene. The load() fallback keeps headless tools and
	# the editor working when no preload was threaded through.
	if packed == null:
		packed = load(SCENE_PATH) as PackedScene
	if packed == null:
		push_error("FX3D: cannot load %s" % SCENE_PATH)
		return null
	var created := packed.instantiate() as FX3D
	if created == null:
		push_error("FX3D: %s is not an FX3D scene" % SCENE_PATH)
		return null

	parent.set_meta(META_KEY, created)
	# _ready() runs while the parent is still setting up its children (the scene
	# root's _ready, or PlayerManager's), and add_child() fails hard in that
	# window. Deferring is the documented fix; the meta above covers the gap.
	if parent.is_node_ready():
		parent.add_child(created)
	else:
		parent.call_deferred("add_child", created)
	_instance = created
	return created


## Spawns effect `id` at a world position. Returns the instance (or null when the
## id is unknown / its scene failed to load) so callers can keep a handle.
func spawn(id: String, world_position: Vector3, opts: Dictionary = {}) -> Node3D:
	var def: Dictionary = FX_LIBRARY.get_effect(id)
	if def.is_empty():
		push_warning("FX3D: unknown effect '%s'" % id)
		return null
	var packed := _scene_for(id, def)
	if packed == null:
		return null

	var effect := packed.instantiate() as Node3D
	if effect == null:
		push_error("FX3D: effect '%s' is not a Node3D" % id)
		return null

	var radius := float(opts.get("radius", def.get("radius", 0.0)))
	var spawn_seed := int(opts.get("seed", 0))
	# Most effect scenes build their material in _ready(), so setup() has to run
	# before the node enters the tree (same contract smoke_cloud.gd documents).
	if effect.has_method("setup"):
		effect.call("setup", radius, spawn_seed)
	if bool(opts.get("warmup", false)) and effect.has_method("set_warmup"):
		effect.call("set_warmup")

	if _effects_root == null:
		_ensure_effects_root()
	_effects_root.add_child(effect)
	if is_inside_tree():
		effect.global_position = world_position
	else:
		# FX3D itself is waiting for its deferred add_child(); global_position is
		# meaningless outside the tree, so park the world position and apply it
		# in _ready() once the host and its children are in the world.
		effect.set_meta(POS_META, world_position)
	_track(id, effect, int(def.get("cap", 0)))

	var sound_id := String(def.get("sound", ""))
	if sound_id != "":
		sound(sound_id, world_position, opts)
	return effect


## Plays a 3D sound id at a world position. No-op until the Audio autoload is
## installed, so scenes can call this before the audio system lands.
func sound(id: String, world_position: Vector3, opts: Dictionary = {}) -> void:
	var audio := _audio_node()
	if audio != null and audio.has_method("play_at"):
		audio.call("play_at", id, world_position, opts)


## Starts a loop that follows `node` (vehicle engine, bee, held chicken) and
## returns the player so the caller can stop or re-tune it.
func attach(id: String, node: Node3D, opts: Dictionary = {}) -> Node:
	var audio := _audio_node()
	if audio != null and audio.has_method("play_on"):
		return audio.call("play_on", id, node, opts)
	return null


## Turns a server `fx` event into an effect on this client. The server never
## touches a node: it broadcasts `{fx, x, y, z, seed}` and every client rebuilds
## the same effect from it.
func spawn_from_event(event: Dictionary) -> Node3D:
	var meta: Dictionary = {}
	if typeof(event.get("meta", null)) == TYPE_DICTIONARY:
		meta = event["meta"]
	var id := String(meta.get("fx", event.get("fx", "")))
	if id == "" or id == "fx":
		return null
	var position := Vector3(
		float(meta.get("x", 0.0)),
		float(meta.get("y", 0.0)),
		float(meta.get("z", 0.0)))
	var opts := {"seed": int(meta.get("seed", 0))}
	if meta.has("radius"):
		opts["radius"] = float(meta["radius"])
	return spawn(id, position, opts)


func _scene_for(id: String, def: Dictionary) -> PackedScene:
	if _scenes.has(id):
		return _scenes[id] as PackedScene
	var entry = def.get("scene", null)
	if entry is PackedScene:
		_scenes[id] = entry
		return entry
	# Path strings are accepted for quick experiments, but they are invisible to
	# the exporter; ship effects as preloads in FXLibrary.
	var path := String(entry) if entry is String else ""
	if path == "":
		push_warning("FX3D: effect '%s' has no scene" % id)
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("FX3D: cannot load effect scene %s" % path)
		return null
	_scenes[id] = packed
	return packed


# Keeps at most `cap` live instances of one id, recycling the oldest. Entries are
# pruned lazily because effect scenes free themselves (smoke_cloud.gd does).
func _track(id: String, effect: Node3D, cap: int) -> void:
	var alive: Array = []
	for existing in _active.get(id, []):
		if is_instance_valid(existing) and not existing.is_queued_for_deletion():
			alive.append(existing)
	if cap > 0:
		while alive.size() >= cap:
			var oldest = alive.pop_front()
			if is_instance_valid(oldest):
				oldest.queue_free()
	alive.append(effect)
	_active[id] = alive


func _audio_node() -> Node:
	if _audio != null and is_instance_valid(_audio):
		return _audio
	_audio = get_node_or_null("/root/Audio")
	return _audio
