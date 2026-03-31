extends VBoxContainer


# Called when the node enters the scene tree for the first time.
func _ready():
	# Connect the pressed signal
	#pressed.connect(_on_pressed)

	# Position button 100px above bottom and 100px left from right edge
	var viewport_size = get_viewport().get_visible_rect().size
	global_position = Vector2(
		viewport_size.x - 100,   # 100px left from right edge
		viewport_size.y - 210    # 100px above bottom edge
	)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
