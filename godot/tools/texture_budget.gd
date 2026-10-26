extends SceneTree
## Texture budget audit for a low-end mobile target.
##
## Usage (headless, from the repo root):
##   godot --headless --script res://tools/texture_budget.gd
##
## Prints every imported texture with the size the importer produced and the
## VRAM it will cost at runtime, biggest first, then flags the ones that look
## wrong for a phone. Nothing is modified - fix the flags in the Import dock
## (Compress Mode = VRAM Compressed, Size Limit) or edit the `*.import` file.
##
## The numbers are a deliberately pessimistic estimate: we cannot see whether
## the importer chose RGB or RGBA, so VRAM-compressed textures are costed at
## 8 bits per pixel (RGBA) and everything else at 32.

## Above this a texture needs a very good reason on mobile.
const MAX_DIM := 1024
## Rough working set we are happy to see resident at once.
const BUDGET_MB := 64.0

## Texture2D import compression modes.
const MODE_LOSSLESS := 0
const MODE_LOSSY := 1
const MODE_VRAM := 2
const MODE_BASIS := 3

## UI art is deliberately lossless with no mipmaps: ETC2 makes HUD sprites and
## thin lines crawl. Textures under these folders are not flagged for it.
const UI_PREFIXES := ["assets/img/", "assets/ui/", "webexport/", "icon."]

const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "tga", "exr", "hdr", "bmp"]


func _initialize() -> void:
	var rows: Array[Dictionary] = []
	_scan("res://", rows)
	rows.sort_custom(func(a, b): return a.vram_kb > b.vram_kb)

	var total_kb := 0.0
	var flags: Array[Dictionary] = []

	for row in rows:
		total_kb += row.vram_kb
		var is_ui: bool = _is_ui_art(String(row.path))
		var reasons: PackedStringArray = []

		if not is_ui:
			if row.mode != MODE_VRAM and row.mode != MODE_BASIS:
				reasons.append("not VRAM compressed")
			if not row.mipmaps:
				reasons.append("no mipmaps")
			if row.size_limit == 0 and row.width > 512:
				reasons.append("no size limit (%dx%d)" % [row.width, row.height])

		if row.width > MAX_DIM or row.height > MAX_DIM:
			reasons.append("%dx%d" % [row.width, row.height])

		if reasons.size() > 0:
			row["why"] = ", ".join(reasons)
			flags.append(row)

	print("")
	print("Texture budget: %d imported textures, ~%.1f MB VRAM" % [rows.size(), total_kb / 1024.0])
	print("")
	print("%9s  %11s  %-8s %-5s  %s" % ["VRAM", "SIZE", "MODE", "MIPS", "FILE"])
	print("-".repeat(92))

	for i in mini(rows.size(), 30):
		var row: Dictionary = rows[i]
		print(
			"%8.0fK  %5dx%-5d  %-8s %-5s  %s"
			% [
				row.vram_kb,
				row.width,
				row.height,
				_mode_name(row.mode),
				"yes" if row.mipmaps else "no",
				String(row.path).trim_prefix("res://"),
			]
		)

	if rows.size() > 30:
		print("... and %d more" % (rows.size() - 30))

	print("")
	if flags.is_empty():
		print("Nothing to fix.")
	else:
		print("%d texture(s) worth a look:" % flags.size())
		for row in flags:
			print("  %-62s %7.0fK  %s" % [String(row.path).trim_prefix("res://"), row.vram_kb, row.why])

	print("")
	if total_kb / 1024.0 > BUDGET_MB:
		print("OVER BUDGET: %.1f MB > %.0f MB" % [total_kb / 1024.0, BUDGET_MB])
	else:
		print("Within budget (%.0f MB)." % BUDGET_MB)

	quit()


func _scan(dir_path: String, rows: Array[Dictionary]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return

	for file_name in dir.get_files():
		if not IMAGE_EXTENSIONS.has(file_name.get_extension().to_lower()):
			continue
		var path := dir_path.path_join(file_name)
		var row := _measure(path)
		if not row.is_empty():
			rows.append(row)

	for sub_dir in dir.get_directories():
		# The import cache holds generated copies, not sources.
		if sub_dir == ".godot":
			continue
		_scan(dir_path.path_join(sub_dir), rows)


func _measure(path: String) -> Dictionary:
	# Only imported textures can be measured; a raw file with no .import is
	# skipped (it will not be in the export either).
	if not FileAccess.file_exists(path + ".import"):
		return {}

	# Loading the *imported* resource gives the size the GPU actually gets,
	# i.e. after `process/size_limit` has been applied.
	var texture: Texture2D = load(path)
	if texture == null:
		return {}

	var params := _read_import_params(path + ".import")
	var width: int = texture.get_width()
	var height: int = texture.get_height()
	var mode: int = int(params.get("compress/mode", MODE_LOSSLESS))
	var mipmaps: bool = bool(params.get("mipmaps/generate", false))
	var size_limit: int = int(params.get("process/size_limit", 0))

	var bytes_per_pixel := 1.0 if (mode == MODE_VRAM or mode == MODE_BASIS) else 4.0
	var pixels := float(width * height)
	if mipmaps:
		pixels *= 1.3333

	return {
		"path": path,
		"width": width,
		"height": height,
		"mode": mode,
		"mipmaps": mipmaps,
		"size_limit": size_limit,
		"vram_kb": pixels * bytes_per_pixel / 1024.0,
	}


## Reads the `[params]` block of a `.import` file into a dictionary.
func _read_import_params(import_path: String) -> Dictionary:
	var params := {}
	var in_params := false
	for line in FileAccess.get_file_as_string(import_path).split("\n"):
		line = line.strip_edges()
		if line.begins_with("["):
			in_params = line == "[params]"
			continue
		if not in_params or line.is_empty() or not line.contains("="):
			continue
		var key := line.get_slice("=", 0)
		var value := line.get_slice("=", 1)
		if value.is_valid_int():
			params[key] = int(value)
		elif value.is_valid_float():
			params[key] = float(value)
		elif value == "true" or value == "false":
			params[key] = value == "true"
		else:
			params[key] = value
	return params


func _is_ui_art(path: String) -> bool:
	for prefix in UI_PREFIXES:
		if path.contains(prefix):
			return true
	return false


func _mode_name(mode: int) -> String:
	match mode:
		MODE_LOSSLESS:
			return "lossless"
		MODE_LOSSY:
			return "lossy"
		MODE_VRAM:
			return "vram"
		MODE_BASIS:
			return "basis"
		_:
			return "?"
