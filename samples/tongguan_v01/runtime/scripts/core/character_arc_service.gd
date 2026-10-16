extends RefCounted

class_name CharacterArcService

func derive_arc(character_id: String, state, data: Dictionary) -> Dictionary:
	var raw_flags: Variant = state.get("flags") if state != null else null
	var flags: Dictionary = raw_flags if raw_flags is Dictionary else {}
	var campaign_id := str(flags.get("campaign_id", ""))
	if campaign_id.is_empty():
		campaign_id = str(data.get("campaign_id", ""))
	if campaign_id == "anshi_beta_1_10" or campaign_id.begins_with("anshi_beta_1_1") or data.has("character_arcs_beta_1_10") or data.has("beta110_character_arcs"):
		return evaluate_fate(character_id, state, data)
	if campaign_id in ["anshi_beta_1_08", "anshi_beta_1_09"]:
		return derive_fate(character_id, state, data)
	var arcs: Dictionary = data.get("character_arcs_beta_1_0", {})
	var arc: Dictionary = arcs.get(character_id, {})
	var stages: Array = arc.get("stages", [])
	if stages.is_empty():
		stages = [
			{"stage_id":"foundation","day_min":1,"stance":"观望","event_refs":[]},
			{"stage_id":"power_formation","day_min":31,"stance":"提出条件","event_refs":[]},
			{"stage_id":"alliance_cost","day_min":61,"stance":"最终取向","event_refs":[]}
		]
	var selected: Dictionary = {}
	for raw_stage in stages:
		if raw_stage is Dictionary and int(state.current_day) >= int(raw_stage.get("day_min", 1)):
			selected = raw_stage
	return {"ok": not selected.is_empty(), "character_id": character_id, "stage_id": str(selected.get("stage_id", "")), "public_label": str(selected.get("stance", "")), "evidence_refs": selected.get("event_refs", []).duplicate()}

func evaluate_fate(character_id: String, state, data: Dictionary) -> Dictionary:
	if state == null:
		return _fail("invalid_state", "character fate evaluation requires state")
	var data_campaign_id := str(data.get("campaign_id", ""))
	var flags_value: Variant = _state_value(state, "flags", {})
	var flags: Dictionary = flags_value if flags_value is Dictionary else {}
	var state_campaign_id := str(flags.get("campaign_id", ""))
	var campaign_id := state_campaign_id if not state_campaign_id.is_empty() else data_campaign_id
	var has_beta110_arcs := data.has("character_arcs_beta_1_10") or data.has("beta110_character_arcs")
	if not has_beta110_arcs and not campaign_id.begins_with("anshi_beta_1_1") and campaign_id != "anshi_beta_1_10":
		return _fail("unsupported_campaign", "character fate evaluation is only available for BETA 1.10+")
	var arcs_root: Variant = data.get("character_arcs_beta_1_10", null)
	if not arcs_root is Dictionary:
		var wrapper: Variant = data.get("beta110_character_arcs", {})
		if wrapper is Dictionary:
			arcs_root = (wrapper as Dictionary).get("arcs", {})
	if not arcs_root is Dictionary:
		return _fail("invalid_character_rules", "BETA 1.10 character fate rules are missing")
	var raw_rules: Variant = (arcs_root as Dictionary).get(character_id, null)
	if not raw_rules is Array:
		return _fail("missing_character_rules", "character fate rules are missing for " + character_id)
	var current_day := int(_state_value(state, "current_day", 0))
	var baseline: Dictionary = {}
	var candidate_records: Array = []
	for raw_rule in raw_rules as Array:
		if not raw_rule is Dictionary:
			return _fail("invalid_character_rule", "character fate rule must be a dictionary")
		var rule: Dictionary = raw_rule as Dictionary
		var rule_id := str(rule.get("arc_id", ""))
		if rule_id.is_empty():
			return _fail("invalid_character_rule", "character fate rule is missing arc_id")
		if bool(rule.get("is_baseline", false)):
			if not baseline.is_empty():
				return _fail("multiple_baselines", "character fate rules have more than one baseline")
			baseline = rule.duplicate(true)
			continue
		var day_min := int(rule.get("day_min", 1))
		var day_max := int(rule.get("day_max", 90))
		if current_day < day_min or current_day > day_max:
			continue
		var predicate_result := _rule_predicates_match(rule, state, character_id, current_day)
		if not bool(predicate_result.get("ok", false)):
			return predicate_result
		if not bool(predicate_result.get("matched", false)):
			continue
		candidate_records.append({
			"rule": rule.duplicate(true),
			"severity": _rule_severity(rule)
		})
	if candidate_records.is_empty():
		if baseline.is_empty():
			return _fail("no_eligible_fate", "no eligible character fate rule or explicit baseline exists")
		return _public_fate_result(character_id, baseline, current_day)
	candidate_records.sort_custom(Callable(self, "_sort_fate_candidates"))
	var selected_record: Dictionary = candidate_records[0] as Dictionary
	return _public_fate_result(character_id, selected_record.get("rule", {}) as Dictionary, current_day)

