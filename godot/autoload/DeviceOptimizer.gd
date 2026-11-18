extends Node

## DeviceOptimizer
##
## Scores the current device (CPU cores, RAM, GPU, platform) and applies
## layered performance optimizations: UI glass shaders, lights/shadows, and
## environment effects. Layers are cumulative (higher = more aggressive):
##   0 Full    - no reductions
##   1 Light   - cheaper shadows / lighter post effects
##   2 Low     - UI glass shaders off, scene shadows off, fewer accent lights
##   3 Minimal - aggressive reductions for very constrained devices
##
## "Device setting" signals (best-effort, cross-platform):
##   - CPU: OS.get_processor_count() (+ navigator.hardwareConcurrency on web)
##   - RAM: navigator.deviceMemory on web (GB, approximate). On native there is
##     no portable total-RAM API in Godot; mobile platforms are treated as
##     memory-constrained unless other signals say otherwise.
##   - GPU: RenderingServer adapter name/type
##   - Platform/screen: OS features, viewport pixel count

signal profile_applied(layer: int)

enum Layer { FULL = 0, LIGHT = 1, LOW = 2, MINIMAL = 3 }

const GLASS_SHADER_PATH := "res://scenes/glasshud.gdshader"

# Human-readable report of how the device was scored.
var report: Dictionary = {}

# Per-dimension scores (higher = more capable).
var cpu_score: int = 0
var ram_score: int = 0
var gpu_score: int = 0
var platform_score: int = 0
var total_score: int = 0
var layer: int = Layer.FULL

# Snapshot of environment values so we can restore/adjust idempotently.
var _env_base: Dictionary = {}


func _ready() -> void:
	_detect_and_score()
	_apply_layer()
	get_tree().node_added.connect(_on_node_added)
	get_tree().scene_changed.connect(_on_scene_changed)
	# Apply once more after the first frame so nodes created during _ready of
	# the initial scene are covered.
	call_deferred("_apply_to_tree")
	print("[DeviceOptimizer] layer=%d total=%d cpu=%d ram=%d gpu=%d platform=%d | %s" % [
		layer, total_score, cpu_score, ram_score, gpu_score, platform_score,
		str(report)
	])


# ------------------------------------------------------------------- detection

func _detect_and_score() -> void:
	var cpu_cores := _detect_cpu_cores()
	var ram_gb := _detect_ram_gb()
	var gpu_name := RenderingServer.get_video_adapter_name()
	var gpu_type := RenderingServer.get_video_adapter_type()
	var is_mobile := _is_mobile()
	var is_web := OS.has_feature("web")
	var screen_pixels := _screen_pixels()

	# CPU cores
	if cpu_cores >= 8:
		cpu_score = 2
	elif cpu_cores >= 4:
		cpu_score = 1
	else:
		cpu_score = 0

	# RAM (GB). -1 means unknown.
	if ram_gb >= 8.0:
		ram_score = 2
	elif ram_gb >= 4.0:
		ram_score = 1
	elif ram_gb > 0.0:
		ram_score = 0
	else:
		# Unknown: assume constrained on mobile/web, neutral on desktop.
		ram_score = 0 if (is_mobile or is_web) else 1

	# GPU
	gpu_score = _score_gpu(gpu_name, gpu_type)

	# Platform / form factor
	platform_score = 1
	if is_mobile:
		platform_score -= 1
	if is_web:
		platform_score -= 1
	if screen_pixels >= 2_073_600: # >= 1920x1080
		platform_score -= 1
	platform_score = clampi(platform_score, -2, 2)

	total_score = cpu_score + ram_score + gpu_score + platform_score
	layer = _score_to_layer(total_score, is_mobile, is_web)

	report = {
		"cpu_cores": cpu_cores,
		"ram_gb": ram_gb,
		"gpu_name": gpu_name,
		"gpu_type": gpu_type,
		"mobile": is_mobile,
		"web": is_web,
		"screen_pixels": screen_pixels,
		"total": total_score,
		"layer": layer,
	}


