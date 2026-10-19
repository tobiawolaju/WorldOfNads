extends Node3D
## A single stationary smoke cloud spawned by the SMOG power-up. Purely visual:
## it has no collision, so it never pushes or blocks anyone - it only hides what
## is inside it. The cloud lives for LIFETIME seconds, fading in and out, then
## frees itself.
##
## The look is a CPUParticles3D blob of soft, camera-facing green sprites. The
## sprite material uses the engine's BILLBOARD_PARTICLES billboard mode (a custom
## spatial shader cannot billboard on its own in Godot 4), and the round wispy
## shape comes from a small texture generated once and shared by every cloud.
##
## `setup()` still takes a seed so the layout varies between drops; for the future
## multiplayer version only the spawn position + lifetime need replicating, since
## the particle scatter is cosmetic.

const LIFETIME: float = 8.0
const FADE_IN: float = 0.4
const FADE_OUT: float = 1.4
const PARTICLE_AMOUNT: int = 24
const PARTICLE_LIFETIME: float = 2.6
const SMOKE_COLOR := Color(0.62, 0.82, 0.32)

## Soft round puff sprite, built once and shared by every cloud instance.
static var _puff_texture: ImageTexture = null

## Horizontal radius of the cloud in metres (half of its width).
var radius: float = 7.0

var _seed: int = 0
var _age: float = 0.0
var _particles: CPUParticles3D = null
var _material: StandardMaterial3D = null
## True on the throwaway cloud built for the warm-up (player.gd's
## `_prewarm_smoke_cloud`). It is assembled exactly like a real cloud so its
## material's shader variant compiles, but is kept fully transparent and never
## expires on its own; the caller frees it once the shader has compiled.
var _is_warmup: bool = false


## Called before the cloud is added to the tree. `cloud_radius` is the cloud's
## half-width in metres; `spawn_seed` varies the puff layout between drops.
func setup(cloud_radius: float, spawn_seed: int) -> void:
	radius = maxf(0.5, cloud_radius)
	_seed = spawn_seed


## Turns this cloud into a throwaway warm-up. Must be called before the cloud
## enters the tree, since that is when its material is built.
func set_warmup() -> void:
	_is_warmup = true


func _ready() -> void:
	if not _is_warmup:
		add_to_group("smoke_clouds")
	_build_particles()


# Builds (once) a wispy, soft-edged white sprite: a radial falloff multiplied by
# a bit of noise so the puffs do not read as clean discs. Tinted green by the
# material, then faded per particle by the particle's own colour ramp.
static func _get_puff_texture() -> ImageTexture:
	if _puff_texture != null:
		return _puff_texture
	const SIZE := 64
	var image := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 1337
	noise.frequency = 0.09
	noise.fractal_octaves = 3
	for y in SIZE:
		for x in SIZE:
			var uv := Vector2(float(x) + 0.5, float(y) + 0.5) / float(SIZE)
			var from_center := ((uv - Vector2(0.5, 0.5)) * 2.0).length()
			var falloff := clampf(1.0 - smoothstep(0.1, 1.0, from_center), 0.0, 1.0)
			var n := (noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			var alpha := clampf(falloff * (0.5 + 0.8 * n), 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	_puff_texture = ImageTexture.create_from_image(image)
	return _puff_texture


func _build_particles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed

	# One 1x1 quad; the particle system scales it per particle and the material
	# billboards it towards the camera.
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_material.billboard_keep_scale = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Warm-up clouds stay fully transparent so they can never flash on screen
	# while their shader compiles.
	_material.albedo_color = Color(SMOKE_COLOR, 0.0) if _is_warmup else SMOKE_COLOR
	_material.albedo_texture = _get_puff_texture()
	# Multiply the sprite by the particle's colour so its alpha ramp fades puffs.
	_material.vertex_color_use_as_albedo = true
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

	var particles := CPUParticles3D.new()
	particles.mesh = quad
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

	# Random per-particle spin so overlapping sprites don't line up.
	particles.angle_min = 0.0
	particles.angle_max = 360.0

	# The drop seed nudges the cloud's spread/scale so no two clouds are identical.
	particles.scale_amount_min = radius * rng.randf_range(0.45, 0.55)
	particles.scale_amount_max = radius * rng.randf_range(0.85, 0.95)

	particles.color = Color.WHITE
	particles.color_ramp = life_ramp

	add_child(particles)
	_particles = particles


func _process(delta: float) -> void:
	# Warm-up clouds exist only to make the shader compile; they are invisible
	# and freed by their caller, so they never age or dissolve on their own.
	if _is_warmup:
		return
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
		# Cloud-level fade: the material is per-cloud, so tinting its alpha here
		# fades the whole blob in/out on top of the per-particle fade.
		_material.albedo_color = Color(SMOKE_COLOR, fade)

	if _age >= LIFETIME:
		queue_free()
