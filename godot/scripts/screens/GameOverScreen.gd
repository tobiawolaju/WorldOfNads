extends CanvasLayer

const DUMMY_XP := 55
const LEVEL_STEP_BASE := 10
const RETURN_HOME_COUNTDOWN := 8
const LOBBY_SCENE_PATH := "res://scenes/lobby.tscn"
const DASHBOARD_SCENE_PATH := "res://scenes/dshbord.tscn"

# Design palette shared with login.tscn / dshbord.tscn.
const WIN_COLOR := Color(0.43137255, 0.32941177, 1.0, 1.0)
const WIN_COLOR_ALT := Color(0.34509805, 0.23137255, 0.83137256, 1.0)
const LOSE_COLOR := Color(0.9411765, 0.22352941, 0.45490196, 1.0)
const LOSE_COLOR_ALT := Color(0.75686276, 0.14509805, 0.36078432, 1.0)
## The card's gold, used for money the round actually earned.
const MON_COLOR := Color(1.0, 0.84313726, 0.0, 1.0)
## Used when there is no money to show: muted, so a zero never reads as a loss.
const MON_MUTED_COLOR := Color(1.0, 1.0, 1.0, 0.55)


@onready var color_bg: ColorRect = get_node_or_null("ColorBG") as ColorRect
@onready var color_bg2: ColorRect = get_node_or_null("ColorBG2") as ColorRect
@onready var result_panel: VBoxContainer = get_node_or_null("ColorBG/Result") as VBoxContainer
@onready var result_title: Label = get_node_or_null("ColorBG/Result/BoxContainer/Title") as Label
@onready var result_subtitle: Label = get_node_or_null("ColorBG/Result/BoxContainer2/Subtitle") as Label
@onready var result_details: Label = get_node_or_null("ColorBG/Result/BoxContainer3/Details") as Label
## The round's money, under the result line. Hidden until a value is known, so a
## result screen with no player manager never shows a bare "+0.0000 MON".
@onready var mon_earned_label: Label = get_node_or_null("ColorBG/Result/BoxContainer6/MonEarned") as Label
@onready var result_card: Panel = get_node_or_null("ColorBG/Result/BoxContainer4/Control/ResultCard") as Panel
@onready var progress_bar: ProgressBar = get_node_or_null("ColorBG/Result/BoxContainer4/Control/ResultCard/ProgressBar") as ProgressBar
@onready var level_label: Label = get_node_or_null("ColorBG/Result/BoxContainer4/Control/ResultCard/Level") as Label
@onready var xp_label: Label = get_node_or_null("ColorBG/Result/BoxContainer4/Control/ResultCard/XP") as Label
@onready var xp_gain_label: Label = get_node_or_null("ColorBG/Result/BoxContainer4/Control/ResultCard/GainLabel") as Label
@onready var return_home_label: Label = get_node_or_null("ColorBG/Result/BoxContainer4/Control/returnhome") as Label
@onready var skip_button: Button = get_node_or_null("ColorBG/Result/BoxContainer4/Control/skiptimmer") as Button

var countdown_time := RETURN_HOME_COUNTDOWN
var _timeline_tween: Tween
var _countdown_timer: Timer
var _returning := false
var _base_color_bg_position := Vector2.ZERO
var _base_color_bg2_position := Vector2.ZERO
var _action_row: HBoxContainer = null
var _did_win: bool = false


func _ready() -> void:
	layer = 100

	if skip_button != null:
		skip_button.pressed.connect(_on_play_again_pressed)

	var did_win := false
	var victory_type := "unknown"
	var split_info: Dictionary = {}

	if get_tree().has_meta("match_result_won"):
		did_win = bool(get_tree().get_meta("match_result_won"))
	if get_tree().has_meta("match_result_victory_type"):
		victory_type = str(get_tree().get_meta("match_result_victory_type"))
	if get_tree().has_meta("match_result_split_info"):
		split_info = get_tree().get_meta("match_result_split_info")

	_did_win = did_win
	_apply_result(did_win, victory_type, split_info)
	call_deferred("_play_sequence")


