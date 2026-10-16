extends RefCounted
const Education = preload("res://scripts/core/education_service.gd")
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Workload = preload("res://scripts/core/character_workload_service.gd")
const Presence = preload("res://scripts/core/production_service.gd")
const Works = preload("res://scripts/core/public_works_service.gd")
const KINDS := ["commission_school_supply", "receive_school_supply"]

static func fail(message: String) -> Dictionary: return {"ok": false, "error": message}

static func offer_for(school: Dictionary, id: String) -> Dictionary:
	for offer in school.get("supply_offers", []):
		if offer.supply_id == id: return offer
	return {}

static func orders(state, school_id: String) -> Array:
	return state.economic_contracts.values().filter(func(order): return order.get("contract_kind") == "school_supply" and order.get("school_id") == school_id)

static func location_for(state, params: Dictionary) -> String:
	return str(state.management_assets.get(params.get("school_id", ""), {}).get("location_id", ""))

static func cost_for(state, kind: String, params: Dictionary) -> Dictionary:
	var school: Dictionary = state.management_assets.get(params.get("school_id", ""), {})
	if school.get("asset_kind") != "school" or not school.has("capacity_origin") or str(params.get("order_id", "")).is_empty(): return fail("学舍供给须有实际学舍、来源和独立合同")
	if kind == "receive_school_supply":
		var order: Dictionary = state.economic_contracts.get(params.order_id, {})
		if order.get("contract_kind") != "school_supply" or order.get("school_id") != school.asset_id: return {"ok": false, "code": "asset_not_ready", "error": "尚无该学舍对应的供给合同"}
		return {"ok": true, "amount": 0, "account_id": ""}
	var offer := offer_for(school, str(params.get("supply_id", "")))
	if kind != "commission_school_supply" or offer.is_empty() or params.get("funding_account_id") != school.account_id: return fail("须使用学舍实际供给报价与经费账户")
	return {"ok": true, "amount": int(offer.price), "account_id": school.account_id}

static func apply(state, kind: String, params: Dictionary, principal: String, execution: String, reservation: String) -> Dictionary:
	var quote := cost_for(state, kind, params)
	if not quote.ok: return quote
	var school: Dictionary = state.management_assets[params.school_id]
	if not Education.authority(state, school, principal): return fail("当前没有该学舍供给经办权")
	if kind == "receive_school_supply": return _receive(state, school, params.order_id, execution)
	var offer := offer_for(school, params.supply_id)
	if state.economic_contracts.has(params.order_id) or orders(state, school.asset_id).filter(func(row): return row.recipe.supply_id == offer.supply_id).size() >= int(offer.max_orders): return fail("该场地扩建或课书材料的可承接份数已用完，不能重复拨付")
	if not Presence.present(state, offer.supplier_id, school.location_id) or not Workload.can_schedule(state, offer.supplier_id, "school_supply", principal): return fail("承办人未到当地或没有可履约的工日")
	if int(state.character_states[offer.supplier_id].get("relationships", {}).get(principal, 0)) < -15: return fail("承办人当前不愿接下该委托")
	if state.economic_contracts.values().any(func(row): return row.get("supplier_id") == offer.supplier_id and row.get("status") == "working"): return fail("承办人仍有未完工合同，须先履约")
	for input in offer.inputs:
		var stock: Dictionary = state.management_assets.get(input.stock_id, {})
		if stock.get("asset_kind") != "material_stock" or stock.get("owner_ref") != school.owner_ref or stock.get("location_id") != school.location_id or int(stock.get("remaining_quantity", 0)) < int(input.quantity): return fail("学舍工程或抄书所需的实际材料不足、产权不符或未到场")
	var paid := Accounts.new().apply(state, "transfer", {"execution_id": execution, "actor_id": principal, "source_account_id": school.account_id, "destination_account_id": offer.payee_account_id, "amount": int(offer.price), "reason_ref": params.order_id, "reservation_id": reservation})
	if not paid.get("ok", false): return paid
	for input in offer.inputs:
		var stock: Dictionary = state.management_assets[input.stock_id]
		stock.remaining_quantity -= int(input.quantity)
		stock.consumptions[params.order_id] = int(input.quantity)
	state.economic_contracts[params.order_id] = {"contract_id": params.order_id, "contract_kind": "school_supply", "school_id": school.asset_id, "customer_id": principal, "supplier_id": offer.supplier_id, "recipe": offer.duplicate(true), "commission_receipt": execution, "collection_receipt": "", "created_day": int(state.current_day), "created_date": state.current_date.duplicate(true), "last_work_day": int(state.current_day), "work_days": 0, "work_log": [], "status": "working", "blocked_reason": ""}
	school.supply_contract_refs.append(params.order_id)
	return {"ok": true, "result_ref": params.order_id, "journal_refs": [execution], "visible_summary": "已委托%s：实付 %d，材料出库；须完成 %d 个真实工日并交验后才增加供给。" % [offer.name, int(offer.price), int(offer.duration_days)]}

