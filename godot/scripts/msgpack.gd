extends RefCounted
class_name MsgPack

static func pack(value) -> PackedByteArray:
	var out := PackedByteArray()
	_pack_value(value, out)
	return out

static func unpack(data: PackedByteArray):
	var offset := [0]
	return _unpack_value(data, offset)

static func _pack_value(value, out: PackedByteArray) -> void:
	match typeof(value):
		TYPE_NIL:
			out.append(0xC0)
		TYPE_BOOL:
			out.append(0xC3 if value else 0xC2)
		TYPE_INT:
			_pack_int(int(value), out)
		TYPE_FLOAT:
			# Use int wire format whenever possible to keep packets small.
			var as_int := int(round(float(value)))
			if is_equal_approx(float(as_int), float(value)):
				_pack_int(as_int, out)
			else:
				out.append(0xCB)
				_append_u64(out, _float_to_u64(float(value)))
		TYPE_STRING:
			_pack_string(String(value), out)
		TYPE_ARRAY:
			_pack_array(value as Array, out)
		TYPE_DICTIONARY:
			_pack_map(value as Dictionary, out)
		_:
			out.append(0xC0)

static func _pack_int(v: int, out: PackedByteArray) -> void:
	if v >= 0 and v <= 0x7F:
		out.append(v)
	elif v >= -32 and v < 0:
		out.append(0x100 + v)
	elif v >= 0 and v <= 0xFF:
		out.append(0xCC)
		out.append(v)
	elif v >= 0 and v <= 0xFFFF:
		out.append(0xCD)
		_append_u16(out, v)
	elif v >= 0 and v <= 0xFFFFFFFF:
		out.append(0xCE)
		_append_u32(out, v)
	elif v >= -128 and v <= 127:
		out.append(0xD0)
		out.append(v & 0xFF)
	elif v >= -32768 and v <= 32767:
		out.append(0xD1)
		_append_u16(out, v & 0xFFFF)
	else:
		out.append(0xD2)
		_append_u32(out, v & 0xFFFFFFFF)

static func _pack_string(s: String, out: PackedByteArray) -> void:
	var b := s.to_utf8_buffer()
	var n := b.size()
	if n <= 31:
		out.append(0xA0 | n)
	elif n <= 0xFF:
		out.append(0xD9)
		out.append(n)
	else:
		out.append(0xDA)
		_append_u16(out, n)
	out.append_array(b)

static func _pack_array(arr: Array, out: PackedByteArray) -> void:
	var n := arr.size()
	if n <= 15:
		out.append(0x90 | n)
	else:
		out.append(0xDC)
		_append_u16(out, n)
	for item in arr:
		_pack_value(item, out)

static func _pack_map(map: Dictionary, out: PackedByteArray) -> void:
	var n := map.size()
	if n <= 15:
		out.append(0x80 | n)
	else:
		out.append(0xDE)
		_append_u16(out, n)
	for key in map.keys():
		_pack_value(str(key), out)
		_pack_value(map[key], out)

static func _unpack_value(data: PackedByteArray, offset_ref: Array):
	if offset_ref[0] >= data.size():
		return null
	var b := data[offset_ref[0]]
	offset_ref[0] += 1

	if b <= 0x7F:
		return b
	if b >= 0xE0:
		return b - 0x100
	if (b & 0xE0) == 0xA0:
		var n := b & 0x1F
		return _read_string(data, offset_ref, n)
	if (b & 0xF0) == 0x90:
		var n := b & 0x0F
		return _read_array(data, offset_ref, n)
	if (b & 0xF0) == 0x80:
		var n := b & 0x0F
		return _read_map(data, offset_ref, n)

	match b:
		0xC0:
			return null
		0xC2:
			return false
		0xC3:
			return true
		0xCC:
			return _read_u8(data, offset_ref)
		0xCD:
			return _read_u16(data, offset_ref)
		0xCE:
			return _read_u32(data, offset_ref)
		0xD0:
			var v8 := _read_u8(data, offset_ref)
			return v8 - 0x100 if v8 >= 0x80 else v8
		0xD1:
			var v16 := _read_u16(data, offset_ref)
			return v16 - 0x10000 if v16 >= 0x8000 else v16
		0xD2:
			var v32 := _read_u32(data, offset_ref)
			return v32 - 0x100000000 if v32 >= 0x80000000 else v32
		0xD9:
			return _read_string(data, offset_ref, _read_u8(data, offset_ref))
		0xDA:
			return _read_string(data, offset_ref, _read_u16(data, offset_ref))
		0xDC:
			return _read_array(data, offset_ref, _read_u16(data, offset_ref))
		0xDE:
			return _read_map(data, offset_ref, _read_u16(data, offset_ref))
		0xCB:
			var raw := _read_u64(data, offset_ref)
			return _u64_to_float(raw)
		_:
			return null

