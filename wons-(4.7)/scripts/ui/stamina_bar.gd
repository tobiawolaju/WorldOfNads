extends ProgressBar
## Stamina bar that only shows while the player is carrying something.
##
## Stamina is only ever spent while holding an item, so the bar is hidden during normal
## free movement and fades in as soon as something is picked up. Matches the same
## holding test player.gd uses to decide whether to drain.

## How long the fade in and out take, in seconds.
const FADE_TIME: float = 0.25

var _cached_player: Node = null
var _alpha: float = 0.0
var _last_value: float = -1.0


func _ready() -> void:
	# Start hidden and let _process fade in, rather than popping on the first frame.
	modulate.a = 0.0
	# The bar is decorative while hidden, so stop it taking mouse focus / input.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if _cached_player == null or not is_instance_valid(_cached_player):
		_cached_player = get_tree().get_first_node_in_group("local_player")

	if _cached_player == null:
		# No player yet, stay hidden rather than flashing at the default value.
		_set_alpha(0.0, delta)
		return

	# Only write value when the stamina actually changed - a repeated write
	# dirties the control for a redraw every frame.
	var stamina_value := float(_cached_player.get("stamina"))
	if not is_equal_approx(stamina_value, _last_value):
		_last_value = stamina_value
		value = stamina_value

	var holding := false
	for method in ["_is_local_holding_chicken", "_is_local_holding_lootbox", "_is_local_holding_pickup"]:
		if _cached_player.has_method(method) and bool(_cached_player.call(method)):
			holding = true
			break

	var target_alpha := 1.0 if holding else 0.0
	if is_equal_approx(_alpha, target_alpha) and is_equal_approx(stamina_value, _last_value):
		return
	_set_alpha(target_alpha, delta)


func _set_alpha(target: float, delta: float) -> void:
	# Move toward the target rather than snapping, so pickup and drop both fade.
	_alpha = move_toward(_alpha, target, delta / FADE_TIME)
	# Fade via modulate only. Toggling visible here would stop _process from running at
	# alpha 0, so the bar could never fade back in on the next pickup.
	modulate.a = _alpha