func _public_fate_result(character_id: String, rule: Dictionary, day: int) -> Dictionary:
	var arc_id := str(rule.get("arc_id", ""))
	var reason_refs: Array = []
	var raw_reason_refs: Variant = rule.get("reason_refs", [])
	if raw_reason_refs is Array:
		for raw_reason_ref in raw_reason_refs as Array:
			if raw_reason_ref is Dictionary:
				var reason_ref: Dictionary = raw_reason_ref as Dictionary
				reason_refs.append({"kind": str(reason_ref.get("kind", "")), "id": str(reason_ref.get("id", ""))})
	return {
		"ok": true,
		"code": "evaluated",
		"character_id": character_id,
		"arc_id": arc_id,
		"stable_ref": "fate|%s|%s" % [character_id, arc_id],
		"day": day,
		"result_fate_status": str(rule.get("result_fate_status", "")),
		"public_label": str(rule.get("public_label", "")),
		"aftermath_category": str(rule.get("aftermath_category", "")),
		"primary_public_reason": str(rule.get("primary_public_reason", "")),
		"reason_refs": reason_refs
	}

func _rule_predicates_match(rule: Dictionary, state, character_id: String, current_day: int) -> Dictionary:
	var all_result := _predicate_array_matches(rule.get("all", []), state, character_id, current_day, true)
	if not bool(all_result.get("ok", false)) or not bool(all_result.get("matched", false)):
		return all_result
	var any_value: Variant = rule.get("any", [])
	if not any_value is Array:
		return _fail("invalid_character_rule", "any predicates must be an array")
	if not (any_value as Array).is_empty():
		var any_result := _predicate_array_matches(any_value, state, character_id, current_day, false)
		if not bool(any_result.get("ok", false)) or not bool(any_result.get("matched", false)):
			return any_result
	var none_value: Variant = rule.get("none", [])
	if not none_value is Array:
		return _fail("invalid_character_rule", "none predicates must be an array")
	for raw_predicate in none_value as Array:
		var predicate_result := _predicate_matches(raw_predicate, state, character_id, current_day)
		if not bool(predicate_result.get("ok", false)):
			return predicate_result
		if bool(predicate_result.get("matched", false)):
			return {"ok": true, "matched": false}
	return {"ok": true, "matched": true}

func _predicate_array_matches(value: Variant, state, character_id: String, current_day: int, require_all: bool) -> Dictionary:
	if not value is Array:
		return _fail("invalid_character_rule", "predicate group must be an array")
	if (value as Array).is_empty():
		return {"ok": true, "matched": true if require_all else false}
	for raw_predicate in value as Array:
		var predicate_result := _predicate_matches(raw_predicate, state, character_id, current_day)
		if not bool(predicate_result.get("ok", false)):
			return predicate_result
		var matched := bool(predicate_result.get("matched", false))
		if require_all and not matched:
			return {"ok": true, "matched": false}
		if not require_all and matched:
			return {"ok": true, "matched": true}
	return {"ok": true, "matched": require_all}

