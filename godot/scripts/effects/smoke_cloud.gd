extends Node3D
## A single stationary smoke cloud spawned by the SMOG power-up. Purely visual:
## it has no collision, so it never pushes or blocks anyone - it only hides what
## is inside it. The cloud lives for LIFETIME seconds, fading in and out, then
## frees itself.
##
## All placement randomness is driven by a single seed, so every client that is
## handed the same seed builds an identical cloud. That is the seam the future
## multiplayer version uses: replicate the spawn position + seed, not the visuals.

const LIFETIME: float = 8.0
const FADE_IN: float = 0.35
const FADE_OUT: float = 1.2
const PUFF_COUNT: int = 6
const SMOKE_COLOR := Color(0.72, 0.74, 0.76)

const SMOKE_SHADER := preload("res://assets/shaders/smoke.gdshader")

## Horizontal radius of the cloud in metres (half of its width).
var radius: float = 7.0

var _seed: int = 0
var _age: float = 0.0
var _materials: Array[ShaderMaterial] = []


## Called before the cloud is added to the tree. `cloud_radius` is the cloud's
## half-width in metres; `spawn_seed` fixes the random puff layout.
func setup(cloud_radius: float, spawn_seed: int) -> void:
	radius = maxf(0.5, cloud_radius)
	_seed = spawn_seed


func _ready() -> void:
	add_to_group("smoke_clouds")
	_build_puffs()


func _build_puffs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	for _i in PUFF_COUNT:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var quad := QuadMesh.new()
		var puff_size := radius * rng.randf_range(0.9, 1.3)
		quad.size = Vector2(puff_size, puff_size)
		mesh_instance.mesh = quad

		var material := ShaderMaterial.new()
		material.shader = SMOKE_SHADER
		material.set_shader_parameter("smoke_color", SMOKE_COLOR)
		material.set_shader_parameter("density", rng.randf_range(0.75, 0.95))
		material.set_shader_parameter("dissolve", rng.randf_range(0.0, 12.0))
		material.set_shader_parameter("uv_rot", rng.randf_range(0.0, TAU))
		material.set_shader_parameter("fade", 0.0)
		mesh_instance.material_override = material

		# Scatter around the centre, biased upward so the blob sits on the ground
		# rather than sinking half of itself into it.
		mesh_instance.position = Vector3(
			rng.randf_range(-0.45, 0.45),
			rng.randf_range(-0.10, 0.40),
			rng.randf_range(-0.45, 0.45)
		) * radius

		add_child(mesh_instance)
		_materials.append(material)


func _process(delta: float) -> void:
	_age += delta
	var fade := 1.0
	if _age < FADE_IN:
		fade = _age / FADE_IN
	elif _age > LIFETIME - FADE_OUT:
		fade = clampf((LIFETIME - _age) / FADE_OUT, 0.0, 1.0)

	for material in _materials:
		material.set_shader_parameter("fade", fade)

	if _age >= LIFETIME:
		queue_free()
