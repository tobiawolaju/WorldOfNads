extends RefCounted
class_name WONAuthAPI

## Centralized HTTP client for the WON backend.
##
## Every authenticated game request goes through here so that token handling,
## the 401 -> refresh -> retry-once policy, and JSON parsing live in exactly one
## place. Gameplay scripts call `WONAuthAPI.request(...)` and never touch an
## `Authorization` header themselves.
##
## Refresh/retry rules:
##   - On 401 the session is refreshed at most once per call, then the request is
##     replayed exactly once.
##   - A second 401, or a failed refresh, clears the session and raises
##     `session_expired` so AuthManager can show the login screen.
##   - There is no unbounded retry loop: the retry budget is per-call and reset.

const DEFAULT_BASE_URL := "https://worldofnads.onrender.com"
const REQUEST_TIMEOUT_SECONDS := 20.0
const MAX_REFRESH_ATTEMPTS := 1

## Emitted for any completed call. `response_code` 0 means transport failure.
signal request_completed(method: int, path: String, response_code: int, body: Dictionary)
## Emitted when a 401 could not be recovered by refreshing.
signal session_expired(reason: String)

var base_url: String = DEFAULT_BASE_URL
## Injected so tests (and the editor) can run without a live backend.
var _token_provider: Callable = Callable()
var _refresh_handler: Callable = Callable()
var _node: Node = null

## In-flight request bookkeeping: path -> HTTPRequest node.
var _active: Dictionary = {}
var _next_id: int = 0

func _init(node: Node = null) -> void:
	_node = node
	if node != null and node.is_inside_tree():
		base_url = _read_base_url_from_settings()

func configure(p_token_provider: Callable, p_refresh_handler: Callable) -> void:
	_token_provider = p_token_provider
	_refresh_handler = p_refresh_handler

func _read_base_url_from_settings() -> String:
	# Allows a local backend without rebuilding the export.
	if OS.has_feature("editor") and ProjectSettings.has_setting("won/backend/base_url"):
		var configured := str(ProjectSettings.get_setting("won/backend/base_url", ""))
		if not configured.is_empty():
			return configured.rstrip("/")
	return base_url.rstrip("/")

# ---------------------------------------------------------------------------
# Public request helpers
# ---------------------------------------------------------------------------

## Authenticated request. Attaches the current WON session token.
##
## `body` is optional; pass a Dictionary for JSON or a PackedByteArray to send
## bytes verbatim. Returns the parsed response, or an empty Dictionary on
## failure (check `last_error_code` / the `request_failed` signal).
func request(
	method: int,
	path: String,
	body: Variant = null,
	authenticated: bool = true,
	extra_headers: PackedStringArray = PackedStringArray()
) -> Dictionary:
	var payload := await _perform(method, path, body, authenticated, extra_headers, 0)
	return payload

## Fire-and-report variant for endpoints whose response body the caller ignores.
func request_no_response(method: int, path: String, body: Variant = null, authenticated: bool = true) -> bool:
	var response := await request(method, path, body, authenticated)
	return int(response.get("__status", 0)) >= 200 and int(response.get("__status", 0)) < 300

# ---------------------------------------------------------------------------
# Device login endpoints
# ---------------------------------------------------------------------------

## POST /auth/device/start -> creates the pending login ticket.
func device_start(platform: String, device_id: String, device_label: String) -> Dictionary:
	return await request(
		HTTPClient.METHOD_POST,
		"/auth/device/start",
		{"platform": platform, "device_id": device_id, "device_label": device_label},
		false
	)

## GET /auth/device/status -> one poll of the ticket state.
func device_status(device_login_id: String) -> Dictionary:
	return await request(
		HTTPClient.METHOD_GET,
		"/auth/device/status?device_login_id=%s" % device_login_id.uri_encode(),
		null,
		false
	)

## POST /auth/device/cancel -> invalidates an abandoned ticket.
func device_cancel(device_login_id: String, secret: String) -> Dictionary:
	return await request(
		HTTPClient.METHOD_POST,
		"/auth/device/cancel",
		{"device_login_id": device_login_id, "secret": secret},
		false
	)

## POST /auth/device/exchange -> trades the approved ticket for a WON session.
func device_exchange(device_login_id: String, secret: String, platform: String, device_id: String) -> Dictionary:
	return await request(
		HTTPClient.METHOD_POST,
		"/auth/device/exchange",
		{
			"device_login_id": device_login_id,
			"secret": secret,
			"platform": platform,
			"device_id": device_id
		},
		false
	)

# ---------------------------------------------------------------------------
# Session endpoints
# ---------------------------------------------------------------------------

