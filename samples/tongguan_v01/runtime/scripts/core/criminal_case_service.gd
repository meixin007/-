extends RefCounted
const C = preload("res://scripts/core/npc_ai_state_contract.gd")
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Info = preload("res://scripts/core/information_propagation_service.gd")
const Canonical = preload("res://scripts/core/canonical_json.gd")
const SOURCE := "scenario:criminal_case_game_model_756"
const KINDS := ["open_criminal_case", "issue_criminal_verdict", "order_criminal_release", "release_criminal_custody", "petition_criminal_case"]
const CASE_FIELDS := ["case_id", "case_kind", "source_id", "incident_id", "lifecycle", "subject_ids", "victim_ids", "victim_kin_ids", "office_ids", "term_ids", "causal_refs", "facts", "claims", "evidence", "jurisdiction_office_id", "location_id", "detention", "decision", "decision_transaction_id", "release_order", "petitions", "created_day"]
const INCIDENT_FIELDS := ["case_id", "incident_id", "jurisdiction_office_id", "location_id", "accused_id", "victim_id", "victim_kin_ids", "summary"]

func execute(context, actor: String, kind: String, params: Dictionary, execution: String) -> Dictionary:
	var dispatcher = load("res://scripts/core/game_action_dispatcher.gd").new()
	var targets: Array = [params.get("case_id", params.get("destination_id", ""))]
	var selection := {"action_kind": kind, "parameters": params, "target_refs": targets}
	return dispatcher.execute(context, dispatcher.bind_npc_request(context.state, actor, selection, execution)) if actor == context.state.player_character_id else dispatcher.execute_npc(context, actor, selection, execution)

static func initialize(state, data: Dictionary) -> Dictionary:
	var config: Dictionary = data.get("management", {}).get("criminal_cases", {})
	if config.is_empty(): return {"ok": true}
	if config.get("source_id") != SOURCE or not config.get("jurisdictions") is Array or not config.get("initial_cases") is Array: return C.fail("刑事玩法缺少实际配置来源")
	state.flags["criminal_case_rules"] = config.duplicate(true)
	for incident in config.initial_cases:
		var id: String = incident.incident_id
		state.record_event_history(id, "occurred", {"source_id": SOURCE, "case_id": incident.case_id, "summary": incident.summary})
		var fact := "crime-fact:" + id
		var judge: String = state.office_state[incident.jurisdiction_office_id].holder_id
		var jailer: String = jurisdiction(state, incident.jurisdiction_office_id).custodian_id
		var created: Dictionary = Info.new().create_fact(state, {"fact_id": fact, "truth_payload": incident.duplicate(true), "holders": [judge, jailer, incident.accused_id] + incident.victim_kin_ids, "secrecy": "case_participants", "source_context": {"context_kind": "office_observation", "context_id": fact, "related_report_id": id}})
		if not created.ok: return created
		var execution: String = "seed:" + str(incident.case_id)
		var opened: Dictionary = open_record(state, incident, judge, execution)
		if not opened.ok: return opened
		state.action_receipts[execution] = {"execution_id": execution, "request_id": execution, "status": "committed", "reason_code": "scenario_custody", "effect_refs": [incident.case_id], "journal_refs": [], "authorization_id": "", "task_id": "", "step_id": "", "executor_id": jailer, "day": state.current_day, "input_hash": Canonical.hash_value(incident).hash, "state_revision_after": maxi(1, state.state_revision), "visible_summary": incident.summary}
	return {"ok": true}

static func jurisdiction(state, office: String) -> Dictionary:
	for row in state.flags.get("criminal_case_rules", {}).get("jurisdictions", []):
		if row.office_id == office: return row
	return {}

static func judge_authority(state, record: Dictionary, actor: String) -> bool:
	var rule: Dictionary = jurisdiction(state, record.jurisdiction_office_id)
	var office: Dictionary = state.office_state.get(record.jurisdiction_office_id, {})
	return not rule.is_empty() and rule.location_id == record.location_id and office.get("holder_id") == actor and office.get("status") == "appointed" and state.character_states[actor].get("location_id") == record.location_id

static func physical_control(state, record: Dictionary, actor: String) -> bool:
	var detention: Dictionary = record.detention
	if detention.status != "held" or detention.custodian_id != actor or state.character_states[actor].get("location_id") != detention.location_id or state.character_states[record.subject_ids[0]].get("location_id") != detention.location_id: return false
	var controller: Dictionary = state.control_relations.get("ctrl|node|" + detention.location_id, {})
	if not controller.is_empty() and controller.get("strength", 0) > 0 and controller.get("controller_id") != detention.controller_id: return false
	return state.local_node_state.get(detention.location_id, {}).get("active_office_holder", detention.controller_id) in ["", detention.controller_id]

