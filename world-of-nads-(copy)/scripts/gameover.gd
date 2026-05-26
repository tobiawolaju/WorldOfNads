extends Node2D

@onready var winner_panel: CanvasItem = get_node_or_null("Node2/Winner")
@onready var loser_panel: CanvasItem = get_node_or_null("Node2/Loser")
@onready var winner_bg: CanvasItem = get_node_or_null("WinnerBg")
@onready var loser_bg: CanvasItem = get_node_or_null("LoserBg")
@onready var lobby_countdown: Node = get_node_or_null("Node2/BoxContainer/LobbyCoundown")
@onready var skip_button: Button = get_node_or_null("Node2/skiptimmer")

var countdown_time := 15

func _ready() -> void:
	if skip_button != null:
		skip_button.pressed.connect(_return_to_lobby)

	var did_win := false
	if get_tree().has_meta("match_result_won"):
		did_win = bool(get_tree().get_meta("match_result_won"))
	_apply_result(did_win)

func _apply_result(did_win: bool) -> void:
	if winner_panel != null:
		winner_panel.visible = did_win
	if loser_panel != null:
		loser_panel.visible = not did_win
	if winner_bg != null:
		winner_bg.visible = did_win
	if loser_bg != null:
		loser_bg.visible = not did_win
	
	if lobby_countdown != null:
		_update_countdown_label()
		var timer := Timer.new()
		timer.wait_time = 1.0
		timer.autostart = true
		timer.timeout.connect(_on_countdown_tick)
		add_child(timer)

func _update_countdown_label() -> void:
	if lobby_countdown != null:
		lobby_countdown.text = "Returning to Lobby >> " + str(countdown_time)

func _on_countdown_tick() -> void:
	countdown_time -= 1
	_update_countdown_label()
	
	if countdown_time <= 0:
		_return_to_lobby()

func _return_to_lobby() -> void:
	if OS.has_feature("web"):
		# Try going back first, or default to dashboard
		JavaScriptBridge.eval("if(window.history.length > 1) { window.history.back(); } else { window.location.href = '/dashboard'; }")
	else:
		get_tree().quit()
