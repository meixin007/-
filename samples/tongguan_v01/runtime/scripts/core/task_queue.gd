extends RefCounted

class_name TaskQueue

const DayValueValidatorScript = preload("res://scripts/core/day_value_validator.gd")
const EventResolutionServiceScript = preload("res://scripts/core/event_resolution_service.gd")

func register_dialogue_intent(state, decisions: Array, intent: Dictionary, response: Dictionary, options: Dictionary = {}) -> Dictionary:
	if not str(options.get("source_event_id", "")).is_empty() or not str(intent.get("event_id", "")).is_empty():
		return _fail("event-bound dialogue must resolve through EventResolutionService")
	return _record_dialogue_intent(state, decisions, intent, response, options)

func _record_dialogue_intent(state, decisions: Array, intent: Dictionary, response: Dictionary, options: Dictionary = {}) -> Dictionary:
	if state == null:
		return _fail("missing state")
	if not intent.get("ok", false):
		return _fail("invalid intent")
	var duration_result: Dictionary = DayValueValidatorScript.validate(options.get("duration_days", 1), "duration_days", 1)
	if not duration_result.get("ok", false):
		return duration_result
	var duration_days := int(duration_result.get("value", 1))
	var response_kind := str(response.get("response_kind", "accept"))
	var decision_id := str(intent.get("decision_id", ""))
	var intent_type := str(intent.get("intent_type", "unknown"))
	var executor_id := str(intent.get("executor_id", ""))
	var target_id := str(intent.get("target_id", intent.get("target", "")))
	var task_record := {
		"id": "dialogue_record__%s__%d__%d" % [intent_type, int(state.current_day), state.dialogue_action_records.size()],
		"intent_type": intent_type,
		"decision_id": decision_id,
		"executor_id": executor_id,
		"target_id": target_id,
		"source_type": str(intent.get("source_type", "private_talk")),
		"response_kind": response_kind,
		"status": "recorded",
		"summary": str(response.get("summary", "")),
		"day": int(state.current_day)
	}
	state.record_dialogue_action(task_record)
	return {"ok": true, "record": task_record.duplicate(true)}

func _create_task_for_resolved_event(state, event: Dictionary, decision: Dictionary, task_effect: Dictionary) -> Dictionary:
	if state == null or event.is_empty() or decision.is_empty():
		return _fail("event task requires state, event, and decision")
	if str(task_effect.get("type", "")) != "task_create":
		return _fail("event task effect must be task_create")
	var decision_id := str(decision.get("id", ""))
	var available_decisions: Array = event.get("available_decisions", [])
	if not available_decisions.has(decision_id):
		return _fail("decision not available for event: " + decision_id)
	var duration_result: Dictionary = DayValueValidatorScript.validate(task_effect.get("duration_days", 1), "duration_days", 1)
	if not duration_result.get("ok", false):
		return duration_result
	var duration_days := int(duration_result.get("value", 1))

	var event_id := str(event.get("id", ""))
	if event_id != "" and _has_active_source_event(state, event_id):
		return _fail("active task already exists for unresolved source event: " + event_id)
	var task_id := "%s__%s__%d" % [event_id, decision_id, int(state.current_day)]
	if _is_active(state, task_id):
		return _fail("task already active: " + task_id)

	var executor_id := str(task_effect.get("executor_id", event.get("source_character_id", "")))
	var task := {
		"id": task_id,
		"name": str(decision.get("label", decision_id)),
		"decision_id": decision_id,
		"source_event_id": event_id,
		"source_event_title": str(event.get("title", "")),
		"executor_id": executor_id,
		"source_type": str(task_effect.get("source_type", "oral_order")),
		"target": str(task_effect.get("target", event_id)),
		"status": "in_progress",
		"risk": str(task_effect.get("risk", "normal")),
		"created_day": int(state.current_day),
		"due_day": int(state.current_day) + duration_days,
		"resolution_applied": true,
		"visible_feedback": [
			"已形成口谕",
			"%s正在执行「%s」。" % [_get_character_name(state, executor_id), str(decision.get("label", decision_id))]
		]
	}
	state.active_tasks.append(task)
	return {"ok": true, "task": task.duplicate(true)}

