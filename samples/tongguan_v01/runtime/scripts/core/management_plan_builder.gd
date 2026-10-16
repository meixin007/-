extends RefCounted
const Contract = preload("res://scripts/core/management_state_contract.gd")
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Family = preload("res://scripts/core/family_office_rules.gd")

# Pure proposal: opening a page or asking advice never reserves or spends money.
static func startup(state, data: Dictionary, building_id: String, capital: int, candidate_id: String, alternative_ids: Array = []) -> Dictionary:
	if capital <= 0 or capital > Contract.MAX_AMOUNT:
		return Contract.fail("请给出有效的营运资金目标")
	var organization := str(state.flags.get("player_organization_id", ""))
	var offices: Array = state.office_state.values().filter(func(o): return o.get("office_kind") == "family" and o.get("organization_id") == organization and o.get("role_key") == "shopkeeper")
	if offices.size() != 1:
		return Contract.fail("尚无本家的掌柜职位，需先明确经营组织")
	var office: Dictionary = offices[0]
	var building: Dictionary = state.management_assets.get(building_id, {})
	if building.get("asset_kind") != "building":
		return Contract.fail("未找到实际铺面")
	var executor := str(state.player_assistant_assignment.get("assistant_id", ""))
	if state.player_assistant_assignment.get("status") != "active" or executor.is_empty():
		return Contract.fail("当前没有可接手的助手，可先任用或亲自办理")
	var shop_id := "pawnshop:%s:%s" % [organization, building_id]
	for task in state.active_tasks:
		if task.get("task_kind") == "management" and task.get("principal_id") == state.player_character_id and task.get("steps", []).any(func(step): return step.get("parameters", {}).get("building_id") == building_id or step.get("parameters", {}).get("shop_id") == shop_id):
			return Contract.fail("已有同一铺面的筹办任务，请查看进度或调整原授权")
	var existing: Array = state.management_assets.values().filter(func(a): return a.get("asset_kind") == "pawnshop" and a.get("building_id") == building_id and a.get("owner_ref", {}).get("entity_id") == organization)
	var shop: Dictionary = existing[0] if not existing.is_empty() else {}
	if not shop.is_empty():
		shop_id = shop.asset_id
	var funding: String = office.remuneration_terms.account_id
	var steps: Array = []
	var budget := 0
	if shop.is_empty():
		if building.status != "available":
			return Contract.fail("铺面已被他人租用")
		_add(steps, "rent", "rent_shop", building_id, {"building_id": building_id, "shop_id": shop_id, "funding_account_id": funding, "office_id": office.office_id})
		budget += int(building.rental_offer.amount)
	if str(office.holder_id).is_empty():
		var candidate := Family.assess(state, data, office.office_id, candidate_id)
		if candidate.get("grade") != "eligible":
			return Contract.fail(str(candidate.get("reason", "候选尚未同意")))
		if alternative_ids.is_empty():
			_add(steps, "hire", "hire_family", office.office_id, {"office_id": office.office_id, "candidate_id": candidate_id})
		else:
			var pool: Array = [candidate_id]
			for id in alternative_ids:
				if pool.has(id): continue
				if Family.assess(state, data, office.office_id, str(id)).get("grade") != "eligible": return Contract.fail("备选人物当前不符合所列聘用条件")
				pool.append(id)
			_add(steps, "hire", "hire_family_from_pool", office.office_id, {"office_id": office.office_id, "candidate_ids": pool, "wage_amount": int(office.remuneration_terms.amount), "period_days": int(office.remuneration_terms.period_days)})
			steps.back().target_refs.append_array(pool)
		budget += int(office.remuneration_terms.amount)
	if shop.get("setup_contract_id", "") == "":
		_add(steps, "prepare", "prepare_pawnshop", shop_id, {"shop_id": shop_id, "funding_account_id": funding})
		budget += int(building.setup_offer.amount)
	var needed: int = maxi(0, capital - (Accounts.new().balance(state, shop.account_id) if not shop.is_empty() else 0))
	if needed > 0:
		_add(steps, "capital", "fund_pawnshop", shop_id, {"shop_id": shop_id, "funding_account_id": funding, "amount": needed})
		budget += needed
	if shop.get("status") != "open":
		_add(steps, "open", "open_pawnshop", shop_id, {"shop_id": shop_id})
	if steps.is_empty():
		return Contract.fail("当铺已经达到指定开业与资金目标，无需重复办理")
	var id := "startup:%s:%d" % [shop_id, int(state.state_revision)]
	var kinds: Array = []
	var targets: Array = []
	for step in steps:
		if not kinds.has(step.action_kind):
			kinds.append(step.action_kind)
		for target in step.target_refs:
			if not targets.has(target):
				targets.append(target)
	var limits: Array = [{"account_id": funding, "amount": budget, "unit_id": "cash_unit"}] if budget > 0 else []
	var auth := {"authorization_id": "auth:" + id, "principal_id": state.player_character_id, "delegate_id": executor, "scope": {"action_kinds": kinds, "target_refs": targets, "allow_subdelegation": true}, "resource_limits": limits, "version": 1, "status": "active", "valid_until_day": null}
	var plan := {"task_id": "task:" + id, "name": "筹办" + str(building.name) + "当铺", "executor_id": executor, "steps": steps}
	var summary := "交由%s办理 %d 项事务；预留本家资金 %d，其中营运资金 %d。租金、工资与整理款依实际步骤支付。" % [str(state.character_states[executor].name), steps.size(), budget, needed]
	for step in steps:
		if step.action_kind == "hire_family_from_pool":
			var names: Array[String] = []
			for person in step.parameters.candidate_ids: names.append(str(state.character_states[person].name))
			summary += "\n掌柜依次选择：%s；每 %d 日 %d。首选无法受聘时在此名单内改选；全部不可用或工资改变时停下商议。" % ["、".join(names), int(step.parameters.period_days), int(step.parameters.wage_amount)]
		elif step.action_kind == "hire_family": summary += "\n掌柜仅聘%s；无法受聘时停下商议。" % str(state.character_states[candidate_id].name)
	return {"ok": true, "authorization": auth, "plan": plan, "execution_id": "agree:" + id, "summary": summary}

static func _add(steps: Array, id: String, kind: String, target: String, params: Dictionary) -> void:
	var dependencies: Array = []
	if not steps.is_empty():
		dependencies.append(steps.back().step_id)
	if steps.any(func(step): return step.step_id == "rent") and not dependencies.has("rent"):
		dependencies.append("rent")
	steps.append({"step_id": id, "action_kind": kind, "target_refs": [target], "parameters": params, "depends_on": dependencies})