func _predicate_matches(raw_predicate: Variant, state, character_id: String, current_day: int) -> Dictionary:
	if not raw_predicate is Dictionary:
		return _fail("invalid_character_rule", "predicate must be a dictionary")
	var predicate: Dictionary = raw_predicate as Dictionary
	var kind := str(predicate.get("kind", ""))
	if kind == "route":
		var route_value: Variant = predicate.get("route_id", null)
		if typeof(route_value) != TYPE_STRING or str(route_value).strip_edges().is_empty():
			return _fail("invalid_predicate", "route predicate requires route_id")
		var route_id := str(route_value)
		var flags_value: Variant = _state_value(state, "flags", {})
		var flags: Dictionary = flags_value if flags_value is Dictionary else {}
		for key in ["beta110_route_id", "beta110_public_route_id", "route_id", "public_route_id"]:
			if str(flags.get(key, "")) == route_id and not route_id.is_empty():
				return {"ok": true, "matched": true}
		return {"ok": true, "matched": false}
	if kind == "case":
		var case_value: Variant = predicate.get("case_id", null)
		if typeof(case_value) != TYPE_STRING or str(case_value).strip_edges().is_empty():
			return _fail("invalid_predicate", "case predicate requires case_id")
		var case_id := str(case_value)
		var cases_value: Variant = _state_value(state, "accountability_cases", {})
		var cases: Dictionary = cases_value if cases_value is Dictionary else {}
		var case_record: Dictionary = cases.get(case_id, {}) if cases.get(case_id, {}) is Dictionary else {}
		var decision: Dictionary = case_record.get("decision", {}) if case_record.get("decision", {}) is Dictionary else {}
		var verdict_id := str(decision.get("verdict_id", case_record.get("verdict_id", "")))
		var verdict_ids: Variant = predicate.get("verdict_ids", null)
		if not verdict_ids is Array or (verdict_ids as Array).is_empty():
			return _fail("invalid_predicate", "case verdict_ids must be a non-empty array")
		for verdict_id_value in verdict_ids as Array:
			if typeof(verdict_id_value) != TYPE_STRING or str(verdict_id_value).strip_edges().is_empty():
				return _fail("invalid_predicate", "case verdict_ids must contain non-empty strings")
		return {"ok": true, "matched": not verdict_id.is_empty() and (verdict_ids as Array).has(verdict_id)}
	if kind == "office":
		var office_value: Variant = predicate.get("office_id", null)
		if typeof(office_value) != TYPE_STRING or str(office_value).strip_edges().is_empty():
			return _fail("invalid_predicate", "office predicate requires office_id")
		var office_id := str(office_value)
		var status := str(predicate.get("status", "active"))
		if status == "active":
			return {"ok": true, "matched": _has_active_office(state, character_id, office_id)}
		if status == "removed":
			return {"ok": true, "matched": _has_removed_office(state, character_id, office_id)}
		return _fail("invalid_predicate", "office predicate status is unsupported")
	if kind == "debt":
		var debt_value: Variant = predicate.get("debt_id", null)
		if typeof(debt_value) != TYPE_STRING or str(debt_value).strip_edges().is_empty():
			return _fail("invalid_predicate", "debt predicate requires debt_id")
		var debt_id := str(debt_value)
		var debt_status := str(predicate.get("status", ""))
		if not ["open", "resolved"].has(debt_status):
			return _fail("invalid_predicate", "debt predicate status is unsupported")
		var debts_value: Variant = _state_value(state, "political_debts", {})
		var debts: Dictionary = debts_value if debts_value is Dictionary else {}
		var debt_record: Dictionary = debts.get(debt_id, {}) if debts.get(debt_id, {}) is Dictionary else {}
		return {"ok": true, "matched": _record_status_matches(debt_record, debt_status)}
	if kind == "memory":
		var memory_value: Variant = predicate.get("memory_id", null)
		if typeof(memory_value) != TYPE_STRING or str(memory_value).strip_edges().is_empty() or str(predicate.get("status", "")) != "confirmed":
			return _fail("invalid_predicate", "memory predicate requires a confirmed memory_id")
		return {"ok": true, "matched": _memory_status_matches(state, str(memory_value), "confirmed", character_id)}
	if kind == "obligation":
		var obligation_value: Variant = predicate.get("target_id", null)
		var obligation_status := str(predicate.get("status", ""))
		if typeof(obligation_value) != TYPE_STRING or str(obligation_value).strip_edges().is_empty() or not ["fulfilled", "breached", "pending"].has(obligation_status):
			return _fail("invalid_predicate", "obligation predicate requires a valid target_id and status")
		return {"ok": true, "matched": _obligation_status_matches(state, str(obligation_value), obligation_status, character_id)}
	if kind == "day":
		var min_value: Variant = predicate.get("min_day", predicate.get("day_min", null))
		var max_value: Variant = predicate.get("max_day", predicate.get("day_max", null))
		if min_value == null and max_value == null:
			return _fail("invalid_predicate", "day predicate requires min_day or max_day")
		var min_day := int(min_value) if min_value != null else 1
		var max_day := int(max_value) if max_value != null else 90
		if min_day < 1 or max_day > 90 or min_day > max_day:
			return _fail("invalid_predicate", "day predicate range is invalid")
		return {"ok": true, "matched": current_day >= min_day and current_day <= max_day}
	return _fail("unsupported_predicate", "unsupported character fate predicate: " + kind)

