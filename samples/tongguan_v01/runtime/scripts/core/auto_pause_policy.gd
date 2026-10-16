extends RefCounted

class_name AutoPausePolicy

const SUPPORTED_SEVERITIES := ["force", "major", "notice"]
const SUPPORTED_CATEGORIES := [
	"audience",
	"promise",
	"war",
	"diplomacy",
	"intelligence",
	"npc_action",
	"task_blocked"
]

func apply_request(state: Variant, request: Variant) -> Dictionary:
	var state_validation := _validate_state(state)
	if not state_validation.get("ok", false):
		return state_validation
	var request_validation := _validate_request(request)
	if not request_validation.get("ok", false):
		return request_validation

	var state_object: Object = state
	var typed_request: Dictionary = request
	var severity: String = typed_request.get("severity")
	var category: String = typed_request.get("category")
	var reason: String = typed_request.get("reason")
	var preferences: Dictionary = state_object.get("auto_pause_preferences")
	var should_pause := severity == "force"
	if severity == "major":
		if not preferences.has(category):
			return _fail("state auto_pause_preferences is missing category: " + category)
		if typeof(preferences.get(category)) != TYPE_BOOL:
			return _fail("state auto_pause preference must be a bool: " + category)
		should_pause = preferences.get(category)

	if should_pause:
		state_object.set("is_time_paused", true)
		state_object.set("pause_reason", reason)

	return {
		"ok": true,
		"severity": severity,
		"category": category,
		"applicable": should_pause,
		"pause_applied": should_pause
	}

func _validate_state(state: Variant) -> Dictionary:
	if typeof(state) != TYPE_OBJECT:
		return _fail("state must be a live Object")
	if not is_instance_valid(state):
		return _fail("state must be a live Object")
	var state_object: Object = state
	for property_name in ["is_time_paused", "pause_reason", "auto_pause_preferences"]:
		var property_info := _find_property(state_object, property_name)
		if property_info.is_empty():
			return _fail("state is missing required property: " + property_name)
		var usage := int(property_info.get("usage", 0))
		if (usage & PROPERTY_USAGE_READ_ONLY) != 0:
			return _fail("state property must be writable: " + property_name)
	if typeof(state_object.get("is_time_paused")) != TYPE_BOOL:
		return _fail("state is_time_paused must be a bool")
	if typeof(state_object.get("pause_reason")) != TYPE_STRING:
		return _fail("state pause_reason must be a String")
	if not (state_object.get("auto_pause_preferences") is Dictionary):
		return _fail("state auto_pause_preferences must be a Dictionary")
	return {"ok": true}

func _validate_request(request: Variant) -> Dictionary:
	if not (request is Dictionary):
		return _fail("auto-pause request must be a Dictionary")
	var typed_request: Dictionary = request
	for field_name in ["severity", "category", "reason"]:
		if not typed_request.has(field_name):
			return _fail("auto-pause request is missing field: " + field_name)
		if typeof(typed_request.get(field_name)) != TYPE_STRING:
			return _fail("auto-pause request field must be a String: " + field_name)
	var severity: String = typed_request.get("severity")
	if not SUPPORTED_SEVERITIES.has(severity):
		return _fail("unsupported auto-pause severity: " + severity)
	var category: String = typed_request.get("category")
	if not SUPPORTED_CATEGORIES.has(category):
		return _fail("unsupported auto-pause category: " + category)
	var reason: String = typed_request.get("reason")
	if reason.strip_edges().is_empty():
		return _fail("auto-pause reason is required")
	return {"ok": true}

func _find_property(state: Object, property_name: String) -> Dictionary:
	for property_info in state.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return property_info
	return {}

func _fail(error: String) -> Dictionary:
	return {"ok": false, "error": error}
