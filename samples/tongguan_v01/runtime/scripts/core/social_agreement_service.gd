extends RefCounted

const Contract = preload("res://scripts/core/npc_ai_state_contract.gd")
const Family = preload("res://scripts/core/family_office_rules.gd")
const Canonical = preload("res://scripts/core/canonical_json.gd")
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const KINDS := ["offer_social_agreement", "respond_social_agreement", "fulfill_social_agreement"]
const FIELDS := ["contract_id", "contract_kind", "source_id", "principal_id", "participant_ids", "purpose", "terms", "terms_version", "terms_hash", "accepted_versions", "responses", "status", "created_day", "office_fingerprint", "result_refs", "blocked_reason"]

func offer(context, actor: String, candidate: String, purpose: String, terms: Dictionary, execution: String) -> Dictionary:
	var targets: Array = ["social:" + execution, candidate]
	for key in ["office_id", "item_id", "recipient_id", "destination_id", "funding_account_id", "case_id"]:
		if terms.has(key): targets.append(terms[key])
	return _execute(context, actor, "offer_social_agreement", {"agreement_id": "social:" + execution, "candidate_id": candidate, "purpose": purpose, "terms": terms}, targets, execution)

func respond(context, actor: String, id: String, version: int, choice: String, counter_terms: Dictionary, execution: String) -> Dictionary:
	return _execute(context, actor, "respond_social_agreement", {"agreement_id": id, "terms_version": version, "choice": choice, "counter_terms": counter_terms}, [id], execution)

func fulfill(context, actor: String, id: String, version: int, execution: String) -> Dictionary:
	return _execute(context, actor, "fulfill_social_agreement", {"agreement_id": id, "terms_version": version}, [id], execution)

static func _execute(context, actor: String, kind: String, params: Dictionary, targets: Array, execution: String) -> Dictionary:
	if kind == "offer_social_agreement":
		var supported := validate_terms(context.state, params.get("purpose", ""), params.get("terms"))
		if not supported.ok: return supported
	var dispatcher = load("res://scripts/core/game_action_dispatcher.gd").new()
	var selection := {"action_kind": kind, "parameters": params, "target_refs": targets}
	var result: Dictionary = dispatcher.execute(context, dispatcher.bind_npc_request(context.state, actor, selection, execution)) if actor == context.state.player_character_id else dispatcher.execute_npc(context, actor, selection, execution)
	if result.get("ok", false):
		var domain: Dictionary = context.state.action_receipts.get(execution, {}).get("social_record", {})
		result["action_ref"] = result.result_ref
		result["result_ref"] = domain.get("result_ref", result.result_ref)
		result["outcome"] = domain.get("outcome", "recorded")
	return result

static func cost_for(state, kind: String, params: Dictionary) -> Dictionary:
	if not Contract.text_id(params.get("agreement_id")): return Contract.fail("agreement requires stable identity")
	if kind == "offer_social_agreement":
		var valid := validate_terms(state, str(params.get("purpose", "")), params.get("terms"))
		if not valid.ok: return valid
		if not state.character_states.has(params.get("candidate_id")) or state.economic_contracts.has(params.agreement_id): return Contract.fail("agreement candidate is absent or identity is already used")
	else:
		var record: Dictionary = state.economic_contracts.get(params.agreement_id, {})
		if record.get("contract_kind") != "social_agreement" or not Contract.whole(params.get("terms_version"), 1) or params.terms_version != record.terms_version: return Contract.fail("agreement terms are absent or obsolete")
		if kind == "fulfill_social_agreement":
			if record.purpose == "delegated_plan": return {"ok": true, "account_id": "", "amount": 0}
			if record.purpose == "person_arrangement": return load("res://scripts/core/person_arrangement_service.gd").cost_for(state, record)
			if record.purpose == "gift_delivery": return {"ok": true, "account_id": record.terms.funding_account_id, "amount": record.terms.fee_amount}
			if record.purpose == "bribery": return {"ok": true, "account_id": record.terms.funding_account_id, "amount": record.terms.amount}
			return {"ok": true, "account_id": state.office_state[record.terms.office_id].remuneration_terms.account_id, "amount": record.terms.wage_amount}
	return {"ok": true, "account_id": "", "amount": 0}

