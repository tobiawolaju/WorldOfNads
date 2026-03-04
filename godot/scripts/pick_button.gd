extends TextureButton

func _ready():
	pressed.connect(_on_pressed)

func _on_pressed():
	Input.action_press("pickup")
	print("pressed")
