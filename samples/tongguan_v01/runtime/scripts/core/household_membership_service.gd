extends RefCounted

static func members(state, principal: String) -> Array:
	var result: Array = []
	for employment in state.economic_contracts.values():
		if employment.get("contract_kind") != "employment" or employment.get("status") != "active": continue
		var office: Dictionary = state.office_state.get(employment.office_id, {})
		if office.get("holder_id") != employment.employee_id or not load("res://scripts/core/family_office_rules.gd").authority(state, employment.office_id, principal): continue
		result.append({"character_id": employment.employee_id, "office_id": employment.office_id, "contract_ref": employment.contract_id, "organization_id": employment.organization_id, "location_id": state.character_states[employment.employee_id].get("location_id", ""), "wage_amount": employment.remuneration_terms.amount, "arrears": employment.arrears})
	return result

static func sync_person(state, person: String) -> void:
	var active: Array = state.economic_contracts.values().filter(func(row): return row.get("contract_kind") == "employment" and row.get("employee_id") == person and row.get("status") == "active" and row.has("agreement_ref"))
	var character: Dictionary = state.character_states[person]
	if active.is_empty():
		if character.get("allegiance", {}).get("kind") == "employment":
			character.erase("allegiance")
			character["patron_id"] = ""
		return
	var agreement: Dictionary = state.economic_contracts[active[0].agreement_ref]
	var employer: String = agreement.terms.recipient_id if agreement.purpose == "person_arrangement" else agreement.principal_id
	character["allegiance"] = {"target_id": employer, "kind": "employment", "day": agreement.created_day}
	character["patron_id"] = employer
