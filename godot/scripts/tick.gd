extends Node

@export var world: WorldEnvironment
@export var countdown: Label
@export var waiting_for_players: bool = false

# Countdown in seconds
var time_left: float = 120.0

# Fog colors
var start_color: Color = Color8(152, 227, 254) # #98e3fe
var end_color: Color = Color8(241, 118, 254)   # #f176fe

func _ready():
	# Create a unique copy of the environment so we can modify it 
	# without affecting the original resource file or other scenes.
	if world.environment:
		world.environment = world.environment.duplicate()

func _process(delta):
	if waiting_for_players:
		if countdown:
			countdown.text = "Waiting for players"
		return
	if time_left > 0:
		time_left -= delta
		if time_left < 0:
			time_left = 0
		
		# Update label (format as MM:SS)
		var minutes = int(time_left) / 60
		var seconds = int(time_left) % 60
		countdown.text = "%02d:%02d" % [minutes, seconds]
		
		# Interpolate fog color
		var t = 1.0 - (time_left / 120.0) # 0 -> 1 over countdown
		var current_color = start_color.lerp(end_color, t)
		
		if world.environment:
			# Update Standard Fog Color
			world.environment.fog_light_color = current_color
			
			# Update Volumetric Fog Color (just in case you are using this instead)
			world.environment.volumetric_fog_albedo = current_color

func set_waiting_for_players(is_waiting: bool) -> void:
	waiting_for_players = is_waiting
	if waiting_for_players and countdown:
		countdown.text = "Waiting for players"
