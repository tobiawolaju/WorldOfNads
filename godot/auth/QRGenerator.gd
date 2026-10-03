extends WONQRProvider
class_name WONQRGenerator

## Dependency-free QR Code (Model 2) encoder: byte mode, error-correction level M
## falling back to L for longer payloads.
##
## The project ships no QR addon, and adding one would mean a native build
## dependency for something the login screen needs once per login. This
## implements the slice of ISO/IEC 18004 that a URL-sized payload requires:
## byte-mode encoding, Reed-Solomon error correction over GF(256), block
## interleaving, function-pattern placement, all eight data masks with penalty
## scoring, and BCH format/version information.
##
## Scope is versions 1-10, which covers far more than any plausible World of
## Nads login URL. Longer input is reported as unavailable rather than silently
## truncated. `WONQRProvider` exists so a real library can replace this later
## without touching the auth logic.

const ECC_M := 0 # 00 in the format-information bit field
const ECC_L := 1 # 01

const QUIET_ZONE := 4
## Rendered pixels per module. Scanners start failing below roughly 4.
const PIXELS_PER_MODULE := 8

## Total codewords (data + error correction) per version, versions 1-10.
const TOTAL_CODEWORDS := [26, 44, 70, 100, 134, 172, 196, 242, 292, 346]

## Per version and ECC level:
## [ec_codewords_per_block, blocks_in_group_1, data_codewords_group_1,
##  blocks_in_group_2, data_codewords_group_2]
const ECC_TABLE := {
	1: {1: [7, 1, 19, 0, 0], 0: [10, 1, 16, 0, 0]},
	2: {1: [10, 1, 34, 0, 0], 0: [16, 1, 28, 0, 0]},
	3: {1: [15, 1, 55, 0, 0], 0: [26, 1, 44, 0, 0]},
	4: {1: [20, 1, 80, 0, 0], 0: [18, 2, 32, 0, 0]},
	5: {1: [26, 1, 108, 0, 0], 0: [24, 2, 43, 0, 0]},
	6: {1: [18, 2, 68, 0, 0], 0: [16, 4, 27, 0, 0]},
	7: {1: [20, 2, 78, 0, 0], 0: [18, 4, 31, 0, 0]},
	8: {1: [24, 2, 97, 0, 0], 0: [22, 2, 38, 2, 39]},
	9: {1: [30, 2, 116, 0, 0], 0: [22, 3, 36, 2, 37]},
	10: {1: [18, 2, 68, 2, 69], 0: [26, 4, 43, 1, 44]},
}

## Row/column centres of the alignment patterns, per version.
const ALIGNMENT_POSITIONS := {
	1: [], 2: [6, 18], 3: [6, 22], 4: [6, 26], 5: [6, 30],
	6: [6, 34], 7: [6, 22, 38], 8: [6, 24, 42], 9: [6, 26, 46], 10: [6, 28, 50]
}

## Zero bits appended after the interleaved codeword stream, per version.
const REMAINDER_BITS := [0, 7, 7, 7, 7, 7, 0, 0, 0, 0]

## 18-bit BCH version information, versions 7-10 only.
const VERSION_INFO := {7: 0x07C94, 8: 0x085BC, 9: 0x09A99, 10: 0x0A4D3}

const MAX_VERSION := 10

# ---------------------------------------------------------------------------
# WONQRProvider implementation
# ---------------------------------------------------------------------------

func provider_name() -> String:
	return "builtin"

func is_available() -> bool:
	return true

## Renders `text` as a QR texture, or null when the payload is out of range.
func generate(text: String, target_px: int = 512) -> ImageTexture:
	if text.is_empty():
		return null

	var modules := _build_matrix(text)
	if modules.is_empty():
		return null

	var count := modules.size()
	var dimension := count + QUIET_ZONE * 2
	var scale := maxi(PIXELS_PER_MODULE, int(floor(float(target_px) / float(dimension))))

	var image := Image.create_empty(dimension * scale, dimension * scale, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)

	# Fill rectangles per dark run rather than writing pixels one at a time.
	for y in count:
		for x in count:
			if modules[y * count + x] != 1:
				continue
			image.fill_rect(
				Rect2i((x + QUIET_ZONE) * scale, (y + QUIET_ZONE) * scale, scale, scale),
				Color.BLACK
			)

	return ImageTexture.create_from_image(image)

# ---------------------------------------------------------------------------
# Version selection and data encoding
# ---------------------------------------------------------------------------

