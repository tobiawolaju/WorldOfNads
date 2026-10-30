# Headless selftest for where a carried weapon is drawn.
#   Godot_v4.8-beta1_win64_console.exe --headless --path godot --script res://tools/_test_weapon_carry.gd
# Prints FAIL lines for every broken expectation and exits non-zero if any fail.
#
# Why this exists: skin.tscn ships the same five weapon models twice - once on
# Skeleton3D/BoneAttachment3D (left hand) and once on Skeleton3D/BackBoneAttachment3D
# (spine). A carried weapon has to ride the back, and only the swing/shot clip may
# move it to the hand for its own duration. The back slot also authors a knife and
# an RPG as visible, so an empty rig would otherwise show two weapons nobody owns.
extends SceneTree

const WEAPONS: Array[String] = ["sword", "ak47", "glock", "Knife", "rpg"]

var failures := 0

func _initialize() -> void:
	var player := (load("res://scenes/skin.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(player)
	await process_frame
	await process_frame

	var hand := player.get_node_or_null("Skeleton3D/BoneAttachment3D") as Node3D
	var back := player.get_node_or_null("Skeleton3D/BackBoneAttachment3D") as Node3D
	_check("the rig ships a hand slot", hand != null)
	_check("the rig ships a back slot", back != null)
	if hand == null or back == null:
		print("weapon carry selftest: %d failure(s)" % failures)
		quit(1)
		return

	# The scene authors a knife and an RPG visible on the back, so the empty rig
	# has to be cleared explicitly instead of trusting the authored state.
	_check("a fresh player hides the hand slot", not hand.visible)
	_check("a fresh player hides the back slot", not back.visible)
	for slot_name in WEAPONS:
		_check("a fresh player hides %s in hand" % slot_name, not (hand.get_node_or_null(slot_name) as Node3D).visible)
		_check("a fresh player hides %s on back" % slot_name, not (back.get_node_or_null(slot_name) as Node3D).visible)

	# Picking a weapon up puts it on the back, not in the hand.
	player._set_weapon_visual(LocalPickup2.WeaponKind.SWORD)
	_check("a carried weapon shows the back slot", back.visible)
	_check("a carried weapon shows its own back mesh", (back.get_node_or_null("sword") as Node3D).visible)
	_check("a carried weapon hides the other back meshes", not (back.get_node_or_null("ak47") as Node3D).visible)
	_check("a carried weapon keeps the hand slot hidden", not hand.visible)
	_check("a carried weapon keeps the hand mesh hidden", not (hand.get_node_or_null("sword") as Node3D).visible)

	# Firing draws it: back copy off, hand copy on, for as long as the clip runs.
	player.held_weapon_kind = LocalPickup2.WeaponKind.SWORD
	player._set_weapon_drawn(true)
	_check("firing hides the back slot", not back.visible)
	_check("firing hides the back mesh", not (back.get_node_or_null("sword") as Node3D).visible)
	_check("firing shows the hand slot", hand.visible)
	_check("firing shows the held mesh in hand", (hand.get_node_or_null("sword") as Node3D).visible)
	_check("firing hides the other hand meshes", not (hand.get_node_or_null("ak47") as Node3D).visible)
	_check("firing keeps the shield out of the hand", not (hand.get_node_or_null("shield") as Node3D).visible)

	# The clip is over: the weapon is carried again.
	player._set_weapon_drawn(false)
	_check("the clip holsters the weapon on the back", back.visible and (back.get_node_or_null("sword") as Node3D).visible)
	_check("the clip empties the hand again", not hand.visible)

	# Losing the weapon (last charge, death) clears both slots.
	player.held_weapon_kind = LocalPickup2.WeaponKind.NONE
	player._set_weapon_visual(LocalPickup2.WeaponKind.NONE)
	_check("losing the weapon hides the back slot", not back.visible)
	_check("losing the weapon hides the hand slot", not hand.visible)

	# Another player's weapon comes from the server, so it is always carried.
	player.show_remote_weapon(LocalPickup2.WeaponKind.AK47)
	_check("show_remote_weapon carries the ak47", back.visible and (back.get_node_or_null("ak47") as Node3D).visible)
	_check("a remote weapon stays out of the hand", not hand.visible)

	# A RemotePlayer copy has to clear the same authored meshes, and it never
	# draws its weapon into the hand: the server only says what it carries.
	var remote := _make_remote_avatar()
	root.add_child(remote)
	await process_frame
	_check("a fresh remote hides the back slot", _visible_weapon_in(remote, "Skeleton3D/BackBoneAttachment3D") == "")
	_check("a fresh remote hides the hand slot", _visible_weapon_in(remote, "Skeleton3D/BoneAttachment3D") == "")
	remote.call("show_remote_weapon", LocalPickup2.WeaponKind.RPG)
	_check("a remote weapon rides the back", _visible_weapon_in(remote, "Skeleton3D/BackBoneAttachment3D") == "rpg")
	_check("a remote weapon never enters the hand", _visible_weapon_in(remote, "Skeleton3D/BoneAttachment3D") == "")
	# A skin swap replaces the skeleton, so the authored meshes come back with it.
	remote.call("refresh_mesh_lod")
	_check("a skin swap keeps the remote weapon", _visible_weapon_in(remote, "Skeleton3D/BackBoneAttachment3D") == "rpg")
	remote.call("show_remote_weapon", LocalPickup2.WeaponKind.NONE)
	_check("a disarmed remote clears the back", _visible_weapon_in(remote, "Skeleton3D/BackBoneAttachment3D") == "")

	print("weapon carry selftest: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


## The same conversion PlayerManager runs for every other player: the skin
## scene's visuals under a RemotePlayer node, with the body dropped.
func _make_remote_avatar() -> Node3D:
	var source := (load("res://scenes/skin.tscn") as PackedScene).instantiate()
	var remote := (load("res://scripts/player/RemotePlayer.gd") as GDScript).new() as Node3D
	remote.name = "RemoteAvatar"
	for child in source.get_children():
		source.remove_child(child)
		child.owner = null
		remote.add_child(child)
	source.free()
	return remote


func _visible_weapon_in(rig: Node, slot_path: String) -> String:
	var slot := rig.get_node_or_null(slot_path) as Node3D
	if slot == null or not slot.visible:
		return ""
	var found := ""
	for slot_name in WEAPONS:
		var node := slot.get_node_or_null(slot_name) as Node3D
		if node != null and node.visible:
			if found != "":
				return ""
			found = slot_name
	return found


func _check(name: String, condition: bool) -> void:
	if condition:
		print("PASS  ", name)
	else:
		failures += 1
		print("FAIL  ", name)
