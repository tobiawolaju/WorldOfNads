extends HBoxContainer

const PORTRAIT_BOTTOM_MARGIN := 95.0
const LANDSCAPE_RIGHT_MARGIN := 245.0
const LANDSCAPE_BOTTOM_MARGIN := 95.0

func _ready() -> void:
	# This node is inside a Container; move the parent holder (if present),
	# otherwise move self.
	get_viewport().size_changed.connect(_reposition)
	_reposition()

func _reposition() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var is_portrait := viewport_size.y > viewport_size.x
	var bottom_margin := PORTRAIT_BOTTOM_MARGIN if is_portrait else LANDSCAPE_BOTTOM_MARGIN
	var target: Control = self
	var parent_control := get_parent() as Control
	if parent_control != null:
		target = parent_control

	# Force manual layout so editor anchor presets do not pin the control.
	target.set_anchors_preset(Control.PRESET_TOP_LEFT)
	if is_portrait:
		target.position = Vector2(
			(viewport_size.x - target.size.x) * 0.5,
			viewport_size.y - bottom_margin
		)
	else:
		target.position = Vector2(
			viewport_size.x - LANDSCAPE_RIGHT_MARGIN,
			viewport_size.y - bottom_margin
		)
