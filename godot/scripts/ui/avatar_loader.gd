extends Node
class_name AvatarLoader

## Resolves a display name to an avatar picture, for the in-game event feed.
##
## The events socket only carries a username (the room server mints its own
## random player ids, so there is nothing to join against the auth store). This
## node asks the backend's public directory — `GET /api/profile/picture` — for
## that name's picture and hands back a texture.
##
## Design constraints, in order of importance:
##
##   1. Never block or stutter the feed. `get_avatar()` returns immediately with
##      either a cached texture or `null`; a miss queues a background fetch and
##      the caller falls back to a badge until `avatar_ready` fires.
##   2. Never fetch per frame. The queue is drained one request at a time up to
##      `MAX_CONCURRENT`, and a name is only ever requested once — including
##      names the backend says have no picture.
##   3. Never trust what comes back. The body is sniffed for PNG/JPEG/WebP and
##      anything else is treated as "no picture".
##
## This is display data only. Nothing here is used to decide who a player is.

## Emitted when a name's picture has been resolved into a texture.
## `texture` is never null: an unresolvable name simply never emits.
signal avatar_ready(username: String, texture: Texture2D)
## Emitted once per name when the backend says there is no picture for it, so
## the caller can settle on the badge and stop waiting.
signal avatar_missing(username: String)

## Stop asking the backend after this many distinct names in one session. A
## lobby can churn through a lot of visitors, and each one costs an HTTP request
## and a texture.
const MAX_NAMES := 96
const MAX_CONCURRENT := 3
const REQUEST_TIMEOUT_SEC := 8.0
const MIN_AVATAR_PIXELS := 8

## Palette for generated badges and for colouring names. Sixteen hues, ordered
## around the wheel so that a run of neighbouring slots never reads as the same
## colour, and kept light enough to survive a 12px font over bright sand thanks
## to the black shadow outline every row carries.
const NAME_COLORS: Array[Color] = [
	Color(1.00, 0.42, 0.42),  # red
	Color(0.45, 0.80, 1.00),  # sky
	Color(0.55, 0.92, 0.45),  # lime
	Color(0.95, 0.52, 0.95),  # magenta
	Color(1.00, 0.80, 0.35),  # amber
	Color(0.38, 0.92, 0.92),  # aqua
	Color(0.78, 0.58, 1.00),  # violet
	Color(0.36, 0.90, 0.66),  # mint
	Color(1.00, 0.58, 0.32),  # orange
	Color(0.40, 0.60, 1.00),  # blue
	Color(1.00, 0.55, 0.75),  # pink
	Color(0.82, 0.93, 0.42),  # yellow-green
	Color(0.62, 0.60, 1.00),  # indigo
	Color(0.45, 0.86, 0.72),  # teal
	Color(1.00, 0.68, 0.68),  # rose
	Color(0.92, 0.86, 0.62),  # sand
]

## `https://host/api/profile/picture?username=...`
var _endpoint := ""

## name(lower) -> Texture2D. Only successful decodes live here.
var _textures: Dictionary = {}
## name(lower) -> true once the backend answered (picture or no picture).
## Prevents re-asking for a name that will never resolve.
var _resolved: Dictionary = {}
## Names waiting for a request slot, in arrival order.
var _queue: Array[String] = []
## Display spelling, so the emitted signal matches what the caller asked for.
var _display_names: Dictionary = {}
var _in_flight := 0
var _stopped := false

## name(lower) -> Color. Sticky for the session so a player does not change
## colour when their row scrolls out of the feed and back in later.
var _name_colors: Dictionary = {}
## colour hex -> name(lower). A second player whose hash lands on a taken colour
## is pushed to the next free one, which is what keeps a busy feed readable.
var _color_owners: Dictionary = {}

## Set by the owner. Kept as a setter so the loader can be reused if the client
## switches between the live backend and localhost (the events bridge does).
func configure(base_url: String) -> void:
	var trimmed := base_url.strip_edges().trim_suffix("/")
	if trimmed.is_empty():
		_endpoint = ""
		return
	_endpoint = "%s/api/profile/picture" % trimmed


func _exit_tree() -> void:
	# Pending HTTPRequest children are freed with this node; just make sure a
	# callback that fires during teardown does not touch freed state.
	_stopped = true
	_queue.clear()


## Cached texture for `username`, or null when it is not known yet. A miss
## schedules a fetch and is safe to call on every render pass.
func get_avatar(username: String) -> Texture2D:
	var key := _cache_key(username)
	if key.is_empty():
		return null
	var cached = _textures.get(key)
	if cached is Texture2D:
		return cached
	_request(key, username.strip_edges())
	return null


## True once `username` can no longer produce a picture (answered, or the
## budget is spent). The caller can stop showing a "loading" state.
func is_settled(username: String) -> bool:
	var key := _cache_key(username)
	return key.is_empty() or _resolved.has(key)


## Colour for a name, Twitch-style: the name's hash picks a preferred slot, but
## a slot already worn by someone else in this session is skipped, so no two
## players in view ever share a colour.
##
## The probe is deterministic given the order names first appeared, which is the
## same order on every client watching the same room — so a player looks the same
## to everyone without any coordination, and stays that colour for the session.
func name_color(username: String) -> Color:
	var key := _cache_key(username)
	if key.is_empty():
		return Color(0.82, 0.82, 0.82)

	var cached = _name_colors.get(key)
	if cached is Color:
		return cached

	var palette_size := NAME_COLORS.size()
	var start := _hash_key(key) % palette_size

	for offset in palette_size:
		var candidate: Color = NAME_COLORS[(start + offset) % palette_size]
		var owner := str(_color_owners.get(candidate.to_html(true), ""))
		if owner.is_empty():
			_name_colors[key] = candidate
			_color_owners[candidate.to_html(true)] = key
			return candidate

	# All sixteen are spoken for: 16+ distinct players in one session. Repeating
	# a colour beats refusing to name someone.
	var overflow: Color = NAME_COLORS[start]
	_name_colors[key] = overflow
	return overflow


