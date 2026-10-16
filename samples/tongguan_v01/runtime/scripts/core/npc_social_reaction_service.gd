extends RefCounted
const C = preload("res://scripts/core/npc_ai_state_contract.gd")
const Profile = preload("res://scripts/core/npc_behavior_profile_service.gd")
const Memory = preload("res://scripts/core/structured_memory_service.gd")
const Canonical = preload("res://scripts/core/canonical_json.gd")
const EVENTS := ["private_release", "legal_release", "verdict", "bribery_payment"]
const FIELDS := ["observer_id", "fact_id", "claim_hash", "evaluation_kind", "target_id", "contribution", "memory_ref", "last_day", "opportunity_kind"]

func settle(state, data: Dictionary, limit: int = 32) -> Dictionary:
	if not state.flags.has("social_reaction_records"): state.flags["social_reaction_records"] = {}
	if state.flags.get("social_reaction_budget", {}).get("day", -1) != state.current_day: state.flags["social_reaction_budget"] = {"day": state.current_day, "processed": 0}
	var records: Dictionary = state.flags.social_reaction_records
	var count := 0
	var facts: Array = state.information_claims.keys()
	facts.sort()
	for fact in facts:
		var people: Array = state.information_claims[fact].keys()
		people.sort()
		for observer in people:
			if count >= clampi(limit, 0, 32) or state.flags.social_reaction_budget.processed >= 32: return {"ok": true, "processed": count}
			var claim: Dictionary = state.information_claims[fact][observer]
			var payload: Dictionary = claim.get("payload", {})
			if payload.get("social_event_kind") not in EVENTS or not state.character_states.has(observer) or not state.character_states.has(payload.get("responsible_id")): continue
			if state.character_states[observer].get("status") in ["dead", "deceased", "executed", "missing", "departed"]: continue
			var key: String = observer + "|" + fact
			var fingerprint: String = Canonical.hash_value(claim).hash
			var previous: Dictionary = records.get(key, {})
			if previous.get("claim_hash") == fingerprint: continue
			var assessed: Dictionary = evaluate(state, data, observer, payload)
			var target: String = payload.responsible_id
			if not previous.is_empty() and previous.target_id != target: return C.fail("新证据若更换责任对象，须另立消息，不能挪用旧判断")
			var person: Dictionary = state.character_states[observer]
			var current: int = person.relationships.get(target, 0)
			var base: int = current - int(previous.get("contribution", 0))
			var after: int = clampi(base + assessed.score, -100, 100)
			var memory_id: String = "social-reaction:" + key
			var summary: String = str(payload.get("summary", "消息已收到。")) + " 本人评价：" + assessed.kind
			var remembered: Dictionary
			if previous.is_empty():
				remembered = Memory.new().create_memory(state, {"id": memory_id, "type": "social_reaction", "memory_type": "social_reaction", "source_id": observer, "target_id": target, "participants": [observer], "known_by": [observer], "summary": summary, "visibility": "private", "tags": [fact, assessed.kind], "original_evidence": {"fact_id": fact, "claim_hash": fingerprint, "observer_id": observer}})
			else:
				remembered = Memory.new().revise_memory(state, memory_id, {"summary": summary, "revision_reason": "收到更新后的证据或主张", "tags": [fact, assessed.kind]})
			if not remembered.ok: return remembered
			state.character_states[observer].relationships[target] = after
			records[key] = {"observer_id": observer, "fact_id": fact, "claim_hash": fingerprint, "evaluation_kind": assessed.kind, "target_id": target, "contribution": after - base, "memory_ref": memory_id, "last_day": state.current_day, "opportunity_kind": assessed.opportunity}
			count += 1
			state.flags.social_reaction_budget.processed += 1
	return {"ok": true, "processed": count}

static func evaluate(state, data: Dictionary, observer: String, payload: Dictionary) -> Dictionary:
	var profile: Dictionary = Profile.new().build(state, data, observer).profile
	var relation: Dictionary = profile.relationships
	var illegal: bool = payload.social_event_kind in ["private_release", "bribery_payment"]
	var kin: bool = payload.get("victim_kin_ids", []).has(observer) or payload.get("victim_ids", []).any(func(id): return int(relation.get(id, 0)) >= 40)
	if kin: return {"kind": "victim_kin", "score": -18 if illegal else 0, "opportunity": "seek_redress" if illegal else ""}
	if payload.get("beneficiary_id") == observer or int(relation.get(payload.get("beneficiary_id"), 0)) >= 40: return {"kind": "beneficiary", "score": 8 if illegal else 4, "opportunity": "repay_favor"}
	if state.office_state.values().any(func(office): return office.get("holder_id") == observer) and profile.vectors.honor > 0: return {"kind": "conscientious_official", "score": -10 if illegal else 4, "opportunity": "seek_review" if illegal else ""}
	if int(relation.get(payload.responsible_id, 0)) <= -30: return {"kind": "political_rival", "score": -6 if illegal else 0, "opportunity": "seek_review" if illegal else ""}
	return {"kind": "unrelated", "score": 0, "opportunity": ""}

static func opportunities(state, observer: String) -> Array:
	var result: Array = []
	for record in state.flags.get("social_reaction_records", {}).values():
		if record.observer_id != observer or record.opportunity_kind == "": continue
		var claim: Dictionary = state.information_claims.get(record.fact_id, {}).get(observer, {})
		var case_id: String = claim.get("payload", {}).get("case_id", "")
		if not state.accountability_cases.has(case_id): continue
		if state.accountability_cases[case_id].get("petitions", []).any(func(row): return row.actor_id == observer): continue
		result.append({"case_id": case_id, "fact_id": record.fact_id, "goal_kind": record.opportunity_kind, "target_id": record.target_id})
	return result

static func validate(raw: Dictionary) -> Dictionary:
	var records: Variant = raw.get("flags", {}).get("social_reaction_records", {})
	if not records is Dictionary: return C.fail("社会反应记录不是唯一字典")
	var budget: Variant = raw.get("flags", {}).get("social_reaction_budget", {})
	if not budget is Dictionary: return C.fail("社会反应预算字段类型无效")
	if not budget.is_empty() and (not C.exact(budget, ["day", "processed"]) or not C.whole(budget.day, 0) or budget.day > raw.current_day or not C.whole(budget.processed, 0) or budget.processed > 32): return C.fail("社会反应处理次数越过实际日预算")
	for key in records:
		var row: Variant = records[key]
		if not C.exact(row, FIELDS) or key != row.observer_id + "|" + row.fact_id or not raw.character_states.has(row.observer_id) or not raw.character_states.has(row.target_id) or not raw.information_claims.get(row.fact_id, {}).has(row.observer_id) or not C.hash_string(row.claim_hash) or row.evaluation_kind not in ["victim_kin", "beneficiary", "conscientious_official", "political_rival", "unrelated"] or row.opportunity_kind not in ["", "seek_redress", "seek_review", "repay_favor"] or not C.whole(row.last_day, 0) or row.last_day > raw.current_day or not C.whole(row.contribution + 200, 0) or abs(row.contribution) > 200: return C.fail("社会判断丢失观察者、实际主张或有限规则来源")
		if not raw.structured_memories.any(func(memory): return memory.get("id") == row.memory_ref and memory.get("source_id") == row.observer_id and memory.get("known_by") == [row.observer_id]): return C.fail("社会判断丢失独立私有记忆")
	return {"ok": true}
