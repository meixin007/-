extends RefCounted

class_name PoliticalSeasonSettlementService

const SUPPORTED_CAMPAIGN_IDS := ["anshi_beta_1_09", "anshi_beta_1_10", "anshi_beta_1_13"]
const FactionAgendaServiceScript = preload("res://scripts/core/faction_agenda_service.gd")
const StructuredMemoryServiceScript = preload("res://scripts/core/structured_memory_service.gd")

func settle_daily(state, data: Dictionary, day: int) -> Dictionary:
	var empty_result := _result(true, "no_op")
	if state == null:
		return _fail("missing state", "invalid_state")
	if not SUPPORTED_CAMPAIGN_IDS.has(str(data.get("campaign_id", ""))):
		return empty_result
	var effective_day := maxi(day, 0)
	var snapshot: Dictionary = state.to_transaction_dictionary().duplicate(true) if state.has_method("to_transaction_dictionary") else {}
	var result := _result(true, "settled")
	var templates: Array = _echo_templates(data)
	templates.sort_custom(Callable(self, "_sort_echoes"))
	for raw_echo in templates:
		if not raw_echo is Dictionary:
			return _rollback_failure(state, snapshot, "political echo must be a dictionary", "invalid_echo")
		var echo: Dictionary = raw_echo
		var echo_id := _echo_id(echo)
		if echo_id.is_empty():
			return _rollback_failure(state, snapshot, "political echo id is required", "invalid_echo")
		if not _echo_is_due(echo, state, effective_day):
			continue
		if _has_applied_echo(state, echo_id):
			continue
		var condition_result := _conditions_match(state, echo)
		if not bool(condition_result.get("ok", false)):
			return _rollback_failure(state, snapshot, str(condition_result.get("error", "political echo condition is invalid")), "invalid_echo_condition")
		if not bool(condition_result.get("matched", false)):
			continue
		var applied := _apply_echo(state, data, echo, effective_day)
		if not bool(applied.get("ok", false)):
			return _rollback_failure(state, snapshot, str(applied.get("error", "political echo failed")), str(applied.get("code", "political_echo_failed")))
		result["echoes"].append(echo_id)
		result["effects"].append_array(applied.get("effects", []))
		result["refs"].append_array(applied.get("refs", []))
	result["code"] = "settled" if not result["echoes"].is_empty() else "no_op"
	return result

func project_applied_echo_ids(state) -> Array:
	var ids: Array = []
	if state == null or not state.chronicle_causal_references is Array:
		return ids
	var seen: Dictionary = {}
	for raw_ref in state.chronicle_causal_references:
		if not raw_ref is Dictionary or str((raw_ref as Dictionary).get("kind", "")) != "political_season_echo":
			continue
		var reference: Dictionary = raw_ref
		var echo_id := str(reference.get("echo_id", ""))
		if echo_id.is_empty():
			echo_id = str(reference.get("id", ""))
			if echo_id.begins_with("political_season_echo|"):
				echo_id = echo_id.trim_prefix("political_season_echo|")
		if echo_id.is_empty() or seen.has(echo_id):
			continue
		seen[echo_id] = true
		ids.append(echo_id)
	ids.sort()
	return ids