func _hash_key(key: String) -> int:
	var hash_value := 0
	for index in key.length():
		hash_value = (hash_value * 31 + key.unicode_at(index)) & 0x7FFFFFFF
	return hash_value


## One or two characters for the badge. Handles the `player-1a2b3c4d` shape the
## room server mints for an empty name, which would otherwise badge as a lone
## "P".
func initial(username: String) -> String:
	var name := username.strip_edges()
	if name.is_empty():
		return "?"
	if name.begins_with("player-"):
		var suffix := name.substr(7, 2)
		return suffix.to_upper() if suffix else "P"
	return name.substr(0, 1).to_upper()


# ---------------------------------------------------------------------------
# Fetch queue
# ---------------------------------------------------------------------------

func _request(key: String, display: String) -> void:
	if _stopped or _endpoint.is_empty():
		return
	if _resolved.has(key) or _queue.has(key):
		return
	if _resolved.size() + _queue.size() >= MAX_NAMES:
		# Out of budget: settle on the badge rather than growing without bound.
		_resolved[key] = true
		avatar_missing.emit(display)
		return
	_display_names[key] = display
	_queue.append(key)
	_pump()


func _pump() -> void:
	while _in_flight < MAX_CONCURRENT and not _queue.is_empty() and not _stopped:
		var key: String = _queue.pop_front()
		_fetch(key)


func _fetch(key: String) -> void:
	var display := str(_display_names.get(key, key))
	var url := "%s?username=%s" % [_endpoint, key.uri_encode()]

	var http := HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT_SEC
	# `use_threads` keeps the TLS handshake off the main thread on web/native.
	http.use_threads = true
	add_child(http)

	_in_flight += 1
	if http.request(url) != OK:
		_finish_request(http, key, display, false, PackedByteArray())
		return

	var result: Array = await http.request_completed
	var code := int(result[1])
	var body: PackedByteArray = result[3]
	_finish_request(http, key, display, code == 200, body)


func _finish_request(
	http: HTTPRequest,
	key: String,
	display: String,
	ok: bool,
	body: PackedByteArray
) -> void:
	_in_flight = maxi(0, _in_flight - 1)
	if is_instance_valid(http):
		http.queue_free()

	if _stopped:
		return

	var picture_url := ""
	if ok:
		picture_url = _picture_url_from_json(body)

	if picture_url.is_empty():
		_resolved[key] = true
		avatar_missing.emit(display)
		_pump()
		return

	# The directory answers with a URL; the image itself is a second request to
	# whatever CDN Privy uses. That one is fetched behind the same slot so the
	# concurrency cap covers the whole resolve, not just the JSON call.
	await _load_image(key, display, picture_url)


func _picture_url_from_json(body: PackedByteArray) -> String:
	if body.is_empty():
		return ""
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""
	var value := str((parsed as Dictionary).get("profile_picture_url", "")).strip_edges()
	# The backend only ever emits https, but a client must not be the place a
	# plaintext or non-web URL becomes a request.
	if not value.begins_with("https://"):
		return ""
	return value


func _load_image(key: String, display: String, url: String) -> void:
	var http := HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT_SEC
	http.use_threads = true
	add_child(http)

	if http.request(url) != OK:
		http.queue_free()
		_resolved[key] = true
		avatar_missing.emit(display)
		_pump()
		return

	var result: Array = await http.request_completed
	if is_instance_valid(http):
		http.queue_free()

	if _stopped:
		return

	var code := int(result[1])
	var body: PackedByteArray = result[3]
	var texture := _decode(code, body)

	_resolved[key] = true
	if texture != null:
		_textures[key] = texture
		avatar_ready.emit(display, texture)
	else:
		avatar_missing.emit(display)
	_pump()


## Format is sniffed from the bytes rather than trusted from Content-Type: a CDN
## can serve `image/*` for something Godot's loaders will reject, and probing
## every loader would print engine errors for each miss.
func _decode(code: int, body: PackedByteArray) -> Texture2D:
	if code != 200 or body.size() < 8:
		return null

	var image := Image.new()
	var loaded := false
	if _bytes_are_png(body):
		loaded = image.load_png_from_buffer(body) == OK
	elif _bytes_are_jpeg(body):
		loaded = image.load_jpg_from_buffer(body) == OK
	elif _bytes_are_webp(body):
		loaded = image.load_webp_from_buffer(body) == OK

	if not loaded:
		return null
	if image.get_width() < MIN_AVATAR_PIXELS or image.get_height() < MIN_AVATAR_PIXELS:
		return null

	return ImageTexture.create_from_image(image)


func _bytes_are_png(data: PackedByteArray) -> bool:
	return (
		data.size() >= 8
		and data[0] == 0x89 and data[1] == 0x50 and data[2] == 0x4E and data[3] == 0x47
	)


func _bytes_are_jpeg(data: PackedByteArray) -> bool:
	return data.size() >= 3 and data[0] == 0xFF and data[1] == 0xD8 and data[2] == 0xFF


func _bytes_are_webp(data: PackedByteArray) -> bool:
	if data.size() < 12:
		return false
	return (
		data[0] == 0x52 and data[1] == 0x49 and data[2] == 0x46 and data[3] == 0x46
		and data[8] == 0x57 and data[9] == 0x45 and data[10] == 0x42 and data[11] == 0x50
	)


func _cache_key(username: String) -> String:
	return username.strip_edges().to_lower()
