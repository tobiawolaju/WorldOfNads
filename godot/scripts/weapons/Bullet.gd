class_name Bullet
extends RigidBody3D
## Offline projectile for the handheld weapons. Attach to
## res://scenes/props/bullet.tscn (a plain RigidBody3D) and let player.gd spawn it
## from the muzzle Marker3D.
##
## Offline only: the hit is resolved here, on the machine that fired the shot.
## When the server owns damage, drop the take_damage() call in _on_body_entered
## and feed `hit` into the network instead; nothing else has to change.
##
## The scene needs nothing but the body itself. CCD, contact reporting and the
## lifetime are configured in _ready(), so re-authoring bullet.tscn (new mesh, new
## shape) cannot silently break hits.

## Emitted once, on the first thing the bullet touches. `at` is where it landed.
signal hit(target: Node, at: Vector3)

## Metres per second out of the muzzle. player.gd overwrites this per weapon from
## WEAPON_FIRE_FX, so the export is only the value used by a hand-placed bullet.
@export var speed: float = 120.0
@export var damage: float = 20.0
## Seconds before a bullet that hit nothing removes itself.
@export var lifetime: float = 2.5
## Push applied to a RigidBody3D it hits (crates, props). 0 leaves physics alone.
@export var impact_impulse: float = 0.0
## Seconds a spent bullet stays where it landed before it is removed. 0 frees it
## on the frame it hits. player.gd raises this for slow-motion debug shots so the
## projectile leaves visible evidence on the floor.
@export var linger_after_hit: float = 0.0
## Debug: print the spawn point and whatever the bullet hits. player.gd switches
## this on together with bullet_speed_scale, so a slow-motion test explains itself
## in the Output panel instead of just vanishing.
@export var debug: bool = false
## Ribbon trail behind the bullet. Built in code and rebuilt per physics frame
## from the last `trail_time` seconds of flight: one mesh, no particles and no
## light, so a burst of shots stays cheap.
@export var trail: bool = true
@export var trail_time: float = 0.15
## Metres of flight the ribbon may cover, independent of speed. Without this the
## trail is as long as the bullet travels in `trail_time`, i.e. ~20 m at rifle
## speed instead of a tracer.
@export_range(0.0, 40.0, 0.5) var trail_length: float = 8.0
@export_range(0.0, 0.5, 0.005) var trail_width: float = 0.05
@export_range(0.0, 0.2, 0.001) var trail_tip_width: float = 0.004
@export var trail_color: Color = Color(1.0, 0.78, 0.25, 0.9)
## Projectile look. player.gd copies these from WEAPON_FIRE_FX before the bullet
## enters the tree, so the RPG is a fat, slow rocket with a smoke plume while
## every gun keeps the thin tracer. Touching nothing here leaves bullet.tscn as
## authored, so hand-placed bullets (tests, props) behave exactly as before.
@export var mesh_scale: float = 1.0
@export var mesh_tint: Color = Color.WHITE
## Smoke plume trailing the projectile (RPG only). A few dozen CPU quads and no
## light, so rapid fire cannot hit the old muzzle-flash bottleneck.
@export var smoke: bool = false
@export_range(4, 256, 1) var smoke_amount: int = 48
@export var smoke_lifetime: float = 0.9
@export var smoke_size: float = 0.55
@export var smoke_color: Color = Color(0.78, 0.76, 0.72, 0.5)
## Hard cap on stored samples, so a bullet that never hits cannot grow the mesh.
const TRAIL_MAX_POINTS: int = 24
## Seconds a spent tracer stays visible after the bullet itself is gone.
const TRAIL_LINGER: float = 0.18
const RPG_SMOKE_SHADER: String = "res://assets/shaders/rpg_smoke.gdshader"

var _shooter: Node = null
var _spent: bool = false
## Set by hit/expire so _exit_tree can tell "freed by something else" apart.
var _freed_reason: String = ""
var _trail_mesh: MeshInstance3D = null
var _trail_immediate: ImmediateMesh = null
var _trail_positions: PackedVector3Array = PackedVector3Array()
var _trail_stamps: PackedFloat64Array = PackedFloat64Array()
var _smoke: CPUParticles3D = null


