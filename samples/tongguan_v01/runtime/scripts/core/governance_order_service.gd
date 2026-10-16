extends RefCounted

class_name GovernanceOrderService

const GovernanceOrderResolverScript = preload("res://scripts/core/governance_order_resolver.gd")
const GovernanceMemorialServiceScript = preload("res://scripts/core/governance_memorial_service.gd")
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const CashRules = preload("res://scripts/core/resource_rule_settlement.gd")
const CashContract = preload("res://scripts/core/management_state_contract.gd")

const REQUIRED_FIELDS := ["recipient_id", "action_id", "location_id", "resources", "authority_tags", "report_due_day"]
const STAGES := ["issued", "delivered", "acknowledged", "gathering", "executing", "closed"]
const MAX_EDICT_CHARS := 1200
const EXECUTION_HASH_FIELDS := [
	"council_id", "order_kind", "recipient_id", "assistant_ids", "action_id", "location_id", "resources", "authority_tags", "report_due_day",
	"required_office_id", "route_id", "drafted_by_office_id", "reviewed_by_office_id", "seal_status", "player_supplement",
	"edict_text", "edict_basis", "nominated_drafter_id", "revision"
]

func create_draft(state, fields: Dictionary) -> Dictionary:
	var validation := _validate_draft_fields(state, fields)
	if not bool(validation.get("ok", false)):
		return validation
	var order_id := "order_%06d" % int(state.governance_state.get("next_sequence", 1))
	state.governance_state["next_sequence"] = int(state.governance_state.get("next_sequence", 1)) + 1
	var draft := fields.duplicate(true)
	draft["order_id"] = order_id; draft["stage"] = "draft"; draft["seal_status"] = str(draft.get("seal_status", "ready")); draft["issued_day"] = int(draft.get("issued_day", state.current_day))
	state.governance_state["orders"][order_id] = draft
	return {"ok":true,"order_id":order_id,"order":draft.duplicate(true)}

func create_council_draft(state, council: Dictionary, fields: Dictionary) -> Dictionary:
	if state == null:
		return _fail("missing state", "missing_state")
	var council_id := str(council.get("council_id", "")).strip_edges()
	if council_id.is_empty():
		return _fail("council draft requires a council", "council_required")
	var stored_council := _stored_council(state, council_id)
	if stored_council.is_empty():
		return _fail("council is unavailable", "council_unavailable")
	if str(stored_council.get("status", "")) != "active" or str(stored_council.get("phase", "")) != "drafting":
		return _fail("council is not ready for drafting", "drafting_unavailable")
	if not str(stored_council.get("draft_order_id", "")).is_empty():
		return _fail("council already has a draft", "council_draft_exists")
	var drafter_id := str(stored_council.get("nominated_drafter_id", "")).strip_edges()
	if drafter_id.is_empty():
		return _fail("council draft requires a nominated drafter", "drafter_required")
	var included_basis: Array = (stored_council.get("included_clause_ids", []) as Array).duplicate(true)
	if included_basis.is_empty():
		return _fail("council draft requires an adopted basis", "basis_required")
	var draft_fields := fields.duplicate(true)
	draft_fields["council_id"] = council_id
	draft_fields["source_memorial_id"] = str(stored_council.get("memorial_id", ""))
	if str(draft_fields.get("source_memorial_id", "")).is_empty():
		return _fail("council draft requires a memorial", "council_memorial_required")
	draft_fields["nominated_drafter_id"] = drafter_id
	draft_fields["edict_basis"] = included_basis
	draft_fields["edict_text"] = stored_council.get("edict_text", "")
	draft_fields["revision"] = 0
	draft_fields["preview_token"] = ""
	var created := create_draft(state, draft_fields)
	if bool(created.get("ok", false)):
		_sync_council_draft_state(state, created.get("order", {}) as Dictionary)
	return created

func revise_council_draft(state, order_id: String, changes: Dictionary) -> Dictionary:
	var order := _draft(state, order_id)
	if order.is_empty() or str(order.get("council_id", "")).is_empty():
		return _fail("council draft is unavailable", "council_draft_unavailable")
	var revised := order.duplicate(true)
	for key in ["recipient_id", "action_id", "location_id", "resources", "authority_tags", "report_due_day", "edict_text"]:
		if changes.has(key):
			revised[key] = changes[key]
	var validation := _validate_draft_fields(state, revised)
	if not bool(validation.get("ok", false)):
		return validation
	revised["revision"] = int(order.get("revision", 0)) + 1
	revised["preview_token"] = ""
	state.governance_state["orders"][order_id] = revised
	_sync_council_draft_state(state, revised)
	return {"ok": true, "order": revised.duplicate(true)}

