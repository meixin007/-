extends RefCounted

class_name TimeController

const StrategicTimeServiceScript = preload("res://scripts/core/strategic_time_service.gd")
const PoliticalSeasonProgressionGuardScript = preload("res://scripts/core/political_season_progression_guard.gd")
const GovernanceMemorialServiceScript = preload("res://scripts/core/governance_memorial_service.gd")
const LEGACY_MINUTES_PER_DAY := 20
const OVERLAY_LOCK_ORDER_KEY := "time_overlay_lock_order"
const PAUSED_AFTER_OVERLAY_REASON := "paused_after_overlay"
const KNOWN_OVERLAY_REASONS := {
	"settings": true,
	"character_overlay": true,
	"character_context_menu": true,
	"free_dialogue": true,
	"event_detail": true,
	"governance_council": true,
	"governance_consultation_dialog": true,
	"accountability_consultation_dialog": true,
	"character_interaction": true,
	"npc_affairs": true,
	"political_confirmation": true,
	"beta110_route_handoff": true,
	"office_appointment_confirmation": true,
	"faction_bargain_modal": true,
	"emperor_coping": true,
	"corridor_logistics": true,
	"battle_vignette": true,
	"api_request": true,
	"war_recruitment_dialog": true,
	"clan_nomination_dialog": true,
	"character_audience": true,
	"imperial_examination": true,
	"clan_petition": true,
	"clan_roster_overlay": true,
	"free_talk_api_request": true,
	"memorial_processing": true,
	"imperial_court_city_view": true,
	"preview_missing": true
}

var _strategic_time_service = StrategicTimeServiceScript.new()

func advance_one_day(state, settlement_steps: Array) -> Dictionary:
	return _strategic_time_service.advance_one_day(state, settlement_steps)

func settle_governance_daily(state, governance_data: Dictionary) -> Dictionary:
	if state == null or not (governance_data is Dictionary): return _fail("governance daily settlement requires state and data")
	var memorials = GovernanceMemorialServiceScript.new()
	var deadlines: Dictionary = memorials.settle_deadlines(state, governance_data)
	if not bool(deadlines.get("ok", false)): return deadlines
	var followups: Dictionary = memorials.activate_followups(state, governance_data)
	if not bool(followups.get("ok", false)): return followups
	return {"ok": true, "expired_memorial_ids": deadlines.get("expired_memorial_ids", []).duplicate(true), "activated_memorial_ids": followups.get("activated_memorial_ids", []).duplicate(true)}

func set_speed(state, speed: int) -> Dictionary:
	return _strategic_time_service.set_speed(state, speed)

func resume(state, speed: int = 1) -> Dictionary:
	if state == null:
		return _fail("missing state")
	var changed: Dictionary = set_speed(state, speed)
	if not bool(changed.get("ok", false)):
		return changed
	if has_overlay_locks(state):
		return _fail("cannot resume while an overlay lock is active")
	state.is_time_paused = false
	state.pause_reason = ""
	return {"ok": true, "speed": speed}

func pause(state, reason: String) -> Dictionary:
	return _strategic_time_service.pause(state, reason)

func format_date(state) -> String:
	return _strategic_time_service.format_date(state)

func acquire_overlay_lock(state, reason: String) -> Dictionary:
	if not _has_overlay_state_contract(state):
		return _fail("state must provide court_workbench_state and pause fields")
	if not KNOWN_OVERLAY_REASONS.has(reason):
		return _fail("unknown overlay pause reason: " + reason)
	var order := get_overlay_lock_order(state)
	if not order.has(reason):
		order.append(reason)
	state.court_workbench_state[OVERLAY_LOCK_ORDER_KEY] = order.duplicate()
	_sync_overlay_pause_reason(state, order)
	return {"ok": true, "reasons": order.duplicate()}

func release_overlay_lock(state, reason: String) -> Dictionary:
	if not _has_overlay_state_contract(state):
		return _fail("state must provide court_workbench_state and pause fields")
	if not KNOWN_OVERLAY_REASONS.has(reason):
		return _fail("unknown overlay pause reason: " + reason)
	var order := get_overlay_lock_order(state)
	order.erase(reason)
	state.court_workbench_state[OVERLAY_LOCK_ORDER_KEY] = order.duplicate()
	_sync_overlay_pause_reason(state, order)
	return {"ok": true, "reasons": order.duplicate()}

func rebuild_overlay_locks(state, reasons: Array) -> Dictionary:
	if not _has_overlay_state_contract(state):
		return _fail("state must provide court_workbench_state and pause fields")
	var order := normalize_overlay_lock_order(reasons)
	state.court_workbench_state[OVERLAY_LOCK_ORDER_KEY] = order.duplicate()
	_sync_overlay_pause_reason(state, order)
	return {"ok": true, "reasons": order.duplicate()}