static func validate_terms(state, purpose: String, terms: Variant) -> Dictionary:
	if purpose == "delegated_plan": return load("res://scripts/core/npc_mandate_service.gd").validate_terms(state, terms)
	if purpose == "person_arrangement": return load("res://scripts/core/person_arrangement_service.gd").validate_terms(state, terms)
	if purpose == "gift_delivery": return load("res://scripts/core/gift_delivery_service.gd").validate_terms(state, terms)
	if purpose == "bribery": return load("res://scripts/core/criminal_case_service.gd").validate_bribe(state, terms)
	if purpose != "employment": return {"ok": false, "code": "unsupported_capability", "error": "该约定目的尚缺实际领域合同"}
	if not Contract.exact(terms, ["office_id", "wage_amount", "period_days"]) or not Family.is_family(state, str(terms.get("office_id", ""))) or not Contract.whole(terms.wage_amount, 1) or not Contract.whole(terms.period_days, 1): return Contract.fail("employment offer needs actual household office and quoted wages")
	if terms.period_days != state.office_state[terms.office_id].remuneration_terms.period_days: return Contract.fail("employment period must match actual office terms")
	return {"ok": true}

static func apply(state, data: Dictionary, kind: String, params: Dictionary, actor: String, execution: String, reservation: String = "") -> Dictionary:
	var valid := cost_for(state, kind, params)
	if not valid.ok: return valid
	var id: String = params.agreement_id
	if kind == "offer_social_agreement":
		var target: String = params.candidate_id
		if target == actor: return Contract.fail("提议和接受须来自不同本人")
		if params.purpose == "employment" and not Family.authority(state, params.terms.office_id, actor): return Contract.fail("proposer lacks household hiring authority")
		if params.purpose == "gift_delivery":
			valid = load("res://scripts/core/gift_delivery_service.gd").offer_allowed(state, actor, target, params.terms)
			if not valid.ok: return valid
		if params.purpose == "person_arrangement":
			valid = load("res://scripts/core/person_arrangement_service.gd").offer_allowed(state, actor, target, params.terms)
			if not valid.ok: return valid
		if params.purpose == "bribery":
			var record: Dictionary = state.accountability_cases[params.terms.case_id]
			if not state.information_claims.values().any(func(holders): return holders.get(actor, {}).get("payload", {}).get("case_id") == record.case_id): return Contract.fail("本人尚未实际获知这份案件，不能猜测秘密对象提出干预")
			if not Accounts.new().can_operate(state, params.terms.funding_account_id, actor) or (target != record.detention.custodian_id and not load("res://scripts/core/criminal_case_service.gd").judge_authority(state, record, target)): return Contract.fail("行贿提议缺少实际付款控制或干预对象")
		var terms_hash: String = Canonical.hash_value(params.terms).hash
		var fingerprint: String = Canonical.hash_value(params.terms if params.purpose in ["person_arrangement", "delegated_plan"] else state.office_state[params.terms.office_id] if params.purpose == "employment" else state.management_assets[params.terms.item_id] if params.purpose == "gift_delivery" else state.accountability_cases[params.terms.case_id]).hash
		if params.purpose == "person_arrangement" and params.terms.arrangement_kind == "attendant": fingerprint = Canonical.hash_value(state.office_state[params.terms.role_ref]).hash
		var record := {"contract_id": id, "contract_kind": "social_agreement", "source_id": execution, "principal_id": actor, "participant_ids": [actor, target], "purpose": params.purpose, "terms": params.terms.duplicate(true), "terms_version": 1, "terms_hash": terms_hash, "accepted_versions": {actor: 1}, "responses": [{"actor_id": actor, "version": 1, "choice": "offer", "terms_hash": terms_hash, "execution_id": execution, "day": state.current_day}], "status": "proposed", "created_day": state.current_day, "office_fingerprint": fingerprint, "result_refs": [], "blocked_reason": ""}
		state.economic_contracts[id] = record
		if record.purpose == "person_arrangement": record.participant_ids = load("res://scripts/core/person_arrangement_service.gd").participants(state, actor, target, record.terms)
		var communicated := communicate(state, record, actor, execution)
		if not communicated.ok: return communicated
		return {"ok": true, "result_ref": id, "outcome": "proposed", "visible_summary": "已提出具体条件，等待本人收到后选择。"}
	var record: Dictionary = state.economic_contracts[id]
	if not record.participant_ids.has(actor): return Contract.fail("agreement response must be signed by its actual participant")
	if kind == "respond_social_agreement":
		if not knows_current_response(state, record, actor): return Contract.fail("本版提议尚未实际送达本人，不能凭空接受")
		if (record.status not in ["proposed", "countered"] and not (record.status == "accepted" and params.get("choice") == "withdraw")) or params.get("choice") not in ["accept", "reject", "counter", "withdraw"] or not params.get("counter_terms") is Dictionary: return Contract.fail("agreement no longer needs this response")
		if record.responses.filter(func(row): return row.day == state.current_day).size() >= 5: return Contract.fail("同一事项今日谈判回合已用尽，请改日续议")
		var choice: String = params.choice
		if choice == "counter":
			valid = validate_terms(state, record.purpose, params.counter_terms)
			if not valid.ok: return valid
			for key in ["office_id", "item_id", "recipient_id", "destination_id", "funding_account_id", "case_id", "intended_action", "arrangement_kind", "role_ref"]:
				if record.terms.has(key) and params.counter_terms.get(key) != record.terms[key]: return Contract.fail("更换交涉对象须另提约定，不能冒用旧承诺")
			record.terms = params.counter_terms.duplicate(true)
			record.terms_version += 1
			record.terms_hash = Canonical.hash_value(record.terms).hash
			record.accepted_versions = {actor: record.terms_version}
			record.status = "countered"
		elif not params.counter_terms.is_empty(): return Contract.fail("接受或拒绝不能夹带新条款")
		elif choice == "reject": record.status = "rejected"
		elif choice == "withdraw": record.status = "withdrawn"
		else:
			record.accepted_versions[actor] = record.terms_version
			if record.participant_ids.all(func(person): return record.accepted_versions.get(person) == record.terms_version): record.status = "accepted"
		record.responses.append({"actor_id": actor, "version": record.terms_version, "choice": choice, "terms_hash": record.terms_hash, "execution_id": execution, "day": state.current_day})
		var communicated := communicate(state, record, actor, execution)
		if not communicated.ok: return communicated
		return {"ok": true, "result_ref": id, "outcome": record.status, "visible_summary": {"accepted": "双方已接受同一版条件。", "rejected": "本人已拒绝这份提议，未发生履约。", "countered": "本人提出新报价，旧接受不再适用。"}.get(record.status, "已记录本人回应。")}
	if (actor != record.principal_id and not (record.purpose == "person_arrangement" and record.terms.arrangement_kind == "attendant" and record.terms.recipient_id == actor)) or record.status != "accepted": return Contract.fail("accepted agreement must be fulfilled by actual employer")
	if not knows_current_response(state, record, actor): return Contract.fail("双方同意的回信尚未送达本人，约定仍保留")
	if record.purpose == "delegated_plan": return load("res://scripts/core/npc_mandate_service.gd").fulfill(state, data, record, execution)
	if record.purpose == "person_arrangement": return load("res://scripts/core/person_arrangement_service.gd").fulfill(state, data, record, actor, execution, reservation)
	if record.purpose == "bribery":
		if Accounts.new().location(state, record.terms.funding_account_id) != state.character_states[actor].get("location_id") or state.character_states[actor].get("location_id") != state.character_states[record.participant_ids[1]].get("location_id"): return Contract.fail("财物须在实际控制及交割地点办理；异地尚需已有递送领域流程")
		var paid: Dictionary = Accounts.new().apply(state, "transfer", {"execution_id": execution, "source_account_id": record.terms.funding_account_id, "destination_account_id": record.participant_ids[1] + "_cash", "amount": record.terms.amount, "actor_id": actor, "reason_ref": id, "reservation_id": reservation})
		if not paid.ok: return paid
		record.status = "fulfilled"
		record.result_refs = [paid.result_ref]
		var completion := communicate(state, record, actor, execution)
		if not completion.ok: return completion
		state.accountability_cases[record.terms.case_id].evidence.append({"kind": "bribery_payment", "ref_id": execution, "agreement_id": id, "responsible_id": record.participant_ids[1], "day": state.current_day})
		var case_record: Dictionary = state.accountability_cases[record.terms.case_id]
		var receiver: String = record.participant_ids[1]
		var fact := "bribery-payment:" + execution
		var informed: Dictionary = load("res://scripts/core/information_propagation_service.gd").new().create_fact(state, {"fact_id": fact, "truth_payload": {"case_id": record.terms.case_id, "social_event_kind": "bribery_payment", "responsible_id": receiver, "beneficiary_id": case_record.subject_ids[0], "victim_ids": case_record.victim_ids.duplicate(), "victim_kin_ids": case_record.victim_kin_ids.duplicate(), "summary": "已实际交付用于案件干预的财物；裁判和释放尚未发生。"}, "holders": [actor, receiver], "secrecy": "private", "source_context": {"context_kind": "office_observation", "context_id": fact, "related_report_id": execution}})
		if not informed.ok: return informed
		return {"ok": true, "result_ref": id, "outcome": "fulfilled", "journal_refs": [paid.result_ref], "visible_summary": "已按本人接受的提议交付财物；裁判和释放尚未发生。"}
	if record.purpose == "gift_delivery":
		var gift: Dictionary = load("res://scripts/core/gift_delivery_service.gd").start(state, record, execution, reservation)
		if not gift.ok: return gift
		record.status = "fulfilled"
		record.result_refs = [gift.result_ref]
		gift.result_ref = id
		gift["outcome"] = "fulfilled"
		return gift
	var person: String = record.participant_ids[1]
	var office: Dictionary = state.office_state[record.terms.office_id]
	var reason := ""
	if not Family.authority(state, office.office_id, actor): reason = "雇用权源已变化。"
	elif Canonical.hash_value(office).hash != record.office_fingerprint: reason = "岗位或原报价已有变化，请重新商议。"
	elif office.holder_id != "": reason = "岗位已由另一人占用。"
	elif state.character_states[actor].get("location_id") != office.scope_ref.entity_id: reason = "任用人尚未在已有任用流程的实际履职地点。"
	elif state.character_states[person].get("location_id") != office.scope_ref.entity_id: reason = "本人尚未抵达履职地点。"
	if reason != "":
		record.blocked_reason = reason
		return {"ok": true, "result_ref": id, "outcome": "blocked", "journal_refs": [], "visible_summary": reason + "约定仍保留。"}
	# Any execution error remains a transaction failure: the caller cannot keep a
	# changed wage or half a payroll transfer. Existing accepted terms survive.
	office.remuneration_terms.amount = int(record.terms.wage_amount)
	var employed: Dictionary = Family.appoint(state, data, {"office_id": office.office_id, "candidate_id": person, "actor_id": actor, "remuneration_terms": office.remuneration_terms.duplicate(true), "reservation_id": reservation}, "social-employment:" + execution)
	if not employed.ok: return employed
	record.status = "fulfilled"
	record.blocked_reason = ""
	record.result_refs = [employed.result_ref]
	state.economic_contracts[employed.result_ref]["agreement_ref"] = id
	load("res://scripts/core/household_membership_service.gd").sync_person(state, person)
	return {"ok": true, "result_ref": id, "outcome": "fulfilled", "journal_refs": ["wage:social-employment:" + execution], "visible_summary": "已按双方条款受聘，首期工资已实际支付。"}

