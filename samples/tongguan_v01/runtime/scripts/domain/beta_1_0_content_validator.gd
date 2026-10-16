extends RefCounted

class_name Beta10ContentValidator

const REQUIRED_KEYS := ["id", "type", "title", "visible_summary", "source_kind", "source_character_id", "related_character_ids", "trigger_day", "deadline_days", "severity", "visibility_state", "requires_player_action", "interaction_targets", "available_decisions", "on_resolve", "on_expire", "knowledge_sources", "confidence", "visible_risks", "related_task_ids", "related_map_ids", "related_chain_ids"]
const VISIBILITY_STATES := ["known", "estimated", "hidden"]
const SEVERITIES := ["ordinary", "important", "major", "critical"]
const SOURCE_KINDS := ["character", "system", "unknown"]
const NUMERIC_EFFECT_TYPES := ["resource_delta", "relationship_delta", "faction_delta", "battlefront_delta", "strategy_route_delta"]
const STRING_VALUE_EFFECT_TYPES := ["battlefront_reason", "character_memory"]
const EFFECT_TYPES := ["resource_delta", "relationship_delta", "faction_delta", "battlefront_delta", "strategy_route_delta", "battlefront_reason", "character_memory", "flag_set", "character_birth"]
const STRING_ARRAY_KEYS := ["related_character_ids", "interaction_targets", "available_decisions", "knowledge_sources", "visible_risks", "related_task_ids", "related_map_ids", "related_chain_ids"]

func validate_events(events: Variant, reference_data: Dictionary, existing_ids: Dictionary) -> Dictionary:
	if not (events is Array):
		return _fail("events")
	var copied: Array = []
	var seen: Dictionary = existing_ids.duplicate(true)
	for index in range(events.size()):
		var raw_event: Variant = events[index]
		if not (raw_event is Dictionary):
			return _fail("events[%d]" % index)
		var event: Dictionary = raw_event
		var validation := _validate_event(event, reference_data, seen, index)
		if not validation.get("ok", false):
			return validation
		seen[event["id"]] = true
		var event_copy: Dictionary = event.duplicate(true)
		event_copy["source_display_label"] = source_display_label(event_copy["source_kind"])
		copied.append(event_copy)
	return {"ok": true, "data": copied}

func _validate_event(event: Dictionary, reference_data: Dictionary, seen: Dictionary, index: int) -> Dictionary:
	var path := "events[%d]" % index
	for key in REQUIRED_KEYS:
		if not event.has(key):
			return _fail("%s.%s" % [path, key])
	if not _is_identifier(event["id"]) or seen.has(event["id"]):
		return _fail(path + ".id")
	for text_key in ["type", "title", "visible_summary"]:
		if not (event[text_key] is String) or str(event[text_key]).is_empty():
			return _fail("%s.%s" % [path, text_key])
	if str(event["title"]).length() > 120:
		return _fail(path + ".title")
	if str(event["visible_summary"]).length() > 2000:
		return _fail(path + ".visible_summary")
	if not _is_integer(event["trigger_day"]) or int(event["trigger_day"]) < 0:
		return _fail(path + ".trigger_day")
	if not _is_integer(event["deadline_days"]) or int(event["deadline_days"]) < 1:
		return _fail(path + ".deadline_days")
	if not _is_number(event["confidence"]) or float(event["confidence"]) < 0.0 or float(event["confidence"]) > 1.0:
		return _fail(path + ".confidence")
	if not (event["requires_player_action"] is bool):
		return _fail(path + ".requires_player_action")
	if not (event["source_kind"] is String) or not SOURCE_KINDS.has(event["source_kind"]):
		return _fail(path + ".source_kind")
	if not (event["visibility_state"] is String) or not VISIBILITY_STATES.has(event["visibility_state"]):
		return _fail(path + ".visibility_state")
	if not (event["severity"] is String) or not SEVERITIES.has(event["severity"]):
		return _fail(path + ".severity")
	var source_validation := _validate_source(event, reference_data, path)
	if not source_validation.get("ok", false):
		return source_validation
	for array_key in STRING_ARRAY_KEYS:
		var array_validation := _validate_string_array(event[array_key], "%s.%s" % [path, array_key])
		if not array_validation.get("ok", false):
			return array_validation
	for effect_key in ["on_resolve", "on_expire"]:
		var effects_validation := _validate_effects(event[effect_key], reference_data, "%s.%s" % [path, effect_key])
		if not effects_validation.get("ok", false):
			return effects_validation
	for reference_rule in [["related_character_ids", "character_ids"], ["interaction_targets", "interaction_target_ids"], ["available_decisions", "decision_ids"], ["related_task_ids", "task_ids"], ["related_map_ids", "map_ids"], ["related_chain_ids", "chain_ids"]]:
		var references_validation := _validate_references(event[reference_rule[0]], reference_data.get(reference_rule[1], []), "%s.%s" % [path, reference_rule[0]])
		if not references_validation.get("ok", false):
			return references_validation
	return {"ok": true}

