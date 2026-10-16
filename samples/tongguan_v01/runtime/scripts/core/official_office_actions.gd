extends RefCounted

const Offices = preload("res://scripts/core/office_service.gd")
const Contract = preload("res://scripts/core/management_state_contract.gd")
const KINDS := ["appoint_office", "dismiss_office", "force_dismiss_office"]

static func project(state, data: Dictionary, principal: String) -> Array:
	var service = Offices.new()
	var result: Array = []
	var catalog = preload("res://scripts/domain/tang_office_catalog.gd")
	var seen: Array = []
	for office in state.office_state.values():
		if office.get("office_kind") == "family" or office.office_id == "imperial_court" or not service.validate_actor_authority(state, office.office_id, principal).get("ok", false): continue
		var canonical: String = catalog.canonical_id(office.office_id)
		if seen.has(canonical): continue
		seen.append(canonical)
		var aliases: Array = []
		for alias in catalog.get_legacy_aliases_for(canonical):
			if state.office_state.has(alias): aliases.append(alias)
		var row := {"office_id": canonical, "aliases": aliases, "name": str(office.get("name", "")), "holder_id": str(office.get("holder_id", "")), "status": str(office.get("status", "")), "candidates": []}
		if office.get("office_kind") == "regional" and office.has("remuneration_terms"): row["remuneration_terms"] = office.remuneration_terms.duplicate(true)
		var authority: Dictionary = service.validate_actor_authority(state, office.office_id, principal)
		if authority.has("authority_ref"):
			row["authority_ref"] = authority.authority_ref.duplicate(true)
			row["authority_holder_id"] = authority.authority_holder_id
		for person in data.get("characters", []):
			var assessed: Dictionary = service.assess_appointment_candidate(state, data, office.office_id, person.id)
			if not assessed.get("appointment_available", false): continue
			row.candidates.append({"character_id": person.id, "mode": assessed.appointment_mode})
		result.append(row)
	return result

static func cost_for(state, kind: String, params: Dictionary) -> Dictionary:
	var fields: Array = ["office_id", "candidate_id", "mode"] if kind == "appoint_office" else ["office_id", "holder_id"]
	if params.size() != fields.size(): return Contract.fail("正式任免参数必须完整，不接受附带权力或结果")
	for field in fields:
		if not params.get(field) is String or str(params[field]).is_empty(): return Contract.fail("正式任免缺少实际对象：" + field)
	var office: Dictionary = state.office_state.get(params.office_id, {})
	if office.is_empty() or office.get("office_kind") == "family" or params.office_id == "imperial_court": return Contract.fail("需要实际臣属职位；家族聘用或继承须使用对应程序")
	if kind == "appoint_office" and (not state.character_states.has(params.candidate_id) or params.mode not in ["normal", "exceptional"]): return Contract.fail("任命候选或任用方式无效")
	if kind != "appoint_office" and not state.character_states.has(params.holder_id): return Contract.fail("免职须指明实际在任者")
	# Existing political costs remain in OfficeService; they are not cash or free grants.
	return {"ok": true, "account_id": "", "amount": 0}

static func apply(state, data: Dictionary, kind: String, params: Dictionary, principal: String, execution: String) -> Dictionary:
	var valid := cost_for(state, kind, params)
	if not valid.ok: return valid
	var service = Offices.new()
	valid = service.validate_actor_authority(state, params.office_id, principal)
	if not valid.ok: return valid
	if kind != "appoint_office" and state.office_state[params.office_id].get("holder_id") != params.holder_id: return Contract.fail("在任者已经变化，请重新核对免职对象")
	var before: String = state.rule_payload_hash_without_revision()
	var result: Dictionary
	if kind == "appoint_office":
		var input: Dictionary = params.duplicate(true)
		input["actor_id"] = principal
		result = service.apply_appointment(state, data, input, execution)
	else:
		result = service.apply_removal(state, params.office_id, execution, kind == "force_dismiss_office", principal)
	if result.get("ok", false) and result.get("code") != "no_op":
		var regional: Dictionary = load("res://scripts/core/regional_office_rules.gd").after_office_change(state, params.office_id)
		if not regional.get("ok", false):
			regional["rollback_required"] = before != state.rule_payload_hash_without_revision()
			return regional
		var arc = preload("res://scripts/core/character_arc_service.gd").new()
		var people: Array = [str(result.get("candidate_id", "")), str(result.get("previous_holder_id", "")), str(result.get("holder_id", ""))]
		var fate: Dictionary = arc.reconcile_characters(state, data, arc.supported_character_ids(data, people), int(state.current_day))
		if not fate.get("ok", false): result = fate
		else: result["character_fate"] = fate
	if not result.get("ok", false):
		# The enclosing daily transaction must roll back any partially applied rule.
		result["rollback_required"] = before != state.rule_payload_hash_without_revision()
		return result
	result["result_ref"] = str(result.get("term_id", params.office_id))
	var term_ref := str(result.get("term_id", ""))
	if kind == "appoint_office" and term_ref.is_empty():
		for term in state.office_terms.values():
			if term.get("holder_id") == params.candidate_id and int(term.get("end_day", 0)) < 0 and _same_office(str(term.get("office_id", "")), params.office_id): term_ref = str(term.term_id); break
		if term_ref.is_empty(): return Contract.fail("原任命缺少实际任职记录，未登记重复办理")
		result.result_ref = term_ref
	result["official_record"] = {"action_kind": kind, "office_id": params.office_id, "principal_id": principal, "subject_id": params.get("candidate_id", params.get("holder_id", "")), "term_ref": term_ref, "unchanged": result.get("code") == "no_op"}
	if kind == "appoint_office" and state.office_terms.get(term_ref, {}).has("education_ref"):
		result.official_record["education_ref"] = state.office_terms[term_ref].education_ref
	if kind == "appoint_office" and state.office_terms.get(term_ref, {}).has("education_entry"):
		result.official_record["education_entry"] = state.office_terms[term_ref].education_entry.duplicate(true)
	if kind == "appoint_office" and state.office_terms.get(term_ref, {}).has("appointment_entry"):
		result.official_record["appointment_entry"] = state.office_terms[term_ref].appointment_entry.duplicate(true)
	result["visible_summary"] = ("任命已按规则登记：" if kind == "appoint_office" else "免职已按规则登记：") + str(state.office_state[params.office_id].get("name", params.office_id))
	var observation: Dictionary=preload("res://scripts/core/regional_office_knowledge.gd").observe_local(state)
	if not observation.ok:
		observation["rollback_required"]=true
		return observation
	return result

