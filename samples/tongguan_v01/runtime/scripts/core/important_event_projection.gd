extends RefCounted

class_name ImportantEventProjection

const TOP_SEVERITIES := {"important": true, "major": true, "critical": true}
const TOP_ITEM_LIMIT := 3
const FEED_ITEM_LIMIT := 18
const SEVERITY_RANK := {"ordinary": 0, "important": 1, "major": 2, "critical": 3}
const TOP_FIELDS := ["title", "type", "visible_summary", "source_kind", "source_character_id", "related_character_ids", "interaction_targets", "trigger_day", "knowledge_sources", "confidence", "visible_conflicting_claims", "visible_risks", "available_decisions", "action_unavailable_reasons", "related_task_ids", "related_map_ids", "related_chain_ids", "blocked_reason"]
const CHARACTER_ALIAS_IDS := {
	"guo_ziyi": ["郭子仪", "Guo Ziyi", "guo_ziyi", "閮瓙浠"],
	"li_fuguo": ["李辅国", "Li Fuguo", "li_fuguo", "鏉庤緟鍥"],
	"li_bi": ["李泌", "Li Bi", "li_bi"],
	"li_heng": ["李亨", "肃宗", "Li Heng", "li_heng"],
	"du_hongjian": ["杜鸿渐", "Du Hongjian", "du_hongjian"],
	"grain_official_lingwu": ["粮官", "灵武粮官", "grain_official_lingwu"]
}

func project(active_events: Array, current_day: int) -> Dictionary:
	var candidates := _visible_candidates(active_events, current_day, "known")
	var top_candidates: Array = []
	for candidate in candidates:
		var event: Dictionary = candidate["event"]
		if not TOP_SEVERITIES.has(str(event.get("severity", ""))) or not bool(event.get("requires_player_action", false)):
			continue
		top_candidates.append(candidate.duplicate(true))
	top_candidates.sort_custom(_sort_top_pressure)
	var items: Array = []
	for index in range(mini(TOP_ITEM_LIMIT, top_candidates.size())):
		var candidate: Dictionary = top_candidates[index]
		items.append(_top_item(candidate["event"], candidate))
	return {"ok": true, "items": items}

func project_future(active_events: Array, current_day: int) -> Dictionary:
	var candidates := _visible_candidates(active_events, current_day, "estimated")
	var items: Array = []
	for candidate in candidates:
		var event: Dictionary = candidate["event"]
		items.append({
			"id": str(event["id"]),
			"title": str(event.get("title", "")),
			"visibility": "estimated",
			"due_day_min": int(candidate["expire_day"]),
			"due_day_max": int(candidate["expire_day"]),
			"confidence": float(event.get("confidence", 0.0)),
			"source_ids": _future_source_ids(event)
		})
	return {"ok": true, "items": items}

func project_feed(active_events: Array, current_day: int) -> Dictionary:
	var candidates := _visible_candidates(active_events, current_day, "known")
	var top_ids := {}
	for item in project(active_events, current_day).get("items", []):
		if item is Dictionary:
			top_ids[str(item.get("event_id", ""))] = true
	var items: Array = []
	for candidate in candidates:
		var event: Dictionary = candidate["event"]
		var event_id := str(event.get("id", ""))
		if top_ids.has(event_id):
			continue
		items.append(_feed_item(event, candidate))
		if items.size() >= FEED_ITEM_LIMIT:
			break
	return {"ok": true, "items": items}

func _visible_candidates(active_events: Array, current_day: int, visibility_state: String) -> Array:
	var candidates: Array = []
	var seen_ids: Dictionary = {}
	for index in range(active_events.size()):
		var raw_event: Variant = active_events[index]
		if not (raw_event is Dictionary):
			continue
		var event := _normalize_legacy_event(raw_event)
		if event.is_empty():
			continue
		if str(event.get("visibility_state", "")) != visibility_state or not _is_live_event(event, current_day):
			continue
		var event_id := str(event.get("id", ""))
		if seen_ids.has(event_id):
			continue
		seen_ids[event_id] = true
		var expire_day := int(event.get("trigger_day", 0)) + int(event.get("deadline_days", 0))
		candidates.append({"event": event.duplicate(true), "index": index, "expire_day": expire_day, "remaining_days": expire_day - current_day})
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if int(left["expire_day"]) != int(right["expire_day"]):
			return int(left["expire_day"]) < int(right["expire_day"])
		var left_severity: int = int(SEVERITY_RANK.get(str(left["event"].get("severity", "")), -1))
		var right_severity: int = int(SEVERITY_RANK.get(str(right["event"].get("severity", "")), -1))
		if left_severity != right_severity:
			return left_severity > right_severity
		return int(left["index"]) < int(right["index"])
	)
	return candidates

