extends Sprite2D
## Simple double-jump indicator.
##
## Swaps this sprite's texture between the two exported images based on the local
## player's double-jump state:
##   - single_jump_image : shown while the double jump is NOT available or already used
##   - double_jump_image : shown while the double jump is available and unused
##
## The indicator lights up the moment the double jump is earned (mid-air or on the
## ground), stays on while you hold the charge, and flips to single only after you
## actually use the double jump. A charge you carry down to a landing keeps showing
## double until spent.

@export var single_jump_image: Texture2D # shown when only a single jump is available
@export var double_jump_image: Texture2D # shown when a double jump is charged

var _cached_player: Node = null

func _process(_delta: float) -> void:
	if _cached_player == null or not is_instance_valid(_cached_player):
		_cached_player = get_tree().get_first_node_in_group("local_player")

	if _cached_player == null:
		return

	var p := _cached_player
	var can_double: bool = p.get("_double_jump_available") == true and p.get("_double_jump_used") != true

	texture = double_jump_image if can_double else single_jump_image