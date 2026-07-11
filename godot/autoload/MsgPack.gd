extends Node

static func pack(data) -> PackedByteArray:
	var buf := PackedByteArray()
	_pack_value(buf, data)
	return buf

static func _pack_value(buf: PackedByteArray, value) -> void:
	if value == null:
		buf.append(0xc0)
	elif typeof(value) == TYPE_BOOL:
		buf.append(0xc3 if value else 0xc2)
	elif typeof(value) == TYPE_INT:
		_pack_int(buf, value)
	elif typeof(value) == TYPE_FLOAT:
		buf.append(0xcb)
		_pack_bytes(buf, _float64_to_bytes(value))
	elif typeof(value) == TYPE_STRING:
		_pack_string(buf, value)
	elif typeof(value) == TYPE_ARRAY or typeof(value) == TYPE_PACKED_BYTE_ARRAY:
		_pack_array(buf, value)
	elif typeof(value) == TYPE_DICTIONARY:
		_pack_map(buf, value)
	elif typeof(value) == TYPE_PACKED_INT32_ARRAY:
		_pack_array(buf, value)
	elif typeof(value) == TYPE_PACKED_FLOAT32_ARRAY:
		_pack_array(buf, value)
	elif typeof(value) == TYPE_PACKED_STRING_ARRAY:
		_pack_array(buf, value)
	else:
		push_error("MsgPack.pack: unsupported type %s" % typeof(value))

static func _pack_int(buf: PackedByteArray, val: int) -> void:
	if val >= 0 and val <= 127:
		buf.append(val)
	elif val >= -32 and val <= -1:
		buf.append(val & 0xff)
	elif val >= -128 and val <= 127:
		buf.append(0xd0)
		buf.append(val & 0xff)
	elif val >= -32768 and val <= 32767:
		buf.append(0xd1)
		buf.append((val >> 8) & 0xff)
		buf.append(val & 0xff)
	elif val >= -8388608 and val <= 8388607:
		buf.append(0xd2)
		buf.append((val >> 24) & 0xff)
		buf.append((val >> 16) & 0xff)
		buf.append((val >> 8) & 0xff)
		buf.append(val & 0xff)
	elif val >= -140737488355328 and val <= 140737488355327:
		buf.append(0xd3)
		buf.append((val >> 56) & 0xff)
		buf.append((val >> 48) & 0xff)
		buf.append((val >> 40) & 0xff)
		buf.append((val >> 32) & 0xff)
		buf.append((val >> 24) & 0xff)
		buf.append((val >> 16) & 0xff)
		buf.append((val >> 8) & 0xff)
		buf.append(val & 0xff)
	else:
		if val >= 0:
			if val <= 0xffffffff:
				buf.append(0xce)
				buf.append((val >> 24) & 0xff)
				buf.append((val >> 16) & 0xff)
				buf.append((val >> 8) & 0xff)
				buf.append(val & 0xff)
			else:
				buf.append(0xcf)
				buf.append((val >> 56) & 0xff)
				buf.append((val >> 48) & 0xff)
				buf.append((val >> 40) & 0xff)
				buf.append((val >> 32) & 0xff)
				buf.append((val >> 24) & 0xff)
				buf.append((val >> 16) & 0xff)
				buf.append((val >> 8) & 0xff)
				buf.append(val & 0xff)
		else:
			buf.append(0xd3)
			buf.append((val >> 56) & 0xff)
			buf.append((val >> 48) & 0xff)
			buf.append((val >> 40) & 0xff)
			buf.append((val >> 32) & 0xff)
			buf.append((val >> 24) & 0xff)
			buf.append((val >> 16) & 0xff)
			buf.append((val >> 8) & 0xff)
			buf.append(val & 0xff)

static func _pack_string(buf: PackedByteArray, val: String) -> void:
	var bytes := val.to_utf8_buffer()
	var length := bytes.size()
	if length <= 31:
		buf.append(0xa0 | length)
	elif length <= 255:
		buf.append(0xd9)
		buf.append(length)
	elif length <= 65535:
		buf.append(0xda)
		buf.append((length >> 8) & 0xff)
		buf.append(length & 0xff)
	else:
		buf.append(0xdb)
		buf.append((length >> 24) & 0xff)
		buf.append((length >> 16) & 0xff)
		buf.append((length >> 8) & 0xff)
		buf.append(length & 0xff)
	buf.append_array(bytes)

static func _pack_array(buf: PackedByteArray, val: Array) -> void:
	var length := val.size()
	if length <= 15:
		buf.append(0x90 | length)
	elif length <= 65535:
		buf.append(0xdc)
		buf.append((length >> 8) & 0xff)
		buf.append(length & 0xff)
	else:
		buf.append(0xdd)
		buf.append((length >> 24) & 0xff)
		buf.append((length >> 16) & 0xff)
		buf.append((length >> 8) & 0xff)
		buf.append(length & 0xff)
	for v in val:
		_pack_value(buf, v)

static func _pack_map(buf: PackedByteArray, val: Dictionary) -> void:
	var length := val.size()
	if length <= 15:
		buf.append(0x80 | length)
	elif length <= 65535:
		buf.append(0xde)
		buf.append((length >> 8) & 0xff)
		buf.append(length & 0xff)
	else:
		buf.append(0xdf)
		buf.append((length >> 24) & 0xff)
		buf.append((length >> 16) & 0xff)
		buf.append((length >> 8) & 0xff)
		buf.append(length & 0xff)
	for key in val:
		if typeof(key) == TYPE_STRING:
			_pack_string(buf, key)
		else:
			_pack_value(buf, key)
		_pack_value(buf, val[key])

static func _pack_bytes(buf: PackedByteArray, bytes: PackedByteArray) -> void:
	buf.append_array(bytes)

static func _float64_to_bytes(val: float) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, val)
	return bytes