func preview_council_edict(state, order_id: String) -> Dictionary:
	var order := _draft(state, order_id)
	if order.is_empty() or str(order.get("council_id", "")).is_empty():
		return _fail("council draft is unavailable", "council_draft_unavailable")
	var validation := _validate_draft_fields(state, order)
	if not bool(validation.get("ok", false)):
		return validation
	var preview := preview_conflicts(state, order)
	if not bool(preview.get("can_seal", false)):
		return preview
	order["preview_token"] = _preview_token(order)
	state.governance_state["orders"][order_id] = order
	_sync_council_draft_state(state, order)
	preview["preview_token"] = str(order.get("preview_token", ""))
	preview["order_id"] = order_id
	preview["revision"] = int(order.get("revision", 0))
	return preview

func preview_direct_edict(state, order_id: String) -> Dictionary:
	var order := _draft(state, order_id)
	if order.is_empty() or not str(order.get("council_id", "")).is_empty(): return _fail("direct draft is unavailable", "direct_draft_unavailable")
	var validation := _validate_draft_fields(state, order)
	if not bool(validation.get("ok", false)): return validation
	var preview := preview_conflicts(state, order)
	if not bool(preview.get("can_seal", false)): return preview
	order["preview_token"] = _preview_token(order)
	state.governance_state["orders"][order_id] = order
	preview["preview_token"] = str(order.get("preview_token", ""))
	preview["order_id"] = order_id
	preview["revision"] = int(order.get("revision", 0))
	return preview

func preview_conflicts(state, draft: Dictionary) -> Dictionary:
	if state == null: return _fail("missing state", "missing_state")
	var conflicts: Array = []
	var execution_risks: Array = []
	var reservations: Dictionary = state.governance_state.get("reservations", {})
	var draft_resources: Variant = draft.get("resources", {})
	if draft_resources is Dictionary:
		for resource_key in (draft_resources as Dictionary).keys():
			var resource_name := str(resource_key).strip_edges()
			var requested := int((draft_resources as Dictionary).get(resource_key, 0))
			var available := CashRules.available(state, resource_name)
			if (reservations.get("resources", {}) as Dictionary).has(resource_key): conflicts.append({"kind":"resource","key":resource_name,"order_id":str((reservations.get("resources", {}) as Dictionary).get(resource_key))})
			if requested > available: execution_risks.append({"kind":"resource_shortage","key":resource_name,"required":requested,"available":available})
	for entry in [["characters","recipient_id"],["offices","required_office_id"],["routes","route_id"]]:
		var value := str(draft.get(str(entry[1]), "")); var bucket: Dictionary = reservations.get(str(entry[0]), {})
		if not value.is_empty() and bucket.has(value): conflicts.append({"kind":str(entry[0]).trim_suffix("s"),"key":value,"order_id":str(bucket.get(value))})
	return {"ok":true,"conflicts":conflicts,"execution_risks":execution_risks,"can_seal":true}

func seal_edict(state, order_id: String, preview_token: String = "") -> Dictionary:
	var plan := build_seal_plan(state, order_id, preview_token)
	if not bool(plan.get("ok", false)):
		return plan
	return apply_seal_plan(state, plan)