## Smallest version that fits. Version is the outer loop and error-correction
## level the inner one, so the size is minimised first and M is preferred within
## each version. Iterating level-first instead would skip straight past the
## larger L capacity of a small version (a 15-17 byte payload belongs in v1-L,
## not v2-M) and always emit a denser code than necessary.
func _choose_version(byte_length: int) -> Dictionary:
	for version in range(1, MAX_VERSION + 1):
		for ecc_level in [ECC_M, ECC_L]:
			var spec: Array = ECC_TABLE[version][ecc_level]
			var data_codewords: int = int(spec[1]) * int(spec[2]) + int(spec[3]) * int(spec[4])
			var count_bits := 8 if version < 10 else 16
			# 4 mode bits + count field precede the payload.
			var capacity_bytes := int(floor((data_codewords * 8 - 4 - count_bits) / 8.0))
			if byte_length <= capacity_bytes:
				return {
					"version": version,
					"ecc_level": ecc_level,
					"data_codewords": data_codewords,
					"ec_per_block": int(spec[0]),
					"blocks_g1": int(spec[1]),
					"data_g1": int(spec[2]),
					"blocks_g2": int(spec[3]),
					"data_g2": int(spec[4]),
				}
	return {}

## Byte mode: 4-bit mode indicator, character count, then UTF-8 bytes.
## The terminator and padding are added later, once the capacity is known.
func _encode_byte_mode(payload: PackedByteArray, version: int) -> PackedInt32Array:
	var bits := PackedInt32Array()
	bits.append_array(_to_bits(0b0100, 4))
	bits.append_array(_to_bits(payload.size(), 8 if version < 10 else 16))
	for byte in payload:
		bits.append_array(_to_bits(byte, 8))
	return bits

func _to_codewords(bits: PackedInt32Array, target_codewords: int) -> PackedInt32Array:
	var stream := bits.duplicate()

	# Terminator: up to four zero bits, stopping at the capacity boundary.
	while stream.size() < target_codewords * 8 and stream.size() % 8 != 0:
		stream.append(0)

	# Alternating pad codewords fill whatever is left.
	var pad := [0xEC, 0x11]
	var pad_index := 0
	while stream.size() < target_codewords * 8:
		stream.append_array(_to_bits(pad[pad_index], 8))
		pad_index = (pad_index + 1) % 2

	var codewords := PackedInt32Array()
	for i in range(0, stream.size(), 8):
		var value := 0
		for bit in 8:
			value = (value << 1) | stream[i + bit]
		codewords.append(value)
	return codewords

func _to_bits(value: int, bit_count: int) -> PackedInt32Array:
	var bits := PackedInt32Array()
	for i in range(bit_count - 1, -1, -1):
		bits.append((value >> i) & 1)
	return bits

# ---------------------------------------------------------------------------
# Reed-Solomon over GF(256), primitive polynomial 0x11D
# ---------------------------------------------------------------------------

static func _gf_mul(a: int, b: int) -> int:
	var result := 0
	var x := a
	var y := b
	for _i in 8:
		if y & 1:
			result ^= x
		y >>= 1
		x <<= 1
		if x & 0x100:
			x ^= 0x11D
	return result

static func _gf_pow(base: int, exponent: int) -> int:
	var result := 1
	for _i in exponent:
		result = _gf_mul(result, base)
	return result

## Generator polynomial for `degree` EC codewords: the product of
## (x - 2^i) for i in [0, degree), highest power first.
static func _generator_polynomial(degree: int) -> PackedInt32Array:
	var poly := PackedInt32Array()
	poly.append(1)
	for i in degree:
		poly = _poly_multiply(poly, _gf_pow(2, i))
	return poly

