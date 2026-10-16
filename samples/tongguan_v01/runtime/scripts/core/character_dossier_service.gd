extends RefCounted

class_name CharacterDossierService

const CharacterKnowledgeServiceScript = preload("res://scripts/core/character_knowledge_service.gd")
const CharacterStateServiceScript = preload("res://scripts/core/character_state_service.gd")
const CharacterArcServiceScript = preload("res://scripts/core/character_arc_service.gd")
const TangCharacterTraitServiceScript = preload("res://scripts/core/tang_character_trait_service.gd")
const TangClanServiceScript = preload("res://scripts/core/tang_clan_service.gd")
const ABILITY_FIELDS := ["military", "governance", "finance", "intrigue", "diplomacy", "prowess"]

func get_summonable_npc_ids(data: Dictionary, state = null) -> Array:
	var query_service = preload("res://scripts/core/character_query_service.gd").new()
	return query_service.get_all_summonable_npc_ids(data, state)

func get_character_list(data: Dictionary, state) -> Array:
	var rows: Array = []
	for npc_id in get_summonable_npc_ids(data, state):
		rows.append(get_dossier(data, state, str(npc_id)))
	return rows

func get_dossier(data: Dictionary, state, character_id: String) -> Dictionary:
	var character := _find_character(data, character_id, state)
	if character.is_empty():
		return {}
	var interactions: Dictionary = data.get("npc_interactions", {})
	var profile: Dictionary = interactions.get("profiles", {}).get(character_id, {})
	var current: Dictionary = {}
	if state != null and state.get("character_states") is Dictionary and state.character_states.get(character_id) is Dictionary:
		current = state.character_states.get(character_id)
	var memories: Array = current.get("memory_summary", character.get("memory_summary", [])).duplicate(true)
	var knowledge_service = CharacterKnowledgeServiceScript.new()
	var state_service = CharacterStateServiceScript.new()
	var tang_trait_service := TangCharacterTraitServiceScript.new()
	var tang_profile: Dictionary = tang_trait_service.get_categorized_trait_profile(state, data, character_id)
	var ai_personality: Dictionary = tang_trait_service.calculate_ai_personality(character_id, state, data)
	var opinion_with_player: Dictionary = tang_trait_service.calculate_mutual_opinion(character_id, "li_heng", state, data)

	var ability_estimates: Dictionary = {}
	var knowledge_sources: Dictionary = {}
	var discovery_routes: Dictionary = {}
	for field_id in ABILITY_FIELDS:
		var visible: Dictionary = knowledge_service.get_visible_field(state, character_id, field_id)
		# Only actual knowledge can support a public estimate. Hidden current
		# abilities are simulation inputs, never an invented reputation source.
		ability_estimates[field_id] = visible
		knowledge_sources[field_id] = visible.get("source_ids", []).duplicate(true)
		discovery_routes[field_id] = knowledge_service.suggest_discovery_routes(state, character_id, field_id)
	var traits_field: Dictionary = knowledge_service.get_visible_field(state, character_id, "traits")
	var suspected_field: Dictionary = knowledge_service.get_visible_field(state, character_id, "suspected_traits")
	var known_traits := _field_values(traits_field) if str(traits_field.get("status", "unknown")) == "confirmed" else []
	var suspected_traits: Array = []
	if str(traits_field.get("status", "unknown")) == "rumor":
		suspected_traits.append_array(_field_values(traits_field))
	for trait_value in _field_values(suspected_field):
		if not suspected_traits.has(trait_value):
			suspected_traits.append(trait_value)
	knowledge_sources["traits"] = traits_field.get("source_ids", []).duplicate(true)
	knowledge_sources["suspected_traits"] = suspected_field.get("source_ids", []).duplicate(true)
	discovery_routes["traits"] = knowledge_service.suggest_discovery_routes(state, character_id, "traits")
	discovery_routes["suspected_traits"] = knowledge_service.suggest_discovery_routes(state, character_id, "suspected_traits")
	var clan_service = TangClanServiceScript.new()
	var clan_profile: Dictionary = clan_service.get_character_clan_profile(state, data, character_id)

	var dossier := {
		"id": character_id,
		"name": str(character.get("name", "")),
		"role": str(character.get("role", "")),
		"faction_id": str(character.get("faction_id", "")),
		"relationship": _relationship_to_player(state, character),
		"stance_line": state_service.describe_visible_attitude(state, character_id),
		"ability_estimates": ability_estimates,
		"known_traits": known_traits,
		"suspected_traits": suspected_traits,
		"tang_traits_profile": tang_profile.duplicate(true),
		"tang_public_traits": (tang_profile.get("public_traits", []) as Array).duplicate(true),
		"tang_exposed_traits": (tang_profile.get("exposed_traits", []) as Array).duplicate(true),
		"tang_suspected_traits": (tang_profile.get("suspected_traits", []) as Array).duplicate(true),
		"tang_hidden_count": int(tang_profile.get("hidden_count", 0)),
		"by_category": (tang_profile.get("by_category", {}) as Dictionary).duplicate(true),
		"ai_personality": ai_personality.duplicate(true),
		"opinion_with_player": opinion_with_player.duplicate(true),
		"clan_profile": clan_profile.duplicate(true),
		"trait_knowledge": {
			"traits": traits_field.duplicate(true),
			"suspected_traits": suspected_field.duplicate(true)
		},
		"knowledge_sources": knowledge_sources,
		"visible_political_state": state_service.describe_visible_attitude(state, character_id),
		"discovery_routes": discovery_routes,
		"public_goal": str(character.get("public_goal", "")),
		"recent_memories": memories.slice(maxi(0, memories.size() - 5), memories.size()),
		"active_pressure": str(profile.get("active_pressure", "")),
		"available_interactions": profile.get("available_interactions", []).duplicate(true),
		"action_history": _action_history(state, character_id),
		"linked_fronts": profile.get("linked_fronts", []).duplicate(true),
		"linked_factions": profile.get("linked_factions", []).duplicate(true),
		"linked_events": profile.get("linked_events", []).duplicate(true),
		"linked_tasks": profile.get("linked_tasks", []).duplicate(true),
		"recent_action_marker": str(profile.get("recent_action_marker", "")),
		"summon": profile.get("summon", {}).duplicate(true),
		"summonable": bool(profile.get("summonable", false))
	}
	var is_beta110 := str(data.get("campaign_id", "")) == "anshi_beta_1_10"
	if is_beta110:
		dossier["fate"] = _project_beta110_fate(data, state, character_id)
		dossier["arc_stage"] = str(dossier["fate"].get("label", "尚无公开命运结论"))
	else:
		var arc: Dictionary = CharacterArcServiceScript.new().derive_arc(character_id, state, data)
		if arc.get("ok", false):
			dossier["arc_stage"] = str(arc.get("public_label", ""))
			dossier["arc_evidence_refs"] = arc.get("evidence_refs", []).duplicate()
	var hidden_goal_field: Dictionary = knowledge_service.get_visible_field(state, character_id, "hidden_goal")
	if str(hidden_goal_field.get("status", "unknown")) != "unknown":
		dossier["learned_hidden_goal"] = hidden_goal_field.duplicate(true)
		knowledge_sources["hidden_goal"] = hidden_goal_field.get("source_ids", []).duplicate(true)
		discovery_routes["hidden_goal"] = knowledge_service.suggest_discovery_routes(state, character_id, "hidden_goal")
	return dossier