func build_seal_plan(state, order_id: String, preview_token: String = "") -> Dictionary:
	var order := _draft(state, order_id)
	if order.is_empty(): return _fail("order is unavailable", "order_unavailable")
	var council_id := str(order.get("council_id", ""))
	if not str(order.get("council_id", "")).is_empty():
		var stored_council := _stored_council(state, council_id)
		if stored_council.is_empty() or str(stored_council.get("status", "")) != "active" or str(stored_council.get("draft_order_id", "")) != order_id:
			return _fail("council draft is no longer linked", "council_draft_unlinked")
		var validation := _validate_draft_fields(state, order)
		if not bool(validation.get("ok", false)):
			return validation
		var expected_token := _preview_token(order)
		if preview_token.is_empty() or preview_token != expected_token or preview_token != str(order.get("preview_token", "")):
			return _fail("edict preview is stale", "stale_preview")
	if str(order.get("order_kind", "edict")) != "edict" or str(order.get("drafted_by_office_id", "")).is_empty() or str(order.get("reviewed_by_office_id", "")).is_empty() or str(order.get("seal_status", "")) != "ready": return _fail("edict is not ready", "edict_not_ready")
	var memorial_id := str(order.get("source_memorial_id", ""))
	if memorial_id.is_empty() or not state.governance_state.get("memorials", {}).has(memorial_id): return _fail("sealed order requires a memorial", "sealed_order_missing_memorial")
	if not council_id.is_empty() and str((_stored_council(state, council_id) as Dictionary).get("memorial_id", "")) != memorial_id: return _fail("council memorial is no longer linked", "council_memorial_unlinked")
	var preview := preview_conflicts(state, order)
	if not bool(preview.get("can_seal", false)): return _fail("command conflicts with reserved capacity", "command_conflict")
	return {"ok": true, "order": order.duplicate(true), "council_id": council_id, "memorial_id": memorial_id, "reservation": _reservation_projection(order), "receipt_report": _receipt_projection(state, order), "pause_reason": "governance_council"}

func build_oral_seal_plan(state, order_id: String, summary_hash: String) -> Dictionary:
	var order := _draft(state, order_id)
	if order.is_empty(): return _fail("order is unavailable", "order_unavailable")
	if JSON.stringify(_hash_fields(order)).sha256_text() != summary_hash: return _fail("oral restatement is stale", "stale_oral_restatement")
	var memorial_id := str(order.get("source_memorial_id", ""))
	if memorial_id.is_empty() or not state.governance_state.get("memorials", {}).has(memorial_id): return _fail("oral order requires a memorial", "sealed_order_missing_memorial")
	var preview := preview_conflicts(state, order)
	if not bool(preview.get("can_seal", false)): return _fail("command conflicts with reserved capacity", "command_conflict")
	order["order_kind"] = "oral"
	return {"ok": true, "order": order.duplicate(true), "council_id": str(order.get("council_id", "")), "memorial_id": memorial_id, "reservation": _reservation_projection(order), "receipt_report": _receipt_projection(state, order), "pause_reason": "governance_council"}

func apply_seal_plan(state, seal_plan: Dictionary, fault_injector: Callable = Callable()) -> Dictionary:
	return _atomic(state, func(): return _apply_seal_plan(state, seal_plan, fault_injector))

func _apply_seal_plan(state, seal_plan: Dictionary, fault_injector: Callable) -> Dictionary:
	if not bool(seal_plan.get("ok", false)):
		return _fail("seal plan is invalid", "invalid_seal_plan")
	var order: Dictionary = (seal_plan.get("order", {}) as Dictionary).duplicate(true)
	var order_id := str(order.get("order_id", ""))
	var issue_fault := _fault(fault_injector, "issue_order")
	if not bool(issue_fault.get("ok", false)): return issue_fault
	var reserve_fault := _fault(fault_injector, "reserve_resources")
	if not bool(reserve_fault.get("ok", false)): return reserve_fault
	var reserved := _reserve(state, order)
	if not reserved.get("ok", false): return reserved
	order["stage"] = "issued"; order["issued_day"] = int(state.current_day)
	state.governance_state["orders"][order_id] = order
	var report_fault := _fault(fault_injector, "append_report")
	if not bool(report_fault.get("ok", false)): return report_fault
	_report(state, order, "issued", "receipt")
	if not str(order.get("council_id", "")).is_empty(): _sync_council_draft_state(state, order)
	return {"ok":true,"order":order.duplicate(true)}

func prepare_oral_restatement(state, order_id: String) -> Dictionary:
	var order := _draft(state, order_id)
	if order.is_empty(): return _fail("order is unavailable", "order_unavailable")
	return {"ok":true,"order_id":order_id,"summary_hash":JSON.stringify(_hash_fields(order)).sha256_text(),"text":"受命人将按所列地点、资源与期限执行口谕。","fields":_hash_fields(order)}

func confirm_oral_order(state, order_id: String, summary_hash: String) -> Dictionary:
	return _atomic(state, func(): return _confirm_oral_order(state, order_id, summary_hash))