func _rule_severity(rule: Dictionary) -> int:
	var severity := 0
	for group_name in ["all", "any"]:
		var predicates: Variant = rule.get(group_name, [])
		if not predicates is Array:
			continue
		for raw_predicate in predicates as Array:
			if not raw_predicate is Dictionary:
				continue
			var predicate: Dictionary = raw_predicate as Dictionary
			var kind := str(predicate.get("kind", ""))
			if kind == "case" and (predicate.get("verdict_ids", []) as Array if predicate.get("verdict_ids", []) is Array else []).has("forced_removal"):
				severity = maxi(severity, 3)
			if kind == "office" and str(predicate.get("status", "")) == "removed":
				severity = maxi(severity, 2)
	return severity

func _sort_fate_candidates(left: Dictionary, right: Dictionary) -> bool:
	var left_severity := int(left.get("severity", 0))
	var right_severity := int(right.get("severity", 0))
	if left_severity != right_severity:
		return left_severity > right_severity
	var left_rule: Dictionary = left.get("rule", {}) if left.get("rule", {}) is Dictionary else {}
	var right_rule: Dictionary = right.get("rule", {}) if right.get("rule", {}) is Dictionary else {}
	var left_priority := int(left_rule.get("priority", 0))
	var right_priority := int(right_rule.get("priority", 0))
	if left_priority != right_priority:
		return left_priority > right_priority
	return str(left_rule.get("arc_id", "")) < str(right_rule.get("arc_id", ""))

func _state_value(state, key: String, fallback: Variant) -> Variant:
	if state is Dictionary:
		return (state as Dictionary).get(key, fallback)
	if state != null:
		var value: Variant = state.get(key)
		return fallback if value == null else value
	return fallback

func _has_active_office(state, character_id: String, office_id: String) -> bool:
	var terms_value: Variant = _state_value(state, "office_terms", {})
	if terms_value is Dictionary:
		for raw_term in (terms_value as Dictionary).values():
			if raw_term is Dictionary and str((raw_term as Dictionary).get("holder_id", "")) == character_id and str((raw_term as Dictionary).get("office_id", "")) == office_id and int((raw_term as Dictionary).get("end_day", -1)) < 0:
				return true
	var offices_value: Variant = _state_value(state, "office_state", {})
	if offices_value is Dictionary:
		var office: Dictionary = (offices_value as Dictionary).get(office_id, {}) if (offices_value as Dictionary).get(office_id, {}) is Dictionary else {}
		return str(office.get("holder_id", "")) == character_id and str(office.get("status", "appointed")) == "appointed"
	return false

func _has_removed_office(state, character_id: String, office_id: String) -> bool:
	var terms_value: Variant = _state_value(state, "office_terms", {})
	if terms_value is Dictionary:
		for raw_term in (terms_value as Dictionary).values():
			if raw_term is Dictionary and str((raw_term as Dictionary).get("holder_id", "")) == character_id and str((raw_term as Dictionary).get("office_id", "")) == office_id and int((raw_term as Dictionary).get("end_day", -1)) >= 0:
				return true
	var history_value: Variant = _state_value(state, "office_history", [])
	if history_value is Array:
		for raw_history in history_value as Array:
			if raw_history is Dictionary and str((raw_history as Dictionary).get("office_id", "")) == office_id and str((raw_history as Dictionary).get("previous_holder_id", (raw_history as Dictionary).get("holder_id", ""))) == character_id:
				return true
	return false

func _record_status_matches(record: Dictionary, expected_status: String) -> bool:
	if record.is_empty():
		return false
	var actual_status := str(record.get("status", record.get("state", "")))
	return actual_status == expected_status

func _memory_status_matches(state, memory_id: String, expected_status: String, character_id: String) -> bool:
	var memories_value: Variant = _state_value(state, "structured_memories", [])
	if not memories_value is Array:
		return false
	for raw_memory in memories_value as Array:
		if not raw_memory is Dictionary:
			continue
		var memory: Dictionary = raw_memory as Dictionary
		if str(memory.get("id", memory.get("memory_id", ""))) != memory_id:
			continue
		var target_id := str(memory.get("target_id", ""))
		if not target_id.is_empty() and target_id != character_id:
			continue
		var actual_status := str(memory.get("status", memory.get("confirmation_status", "")))
		if actual_status.is_empty() and expected_status == "confirmed":
			return true
		return actual_status == expected_status
	return false