static func employment_consent(state, office_id: String, candidate: String, wage: int) -> bool:
	if state.economic_contracts.values().any(func(row): return row.get("purpose") == "person_arrangement" and row.get("status") == "accepted" and row.terms.arrangement_kind == "attendant" and row.participant_ids[1] == candidate and row.terms.role_ref == office_id and row.participant_ids.all(func(person): return row.accepted_versions.get(person) == row.terms_version) and Family.authority(state, office_id, row.terms.recipient_id) and state.office_state[office_id].remuneration_terms.amount == wage and Canonical.hash_value(state.office_state[office_id]).hash == row.office_fingerprint): return true
	return state.economic_contracts.values().any(func(row): return row.get("contract_kind") == "social_agreement" and row.get("purpose") == "employment" and row.get("status") in ["accepted", "fulfilled"] and row.get("participant_ids", []).has(candidate) and row.terms.office_id == office_id and row.terms.wage_amount == wage and row.participant_ids.all(func(id): return row.accepted_versions.get(id) == row.terms_version) and Family.authority(state, office_id, row.principal_id))

static func knows_current_response(state, record: Dictionary, actor: String) -> bool:
	return state.information_claims.get("social-message:" + str(record.responses[-1].execution_id), {}).has(actor)

static func communicate(state, record: Dictionary, actor: String, execution: String) -> Dictionary:
	var holders: Array = [actor]
	var remote: Array = []
	for person in record.participant_ids:
		if person == actor: continue
		if state.character_states[actor].get("location_id") == state.character_states[person].get("location_id"): holders.append(person)
		else: remote.append(person)
	var info = load("res://scripts/core/information_propagation_service.gd").new()
	var fact := "social-message:" + execution
	var payload := {"agreement_id": record.contract_id, "participant_ids": record.participant_ids.duplicate(), "terms_version": record.terms_version, "terms": record.terms.duplicate(true), "terms_hash": record.terms_hash, "status": record.status, "accepted_versions": record.accepted_versions.duplicate(true), "response_actor": actor}
	if record.purpose == "employment":
		var first: Dictionary = state.information_truths.get("social-message:" + str(record.responses[0].execution_id), {}).get("truth_payload", {})
		var previous: Dictionary = first.get("employment_offer", {})
		var quoted: Dictionary = previous.get("office", {})
		if quoted.is_empty(): quoted = load("res://scripts/core/npc_opportunity_projection.gd").public_office(state.office_state[record.terms.office_id], record.terms)
		payload["employment_offer"] = {"office_id": record.terms.office_id, "wage_amount": record.terms.wage_amount, "period_days": record.terms.period_days, "office": quoted.duplicate(true)}
	if record.purpose == "person_arrangement" and record.terms.arrangement_kind == "attendant":
		var first: Dictionary = state.information_truths.get("social-message:" + str(record.responses[0].execution_id), {}).get("truth_payload", {})
		var office: Dictionary = state.office_state[record.terms.role_ref]
		payload["employment_offer"] = first.get("employment_offer", {"office_id": office.office_id, "wage_amount": office.remuneration_terms.amount, "period_days": office.remuneration_terms.period_days}).duplicate(true)
	var created: Dictionary = info.create_fact(state, {"fact_id": fact, "truth_payload": payload, "holders": holders, "secrecy": "private", "source_context": {"context_kind": "office_observation", "context_id": fact, "related_report_id": execution}})
	if not created.ok: return created
	for recipient in remote:
		var sent: Dictionary = info.queue_dispatch(state, fact, actor, recipient)
		if not sent.ok: return sent
	return {"ok": true}

