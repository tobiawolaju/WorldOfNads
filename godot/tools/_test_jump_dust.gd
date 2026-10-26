# Headless selftest for the jump/landing dust prefab.
#   Godot_v4.8-beta1_win64_console.exe --headless --path godot --script res://tools/_test_jump_dust.gd
# Prints FAIL lines for every broken expectation and exits non-zero if any fail.
extends SceneTree

var failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var packed := load("res://scenes/dust_burst.tscn") as PackedScene
	_check("prefab loads", packed != null)
	if packed == null:
		_finish()
		return

	# _ready() is where the burst builds its sprite, so the checks below only
	# mean anything after one frame has let the nodes enter the tree.
	var small := _burst(packed, 0.4)
	var big := _burst(packed, 2.0)
	await process_frame

	_check("burst starts emitting", small.emitting)
	_check("burst is one-shot", small.one_shot)
	_check("burst has particles", small.amount > 0)
	_check("burst has a sprite", small.mesh != null)
	_check("burst has an alpha ramp", small.color_ramp != null)
	_check("burst grows over its life", small.scale_amount_curve != null)
	_check("burst runs in world space", not small.local_coords)
	_check("strength raises the particle count", big.amount > small.amount)
	_check("strength raises the size", big.scale_amount_max > small.scale_amount_max)

	var material := small.get_mesh().surface_get_material(0) as StandardMaterial3D
	_check("burst has a material", material != null)
	if material != null:
		_check("burst is unshaded", material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED)
		_check("sprite is billboarded", material.billboard_mode == BaseMaterial3D.BILLBOARD_PARTICLES)
		_check("burst is visible", material.albedo_color.a > 0.0)
		_check("burst has the shared puff sprite", material.albedo_texture != null)

	# A warm-up burst is transparent and never expires on its own.
	var warm := packed.instantiate() as CPUParticles3D
	warm.call("setup", 1.0)
	warm.call("set_warmup")
	root.add_child(warm)
	await process_frame
	var warm_material := warm.get_mesh().surface_get_material(0) as StandardMaterial3D
	_check("warm-up has a material", warm_material != null)
	if warm_material != null:
		_check("warm-up is fully transparent", warm_material.albedo_color.a == 0.0)

	# A real burst frees itself once the last particle has faded.
	var doomed := _burst(packed, 0.6)
	var doomed_id := doomed.get_instance_id()
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline and is_instance_valid(instance_from_id(doomed_id)):
		await process_frame
	_check("burst frees itself", not is_instance_valid(instance_from_id(doomed_id)))

	# The warm-up must never free itself; the caller owns it.
	_check("warm-up is still alive", is_instance_valid(warm))

	# `small`/`big` have already freed themselves by now (their lifetimes are
	# shorter than the self-free wait above), so only free what is still alive.
	for node in [small, big, warm]:
		if is_instance_valid(node):
			node.queue_free()
	_finish()


func _burst(packed: PackedScene, strength: float) -> CPUParticles3D:
	var burst := packed.instantiate() as CPUParticles3D
	burst.call("setup", strength)
	root.add_child(burst)
	return burst


func _finish() -> void:
	print("")
	if failures == 0:
		print("all jump-dust checks passed")
	else:
		print("%d check(s) failed" % failures)
	quit(failures)


func _check(label: String, ok: bool) -> void:
	if ok:
		print("ok   ", label)
	else:
		failures += 1
		print("FAIL ", label)
