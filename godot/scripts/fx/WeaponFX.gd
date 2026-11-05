class_name WeaponFX
extends RefCounted
## Transient, code-only weapon effects: muzzle flash, tracer, smoke and the
## full-screen tint.
##
## Everything here is built from primitives (QuadMesh / CylinderMesh /
## CPUParticles3D / OmniLight3D) so no textures, scenes or art imports are
## required and a missing art pass can never break firing. Every spawned node
## lives for a fraction of a second and frees itself; nothing is kept between
## shots.
##
## The caller passes a per-weapon config dictionary (see player.gd
## WEAPON_FIRE_FX) so all numbers stay in one tuning table.


## The node transient effects are parented to. Never the player: an FX node on
## the skeleton would ride the animation and jitter.
static func host_of(source: Node) -> Node:
	if source == null or not source.is_inside_tree():
		return null
	var tree := source.get_tree()
	if tree == null:
		return null
	return tree.current_scene if tree.current_scene != null else tree.root


static func _additive(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	return mat


## Billboard flash + a short light pulse at the muzzle. Reads
## `muzzle_size`, `flash_color`, `flash_time`, `light_energy`, `light_range`
## and optionally `smoke` from `cfg`. A weapon with `muzzle_size` 0 (melee)
## spawns nothing.
static func spawn_muzzle_flash(source: Node, world_pos: Vector3, aim: Vector3, cfg: Dictionary) -> void:
	var host := host_of(source)
	if host == null:
		return
	var size: float = cfg.get("muzzle_size", 0.0)
	if size <= 0.0:
		return
	var color: Color = cfg.get("flash_color", Color(1.0, 0.86, 0.55))
	var lifetime: float = cfg.get("flash_time", 0.09)

	var root := Node3D.new()
	root.name = "_muzzle_flash"
	host.add_child(root)
	root.global_position = world_pos

	var mat := _additive(Color(color.r, color.g, color.b, 0.95))
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var quad_node := MeshInstance3D.new()
	quad_node.mesh = quad
	quad_node.material_override = mat
	quad_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(quad_node)

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = cfg.get("light_energy", 2.0)
	light.omni_range = cfg.get("light_range", 2.5)
	light.shadow_enabled = false
	root.add_child(light)

	# RPG backblast: a puff of dust leaving the tube. `world_pos` is global, so it
	# is passed through rather than placed relative to the flash node.
	if float(cfg.get("smoke", 0.0)) > 0.0:
		_spawn_puff(source, world_pos, -aim, size * 0.9, Color(0.78, 0.74, 0.70, 0.5), 0.55)

	var tween := root.create_tween()
	tween.set_parallel(true)
	tween.tween_property(mat, "albedo_color:a", 0.0, lifetime)
	tween.tween_property(light, "light_energy", 0.0, lifetime * 1.4)
	var timer := root.get_tree().create_timer(lifetime * 1.6)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(root):
			root.queue_free()
	)


## Thin additive streak from the muzzle to the impact point. Width and colour
## come from `tracer_width` / `tracer_color` / `tracer_time`.
static func spawn_tracer(source: Node, from: Vector3, to: Vector3, cfg: Dictionary) -> void:
	var host := host_of(source)
	if host == null:
		return
	var width: float = cfg.get("tracer_width", 0.012)
	if width <= 0.0:
		return
	var delta := to - from
	var dist := delta.length()
	if dist < 0.15:
		return
	var color: Color = cfg.get("tracer_color", Color(1.0, 0.9, 0.62))
	var lifetime: float = cfg.get("tracer_time", 0.07)

	var mesh := CylinderMesh.new()
	mesh.top_radius = width
	mesh.bottom_radius = width
	mesh.height = dist
	mesh.radial_segments = 5
	mesh.rings = 0

	var mat := _additive(Color(color.r, color.g, color.b, 0.9))
	var streak := MeshInstance3D.new()
	streak.mesh = mesh
	streak.material_override = mat
	streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(streak)

	# A CylinderMesh points along +Y, so build a basis whose Y follows the shot.
	var y_axis := delta / dist
	var x_axis := y_axis.cross(Vector3.UP)
	if x_axis.length_squared() < 0.0001:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	streak.global_transform = Transform3D(Basis(x_axis, y_axis, z_axis), (from + to) * 0.5)

	var tween := streak.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, lifetime)
	tween.tween_callback(streak.queue_free)