static func _same_office(first: String, second: String) -> bool:
	return preload("res://scripts/domain/tang_office_catalog.gd").canonical_id(first) == preload("res://scripts/domain/tang_office_catalog.gd").canonical_id(second)

static func validate(raw: Dictionary) -> Dictionary:
	var receipts: Dictionary = raw.get("action_receipts", {})
	var terms: Variant = raw.get("office_terms")
	var history: Variant = raw.get("office_history")
	if not terms is Dictionary or not history is Array: return Contract.fail("正式任免缺少任职与离任历史容器")
	for id in receipts:
		var receipt: Dictionary = receipts[id]
		if not receipt.has("official_record"): continue
		var record: Variant = receipt.official_record
		if not record is Dictionary or record.get("action_kind") not in KINDS or not raw.office_state.has(record.get("office_id")) or not raw.character_states.has(record.get("principal_id")) or not raw.character_states.has(record.get("subject_id")) or not record.get("term_ref") is String or not record.get("unchanged") is bool: return Contract.fail("正式任免回执丢失实际主体或职位")
		if record.action_kind == "appoint_office":
			var term: Variant = terms.get(record.term_ref, {})
			if not term is Dictionary or term.is_empty() or not _same_office(str(term.get("office_id", "")), record.office_id) or term.get("holder_id") != record.subject_id or not receipt.effect_refs.has(record.term_ref) or (not record.unchanged and term.get("appointment_transaction_id") != id): return Contract.fail("正式任命回执丢失实际任职历史")
		elif not receipt.effect_refs.has(record.office_id) or not history.any(func(entry): return entry is Dictionary and entry.get("transaction_id") == id and _same_office(str(entry.get("office_id", "")), record.office_id) and entry.get("previous_holder_id") == record.subject_id and entry.get("holder_id", "") == "" and entry.get("forced", false) == (record.action_kind == "force_dismiss_office")):
			return Contract.fail("正式免职回执丢失真实离任历史")
	for term in terms.values():
		if not term is Dictionary: return Contract.fail("正式任职历史记录类型无效")
		var id := str(term.get("appointment_transaction_id", ""))
		if receipts.has(id) and raw.office_state.get(term.get("office_id", ""), {}).get("office_kind") != "family" and not receipts[id].has("official_record"): return Contract.fail("任职历史的共同回执丢失任免主体")
	for entry in history:
		if entry is Dictionary and entry.get("source") == "accountability_verdict" and receipts.has(entry.get("transaction_id")) and not receipts[entry.transaction_id].has("official_record"): return Contract.fail("离任历史的共同回执丢失任免主体")
	for transaction in raw.get("processed_transactions", {}).values():
		if transaction.get("kind") == "game_action" or (transaction.get("kind") in KINDS and transaction.get("result_ref") == transaction.get("transaction_id")):
			if not receipts.has(transaction.get("result_ref")): return Contract.fail("已提交共同动作丢失执行回执")
	return preload("res://scripts/core/school_appointment_rules.gd").validate_terms(raw)

static func manual(context, kind: String, params: Dictionary, execution: String) -> Dictionary:
	var player: String = context.state.player_character_id
	var targets: Array = [params.office_id, params.get("candidate_id", params.get("holder_id", ""))]
	var request := {"execution_id": execution, "request_id": execution, "actor_id": player, "principal_id": player, "executor_id": player, "action_kind": kind, "target_refs": targets, "parameters": params, "expected_state_revision": context.state.state_revision}
	var result: Dictionary = load("res://scripts/core/game_action_dispatcher.gd").apply(context.state, context.scenario_data, request)
	if not result.get("ok", false): return result
	var domain: Dictionary = result.get("domain_result", {}).duplicate(true)
	domain["ok"] = true
	domain["result_ref"] = result.result_ref
	return domain