func _score_to_layer(score: int, is_mobile: bool, is_web: bool) -> int:
	# Base mapping from the total score.
	var l := Layer.FULL
	if score <= 0:
		l = Layer.MINIMAL
	elif score <= 2:
		l = Layer.LOW
	elif score <= 4:
		l = Layer.LIGHT
	else:
		l = Layer.FULL

	# Careful floors: constrained platforms should not run at Full by default.
	if is_mobile and l < Layer.LIGHT:
		l = Layer.LIGHT
	if is_web and is_mobile and l < Layer.LOW:
		l = Layer.LOW
	elif is_web and l < Layer.LIGHT:
		l = Layer.LIGHT

	return clampi(l, Layer.FULL, Layer.MINIMAL)


func _score_gpu(gpu_name: String, gpu_type: int) -> int:
	var name := gpu_name.to_lower()

	# Software / very slow renderers.
	for token in ["swiftshader", "llvmpipe", "softpipe", "software", "microsoft basic render"]:
		if name.find(token) != -1:
			return 0

	# Explicit adapter type when available (RenderingDevice.DeviceType values).
	match gpu_type:
		RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
			return 2
		RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
			return 1
		RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU:
			return 0
		RenderingDevice.DEVICE_TYPE_CPU:
			return 0
		_:
			pass

	# Heuristics from name for mobile/other GPUs.
	for token in ["adreno 3", "adreno 4", "adreno 5", "mali-4", "mali-t6", "mali-t7", "powervr", "tegra 3", "tegra 4", "videocore"]:
		if name.find(token) != -1:
			return 0
	for token in ["adreno 6", "adreno 7", "mali-g5", "mali-g6", "mali-g7", "apple a1", "apple a2", "apple gpu"]:
		if name.find(token) != -1:
			return 1
	for token in ["adreno 8", "mali-g8", "apple m", "geforce", "radeon rx", "rtx", "gtx 1", "gtx 2"]:
		if name.find(token) != -1:
			return 2

	return 1 if name != "" else 0


func _detect_cpu_cores() -> int:
	var cores := OS.get_processor_count()
	if OS.has_feature("web"):
		var v = _js_number("navigator.hardwareConcurrency || 0")
		if v > 0:
			cores = int(v)
	return maxi(cores, 1)


func _detect_ram_gb() -> float:
	if OS.has_feature("web"):
		var v = _js_number("navigator.deviceMemory || 0")
		if v > 0.0:
			return float(v)
	# No portable total-RAM API on native in Godot; return -1 (unknown).
	return -1.0


func _screen_pixels() -> int:
	var vp := get_viewport()
	if vp == null:
		return 0
	var s := vp.get_visible_rect().size
	return int(s.x * s.y)


func _is_mobile() -> bool:
	return (
		OS.has_feature("mobile")
		or OS.has_feature("web_android")
		or OS.has_feature("web_ios")
	)


func _js_number(expr: String) -> float:
	if not OS.has_feature("web"):
		return 0.0
	var v = JavaScriptBridge.eval(expr)
	if typeof(v) == TYPE_INT:
		return float(v)
	if typeof(v) == TYPE_FLOAT:
		return float(v)
	if typeof(v) == TYPE_STRING:
		return float(str(v))
	return 0.0


# ---------------------------------------------------------------- application

func _apply_layer() -> void:
	_apply_to_tree()
	profile_applied.emit(layer)


func _on_scene_changed(_scene: Node) -> void:
	# Scene nodes are added after this signal in some cases; defer to be safe.
	call_deferred("_apply_to_tree")


func _on_node_added(node: Node) -> void:
	# Apply incrementally so dynamically spawned UI/effects are covered.
	if node is CanvasItem:
		_maybe_apply_glass(node as CanvasItem)
	if node is Light3D:
		_apply_light(node as Light3D)
	if node is WorldEnvironment:
		_apply_environment(node as WorldEnvironment)


func _apply_to_tree() -> void:
	var root := get_tree().root if get_tree() else null
	if root == null:
		return
	_apply_subtree(root)


func _apply_subtree(node: Node) -> void:
	if node is CanvasItem:
		_maybe_apply_glass(node as CanvasItem)
	if node is Light3D:
		_apply_light(node as Light3D)
	if node is WorldEnvironment:
		_apply_environment(node as WorldEnvironment)
	for child in node.get_children():
		_apply_subtree(child)


