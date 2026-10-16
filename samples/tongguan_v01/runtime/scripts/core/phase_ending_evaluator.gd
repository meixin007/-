extends RefCounted

class_name PhaseEndingEvaluator

const FIRST_ASSESSMENT_DAY := 30
const SUPPORTED_ENDING_IDS := [
	"lingwu_secure_weak_momentum",
	"counteroffensive_ready",
	"counteroffensive_generals_empowered",
	"uighur_power_expands",
	"uighur_demands_distort_court",
	"old_court_constraint",
	"li_fuguo_gate_control",
	"court_power_captured",
	"front_collapse",
	"legitimacy_failure",
	"mixed_survival_heavy_debt",
	"lingwu_regime_stabilized",
	"beta110_frontline_recovery",
	"beta110_institutional_continuity",
	"beta110_authority_fracture"
]

func get_supported_ending_ids() -> Array:
	return SUPPORTED_ENDING_IDS.duplicate(true)

func evaluate(state, scenario_data: Dictionary = {}) -> Dictionary:
	if int(scenario_data.get("schema_version", 0)) >= 113:
		return _evaluate_manifest_campaign(state, scenario_data)
	if _is_beta_1_05_campaign(state):
		return _evaluate_beta_1_05(state)
	if _is_beta_1_10_campaign(state):
		return _evaluate_beta_1_10(state, scenario_data)
	if _is_beta_1_09_campaign(state):
		return _evaluate_beta_1_09(state)
	if _is_beta_1_08_campaign(state):
		return _evaluate_beta_1_08(state)
	if not state.phase_ending.is_empty():
		var existing_ending: Dictionary = state.phase_ending.duplicate(true)
		if not existing_ending.has("cause_summary"):
			existing_ending = _with_cause_recap(existing_ending, state, ["existing_phase_ending"])
			state.phase_ending = existing_ending.duplicate(true)
		return {"ok": true, "ending": existing_ending}
	if int(state.current_day) != FIRST_ASSESSMENT_DAY:
		return {"ok": false, "error": "phase_not_due" if int(state.current_day) < FIRST_ASSESSMENT_DAY else "phase_window_closed"}

	var ending := _select_ending(state)
	if not SUPPORTED_ENDING_IDS.has(str(ending.get("id", ""))):
		return {"ok": false, "error": "undeclared_ending_id"}
	state.phase_ending = ending.duplicate(true)
	state.phase = "phase_ending"
	state.set_flag("first_phase_concluded", true)
	return {"ok": true, "ending": ending}

func _evaluate_manifest_campaign(state, scenario_data: Dictionary) -> Dictionary:
	var day := int(state.current_day)
	var final_day := int(scenario_data.get("campaign_days", 90))
	if day < final_day:
		for phase_definition in scenario_data.get("phases", []):
			if phase_definition is Dictionary and int(phase_definition.get("end_day", -1)) == day:
				var checkpoint := {"id": "%s_checkpoint" % str(phase_definition.get("id", "phase")), "day": day, "kind": "checkpoint", "summary": "阶段纪要已记录，战役继续。"}
				state.flags["last_phase_checkpoint"] = checkpoint.duplicate(true)
				return {"ok": true, "kind": "checkpoint", "checkpoint": checkpoint}
		return {"ok": false, "error": "phase_not_due"}
	if not state.phase_ending.is_empty():
		return {"ok": true, "kind": "ending", "ending": state.phase_ending.duplicate(true)}
	var ending := _select_ending(state)
	state.phase_ending = ending.duplicate(true)
	state.phase = "phase_ending"
	return {"ok": true, "kind": "ending", "ending": ending}

func _evaluate_beta_1_05(state) -> Dictionary:
	var day := int(state.current_day)
	if day == 30 or day == 60:
		var checkpoint := {
			"id": "phase_%d_checkpoint" % (1 if day == 30 else 2),
			"day": day,
			"phase": 1 if day == 30 else 2,
			"kind": "checkpoint",
			"summary": "阶段总结已生成，九十日战役继续推进。"
		}
		state.flags["last_phase_checkpoint"] = checkpoint.duplicate(true)
		state.phase = "power_formation" if day == 30 else "alliance_cost"
		return {"ok": true, "kind": "checkpoint", "checkpoint": checkpoint}
	if day != 90:
		return {"ok": false, "error": "phase_not_due" if day < 90 else "phase_window_closed"}
	if not state.phase_ending.is_empty():
		return {"ok": true, "kind": "ending", "ending": state.phase_ending.duplicate(true)}
	var ending := _select_ending(state)
	if not SUPPORTED_ENDING_IDS.has(str(ending.get("id", ""))):
		return {"ok": false, "error": "undeclared_ending_id"}
	ending["ending_id"] = "beta105_" + str(ending.get("id", "balanced_restoration"))
	ending["evidence_refs"] = _beta_1_05_evidence_refs(state)
	state.phase_ending = ending.duplicate(true)
	state.phase = "phase_ending"
	return {"ok": true, "kind": "ending", "ending": ending}

func _is_beta_1_05_campaign(state) -> bool:
	return state != null and state.get("flags") is Dictionary and str(state.flags.get("campaign_id", "")) == "anshi_beta_1_05"

func _is_beta_1_08_campaign(state) -> bool:
	return state != null and state.get("flags") is Dictionary and str(state.flags.get("campaign_id", "")) == "anshi_beta_1_08"

func _is_beta_1_09_campaign(state) -> bool:
	return state != null and state.get("flags") is Dictionary and str(state.flags.get("campaign_id", "")) == "anshi_beta_1_09"

func _is_beta_1_10_campaign(state) -> bool:
	return state != null and state.get("flags") is Dictionary and str(state.flags.get("campaign_id", "")) == "anshi_beta_1_10"

