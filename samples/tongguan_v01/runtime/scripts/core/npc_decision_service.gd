extends RefCounted

const Contract = preload("res://scripts/core/npc_ai_state_contract.gd")
const Transaction = preload("res://scripts/core/game_state_transaction.gd")

func open(context, actor_id: String, slot_id: String, read_set: Dictionary) -> Dictionary:
	var prepared := _prepare_open(context, actor_id, slot_id, read_set)
	if not prepared.has("input"): return prepared
	return _transaction(context, prepared.input, func(working): return _make_record(working, prepared.input))

static func _prepare_open(context, actor_id: String, slot_id: String, read_set: Dictionary) -> Dictionary:
	if context == null or context.state == null or not context.state.character_states.has(actor_id) or not Contract.text_id(slot_id): return Contract.fail("invalid NPC decision actor or slot")
	var reads := read_set.duplicate(true)
	if not reads.get("characters", []) is Array: return Contract.fail("invalid NPC character read set")
	if not reads.has("characters"): reads["characters"] = []
	if not reads.characters.has(actor_id): reads.characters.append(actor_id)
	reads["behavior"] = [actor_id]
	var attempt_count := 0
	for record in context.state.npc_decision_records.values():
		if record.actor_id == actor_id and preload("res://scripts/core/npc_decision_opportunity.gd").slot_identity(record.slot_id) == preload("res://scripts/core/npc_decision_opportunity.gd").slot_identity(slot_id):
			attempt_count += 1
			if record.status in ["pending", "adopted"]:
				return {"ok": true, "code": "existing_slot", "request_id": record.request_id, "status": record.status}
	if attempt_count >= 3: return Contract.fail("NPC opportunity retry limit reached")
	var actor: Dictionary = context.state.npc_ai_runtime.actors.get(actor_id, {})
	if actor.get("pending_request_id", "") != "": return Contract.fail("actor already has a pending decision")
	var fingerprint: Dictionary = Contract.fingerprint(context.state, reads, context.scenario_data)
	if not fingerprint.ok: return fingerprint
	var input := {"execution_id": "open:" + actor_id + ":" + str(int(context.state.npc_ai_runtime.request_sequence) + 1), "actor_id": actor_id, "slot_id": slot_id, "reads": reads, "fingerprint": fingerprint.hash, "epoch": context.world_epoch}
	return {"ok": true, "input": input}

static func _make_record(working, input: Dictionary) -> Dictionary:
	var state = working.state
	var actor_id: String = input.actor_id
	# JSON restores whole-number counters as floats. Canonical integer IDs
	# must survive that representation change without skipping any history.
	state.npc_ai_runtime.request_sequence = int(state.npc_ai_runtime.request_sequence) + 1
	var id: String = "npc-request:" + str(state.npc_ai_runtime.request_sequence) + ":" + actor_id
	if not state.npc_ai_runtime.actors.has(actor_id): state.npc_ai_runtime.actors[actor_id] = Contract.default_actor(state.current_day)
	state.npc_ai_runtime.actors[actor_id].pending_request_id = id
	state.npc_decision_records[id] = {"request_id": id, "slot_id": input.slot_id, "actor_id": actor_id, "player_character_id": state.player_character_id, "policy_version": state.npc_ai_runtime.policy_version, "world_epoch": input.epoch, "status": "pending", "read_set": input.reads.duplicate(true), "read_fingerprint": input.fingerprint, "selection": {}, "source": "", "adoption_order": 0, "result_ref": "", "opened_day": state.current_day, "resolved_day": -1}
	return {"ok": true, "request_id": id, "status": "pending", "result_ref": id}

func cancel(context, request_id: String, status: String = "cancelled") -> Dictionary:
	if status not in ["cancelled", "superseded", "failed"] or not context.state.npc_decision_records.has(request_id): return Contract.fail("invalid NPC cancellation")
	var record: Dictionary = context.state.npc_decision_records[request_id]
	if record.status != "pending": return {"ok": true, "code": "already_resolved", "result_ref": request_id}
	return _transaction(context, {"execution_id": "resolve:" + request_id, "status": status}, func(working): return _cancel_pending(working.state, request_id, status))