func clear_overlay_locks(state) -> Dictionary:
	return rebuild_overlay_locks(state, [])

func get_overlay_lock_order(state) -> Array[String]:
	if not _has_overlay_state_contract(state):
		return []
	return normalize_overlay_lock_order(state.court_workbench_state.get(OVERLAY_LOCK_ORDER_KEY, []))

func has_overlay_locks(state) -> bool:
	return not get_overlay_lock_order(state).is_empty()

func has_overlay_lock(state) -> bool:
	return has_overlay_locks(state)

func get_current_overlay_reason(state) -> String:
	var order := get_overlay_lock_order(state)
	return order[-1] if not order.is_empty() else ""

static func normalize_overlay_lock_order(value: Variant) -> Array[String]:
	var normalized: Array[String] = []
	if not value is Array:
		return normalized
	for entry in value:
		if typeof(entry) != TYPE_STRING:
			continue
		var reason := str(entry)
		if KNOWN_OVERLAY_REASONS.has(reason) and not normalized.has(reason):
			normalized.append(reason)
	return normalized

func _has_overlay_state_contract(state) -> bool:
	return state != null \
		and state.get("court_workbench_state") is Dictionary \
		and typeof(state.get("is_time_paused")) == TYPE_BOOL \
		and typeof(state.get("pause_reason")) == TYPE_STRING

func _sync_overlay_pause_reason(state, order: Array[String]) -> void:
	if not order.is_empty():
		state.is_time_paused = true
		state.pause_reason = order[-1]
	elif bool(state.is_time_paused) and KNOWN_OVERLAY_REASONS.has(str(state.pause_reason)):
		state.pause_reason = PAUSED_AFTER_OVERLAY_REASON

func advance_minutes(state, queue, events: Array, rules, minutes: int) -> Dictionary:
	var validation_result := _validate_legacy_inputs(state, queue, minutes)
	if not bool(validation_result.get("ok", false)):
		return validation_result
	var progression_guard := PoliticalSeasonProgressionGuardScript.can_advance(state)
	if not bool(progression_guard.get("ok", false)):
		return progression_guard
	if bool(state.is_time_paused):
		return _fail("paused: %s" % str(state.pause_reason))
	var snapshot_result := _capture_legacy_snapshot(state)
	if not bool(snapshot_result.get("ok", false)):
		return snapshot_result
	var snapshot: Dictionary = snapshot_result.get("snapshot", {}).duplicate(true)

	var previous_time_minutes := int(state.current_time_minutes)
	var previous_day_bucket := maxi(floori(float(previous_time_minutes) / float(LEGACY_MINUTES_PER_DAY)), 0)
	state.current_time_minutes += minutes
	state.flags["legacy_time_controller_minutes_adapter"] = true
	var current_day_bucket := maxi(floori(float(state.current_time_minutes) / float(LEGACY_MINUTES_PER_DAY)), 0)
	var days_to_advance := maxi(current_day_bucket - previous_day_bucket, 0)
	for _day_index in range(days_to_advance):
		var advance_result: Variant = _strategic_time_service.advance_one_day(state, [
			Callable(queue, "activate_due_events").bind(events),
			Callable(queue, "expire_due_events").bind(rules)
		])
		if not (advance_result is Dictionary):
			return _rollback_legacy_and_fail(state, snapshot, "strategic day result contract requires a Dictionary with explicit boolean ok")
		if not advance_result.has("ok") or typeof(advance_result.get("ok")) != TYPE_BOOL:
			return _rollback_legacy_and_fail(state, snapshot, "strategic day result contract requires a Dictionary with explicit boolean ok")
		if not bool(advance_result.get("ok", false)):
			return _rollback_legacy_and_fail_with_contract(state, snapshot, advance_result)
	if days_to_advance == 0:
		var queue_result: Variant = queue.activate_due_events(state, events)
		if queue_result != null:
			if not (queue_result is Dictionary):
				return _rollback_legacy_and_fail(state, snapshot, "queue result contract requires null or a Dictionary with explicit boolean ok")
			if not queue_result.has("ok") or typeof(queue_result.get("ok")) != TYPE_BOOL:
				return _rollback_legacy_and_fail(state, snapshot, "queue result contract requires null or a Dictionary with explicit boolean ok")
			if not bool(queue_result.get("ok")):
				return _rollback_legacy_and_fail(state, snapshot, "queue update failed: %s" % str(queue_result.get("error", "unknown queue failure")))
	return {"ok": true}

