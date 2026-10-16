extends RefCounted

class_name AccountabilityVerdictEffectService

const FactionAgendaServiceScript = preload("res://scripts/core/faction_agenda_service.gd")
const StructuredMemoryServiceScript = preload("res://scripts/core/structured_memory_service.gd")
const RouteNetworkServiceScript = preload("res://scripts/core/route_network_service.gd")
const LocalNodeServiceScript = preload("res://scripts/core/local_node_service.gd")

const VERDICTS := ["dismiss", "reform", "forced_removal"]

func apply(state, data: Dictionary, case_id: String, verdict_id: String, transaction_id: String) -> Dictionary:
	if state == null:
		return _fail("missing state", "missing_state")
	if str(data.get("campaign_id", "")) != "anshi_beta_1_10":
		return {"ok": true, "code": "no_op", "refs": [], "effects": []}
	if case_id.is_empty() or verdict_id not in VERDICTS or transaction_id.is_empty():
		return _fail("invalid verdict effect identity", "invalid_effect_identity")
	var stable_id := "accountability_verdict|%s" % transaction_id
	if _has_chronicle_ref(state, stable_id):
		return {"ok": true, "code": "no_op", "result_ref": stable_id, "refs": [{"kind": "accountability_verdict", "id": stable_id}], "effects": []}
	var effect_entry := _find_case_effect(data, case_id)
	if effect_entry.is_empty():
		return _fail("BETA 1.10 verdict effect is missing: " + case_id, "missing_effect")
	var verdicts: Dictionary = effect_entry.get("verdict_effects", {}) if effect_entry.get("verdict_effects", {}) is Dictionary else {}
	var effects: Dictionary = verdicts.get(verdict_id, {}) if verdicts.get(verdict_id, {}) is Dictionary else {}
	if effects.is_empty():
		return _fail("BETA 1.10 verdict effect is missing: " + case_id + "/" + verdict_id, "missing_effect")

	for raw_resource in effects.get("resource_delta", {}).keys() if effects.get("resource_delta", {}) is Dictionary else []:
		var settled: Dictionary = state.apply_resource_delta(str(raw_resource), int((effects.get("resource_delta", {}) as Dictionary).get(raw_resource, 0)), "rule:accountability:" + case_id + ":" + verdict_id)
		if not settled.get("ok", false): return settled
	var faction_service := FactionAgendaServiceScript.new()
	for raw_reaction in effects.get("faction_reactions", []) if effects.get("faction_reactions", []) is Array else []:
		if not raw_reaction is Dictionary:
			return _fail("invalid faction reaction effect", "invalid_effect")
		var reaction: Dictionary = (raw_reaction as Dictionary).duplicate(true)
		var faction_id := str(reaction.get("faction_id", ""))
		if faction_id.is_empty(): return _fail("faction reaction has no faction", "invalid_effect")
		reaction["reaction_type"] = str(reaction.get("reaction_type", "accountability_verdict"))
		reaction["summary"] = str(reaction.get("summary", "accountability verdict reaction"))
		var faction_result := faction_service.apply_reaction(state, data, faction_id, reaction)
		if not bool(faction_result.get("ok", false)): return faction_result
	for raw_relationship in effects.get("relationship_effects", []) if effects.get("relationship_effects", []) is Array else []:
		if not raw_relationship is Dictionary: return _fail("invalid relationship effect", "invalid_effect")
		var relationship: Dictionary = raw_relationship
		var character_id := str(relationship.get("character_id", ""))
		if character_id.is_empty(): return _fail("relationship effect has no character", "invalid_effect")
		state.apply_relationship_delta(character_id, int(relationship.get("delta", 0)))
	var memory_service := StructuredMemoryServiceScript.new()
	for raw_memory in effects.get("memories", []) if effects.get("memories", []) is Array else []:
		if not raw_memory is Dictionary: return _fail("invalid memory effect", "invalid_effect")
		var memory: Dictionary = raw_memory as Dictionary
		var memory_id := str(memory.get("memory_id", memory.get("id", "")))
		var memory_result := memory_service.create_memory(state, {
			"id": memory_id,
			"memory_type": "accountability_verdict",
			"source_id": "li_heng",
			"target_id": str(memory.get("character_id", "")),
			"summary": str(memory.get("summary", "")),
			"visibility": "court",
			"tags": ["accountability_verdict", case_id, verdict_id]
		})
		if not bool(memory_result.get("ok", false)) and not str(memory_result.get("error", "")).begins_with("duplicate memory id"):
			return memory_result
	for raw_route in effects.get("route_effects", []) if effects.get("route_effects", []) is Array else []:
		if not raw_route is Dictionary: return _fail("invalid route effect", "invalid_effect")
		var route: Dictionary = raw_route
		var route_effects := _field_effects(route.get("effects", {}))
		var route_result := RouteNetworkServiceScript.new().apply_route_effects(state, str(route.get("route_id", "")), route_effects, {"reason": "accountability verdict|%s" % case_id})
		if not bool(route_result.get("ok", false)): return route_result
	for raw_node in effects.get("node_effects", []) if effects.get("node_effects", []) is Array else []:
		if not raw_node is Dictionary: return _fail("invalid node effect", "invalid_effect")
		var node: Dictionary = raw_node
		var node_result := LocalNodeServiceScript.new().apply_order_effects(state, str(node.get("node_id", "")), _field_effects(node.get("effects", {})), {"reason": "accountability verdict|%s" % case_id})
		if not bool(node_result.get("ok", false)): return node_result
	var debt: Variant = effects.get("political_debt", null)
	if debt is Dictionary:
		var debt_record: Dictionary = (debt as Dictionary).duplicate(true)
		var debt_id := str(debt_record.get("debt_id", ""))
		if not debt_id.is_empty():
			debt_record["created_day"] = int(state.current_day)
			debt_record["source_transaction_id"] = transaction_id
			debt_record["status"] = "active"
			debt_record["effects_applied"] = true
			var next_debts: Dictionary = state.political_debts.duplicate(true)
			if not next_debts.has(debt_id): next_debts[debt_id] = debt_record
			state.political_debts = next_debts
	state.chronicle_causal_references.append({
		"kind": "accountability_verdict",
		"id": stable_id,
		"case_id": case_id,
		"verdict_id": verdict_id,
		"transaction_id": transaction_id,
		"day": int(state.current_day),
		"source_ids": [case_id]
	})
	return {"ok": true, "code": "verdict_effects_applied", "result_ref": stable_id, "refs": [{"kind": "accountability_verdict", "id": stable_id}], "effects": effects.duplicate(true)}

func _find_case_effect(data: Dictionary, case_id: String) -> Dictionary:
	var container: Variant = data.get("accountability_effects", {})
	var entries: Variant = container.get("case_effects", []) if container is Dictionary else data.get("beta110_accountability_effects", [])
	for raw_entry in entries if entries is Array else []:
		if raw_entry is Dictionary and str((raw_entry as Dictionary).get("case_id", "")) == case_id:
			return (raw_entry as Dictionary).duplicate(true)
	return {}

func _field_effects(value: Variant) -> Array:
	var result: Array = []
	if value is Dictionary:
		for field in (value as Dictionary).keys(): result.append({"field": str(field), "value": int((value as Dictionary).get(field, 0))})
	elif value is Array:
		for effect in value:
			if effect is Dictionary: result.append((effect as Dictionary).duplicate(true))
	return result

func _has_chronicle_ref(state, stable_id: String) -> bool:
	for raw_ref in state.chronicle_causal_references if state.chronicle_causal_references is Array else []:
		if raw_ref is Dictionary and str((raw_ref as Dictionary).get("id", "")) == stable_id: return true
	return false

func _fail(message: String, code: String) -> Dictionary:
	return {"ok": false, "code": code, "error": message, "message": message}