static func _cancel_pending(state, request_id: String, status: String) -> Dictionary:
	var row: Dictionary = state.npc_decision_records[request_id]
	row.status = status
	row.resolved_day = state.current_day
	if state.npc_ai_runtime.actors[row.actor_id].pending_request_id == request_id: state.npc_ai_runtime.actors[row.actor_id].pending_request_id = ""
	return {"ok": true, "result_ref": request_id}

func adopt(context, request_id: String, response: Dictionary, source: String) -> Dictionary:
	var prepared := _prepare_adoption(context, request_id, response, source)
	if not prepared.has("selection"): return prepared
	return _transaction(context, {"execution_id": "adopt:" + request_id, "selection": prepared.selection, "source": source}, func(working): return _apply_adoption(working, request_id, prepared.selection, source))

static func _prepare_adoption(context, request_id: String, response: Dictionary, source: String) -> Dictionary:
	if context == null or context.state == null or source not in ["model", "rule"] or not context.state.npc_decision_records.has(request_id): return Contract.fail("unknown NPC request or source")
	var parsed: Dictionary = load("res://scripts/ai/npc_decision_parser.gd").new().parse(response)
	if not parsed.ok: return parsed
	var record: Dictionary = context.state.npc_decision_records[request_id]
	if record.status == "adopted":
		if record.selection != parsed.selection or record.source != source: return Contract.fail("resolved NPC slot cannot adopt a different choice")
		return {"ok": true, "code": "idempotent_replay", "result_ref": record.result_ref}
	var current: Dictionary = check_current(context, request_id)
	if not current.ok: return current
	var choice_hash: String = _selection_hash(parsed.selection)
	for failure in context.state.npc_ai_runtime.actors[record.actor_id].recent_failures:
		if failure.category == "domain" and failure.repeat_count >= 2 and failure.selection_hash == choice_hash and failure.read_fingerprint == record.read_fingerprint and failure.day == context.state.current_day: return Contract.fail("NPC unchanged failed choice is cooling down")
	var scoped: Dictionary = check_object_scope(record, parsed.selection)
	if not scoped.ok: return scoped
	return {"ok": true, "selection": parsed.selection}

static func _apply_adoption(working, request_id: String, selection: Dictionary, source: String) -> Dictionary:
	var recheck: Dictionary = check_current(working, request_id)
	if not recheck.ok: return recheck
	var state = working.state
	var row: Dictionary = state.npc_decision_records[request_id]
	var result := {"ok": true, "result_ref": request_id}
	if selection.kind == "action":
		var dispatcher = load("res://scripts/core/game_action_dispatcher.gd")
		var request: Dictionary = dispatcher.bind_npc_request(state, row.actor_id, selection.action, "npc-action:" + request_id)
		result = dispatcher.apply(state, working.scenario_data, request)
	elif selection.kind == "plan":
		var authority = load("res://scripts/core/action_authorization_service.gd")
		result = authority.apply_npc_revision(working, row.actor_id, selection.plan, selection.resource_limits, request_id) if selection.plan.has("task_id") else authority.apply_npc_plan(working, row.actor_id, selection.plan, selection.resource_limits, request_id)
	if not result.ok: return result
	state.npc_ai_runtime.adoption_sequence = int(state.npc_ai_runtime.adoption_sequence) + 1
	row.status = "adopted"
	row.selection = selection.duplicate(true)
	row.source = source
	row.adoption_order = state.npc_ai_runtime.adoption_sequence
	row.result_ref = result.result_ref
	row.resolved_day = state.current_day
	state.npc_ai_runtime.actors[row.actor_id].pending_request_id = ""
	state.npc_ai_runtime.actors[row.actor_id].last_decision_day = state.current_day
	return result

static func _selection_hash(selection: Dictionary) -> String:
	var payload := selection.duplicate(true)
	payload.erase("reason_code")
	return load("res://scripts/core/canonical_json.gd").hash_value(payload).get("hash", "")