func _apply_echo(state, data: Dictionary, echo: Dictionary, day: int) -> Dictionary:
	var echo_id := _echo_id(echo)
	var effects: Array = []
	var refs: Array = []
	var faction_service = FactionAgendaServiceScript.new()
	for raw_reaction in _faction_reactions(echo):
		if not raw_reaction is Dictionary:
			return _fail("faction reaction is invalid", "invalid_faction_reaction")
		var reaction_record: Dictionary = raw_reaction
		var faction_id := str(reaction_record.get("faction_id", reaction_record.get("faction_key", echo.get("faction_id", echo.get("target_faction", "")))))
		var reaction: Dictionary = reaction_record.get("reaction", reaction_record) if reaction_record.get("reaction", reaction_record) is Dictionary else {}
		if faction_id.is_empty():
			return _fail("faction reaction has no faction id", "invalid_faction_reaction")
		if reaction.is_empty():
			return _fail("faction reaction has no effect", "invalid_faction_reaction")
		var faction_result: Dictionary = faction_service.apply_reaction(state, data, faction_id, reaction)
		if not bool(faction_result.get("ok", false)):
			return _fail(str(faction_result.get("error", "faction reaction failed")), "faction_reaction_failed")
		effects.append({"type": "faction_reaction", "faction_id": faction_id, "reaction_type": str(reaction.get("reaction_type", "")), "echo_id": echo_id})
		refs.append({"kind": "faction_agenda", "id": faction_id, "echo_id": echo_id})
	for raw_relationship in _relationship_effects(echo):
		if not raw_relationship is Dictionary:
			return _fail("relationship effect is invalid", "invalid_relationship_effect")
		var relationship: Dictionary = raw_relationship
		var character_id := str(relationship.get("character_id", relationship.get("target_id", relationship.get("target_character_id", echo.get("relationship_target_character_id", echo.get("target_character_id", ""))))))
		var delta := int(relationship.get("value", relationship.get("delta", relationship.get("relationship_delta", 0))))
		if character_id.is_empty() or not state.character_states.has(character_id):
			return _fail("relationship target is unknown: " + character_id, "invalid_relationship_effect")
		state.apply_relationship_delta(character_id, delta)
		effects.append({"type": "relationship_delta", "character_id": character_id, "source_character_id": str(relationship.get("source_character_id", echo.get("source_character_id", ""))), "target_character_id": character_id, "value": delta, "echo_id": echo_id})
		refs.append({"kind": "relationship", "id": "%s|%s" % [echo_id, character_id], "character_id": character_id, "echo_id": echo_id})
	var memory_index := 0
	for raw_memory in _memory_entries(echo):
		if not raw_memory is Dictionary:
			return _fail("political memory is invalid", "invalid_memory")
		var memory_input: Dictionary = _normalize_memory_input(raw_memory, echo, echo_id, memory_index)
		var memory_result: Dictionary = StructuredMemoryServiceScript.new().create_memory(state, memory_input)
		if not bool(memory_result.get("ok", false)):
			return _fail(str(memory_result.get("error", "political memory failed")), "memory_creation_failed")
		var memory: Dictionary = memory_result.get("memory", {}) if memory_result.get("memory", {}) is Dictionary else {}
		effects.append({"type": "structured_memory", "memory_id": str(memory.get("id", "")), "echo_id": echo_id})
		refs.append({"kind": "memory", "id": str(memory.get("id", "")), "echo_id": echo_id})
		memory_index += 1
	for raw_action in _npc_actions(echo):
		if not raw_action is Dictionary:
			return _fail("NPC echo action is invalid", "invalid_npc_action")
		var action: Dictionary = (raw_action as Dictionary).duplicate(true)
		var action_id := str(action.get("action_id", action.get("id", "")))
		if action_id.is_empty():
			action_id = "npc|political_season|%s|%d" % [echo_id, effects.size()]
		if _has_npc_action(state, action_id):
			continue
		action["action_id"] = action_id
		action["source_echo_id"] = echo_id
		action["source_day"] = day
		if not action.has("target_character_id") and echo.has("target_character_id"):
			action["target_character_id"] = str(echo.get("target_character_id", ""))
		if not action.has("summary") and echo.has("public_summary"):
			action["summary"] = str(echo.get("public_summary", ""))
		state.record_npc_active_action(action)
		effects.append({"type": "npc_action", "action_id": action_id, "echo_id": echo_id})
		refs.append({"kind": "npc_action", "id": action_id, "echo_id": echo_id})
	var source_ids := _source_ids(echo)
	var chronicle_id := "political_season_echo|%s" % echo_id
	state.chronicle_causal_references.append({
		"kind": "political_season_echo",
		"id": chronicle_id,
		"echo_id": echo_id,
		"day": day,
		"source_ids": source_ids,
		"source_memorial_ids": _source_values(echo, ["source_memorial_ids", "source_memorial_id"]),
		"source_order_ids": _source_values(echo, ["source_order_ids", "source_order_id"])
	})
	refs.append({"kind": "political_season_echo", "id": chronicle_id, "echo_id": echo_id, "day": day, "source_ids": source_ids})
	effects.append({"type": "chronicle_causal_reference", "id": chronicle_id, "echo_id": echo_id})
	return {"ok": true, "effects": effects, "refs": refs}

func _normalize_memory_input(raw_memory: Dictionary, echo: Dictionary, echo_id: String, index: int) -> Dictionary:
	var memory := raw_memory.duplicate(true)
	if str(memory.get("id", "")).is_empty():
		memory["id"] = str(memory.get("memory_id", ""))
		if str(memory.get("id", "")).is_empty():
			memory["id"] = "memory|political_season|%s|%d" % [echo_id, index]
	if not memory.has("target_id") and memory.has("character_id"):
		memory["target_id"] = str(memory.get("character_id", ""))
	memory.erase("memory_id")
	memory.erase("character_id")
	if not memory.has("type"):
		memory["type"] = str(memory.get("memory_type", "political_echo"))
	if not memory.has("memory_type"):
		memory["memory_type"] = str(memory.get("type", "political_echo"))
	if not memory.has("participants"):
		var participants: Array = []
		for character_id in [str(memory.get("source_id", "li_heng")), str(memory.get("target_id", ""))]:
			if not character_id.is_empty() and not participants.has(character_id):
				participants.append(character_id)
		memory["participants"] = participants
	if not memory.has("original_evidence"):
		memory["original_evidence"] = {"echo_id": echo_id, "source_ids": _source_ids(echo)}
	var context: Dictionary = memory.get("source_context", {}) if memory.get("source_context", {}) is Dictionary else {}
	context["political_season_echo_id"] = echo_id
	context["source_ids"] = _source_ids(echo)
	memory["source_context"] = context
	memory.erase("political_meaning_id")
	return memory