## Slow, rising smoke puff, used for the RPG backblast. Purely cosmetic: no
## physics query is involved anywhere in this file.
static func _spawn_puff(source: Node, pos: Vector3, dir: Vector3, size: float, color: Color, lifetime: float) -> void:
	var host := host_of(source)
	if host == null:
		return
	var puff := CPUParticles3D.new()
	puff.one_shot = true
	puff.emitting = false
	puff.amount = 8
	puff.lifetime = lifetime
	puff.explosiveness = 0.95
	puff.direction = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.UP
	puff.spread = 26.0
	puff.initial_velocity_min = 0.3
	puff.initial_velocity_max = 1.1
	puff.gravity = Vector3(0.0, 0.5, 0.0)
	puff.damping_min = 2.0
	puff.damping_max = 4.5
	puff.scale_amount_min = size * 0.5
	puff.scale_amount_max = size
	puff.color = color
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	puff.mesh = sphere
	puff.material_override = _additive(color)
	host.add_child(puff)
	puff.global_position = pos
	puff.emitting = true
	var timer := puff.get_tree().create_timer(lifetime + 0.7)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(puff):
			puff.queue_free()
	)


## Full-screen colour tint on the camera, used for the RPG blast. Repeated
## shots replace the previous tint instead of stacking towards white.
static func spawn_screen_flash(cam: Camera3D, color: Color, duration: float) -> void:
	if cam == null or not cam.is_inside_tree() or color.a <= 0.0:
		return
	var viewport := cam.get_viewport()
	if viewport == null:
		return
	var old := cam.get_node_or_null("_weapon_flash")
	if old != null:
		old.queue_free()
	var overlay := ColorRect.new()
	overlay.color = color
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.size = viewport.get_visible_rect().size
	var layer := CanvasLayer.new()
	layer.name = "_weapon_flash"
	layer.layer = 98
	layer.add_child(overlay)
	cam.add_child(layer)
	var tween := layer.create_tween()
	tween.tween_property(overlay, "color:a", 0.0, maxf(duration, 0.05))
	tween.tween_callback(layer.queue_free)


## Muzzle position for the weapon currently drawn in the hand, as the front of
## its bounding box along the aim direction. Falls back to the hand slot itself
## when the rig has no measurable mesh.
static func muzzle_point(rig: Node3D, slot_path: String, aim: Vector3) -> Vector3:
	if rig == null:
		return Vector3.ZERO
	var direction := aim.normalized() if aim.length_squared() > 0.0001 else -rig.global_transform.basis.z
	var slot := rig.get_node_or_null(slot_path) as Node3D
	if slot == null:
		return rig.global_position + direction * 0.5
	var box := _visible_global_aabb(slot)
	if box.size.length_squared() < 0.000001:
		return slot.global_position + direction * 0.35
	var half := box.size * 0.5
	# Projected half-extent of the box along the aim: the distance from its
	# centre to the face pointing down the barrel.
	var reach: float = absf(direction.x) * half.x \
		+ absf(direction.y) * half.y \
		+ absf(direction.z) * half.z
	return box.get_center() + direction * reach


## Axis-aligned bounding box of every visible mesh under `node`, in world space.
static func _visible_global_aabb(node: Node) -> AABB:
	var out := AABB()
	var has_point := false
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is MeshInstance3D and current.is_visible_in_tree():
			var mesh_node := current as MeshInstance3D
			var local := mesh_node.get_aabb()
			if local.size.length_squared() > 0.000001:
				var xform := mesh_node.global_transform
				for i in 8:
					var point: Vector3 = xform * local.get_endpoint(i)
					if not has_point:
						out = AABB(point, Vector3.ZERO)
						has_point = true
					else:
						out = out.expand(point)
		for child in current.get_children():
			stack.push_back(child)
	if not has_point:
		return AABB()
	return out