func _evaluate_beta_1_10(state, scenario_data: Dictionary = {}) -> Dictionary:
	var day := int(state.current_day)
	if day == 45 or day == 65:
		var phase := 2 if day == 45 else 3
		var checkpoint := {
			"id": "beta110_phase_%d_checkpoint" % phase,
			"campaign_id": "anshi_beta_1_10",
			"day": day,
			"phase": phase,
			"kind": "checkpoint",
			"review_refs": _beta_1_10_report_refs(state),
			"case_refs": _beta_1_10_case_refs(state),
			"echo_refs": _beta_1_10_echo_refs(state),
			"debt_refs": _beta_1_10_debt_refs(state),
			"summary": "余波阶段第 %d 次复盘已生成，既有裁决、报告与关系记忆继续约束后续路线。" % phase
		}
		state.flags["last_phase_checkpoint"] = checkpoint.duplicate(true)
		state.phase = "political_season_review" if day == 45 else "authority_review"
		return {"ok": true, "kind": "checkpoint", "checkpoint": checkpoint}
	if day != 90:
		return {"ok": false, "error": "phase_window_closed" if day > 90 else "phase_not_due"}
	if not _beta110_review_acknowledged(state, "beta110_final_assessment"):
		return _beta_1_10_final_checkpoint(state)
	if not _beta110_report_exists(state, "beta110_report_final_assessment"):
		return {"ok": false, "error": "final_assessment_report_required"}
	return _evaluate_beta_1_10_ending(state, scenario_data)

func _beta_1_10_final_checkpoint(state) -> Dictionary:
	var existing: Variant = state.flags.get("last_phase_checkpoint", {}) if state.flags is Dictionary else {}
	if existing is Dictionary and str((existing as Dictionary).get("id", "")) == "beta110_final_assessment":
		state.phase = "final_assessment"
		return {"ok": true, "kind": "checkpoint", "checkpoint": (existing as Dictionary).duplicate(true)}
	var checkpoint := {
		"id": "beta110_final_assessment",
		"campaign_id": "anshi_beta_1_10",
		"day": 90,
		"phase": 4,
		"kind": "checkpoint",
		"review_id": "beta110_final_assessment",
		"report_id": "beta110_report_final_assessment",
		"review_refs": _beta_1_10_report_refs(state),
		"case_refs": _beta_1_10_case_refs(state),
		"echo_refs": _beta_1_10_echo_refs(state),
		"debt_refs": _beta_1_10_debt_refs(state),
		"summary": "九十日余波结算已生成，确认最终复盘后才进入结局。"
	}
	state.flags["last_phase_checkpoint"] = checkpoint.duplicate(true)
	state.phase = "final_assessment"
	return {"ok": true, "kind": "checkpoint", "checkpoint": checkpoint}

func _evaluate_beta_1_10_ending(state, scenario_data: Dictionary = {}) -> Dictionary:
	if scenario_data.is_empty():
		return {"ok": false, "error": "scenario_data_required_for_beta_1_10"}
	if not state.phase_ending.is_empty():
		var persisted_aftermath: Dictionary = _beta_1_10_character_aftermath(state, scenario_data)
		var persisted_ending: Dictionary = state.phase_ending.duplicate(true)
		persisted_ending["character_fate_refs"] = _beta_1_10_character_fate_refs(state, scenario_data)
		persisted_ending["character_aftermath"] = persisted_aftermath.get("groups", {})
		persisted_ending["character_aftermath_audit"] = persisted_aftermath.get("audit", {})
		state.phase_ending = persisted_ending.duplicate(true)
		return {"ok": true, "kind": "ending", "ending": persisted_ending}
	var route_id := str(state.flags.get("beta110_public_route_id", state.flags.get("beta110_route_id", "")))
	var ending_id := _beta_1_10_ending_id(state, route_id)
	if not SUPPORTED_ENDING_IDS.has(ending_id):
		return {"ok": false, "error": "undeclared_ending_id"}
	var character_aftermath_result: Dictionary = _beta_1_10_character_aftermath(state, scenario_data)
	var ending := _with_cause_recap({
		"id": ending_id,
		"ending_id": ending_id,
		"campaign_id": "anshi_beta_1_10",
		"outcome": "success" if ending_id == "beta110_frontline_recovery" else "mixed",
		"title": _beta_1_10_ending_title(ending_id),
		"summary": _beta_1_10_ending_summary(ending_id),
		"case_refs": _beta_1_10_case_refs(state),
		"report_refs": _beta_1_10_report_refs(state),
		"echo_refs": _beta_1_10_echo_refs(state),
		"debt_refs": _beta_1_10_debt_refs(state),
		"character_fate_refs": _beta_1_10_character_fate_refs(state, scenario_data),
		"character_aftermath": character_aftermath_result.get("groups", {}),
		"character_aftermath_audit": character_aftermath_result.get("audit", {})
	}, state, ["accountability_cases", "governance_reports", "political_echoes", "political_debts"])
	ending["cause_summary"] = str(ending.get("cause_summary", "")) + " 余波结算保留案件、报告、政治回响与债务引用。"
	state.phase_ending = ending.duplicate(true)
	state.phase = "phase_ending"
	return {"ok": true, "kind": "ending", "ending": ending}

func _beta110_review_acknowledged(state, review_id: String) -> bool:
	var workbench: Variant = state.court_workbench_state if state != null and state.court_workbench_state is Dictionary else {}
	var acknowledged: Variant = workbench.get("political_season_reviews_acknowledged", {}) if workbench is Dictionary else {}
	return acknowledged is Dictionary and bool((acknowledged as Dictionary).get(review_id, false))

func _beta110_report_exists(state, report_id: String) -> bool:
	var reports: Variant = state.governance_state.get("reports", []) if state != null and state.governance_state is Dictionary else []
	if not reports is Array:
		return false
	for raw_report in reports as Array:
		if raw_report is Dictionary and str((raw_report as Dictionary).get("report_id", "")) == report_id:
			return true
	return false

