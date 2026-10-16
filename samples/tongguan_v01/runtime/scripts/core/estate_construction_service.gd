extends RefCounted
const Contract = preload("res://scripts/core/management_state_contract.gd")
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Land = preload("res://scripts/core/land_property_service.gd")
const Presence = preload("res://scripts/core/production_service.gd")
const Workload = preload("res://scripts/core/character_workload_service.gd")
const KINDS := ["start_construction","cancel_construction","resume_construction"]
const INDUSTRIES := ["pawnshop","workshop","restaurant","pleasure_house","money_house","cloth_shop","smithy","grain_estate","tea_garden","warehouse","granary","repair_yard","housing","shop","market","inn","infirmary","camp"]

static func cost_for(state, kind: String, params: Dictionary) -> Dictionary:
	var land: Dictionary = state.management_assets.get(params.get("land_id",""),{})
	if land.get("asset_kind") != "land": return Contract.fail("建设须指定实际地块")
	if kind != "start_construction":
		var order: Dictionary = state.economic_contracts.get(params.get("order_id",""),{})
		if order.get("contract_kind") != "estate_construction" or order.get("land_id") != land.asset_id: return Contract.fail("工程不属于所选土地")
		return {"ok":true,"amount":0,"account_id":""}
	var offer: Dictionary = land.development_offers.get(params.get("blueprint_id",""),{})
	if not (offer.get("industry_kind") in INDUSTRIES or offer.has("operation_terms")) or not Contract.amount(offer.get("price"),true) or not state.resource_accounts.has(params.get("funding_account_id")) or offer.get("version") != params.get("quote_version"): return Contract.fail("建设类型或报价已失效")
	return {"ok":true,"amount":int(offer.price),"account_id":params.funding_account_id}

