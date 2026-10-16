extends RefCounted

class_name CharacterStateService

const DIMENSIONS := ["trust", "fear", "resentment", "ambition_pressure", "security", "issue_alignment", "political_burden", "urgency"]
const TRANSITION_DELTAS := {
	"promise_fulfilled": {"trust": 15, "resentment": -8, "security": 5, "political_burden": -5},
	"public_humiliation": {"trust": -20, "fear": 10, "resentment": 25, "security": -15, "political_burden": 10, "urgency": 8},
	"office_security": {"trust": 5, "resentment": -5, "ambition_pressure": -10, "security": 20, "political_burden": -8}
}
const MAX_ID_LENGTH := 64
const MAX_HISTORY := 1000
const MAX_HISTORY_SCAN := 10000

func apply_transition(state, character_id: Variant, transition_id: Variant, context: Variant) -> Dictionary:
	var validation := _validate_request(state, character_id, transition_id, context)
	if validation != "":
		return _fail(validation)
	var before: Dictionary
	if state.character_political_states.has(character_id):
		before = state.character_political_states.get(character_id).duplicate(true)
	else:
		before = default_state()
	var after: Dictionary = before.duplicate(true)
	var applied_delta: Dictionary = {}
	for field_id in TRANSITION_DELTAS[transition_id].keys():
		var old_value := int(before.get(field_id))
		var new_value := clampi(old_value + int(TRANSITION_DELTAS[transition_id][field_id]), 0, 100)
		after[field_id] = new_value
		applied_delta[field_id] = new_value - old_value
	var history_record := {
		"character_id": str(character_id),
		"transition_id": str(transition_id),
		"cause_id": str(context.get("cause_id")),
		"day": int(state.current_day),
		"delta": applied_delta.duplicate(true),
		"before": before.duplicate(true),
		"after": after.duplicate(true)
	}
	var next_states: Dictionary = state.character_political_states.duplicate(false)
	next_states[character_id] = after.duplicate(true)
	var start_index := maxi(0, state.character_state_history.size() - (MAX_HISTORY - 1))
	var next_history: Array = state.character_state_history.slice(start_index, state.character_state_history.size())
	next_history.append(history_record.duplicate(true))
	state.character_political_states = next_states
	state.character_state_history = next_history
	return {"ok": true, "state": after.duplicate(true), "history": history_record.duplicate(true)}

func describe_visible_attitude(state, character_id: Variant) -> String:
	if state == null or not (state.get("character_political_states") is Dictionary):
		return "态度审慎，尚需进一步观察。"
	if _validate_id(character_id, "character_id") != "":
		return "态度审慎，尚需进一步观察。"
	var raw_state = state.character_political_states.get(character_id, {})
	if not (raw_state is Dictionary) or validate_runtime_state(raw_state) != "":
		return "态度审慎，尚需进一步观察。"
	var political: Dictionary = raw_state
	var attitude := "保持戒心"
	if political.trust >= 70 and political.resentment < 40:
		attitude = "较为信任"
	elif political.trust < 35 or political.resentment >= 70:
		attitude = "明显疏离"
	elif political.trust >= 55:
		attitude = "谨慎合作"
	var position := "处境尚稳"
	if political.security < 35:
		position = "地位不安"
	elif political.security >= 70:
		position = "地位稳固"
	var pressure := "从容观望"
	if political.urgency >= 70 or political.political_burden >= 70:
		pressure = "承压急切"
	elif political.urgency >= 55 or political.political_burden >= 55:
		pressure = "压力渐增"
	return "态度%s；%s；%s。" % [attitude, position, pressure]

static func default_state() -> Dictionary:
	var state: Dictionary = {}
	for field_id in DIMENSIONS:
		state[field_id] = 50
	return state

static func validate_runtime_state(value: Variant) -> String:
	if not (value is Dictionary):
		return "political state must be a dictionary"
	for key in value.keys():
		if typeof(key) != TYPE_STRING or not DIMENSIONS.has(key):
			return "political state contains an unsupported dimension"
	for field_id in DIMENSIONS:
		if not value.has(field_id):
			return "political state requires all dimensions"
		var dimension_value = value.get(field_id)
		if typeof(dimension_value) != TYPE_INT or int(dimension_value) < 0 or int(dimension_value) > 100:
			return "runtime political dimensions must be integers within 0..100"
	return ""

static func normalize_saved_states(value: Variant, valid_character_ids: Array) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var normalized: Dictionary = {}
	var character_ids: Array = []
	for raw_character_id in value.keys():
		if typeof(raw_character_id) == TYPE_STRING:
			character_ids.append(raw_character_id)
	character_ids.sort()
	for character_id in character_ids:
		if _validate_id(character_id, "character_id") != "" or not valid_character_ids.has(character_id):
			continue
		var raw_state = value.get(character_id)
		if not (raw_state is Dictionary):
			continue
		var political := default_state()
		for field_id in DIMENSIONS:
			var raw_dimension = raw_state.get(field_id, 50)
			if _is_integral_number(raw_dimension):
				political[field_id] = clampi(int(round(float(raw_dimension))), 0, 100)
		normalized[character_id] = political
	return normalized

