extends Node

@export var status_label: Label

# Wake the room server (Render can sleep). Events stream uses this host; gameplay connects to it too.
const WAKE_URL := "https://wons-room-server.onrender.com/health"
const COUNTDOWN_SECONDS := 60
const EVENTS_WAIT_TIMEOUT_SEC := 45.0

var _wake_requested := false
var _countdown_started := false

func _ready() -> void:
	_set_status("Waking up game server...")
	_wake_server()
	set_process(true)

func _process(_delta: float) -> void:
	if _countdown_started:
		return
	if not _wake_requested:
		return
	var events = _get_events_bridge()
	if events != null and bool(events.get("connected")):
		_start_countdown()
		return
	# Keep waiting for events bridge/connection.

func _wake_server() -> void:
	# Fire-and-forget HTTP ping to wake Render; countdown waits for event stream connection.
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(_on_wake_completed.bind(req))
	var err := req.request(WAKE_URL)
	if err != OK:
		_on_wake_completed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray(), req)

func _on_wake_completed(_result: int, _response_code: int, _headers: PackedStringArray, _body: PackedByteArray, req: HTTPRequest) -> void:
	if req != null and is_instance_valid(req):
		req.queue_free()
	_wake_requested = true
	_set_status("Waiting for event stream...")
	_arm_events_timeout()

func _arm_events_timeout() -> void:
	await get_tree().create_timer(EVENTS_WAIT_TIMEOUT_SEC).timeout
	if _countdown_started or not is_inside_tree():
		return
	_start_countdown()

func _start_countdown() -> void:
	if _countdown_started:
		return
	_countdown_started = true
	for i in range(COUNTDOWN_SECONDS, 0, -1):
		_set_status("Server ready. Loading in %d..." % i)
		await get_tree().create_timer(1.0).timeout
	if not is_inside_tree():
		return
	_set_status("Let's go!")
	var lobby := get_parent()
	var handoff: Dictionary = {}
	if lobby != null and lobby.has_method("match_handoff"):
		handoff = lobby.match_handoff()
	Game.transition_layer.change_scene("res://scenes/gameplay.tscn", handoff)

func _get_events_bridge() -> Node:
	return get_tree().get_first_node_in_group("events_bridge")

func _set_status(text: String) -> void:
	if status_label != null and is_instance_valid(status_label):
		status_label.text = text