func update_tasks(state, rules, decisions: Array, event_queue, scenario_data: Dictionary = {}) -> Dictionary:
	var transaction_snapshot: Dictionary = state.to_dictionary().duplicate(true)
	var still_active: Array = []
	var completed: Array = []
	var blocked: Array = []
	var followups: Array = []
	# Authorized actions may retire or create other tasks. Process only the
	# starting schedule, then preserve newly issued tasks and remove retirees.
	var scheduled: Array=state.active_tasks.duplicate()
	for task in scheduled:
		if task.get("task_kind") == "management":
			var result: Dictionary = preload("res://scripts/core/action_authorization_service.gd").settle_task(state, scenario_data, task)
			if not result.get("ok", false):
				_restore_snapshot(state, transaction_snapshot)
				return result
			if task.status == "completed":
				completed.append(task.duplicate(true))
				state.completed_tasks.append(task.duplicate(true))
			else:
				still_active.append(task)
				if task.status == "blocked":
					blocked.append(task.duplicate(true))
			continue
		if str(task.get("status", "")) == "blocked":
			still_active.append(task)
			continue
		if str(task.get("task_kind", "")) == "private_entrustment":
			var prev_stage := str(task.get("stage", ""))
			var entrustment_service = preload("res://scripts/core/private_entrustment_service.gd").new()
			var settle_res: Dictionary = entrustment_service.settle_task(state, task)
			if not settle_res.get("ok", false):
				_restore_snapshot(state, transaction_snapshot)
				return settle_res
			var cur_status := str(task.get("status", "in_progress"))
			var cur_stage := str(task.get("stage", ""))
			if prev_stage != cur_stage and cur_stage in ["awaiting_introduction", "awaiting_report"]:
				var fb_arr: Array = task.get("visible_feedback", []) if task.get("visible_feedback", []) is Array else []
				followups.append({
					"task_id": str(task.get("id", "")),
					"executor_id": str(task.get("executor_id", "")),
					"stage": cur_stage,
					"status": cur_status,
					"execution_status": str(task.get("execution_status", "")),
					"report_status": str(task.get("report_status", "")),
					"outcome_code": str(task.get("outcome_code", "")),
					"summary": str(fb_arr[0]) if not fb_arr.is_empty() else str(task.get("name", ""))
				})
			if cur_status == "completed":
				completed.append(task.duplicate(true))
				state.completed_tasks.append(task.duplicate(true))
			elif cur_status == "blocked":
				blocked.append(task.duplicate(true))
				still_active.append(task)
			else:
				still_active.append(task)
			continue
		if int(state.current_day) < int(task.get("due_day", 0)):
			still_active.append(task)
			continue
		var result: Dictionary = {"ok": true} if bool(task.get("resolution_applied", false)) else rules.apply_decision(state, decisions, str(task.get("decision_id", "")))
		if result.get("ok", false):
			task["status"] = "completed"
			task["completed_day"] = int(state.current_day)
			var event_id := str(task.get("source_event_id", ""))
			if event_id != "":
				var finalization := EventResolutionServiceScript.new().finalize_completed_task(state, event_id, task)
				if not finalization.get("ok", false):
					_restore_snapshot(state, transaction_snapshot)
					return finalization
			var executor_id := str(task.get("executor_id", ""))
			if executor_id != "":
				state.add_character_memory(
					executor_id,
					"%s完成「%s」，处置「%s」。" % [_get_character_name(state, executor_id), task.get("name", ""), task.get("source_event_title", "")]
				)
			var followup := _enqueue_followup_event(state, decisions, str(task.get("decision_id", "")), task, event_queue)
			if followup.is_empty() and bool(task.get("dialogue_originated", false)):
				followup = _enqueue_dialogue_followup_event(state, task, event_queue)
			if not followup.is_empty():
				followups.append(followup)
			state.completed_tasks.append(task.duplicate(true))
			completed.append(task.duplicate(true))
		else:
			task["status"] = "blocked"
			task["block_reason"] = str(result.get("error", "unknown"))
			task["visible_feedback"] = [
				"受阻，需要补发诏令",
				"%s执行「%s」受阻：%s。" % [_get_character_name(state, str(task.get("executor_id", ""))), task.get("name", ""), task.get("block_reason", "unknown")]
			]
			var blocked_executor_id := str(task.get("executor_id", ""))
			if blocked_executor_id != "":
				state.add_character_memory(
					blocked_executor_id,
					"%s执行「%s」受阻：%s。" % [_get_character_name(state, blocked_executor_id), task.get("name", ""), task.get("block_reason", "unknown")]
				)
			blocked.append(task.duplicate(true))
			still_active.append(task)
	for task in state.active_tasks:
		if not scheduled.has(task) and not still_active.has(task): still_active.append(task)
	state.active_tasks = still_active.filter(func(task):return task.get("status") not in ["completed","cancelled"] and not state.completed_tasks.any(func(done):return done.get("id")==task.get("id")))
	return {"ok": true, "completed": completed, "blocked": blocked, "followups": followups}

