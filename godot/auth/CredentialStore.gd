extends RefCounted
class_name WONCredentialStore

## Persistent storage for the session tokens.
##
## On mobile the tokens go through the platform keystore (Android Keystore via
## the exported plugin, iOS Keychain) because a refresh token is a long-lived
## bearer credential: anyone who copies it can mint sessions. On desktop there
## is no equivalent keystore, so the file lands under `user://`, which is a
## per-user, per-application directory rather than shared storage.
##
## This is an abstraction rather than a direct keystore call so that:
##   - the auth flow has no hard dependency on a mobile export plugin, so the
##     project still runs in the editor and on desktop;
##   - a platform-specific implementation can be dropped in without touching
##     AuthManager;
##   - tests can inject an in-memory store.

## Injectable backends: a callable taking (key: String, value: String) and one
## taking (key: String) and returning a String. Set both to use an external store.
var _setter: Callable = Callable()
var _getter: Callable = Callable()

const SESSION_KEY := "won_session_v1"
const DEVICE_ID_KEY := "won_device_id"

var _memory: Dictionary = {}

func _init() -> void:
	# Desktop fallback via ProjectSettings file storage.
	if not _setter.is_valid() or not _getter.is_valid():
		var cfg := ConfigFile.new()
		var path := _store_path()
		if cfg.load(path) == OK:
			for key in cfg.get_section_keys(""):
				_memory[key] = cfg.get_value("", key, "")

## Wires a platform keystore (or a test double) in place of the file store.
func configure(p_setter: Callable, p_getter: Callable) -> void:
	_setter = p_setter
	_getter = p_getter

func _store_path() -> String:
	# user:// is scoped to the app and the signed-in OS user.
	return "user://won_auth.cfg"

# ---------------------------------------------------------------------------
# Session
# ---------------------------------------------------------------------------

## Persists the session as JSON. Only the fields in
## WONAuthState.to_persisted_dict() are written.
func save_session(state: WONAuthState) -> void:
	var payload := JSON.stringify(state.to_persisted_dict())
	if _setter.is_valid():
		_setter.call(SESSION_KEY, payload)
		return
	_memory[SESSION_KEY] = payload
	_flush()

## Returns the stored session, or null when there is none or it is unreadable.
func load_session() -> WONAuthState:
	var raw := _read(SESSION_KEY)
	if raw.is_empty():
		return null
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		# Corrupt payload: treat as signed out rather than crashing at boot.
		return null
	var state := WONAuthState.from_persisted_dict(parsed)
	if state.refresh_token.is_empty() and state.access_token.is_empty():
		return null
	return state

func clear_session() -> void:
	if _setter.is_valid():
		_setter.call(SESSION_KEY, "")
	else:
		_memory.erase(SESSION_KEY)
		_flush()

# ---------------------------------------------------------------------------
# Device identity
# ---------------------------------------------------------------------------

## Stable per-install identifier. Generated once, then reused, so that the
## backend can tell a refresh from a stolen-token replay on a different device.
##
## This is an installation identifier, not a hardware serial and not a user
## identity. It is random on purpose: a machine-derived id would leak hardware
## details to the backend for no benefit here.
func get_or_create_device_id() -> String:
	var existing := _read(DEVICE_ID_KEY)
	if not existing.is_empty():
		return existing

	var generated := _random_hex(32)
	if _setter.is_valid():
		_setter.call(DEVICE_ID_KEY, generated)
	else:
		_memory[DEVICE_ID_KEY] = generated
		_flush()
	return generated

func _read(key: String) -> String:
	if _getter.is_valid():
		# Keystore plugins often return null for a missing key. Without this
		# guard, `str(null)` ("<null>") would look like a real stored value.
		var value: Variant = _getter.call(key)
		return "" if value == null else str(value)
	return str(_memory.get(key, ""))

func _flush() -> void:
	var cfg := ConfigFile.new()
	for key in _memory:
		cfg.set_value("", key, _memory[key])
	# ConfigFile writes atomically via a temp file, so a crash mid-write cannot
	# leave a half-written session behind.
	cfg.save(_store_path())

## 256 bits of randomness from the engine CSPRNG.
func _random_hex(byte_count: int) -> String:
	# `generate_random_bytes` is an instance method, not a static one.
	var crypto := Crypto.new()
	var bytes := crypto.generate_random_bytes(byte_count)
	return bytes.hex_encode()
