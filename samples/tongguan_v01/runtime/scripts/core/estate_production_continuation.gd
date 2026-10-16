extends RefCounted
# A bounded continuation of an existing signed private production mandate.
# This record neither replaces the task queue nor grants account operators.
const Canonical = preload("res://scripts/core/canonical_json.gd")
const Production = preload("res://scripts/core/production_service.gd")
const Rules = preload("res://scripts/core/management_state_contract.gd")

static func authority_terms(auth: Dictionary) -> Dictionary:
	var result := auth.duplicate(true)
	result.erase("status")
	return result

static func task_terms(task: Dictionary) -> Dictionary:
	var result := {}
	for key in ["task_id", "principal_id", "executor_id", "authorization_id", "plan_revision", "authorization_version", "parent_task_id", "delegation_chain"]: result[key] = task.get(key)
	result["steps"] = []
	for step in task.get("steps", []):
		var terms: Dictionary = step.duplicate(true)
		terms.erase("status"); terms.erase("receipt_ref")
		result.steps.append(terms)
	return result

static func same(left: Variant, right: Variant) -> bool:
	var first := Canonical.hash_value(left)
	var second := Canonical.hash_value(right)
	return first.get("ok", false) and second.get("ok", false) and first.hash == second.hash

static func capture(state, rule: Dictionary) -> Dictionary:
	var result := {}
	if not rule.get("continue_private_production", false): return result
	for task in state.active_tasks:
		if task.get("task_kind") != "management" or task.get("principal_id") != rule.owner_id or task.get("status") not in ["reserved", "running"] or task.get("parent_task_id", "") != "" or task.get("executor_id") == rule.owner_id: continue
		var auth: Dictionary = state.action_authorizations.get(task.get("authorization_id"), {})
		if auth.get("status") != "active" or auth.get("root_task_id") != task.task_id or auth.get("delegate_ids", []).size() != 1 or auth.get("consent_source", {}).get("kind") != "private_dialogue": continue
		if not task.steps.all(func(step): return step.get("action_kind") in Production.KINDS): continue
		if not auth.resource_limits.all(func(limit): return limit.account_id == rule.account_id): continue
		var pending: Array = []
		for step in task.steps:
			if step.status != "completed": pending.append(step.execution_id)
		result[task.task_id] = {"authority": authority_terms(auth), "task": task_terms(task), "pending_execution_ids": pending}
	return result

static func task_for(state, id: String) -> Dictionary:
	for task in state.active_tasks + state.completed_tasks:
		if task.get("task_kind") == "management" and task.get("task_id") == id: return task
	return {}

static func estate_for(state, task_id: String) -> Dictionary:
	if task_id.is_empty(): return {}
	var task := task_for(state, task_id)
	if task.is_empty(): return {}
	for estate in state.economic_contracts.values():
		var saved: Dictionary = estate.get("production_continuations", {}).get(task_id, {})
		if saved.is_empty(): continue
		var auth: Dictionary = state.action_authorizations.get(task.authorization_id, {})
		if state.character_states.get(estate.get("owner_id"), {}).get("status") == "dead" and same(saved.get("task"), task_terms(task)) and same(saved.get("authority"), authority_terms(auth)): return estate
	return {}

static func proof(state, request: Dictionary) -> Dictionary:
	var id := str(request.get("task_id", ""))
	var estate := estate_for(state, id)
	if estate.get("status") != "pending": return {}
	var task := task_for(state, id)
	var auth: Dictionary = state.action_authorizations[task.authorization_id]
	if auth.get("status") != "active" or task.get("status") not in ["reserved", "running"] or request.get("actor_id") != task.executor_id or request.get("principal_id") != task.principal_id or request.get("executor_id") != task.executor_id or request.get("authorization_id") != task.authorization_id: return {}
	if auth.valid_until_day != null and int(state.current_day) > int(auth.valid_until_day): return {}
	for step in task.steps:
		if step.execution_id == request.get("execution_id") and step.status == "planned" and same(step.parameters, request.get("parameters")) and same(step.target_refs, request.get("target_refs")) and step.action_kind == request.get("action_kind") and step.step_id == request.get("step_id") and estate.production_continuations[id].pending_execution_ids.has(step.execution_id):
			return {"estate_id": estate.contract_id, "task_id": id, "death_receipt": estate.death_receipt}
	return {}

