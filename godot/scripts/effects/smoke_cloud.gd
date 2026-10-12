extends Node3D
## A single stationary smoke cloud spawned by the SMOG power-up. Purely visual:
## it has no collision, so it never pushes or blocks anyone - it only hides what
## is inside it. The cloud lives for LIFETIME seconds, fading in and out, then
## frees itself.
##
## The look is a CPUParticles3D blob: soft, camera-facing particle sprites (see
## smoke.gdshader) tinted the SMOG green. `setup()` still takes a seed so the
## layout varies between drops; for the future multiplayer version only the spawn
## position + lifetime need replicating, since the particle scatter is cosmetic.

const LIFETIME: float = 8.0
const FADE_IN: float = 0.4
const FADE_OUT: float = 1.4
const PARTICLE_AMOUNT: int = 24
const PARTICLE_LIFETIME: float = 2.6
const SMOKE_COLOR := Color(0.45, 0.8, 0.4)

const SMOKE_SHADER := preload("res://assets/shaders/smoke.gdshader")

## Horizontal radius of the cloud in metres (half of its width).
var radius: float = 7.0

var _seed: int = 0
var _age: float = 0.0
var _particles: CPUParticles3D = null
var _material: ShaderMaterial = null


## Called before the cloud is added to the tree. `cloud_radius` is the cloud's
## half-width in metres; `spawn_seed` varies the puff layout between drops.
func setup(cloud_radius: float, spawn_seed: int) -> void:
	radius = maxf(0.5, cloud_radius)
	_seed = spawn_seed


func _ready() -> void:
	add_to_group("smoke_clouds")
	_build_particles()


func _build_particles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed

	# One 1x1 quad; CPUParticles3D scales and orients it per particle, and the
	# shader billboards it and gives it the soft round shape.
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE

	_material = ShaderMaterial.new()
	_material.shader = SMOKE_SHADER
	_material.set_shader_parameter("smoke_color", SMOKE_COLOR)
	_material.set_shader_parameter("softness", 0.5)
	_material.set_shader_parameter("density", 0.75)
	_material.set_shader_parameter("cloud_alpha", 0.0)
	quad.material = _material

	# Alpha ramp over each particle's lifetime: born transparent, then fades out.
	var life_ramp := Gradient.new()
	life_ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.65, 1.0])
	life_ramp.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.0),
	])

	# Random grayscale per particle (alpha 1) so its spin + noise differ.
	var initial_ramp := Gradient.new()
	initial_ramp.offsets = PackedFloat32Array([0.0, 1.0])
	initial_ramp.colors = PackedColorArray([
		Color(0.35, 0.35, 0.35, 1.0),
		Color(1.0, 1.0, 1.0, 1.0),
	])

	var particles := CPUParticles3D.new()
	particles.mesh = quad
	particles.material_override = _material
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	particles.amount = PARTICLE_AMOUNT
	particles.lifetime = PARTICLE_LIFETIME
	# Pre-process one lifetime so the cloud is already full on the first frame
	# instead of filling in over a couple of seconds.
	particles.preprocess = PARTICLE_LIFETIME
	particles.emitting = true
	particles.one_shot = false
	particles.explosiveness = 0.0
	particles.randomness = 0.7

	# Emit from a loose volume and drift slowly so the puffs hang as a cloud.
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = radius * rng.randf_range(0.5, 0.6)
	particles.direction = Vector3.UP
	particles.spread = 180.0
	particles.initial_velocity_min = 0.15
	particles.initial_velocity_max = 0.6
	particles.gravity = Vector3(0.0, 0.15, 0.0)
	particles.damping_min = 0.4
	particles.damping_max = 0.9

	# The drop seed nudges the cloud's spread/scale so no two clouds are identical.
	particles.scale_amount_min = radius * rng.randf_range(0.45, 0.55)
	particles.scale_amount_max = radius * rng.randf_range(0.85, 0.95)

	particles.color = Color.WHITE
	particles.color_ramp = life_ramp
	particles.color_initial_ramp = initial_ramp

	add_child(particles)
	_particles = particles


func _process(delta: float) -> void:
	_age += delta
	var fade := 1.0
	if _age < FADE_IN:
		fade = _age / FADE_IN
	elif _age > LIFETIME - FADE_OUT:
		fade = clampf((LIFETIME - _age) / FADE_OUT, 0.0, 1.0)
		if _particles != null and _particles.emitting:
			# Stop spawning new puffs once the whole cloud starts dissolving.
			_particles.emitting = false

	if _material != null:
		_material.set_shader_parameter("cloud_alpha", fade)

	if _age >= LIFETIME:
		queue_free()
