extends CPUParticles3D
## A short burst of dust, kicked up when the player leaves the ground or lands.
##
## One-shot and self-freeing: spawn it, it plays once and deletes itself. The
## whole burst is scaled from a single `strength` so a small hop, a full jump
## and a hard landing can share one effect without three sets of numbers.
##
## The puff sprite is the same soft round texture the SMOG cloud uses (white,
## noise-edged, so it tinted cleanly); here it is tinted warm grey and left
## unshaded. Sharing the texture also means the 64x64 image is only generated
## once per process, no matter how many jumps happen.
##
## Visual only: no collision, no gameplay effect.

const SMOKE_CLOUD_SCRIPT := preload("res://scripts/effects/smoke_cloud.gd")

## Warm grey-brown, so it reads as ground dust rather than smoke.
const DUST_COLOR := Color(0.78, 0.73, 0.64)
## How long the puff lingers. A landing dust cloud should be gone before the
## player has committed to the next input.
const LIFETIME: float = 0.6
## Particles at strength 1.0; the count scales with the burst.
const BASE_AMOUNT: int = 12
const MAX_AMOUNT: int = 30

## 0.35 (a step off a kerb) .. 2.0 (a MEGA_LEAP take-off or a long fall).
var strength: float = 1.0

## Warm-up copy: same material and mesh, fully transparent, never expires on its
## own. The caller frees it once the shader has compiled (see player.gd's
## `_prewarm_jump_dust`), so the first real jump never hitches.
var _is_warmup: bool = false


## Must be called before the burst enters the tree. `burst_strength` scales the
## particle count, spread, speed and size together.
func setup(burst_strength: float) -> void:
	strength = clampf(burst_strength, 0.35, 2.0)


func set_warmup() -> void:
	_is_warmup = true


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# A custom shader cannot billboard in Godot 4; this material flag is what
	# keeps the sprites facing the camera.
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(DUST_COLOR, 0.0) if _is_warmup else DUST_COLOR
	material.albedo_texture = SMOKE_CLOUD_SCRIPT._get_puff_texture()
	# Let the per-particle colour ramp fade each puff out on its own.
	material.vertex_color_use_as_albedo = true
	quad.material = material
	mesh = quad

	# Born almost invisible, peak fast, then fade. Dust should not pop in.
	var life_ramp := Gradient.new()
	life_ramp.offsets = PackedFloat32Array([0.0, 0.12, 0.55, 1.0])
	life_ramp.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 0.85),
		Color(1.0, 1.0, 1.0, 0.45),
		Color(1.0, 1.0, 1.0, 0.0),
	])

	# Puffs expand as they lose energy, which is what makes dust read as dust
	# instead of a smoke ball.
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.55))
	grow.add_point(Vector2(1.0, 1.0))

	amount = clampi(int(round(BASE_AMOUNT * strength)), 5, MAX_AMOUNT)
	lifetime = LIFETIME * lerpf(0.85, 1.15, (strength - 0.35) / 1.65)
	one_shot = true
	explosiveness = 0.9
	randomness = 0.5
	# World space: the node is spawned at the feet and never moves, but this way
	# it can never inherit motion if it is ever parented to something that does.
	local_coords = false

	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# A flat-ish disc at the feet, so it spreads outward along the ground
	# instead of puffing upward like a fountain.
	emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	emission_sphere_radius = 0.12 + 0.1 * strength
	direction = Vector3.UP
	spread = 78.0
	initial_velocity_min = 0.7 * strength
	initial_velocity_max = 1.7 * strength
	# Light downward pull plus heavy damping: the dust leaps out, then settles
	# almost immediately instead of drifting like smoke.
	gravity = Vector3(0.0, -1.1, 0.0)
	damping_min = 2.6
	damping_max = 4.2
	angle_min = 0.0
	angle_max = 360.0
	scale_amount_min = 0.22 * strength
	scale_amount_max = 0.42 * strength
	scale_amount_curve = grow
	color = Color.WHITE
	color_ramp = life_ramp

	if _is_warmup:
		return

	# Fired only now that every property above is in place, so the single burst
	# uses the configured spread/speed/size instead of the defaults it would
	# have seen mid-configuration.
	emitting = true

	# Self-cleanup. The extra frame of slack covers the last particle's fade.
	await get_tree().create_timer(lifetime + 0.15).timeout
	if is_instance_valid(self):
		queue_free()
