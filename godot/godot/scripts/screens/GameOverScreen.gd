extends CanvasLayer

const DUMMY_XP := 55
const LEVEL_STEP_BASE := 10
const RETURN_HOME_COUNTDOWN := 8
const LOBBY_SCENE_PATH := "res://scenes/lobby.tscn"



@onready var color_bg: ColorRect = get_node_or_null("ColorBG") as ColorRect
@onready var color_bg2: ColorRect = get_node_or_null("ColorBG2") as ColorRect
@onready var result_panel: VBoxContainer = get_node_or_null("ColorBG/Result") as VBoxContainer
@onready var result_title: Label = get_node_or_null("ColorBG/Result/BoxContainer/Title") as Label
@onready var result_subtitle: Label = get_node_or_null("ColorBG/Result/BoxContainer2/Subtitle") as Label
@onready var result_details: Label = get_node_or_null("ColorBG/Result/BoxContainer3/Details") as Label
@onready var progress_bar: ProgressBar = get_node_or_null("ColorBG/Result/BoxContainer4/Control/ProgressBar") as ProgressBar
@onready var level_label: Label = get_node_or_null("ColorBG/Result/BoxContainer4/Control/ProgressBar/Level") as Label
@onready var xp_label: Label = get_node_or_null("ColorBG/Result/BoxContainer4/Control/ProgressBar/XP") as Label
@onready var return_home_label: Label = get_node_or_null("ColorBG/Result/BoxContainer4/Control/returnhome") as Label
@onready var skip_button: Button = get_node_or_null("ColorBG/Result/BoxContainer4/Control/skiptimmer") as Button

var countdown_time := RETURN_HOME_COUNTDOWN
var _timeline_tween: Tween
var _countdown_timer: Timer
var _returning := false
var _base_color_bg_position := Vector2.ZERO
var _base_color_bg2_position := Vector2.ZERO


func _ready() -> void:
	layer = 100

	if skip_button != null:
		skip_button.pressed.connect(_force_return_to_lobby)

	var did_win := false
	if get_tree().has_meta("match_result_won"):
		did_win = bool(get_tree().get_meta("match_result_won"))

	_apply_result(did_win)
	call_deferred("_play_sequence")


func _apply_result(did_win: bool) -> void:
	if color_bg != null:
		color_bg.visible = true
		color_bg.color = Color(0.345, 0.146, 1.0, 1.0) if did_win else Color(1.0, 0.0, 0.0, 1.0)

	if color_bg2 != null:
		color_bg2.visible = true
		color_bg2.color = Color(0.345, 0.146, 1.0, 1.0) if did_win else Color(1.0, 0.0, 0.0, 1.0)

	if result_panel != null:
		result_panel.visible = true

	if result_title != null:
		result_title.text = "Congratulations" if did_win else "You almost made it"
		result_title.add_theme_color_override("font_color", Color.WHITE)

	if result_subtitle != null:
		result_subtitle.text = "You won" if did_win else "You tried"
		result_subtitle.add_theme_color_override("font_color", Color.WHITE)

	if result_details != null:
		result_details.text = "You outplayed other nads" if did_win else "You got outplayed"
		result_details.add_theme_color_override("font_color", Color.WHITE)



	if return_home_label != null and color_bg != null:
		return_home_label.add_theme_color_override("font_color", color_bg.color)

	if progress_bar != null:
		progress_bar.visible = false
		progress_bar.value = 0.0

	if level_label != null:
		level_label.visible = false
		level_label.text = "Level 0"

	if xp_label != null:
		xp_label.visible = false
		xp_label.text = "XP 0"

	if return_home_label != null:
		return_home_label.visible = false

	if skip_button != null:
		skip_button.visible = false


func _play_sequence() -> void:
	if _returning:
		return

	await get_tree().process_frame
	if _returning:
		return

	_setup_slide_in_state()
	await _play_slide_in()
	if _returning:
		return

	await _play_label_popups()
	if _returning:
		return

	var earned_xp: int = 0
	var starting_xp: int = 0
	
	# Attempt to access via the global class name, with a fallback to group search
	# to bypass potential Godot parser/scope delays with new class_names.
	var pm_node = get_tree().get_first_node_in_group("player_manager")
	if pm_node:
		earned_xp = int(pm_node.session_earned_xp)
		starting_xp = pm_node.local_base_xp
	
	await _play_xp_progression(earned_xp, starting_xp)
	if _returning:
		return

	_show_return_home_phase()


func _setup_slide_in_state() -> void:
	if color_bg != null:
		_base_color_bg_position = color_bg.position
	if color_bg2 != null:
		_base_color_bg2_position = color_bg2.position

	var viewport_width := get_viewport().get_visible_rect().size.x

	if color_bg != null:
		color_bg.position = Vector2(viewport_width + 140.0, _base_color_bg_position.y)

	if color_bg2 != null:
		color_bg2.position = Vector2(viewport_width + 200.0, _base_color_bg2_position.y)

	for label in _get_intro_labels():
		_reset_label_for_pop(label)


