extends RefCounted

const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Workload = preload("res://scripts/core/character_workload_service.gd")
const Presence = preload("res://scripts/core/production_service.gd")
const KINDS := ["start_public_work", "finish_public_work"]

static func fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}

static func initialize(state, data: Dictionary) -> Dictionary:
	for definition in data.get("management", {}).get("regional_administration", {}).get("public_works_assets", []):
		if not definition is Dictionary or state.management_assets.has(definition.get("asset_id")): return fail("公共工程资产来源重复")
		if not definition.get("asset_id") is String or str(definition.asset_id).is_empty() or not definition.get("name") is String or not definition.get("status") is String or not definition.get("owner_ref") is Dictionary or not definition.get("source_ref") is Dictionary or not definition.get("rights") is Array or not definition.get("contract_refs") is Array or not state.local_node_state.has(definition.get("location_id")): return fail("公共工程资产定义缺少归属、来源、地点或权利字段")
		if definition.get("asset_kind") not in ["irrigation_canal", "farmland", "material_stock"]: return fail("公共工程资产定义类型无效")
		state.management_assets[definition.asset_id] = definition.duplicate(true)
	return validate(state.to_dictionary())

static func authority(state, canal: Dictionary, person: String) -> bool:
	var office: Dictionary = state.office_state.get(canal.get("owner_ref", {}).get("entity_id"), {})
	return office.get("office_kind") == "regional" and office.get("status") == "appointed" and office.get("holder_id") == person and Accounts.new().can_operate(state, str(canal.get("account_id", "")), person)

static func canal_for(state, kind: String, params: Dictionary) -> Dictionary:
	var id := str(params.get("canal_id", ""))
	if kind == "finish_public_work": id = str(state.economic_contracts.get(params.get("order_id"), {}).get("canal_id", ""))
	return state.management_assets.get(id, {})

static func location_for(state, kind: String, params: Dictionary) -> String:
	return str(canal_for(state, kind, params).get("location_id", ""))

static func cost_for(state, kind: String, params: Dictionary) -> Dictionary:
	if not params.get("order_id") is String or str(params.order_id).is_empty(): return fail("工程需要唯一合同标识")
	if kind == "finish_public_work":
		if state.economic_contracts.get(params.order_id, {}).get("contract_kind") != "public_work": return {"ok": false, "code": "asset_not_ready", "error": "尚无对应公共工程合同"}
		return {"ok": true, "account_id": "", "amount": 0}
	var canal := canal_for(state, kind, params)
	if canal.get("asset_kind") != "irrigation_canal" or params.get("funding_account_id") != canal.get("account_id"): return fail("修渠须指定真实渠道及其州库账户")
	return {"ok": true, "account_id": canal.account_id, "amount": int(canal.repair_offer.price)}

static func apply(state, kind: String, params: Dictionary, principal: String, execution: String, reservation: String = "") -> Dictionary:
	var canal := canal_for(state, kind, params)
	if not authority(state, canal, principal): return fail("当前没有该州公共工程经办权")
	if kind == "finish_public_work": return _finish(state, canal, params.order_id, execution)
	if state.economic_contracts.has(params.order_id) or canal.status != "damaged" or canal.active_contract_id != "": return fail("渠道已开工或已修复，不能重复拨款")
	var offer: Dictionary = canal.repair_offer
	if not Presence.present(state, offer.supplier_id, canal.location_id) or not Workload.can_schedule(state, offer.supplier_id, "public_works", principal): return fail("工匠离场或无可履行的空闲工日")
	if int(state.character_states[offer.supplier_id].get("relationships", {}).get(principal, 0)) < -15: return fail("工匠不愿承接当前委托")
	for other in state.economic_contracts.values():
		if other.get("supplier_id") == offer.supplier_id and other.get("status") == "working": return fail("工匠已承接另一份未完合同")
	for input in offer.inputs:
		var stock: Dictionary = state.management_assets.get(input.stock_id, {})
		if stock.get("asset_kind") != "material_stock" or stock.owner_ref != canal.owner_ref or stock.location_id != canal.location_id or int(stock.remaining_quantity) < int(input.quantity): return fail("州库现有工程材料不足或不在场")
	var paid := Accounts.new().apply(state, "transfer", {"execution_id": execution, "source_account_id": canal.account_id, "destination_account_id": offer.payee_account_id, "amount": int(offer.price), "actor_id": principal, "reason_ref": params.order_id, "reservation_id": reservation})
	if not paid.get("ok", false): return paid
	for input in offer.inputs:
		var stock: Dictionary = state.management_assets[input.stock_id]
		stock.remaining_quantity -= int(input.quantity)
		stock.consumptions[params.order_id] = int(input.quantity)
	canal.status = "working"
	canal.active_contract_id = params.order_id
	canal.contract_refs.append(params.order_id)
	state.economic_contracts[params.order_id] = {"contract_id": params.order_id, "contract_kind": "public_work", "status": "working", "terms_version": 1, "party_refs": [canal.owner_ref.entity_id, offer.supplier_id], "customer_id": principal, "supplier_id": offer.supplier_id, "canal_id": canal.asset_id, "recipe": offer.duplicate(true), "funding_account_id": canal.account_id, "payee_account_id": offer.payee_account_id, "commission_receipt": execution, "collection_receipt": "", "execution_refs": [execution], "created_day": int(state.current_day), "created_date": state.current_date.duplicate(true), "work_days": 0, "last_work_day": int(state.current_day), "work_log": [], "blocked_reason": ""}
	return {"ok": true, "result_ref": params.order_id, "journal_refs": [execution], "visible_summary": "%s已开工：实际支付工款 %d，材料已出库；需 %d 个可施工工日。" % [canal.name, int(offer.price), int(offer.duration_days)]}