static func settle_daily(state) -> Dictionary:
	for order in state.economic_contracts.values():
		if order.get("contract_kind") != "school_supply" or order.status != "working" or int(order.last_work_day) >= int(state.current_day): continue
		var school: Dictionary = state.management_assets[order.school_id]
		if not order.recipe.work_months.any(func(month): return int(month) == int(state.current_date.month)):
			order.blocked_reason = "当前不是约定施工月份；保留投入与已完成工日。"
			continue
		var rations: String = order.supplier_id + "_rations"
		if not Presence.present(state, order.supplier_id, school.location_id) or Workload.occupied_today(state, order.supplier_id, order.contract_id, order.customer_id, "school_supply") or (state.resource_accounts.has(rations) and Accounts.new().available(state, rations) <= 0):
			order.blocked_reason = "承办人缺席、缺粮或今日另有职责，等待实际履约。"
			continue
		Workload.record_work(state, order)
		order.work_log[-1]["date"] = state.current_date.duplicate(true)
		order.blocked_reason = ""
		if int(order.work_days) == int(order.recipe.duration_days):
			order.status = "ready"
			order["completed_day"] = int(state.current_day)
	return {"ok": true}

static func _receive(state, school: Dictionary, id: String, execution: String) -> Dictionary:
	var order: Dictionary = state.economic_contracts[id]
	if order.status == "working": return {"ok": false, "code": "awaiting_delivery", "error": order.blocked_reason if order.blocked_reason != "" else "实际施工或抄书尚未完成，不能提前入账。"}
	if order.status != "ready" or not Presence.present(state, order.supplier_id, school.location_id): return fail("供给已交验或承办人未到场")
	order.status = "accepted"
	order.collection_receipt = execution
	order["accepted_day"] = int(state.current_day)
	var field: String = order.recipe.output_kind
	school[field] = int(school[field]) + int(order.recipe.output_quantity)
	return {"ok": true, "result_ref": id, "visible_summary": "%s已交验：实际增加 %d %s；师资和考试名额仍按各自规则核对。" % [order.recipe.name, int(order.recipe.output_quantity), "个席位" if field == "seats" else "套课书"]}

# Historic capacity must not borrow a room or book delivered in the future.
static func physical_capacity(school: Dictionary, contracts: Dictionary, field: String, day: int) -> int:
	if not school.has("capacity_origin"): return int(school.get(field, 0))
	var total := int(school.capacity_origin.get(field, 0))
	for order in contracts.values():
		if order.get("contract_kind") == "school_supply" and order.get("school_id") == school.asset_id and order.get("status") == "accepted" and int(order.get("accepted_day", day + 1)) <= day and order.get("recipe", {}).get("output_kind") == field: total += int(order.recipe.output_quantity)
	return total

static func project(state, school: Dictionary) -> Dictionary:
	var supplies := orders(state, school.asset_id)
	var offers: Array = []
	for offer in school.get("supply_offers", []):
		var row: Dictionary = offer.duplicate(true)
		row["remaining_orders"] = int(offer.max_orders) - supplies.filter(func(order): return order.recipe.supply_id == offer.supply_id).size()
		row["proposed_order_id"] = "school-supply:%s:%s:%d" % [school.asset_id, offer.supply_id, supplies.size() + 1]
		row["materials"] = offer.inputs.map(func(input): return {"stock_id": input.stock_id, "name": state.management_assets[input.stock_id].name, "required": int(input.quantity), "available": int(state.management_assets[input.stock_id].remaining_quantity)})
		offers.append(row)
	return {"supplies": supplies.duplicate(true), "available_supply_offers": offers}