func _beta_1_10_ending_id(state, route_id: String) -> String:
	if route_id == "beta110_route_frontline_urgency" or route_id == "frontline_urgent":
		return "beta110_frontline_recovery"
	if route_id == "beta110_route_court_consolidation" or route_id == "court_consolidation":
		return "beta110_authority_fracture"
	if route_id == "beta110_route_audit_continuity" or route_id == "audit_continuity":
		return "beta110_institutional_continuity"
	var authority := int(state.resources.get("court_authority", 0))
	var morale := int(state.resources.get("military_morale", 0))
	var debts := _beta_1_10_debt_refs(state).size()
	if morale >= 60 and int(state.resources.get("grain", 0)) >= 350:
		return "beta110_frontline_recovery"
	if authority <= 30 or _faction_pressure(state, "eunuch_network") >= 85:
		return "beta110_authority_fracture"
	if debts >= 3:
		return "beta110_authority_fracture"
	return "beta110_institutional_continuity"

func _beta_1_10_ending_title(ending_id: String) -> String:
	match ending_id:
		"beta110_frontline_recovery": return "前线恢复，代价入账"
		"beta110_authority_fracture": return "中枢稳住，权威出现裂缝"
		_: return "制度延续，余波留痕"

func _beta_1_10_ending_summary(ending_id: String) -> String:
	match ending_id:
		"beta110_frontline_recovery": return "九十日结算显示前线补给与军方信任被接续下来，但援助付款和紧急授权已经成为下一阶段必须偿还的政治成本。"
		"beta110_authority_fracture": return "九十日结算显示中枢仍能发令，却无法让所有派系接受同一套程序。案件、门禁与紧急例外留下了可追溯的权威裂缝。"
		_: return "九十日结算显示公开核账与连续制度保住了治理链条，但速度损失、关系记忆和持续债务将进入下一阶段。"

func _beta_1_10_case_refs(state) -> Array:
	var refs: Array = []
	if not (state.accountability_cases is Dictionary):
		return refs
	var ids: Array = state.accountability_cases.keys()
	ids.sort()
	for case_id in ids:
		var record: Dictionary = state.accountability_cases[case_id] if state.accountability_cases[case_id] is Dictionary else {}
		refs.append({"kind": "case", "id": str(case_id), "lifecycle": str(record.get("lifecycle", "")), "decision_transaction_id": str(record.get("decision_transaction_id", ""))})
	return refs

func _beta_1_10_report_refs(state) -> Array:
	var refs: Array = []
	var reports: Array = state.governance_state.get("reports", []) if state.governance_state.get("reports", []) is Array else []
	for raw_report in reports:
		if raw_report is Dictionary:
			var report: Dictionary = raw_report
			var report_id := str(report.get("report_id", ""))
			if not report_id.is_empty():
				refs.append(report_id)
	refs = _sorted_unique_strings(refs)
	return refs

func _beta_1_10_echo_refs(state) -> Array:
	var refs: Array = []
	for raw_ref in state.chronicle_causal_references if state.chronicle_causal_references is Array else []:
		if not raw_ref is Dictionary:
			continue
		var reference: Dictionary = raw_ref
		if str(reference.get("kind", "")) == "political_season_echo":
			var echo_id := str(reference.get("echo_id", reference.get("id", "")))
			if echo_id.begins_with("political_season_echo|"):
				echo_id = echo_id.trim_prefix("political_season_echo|")
			if not echo_id.is_empty():
				refs.append(echo_id)
	return _sorted_unique_strings(refs)

func _beta_1_10_debt_refs(state) -> Array:
	var refs: Array = []
	if state.political_debts is Dictionary:
		for debt_id in state.political_debts.keys():
			refs.append(str(debt_id))
	return _sorted_unique_strings(refs)

func _beta_1_10_character_fate_refs(state, scenario_data: Dictionary = {}) -> Array:
	var refs: Array = []
	if not (state.character_states is Dictionary):
		return refs
	for character_id in state.character_states.keys():
		var character: Dictionary = state.character_states[character_id] if state.character_states[character_id] is Dictionary else {}
		for raw_ref in character.get("fate_causal_refs", []) if character.get("fate_causal_refs", []) is Array else []:
			if scenario_data.size() > 0 and (not raw_ref is Dictionary or not _is_valid_persisted_beta110_fate(raw_ref as Dictionary, str(character_id), scenario_data, state)):
				continue
			refs.append({"character_id": str(character_id), "ref": raw_ref.duplicate(true) if raw_ref is Dictionary else {}})
	return refs

func _beta_1_10_character_aftermath(state, scenario_data: Dictionary = {}) -> Dictionary:
	var configured_ids: Array = []
	var flags: Variant = state.flags if state != null else {}
	if flags is Dictionary and (flags as Dictionary).get("beta110_core_character_ids", []) is Array:
		for raw_id in (flags as Dictionary).get("beta110_core_character_ids", []) as Array:
			var character_id := str(raw_id).strip_edges()
			if not character_id.is_empty() and not configured_ids.has(character_id):
				configured_ids.append(character_id)
	if configured_ids.is_empty() and state != null and state.character_states is Dictionary:
		configured_ids = state.character_states.keys()
		configured_ids.sort()
	var groups := {
		"gained_position": [],
		"constrained": [],
		"paid_cost": []
	}
	var audit_errors: Array = []
	for character_id in configured_ids:
		var character: Dictionary = {}
		if state != null and state.character_states is Dictionary and state.character_states.get(character_id, {}) is Dictionary:
			character = state.character_states.get(character_id, {}).duplicate(true)
		var persisted: Dictionary = _read_persisted_beta110_fate(character.get("fate_causal_refs", []), character_id, scenario_data, state)
		if not bool(persisted.get("ok", false)):
			audit_errors.append({"character_id": character_id, "code": str(persisted.get("code", "invalid_persisted_fate"))})
		var latest: Dictionary = persisted.get("ref", {}) if persisted.get("ref", {}) is Dictionary else {}
		var category := str(latest.get("aftermath_category", "constrained"))
		if category not in ["gained_position", "constrained", "paid_cost"]:
			category = "constrained"
		var label := _safe_aftermath_text(latest.get("public_label", ""), "当前走向未明")
		var reason := _safe_aftermath_text(latest.get("primary_public_reason", ""), "当前依据不足，需通过调查或复核确认")
		var character_name := _safe_aftermath_text(character.get("name", ""), "人物")
		var row := {
			"character_id": character_id,
			"character_name": character_name,
			"final_public_label": label,
			"category": category,
			"primary_public_reason": reason,
			"profile_target": {"kind": "character", "id": character_id},
			"day": int(latest.get("day", 0)) if not latest.is_empty() else 0
		}
		(groups[category] as Array).append(row)
	return {
		"groups": groups,
		"audit": {"ok": audit_errors.is_empty(), "errors": audit_errors}
	}

