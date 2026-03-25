extends Node

@export var status_label: Label3D

# URL to "wake up" the server (can be the WS URL)
const SERVER_URL := "wss://worldofnads-129481786742.europe-west1.run.app"

func _ready():
	status_label.text = "🔄 Waking up game server..."
	_wake_server()


func _wake_server():
	# Create a dummy HTTPRequest just to ping the server
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(_on_server_ping_completed)
	
	# Use HTTPS endpoint to wake the server if your WS server doesn’t support HTTP ping
	# If your WS server is only WS, you could just skip sending anything
	req.request("https://worldofnads-129481786742.europe-west1.run.app") 


func _on_server_ping_completed(result, response_code, headers, body):
	# Ignore errors, we just want to wake the server
	status_label.text = "✅ Server awake. Loading game..."
	
	# Load the real gameplay scene that connects via WebSocket
	get_tree().change_scene_to_file("res://scenes/gameplay2d.tscn")