static func cost_for(state, kind: String, params: Dictionary) -> Dictionary:
	if kind == "open_criminal_case":
		if not state.information_truths.has(params.get("fact_id")) or not state.office_state.has(params.get("jurisdiction_office_id")) or not C.text_id(params.get("case_id")): return C.fail("立案须引用已经发生的实际事件与管辖职位")
	elif state.accountability_cases.get(params.get("case_id"), {}).get("case_kind") != "criminal": return C.fail("这份刑事案件不存在")
	return {"ok": true, "account_id": "", "amount": 0}

static func open_record(state, incident: Dictionary, actor: String, execution: String) -> Dictionary:
	if not C.exact(incident, INCIDENT_FIELDS) or not incident.get("victim_kin_ids") is Array or incident.victim_kin_ids.size() > 16 or not incident.get("summary") is String: return C.fail("立案事件不具备完整真实命案来源")
	for field in ["case_id", "incident_id", "jurisdiction_office_id", "location_id", "accused_id", "victim_id"]:
		if not C.text_id(incident[field]): return C.fail("命案来源缺少稳定对象引用")
	var rule: Dictionary = jurisdiction(state, incident.jurisdiction_office_id)
	if rule.is_empty() or rule.location_id != incident.location_id or state.accountability_cases.has(incident.case_id) or not state.event_history.any(func(row): return row.get("event_id") == incident.incident_id): return C.fail("案件来源、地域或身份无效")
	if state.accountability_cases.values().any(func(row): return row.get("incident_id") == incident.incident_id): return C.fail("同一实际事件已有案卷，须在原案复查而非重复复制")
	for id in [incident.accused_id, incident.victim_id, rule.custodian_id] + incident.victim_kin_ids:
		if not state.character_states.has(id): return C.fail("涉案人物不存在")
	if state.character_states[incident.victim_id].get("status") not in ["dead", "deceased", "executed"] or state.character_states[incident.accused_id].get("location_id") != incident.location_id or state.character_states[rule.custodian_id].get("location_id") != incident.location_id: return C.fail("命案与实际看管位置不成立")
	if state.accountability_cases.values().any(func(row): return row.get("case_kind") == "criminal" and row.get("subject_ids", []).has(incident.accused_id) and row.detention.status == "held"): return C.fail("人物已被另一案实际拘押，不能重复建立看管状态")
	var prior: String = state.character_states[incident.accused_id].status
	var record := {"case_id": incident.case_id, "case_kind": "criminal", "source_id": SOURCE, "incident_id": incident.incident_id, "lifecycle": "investigating", "subject_ids": [incident.accused_id], "victim_ids": [incident.victim_id], "victim_kin_ids": incident.victim_kin_ids.duplicate(), "office_ids": [incident.jurisdiction_office_id], "term_ids": [], "causal_refs": [{"kind": "event_history", "id": incident.incident_id}], "facts": [{"kind": "homicide", "incident_id": incident.incident_id, "victim_id": incident.victim_id, "summary": incident.summary}], "claims": [], "evidence": [{"kind": "incident", "ref_id": incident.incident_id}], "jurisdiction_office_id": incident.jurisdiction_office_id, "location_id": incident.location_id, "detention": {"status": "held", "custodian_id": rule.custodian_id, "controller_id": actor, "location_id": incident.location_id, "prior_status": prior, "opened_receipt": execution, "release_receipt": "", "release_kind": "", "released_day": -1}, "decision": {}, "decision_transaction_id": "", "release_order": {}, "petitions": [], "created_day": state.current_day}
	if not judge_authority(state, record, actor): return C.fail("立案经办人没有实际管辖权")
	state.accountability_cases[incident.case_id] = record
	state.character_states[incident.accused_id].status = "imprisoned"
	return {"ok": true, "result_ref": incident.case_id, "visible_summary": incident.summary}

