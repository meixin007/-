extends RefCounted
const Rules = preload("res://scripts/core/management_state_contract.gd")
const Production = preload("res://scripts/core/production_service.gd")
const Workload = preload("res://scripts/core/character_workload_service.gd")

static func active_collector(state, order_id: String) -> bool:
	return state.active_tasks.any(func(task): return task.get("status") not in ["cancelled", "completed", "failed"] and task.get("steps", []).any(func(step): return step.get("action_kind") == "collect_production" and step.get("parameters", {}).get("order_id") == order_id and step.get("status") != "completed"))

static func assess(state, rule: Dictionary, order_id: String) -> Dictionary:
	var estate: Dictionary = state.economic_contracts.get(rule.estate_id, {})
	var order: Dictionary = state.economic_contracts.get(order_id, {})
	if not rule.get("collect_paid_production", false) or estate.get("status") != "pending" or state.character_states[rule.owner_id].get("status") != "dead": return Rules.fail("没有原受托人接收已付款订单的遗产安排")
	if order.get("contract_kind") != "production" or order.get("customer_id") != rule.owner_id: return Rules.fail("不是死者实际已付款的原生产合同")
	if active_collector(state, order_id): return Rules.fail("原委托仍负责接货，不能越过原任务重复办理")
	if order.status == "working": return Rules.fail("原工坊尚未完成；已付款与实际材料保留等待交付")
	if order.status != "ready": return Rules.fail("原生产订单已经接收或不在可交付状态")
	var item: Dictionary = state.management_assets.get(order.output_id, {})
	if item.get("location_id") != rule.location_id or not Production.present(state, order.supplier_id, rule.location_id): return Rules.fail("原产物或实际保管人未到遗产交割地")
	if not rule.get("executor_willing", false) or not Production.present(state, rule.executor_id, rule.location_id): return Rules.fail("原遗产经办人尚未同意或未实际到场")
	if Workload.occupied_today(state, rule.executor_id, "", rule.executor_id): return Rules.fail("遗产经办人今日已有实际职责或事务，原订单继续保留")
	return {"ok": true}

static func collect(state, rule: Dictionary, order_id: String, principal: String, execution: String) -> Dictionary:
	if principal != rule.executor_id: return Rules.fail("只有原实际受托人可以接管死者的已付款订单")
	var ready := assess(state, rule, order_id)
	if not ready.ok: return ready
	var collected := Production.apply(state, "collect_production", {"order_id": order_id}, rule.owner_id, execution, "", {"estate_id": rule.estate_id})
	if not collected.ok: return collected
	var estate: Dictionary = state.economic_contracts[rule.estate_id]
	if not estate.has("collected_orders"): estate["collected_orders"] = {}
	estate.collected_orders[order_id] = execution
	return {"ok": true, "result_ref": order_id, "estate_collection": {"estate_id": rule.estate_id, "order_id": order_id, "commission_receipt": state.economic_contracts[order_id].commission_receipt}, "visible_summary": "已依原付款合同现场接管实际产物；原买方及遗产所有权保留，尚未分配。"}

static func orders_for(state, rule: Dictionary) -> Array:
	var result: Array = []
	for order in state.economic_contracts.values():
		if order.get("contract_kind") == "production" and order.get("customer_id") == rule.owner_id and (order.status != "delivered" or order.get("estate_custody", {}).get("estate_id") == rule.estate_id): result.append(order)
	result.sort_custom(func(a, b): return str(a.contract_id) < str(b.contract_id))
	return result

static func project(state, rule: Dictionary, viewer: String) -> Array:
	var result: Array = []
	for order in orders_for(state, rule):
		if active_collector(state, order.contract_id): continue
		var ready := assess(state, rule, order.contract_id)
		var payment: Dictionary = state.resource_journal[order.commission_receipt]
		result.append({"order_id": order.contract_id, "name": order.recipe.output_definition.name, "paid": payment.amount, "supplier_name": state.character_states[order.supplier_id].name, "status": order.status, "can_collect": ready.ok and viewer == rule.executor_id, "reason": "可由原受托人现场接管，沿用原付款，不再付价。" if ready.ok else ("已实际接管，原付款合同保留。" if order.status == "delivered" else ready.error)})
	return result

static func validate(raw: Dictionary, rule: Dictionary, estate: Dictionary) -> Dictionary:
	if rule.has("collect_paid_production") and not rule.collect_paid_production is bool: return Rules.fail("原已付款订单接管安排无效")
	var records: Variant = estate.get("collected_orders", {})
	if not records is Dictionary or (not records.is_empty() and not rule.get("collect_paid_production", false)): return Rules.fail("遗产订单接管缺少实际来源")
	for id in records:
		var order: Dictionary = raw.economic_contracts.get(id, {})
		var receipt: Dictionary = raw.action_receipts.get(records[id], {})
		if order.get("contract_kind") != "production" or order.get("customer_id") != rule.owner_id or order.get("status") != "delivered" or order.get("collection_receipt") != records[id] or receipt.get("estate_collection") != {"estate_id": rule.estate_id, "order_id": id, "commission_receipt": order.get("commission_receipt")} or receipt.get("executor_id") != rule.executor_id or int(receipt.get("day", -1)) < int(estate.created_day) or not receipt.get("effect_refs", []).has(id) or not receipt.get("journal_refs", []).is_empty(): return Rules.fail("遗产接管丢失原已付款合同、实际经办人或交货回执")
		if active_collector(raw, id): return Rules.fail("遗产不能越过仍在经办的原取货委托")
	return {"ok": true}