func _confirm_oral_order(state, order_id: String, summary_hash: String) -> Dictionary:
	var order := _draft(state, order_id); if order.is_empty(): return _fail("order is unavailable", "order_unavailable")
	if JSON.stringify(_hash_fields(order)).sha256_text() != summary_hash: return _fail("oral restatement is stale", "stale_oral_restatement")
	var preview := preview_conflicts(state, order); if not bool(preview.get("can_seal", false)): return _fail("command conflicts with reserved capacity", "command_conflict")
	var reserved := _reserve(state, order)
	if not reserved.get("ok", false): return reserved
	order["order_kind"] = "oral"; order["stage"] = "issued"; order["issued_day"] = int(state.current_day); state.governance_state["orders"][order_id] = order; _report(state, order, "issued")
	return {"ok":true,"order":order.duplicate(true)}

func withdraw(state, order_id: String) -> Dictionary:
	var order: Dictionary = state.governance_state.get("orders", {}).get(order_id, {}).duplicate(true)
	if order.is_empty(): return _fail("order is unavailable", "order_unavailable")
	if str(order.get("stage", "")) != "issued": return _fail("order already delivered", "order_already_delivered")
	_release(state, order); order["stage"] = "withdrawn"; state.governance_state["orders"][order_id] = order; _report(state, order, "withdrawn")
	return {"ok":true,"order":order.duplicate(true)}

func settle_daily(state, governance_data: Dictionary = {}) -> Dictionary:
	if state == null: return _fail("missing state", "missing_state")
	var order_ids: Array = state.governance_state.get("orders", {}).keys(); order_ids.sort()
	for order_id in order_ids:
		var order: Dictionary = state.governance_state["orders"][order_id].duplicate(true); var stage := str(order.get("stage", "")); var next := ""
		if stage in ["draft", "closed", "withdrawn"]:
			continue
		if not governance_data.is_empty() and stage in STAGES:
			var plan: Dictionary = GovernanceOrderResolverScript.new().plan_daily_transition(state.to_dictionary(), governance_data, order)
			if not bool(plan.get("ok", false)): return plan
			var applied := apply_resolution_plan(state, plan)
			if not bool(applied.get("ok", false)): return applied
			continue
		if stage == "issued" and int(state.current_day) >= int(order.get("issued_day", 0)) + 1: next = "delivered"
		elif stage == "delivered": next = "acknowledged"
		elif stage == "acknowledged": next = "gathering"
		elif stage == "gathering": next = "executing"
		elif stage == "executing" and int(state.current_day) >= int(order.get("report_due_day", 0)):
			var fallback_plan: Dictionary = GovernanceOrderResolverScript.new().plan_daily_transition(state.to_dictionary(), {}, order)
			if not bool(fallback_plan.get("ok", false)): return fallback_plan
			var fallback_applied := apply_resolution_plan(state, fallback_plan)
			if not bool(fallback_applied.get("ok", false)): return fallback_applied
			continue
		if not next.is_empty():
			order["stage"] = next; state.governance_state["orders"][order_id] = order; _report(state, order, next)
	return {"ok":true}

func apply_resolution_plan(state, plan: Dictionary) -> Dictionary:
	return _atomic(state, func(): return _apply_resolution_plan(state, plan))

func _apply_resolution_plan(state, plan: Dictionary) -> Dictionary:
	if state == null or not bool(plan.get("ok", false)):
		return _fail("resolution plan is invalid", "invalid_resolution_plan")
	var resolved: Dictionary = plan.get("order", {}) as Dictionary
	var order_id := str(resolved.get("order_id", ""))
	var stored: Dictionary = state.governance_state.get("orders", {}).get(order_id, {}) as Dictionary
	if order_id.is_empty() or stored.is_empty():
		return _fail("resolution order is unavailable", "resolution_order_unavailable")
	var before_stage := str(stored.get("stage", ""))
	var after_stage := str(resolved.get("stage", ""))
	if not _valid_stage_step(before_stage, after_stage):
		return _fail("resolution must advance one stage", "invalid_resolution_stage")
	var effects: Variant = plan.get("effects", {})
	if not (effects is Dictionary) or not _effects_are_whitelisted(effects as Dictionary):
		return _fail("resolution contains an unauthorized effect", "invalid_resolution_effect")
	var committed: Dictionary = resolved.duplicate(true)
	state.governance_state["orders"][order_id] = committed
	var memorial_id := str(committed.get("source_memorial_id", ""))
	if before_stage == "issued" and after_stage == "delivered" and not memorial_id.is_empty():
		var executing := GovernanceMemorialServiceScript.new().mark_executing(state, memorial_id)
		if not bool(executing.get("ok", false)): return executing
	var report_list: Variant = plan.get("reports", [])
	if report_list is Array:
		for report in report_list:
			if report is Dictionary:
				_append_report_descriptor(state, report as Dictionary)
	if after_stage == "closed":
		var paid := _apply_effects(state, committed, effects as Dictionary, plan.get("rule_trace", {}).get("resource_availability", {}))
		if not paid.get("ok", false): return paid
		if not memorial_id.is_empty():
			var closed := GovernanceMemorialServiceScript.new().close_order_chain(state, memorial_id, str(committed.get("outcome", "")), effects as Dictionary)
			if not bool(closed.get("ok", false)): return closed
		_release(state, committed)
	return {"ok": true, "order": committed.duplicate(true)}

