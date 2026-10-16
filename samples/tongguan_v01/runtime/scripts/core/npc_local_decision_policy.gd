extends RefCounted
# Finite offline policy. Model decisions retain the open catalog; this fallback
# only continues known offers, obligations and received information.
const ContextProjection = preload("res://scripts/core/npc_decision_context_projection.gd")
const Profile = preload("res://scripts/core/npc_behavior_profile_service.gd")
const Family = preload("res://scripts/core/family_office_rules.gd")
const Workload = preload("res://scripts/core/character_workload_service.gd")

func choose(state, data: Dictionary, actor: String) -> Dictionary:
	var projected: Dictionary = ContextProjection.new().build(state, data, actor)
	if not projected.ok: return wait("self_context_unavailable")
	var view: Dictionary = projected.context
	if view.self_profile.condition in ["dead", "deceased", "executed", "missing", "departed", "exiled"]: return wait("actor_unavailable")
	var food: Dictionary = food_choice(state, data, actor, view)
	if not food.is_empty(): return food
	for claim in view.information_claims.values():
		if claim.payload.get("social_event_kind") != "release_order": continue
		var record: Dictionary = state.accountability_cases.get(claim.payload.get("case_id"), {})
		if not record.is_empty() and load("res://scripts/core/criminal_case_service.gd").physical_control(state, record, actor) and view.self_profile.relationships.get(claim.payload.responsible_id, 0) >= 0: return action("release_criminal_custody", {"case_id": record.case_id, "release_kind": "legal"}, [record.case_id], "obey_received_order_using_actual_custody")
	for opportunity in load("res://scripts/core/npc_social_reaction_service.gd").opportunities(state, actor):
		if opportunity.goal_kind in ["seek_redress", "seek_review"]: return action("petition_criminal_case", {"case_id": opportunity.case_id, "request_text": "本人据实际收到的消息请求复查并保留案卷：" + opportunity.fact_id}, [opportunity.case_id], "seek_review_of_received_case_claim")
	var ids: Array = view.own_contracts.keys()
	ids.sort()
	# Reorder only competing employment-response positions. Other obligations
	# keep their existing relative order; candidates use received signed terms.
	var employment_ids: Array = ids.filter(func(id): return pending_employment(view.own_contracts[id], actor))
	var responses := {}
	var comparisons := {}
	for comparison in view.get("employment_guidance", []): comparisons[comparison.contract_id] = comparison
	for id in employment_ids:
		responses[id] = employment_response(state, data, actor, view, view.own_contracts[id])
	employment_ids.sort_custom(func(a, b):
		var ranks := {"accept": 0, "counter": 1, "reject": 2}
		if ranks[responses[a].choice] != ranks[responses[b].choice]: return ranks[responses[a].choice] < ranks[responses[b].choice]
		var first: Dictionary = view.own_contracts[a]
		var second: Dictionary = view.own_contracts[b]
		var first_comparison: Dictionary = comparisons.get(a, {})
		var second_comparison: Dictionary = comparisons.get(b, {})
		var first_n: int = int(first_comparison.get("comparison_numerator", first.terms.wage_amount))
		var first_d: int = int(first_comparison.get("comparison_denominator", first.terms.period_days))
		var second_n: int = int(second_comparison.get("comparison_numerator", second.terms.wage_amount))
		var second_d: int = int(second_comparison.get("comparison_denominator", second.terms.period_days))
		var left: int = first_n * second_d
		var right: int = second_n * first_d
		if left != right: return left > right
		var relation_a: int = view.self_profile.relationships.get(first.principal_id, 0)
		var relation_b: int = view.self_profile.relationships.get(second.principal_id, 0)
		return relation_a > relation_b if relation_a != relation_b else str(a) < str(b))
	var employment_index := 0
	for index in ids.size():
		if pending_employment(view.own_contracts[ids[index]], actor):
			ids[index] = employment_ids[employment_index]
			employment_index += 1
	for id in ids:
		var row: Dictionary = view.own_contracts[id]
		if row.get("contract_kind") == "gift_delivery" and row.recipient_id == actor and row.status == "awaiting_response":
			var vectors: Dictionary = view.self_profile.vectors
			var relation: int = view.self_profile.relationships.get(row.sender_id, 0)
			var accept: bool = relation >= -15 and (vectors.greed + vectors.compassion >= 0 or vectors.honor < 30)
			return action("respond_gift_delivery", {"delivery_id": id, "choice": "accept" if accept else "reject"}, [id], "gift_interest_and_personal_principles")
		if row.get("contract_kind") != "social_agreement": continue
		if row.status == "fulfilled" and row.purpose == "bribery" and actor == row.participant_ids[1]:
			var criminal = load("res://scripts/core/criminal_case_service.gd")
			var case_record: Dictionary = state.accountability_cases.get(row.terms.case_id, {})
			if view.self_profile.vectors.greed > view.self_profile.vectors.honor:
				if row.terms.intended_action == "private_release" and criminal.physical_control(state, case_record, actor): return action("release_criminal_custody", {"case_id": row.terms.case_id, "release_kind": "private"}, [row.terms.case_id], "perform_paid_promise_using_actual_custody")
				if row.terms.intended_action == "acquit" and case_record.decision.is_empty() and criminal.judge_authority(state, case_record, actor): return action("issue_criminal_verdict", {"case_id": row.terms.case_id, "verdict": "acquit"}, [row.terms.case_id], "perform_paid_promise_with_actual_signing_authority")
		if row.status in ["proposed", "countered"] and row.accepted_versions.get(actor) != row.terms_version:
			var choice := "accept"
			var counter := {}
			if row.purpose == "employment":
				var decision: Dictionary = responses.get(id, {})
				if decision.is_empty(): decision = employment_response(state, data, actor, view, row)
				choice = decision.choice
				counter = decision.counter_terms
			elif row.purpose == "gift_delivery":
				var trip: Dictionary = load("res://scripts/core/regional_visit_service.gd").quote(state, row.terms.destination_id, actor)
				if not trip.ok or row.terms.fee_amount < 2 * trip.get("amount", 0) or view.self_profile.relationships.get(row.principal_id, 0) < -15: choice = "reject"
			elif row.purpose == "bribery":
				if view.self_profile.vectors.honor >= view.self_profile.vectors.greed or view.self_profile.relationships.get(row.principal_id, 0) < -15: choice = "reject"
			elif row.purpose == "person_arrangement":
				if view.self_profile.relationships.get(row.principal_id, 0) < -15 or view.self_profile.condition == "imprisoned": choice = "reject"
				if row.terms.arrangement_kind == "attendant" and actor == row.participant_ids[1] and not Workload.can_schedule(state, actor, "employment", row.terms.recipient_id, state.office_state[row.terms.role_ref]): choice = "reject"
			return action("respond_social_agreement", {"agreement_id": id, "terms_version": row.terms_version, "choice": choice, "counter_terms": counter}, [id], "known_terms_personal_interest_and_commitments")
		if row.status == "accepted":
			if row.purpose == "person_arrangement" and row.terms.arrangement_kind == "attendant" and actor == row.terms.recipient_id: return action("fulfill_social_agreement", {"agreement_id": id, "terms_version": row.terms_version}, [id], "fulfill_independently_accepted_attendant_employment")
			if row.purpose == "employment" and actor == row.participant_ids[1]:
				var office: Dictionary = load("res://scripts/core/npc_opportunity_projection.gd").observed_office(state, row, actor)
				var destination: String = office.get("scope_ref", {}).get("entity_id", "")
				if destination.is_empty(): return wait("accepted_employment_worksite_unknown")
				if view.self_profile.location_id != destination:
					var comparison: Dictionary = comparisons.get(id, {})
					if not comparison.get("blockers", []).is_empty(): return wait("accepted_employment_journey_conditions_not_met")
					return action("visit_region", {"destination_id": destination}, [destination], "travel_to_accepted_employment")
			if actor == row.principal_id: return action("fulfill_social_agreement", {"agreement_id": id, "terms_version": row.terms_version}, [id], "fulfill_accepted_commitment")
	if view.get("survival_guidance", {}).get("needs_food", false):
		return wait("known_food_choices_cooling_down" if view.purchase_guidance.any(func(offer): return offer.can_afford) else "no_affordable_known_food_or_other_feasible_opportunity")
	return wait("no_new_feasible_known_opportunity")

