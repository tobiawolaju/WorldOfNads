extends Node

@export var status_label: Label3D

# URL to "wake up" the server (can be the WS URL)
const SERVER_URL := "wss://worldofnads.onrender.com"

func _ready():
	status_label.text = "Waking up game server..."
	_wake_server()


func _wake_server():
	# Create a dummy HTTPRequest just to ping the server
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(_on_server_ping_completed)
	
	# Use HTTPS endpoint to wake the server if your WS server doesn’t support HTTP ping
	# If your WS server is only WS, you could just skip sending anything
	req.request("https://worldofnads.onrender.com") 


func _on_server_ping_completed(result, response_code, headers, body):
	# Ignore errors, we just want to wake the server
	for i in range(5, 0, -1):
		status_label.text = "Server awake. Loading in %d..." % i
		await get_tree().create_timer(1.0).timeout
	status_label.text = "Let's go!"
	
	# Load the real gameplay scene that connects via WebSocket
	TransitionScreen.change_scene("res://scenes/gameplay2d.tscn")