func _conditions_match(state, echo: Dictionary) -> Dictionary:
	var required_flags: Variant = echo.get("required_flags", {})
	if required_flags != null and not required_flags is Dictionary:
		return {"ok": false, "error": "required_flags must be a dictionary"}
	if required_flags is Dictionary:
		for flag_id in (required_flags as Dictionary).keys():
			if state.flags.get(str(flag_id), null) != (required_flags as Dictionary).get(flag_id):
				return {"ok": true, "matched": false}
	var required_sources: Variant = echo.get("required_source_ids", [])
	if required_sources != null and not required_sources is Array:
		return {"ok": false, "error": "required_source_ids must be an array"}
	for raw_source_id in required_sources if required_sources is Array else []:
		if not _has_authoritative_reference(state, str(raw_source_id)):
			return {"ok": true, "matched": false}
	var route_ids := _string_array(echo.get("route_ids", []))
	if not route_ids.is_empty():
		var selected_routes := []
		for flag_id in ["beta109_route_id", "beta109_public_route_id", "beta110_route_id", "beta110_public_route_id", "route_id", "public_route_id"]:
			var selected := str(state.flags.get(flag_id, ""))
			if not selected.is_empty() and not selected_routes.has(selected):
				selected_routes.append(selected)
		if selected_routes.is_empty():
			return {"ok": true, "matched": false}
		var route_matches := false
		for selected_route in selected_routes:
			if route_ids.has(selected_route):
				route_matches = true
				break
		if not route_matches:
			return {"ok": true, "matched": false}
	var trigger_outcomes := _string_array(echo.get("trigger_outcomes", []))
	var trigger_conditions := _string_array(echo.get("trigger_conditions", []))
	if not trigger_outcomes.is_empty() or not trigger_conditions.is_empty():
		var source_result := _resolve_source_state(state, echo)
		if not bool(source_result.get("found", false)):
			return {"ok": true, "matched": false}
		if not trigger_outcomes.is_empty() and not trigger_outcomes.has(str(source_result.get("outcome", ""))):
			return {"ok": true, "matched": false}
		if not trigger_conditions.is_empty() and not trigger_conditions.has(str(source_result.get("condition", ""))):
			return {"ok": true, "matched": false}
	return {"ok": true, "matched": true}

func _resolve_source_state(state, echo: Dictionary) -> Dictionary:
	var governance: Dictionary = state.governance_state if state != null and state.governance_state is Dictionary else {}
	var memorial_id := str(echo.get("source_memorial_id", ""))
	var order_id := str(echo.get("source_order_id", ""))
	var memorial := _find_record(governance.get("memorials", {}), memorial_id, ["memorial_id", "id"])
	if order_id.is_empty() and not memorial.is_empty():
		order_id = str(memorial.get("order_id", ""))
	var order := _find_record(governance.get("orders", {}), order_id, ["order_id", "id"])
	var outcome := str(order.get("outcome", memorial.get("outcome", "")))
	var condition := str(order.get("condition", memorial.get("condition", "")))
	if condition.is_empty():
		condition = "normal" if outcome in ["completed", "partial", "failed"] else outcome
	return {"found": not memorial.is_empty() or not order.is_empty(), "memorial": memorial, "order": order, "outcome": outcome, "condition": condition}

func _find_record(collection: Variant, record_id: String, id_keys: Array) -> Dictionary:
	if record_id.is_empty():
		return {}
	if collection is Dictionary:
		var mapped: Variant = (collection as Dictionary).get(record_id, null)
		if mapped is Dictionary:
			return (mapped as Dictionary).duplicate(true)
	if collection is Array:
		for raw_record in collection:
			if not raw_record is Dictionary:
				continue
			for id_key in id_keys:
				if str((raw_record as Dictionary).get(str(id_key), "")) == record_id:
					return (raw_record as Dictionary).duplicate(true)
	return {}

