extends RefCounted
const Contract = preload("res://scripts/core/management_state_contract.gd")
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Workload = preload("res://scripts/core/character_workload_service.gd")
const KINDS := ["commission_production", "collect_production"]

static func location_for(state, kind: String, params: Dictionary) -> String:
	var workshop_id := str(params.get("workshop_id", ""))
	if kind == "collect_production": workshop_id = str(state.economic_contracts.get(params.get("order_id"), {}).get("workshop_id", ""))
	return str(state.management_assets.get(workshop_id, {}).get("location_id", ""))

static func cost_for(state, kind: String, params: Dictionary) -> Dictionary:
	if not params.get("order_id") is String or str(params.order_id).is_empty(): return Contract.fail("生产需要明确订单标识")
	if kind == "collect_production":
		if state.economic_contracts.get(params.order_id, {}).get("contract_kind") != "production": return {"ok": false, "code": "asset_not_ready", "error": "尚无对应生产订单"}
		return {"ok": true, "account_id": "", "amount": 0}
	var workshop: Dictionary = state.management_assets.get(params.get("workshop_id"), {})
	var recipe: Dictionary = workshop.get("recipes", {}).get(params.get("recipe_id"), {})
	if workshop.get("asset_kind") != "workshop" or not Contract.amount(recipe.get("price"), true) or not state.resource_accounts.has(params.get("funding_account_id")): return Contract.fail("未找到真实工坊报价或付款账户")
	return {"ok": true, "account_id": params.funding_account_id, "amount": int(recipe.price)}

static func present(state, person: String, place: String) -> bool:
	var character: Dictionary = state.character_states.get(person, {})
	return not character.is_empty() and character.get("status") not in ["dead", "deceased", "executed", "missing", "imprisoned", "departed", "exiled", "unreachable"] and str(character.get("location_id", "")).trim_suffix("_node") == place.trim_suffix("_node")

static func apply(state, kind: String, params: Dictionary, principal: String, execution: String, reservation: String = "", continuation: Dictionary = {}) -> Dictionary:
	if kind == "collect_production": return _collect(state, params.order_id, principal, execution, continuation)
	var workshop: Dictionary = state.management_assets[params.workshop_id]
	var recipe: Dictionary = workshop.recipes[params.recipe_id]
	if state.economic_contracts.has(params.order_id) or state.management_assets.has("product:" + params.order_id): return Contract.fail("生产订单标识已使用")
	if workshop.status != "available" or not present(state, workshop.supplier_id, workshop.location_id): return Contract.fail("工坊停工或工匠不在场")
	if not Workload.can_schedule(state, workshop.supplier_id, "production", principal): return Contract.fail("工匠现有任职已占满排班，须先安排交接，不能先收取无法履行的订单款")
	if int(state.character_states[workshop.supplier_id].get("relationships", {}).get(principal, 0)) < -15: return Contract.fail("工匠不愿接受此项委托")
	for other in state.economic_contracts.values():
		if other.get("supplier_id") == workshop.supplier_id and other.get("status") == "working": return Contract.fail("工匠正在履行另一份合同，尚无空闲工时")
	for input in recipe.inputs:
		var stock: Dictionary = state.management_assets.get(input.stock_id, {})
		if stock.get("asset_kind") != "material_stock" or stock.owner_ref != workshop.owner_ref or stock.location_id != workshop.location_id or int(stock.remaining_quantity) < int(input.quantity): return Contract.fail("实际材料不足或不在工坊保管范围")
	var source := str(recipe.get("source_work_id", ""))
	if not source.is_empty():
		var manuscript: Dictionary = state.management_assets.get(source, {})
		if manuscript.get("status") != "available" or manuscript.get("location_id") != workshop.location_id or manuscript.get("copy_permission") != "public" or manuscript.get("custodian_ref") != workshop.owner_ref: return Contract.fail("现有底本不在场或无誊写权利")
	var payer := principal
	if not continuation.is_empty(): payer = str(load("res://scripts/core/estate_production_continuation.gd").task_for(state, continuation.task_id).executor_id)
	if not continuation.is_empty(): state.economic_contracts[continuation.estate_id]["processing_task"] = continuation.task_id
	var paid := Accounts.new().apply(state, "transfer", {"execution_id": execution, "source_account_id": params.funding_account_id, "destination_account_id": workshop.payee_account_id, "amount": int(recipe.price), "actor_id": payer, "reason_ref": params.order_id, "reservation_id": reservation, "estate_task_id": continuation.get("task_id", "")})
	if not continuation.is_empty(): state.economic_contracts[continuation.estate_id].erase("processing_task")
	if not paid.get("ok", false): return paid
	for input in recipe.inputs:
		var stock: Dictionary = state.management_assets[input.stock_id]
		stock.remaining_quantity -= int(input.quantity)
		stock.consumptions[params.order_id] = int(input.quantity)
	state.economic_contracts[params.order_id] = {"contract_id": params.order_id, "contract_kind": "production", "status": "working", "terms_version": 1, "party_refs": [principal, workshop.supplier_id], "customer_id": principal, "supplier_id": workshop.supplier_id, "workshop_id": workshop.asset_id, "recipe_id": params.recipe_id, "recipe": recipe.duplicate(true), "funding_account_id": params.funding_account_id, "payee_account_id": workshop.payee_account_id, "execution_refs": [execution], "commission_receipt": execution, "collection_receipt": "", "output_id": "product:" + params.order_id, "created_day": int(state.current_day), "work_days": 0, "last_work_day": int(state.current_day), "due_day": int(state.current_day) + int(recipe.duration_days), "blocked_reason": ""}
	state.economic_contracts[params.order_id]["work_log"] = []
	return {"ok": true, "result_ref": params.order_id, "journal_refs": [execution]}