static func apply(state, kind: String, params: Dictionary, actor: String, execution: String) -> Dictionary:
	if kind == "open_criminal_case":
		var claim: Dictionary = Info.new().get_claim(state, params.fact_id, actor)
		if claim.is_empty(): return C.fail("本人尚未收到实际案情，不能借全知事实立案")
		var incident: Dictionary = state.information_truths[params.fact_id].truth_payload.duplicate(true)
		if not C.exact(incident, INCIDENT_FIELDS): return C.fail("所知消息并非已有实际命案事件")
		incident["case_id"] = params.case_id
		if incident.get("jurisdiction_office_id") != params.jurisdiction_office_id: return C.fail("提议管辖与事件来源不符")
		return open_record(state, incident, actor, execution)
	var record: Dictionary = state.accountability_cases[params.case_id]
	if kind == "petition_criminal_case":
		if not state.information_claims.values().any(func(claims): return claims.get(actor, {}).get("payload", {}).get("case_id") == record.case_id): return C.fail("本人尚未实际获知案件")
		if not params.get("request_text") is String or params.request_text.is_empty() or params.request_text.length() > 512: return C.fail("求援需具体诉求")
		record.petitions.append({"actor_id": actor, "request_text": params.request_text, "execution_id": execution, "day": state.current_day})
		return {"ok": true, "result_ref": record.case_id, "visible_summary": "已登记本人求援诉求，裁判与拘押尚未改变。"}
	if kind in ["issue_criminal_verdict", "order_criminal_release"]:
		if not judge_authority(state, record, actor): return C.fail("本人已失去案件签判权或尚未到实际管辖地")
		if kind == "issue_criminal_verdict":
			if not jurisdiction(state, record.jurisdiction_office_id).permitted_verdicts.has(params.get("verdict")): return C.fail("此裁判尚无本地制度规则；重刑须另有实际复核流程")
			if not record.decision.is_empty(): return C.fail("已有签判须走重新审理，不能直接覆写旧案卷")
			record.decision = {"verdict": params.verdict, "signed_by": actor, "day": state.current_day, "execution_id": execution}
			record.decision_transaction_id = execution
			record.lifecycle = "decided"
			var announced: Dictionary = publish_event(state, record, actor, execution, "verdict", false)
			if not announced.ok: return announced
			return {"ok": true, "result_ref": record.case_id, "visible_summary": "已签判：" + params.verdict + "；实际拘押须另由看管人执行。"}
		if record.decision.get("verdict") != "acquit": return C.fail("尚无无罪签判作为合法释放的权源")
		record.release_order = {"signed_by": actor, "execution_id": execution, "day": state.current_day}
		var sent := publish_event(state, record, actor, execution, "release_order", false)
		if not sent.ok: return sent
		return {"ok": true, "result_ref": record.case_id, "visible_summary": "已签释放令，等待具名看管人实际执行。"}
	if params.get("release_kind") not in ["legal", "private"] or not physical_control(state, record, actor): return C.fail("看管人、实际位置或控制不足，不能伪造释放")
	if params.release_kind == "legal":
		if record.release_order.is_empty() or not judge_authority(state, record, record.release_order.signed_by) or state.character_states[actor].get("relationships", {}).get(record.release_order.signed_by, 0) < 0: return C.fail("释放令权源或执行者服从不足，拘押继续保留")
	else: record.evidence.append({"kind": "unauthorized_release", "ref_id": execution, "responsible_id": actor, "day": state.current_day})
	record.detention.status = "released"
	record.detention.release_receipt = execution
	record.detention.release_kind = params.release_kind
	record.detention.released_day = state.current_day
	state.character_states[record.subject_ids[0]].status = record.detention.prior_status
	var announced: Dictionary = publish_event(state, record, actor, execution, "private_release" if params.release_kind == "private" else "legal_release", params.release_kind == "private")
	if not announced.ok: return announced
	return {"ok": true, "result_ref": record.case_id, "visible_summary": "看管人已实际释放；原命案、案卷及责任记录继续保留。"}

static func publish_event(state, record: Dictionary, actor: String, execution: String, event_kind: String, secret: bool) -> Dictionary:
	var id := "case-event:" + execution
	var parties: Array = [actor, record.subject_ids[0], record.detention.custodian_id]
	if not secret:
		for person in record.victim_kin_ids:
			if not parties.has(person): parties.append(person)
	var holders: Array = parties.filter(func(person): return person == actor or state.character_states[person].get("location_id") == state.character_states[actor].get("location_id"))
	var made: Dictionary = Info.new().create_fact(state, {"fact_id": id, "truth_payload": {"case_id": record.case_id, "social_event_kind": event_kind, "responsible_id": actor, "beneficiary_id": record.subject_ids[0], "victim_ids": record.victim_ids.duplicate(), "victim_kin_ids": record.victim_kin_ids.duplicate(), "location_id": record.location_id, "verdict": record.decision.get("verdict", ""), "release_order": record.release_order.duplicate(true), "summary": "案情处理：" + event_kind}, "holders": holders, "secrecy": "private" if secret else "case_participants", "source_context": {"context_kind": "office_observation", "context_id": id, "related_report_id": execution}})
	if not made.ok: return made
	if not secret:
		for person in parties:
			if holders.has(person): continue
			var sent: Dictionary = Info.new().queue_dispatch(state, id, actor, person)
			if not sent.ok: return sent
	return {"ok": true}