func create_correction_draft(state, governance_data: Dictionary, parent_order_id: String, correction_kind: String, fields: Dictionary = {}) -> Dictionary:
	if state == null:
		return _fail("missing state", "missing_state")
	var orders: Dictionary = state.governance_state.get("orders", {})
	var parent: Dictionary = orders.get(parent_order_id, {}) as Dictionary
	if parent.is_empty():
		return _fail("parent order is unavailable", "parent_order_unavailable")
	if str(parent.get("condition", "")) not in ["delayed", "blocked", "lost_contact"]:
		return _fail("parent order cannot be corrected", "correction_unavailable")
	if correction_kind not in ["wait", "reassign", "supplement", "investigate"]:
		return _fail("correction kind is not allowed", "invalid_correction_kind")
	for raw_order in orders.values():
		if raw_order is Dictionary and str((raw_order as Dictionary).get("parent_order_id", "")) == parent_order_id and str((raw_order as Dictionary).get("correction_kind", "")) == correction_kind and str((raw_order as Dictionary).get("stage", "")) not in ["closed", "withdrawn"]:
			return _fail("correction kind is already active", "duplicate_active_correction")
	var child_fields: Dictionary = parent.duplicate(true)
	for key in fields.keys():
		child_fields[str(key)] = fields.get(key)
	child_fields.erase("order_id")
	child_fields.erase("stage")
	child_fields["parent_order_id"] = parent_order_id
	child_fields["correction_kind"] = correction_kind
	child_fields["condition"] = "normal"
	child_fields["outcome"] = ""
	child_fields["issued_day"] = int(state.current_day)
	child_fields["report_due_day"] = maxi(int(child_fields.get("report_due_day", state.current_day + 1)), int(state.current_day) + 1)
	var created := create_draft(state, child_fields)
	if not bool(created.get("ok", false)):
		return created
	var parent_copy := parent.duplicate(true)
	var correction_ids: Array = parent_copy.get("correction_ids", []).duplicate(true)
	correction_ids.append(str(created.get("order_id", "")))
	parent_copy["correction_ids"] = correction_ids
	orders[parent_order_id] = parent_copy
	state.governance_state["orders"] = orders
	return created

func _draft(state, order_id: String) -> Dictionary:
	if state == null: return {}
	var order: Dictionary = state.governance_state.get("orders", {}).get(order_id, {}).duplicate(true)
	return order if str(order.get("stage", "")) == "draft" else {}

func _stored_council(state, council_id: String) -> Dictionary:
	if state == null:
		return {}
	var council: Variant = state.governance_state.get("councils", {}).get(council_id, {})
	return (council as Dictionary).duplicate(true) if council is Dictionary else {}

