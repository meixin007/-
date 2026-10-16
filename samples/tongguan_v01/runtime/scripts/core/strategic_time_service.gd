extends RefCounted

class_name StrategicTimeService

const MapStatusProjectionScript = preload("res://scripts/core/map_status_projection.gd")
const PoliticalSeasonProgressionGuardScript = preload("res://scripts/core/political_season_progression_guard.gd")

const DAYS_PER_MONTH := 30
const MONTHS_PER_YEAR := 12
const DEFAULT_DATE := {
	"era": "至德",
	"year": 1,
	"month": 7,
	"day": 12
}

func advance_one_day(state, settlement_steps: Array) -> Dictionary:
	var state_validation := _validate_advance_state(state)
	if not bool(state_validation.get("ok", false)):
		return state_validation
	var progression_guard := PoliticalSeasonProgressionGuardScript.can_advance(state)
	if not bool(progression_guard.get("ok", false)):
		return progression_guard
	var validated_steps := _validate_settlement_steps(settlement_steps)
	if not bool(validated_steps.get("ok", false)):
		return validated_steps
	if bool(state.is_time_paused):
		return _fail("paused: %s" % str(state.pause_reason))

	var serialized_state: Variant = state.to_dictionary()
	if not (serialized_state is Dictionary):
		return _fail("state to_dictionary must return a Dictionary")
	var snapshot: Dictionary = serialized_state.duplicate(true)
	var snapshot_validation := _validate_snapshot_restore_contract(state, snapshot)
	if not bool(snapshot_validation.get("ok", false)):
		return snapshot_validation
	var map_status_baseline: Dictionary = MapStatusProjectionScript.new().snapshot(state)
	state.current_day = maxi(int(state.current_day), 0) + 1
	state.current_date = next_date(state.current_date)

	for step_entry in validated_steps.get("steps", []):
		var step: Callable = step_entry
		var result = step.call(state)
		if not (result is Dictionary):
			return _rollback_and_fail(state, snapshot, "settlement step must return a Dictionary with explicit boolean ok")
		if not result.has("ok") or typeof(result.get("ok")) != TYPE_BOOL:
			return _rollback_and_fail(state, snapshot, "settlement step must return a Dictionary with explicit boolean ok")
		if not result.get("ok"):
			var error_message := str(result.get("error", "unknown step failure"))
			return _rollback_and_fail(state, snapshot, "settlement step failed: %s" % error_message)

	_store_map_status_baseline(state, map_status_baseline)
	return {"ok": true}

func set_speed(state, speed: int) -> Dictionary:
	if speed < 1 or speed > 3:
		return _fail("speed must be between 1 and 3")
	var progression_guard := PoliticalSeasonProgressionGuardScript.can_advance(state)
	if not bool(progression_guard.get("ok", false)):
		return progression_guard
	state.time_speed = speed
	return {"ok": true}

func pause(state, reason: String) -> Dictionary:
	state.is_time_paused = true
	state.pause_reason = reason
	return {"ok": true}

func next_date(value: Variant) -> Dictionary:
	return _next_date(_normalize_date(value))

func format_date(state) -> String:
	var current_date := _normalize_date(state.current_date)
	return "%s%s载%s月%s日" % [
		str(current_date.get("era", DEFAULT_DATE["era"])),
		_format_year(int(current_date.get("year", 1))),
		_to_chinese_number(int(current_date.get("month", 1))),
		_to_chinese_number(int(current_date.get("day", 1)))
	]

func _validate_settlement_steps(settlement_steps: Array) -> Dictionary:
	var validated_steps: Array = []
	for step in settlement_steps:
		if not (step is Callable):
			return _fail("settlement step must be callable")
		var callable_step: Callable = step
		if not callable_step.is_valid():
			return _fail("settlement step must be valid")
		validated_steps.append(callable_step)
	return {
		"ok": true,
		"steps": validated_steps
	}

func _validate_advance_state(state) -> Dictionary:
	if typeof(state) != TYPE_OBJECT or not is_instance_valid(state):
		return _fail("state must be a valid object")
	var property_usage := _state_property_usage(state)
	for required_property in [
		"current_day",
		"current_date",
		"is_time_paused",
		"pause_reason"
	]:
		if not property_usage.has(required_property):
			return _fail("state is missing required property: %s" % required_property)
	if not state.has_method("to_dictionary") or not state.has_method("load_dictionary"):
		return _fail("state must support serialization with to_dictionary/load_dictionary")
	return {"ok": true}