static func settle_daily(state) -> Dictionary:
	for order in state.economic_contracts.values():
		if order.get("contract_kind") != "public_work" or order.status != "working" or int(order.last_work_day) >= int(state.current_day): continue
		var canal: Dictionary = state.management_assets[order.canal_id]
		if not order.recipe.work_months.any(func(month): return int(month) == int(state.current_date.month)):
			order.blocked_reason = "当前月份停工避汛或避冻，已付工款、材料与完成工日保留。"
			continue
		if not Presence.present(state, order.supplier_id, canal.location_id):
			order.blocked_reason = "工匠未在施工地，等待其到场；已投入保留。"
			continue
		if Workload.occupied_today(state, order.supplier_id, order.contract_id, order.customer_id, "public_works"):
			order.blocked_reason = "工匠今日须履行另一项职责，未计入本工程工日。"
			continue
		order.blocked_reason = ""
		Workload.record_work(state, order)
		order.work_log[-1]["date"] = state.current_date.duplicate(true)
		if int(order.work_days) == int(order.recipe.duration_days):
			order.status = "ready"
			order["completed_day"] = int(state.current_day)
			canal.status = "ready"
	return {"ok": true}

static func _finish(state, canal: Dictionary, id: String, execution: String) -> Dictionary:
	var order: Dictionary = state.economic_contracts[id]
	if order.status == "working": return {"ok": false, "code": "awaiting_delivery", "error": order.blocked_reason if order.blocked_reason != "" else "施工尚未完成，不能验收通水。"}
	if order.status != "ready" or canal.status != "ready": return fail("工程已验收或状态已变化")
	if not Presence.present(state, order.supplier_id, canal.location_id): return fail("承修人未在场，暂不能交验")
	order.status = "accepted"
	order.collection_receipt = execution
	order["accepted_day"] = int(state.current_day)
	canal.status = "operational"
	for id_field in canal.benefit_field_ids:
		var field: Dictionary = state.management_assets[id_field]
		field.water_supply = int(canal.repaired_water_supply)
		field.water_source_contract_id = id
		field.contract_refs.append(id)
	return {"ok": true, "result_ref": id, "visible_summary": "%s已验收通水，%d 块接渠田地的灌溉条件已更新；尚未收获，不计作现金或粮食收入。" % [canal.name, canal.benefit_field_ids.size()]}

static func project(state, person: String) -> Array:
	var rows: Array = []
	for canal in state.management_assets.values():
		if canal.get("asset_kind") != "irrigation_canal" or not authority(state, canal, person): continue
		var row: Dictionary = canal.duplicate(true)
		row["proposed_order_id"] = "public-work:%s:%s" % [person, canal.asset_id]
		row["fields"] = []
		for id in canal.benefit_field_ids:
			var field: Dictionary = state.management_assets[id]
			row.fields.append({"asset_id": id, "name": field.name, "area_units": field.area_units, "water_supply": field.water_supply})
		row["materials"] = []
		for input in canal.repair_offer.inputs:
			var stock: Dictionary = state.management_assets[input.stock_id]
			row.materials.append({"asset_id": stock.asset_id, "name": stock.name, "required": input.quantity, "remaining": stock.remaining_quantity})
		row["order"] = state.economic_contracts.get(canal.active_contract_id, {}).duplicate(true)
		rows.append(row)
	return rows

