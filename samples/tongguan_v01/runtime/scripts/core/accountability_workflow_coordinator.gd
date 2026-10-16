extends RefCounted

class_name AccountabilityWorkflowCoordinator

const GameStateTransactionScript = preload("res://scripts/core/game_state_transaction.gd")
const AccountabilityCaseServiceScript = preload("res://scripts/core/accountability_case_service.gd")
const OfficeServiceScript = preload("res://scripts/core/office_service.gd")
const AccountabilityVerdictEffectServiceScript = preload("res://scripts/core/accountability_verdict_effect_service.gd")
const CharacterArcServiceScript = preload("res://scripts/core/character_arc_service.gd")

func preview_verdict(context, case_id: String, verdict_id: String) -> Dictionary:
	if context == null or context.state == null:
		return _fail("invalid accountability context", "invalid_context")
	var case_record: Dictionary = context.state.accountability_cases.get(case_id, {})
	if case_record.is_empty() or str(case_record.get("lifecycle", "")) != "ready":
		return _fail("case is not ready for verdict", "invalid_lifecycle")
	if AccountabilityCaseServiceScript.new().project_available_verdicts(case_record, context.state).find(verdict_id) < 0:
		return _fail("verdict is not available", "invalid_verdict")
	var decision: Dictionary = {}
	if verdict_id == "forced_removal":
		decision = _forced_removal_target(context.state, case_record)
		if decision.is_empty():
			return _fail("forced removal has no office target", "invalid_verdict")
	var input := {"case_id": case_id, "verdict_id": verdict_id, "decision": decision}
	var transaction := GameStateTransactionScript.new()
	var preview: Dictionary = transaction.preview_command(context.state, "accountability_verdict", input, "", case_id)
	if not bool(preview.get("ok", false)):
		return _public_failure(preview)
	return {"ok": true, "code": "preview_ready", "preview_token": preview.get("preview_token", {}).duplicate(true), "envelope": transaction.build_command_envelope("accountability_verdict", input, preview.get("preview_token", {}))}

func confirm_verdict(context, envelope: Dictionary) -> Dictionary:
	var transaction := GameStateTransactionScript.new()
	var operation := Callable(self, "_apply_verdict_transaction").bind(envelope.get("input", {}), str(envelope.get("transaction_id", "")))
	return _public_failure(transaction.execute_command(context, envelope, operation))

func read_consequence(context, case_id: String) -> Dictionary:
	if context == null or context.state == null:
		return _fail("invalid accountability context", "invalid_context")
	var case_record: Dictionary = context.state.accountability_cases.get(case_id, {}) if context.state.accountability_cases.get(case_id, {}) is Dictionary else {}
	if case_record.is_empty():
		return _fail("unknown accountability case", "unknown_case")
	if str(case_record.get("lifecycle", "")) not in ["decided", "closed"]:
		return _fail("case has no committed consequence", "consequence_unavailable")
	var decision: Dictionary = case_record.get("decision", {}) if case_record.get("decision", {}) is Dictionary else {}
	var verdict_id := str(decision.get("verdict_id", ""))
	var transaction_id := str(case_record.get("decision_transaction_id", ""))
	if verdict_id.is_empty() or transaction_id.is_empty():
		return _fail("case decision receipt is incomplete", "consequence_unavailable")
	var effect_entry := _find_case_effect(context.scenario_data, case_id)
	var verdicts: Dictionary = effect_entry.get("verdict_effects", {}) if effect_entry.get("verdict_effects", {}) is Dictionary else {}
	var verdict_effect: Dictionary = verdicts.get(verdict_id, {}) if verdicts.get(verdict_id, {}) is Dictionary else {}
	if verdict_effect.is_empty():
		return _fail("committed consequence is unavailable", "consequence_unavailable")
	var stable_ref := "accountability_verdict|%s" % transaction_id
	var refs: Array = []
	for raw_ref in context.state.chronicle_causal_references if context.state.chronicle_causal_references is Array else []:
		if raw_ref is Dictionary and str((raw_ref as Dictionary).get("id", "")) == stable_ref:
			refs.append((raw_ref as Dictionary).duplicate(true))
	if refs.is_empty():
		return _fail("committed consequence receipt is missing", "consequence_unavailable")
	return {"ok": true, "code": "consequence_read", "case_id": case_id, "verdict_id": verdict_id, "transaction_id": transaction_id, "consequence": verdict_effect.duplicate(true), "chronicle_refs": refs, "source": "authoritative_state"}

