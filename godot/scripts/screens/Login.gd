extends Control

## The device-linking screen.
##
## Shows a QR code and the matching short code, then waits while the player
## approves the login on the web. All the actual flow logic lives in
## AuthManager and WONDeviceLogin; this script is presentation plus the two
## things only a human can do: tap a button, or leave.
##
## Security note: the short code is a single-use, short-lived ticket handle, not
## a credential. Approval happens on the web page behind an authenticated Privy
## session, and the player must press the button there, so an observer who
## photographs this screen gains nothing once the code expires.

## Where to go once the player is authenticated. Overridable in the inspector.
@export var next_scene: String = ""

@onready var _qr_code: TextureRect = %QRCode
@onready var _code_label: Label = %CodeLabel
@onready var _expiry_label: Label = %ExpiryLabel
@onready var _status_label: Label = %StatusLabel
@onready var _refresh_button: Button = %RefreshButton
@onready var _cancel_button: Button = %CancelButton

## home.tscn is the existing boot scene: it captures the minimap and then hands
## off to the lobby. Returning there keeps the normal startup path intact.
const SCENE_DEFAULT_GAME := "res://scenes/home.tscn"
const QR_TARGET_PX := 512

## Copy for each failure mode. Keys must stay in sync with
## AuthManager._describe_error.
const ERROR_COPY := {
	"network_error": "Could not reach World of Nads. Check your connection and try again.",
	"rate_limited": "Too many login attempts. Wait a moment and try again.",
	"ticket_expired": "That code expired. Generate a new one to continue.",
	"ticket_not_found": "That code is no longer valid. Generate a new one.",
	"ticket_already_used": "That code was already used. Generate a new one.",
	"ticket_cancelled": "This login was cancelled. Generate a new code to continue.",
	"ticket_not_redeemable": "That code can no longer be used. Generate a new one.",
	"invalid_ticket_secret": "This login could not be verified. Generate a new code.",
	"device_mismatch": "This login was started on a different device. Generate a new code.",
	"forbidden": "Sign-in was rejected. Please try again.",
	"unauthorized": "Sign-in was rejected. Please try again.",
	"identity_error": "We could not verify your account. Please try again.",
	"server_error": "Something went wrong on our side. Please try again.",
	"bad_request": "The login request was rejected. Please try again.",
}

func _ready() -> void:
	_refresh_button.pressed.connect(_on_refresh_pressed)
	_cancel_button.pressed.connect(_on_cancel_pressed)

	AuthManager.login_completed.connect(_on_login_completed)
	AuthManager.login_failed.connect(_on_login_failed)

	# A stored session is still being validated at this point. Wait for it before
	# asking for a QR code, otherwise returning players would see the login
	# screen flash before being bounced into the game.
	if await AuthManager.await_restore():
		_go_to_game()
		return

	_show_idle()
	await _start_login()

func _exit_tree() -> void:
	# Detach from autoload signals so a queued transition cannot fire into a
	# freed scene.
	if AuthManager.login_completed.is_connected(_on_login_completed):
		AuthManager.login_completed.disconnect(_on_login_completed)
	if AuthManager.login_failed.is_connected(_on_login_failed):
		AuthManager.login_failed.disconnect(_on_login_failed)

# ---------------------------------------------------------------------------
# Flow
# ---------------------------------------------------------------------------

func _start_login() -> void:
	_set_status("Requesting a login code…", true)
	_set_buttons_enabled(false)

	var login := await AuthManager.begin_device_login()
	if login == null:
		# AuthManager has already emitted login_failed; the handler renders it.
		return

	_render_code(login)
	_set_buttons_enabled(true)

	login.progress.connect(_on_progress)
	login.status_changed.connect(_on_status_changed)
	login.cancelled.connect(_on_attempt_cancelled)