func _read_persisted_beta110_fate(raw_refs: Variant, character_id: String, scenario_data: Dictionary = {}, state = null) -> Dictionary:
	if not raw_refs is Array or (raw_refs as Array).is_empty():
		return {"ok": false, "code": "missing_persisted_fate", "ref": {}}
	var valid: Array = []
	for raw_ref in raw_refs as Array:
		if not raw_ref is Dictionary or not _is_valid_persisted_beta110_fate(raw_ref as Dictionary, character_id, scenario_data, state):
			continue
		valid.append((raw_ref as Dictionary).duplicate(true))
	if valid.is_empty():
		return {"ok": false, "code": "invalid_persisted_fate", "ref": {}}
	valid.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if int(left.get("day", 0)) != int(right.get("day", 0)):
			return int(left.get("day", 0)) < int(right.get("day", 0))
		return str(left.get("id", "")) < str(right.get("id", ""))
	)
	return {"ok": true, "code": "persisted_fate_read", "ref": valid[valid.size() - 1].duplicate(true)}

func _is_valid_persisted_beta110_fate(ref: Dictionary, character_id: String, scenario_data: Dictionary = {}, state = null) -> bool:
	var arc_id := str(ref.get("arc_id", "")).strip_edges()
	if str(ref.get("kind", "")) != "character_fate" or str(ref.get("character_id", "")) != character_id or arc_id.is_empty():
		return false
	if str(ref.get("id", "")) != "fate|%s|%s" % [character_id, arc_id]:
		return false
	var day_value: Variant = ref.get("day", -1)
	if typeof(day_value) != TYPE_INT or int(day_value) < 1 or int(day_value) > 90:
		return false
	for key in ["result_fate_status", "public_label", "primary_public_reason"]:
		if _safe_aftermath_text(ref.get(key, ""), "").is_empty():
			return false
	if str(ref.get("aftermath_category", "")) not in ["gained_position", "constrained", "paid_cost"]:
		return false
	var reason_refs: Variant = ref.get("reason_refs", [])
	if not reason_refs is Array or (reason_refs as Array).is_empty() or (reason_refs as Array).size() > 8:
		return false
	for raw_reason in reason_refs as Array:
		if not raw_reason is Dictionary:
			return false
		var reason: Dictionary = raw_reason as Dictionary
		if str(reason.get("kind", "")) not in ["route", "case", "office", "review", "chronicle"] or str(reason.get("id", "")).strip_edges().is_empty():
			return false
	if scenario_data.size() > 0:
		var arcs: Variant = scenario_data.get("character_arcs_beta_1_10", null)
		if not arcs is Dictionary:
			var wrapper: Variant = scenario_data.get("beta110_character_arcs", {})
			if wrapper is Dictionary:
				arcs = (wrapper as Dictionary).get("arcs", {})
		if not arcs is Dictionary:
			return false
		var rules: Variant = (arcs as Dictionary).get(character_id, null)
		if not rules is Array:
			return false
		var known_arc := false
		for raw_rule in rules as Array:
			if raw_rule is Dictionary and str((raw_rule as Dictionary).get("arc_id", "")) == arc_id:
				known_arc = true
				break
		if not known_arc:
			return false
		for raw_reason in reason_refs as Array:
			var reason: Dictionary = raw_reason as Dictionary
			if not _beta110_public_reference_exists(str(reason.get("kind", "")), str(reason.get("id", "")), scenario_data, state):
				return false
	return true

func _beta110_public_reference_exists(kind: String, reference_id: String, scenario_data: Dictionary, state) -> bool:
	if reference_id.is_empty():
		return false
	var campaign_arrays := {
		"route": [["beta110_routes", ["route_id", "id"]]],
		"case": [["beta110_accountability_effects", ["case_id", "id"]], ["accountability_case_templates", ["case_id", "id"]], ["beta110_nodes", ["case_id"]]],
		"office": [["offices", ["office_id", "id"]]],
		"review": [["beta110_reviews", ["review_id", "id"]], ["political_season_reviews", ["review_id", "id"]]],
		"chronicle": [["beta110_echoes", ["echo_id", "id"]]]
	}
	for raw_source in campaign_arrays.get(kind, []):
		var source: Array = raw_source as Array
		if _beta110_array_has_public_id(scenario_data.get(str(source[0]), []), reference_id, source[1] as Array):
			return true
	if state == null:
		return false
	if kind == "route" and state.flags is Dictionary:
		for key in ["beta110_route_id", "beta110_public_route_id", "route_id", "public_route_id"]:
			if str(state.flags.get(key, "")) == reference_id:
				return true
	if kind == "case" and state.accountability_cases is Dictionary and state.accountability_cases.has(reference_id):
		return true
	if kind == "office":
		if state.office_terms is Dictionary:
			for raw_term in state.office_terms.values():
				if raw_term is Dictionary and str((raw_term as Dictionary).get("office_id", "")) == reference_id:
					return true
		if state.office_state is Dictionary and state.office_state.has(reference_id):
			return true
	if kind == "review" and state.court_workbench_state is Dictionary:
		var acknowledged: Variant = state.court_workbench_state.get("political_season_reviews_acknowledged", {})
		if acknowledged is Dictionary and acknowledged.has(reference_id):
			return true
	if state.chronicle_causal_references is Array:
		for raw_reference in state.chronicle_causal_references:
			if not raw_reference is Dictionary:
				continue
			var reference: Dictionary = raw_reference as Dictionary
			var state_id := str(reference.get("id", reference.get("echo_id", "")))
			var state_kind := str(reference.get("kind", ""))
			if state_id == reference_id and (state_kind == kind or (kind == "chronicle" and state_kind == "political_season_echo")):
				return true
	return false