func record_failure(context, request_id: String, category: String, error: String, selection: Dictionary = {}) -> Dictionary:
	if category not in ["transport", "protocol", "stale", "domain"] or not context.state.npc_decision_records.has(request_id): return Contract.fail("invalid NPC failure")
	var record: Dictionary = context.state.npc_decision_records[request_id]
	if record.world_epoch != context.world_epoch or record.status != "pending": return Contract.fail("NPC failure belongs to an old request")
	var digest := _selection_hash(selection)
	if digest.is_empty(): return Contract.fail("noncanonical failed NPC selection")
	var message: String = error.left(256) if not error.is_empty() else "request_failed"
	if category != "domain": message = {"transport": "npc_transport_failed", "protocol": "npc_protocol_invalid", "stale": "npc_inputs_changed"}[category]
	elif message.to_lower().contains("bearer ") or message.to_lower().contains("sk-") or message.to_lower().contains("api_key"): message = "npc_conditions_not_met"
	var attempted_kind := "unknown"
	var attempted_kinds: Array = []
	var parsed: Dictionary = load("res://scripts/ai/npc_decision_parser.gd").new().parse(selection)
	if parsed.ok:
		attempted_kind = parsed.selection.kind
		var actions: Array = [parsed.selection.action] if attempted_kind == "action" else parsed.selection.plan.get("steps", [])
		for action in actions:
			if not attempted_kinds.has(action.action_kind): attempted_kinds.append(action.action_kind)
	return _transaction(context, {"execution_id": "failure:%s:%s" % [request_id, context.state.state_revision], "category": category, "error": message, "selection_hash": digest}, func(working): return _apply_failure(working, request_id, category, message, digest, attempted_kind, attempted_kinds))

static func _apply_failure(working, request_id: String, category: String, message: String, digest: String, attempted_kind: String, attempted_kinds: Array) -> Dictionary:
	var record: Dictionary = working.state.npc_decision_records[request_id]
	var history: Array = working.state.npc_ai_runtime.actors[record.actor_id].recent_failures
	for failure in history:
		if failure.category == category and failure.error == message and failure.selection_hash == digest and failure.read_fingerprint == record.read_fingerprint and failure.day == working.state.current_day:
			failure.repeat_count = mini(int(failure.repeat_count) + 1, 1000)
			failure.request_id = request_id
			failure["attempted_kind"] = attempted_kind
			failure["attempted_kinds"] = attempted_kinds.duplicate()
			return {"ok": true, "result_ref": request_id}
	history.append({"request_id": request_id, "category": category, "error": message, "day": working.state.current_day, "selection_hash": digest, "read_fingerprint": record.read_fingerprint, "repeat_count": 1, "attempted_kind": attempted_kind, "attempted_kinds": attempted_kinds.duplicate()})
	while history.size() > 8: history.pop_front()
	return {"ok": true, "result_ref": request_id}

static func settlement_food_choice(working, actor: String, response: Dictionary) -> Dictionary:
	# Compose the SAME record and shared action inside the caller's existing
	# daily settlement. A nested transaction would replace its state object and
	# detach later mandatory meals from the original daily working state.
	if working == null or working.state == null or working.scenario_data.get("campaign_id") != "anshi_beta_1_14" or actor == working.state.player_character_id: return Contract.fail("invalid NPC settlement food actor")
	var parsed: Dictionary = load("res://scripts/ai/npc_decision_parser.gd").new().parse(response)
	if not parsed.ok: return parsed
	if parsed.selection.kind != "action" or parsed.selection.action.action_kind != "buy_food": return Contract.fail("settlement continuation only accepts an actual food purchase")
	var state = working.state
	var request_id: String = state.npc_ai_runtime.actors.get(actor, {}).get("pending_request_id", "")
	var slot := ""
	var adoption := {}
	if not request_id.is_empty():
		var pending: Dictionary = state.npc_decision_records[request_id]
		if int(pending.opened_day) == int(state.current_day):
			slot = pending.slot_id
			adoption = _prepare_adoption(working, request_id, parsed.selection, "rule")
		if not adoption.has("selection"):
			_cancel_pending(state, request_id, "superseded")
			request_id = ""
	if request_id.is_empty():
		if slot.is_empty(): slot = load("res://scripts/core/npc_decision_opportunity.gd").next_slot(state, actor)
		if slot.is_empty(): return {"ok": true, "code": "choice_already_resolved", "purchased": false, "result_ref": ""}
		var projected: Dictionary = load("res://scripts/core/npc_decision_context_projection.gd").new().build(state, working.scenario_data, actor, 0, -1)
		if not projected.ok: return projected
		var view: Dictionary = projected.context
		var assets: Array = view.controlled_assets.keys()
		for id in view.public_assets:
			if not assets.has(id): assets.append(id)
		var opened := _prepare_open(working, actor, slot, {"characters": [actor], "accounts": view.controlled_accounts.keys(), "assets": assets, "observer_view": [actor]})
		if not opened.ok: return {"ok": true, "code": "opportunity_unavailable", "purchased": false, "result_ref": ""}
		if opened.has("input"): opened = _make_record(working, opened.input)
		if opened.get("status") != "pending": return {"ok": true, "code": "choice_already_resolved", "purchased": false, "result_ref": ""}
		request_id = opened.request_id
		adoption = _prepare_adoption(working, request_id, parsed.selection, "rule")
	if not adoption.has("selection"):
		_apply_failure(working, request_id, "domain", "npc_meal_conditions_not_met", _selection_hash(parsed.selection), "action", ["buy_food"])
		_cancel_pending(state, request_id, "failed")
		return {"ok": true, "code": "meal_conditions_not_met", "purchased": false, "result_ref": ""}
	# Food's shared domain checks funds/stock before transfer. Any unexpected
	# partial failure must abort the OUTER daily transaction, never be concealed
	# as a harmless local failure with a lost payment.
	var receipts_before: int = state.action_receipts.size()
	var journal_before: int = state.resource_journal.size()
	var contracts_before: int = state.economic_contracts.size()
	var result := _apply_adoption(working, request_id, adoption.selection, "rule")
	if not result.ok:
		if state.action_receipts.size() != receipts_before or state.resource_journal.size() != journal_before or state.economic_contracts.size() != contracts_before: return Contract.fail("food continuation requires outer daily rollback")
		_apply_failure(working, request_id, "domain", str(result.get("error", "npc_meal_conditions_not_met")).left(256), _selection_hash(parsed.selection), "action", ["buy_food"])
		_cancel_pending(state, request_id, "failed")
		return {"ok": true, "code": "meal_conditions_not_met", "purchased": false, "result_ref": ""}
	result["purchased"] = true
	return result