func _ready() -> void:
	# Forward speed comes from launch(); the drop comes from gravity_scale, which
	# player.gd sets per shot. No tumbling, and never allowed to fall asleep mid-air.
	can_sleep = false
	# body_entered only exists when contact reporting is on. Without these two the
	# bullet would pass through the world and deal no damage, silently.
	contact_monitor = true
	max_contacts_reported = 4
	# Ray CCD every physics step: at 120 m/s a bullet covers 2 m per tick, wider
	# than most targets, so discrete collision would tunnel straight through.
	continuous_cd = true
	body_entered.connect(_on_body_entered)
	if mesh_scale != 1.0 or mesh_tint != Color.WHITE:
		_style_mesh()
	if smoke:
		_build_smoke()
	if lifetime > 0.0:
		var timer := get_tree().create_timer(lifetime)
		timer.timeout.connect(_expire)
	if trail:
		_build_trail()


## Sends the bullet on its way. Call it AFTER add_child(): global_position needs a
## parent in the tree to be resolved against.
func launch(from: Vector3, direction: Vector3, shot_speed: float, shot_damage: float, shooter: Node = null) -> void:
	_shooter = shooter
	if shot_speed > 0.0:
		speed = shot_speed
	if shot_damage > 0.0:
		damage = shot_damage
	var dir := direction.normalized() if direction.length_squared() > 0.000001 else Vector3.FORWARD
	global_position = from
	linear_velocity = dir * speed
	# Never collide with the player who pulled the trigger: the muzzle sits inside
	# their capsule, so the first physics tick would read as a self-hit.
	if shooter is CollisionObject3D:
		add_collision_exception_with(shooter)
	if debug:
		var host := get_parent()
		print("[bullet] spawn %s | parent=%s | speed=%.1f dmg=%.0f" % [
			from, host.name if host != null else "<no parent>", speed, damage])
	# Prime the ribbon so the first drawn frame already has a segment.
	_remember_trail_point()


func _physics_process(_delta: float) -> void:
	# A spent bullet stops feeding the ribbon: the last streak stays where it is,
	# which is exactly the "it got there" evidence a slow-motion shot needs.
	if _trail_mesh == null or _spent:
		return
	_remember_trail_point()
	_rebuild_trail()


## One mesh, rebuilt from the last `trail_time` seconds of sampled positions. No
## particles and no light, so this cannot come back to the fire-rate bottleneck.
func _build_trail() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Depth testing stays on: the tracer must disappear behind the gun, the player
	# and walls like any other object. (no_depth_test draws through them.)
	material.disable_receive_shadows = true

	_trail_immediate = ImmediateMesh.new()
	_trail_mesh = MeshInstance3D.new()
	_trail_mesh.name = "Trail"
	_trail_mesh.mesh = _trail_immediate
	_trail_mesh.material_override = material
	_trail_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Vertices are written in world space, so the mesh must not follow the body.
	_trail_mesh.top_level = true
	add_child(_trail_mesh)


## Scales/tints the visual only. Never the body: a scaled RigidBody3D scales its
## collision shape too, which would change what the rocket can hit.
func _style_mesh() -> void:
	for child in get_children():
		if child is MeshInstance3D:
			var mesh_node := child as MeshInstance3D
			mesh_node.scale = Vector3.ONE * mesh_scale
			if mesh_tint != Color.WHITE and mesh_node.material_override is StandardMaterial3D:
				# Resources are shared between every bullet from the scene: duplicate
				# before tinting or the rifles would inherit the rocket's paint.
				var material := (mesh_node.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
				material.albedo_color *= mesh_tint
				mesh_node.material_override = material
			return


## World-space CPU plume. Puffs are left where they were born, so the smoke marks
## the flight path and keeps drifting after the rocket itself is gone.
func _build_smoke() -> void:
	_smoke = CPUParticles3D.new()
	_smoke.name = "Smoke"
	_smoke.amount = smoke_amount
	_smoke.lifetime = smoke_lifetime
	_smoke.local_coords = false
	_smoke.emitting = true
	_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_smoke.emission_sphere_radius = 0.12
	_smoke.direction = Vector3(0.0, 1.0, 0.0)
	_smoke.spread = 70.0
	_smoke.initial_velocity_min = 0.05
	_smoke.initial_velocity_max = 0.45
	_smoke.gravity = Vector3(0.0, 0.45, 0.0)
	_smoke.damping_min = 0.3
	_smoke.damping_max = 0.9
	_smoke.scale_amount_min = smoke_size * 0.45
	_smoke.scale_amount_max = smoke_size
	# Puffs grow as they age; a fixed size reads as a string of balls.
	var growth := Curve.new()
	growth.add_point(Vector2(0.0, 0.4))
	growth.add_point(Vector2(1.0, 1.8))
	_smoke.scale_amount_curve = growth
	_smoke.color = smoke_color
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	fade.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0, 0.85), Color(1.0, 1.0, 1.0, 0.0)])
	_smoke.color_ramp = fade
	_smoke.mesh = _smoke_mesh()
	add_child(_smoke)


