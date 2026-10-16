extends RefCounted
## Pure guidance from authorized projections and original shared work/travel rules.
const Workload = preload("res://scripts/core/character_workload_service.gd")
const Family = preload("res://scripts/core/family_office_rules.gd")
const Travel = preload("res://scripts/core/regional_visit_service.gd")

static func employment(state, data: Dictionary, view: Dictionary) -> Array:
	var actor: String = view.actor_id
	var result: Array = []
	for id in view.own_contracts:
		var contract: Dictionary = view.own_contracts[id]
		if contract.get("contract_kind") != "social_agreement" or contract.get("purpose") != "employment" or contract.participant_ids[1] != actor or contract.status not in ["proposed", "countered", "accepted"]: continue
		var office := observed_office(state, contract, actor)
		var blockers: Array = []
		var schedule: Array = office.get("work_schedule", {}).get("days", [])
		var days: Array = []
		for day in schedule:
			if not days.has(int(day)): days.append(int(day))
		if office.is_empty() or days.is_empty(): blockers.append("quoted_work_conditions_unknown")
		if view.self_profile.condition in ["dead", "deceased", "executed", "missing", "imprisoned", "departed", "exiled", "unreachable"]: blockers.append("self_unavailable")
		if not Workload.can_schedule(state, actor, "employment", contract.principal_id): blockers.append("own_work_or_journey_conflict")
		if not office.is_empty():
			# Only the conflict result is used: it concerns the candidate's own
			# actual duties/orders. Willingness uses the received terms below.
			var own_assessment: Dictionary = Family.assess(state, data, contract.terms.office_id, actor, int(contract.terms.wage_amount), office)
			if not str(own_assessment.get("conflict_office", "")).is_empty(): blockers.append("own_existing_commitment_conflict")
		var signed: Array = []
		for promise in view.own_contracts.values():
			if promise.get("contract_kind") != "social_agreement" or promise.get("purpose") != "employment" or promise.contract_id == id or promise.participant_ids[1] != actor: continue
			if promise.status not in ["proposed", "countered", "accepted"] or promise.accepted_versions.get(actor) != promise.terms_version: continue
			signed.append(promise.contract_id)
			var prior := observed_office(state, promise, actor)
			if prior.is_empty() or office.is_empty() or prior.get("organization_id") != office.get("organization_id") or Workload.overlaps(prior, office):
				if not blockers.has("known_signed_commitment_overlap"): blockers.append("known_signed_commitment_overlap")
		var destination: String = office.get("scope_ref", {}).get("entity_id", "")
		var needs_travel: bool = destination != "" and destination != view.self_profile.location_id
		var travel := {"required": needs_travel, "known": not destination.is_empty(), "destination_id": destination, "fare_amount": 0, "days": 0, "can_afford": true, "source_id": Travel.SOURCE}
		if needs_travel:
			var quote: Dictionary = Travel.quote(state, destination, actor)
			travel.known = quote.ok
			if quote.ok:
				travel.fare_amount = int(quote.amount)
				travel.days = int(quote.days)
				travel.can_afford = int(view.controlled_accounts.get(quote.account_id, {}).get("available", 0)) >= int(quote.amount)
				if not travel.can_afford: blockers.append("insufficient_known_fare")
			else: blockers.append("no_available_configured_journey")
		var wage: int = int(contract.terms.wage_amount)
		var period: int = int(contract.terms.period_days)
		var preferences: Dictionary = view.self_profile.employment_preferences
		var minimum: int = maxi(1, int(preferences.get("minimum_wage", 0)) + maxi(0, int(view.self_profile.vectors.greed)) / 10)
		var net: int = wage - int(travel.fare_amount)
		result.append({"contract_id": id, "office_id": contract.terms.office_id, "terms_version": contract.terms_version, "known_day": contract.get("known_day", 0), "wage_amount": wage, "period_days": period, "work_days_per_week": days.size(), "travel": travel, "first_period_net_after_fare": net, "comparison_numerator": maxi(0, net) * 7, "comparison_denominator": maxi(1, period + int(travel.days)) * maxi(1, days.size()), "qualification": "eligible" if blockers.is_empty() else "blocked", "blockers": blockers, "signed_commitments": signed, "minimum_personal_wage": minimum, "role_preferred": preferences.get("roles", []).has(office.get("role_key")), "employer_preferred": preferences.get("organization_ids", []).has(office.get("organization_id")), "relationship": view.self_profile.relationships.get(contract.principal_id, 0), "source_refs": [id], "requires_world_recheck": true})
	result.sort_custom(func(a, b):
		if a.blockers.is_empty() != b.blockers.is_empty(): return a.blockers.is_empty()
		var left: int = int(a.comparison_numerator) * int(b.comparison_denominator)
		var right: int = int(b.comparison_numerator) * int(a.comparison_denominator)
		if left != right: return left > right
		if a.relationship != b.relationship: return a.relationship > b.relationship
		return str(a.contract_id) < str(b.contract_id))
	return result