static func permits_resource(state, action: String, request: Dictionary) -> bool:
	var task_id := str(request.get("estate_task_id", ""))
	var estate := estate_for(state, task_id)
	if estate.get("status") != "pending": return false
	var task := task_for(state, task_id)
	var auth: Dictionary = state.action_authorizations[task.authorization_id]
	if request.get("actor_id") != task.executor_id or not Production.present(state, task.executor_id, estate.location_id) or request.get("reservation_id") != auth.reservation_refs.get(estate.account_id): return false
	if action == "release": return task.steps.all(func(step): return step.status == "completed")
	if action != "transfer" or estate.get("processing_task") != task_id or request.get("source_account_id") != estate.account_id or state.resource_journal.has(request.get("execution_id")): return false
	for step in task.steps:
		if step.action_kind != "commission_production" or step.status != "planned" or step.execution_id != request.get("execution_id"): continue
		var envelope := {"actor_id": task.executor_id, "principal_id": task.principal_id, "executor_id": task.executor_id, "task_id": task_id, "authorization_id": task.authorization_id, "step_id": step.step_id, "execution_id": step.execution_id, "action_kind": step.action_kind, "parameters": step.parameters, "target_refs": step.target_refs}
		var workshop: Dictionary = state.management_assets.get(step.parameters.get("workshop_id"), {})
		return not proof(state, envelope).is_empty() and step.parameters.get("funding_account_id") == estate.account_id and request.get("destination_account_id") == workshop.get("payee_account_id") and request.get("amount") == workshop.get("recipes", {}).get(step.parameters.get("recipe_id"), {}).get("price") and request.get("reason_ref") == step.parameters.get("order_id")
	return false

static func custody_valid(raw: Dictionary, item: Dictionary) -> bool:
	var order: Dictionary = raw.economic_contracts.get(item.get("source_ref", {}).get("entity_id"), {})
	var custody: Dictionary = order.get("estate_custody", {})
	var estate: Dictionary = raw.economic_contracts.get(custody.get("estate_id"), {})
	var receipt: Dictionary = raw.action_receipts.get(order.get("collection_receipt"), {})
	return not custody.is_empty() and estate.get("status") == "pending" and estate.get("owner_id") == order.get("customer_id") and item.get("owner_ref") == {"entity_kind": "character", "entity_id": estate.get("owner_id")} and item.get("custodian_ref") == {"entity_kind": "character", "entity_id": estate.get("executor_id")} and custody.get("custodian_id") == estate.get("executor_id") and custody.get("execution_id") == order.get("collection_receipt") and receipt.get("estate_continuation", receipt.get("estate_collection", {})).get("estate_id") == estate.get("contract_id")

static func validate(raw: Dictionary, rule: Dictionary, estate: Dictionary, death: Dictionary) -> Dictionary:
	var records: Variant = estate.get("production_continuations", {})
	if estate.has("processing_task"): return Rules.fail("不能保存尚未原子完成的原委托支出")
	if not records is Dictionary or not same(records, death.get("estate_continuations", {})): return Rules.fail("遗产原委托承继与死亡登记回执不符")
	if not records.is_empty() and not rule.get("continue_private_production", false): return Rules.fail("缺少原委托延续安排")
	for id in records:
		var saved: Variant = records[id]
		var task := task_for(raw, id)
		if not saved is Dictionary or saved.size() != 3 or task.is_empty() or not saved.get("pending_execution_ids") is Array or not same(saved.get("task"), task_terms(task)) or not same(saved.get("authority"), authority_terms(raw.action_authorizations.get(task.get("authorization_id"), {}))): return Rules.fail("不能改写死者原授权、预算、执行人或步骤")
		if task.principal_id != rule.owner_id or task.executor_id == rule.owner_id or not task.steps.all(func(step): return step.action_kind in Production.KINDS): return Rules.fail("承继只能处理所列原私人生产委托")
		for execution in saved.pending_execution_ids:
			if not task.steps.any(func(step): return step.execution_id == execution): return Rules.fail("承继引用缺失原步骤")
			var receipt: Dictionary = raw.action_receipts.get(execution, {})
			if not receipt.is_empty() and (receipt.get("estate_continuation") != {"estate_id": rule.estate_id, "task_id": id, "death_receipt": estate.death_receipt} or receipt.get("executor_id") != task.executor_id or int(receipt.get("day", -1)) < int(estate.created_day)): return Rules.fail("承继步骤缺少实际执行人与回执")
	return {"ok": true}
