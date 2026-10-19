extends Node

## Autoload. Single owner of the World of Nads session.
##
## Everything that needs to know who the player is asks this node; nothing else
## reads tokens or talks to the auth endpoints directly. Gameplay code calls
## `AuthManager.api` for authenticated requests and never assembles an
## `Authorization` header by hand.
##
## The backend is the authority. This class never decides who the player is: it
## holds whatever `/auth/me` and `/auth/device/exchange` returned and refreshes
## it. Nothing reported by the game client (wallet address, score, rewards) is
## trusted anywhere in this subsystem.
##
## Persistent login: on boot `restore_session()` is called once. A stored
## session is validated against `/auth/me`, refreshed if the access token has
## expired, and accepted only if the backend still recognises it. Otherwise the
## session is dropped and `login_required` fires so the caller can show
## Login.tscn. First launch therefore always lands on the QR screen.

## Emitted at the very start of any login attempt.
signal login_started()
## Emitted once a session is established or successfully restored.
signal login_completed(state: WONAuthState)
## Emitted when a login attempt fails. `error` is a stable machine-readable
## code (see `_describe_error`), never a raw server string.
signal login_failed(error: String)
## Emitted after a successful token rotation.
signal session_refreshed(state: WONAuthState)
## Emitted when the session ends, either by `logout()` or because the backend
## rejected it. Carries the reason so the UI can explain itself.
signal logged_out(reason: String)
## Emitted when there is no usable session and the login screen is required.
signal login_required(reason: String)
## Emitted once, when the boot-time session restore has finished either way.
## `authenticated` reports whether a usable session survived.
signal restore_finished(authenticated: bool)
## Coarse state changes, for UI that wants to follow the flow without
## interpreting individual signals.
signal state_changed(state: String)

const STATE_IDLE := "idle"
const STATE_RESTORING := "restoring"
const STATE_WAITING_FOR_APPROVAL := "waiting_for_approval"
const STATE_AUTHENTICATED := "authenticated"
const STATE_SIGNED_OUT := "signed_out"

const LOGIN_SCENE := "res://scenes/login.tscn"

## HTTP layer. Exposed so gameplay scripts can make authenticated calls without
## duplicating token handling.
var api: WONAuthAPI = null
## Persistent token storage. Swappable for tests.
var store: WONCredentialStore = null
## QR rendering, behind an interface so an addon can replace the built-in one.
var qr_provider: WONQRProvider = null

var _session: WONAuthState = null
var _device_login: WONDeviceLogin = null
var _state: String = STATE_IDLE
var _restoring: bool = false
## Guards against two concurrent refreshes racing on the same token.
var _refresh_in_flight: bool = false

func _ready() -> void:
	# Boot order matters: AuthManager must exist before the first scene's _ready
	# runs, because scenes read is_authenticated during their own setup.
	process_mode = Node.PROCESS_MODE_ALWAYS

	store = WONCredentialStore.new()
	api = WONAuthAPI.new(self)
	# Method references rather than lambdas: the refresh handler is a coroutine,
	# and `await` inside a lambda is not reliably supported across Godot builds.
	api.configure(
		Callable(self, "_provide_access_token"),
		Callable(self, "_refresh_session")
	)
	qr_provider = WONQRGenerator.new()

	api.session_expired.connect(_on_api_session_expired)

	# Mark restoring here, in _ready, not inside the deferred call: autoload
	# _ready runs before the main scene's _ready, so a gate in the main scene
	# must already see the restore as in flight. call_deferred would otherwise
	# start it after that scene had already given up waiting.
	_restoring = true
	_set_state(STATE_RESTORING)
	call_deferred("_run_boot_restore")

# ---------------------------------------------------------------------------
# Public interface
# ---------------------------------------------------------------------------

func is_authenticated() -> bool:
	return _session != null and _session.is_authenticated()

## Stable, immutable WON account id. Empty when signed out.
func get_user_id() -> String:
	return _session.user_id if _session != null else ""

## Display name derived by the backend. Not an identity.
func get_username() -> String:
	return _session.username if _session != null else ""

## Blockchain address associated with the Privy account. Informational only:
## the backend does not key anything on it, so it must never be used as an id.
func get_wallet_address() -> String:
	return _session.wallet_address if _session != null else ""

