extends Control

## Simple WebSocket connectivity tester for native editor / exports.
## Tests a sequence of ws:// and wss:// endpoints and logs results to Output.
##
## Usage:
## 1. (Optional) Start local room server: `cd backend-rust && cargo run`
##    - serves plain WS at ws://127.0.0.1:8080 (no WSS by default)
## 2. Open/run this scene in the native editor.
## 3. Watch [WS_TEST] logs for URL, state transitions, and close code/reason.

@export var test_urls: PackedStringArray = PackedStringArray([
	"ws://127.0.0.1:8080/?skin=s-default",
	"wss://wons-room-server.onrender.com/?skin=s-default",
	"wss://wons-room-server.onrender.com/events",
	"wss://worldofnads.onrender.com/?skin=s-default",
	# Local WSS requires a TLS terminator/proxy in front of backend-rust (not provided by default).
	# Example: "wss://localhost:8443/?skin=s-default"
])
@export var per_test_timeout_sec: float = 12.0
@export var unsafe_tls_for_wss: bool = false
# How long to keep a successful connection open before closing it. This is what
# distinguishes "handshake accepted" from "server accepted then immediately dropped".
@export var hold_open_sec: float = 1.5

var _index: int = -1
var _peer: WebSocketPeer = WebSocketPeer.new()
var _active: bool = false
var _start_ms: int = 0
var _last_state: int = -1
var _opened: bool = false
var _open_at_ms: int = 0
var _label: Label

var _auto_quit: bool = false

func _ready() -> void:
	_auto_quit = "--auto-quit" in OS.get_cmdline_user_args()
	_label = get_node_or_null("StatusLabel") as Label
	_log("WebSocket test scene ready")
	_log("unsafe_tls_for_wss=%s timeout=%.1fs auto_quit=%s" % [str(unsafe_tls_for_wss), per_test_timeout_sec, str(_auto_quit)])
	_apply_cli_urls()
	_start_next()

# Allows headless runs like:
#   godot --headless --path godot --scene res://scenes/test_ws.tscn -- \
#     ws://127.0.0.1:8080/?skin=s-default wss://wons-room-server.onrender.com/?skin=s-default \
#     --auto-quit
func _apply_cli_urls() -> void:
	# Godot treats `--` as "everything after this is for the game". Look at both
	# sources so `--headless --scene ... -- url1 url2` works as expected.
	var urls := PackedStringArray()
	var raw := PackedStringArray(OS.get_cmdline_args())
	raw.append_array(OS.get_cmdline_user_args())
	var after_sep := false
	for arg in raw:
		if arg == "--":
			after_sep = true
			continue
		if not after_sep:
			continue
		if arg.begins_with("--"):
			continue
		urls.append(str(arg))
	if urls.size() > 0:
		test_urls = urls

func _process(_delta: float) -> void:
	if not _active:
		return

	_peer.poll()
	var state := _peer.get_ready_state()
	if state != _last_state:
		_last_state = state
		_log("state=%s" % _state_name(state))

	if state == WebSocketPeer.STATE_OPEN:
		if not _opened:
			_opened = true
			_open_at_ms = Time.get_ticks_msec()
			_log("OPEN ok (connected successfully)")
		# Drain any packets the server sends while we hold the connection, so an
		# immediate server-side rejection is visible instead of being hidden.
		var packets := 0
		while _peer.get_available_packet_count() > 0 and packets < 8:
			packets += 1
			var pkt := _peer.get_packet()
			var preview := pkt.slice(0, mini(pkt.size(), 120)).get_string_from_utf8()
			_log("recv packet bytes=%d preview=%s" % [pkt.size(), JSON.stringify(preview)])
		if Time.get_ticks_msec() - _open_at_ms >= int(hold_open_sec * 1000.0):
			_log("held open %.1fs; closing" % hold_open_sec)
			_peer.close(1000, "test_done")
		return

	if state == WebSocketPeer.STATE_CLOSED:
		var code := _peer.get_close_code()
		var reason := _peer.get_close_reason()
		_log("CLOSED close_code=%d reason='%s' opened=%s elapsed_ms=%d" % [
			code, reason, str(_opened), Time.get_ticks_msec() - _start_ms
		])
		_finish_current()
		return

	# CONNECTING/CLOSING timeout guard
	if Time.get_ticks_msec() - _start_ms > int(per_test_timeout_sec * 1000.0):
		_log("TIMEOUT after %.1fs in state=%s" % [per_test_timeout_sec, _state_name(state)])
		_peer.close()
		_finish_current()

func _start_next() -> void:
	_index += 1
	if _index >= test_urls.size():
		_active = false
		_log("All tests finished")
		_set_label("All tests finished. See Output for [WS_TEST] logs.")
		if _auto_quit:
			await get_tree().create_timer(0.2).timeout
			get_tree().quit()
		return

	var url := String(test_urls[_index]).strip_edges()
	if url == "":
		_start_next()
		return

	_peer = WebSocketPeer.new()
	_active = true
	_opened = false
	_last_state = -1
	_start_ms = Time.get_ticks_msec()
	_log("--- TEST %d/%d ---" % [_index + 1, test_urls.size()])
	_log("Connecting: %s" % url)
	_set_label("Testing (%d/%d): %s" % [_index + 1, test_urls.size(), url])

	var tls: TLSOptions = null
	if url.begins_with("wss://") and unsafe_tls_for_wss:
		tls = TLSOptions.client_unsafe()
		_log("Using TLSOptions.client_unsafe() for this WSS attempt")
	elif url.begins_with("wss://"):
		_log("Using default TLS verification for this WSS attempt")

	var err := _peer.connect_to_url(url, tls) if tls != null else _peer.connect_to_url(url)
	if err != OK:
		_log("connect_to_url returned err=%s (%d)" % [error_string(err), err])
		_active = false
		# move on to next test
		await get_tree().process_frame
		_start_next()

func _finish_current() -> void:
	_active = false
	# Small delay between tests to keep logs readable.
	await get_tree().create_timer(0.5).timeout
	_start_next()

func _state_name(state: int) -> String:
	match state:
		WebSocketPeer.STATE_CONNECTING:
			return "CONNECTING"
		WebSocketPeer.STATE_OPEN:
			return "OPEN"
		WebSocketPeer.STATE_CLOSING:
			return "CLOSING"
		WebSocketPeer.STATE_CLOSED:
			return "CLOSED"
		_:
			return "UNKNOWN(%d)" % state

func _set_label(text: String) -> void:
	if _label != null:
		_label.text = text

func _log(msg: String) -> void:
	print("[WS_TEST] %s" % msg)