static func number(value: Variant, minimum: int = 0, maximum: int = 1000000000) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= minimum and float(value) <= maximum

static func date_serial(date: Variant) -> int:
	if not date is Dictionary or not number(date.get("year"), 1) or not number(date.get("month"), 1, 12) or not number(date.get("day"), 1, 30): return -1
	return int(date.year) * 360 + (int(date.month) - 1) * 30 + int(date.day) - 1

static func validate(raw: Dictionary) -> Dictionary:
	var assets: Dictionary = raw.get("management_assets", {})
	var contracts: Dictionary = raw.get("economic_contracts", {})
	for asset in assets.values():
		if asset.get("asset_kind") == "farmland":
			if not number(asset.get("area_units"), 1) or not number(asset.get("base_water_supply"), 0, 100) or not number(asset.get("water_supply"), 0, 100) or not asset.get("water_source_contract_id") is String or not asset.get("irrigation_canal_id") is String: return fail("田地缺少面积或实际供水来源")
			var canal: Dictionary = assets.get(asset.irrigation_canal_id, {})
			if not asset.irrigation_canal_id.is_empty() and (canal.get("asset_kind") != "irrigation_canal" or not canal.get("benefit_field_ids", []).has(asset.asset_id)): return fail("田地与实际渠道连接不一致")
			var irrigated: bool = canal.get("status") == "operational"
			if asset.water_supply != (canal.repaired_water_supply if irrigated else asset.base_water_supply) or asset.water_source_contract_id != (canal.active_contract_id if irrigated else ""): return fail("田地供水改变缺少已验收工程")
			if irrigated and not asset.contract_refs.has(canal.active_contract_id): return fail("受益田地缺少工程凭据")
		if asset.get("asset_kind") != "irrigation_canal": continue
		var office: Dictionary = raw.office_state.get(asset.owner_ref.get("entity_id"), {})
		var account: Dictionary = raw.resource_accounts.get(asset.get("account_id"), {})
		if asset.owner_ref.get("entity_kind") != "office" or office.get("office_kind") != "regional" or account.get("owner_ref") != asset.owner_ref or account.get("location_id") != asset.location_id or asset.get("status") not in ["damaged", "working", "ready", "operational"] or not asset.get("active_contract_id") is String: return fail("公共渠道归属、州库或施工状态无效")
		var offer: Variant = asset.get("repair_offer")
		if not offer is Dictionary or not number(offer.get("price"), 1) or not number(offer.get("duration_days"), 1) or not offer.get("inputs") is Array or offer.inputs.is_empty() or not offer.get("work_months") is Array or offer.work_months.is_empty() or not raw.character_states.has(offer.get("supplier_id")) or raw.resource_accounts.get(offer.get("payee_account_id"), {}).get("owner_ref") != {"entity_kind": "character", "entity_id": offer.get("supplier_id")}: return fail("公共工程报价缺少实际承修人、工款、材料或季节")
		var months: Array = []
		for month in offer.work_months:
			if not number(month, 1, 12) or months.has(int(month)): return fail("施工月份无效或重复")
			months.append(int(month))
		var stocks: Array = []
		for input in offer.inputs:
			if not input is Dictionary or not number(input.get("quantity"), 1) or stocks.has(input.get("stock_id")): return fail("工程材料数量无效或重复")
			var stock: Dictionary = assets.get(input.get("stock_id"), {})
			if stock.get("asset_kind") != "material_stock" or stock.get("owner_ref") != asset.owner_ref or stock.get("location_id") != asset.location_id: return fail("工程材料缺少州库实物来源")
			stocks.append(input.stock_id)
		if not number(asset.get("repaired_water_supply"), 1, 100) or not asset.get("benefit_field_ids") is Array or asset.benefit_field_ids.is_empty(): return fail("渠道缺少实际受益田地")
		var fields: Array = []
		for field_id in asset.benefit_field_ids:
			var field: Dictionary = assets.get(field_id, {})
			if fields.has(field_id) or field.get("asset_kind") != "farmland" or field.get("irrigation_canal_id") != asset.asset_id or field.get("location_id") != asset.location_id: return fail("工程受益田地重复或未接渠")
			fields.append(field_id)
		if asset.status == "damaged":
			if asset.active_contract_id != "" or not asset.contract_refs.is_empty(): return fail("未开工渠道已经记入合同")
		else:
			var order: Dictionary = contracts.get(asset.active_contract_id, {})
			if order.get("contract_kind") != "public_work" or order.get("canal_id") != asset.asset_id or not asset.contract_refs.has(order.get("contract_id")): return fail("渠道施工缺少有效合同")
	for order in contracts.values():
		if order.get("contract_kind") != "public_work": continue
		var checked := _validate_order(raw, order)
		if not checked.ok: return checked
	return {"ok": true}