func _beta110_array_has_public_id(value: Variant, reference_id: String, id_keys: Array) -> bool:
	if not value is Array:
		return false
	for raw_entry in value as Array:
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry as Dictionary
		for key in id_keys:
			if str(entry.get(str(key), "")) == reference_id:
				return true
	return false

func _safe_aftermath_text(value: Variant, fallback: String) -> String:
	if typeof(value) != TYPE_STRING:
		return fallback
	var text := str(value).strip_edges()
	if text.is_empty() or text.length() > 256 or text.contains("<") or text.contains(">"):
		return fallback
	return text

func _evaluate_beta_1_09(state) -> Dictionary:
	var day := int(state.current_day)
	if day == 30:
		var season_refs: Array = []
		var review_refs: Array = []
		for raw_ref in state.chronicle_causal_references if state.chronicle_causal_references is Array else []:
			if not raw_ref is Dictionary:
				continue
			var reference: Dictionary = raw_ref
			var kind := str(reference.get("kind", ""))
			if kind == "political_season_echo":
				season_refs.append(str(reference.get("id", "")))
			elif kind in ["office_appointment", "political_season_review"]:
				review_refs.append(str(reference.get("id", "")))
		season_refs = _sorted_unique_strings(season_refs)
		review_refs = _sorted_unique_strings(review_refs)
		var checkpoint := {
			"id": "beta109_phase_1_checkpoint",
			"day": 30,
			"phase": 1,
			"kind": "checkpoint",
			"season_refs": season_refs,
			"review_refs": review_refs,
			"case_refs": _beta_1_08_case_refs(state)
		}
		state.flags["last_phase_checkpoint"] = checkpoint.duplicate(true)
		state.phase = "political_season_review"
		return {"ok": true, "kind": "checkpoint", "checkpoint": checkpoint}
	if day == 60:
		var derived := _evaluate_beta_1_08(state)
		if bool(derived.get("ok", false)) and derived.get("kind", "") == "checkpoint":
			var checkpoint: Dictionary = derived.get("checkpoint", {}).duplicate(true)
			checkpoint["id"] = "beta109_phase_2_checkpoint"
			checkpoint["campaign_id"] = "anshi_beta_1_09"
			state.flags["last_phase_checkpoint"] = checkpoint.duplicate(true)
			derived["checkpoint"] = checkpoint
			return derived
		return derived
	if day == 90:
		return _evaluate_beta_1_09_ending(state)
	return {"ok": false, "error": "phase_window_closed" if day > 90 else "phase_not_due"}

func _evaluate_beta_1_09_ending(state) -> Dictionary:
	if not state.phase_ending.is_empty():
		return {"ok": true, "kind": "ending", "ending": state.phase_ending.duplicate(true)}
	var ending := _select_ending(state)
	if not SUPPORTED_ENDING_IDS.has(str(ending.get("id", ""))):
		return {"ok": false, "error": "undeclared_ending_id"}
	ending["ending_id"] = "beta109_" + str(ending.get("id", "balanced_restoration"))
	ending["campaign_id"] = "anshi_beta_1_09"
	ending["case_refs"] = _beta_1_08_case_refs(state)
	state.phase_ending = ending.duplicate(true)
	state.phase = "phase_ending"
	return {"ok": true, "kind": "ending", "ending": ending}

func _sorted_unique_strings(values: Array) -> Array:
	var unique: Array = []
	for value in values:
		var text := str(value)
		if not text.is_empty() and not unique.has(text):
			unique.append(text)
	unique.sort()
	return unique

func _evaluate_beta_1_08(state) -> Dictionary:
	var day := int(state.current_day)
	if day == 30 or day == 60:
		var checkpoint := {"id": "beta108_phase_%d_checkpoint" % (1 if day == 30 else 2), "day": day, "phase": 1 if day == 30 else 2, "kind": "checkpoint", "case_refs": _beta_1_08_case_refs(state)}
		state.flags["last_phase_checkpoint"] = checkpoint.duplicate(true)
		state.phase = "accountability" if day == 30 else "crisis_reorganization"
		return {"ok": true, "kind": "checkpoint", "checkpoint": checkpoint}
	if day != 90:
		return {"ok": false, "error": "phase_not_due" if day < 90 else "phase_window_closed"}
	if not state.phase_ending.is_empty():
		return {"ok": true, "kind": "ending", "ending": state.phase_ending.duplicate(true)}
	var ending_id := "beta108_heavy_political_debt" if state.political_debts.size() >= 3 or int(state.resources.get("court_authority", 0)) <= 20 else "beta108_final_assessment"
	var debt_refs: Array = state.political_debts.keys()
	debt_refs.sort()
	var ending := {"id": ending_id, "ending_id": ending_id, "outcome": "mixed" if ending_id == "beta108_heavy_political_debt" else "success", "title": "BETA 1.08 final assessment", "summary": "The ninety-day accountability assessment is closed.", "case_refs": _beta_1_08_case_refs(state), "debt_refs": debt_refs, "character_fate_refs": _beta_1_08_character_fate_refs(state)}
	state.phase_ending = ending.duplicate(true)
	state.phase = "phase_ending"
	return {"ok": true, "kind": "ending", "ending": ending}

func _beta_1_08_case_refs(state) -> Array:
	var refs: Array = []
	var case_ids: Array = state.accountability_cases.keys()
	case_ids.sort()
	for case_id in case_ids:
		var case_record: Dictionary = state.accountability_cases[case_id] if state.accountability_cases[case_id] is Dictionary else {}
		if str(case_record.get("lifecycle", "")) in ["decided", "closed"]:
			refs.append({"kind": "case", "id": str(case_id), "decision_transaction_id": str(case_record.get("decision_transaction_id", ""))})
	return refs

