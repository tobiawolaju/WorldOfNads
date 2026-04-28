@tool
extends MultiMeshInstance3D

func _ready():
	if multimesh == null:
		return
	
	# Reset everything
	multimesh.instance_count = 0
	multimesh.instance_count = 1
	
	var t := Transform3D()
	t.basis = Basis().scaled(Vector3(0.1, 0.1, 0.1))
	t.origin = Vector3.ZERO
	
	multimesh.set_instance_transform(0, t)