func _obligation_status_matches(state, obligation_id: String, expected_status: String, character_id: String) -> bool:
	var obligations_value: Variant = _state_value(state, "obligation_ledger", [])
	if not obligations_value is Array:
		return false
	for raw_obligation in obligations_value as Array:
		if not raw_obligation is Dictionary:
			continue
		var obligation: Dictionary = raw_obligation as Dictionary
		var stable_id := str(obligation.get("id", obligation.get("obligation_id", obligation.get("template_id", ""))))
		var template_id := str(obligation.get("template_id", obligation.get("ledger_template_id", "")))
		if stable_id != obligation_id and template_id != obligation_id:
			continue
		var target_id := str(obligation.get("target_id", ""))
		if not target_id.is_empty() and target_id != character_id:
			continue
		return str(obligation.get("status", "")) == expected_status
	return false

func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "error": message}

func reconcile_character(state, data: Dictionary, character_id: String, day: int) -> Dictionary:
	var aggregate: Dictionary = reconcile_characters(state, data, [character_id], day)
	if not bool(aggregate.get("ok", false)):
		return aggregate
	var results: Array = aggregate.get("results", []) if aggregate.get("results", []) is Array else []
	if results.is_empty() or not results[0] is Dictionary:
		return _fail("reconcile_empty", "character fate reconciliation produced no result")
	var result: Dictionary = (results[0] as Dictionary).duplicate(true)
	result["character_ids"] = (aggregate.get("character_ids", []) as Array).duplicate(true)
	result["results"] = results.duplicate(true)
	return result

func reconcile_characters(state, data: Dictionary, character_ids: Array, day: int) -> Dictionary:
	if state == null:
		return _fail("invalid_state", "character fate reconciliation requires state")
	var normalized_ids: Array = []
	for raw_character_id in character_ids:
		var character_id := str(raw_character_id).strip_edges()
		if character_id.is_empty() or normalized_ids.has(character_id):
			continue
		normalized_ids.append(character_id)
	normalized_ids.sort()
	if normalized_ids.is_empty():
		return {"ok": true, "code": "no_op", "changed": false, "character_ids": [], "results": [], "refs": []}
	var pending: Array = []
	for character_id in normalized_ids:
		var evaluation: Dictionary = evaluate_fate(character_id, state, data)
		if not bool(evaluation.get("ok", false)):
			return evaluation
		var character_states_value: Variant = _state_value(state, "character_states", {})
		var character_states: Dictionary = character_states_value if character_states_value is Dictionary else {}
		if not character_states.has(character_id) or not character_states.get(character_id, {}) is Dictionary:
			return _fail("missing_character_state", "character state is missing for " + character_id)
		pending.append({"character_id": character_id, "evaluation": evaluation.duplicate(true)})
	var next_character_states_value: Variant = _state_value(state, "character_states", {})
	var next_character_states: Dictionary = next_character_states_value.duplicate(true) if next_character_states_value is Dictionary else {}
	var next_chronicle_value: Variant = _state_value(state, "chronicle_causal_references", [])
	var next_chronicle: Array = next_chronicle_value.duplicate(true) if next_chronicle_value is Array else []
	var results: Array = []
	var refs: Array = []
	var changed_any := false
	for raw_pending in pending:
		var pending_record: Dictionary = raw_pending as Dictionary
		var character_id := str(pending_record.get("character_id", ""))
		var evaluation: Dictionary = pending_record.get("evaluation", {}) as Dictionary
		var character_state: Dictionary = next_character_states.get(character_id, {}).duplicate(true)
		var fate_refs_value: Variant = character_state.get("fate_causal_refs", [])
		var fate_refs: Array = fate_refs_value.duplicate(true) if fate_refs_value is Array else []
		var stable_ref := str(evaluation.get("stable_ref", ""))
		var current_ref := _latest_character_fate_ref(fate_refs)
		var has_existing_ref := _has_character_fate_ref(fate_refs, stable_ref)
		var changed := false
		var fate_record := {
			"kind": "character_fate",
			"id": stable_ref,
			"character_id": character_id,
			"arc_id": str(evaluation.get("arc_id", "")),
			"day": clampi(day, 1, 90),
			"result_fate_status": str(evaluation.get("result_fate_status", "")),
			"public_label": str(evaluation.get("public_label", "")),
			"aftermath_category": str(evaluation.get("aftermath_category", "")),
			"primary_public_reason": str(evaluation.get("primary_public_reason", "")),
			"reason_refs": (evaluation.get("reason_refs", []) as Array).duplicate(true)
		}
		if not has_existing_ref and not stable_ref.is_empty():
			fate_refs.append(fate_record.duplicate(true))
			changed = true
			if not _chronicle_has_character_fate(next_chronicle, stable_ref):
				next_chronicle.append({
					"kind": "character_fate",
					"id": stable_ref,
					"character_id": character_id,
					"arc_id": str(evaluation.get("arc_id", "")),
					"day": clampi(day, 1, 90),
					"result_fate_status": str(evaluation.get("result_fate_status", "")),
					"reason_refs": (evaluation.get("reason_refs", []) as Array).duplicate(true)
				})
				refs.append({"kind": "character_fate", "id": stable_ref, "character_id": character_id, "arc_id": str(evaluation.get("arc_id", ""))})
		elif has_existing_ref and not stable_ref.is_empty() and not _chronicle_has_character_fate(next_chronicle, stable_ref):
			next_chronicle.append({
				"kind": "character_fate",
				"id": stable_ref,
				"character_id": character_id,
				"arc_id": str(evaluation.get("arc_id", "")),
				"day": clampi(day, 1, 90),
				"result_fate_status": str(evaluation.get("result_fate_status", "")),
				"reason_refs": (evaluation.get("reason_refs", []) as Array).duplicate(true)
			})
			refs.append({"kind": "character_fate", "id": stable_ref, "character_id": character_id, "arc_id": str(evaluation.get("arc_id", ""))})
			changed = true
		var normalized_fate_refs := _normalize_reconciled_fate_refs(fate_refs)
		if normalized_fate_refs != fate_refs:
			changed = true
		character_state["fate_causal_refs"] = normalized_fate_refs
		if str(character_state.get("status", "")) != str(evaluation.get("result_fate_status", "")):
			character_state["status"] = str(evaluation.get("result_fate_status", ""))
			changed = true
		if changed:
			next_character_states[character_id] = character_state
			changed_any = true
		results.append({
				"ok": true,
				"code": "changed" if changed else "unchanged",
				"changed": changed,
				"character_id": character_id,
				"stable_ref": stable_ref,
				"current_ref": current_ref,
				"fate": fate_record.duplicate(true)
			})
	if changed_any:
		if state is Dictionary:
			(state as Dictionary)["character_states"] = next_character_states
			(state as Dictionary)["chronicle_causal_references"] = next_chronicle
		else:
			state.character_states = next_character_states
			state.chronicle_causal_references = next_chronicle
	return {
		"ok": true,
		"code": "settled" if changed_any else "no_op",
		"changed": changed_any,
		"character_ids": normalized_ids.duplicate(true),
		"results": results,
		"refs": refs
	}