func _validate_draft_fields(state, fields: Dictionary) -> Dictionary:
	if state == null:
		return _fail("missing state", "missing_state")
	for field in REQUIRED_FIELDS:
		if not fields.has(field) or _empty_value(fields.get(field)):
			return _fail("draft is missing " + field, "incomplete_draft")
	if str(fields.get("player_supplement", "")).length() > 240:
		return _fail("supplement is too long", "supplement_too_long")
	if int(fields.get("report_due_day", 0)) <= int(state.current_day):
		return _fail("report deadline is invalid", "invalid_deadline")
	if not state.character_states.has(str(fields.get("recipient_id", ""))):
		return _fail("recipient is unknown", "unknown_recipient")
	if not state.local_node_state.has(str(fields.get("location_id", ""))):
		return _fail("location is unknown", "unknown_location")
	var action_id := str(fields.get("action_id", "")).strip_edges()
	if action_id.is_empty():
		return _fail("action is not authorized", "unknown_action")
	var action_catalog: Variant = state.governance_state.get("action_catalog", {})
	if action_catalog is Dictionary and not (action_catalog as Dictionary).is_empty() and not (action_catalog as Dictionary).has(action_id):
		return _fail("action is not authorized", "unknown_action")
	var resources: Variant = fields.get("resources", {})
	if not resources is Dictionary or (resources as Dictionary).is_empty():
		return _fail("resources are invalid", "invalid_resources")
	for resource_key in (resources as Dictionary).keys():
		var resource_name := str(resource_key).strip_edges()
		var raw_amount: Variant = (resources as Dictionary).get(resource_key, 0)
		if resource_name.is_empty() or not state.resources.has(resource_name):
			return _fail("resource is unknown", "unknown_resource")
		if not CashContract.amount(raw_amount, true):
			return _fail("resource amount is invalid", "invalid_resource_amount")
	for authority_tag in fields.get("authority_tags", []):
		if not _has_authority(state, str(fields.get("recipient_id", "")), str(authority_tag), fields.get("assistant_ids", [])):
			return _fail("recipient lacks command authority", "missing_authority")
	if not str(fields.get("council_id", "")).is_empty():
		var edict_text_validation := _validate_edict_text(fields.get("edict_text", null))
		if not bool(edict_text_validation.get("ok", false)):
			return edict_text_validation
	return {"ok": true}

func _validate_edict_text(value: Variant) -> Dictionary:
	if not value is String:
		return _fail("edict text is invalid", "invalid_edict_text")
	var text := str(value).strip_edges()
	if text.is_empty() or text.length() > MAX_EDICT_CHARS:
		return _fail("edict text is invalid", "invalid_edict_text")
	return {"ok": true}

func _preview_token(order: Dictionary) -> String:
	return JSON.stringify({"order_id": str(order.get("order_id", "")), "revision": int(order.get("revision", 0)), "content": _hash_fields(order)}).sha256_text()

func _sync_council_draft_state(state, order: Dictionary) -> void:
	var council_id := str(order.get("council_id", ""))
	if council_id.is_empty():
		return
	var councils: Dictionary = state.governance_state.get("councils", {})
	if not councils.has(council_id) or not councils[council_id] is Dictionary:
		return
	var council: Dictionary = (councils[council_id] as Dictionary).duplicate(true)
	council["draft_order_id"] = str(order.get("order_id", ""))
	council["edict_text"] = str(order.get("edict_text", ""))
	council["revision"] = int(order.get("revision", 0))
	council["preview_token"] = str(order.get("preview_token", ""))
	councils[council_id] = council
	state.governance_state["councils"] = councils

func _reserve(state, order: Dictionary) -> Dictionary:
	var reservations: Dictionary = state.governance_state.get("reservations", {}).duplicate(true); var order_id := str(order.get("order_id", ""))
	if state.resource_accounts.has("court_treasury") and not state.resource_accounts.court_treasury.operator_refs.any(func(ref): return ref.entity_id == state.player_character_id):
		return _fail("当前身份无权签发国库政令", "public_account_authority_required")
	for key in (order.get("resources", {}) as Dictionary).keys():
		var account := CashRules.account_for(state, str(key))
		if not account.is_empty():
			var result := Accounts.new().apply(state, "reserve", {"execution_id": _cash_reservation_id(order_id, str(key)), "task_id": order_id, "account_id": account, "amount": order.resources[key], "actor_id": state.player_character_id})
			if not result.get("ok", false): return result
		else:
			reservations["resources"][key] = order_id
	for entry in [["characters","recipient_id"],["offices","required_office_id"],["routes","route_id"]]:
		var value := str(order.get(str(entry[1]), "")); if not value.is_empty(): reservations[str(entry[0])][value] = order_id
	state.governance_state["reservations"] = reservations
	return {"ok": true}

func _release(state, order: Dictionary) -> void:
	var reservations: Dictionary = state.governance_state.get("reservations", {}).duplicate(true); var order_id := str(order.get("order_id", ""))
	for key in order.get("resources", {}):
		var held: Dictionary = state.resource_reservations.get(_cash_reservation_id(order_id, str(key)), {})
		if not held.is_empty() and held.get("task_id") == order_id and held.get("status") == "active":
			held.remaining_amount = 0
			held.status = "released"
	for bucket in reservations.values():
		if bucket is Dictionary:
			for key in (bucket as Dictionary).keys(): if str((bucket as Dictionary).get(key)) == order_id: (bucket as Dictionary).erase(key)
	state.governance_state["reservations"] = reservations