func _validate_source(event: Dictionary, reference_data: Dictionary, path: String) -> Dictionary:
	var source_id: Variant = event["source_character_id"]
	if not (source_id is String):
		return _fail(path + ".source_character_id")
	if event["source_kind"] == "character":
		if not _is_identifier(source_id) or not reference_data.get("character_ids", []).has(source_id):
			return _fail(path + ".source_character_id")
	elif not str(source_id).is_empty():
		return _fail(path + ".source_character_id")
	return {"ok": true}

func _validate_string_array(value: Variant, path: String) -> Dictionary:
	if not (value is Array) or value.size() > 32:
		return _fail(path)
	for item_index in range(value.size()):
		if not (value[item_index] is String):
			return _fail("%s[%d]" % [path, item_index])
	return {"ok": true}

func _validate_references(values: Array, valid_ids: Array, path: String) -> Dictionary:
	for item_index in range(values.size()):
		var value: String = values[item_index]
		if not valid_ids.has(value):
			return _fail("%s[%d]" % [path, item_index])
	return {"ok": true}

func _validate_effects(value: Variant, reference_data: Dictionary, path: String) -> Dictionary:
	if not (value is Array) or value.size() > 32:
		return _fail(path)
	for effect_index in range(value.size()):
		var effect: Variant = value[effect_index]
		if not (effect is Dictionary):
			return _fail("%s[%d]" % [path, effect_index])
		var effect_validation := _validate_effect(effect, reference_data, "%s[%d]" % [path, effect_index])
		if not effect_validation.get("ok", false):
			return effect_validation
	return {"ok": true}

func _validate_effect(effect: Dictionary, reference_data: Dictionary, path: String) -> Dictionary:
	if not effect.has("type") or not (effect["type"] is String) or not EFFECT_TYPES.has(effect["type"]):
		return _fail(path + ".type")
	if not effect.has("target") or not _is_identifier(effect["target"]):
		return _fail(path + ".target")
	var effect_type: String = effect["type"]
	if effect_type=="character_birth":
		var birth: Dictionary = preload("res://scripts/core/character_birth_contract.gd").validate(effect.get("value"))
		if not birth.ok or effect.value.child_id!=effect.target: return _fail(path+".value")
	if NUMERIC_EFFECT_TYPES.has(effect_type) and (not effect.has("value") or not _is_integer(effect["value"])):
		return _fail(path + ".value")
	if STRING_VALUE_EFFECT_TYPES.has(effect_type) and (not effect.has("value") or not (effect["value"] is String)):
		return _fail(path + ".value")
	if effect_type == "flag_set" and not effect.has("value"):
		return _fail(path + ".value")
	if effect_type in ["faction_delta", "battlefront_delta"] and (not effect.has("field") or not _is_identifier(effect["field"])):
		return _fail(path + ".field")
	if effect_type == "faction_delta" and not reference_data.get("faction_fields_by_id", {}).get(effect["target"], []).has(effect["field"]):
		return _fail(path + ".field")
	if effect_type == "battlefront_delta" and not reference_data.get("battlefront_fields_by_id", {}).get(effect["target"], []).has(effect["field"]):
		return _fail(path + ".field")
	var reference_key := _effect_reference_key(effect_type)
	if not reference_key.is_empty() and not reference_data.get(reference_key, []).has(effect["target"]):
		return _fail(path + ".target")
	return {"ok": true}

func _effect_reference_key(effect_type: String) -> String:
	match effect_type:
		"resource_delta": return "resource_ids"
		"relationship_delta", "character_memory": return "character_ids"
		"faction_delta": return "faction_ids"
		"battlefront_delta", "battlefront_reason": return "battlefront_ids"
		"strategy_route_delta": return "strategy_route_ids"
	return ""