# --- Glass shader (UI) -------------------------------------------------------
# Layer >= LOW: disable expensive screen-reading glass shader in UI.
# The material is removed per-node; the control's own StyleBox/modulate remains
# as a readable fallback.

func _maybe_apply_glass(item: CanvasItem) -> void:
	var mat := item.material
	if not (mat is ShaderMaterial):
		return
	var shader := (mat as ShaderMaterial).shader
	if shader == null:
		return
	if shader.resource_path != GLASS_SHADER_PATH:
		return
	if layer >= Layer.LOW:
		if not item.has_meta("_glass_mat"):
			item.set_meta("_glass_mat", mat)
		item.material = null
	else:
		if item.has_meta("_glass_mat"):
			item.material = item.get_meta("_glass_mat")


# --- Lights ------------------------------------------------------------------
# Layer LIGHT: keep lights but disable shadows on secondary/fill lights.
# Layer LOW:   disable shadows on all lights; dim non-key accent lights.
# Layer MINIMAL: disable shadows and strongly dim/disable accent lights.

func _apply_light(light: Light3D) -> void:
	# Record base values once so we can scale from originals.
	if not light.has_meta("_opt_base_energy"):
		light.set_meta("_opt_base_energy", light.light_energy)
		light.set_meta("_opt_base_shadow", light.shadow_enabled)
	var base_energy: float = light.get_meta("_opt_base_energy")
	var base_shadow: bool = light.get_meta("_opt_base_shadow")

	if layer <= Layer.FULL:
		light.light_energy = base_energy
		light.shadow_enabled = base_shadow
		return

	var lname := light.name.to_lower()
	var is_accent := lname.find("fill") != -1 or lname.find("rim") != -1

	if layer == Layer.LIGHT:
		# Keep key lights intact; drop shadows from accent lights.
		light.light_energy = base_energy
		light.shadow_enabled = false if is_accent else base_shadow
	elif layer == Layer.LOW:
		light.shadow_enabled = false
		light.light_energy = base_energy * (0.6 if is_accent else 1.0)
	else: # MINIMAL
		light.shadow_enabled = false
		if is_accent:
			light.visible = false
			light.light_energy = base_energy
		else:
			light.visible = true
			light.light_energy = base_energy * 0.85

	if light is DirectionalLight3D and layer >= Layer.LOW:
		(light as DirectionalLight3D).directional_shadow_max_distance = minf(
			(light as DirectionalLight3D).directional_shadow_max_distance, 12.0
		)


# --- Environment -------------------------------------------------------------
# Layer LIGHT: reduce glow intensity.
# Layer LOW+:  disable glow; keep fog (important for depth/gameplay cues).

func _apply_environment(world_env: WorldEnvironment) -> void:
	var env := world_env.environment
	if env == null:
		return
	var id := env.get_instance_id()
	if not _env_base.has(id):
		_env_base[id] = {
			"glow_enabled": env.glow_enabled,
			"glow_intensity": env.glow_intensity,
			"glow_bloom": env.glow_bloom,
		}
	var base: Dictionary = _env_base[id]

	if layer <= Layer.FULL:
		env.glow_enabled = base.get("glow_enabled", env.glow_enabled)
		env.glow_intensity = base.get("glow_intensity", env.glow_intensity)
		env.glow_bloom = base.get("glow_bloom", env.glow_bloom)
	elif layer == Layer.LIGHT:
		env.glow_enabled = base.get("glow_enabled", env.glow_enabled)
		env.glow_intensity = float(base.get("glow_intensity", env.glow_intensity)) * 0.5
		env.glow_bloom = float(base.get("glow_bloom", env.glow_bloom)) * 0.5
	else:
		env.glow_enabled = false


# --- Public helpers ----------------------------------------------------------

func get_layer() -> int:
	return layer


func get_layer_name() -> String:
	match layer:
		Layer.FULL:
			return "full"
		Layer.LIGHT:
			return "light"
		Layer.LOW:
			return "low"
		Layer.MINIMAL:
			return "minimal"
		_:
			return "unknown"


func is_glass_disabled() -> bool:
	return layer >= Layer.LOW


func is_shadows_reduced() -> bool:
	return layer >= Layer.LIGHT