## Returns `a * (x + scalar)` with coefficients ordered highest power first.
##
## In highest-power-first order the multiplication by `x` keeps a[i] at index
## i (it raises the degree by one, which extends the array), while the scalar
## term shifts it up one further slot at index i + 1. Both land in the same
## length-(n + 1) result.
static func _poly_multiply(a: PackedInt32Array, scalar: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(a.size() + 1)
	for i in a.size():
		out[i] ^= a[i]
		out[i + 1] ^= _gf_mul(a[i], scalar)
	return out

## Error correction codewords for one block, via polynomial long division.
static func _reed_solomon(data: PackedInt32Array, degree: int) -> PackedInt32Array:
	if degree <= 0:
		return PackedInt32Array()

	var generator := _generator_polynomial(degree)

	var remainder := PackedInt32Array()
	remainder.resize(degree)
	for byte in data:
		var factor: int = byte ^ remainder[0]
		for i in range(degree - 1):
			remainder[i] = remainder[i + 1] ^ _gf_mul(factor, generator[i + 1])
		remainder[degree - 1] = _gf_mul(factor, generator[degree])
	return remainder

## Splits into blocks, appends ECC to each, then interleaves both streams.
func _add_error_correction(
	codewords: PackedInt32Array, version: int, placement: Dictionary
) -> PackedInt32Array:
	var ec_per_block: int = placement["ec_per_block"]

	var data_blocks: Array[PackedInt32Array] = []
	var ec_blocks: Array[PackedInt32Array] = []

	var offset := 0
	for _i in int(placement["blocks_g1"]):
		var block := _slice(codewords, offset, int(placement["data_g1"]))
		offset += block.size()
		data_blocks.append(block)
		ec_blocks.append(_reed_solomon(block, ec_per_block))

	for _i in int(placement["blocks_g2"]):
		var block := _slice(codewords, offset, int(placement["data_g2"]))
		offset += block.size()
		data_blocks.append(block)
		ec_blocks.append(_reed_solomon(block, ec_per_block))

	# Interleave: one codeword from each block in turn, data first then EC, so a
	# physical smudge spreads across blocks instead of destroying one.
	var result := PackedInt32Array()
	var longest_data := 0
	for block in data_blocks:
		longest_data = maxi(longest_data, block.size())
	for i in longest_data:
		for block in data_blocks:
			if i < block.size():
				result.append(block[i])
	for i in ec_per_block:
		for block in ec_blocks:
			if i < block.size():
				result.append(block[i])

	# The remainder bits are defined to be zero and simply pad the stream out to
	# a whole number of modules.
	result.resize(result.size() + int(REMAINDER_BITS[version - 1]))
	return result

func _slice(source: PackedInt32Array, offset: int, length: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in range(offset, mini(offset + length, source.size())):
		out.append(source[i])
	return out

# ---------------------------------------------------------------------------
# Matrix construction
# ---------------------------------------------------------------------------

func _build_matrix(text: String) -> PackedInt32Array:
	var payload := text.to_utf8_buffer()
	var placement := _choose_version(payload.size())
	if placement.is_empty():
		return PackedInt32Array()

	var version: int = placement["version"]
	var ecc_level: int = placement["ecc_level"]

	var codewords := _to_codewords(_encode_byte_mode(payload, version), placement["data_codewords"])
	var stream := _add_error_correction(codewords, version, placement)
	return _render_matrix(stream, version, ecc_level)

func _render_matrix(stream: PackedInt32Array, version: int, ecc_level: int) -> PackedInt32Array:
	var size := version * 4 + 17

	var modules := PackedInt32Array()
	modules.resize(size * size)
	modules.fill(0)

	var reserved := PackedByteArray()
	reserved.resize(size * size)
	reserved.fill(0)

	_draw_finders(modules, reserved, size)
	_draw_timing(modules, reserved, size)
	_draw_alignment(modules, reserved, size, version)
	_reserve_format(reserved, size)
	_reserve_version(reserved, size, version)

	_place_data(modules, reserved, size, stream)
	_write_version_info(modules, size, version)
	_apply_best_mask(modules, size, version, ecc_level)
	return modules

func _put(modules: PackedInt32Array, reserved: PackedByteArray, size: int, x: int, y: int, value: int) -> void:
	if x < 0 or y < 0 or x >= size or y >= size:
		return
	modules[y * size + x] = value
	reserved[y * size + x] = 1

## Finder patterns (7x7 rings), their separators, and the always-dark module.
func _draw_finders(modules: PackedInt32Array, reserved: PackedByteArray, size: int) -> void:
	var origins := [Vector2i(0, 0), Vector2i(size - 7, 0), Vector2i(0, size - 7)]
	for origin in origins:
		for dy in range(-1, 8):
			for dx in range(-1, 8):
				var x: int = origin.x + dx
				var y: int = origin.y + dy
				if x < 0 or y < 0 or x >= size or y >= size:
					continue
				var dark := 0
				if dx >= 0 and dx <= 6 and dy >= 0 and dy <= 6:
					# Chebyshev distance from the edge: 0 on the border, 1 inside,
					# 2 in the middle band, 3 in the core.
					var ring := mini(mini(dx, dy), mini(6 - dx, 6 - dy))
					dark = 1 if ring == 0 or ring == 2 else 0
				_put(modules, reserved, size, x, y, dark)

	_put(modules, reserved, size, 8, size - 8, 1)

func _draw_timing(modules: PackedInt32Array, reserved: PackedByteArray, size: int) -> void:
	for i in range(8, size - 8):
		var bit := 1 if i % 2 == 0 else 0
		_put(modules, reserved, size, i, 6, bit)
		_put(modules, reserved, size, 6, i, bit)

func _draw_alignment(
	modules: PackedInt32Array, reserved: PackedByteArray, size: int, version: int
) -> void:
	var positions: Array = ALIGNMENT_POSITIONS[version]
	for cy_value in positions:
		for cx_value in positions:
			var cx := int(cx_value)
			var cy := int(cy_value)
			# Skip the three positions that would collide with a finder.
			var on_finder := (cx <= 8 and cy <= 8) \
				or (cx <= 8 and cy >= size - 9) \
				or (cx >= size - 9 and cy <= 8)
			if on_finder:
				continue
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var ring := maxi(absi(dx), absi(dy))
					_put(modules, reserved, size, cx + dx, cy + dy, 1 if ring != 1 else 0)

func _reserve_format(reserved: PackedByteArray, size: int) -> void:
	for i in 9:
		reserved[i * size + 8] = 1
		reserved[8 * size + i] = 1
	for i in 8:
		reserved[8 * size + (size - 1 - i)] = 1
		reserved[(size - 1 - i) * size + 8] = 1

func _reserve_version(reserved: PackedByteArray, size: int, version: int) -> void:
	if version < 7:
		return
	for i in 18:
		var row := i / 3
		var col := size - 11 + (i % 3)
		reserved[row * size + col] = 1
		reserved[col * size + row] = 1

## Zig-zag walk upward/downward in two-column strips, skipping the timing column.
func _place_data(
	modules: PackedInt32Array, reserved: PackedByteArray, size: int, stream: PackedInt32Array
) -> void:
	var bits := PackedInt32Array()
	for byte in stream:
		bits.append_array(_to_bits(byte, 8))

	var bit_index := 0
	var upward := true
	var col := size - 1

	while col > 0:
		if col == 6:
			col -= 1  # column 6 is the vertical timing pattern
		for step in size:
			var row: int = (size - 1 - step) if upward else step
			for offset in 2:
				var x: int = col - offset
				var index := row * size + x
				if reserved[index] == 1:
					continue
				modules[index] = bits[bit_index] if bit_index < bits.size() else 0
				bit_index += 1
		upward = not upward
		col -= 2

func _write_version_info(modules: PackedInt32Array, size: int, version: int) -> void:
	if version < 7:
		return
	var value: int = VERSION_INFO[version]
	for i in 18:
		var bit := (value >> i) & 1
		var row := i / 3
		var col := size - 11 + (i % 3)
		modules[row * size + col] = bit
		modules[col * size + row] = bit

# ---------------------------------------------------------------------------
# Masking
# ---------------------------------------------------------------------------

func _apply_best_mask(modules: PackedInt32Array, size: int, version: int, ecc_level: int) -> void:
	var best: PackedInt32Array = modules.duplicate()
	var best_penalty := -1

	for mask in 8:
		var candidate := modules.duplicate()
		_apply_mask(candidate, size, version, mask)
		_write_format_info(candidate, size, ecc_level, mask)
		var penalty := _penalty(candidate, size)
		if best_penalty < 0 or penalty < best_penalty:
			best_penalty = penalty
			best = candidate

	for i in modules.size():
		modules[i] = best[i]

func _apply_mask(modules: PackedInt32Array, size: int, version: int, mask: int) -> void:
	for y in size:
		for x in size:
			if _is_function_module(size, version, x, y):
				continue
			if _mask_applies(mask, x, y):
				modules[y * size + x] = 1 - modules[y * size + x]

## Function patterns must keep their values under every mask.
func _is_function_module(size: int, version: int, x: int, y: int) -> bool:
	# Finder patterns plus their separators. The separator sits at size - 8, so
	# the boundary is size - 8 and not size - 9: using the latter would exempt a
	# column or row of ordinary data modules from the mask, and every decoder
	# would then un-mask bits that were never masked.
	if x <= 8 and y <= 8:
		return true
	if x >= size - 8 and y <= 8:
		return true
	if x <= 8 and y >= size - 8:
		return true
	# Timing patterns.
	if x == 6 or y == 6:
		return true
	# Format information, both copies.
	if x == 8 and (y <= 8 or y >= size - 8):
		return true
	if y == 8 and (x <= 8 or x >= size - 8):
		return true
	# Version information, versions 7 and up only. Below that these coordinates
	# overlap ordinary data modules, so the check has to be gated on version.
	if version >= 7:
		if x <= 5 and y >= size - 11 and y <= size - 9:
			return true
		if y <= 5 and x >= size - 11 and x <= size - 9:
			return true
	return false

func _mask_applies(mask: int, x: int, y: int) -> bool:
	match mask:
		0: return (x + y) % 2 == 0
		1: return y % 2 == 0
		2: return x % 3 == 0
		3: return (x + y) % 3 == 0
		4: return (int(y / 2) + int(x / 3)) % 2 == 0
		5: return (x * y) % 2 + (x * y) % 3 == 0
		6: return ((x * y) % 2 + (x * y) % 3) % 2 == 0
		_: return ((x + y) % 2 + (x * y) % 3) % 2 == 0

## 15-bit format information: 5 data bits, BCH(15,5), XOR-masked with 0x5412.
## The generator is 0x537 (10100110111); the mask pattern is 0x5412.
func _format_bits(ecc_level: int, mask: int) -> PackedInt32Array:
	var data := ((ecc_level & 0b11) << 3) | (mask & 0b111)

	# Long division of the 5 data bits shifted into the top of the 15-bit field,
	# discarding the remainder after ten redundant bits.
	var remainder := data << 10
	for i in range(14, 9, -1):
		if (remainder >> i) & 1:
			remainder ^= 0b10100110111 << (i - 10)

	return _to_bits(((data << 10) | remainder) ^ 0b101010000010010, 15)

func _write_format_info(modules: PackedInt32Array, size: int, ecc_level: int, mask: int) -> void:
	var bits := _format_bits(ecc_level, mask)

	# First copy, wrapped around the top-left finder.
	for i in 6:
		modules[8 * size + i] = bits[i]
	modules[8 * size + 7] = bits[6]
	modules[8 * size + 8] = bits[7]
	modules[7 * size + 8] = bits[8]
	for i in range(9, 15):
		modules[(14 - i) * size + 8] = bits[i]

	# Second copy, split between the other two finders.
	for i in range(7):
		modules[(size - 1 - i) * size + 8] = bits[i]
	for i in range(8):
		modules[8 * size + (size - 8 + i)] = bits[7 + i]

# ---------------------------------------------------------------------------
# Mask selection
# ---------------------------------------------------------------------------

## Standard penalty score; the lowest score is the easiest to scan.
func _penalty(modules: PackedInt32Array, size: int) -> int:
	var score := 0

	# Rule 1: runs of five or more same-coloured modules in a row or column.
	for y in size:
		var run := 1
		for x in range(1, size):
			if modules[y * size + x] == modules[y * size + x - 1]:
				run += 1
			else:
				if run >= 5:
					score += 3 + (run - 5)
				run = 1
		if run >= 5:
			score += 3 + (run - 5)

	for x in size:
		var run := 1
		for y in range(1, size):
			if modules[y * size + x] == modules[(y - 1) * size + x]:
				run += 1
			else:
				if run >= 5:
					score += 3 + (run - 5)
				run = 1
		if run >= 5:
			score += 3 + (run - 5)

	# Rule 2: every 2x2 block of one colour.
	for y in range(size - 1):
		for x in range(size - 1):
			var value := modules[y * size + x]
			if value == modules[y * size + x + 1] \
				and value == modules[(y + 1) * size + x] \
				and value == modules[(y + 1) * size + x + 1]:
				score += 3

	# Rule 3: the 1:1:3:1:1 finder-like sequence with four light modules on
	# either side. Both the pattern and its mirror count, in rows and columns.
	var pattern_a := [1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0]
	var pattern_b := [0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1]
	for pattern in [pattern_a, pattern_b]:
		for y in size:
			for x in range(size - 10):
				var matched := true
				for i in 11:
					if modules[y * size + x + i] != pattern[i]:
						matched = false
						break
				if matched:
					score += 40
		for x in size:
			for y in range(size - 10):
				var matched := true
				for i in 11:
					if modules[(y + i) * size + x] != pattern[i]:
						matched = false
						break
				if matched:
					score += 40

	# Rule 4: overall balance of dark and light modules.
	var dark := 0
	for value in modules:
		if value == 1:
			dark += 1
	var percent := (float(dark) / float(modules.size())) * 100.0
	score += int(absf(percent - 50.0) / 5.0) * 10

	return score