func start_case_consultation(context, case_id: String, character_id: String) -> Dictionary:
	if context == null or context.state == null:
		return _fail("invalid accountability context", "invalid_context")
	if _has_adopted_subject_testimony(context.state, case_id, character_id):
		return _fail("this case subject has already given adopted testimony", "subject_already_interviewed")
	var input := {"case_id": case_id, "character_id": character_id}
	var transaction := GameStateTransactionScript.new()
	var preview: Dictionary = transaction.preview_command(context.state, "start_case_consultation", input, "", case_id)
	if not bool(preview.get("ok", false)):
		return _public_failure(preview)
	var envelope := transaction.build_command_envelope("start_case_consultation", input, preview.get("preview_token", {}))
	return _public_failure(transaction.execute_command(context, envelope, Callable(self, "_apply_start_consultation").bind(input, str(envelope.get("transaction_id", "")))))

func publish_case_consultation(context, consultation_id: String, selected_turn_ids: Array) -> Dictionary:
	if context == null or context.state == null:
		return _fail("invalid accountability context", "invalid_context")
	var existing_consultation: Dictionary = context.state.governance_state.get("consultations", {}).get(consultation_id, {}).duplicate(true)
	if not existing_consultation.is_empty() and str(existing_consultation.get("case_id", "")).is_empty():
		return _fail("consultation does not belong to an accountability case", "invalid_case_consultation")
	var input := {"consultation_id": consultation_id, "selected_turn_ids": selected_turn_ids.duplicate(true)}
	var transaction := GameStateTransactionScript.new()
	var preview: Dictionary = transaction.preview_command(context.state, "publish_case_consultation", input, "", "")
	if not bool(preview.get("ok", false)):
		return _public_failure(preview)
	var envelope := transaction.build_command_envelope("publish_case_consultation", input, preview.get("preview_token", {}))
	return _public_failure(transaction.execute_command(context, envelope, Callable(self, "_apply_publish_consultation").bind(input, str(envelope.get("transaction_id", "")))))

func submit_investigation(context, case_id: String) -> Dictionary:
	if context == null or context.state == null:
		return _fail("invalid accountability context", "invalid_context")
	var current_case: Dictionary = context.state.accountability_cases.get(case_id, {}) if context.state.accountability_cases.get(case_id, {}) is Dictionary else {}
	if str(current_case.get("lifecycle", "")) == "ready":
		return {"ok": true, "code": "idempotent_replay", "result_ref": case_id, "case_id": case_id, "state_revision": int(context.state.state_revision)}
	var input := {"case_id": case_id}
	var transaction := GameStateTransactionScript.new()
	var preview: Dictionary = transaction.preview_command(context.state, "submit_accountability_investigation", input, "", case_id)
	if not bool(preview.get("ok", false)):
		return _public_failure(preview)
	var envelope := transaction.build_command_envelope("submit_accountability_investigation", input, preview.get("preview_token", {}))
	return _public_failure(transaction.execute_command(context, envelope, Callable(self, "_apply_submit_investigation").bind(input, str(envelope.get("transaction_id", "")))))