static func validate(raw: Dictionary) -> Dictionary:
	var contracts: Dictionary = raw.get("economic_contracts", {})
	var assets: Dictionary = raw.get("management_assets", {})
	for school in assets.values():
		if school.get("asset_kind") != "school" or not school.has("supply_offers"): continue
		var origin: Variant = school.get("capacity_origin")
		if not origin is Dictionary or not str(origin.get("source_id", "")).begins_with("scenario:") or not Works.number(origin.get("seats"), 1) or not Works.number(origin.get("book_sets"), 1) or not school.supply_offers is Array or not school.get("supply_contract_refs") is Array: return fail("学舍供给缺少原有容量来源或合同目录")
		var ids := {}
		for offer in school.supply_offers:
			if not offer is Dictionary or not offer.get("supply_id") is String or str(offer.supply_id).is_empty() or ids.has(offer.supply_id) or not offer.get("name") is String or not str(offer.get("source_id", "")).begins_with("scenario:") or offer.get("output_kind") not in ["seats", "book_sets"] or not raw.character_states.has(offer.get("supplier_id")) or raw.resource_accounts.get(offer.get("payee_account_id"), {}).get("owner_ref") != {"entity_kind": "character", "entity_id": offer.get("supplier_id")}: return fail("学舍供给报价缺少实际承办人、产出或来源")
			ids[offer.supply_id] = true
			for field in ["price", "duration_days", "max_orders", "output_quantity"]:
				if not Works.number(offer.get(field), 1): return fail("学舍供给金额、工日或可承接量无效")
			if not offer.get("inputs") is Array or offer.inputs.is_empty() or not offer.get("work_months") is Array or offer.work_months.is_empty(): return fail("学舍供给缺少实物投入或履约月份")
			var seen := {}
			for month in offer.work_months:
				if not Works.number(month, 1, 12) or seen.has(int(month)): return fail("学舍供给月份重复或无效")
				seen[int(month)] = true
			seen.clear()
			for input in offer.inputs:
				if not input is Dictionary or not Works.number(input.get("quantity"), 1) or seen.has(input.get("stock_id")): return fail("学舍供给材料数量无效或重复")
				var stock: Dictionary = assets.get(input.get("stock_id"), {})
				if stock.get("asset_kind") != "material_stock" or stock.get("owner_ref") != school.owner_ref or stock.get("location_id") != school.location_id: return fail("学舍供给缺少实际材料产权或地点")
				seen[input.stock_id] = true
		var refs := {}
		var counts := {}
		for ref in school.supply_contract_refs:
			var order: Dictionary = contracts.get(ref, {})
			if refs.has(ref) or order.get("contract_kind") != "school_supply" or order.get("school_id") != school.asset_id or not order.get("recipe") is Dictionary: return fail("学舍供给目录重复或引用无关事务")
			refs[ref] = true
			var offer := offer_for(school, str(order.recipe.get("supply_id", "")))
			if offer.is_empty(): return fail("供给合同丢失实际报价")
			counts[offer.supply_id] = int(counts.get(offer.supply_id, 0)) + 1
			if int(counts[offer.supply_id]) > int(offer.max_orders): return fail("学舍供给超过有来源的可承接次数")
		for field in ["seats", "book_sets"]:
			if school.get(field) != physical_capacity(school, contracts, field, int(raw.current_day)): return fail("学舍容量没有实际原有来源或已交验产出")
	for order in contracts.values():
		if order.get("contract_kind") != "school_supply": continue
		var school: Dictionary = assets.get(order.get("school_id"), {})
		var offer := offer_for(school, str(order.get("recipe", {}).get("supply_id", "")))
		if school.get("asset_kind") != "school" or not school.get("supply_contract_refs", []).has(order.contract_id) or offer.is_empty() or order.get("recipe") != offer or order.get("supplier_id") != offer.supplier_id or not raw.character_states.has(order.get("customer_id")) or not order.get("blocked_reason") is String: return fail("学舍供给合同丢失学校、报价或实际人物")
		if not Works.number(order.get("created_day")) or int(order.created_day) > int(raw.current_day) or Works.date_serial(order.get("created_date")) != Works.date_serial(raw.current_date) - (int(raw.current_day) - int(order.created_day)) or not Works.number(order.get("work_days")) or int(order.work_days) > int(offer.duration_days) or not order.get("work_log") is Array or order.work_log.size() != int(order.work_days): return fail("学舍供给工日或起始日期无效")
		if order.work_log.any(func(day): return not day is Dictionary) or order.get("last_work_day") != (order.created_day if order.work_log.is_empty() else order.work_log[-1].get("day")): return fail("学舍供给累计工日与最后履约日不符")
		if order.get("status") not in (["working"] if int(order.work_days) < int(offer.duration_days) else ["ready", "accepted"]): return fail("学舍供给状态与真实工日不符")
		for day in order.work_log:
			if Works.date_serial(day.get("date")) != Works.date_serial(order.created_date) + (int(day.get("day", -1)) - int(order.created_day)) or not offer.work_months.any(func(month): return int(month) == int(day.get("date", {}).get("month", -1))): return fail("学舍工日不在真实日期或约定月份")
		for input in offer.inputs:
			if assets.get(input.stock_id, {}).get("consumptions", {}).get(order.contract_id) != input.quantity: return fail("学舍供给未消耗实际材料")
		var payment: Dictionary = raw.resource_journal.get(order.get("commission_receipt"), {})
		var receipt: Dictionary = raw.action_receipts.get(order.get("commission_receipt"), {})
		if payment.get("entry_kind") != "transfer" or payment.get("source_account_id") != school.account_id or payment.get("destination_account_id") != offer.payee_account_id or payment.get("amount") != offer.price or payment.get("reason_ref") != order.contract_id or payment.get("actor_id") != order.customer_id or payment.get("day") != order.created_day or not receipt.get("effect_refs", []).has(order.contract_id): return fail("学舍供给缺少真实付款或委托回执")
		if order.status != "working" and (order.work_log.is_empty() or order.get("completed_day") != order.work_log[-1].get("day")): return fail("学舍供给缺少实际完工日期")
		if order.status == "accepted":
			var accepted: Dictionary = raw.action_receipts.get(order.get("collection_receipt"), {})
			if not Works.number(order.get("accepted_day")) or int(order.accepted_day) < int(order.completed_day) or int(order.accepted_day) > int(raw.current_day) or accepted.get("day") != order.accepted_day or not accepted.get("effect_refs", []).has(order.contract_id): return fail("学舍新增容量缺少完工后的实际交验凭据")
		elif order.get("collection_receipt", "") != "": return fail("未交验供给不能拥有交验回执")
	return {"ok": true}
