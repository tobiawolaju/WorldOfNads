extends Node

## Lobby performance benchmark.
##
## Loads a scene, lets it settle, then measures a window of frames and prints one
## summary line (plus the worst frames). Copy that line into a bug report / chat
## so runs can be compared after a change.
##
## Run from a terminal (no editor overhead, no live graphs to read):
##
##   godot --path godot res://tools/lobby_bench.tscn
##   godot --path godot res://tools/lobby_bench.tscn -- scene=res://scenes/gameplay.tscn
##   godot --path godot res://tools/lobby_bench.tscn -- hud=0 bots=0
##
## Or open tools/lobby_bench.tscn in the editor and press F6.
##
## Options (user args, all optional):
##   scene=res://...   default res://scenes/lobby.tscn
##   hud=0|1           hide the Hud node (default 1 = visible)
##   bots=0|1          lobby stress bots (default 1 = on)
##   warmup=SECONDS    default 5
##   measure=SECONDS   default 10

const DEFAULT_SCENE := "res://scenes/lobby.tscn"

var _scene_path: String = DEFAULT_SCENE
var _show_hud: bool = true
var _spawn_bots: bool = true
var _glow: bool = true
var _shadows: bool = true
var _fog: bool = true
var _warmup_sec: float = 5.0
var _measure_sec: float = 10.0


func _ready() -> void:
	_parse_args()
	# The project ships with run/max_fps=60, which hides all headroom: every
	# frame is clamped to 16.6 ms and a scene that needs 40 ms looks "fine".
	# The benchmark runs uncapped so the numbers mean something.
	Engine.max_fps = 0
	await get_tree().process_frame
	_run()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.split("=", true, 1)
		if parts.size() != 2:
			continue
		match parts[0]:
			"scene":
				_scene_path = parts[1]
			"hud":
				_show_hud = parts[1] != "0"
			"bots":
				_spawn_bots = parts[1] != "0"
			"glow":
				_glow = parts[1] != "0"
			"shadows":
				_shadows = parts[1] != "0"
			"fog":
				_fog = parts[1] != "0"
			"warmup":
				_warmup_sec = maxf(0.0, parts[1].to_float())
			"measure":
				_measure_sec = maxf(1.0, parts[1].to_float())


func _run() -> void:
	var packed := load(_scene_path) as PackedScene
	if packed == null:
		push_error("lobby_bench: cannot load %s" % _scene_path)
		get_tree().quit(1)
		return

	var t0 := Time.get_ticks_usec()
	var scene := packed.instantiate()
	if scene.has_method("set") and not _spawn_bots:
		scene.set("spawn_lobby_stress_agents", false)
	add_child(scene)
	var instantiate_ms := (Time.get_ticks_usec() - t0) / 1000.0

	if not _show_hud and scene.has_node("Hud"):
		(scene.get_node("Hud") as Node).visible = false

	_apply_toggles(scene)

	# Warm up: shader compiles, bot spawn, first-tick allocations all land here.
	var warm_frames := int(maxf(1.0, _warmup_sec) * 60.0)
	var t_start := Time.get_ticks_msec()
	for _i in range(warm_frames):
		await get_tree().process_frame

	var proc_ms: Array[float] = []
	var phys_ms: Array[float] = []
	var frame_ms: Array[float] = []
	var last_us := Time.get_ticks_usec()
	var measure_end := Time.get_ticks_msec() + int(_measure_sec * 1000.0)
	while Time.get_ticks_msec() < measure_end:
		await get_tree().process_frame
		var now_us := Time.get_ticks_usec()
		frame_ms.append(float(now_us - last_us) / 1000.0)
		last_us = now_us
		proc_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		phys_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)

	proc_ms.sort()
	phys_ms.sort()
	frame_ms.sort()

	var elapsed := float(Time.get_ticks_msec() - t_start) / 1000.0
	print("")
	print("=== LOBBY BENCH ===")
	print("scene=%s hud=%s bots=%s instantiate_ms=%.0f frames=%d wall_s=%.1f" % [
		_scene_path, _show_hud, _spawn_bots, instantiate_ms, frame_ms.size(), elapsed])
	print("frame_ms  avg=%6.2f  p50=%6.2f  p95=%6.2f  p99=%6.2f  max=%7.2f" % [
		_mean(frame_ms), _pct(frame_ms, 0.50), _pct(frame_ms, 0.95), _pct(frame_ms, 0.99), _pct(frame_ms, 1.0)])
	print("process   avg=%6.2f  p95=%6.2f" % [_mean(proc_ms), _pct(proc_ms, 0.95)])
	print("physics   avg=%6.2f  p95=%6.2f" % [_mean(phys_ms), _pct(phys_ms, 0.95)])
	var avg_frame := _mean(frame_ms)
	print("fps       avg=%6.1f  p05=%6.1f  min=%6.1f" % [
		1000.0 / maxf(0.001, avg_frame),
		1000.0 / maxf(0.001, _pct(frame_ms, 0.95)),
		1000.0 / maxf(0.001, _pct(frame_ms, 1.0))])
	print("render    draw_calls=%d primitives=%d" % [
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])
	print("memory    video_mb=%.1f texture_mb=%.1f nodes=%d objects=%d orphans=%d" % [
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))])
	print("===================")
	get_tree().quit()


func _apply_toggles(root: Node) -> void:
	for node in root.find_children("*", "", true, false):
		if node is WorldEnvironment:
			var env := (node as WorldEnvironment).environment
			if env != null:
				env.glow_enabled = _glow
				env.fog_enabled = _fog
		elif node is Light3D:
			(node as Light3D).shadow_enabled = _shadows


func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += v
	return total / float(values.size())


func _pct(sorted_values: Array[float], fraction: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var idx := clampi(int(round(fraction * float(sorted_values.size() - 1))), 0, sorted_values.size() - 1)
	return sorted_values[idx]
