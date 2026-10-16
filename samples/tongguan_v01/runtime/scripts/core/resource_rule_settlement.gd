extends RefCounted
const Storage = preload("res://scripts/core/resource_storage_adapter.gd")
const Contract = preload("res://scripts/core/management_state_contract.gd")

# Internal configured-rule effects, not an action exposed to model plans.
static func apply(state, resource: String, delta: int, rule: String, execution_id: String = "") -> Dictionary:
	var account_id := account_for(state, resource)
	if account_id.is_empty():
		if state.flags.get("campaign_id") == "anshi_beta_1_14" and resource in ["silver", "treasury"]:
			return Contract.fail("当前版本现金账户缺失，不能回退为独立余额")
		state.resources[resource] = int(state.resources.get(resource, 0)) + delta
		return {"ok": true}
	if delta == 0: return {"ok": true, "code": "no_op"}
	if not Contract.amount(absi(delta), true) or not rule.begins_with("rule:") or rule.length() <= 5:
		return Contract.fail("现金变化缺少有界金额或具体规则依据")
	var sequence := int(state.flags.get("cash_rule_sequence", 0)) + 1
	var execution := execution_id if not execution_id.is_empty() else "cash-rule:%d:%d" % [int(state.current_day), sequence]
	var account: Dictionary = state.resource_accounts[account_id]
	if account.operator_refs.is_empty(): return Contract.fail("账户没有可核验的经办权源")
	if state.resource_journal.has(execution):
		var old: Dictionary = state.resource_journal[execution]
		if old.get("entry_kind") == ("rule_income" if delta > 0 else "rule_consumption") and old.get("reason_ref") == rule and old.get("amount") == absi(delta) and old.get("destination_account_id" if delta > 0 else "source_account_id") == account_id:
			return {"ok": true, "code": "idempotent_replay", "result_ref": execution}
		return Contract.fail("规则执行标识不能改写已入账收支")
	if delta < 0:
		var result: Dictionary = load("res://scripts/core/resource_account_service.gd").new().apply(state, "consume", {"execution_id": execution, "account_id": account_id, "amount": -delta, "actor_id": account.operator_refs[0].entity_id, "reason_ref": rule})
		if not result.get("ok", false): return result
	else:
		var value := Storage.balance(state, account.storage_ref)
		if value < 0 or value > Contract.MAX_AMOUNT - delta: return Contract.fail("规则收入超过账户范围")
		Storage.write_balance(state, account.storage_ref, value + delta)
		state.resource_journal[execution] = {"entry_id": execution, "execution_id": execution, "entry_kind": "rule_income", "source_ref": {"entity_kind": "rule", "entity_id": rule, "rule_id": rule}, "destination_account_id": account_id, "destination_ref": account.owner_ref.duplicate(true), "amount": delta, "unit_id": account.unit_id, "reason_ref": rule, "day": int(state.current_day)}
	if execution_id.is_empty(): state.flags["cash_rule_sequence"] = sequence
	return {"ok": true, "result_ref": execution}

static func account_for(state, resource: String) -> String:
	if resource == "silver": return Storage.personal_account(state, state.player_character_id)
	if resource == "treasury" and state.resource_accounts.has("court_treasury"): return "court_treasury"
	return ""

static func available(state, resource: String) -> int:
	var account := account_for(state, resource)
	if account.is_empty() and state.flags.get("campaign_id") == "anshi_beta_1_14" and resource in ["silver", "treasury"]: return -1
	return int(state.resources.get(resource, 0)) if account.is_empty() else int(load("res://scripts/core/resource_account_service.gd").new().available(state, account))
