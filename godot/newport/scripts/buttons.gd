extends HBoxContainer

const RIGHT_MARGIN := 237.5
const BOTTOM_MARGIN := 157.5

func _ready() -> void:
	# This node is inside a Container; move the parent holder (if present),
	# otherwise move self.
	get_viewport().size_changed.connect(_reposition)
	_reposition()

func _reposition() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var target: Control = self
	var parent_control := get_parent() as Control
	if parent_control != null:
		target = parent_control

	# Always position on the right side.
	target.set_anchors_preset(Control.PRESET_TOP_LEFT)
	target.position = Vector2(
		viewport_size.x - RIGHT_MARGIN,
		viewport_size.y - BOTTOM_MARGIN
	)