static func validate_bribe(state, terms: Variant) -> Dictionary:
	if not C.exact(terms, ["case_id", "intended_action", "amount", "funding_account_id"]) or state.accountability_cases.get(terms.case_id, {}).get("case_kind") != "criminal" or terms.intended_action not in ["acquit", "private_release"] or not C.whole(terms.amount, 1) or state.resource_accounts.get(terms.funding_account_id, {}).get("unit_id") != "cash_unit": return C.fail("行贿提议须引用实际案件、付款及可区分的企图")
	return {"ok": true}

static func validate(raw: Dictionary) -> Dictionary:
	var detained := {}
	for id in raw.get("accountability_cases", {}):
		var row: Dictionary = raw.accountability_cases[id]
		if row.get("case_kind", "official_accountability") != "criminal": continue
		if not C.exact(row, CASE_FIELDS) or not row.get("detention") is Dictionary or not row.get("petitions") is Array or not row.get("decision") is Dictionary or not row.get("release_order") is Dictionary or not row.get("subject_ids") is Array or not row.get("victim_ids") is Array or not row.get("victim_kin_ids") is Array: return C.fail("刑事案件字段类型无效")
		if not C.exact(row.detention, ["status", "custodian_id", "controller_id", "location_id", "prior_status", "opened_receipt", "release_receipt", "release_kind", "released_day"]): return C.fail("实际拘押字段缺失")
		if not C.exact(row, CASE_FIELDS) or row.case_id != id or row.source_id != SOURCE or row.subject_ids.size() != 1 or row.victim_ids.size() != 1 or not raw.event_history.any(func(event): return event.get("event_id") == row.incident_id) or not raw.office_state.has(row.jurisdiction_office_id) or not raw.local_node_state.has(row.location_id): return C.fail("刑事案件身份、来源或引用无效")
		for person in row.subject_ids + row.victim_ids + row.victim_kin_ids + [row.detention.get("custodian_id"), row.detention.get("controller_id")]:
			if not raw.character_states.has(person): return C.fail("刑事案件丢失真实参与人")
		if not C.exact(row.detention, ["status", "custodian_id", "controller_id", "location_id", "prior_status", "opened_receipt", "release_receipt", "release_kind", "released_day"]) or row.detention.status not in ["held", "released"] or not raw.action_receipts.get(row.detention.opened_receipt, {}).get("effect_refs", []).has(id): return C.fail("实际拘押缺少经办来源")
		var accused: String = row.subject_ids[0]
		if row.detention.status == "held":
			if detained.has(accused) or raw.character_states[accused].get("status") != "imprisoned" or raw.character_states[accused].get("location_id") != row.detention.location_id or row.detention.release_receipt != "" or row.detention.released_day != -1: return C.fail("人物与单一实际拘押不一致")
			detained[accused] = id
		elif not raw.action_receipts.get(row.detention.release_receipt, {}).get("effect_refs", []).has(id) or row.detention.release_kind not in ["legal", "private"] or not C.whole(row.detention.released_day, 0) or row.detention.released_day > raw.current_day: return C.fail("实际释放缺少执行回执")
		if not row.decision.is_empty() and (not C.exact(row.decision, ["verdict", "signed_by", "day", "execution_id"]) or not raw.action_receipts.get(row.decision_transaction_id, {}).get("effect_refs", []).has(id) or row.decision.execution_id != row.decision_transaction_id): return C.fail("裁判丢失独立签判回执")
		for petition in row.petitions:
			if not raw.action_receipts.get(petition.get("execution_id"), {}).get("effect_refs", []).has(id): return C.fail("求援记录丢失本人执行来源")
		if row.facts.is_empty() or raw.character_states[row.victim_ids[0]].get("status") not in ["dead", "deceased", "executed"]: return C.fail("案件不能抹除既成命案事实")
	return {"ok": true}