func _apply_start_consultation(working_context, input: Dictionary, transaction_id: String) -> Dictionary:
	var case_id := str(input.get("case_id", ""))
	var character_id := str(input.get("character_id", ""))
	var case_record: Dictionary = working_context.state.accountability_cases.get(case_id, {}) if working_context.state.accountability_cases.get(case_id, {}) is Dictionary else {}
	var subject_ids: Array = case_record.get("subject_ids", []) if case_record.get("subject_ids", []) is Array else []
	if case_record.is_empty() or not working_context.state.character_states.has(character_id) or not subject_ids.has(character_id):
		return _fail("consultation adviser is not an authorized case subject", "invalid_character")
	if _has_adopted_subject_testimony(working_context.state, case_id, character_id):
		return _fail("this case subject has already given adopted testimony", "subject_already_interviewed")
	var existing_consultation := _find_active_case_consultation(working_context.state, case_id)
	if not existing_consultation.is_empty():
		var duplicate := _fail("case already has an active consultation", "consultation_already_open")
		duplicate["consultation_id"] = str(existing_consultation.get("consultation_id", ""))
		return duplicate
	var case_service := AccountabilityCaseServiceScript.new()
	var lifecycle := str(case_record.get("lifecycle", ""))
	if lifecycle == "dormant":
		return _fail("case is not open for consultation", "case_not_open")
	if lifecycle == "open":
		var transition: Dictionary = case_service.begin_investigation(working_context.state, case_id, {"kind": "consultation", "id": transaction_id})
		if not bool(transition.get("ok", false)):
			return transition
	elif lifecycle == "investigating":
		var consultation_ref: Dictionary = case_service.record_causal_ref(working_context.state, case_id, {"kind": "consultation", "id": transaction_id})
		if not bool(consultation_ref.get("ok", false)):
			return consultation_ref
	else:
		return _fail("case is not investigable", "invalid_lifecycle")
	var consultation_id := "consultation|case|%s" % transaction_id
	var memorial_id := "memorial|case|%s" % case_id
	var consultation := {"consultation_id": consultation_id, "case_id": case_id, "memorial_id": memorial_id, "adviser_id": character_id, "day": int(working_context.state.current_day), "position": "conditional_support", "recommended_action": "review_case", "required_offices": [], "required_resources": [], "location_id": "", "deadline_day": int(working_context.state.current_day) + 3, "visible_risks": [], "known_basis": [], "status": "open", "ability": 0, "reason": "", "choice": "", "public_text": "", "tone": "", "wording_source": "offline", "conversation_phase": "talking", "turns": [], "selected_turn_ids": [], "draft_text": "", "draft_source": "", "draft_order_id": ""}
	var governance: Dictionary = working_context.state.governance_state.duplicate(true)
	var consultations: Dictionary = governance.get("consultations", {}).duplicate(true)
	var memorials: Dictionary = governance.get("memorials", {}).duplicate(true)
	var memorial: Dictionary = memorials.get(memorial_id, {}).duplicate(true) if memorials.get(memorial_id, {}) is Dictionary else {}
	if memorial.is_empty():
		memorial = {"memorial_id": memorial_id, "sender_id": "li_heng", "topic": "accountability_case", "location_id": "", "resource_keys": [], "deadline_days": 3, "recommended_executor_ids": [], "visible_facts": [], "visible_resistance": [], "request_text": "", "filed_day": int(working_context.state.current_day), "status": "consulting", "source_kind": "accountability_case", "case_chain_id": case_id, "case_phase": "investigating", "activated_day": int(working_context.state.current_day), "deadline_day": int(working_context.state.current_day) + 3, "consultation_ids": [], "active_council_id": "", "order_id": "", "closed_day": -1, "outcome": "", "activation_variant": "accountability"}
	var consultation_ids: Array = memorial.get("consultation_ids", []).duplicate(true) if memorial.get("consultation_ids", []) is Array else []
	if not consultation_ids.has(consultation_id):
		consultation_ids.append(consultation_id)
	memorial["consultation_ids"] = consultation_ids
	consultations[consultation_id] = consultation
	memorials[memorial_id] = memorial
	governance["consultations"] = consultations
	governance["memorials"] = memorials
	working_context.state.governance_state = governance
	return {"ok": true, "code": "consultation_started", "consultation_id": consultation_id, "result_ref": consultation_id}