func supported_character_ids(data: Dictionary, candidates: Array) -> Array:
	var arcs_value: Variant = data.get("character_arcs_beta_1_10", {})
	var arcs: Dictionary = arcs_value if arcs_value is Dictionary else {}
	var supported: Array = []
	for raw_character_id in candidates:
		var character_id := str(raw_character_id).strip_edges()
		if not character_id.is_empty() and arcs.has(character_id) and not supported.has(character_id):
			supported.append(character_id)
	supported.sort()
	return supported

func _latest_character_fate_ref(fate_refs: Array) -> String:
	var latest_id := ""
	var latest_day := -1
	for raw_ref in fate_refs:
		if not raw_ref is Dictionary or str((raw_ref as Dictionary).get("kind", "")) != "character_fate":
			continue
		var ref: Dictionary = raw_ref as Dictionary
		var ref_day := int(ref.get("day", -1))
		var ref_id := str(ref.get("id", ""))
		if ref_day > latest_day or (ref_day == latest_day and ref_id > latest_id):
			latest_day = ref_day
			latest_id = ref_id
	return latest_id

func _has_character_fate_ref(fate_refs: Array, stable_ref: String) -> bool:
	if stable_ref.is_empty():
		return false
	for raw_ref in fate_refs:
		if raw_ref is Dictionary and str((raw_ref as Dictionary).get("kind", "")) == "character_fate" and str((raw_ref as Dictionary).get("id", "")) == stable_ref:
			return true
	return false

func _chronicle_has_character_fate(chronicle: Array, stable_ref: String) -> bool:
	for raw_ref in chronicle:
		if raw_ref is Dictionary and str((raw_ref as Dictionary).get("kind", "")) == "character_fate" and str((raw_ref as Dictionary).get("id", "")) == stable_ref:
			return true
	return false

