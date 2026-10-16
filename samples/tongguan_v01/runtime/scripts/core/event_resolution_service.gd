extends RefCounted

class_name EventResolutionService

const EventQueueScript = preload("res://scripts/core/event_queue.gd")
const TaskQueueScript = preload("res://scripts/core/task_queue.gd")

var _queue = EventQueueScript.new()
var _task_queue = TaskQueueScript.new()

func preview_player_decision(state, decisions: Array, event_id: String, decision_id: String, rules) -> Dictionary:
	var validated := _validate_player_decision(state, decisions, event_id, decision_id, rules)
	if not validated.get("ok", false):
		return validated
	var event: Dictionary = validated.event
	var decision: Dictionary = validated.decision
	return {
		"ok": true,
		"event_id": event_id,
		"decision_id": decision_id,
		"costs": _visible_costs(decision.get("costs", [])),
		"effects": _visible_effects(decision.get("effects", [])),
		"deadline": int(event.get("trigger_day", 0)) + int(event.get("deadline_days", 0)),
		"affected_political_objects": event.get("affected_political_objects", []).duplicate(true),
		"visible_risks": event.get("visible_risks", []).duplicate(true),
		"expected_preview_token": _preview_token(state, event, decision)
	}

func resolve_player_decision(state, decisions: Array, event_id: String, decision_id: String, rules, expected_preview_token: String) -> Dictionary:
	var validated := _validate_player_decision(state, decisions, event_id, decision_id, rules)
	if not validated.get("ok", false):
		return validated
	var event: Dictionary = validated.event
	var decision: Dictionary = validated.decision
	if expected_preview_token != _preview_token(state, event, decision):
		return _fail("stale preview token")
	var snapshot: Dictionary = state.to_dictionary().duplicate(true)
	var immediate_decisions := _without_task_create_effects(decisions, decision_id)
	var decision_result: Dictionary = rules.apply_decision(state, immediate_decisions, decision_id)
	if not decision_result.get("ok", false):
		_restore_snapshot(state, snapshot)
		return decision_result
	var task_result := _create_event_tasks(state, event, decision)
	if not task_result.get("ok", false):
		_restore_snapshot(state, snapshot)
		return task_result
	var finalization := _finalize_event(state, event, "resolved", {"decision_id": decision_id, "resolution_kind": "player_decision", "task_id": str(task_result.get("task_id", ""))})
	if not finalization.get("ok", false):
		_restore_snapshot(state, snapshot)
		return finalization
	finalization["task_id"] = str(task_result.get("task_id", ""))
	finalization["tasks"] = [task_result.get("task", {}).duplicate(true)] if not task_result.get("task", {}).is_empty() else []
	return finalization

func _create_event_tasks(state, event: Dictionary, decision: Dictionary) -> Dictionary:
	var task_effects: Array = []
	for effect in decision.get("effects", []):
		if effect is Dictionary and str(effect.get("type", "")) == "task_create":
			task_effects.append(effect.duplicate(true))
	if task_effects.is_empty():
		return {"ok": true, "task_id": "", "task": {}}
	if task_effects.size() != 1:
		return _fail("a decision may create at most one event task")
	var created: Dictionary = _task_queue.call("_create_task_for_resolved_event", state, event, decision, task_effects[0])
	if not created.get("ok", false):
		return created
	return {"ok": true, "task_id": str(created.get("task", {}).get("id", "")), "task": created.get("task", {}).duplicate(true)}

func _without_task_create_effects(decisions: Array, decision_id: String) -> Array:
	var copied: Array = []
	for candidate in decisions:
		if not (candidate is Dictionary):
			copied.append(candidate)
			continue
		var decision: Dictionary = candidate.duplicate(true)
		if str(decision.get("id", "")) == decision_id:
			var immediate_effects: Array = []
			for effect in decision.get("effects", []):
				if effect is Dictionary and str(effect.get("type", "")) == "task_create":
					continue
				immediate_effects.append(effect.duplicate(true) if effect is Dictionary else effect)
			decision["effects"] = immediate_effects
		copied.append(decision)
	return copied

