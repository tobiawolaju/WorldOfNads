extends ProgressBar

var _cached_player: Node = null

func _process(_delta: float) -> void:
	if _cached_player == null or not is_instance_valid(_cached_player):
		_cached_player = get_tree().get_first_node_in_group("local_player")

	if _cached_player == null:
		return

	var p := _cached_player
	var on_floor: bool = p.is_on_floor()
	var can_double: bool = p.get("_double_jump_available") == true
	var used_double: bool = p.get("_double_jump_used") == true
	var ground_count: int = int(p.get("_ground_jump_count"))

	if on_floor:
		value = 100.0 if can_double or ground_count >= 1 else 50.0
	elif can_double and not used_double:
		value = 50.0
	else:
		value = 0.0