func _apply_submit_investigation(working_context, input: Dictionary, transaction_id: String) -> Dictionary:
	var case_id := str(input.get("case_id", ""))
	var case_record: Dictionary = working_context.state.accountability_cases.get(case_id, {}) if working_context.state.accountability_cases.get(case_id, {}) is Dictionary else {}
	if case_record.is_empty():
		return _fail("unknown accountability case", "unknown_case")
	var service := AccountabilityCaseServiceScript.new()
	if str(case_record.get("lifecycle", "")) == "open":
		var begun: Dictionary = service.begin_investigation(working_context.state, case_id, {"kind": "transaction", "id": transaction_id})
		if not bool(begun.get("ok", false)):
			return begun
	var ready: Dictionary = service.mark_ready(working_context.state, case_id, {"kind": "transaction", "id": transaction_id})
	if not bool(ready.get("ok", false)):
		return ready
	return {"ok": true, "code": "investigation_submitted", "case_id": case_id, "result_ref": case_id}

func _apply_publish_consultation(working_context, input: Dictionary, transaction_id: String) -> Dictionary:
	var consultation_id := str(input.get("consultation_id", ""))
	var selected: Array = input.get("selected_turn_ids", []) if input.get("selected_turn_ids", []) is Array else []
	var governance: Dictionary = working_context.state.governance_state.duplicate(true)
	var consultation: Dictionary = governance.get("consultations", {}).get(consultation_id, {}).duplicate(true)
	if consultation.is_empty() or selected.is_empty():
		return _fail("consultation or selected turns are unavailable", "consultation_unavailable")
	var case_id := str(consultation.get("case_id", ""))
	var memorial_id := str(consultation.get("memorial_id", ""))
	var memorial: Dictionary = governance.get("memorials", {}).get(memorial_id, {}).duplicate(true)
	var memorial_consultation_ids: Array = memorial.get("consultation_ids", []) if memorial.get("consultation_ids", []) is Array else []
	if case_id.is_empty() or memorial.is_empty() or str(memorial.get("source_kind", "")) != "accountability_case" or str(memorial.get("case_chain_id", "")) != case_id or not memorial_consultation_ids.has(consultation_id):
		return _fail("consultation does not belong to an accountability case", "invalid_case_consultation")
	if str(consultation.get("status", "")) != "open":
		return _fail("consultation is already published or closed", "consultation_not_open")
	var known_turns: Array = consultation.get("turns", []) if consultation.get("turns", []) is Array else []
	for turn_id in selected:
		var found := false
		for turn in known_turns:
			if turn is Dictionary and str((turn as Dictionary).get("turn_id", "")) == str(turn_id) and bool((turn as Dictionary).get("selectable", false)):
				found = true
				break
		if not found:
			return _fail("selected consultation turn is unavailable", "turn_unavailable")
	consultation["selected_turn_ids"] = selected.duplicate(true)
	consultation["status"] = "adopted"
	consultation["conversation_phase"] = "selecting"
	var case_service := AccountabilityCaseServiceScript.new()
	var evidence: Dictionary = case_service.attach_evidence(working_context.state, case_id, {"evidence_id": "evidence|consultation|%s" % transaction_id, "kind": "consultation", "ref_id": consultation_id}, {"kind": "consultation", "id": transaction_id})
	if not bool(evidence.get("ok", false)):
		return evidence
	var claim: Dictionary = case_service.attach_claim(working_context.state, case_id, {"claim_id": "claim|consultation|%s" % transaction_id, "character_id": str(consultation.get("adviser_id", "")), "fact_ids": []}, {"kind": "consultation", "id": transaction_id})
	if not bool(claim.get("ok", false)):
		return claim
	var consultations: Dictionary = governance.get("consultations", {}).duplicate(true)
	consultations[consultation_id] = consultation
	governance["consultations"] = consultations
	working_context.state.governance_state = governance
	return {"ok": true, "code": "consultation_published", "result_ref": consultation_id, "claim_refs": [{"kind": "claim", "id": "claim|consultation|%s" % transaction_id}], "evidence_refs": [{"kind": "evidence", "id": "evidence|consultation|%s" % transaction_id}], "transaction_id": transaction_id}