func _normalize_reconciled_fate_refs(value: Array) -> Array:
	var normalized: Array = []
	var seen: Dictionary = {}
	for raw_ref in value:
		if not raw_ref is Dictionary:
			continue
		var ref: Dictionary = raw_ref as Dictionary
		if str(ref.get("kind", "")) != "character_fate":
			continue
		var ref_id := str(ref.get("id", ""))
		var character_id := str(ref.get("character_id", ""))
		var arc_id := str(ref.get("arc_id", ""))
		if ref_id.is_empty() or character_id.is_empty() or arc_id.is_empty():
			continue
		var identity := ref_id + "|" + character_id + "|" + arc_id
		if seen.has(identity):
			continue
		seen[identity] = true
		normalized.append(ref.duplicate(true))
	normalized.sort_custom(Callable(self, "_sort_reconciled_fate_refs"))
	if normalized.size() > 5:
		normalized = normalized.slice(normalized.size() - 5, normalized.size())
	return normalized

func _sort_reconciled_fate_refs(left: Dictionary, right: Dictionary) -> bool:
	var left_day := int(left.get("day", 0))
	var right_day := int(right.get("day", 0))
	if left_day != right_day:
		return left_day < right_day
	return str(left.get("id", "")) < str(right.get("id", ""))

func derive_fate(character_id: String, state, data: Dictionary) -> Dictionary:
	var routes: Array = data.get("character_arcs_beta_1_08", {}).get(character_id, []) if data.get("character_arcs_beta_1_08", {}).get(character_id, []) is Array else []
	var current_status := str(state.character_states.get(character_id, {}).get("status", ""))
	var selected: Dictionary = {}
	var fallback: Dictionary = {}
	var selected_priority := -1
	var fallback_priority := 2147483647
	for raw_route in routes:
		if not raw_route is Dictionary:
			continue
		var route: Dictionary = raw_route
		var priority := int(route.get("priority", 0))
		if priority < fallback_priority:
			fallback = route.duplicate(true)
			fallback_priority = priority
		if int(state.current_day) < int(route.get("day_min", 1)) or (not str(route.get("result_fate_status", "")).is_empty() and current_status in (route.get("forbidden_fate_statuses", []) as Array)):
			continue
		var offices: Array = route.get("required_offices", []) if route.get("required_offices", []) is Array else []
		var offices_met := true
		for office_id in offices:
			if not _character_has_active_office(state, character_id, str(office_id)):
				offices_met = false
		if not offices_met:
			continue
		var required_verdicts: Array = route.get("required_case_verdicts", []) if route.get("required_case_verdicts", []) is Array else []
		if not _case_verdicts_met(state, required_verdicts):
			continue
		if priority > selected_priority:
			selected = route.duplicate(true)
			selected_priority = priority
	if selected.is_empty() and not fallback.is_empty():
		selected = fallback.duplicate(true)
	var refs: Array = []
	var selected_arc_id := str(selected.get("arc_id", ""))
	if not selected_arc_id.is_empty():
		refs.append({"kind": "character_arc", "id": selected_arc_id})
	for raw_term in state.office_terms.values():
		if raw_term is Dictionary and str((raw_term as Dictionary).get("holder_id", "")) == character_id and int((raw_term as Dictionary).get("end_day", 0)) < 0:
			refs.append({"kind": "term", "id": str((raw_term as Dictionary).get("term_id", ""))})
	for raw_ref in selected.get("evidence_refs", []):
		var evidence_kind := str(raw_ref)
		if evidence_kind == "case":
			refs.append_array(_resolved_case_refs(state, character_id))
		elif evidence_kind == "transaction":
			refs.append_array(_resolved_chronicle_refs(state, ["transaction", "verdict"]))
	return {"ok": not selected.is_empty(), "character_id": character_id, "arc_id": str(selected.get("arc_id", "")), "public_label": str(selected.get("title", "")), "result_fate_status": str(selected.get("result_fate_status", "")), "causal_refs": refs}