func retry_blocked_tasks(state, rules, decisions: Array, event_queue) -> Dictionary:
	var transaction_snapshot: Dictionary = state.to_dictionary().duplicate(true)
	var still_active: Array = []
	var completed: Array = []
	var blocked: Array = []
	var followups: Array = []
	for task in state.active_tasks:
		if str(task.get("status", "")) != "blocked":
			still_active.append(task)
			continue
		if task.get("task_kind") == "management":
			var retried: Dictionary = preload("res://scripts/core/action_authorization_service.gd").retry_task(state, task)
			still_active.append(task)
			if not retried.get("ok", false):
				blocked.append(task.duplicate(true))
			continue
		if task.get("task_kind") == "private_entrustment":
			task.status = "in_progress"
			task.erase("block_reason")
			var retried: Dictionary = preload("res://scripts/core/private_entrustment_service.gd").new().settle_task(state, task)
			if not retried.get("ok", false):
				_restore_snapshot(state, transaction_snapshot)
				return retried
			still_active.append(task)
			if task.status == "blocked": blocked.append(task.duplicate(true))
			continue
		task["status"] = "in_progress"
		task.erase("block_reason")
		task["due_day"] = int(state.current_day)
		var result: Dictionary = {"ok": true} if bool(task.get("resolution_applied", false)) else rules.apply_decision(state, decisions, str(task.get("decision_id", "")))
		if result.get("ok", false):
			task["status"] = "completed"
			task["completed_day"] = int(state.current_day)
			var event_id := str(task.get("source_event_id", ""))
			if event_id != "":
				var finalization := EventResolutionServiceScript.new().finalize_completed_task(state, event_id, task)
				if not finalization.get("ok", false):
					_restore_snapshot(state, transaction_snapshot)
					return finalization
			var executor_id := str(task.get("executor_id", ""))
			if executor_id != "":
				state.add_character_memory(
					executor_id,
					"%s在补救后完成「%s」，处置「%s」。" % [_get_character_name(state, executor_id), task.get("name", ""), task.get("source_event_title", "")]
				)
			var followup := _enqueue_followup_event(state, decisions, str(task.get("decision_id", "")), task, event_queue)
			if followup.is_empty() and bool(task.get("dialogue_originated", false)):
				followup = _enqueue_dialogue_followup_event(state, task, event_queue)
			if not followup.is_empty():
				followups.append(followup)
			state.completed_tasks.append(task.duplicate(true))
			completed.append(task.duplicate(true))
		else:
			task["status"] = "blocked"
			task["block_reason"] = str(result.get("error", "unknown"))
			task["visible_feedback"] = [
				"仍然受阻，需要补发诏令",
				"%s重新执行「%s」仍受阻：%s。" % [_get_character_name(state, str(task.get("executor_id", ""))), task.get("name", ""), task.get("block_reason", "unknown")]
			]
			blocked.append(task.duplicate(true))
			still_active.append(task)
	state.active_tasks = still_active
	return {"ok": true, "completed": completed, "blocked": blocked, "followups": followups}

func enqueue_ledger_report(state, entry: Dictionary, event_queue) -> Dictionary:
	if state == null:
		return {}
	if entry.is_empty() or event_queue == null:
		return {}
	var report := {
		"id": "ledger_report__%s__%d" % [str(entry.get("id", "")), int(state.current_day)],
		"type": "ledger_report",
		"title": "Conversation obligation report",
		"source_character_id": str(entry.get("target_id", "")),
		"trigger_day": int(state.current_day),
		"deadline_days": 2,
		"urgency": 45,
		"visible_summary": str(entry.get("summary", "")),
		"available_decisions": [],
		"ledger_entry_id": str(entry.get("id", "")),
		"ledger_status": str(entry.get("status", "pending"))
	}
	if event_queue.enqueue_event(state, report, true):
		return report
	return {}

