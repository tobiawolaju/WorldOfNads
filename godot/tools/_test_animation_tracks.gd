# Headless selftest for the player rig's animation tracks.
#   Godot_v4.8-beta1_win64_console.exe --headless --path godot --script res://tools/_test_animation_tracks.gd
#
# The extra Mixamo AnimationPlayers in skin.tscn are imported from FBX files whose
# tracks keep the FBX armature path ("Armature/Skeleton3D:bone"). The rig in this
# scene has no Armature node - the skeleton sits at "Skeleton3D" - so every one of
# those tracks silently failed to resolve and the mixer logged a warning for each.
#
# This checks that every track of every AnimationPlayer in the scene points at a
# node that exists and, for bone tracks, a bone the skeleton actually has.
extends SceneTree

const SCENE_PATH := "res://scenes/skin.tscn"

var failures := 0


func _initialize() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_check("skin.tscn loads", packed != null)
	if packed == null:
		_finish()
		return

	var scene_root := packed.instantiate()
	var players := _animation_players(scene_root)
	_check("scene has animation players", players.size() > 0)

	var track_total := 0
	for player in players:
		for library_name in player.get_animation_library_list():
			var library: AnimationLibrary = player.get_animation_library(library_name)
			for animation_name in library.get_animation_list():
				var animation: Animation = library.get_animation(animation_name)
				for track in animation.get_track_count():
					track_total += 1
					_check_track(player, animation_name, animation, track)

	scene_root.free()
	_check("every player was scanned", players.size() == 8)
	_check("every track resolves", failures == 0)
	print("")
	print("%d players, %d tracks scanned" % [players.size(), track_total])
	_finish()


func _check_track(player: AnimationPlayer, animation_name: StringName, animation: Animation, track: int) -> void:
	var path := animation.track_get_path(track)
	var base: Node = player.get_node_or_null(player.root_node)
	if base == null:
		base = player.get_parent()
	var node: Node = base.get_node_or_null(NodePath(path.get_concatenated_names())) if base != null else null
	if node == null:
		failures += 1
		print("FAIL %s / %s: no node for %s" % [player.name, animation_name, path])
		return

	var bone := path.get_concatenated_subnames()
	if bone.is_empty():
		return
	if not (node is Skeleton3D):
		failures += 1
		print("FAIL %s / %s: %s is not a skeleton" % [player.name, animation_name, path])
		return
	if (node as Skeleton3D).find_bone(bone) == -1:
		failures += 1
		print("FAIL %s / %s: skeleton has no bone %s" % [player.name, animation_name, bone])


func _animation_players(node: Node) -> Array:
	var found: Array = []
	if node is AnimationPlayer:
		found.append(node)
	for child in node.get_children():
		found.append_array(_animation_players(child))
	return found


func _finish() -> void:
	print("")
	if failures == 0:
		print("all animation track checks passed")
	else:
		print("%d check(s) failed" % failures)
	quit(failures)


func _check(label: String, ok: bool) -> void:
	if ok:
		print("ok   ", label)
	else:
		failures += 1
		print("FAIL ", label)