func _render_code(login: WONDeviceLogin) -> void:
	_code_label.text = login.code

	var texture: ImageTexture = null
	if AuthManager.qr_provider != null and AuthManager.qr_provider.is_available():
		texture = AuthManager.qr_provider.generate(login.auth_url, QR_TARGET_PX)

	if texture != null:
		_qr_code.texture = texture
		_qr_code.visible = true
		_set_status("Scan the code to sign in", true)
	else:
		# No QR renderer available. The short code is still a complete way to
		# sign in, so degrade to typing it rather than dead-ending the player.
		_qr_code.visible = false
		_set_status("Open %s and enter the code above" % _short_origin(login.auth_url), true)

	_expiry_label.text = ""

func _short_origin(url: String) -> String:
	var parsed := url.split("?")[0]
	return parsed.trim_prefix("https://")

func _on_progress(seconds_remaining: int) -> void:
	if seconds_remaining <= 0:
		_expiry_label.text = "Code expired"
		return
	_expiry_label.text = "Expires in %d seconds" % seconds_remaining

func _on_status_changed(status: String) -> void:
	match status:
		WONDeviceLogin.STATUS_PENDING:
			_set_status("Waiting for approval…", true)
		WONDeviceLogin.STATUS_APPROVED:
			# Exchange is about to run; stop the player starting a second attempt.
			_set_status("Approved. Signing in…", true)
			_set_buttons_enabled(false)
			_expiry_label.text = ""

func _on_attempt_cancelled() -> void:
	_show_idle()
	_set_status("Sign-in cancelled.", false)
	# The attempt is over: let the player start a new one rather than leaving
	# them on a screen whose only controls are disabled.
	_set_buttons_enabled(true)

# ---------------------------------------------------------------------------
# AuthManager signals
# ---------------------------------------------------------------------------

func _on_login_completed(_state: WONAuthState) -> void:
	_set_status("Welcome, %s" % AuthManager.get_username(), true)
	_set_buttons_enabled(false)
	_go_to_game()

func _on_login_failed(error: String) -> void:
	_show_idle()
	_set_status(ERROR_COPY.get(error, ERROR_COPY["server_error"]), false)
	# A failure can arrive while the buttons were disabled (mid-start, or after
	# approval during exchange). Re-enable them so the player can retry instead
	# of being stranded.
	_set_buttons_enabled(true)

# ---------------------------------------------------------------------------
# Buttons
# ---------------------------------------------------------------------------

func _on_refresh_pressed() -> void:
	_code_label.text = ""
	_qr_code.texture = null
	_expiry_label.text = ""
	await _start_login()

func _on_cancel_pressed() -> void:
	_set_buttons_enabled(false)
	AuthManager.cancel_device_login()
	_show_idle()
	_set_status("Sign-in cancelled.", false)
	# `cancel_device_login` emits `cancelled` only when there is a live attempt,
	# so re-enable unconditionally rather than relying on that signal.
	_set_buttons_enabled(true)

# ---------------------------------------------------------------------------
# Presentation helpers
# ---------------------------------------------------------------------------

func _show_idle() -> void:
	_code_label.text = ""
	_qr_code.texture = null
	_qr_code.visible = false
	_expiry_label.text = ""

func _set_status(text: String, in_progress: bool) -> void:
	_status_label.text = text
	# Amber while waiting, red once it has failed, so the state is readable at a
	# glance without reading the text.
	_status_label.modulate = (
		Color(1.0, 0.84, 0.0, 1.0) if in_progress else Color(1.0, 0.35, 0.35, 1.0)
	)

func _set_buttons_enabled(enabled: bool) -> void:
	_refresh_button.disabled = not enabled
	_cancel_button.disabled = not enabled

func _go_to_game() -> void:
	var target := next_scene if not next_scene.is_empty() else SCENE_DEFAULT_GAME
	# Transition so the game does not pop in over the QR code.
	if Game.transition_layer != null:
		Game.transition_layer.change_scene(target)
	else:
		get_tree().change_scene_to_file(target)