func _apply_result(did_win: bool, victory_type: String = "legacy", split_info: Dictionary = {}) -> void:
	if color_bg != null:
		color_bg.visible = true
		color_bg.color = WIN_COLOR if did_win else LOSE_COLOR

	if color_bg2 != null:
		color_bg2.visible = true
		color_bg2.color = WIN_COLOR_ALT if did_win else LOSE_COLOR_ALT

	if result_panel != null:
		result_panel.visible = true

	# Victory type specific messaging.
	var title_text = "Congratulations"
	var subtitle_text = "You won"
	var details_text = "You outplayed other nads"

	match victory_type:
		"instant":
			title_text = "VICTORY!"
			subtitle_text = "60s Possession Reached"
			details_text = "You held the chicken for 60 seconds and won instantly!"
		"buzzer":
			if split_info.get("split", false):
				title_text = "Match Ended"
				subtitle_text = "Reward Split"
				var holder_name = split_info.get("holderName", "Holder")
				var progress_name = split_info.get("progressName", "Progress Leader")
				var holder_pct = int(split_info.get("holderShare", 0.5) * 100)
				var progress_pct = int(split_info.get("progressShare", 0.5) * 100)
				if did_win:
					details_text = "%s held the chicken (%d%%); %s had most possession (%d%%)" % [holder_name, holder_pct, progress_name, progress_pct]
				else:
					details_text = "Reward split between chicken holder and possession leader."
			elif did_win:
				title_text = "Congratulations"
				subtitle_text = "Buzzer Victory"
				details_text = "You won when time expired!"
			else:
				title_text = "Time's Up"
				subtitle_text = "You didn't win"
				details_text = "The match ended before you could win."
		"legacy":
			if did_win:
				title_text = "Congratulations"
				subtitle_text = "You won"
				details_text = "You outplayed other nads"
			else:
				title_text = "You almost made it"
				subtitle_text = "You tried"
				details_text = "You got outplayed"
		_:  # fallback
			if did_win:
				title_text = "Congratulations"
				subtitle_text = "You won"
				details_text = "You won the match"
			else:
				title_text = "Match Over"
				subtitle_text = "No victory"
				details_text = ""

	if result_title != null:
		result_title.text = title_text
		result_title.add_theme_color_override("font_color", Color.WHITE)

	if result_subtitle != null:
		result_subtitle.text = subtitle_text
		result_subtitle.add_theme_color_override("font_color", Color.WHITE)

	if result_details != null:
		result_details.text = details_text
		result_details.add_theme_color_override("font_color", Color.WHITE)

	var mon_values := _session_mon()
	_apply_mon_line(mon_values.x, mon_values.y)

	if progress_bar != null:
		progress_bar.visible = false
		progress_bar.value = 0.0

	if result_card != null:
		result_card.visible = false

	if level_label != null:
		level_label.visible = false
		level_label.text = "LEVEL 0"

	if xp_label != null:
		xp_label.visible = false
		xp_label.text = "0 XP"

	if xp_gain_label != null:
		xp_gain_label.visible = false
		xp_gain_label.text = ""

	if return_home_label != null:
		return_home_label.visible = false

	if skip_button != null:
		skip_button.visible = false


func _session_mon() -> Vector2:
	# The player manager is the only node that saw the server's reward ticks. It
	# is absent in tests and in a result screen opened from the dashboard, which
	# reads as "nothing earned" instead of erroring.
	var earned := 0.0
	var pool := 0.0
	var pm_node := get_tree().get_first_node_in_group("player_manager")
	if pm_node != null:
		var earned_value: Variant = pm_node.get("session_earned_mon")
		if typeof(earned_value) == TYPE_FLOAT or typeof(earned_value) == TYPE_INT:
			earned = float(earned_value)
		var pool_value: Variant = pm_node.get("session_pool_mon")
		if typeof(pool_value) == TYPE_FLOAT or typeof(pool_value) == TYPE_INT:
			pool = float(pool_value)
	return Vector2(earned, pool)


