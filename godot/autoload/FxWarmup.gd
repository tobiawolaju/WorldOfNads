extends Node
## Global FX/shader prewarm to avoid first-use stalls (shader/particle pipeline
## compilation), especially on GL Compatibility/web. Runs once per session.
##
## Warms: muzzle flash, hit-confetti particles, and death-dissolve shaders.
## Safe in headless (no-op). Triggers opportunistically when a camera exists.

const MUZZLE_FLASH_SCENE := preload("res://scenes/fx/muzzle_flash.tscn")
const SMOKE_CLOUD_SCENE := preload("res://scenes/smoke_cloud.tscn")
const DEATH_DISSOLVE_SHADER := preload("res://assets/shaders/death_dissolve.gdshader")
const DEATH_DISSOLVE_UNSHADED_SHADER := preload("res://assets/shaders/death_dissolve_unshaded.gdshader")

var _done := false
var _running := false

func _ready() -> void:
	# Kick off after the scene settles; retries until a camera is available.
	call_deferred("_try_start")


func warm() -> void:
	_try_start()


func _try_start() -> void:
	if _done or _running:
		return
	if DisplayServer.get_name() == "headless":
		_done = true
		return
	var tree := get_tree()
	if tree == null:
		return
	var camera := tree.root.get_viewport().get_camera_3d() if tree.root else null
	if camera == null:
		# No camera yet (loading/lobby bootstrap). Retry shortly.
		if is_inside_tree():
			get_tree().create_timer(0.5).timeout.connect(_try_start, CONNECT_ONE_SHOT)
		return
	_running = true
	await _run_warmup(camera)
	_running = false
	_done = true


func _run_warmup(camera: Camera3D) -> void:
	if camera == null or not is_instance_valid(camera):
		return
	var host: Node = get_tree().current_scene if get_tree() and get_tree().current_scene != null else camera
	if host == null or not is_instance_valid(host):
		return

	# 1) Muzzle flash (GPU particles + muzzle_flash shader)
	await _warm_muzzle_flash(host, camera)
	await _next_frame()

	# 2) Hit confetti (particle process + unshaded billboard draw pass)
	await _warm_hit_confetti(host, camera)
	await _next_frame()

	# 3) Death dissolve shaders (shaded + unshaded variants)
	await _warm_death_dissolve(camera)
	await _next_frame()

	# 4) Smoke cloud material (CPUParticles + StandardMaterial3D billboard path)
	await _warm_smoke(host, camera)


func _warm_muzzle_flash(host: Node, camera: Camera3D) -> void:
	var fx: Node = MUZZLE_FLASH_SCENE.instantiate()
	if fx == null:
		return
	host.add_child(fx)
	if fx is Node3D:
		var n := fx as Node3D
		n.global_position = camera.global_position - camera.global_transform.basis.z * 0.6
		n.scale = Vector3(0.001, 0.001, 0.001) # invisible prewarm
	if fx.has_method("flash"):
		fx.call("flash")
	elif fx is GPUParticles3D:
		var p := fx as GPUParticles3D
		p.emitting = true
		p.restart()
	await _frames(2)
	if is_instance_valid(fx):
		fx.queue_free()


func _warm_hit_confetti(host: Node, camera: Camera3D) -> void:
	var p := GPUParticles3D.new()
	p.name = "FxWarmupConfetti"
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 8
	p.lifetime = 0.05
	p.local_coords = true
	p.emitting = false
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(1, 0, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 1.0
	mat.gravity = Vector3.ZERO
	mat.color = Color(1, 1, 1, 1)
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.01, 0.01)
	var draw := StandardMaterial3D.new()
	draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	draw.vertex_color_use_as_albedo = true
	draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw.albedo_color = Color(1, 1, 1, 0.0) # keep prewarm invisible
	quad.material = draw
	p.draw_pass_1 = quad
	host.add_child(p)
	p.global_position = camera.global_position - camera.global_transform.basis.z * 0.6
	p.scale = Vector3(0.001, 0.001, 0.001)
	p.emitting = true
	p.restart()
	await _frames(2)
	if is_instance_valid(p):
		p.queue_free()


func _warm_death_dissolve(camera: Camera3D) -> void:
	if camera == null or not is_instance_valid(camera):
		return
	# Mirror DeathDissolve.prewarm probe approach (tiny, fully dissolved/discarded).
	var probes: Array[MeshInstance3D] = []
	for shader in [DEATH_DISSOLVE_SHADER, DEATH_DISSOLVE_UNSHADED_SHADER]:
		if shader == null:
			continue
		var probe := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.002, 0.002)
		probe.mesh = quad
		probe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := ShaderMaterial.new()
		material.shader = shader
		# Best-effort: dissolve=1 discards in DeathDissolve shader (invisible draw).
		if material.shader != null:
			material.set_shader_parameter("dissolve", 1.0)
		probe.material_override = material
		probe.position = Vector3(0.0, 0.0, -0.5)
		camera.add_child(probe)
		probes.append(probe)
	await _frames(2)
	for probe in probes:
		if is_instance_valid(probe):
			probe.queue_free()
	# Let DeathDissolve know its shaders are warmed too (if it exposes/uses flag pattern).
	# DeathDissolve.prewarm() has its own guard; harmless to leave it for player path.


func _warm_smoke(host: Node, camera: Camera3D) -> void:
	var cloud: Node = SMOKE_CLOUD_SCENE.instantiate()
	if cloud == null:
		return
	if cloud.has_method("setup"):
		cloud.call("setup", 2.0, 1)
	if cloud.has_method("set_warmup"):
		cloud.call("set_warmup")
	host.add_child(cloud)
	if cloud is Node3D:
		(cloud as Node3D).global_position = camera.global_position - camera.global_transform.basis.z * 0.8
		(cloud as Node3D).scale = Vector3(0.001, 0.001, 0.001)
	await _frames(2)
	if is_instance_valid(cloud):
		cloud.queue_free()


func _frames(n: int) -> void:
	for _i in n:
		if not is_inside_tree():
			return
		await RenderingServer.frame_post_draw


func _next_frame() -> void:
	if is_inside_tree():
		await get_tree().process_frame