func _beta_1_08_character_fate_refs(state) -> Array:
	var refs: Array = []
	var character_ids: Array = state.character_states.keys()
	character_ids.sort()
	for character_id in character_ids:
		var character: Dictionary = state.character_states[character_id] if state.character_states[character_id] is Dictionary else {}
		for ref in character.get("fate_causal_refs", []) if character.get("fate_causal_refs", []) is Array else []:
			refs.append({"character_id": str(character_id), "ref": ref.duplicate(true) if ref is Dictionary else {}})
	return refs

func _beta_1_05_evidence_refs(state) -> Array:
	var refs: Array = ["beta105_day90_final_court"]
	for record in state.event_history:
		if record is Dictionary and str(record.get("event_id", "")).begins_with("beta105_"):
			_add_unique_ref(refs, str(record.get("event_id", "")))
	for reference in state.chronicle_causal_references:
		if reference is Dictionary:
			_add_unique_ref(refs, str(reference.get("id", "")))
	return refs

func _add_unique_ref(refs: Array, reference_id: String) -> void:
	if not reference_id.is_empty() and not refs.has(reference_id):
		refs.append(reference_id)

func _select_ending(state) -> Dictionary:
	var grain := int(state.resources.get("grain", 0))
	var morale := int(state.resources.get("military_morale", 0))
	var authority := int(state.resources.get("court_authority", 0))
	var legitimacy := int(state.resources.get("legitimacy", 0))
	var support_shuofang := int(state.strategic_routes.get("support_shuofang", 0))
	var defend_lingwu := int(state.strategic_routes.get("defend_lingwu", 0))
	var uighur_push := int(state.strategic_routes.get("uighur_push", 0))
	var shuofang: Dictionary = state.battlefront_states.get("shuofang_front", {})

	if grain <= 0 or morale <= 35:
		return _with_cause_recap({
			"id": "front_collapse",
			"outcome": "failure",
			"title": "前线粮尽军溃",
			"summary": "第一轮大势已定：朔方粮道失守，军心跌落谷底。郭子仪虽仍愿奉诏，但前线已经无法支撑新朝的第一轮战局，灵武行在被迫转入败局。"
		}, state, ["resources", "battlefronts"])
	if legitimacy <= 30:
		return _with_cause_recap({
			"id": "legitimacy_failure",
			"outcome": "failure",
			"title": "正统崩裂",
			"summary": "第一轮大势已定：灵武虽有兵粮残余，却失去足以号令诸方的正统解释。旧臣、军府与民间都开始怀疑新朝诏令能否承担下一章成本。"
		}, state, ["resources", "factions", "event_history"])
	if _faction_pressure(state, "eunuch_network") >= 85 and authority <= 35:
		return _with_cause_recap({
			"id": "li_fuguo_gate_control",
			"outcome": "mixed",
			"title": "李辅国控住宫门",
			"summary": "第一轮大势已定：近侍渠道替皇帝挡下了混乱，也把外朝、军府与奏疏入口握得太紧。灵武没有垮，但下一阶段会先处理谁能见到皇帝。"
		}, state, ["factions", "event_history", "resources"])
	if authority <= 20 or legitimacy <= 35:
		return _with_cause_recap({
			"id": "court_power_captured" if authority <= 20 else "legitimacy_failure",
			"outcome": "failure",
			"title": "行在权柄旁落",
			"summary": "第一轮大势已定：行在朝威不足，正统号令难以压住旧臣、近侍与军府。李亨名义仍在位，但关键政令已被旁人截流，灵武政权进入被架空的败局。"
		}, state, ["resources", "factions"])
	if uighur_push >= 5 and _faction_pressure(state, "uighur_envoys") >= 90:
		return _with_cause_recap({
			"id": "uighur_demands_distort_court",
			"outcome": "mixed",
			"title": "回纥索价扭曲朝局",
			"summary": "第一轮大势已定：外援打破了战场僵局，却让赏约、马价和战后分赐反过来牵动朝廷议程。军事上得救，政治上开始欠债。"
		}, state, ["strategic_routes", "factions", "resources"])
	if uighur_push >= 4 and _faction_pressure(state, "uighur_envoys") >= 70:
		return _with_cause_recap({
			"id": "uighur_power_expands",
			"outcome": "mixed",
			"title": "借兵成势，回纥坐大",
			"summary": "第一轮大势已定：回纥援军的确让行在看见反攻机会，但赏约与兵权代价随之抬高。灵武没有立刻崩坏，却把下一阶段的外交和财政压力推到台前。"
		}, state, ["strategic_routes", "factions", "battlefronts"])
	if support_shuofang >= 5 and _faction_pressure(state, "military_commanders") >= 80:
		return _with_cause_recap({
			"id": "counteroffensive_generals_empowered",
			"outcome": "mixed",
			"title": "反攻成形，将帅坐大",
			"summary": "第一轮大势已定：朔方反攻已可准备，但军府借粮道、战功与节制权取得了更强发言权。胜势不是免费的，下一章会继承将帅 leverage。"
		}, state, ["strategic_routes", "factions", "battlefronts"])
	if support_shuofang >= 4 and int(shuofang.get("control", 0)) >= 65 and int(shuofang.get("supply", 0)) >= 55:
		return _with_cause_recap({
			"id": "counteroffensive_ready",
			"outcome": "success",
			"title": "反攻准备成形",
			"summary": "第一轮大势已定：朔方粮道和将帅信任被及时接住，行在已经具备组织下一轮反攻的底气。真正的收复两京尚未开始，但灵武终于不再只是避难朝廷。"
		}, state, ["strategic_routes", "battlefronts", "event_history"])
	if _faction_pressure(state, "xuanzong_old_court") >= 80 and legitimacy <= 45:
		return _with_cause_recap({
			"id": "old_court_constraint",
			"outcome": "mixed",
			"title": "旧臣掣肘新朝",
			"summary": "第一轮大势已定：灵武行在勉强维持，但玄宗旧臣借礼制和诏命持续牵制新皇。李亨可以继续发令，却必须在下一阶段付出更多政治成本。"
		}, state, ["factions", "resources"])
	if defend_lingwu >= 4:
		return _with_cause_recap({
			"id": "lingwu_secure_weak_momentum",
			"outcome": "mixed",
			"title": "灵武固守得成",
			"summary": "第一轮大势已定：行在守住了灵武安全线，朝廷暂免流离，但反攻声势不足。这个结局给了李亨喘息时间，也让将帅和前线更急于索取明确路线。"
		}, state, ["strategic_routes", "battlefronts"])
	if grain < 350 or _faction_pressure(state, "uighur_envoys") >= 75:
		return _with_cause_recap({
			"id": "mixed_survival_heavy_debt",
			"outcome": "mixed",
			"title": "灵武尚存，债压下一章",
			"summary": "第一轮大势已定：灵武没有倒下，但粮、钱、人心和外援条件已经把下一章成本提前写在账上。玩家路线有效，却留下沉重未解债。"
		}, state, ["resources", "factions", "event_history"])
	return _with_cause_recap({
		"id": "lingwu_regime_stabilized",
		"outcome": "success",
		"title": "灵武政权暂稳",
		"summary": "第一轮大势已定：粮草、军心与朝廷号令尚能互相支撑。李亨没有赢下安史之乱，但已经让灵武行在撑过最危险的开局，下一阶段可以围绕将帅、粮道与正统继续展开。"
	}, state, ["resources", "battlefronts", "event_history"])