func to_player_visible_source_person(dossier: Dictionary) -> Dictionary:
	if dossier.is_empty():
		return {}
	var character_id := str(dossier.get("id", dossier.get("character_id", ""))).strip_edges()
	var display_name := str(dossier.get("name", dossier.get("display_name", character_id))).strip_edges()
	if character_id.is_empty() or display_name.is_empty():
		return {}
	return {
		"character_id": character_id,
		"display_name": display_name,
		"public_identity": str(dossier.get("role", dossier.get("public_identity", ""))).strip_edges(),
		"portrait_path": str(dossier.get("portrait_path", "")).strip_edges(),
		"public_attitude": str(dossier.get("stance_line", dossier.get("visible_political_state", dossier.get("public_attitude", "")))).strip_edges(),
		"knowledge_reason": str(dossier.get("knowledge_reason", "公开可见")).strip_edges()
	}

func summon_npc(data: Dictionary, state, character_id: String) -> Dictionary:
	var dossier := get_dossier(data, state, character_id)
	if dossier.is_empty():
		return _fail("unknown character: " + character_id)
	if not bool(dossier.get("summonable", false)):
		return _fail("character is not summonable: " + character_id)
	if state != null:
		state.active_conversation_target_id = character_id
	var summon: Dictionary = dossier.get("summon", {})
	return {
		"ok": true,
		"npc_id": character_id,
		"npc_name": str(dossier.get("name", character_id)),
		"result_type": str(summon.get("default_result", "immediate_audience")),
		"scene_id": str(summon.get("key_scene_id", "")),
		"variants": summon.get("variants", []).duplicate(true)
	}

