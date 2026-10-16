extends RefCounted
const Catalog = preload("res://scripts/domain/tang_office_catalog.gd")
const Presence = preload("res://scripts/core/production_service.gd")
const Accounts = preload("res://scripts/core/resource_account_service.gd")

static func qualification(raw: Dictionary, office_id: String, person: String, through_day: int) -> Dictionary:
	for candidate in raw.get("economic_contracts", {}).values():
		if candidate.get("contract_kind") != "school_candidacy" or candidate.get("supplier_id") != person or candidate.get("status") != "admitted" or int(candidate.get("result_day", through_day + 1)) > through_day: continue
		var venue: Dictionary = raw.get("management_assets", {}).get(candidate.get("school_id"), {})
		if venue.get("asset_kind") == "examination_hall" and venue.get("appointment_rules", {}).get("office_ids", []).has(Catalog.canonical_id(office_id)): return candidate
	return {}

static func assess(state, office_id: String, person: String) -> Dictionary:
	var source := qualification({"economic_contracts": state.economic_contracts, "management_assets": state.management_assets}, office_id, person, int(state.current_day))
	if source.is_empty(): return {"ok": true, "applicable": false}
	var venue: Dictionary = state.management_assets[source.school_id]
	var journey: Dictionary = state.economic_contracts.get(source.get("journey_ref"), {})
	var school: Dictionary = state.management_assets.get(journey.get("school_id"), {})
	var offer: Dictionary = load("res://scripts/core/education_service.gd").student_offer(school, person)
	var ruler: String = str(state.office_state.get("imperial_court", {}).get("holder_id", ""))
	if not offer.get("central_office_willing", false) or int(state.character_states.get(person, {}).get("relationships", {}).get(ruler, 0)) < -15: return {"ok": false, "error": "中央录取不代替本人受职意愿；本人目前不愿接受任用"}
	if not Presence.present(state, person, venue.location_id) or Accounts.new().location(state, person + "_cash") != venue.location_id: return {"ok": false, "error": "本人及随身账户尚未在行在完成到任核验"}
	for office in state.office_state.values():
		if office.get("holder_id") == person and office.get("status") == "appointed" and Catalog.canonical_id(str(office.get("office_id", ""))) != Catalog.canonical_id(office_id): return {"ok": false, "error": "本人仍在其他职位履职，须先办理离任交接"}
	return {"ok": true, "applicable": true, "education_ref": source.contract_id, "education_entry": {"venue_id": venue.asset_id, "source_id": venue.appointment_rules.source_id, "arrival_ref": journey.contract_id, "location_id": venue.location_id, "consent": true}, "reason": "已取得实际中央录取，并核验本人受职意愿与行在到任；原官职才能、权源及破格成本仍适用"}

static func validate(raw: Dictionary) -> Dictionary:
	for venue in raw.get("management_assets", {}).values():
		if venue.get("asset_kind") != "examination_hall" or not venue.has("appointment_rules"): continue
		var rules: Variant = venue.appointment_rules
		if not rules is Dictionary or not str(rules.get("source_id", "")).begins_with("scenario:") or not rules.get("office_ids") is Array or rules.office_ids.is_empty() or not rules.get("content_basis") is String: return {"ok": false, "error": "中央考试任用衔接缺少明确来源"}
		var seen := {}
		for office_id in rules.office_ids:
			if not office_id is String or not raw.office_state.has(office_id) or seen.has(office_id): return {"ok": false, "error": "中央考试任用引用不存在或重复职位"}
			seen[office_id] = true
	for term in raw.get("office_terms", {}).values():
		var expected := qualification(raw, str(term.get("office_id", "")), str(term.get("holder_id", "")), int(term.get("start_day", -1)))
		if expected.is_empty():
			if term.has("education_entry"): return {"ok": false, "error": "中央任期没有在任命之前取得对应考试资格"}
			continue
		if term.get("education_ref") != expected.contract_id or not term.get("education_entry") is Dictionary: return {"ok": false, "error": "中央任期丢失实际录取及到任条件"}
		var venue: Dictionary = raw.management_assets[expected.school_id]
		var journey: Dictionary = raw.economic_contracts.get(expected.get("journey_ref"), {})
		var entry: Dictionary = term.education_entry
		if entry != {"venue_id": venue.asset_id, "source_id": venue.appointment_rules.source_id, "arrival_ref": journey.get("contract_id"), "location_id": venue.location_id, "consent": true} or int(journey.get("arrived_day", raw.current_day + 1)) > int(term.start_day): return {"ok": false, "error": "中央任期的本人同意、资格或实际到任来源无效"}
		var receipt: Dictionary = raw.action_receipts.get(term.get("appointment_transaction_id"), {}).get("official_record", {})
		if receipt.get("term_ref") != term.term_id or receipt.get("education_ref") != expected.contract_id or receipt.get("education_entry") != entry: return {"ok": false, "error": "中央录取任官缺少共同任命回执"}
	return {"ok": true}
