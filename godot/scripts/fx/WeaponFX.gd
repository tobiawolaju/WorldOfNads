class_name WeaponFX
extends RefCounted
## Screen-space weapon effects. Currently just the blast tint for the RPG.
##
## Deliberately empty of 3D work: a muzzle flash used to spawn an OmniLight3D
## and a billboard per trigger pull, and creating/destroying lights stalls the
## GL Compatibility renderer — that was the fire-rate bottleneck. Camera kick and
## shake live in player.gd, on the follow camera, with no per-shot allocation.


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