static func apply(state, kind: String, params: Dictionary, principal: String, execution: String, reservation: String = "") -> Dictionary:
	var valid := cost_for(state,kind,params)
	if not valid.ok: return valid
	var land: Dictionary = state.management_assets[params.land_id]
	if kind != "start_construction":
		var order: Dictionary = state.economic_contracts[params.order_id]
		var source: Dictionary=state.resource_accounts[order.funding_account_id]
		if not Accounts.new().can_operate(state,order.funding_account_id,principal) or preload("res://scripts/core/land_lease_service.gd").permission(state,land,source.owner_ref,principal).is_empty():return Contract.fail("缺少原工程及场所的实际经办权")
		if order.status == "completed": return Contract.fail("工程已经竣工")
		if kind == "cancel_construction":
			if order.status == "cancelled": return Contract.fail("工程已停工")
			order.status = "cancelled"
			order.blocked_reason = "已停工；已付工款、用料及未完工程保留，可接续施工"
		else:
			if order.status != "cancelled": return Contract.fail("工程未停工")
			order.status = "working"
			order.blocked_reason = ""
		order.change_receipts.append(execution)
		return {"ok":true,"result_ref":order.contract_id}
	var offer: Dictionary = land.development_offers[params.blueprint_id]
	if offer.industry_kind in ["grain_estate","tea_garden"] and not land.get("agricultural_resources", {}).get("arable", false): return Contract.fail("田庄必须有真实登记的可耕地")
	if offer.has("operation_terms"):
		var spec := {"chronology":"current_scope","requirements":offer.get("site_requirements",[]),"model":"extraction" if offer.operation_terms.config.model=="extraction" else "other","industry_id":offer.industry_kind}
		if not preload("res://scripts/core/modeled_business_service.gd").site_ready(land,spec): return Contract.fail("建设缺少登记资源、用地条件或许可")
	var account: Dictionary = state.resource_accounts[params.funding_account_id]
	var access: Dictionary=preload("res://scripts/core/land_lease_service.gd").permission(state,land,account.owner_ref,principal)
	if access.is_empty() or account.unit_id != "cash_unit" or not Accounts.new().can_operate(state,params.funding_account_id,principal): return Contract.fail("建设款须由有权办理的产权或承租建设主体支付")
	if not str(access.contract_id).is_empty() and int(land.used_area_units)>0:return Contract.fail("整块承租土地已有工程或房产，不能重复占用")
	if int(land.used_area_units)+int(offer.area_units) > int(land.area_units): return Contract.fail("可用空地面积不足")
	if not Presence.present(state,offer.supplier_id,land.location_id) or not Workload.can_schedule(state,offer.supplier_id,"estate_construction",principal): return Contract.fail("工匠尚未到场或没有可承接的工日")
	if int(state.character_states[offer.supplier_id].get("relationships",{}).get(principal,0)) < -15: return Contract.fail("工匠不愿承接此项工程")
	for other in state.economic_contracts.values():
		if other.get("supplier_id") == offer.supplier_id and other.get("status") == "working": return Contract.fail("工匠已有未完工委托")
	for input in offer.inputs:
		var stock: Dictionary = state.management_assets.get(input.stock_id,{})
		if stock.get("owner_ref") != {"entity_kind":"character","entity_id":offer.supplier_id} or stock.get("location_id") != land.location_id or int(stock.get("remaining_quantity",0)) < int(input.quantity): return Contract.fail("约定工程材料不足或尚未到场")
	var id := "construction:"+execution
	var paid := Accounts.new().apply(state,"transfer",{"execution_id":execution,"source_account_id":params.funding_account_id,"destination_account_id":offer.payee_account_id,"amount":int(offer.price),"actor_id":principal,"reason_ref":id,"reservation_id":reservation})
	if not paid.ok: return paid
	for input in offer.inputs:
		var stock: Dictionary = state.management_assets[input.stock_id]
		stock.remaining_quantity -= int(input.quantity)
		stock.consumptions[id] = int(input.quantity)
	land.used_area_units += int(offer.area_units)
	land.sale_offer = {"active":false,"version":int(land.sale_offer.version)+1}
	land.status = "construction"
	land.contract_refs.append(id)
	state.economic_contracts[id] = {"contract_id":id,"contract_kind":"estate_construction","status":"working","land_id":land.asset_id,"building_id":"building:"+execution,"blueprint_id":params.blueprint_id,"recipe":offer.duplicate(true),"supplier_id":offer.supplier_id,"principal_id":principal,"owner_ref":land.owner_ref.duplicate(true),"funding_account_id":params.funding_account_id,"created_day":int(state.current_day),"last_update_day":int(state.current_day),"last_work_day":int(state.current_day),"work_days":0,"work_log":[],"blocked_reason":"","commission_receipt":execution,"change_receipts":[],"terms_version":1,"party_refs":[land.owner_ref.entity_id,offer.supplier_id],"execution_refs":[execution]}
	state.economic_contracts[id].owner_ref=account.owner_ref.duplicate(true)
	state.economic_contracts[id].party_refs=[account.owner_ref.entity_id,offer.supplier_id]
	if not str(access.contract_id).is_empty():state.economic_contracts[id]["land_lease_id"]=access.contract_id
	return {"ok":true,"result_ref":id,"journal_refs":[execution],"visible_summary":"工程已开工；工款与材料已入账，等待实际施工"}