func _is_identifier(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= 64

func _is_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), floor(float(value))))

func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT

func source_display_label(source_kind: String) -> String:
	if source_kind == "system":
		return "系统奏报"
	if source_kind == "unknown":
		return "来源不明"
	return ""

func _fail(path: String) -> Dictionary:
	return {"ok": false, "error": path}

func validate_character_arcs(arcs_payload: Variant, character_ids: Array) -> Dictionary:
	if not (arcs_payload is Dictionary):
		return _fail("arcs")
	var payload: Dictionary = arcs_payload
	if not payload.has("arcs") or not (payload["arcs"] is Dictionary):
		return _fail("arcs")
	var arcs: Dictionary = payload["arcs"]
	var copied: Dictionary = {}
	for character_id in arcs.keys():
		var cid := str(character_id)
		if not character_ids.has(cid):
			return _fail("arcs." + cid + ".character_id")
		var raw: Variant = arcs[character_id]
		if not (raw is Dictionary):
			return _fail("arcs." + cid)
		var arc: Dictionary = raw
		if str(arc.get("character_id", "")) != cid:
			return _fail("arcs." + cid + ".character_id")
		if not _is_identifier(arc.get("arc_id", "")):
			return _fail("arcs." + cid + ".arc_id")
		if not (arc.get("title", "") is String) or str(arc.get("title", "")).is_empty():
			return _fail("arcs." + cid + ".title")
		if not (arc.get("stages", null) is Array) or (arc["stages"] as Array).size() < 2:
			return _fail("arcs." + cid + ".stages")
		var stages_copy: Array = []
		for stage_index in range((arc["stages"] as Array).size()):
			var stage_raw: Variant = arc["stages"][stage_index]
			if not (stage_raw is Dictionary):
				return _fail("arcs.%s.stages[%d]" % [cid, stage_index])
			var stage: Dictionary = stage_raw
			for key in ["stage_id", "stance", "trigger", "memory_callback"]:
				if not (stage.get(key, "") is String) or str(stage.get(key, "")).is_empty():
					return _fail("arcs.%s.stages[%d].%s" % [cid, stage_index, key])
			if not _is_integer(stage.get("day_min", null)) or not _is_integer(stage.get("day_max", null)):
				return _fail("arcs.%s.stages[%d].day_window" % [cid, stage_index])
			if int(stage.get("day_min", 0)) < 1 or int(stage.get("day_max", 0)) < int(stage.get("day_min", 0)):
				return _fail("arcs.%s.stages[%d].day_window" % [cid, stage_index])
			if not (stage.get("event_refs", null) is Array):
				return _fail("arcs.%s.stages[%d].event_refs" % [cid, stage_index])
			stages_copy.append(stage.duplicate(true))
		copied[cid] = {
			"character_id": cid,
			"arc_id": str(arc.get("arc_id", "")),
			"title": str(arc.get("title", "")),
			"stages": stages_copy
		}
	return {"ok": true, "data": copied}

func validate_character_depth_model(model: Variant) -> Dictionary:
	if not (model is Dictionary):
		return _fail("model")
	var m: Dictionary = model
	var cid := str(m.get("character_id", ""))
	if not _is_identifier(cid):
		return _fail("character_id")
	var checks := {
		"personality_rules": [3, 5],
		"goals": [2, 3],
		"red_lines": [3, 3],
		"persuasion_hooks": [3, 32],
		"memory_priorities": [5, 5],
		"action_families": [4, 32],
		"relationships": [3, 32],
		"mutable_stances": [2, 32]
	}
	for key in checks.keys():
		if not (m.get(key, null) is Array):
			return _fail(cid + "." + key)
		var size := (m[key] as Array).size()
		var bounds: Array = checks[key]
		if size < int(bounds[0]) or size > int(bounds[1]):
			return _fail(cid + "." + key)
	if not m.has("arc_id") or not _is_identifier(m.get("arc_id", "")):
		return _fail(cid + ".arc_id")
	if not m.has("arc_stage_count") or not _is_integer(m.get("arc_stage_count", null)) or int(m.get("arc_stage_count", 0)) < 2:
		return _fail(cid + ".arc_stage_count")
	return {"ok": true, "data": m.duplicate(true)}