func format_dossier_text(data: Dictionary, state, character_id: String) -> String:
	var dossier := get_dossier(data, state, character_id)
	if dossier.is_empty():
		return "dossier missing: " + character_id
	var ability_parts: Array = []
	for field_id in ABILITY_FIELDS:
		ability_parts.append("%s=%s" % [field_id, _format_visible_field(dossier.get("ability_estimates", {}).get(field_id, {}))])
	var hidden_goal_line := ""
	if dossier.has("learned_hidden_goal"):
		hidden_goal_line = "\nlearned_hidden_goal=%s" % _format_visible_field(dossier.get("learned_hidden_goal", {}))
	return "%s | %s | faction=%s | relationship=%d\nabilities %s\nknown_traits=%s\nsuspected_traits=%s\npolitical_state=%s\npressure=%s\npublic_goal=%s%s\nmemories=%d\ninteractions=%s\nlinked_fronts=%s\nlinked_tasks=%s\ndiscovery_routes=%s" % [
		str(dossier.get("id", "")),
		str(dossier.get("role", "")),
		str(dossier.get("faction_id", "")),
		int(dossier.get("relationship", 0)),
		", ".join(ability_parts),
		", ".join(dossier.get("known_traits", [])),
		", ".join(dossier.get("suspected_traits", [])),
		str(dossier.get("visible_political_state", "")),
		str(dossier.get("active_pressure", "")),
		str(dossier.get("public_goal", "")),
		hidden_goal_line,
		dossier.get("recent_memories", []).size(),
		", ".join(dossier.get("available_interactions", [])),
		", ".join(dossier.get("linked_fronts", [])),
		", ".join(dossier.get("linked_tasks", [])),
		JSON.stringify(dossier.get("discovery_routes", {}))
	]

func _field_values(field: Dictionary) -> Array:
	var value = field.get("value")
	if value is Array:
		return value.duplicate(true)
	if value != null and str(value) != "":
		return [value]
	return []

func _format_visible_field(field: Dictionary) -> String:
	var status := str(field.get("status", "unknown"))
	if field.has("min") and field.has("max"):
		return "%s[%s-%s] confidence=%.2f sources=%s" % [status, str(field.get("min")), str(field.get("max")), float(field.get("confidence", 0.0)), ",".join(field.get("source_ids", []))]
	if field.has("value"):
		return "%s value=%s confidence=%.2f sources=%s" % [status, str(field.get("value")), float(field.get("confidence", 0.0)), ",".join(field.get("source_ids", []))]
	if field.has("text"):
		return "%s text=%s confidence=%.2f sources=%s" % [status, str(field.get("text")), float(field.get("confidence", 0.0)), ",".join(field.get("source_ids", []))]
	return status

func _find_character(data: Dictionary, character_id: String, state = null) -> Dictionary:
	var query_service = preload("res://scripts/core/character_query_service.gd").new()
	return query_service.find_character(data, state, character_id)

func _relationship_to_player(state, character: Dictionary) -> int:
	var character_id := str(character.get("id", ""))
	if state is Object and state.get("character_states") is Dictionary and state.character_states.get(character_id) is Dictionary and state.has_method("get_relationship"):
		return int(state.call("get_relationship", character_id))
	var relationships: Dictionary = character.get("relationships", {})
	return int(relationships.get("li_heng", 0))