static func settle_daily(state) -> Dictionary:
	var ids: Array = state.economic_contracts.keys(); ids.sort()
	for id in ids:
		var order: Dictionary = state.economic_contracts[id]
		if order.get("contract_kind") != "estate_construction" or order.status != "working" or int(order.last_update_day) >= int(state.current_day): continue
		order.last_update_day = int(state.current_day)
		var land: Dictionary = state.management_assets[order.land_id]
		if not Presence.present(state,order.supplier_id,land.location_id): order.blocked_reason = "工匠不在场，等待到场"; continue
		if Workload.occupied_today(state,order.supplier_id,id,order.principal_id,"estate_construction"): order.blocked_reason = "工匠今日已有其他职责或施工"; continue
		if land.disputed: order.blocked_reason = "土地产权争议尚未解决"; continue
		if order.has("land_lease_id"):
			var lease: Dictionary=preload("res://scripts/core/land_lease_service.gd").current(state,land)
			if lease.is_empty() or not lease.allow_build or lease.lessee_ref!=order.owner_ref:order.blocked_reason="土地建设租约已到期或失效；已付费用与工程保留，请先接洽续约。";continue
		order.blocked_reason = ""
		Workload.record_work(state,order)
		if int(order.work_days) < int(order.recipe.duration_days): continue
		if state.management_assets.has(order.building_id): return Contract.fail("同一工程不能重复生成房屋")
		order.status = "completed"
		order["completed_day"] = int(state.current_day)
		state.management_assets[order.building_id] = {"asset_id":order.building_id,"asset_kind":"estate_building","industry_kind":order.recipe.industry_kind,"name":str(order.recipe.name),"location_id":land.location_id,"land_id":land.asset_id,"owner_ref":order.owner_ref.duplicate(true),"source_ref":{"entity_kind":"contract","entity_id":id},"status":"completed","rights":[],"contract_refs":[id],"area_units":int(order.recipe.area_units),"setup_offer":order.recipe.setup_offer.duplicate(true),"maintenance_offer":order.recipe.maintenance_offer.duplicate(true),"offer_visibility":"public"}
		if order.recipe.has("operation_terms"): state.management_assets[order.building_id]["operation_terms"]=order.recipe.operation_terms.duplicate(true)
		if order.recipe.has("manufacturing_terms"): state.management_assets[order.building_id]["manufacturing_terms"] = order.recipe.manufacturing_terms.duplicate(true)
		if order.recipe.has("agricultural_terms"): state.management_assets[order.building_id]["agricultural_terms"] = order.recipe.agricultural_terms.duplicate(true)
		state.management_assets[order.building_id]["geographic_scope_kind"] = land.get("geographic_scope_kind","city")
		if order.recipe.has("retail_terms"): state.management_assets[order.building_id]["retail_terms"] = order.recipe.retail_terms.duplicate(true)
		land.status = "developed"
	return {"ok":true}

