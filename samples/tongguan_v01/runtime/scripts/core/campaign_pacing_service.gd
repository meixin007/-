extends RefCounted

class_name CampaignPacingService

const CAMPAIGN_DAYS := 90
const MAX_ACTIVE_IMPORTANT_EVENTS := 4
const CRISIS_DAYS := [0, 30, 60, 88, 90]

func phase_for_day(day: int) -> int:
	if day >= 1 and day <= 30:
		return 1
	if day >= 31 and day <= 60:
		return 2
	if day >= 61 and day <= CAMPAIGN_DAYS:
		return 3
	return 0

func max_new_important_events(day: int) -> int:
	return 2 if CRISIS_DAYS.has(day) and day != 0 else 3 if day == 0 else 1

func max_active_important_events() -> int:
	return MAX_ACTIVE_IMPORTANT_EVENTS

func schedule(day: int, candidates: Array, active_events: Array) -> Dictionary:
	if day < 0 or day > CAMPAIGN_DAYS:
		return _fail("campaign day must be between 0 and %d" % CAMPAIGN_DAYS)
	var active_count := active_events.size()
	var capacity := maxi(MAX_ACTIVE_IMPORTANT_EVENTS - active_count, 0)
	var budget := mini(max_new_important_events(day), capacity)
	var due: Array = []
	for raw_candidate in candidates:
		if not (raw_candidate is Dictionary):
			return _fail("event candidate must be a Dictionary")
		var candidate: Dictionary = (raw_candidate as Dictionary).duplicate(true)
		if str(candidate.get("id", "")).is_empty():
			return _fail("event candidate id is required")
		if int(candidate.get("trigger_day", day)) <= day:
			due.append(candidate)
	_due_sort(due)
	var selected_ids: Array[String] = []
	var delayed_ids: Array[String] = []
	var reasons_by_id: Dictionary = {}
	for index in range(due.size()):
		var candidate: Dictionary = due[index]
		var event_id := str(candidate.get("id", ""))
		if index < budget:
			selected_ids.append(event_id)
			reasons_by_id[event_id] = "selected"
		else:
			delayed_ids.append(event_id)
			reasons_by_id[event_id] = "active_cap" if capacity == 0 else "daily_budget"
	return {
		"ok": true,
		"selected_ids": selected_ids,
		"delayed_ids": delayed_ids,
		"reasons_by_id": reasons_by_id,
		"daily_budget": max_new_important_events(day),
		"active_capacity": capacity
	}

func _due_sort(events: Array) -> void:
	for left in range(events.size()):
		for right in range(left + 1, events.size()):
			if _sort_key(events[right]) < _sort_key(events[left]):
				var swap = events[left]
				events[left] = events[right]
				events[right] = swap

func _sort_key(event: Dictionary) -> Array:
	return [
		0 if bool(event.get("forced_phase_checkpoint", false)) else 1,
		int(event.get("prerequisites_earliest_day", event.get("trigger_day", 0))),
		0 if bool(event.get("crisis_escalation", false)) else 1,
		0 if bool(event.get("character_matter", false)) else 1,
		int(event.get("manifest_order", 2147483647)),
		str(event.get("id", ""))
	]

func _fail(message: String) -> Dictionary:
	return {"ok": false, "code": "campaign_pacing_error", "error": message, "message": message}
