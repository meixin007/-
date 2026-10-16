extends RefCounted

class_name EventQueue

const CampaignPacingServiceScript = preload("res://scripts/core/campaign_pacing_service.gd")

func update_events(state, events: Array, rules) -> Dictionary:
	return activate_due_events(state, events)

func activate_due_events(state, events: Array) -> Dictionary:
	if state == null:
		return {"ok": false, "error": "missing state"}
	retire_prototype_events(state)
	var eligible_events: Array = events
	var delayed_ids: Array = []
	var reasons_by_id: Dictionary = {}
	if _uses_beta_1_05_pacing(state):
		var pacing_result: Dictionary = CampaignPacingServiceScript.new().schedule(int(state.current_day), events, state.active_events)
		if not bool(pacing_result.get("ok", false)):
			return pacing_result
		var selected_by_id: Dictionary = {}
		for raw_event in events:
			if raw_event is Dictionary:
				selected_by_id[str((raw_event as Dictionary).get("id", ""))] = (raw_event as Dictionary).duplicate(true)
		eligible_events = []
		for event_id in pacing_result.get("selected_ids", []):
			if selected_by_id.has(str(event_id)):
				eligible_events.append(selected_by_id[str(event_id)])
		delayed_ids = pacing_result.get("delayed_ids", []).duplicate()
		reasons_by_id = pacing_result.get("reasons_by_id", {}).duplicate(true)
	var activated: Array = []
	for event in eligible_events:
		if _is_retired_prototype_event(state, event):
			continue
		var event_id := str(event.get("id", ""))
		if int(event.get("trigger_day", 0)) <= state.current_day:
			if not _is_active(state, event_id) and not state.resolved_events.has(event_id):
				state.active_events.append(event.duplicate(true))
				activated.append(event_id)
				state.record_event_history(event_id, "triggered", {
					"type": str(event.get("type", "")),
					"title": str(event.get("title", "")),
					"source_character_id": str(event.get("source_character_id", ""))
				})
	return {"ok": true, "activated": activated, "delayed_ids": delayed_ids, "reasons_by_id": reasons_by_id}

func _uses_beta_1_05_pacing(state) -> bool:
	return state.get("flags") is Dictionary and str(state.flags.get("campaign_id", "")) == "anshi_beta_1_05"

func expire_due_events(state, rules) -> Dictionary:
	if state == null:
		return {"ok": false, "error": "missing state"}
	if rules == null:
		return {"ok": false, "error": "missing rules"}
	var snapshot_result := _capture_snapshot(state)
	if not snapshot_result.get("ok", false):
		return snapshot_result
	var snapshot: Dictionary = snapshot_result.get("snapshot", {}).duplicate(true)
	var expired: Array = []
	var still_active: Array = []
	for active_event in state.active_events:
		if _is_retired_prototype_event(state, active_event):
			continue
		var expire_at := int(active_event.get("trigger_day", 0)) + int(active_event.get("deadline_days", 0))
		if state.current_day >= expire_at:
			var effect_result: Variant = rules.apply_effects(state, active_event.get("on_expire", []))
			if not (effect_result is Dictionary) or not effect_result.get("ok", false):
				state.load_dictionary(snapshot.duplicate(true))
				return {"ok": false, "error": str(effect_result.get("error", "event expiry effects failed")) if effect_result is Dictionary else "event expiry effects must return a Dictionary"}
			var expired_event_id := str(active_event.get("id", ""))
			state.resolved_events.append(expired_event_id)
			expired.append(expired_event_id)
			state.record_event_history(expired_event_id, "expired", {
				"type": str(active_event.get("type", "")),
				"title": str(active_event.get("title", ""))
			})
		else:
			still_active.append(active_event)
	state.active_events = still_active
	return {"ok": true, "expired": expired}

func _is_retired_prototype_event(state, event: Dictionary) -> bool:
	if str(state.flags.get("campaign_id", "")) not in ["anshi_beta_1_13", "anshi_beta_1_14"]:
		return false
	var id := str(event.get("id", ""))
	for prefix in ["beta06_court_power_event_", "beta07_war_intel_event_", "beta06_office_decree_", "beta07_intelligence_action_", "beta06_court_power_scene_", "beta07_war_table_scene_"]:
		if id.begins_with(prefix):
			return true
	return false

func retire_prototype_events(state) -> void:
	if state == null:
		return
	var kept: Array = []
	for event in state.active_events:
		if not _is_retired_prototype_event(state, event):
			kept.append(event)
	# Retire only the explicitly removed prototype families. Do not apply expiry
	# penalties, mark them resolved, or alter genuine events or historical effects.
	state.active_events = kept

func _capture_snapshot(state) -> Dictionary:
	if not state.has_method("to_dictionary") or not state.has_method("load_dictionary"):
		return {"ok": false, "error": "state must support serialization"}
	var serialized: Variant = state.to_dictionary()
	if not (serialized is Dictionary):
		return {"ok": false, "error": "state serialization must return a Dictionary"}
	return {"ok": true, "snapshot": serialized.duplicate(true)}

func find_active_event(state, event_id: String) -> Dictionary:
	if state == null:
		return {"ok": false, "error": "missing state"}
	for active_event in state.active_events:
		if str(active_event.get("id", "")) == event_id:
			return {"ok": true, "event": active_event.duplicate(true)}
	return {"ok": false, "error": "active event not found: " + event_id}

func enqueue_event(state, event: Dictionary, put_front: bool = false) -> bool:
	var preflight := can_enqueue_event(state, event)
	if not preflight.get("ok", false):
		return false
	var event_id := str(event.get("id", ""))
	if put_front:
		state.active_events.insert(0, event.duplicate(true))
	else:
		state.active_events.append(event.duplicate(true))
	state.record_event_history(event_id, "enqueued", {
		"type": str(event.get("type", "")),
		"title": str(event.get("title", "")),
		"created_from_task_id": str(event.get("created_from_task_id", ""))
	})
	return true

func can_enqueue_event(state, event: Dictionary) -> Dictionary:
	if state == null:
		return {"ok": false, "error": "missing state"}
	var event_id := str(event.get("id", ""))
	if event_id == "":
		return {"ok": false, "error": "event id is required"}
	if state.resolved_events.has(event_id):
		return {"ok": false, "error": "event id is already resolved: %s" % event_id}
	if _is_active(state, event_id):
		return {"ok": false, "error": "event id is already active: %s" % event_id}
	return {"ok": true}

func _is_active(state, event_id: String) -> bool:
	for active_event in state.active_events:
		if str(active_event.get("id", "")) == event_id:
			return true
	return false