func mark_model_service(context, request_id: String) -> Dictionary:
	var record: Dictionary = context.state.npc_decision_records.get(request_id, {})
	if record.get("world_epoch") != context.world_epoch or record.get("status") != "pending": return Contract.fail("model service belongs to an old request")
	# Preserve service already recorded by the request-keyed implementation.
	# Retries and restore must not erase a real prior service of this slot.
	var opportunity = preload("res://scripts/core/npc_decision_opportunity.gd")
	var logical_slot: String = opportunity.slot_identity(record.slot_id)
	for prior in context.state.npc_decision_records.values():
		if prior.actor_id != record.actor_id or opportunity.slot_identity(prior.slot_id) != logical_slot: continue
		for key in ["model-service:" + str(prior.request_id), "model-service-opportunity:" + str(prior.actor_id) + ":" + str(prior.slot_id)]:
			var receipt_id: String = "tx|npc_decision|" + key.sha256_text().left(32)
			if context.state.processed_transactions.has(receipt_id): return {"ok": true, "code": "opportunity_already_served", "result_ref": context.state.processed_transactions[receipt_id].result_ref}
	var identity: String = "model-service-opportunity:" + str(record.actor_id) + ":" + logical_slot
	return _transaction(context, {"execution_id": identity}, func(working):
		working.state.npc_ai_runtime.model_service_sequence = int(working.state.npc_ai_runtime.model_service_sequence) + 1
		var actor: Dictionary = working.state.npc_ai_runtime.actors[record.actor_id]
		actor.model_service_order = working.state.npc_ai_runtime.model_service_sequence
		actor.waiting_since_day = working.state.current_day
		return {"ok": true, "result_ref": request_id}
	)

static func check_page_budget(state, request_id: String) -> Dictionary:
	var current: Variant = state.npc_decision_records.get(request_id, {})
	if not current is Dictionary or current.get("status") != "pending" or not Contract.text_id(current.get("slot_id")) or not Contract.text_id(current.get("actor_id")): return Contract.fail("NPC page request is no longer pending")
	var used := 0
	var slot: String = preload("res://scripts/core/npc_decision_opportunity.gd").slot_identity(current.slot_id)
	for record in state.npc_decision_records.values():
		if not record is Dictionary: return Contract.fail("invalid NPC page budget record")
		if record.get("actor_id") == current.actor_id:
			if not Contract.text_id(record.get("slot_id")) or not record.get("read_set") is Dictionary: return Contract.fail("invalid NPC page budget record")
			if preload("res://scripts/core/npc_decision_opportunity.gd").slot_identity(record.slot_id) != slot: continue
			var manifest: Variant = record.read_set.get("observer_pages", [])
			if not manifest is Array: return Contract.fail("invalid NPC page budget manifest")
			used += maxi(0, manifest.size() - 1)
	return Contract.fail("NPC opportunity page limit reached") if used >= Contract.MAX_CONTEXT_PAGES else {"ok": true, "remaining_pages": Contract.MAX_CONTEXT_PAGES - used}