func _sort_top_pressure(left: Dictionary, right: Dictionary) -> bool:
	var left_due := int(left.get("remaining_days", 0)) <= 1
	var right_due := int(right.get("remaining_days", 0)) <= 1
	if left_due != right_due:
		return left_due
	var left_severity := int(SEVERITY_RANK.get(str(left.get("event", {}).get("severity", "")), -1))
	var right_severity := int(SEVERITY_RANK.get(str(right.get("event", {}).get("severity", "")), -1))
	if left_severity != right_severity:
		return left_severity > right_severity
	if int(left.get("expire_day", 0)) != int(right.get("expire_day", 0)):
		return int(left.get("expire_day", 0)) < int(right.get("expire_day", 0))
	return int(left.get("index", 0)) < int(right.get("index", 0))

func _is_live_event(event: Dictionary, current_day: int) -> bool:
	if not (event.get("id", "") is String) or str(event.get("id", "")).is_empty():
		return false
	for text_key in ["type", "title", "visible_summary", "source_kind", "source_character_id"]:
		if not (event.get(text_key, "") is String) or (text_key != "source_character_id" and str(event.get(text_key, "")).is_empty()):
			return false
	if not ["known", "estimated", "hidden"].has(str(event.get("visibility_state", ""))):
		return false
	if not SEVERITY_RANK.has(str(event.get("severity", ""))) or not (event.get("requires_player_action", null) is bool):
		return false
	for array_key in ["related_character_ids", "interaction_targets", "knowledge_sources", "visible_risks", "available_decisions", "related_task_ids", "related_map_ids", "related_chain_ids"]:
		if not (event.get(array_key, null) is Array):
			return false
	for optional_array_key in ["visible_conflicting_claims", "action_unavailable_reasons"]:
		if event.has(optional_array_key) and not (event[optional_array_key] is Array):
			return false
	if event.has("blocked_reason") and not (event["blocked_reason"] is String):
		return false
	if not _is_integer(event.get("trigger_day")) or not _is_integer(event.get("deadline_days")):
		return false
	if int(event.get("deadline_days", 0)) < 1:
		return false
	if not (event.get("title", "") is String) or str(event.get("title", "")).is_empty():
		return false
	if not (event.get("confidence", 0.0) is float or event.get("confidence", 0.0) is int):
		return false
	var confidence := float(event.get("confidence", 0.0))
	if confidence < 0.0 or confidence > 1.0:
		return false
	return current_day < int(event.get("trigger_day", 0)) + int(event.get("deadline_days", 0))

func _normalize_legacy_event(raw_event: Dictionary) -> Dictionary:
	var event: Dictionary = raw_event.duplicate(true)
	var source_id: Variant = event.get("source_character_id", null)
	if not event.has("source_kind"):
		if not (source_id is String) or str(source_id).is_empty():
			return {}
		event["source_kind"] = "character"
	elif not (event["source_kind"] is String):
		return {}
	var source_kind := str(event["source_kind"])
	if source_kind == "character" and (not (source_id is String) or str(source_id).is_empty()):
		return {}
	if source_kind in ["system", "unknown"] and (not (source_id is String) or not str(source_id).is_empty()):
		return {}
	if not source_kind in ["character", "system", "unknown"]:
		return {}
	if not event.has("visibility_state"):
		event["visibility_state"] = "known"
	if not event.has("severity"):
		var urgency := int(event.get("urgency", 0))
		event["severity"] = "critical" if urgency >= 80 else "major" if urgency >= 60 else "important" if urgency >= 40 else "ordinary"
	if not event.has("requires_player_action"):
		event["requires_player_action"] = event.get("available_decisions", []) is Array and not event.get("available_decisions", []).is_empty()
	if not event.has("confidence"):
		event["confidence"] = 1.0
	var defaults := {
		"related_character_ids": [source_id] if source_kind == "character" else [],
		"interaction_targets": [],
		"knowledge_sources": [],
		"visible_risks": [],
		"available_decisions": [],
		"related_task_ids": [],
		"related_map_ids": [],
		"related_chain_ids": []
	}
	for key in defaults:
		if not event.has(key):
			event[key] = defaults[key].duplicate(true)
	event["related_character_ids"] = _infer_related_character_ids(event)
	return event

