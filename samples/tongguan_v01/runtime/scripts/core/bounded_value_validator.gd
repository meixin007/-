extends RefCounted

class_name BoundedValueValidator

const MAX_CONTAINER_DEPTH := 8
const MAX_CONTAINER_ITEMS := 2048
const MAX_CONTAINER_SIZE := 128
const MAX_STRING_LENGTH := 4096
const MAX_KEY_LENGTH := 128
const REQUIRED_OCCURRENCE_LINKS := ["related_memory_id", "related_ledger_id", "related_report_id", "related_chronicle_id"]

static func validate_and_copy_dictionary(value: Variant, label: String = "payload") -> Dictionary:
	if not value is Dictionary:
		return _fail(label + " must be a Dictionary")
	var budget := {"count": 0}
	var error := _validate_value(value, 0, budget, [])
	if not error.is_empty():
		return _fail(label + " " + error)
	return {"ok": true, "value": value.duplicate(true)}

static func validate_and_copy_occurrence_source_context(value: Variant, label: String = "source_context") -> Dictionary:
	var validation := validate_and_copy_dictionary(value, label)
	if not validation.get("ok", false):
		return validation
	var context: Dictionary = validation.get("value", {})
	for link_key in REQUIRED_OCCURRENCE_LINKS:
		if typeof(context.get(link_key, null)) != TYPE_STRING or str(context.get(link_key, "")).strip_edges().is_empty():
			return _fail(label + " is missing occurrence link: " + link_key)
	return {"ok": true, "value": context.duplicate(true)}

static func _validate_value(value: Variant, depth: int, budget: Dictionary, ancestors: Array) -> String:
	if depth > MAX_CONTAINER_DEPTH:
		return "exceeds maximum depth"
	budget["count"] = int(budget.get("count", 0)) + 1
	if int(budget.count) > MAX_CONTAINER_ITEMS:
		return "exceeds maximum item count"
	if value is Dictionary or value is Array:
		for ancestor in ancestors:
			if is_same(value, ancestor):
				return "contains a cyclic container"
		if value.size() > MAX_CONTAINER_SIZE:
			return "contains an oversized container"
		ancestors.append(value)
		if value is Dictionary:
			for key in value.keys():
				if typeof(key) != TYPE_STRING or str(key).strip_edges().is_empty() or str(key).length() > MAX_KEY_LENGTH:
					ancestors.pop_back()
					return "contains an invalid Dictionary key"
				var child_error := _validate_value(value[key], depth + 1, budget, ancestors)
				if not child_error.is_empty():
					ancestors.pop_back()
					return child_error
		else:
			for child in value:
				var child_error := _validate_value(child, depth + 1, budget, ancestors)
				if not child_error.is_empty():
					ancestors.pop_back()
					return child_error
		ancestors.pop_back()
		return ""
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_VECTOR2I:
			return ""
		TYPE_FLOAT:
			return "" if is_finite(float(value)) else "contains a non-finite Float"
		TYPE_STRING:
			return "" if str(value).length() <= MAX_STRING_LENGTH else "contains an oversized String"
		TYPE_VECTOR2:
			return "" if is_finite(value.x) and is_finite(value.y) else "contains a non-finite Vector2"
		_:
			return "contains an unsupported value type"

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message if not message.strip_edges().is_empty() else "validation failed"}
