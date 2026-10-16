extends RefCounted
const Assessment = preload("res://scripts/core/school_assessment_service.gd")
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Presence = preload("res://scripts/core/production_service.gd")

static func arrival(state, hall_id: String, person: String) -> Dictionary:
	var hall: Dictionary = state.management_assets.get(hall_id, {})
	if hall.get("asset_kind") != "examination_hall": return {}
	for journey in state.economic_contracts.values():
		if journey.get("contract_kind") == "school_exam_journey" and journey.get("supplier_id") == person and journey.get("status") in ["arrived", "reported"] and journey.get("rule", {}).get("destination_id") == hall.location_id: return journey
	return {}

static func course_for(state, hall_id: String, person: String) -> Dictionary:
	var journey := arrival(state, hall_id, person)
	return state.economic_contracts.get(journey.get("course_ref"), {})

static func offers(state, hall: Dictionary) -> Array:
	var result: Array = []
	var seen := {}
	for journey in state.economic_contracts.values():
		if journey.get("contract_kind") != "school_exam_journey" or arrival(state, hall.asset_id, str(journey.get("supplier_id", ""))).is_empty() or seen.has(journey.supplier_id): continue
		seen[journey.supplier_id] = true
		var source: Dictionary = state.management_assets.get(journey.school_id, {})
		var offer: Dictionary = load("res://scripts/core/education_service.gd").student_offer(source, journey.supplier_id).duplicate(true)
		if offer.is_empty(): continue
		offer["assessment_willing"] = offer.get("assessment_willing", false) and offer.get("central_exam_willing", false)
		result.append(offer)
	return result

static func project(state, hall: Dictionary) -> Dictionary:
	var result := Assessment.project(state, hall)
	result.merge({"student_offers": offers(state, hall), "teacher_offers": [], "waiting": [], "available_supply_offers": [], "exam_travel_candidates": [], "supplies": [], "living_aid_awards": [], "exam_journeys": []})
	return result

static func _request(state, data: Dictionary, actor: String, kind: String, params: Dictionary, id: String) -> Dictionary:
	return load("res://scripts/core/game_action_dispatcher.gd").apply(state, data, {"action_kind": kind, "parameters": params, "target_refs": [params.school_id], "actor_id": actor, "principal_id": actor, "executor_id": actor, "execution_id": id, "request_id": id, "expected_state_revision": state.state_revision})

static func settle_daily(state, data: Dictionary) -> Dictionary:
	for hall in state.management_assets.values():
		if hall.get("asset_kind") != "examination_hall": continue
		var principal: String = str(state.office_state.get("imperial_court", {}).get("holder_id", ""))
		var projection := Assessment.project(state, hall)
		# A non-player court still acts under its actual authority and pays the
		# actual examiner. A player emperor chooses when to commission the round.
		if principal != state.player_character_id and projection.can_open_assessment and Accounts.new().can_operate(state, hall.account_id, principal) and Presence.present(state, principal, hall.location_id):
			_request(state, data, principal, "open_school_assessment", {"school_id": hall.asset_id, "assessment_id": projection.proposed_assessment_id, "funding_account_id": hall.account_id}, "central-open:" + projection.proposed_assessment_id)
		var exams := Assessment.assessments(state, hall.asset_id)
		if exams.is_empty(): continue
		var exam: Dictionary = exams[-1]
		if exam.status != "registration" or int(state.current_day) > int(exam.deadline): continue
		for offer in offers(state, hall):
			var person: String = offer.character_id
			if person == state.player_character_id or not offer.assessment_willing or not Presence.present(state, person, hall.location_id) or Assessment.admitted(state, hall.asset_id, person): continue
			var id: String = "candidacy:%s:%s" % [exam.contract_id, person]
			if state.economic_contracts.has(id): continue
			_request(state, data, person, "register_school_candidate", {"school_id": hall.asset_id, "assessment_id": exam.contract_id, "student_id": person}, "central-register:" + id)
	return {"ok": true}