static func normalize_saved_history(value: Variant, valid_character_ids: Array) -> Array:
	if not (value is Array):
		return []
	var reversed_valid: Array = []
	var scanned := 0
	for index in range(value.size() - 1, -1, -1):
		if scanned >= MAX_HISTORY_SCAN or reversed_valid.size() >= MAX_HISTORY:
			break
		scanned += 1
		var result := _normalize_history_entry(value[index], valid_character_ids)
		if result.get("ok", false):
			reversed_valid.append(result.entry)
	reversed_valid.reverse()
	return reversed_valid

static func _normalize_history_entry(value: Variant, valid_character_ids: Array) -> Dictionary:
	if not (value is Dictionary):
		return {"ok": false}
	var character_id = value.get("character_id")
	var transition_id = value.get("transition_id")
	var cause_id = value.get("cause_id")
	if _validate_id(character_id, "character_id") != "" or not valid_character_ids.has(character_id):
		return {"ok": false}
	if typeof(transition_id) != TYPE_STRING or not TRANSITION_DELTAS.has(transition_id):
		return {"ok": false}
	if _validate_id(cause_id, "cause_id") != "":
		return {"ok": false}
	if typeof(value.get("day")) != TYPE_INT or int(value.get("day")) < 0:
		return {"ok": false}
	var before_result := _normalize_complete_saved_state(value.get("before"))
	var after_result := _normalize_complete_saved_state(value.get("after"))
	if not before_result.get("ok", false) or not after_result.get("ok", false):
		return {"ok": false}
	var raw_delta = value.get("delta")
	var transition_delta: Dictionary = TRANSITION_DELTAS[transition_id]
	if not (raw_delta is Dictionary) or raw_delta.size() != transition_delta.size():
		return {"ok": false}
	var expected_after: Dictionary = before_result.state.duplicate(true)
	var delta: Dictionary = {}
	for field_id in transition_delta.keys():
		if not raw_delta.has(field_id) or not _is_integral_number(raw_delta[field_id]):
			return {"ok": false}
		var before_value := int(before_result.state[field_id])
		var expected_value := clampi(before_value + int(transition_delta[field_id]), 0, 100)
		var expected_delta := expected_value - before_value
		if int(round(float(raw_delta[field_id]))) != expected_delta:
			return {"ok": false}
		expected_after[field_id] = expected_value
		delta[field_id] = expected_delta
	if after_result.state != expected_after:
			return {"ok": false}
	return {"ok": true, "entry": {
		"character_id": str(character_id),
		"transition_id": str(transition_id),
		"cause_id": str(cause_id),
		"day": int(value.get("day")),
		"delta": delta,
		"before": before_result.state.duplicate(true),
		"after": expected_after
	}}

static func _normalize_complete_saved_state(value: Variant) -> Dictionary:
	if not (value is Dictionary) or value.size() != DIMENSIONS.size():
		return {"ok": false}
	for key in value.keys():
		if typeof(key) != TYPE_STRING or not DIMENSIONS.has(key):
			return {"ok": false}
	var normalized: Dictionary = {}
	for field_id in DIMENSIONS:
		if not value.has(field_id) or not _is_integral_number(value.get(field_id)):
			return {"ok": false}
		var dimension := int(round(float(value.get(field_id))))
		if dimension < 0 or dimension > 100:
			return {"ok": false}
		normalized[field_id] = dimension
	return {"ok": true, "state": normalized}

static func _validate_request(state, character_id: Variant, transition_id: Variant, context: Variant) -> String:
	if state == null:
		return "state is required"
	if not (state.get("character_states") is Dictionary) or not (state.get("character_political_states") is Dictionary) or not (state.get("character_state_history") is Array):
		return "state must expose character and political state containers"
	if typeof(state.get("current_day")) != TYPE_INT or int(state.get("current_day")) < 0:
		return "state.current_day must be a non-negative integer"
	var character_error := _validate_id(character_id, "character_id")
	if character_error != "":
		return character_error
	if not state.character_states.has(character_id) or not (state.character_states.get(character_id) is Dictionary):
		return "unknown character_id"
	if typeof(transition_id) != TYPE_STRING or str(transition_id).strip_edges() == "" or str(transition_id).length() > MAX_ID_LENGTH:
		return "transition_id must be a non-empty bounded string"
	if not TRANSITION_DELTAS.has(transition_id):
		return "unsupported transition"
	if not (context is Dictionary):
		return "context must be a dictionary"
	var cause_error := _validate_id(context.get("cause_id"), "cause_id")
	if cause_error != "":
		return cause_error
	if context.has("day"):
		if typeof(context.get("day")) != TYPE_INT:
			return "context day must be an integer"
		if int(context.get("day")) != int(state.current_day):
			return "context day must match state.current_day"
	if state.character_political_states.has(character_id):
		var runtime_error := validate_runtime_state(state.character_political_states.get(character_id))
		if runtime_error != "":
			return runtime_error
	return ""

static func _validate_id(value: Variant, label: String) -> String:
	if typeof(value) != TYPE_STRING:
		return label + " must be a string"
	var text := str(value)
	if text.strip_edges() == "" or text.length() > MAX_ID_LENGTH:
		return label + " must be non-empty and at most 64 characters"
	return ""

static func _is_integral_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT or not is_finite(float(value)):
		return false
	return is_equal_approx(float(value), round(float(value)))

func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
