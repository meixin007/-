extends RefCounted
const Ledger = preload("res://scripts/core/npc_decision_service.gd")
const Relevance = preload("res://scripts/core/npc_relevance_service.gd")
const DecisionContext = preload("res://scripts/core/npc_decision_context_projection.gd")
const Transaction = preload("res://scripts/core/game_state_transaction.gd")
const Opportunity = preload("res://scripts/core/npc_decision_opportunity.gd")

func refresh(context) -> Dictionary:
	var input := {"execution_id": "relevance:" + str(context.state.state_revision)}
	return Ledger._transaction(context, input, func(working):
		var result: Dictionary = Relevance.new().update(working.state, 8, working.world_epoch)
		result["result_ref"] = input.execution_id
		return result
	)

func prepare(context, actor_id: String, rule_source: bool = false) -> Dictionary:
	var row: Dictionary = context.state.npc_ai_runtime.actors.get(actor_id, {})
	if not rule_source and row.get("mode") != "focus_model": return {"ok": false, "error": "NPC is not in the model focus set"}
	var slot: String = Opportunity.next_slot(context.state, actor_id)
	if slot.is_empty(): return {"ok": false, "error": "NPC is not due for another decision"}
	var projection: Dictionary = DecisionContext.new().build(context.state, context.scenario_data, actor_id)
	if not projection.ok: return projection
	projection.context["projection_kind"] = "npc_self_decision_v1"
	var reads := {"characters": [actor_id], "accounts": projection.context.controlled_accounts.keys(), "contracts": projection.context.own_contracts.keys(), "tasks": projection.context.own_tasks.map(func(task): return task.task_id)}
	reads["authorizations"] = projection.context.own_authorizations.keys()
	reads["observer_view"] = [actor_id]
	reads["offices"] = projection.context.own_offices.keys()
	reads["assets"] = projection.context.controlled_assets.keys()
	for id in projection.context.public_assets:
		if not reads.assets.has(id): reads.assets.append(id)
	reads["locations"] = projection.context.travel_destinations.keys()
	reads["claims"] = projection.context.information_claims.keys()
	reads["cases"] = []
	for claim in projection.context.information_claims.values():
		var case_id: String = claim.payload.get("case_id", "")
		if context.state.accountability_cases.has(case_id) and not reads.cases.has(case_id): reads.cases.append(case_id)
	for agreement in projection.context.own_contracts.values():
		if agreement.get("contract_kind") == "social_agreement" and agreement.terms.has("office_id") and not reads.offices.has(agreement.terms.office_id): reads.offices.append(agreement.terms.office_id)
		if agreement.get("purpose") == "person_arrangement" and context.state.office_state.has(agreement.terms.role_ref) and not reads.offices.has(agreement.terms.role_ref): reads.offices.append(agreement.terms.role_ref)
	for id in projection.context.known_characters:
		if not reads.characters.has(id): reads.characters.append(id)
	var full: Dictionary = DecisionContext.new().build(context.state, context.scenario_data, actor_id, 0, -1)
	if not full.ok: return full
	full.context["projection_kind"] = "npc_self_decision_v1"
	full.context["recent_failures"] = load("res://scripts/core/npc_recent_result_projection.gd").failures(row.get("recent_failures", []))
	if not rule_source:
		var wire: Dictionary = load("res://scripts/core/npc_context_pages.gd").new().create(full.context, "scope-preview", context.world_epoch)
		reads["observer_pages"] = [{"kind": "preview", "page_size": wire.context_paging.page_size}]
		reads.characters = [actor_id]
		for id in _collection(wire, "known_characters"):
			if not reads.characters.has(id): reads.characters.append(id)
		reads.accounts = _collection(wire, "controlled_accounts").keys()
		reads.contracts = _collection(wire, "own_contracts").keys()
		reads.authorizations = _collection(wire, "own_authorizations").keys()
		reads.offices = _collection(wire, "own_offices").keys()
		reads.assets = _collection(wire, "controlled_assets").keys()
		for id in _collection(wire, "public_assets"):
			if not reads.assets.has(id): reads.assets.append(id)
		reads.locations = _collection(wire, "travel_destinations").keys()
		reads.claims = _collection(wire, "information_claims").keys()
		reads.cases = []
		for raw_claim in _collection(wire, "information_claims").values():
			var claim: Dictionary = raw_claim.get("preview", raw_claim)
			var payload: Dictionary = claim.get("payload", {})
			var case_id: String = payload.get("preview", payload).get("case_id", "")
			if context.state.accountability_cases.has(case_id) and not reads.cases.has(case_id): reads.cases.append(case_id)
		for raw_contract in _collection(wire, "own_contracts").values():
			var contract: Dictionary = raw_contract.get("preview", raw_contract)
			var terms: Dictionary = contract.get("terms", {})
			terms = terms.get("preview", terms)
			for key in ["office_id", "role_ref"]:
				var office: String = terms.get(key, "")
				if context.state.office_state.has(office) and not reads.offices.has(office): reads.offices.append(office)
		var task_rows: Variant = wire.own_tasks
		if task_rows is Dictionary: task_rows = task_rows.get("preview", [])
		reads.tasks = []
		for raw_task in task_rows:
			var task: Dictionary = raw_task.get("preview", raw_task)
			if task.has("task_id"): reads.tasks.append(task.task_id)
		# Guidance may expose a received offer ahead of the separately paged
		# contract list. Register exactly those delivered stable identities.
		for key in ["employment_guidance", "decision_guidance", "public_work_guidance"]:
			Ledger._append_visible_page_dependencies(wire.get(key, []), reads)
	var opened: Dictionary = Ledger.new().open(context, actor_id, slot, reads)
	if opened.ok:
		opened["context"] = projection.context
		opened["page_source"] = full.context
	return opened