func settle_daily(state, data: Dictionary, day: int) -> Dictionary:
	if state == null:
		return {"ok": true, "code": "no_op", "effects": [], "refs": []}
	var campaign_id := str(data.get("campaign_id", ""))
	if campaign_id == "anshi_beta_1_10" or campaign_id.begins_with("anshi_beta_1_1") or data.has("character_arcs_beta_1_10"):
		var configured_ids: Array = data.get("core_character_ids", []) if data.get("core_character_ids", []) is Array else []
		var beta110_result: Dictionary = reconcile_characters(state, data, configured_ids, day)
		beta110_result["effects"] = []
		return beta110_result
	if campaign_id not in ["anshi_beta_1_08", "anshi_beta_1_09"]:
		return {"ok": true, "code": "no_op", "effects": [], "refs": []}
	var refs: Array = []
	var character_ids: Array = data.get("core_character_ids", []) if data.get("core_character_ids", []) is Array else []
	for raw_character_id in character_ids:
		var character_id := str(raw_character_id)
		var fate: Dictionary = derive_fate(character_id, state, data)
		var result_status := str(fate.get("result_fate_status", ""))
		var arc_id := str(fate.get("arc_id", ""))
		if not bool(fate.get("ok", false)) or result_status.is_empty() or arc_id.is_empty():
			continue
		var character_state: Dictionary = state.character_states.get(character_id, {}).duplicate(true)
		var fate_refs: Array = character_state.get("fate_causal_refs", []).duplicate(true)
		var ref_id := "fate|%s|%s" % [character_id, arc_id]
		var already_recorded := false
		for raw_ref in fate_refs:
			if raw_ref is Dictionary and str((raw_ref as Dictionary).get("id", "")) == ref_id:
				already_recorded = true
				break
		if already_recorded:
				continue
		character_state["status"] = result_status
		fate_refs.append({"kind": "character_fate", "id": ref_id, "arc_id": arc_id, "day": day})
		character_state["fate_causal_refs"] = fate_refs
		state.character_states[character_id] = character_state
		state.chronicle_causal_references.append({"kind": "character_fate", "id": ref_id, "character_id": character_id, "arc_id": arc_id, "day": day})
		refs.append({"kind": "character_fate", "id": ref_id, "character_id": character_id, "arc_id": arc_id})
	return {"ok": true, "code": "settled", "effects": [], "refs": refs}

func _character_has_active_office(state, character_id: String, office_id: String) -> bool:
	for term in state.office_terms.values():
		if term is Dictionary and str((term as Dictionary).get("holder_id", "")) == character_id and str((term as Dictionary).get("office_id", "")) == office_id and int((term as Dictionary).get("end_day", 0)) < 0:
			return true
	return false

func _case_verdicts_met(state, required: Array) -> bool:
	for requirement in required:
		if not requirement is Dictionary:
			return false
		var case_record: Dictionary = state.accountability_cases.get(str((requirement as Dictionary).get("case_id", "")), {})
		var decision: Dictionary = case_record.get("decision", {}) if case_record.get("decision", {}) is Dictionary else {}
		if str(decision.get("verdict_id", "")) != str((requirement as Dictionary).get("verdict_id", "")):
			return false
	return true

func _resolved_case_refs(state, character_id: String) -> Array:
	var refs: Array = []
	if state == null or not state.accountability_cases is Dictionary:
		return refs
	var case_ids: Array = state.accountability_cases.keys()
	case_ids.sort()
	for raw_case_id in case_ids:
		var case_id := str(raw_case_id)
		var case_record: Dictionary = state.accountability_cases.get(case_id, {}) if state.accountability_cases.get(case_id, {}) is Dictionary else {}
		var subjects: Array = case_record.get("subject_ids", []) if case_record.get("subject_ids", []) is Array else []
		if not subjects.has(character_id) or str(case_record.get("lifecycle", "dormant")) == "dormant":
			continue
		refs.append({"kind": "case", "id": case_id})
		var decision_transaction_id := str(case_record.get("decision_transaction_id", ""))
		if not decision_transaction_id.is_empty():
			refs.append({"kind": "transaction", "id": decision_transaction_id})
		for raw_ref in case_record.get("causal_refs", []) if case_record.get("causal_refs", []) is Array else []:
			if raw_ref is Dictionary:
				var causal_ref: Dictionary = raw_ref
				var kind := str(causal_ref.get("kind", ""))
				var ref_id := str(causal_ref.get("id", ""))
				if not ref_id.is_empty() and ["transaction", "verdict", "office_removal", "office_appointment"].has(kind):
					refs.append({"kind": kind, "id": ref_id})
	return refs

func _resolved_chronicle_refs(state, allowed_kinds: Array) -> Array:
	var refs: Array = []
	if state == null or not state.chronicle_causal_references is Array:
		return refs
	for raw_ref in state.chronicle_causal_references:
		if raw_ref is Dictionary and allowed_kinds.has(str((raw_ref as Dictionary).get("kind", ""))):
			var ref_id := str((raw_ref as Dictionary).get("id", ""))
			if not ref_id.is_empty():
				refs.append({"kind": str((raw_ref as Dictionary).get("kind", "")), "id": ref_id})
	return refs