static func _read_u8(data: PackedByteArray, offset_ref: Array) -> int:
	var v := data[offset_ref[0]]
	offset_ref[0] += 1
	return v

static func _read_u16(data: PackedByteArray, offset_ref: Array) -> int:
	var base := offset_ref[0]
	var v := (data[base] << 8) | data[base + 1]
	offset_ref[0] += 2
	return v

static func _read_u32(data: PackedByteArray, offset_ref: Array) -> int:
	var base := offset_ref[0]
	var v := (data[base] << 24) | (data[base + 1] << 16) | (data[base + 2] << 8) | data[base + 3]
	offset_ref[0] += 4
	return v

static func _read_u64(data: PackedByteArray, offset_ref: Array) -> int:
	var hi := _read_u32(data, offset_ref)
	var lo := _read_u32(data, offset_ref)
	return (hi << 32) | lo

static func _read_string(data: PackedByteArray, offset_ref: Array, n: int) -> String:
	var start := offset_ref[0]
	var b := data.slice(start, start + n)
	offset_ref[0] += n
	return b.get_string_from_utf8()

static func _read_array(data: PackedByteArray, offset_ref: Array, n: int) -> Array:
	var out := []
	for _i in range(n):
		out.append(_unpack_value(data, offset_ref))
	return out

static func _read_map(data: PackedByteArray, offset_ref: Array, n: int) -> Dictionary:
	var out := {}
	for _i in range(n):
		var k = _unpack_value(data, offset_ref)
		var v = _unpack_value(data, offset_ref)
		out[str(k)] = v
	return out

static func _append_u16(out: PackedByteArray, v: int) -> void:
	out.append((v >> 8) & 0xFF)
	out.append(v & 0xFF)

static func _append_u32(out: PackedByteArray, v: int) -> void:
	out.append((v >> 24) & 0xFF)
	out.append((v >> 16) & 0xFF)
	out.append((v >> 8) & 0xFF)
	out.append(v & 0xFF)

static func _append_u64(out: PackedByteArray, v: int) -> void:
	_append_u32(out, (v >> 32) & 0xFFFFFFFF)
	_append_u32(out, v & 0xFFFFFFFF)

static func _float_to_u64(v: float) -> int:
	var packed := PackedByteArray()
	packed.resize(8)
	packed.encode_double(0, v)
	var hi := (packed[0] << 24) | (packed[1] << 16) | (packed[2] << 8) | packed[3]
	var lo := (packed[4] << 24) | (packed[5] << 16) | (packed[6] << 8) | packed[7]
	return (hi << 32) | lo

static func _u64_to_float(v: int) -> float:
	var packed := PackedByteArray()
	packed.resize(8)
	packed[0] = (v >> 56) & 0xFF
	packed[1] = (v >> 48) & 0xFF
	packed[2] = (v >> 40) & 0xFF
	packed[3] = (v >> 32) & 0xFF
	packed[4] = (v >> 24) & 0xFF
	packed[5] = (v >> 16) & 0xFF
	packed[6] = (v >> 8) & 0xFF
	packed[7] = v & 0xFF
	return packed.decode_double(0)