static func _validate_order(raw: Dictionary, order: Dictionary) -> Dictionary:
	var canal: Dictionary = raw.management_assets.get(order.get("canal_id"), {})
	if canal.get("asset_kind") != "irrigation_canal" or canal.get("active_contract_id") != order.contract_id or order.get("recipe") != canal.get("repair_offer") or not raw.character_states.has(order.get("customer_id")): return fail("工程合同失去实际渠道、承诺报价或原经办人")
	var offer: Dictionary = canal.repair_offer
	if order.get("terms_version") != 1 or order.get("supplier_id") != offer.supplier_id or order.get("party_refs") != [canal.owner_ref.entity_id, offer.supplier_id] or order.get("funding_account_id") != canal.account_id or order.get("payee_account_id") != offer.payee_account_id or order.get("execution_refs") != [order.get("commission_receipt")] or not order.get("blocked_reason") is String: return fail("工程合同当事人、款项或凭据不一致")
	for field in ["created_day", "work_days", "last_work_day"]:
		if not number(order.get(field)): return fail("工程工日不是非负整数")
	if int(order.work_days) > int(offer.duration_days) or int(order.last_work_day) > int(raw.current_day) or int(order.created_day) > int(order.last_work_day) or not order.get("work_log") is Array or order.work_log.size() != int(order.work_days): return fail("工程累计工日与工时凭据不符")
	var created_date := date_serial(order.get("created_date"))
	if created_date < 0 or date_serial(raw.get("current_date")) != created_date + int(raw.current_day) - int(order.created_day): return fail("工程开工日历与实际经过天数不一致")
	var last_day := int(order.created_day)
	for row in order.work_log:
		if not row is Dictionary or not number(row.get("day")) or int(row.day) <= last_day or date_serial(row.get("date")) < 0 or date_serial(row.get("date")) != created_date + int(row.day) - int(order.created_day) or not offer.work_months.any(func(month): return int(month) == int(row.date.month)): return fail("工程在非施工季节计入工时或日历不一致")
		last_day = int(row.day)
	if int(order.last_work_day) != last_day: return fail("工程最近工日与实际记录不一致")
	var paid: Dictionary = raw.resource_journal.get(order.get("commission_receipt"), {})
	var receipt: Dictionary = raw.action_receipts.get(order.get("commission_receipt"), {})
	if paid.get("entry_kind") != "transfer" or paid.get("source_account_id") != canal.account_id or paid.get("destination_account_id") != offer.payee_account_id or paid.get("amount") != offer.price or paid.get("reason_ref") != order.contract_id or receipt.get("day") != order.created_day or not receipt.get("effect_refs", []).has(order.contract_id) or not receipt.get("journal_refs", []).has(order.commission_receipt): return fail("工程缺少实际拨款或开工回执")
	for input in offer.inputs:
		if raw.management_assets[input.stock_id].consumptions.get(order.contract_id) != input.quantity: return fail("工程未实际消耗约定材料")
	var statuses := {"working": "working", "ready": "ready", "accepted": "operational"}
	if not statuses.has(order.get("status")) or canal.status != statuses[order.status] or not order.get("collection_receipt") is String: return fail("工程与渠道状态不一致")
	if order.status == "working":
		if int(order.work_days) >= int(offer.duration_days) or order.collection_receipt != "": return fail("未完成工程已提前验收")
	else:
		if int(order.work_days) != int(offer.duration_days) or order.get("completed_day") != order.last_work_day: return fail("竣工缺少实际工期")
		if order.status == "ready" and order.collection_receipt != "": return fail("未验收工程已有交验凭据")
		if order.status == "accepted":
			var acceptance: Dictionary = raw.action_receipts.get(order.collection_receipt, {})
			if not number(order.get("accepted_day")) or int(order.accepted_day) < int(order.completed_day) or int(order.accepted_day) > int(raw.current_day) or acceptance.get("day") != order.accepted_day or not acceptance.get("effect_refs", []).has(order.contract_id): return fail("验收缺少正式回执或日期")
	return {"ok": true}
