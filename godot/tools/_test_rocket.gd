# Checks the RPG projectile: slower than every gun, a fat orange exhaust instead
# of a rifle tracer, a bigger shell, and a smoke plume that keeps drifting at the
# impact point after the rocket itself is gone.
#   Godot_v4.8-beta1_win64_console.exe --headless --path godot --script res://tools/_test_rocket.gd
extends SceneTree

const SKIN_SCENE := "res://scenes/skin.tscn"
const GLOCK := 3
const RPG := 5

var failures: int = 0
var _started: bool = false


## A body that can be hit and records it, so the rocket has something to strike.
class Target extends CharacterBody3D:
	var hits: int = 0

	func take_damage(_amount: float, _source: Node = null) -> void:
		hits += 1


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	_run()  # async, not awaited: _process must keep running for physics to tick
	return false


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	# The player runs its own camera code while local; without one it errors.
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	world.add_child(camera)

	var player: Node = (load(SKIN_SCENE) as PackedScene).instantiate()
	world.add_child(player)
	await process_frame
	player.set("is_local", true)

	# --- 1. The row itself: slow, plumed, and flatter than a rifle round. ---
	var rpg_cfg: Dictionary = player.call("_weapon_fx_config", RPG)
	var glock_cfg: Dictionary = player.call("_weapon_fx_config", GLOCK)
	var rpg_speed := float(rpg_cfg.get("bullet_speed", 0.0))
	_check("the rocket leaves at 32 m/s", is_equal_approx(rpg_speed, 32.0), str(rpg_speed))
	_check("the rocket is slower than the pistol",
		rpg_speed < float(glock_cfg.get("bullet_speed", 0.0)),
		"%s vs %s" % [rpg_speed, glock_cfg.get("bullet_speed")])
	_check("the rocket drops less than a rifle round",
		float(rpg_cfg.get("gravity", 1.0)) < 1.0, str(rpg_cfg.get("gravity")))
	_check("the rocket carries smoke", bool(rpg_cfg.get("smoke", false)))
	_check("the guns keep the plain tracer", not bool(glock_cfg.get("smoke", false)))

	# --- 2. Firing builds the plume, the fat ribbon and the bigger shell. ---
	player.set("held_weapon_kind", RPG)
	player.set("held_weapon_max_uses", 4)
	player.set("held_weapon_uses", 4)
	player.call("_use_held_weapon")
	var rocket: Node = _newest_bullet(world)
	_check("RPG fire spawns a projectile", rocket != null)
	if rocket == null:
		_finish()
		return
	_check("the projectile flies at the rocket speed",
		is_equal_approx(float(rocket.get("speed")), 32.0), str(rocket.get("speed")))
	_check("the projectile keeps the rocket gravity",
		is_equal_approx((rocket as RigidBody3D).gravity_scale, 0.2),
		str((rocket as RigidBody3D).gravity_scale))
	var trail_width := float(rocket.get("trail_width"))
	_check("the rocket trail is fatter than a tracer", trail_width >= 0.15, str(trail_width))
	var trail_color: Color = rocket.get("trail_color")
	_check("the rocket trail is orange, not yellow", trail_color.r > trail_color.g,
		str(trail_color))

	var smoke := rocket.get_node_or_null("Smoke") as CPUParticles3D
	_check("the rocket carries a smoke emitter", smoke != null)
	if smoke != null:
		_check("the smoke is emitting", smoke.emitting)
		_check("the smoke stays in world space", not smoke.local_coords)
		_check("the smoke has a few dozen puffs", smoke.amount >= 40, str(smoke.amount))
		_check("the smoke puffs fade to nothing", smoke.color_ramp != null
			and smoke.color_ramp.get_color(smoke.color_ramp.get_point_count() - 1).a < 0.1)
		_check("the smoke lingers", smoke.lifetime >= 2.0, str(smoke.lifetime))
		var plume_mesh := smoke.mesh as QuadMesh
		var plume_material := plume_mesh.material as ShaderMaterial if plume_mesh != null else null
		_check("the plume renders with the particle shader", plume_material != null
			and plume_material.shader != null
			and plume_material.shader.resource_path.ends_with("rpg_smoke.gdshader"))
		_check("the shader is fed the soft dot for its shape", plume_material != null
			and plume_material.get_shader_parameter("tex_frg_2") != null)
		_check("the shader samples one frame, not a sheet", plume_material != null
			and is_equal_approx(float(plume_material.get_shader_parameter("particle_h_frames")), 1.0)
			and is_equal_approx(float(plume_material.get_shader_parameter("particle_v_frames")), 1.0))
	var mesh := _bullet_mesh(rocket)
	_check("the rocket shell is bigger than a bullet",
		mesh != null and mesh.scale.x >= 2.0, str(mesh.scale.x) if mesh != null else "no mesh")

	# --- 3. The plume outlives the impact instead of popping with the rocket. ---
	var target := Target.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	shape.shape = box
	target.add_child(shape)
	world.add_child(target)
	target.global_position = (rocket as RigidBody3D).global_position \
		+ (rocket as RigidBody3D).linear_velocity.normalized() * 6.0

	for _i in 30:
		await physics_frame
	_check("the rocket hits what it flies into", target.hits == 1, str(target.hits))
	_check("the rocket frees itself on impact", not is_instance_valid(rocket))
	var plume := world.get_node_or_null("Smoke") as CPUParticles3D
	_check("the smoke is left behind at the impact point", plume != null)
	if plume != null:
		_check("the detached plume stops emitting", not plume.emitting)
		for _i in 260:
			await physics_frame
			if not is_instance_valid(plume):
				break
		_check("the smoke frees itself once the last puff fades", not is_instance_valid(plume))

	_finish()


## The projectile spawned by this shot. _use_held_weapon() adds it to current_scene.
func _newest_bullet(world: Node) -> Node:
	var found: Node = null
	for child in world.get_children():
		if child.has_method("launch") and not child.is_queued_for_deletion():
			found = child
	return found


func _bullet_mesh(bullet: Node) -> MeshInstance3D:
	for child in bullet.get_children():
		if child is MeshInstance3D:
			return child
	return null


func _finish() -> void:
	print("rocket selftest: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  ", what)
		return
	failures += 1
	print("FAIL  ", what, "" if detail == "" else "  (got %s)" % detail)