static func observed_office(state, contract: Dictionary, actor: String) -> Dictionary:
	var snapshot: Dictionary = contract.get("employment_offer", {}).get("office", {})
	if not snapshot.is_empty():
		var result := snapshot.duplicate(true)
		result["remuneration_terms"] = result.get("remuneration_terms", {}).duplicate(true)
		result.remuneration_terms["amount"] = contract.terms.wage_amount
		result.remuneration_terms["period_days"] = contract.terms.period_days
		return result
	# Legacy same-version messages did not carry a schedule. Only a currently
	# observed public local notice may supply missing conditions; remote gaps
	# remain explicit rather than consulting another actor's live private office.
	var current: Dictionary = state.office_state.get(contract.terms.office_id, {})
	var notice: Dictionary = current.get("recruitment_notice", {})
	if notice.get("visibility") != "public" or notice.get("location_id") != state.character_states[actor].get("location_id"): return {}
	return public_office(current, contract.terms)

static func public_office(office: Dictionary, terms: Dictionary) -> Dictionary:
	var result := {}
	for key in ["office_id", "name", "office_kind", "role_key", "organization_id", "scope_ref", "work_schedule"]:
		if not office.has(key): continue
		result[key] = office[key].duplicate(true) if office[key] is Dictionary or office[key] is Array else office[key]
	result["remuneration_terms"] = {"amount": terms.wage_amount, "period_days": terms.period_days, "account_id": office.get("remuneration_terms", {}).get("account_id", "")}
	return result

static func public_work(state, data: Dictionary, view: Dictionary) -> Array:
	var actor: String = view.actor_id
	var model: Dictionary = data.get("management", {}).get("life_models", {}).get(actor, {})
	if model.is_empty(): return []
	# The original livelihood service owns discovery and application. This
	# projection describes that route without inventing a callable apply action.
	var options: Array = load("res://scripts/core/character_agenda_service.gd").new()._known_jobs(state, data, actor, model, view.own_contracts)
	var goal: Dictionary = view.self_profile.life_goal
	var application: Dictionary = goal.get("application", {})
	var result: Array = []
	for option in options:
		var office: Dictionary = state.office_state[option.office_id]
		var blockers: Array = []
		if view.self_profile.condition in ["dead", "deceased", "executed", "missing", "imprisoned", "departed", "exiled", "unreachable"]: blockers.append("self_unavailable")
		var assessment: Dictionary = Family.assess(state, data, option.office_id, actor, int(option.requested_wage), public_office(office, {"wage_amount": option.requested_wage, "period_days": option.period_days}))
		if not str(assessment.get("conflict_office", "")).is_empty(): blockers.append("own_existing_commitment_conflict")
		if not Workload.can_schedule(state, actor, "employment", option.employer_id): blockers.append("own_work_or_journey_conflict")
		if int(goal.get("rejected_offices", {}).get(option.office_id, -1)) > int(view.day): blockers.append("original_application_cooldown")
		if application.get("status") == "waiting": blockers.append("original_application_awaiting_response")
		if not option.get("known_commitment_refs", []).is_empty(): blockers.append("known_signed_commitment_overlap")
		var days: Array = []
		for day in office.get("work_schedule", {}).get("days", []):
			if not days.has(int(day)): days.append(int(day))
		if days.is_empty(): blockers.append("quoted_work_conditions_unknown")
		var own_application := {}
		if application.get("office_id") == option.office_id: own_application = application.duplicate(true)
		# Discovery location identifies where the public notice was observed;
		# attendance uses its advertised office scope. Neither creates a journey.
		var scope: Dictionary = office.get("scope_ref", {})
		var workplace: String = str(scope.get("entity_id", "")) if scope.get("entity_kind") == "location" else ""
		var needs_travel: bool = not workplace.is_empty() and workplace != view.self_profile.location_id
		var travel := {"required": needs_travel, "known": not workplace.is_empty(), "destination_id": workplace, "fare_amount": 0, "days": 0, "can_afford": not workplace.is_empty(), "source_id": Travel.SOURCE}
		if workplace.is_empty(): blockers.append("quoted_worksite_unknown")
		elif needs_travel:
			var quote: Dictionary = Travel.quote(state, workplace, actor)
			travel.known = quote.ok
			travel.can_afford = false
			if quote.ok:
				travel.fare_amount = int(quote.amount)
				travel.days = int(quote.days)
				travel.can_afford = int(view.controlled_accounts.get(quote.account_id, {}).get("available", 0)) >= int(quote.amount)
				if not travel.can_afford: blockers.append("insufficient_known_fare")
			else: blockers.append("no_available_configured_journey")
		var net: int = int(option.quoted_wage) - int(travel.fare_amount)
		result.append({"office_id": option.office_id, "location_id": office.recruitment_notice.location_id, "workplace_id": workplace, "travel": travel, "wage_amount": option.quoted_wage, "requested_wage": option.requested_wage, "period_days": option.period_days, "work_days_per_week": days.size(), "first_period_net_after_fare": net, "comparison_numerator": maxi(0, net) * 7, "comparison_denominator": (int(option.period_days) + int(travel.days)) * maxi(1, days.size()), "relationship": view.self_profile.relationships.get(option.employer_id, 0), "qualification": "own_conditions_met" if blockers.is_empty() else "blocked", "qualification_basis": "original_own_preferences_and_shared_commitments", "blockers": blockers, "application": own_application, "source_refs": [option.notice_source], "feasible_actions": [], "continuation": "original_livelihood_review", "requires_employer_consent": true, "requires_world_recheck": true})
	return result