func _validate_snapshot_restore_contract(state, snapshot: Dictionary) -> Dictionary:
	var property_usage := _state_property_usage(state)
	var serialized_value: Variant = state.to_dictionary()
	if not (serialized_value is Dictionary):
		return _fail("state to_dictionary must return a Dictionary")
	var serialized_state: Dictionary = serialized_value
	for required_snapshot_field in ["current_day", "current_date"]:
		if not snapshot.has(required_snapshot_field):
			return _fail("state snapshot is missing required field: %s" % required_snapshot_field)
		if not property_usage.has(required_snapshot_field):
			return _fail("state snapshot field has no matching property: %s" % required_snapshot_field)
		if (int(property_usage.get(required_snapshot_field, 0)) & PROPERTY_USAGE_READ_ONLY) != 0:
			return _fail("state snapshot property is read-only: %s" % required_snapshot_field)
	for key in snapshot.keys():
		var property_name := str(key)
		if not serialized_state.has(key):
			return _fail("state snapshot key is not serialized by state: %s" % property_name)
		if property_usage.has(property_name) and (int(property_usage.get(property_name, 0)) & PROPERTY_USAGE_READ_ONLY) != 0:
			return _fail("state snapshot property is read-only: %s" % property_name)
		if not property_usage.has(property_name) and serialized_state.get(key) != snapshot.get(key):
			return _fail("state snapshot metadata is not stable: %s" % property_name)
	return {"ok": true}

func _state_property_usage(state) -> Dictionary:
	var property_usage: Dictionary = {}
	for property_entry in state.get_property_list():
		property_usage[str(property_entry.get("name", ""))] = int(property_entry.get("usage", 0))
	return property_usage

func _rollback_and_fail(state, snapshot: Dictionary, failure_message: String) -> Dictionary:
	var rollback_result := _restore_snapshot(state, snapshot)
	if not bool(rollback_result.get("ok", false)):
		return _fail("%s; rollback failed: %s" % [
			failure_message,
			str(rollback_result.get("error", "unknown rollback failure"))
		])
	return _fail(failure_message)

func _store_map_status_baseline(state, baseline: Dictionary) -> void:
	var property_usage := _state_property_usage(state)
	if not property_usage.has("flags"):
		return
	var flags_value: Variant = state.get("flags")
	if not (flags_value is Dictionary):
		return
	var flags: Dictionary = flags_value
	flags[MapStatusProjectionScript.PREVIOUS_KEY] = baseline.duplicate(true)
	state.set("flags", flags)

func _restore_snapshot(state, snapshot: Dictionary) -> Dictionary:
	state.load_dictionary(snapshot.duplicate(true))
	var property_usage := _state_property_usage(state)
	for key in snapshot.keys():
		var property_name := str(key)
		if property_usage.has(property_name) and (int(property_usage.get(property_name, 0)) & PROPERTY_USAGE_READ_ONLY) == 0:
			state.set(property_name, _duplicate_serialized_value(snapshot.get(key)))
	var restored_value: Variant = state.to_dictionary()
	if not (restored_value is Dictionary):
		return _fail("state to_dictionary must return a Dictionary after rollback")
	var restored: Dictionary = restored_value.duplicate(true)
	if restored != snapshot:
		return _fail("complete serialized state was not restored")
	return {"ok": true}

func _duplicate_serialized_value(value: Variant) -> Variant:
	if value is Dictionary:
		var dictionary_value: Dictionary = value
		return dictionary_value.duplicate(true)
	if value is Array:
		var array_value: Array = value
		return array_value.duplicate(true)
	return value

func _normalize_date(value: Variant) -> Dictionary:
	var normalized := DEFAULT_DATE.duplicate(true)
	if value is Dictionary:
		var source: Dictionary = value
		normalized["era"] = str(source.get("era", normalized["era"]))
		normalized["year"] = maxi(int(source.get("year", normalized["year"])), 1)
		normalized["month"] = clampi(int(source.get("month", normalized["month"])), 1, MONTHS_PER_YEAR)
		normalized["day"] = clampi(int(source.get("day", normalized["day"])), 1, DAYS_PER_MONTH)
	return normalized

func _next_date(current_date: Dictionary) -> Dictionary:
	var next_date := current_date.duplicate(true)
	var day := int(next_date.get("day", 1)) + 1
	var month := int(next_date.get("month", 1))
	var year := int(next_date.get("year", 1))

	if day > DAYS_PER_MONTH:
		day = 1
		month += 1
	if month > MONTHS_PER_YEAR:
		month = 1
		year += 1

	next_date["year"] = year
	next_date["month"] = month
	next_date["day"] = day
	return next_date

func _format_year(year: int) -> String:
	if year <= 1:
		return "元"
	return _to_chinese_number(year)

func _to_chinese_number(value: int) -> String:
	var number := maxi(value, 0)
	if number == 0:
		return "零"
	if number < 10:
		return _digit_to_chinese(number)
	if number < 20:
		return "十" + ("" if number == 10 else _digit_to_chinese(number % 10))
	if number < 100:
		var tens := int(number / 10)
		var ones := number % 10
		return "%s十%s" % [
			_digit_to_chinese(tens),
			"" if ones == 0 else _digit_to_chinese(ones)
		]
	return str(number)

func _digit_to_chinese(value: int) -> String:
	match value:
		0:
			return "零"
		1:
			return "一"
		2:
			return "二"
		3:
			return "三"
		4:
			return "四"
		5:
			return "五"
		6:
			return "六"
		7:
			return "七"
		8:
			return "八"
		9:
			return "九"
		_:
			return str(value)

func _fail(message: String) -> Dictionary:
	return {
		"ok": false,
		"error": message
	}