func _report(state, order: Dictionary, status: String, kind: String = "progress") -> void:
	var report_id := "report_%06d" % int(state.governance_state.get("next_sequence", 1)); state.governance_state["next_sequence"] = int(state.governance_state.get("next_sequence", 1)) + 1
	var labels := {"issued":"已发出","delivered":"已抵达","acknowledged":"已回执","gathering":"已进入材料收集","executing":"执行中","closed":"已结案","withdrawn":"已撤回"}
	state.governance_state["reports"].append({
		"report_id":report_id,
		"order_id":str(order.get("order_id", "")),
		"status":status,
		"kind":kind,
		"day":int(state.current_day),
		"title":"政令%s" % str(labels.get(status, "状态更新")),
		"summary":"第%d日，政令%s；等待具体执行结果。" % [int(state.current_day), str(labels.get(status, "状态更新"))],
		"source_label":"行在传令",
		"confidence":0.75,
		"related_character_ids":[str(order.get("recipient_id", ""))],
		"related_location_ids":[str(order.get("location_id", ""))],
		"execution_details":_report_execution_details(order, status)
	})

func _append_report_descriptor(state, descriptor: Dictionary) -> void:
	var report := descriptor.duplicate(true)
	if str(report.get("report_id", "")).is_empty():
		report["report_id"] = "report_%06d" % int(state.governance_state.get("next_sequence", 1))
	state.governance_state["next_sequence"] = int(state.governance_state.get("next_sequence", 1)) + 1
	report["day"] = int(report.get("created_day", state.current_day))
	state.governance_state["reports"].append(report)

func _report_execution_details(order: Dictionary, status: String) -> Dictionary:
	var resources_value: Variant = order.get("resources", {})
	var requested_resources: Dictionary = resources_value.duplicate(true) if resources_value is Dictionary else {}
	var result := str(order.get("outcome", "")) if status == "closed" else ""
	var next_step := "政令已撤回，未进入执行" if status == "withdrawn" else "等待下一阶段回报"
	if status == "closed":
		next_step = "进入后续复盘"
	return {
		"stage": status,
		"condition": str(order.get("condition", "normal")),
		"action_id": str(order.get("action_id", "")),
		"recipient_id": str(order.get("recipient_id", "")),
		"location_id": str(order.get("location_id", "")),
		"requested_resources": requested_resources,
		"available_resources": {},
		"usable_resources": {},
		"resource_status": "",
		"result": result,
		"next_action_ids": [],
		"next_step": next_step,
		"applied_effects": {}
	}

func _valid_stage_step(before_stage: String, after_stage: String) -> bool:
	if before_stage == after_stage:
		return before_stage == "executing"
	if before_stage == "executing":
		return after_stage == "closed"
	return str({"issued":"delivered", "delivered":"acknowledged", "acknowledged":"gathering", "gathering":"executing"}.get(before_stage, "")) == after_stage

func _effects_are_whitelisted(effects: Dictionary) -> bool:
	for key in effects.keys():
		if str(key) not in ["resource_delta", "relationship_delta", "strategy_route_delta", "faction_delta", "resolution_path", "memory", "location_update"]:
			return false
	return true

func _apply_effects(state, order: Dictionary, effects: Dictionary, availability: Dictionary = {}) -> Dictionary:
	# Costs precede rewards: an outcome must not finance its own unpaid inputs.
	var paid := _apply_outcome(state, order, availability)
	if not paid.get("ok", false): return paid
	if effects.has("resource_delta") and effects["resource_delta"] is Dictionary:
		for key in (effects["resource_delta"] as Dictionary).keys():
			var raw: Variant = effects.resource_delta[key]
			if typeof(raw) not in [TYPE_INT, TYPE_FLOAT] or not CashContract.amount(absf(float(raw))):
				return _fail("政令规则收支金额无效", "invalid_effect_amount")
			var settled := CashRules.apply(state, str(key), int(raw), "rule:governance_effect:" + str(order.order_id), "governance-effect:" + str(order.order_id) + ":" + str(key))
			if not settled.get("ok", false): return settled
	return {"ok": true}