## One soft white dot for the plume. The shader samples this at the particle UV
## for the puff's shape and alpha.
func _soft_dot_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0, 0.55), Color(1.0, 1.0, 1.0, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	return texture


## 1x1 flat texture for the shader's ramp/normal slots: the authored shader reads
## a whole particle sheet, our single soft dot does not need one per channel.
func _flat_texture(color: Color) -> ImageTexture:
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


## The smoke quad. Uses the authored particle-sheet shader (soft depth fade,
## camera-facing billboard in the vertex stage, colour ramp) with its sheet
## slots fed hand-built 1x1 ramps so nothing samples a missing texture.
func _smoke_mesh() -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var shader := load(RPG_SMOKE_SHADER) as Shader
	if shader == null:
		push_warning("RPG smoke shader missing: %s" % RPG_SMOKE_SHADER)
		return quad
	var material := ShaderMaterial.new()
	material.shader = shader
	# One frame, no sheet animation: the whole soft dot is the frame.
	material.set_shader_parameter("particle_h_frames", 1.0)
	material.set_shader_parameter("particle_v_frames", 1.0)
	material.set_shader_parameter("still_frame", 0.0)
	material.set_shader_parameter("tex_frg_2", _soft_dot_texture())
	# ALBEDO ramp, sampled by the dot's brightness: flat = the smoke colour.
	material.set_shader_parameter("tex_frg_27", _flat_texture(smoke_color))
	material.set_shader_parameter("tex_frg_24", _flat_texture(Color.WHITE))
	# No emission; these two would otherwise glow white at 5x.
	material.set_shader_parameter("tex_frg_25", _flat_texture(Color.BLACK))
	material.set_shader_parameter("tex_frg_26", _flat_texture(Color.BLACK))
	# Fragile normal: a fixed up-facing tangent normal reads as soft smoke.
	material.set_shader_parameter("tex_frg_16", _flat_texture(Color(0.5, 0.5, 1.0)))
	material.set_shader_parameter("tex_frg_17", _flat_texture(Color.BLACK))
	# Soft-particle band in metres: how close to geometry a puff fades out.
	material.set_shader_parameter("Soft_limit", 0.45)
	material.set_shader_parameter("blend_scale", 0.25)
	quad.material = material
	return quad


## Stops the plume and lets the puffs already in the air finish their fade where
## the projectile died, instead of popping out of existence with it.
func _release_smoke() -> void:
	if _smoke == null or not is_instance_valid(_smoke):
		return
	var plume := _smoke
	_smoke = null
	plume.emitting = false
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	# Reparent synchronously: queue_free() below runs at the end of this frame and
	# would take the plume with it. CPUParticles3D is not a physics body, so moving
	# it out of the bullet during the contact callback is safe.
	plume.reparent(tree.current_scene, true)
	tree.create_timer(smoke_lifetime + 0.5).timeout.connect(plume.queue_free)


## Detaches the ribbon so the last streak survives the bullet for a moment. The
## gun tracers used to vanish on the same frame as the impact - at rifle speed the
## bullet exists for only a handful of frames, so the shot read as "no trail".
func _release_trail(linger: float = TRAIL_LINGER) -> void:
	if _trail_mesh == null or not is_instance_valid(_trail_mesh):
		return
	var ribbon := _trail_mesh
	_trail_mesh = null
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		ribbon.queue_free()
		return
	# Synchronous reparent, for the same reason as the smoke: queue_free() at the
	# end of this frame would take the child ribbon with it. Vertices are world
	# space and the node is top_level, so it stays exactly where it was drawn.
	ribbon.reparent(tree.current_scene, true)
	tree.create_timer(linger).timeout.connect(ribbon.queue_free)


func _remember_trail_point() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_trail_positions.append(global_position)
	_trail_stamps.append(now)
	# Always keep the last two samples: a fast bullet on a heavy frame can cover
	# the whole trail_length between two ticks, and trimming down to one point
	# left the ribbon with nothing to draw (the pistol/AK "missing tracer").
	while _trail_positions.size() > 2 and now - _trail_stamps[0] > trail_time:
		_trail_positions.remove_at(0)
		_trail_stamps.remove_at(0)
	# Also cap the span in metres: at 170 m/s a 0.15 s trail would be 25 m of
	# laser, so the ribbon is trimmed to the same length at every weapon speed.
	while _trail_positions.size() > 2 \
			and _trail_positions[_trail_positions.size() - 1].distance_to(_trail_positions[0]) > trail_length:
		_trail_positions.remove_at(0)
		_trail_stamps.remove_at(0)
	while _trail_stamps.size() > TRAIL_MAX_POINTS:
		_trail_positions.remove_at(0)
		_trail_stamps.remove_at(0)


## Camera-facing triangle strip: two vertices per sample, widest at the bullet and
## tapering to nothing at the tail, fading out with the vertex colour.
func _rebuild_trail() -> void:
	_trail_immediate.clear_surfaces()
	var count := _trail_positions.size()
	if count < 2:
		return
	var camera := get_viewport().get_camera_3d()
	var eye := camera.global_position if camera != null else global_position + Vector3.UP * 20.0

	_trail_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in count:
		var point := _trail_positions[i]
		# 0 at the tail (oldest sample), 1 at the bullet.
		var t := float(i) / float(count - 1)
		var next_point := _trail_positions[mini(i + 1, count - 1)]
		var prev_point := _trail_positions[maxi(i - 1, 0)]
		var along := prev_point - next_point
		if along.length_squared() < 0.000001:
			along = Vector3.FORWARD
		var side := along.normalized().cross((eye - point).normalized())
		if side.length_squared() < 0.000001:
			side = Vector3.UP
		side = side.normalized() * lerpf(trail_tip_width, trail_width, t)

		var color := trail_color
		color.a *= t
		_trail_immediate.surface_set_color(color)
		_trail_immediate.surface_add_vertex(point + side)
		_trail_immediate.surface_set_color(color)
		_trail_immediate.surface_add_vertex(point - side)
	_trail_immediate.surface_end()


func _expire() -> void:
	if not _spent and is_instance_valid(self):
		if debug:
			print("[bullet] expired at %s (nothing in %ds)" % [global_position, int(lifetime)])
		_freed_reason = "expired"
		_release_smoke()
		_release_trail()
		queue_free()


func _exit_tree() -> void:
	# Debug only: if a live bullet leaves the tree without a hit or a timeout,
	# something above it was deleted or hidden away. That is the one case where
	# the projectile really can "pop out of existence" mid-flight.
	if debug and _freed_reason == "":
		print("[bullet] removed mid-flight at %s (nothing hit, not expired)" % global_position)


func _on_body_entered(body: Node) -> void:
	if _spent or body == null or body == _shooter:
		return
	_spent = true
	_freed_reason = "hit"
	_release_smoke()
	# The body may be a hitbox rather than the actor: walk up until something
	# accepts damage, the same way the storm ticks the player.
	var target := _damage_target(body)
	if debug:
		print("[bullet] hit %s%s at %s" % [
			body.get_path(),
			" (damage target: %s)" % target.get_path() if target != null else " (no damage target)",
			global_position])
	if target != null:
		target.call("take_damage", damage, _shooter)
	if impact_impulse > 0.0 and body is RigidBody3D and body != self:
		(body as RigidBody3D).apply_central_impulse(linear_velocity.normalized() * impact_impulse)
	hit.emit(target if target != null else body, global_position)
	if linger_after_hit > 0.0:
		# Debug: stop dead where it landed and stay visible for a moment, so a
		# slow shot leaves proof on the floor instead of blinking out of view.
		freeze = true
		linear_velocity = Vector3.ZERO
		# Deferred: contact monitoring cannot be turned off inside its own callback.
		set_deferred("contact_monitor", false)
		get_tree().create_timer(linger_after_hit).timeout.connect(queue_free)
		return
	# The streak outlives the bullet for a beat, otherwise a fast shot's tracer
	# disappears on the same frame the impact does.
	_release_trail()
	queue_free()


## Nearest node at or above `node` that owns a take_damage() method, or null.
func _damage_target(node: Node) -> Node:
	var current := node
	while current != null:
		if current.has_method("take_damage"):
			return current
		current = current.get_parent()
	return null