static func _collection(wire: Dictionary, key: String) -> Dictionary:
	var value: Dictionary = wire.get(key, {})
	return value.get("preview", value)

func fallback(context, request_id: String, reason: String) -> Dictionary:
	var record: Dictionary = context.state.npc_decision_records.get(request_id, {})
	if record.get("status") != "pending": return {"ok": false, "error": "NPC slot is no longer pending"}
	if not Ledger.check_current(context, request_id).ok:
		var cancelled: Dictionary = Ledger.new().cancel(context, request_id, "superseded")
		if not cancelled.ok: return cancelled
		# A changed world requires another bounded opportunity attempt. The
		# host will rebuild the visible inputs before another model or rule choice.
		return {"ok": false, "error": "NPC relevant inputs changed; fresh request required"}
	var response: Dictionary = load("res://scripts/core/npc_local_decision_policy.gd").new().choose(context.state, context.scenario_data, record.actor_id)
	var adopted: Dictionary = Ledger.new().adopt(context, request_id, response, "rule")
	if not adopted.ok:
		var category := "domain" if Ledger.check_current(context, request_id).ok else "stale"
		var recorded: Dictionary = Ledger.new().record_failure(context, request_id, category, str(adopted.get("error", "rule_adoption_failed")), response)
		if not recorded.ok: return recorded
		Ledger.new().cancel(context, request_id, "superseded")
	return adopted

func rule_tick(context, limit: int = 2) -> Dictionary:
	var policy = load("res://scripts/core/npc_local_decision_policy.gd").new()
	var ids: Array = []
	for actor in context.scenario_data.get("management", {}).get("life_models", {}):
		if load("res://scripts/core/household_subsistence_service.gd").decision_need(context.state, context.scenario_data, actor).get("needs_food", false): ids.append(actor)
	for contract in context.state.economic_contracts.values():
		var people: Array = contract.get("participant_ids", []) if contract.get("contract_kind") == "social_agreement" and contract.get("status") in ["proposed", "countered", "accepted"] else ([contract.recipient_id] if contract.get("contract_kind") == "gift_delivery" and contract.get("status") == "awaiting_response" else [])
		if contract.get("purpose") == "bribery" and contract.get("status") == "fulfilled": people = [contract.participant_ids[1]]
		for id in people:
			if not ids.has(id): ids.append(id)
	for record in context.state.flags.get("social_reaction_records", {}).values():
		if record.opportunity_kind != "" and not ids.has(record.observer_id): ids.append(record.observer_id)
	ids.sort()
	var count := 0
	for id in ids:
		if id == context.state.player_character_id or count >= clampi(limit, 0, 8): continue
		var row: Dictionary = context.state.npc_ai_runtime.actors.get(id, {})
		if Opportunity.next_slot(context.state, id).is_empty(): continue
		var selection: Dictionary = policy.choose(context.state, context.scenario_data, id)
		if selection.kind == "wait": continue
		var prepared := prepare(context, id, true)
		if not prepared.ok or prepared.get("status") != "pending": continue
		var adopted := Ledger.new().adopt(context, prepared.request_id, selection, "rule")
		if not adopted.ok:
			var category := "domain" if Ledger.check_current(context, prepared.request_id).ok else "stale"
			var recorded: Dictionary = Ledger.new().record_failure(context, prepared.request_id, category, str(adopted.get("error", "rule_adoption_failed")), selection)
			if not recorded.ok: return recorded
			Ledger.new().cancel(context, prepared.request_id, "failed")
		count += 1
	return {"ok": true, "processed": count}

func disable(context) -> Dictionary:
	var input := {"execution_id": "npc-disable:" + str(context.state.npc_ai_runtime.policy_version)}
	return Ledger._transaction(context, input, func(working):
		working.state.npc_ai_runtime.policy_version = int(working.state.npc_ai_runtime.policy_version) + 1
		load("res://scripts/core/npc_ai_state_contract.gd").cancel_pending(working.state)
		for row in working.state.npc_ai_runtime.actors.values():
			if row.mode == "focus_model": row.mode = "related_rules"
		return {"ok": true, "result_ref": input.execution_id}
	)

func cancel_requests(context, request_ids: Array) -> Dictionary:
	for request_id in request_ids:
		var record: Dictionary = context.state.npc_decision_records.get(request_id, {})
		if record.get("status") != "pending": continue
		var cancelled: Dictionary = Ledger.new().cancel(context, request_id)
		if not cancelled.ok: return cancelled
	return {"ok": true}