## Privy DID. Kept separate from the WON user id on purpose.
func get_privy_user_id() -> String:
	return _session.privy_user_id if _session != null else ""

## Avatar URL from the linked Privy account. Display only; may be empty.
func get_profile_picture_url() -> String:
	return _session.profile_picture_url if _session != null else ""

## `0x1234…abcd` form for compact UI. Empty when there is no wallet.
func get_short_wallet_address() -> String:
	var address := get_wallet_address()
	if address.length() <= 12:
		return address
	return "%s...%s" % [address.substr(0, 6), address.substr(address.length() - 4, 4)]

## Backend-verified profile for the current session.
func get_profile() -> Dictionary:
	return _session.profile.duplicate(true) if _session != null else {}

## Raw bearer token for the WON backend. Never a Privy token.
func get_access_token() -> String:
	return _session.access_token if _session != null else ""

## Passed to AuthAPI as the bearer token source.
func _provide_access_token() -> String:
	return get_access_token()

func get_session() -> WONAuthState:
	return _session

func get_state() -> String:
	return _state

## Stable per-install id, sent with every login and refresh.
func get_device_id() -> String:
	return store.get_or_create_device_id()

## Convenience wrapper for making an authenticated call.
func request(method: int, path: String, body: Variant = null) -> Dictionary:
	if not is_authenticated():
		return {"ok": false, "error": "not_authenticated", "__status": 0}
	return await api.request(method, path, body, true)

# ---------------------------------------------------------------------------
# Device login
# ---------------------------------------------------------------------------

## Starts a QR + short-code login attempt.
##
## Returns the WONDeviceLogin driving it so a UI can render the code and
## countdown, or null when the request could not be started. Listen for
## `login_completed` / `login_failed` rather than awaiting this.
func begin_device_login() -> WONDeviceLogin:
	# Abandon any previous attempt first. Without this a Refresh tap would leave
	# the old poll loop running against a ticket nobody is looking at.
	if _device_login != null:
		_device_login.cancel()
		_device_login = null

	login_started.emit()
	_set_state(STATE_WAITING_FOR_APPROVAL)

	_device_login = WONDeviceLogin.new(api, _platform_name(), get_device_id(), _device_label())
	_device_login.approved.connect(_on_device_login_approved)
	_device_login.failed.connect(_on_device_login_failed)
	_device_login.cancelled.connect(_on_device_login_cancelled)

	if not await _device_login.start():
		# `failed` has already been emitted by DeviceLogin; the caller reacts to
		# the signal, so no second emit here.
		_device_login = null
		return null
	return _device_login

## Abandons an in-flight login attempt and invalidates the code on the server.
func cancel_device_login() -> void:
	if _device_login != null:
		_device_login.cancel()

## Regenerates the code, e.g. when the player asks for a fresh one.
func restart_device_login() -> WONDeviceLogin:
	return await begin_device_login()

# ---------------------------------------------------------------------------
# Session lifecycle
# ---------------------------------------------------------------------------

## Rotates the token pair. Returns true when a fresh access token is in place.
##
## Safe to call from gameplay code: AuthAPI calls it on a 401, and concurrent
## callers share one in-flight refresh rather than stampeding the endpoint.
func refresh_session() -> bool:
	var ok := await _refresh_session()
	if not ok:
		# A refresh that fails outside the AuthAPI 401 path still has to end the
		# session, otherwise a dead token lingers and every later call repeats
		# the failure.
		_drop_session("refresh_failed")
	return ok

## Ends the session locally and tells the backend to revoke it.
##
## `reason` is for the `logged_out` signal only. A failed revoke is not fatal:
## the local tokens are cleared either way, and the server expires the session
## on its own schedule regardless.
func logout(reason: String = "user_requested") -> void:
	var refresh_token := _session.refresh_token if _session != null else ""

	_session = null
	_device_login = null
	store.clear_session()
	_set_state(STATE_SIGNED_OUT)

	# Revoke server-side best-effort. Deliberately not awaited so the UI can
	# move on immediately; the tokens are already gone locally. The call must
	# stay a bare statement (not assigned), because using a coroutine's value
	# without `await` is a hard parser error in GDScript.
	if not refresh_token.is_empty():
		@warning_ignore("missing_await")
		api.logout(refresh_token)

	logged_out.emit(reason)

# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## Resolves once the boot-time restore has finished, reporting whether a usable
## session survived. Safe to call at any time: returns immediately when the
## restore is already done rather than waiting for a signal that has passed.
func await_restore() -> bool:
	if not _restoring:
		return is_authenticated()
	await restore_finished
	return is_authenticated()

func is_restoring() -> bool:
	return _restoring

## Every path through the boot restore ends here, so `_restoring` cannot be left
## set on an early return (which would deadlock anything awaiting restore).
func _run_boot_restore() -> void:
	var reason := await _perform_boot_restore()
	_restoring = false

	if is_authenticated():
		restore_finished.emit(true)
		return

	login_required.emit(reason)
	restore_finished.emit(false)

func _perform_boot_restore() -> String:
	var stored := store.load_session()
	if stored == null:
		_set_state(STATE_SIGNED_OUT)
		return "no_stored_session"

	_session = stored
	# The access token may already be dead while the refresh token is still good,
	# which is the common case after the app has been closed for a while.
	if _session.is_expired():
		if not await _refresh_session():
			# Clear quietly: `_refresh_session` no longer drops the session, and
			# emitting logged_out/login_required during boot would duplicate the
			# signals `_run_boot_restore` is about to send.
			_session = null
			store.clear_session()
			return "refresh_failed"

	# Ask the backend whether this session is still valid. Trusting the stored
	# token alone would let a revoked session look authenticated until the first
	# real request failed.
	var response := await api.me()
	var status := int(response.get("__status", 0))
	if status != 200:
		# 401 means the session is genuinely gone. Anything else (network,
		# server error) leaves the token alone: the player is probably offline
		# and should not be forced to re-scan a QR code because of a blip.
		if status == 401 or status == 403:
			_session = null
			store.clear_session()
			return "session_revoked"
		_set_state(STATE_SIGNED_OUT)
		return "backend_unreachable"

	_adopt_me_payload(response)
	store.save_session(_session)
	_set_state(STATE_AUTHENTICATED)
	login_completed.emit(_session)
	return ""

## `/auth/me` is authoritative for identity, so its response overwrites whatever
## was cached locally. This is what stops a tampered local file from changing
## the player id.
func _adopt_me_payload(response: Dictionary) -> void:
	var user: Dictionary = response.get("user", {}) if response.get("user") is Dictionary else {}
	if not user.is_empty():
		_session.user_id = str(user.get("id", _session.user_id))
		_session.username = str(user.get("username", _session.username))
		_session.privy_user_id = str(user.get("privy_user_id", _session.privy_user_id))
		_session.wallet_address = str(user.get("wallet_address", _session.wallet_address))
		_session.profile_picture_url = str(user.get("profile_picture_url", _session.profile_picture_url))
		_session.profile = user.duplicate(true)

	var expires_in := int(response.get("expires_in", 0))
	if expires_in > 0:
		_session.access_token_expires_at = Time.get_unix_time_from_system() + expires_in

## One refresh at a time; extra callers await the same result.
func _refresh_session() -> bool:
	if _refresh_in_flight:
		# Wait for the in-flight rotation instead of starting a second one with a
		# token that is about to be invalidated by the first.
		while _refresh_in_flight:
			await get_tree().process_frame
		return is_authenticated()

	if _session == null or _session.refresh_token.is_empty():
		return false

	_refresh_in_flight = true
	# Snapshot before the request: a rotation invalidates the old pair.
	var refresh_token := _session.refresh_token
	var device_id := _session.device_id if not _session.device_id.is_empty() else get_device_id()

	var response := await api.refresh(refresh_token, device_id)
	var status := int(response.get("__status", 0))

	var ok := false
	if status == 200:
		var access_token := str(response.get("access_token", ""))
		if not access_token.is_empty():
			_session.access_token = access_token
			_session.refresh_token = str(response.get("refresh_token", refresh_token))
			var expires_in := int(response.get("expires_in", 3600))
			_session.access_token_expires_at = Time.get_unix_time_from_system() + expires_in
			_session.device_id = device_id
			_session.state = WONAuthState.STATE_AUTHENTICATED
			store.save_session(_session)
			ok = true

	_refresh_in_flight = false

	if ok:
		session_refreshed.emit(_session)
	# On failure the caller decides what the session becomes: the AuthAPI 401
	# path drops it via `session_expired`, boot restore clears it quietly, and
	# `refresh_session()` drops it explicitly. Dropping here too would emit
	# duplicate logged_out/login_required signals during boot.
	return ok