func finalize_completed_task(state, event_id: String, completed_task: Dictionary) -> Dictionary:
	if str(completed_task.get("source_event_id", "")) != event_id or str(completed_task.get("status", "")) != "completed":
		return _fail("completed task does not match source event")
	var found := _queue.find_active_event(state, event_id)
	if not found.get("ok", false):
		if state.resolved_events.has(event_id):
			return {"ok": true, "event_id": event_id, "already_resolved": true}
		return found
	return _finalize_event(state, found.event, "resolved", {"task_id": str(completed_task.get("id", "")), "resolution_kind": "completed_task"})

func _validate_player_decision(state, decisions: Array, event_id: String, decision_id: String, rules) -> Dictionary:
	if state == null or rules == null:
		return _fail("missing state or rules")
	var found := _queue.find_active_event(state, event_id)
	if not found.get("ok", false):
		return found
	var event: Dictionary = found.event
	if int(state.current_day) >= int(event.get("trigger_day", 0)) + int(event.get("deadline_days", 0)):
		return _fail("event expired")
	if not event.get("available_decisions", []).has(decision_id):
		return _fail("decision unavailable: " + decision_id)
	var decision_validation: Dictionary = rules.validate_decision(state, decisions, decision_id)
	if not decision_validation.get("ok", false):
		return decision_validation
	return {"ok": true, "event": event, "decision": decision_validation.decision}

func _finalize_event(state, event: Dictionary, status: String, details: Dictionary) -> Dictionary:
	var event_id := str(event.get("id", ""))
	if state.resolved_events.has(event_id):
		return _fail("event already resolved: " + event_id)
	var still_active: Array = []
	for active_event in state.active_events:
		if str(active_event.get("id", "")) != event_id:
			still_active.append(active_event)
	state.active_events = still_active
	state.resolved_events.append(event_id)
	var history := {"type": str(event.get("type", "")), "title": str(event.get("title", ""))}
	history.merge(details, true)
	state.record_event_history(event_id, status, history)
	return {"ok": true, "event_id": event_id}

func _preview_token(state, event: Dictionary, decision: Dictionary) -> String:
	var payload := {"state": _sanitized_authoritative_state(state.to_dictionary()), "event": event, "decision": decision}
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(_canonicalize(payload)).to_utf8_buffer())
	return context.finish().hex_encode().to_lower()

func _sanitized_authoritative_state(serialized: Dictionary) -> Dictionary:
	var copy := serialized.duplicate(true)
	for transient_key in ["pending_dialogue_intent", "pending_dialogue_response", "dialogue_history_summary", "active_conversation_target_id"]:
		copy.erase(transient_key)
	if copy.get("court_workbench_state") is Dictionary:
		var workbench: Dictionary = copy.court_workbench_state
		for key in ["settings_open", "free_dialogue_open", "time_overlay_lock_order", "right_context_kind", "right_context_payload"]:
			workbench.erase(key)
		copy.court_workbench_state = workbench
	return copy

func _restore_snapshot(state, snapshot: Dictionary) -> void:
	state.load_dictionary(snapshot.duplicate(true))
	for key in snapshot.keys():
		state.set(str(key), _duplicate_value(snapshot[key]))

func _duplicate_value(value: Variant) -> Variant:
	if value is Dictionary: return value.duplicate(true)
	if value is Array: return value.duplicate(true)
	return value

func _canonicalize(value: Variant) -> Variant:
	if value is Dictionary:
		var sorted: Dictionary = {}
		var keys: Array = value.keys()
		keys.sort()
		for key in keys: sorted[str(key)] = _canonicalize(value[key])
		return sorted
	if value is Array:
		var copied: Array = []
		for item in value: copied.append(_canonicalize(item))
		return copied
	return value

func _visible_effects(effects: Array) -> Array:
	var visible: Array = []
	for effect in effects:
		if effect is Dictionary and bool(effect.get("player_visible", true)):
			visible.append({"type": str(effect.get("type", "")), "target": str(effect.get("target", "")), "value": effect.get("value"), "field": str(effect.get("field", ""))})
	return visible

func _visible_costs(costs: Array) -> Array:
	var visible: Array = []
	for cost in costs:
		if cost is Dictionary and bool(cost.get("player_visible", true)):
			visible.append({"resource": str(cost.get("resource", "")), "value": cost.get("value")})
	return visible

func _find_decision(decisions: Array, decision_id: String) -> Dictionary:
	for decision in decisions:
		if decision is Dictionary and str(decision.get("id", "")) == decision_id: return decision.duplicate(true)
	return {}

func _fail(error: String) -> Dictionary:
	return {"ok": false, "error": error}