func _play_slide_in() -> void:
	if _timeline_tween != null:
		_timeline_tween.kill()

	_timeline_tween = create_tween()
	_timeline_tween.set_parallel(true)

	if color_bg != null:
		_timeline_tween.tween_property(color_bg, "position:x", _base_color_bg_position.x, 0.75).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	if color_bg2 != null:
		_timeline_tween.tween_property(color_bg2, "position:x", _base_color_bg2_position.x, 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	await _timeline_tween.finished


func _play_label_popups() -> void:
	for label in _get_intro_labels():
		if _returning:
			return
		if label == null:
			continue

		label.visible = true

		if _timeline_tween != null:
			_timeline_tween.kill()

		_timeline_tween = create_tween()
		_timeline_tween.set_parallel(true)
		_timeline_tween.tween_property(label, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_timeline_tween.tween_property(label, "scale", Vector2.ONE, 0.38).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		await _timeline_tween.finished
		await get_tree().create_timer(0.04).timeout


func _play_xp_progression(earned_xp: int, starting_xp: int) -> void:
	if progress_bar == null:
		return

	progress_bar.visible = true
	
	var accumulated_total_xp := starting_xp
	var current_level := _get_level_from_xp(accumulated_total_xp)
	var xp_in_current_level := accumulated_total_xp - _get_xp_required_for_level(current_level)
	var level_requirement := _get_segment_requirement(current_level)
	
	progress_bar.max_value = float(level_requirement)
	progress_bar.value = float(xp_in_current_level)

	if level_label != null:
		level_label.visible = true
		level_label.text = "Level " + str(current_level)

	if xp_label != null:
		xp_label.visible = true
		xp_label.text = "XP " + str(accumulated_total_xp)

	var remaining_to_add := earned_xp

	while remaining_to_add > 0 and not _returning:
		var space_in_level := level_requirement - xp_in_current_level
		var gain := mini(remaining_to_add, space_in_level)
		
		if _timeline_tween != null:
			_timeline_tween.kill()

		_timeline_tween = create_tween()
		_timeline_tween.tween_property(progress_bar, "value", float(xp_in_current_level + gain), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		await _timeline_tween.finished

		accumulated_total_xp += gain
		remaining_to_add -= gain
		xp_in_current_level += gain

		if xp_label != null:
			xp_label.text = "XP " + str(accumulated_total_xp)

		if xp_in_current_level >= level_requirement:
			current_level += 1
			xp_in_current_level = 0
			level_requirement = _get_segment_requirement(current_level)
			progress_bar.max_value = float(level_requirement)
			progress_bar.value = 0.0
			if level_label != null:
				level_label.text = "Level " + str(current_level)
			await get_tree().create_timer(0.08).timeout

func _get_level_from_xp(xp: int) -> int:
	var lvl := 0
	var req := _get_segment_requirement(lvl)
	var temp_xp := xp
	while temp_xp >= req:
		temp_xp -= req
		lvl += 1
		req = _get_segment_requirement(lvl)
	return lvl

func _get_xp_required_for_level(level: int) -> int:
	var total := 0
	for i in range(level):
		total += _get_segment_requirement(i)
	return total


func _show_return_home_phase() -> void:
	if progress_bar != null:
		progress_bar.visible = false

	if level_label != null:
		level_label.visible = false

	if xp_label != null:
		xp_label.visible = false

	if return_home_label != null:
		countdown_time = RETURN_HOME_COUNTDOWN
		return_home_label.visible = true
		_update_countdown_label()

	if skip_button != null:
		skip_button.visible = true

	_countdown_timer = Timer.new()
	_countdown_timer.one_shot = false
	_countdown_timer.wait_time = 1.0
	_countdown_timer.timeout.connect(_on_countdown_tick)
	add_child(_countdown_timer)
	_countdown_timer.start()


func _get_intro_labels() -> Array[Label]:
	return [result_title, result_subtitle, result_details]


func _reset_label_for_pop(label: Label) -> void:
	if label == null:
		return
	label.visible = true
	label.modulate.a = 0.0
	label.scale = Vector2.ONE * 0.65


func _get_segment_requirement(segment_index: int) -> int:
	return LEVEL_STEP_BASE * (segment_index + 1)


func _update_countdown_label() -> void:
	if return_home_label != null:
		return_home_label.text = "Returning to Lobby >> " + str(countdown_time)


func _on_countdown_tick() -> void:
	if _returning:
		return

	countdown_time -= 1
	_update_countdown_label()

	if countdown_time <= 0:
		_force_return_to_lobby()


func _force_return_to_lobby() -> void:
	if _returning:
		return

	_returning = true

	if _timeline_tween != null:
		_timeline_tween.kill()
		_timeline_tween = null

	if _countdown_timer != null:
		_countdown_timer.stop()
		_countdown_timer.queue_free()
		_countdown_timer = null

	if OS.has_feature("web"):
		JavaScriptBridge.eval("if(window.history.length > 1) { window.history.back(); } else { window.location.href = '/dashboard'; }")
	else:
		get_tree().quit()