func _has_authoritative_reference(state, reference_id: String) -> bool:
	if reference_id.is_empty():
		return false
	for raw_ref in state.chronicle_causal_references if state.chronicle_causal_references is Array else []:
		if raw_ref is Dictionary and str((raw_ref as Dictionary).get("id", "")) == reference_id:
			return true
	for collection in [state.event_history, state.active_events, state.resolved_events, state.battlefront_reports]:
		if not collection is Array:
			continue
		for raw_record in collection:
			if raw_record is Dictionary and str((raw_record as Dictionary).get("id", (raw_record as Dictionary).get("event_id", (raw_record as Dictionary).get("report_id", "")))) == reference_id:
				return true
	for collection in [state.governance_state.get("memorials", {}), state.governance_state.get("orders", {})] if state.governance_state is Dictionary else []:
		if _find_record(collection, reference_id, ["id", "memorial_id", "order_id"]).is_empty():
			continue
		return true
	return false

func _echo_is_due(echo: Dictionary, state, day: int) -> bool:
	var window_value: Variant = echo.get("day_window", echo.get("activation_window", echo.get("window", {})))
	var window: Dictionary = window_value if window_value is Dictionary else {}
	var start_day := int(echo.get("day_min", window.get("start_day", 0)))
	var end_day := int(echo.get("day_max", window.get("end_day", 0)))
	if echo.has("day"):
		return day == int(echo.get("day", -1))
	if start_day > 0 and day < start_day:
		return false
	if end_day > 0 and day > end_day:
		return false
	return true

func _echo_templates(data: Dictionary) -> Array:
	for key in ["political_echoes", "beta109_political_echoes", "political_echoes_beta_1_09", "political_echoes_beta_1_10", "echoes"]:
		var value: Variant = data.get(key, null)
		if value is Array:
			return (value as Array).duplicate(true)
		if value is Dictionary:
			for collection_key in ["echoes", "items", "entries"]:
				if (value as Dictionary).get(collection_key, null) is Array:
					return ((value as Dictionary).get(collection_key) as Array).duplicate(true)
			var entries: Array = []
			for raw_id in (value as Dictionary).keys():
				var entry: Variant = (value as Dictionary)[raw_id]
				if entry is Dictionary:
					var copy: Dictionary = (entry as Dictionary).duplicate(true)
					if _echo_id(copy).is_empty():
						copy["echo_id"] = str(raw_id)
					entries.append(copy)
			return entries
	return []

func _faction_reactions(echo: Dictionary) -> Array:
	if echo.get("faction_reactions", null) is Array:
		return (echo.get("faction_reactions") as Array).duplicate(true)
	if echo.get("faction_reaction", null) is Dictionary:
		return [echo.get("faction_reaction").duplicate(true)]
	if echo.get("reaction", null) is Dictionary and (echo.has("faction_id") or echo.get("reaction", {}).has("faction_id")):
		return [{"faction_id": str(echo.get("faction_id", echo.get("reaction", {}).get("faction_id", ""))), "reaction": echo.get("reaction").duplicate(true)}]
	var effects: Dictionary = _effects_container(echo)
	if effects.get("faction_reactions", null) is Array:
		return (effects.get("faction_reactions") as Array).duplicate(true)
	if effects.get("faction_reaction", null) is Dictionary:
		var reaction: Dictionary = (effects.get("faction_reaction") as Dictionary).duplicate(true)
		var faction_id := str(reaction.get("faction_id", reaction.get("faction_key", echo.get("target_faction", ""))))
		return [{"faction_id": faction_id, "reaction": reaction}]
	return []

func _relationship_effects(echo: Dictionary) -> Array:
	if echo.get("relationship_effects", null) is Array:
		return (echo.get("relationship_effects") as Array).duplicate(true)
	if echo.get("relationship_deltas", null) is Array:
		return (echo.get("relationship_deltas") as Array).duplicate(true)
	var effects: Dictionary = _effects_container(echo)
	if effects.get("relationship_effects", null) is Array:
		return (effects.get("relationship_effects") as Array).duplicate(true)
	if effects.get("relationship_delta", null) is Dictionary:
		return [(effects.get("relationship_delta") as Dictionary).duplicate(true)]
	return []

func _memory_entries(echo: Dictionary) -> Array:
	if echo.get("memories", null) is Array:
		return (echo.get("memories") as Array).duplicate(true)
	if echo.get("memory", null) is Dictionary:
		return [echo.get("memory").duplicate(true)]
	var effects: Dictionary = _effects_container(echo)
	if effects.get("memories", null) is Array:
		return (effects.get("memories") as Array).duplicate(true)
	if effects.get("structured_memory", null) is Dictionary:
		return [(effects.get("structured_memory") as Dictionary).duplicate(true)]
	return []