## POST /auth/refresh -> rotates the token pair.
func refresh(refresh_token: String, device_id: String) -> Dictionary:
	return await request(
		HTTPClient.METHOD_POST,
		"/auth/refresh",
		{"refresh_token": refresh_token, "device_id": device_id},
		false
	)

## POST /auth/logout -> best-effort server-side revoke.
func logout(refresh_token: String) -> Dictionary:
	return await request(
		HTTPClient.METHOD_POST,
		"/auth/logout",
		{"refresh_token": refresh_token},
		false
	)

## GET /auth/me -> validates the current session on cold start.
func me() -> Dictionary:
	return await request(HTTPClient.METHOD_GET, "/auth/me")

# ---------------------------------------------------------------------------
# Transport
# ---------------------------------------------------------------------------

func _perform(
	method: int,
	path: String,
	body: Variant,
	authenticated: bool,
	extra_headers: PackedStringArray,
	refresh_attempts: int
) -> Dictionary:
	var headers := PackedStringArray(extra_headers)
	headers.append("Accept: application/json")

	var has_payload := body != null
	if has_payload and body is Dictionary:
		headers.append("Content-Type: application/json")

	if authenticated:
		var token := _current_access_token()
		if token.is_empty():
			# No session at all: fail fast rather than sending an anonymous
			# request that the backend would answer with 401 anyway.
			return _fail(0, "no_session")
		headers.append("Authorization: Bearer %s" % token)

	var response := await _send(method, path, body, headers)

	# A 401 on an authenticated call gets exactly one refresh + replay.
	if response.get("__status", 0) == 401 and authenticated and refresh_attempts < MAX_REFRESH_ATTEMPTS:
		if await _refresh_session():
			return await _perform(method, path, body, authenticated, extra_headers, refresh_attempts + 1)
		session_expired.emit("refresh_failed")
		return response

	if response.get("__status", 0) == 401 and authenticated and refresh_attempts >= MAX_REFRESH_ATTEMPTS:
		# Refreshed, replayed, still 401: the session is not coming back.
		session_expired.emit("unauthorized")

	request_completed.emit(method, path, int(response.get("__status", 0)), response)
	return response

func _send(method: int, path: String, body: Variant, headers: PackedStringArray) -> Dictionary:
	var http := _make_http_node()
	var url := base_url + path

	# `HTTPRequest.request()` only takes a String body, so a caller that really
	# wants to send raw bytes has to go through `request_raw()` instead.
	var err := OK
	if body is PackedByteArray:
		var raw: PackedByteArray = body
		err = http.request_raw(url, headers, method, raw)
	else:
		var payload := ""
		if body is Dictionary:
			payload = JSON.stringify(body)
		elif body is String:
			payload = body
		err = http.request(url, headers, method, payload)

	if err != OK:
		http.queue_free()
		return _fail(0, "request_setup_failed_%d" % err)

	var result: Array = await http.request_completed
	http.queue_free()

	var response_code := int(result[1])
	var response_headers: PackedStringArray = result[2]
	var response_body: PackedByteArray = result[3]

	var parsed := _parse_body(response_body)
	parsed["__status"] = response_code
	parsed["__headers"] = response_headers

	if response_code == 0:
		return _fail(0, "transport_error")
	return parsed

func _parse_body(body: PackedByteArray) -> Dictionary:
	if body.is_empty():
		return {}
	var text := body.get_string_from_utf8()
	if text.strip_edges().is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	# Some endpoints answer with a bare array; wrap it so callers get a
	# consistent Dictionary back.
	return {"data": parsed}

func _fail(status: int, error: String) -> Dictionary:
	return {"ok": false, "error": error, "__status": status}

func _current_access_token() -> String:
	if _token_provider.is_valid():
		return str(_token_provider.call())
	return ""

## Asks AuthManager to refresh. Returns true when a new token is available.
##
## The handler is usually a coroutine, so the result has to be awaited. Awaiting
## a plain (non-coroutine) callable returns its value immediately, which keeps
## a synchronous test double working.
func _refresh_session() -> bool:
	if not _refresh_handler.is_valid():
		return false
	var result: Variant = await _refresh_handler.call()
	if result is bool:
		return result
	return false

func _make_http_node() -> HTTPRequest:
	var http := HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT_SECONDS
	http.accept_gzip = true
	# Added immediately rather than deferred: HTTPRequest.request() requires the
	# node to already be inside the tree.
	var parent: Node = _node if (_node != null and is_instance_valid(_node)) else null
	if parent == null:
		parent = Engine.get_main_loop().root
	parent.add_child(http)
	return http