func _apply_verdict_transaction(working_context, raw_input: Variant, transaction_id: String) -> Dictionary:
	if not raw_input is Dictionary:
		return _fail("verdict input is invalid", "invalid_command_payload")
	var input: Dictionary = raw_input
	var service := AccountabilityCaseServiceScript.new()
	var case_id := str(input.get("case_id", ""))
	var verdict_id := str(input.get("verdict_id", ""))
	var decision: Dictionary = input.get("decision", {}) if input.get("decision", {}) is Dictionary else {}
	var case_record: Dictionary = working_context.state.accountability_cases.get(case_id, {}) if working_context.state.accountability_cases.get(case_id, {}) is Dictionary else {}
	if verdict_id == "forced_removal":
		var office_ids: Array = case_record.get("office_ids", []) if case_record.get("office_ids", []) is Array else []
		var office_id := str(decision.get("office_id", ""))
		var holder_id := str(decision.get("holder_id", ""))
		var office: Dictionary = working_context.state.office_state.get(office_id, {}) if working_context.state.office_state.get(office_id, {}) is Dictionary else {}
		var expected_target := _forced_removal_target(working_context.state, case_record)
		if office_ids.find(office_id) < 0 or holder_id.is_empty() or str(office.get("holder_id", "")) != holder_id or expected_target.get("office_id", "") != office_id or expected_target.get("holder_id", "") != holder_id:
			return _fail("forced removal target does not match the ready case", "invalid_verdict_target")
	var result: Dictionary = service.apply_verdict(working_context.state, case_id, verdict_id, decision, transaction_id, {"kind": "verdict", "id": transaction_id})
	if not bool(result.get("ok", false)):
		return result
	var effects: Dictionary = AccountabilityVerdictEffectServiceScript.new().apply(working_context.state, working_context.scenario_data, case_id, verdict_id, transaction_id)
	if not bool(effects.get("ok", false)):
		return effects
	result["effects"] = effects.duplicate(true)
	if verdict_id == "forced_removal":
		var removal: Dictionary = OfficeServiceScript.new().apply_removal(working_context.state, str(decision.get("office_id", "")), transaction_id, true)
		if not bool(removal.get("ok", false)):
			return removal
		result["removal"] = removal.duplicate(true)
	var affected_ids: Array = _affected_character_ids(working_context.scenario_data, case_record, decision, result)
	var fate_result: Dictionary = CharacterArcServiceScript.new().reconcile_characters(working_context.state, working_context.scenario_data, affected_ids, int(working_context.state.current_day))
	if not bool(fate_result.get("ok", false)):
		return fate_result
	result["character_fate"] = fate_result.duplicate(true)
	return result

func _affected_character_ids(data: Dictionary, case_record: Dictionary, decision: Dictionary, result: Dictionary) -> Array:
	var candidates: Array = []
	for raw_subject_id in case_record.get("subject_ids", []) if case_record.get("subject_ids", []) is Array else []:
		candidates.append(str(raw_subject_id))
	for raw_claim in case_record.get("claims", []) if case_record.get("claims", []) is Array else []:
		if raw_claim is Dictionary:
			candidates.append(str((raw_claim as Dictionary).get("character_id", "")))
	candidates.append(str(decision.get("holder_id", "")))
	var removal: Dictionary = result.get("removal", {}) if result.get("removal", {}) is Dictionary else {}
	candidates.append(str(removal.get("holder_id", "")))
	return CharacterArcServiceScript.new().supported_character_ids(data, candidates)