static func goals(view: Dictionary) -> Array:
	var result: Array = []
	var need: Dictionary = view.survival_guidance
	if not need.is_empty():
		var actions: Array = []
		for offer in view.purchase_guidance:
			if offer.can_afford: actions.append(offer.action.duplicate(true))
		result.append({"goal_kind": "survival", "urgency": need.urgency, "source_refs": [need.ration_account_id, need.source_id], "daily_required_units": need.daily_ration_units, "available_units": need.available_ration_units, "feasible_actions": actions, "requires_world_recheck": true})
	for task in view.own_tasks:
		if task.get("status") in ["completed", "cancelled"]: continue
		result.append({"goal_kind": "commitment", "urgency": "due" if int(task.get("due_day", 2147483647)) <= int(view.day) else "scheduled", "due_day": task.get("due_day", -1), "status": task.status, "source_refs": [task.task_id], "feasible_actions": [], "continuation": "original_task_queue", "may_revise_own_remaining_plan": task.get("principal_id") == view.actor_id and task.get("executor_id") == view.actor_id and not task.has("business_policy") and task.get("source_agreement_id", "") == ""})
	for row in view.get("employment_guidance", []):
		result.append({"goal_kind": "employment", "urgency": "response_pending", "source_refs": row.source_refs.duplicate(), "blockers": row.blockers.duplicate(), "feasible_actions": [{"action_kind": "respond_social_agreement", "parameters": {"agreement_id": row.contract_id, "terms_version": row.terms_version, "choice": "accept", "counter_terms": {}}, "target_refs": [row.contract_id]}] if row.blockers.is_empty() else [], "requires_world_recheck": true})
	for row in view.get("public_work_guidance", []):
		result.append({"goal_kind": "employment", "urgency": "response_pending" if row.application.get("status") == "waiting" else "scheduled", "office_id": row.office_id, "source_refs": row.source_refs.duplicate(), "blockers": row.blockers.duplicate(), "feasible_actions": [], "continuation": row.continuation, "application": row.application.duplicate(true), "requires_world_recheck": true})
	if not view.controlled_accounts.is_empty():
		result.append({"goal_kind": "resources", "urgency": "longer_term", "source_refs": view.controlled_accounts.keys(), "reserve_target": view.self_profile.life_goal.get("private_priorities", {}).get("reserve_target", null), "feasible_actions": [], "basis": "actual_controlled_accounts_and_original_life_goal"})
	result.sort_custom(func(a, b):
		var ranks := {"next_meal": 0, "due": 1, "response_pending": 2, "scheduled": 3, "pantry_sufficient": 4, "longer_term": 5}
		return int(ranks.get(a.urgency, 10)) < int(ranks.get(b.urgency, 10)))
	return result