func _on_device_login_approved() -> void:
	var login := _device_login
	if login == null:
		return

	var response := await api.device_exchange(login.device_login_id, login.secret, _platform_name(), get_device_id())
	var status := int(response.get("__status", 0))

	if status != 200:
		_device_login = null
		_set_state(STATE_SIGNED_OUT)
		login_failed.emit(_describe_error(status, response))
		return

	var state := WONAuthState.from_exchange_payload(response)
	state.platform = _platform_name()
	state.device_id = get_device_id()

	_session = state
	store.save_session(_session)
	_device_login = null
	_set_state(STATE_AUTHENTICATED)
	login_completed.emit(_session)

func _on_device_login_failed(reason: String) -> void:
	_device_login = null
	if is_authenticated():
		return
	_set_state(STATE_SIGNED_OUT)
	login_failed.emit(_local_failure_code(reason))

## DeviceLogin reports both raw server error tokens and its own local reasons
## (a ticket that expired while polling, a timeout). Normalise both to the same
## stable codes `_describe_error` produces, so the UI has one vocabulary.
func _local_failure_code(reason: String) -> String:
	match reason:
		"expired", "device_login_timeout":
			return "ticket_expired"
		"used":
			return "ticket_already_used"
		"cancelled":
			return "ticket_cancelled"
		"start_failed", "malformed_start_response":
			return "network_error"
		_:
			return _describe_error(0, {"error": reason})

func _on_device_login_cancelled() -> void:
	_device_login = null
	if is_authenticated():
		return
	_set_state(STATE_SIGNED_OUT)

## AuthAPI could not recover from a 401. The session is finished.
func _on_api_session_expired(reason: String) -> void:
	if _session == null:
		return
	_drop_session(reason)

func _drop_session(reason: String) -> void:
	_session = null
	store.clear_session()
	_set_state(STATE_SIGNED_OUT)
	logged_out.emit(reason)
	login_required.emit(reason)

func _set_state(next: String) -> void:
	if _state == next:
		return
	_state = next
	state_changed.emit(_state)

## Maps transport/HTTP detail onto stable codes the UI can switch on.
##
## The server's stable error token is checked first: it is more precise than the
## status code (a `409` alone cannot say whether a ticket expired, was used, or
## was cancelled). Status is the fallback for transport-level failures.
func _describe_error(status: int, response: Dictionary) -> String:
	var server_error := str(response.get("error", ""))

	match server_error:
		"too_many_requests":
			return "rate_limited"
		"device_login_not_found", "invalid_code":
			return "ticket_not_found"
		"invalid_device_secret":
			return "invalid_ticket_secret"
		"device_login_already_used", "device_login_used":
			return "ticket_already_used"
		"device_login_expired":
			return "ticket_expired"
		"device_login_cancelled":
			return "ticket_cancelled"
		"device_mismatch":
			return "device_mismatch"
		"privy_not_configured", "invalid_privy_access_token", "verification_failed", "privy_user_lookup_failed":
			return "identity_error"

	match status:
		0:
			# No HTTP response at all: the request never completed.
			return "network_error"
		400:
			return "bad_request"
		401:
			return "unauthorized"
		403:
			return "forbidden"
		404:
			return "ticket_not_found"
		409:
			return "ticket_not_redeemable"
		429:
			return "rate_limited"
		502:
			return "identity_error"
		_:
			return "server_error"

func _platform_name() -> String:
	if OS.get_name() == "Android":
		return "android"
	if OS.get_name() == "iOS":
		return "ios"
	return "desktop"

## Short, non-identifying description for the HUD and logs.
func _device_label() -> String:
	return "%s %s" % [OS.get_name(), Engine.get_version_info().get("string", "?")]