func _fail(message: String, code: String) -> Dictionary:
	var impact := "权威案件状态未改变。"
	var next_step := "返回案卷并按提示继续调查或重试。"
	match code:
		"stale_preview":
			impact = "预览已失效，尚未写入裁决或任何后果。"
			next_step = "重新打开裁决预览，核对最新案卷后再确认。"
		"missing_effect", "command_failed", "transaction_commit_failed", "transaction_validation_failed":
			impact = "确认未提交，案件仍保持可复核的原状态。"
			next_step = "返回案卷核对公开后果配置，再重新预览；不要重复确认旧令牌。"
		"consequence_unavailable":
			impact = "案件已经裁决，但当前页面无法读取其后果回执。"
			next_step = "刷新案卷并查看裁决回执与时间线。"
		"idempotent_replay":
			impact = "重复提交没有再次写入状态或产生新后果。"
			next_step = "继续查看调查结果或打开裁决预览。"
	return {"ok": false, "code": code, "reason_code": code, "error": message, "message": message, "summary": message, "impact": impact, "next_step": next_step}

func _public_failure(result: Dictionary) -> Dictionary:
	if bool(result.get("ok", false)):
		return result
	var code := str(result.get("reason_code", result.get("code", "accountability_command_failed")))
	var message := str(result.get("summary", result.get("error", result.get("message", "问责操作未完成。"))))
	return _fail(message, code)

func _find_case_effect(data: Dictionary, case_id: String) -> Dictionary:
	var container: Variant = data.get("accountability_effects", {})
	var entries: Variant = container.get("case_effects", []) if container is Dictionary else data.get("beta110_accountability_effects", [])
	for raw_entry in entries if entries is Array else []:
		if raw_entry is Dictionary and str((raw_entry as Dictionary).get("case_id", "")) == case_id:
			return (raw_entry as Dictionary).duplicate(true)
	return {}

func _forced_removal_target(state, case_record: Dictionary) -> Dictionary:
	var subject_ids: Array = case_record.get("subject_ids", []) if case_record.get("subject_ids", []) is Array else []
	var office_ids: Array = case_record.get("office_ids", []) if case_record.get("office_ids", []) is Array else []
	var candidates: Array = []
	for raw_office_id in office_ids:
		var office_id := str(raw_office_id)
		var office: Dictionary = state.office_state.get(office_id, {}) if state.office_state.get(office_id, {}) is Dictionary else {}
		var holder_id := str(office.get("holder_id", ""))
		if str(office.get("status", "")) == "appointed" and not holder_id.is_empty() and subject_ids.has(holder_id):
			candidates.append({"office_id": office_id, "holder_id": holder_id})
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(left: Dictionary, right: Dictionary): return str(left.get("office_id", "")) < str(right.get("office_id", "")))
	return (candidates[0] as Dictionary).duplicate(true)

func _find_active_case_consultation(state, case_id: String) -> Dictionary:
	if state == null or not state.governance_state is Dictionary:
		return {}
	var consultations: Variant = state.governance_state.get("consultations", {})
	if not consultations is Dictionary:
		return {}
	for raw_consultation in consultations.values():
		if not raw_consultation is Dictionary:
			continue
		var consultation: Dictionary = raw_consultation
		if str(consultation.get("case_id", "")) == case_id and str(consultation.get("status", "")) == "open":
			return consultation.duplicate(true)
	return {}

func _has_adopted_subject_testimony(state, case_id: String, character_id: String) -> bool:
	if state == null or not state.governance_state is Dictionary:
		return false
	var consultations: Variant = state.governance_state.get("consultations", {})
	if not consultations is Dictionary:
		return false
	for raw_consultation in consultations.values():
		if raw_consultation is Dictionary and str((raw_consultation as Dictionary).get("case_id", "")) == case_id and str((raw_consultation as Dictionary).get("adviser_id", "")) == character_id and str((raw_consultation as Dictionary).get("status", "")) == "adopted":
			return true
	return false
