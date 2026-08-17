extends ProgressBar

var _cached_player: Node = null

func _process(_delta: float) -> void:
	if _cached_player == null or not is_instance_valid(_cached_player):
		_cached_player = get_tree().get_first_node_in_group("local_player")

	if _cached_player == null:
		return

	value = _cached_player.get("stamina")
