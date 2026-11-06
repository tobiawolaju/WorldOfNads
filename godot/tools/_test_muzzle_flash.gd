# Checks the pooled muzzle flash: real scene, shader material, no light on the
# fire path, and one instance reused for every shot (no per-shot allocation).
#   Godot_v4.8-beta1_win64_console.exe --headless --path godot --script res://tools/_test_muzzle_flash.gd
extends SceneTree

const FLASH_SCENE := "res://scenes/fx/muzzle_flash.tscn"
const SKIN_SCENE := "res://scenes/skin.tscn"
const GLOCK := 3

var failures: int = 0
var _started: bool = false


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

	var packed: PackedScene = load(FLASH_SCENE)
	_check("muzzle_flash.tscn loads", packed != null)
	if packed == null:
		_finish()
		return

	var flash: Node = packed.instantiate()
	world.add_child(flash)
	_check("the flash is a GPUParticles3D", flash is GPUParticles3D)
	_check("the flash carries the MuzzleFlash script", flash.has_method("flash"))

	var particles := flash as GPUParticles3D
	_check("the flash is one-shot and idle", particles.one_shot and not particles.emitting)
	_check("the flash has a draw pass", particles.draw_pass_1 != null)

	var quad := particles.draw_pass_1 as QuadMesh
	_check("the draw pass is a quad", quad != null)
	var material := quad.material as ShaderMaterial if quad != null else null
	_check("the quad uses a shader material", material != null)
	_check("the shader is loaded", material.shader != null if material != null else false)
	_check("the flash texture is set",
			material.get_shader_parameter("texture_albedo") != null if material != null else false)
	_check("the sprite sheet is one frame",
			int(material.get_shader_parameter("particles_anim_h_frames")) == 1
			and int(material.get_shader_parameter("particles_anim_v_frames")) == 1
			if material != null else false)
	_check("the flash is billboarded",
			bool(material.get_shader_parameter("billboard")) if material != null else false)

	# The removed flash created an OmniLight3D per shot, which is what stalled the
	# Compatibility renderer. The pool must never bring a light back.
	var lights := flash.find_children("*", "Light3D", true, false)
	_check("the flash adds no light", lights.is_empty(), str(lights))

	flash.call("flash")
	_check("flash() starts emitting", particles.emitting)

	# Player level: the same node must be reused for shot after shot.
	var player: Node = (load(SKIN_SCENE) as PackedScene).instantiate()
	world.add_child(player)
	await process_frame
	player.set("is_local", true)
	player.set("held_weapon_kind", GLOCK)
	player.set("held_weapon_max_uses", 5)
	player.set("held_weapon_uses", 5)
	player.call("_trigger_weapon_fx", "shoot")
	var first: Node = player.get("_muzzle_flash")
	_check("the player builds a flash on the first shot", first != null)
	var marker: Node = player.get_node_or_null("Skeleton3D/BoneAttachment3D/Marker3D")
	_check("the flash hangs off the muzzle marker", first != null and first.get_parent() == marker)

	player.call("_trigger_weapon_fx", "shoot")
	var second: Node = player.get("_muzzle_flash")
	_check("the second shot reuses the same flash", first != null and second == first)
	var flashes := 0
	if marker != null:
		for child in marker.get_children():
			if child.has_method("flash"):
				flashes += 1
	_check("the marker holds exactly one flash", flashes == 1, str(flashes))

	_finish()


func _finish() -> void:
	print("muzzle flash selftest: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func _check(what: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  ", what)
		return
	failures += 1
	print("FAIL  ", what, "" if detail == "" else "  (got %s)" % detail)
