extends RefCounted
# Contract identifiers for the scenario's education entry route. Removing the
# prerequisite field from a snapshot must not turn it into an unrestricted post.
const ENTRY_POSTS := {"pingyuan_school_clerk": "pingyuan_school"}

static func assess(state, data: Dictionary, office: Dictionary, person: String) -> Dictionary:
	if ENTRY_POSTS.has(office.office_id) and office.get("entry_school_id") != ENTRY_POSTS[office.office_id]: return {"ok": false, "error": "本职位缺少有来源的学舍任用条件"}
	var source: Dictionary = {}
	for candidate in state.economic_contracts.values():
		if candidate.get("contract_kind") == "school_candidacy" and candidate.get("school_id") == office.entry_school_id and candidate.get("supplier_id") == person and candidate.get("status") == "admitted": source = candidate; break
	if source.is_empty(): return {"ok": false, "error": "须先实际完成该学舍荐举录取；学习合格或付费不能代替名额"}
	var conflicts: Array = state.office_state.values().filter(func(row): return row.get("holder_id") == person and row.get("status") == "appointed" and row.get("office_id") != office.office_id)
	if not conflicts.is_empty(): return {"ok": false, "error": "本人仍在其他职位履职，须先办理离任交接"}
	var definition: Dictionary = {}
	for character in data.get("characters", []):
		if character.id == person: definition = character; break
	var stats: Dictionary = definition.get("stats", {}).duplicate(true)
	stats.merge(state.character_states.get(person, {}).get("stats", {}), true)
	for key in office.required_stats:
		if int(stats.get(key, 0)) < int(office.required_stats[key]): return {"ok": false, "error": "当前实际才能尚未达到书吏职责要求"}
	return {"ok": true, "education_ref": source.contract_id, "reason": "已取得实际州学荐举资格，达到本作学舍书吏入职条件；仍需刺史正式辟用"}

static func validate_terms(raw: Dictionary) -> Dictionary:
	for office in raw.get("office_state", {}).values():
		if ENTRY_POSTS.has(office.get("office_id")) and office.get("entry_school_id") != ENTRY_POSTS[office.office_id]: return {"ok": false, "error": "学舍书吏不能丢失荐举资格条件"}
	for term in raw.get("office_terms", {}).values():
		var office: Dictionary = raw.office_state.get(term.get("office_id", ""), {})
		if not office.has("entry_school_id") and not ENTRY_POSTS.has(term.get("office_id")): continue
		if not office.has("entry_school_id"): return {"ok": false, "error": "荐举任期丢失实际职位及条件"}
		var candidate: Dictionary = raw.get("economic_contracts", {}).get(term.get("education_ref", ""), {})
		if candidate.get("contract_kind") != "school_candidacy" or candidate.get("school_id") != office.entry_school_id or candidate.get("supplier_id") != term.get("holder_id") or candidate.get("status") != "admitted" or int(candidate.get("result_day", int(raw.current_day) + 1)) > int(term.get("start_day", -1)):
			return {"ok": false, "error": "学舍书吏任期缺少在任命之前取得的实际荐举资格"}
		var receipt: Dictionary = raw.get("action_receipts", {}).get(term.get("appointment_transaction_id", ""), {})
		if receipt.get("official_record", {}).get("term_ref") != term.term_id or receipt.get("official_record", {}).get("education_ref") != term.education_ref:
			return {"ok": false, "error": "荐举任职缺少共同任命回执及学业来源"}
	return preload("res://scripts/core/central_appointment_rules.gd").validate(raw)