func extend_page_scope(context, request_id: String, page: Dictionary) -> Dictionary:
	var checked := check_current(context, request_id)
	if not checked.ok: return checked
	var stored: Dictionary = context.state.npc_decision_records[request_id]
	var reader = load("res://scripts/core/npc_decision_read_set.gd")
	if stored.read_set.has("observer_pages") and reader.has_page(stored.read_set.observer_pages, page):
		var repeated: Dictionary = reader.fingerprint(context.state, context.scenario_data, stored.actor_id, stored.read_set.observer_pages, page)
		return {"ok": true, "code": "page_already_registered", "result_ref": request_id} if repeated.ok else repeated
	var budget := check_page_budget(context.state, request_id)
	if not budget.ok: return budget
	var domains := {"known_characters": "characters", "travel_destinations": "locations", "public_assets": "assets", "controlled_assets": "assets", "own_contracts": "contracts", "own_authorizations": "authorizations", "own_offices": "offices", "controlled_accounts": "accounts", "information_claims": "claims", "own_tasks": "tasks"}
	var path: Array = page.get("path", [])
	if path.is_empty(): return Contract.fail("missing NPC delivered page path")
	var domain: String = domains.get(path[0], "")
	var ids: Array = []
	if domain != "" and path.size() > 1 and path[1] is String:
		ids = [path[1]]
	elif domain != "" and path.size() == 1 and page.get("values") is Dictionary:
		ids = page.values.keys()
	elif path.size() == 1 and domain == "tasks" and page.get("values") is Array:
		for task in page.values:
			if task is Dictionary and task.has("task_id"): ids.append(task.task_id)
	return _transaction(context, {"execution_id": "page:" + request_id + ":" + str(page).sha256_text(), "ids": ids}, func(working):
		var recheck: Dictionary = check_current(working, request_id)
		if not recheck.ok: return recheck
		var remaining: Dictionary = check_page_budget(working.state, request_id)
		if not remaining.ok: return remaining
		var record: Dictionary = working.state.npc_decision_records[request_id]
		if not ids.is_empty() and not record.read_set.has(domain): record.read_set[domain] = []
		for id in ids:
			if not record.read_set[domain].has(id): record.read_set[domain].append(id)
		_append_visible_page_dependencies(page.get("values", {}), record.read_set)
		if record.read_set.has("observer_pages"):
			var reads = load("res://scripts/core/npc_decision_read_set.gd")
			var descriptor: Dictionary = reads.page_descriptor(page)
			if descriptor not in record.read_set.observer_pages: record.read_set.observer_pages.append(descriptor)
			var fingerprint: Dictionary = reads.fingerprint(working.state, working.scenario_data, record.actor_id, record.read_set.observer_pages, page)
			if not fingerprint.ok: return fingerprint
			record.read_fingerprint = fingerprint.hash
		return {"ok": true, "result_ref": request_id}
	)

static func _append_visible_page_dependencies(value: Variant, reads: Dictionary) -> void:
	if value is Dictionary:
		var domains := {"case_id": "cases", "office_id": "offices", "task_id": "tasks", "contract_id": "contracts", "agreement_id": "contracts", "account_id": "accounts", "destination_id": "locations"}
		for key in value:
			if key == "page_ref": continue
			if domains.has(key) and Contract.text_id(value[key]):
				var domain: String = domains[key]
				if not reads.has(domain): reads[domain] = []
				if not reads[domain].has(value[key]): reads[domain].append(value[key])
			_append_visible_page_dependencies(value[key], reads)
	elif value is Array:
		for item in value: _append_visible_page_dependencies(item, reads)