func _top_item(event: Dictionary, candidate: Dictionary) -> Dictionary:
	var item := {
		"event_id": str(event["id"]),
		"expire_day": int(candidate["expire_day"]),
		"remaining_days": int(candidate["remaining_days"]),
		"due_soon": int(candidate["remaining_days"]) <= 1,
		"severity": str(event.get("severity", ""))
	}
	for key in TOP_FIELDS:
		if not event.has(key):
			continue
		item[key] = event[key].duplicate(true) if event[key] is Array or event[key] is Dictionary else event[key]
	return item

func _feed_item(event: Dictionary, candidate: Dictionary) -> Dictionary:
	var feed_kind := _feed_kind(event)
	var item := {
		"event_id": str(event["id"]),
		"title": str(event.get("title", "")),
		"summary": str(event.get("visible_summary", "")),
		"feed_kind": feed_kind,
		"severity": str(event.get("severity", "")),
		"remaining_days": int(candidate["remaining_days"]),
		"expire_day": int(candidate["expire_day"]),
		"confidence": float(event.get("confidence", 0.0)),
		"source_label": _feed_source_label(event),
		"related_character_ids": _feed_related_character_ids(event)
	}
	return item

func _feed_kind(event: Dictionary) -> String:
	var event_type := str(event.get("type", "")).to_lower()
	if event_type.contains("rumor") or event_type == "public_sentiment" or str(event.get("source_kind", "")) == "unknown":
		return "rumor"
	return "delegated" if bool(event.get("requires_player_action", false)) else "report"

func _feed_source_label(event: Dictionary) -> String:
	var display_label := str(event.get("source_display_label", "")).strip_edges()
	if not display_label.is_empty():
		return display_label
	var source_id := str(event.get("source_character_id", "")).strip_edges()
	if not source_id.is_empty():
		return source_id
	var sources: Array = event.get("knowledge_sources", [])
	if not sources.is_empty():
		return str(sources[0]).strip_edges()
	return "系统奏报" if str(event.get("source_kind", "")) == "system" else "来源不明"

func _feed_related_character_ids(event: Dictionary) -> Array:
	var ids: Array = []
	var source_id := str(event.get("source_character_id", "")).strip_edges()
	if not source_id.is_empty():
		ids.append(source_id)
	var related_values: Variant = event.get("related_character_ids", [])
	if related_values is Array:
		for related in related_values:
			var related_id := str(related).strip_edges()
			if not related_id.is_empty() and not ids.has(related_id):
				ids.append(related_id)
	return ids

func _infer_related_character_ids(event: Dictionary) -> Array:
	var ids: Array = []
	var source_id := str(event.get("source_character_id", "")).strip_edges()
	if not source_id.is_empty():
		ids.append(source_id)
	var related_values: Variant = event.get("related_character_ids", [])
	if related_values is Array:
		for related in related_values:
			var related_id := str(related).strip_edges()
			if not related_id.is_empty() and not ids.has(related_id):
				ids.append(related_id)
	var searchable_text := "%s\n%s\n%s" % [
		str(event.get("title", "")),
		str(event.get("visible_summary", "")),
		str(event.get("source_display_label", ""))
	]
	for character_id in CHARACTER_ALIAS_IDS.keys():
		if ids.has(character_id):
			continue
		for alias in CHARACTER_ALIAS_IDS[character_id]:
			var alias_text := str(alias)
			if not alias_text.is_empty() and searchable_text.contains(alias_text):
				ids.append(character_id)
				break
	return ids

func _future_source_ids(event: Dictionary) -> Array:
	var source_ids: Array = []
	var source_character_id := str(event.get("source_character_id", ""))
	if not source_character_id.is_empty():
		source_ids.append(source_character_id)
	elif str(event.get("source_display_label", "")).is_empty():
		source_ids.append("系统奏报" if str(event.get("source_kind", "")) == "system" else "来源不明")
	else:
		source_ids.append(str(event.get("source_display_label", "")))
	return source_ids

func _is_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), floor(float(value))))
