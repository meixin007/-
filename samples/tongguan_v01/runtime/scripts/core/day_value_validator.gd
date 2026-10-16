extends RefCounted

class_name DayValueValidator

static func validate(value: Variant, field_name: String, minimum: int = 0, maximum: int = 1000000) -> Dictionary:
	if not (value is int or value is float):
		return _fail("%s must be a finite integer" % field_name)
	var numeric_value := float(value)
	if not is_finite(numeric_value) or floorf(numeric_value) != numeric_value:
		return _fail("%s must be a finite integer" % field_name)
	if numeric_value < minimum or numeric_value > maximum:
		return _fail("%s must be in range %d-%d" % [field_name, minimum, maximum])
	return {"ok": true, "value": int(numeric_value)}

static func validate_due_order(created_day: int, due_day: int) -> Dictionary:
	if due_day < created_day:
		return _fail("due_day must be greater than or equal to created_day")
	return {"ok": true}

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