static func settle_daily(state) -> Dictionary:
	for order in state.economic_contracts.values():
		if order.get("contract_kind") != "production" or order.status != "working" or int(order.last_work_day) >= int(state.current_day): continue
		var workshop: Dictionary = state.management_assets[order.workshop_id]
		if workshop.status != "available" or not present(state, order.supplier_id, workshop.location_id):
			order.blocked_reason = "工匠离场或工坊停工，材料与已付款保留在订单中。"
			continue
		if Workload.occupied_today(state, order.supplier_id, order.contract_id, order.customer_id, "production"):
			order.blocked_reason = "工匠今日有任职或其他工序占用；请等待空闲工日或安排交接，已付款与材料保留。"
			continue
		order.blocked_reason = ""
		Workload.record_work(state, order)
		order.due_day = int(state.current_day) + maxi(0, int(order.recipe.duration_days) - int(order.work_days))
		if int(order.work_days) < int(order.recipe.duration_days): continue
		if state.management_assets.has(order.output_id): return Contract.fail("生产产物标识冲突，不能覆盖现有实物")
		var owner := {"entity_kind": "character", "entity_id": order.customer_id}
		state.management_assets[order.output_id] = {"asset_id": order.output_id, "asset_kind": "movable", "name": order.recipe.output_definition.name, "owner_ref": owner, "custodian_ref": workshop.owner_ref.duplicate(true), "location_id": workshop.location_id, "source_ref": {"entity_kind": "contract", "entity_id": order.contract_id}, "rights": [], "contract_refs": [order.contract_id], "status": "awaiting_delivery", "condition": 100, "lien_contract_id": "", "equipped_by": "", "item_definition": order.recipe.output_definition.duplicate(true)}
		order.status = "ready"
		order["completed_day"] = int(state.current_day)
	var manufacturing: Dictionary = load("res://scripts/core/manufacturing_business_service.gd").settle_daily(state)
	if not manufacturing.ok: return manufacturing
	return load("res://scripts/core/managed_farming_service.gd").settle_daily(state)

static func _collect(state, id: String, principal: String, execution: String, continuation: Dictionary = {}) -> Dictionary:
	var order: Dictionary = state.economic_contracts[id]
	if order.customer_id != principal: return Contract.fail("无权领取他人的生产订单")
	if order.status == "working": return {"ok": false, "code": "awaiting_delivery", "error": str(order.blocked_reason) if order.blocked_reason != "" else "工序尚未完成，等待工匠交付。"}
	if order.status != "ready": return Contract.fail("订单已经交割，不能再次领取")
	var item: Dictionary = state.management_assets[order.output_id]
	if not present(state, order.supplier_id, item.location_id): return Contract.fail("实际保管人未到交割地点")
	if item.status != "awaiting_delivery" or item.custodian_ref != {"entity_kind": "character", "entity_id": order.supplier_id}: return Contract.fail("订单产物或保管权已经变化")
	var custodian: Dictionary = item.owner_ref.duplicate(true)
	if not continuation.is_empty():
		var estate: Dictionary = state.economic_contracts[continuation.estate_id]
		var rule: Dictionary = load("res://scripts/core/personal_estate_service.gd").rule_for(state, continuation.estate_id)
		if not rule.get("executor_willing", false) or not present(state, estate.executor_id, item.location_id): return {"ok": false, "code": "awaiting_delivery", "error": "遗产经办人须同意并实际到场接管；原产物仍由工坊保管。"}
		custodian = {"entity_kind": "character", "entity_id": estate.executor_id}
		order["estate_custody"] = {"estate_id": continuation.estate_id, "custodian_id": estate.executor_id, "execution_id": execution}
	item.status = "available"
	item.custodian_ref = custodian
	order.status = "delivered"
	order.collection_receipt = execution
	order["delivered_day"] = int(state.current_day)
	if principal == state.player_character_id: state.inventory.append({"id": item.asset_id, "asset_ref": item.asset_id})
	return {"ok": true, "result_ref": id}