static func project(state, record: Dictionary, viewer: String) -> Dictionary:
	if not record.participant_ids.has(viewer): return {}
	for holders in state.information_claims.values():
		var completion: Dictionary = holders.get(viewer, {})
		if completion.get("payload", {}).get("agreement_id") == record.contract_id and completion.payload.get("status") == "fulfilled":
			return {"contract_id": record.contract_id, "contract_kind": "social_agreement", "purpose": record.purpose, "principal_id": record.principal_id, "participant_ids": record.participant_ids.duplicate(), "terms": completion.payload.terms.duplicate(true), "employment_offer": completion.payload.get("employment_offer", {}).duplicate(true), "terms_version": completion.payload.terms_version, "status": "fulfilled", "accepted_versions": completion.payload.accepted_versions.duplicate(true), "known_day": completion.known_day}
	var responses: Array = record.responses.duplicate()
	responses.reverse()
	for response in responses:
		var claim: Dictionary = state.information_claims.get("social-message:" + str(response.execution_id), {}).get(viewer, {})
		if not claim.is_empty():
			return {"contract_id": record.contract_id, "contract_kind": "social_agreement", "purpose": record.purpose, "principal_id": record.principal_id, "participant_ids": record.participant_ids.duplicate(), "terms": claim.payload.terms.duplicate(true), "employment_offer": claim.payload.get("employment_offer", {}).duplicate(true), "terms_version": claim.payload.terms_version, "status": claim.payload.status, "accepted_versions": claim.payload.accepted_versions.duplicate(true), "known_day": claim.known_day}
	return {}

static func validate(raw: Dictionary, record: Dictionary) -> Dictionary:
	if not Contract.exact(record, FIELDS) or record.contract_kind != "social_agreement" or not Contract.text_id(record.source_id) or not record.participant_ids is Array or record.participant_ids.size() < 2 or record.participant_ids.size() > 4 or record.participant_ids[0] != record.principal_id or record.participant_ids[0] == record.participant_ids[1]: return Contract.fail("invalid social agreement parties or fields")
	for person in record.participant_ids:
		if not raw.character_states.has(person): return Contract.fail("social agreement lost participant")
	var terms_valid := validate_terms(_Snapshot.new(raw), record.purpose, record.terms)
	if not terms_valid.ok: return terms_valid
	if record.purpose != "person_arrangement" and record.participant_ids != [record.principal_id, record.participant_ids[1]]: return Contract.fail("约定丢失真实签署人")
	if not Contract.whole(record.terms_version, 1) or not Contract.whole(record.created_day, 0) or record.created_day > raw.current_day or record.status not in ["proposed", "countered", "accepted", "rejected", "fulfilled", "withdrawn"] or not Contract.hash_string(record.office_fingerprint) or record.terms_hash != Canonical.hash_value(record.terms).hash or not record.blocked_reason is String or not record.accepted_versions is Dictionary or not record.responses is Array or record.responses.is_empty() or not record.result_refs is Array: return Contract.fail("invalid social agreement versions or history")
	var executions: Array = []
	for response in record.responses:
		if not Contract.exact(response, ["actor_id", "version", "choice", "terms_hash", "execution_id", "day"]) or not record.participant_ids.has(response.actor_id) or response.choice not in ["offer", "accept", "reject", "counter", "withdraw"] or not Contract.whole(response.version, 1) or response.version > record.terms_version or not Contract.whole(response.day, 0) or response.day < record.created_day or response.day > raw.current_day or not Contract.hash_string(response.terms_hash) or not raw.action_receipts.has(response.execution_id) or executions.has(response.execution_id): return Contract.fail("social agreement response lost signed action")
		executions.append(response.execution_id)
		var fact: Dictionary = raw.get("information_truths", {}).get("social-message:" + str(response.execution_id), {})
		if fact.get("truth_payload", {}).get("agreement_id") != record.contract_id or fact.truth_payload.get("participant_ids") != record.participant_ids or fact.truth_payload.get("response_actor") != response.actor_id or fact.truth_payload.get("terms_hash") != response.terms_hash: return Contract.fail("约定回应丢失真实本人及原签署人发出的消息")
	for actor in record.accepted_versions:
		if not record.participant_ids.has(actor) or not record.responses.any(func(row): return row.actor_id == actor and row.version == record.accepted_versions[actor] and row.choice in ["offer", "accept", "counter"] and (row.version != record.terms_version or row.terms_hash == record.terms_hash)): return Contract.fail("social agreement has unsigned consent")
	if record.status in ["accepted", "fulfilled"] and not record.participant_ids.all(func(actor): return record.accepted_versions.get(actor) == record.terms_version): return Contract.fail("social agreement lacks independent bilateral consent")
	if record.status == "fulfilled":
		if record.result_refs.size() != 1: return Contract.fail("fulfilled agreement lost unique actual domain execution")
		if record.purpose == "delegated_plan":
			var tasks: Array = raw.get("active_tasks", []) + raw.get("completed_tasks", [])
			if not tasks.any(func(task): return task.get("task_id") == record.result_refs[0] and task.get("source_agreement_id") == record.contract_id and task.get("principal_id") == record.principal_id and task.get("executor_id") == record.participant_ids[1]): return Contract.fail("双方委托丢失原任务队列办理结果")
		elif record.purpose == "bribery":
			var paid: Dictionary = raw.resource_journal.get(record.result_refs[0], {})
			if paid.get("reason_ref") != record.contract_id or paid.get("source_account_id") != record.terms.funding_account_id or paid.get("destination_account_id") != record.participant_ids[1] + "_cash" or paid.get("amount") != record.terms.amount: return Contract.fail("行贿财物未实际交割")
		elif record.purpose == "person_arrangement":
			if not load("res://scripts/core/person_arrangement_service.gd").fulfillment_valid(raw, record): return Contract.fail("人物安排丢失实际办理结果")
		elif raw.economic_contracts.get(record.result_refs[0], {}).get("agreement_ref") != record.contract_id: return Contract.fail("fulfilled agreement lost actual domain execution")
	elif not record.result_refs.is_empty(): return Contract.fail("unfulfilled agreement cannot claim execution")
	return {"ok": true}

class _Snapshot extends RefCounted:
	var office_state: Dictionary
	var management_assets: Dictionary
	var character_states: Dictionary
	var resource_accounts: Dictionary
	var flags: Dictionary
	var local_node_state: Dictionary
	var accountability_cases: Dictionary
	func _init(raw: Dictionary) -> void:
		office_state = raw.office_state
		management_assets = raw.management_assets
		character_states = raw.character_states
		resource_accounts = raw.resource_accounts
		flags = raw.flags
		local_node_state = raw.local_node_state
		accountability_cases = raw.accountability_cases