static func pending_employment(row: Dictionary, actor: String) -> bool:
	return row.get("contract_kind") == "social_agreement" and row.get("purpose") == "employment" and row.participant_ids[1] == actor and row.status in ["proposed", "countered"] and row.accepted_versions.get(actor) != row.terms_version

static func employment_response(_state, _data: Dictionary, _actor: String, view: Dictionary, row: Dictionary) -> Dictionary:
	var comparisons: Array = view.get("employment_guidance", []).filter(func(item): return item.contract_id == row.contract_id)
	if comparisons.is_empty() or not comparisons[0].blockers.is_empty(): return {"choice": "reject", "counter_terms": {}}
	var minimum: int = int(comparisons[0].minimum_personal_wage)
	if int(row.terms.wage_amount) < minimum:
		var counter: Dictionary = row.terms.duplicate(true)
		counter.wage_amount = minimum
		return {"choice": "counter", "counter_terms": counter}
	return {"choice": "accept", "counter_terms": {}}
static func food_choice(state, data: Dictionary, actor: String, view: Dictionary) -> Dictionary:
	if not view.get("survival_guidance", {}).get("needs_food", false): return {}
	var offers: Array = view.purchase_guidance.filter(func(row): return row.can_afford)
	# Compare only posted prices and lot sizes. Seller stock remains private
	# and is rechecked by the common domain when attempting the transaction.
	offers.sort_custom(func(a, b):
		var left: int = int(a.quoted_cost.amount) * int(b.ration_units)
		var right: int = int(b.quoted_cost.amount) * int(a.ration_units)
		return left < right if left != right else str(a.action.parameters.stall_id) < str(b.action.parameters.stall_id))
	for offer in offers:
		var selection := action("buy_food", offer.action.parameters.duplicate(true), offer.action.target_refs.duplicate(), "secure_next_meal_from_posted_food_with_personal_cash")
		var digest: String = load("res://scripts/core/npc_decision_service.gd")._selection_hash(selection)
		var repeated: Array = state.npc_ai_runtime.actors.get(actor, {}).get("recent_failures", []).filter(func(failure): return failure.category == "domain" and failure.repeat_count >= 2 and failure.selection_hash == digest and failure.day == state.current_day)
		if not repeated.is_empty():
			var current: Dictionary = load("res://scripts/core/npc_ai_state_contract.gd").fingerprint(state, {"observer_view": [actor]}, data)
			if current.ok and repeated.any(func(failure): return failure.read_fingerprint == current.hash): continue
		return selection
	return {}

static func action(kind: String, params: Dictionary, targets: Array, reason: String) -> Dictionary:
	return {"schema_version": 1, "kind": "action", "reason_code": reason, "action": {"action_kind": kind, "parameters": params, "target_refs": targets}, "plan": {}, "resource_limits": []}

static func wait(reason: String) -> Dictionary:
	return {"schema_version": 1, "kind": "wait", "reason_code": reason, "action": {}, "plan": {}, "resource_limits": []}