static func validate(raw: Dictionary) -> Dictionary:
	var occupied := {}
	for land in raw.get("management_assets",{}).values():
		if land.get("asset_kind") != "land": continue
		for offer in land.development_offers.values():
			if offer is Dictionary and offer.has("operation_terms"):
				if not offer.get("site_requirements") is Array or offer.site_requirements.is_empty() or not offer.operation_terms is Dictionary or not preload("res://scripts/core/modeled_business_service.gd").validate_config(offer.operation_terms.get("config")).ok: return Contract.fail("分类产业报价缺少用地条件或有效经营配置")
			if not offer is Dictionary or (offer.get("industry_kind") not in INDUSTRIES and not offer.has("operation_terms")) or not Contract.amount(offer.get("area_units"),true) or not Contract.amount(offer.get("price"),true) or not Contract.amount(offer.get("duration_days"),true) or not Contract.amount(offer.get("version"),true) or not offer.get("inputs") is Array or offer.inputs.is_empty() or not raw.character_states.has(offer.get("supplier_id")) or raw.resource_accounts.get(offer.get("payee_account_id"),{}).get("owner_ref") != {"entity_kind":"character","entity_id":offer.get("supplier_id")}: return Contract.fail("建设目录缺少实际工匠、报价、占地或工期")
			var stocks := {}
			for input in offer.inputs:
				var stock: Dictionary = raw.management_assets.get(input.get("stock_id"),{})
				if stocks.has(input.get("stock_id")) or not Contract.amount(input.get("quantity"),true) or stock.get("asset_kind") != "material_stock" or stock.get("location_id") != land.location_id or stock.get("owner_ref") != {"entity_kind":"character","entity_id":offer.supplier_id}: return Contract.fail("建设材料重复或不属于供应方")
				stocks[input.stock_id] = true
			for finish in [offer.get("setup_offer",{}),offer.get("maintenance_offer",{})]:
				if not finish is Dictionary or not Contract.amount(finish.get("amount"),true) or finish.get("supplier_id") != offer.supplier_id or finish.get("payee_account_id") != offer.payee_account_id: return Contract.fail("竣工后筹办维护报价缺少来源")
	for order in raw.get("economic_contracts",{}).values():
		if order.get("contract_kind") != "estate_construction": continue
		var land: Dictionary = raw.management_assets.get(order.get("land_id",""),{})
		var lease: Dictionary=raw.economic_contracts.get(order.get("land_lease_id"),{})
		var land_owner: Dictionary=land.get("initial_owner_ref",{}).duplicate(true)
		var commissioned_revision: int=int(raw.action_receipts.get(order.get("commission_receipt"),{}).get("state_revision_after",2147483647))
		for sale_id in land.get("transfer_history",[]):
			var sale: Dictionary=raw.economic_contracts.get(sale_id,{})
			if int(raw.action_receipts.get(sale.get("receipt_id"),{}).get("state_revision_after",2147483647))<commissioned_revision:land_owner=sale.get("buyer_ref",{}).duplicate(true)
		var leased: bool=lease.get("contract_kind")=="land_lease" and lease.get("land_id")==land.get("asset_id") and lease.get("allow_build")==true and lease.get("lessee_ref")==order.get("owner_ref") and int(lease.get("from_day",2147483647))<=int(order.get("created_day",-1)) and int(lease.get("until_day",-1))>int(order.get("created_day",2147483647))
		if land.get("asset_kind") != "land" or not land.contract_refs.has(order.contract_id) or (order.get("owner_ref") != land_owner and not leased) or (order.has("land_lease_id") and not leased) or raw.resource_accounts.get(order.get("funding_account_id"),{}).get("owner_ref")!=order.get("owner_ref") or order.get("status") not in ["working","completed","cancelled"] or not order.get("recipe") is Dictionary or not order.get("work_log") is Array or not order.get("change_receipts") is Array: return Contract.fail("工程丢失实际土地、权利或工作记录")
		var recipe: Dictionary = order.recipe
		if recipe != land.development_offers.get(order.get("blueprint_id"),{}) or order.get("supplier_id") != recipe.get("supplier_id"): return Contract.fail("工程约定与来源报价不符")
		if not Contract.amount(order.get("work_days")) or int(order.work_days) != order.work_log.size() or int(order.work_days) > int(recipe.duration_days) or (order.status=="completed") != (int(order.work_days)==int(recipe.duration_days)): return Contract.fail("工程进度与实际工日不符")
		if raw.management_assets.get(order.get("building_id"),{}).get("status")!="demolished":occupied[land.asset_id] = int(occupied.get(land.asset_id,0))+int(recipe.area_units)
		var paid: Dictionary = raw.resource_journal.get(order.get("commission_receipt"),{})
		var receipt: Dictionary = raw.action_receipts.get(order.get("commission_receipt"),{})
		if paid.get("reason_ref") != order.contract_id or paid.get("amount") != recipe.price or paid.get("source_account_id") != order.get("funding_account_id") or paid.get("destination_account_id") != recipe.payee_account_id or not receipt.get("effect_refs",[]).has(order.contract_id): return Contract.fail("工程缺少实际付款回执")
		for input in recipe.inputs:
			if raw.management_assets.get(input.stock_id,{}).get("consumptions",{}).get(order.contract_id) != input.quantity: return Contract.fail("工程缺少实际出库材料")
		for ref in order.change_receipts:
			if not raw.action_receipts.get(ref,{}).get("effect_refs",[]).has(order.contract_id): return Contract.fail("工程停复工缺少回执")
		if (order.status=="completed") != raw.management_assets.has(order.get("building_id")): return Contract.fail("工程竣工与房屋不符")
	for asset in raw.get("management_assets",{}).values():
		if asset.get("asset_kind") == "land" and int(asset.used_area_units) != int(occupied.get(asset.asset_id,0))+preload("res://scripts/core/estate_lifecycle_service.gd").additional_area(raw,str(asset.asset_id)): return Contract.fail("土地占用与工程不符")
		if asset.get("asset_kind") != "estate_building": continue
		var order: Dictionary = raw.economic_contracts.get(asset.source_ref.get("entity_id"),{})
		if order.get("contract_kind") != "estate_construction" or order.get("status") != "completed" or order.get("building_id") != asset.asset_id or order.get("land_id") != asset.get("land_id") or load("res://scripts/core/estate_property_transaction_service.gd").owner_on_day(raw,asset,int(raw.current_day)) != asset.owner_ref or order.recipe.industry_kind != asset.get("industry_kind") or order.recipe.area_units != asset.get("area_units"): return Contract.fail("房屋缺少竣工与产权来源")
	return {"ok":true}