func _validate_legacy_inputs(state, queue, minutes: int) -> Dictionary:
	if minutes < 0:
		return _fail("negative minutes are not allowed")
	if typeof(state) != TYPE_OBJECT or not is_instance_valid(state):
		return _fail("state must be a valid object")

	var state_properties: Dictionary = {}
	for property_entry in state.get_property_list():
		state_properties[str(property_entry.get("name", ""))] = true
	for required_property in [
		"current_time_minutes",
		"current_day",
		"current_date",
		"is_time_paused",
		"pause_reason",
		"flags"
	]:
		if not state_properties.has(required_property):
			return _fail("state is missing required property: %s" % required_property)
	if not (state.get("flags") is Dictionary):
		return _fail("state flags must be a Dictionary")
	if not state.has_method("to_dictionary") or not state.has_method("load_dictionary"):
		return _fail("state must support serialization")
	if typeof(queue) != TYPE_OBJECT or not is_instance_valid(queue) or not queue.has_method("activate_due_events") or not queue.has_method("expire_due_events"):
		return _fail("queue must provide activation and expiry methods")
	return {"ok": true}

func _capture_legacy_snapshot(state) -> Dictionary:
	var serialized_value: Variant = state.to_dictionary()
	if not (serialized_value is Dictionary):
		return _fail("state to_dictionary must return a Dictionary")
	var snapshot: Dictionary = serialized_value.duplicate(true)
	var property_usage := _state_property_usage(state)
	for required_snapshot_field in [
		"current_time_minutes",
		"current_day",
		"current_date",
		"flags"
	]:
		if not snapshot.has(required_snapshot_field):
			return _fail("state snapshot is missing required field: %s" % required_snapshot_field)
		if not property_usage.has(required_snapshot_field):
			return _fail("state snapshot field has no matching property: %s" % required_snapshot_field)
		if (int(property_usage.get(required_snapshot_field, 0)) & PROPERTY_USAGE_READ_ONLY) != 0:
			return _fail("state snapshot property is read-only: %s" % required_snapshot_field)
	for key in snapshot.keys():
		var property_name := str(key)
		if property_usage.has(property_name) and (int(property_usage.get(property_name, 0)) & PROPERTY_USAGE_READ_ONLY) != 0:
			return _fail("state snapshot property is read-only: %s" % property_name)
	return {"ok": true, "snapshot": snapshot}

func _rollback_legacy_and_fail(state, snapshot: Dictionary, failure_message: String) -> Dictionary:
	var rollback_result := _restore_legacy_snapshot(state, snapshot)
	if not bool(rollback_result.get("ok", false)):
		return _fail("%s; rollback failed: %s" % [
			failure_message,
			str(rollback_result.get("error", "unknown rollback failure"))
		])
	return _fail(failure_message)

func _rollback_legacy_and_fail_with_contract(state, snapshot: Dictionary, failure: Dictionary) -> Dictionary:
	var result := _rollback_legacy_and_fail(state, snapshot, str(failure.get("error", "strategic day advancement failed")))
	if failure.has("code"):
		result["code"] = failure.get("code")
	for key in ["reason_code", "blocking_review_id", "route_required", "next_step"]:
		if failure.has(key):
			result[key] = failure.get(key)
	return result

func _restore_legacy_snapshot(state, snapshot: Dictionary) -> Dictionary:
	state.load_dictionary(snapshot.duplicate(true))
	var property_usage := _state_property_usage(state)
	for key in snapshot.keys():
		var property_name := str(key)
		if property_usage.has(property_name) and (int(property_usage.get(property_name, 0)) & PROPERTY_USAGE_READ_ONLY) == 0:
			state.set(property_name, _duplicate_serialized_value(snapshot.get(key)))
	var restored_value: Variant = state.to_dictionary()
	if not (restored_value is Dictionary):
		return _fail("state to_dictionary must return a Dictionary after rollback")
	var restored: Dictionary = restored_value
	if restored.duplicate(true) != snapshot:
		return _fail("complete serialized state was not restored")
	return {"ok": true}

func _state_property_usage(state) -> Dictionary:
	var property_usage: Dictionary = {}
	for property_entry in state.get_property_list():
		property_usage[str(property_entry.get("name", ""))] = int(property_entry.get("usage", 0))
	return property_usage

func _duplicate_serialized_value(value: Variant) -> Variant:
	if value is Dictionary:
		var dictionary_value: Dictionary = value
		return dictionary_value.duplicate(true)
	if value is Array:
		var array_value: Array = value
		return array_value.duplicate(true)
	return value

func _fail(message: String) -> Dictionary:
	return {
		"ok": false,
		"error": message
	}
