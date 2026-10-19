# One-off probe (safe to delete): does BoneAttachment3D overwrite its own
# transform with the bone's pose at runtime, or do its children stay relative
# to the transform authored in the .tscn file?
#
#   Godot_v4.7-stable_win64_console.exe --headless --path godot --script res://tools/_probe_bone_attachment.gd
extends SceneTree

func _initialize() -> void:
	print("probe: started")
	var skel := Skeleton3D.new()
	skel.add_bone("B")
	skel.set_bone_rest(0, Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(1, 2, 3)))
	root.add_child(skel)

	var att := BoneAttachment3D.new()
	att.bone_name = "B"
	# Deliberately different from the bone pose so we can tell who wins.
	att.transform = Transform3D(Basis.IDENTITY, Vector3(9, 9, 9))
	skel.add_child(att)

	var child := Node3D.new()
	child.transform = Transform3D(Basis.IDENTITY, Vector3(0, 5, 0))
	att.add_child(child)

	await process_frame
	await process_frame

	var pose := skel.get_bone_global_pose(0)
	print("probe: bone global pose   = ", pose)
	print("probe: att.global (actual)= ", att.global_transform)
	print("probe: child.global pos   = ", child.global_position)
	var synced := skel.global_transform * pose
	print("probe: att.global if synced to bone = ", synced)
	var authored := skel.global_transform * Transform3D(Basis.IDENTITY, Vector3(9, 9, 9))
	print("probe: att.global if authored kept   = ", authored)
	quit()
