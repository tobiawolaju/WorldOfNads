extends RefCounted
class_name WONDeviceLogin

## Owns one device-linking attempt: start -> poll -> (approved) -> exchange.
##
## Deliberately UI-free. Login.gd renders whatever state this reports and drives
## cancel/regenerate; nothing here knows about labels, colours or scenes. That
## split is what lets the same flow be reused by a HUD prompt or a test harness.
##
## Polling stops the moment the ticket reaches a terminal state, and the whole
## attempt has a hard deadline so a dropped network cannot leave the player
## staring at a QR code forever.

signal started(device_login_id: String, code: String, auth_url: String, expires_in: int)
signal status_changed(status: String)
signal progress(seconds_remaining: int)
signal approved()
signal failed(reason: String)
signal cancelled()

const STATUS_PENDING := "pending"
const STATUS_APPROVED := "approved"
const STATUS_EXPIRED := "expired"
const STATUS_USED := "used"
const STATUS_CANCELLED := "cancelled"

## States that must stop the poll loop.
const TERMINAL_STATUSES := [STATUS_EXPIRED, STATUS_USED, STATUS_CANCELLED]

var device_login_id: String = ""
## The human-readable code (e.g. "KJI-FYE"). A login ticket handle only.
var code: String = ""
var auth_url: String = ""
## High-entropy half of the credential. Required at exchange; never displayed.
var secret: String = ""
var expires_at_unix: int = 0
var poll_interval_ms: int = 1500

var status: String = "idle"
var is_active: bool = false

var _api: WONAuthAPI = null
var _platform: String = "desktop"
var _device_id: String = ""
var _device_label: String = ""
var _deadline_unix: int = 0
## Guards the countdown loop from outliving an abandoned attempt.
var _countdown_running: bool = false
## Guards against a second `_poll_loop` when `restart()` is called on a live
## instance (the loops share the `is_active` stop flag).
var _poll_loop_running: bool = false

func _init(api: WONAuthAPI, platform: String, device_id: String, device_label: String) -> void:
	_api = api
	_platform = platform
	_device_id = device_id
	_device_label = device_label

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Requests a fresh login ticket. Fails (and emits `failed`) if the backend is
## unreachable or rate limiting us.
func start() -> bool:
	stop_polling()
	status = "starting"
	device_login_id = ""
	secret = ""

	var response := await _api.device_start(_platform, _device_id, _device_label)
	if int(response.get("__status", 0)) != 200 and int(response.get("__status", 0)) != 201:
		status = "error"
		var reason := str(response.get("error", "start_failed"))
		failed.emit(reason)
		return false

	device_login_id = str(response.get("device_login_id", ""))
	code = str(response.get("code", ""))
	auth_url = str(response.get("auth_url", ""))
	secret = str(response.get("secret", ""))

	var expires_in := int(response.get("expires_in", 120))
	poll_interval_ms = maxi(500, int(response.get("poll_interval_ms", 1500)))
	expires_at_unix = Time.get_unix_time_from_system() + expires_in

	if device_login_id.is_empty() or secret.is_empty():
		status = "error"
		failed.emit("malformed_start_response")
		return false

	# Hard stop a few seconds past the server expiry so a clock-skewed client
	# cannot poll indefinitely.
	_deadline_unix = Time.get_unix_time_from_system() + expires_in + 5

	status = STATUS_PENDING
	is_active = true
	started.emit(device_login_id, code, auth_url, expires_in)
	status_changed.emit(status)
	_start_polling()
	return true

## Abandons the attempt locally and tells the backend to kill the ticket, so a
## code left on screen (or in a screenshot) cannot be approved later.
func cancel() -> void:
	if device_login_id.is_empty() or secret.is_empty():
		_finish_local(STATUS_CANCELLED)
		return

	stop_polling()
	# Fire-and-forget: the user already stopped caring, so a slow or failed
	# revoke must not block the UI. The ticket expires on its own regardless.
	# Kept as a bare statement (not assigned): using a coroutine's value without
	# `await` is a hard parser error in GDScript.
	@warning_ignore("missing_await")
	_api.device_cancel(device_login_id, secret)
	_finish_local(STATUS_CANCELLED)

## Convenience: cancel + start again.
func restart() -> bool:
	cancel()
	return await start()

func seconds_remaining() -> int:
	if expires_at_unix <= 0:
		return 0
	return maxi(0, expires_at_unix - Time.get_unix_time_from_system())

func is_expired() -> bool:
	return expires_at_unix > 0 and seconds_remaining() <= 0

# ---------------------------------------------------------------------------
# Polling
# ---------------------------------------------------------------------------

func _start_polling() -> void:
	# `is_active` was set to true by start(). Do NOT call stop_polling() here: it
	# would clear that flag and `_poll_loop` would exit before its first poll.
	# Each loop awaits its own network call / timer, so requests cannot pile up.
	if not _countdown_running:
		_countdown_running = true
		@warning_ignore("missing_await")
		_tick_countdown()
	if not _poll_loop_running:
		_poll_loop_running = true
		@warning_ignore("missing_await")
		_poll_loop()

func _poll_loop() -> void:
	while is_active:
		await _tree().create_timer(poll_interval_ms / 1000.0).timeout
		if not is_active:
			break
		if Time.get_unix_time_from_system() >= _deadline_unix:
			_fail("device_login_timeout")
			break
		await _poll_once()
	_poll_loop_running = false

func _poll_once() -> void:
	var response := await _api.device_status(device_login_id)
	var code_status := int(response.get("__status", 0))

	if code_status == 404 or code_status == 410:
		# Ticket gone: expired server-side, cancelled, or already redeemed.
		_finish_local(STATUS_EXPIRED)
		return

	if code_status == 0:
		# Transient network trouble: keep trying until the deadline expires.
		# The server is still the one deciding the outcome.
		return

	var reported := str(response.get("status", ""))
	if reported.is_empty():
		return

	if reported == STATUS_APPROVED:
		if status != STATUS_APPROVED:
			status = STATUS_APPROVED
			status_changed.emit(status)
		stop_polling()
		approved.emit()
		return

	if TERMINAL_STATUSES.has(reported):
		_finish_local(reported)
		return

	if reported != status:
		status = reported
		status_changed.emit(status)

func _tick_countdown() -> void:
	# Drives the "Expires in 58 seconds" label without the UI polling itself.
	while is_active:
		progress.emit(seconds_remaining())
		await _tree().create_timer(1.0).timeout
	_countdown_running = false

# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _fail(reason: String) -> void:
	stop_polling()
	status = "error"
	is_active = false
	failed.emit(reason)

func _finish_local(final_status: String) -> void:
	stop_polling()
	is_active = false
	if status != final_status:
		status = final_status
		status_changed.emit(status)
	if final_status == STATUS_CANCELLED:
		cancelled.emit()
	else:
		failed.emit(final_status)

func stop_polling() -> void:
	is_active = false

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree
