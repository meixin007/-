extends RefCounted
const C = preload("res://scripts/core/npc_ai_state_contract.gd")
const Family = preload("res://scripts/core/family_office_rules.gd")
const Marriage = preload("res://scripts/core/marriage_service.gd")
const Info = preload("res://scripts/core/information_propagation_service.gd")
const Canonical = preload("res://scripts/core/canonical_json.gd")

static func validate_terms(state, terms: Variant) -> Dictionary:
	if not C.exact(terms, ["arrangement_kind", "recipient_id", "destination_id", "role_ref"]) or not state.character_states.has(terms.recipient_id) or not state.local_node_state.has(terms.destination_id) or not terms.role_ref is String: return C.fail("人物安排须引用真实接洽人、地点与关系类型")
	if terms.arrangement_kind not in ["introduction", "attendant", "marriage"]: return {"ok": false, "code": "unsupported_capability", "error": "该强制或其他人物安排尚无实际领域规则。"}
	if terms.arrangement_kind == "introduction" and terms.role_ref != "": return C.fail("引见不授予职位或婚配身份")
	if terms.arrangement_kind == "attendant" and (not Family.is_family(state, terms.role_ref) or state.office_state[terms.role_ref].scope_ref.entity_id != terms.destination_id): return C.fail("侍从安排须有实际家职及履职地点")
	if terms.arrangement_kind == "marriage":
		var match_row: Dictionary = Marriage.match_for(state, terms.role_ref)
		if match_row.is_empty() or terms.recipient_id != match_row.party_b or terms.destination_id != match_row.location_id: return C.fail("婚配须引用已有成年双方与家庭财产合同")
	return {"ok": true}

static func participants(state, actor: String, candidate: String, terms: Dictionary) -> Array:
	var result: Array = [actor, candidate]
	if not result.has(terms.recipient_id): result.append(terms.recipient_id)
	if terms.arrangement_kind == "marriage":
		var match_row: Dictionary = Marriage.match_for(state, terms.role_ref)
		var counter: String = Marriage.representative(state, match_row.counter_account)
		if counter != "" and not result.has(counter): result.append(counter)
	return result

static func offer_allowed(state, actor: String, candidate: String, terms: Dictionary) -> Dictionary:
	if candidate == terms.recipient_id: return C.fail("被引见、受雇或婚配的人须与另一方分别保有身份")
	if terms.arrangement_kind == "attendant" and not Family.authority(state, terms.role_ref, terms.recipient_id): return C.fail("接洽人当前没有该家职的实际雇用权源")
	if terms.arrangement_kind == "marriage":
		var match_row: Dictionary = Marriage.match_for(state, terms.role_ref)
		if candidate != match_row.party_a or not load("res://scripts/core/resource_account_service.gd").new().can_operate(state, match_row.sponsor_account, actor): return C.fail("提出婚配须有实际双方及本人家庭代表权源")
	return {"ok": true}

static func cost_for(state, record: Dictionary) -> Dictionary:
	if record.terms.arrangement_kind == "attendant":
		var office: Dictionary = state.office_state[record.terms.role_ref]
		return {"ok": true, "account_id": office.remuneration_terms.account_id, "amount": office.remuneration_terms.amount}
	return {"ok": true, "account_id": "", "amount": 0}

static func fulfill(state, data: Dictionary, row: Dictionary, actor: String, execution: String, reservation: String) -> Dictionary:
	var employer: String = row.terms.recipient_id if row.terms.arrangement_kind == "attendant" else row.principal_id
	if actor != employer: return C.fail("仅实际接洽、付款或家庭代表人可以办理")
	for person in row.participant_ids:
		if state.character_states[person].get("status") in ["dead", "deceased", "executed", "missing", "imprisoned", "departed", "exiled"] or state.character_states[person].get("location_id") != row.terms.destination_id: return C.fail("人物未能实际到场，各自已有承诺和财产继续保留")
	var result: Dictionary
	if row.terms.arrangement_kind == "attendant":
		var office: Dictionary = state.office_state[row.terms.role_ref]
		if Canonical.hash_value(office).hash != row.office_fingerprint: return C.fail("岗位或原薪资已有变化，请重新商议并签署")
		result = Family.appoint(state, data, {"office_id": office.office_id, "candidate_id": row.participant_ids[1], "actor_id": actor, "remuneration_terms": office.remuneration_terms.duplicate(true), "reservation_id": reservation}, "attendant:" + execution)
		if not result.ok: return result
		state.economic_contracts[result.result_ref]["agreement_ref"] = row.contract_id
	elif row.terms.arrangement_kind == "marriage":
		var match_row: Dictionary = Marriage.match_for(state, row.terms.role_ref)
		if not row.participant_ids.has(Marriage.representative(state, match_row.counter_account)): return C.fail("对方家庭代表权源已变化，请由现任代表重新商议")
		result = Marriage.apply(state, "inquire_marriage", {"match_id": match_row.match_id, "proposal_id": "marriage:" + execution, "offered_gift": match_row.minimum_gift}, actor, execution, reservation)
		if not result.ok: return result
		state.economic_contracts[result.result_ref]["agreement_ref"] = row.contract_id
	else:
		var fact := "introduction:" + execution
		result = Info.new().create_fact(state, {"fact_id": fact, "truth_payload": {"agreement_ref": row.contract_id, "person_ids": row.participant_ids.duplicate(), "summary": "各方同意后已当场相互引见。"}, "holders": row.participant_ids.duplicate(), "secrecy": "private", "source_context": {"context_kind": "office_observation", "context_id": fact, "related_report_id": execution}})
		if not result.ok: return result
		var knowledge = load("res://scripts/core/character_knowledge_service.gd").new()
		for observer in row.participant_ids:
			for person in row.participant_ids:
				if observer != person:
					knowledge.record_observer_claim(state, observer, person, "public_title", {"status": "confirmed", "source_id": fact, "acquired_day": state.current_day, "confidence": 1.0, "value": state.character_states[person].get("role", "已引见的人物")})
		result = {"ok": true, "result_ref": fact}
	row.status = "fulfilled"
	row.result_refs = [result.result_ref]
	if row.terms.arrangement_kind == "attendant": load("res://scripts/core/household_membership_service.gd").sync_person(state, row.participant_ids[1])
	var response := {"ok": true, "result_ref": row.contract_id, "outcome": "fulfilled", "effect_refs": [row.contract_id, result.result_ref], "journal_refs": ["wage:attendant:" + execution] if row.terms.arrangement_kind == "attendant" else [], "visible_summary": "已按各方真实同意办理；婚配后续仍须原礼金、家庭及到期手续。"}
	if result.has("marriage_record"): response["marriage_record"] = result.marriage_record.duplicate(true)
	return response

static func fulfillment_valid(raw: Dictionary, row: Dictionary) -> bool:
	if row.terms.arrangement_kind == "introduction": return raw.get("information_truths", {}).get(row.result_refs[0], {}).get("truth_payload", {}).get("agreement_ref") == row.contract_id
	return raw.economic_contracts.get(row.result_refs[0], {}).get("agreement_ref") == row.contract_id