## Shows the round's money, or says plainly why there is none.
##
## A room with no escrow behind it (the shared practice lobby) can never pay MON,
## so it says so instead of showing a zero that reads like a loss. That is also
## why the HUD hides the MON stream there: nothing is on its way.
func _apply_mon_line(earned: float, pool: float) -> void:
	if mon_earned_label == null:
		return
	if earned > 0.0:
		mon_earned_label.text = "+ %.4f MON" % earned
		mon_earned_label.add_theme_color_override("font_color", MON_COLOR)
	elif pool <= 0.0:
		mon_earned_label.text = "No prize pool in this room"
		mon_earned_label.add_theme_color_override("font_color", MON_MUTED_COLOR)
	else:
		mon_earned_label.text = "No MON this round"
		mon_earned_label.add_theme_color_override("font_color", MON_MUTED_COLOR)
	mon_earned_label.visible = true


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

	if result_card != null:
		result_card.visible = true
		result_card.modulate.a = 0.0
		result_card.scale = Vector2.ONE * 0.92
		result_card.pivot_offset = result_card.size * 0.5

	progress_bar.visible = true
	progress_bar.value = 0.0

	if level_label != null:
		level_label.visible = true

	if xp_label != null:
		xp_label.visible = true

	if xp_gain_label != null:
		xp_gain_label.visible = true
		xp_gain_label.text = "+" + str(earned_xp) + " XP"
		xp_gain_label.pivot_offset = xp_gain_label.size * 0.5
		xp_gain_label.scale = Vector2.ONE * 0.5

	# Reveal the result card before the numbers start ticking up.
	if result_card != null:
		if _timeline_tween != null:
			_timeline_tween.kill()
		_timeline_tween = create_tween()
		_timeline_tween.set_parallel(true)
		_timeline_tween.tween_property(result_card, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_timeline_tween.tween_property(result_card, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_timeline_tween.tween_property(xp_gain_label, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		await _timeline_tween.finished

	if _returning:
		return

	var accumulated_total_xp := starting_xp
	var current_level := _get_level_from_xp(accumulated_total_xp)
	var xp_in_current_level := accumulated_total_xp - _get_xp_required_for_level(current_level)
	var level_requirement := _get_segment_requirement(current_level)

	progress_bar.max_value = float(level_requirement)
	progress_bar.value = float(xp_in_current_level)

	if level_label != null:
		level_label.text = "LEVEL " + str(current_level)

	if xp_label != null:
		xp_label.text = str(accumulated_total_xp) + " XP"

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
			xp_label.text = str(accumulated_total_xp) + " XP"

		if xp_in_current_level >= level_requirement:
			current_level += 1
			xp_in_current_level = 0
			level_requirement = _get_segment_requirement(current_level)
			progress_bar.max_value = float(level_requirement)
			progress_bar.value = 0.0
			if level_label != null:
				level_label.text = "LEVEL " + str(current_level)
			_play_level_up_flash()
			await get_tree().create_timer(0.08).timeout


func _play_level_up_flash() -> void:
	if result_card == null:
		return
	var flash := create_tween()
	flash.tween_property(result_card, "modulate", Color(1.35, 1.3, 1.1, 1.0), 0.12)
	flash.tween_property(result_card, "modulate", Color.WHITE, 0.22)


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
	if result_card != null:
		result_card.visible = false

	if progress_bar != null:
		progress_bar.visible = false

	if level_label != null:
		level_label.visible = false

	if xp_label != null:
		xp_label.visible = false

	if xp_gain_label != null:
		xp_gain_label.visible = false

	# Replace the old auto-countdown label with clear retention actions:
	# jump straight back into the lobby (play again) or head to the dashboard.
	if return_home_label != null:
		return_home_label.visible = false
	if skip_button != null:
		skip_button.visible = false

	_build_action_buttons()


func _build_action_buttons() -> void:
	if _action_row != null and is_instance_valid(_action_row):
		return
	var control := get_node_or_null("ColorBG/Result/BoxContainer4/Control") as Control
	if control == null:
		return

	_action_row = HBoxContainer.new()
	_action_row.name = "ActionRow"
	_action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_action_row.add_theme_constant_override("separation", 14)
	_action_row.set_anchors_preset(Control.PRESET_CENTER)
	_action_row.offset_left = -180.0
	_action_row.offset_top = -24.0
	_action_row.offset_right = 180.0
	_action_row.offset_bottom = 24.0
	_action_row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_action_row.grow_vertical = Control.GROW_DIRECTION_BOTH
	control.add_child(_action_row)

	var play_again := _make_action_button("PLAY AGAIN", true)
	play_again.pressed.connect(_on_play_again_pressed)
	_action_row.add_child(play_again)

	var dashboard := _make_action_button("DASHBOARD", false)
	dashboard.pressed.connect(_on_dashboard_pressed)
	_action_row.add_child(dashboard)

	# Pop the buttons in so the choice feels responsive and intentional.
	_action_row.modulate.a = 0.0
	_action_row.scale = Vector2.ONE * 0.92
	_action_row.pivot_offset = Vector2(180.0, 24.0)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_action_row, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(_action_row, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _did_win:
		_spawn_confetti()
	_pulse_play_again(play_again)
	play_again.grab_focus()


func _make_action_button(text: String, primary: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(150.0, 46.0)
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var font := load("res://assets/fonts/font1.ttf") as Font
	if font != null:
		btn.add_theme_font_override("font", font)
	btn.add_theme_font_size_override("font_size", 20)

	var bg := Color(1.0, 0.84313726, 0.0, 1.0) if primary else Color(1.0, 1.0, 1.0, 0.12)
	var bg_hover := Color(1.0, 0.9, 0.35, 1.0) if primary else Color(1.0, 1.0, 1.0, 0.22)
	var bg_pressed := Color(0.9, 0.74, 0.0, 1.0) if primary else Color(1.0, 1.0, 1.0, 0.28)
	var fg := Color(0.0, 0.0, 0.0, 1.0) if primary else Color(1.0, 1.0, 1.0, 1.0)

	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.skew = Vector2(0.24, 0)
		sb.content_margin_left = 22.0
		sb.content_margin_right = 22.0
		sb.content_margin_top = 6.0
		sb.content_margin_bottom = 6.0
		match state:
			"hover":
				sb.bg_color = bg_hover
			"pressed":
				sb.bg_color = bg_pressed
			"disabled":
				sb.bg_color = bg
				sb.border_width_left = 2
				sb.border_width_top = 2
				sb.border_width_right = 2
				sb.border_width_bottom = 2
				sb.border_color = Color(1, 1, 1, 0.2)
			_:
				sb.bg_color = bg
		if not primary and state in ["normal", "focus"]:
			sb.border_width_left = 2
			sb.border_width_top = 2
			sb.border_width_right = 2
			sb.border_width_bottom = 2
			sb.border_color = Color(1, 1, 1, 0.45)
		btn.add_theme_stylebox_override(state, sb)

	for col_state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		btn.add_theme_color_override(col_state, fg)
	return btn


func _spawn_confetti() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var colors := [
		Color(1.0, 0.843, 0.0, 1.0),   # gold
		Color(0.431, 0.329, 1.0, 1.0), # purple
		Color(1.0, 0.478, 0.714, 1.0), # pink
		Color(0.31, 1.0, 0.0, 1.0),    # green
		Color(1.0, 1.0, 1.0, 1.0),     # white
		Color(0.0, 0.85, 1.0, 1.0),    # cyan
	]
	for i in range(3):
		var p := CPUParticles2D.new()
		p.position = Vector2(viewport_size.x * (0.2 + 0.3 * i), -10.0)
		p.emitting = true
		p.one_shot = false
		p.amount = 28
		p.lifetime = 2.8
		p.preprocess = 0.2
		p.explosiveness = 0.15
		p.randomness = 0.6
		p.direction = Vector2(0, 1)
		p.spread = 35.0
		p.gravity = Vector2(0, 220)
		p.initial_velocity_min = 120.0
		p.initial_velocity_max = 260.0
		p.angular_velocity_min = -180.0
		p.angular_velocity_max = 180.0
		p.scale_amount_min = 3.0
		p.scale_amount_max = 7.0
		p.color = colors[i % colors.size()]
		# A second burst of varied colors via color_ramp isn't available on
		# CPUParticles2D without a gradient resource; use multiple emitters.
		add_child(p)
		# Stop emitting after a few seconds but let particles fall out.
		var stop := get_tree().create_timer(2.4)
		stop.timeout.connect(func(): if is_instance_valid(p): p.emitting = false)
		var cleanup := get_tree().create_timer(6.0)
		cleanup.timeout.connect(func(): if is_instance_valid(p): p.queue_free())
	# A few extra accent emitters with different colors.
	for i in range(2):
		var p := CPUParticles2D.new()
		p.position = Vector2(viewport_size.x * (0.35 + 0.3 * i), -10.0)
		p.emitting = true
		p.one_shot = false
		p.amount = 22
		p.lifetime = 2.6
		p.explosiveness = 0.2
		p.randomness = 0.7
		p.direction = Vector2(0, 1)
		p.spread = 40.0
		p.gravity = Vector2(0, 240)
		p.initial_velocity_min = 100.0
		p.initial_velocity_max = 240.0
		p.angular_velocity_min = -220.0
		p.angular_velocity_max = 220.0
		p.scale_amount_min = 2.5
		p.scale_amount_max = 6.0
		p.color = colors[(i + 3) % colors.size()]
		add_child(p)
		var stop := get_tree().create_timer(2.2)
		stop.timeout.connect(func(): if is_instance_valid(p): p.emitting = false)
		var cleanup := get_tree().create_timer(5.5)
		cleanup.timeout.connect(func(): if is_instance_valid(p): p.queue_free())


func _pulse_play_again(btn: Button) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	btn.pivot_offset = btn.size * 0.5
	var pulse := create_tween().set_loops()
	pulse.tween_property(btn, "scale", Vector2(1.04, 1.04), 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


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
		_on_play_again_pressed()


func _current_match_and_skin() -> Dictionary:
	var match_id := ""
	var skin_id := "s-default"
	var pm_node := get_tree().get_first_node_in_group("player_manager")
	if pm_node != null:
		for key in ["local_match_id", "selected_match_id"]:
			var v = pm_node.get(key)
			if typeof(v) == TYPE_STRING and str(v).strip_edges() != "":
				match_id = str(v).strip_edges()
				break
		for key in ["local_skin_name", "selected_skin_id"]:
			var v = pm_node.get(key)
			if typeof(v) == TYPE_STRING and str(v).strip_edges() != "":
				skin_id = str(v).strip_edges()
				break
	return {"match_id": match_id, "skin_id": skin_id}


func _on_play_again_pressed() -> void:
	if _returning:
		return
	_returning = true
	_cleanup_timers()

	var ctx := _current_match_and_skin()
	var match_id: String = str(ctx.get("match_id", ""))
	var skin_id: String = str(ctx.get("skin_id", "s-default"))

	if OS.has_feature("web") and match_id != "":
		# Keep the browser URL in step so a reload rejoins the same room with
		# the same skin, matching the dashboard -> lobby handoff.
		var js_match := match_id.replace("\\", "\\\\").replace("'", "\\'")
		var js_skin := skin_id.replace("\\", "\\\\").replace("'", "\\'")
		JavaScriptBridge.eval(
			(
				"(() => { const p = new URLSearchParams(window.location.search);"
				+ " p.set('match', '%s'); p.set('skin', '%s');"
				+ " window.history.replaceState({}, '', window.location.pathname + '?' + p.toString()); })();"
			) % [js_match, js_skin]
		)

	var payload := {}
	if match_id != "":
		payload["selected_match_id"] = match_id
	if skin_id != "":
		payload["selected_skin_id"] = skin_id

	var game := get_node_or_null("/root/Game")
	var transition = game.get("transition_layer") if game != null else null
	if transition != null and transition.has_method("change_scene"):
		transition.call("change_scene", LOBBY_SCENE_PATH, payload)
	else:
		# Fallback: swap directly (e.g. running the scene standalone).
		var packed := load(LOBBY_SCENE_PATH) as PackedScene
		if packed != null:
			var inst := packed.instantiate()
			for k in payload.keys():
				if inst.get(k) != null or k in ["selected_match_id", "selected_skin_id"]:
					inst.set(k, payload[k])
			var tree := get_tree()
			var prev := tree.current_scene
			tree.root.add_child(inst)
			tree.current_scene = inst
			if prev != null and prev != inst:
				prev.queue_free()
		else:
			get_tree().change_scene_to_file(LOBBY_SCENE_PATH)


func _on_dashboard_pressed() -> void:
	if _returning:
		return
	_returning = true
	_cleanup_timers()

	var game := get_node_or_null("/root/Game")
	var transition = game.get("transition_layer") if game != null else null
	if transition != null and transition.has_method("change_scene"):
		transition.call("change_scene", DASHBOARD_SCENE_PATH)
	else:
		get_tree().change_scene_to_file(DASHBOARD_SCENE_PATH)


func _cleanup_timers() -> void:
	if _timeline_tween != null:
		_timeline_tween.kill()
		_timeline_tween = null
	if _countdown_timer != null:
		_countdown_timer.stop()
		_countdown_timer.queue_free()
		_countdown_timer = null


# Kept for compatibility with older call sites/tests that expect this name.
func _force_return_to_lobby() -> void:
	_on_play_again_pressed()
