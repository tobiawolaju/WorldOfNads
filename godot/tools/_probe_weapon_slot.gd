# One-off probe: can a single BoneAttachment3D swap bones at runtime, and what
# are the authored back-slot transforms in skin.tscn?
extends SceneTree

const HAND_BONE := "mixamorig_LeftHand"
const BACK_BONE := "mixamorig_Spine1"
const NAMES := ["sword", "ak47", "glock", "Knife", "rpg"]


func _initialize() -> void:
	_run()


func _run() -> void:
	var scene := (load("res://scenes/skin.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var skel := scene.get_node_or_null("Skeleton3D") as Skeleton3D
	var att := scene.get_node_or_null("Skeleton3D/BoneAttachment3D") as BoneAttachment3D
	var back := scene.get_node_or_null("Skeleton3D/BackBoneAttachment3D") as Node3D
	print("skel=", skel, " att=", att, " back=", back)
	if att == null or skel == null:
		quit()
		return
	print("att bone=", att.bone_name, " idx=", att.bone_idx)
	print("hand idx=", skel.find_bone(HAND_BONE), " spine idx=", skel.find_bone(BACK_BONE))
	var skel_x := skel.global_transform
	print("att global        = ", att.global_position)
	print("hand bone world   = ", (skel_x * skel.get_bone_global_pose(skel.find_bone(HAND_BONE))).origin)
	att.bone_name = BACK_BONE
	await process_frame
	await process_frame
	print("after switch bone=", att.bone_name, " idx=", att.bone_idx, " global=", att.global_position)
	print("spine bone world  = ", (skel_x * skel.get_bone_global_pose(skel.find_bone(BACK_BONE))).origin)
	att.bone_name = HAND_BONE
	await process_frame
	await process_frame
	print("back to hand bone=", att.bone_name, " idx=", att.bone_idx, " global=", att.global_position)
	print("hand bone world   = ", (skel_x * skel.get_bone_global_pose(skel.find_bone(HAND_BONE))).origin)
	for n in NAMES:
		var back_node := back.get_node_or_null(n) as Node3D
		var hand_node := att.get_node_or_null(n) as Node3D
		if back_node != null:
			print("BACK ", n, " = ", var_to_str(back_node.transform), " vis=", back_node.visible)
		if hand_node != null:
			print("HAND ", n, " = ", var_to_str(hand_node.transform), " vis=", hand_node.visible)
	print("back children: ", back.get_children().map(func(c): return String(c.name)))
	quit()