func _is_active(state, task_id: String) -> bool:
	for task in state.active_tasks:
		if str(task.get("id", "")) == task_id:
			return true
	return false

func _has_active_source_event(state, event_id: String) -> bool:
	for task in state.active_tasks:
		if str(task.get("source_event_id", "")) == event_id:
			return true
	return false

func _next_dialogue_task_occurrence(state, task_prefix: String) -> int:
	var highest := 0
	for collection in [state.active_tasks, state.completed_tasks]:
		for task in collection:
			highest = maxi(highest, _dialogue_task_occurrence(str(task.get("id", "")), task_prefix))
	for record in state.dialogue_action_records:
		highest = maxi(highest, _dialogue_task_occurrence(str(record.get("task_id", "")), task_prefix))
	return highest + 1

func _dialogue_task_occurrence(task_id: String, task_prefix: String) -> int:
	if task_id == task_prefix:
		return 1
	var occurrence_prefix := task_prefix + "__"
	if not task_id.begins_with(occurrence_prefix):
		return 0
	var suffix := task_id.trim_prefix(occurrence_prefix)
	if not suffix.is_valid_int():
		return 0
	return maxi(suffix.to_int(), 0)

func _find_by_id(items: Array, item_id: String) -> Dictionary:
	for item in items:
		if str(item.get("id", "")) == item_id:
			return item
	return {}

func _enqueue_followup_event(state, decisions: Array, decision_id: String, task: Dictionary, event_queue) -> Dictionary:
	var decision := _find_by_id(decisions, decision_id)
	var template: Dictionary = decision.get("follow_up_event", {})
	if template.is_empty():
		return {}
	var followup := template.duplicate(true)
	followup["trigger_day"] = int(state.current_day)
	followup["created_from_task_id"] = str(task.get("id", ""))
	followup["source_event_id"] = str(task.get("source_event_id", ""))
	if not followup.has("available_decisions"):
		followup["available_decisions"] = []
	if event_queue.enqueue_event(state, followup, true):
		return followup
	return {}

func _enqueue_dialogue_followup_event(state, task: Dictionary, event_queue) -> Dictionary:
	var template: Dictionary = task.get("dialogue_follow_up_report", {})
	if template.is_empty():
		return {}
	var followup := template.duplicate(true)
	followup["trigger_day"] = int(state.current_day)
	followup["created_from_task_id"] = str(task.get("id", ""))
	followup["available_decisions"] = followup.get("available_decisions", [])
	if event_queue.enqueue_event(state, followup, true):
		return followup
	return {}

func _build_dialogue_followup_event(state, intent: Dictionary, response: Dictionary) -> Dictionary:
	var intent_type := str(intent.get("intent_type", "dialogue"))
	var executor_id := str(intent.get("executor_id", ""))
	return {
		"id": "dialogue_followup__%s__%d__%d" % [intent_type, int(state.current_day), state.completed_tasks.size() + state.active_tasks.size()],
		"type": "completion_report",
		"title": "Dialogue-originated report: " + intent_type,
		"source_character_id": executor_id,
		"deadline_days": 2,
		"urgency": 45,
		"visible_summary": "%s reports a %s result from a confirmed conversation order." % [_get_character_name(state, executor_id), str(response.get("response_kind", "accept"))],
		"available_decisions": []
	}

func _dialogue_response_creates_task(response_kind: String, decision_id: String, intent_type: String) -> bool:
	if intent_type == "open_key_scene":
		return false
	if decision_id == "":
		return false
	return ["accept", "accept_with_warning", "bargain", "secretly_resist"].has(response_kind)

func _get_character_name(state, character_id: String) -> String:
	if state.character_states.has(character_id):
		return str(state.character_states[character_id].get("name", character_id))
	return character_id

func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}

func _restore_snapshot(state, snapshot: Dictionary) -> void:
	state.load_dictionary(snapshot.duplicate(true))
	for key in snapshot.keys():
		var value: Variant = snapshot[key]
		state.set(str(key), value.duplicate(true) if value is Dictionary or value is Array else value)