func _stance_line(relationship: int, profile: Dictionary) -> String:
	if relationship >= 20:
		return "trusting but still rule-bound"
	if relationship <= -10:
		return "skeptical and likely to resist"
	if str(profile.get("response_profile", "")).contains("bargain"):
		return "open to negotiation"
	return "watchful"

func _action_history(state, character_id: String) -> Array:
	var history: Array = []
	if state == null:
		return history
	var feed: Array = []
	if state is Dictionary:
		feed = state.get("npc_action_feed", []) if state.get("npc_action_feed") is Array else []
	elif state.get("npc_action_feed") is Array:
		feed = state.get("npc_action_feed")

	for action in feed:
		if str(action.get("character_id", "")) == character_id:
			history.append(action.duplicate(true))

	var records: Array = []
	if state is Dictionary:
		records = state.get("dialogue_action_records", []) if state.get("dialogue_action_records") is Array else []
	elif state.get("dialogue_action_records") is Array:
		records = state.get("dialogue_action_records")

	for record in records:
		if str(record.get("executor_id", "")) == character_id or str(record.get("target_id", "")) == character_id:
			history.append(record.duplicate(true))
	return history

func _project_beta110_fate(data: Dictionary, state, character_id: String) -> Dictionary:
	var character_states_value: Variant = state.get("character_states") if state != null else null
	var character_states: Dictionary = character_states_value if character_states_value is Dictionary else {}
	var character_state: Dictionary = character_states.get(character_id, {}) if character_states.get(character_id, {}) is Dictionary else {}
	var raw_refs: Variant = character_state.get("fate_causal_refs", [])
	var refs: Array = []
	if raw_refs is Array:
		for raw_ref in raw_refs as Array:
			if raw_ref is Dictionary and str((raw_ref as Dictionary).get("kind", "")) == "character_fate" and str((raw_ref as Dictionary).get("character_id", character_id)) == character_id:
				refs.append((raw_ref as Dictionary).duplicate(true))
	refs.sort_custom(Callable(self, "_fate_transition_less"))
	var latest: Dictionary = refs[-1] if not refs.is_empty() else {}
	var category := str(latest.get("aftermath_category", "constrained"))
	if category not in ["gained_position", "constrained", "paid_cost"]:
		category = "constrained"
	var label := _safe_fate_label(latest.get("public_label", ""), "当前走向未明")
	var reason_result: Dictionary = CharacterKnowledgeServiceScript.new().project_public_fate_reasons(state, data, character_id, latest)
	var reasons: Array = reason_result.get("reasons", []) if reason_result.get("reasons", []) is Array else [{"summary": "当前依据不足，需通过调查或复盘确认"}]
	var transitions: Array = []
	var start_index := maxi(0, refs.size() - 5)
	for index in range(start_index, refs.size()):
		var ref: Dictionary = refs[index] as Dictionary
		var day := int(ref.get("day", 0))
		var transition_label := _safe_fate_label(ref.get("public_label", ""), "当前走向未明")
		if day < 1 or day > 90 or transition_label.is_empty():
			continue
		transitions.append({"day": day, "label": transition_label})
	var current_day := int(state.current_day) if state != null else 0
	return {
		"label": label,
		"phase_label": "最终命运" if current_day >= 90 else "当前走向",
		"category": category,
		"reasons": reasons.slice(0, 3).duplicate(true),
		"transitions": transitions.slice(0, 5).duplicate(true)
	}

func _safe_fate_label(value: Variant, fallback: String) -> String:
	if typeof(value) != TYPE_STRING:
		return fallback
	var label := str(value).strip_edges()
	if label.is_empty() or label.length() > 128 or label.contains("<") or label.contains(">"):
		return fallback
	return label

func _fate_transition_less(left: Dictionary, right: Dictionary) -> bool:
	var left_day := int(left.get("day", 0))
	var right_day := int(right.get("day", 0))
	if left_day != right_day:
		return left_day < right_day
	return str(left.get("id", "")) < str(right.get("id", ""))

func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
