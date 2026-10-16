class_name CanonicalJSON
extends RefCounted

static func encode(value: Variant, path: String = "$") -> Dictionary:
	var fragments: Array[String] = []
	var location: Array[String] = [path]
	var error := {}
	if not _append(value, fragments, location, error): return error
	return _ok("".join(fragments))

# Accumulate once, rather than returning a dictionary and rebuilding every
# ancestor string for every leaf. Error paths are materialized only on failure.
static func _append(value: Variant, fragments: Array[String], location: Array[String], error: Dictionary) -> bool:
	match typeof(value):
		TYPE_DICTIONARY:
			var source: Dictionary = value
			var keys: Array[String] = []
			for raw_key in source.keys():
				if typeof(raw_key) != TYPE_STRING: return _append_error("non_string_key", location, error)
				keys.append(str(raw_key))
			keys.sort()
			fragments.append("{")
			var first := true
			for key in keys:
				if not first: fragments.append(",")
				first = false
				fragments.append(JSON.stringify(key) + ":")
				location.append("." + key)
				if not _append(source[key], fragments, location, error): return false
				location.pop_back()
			fragments.append("}")
		TYPE_ARRAY:
			fragments.append("[")
			for index in range((value as Array).size()):
				if index > 0: fragments.append(",")
				location.append("[%d]" % index)
				if not _append(value[index], fragments, location, error): return false
				location.pop_back()
			fragments.append("]")
		TYPE_NIL:
			fragments.append("null")
		TYPE_BOOL:
			fragments.append("true" if value else "false")
		TYPE_INT:
			fragments.append(str(value))
		TYPE_FLOAT:
			if is_nan(value) or is_inf(value): return _append_error("non_finite_number", location, error)
			if value == 0.0: fragments.append("0")
			elif value == round(value): fragments.append(str(int(value)))
			else: fragments.append(String.num(float(value), 17))
		TYPE_STRING:
			fragments.append(JSON.stringify(value))
		_:
			return _append_error("unsupported_type", location, error)
	return true

static func _append_error(code: String, location: Array[String], error: Dictionary) -> bool:
	error.merge(_fail(code, "".join(location)))
	return false

static func hash_value(value: Variant) -> Dictionary:
	var encoded := encode(value)
	if not bool(encoded.get("ok", false)):
		return encoded
	return {"ok": true, "hash": str(encoded.get("text", "")).sha256_text()}

# Check every value before comparison, including branches after a difference.
# This is transaction-local work, with no mutable-state cache or stale hash.
static func compare_values(left: Variant, right: Variant) -> Dictionary:
	var left_validation := validate_value(left)
	if not left_validation.ok: return left_validation
	var right_validation := validate_value(right)
	if not right_validation.ok: return right_validation
	return {"ok": true, "equal": _equal_canonical(left, right)}

static func validate_value(value: Variant) -> Dictionary:
	var location: Array[String] = ["$"]
	var error := {}
	if not _validate_value(value, location, error): return error
	return {"ok": true}

static func _validate_value(value: Variant, location: Array[String], error: Dictionary) -> bool:
	match typeof(value):
		TYPE_DICTIONARY:
			var keys: Array = value.keys()
			for key in keys:
				if typeof(key) != TYPE_STRING: return _append_error("non_string_key", location, error)
			keys.sort()
			for key in keys:
				var child: Variant = value[key]
				var child_type := typeof(child)
				if child_type in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING]: continue
				if child_type == TYPE_FLOAT and not is_nan(child) and not is_inf(child): continue
				location.append("." + key)
				if not _validate_value(child, location, error): return false
				location.pop_back()
		TYPE_ARRAY:
			for index in value.size():
				var child: Variant = value[index]
				var child_type := typeof(child)
				if child_type in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING]: continue
				if child_type == TYPE_FLOAT and not is_nan(child) and not is_inf(child): continue
				location.append("[%d]" % index)
				if not _validate_value(child, location, error): return false
				location.pop_back()
		TYPE_FLOAT:
			if is_nan(value) or is_inf(value): return _append_error("non_finite_number", location, error)
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			pass
		_:
			return _append_error("unsupported_type", location, error)
	return true

static func _equal_canonical(left: Variant, right: Variant) -> bool:
	var left_type := typeof(left)
	var right_type := typeof(right)
	if left_type != right_type:
		if left_type in [TYPE_INT, TYPE_FLOAT] and right_type in [TYPE_INT, TYPE_FLOAT]:
			return _number_text(left) == _number_text(right)
		return false
	match left_type:
		TYPE_DICTIONARY:
			if left.size() != right.size(): return false
			for key in left:
				if not right.has(key) or not _equal_canonical(left[key], right[key]): return false
		TYPE_ARRAY:
			if left.size() != right.size(): return false
			for index in left.size():
				if not _equal_canonical(left[index], right[index]): return false
		TYPE_FLOAT:
			return left == right or _number_text(left) == _number_text(right)
		_:
			return left == right
	return true

static func _number_text(value: Variant) -> String:
	if typeof(value) == TYPE_INT: return str(value)
	if value == 0.0: return "0"
	if value == round(value): return str(int(value))
	return String.num(float(value), 17)

static func _ok(text: String) -> Dictionary:
	return {"ok": true, "text": text}

static func _fail(code: String, path: String) -> Dictionary:
	return {"ok": false, "code": code, "path": path}