static func check_current(context, request_id: String) -> Dictionary:
	var record: Dictionary = context.state.npc_decision_records.get(request_id, {})
	if record.get("status") != "pending" or record.get("world_epoch") != context.world_epoch or record.get("policy_version") != context.state.npc_ai_runtime.policy_version or record.get("player_character_id") != context.state.player_character_id: return Contract.fail("NPC request belongs to a resolved slot, policy or old world")
	var fingerprint: Dictionary = Contract.fingerprint(context.state, record.read_set, context.scenario_data)
	if not fingerprint.ok or fingerprint.hash != record.read_fingerprint: return Contract.fail("NPC relevant read set changed; replan on current world")
	return {"ok": true}

static func check_object_scope(record: Dictionary, selection: Dictionary) -> Dictionary:
	var known: Array = [record.actor_id]
	var typed_reads: Dictionary = record.read_set.duplicate(true)
	if selection.kind == "plan" and selection.plan.has("task_id") and not record.read_set.get("tasks", []).has(selection.plan.task_id): return Contract.fail("NPC revision references an undiscovered task")
	var limits: Variant = selection.get("resource_limits", [])
	if not limits is Array: return Contract.fail("invalid NPC scoped resource limits")
	for limit in limits:
		if not limit is Dictionary or not Contract.text_id(limit.get("account_id")) or not record.read_set.get("accounts", []).has(limit.account_id): return Contract.fail("NPC plan references an undiscovered funding account")
	for field in record.read_set:
		if field != "observer_pages": known.append_array(record.read_set[field])
	var actions: Array = [selection.action] if selection.kind == "action" else selection.plan.get("steps", [])
	for action in actions:
		var typed_scope: Dictionary = load("res://scripts/core/game_action_catalog.gd").validate_scoped_parameters(action, typed_reads)
		if not typed_scope.ok: return typed_scope
		for ref in load("res://scripts/core/game_action_catalog.gd").produced_refs(action):
			if not Contract.text_id(ref): return Contract.fail("new process object requires a stable identity")
			if not known.has(ref): known.append(ref)
		for ref in action.target_refs:
			if not known.has(ref): return Contract.fail("NPC selection references an undiscovered target")
		var checked: Dictionary = check_parameter_refs(action.parameters, known)
		if not checked.ok: return checked
		# Only the existing creation rule declares the shop produced for later
		# steps. The authorization service still validates their dependencies.
		if action.action_kind == "rent_shop":
			if not typed_reads.has("assets"): typed_reads["assets"] = []
			if not typed_reads.assets.has(action.parameters.shop_id): typed_reads.assets.append(action.parameters.shop_id)
	return {"ok": true}

static func check_parameter_refs(params: Dictionary, known: Array) -> Dictionary:
	for key in params:
		if key in ["stall_id", "task_id", "loan_id", "buyer_id", "payee_account_id", "source_depot_id", "target_depot_id", "expected_authorization_id", "expected_manager_id"] and not known.has(params[key]): return Contract.fail("NPC selection references an undiscovered object at parameter " + str(key))
		if key in ["source_account_id", "destination_account_id", "funding_account_id", "item_id", "recipient_id", "candidate_id", "holder_id", "person_id", "teacher_id", "student_id", "borrower_id", "collateral_id", "office_id", "workshop_id", "shop_id", "land_id", "building_id", "school_id", "case_id", "agreement_id", "delivery_id", "destination_id", "location_id", "jurisdiction_office_id", "fact_id", "order_id", "journey_id", "match_id", "proposal_id", "assessment_id", "contract_id", "canal_id"] and not known.has(params[key]): return Contract.fail("NPC selection references an undiscovered object at parameter " + str(key))
		if params[key] is Dictionary:
			var nested: Dictionary = check_parameter_refs(params[key], known)
			if not nested.ok: return nested
		elif params[key] is Array:
			for item in params[key]:
				if key in ["candidate_ids", "participant_ids"] and not known.has(item): return Contract.fail("NPC array references an undiscovered person")
				if item is Dictionary:
					var nested: Dictionary = check_parameter_refs(item, known)
					if not nested.ok: return nested
	return {"ok": true}

static func _transaction(context, input: Dictionary, operation: Callable) -> Dictionary:
	var transaction = Transaction.new()
	var preview: Dictionary = transaction.preview_command(context.state, "npc_decision", input)
	if not preview.ok: return preview
	return transaction.execute_command(context, transaction.build_command_envelope("npc_decision", input, preview.preview_token), operation)
