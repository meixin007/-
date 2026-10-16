extends RefCounted
const C = preload("res://scripts/core/npc_ai_state_contract.gd")
const Canonical = preload("res://scripts/core/canonical_json.gd")

static func validate_terms(_state, terms: Variant) -> Dictionary:
	if not C.exact(terms, ["plan", "resource_limits"]): return C.fail("委托须包含实际步骤和累计资金上限")
	return load("res://scripts/ai/npc_decision_parser.gd").new().parse({"schema_version": 1, "kind": "plan", "reason_code": "actual_mandate", "action": {}, "plan": terms.plan, "resource_limits": terms.resource_limits})

static func fulfill(state, data: Dictionary, row: Dictionary, execution: String) -> Dictionary:
	var principal: String = row.principal_id
	var delegate: String = row.participant_ids[1]
	if state.character_states[principal].get("status") in ["dead", "deceased", "executed", "imprisoned", "missing"] or state.character_states[delegate].get("status") in ["dead", "deceased", "executed", "imprisoned", "missing"]: return C.fail("委托双方当前无法实际签发或经办")
	var kinds: Array = []
	var targets: Array = []
	for step in row.terms.plan.steps:
		if not kinds.has(step.action_kind): kinds.append(step.action_kind)
		for ref in step.target_refs:
			if not targets.has(ref): targets.append(ref)
	var auth := {"authorization_id": "npc-auth:" + execution, "principal_id": principal, "delegate_id": delegate, "scope": {"action_kinds": kinds, "target_refs": targets, "allow_subdelegation": false}, "resource_limits": row.terms.resource_limits.duplicate(true), "version": 1, "status": "active", "valid_until_day": null}
	var plan := {"task_id": "npc-task:" + execution, "name": row.terms.plan.name, "executor_id": delegate, "steps": row.terms.plan.steps.duplicate(true)}
	var result: Dictionary = load("res://scripts/core/action_authorization_service.gd")._submit({"state": state, "scenario_data": data}, {"authorization": auth, "plan": plan, "execution_id": execution}, principal, row.contract_id)
	if not result.ok: return result
	row.status = "fulfilled"
	row.result_refs = [result.result_ref]
	var informed: Dictionary = load("res://scripts/core/social_agreement_service.gd").communicate(state, row, principal, execution)
	if not informed.ok: return informed
	return {"ok": true, "result_ref": row.contract_id, "outcome": "fulfilled", "effect_refs": [row.contract_id, result.result_ref], "visible_summary": "已按双方接受的步骤签发真实授权并预留资金，经办进入原任务队列。"}

static func validate_consent(raw: Dictionary, auth: Dictionary, task: Dictionary) -> Dictionary:
	var consent: Dictionary = auth.consent_source
	if not C.exact(consent, ["kind", "agreement_id", "terms_version", "accepted_day", "principal_id", "delegate_id", "terms_hash"]): return C.fail("委托授权同意字段无效")
	var row: Dictionary = raw.economic_contracts.get(consent.agreement_id, {})
	if row.get("purpose") != "delegated_plan" or row.get("status") != "fulfilled" or row.get("principal_id") != auth.principal_id or row.get("participant_ids", []) != [auth.principal_id, auth.delegate_id] or row.get("terms_version") != consent.terms_version or row.get("terms_hash") != consent.terms_hash or not row.get("result_refs", []).has(task.task_id): return C.fail("委托授权丢失具体双方约定")
	if consent.principal_id != auth.principal_id or consent.delegate_id != auth.delegate_id or not C.whole(consent.accepted_day, 0) or consent.accepted_day > raw.current_day or row.terms.resource_limits != auth.resource_limits or task.get("source_agreement_id") != row.contract_id or task.get("source_type") != "social_agreement" or task.steps.size() != row.terms.plan.steps.size(): return C.fail("任务改变了已同意的主体或预算")
	for index in task.steps.size():
		var actual := {}
		for field in ["step_id", "action_kind", "parameters", "target_refs", "depends_on"]: actual[field] = task.steps[index][field]
		if Canonical.hash_value(actual).hash != Canonical.hash_value(row.terms.plan.steps[index]).hash: return C.fail("任务步骤改变了本人接受的条件")
	return {"ok": true}
