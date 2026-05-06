## String ↔ WL grammar. Int-preserving JSON. No game semantics.

class_name WireCodec extends RefCounted


## Parse one JSON line into a WL Dictionary (or Array / primitive). Returns null on parse error.
static func decode(line: String) -> Variant:
	var json := JSON.new()
	var err := json.parse(line)
	if err != OK:
		push_error("WireCodec.decode: %s (line: %s)" % [json.get_error_message(), line])
		return null
	return json.data


## Encode a WL value to a JSON string. Whole-valued floats emit without a
## decimal point so round-trips through JSON don't turn `0` into `0.0` — required
## for protocol §4.4 byte-identical echo of response options.
static func encode(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_INT:
			return str(value)
		TYPE_FLOAT:
			var f: float = value
			if is_finite(f) and abs(f) < 1e16 and f == floor(f):
				return str(int(f))
			return String.num(f)
		TYPE_STRING, TYPE_STRING_NAME:
			return JSON.stringify(value)
		# `as Dictionary` / `as Array` narrow `value: Variant` for iteration —
		# cannot be dropped because `match typeof(value)` does not flow-narrow
		# the static type of `value` in GDScript.
		TYPE_DICTIONARY:
			var parts: PackedStringArray = []
			for k in (value as Dictionary):
				parts.append(JSON.stringify(str(k)) + ":" + encode(value[k]))
			return "{" + ",".join(parts) + "}"
		TYPE_ARRAY:
			var parts: PackedStringArray = []
			for v in (value as Array):
				parts.append(encode(v))
			return "[" + ",".join(parts) + "]"
		_:
			return JSON.stringify(value)