func _npc_actions(echo: Dictionary) -> Array:
	if echo.get("npc_actions", null) is Array:
		return (echo.get("npc_actions") as Array).duplicate(true)
	if echo.get("npc_active_actions", null) is Array:
		return (echo.get("npc_active_actions") as Array).duplicate(true)
	var effects: Dictionary = _effects_container(echo)
	if effects.get("npc_action", null) is Dictionary:
		return [(effects.get("npc_action") as Dictionary).duplicate(true)]
	var target_action := str(echo.get("target_npc_action", ""))
	if not target_action.is_empty():
		return [{"action_id": "npc|political_season|%s|%s" % [_echo_id(echo), target_action], "action_type": target_action, "target_npc_action": target_action}]
	return []

func _source_ids(echo: Dictionary) -> Array:
	var ids: Array = []
	for key in ["source_ids", "source_memorial_ids", "source_order_ids", "source_report_ids", "source_memorial_id", "source_order_id", "source_report_id"]:
		for raw_id in _string_array(echo.get(key, [])) if echo.get(key, []) is Array else [str(echo.get(key, ""))]:
			if not ids.has(raw_id):
				ids.append(raw_id)
	var effects: Dictionary = _effects_container(echo)
	var chronicle: Variant = effects.get("chronicle", {})
	if chronicle is Dictionary:
		for key in ["source_memorial_id", "source_order_id", "source_report_id"]:
			var source_id := str((chronicle as Dictionary).get(key, ""))
			if not source_id.is_empty() and not ids.has(source_id):
				ids.append(source_id)
	var single_source := str(echo.get("source_id", ""))
	if not single_source.is_empty() and not ids.has(single_source):
		ids.append(single_source)
	return ids

func _source_values(echo: Dictionary, keys: Array) -> Array:
	var values: Array = []
	var effects: Dictionary = _effects_container(echo)
	var chronicle: Variant = effects.get("chronicle", {})
	for key in keys:
		for raw_id in _string_array(echo.get(str(key), [])) if echo.get(str(key), []) is Array else [str(echo.get(str(key), ""))]:
			var source_id := str(raw_id)
			if not source_id.is_empty() and not values.has(source_id):
				values.append(source_id)
		if chronicle is Dictionary:
			var chronicle_key := str(key).trim_suffix("s")
			var chronicle_id := str((chronicle as Dictionary).get(chronicle_key, ""))
			if not chronicle_id.is_empty() and not values.has(chronicle_id):
				values.append(chronicle_id)
	return values

func _effects_container(echo: Dictionary) -> Dictionary:
	var effects: Variant = echo.get("effects", {})
	return (effects as Dictionary).duplicate(true) if effects is Dictionary else {}

func _string_array(value: Variant) -> Array:
	var result: Array = []
	if not value is Array:
		return result
	for item in value:
		var text := str(item)
		if not text.is_empty() and not result.has(text):
			result.append(text)
	return result

func _has_applied_echo(state, echo_id: String) -> bool:
	var stable_id := "political_season_echo|%s" % echo_id
	for raw_ref in state.chronicle_causal_references if state.chronicle_causal_references is Array else []:
		if raw_ref is Dictionary:
			var reference: Dictionary = raw_ref
			if str(reference.get("kind", "")) == "political_season_echo" and (str(reference.get("echo_id", "")) == echo_id or str(reference.get("id", "")) == stable_id):
				return true
	return false

func _has_npc_action(state, action_id: String) -> bool:
	for raw_action in state.active_npc_actions if state.active_npc_actions is Array else []:
		if raw_action is Dictionary and str((raw_action as Dictionary).get("action_id", (raw_action as Dictionary).get("id", ""))) == action_id:
			return true
	return false

func _echo_id(echo: Dictionary) -> String:
	return str(echo.get("echo_id", echo.get("id", ""))).strip_edges()

func _sort_echoes(left: Dictionary, right: Dictionary) -> bool:
	return _echo_id(left) < _echo_id(right)

func _rollback_failure(state, snapshot: Dictionary, message: String, code: String) -> Dictionary:
	if not snapshot.is_empty() and state.has_method("load_transaction_dictionary"):
		state.load_transaction_dictionary(snapshot)
	return _fail(message, code)

func _result(ok: bool, code: String) -> Dictionary:
	return {"ok": ok, "code": code, "echoes": [], "effects": [], "refs": []}

func _fail(message: String, code: String) -> Dictionary:
	var result := _result(false, code)
	result["error"] = message
	result["message"] = message
	return result