func _with_cause_recap(ending: Dictionary, state, source_tags: Array) -> Dictionary:
	var result := ending.duplicate(true)
	var tags: Array = []
	for tag in source_tags:
		_add_unique_tag(tags, str(tag))
	if not state.event_history.is_empty():
		_add_unique_tag(tags, "event_history")
	if not state.battlefront_states.is_empty():
		_add_unique_tag(tags, "battlefronts")
	if not state.strategic_routes.is_empty():
		_add_unique_tag(tags, "strategic_routes")
	_add_unique_tag(tags, "resources")
	result["cause_tags"] = tags
	result["cause_summary"] = _build_cause_summary(state)
	result["chain_outcomes"] = _chain_outcomes(state)
	result["character_stances"] = _character_stances(state)
	result["obligation_statuses"] = _obligation_statuses(state)
	result["event_outcomes"] = _event_outcomes(state)
	result["map_and_resources"] = _map_and_resource_evidence(state)
	result["chronicle_causes"] = _chronicle_causes(state)
	result["winners"] = _winners(state, result)
	result["losers"] = _losers(state, result)
	result["inherited_debts"] = _inherited_debts(state, result)
	result["next_stage_opportunities"] = _next_stage_opportunities(state, result)
	return result

func _chain_outcomes(state) -> Array:
	var outcomes: Array = []
	var chain_states: Dictionary = state.flags.get("political_chain_states", {})
	for chain_id in chain_states.keys():
		var entry: Dictionary = chain_states[chain_id] if chain_states[chain_id] is Dictionary else {}
		outcomes.append({
			"id": str(entry.get("chain_id", chain_id)),
			"status": str(entry.get("status", "unresolved")),
			"branch_id": str(entry.get("branch_id", ""))
		})
	if outcomes.is_empty():
		outcomes.append({"id": "no_recorded_political_chain", "status": "unresolved", "branch_id": ""})
	return outcomes

const LEGACY_STANCE_CHARACTER_IDS := ["guo_ziyi", "li_bi", "li_fuguo", "uighur_envoy"]

func _character_stances(state) -> Array:
	var stances: Array = []
	for character_id in _stance_character_ids(state):
		if not state.character_states.has(character_id):
			continue
		var character: Dictionary = state.character_states[character_id]
		var relationship := int(character.get("relationships", {}).get("li_heng", 0))
		stances.append({
			"id": character_id,
			"name": str(character.get("name", character_id)),
			"stance": _stance_label(relationship),
			"relationship": relationship
		})
	return stances

# Beta 1.05 endings must report every core character so two routes can be compared
# character by character. Pre-1.05 saves keep the original four-character summary.
func _stance_character_ids(state) -> Array:
	if not _is_beta_1_05_campaign(state) and not _is_beta_1_08_campaign(state) and not _is_beta_1_09_campaign(state) and not _is_beta_1_10_campaign(state):
		return LEGACY_STANCE_CHARACTER_IDS.duplicate()
	var ids: Array = []
	for character_id in state.character_states.keys():
		ids.append(str(character_id))
	ids.sort()
	return ids

func _stance_label(relationship: int) -> String:
	if relationship > 35:
		return "公开合作"
	if relationship > 15:
		return "支持"
	if relationship < -35:
		return "公开反对"
	if relationship < -15:
		return "抵触"
	return "观望"

func _obligation_statuses(state) -> Array:
	var statuses: Array = []
	for obligation in state.obligation_ledger:
		if not (obligation is Dictionary):
			continue
		var obligation_id := str(obligation.get("id", ""))
		if obligation_id.is_empty():
			continue
		statuses.append({"id": obligation_id, "status": str(obligation.get("status", "pending")), "summary": str(obligation.get("summary", obligation_id))})
	if statuses.is_empty():
		statuses.append({"id": "no_recorded_promise", "status": "none", "summary": "本阶段没有登记承诺。"})
	return statuses

func _event_outcomes(state) -> Array:
	var outcomes: Array = []
	for record in state.event_history:
		if not (record is Dictionary):
			continue
		var status := str(record.get("status", ""))
		if not ["resolved", "ignored", "expired"].has(status):
			continue
		var event_id := str(record.get("event_id", ""))
		if event_id.is_empty():
			continue
		outcomes.append({"id": event_id, "status": status, "summary": str(record.get("details", {}))})
	if outcomes.is_empty():
		outcomes.append({"id": "no_recorded_event", "status": "unresolved", "summary": "本阶段没有已结算事件记录。"})
	return outcomes