func _reservation_projection(order: Dictionary) -> Dictionary:
	return {"resources": (order.get("resources", {}) as Dictionary).duplicate(true), "recipient_id": str(order.get("recipient_id", "")), "required_office_id": str(order.get("required_office_id", "")), "route_id": str(order.get("route_id", ""))}

func _receipt_projection(state, order: Dictionary) -> Dictionary:
	return {"kind": "receipt", "order_id": str(order.get("order_id", "")), "day": int(state.current_day)}

func _fault(injector: Callable, stage: String) -> Dictionary:
	if not injector.is_valid(): return {"ok": true}
	var result: Variant = injector.call(stage)
	return result as Dictionary if result is Dictionary else {"ok": false, "code": "invalid_seal_fault_injector"}

func _hash_fields(order: Dictionary) -> Dictionary:
	var result: Dictionary = {}; for key in EXECUTION_HASH_FIELDS: result[key] = order.get(key)
	return result

func _has_authority(state, recipient_id: String, authority_tag: String, assistants: Array) -> bool:
	if authority_tag == "execute":
		return true
	for office in state.office_state.values():
		if not (office is Dictionary):
			continue
		if str((office as Dictionary).get("holder_id", "")) in [recipient_id] + assistants and ((office as Dictionary).get("authority_tags", []) as Array).has(authority_tag):
			return true
	return false

func _apply_outcome(state, order: Dictionary, availability: Dictionary = {}) -> Dictionary:
	for resource_key in (order.get("resources", {}) as Dictionary).keys():
		var required := int(order.resources[resource_key])
		var used := int(availability.get(resource_key, {}).get("usable", required))
		if used < 0 or used > required: return _fail("政令实际支出超出原请求", "invalid_order_consumption")
		var account := CashRules.account_for(state, str(resource_key))
		if not account.is_empty() and used > 0:
			var paid := Accounts.new().apply(state, "consume", {"execution_id": "governance-payment:" + str(order.order_id) + ":" + str(resource_key), "actor_id": state.resource_accounts[account].operator_refs[0].entity_id, "account_id": account, "amount": used, "reason_ref": "rule:governance_order:" + str(order.order_id), "task_id": order.order_id, "reservation_id": _cash_reservation_id(str(order.order_id), str(resource_key))})
			if not paid.get("ok", false): return paid
		elif account.is_empty():
			state.resources[resource_key] = maxi(int(state.resources.get(resource_key, 0)) - used, 0)
	var recipient_id := str(order.get("recipient_id", ""))
	if state.character_states.has(recipient_id):
		var recipient: Dictionary = state.character_states[recipient_id].duplicate(true)
		var relationships: Dictionary = recipient.get("relationships", {}).duplicate(true)
		relationships["li_heng"] = clampi(int(relationships.get("li_heng", 0)) + 3, -100, 100)
		recipient["relationships"] = relationships
		state.character_states[recipient_id] = recipient
	state.structured_memories.append({"memory_type":"governance_order_outcome","order_id":str(order.get("order_id", "")),"recipient_id":recipient_id,"action_id":str(order.get("action_id", "")),"day":int(state.current_day)})
	var location_id := str(order.get("location_id", ""))
	if state.local_node_state.has(location_id):
		var node: Dictionary = state.local_node_state[location_id].duplicate(true)
		node["last_governance_order_id"] = str(order.get("order_id", ""))
		state.local_node_state[location_id] = node
	return {"ok": true}

static func _cash_reservation_id(order_id: String, resource: String) -> String:
	return "governance:" + order_id + ":" + resource

func _atomic(state, operation: Callable) -> Dictionary:
	if state == null: return _fail("missing state", "missing_state")
	# The coordinator owns the outer shared transaction; keep direct calls atomic too.
	var snapshot: Dictionary = state.to_transaction_dictionary()
	var result: Dictionary = operation.call()
	if not result.get("ok", false) and state.to_transaction_dictionary() != snapshot:
		var restored: Dictionary = state.load_transaction_dictionary(snapshot)
		if not restored.get("ok", false): return _fail("政令回滚失败：" + str(restored), "rollback_failed")
	return result

func _empty_value(value: Variant) -> bool:
	return value == null or (value is String and str(value).is_empty()) or (value is Array and (value as Array).is_empty()) or (value is Dictionary and (value as Dictionary).is_empty())

func _fail(message: String, code: String) -> Dictionary:
	return {"ok":false,"code":code,"error":message}
