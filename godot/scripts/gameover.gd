extends Node2D

@onready var winner_panel: CanvasItem = get_node_or_null("Node2/Winner")
@onready var loser_panel: CanvasItem = get_node_or_null("Node2/Loser")
@onready var winner_bg: CanvasItem = get_node_or_null("WinnerBg")
@onready var loser_bg: CanvasItem = get_node_or_null("LoserBg")

func _ready() -> void:
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