func _map_and_resource_evidence(state) -> Dictionary:
	var fronts: Array = []
	for front_id in state.battlefront_states.keys():
		var front: Dictionary = state.battlefront_states[front_id]
		fronts.append({"id": str(front_id), "control": int(front.get("control", 0)), "supply": int(front.get("supply", 0)), "threat": int(front.get("threat", 0))})
	return {
		"resources": state.resources.duplicate(true),
		"routes": state.strategic_routes.duplicate(true),
		"fronts": fronts
	}

func _chronicle_causes(state) -> Array:
	var causes: Array = []
	for cause in state.chronicle_causal_references:
		if not (cause is Dictionary):
			continue
		var cause_id := str(cause.get("id", ""))
		if cause_id.is_empty():
			continue
		causes.append({"id": cause_id, "kind": str(cause.get("kind", "cause")), "outcome_id": str(cause.get("outcome_id", cause.get("status", "")))})
	if causes.is_empty():
		causes.append({"id": "no_recorded_chronicle_cause", "kind": "phase_assessment", "outcome_id": "unresolved"})
	return causes

func _winners(state, ending: Dictionary) -> Array:
	var candidates := _character_stances(state)
	var winners: Array = []
	for entry in candidates:
		if int(entry.get("relationship", 0)) >= 0:
			winners.append(entry.duplicate(true))
	if winners.is_empty() and not candidates.is_empty():
		winners.append(candidates[0].duplicate(true))
	return winners

func _losers(state, ending: Dictionary) -> Array:
	var candidates := _character_stances(state)
	var losers: Array = []
	for entry in candidates:
		if int(entry.get("relationship", 0)) < 0:
			losers.append(entry.duplicate(true))
	if losers.is_empty() and candidates.size() > 1:
		losers.append(candidates[candidates.size() - 1].duplicate(true))
	return losers

func _inherited_debts(state, ending: Dictionary) -> Array:
	var debts: Array = []
	for obligation in _obligation_statuses(state):
		if ["pending", "broken", "expired", "converted_to_task"].has(str(obligation.get("status", ""))):
			debts.append(obligation.duplicate(true))
	if str(ending.get("outcome", "")) == "success":
		var route_id := _positive_route_id(state)
		if not route_id.is_empty():
			debts.append({"id": route_id, "status": "strategic_cost", "summary": "胜势依赖既定路线，下一阶段必须支付其军政成本。"})
		else:
			debts.append({"id": "grain", "status": "resource_commitment", "summary": "行在以现有粮草维持胜势，下一阶段仍须为军粮补给付出成本。"})
	if debts.is_empty():
		debts.append({"id": "phase_cost_" + str(ending.get("id", "unknown")), "status": "unresolved", "summary": "本阶段代价将延续至下一阶段。"})
	return debts

func _positive_route_id(state) -> String:
	for route_id in ["support_shuofang", "defend_lingwu", "uighur_push"]:
		if int(state.strategic_routes.get(route_id, 0)) > 0:
			return route_id
	return ""

func _next_stage_opportunities(state, ending: Dictionary) -> Array:
	var opportunities: Array = []
	for route_id in state.strategic_routes.keys():
		if int(state.strategic_routes[route_id]) > 0:
			opportunities.append({"id": str(route_id), "summary": "可沿既定路线继续部署。"})
	if opportunities.is_empty():
		opportunities.append({"id": "court_rebuild", "summary": "可重新整顿行在的资源与朝威。"})
	return opportunities

func _build_cause_summary(state) -> String:
	var grain := int(state.resources.get("grain", 0))
	var morale := int(state.resources.get("military_morale", 0))
	var authority := int(state.resources.get("court_authority", 0))
	var legitimacy := int(state.resources.get("legitimacy", 0))
	var parts: Array = [
		"资源：粮草 %d、军心 %d、朝威 %d、正统 %d" % [grain, morale, authority, legitimacy]
	]
	if not state.strategic_routes.is_empty():
		if _is_beta_1_10_campaign(state):
			parts.append("余波路线：核账连续 %d、前线急应 %d、固守中枢 %d" % [
				int(state.strategic_routes.get("beta110_route_audit_continuity", 0)),
				int(state.strategic_routes.get("beta110_route_frontline_urgency", 0)),
				int(state.strategic_routes.get("beta110_route_court_consolidation", 0))
			])
		else:
			parts.append("路线：固守灵武 %d、支援朔方 %d、借回纥 %d" % [
				int(state.strategic_routes.get("defend_lingwu", 0)),
				int(state.strategic_routes.get("support_shuofang", 0)),
				int(state.strategic_routes.get("uighur_push", 0))
			])
	if state.battlefront_states.has("shuofang_front"):
		var shuofang: Dictionary = state.battlefront_states["shuofang_front"]
		parts.append("朔方粮道：控制 %d、补给 %d、威胁 %d" % [
			int(shuofang.get("control", 0)),
			int(shuofang.get("supply", 0)),
			int(shuofang.get("threat", 0))
		])
	var recent_events: String = _format_recent_event_history(state.event_history)
	if recent_events != "":
		parts.append("事件：%s" % recent_events)
	return "关键因果：" + "；".join(parts) + "。"

func _faction_pressure(state, faction_id: String) -> int:
	if not state.faction_states.has(faction_id):
		return 0
	return int(state.faction_states[faction_id].get("pressure", 0))

func _format_recent_event_history(event_history: Array) -> String:
	if event_history.is_empty():
		return "暂无已记录事件"
	var start_index := maxi(event_history.size() - 3, 0)
	var entries: Array = []
	for index in range(start_index, event_history.size()):
		var entry: Dictionary = event_history[index]
		entries.append("%s:%s" % [
			str(entry.get("event_id", "")),
			str(entry.get("status", ""))
		])
	return "，".join(entries)

func _add_unique_tag(tags: Array, tag: String) -> void:
	if tag == "" or tags.has(tag):
		return
	tags.append(tag)
