extends RefCounted

const Contract = preload("res://scripts/core/management_state_contract.gd")
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const KINDS := ["rent_shop", "establish_owned_pawnshop", "establish_owned_retail", "establish_owned_manufacturing", "establish_owned_farm", "establish_owned_modeled", "prepare_pawnshop", "fund_pawnshop", "open_pawnshop", "close_pawnshop", "issue_pawn_loan", "redeem_pawn", "dispose_pawn"]

static func initialize(state, data: Dictionary) -> Dictionary:
	for definition in data.get("management", {}).get("initial_assets", []):
		if not definition is Dictionary or state.management_assets.has(definition.get("asset_id")) or not state.local_node_state.has(definition.get("location_id")):
			return Contract.fail("初始资产缺少地点或标识重复")
		if not definition.get("owner_ref") is Dictionary or definition.owner_ref.get("entity_kind") != "character" or not state.character_states.has(definition.owner_ref.get("entity_id")) or not definition.get("source_ref") is Dictionary:
			return Contract.fail("初始资产缺少实际所有人或来源")
		state.management_assets[definition.asset_id] = definition.duplicate(true)
	return {"ok": true}

static func location_for(state, kind: String, params: Dictionary) -> String:
	var id := str(params.get("building_id", "")) if kind in ["rent_shop","establish_owned_pawnshop","establish_owned_retail","establish_owned_manufacturing","establish_owned_farm","establish_owned_modeled"] else str(params.get("shop_id", ""))
	return str(state.management_assets.get(id, {}).get("location_id", ""))

static func cost_for(state, kind: String, params: Dictionary) -> Dictionary:
	if kind not in KINDS:
		return Contract.fail("未知经营动作")
	var asset_id := str(params.get("building_id", "")) if kind in ["rent_shop","establish_owned_pawnshop","establish_owned_retail","establish_owned_manufacturing","establish_owned_farm","establish_owned_modeled"] else str(params.get("shop_id", ""))
	var asset: Dictionary = state.management_assets.get(asset_id, {})
	if asset.is_empty():
		if kind in ["establish_owned_pawnshop","establish_owned_retail","establish_owned_manufacturing","establish_owned_farm","establish_owned_modeled"]:
			for order in state.economic_contracts.values():
				if order.get("contract_kind") == "estate_construction" and order.get("building_id") == asset_id and order.get("status") == "working":
					return {"ok":false,"code":"awaiting_delivery","error":"等待房屋竣工：" + (str(order.blocked_reason) if order.get("blocked_reason","")!="" else "工匠按约施工中")}
		return {"ok": false, "code": "asset_not_ready", "error": "尚无对应铺面或经营单位：" + asset_id}
	var account_id := str(params.get("funding_account_id", ""))
	var amount := 0
	if kind == "rent_shop":
		amount = int(asset.get("rental_offer", {}).get("amount", 0))
	elif kind == "prepare_pawnshop":
		amount = int(state.management_assets.get(asset.get("building_id", ""), {}).get("setup_offer", {}).get("amount", 0))
	elif kind == "fund_pawnshop":
		if not Contract.amount(params.get("amount"), true):
			return Contract.fail("营运资金须为正整数")
		amount = int(params.amount)
	elif kind == "issue_pawn_loan":
		var item: Dictionary = state.management_assets.get(params.get("collateral_id", ""), {})
		amount = int(item.get("pledge_offer", {}).get("principal", 0))
		account_id = str(asset.get("account_id", ""))
	if kind in ["rent_shop", "prepare_pawnshop", "fund_pawnshop", "issue_pawn_loan"] and (amount <= 0 or not state.resource_accounts.has(account_id)):
		return Contract.fail("经营动作缺少有效报价或资金来源")
	return {"ok": true, "account_id": account_id, "amount": amount}

static func apply(state, kind: String, params: Dictionary, principal: String, execution: String, reservation_id: String = "") -> Dictionary:
	if kind=="establish_owned_farm" and state.management_assets.get(params.get("building_id",""),{}).get("industry_kind") not in ["grain_estate","tea_garden"]: return Contract.fail("农产登记需要实际田庄或茶园工程")
	if kind in ["establish_owned_pawnshop","establish_owned_retail","establish_owned_manufacturing","establish_owned_farm","establish_owned_modeled"]: return _establish_owned(state,params,principal,str(state.management_assets.get(params.get("building_id",""),{}).get("industry_kind","")) if kind in ["establish_owned_farm","establish_owned_modeled"] else "smithy" if kind=="establish_owned_manufacturing" else "cloth_shop" if kind=="establish_owned_retail" else "pawnshop",execution)
	if kind == "rent_shop":
		return _rent(state, params, principal, execution, reservation_id)
	var shop: Dictionary = state.management_assets.get(params.get("shop_id", ""), {})
	if shop.get("asset_kind") not in ["pawnshop","retail_shop","manufacturing_shop","managed_farm","modeled_business"] or not _operator(state, str(shop.get("account_id", "")), principal):
		return Contract.fail("没有该当铺的经营权")
	if kind == "prepare_pawnshop":
		return _prepare(state, shop, params, principal, execution, reservation_id)
	if kind == "fund_pawnshop":
		return _pay(state, execution, str(params.get("funding_account_id", "")), shop.account_id, int(params.amount), principal, shop.asset_id, reservation_id)
	if kind == "open_pawnshop":
		var readiness := _ready_to_trade(state, shop)
		if not readiness.get("ok", false):
			return readiness
		if Accounts.new().available(state, shop.account_id) <= 0:
			return Contract.fail("当铺尚无可用营运资金")
		shop.status = "open"
		if int(shop.opened_day) < 0:
			shop.opened_day = int(state.current_day)
			var offer: Dictionary = state.management_assets[shop.building_id].maintenance_offer
			var id := "maintenance:" + str(shop.asset_id)
			state.economic_contracts[id] = {"contract_id": id, "contract_kind": "maintenance", "party_refs": [shop.owner_ref.entity_id, offer.supplier_id], "terms_version": 1, "status": "active", "execution_refs": [], "shop_id": shop.asset_id, "supplier_id": offer.supplier_id, "funding_account_id": shop.account_id, "payee_account_id": offer.payee_account_id, "amount": int(offer.amount), "period_days": int(offer.period_days), "next_due_day": int(state.current_day) + int(offer.period_days), "arrears": 0}
			shop.contract_refs.append(id)
		return {"ok": true, "result_ref": shop.asset_id}
	if kind == "close_pawnshop":
		shop.status = "closed"
		return {"ok": true, "result_ref": shop.asset_id}
	if kind in ["issue_pawn_loan","redeem_pawn","dispose_pawn"] and shop.asset_kind!="pawnshop": return Contract.fail("零售产业不能办理抵押借贷")
	if kind == "issue_pawn_loan":
		return _lend(state, shop, params, principal, execution, reservation_id)
	if kind == "redeem_pawn":
		return _redeem(state, shop, params, execution)
	if kind == "dispose_pawn":
		return _dispose(state, shop, params, principal, execution)
	return Contract.fail("经营动作尚无规则")

static func _establish_owned(state, params: Dictionary, principal: String, industry: String = "pawnshop", execution: String = "") -> Dictionary:
	var building: Dictionary = state.management_assets.get(params.get("building_id",""),{})
	var source := str(params.get("funding_account_id",""))
	var office: Dictionary = state.office_state.get(params.get("office_id",""),{})
	var id := str(params.get("shop_id",""))
	if building.get("asset_kind") != "estate_building" or building.get("industry_kind") != industry or building.get("status") != "completed" or id.is_empty() or state.management_assets.has(id): return Contract.fail("需要已竣工、尚未开办产业的自有当铺房屋")
	var right: Dictionary=state.economic_contracts.get(params.get("operating_right_id"),{})
	var licensed: bool=not right.is_empty()
	if params.has("operating_right_id") and not licensed:return Contract.fail("经营权引用已失效，不能当成房产所有权")
	if licensed and (right.get("contract_kind")!="estate_operating_right" or right.get("status")!="active" or right.get("building_id")!=building.asset_id or right.get("operating_shop_id","")!="" or int(right.get("until_day",-1))<=int(state.current_day) or right.get("operator_ref")!=state.resource_accounts.get(source,{}).get("owner_ref")):return Contract.fail("须有尚未重复使用的真实经营权及同一经营资金主体")
	if not _operator(state,source,principal) or (not licensed and state.resource_accounts[source].owner_ref != building.owner_ref): return Contract.fail("没有该房产与筹办资金的共同经办权")
	var owner: Dictionary = right.operator_ref if licensed else building.owner_ref
	var new_office := params.has("office_template_id")
	if new_office:
		var drafted: Dictionary = load("res://scripts/core/business_manager_office.gd").draft(state,str(params.office_template_id),id,source,params.get("wage_amount"))
		if not drafted.ok: return drafted
		if drafted.office.office_id!=params.get("office_id") or execution.is_empty(): return Contract.fail("产业岗位标识或实际设立动作不符")
		office=drafted.office
	if office.get("role_key") != "shopkeeper" or office.get("organization_id") != owner.entity_id or office.get("scope_ref",{}).get("entity_id") != building.location_id: return Contract.fail("需要本家在当地的真实掌柜职位")
	if state.management_assets.values().any(func(asset):return asset.get("asset_kind") in ["pawnshop","retail_shop","manufacturing_shop","managed_farm","modeled_business"] and asset.get("office_id")==office.office_id): return Contract.fail("掌柜职位已有其他产业归属，请使用本产业独立岗位")
	var account := id+"_cash"
	var depot := "business:"+id
	if state.resource_accounts.has(account) or state.depot_states.has(depot): return Contract.fail("经营账户标识已经存在")
	state.depot_states[depot] = {"depot_id":depot,"location_node_id":building.location_id,"owner_organization_id":owner.entity_id if owner.entity_kind!="character" else "","owner_character_id":owner.entity_id if owner.entity_kind=="character" else "","capacity":Contract.MAX_AMOUNT,"stock":{"silk_cash":0}}
	state.resource_accounts[account] = {"account_id":account,"owner_ref":owner.duplicate(true),"resource_key":"silk_cash","unit_id":"cash_unit","storage_ref":{"storage_kind":"depot","storage_id":depot,"resource_key":"silk_cash"},"operator_refs":state.resource_accounts[source].operator_refs.duplicate(true)}
	state.management_assets[id] = {"asset_id":id,"asset_kind":"pawnshop","name":"自有当铺","owner_ref":owner.duplicate(true),"location_id":building.location_id,"status":"preparing","source_ref":building.source_ref.duplicate(true),"rights":[],"contract_refs":building.contract_refs.duplicate(),"building_id":building.asset_id,"office_id":office.office_id,"account_id":account,"premises_kind":"owned","lease_id":"","setup_contract_id":"","opened_day":-1}
	if industry=="cloth_shop":
		state.management_assets[id].asset_kind = "retail_shop"
		state.management_assets[id].name = "自有布庄"
		state.management_assets[id]["industry_kind"] = industry
		state.management_assets[id]["retail_terms"] = building.retail_terms.duplicate(true)
		state.management_assets[id]["stock_lots"] = {}
	if industry=="smithy":
		state.management_assets[id].asset_kind = "manufacturing_shop"
		state.management_assets[id].name = "自有铁匠铺"
		state.management_assets[id]["industry_kind"] = industry
		state.management_assets[id]["manufacturing_terms"] = building.manufacturing_terms.duplicate(true)
		state.management_assets[id]["stock_lots"] = {}
	if industry in ["grain_estate","tea_garden"]:
		var farm: Dictionary = state.management_assets[id]
		farm.asset_kind = "managed_farm"
		farm.name = "自有茶园" if industry=="tea_garden" else "自有粮食田庄"
		farm["industry_kind"] = industry
		farm["geographic_scope_kind"] = "prefecture"
		farm["agricultural_terms"] = building.agricultural_terms.duplicate(true)
		farm["stock_lots"] = {}
		var products = preload("res://scripts/core/resource_commodity_definitions.gd")
		var product: String = products.agricultural_resource(farm.agricultural_terms.good_id)
		farm["product_account_id"] = id+"_product"
		state.depot_states[depot].stock[product] = 0
		state.resource_accounts[farm.product_account_id] = {"account_id":farm.product_account_id,"owner_ref":owner.duplicate(true),"resource_key":product,"unit_id":products.agricultural_unit(farm.agricultural_terms.good_id),"storage_ref":{"storage_kind":"depot","storage_id":depot,"resource_key":product},"operator_refs":state.resource_accounts[source].operator_refs.duplicate(true)}
	if building.has("operation_terms"):
		state.management_assets[id].asset_kind="modeled_business"
		state.management_assets[id].name=str(building.name)
		state.management_assets[id]["industry_kind"]=industry
		state.management_assets[id]["operation_terms"]=building.operation_terms.duplicate(true)
	var office_proof := {}
	if new_office:
		office.name=state.management_assets[id].name+"掌柜"; office.display_name=office.name
		office["created_by"]=execution
		state.office_state[office.office_id]=office
		office_proof={"office_id":office.office_id,"shop_id":id,"template_office_id":params.office_template_id,"definition":office.duplicate(true)}
	building.status = "in_use"
	if licensed:
		state.management_assets[id]["premises_kind"]="operating_right"
		state.management_assets[id]["operating_right_id"]=right.contract_id
		right.operating_shop_id=id;state.management_assets[id].contract_refs.append(right.contract_id)
	var result := {"ok":true,"result_ref":id,"visible_summary":"已登记自有房屋经营；仍须安排掌柜、设施与本钱"}
	if new_office: result["business_office_creation"]=office_proof
	return result

static func _rent(state, params: Dictionary, principal: String, execution: String, reservation: String) -> Dictionary:
	var building: Dictionary = state.management_assets.get(params.get("building_id", ""), {})
	var source := str(params.get("funding_account_id", ""))
	var office: Dictionary = state.office_state.get(params.get("office_id", ""), {})
	var shop_id := str(params.get("shop_id", ""))
	if building.get("asset_kind") != "building" or building.get("status") != "available" or shop_id.is_empty() or state.management_assets.has(shop_id):
		return Contract.fail("铺面不可出租或经营标识已存在")
	if not _operator(state, source, principal) or state.resource_accounts[source].owner_ref.get("entity_kind") not in ["clan", "household"]:
		return Contract.fail("租铺须使用本人有权经办的家族账户")
	var owner: Dictionary = state.resource_accounts[source].owner_ref
	var offer: Dictionary = building.get("rental_offer", {})
	if not offer.get("organization_ids", []).has(owner.entity_id) or int(offer.get("valid_until_day", -1)) < int(state.current_day) or building.owner_ref.entity_id != offer.get("landlord_id") or not _living_here(state, str(offer.get("landlord_id", "")), building.location_id):
		return Contract.fail("出租人未同意本次租用或报价已失效")
	if office.get("role_key") != "shopkeeper" or office.get("organization_id") != owner.entity_id or office.get("scope_ref", {}).get("entity_id") != building.location_id:
		return Contract.fail("缺少本家在当地的掌柜职位")
	if state.management_assets.values().any(func(asset): return asset.get("asset_kind") in ["pawnshop","retail_shop","manufacturing_shop","managed_farm","modeled_business"] and asset.get("office_id") == office.office_id and asset.get("status") != "closed"):
		return Contract.fail("该掌柜职位已负责另一处营业或筹办中的店铺")
	var account_id := shop_id + "_cash"
	var depot_id := "business:" + shop_id
	if state.resource_accounts.has(account_id) or state.depot_states.has(depot_id):
		return Contract.fail("经营账户标识已存在")
	var lease_id := "lease:" + execution
	var paid := _pay(state, execution, source, str(offer.payee_account_id), int(offer.amount), principal, lease_id, reservation)
	if not paid.get("ok", false):
		return paid
	var lease := {"contract_id": lease_id, "contract_kind": "lease", "party_refs": [owner.entity_id, offer.landlord_id], "terms_version": 1, "status": "active", "execution_refs": [execution], "building_id": building.asset_id, "shop_id": shop_id, "tenant_ref": owner.duplicate(true), "landlord_id": offer.landlord_id, "funding_account_id": source, "payee_account_id": offer.payee_account_id, "amount": int(offer.amount), "period_days": int(offer.period_days), "next_due_day": int(state.current_day) + int(offer.period_days), "arrears": 0}
	state.economic_contracts[lease_id] = lease
	building.status = "rented"
	building.contract_refs.append(lease_id)
	building.rights.append({"right_kind": "lease", "holder_ref": owner.duplicate(true), "contract_id": lease_id})
	state.depot_states[depot_id] = {"depot_id": depot_id, "location_node_id": building.location_id, "owner_organization_id": owner.entity_id if owner.entity_kind!="character" else "", "owner_character_id": owner.entity_id if owner.entity_kind=="character" else "", "capacity": Contract.MAX_AMOUNT, "stock": {"silk_cash": 0}}
	state.resource_accounts[account_id] = {"account_id": account_id, "owner_ref": owner.duplicate(true), "resource_key": "silk_cash", "unit_id": "cash_unit", "storage_ref": {"storage_kind": "depot", "storage_id": depot_id, "resource_key": "silk_cash"}, "operator_refs": state.resource_accounts[source].operator_refs.duplicate(true)}
	state.management_assets[shop_id] = {"asset_id": shop_id, "asset_kind": "pawnshop", "name": "市集当铺", "owner_ref": owner.duplicate(true), "location_id": building.location_id, "status": "preparing", "source_ref": {"entity_kind": "contract", "entity_id": lease_id}, "rights": [], "contract_refs": [lease_id], "building_id": building.asset_id, "office_id": office.office_id, "account_id": account_id, "lease_id": lease_id, "setup_contract_id": "", "opened_day": -1}
	return {"ok": true, "result_ref": shop_id, "journal_refs": [execution]}

static func _prepare(state, shop: Dictionary, params: Dictionary, principal: String, execution: String, reservation: String) -> Dictionary:
	if shop.get("setup_contract_id", "") != "":
		return Contract.fail("已有整理合同，请等待交付或处理原合同")
	var building: Dictionary = state.management_assets[shop.building_id]
	var offer: Dictionary = building.setup_offer
	if not _living_here(state, offer.supplier_id, shop.location_id):
		return Contract.fail("供应方不在当地或无法履约")
	if not preload("res://scripts/core/character_workload_service.gd").can_schedule(state, offer.supplier_id, "setup", principal): return Contract.fail("供应方现有任职没有可用整理工日，须先安排交接")
	if state.economic_contracts.values().any(func(c): return c.get("contract_kind") == "setup" and c.get("supplier_id") == offer.supplier_id and c.get("status") == "working"):
		return Contract.fail("供应方正在履行另一份整理合同")
	var id := "setup:" + execution
	var paid := _pay(state, execution, str(params.get("funding_account_id", "")), offer.payee_account_id, int(offer.amount), principal, id, reservation)
	if not paid.get("ok", false):
		return paid
	state.economic_contracts[id] = {"contract_id": id, "contract_kind": "setup", "party_refs": [shop.owner_ref.entity_id, offer.supplier_id], "terms_version": 1, "status": "working", "execution_refs": [execution], "shop_id": shop.asset_id, "supplier_id": offer.supplier_id, "description": offer.description, "amount": int(offer.amount), "due_day": int(state.current_day) + int(offer.duration_days)}
	state.economic_contracts[id].merge({"created_day": int(state.current_day), "duration_days": int(offer.duration_days), "work_days": 0, "last_work_day": int(state.current_day), "work_log": [], "blocked_reason": ""})
	shop.setup_contract_id = id
	shop.contract_refs.append(id)
	return {"ok": true, "result_ref": id, "journal_refs": [execution]}

static func _ready_to_trade(state, shop: Dictionary) -> Dictionary:
	if shop.get("premises_kind")=="retired":return Contract.fail("原经营场所已交割；旧店资金与合同保留，不能继续在该处开业")
	if state.management_assets.get(shop.get("building_id"),{}).get("status")=="demolished":return Contract.fail("原设施已拆除；土地和账目保留，请从土地重新筹建")
	if not preload("res://scripts/core/estate_lifecycle_service.gd").working(state,str(shop.get("building_id",""))).is_empty():return Contract.fail("设施扩建施工中，请待竣工后重新开业")
	var lease: Dictionary = state.economic_contracts.get(shop.lease_id, {})
	var setup: Dictionary = state.economic_contracts.get(shop.setup_contract_id, {})
	var owned: bool = shop.get("premises_kind","") == "owned"
	var licensed: bool=shop.get("premises_kind")=="operating_right"
	if licensed and not load("res://scripts/core/estate_property_transaction_service.gd").operating_access(state,shop):return Contract.fail("经营权或场所使用期已失效；原资金、历史与工资义务保留")
	if owned and state.management_assets.get(shop.building_id,{}).get("owner_ref") != shop.owner_ref: return Contract.fail("自有房屋产权已经变化")
	if owned and not preload("res://scripts/core/land_lease_service.gd").building_access(state,state.management_assets.get(shop.building_id,{})):return Contract.fail("土地使用租约已到期或失效，请先处理场所权利；房屋与原义务保留。")
	if not owned and not licensed and (lease.get("status") != "active" or int(lease.get("arrears", 0)) > 0):
		return Contract.fail("铺面租约无效或租金欠付")
	if setup.get("status") != "delivered":
		return {"ok": false, "code": "awaiting_delivery" if setup.get("status") == "working" and setup.get("blocked_reason", "") == "" else "setup_unavailable", "error": str(setup.blocked_reason) if setup.get("blocked_reason", "") != "" else "柜台与保管设施尚未交付"}
	return preload("res://scripts/core/business_staff_service.gd").resolve(state,shop)

static func _lend(state, shop: Dictionary, params: Dictionary, principal: String, execution: String, reservation: String) -> Dictionary:
	var ready := _ready_to_trade(state, shop)
	if shop.status != "open" or not ready.get("ok", false):
		return Contract.fail("当铺未营业：" + str(ready.get("error", "请先开业")))
	var item: Dictionary = state.management_assets.get(params.get("collateral_id", ""), {})
	var borrower := str(params.get("borrower_id", ""))
	var offer: Dictionary = item.get("pledge_offer", {})
	if item.get("asset_kind") != "movable" or item.get("status") != "available" or item.get("lien_contract_id", "") != "" or item.get("owner_ref", {}).get("entity_id") != borrower or item.get("custodian_ref", {}).get("entity_id") != borrower:
		return Contract.fail("抵押物并非借款人可自由处分的实物")
	if not _living_here(state, borrower, shop.location_id) or item.get("location_id") != shop.location_id or offer.get("borrower_id") != borrower or not offer.get("organization_ids", []).has(shop.owner_ref.entity_id):
		return Contract.fail("借款人未同意该当铺条件或钱物未到场")
	if int(item.get("condition", 0)) < 60 or int(offer.get("valuation", 0)) < int(offer.get("principal", 0)) + int(offer.get("fee", 0)):
		return Contract.fail("抵押物状况或估值不足以支持该借款")
	var id := "loan:" + execution
	var paid := _pay(state, execution, shop.account_id, offer.borrower_account_id, int(offer.principal), principal, id, reservation)
	if not paid.get("ok", false):
		return paid
	state.economic_contracts[id] = {"contract_id": id, "contract_kind": "pawn_loan", "party_refs": [shop.owner_ref.entity_id, borrower], "terms_version": 1, "status": "outstanding", "execution_refs": [execution], "shop_id": shop.asset_id, "lender_account_id": shop.account_id, "borrower_id": borrower, "borrower_account_id": offer.borrower_account_id, "collateral_id": item.asset_id, "principal": int(offer.principal), "fee": int(offer.fee), "due_day": int(state.current_day) + int(offer.duration_days), "disposal_day": int(state.current_day) + int(offer.duration_days) + int(offer.disposal_grace_days), "valuation": int(offer.valuation), "valuation_basis": offer.valuation_basis, "custody_location_id": shop.location_id, "allow_redemption_collection": offer.allow_redemption_collection, "recourse": offer.recourse, "principal_repaid": 0, "fee_received": 0, "principal_written_off": 0, "fee_written_off": 0, "remaining_debt": int(offer.principal) + int(offer.fee), "surplus_returned": 0}
	item.status = "pledged"
	if item.has("equipped_by"): item.equipped_by = ""
	item.custodian_ref = {"entity_kind": "asset", "entity_id": shop.asset_id}
	item.lien_contract_id = id
	item.contract_refs.append(id)
	shop.contract_refs.append(id)
	return {"ok": true, "result_ref": id, "journal_refs": [execution]}

static func _redeem(state, shop: Dictionary, params: Dictionary, execution: String) -> Dictionary:
	var loan: Dictionary = state.economic_contracts.get(params.get("loan_id", ""), {})
	if loan.get("contract_kind") != "pawn_loan" or loan.get("shop_id") != shop.asset_id or loan.get("status") not in ["outstanding", "overdue"] or not loan.get("allow_redemption_collection", false):
		return Contract.fail("没有可依约收款赎回的借据")
	var item: Dictionary = state.management_assets[loan.collateral_id]
	if not _living_here(state, loan.borrower_id, shop.location_id) or item.get("condition", 0) <= 0:
		return Contract.fail("借款人未到场或抵押物损毁待处理")
	var paid := _pay(state, execution, loan.borrower_account_id, loan.lender_account_id, int(loan.remaining_debt), loan.borrower_id, loan.contract_id)
	if not paid.get("ok", false):
		return paid
	return finish_redemption(state, loan, execution)

static func finish_redemption(state, loan: Dictionary, execution: String) -> Dictionary:
	var journal: Dictionary = state.resource_journal.get(execution, {})
	if loan.get("status") not in ["outstanding", "overdue"] or journal.get("source_account_id") != loan.get("borrower_account_id") or journal.get("destination_account_id") != loan.get("lender_account_id") or journal.get("reason_ref") != loan.get("contract_id") or int(journal.get("amount", -1)) != int(loan.get("remaining_debt", 0)):
		return Contract.fail("赎回必须先有同借据全额实际还款")
	var item: Dictionary = state.management_assets[loan.collateral_id]
	loan.execution_refs.append(execution)
	loan.status = "redeemed"
	loan.principal_repaid = int(loan.principal)
	loan.fee_received = int(loan.fee)
	loan.remaining_debt = 0
	item.status = "available"
	item.lien_contract_id = ""
	item.custodian_ref = item.owner_ref.duplicate(true)
	item.erase("pledge_offer")
	return {"ok": true, "result_ref": loan.contract_id, "journal_refs": [execution]}

static func _dispose(state, shop: Dictionary, params: Dictionary, principal: String, execution: String) -> Dictionary:
	var loan: Dictionary = state.economic_contracts.get(params.get("loan_id", ""), {})
	if loan.get("contract_kind") != "pawn_loan" or loan.get("shop_id") != shop.asset_id or loan.get("status") != "overdue" or int(state.current_day) < int(loan.disposal_day):
		return Contract.fail("借据尚未到约定处置阶段")
	var item: Dictionary = state.management_assets[loan.collateral_id]
	var offer: Dictionary = item.get("purchase_offer", {})
	if not _living_here(state, str(offer.get("buyer_id", "")), shop.location_id) or int(offer.get("valid_until_day", -1)) < int(state.current_day) or int(item.get("condition", 0)) < int(offer.get("minimum_condition", 101)):
		return Contract.fail("没有到场且接受当前物况的实际买方")
	var price := int(offer.get("price", 0))
	if price <= 0:
		return Contract.fail("买方未提出有效价格")
	var due := int(loan.remaining_debt)
	var retained: int = mini(price, due)
	var surplus: int = maxi(0, price - due)
	if offer.buyer_id == loan.borrower_id or Accounts.new().available(state, offer.account_id) < price or Accounts.new().balance(state, shop.account_id) > Contract.MAX_AMOUNT - retained or Accounts.new().balance(state, loan.borrower_account_id) > Contract.MAX_AMOUNT - surplus:
		return Contract.fail("买方实际可用款不足或借款人收款超限")
	var paid := _pay(state, execution, offer.account_id, shop.account_id, retained, offer.buyer_id, loan.contract_id)
	if not paid.get("ok", false):
		return paid
	var receipts: Array = [execution]
	if surplus > 0:
		var returned := _pay(state, execution + ":surplus", offer.account_id, loan.borrower_account_id, surplus, offer.buyer_id, loan.contract_id)
		if not returned.get("ok", false):
			return returned
		receipts.append(execution + ":surplus")
	loan.execution_refs.append_array(receipts)
	loan.principal_repaid = mini(retained, int(loan.principal))
	loan.fee_received = maxi(0, retained - int(loan.principal))
	loan.surplus_returned = surplus
	loan.remaining_debt = due - retained if loan.recourse else 0
	loan.principal_written_off = int(loan.principal) - int(loan.principal_repaid) if not loan.recourse else 0
	loan.fee_written_off = int(loan.fee) - int(loan.fee_received) if not loan.recourse else 0
	loan.status = "disposed_with_debt" if int(loan.remaining_debt) > 0 else "disposed"
	var former: Dictionary = item.owner_ref.duplicate(true)
	item.owner_ref = {"entity_kind": "character", "entity_id": offer.buyer_id}
	item.custodian_ref = item.owner_ref.duplicate(true)
	var history: Array = item.get("transfer_history", []).duplicate(true)
	history.append({"execution_id": execution, "from_ref": former, "to_ref": item.owner_ref.duplicate(true), "day": int(state.current_day), "consent_rule": "pawn_default_sale", "contract_id": loan.contract_id})
	item["transfer_history"] = history
	if former.entity_id == state.player_character_id:
		state.inventory = state.inventory.filter(func(ref): return ref.get("id") != item.asset_id)
	if offer.buyer_id == state.player_character_id:
		state.inventory.append({"id": item.asset_id, "asset_ref": item.asset_id})
	item.status = "available"
	item.lien_contract_id = ""
	item.erase("purchase_offer")
	item.erase("pledge_offer")
	return {"ok": true, "result_ref": loan.contract_id, "journal_refs": receipts}

static func settle_daily(state) -> Dictionary:
	for contract in state.economic_contracts.values():
		if contract.get("contract_kind") == "setup" and contract.status == "working" and int(state.current_day) > int(contract.last_work_day):
			var shop: Dictionary = state.management_assets[contract.shop_id]
			if _living_here(state, contract.supplier_id, shop.location_id):
				if preload("res://scripts/core/character_workload_service.gd").occupied_today(state, contract.supplier_id, contract.contract_id):
					contract.blocked_reason = "工匠今日有任职或其他工序占用；等待空闲工日，已付款保留。"
					continue
				contract.blocked_reason = ""
				preload("res://scripts/core/character_workload_service.gd").record_work(state, contract)
				contract.due_day = int(state.current_day) + maxi(0, int(contract.duration_days) - int(contract.work_days))
				if int(contract.work_days) >= int(contract.duration_days): contract.status = "delivered"
			else:
				contract["blocked_reason"] = "供应方离开或无法履约；已付款保留，待协商退款或接手"
		elif contract.get("contract_kind") == "pawn_loan" and contract.status == "outstanding" and int(state.current_day) > int(contract.due_day):
			contract.status = "overdue"
		elif contract.get("contract_kind") in ["lease", "maintenance"] and contract.status == "active":
			while int(state.current_day) >= int(contract.next_due_day):
				var account: Dictionary = state.resource_accounts[contract.funding_account_id]
				var operator := str(account.operator_refs[0].entity_id) if not account.operator_refs.is_empty() else ""
				var id := "periodic:%s:%d" % [contract.contract_id, int(contract.next_due_day)]
				var paid := _pay(state, id, contract.funding_account_id, contract.payee_account_id, int(contract.amount), operator, contract.contract_id)
				if not paid.get("ok", false):
					contract.arrears = int(contract.amount) * (1 + (int(state.current_day) - int(contract.next_due_day)) / int(contract.period_days))
					break
				contract.execution_refs.append(id)
				contract.next_due_day += int(contract.period_days)
				contract.arrears = 0
	return {"ok": true}

static func project(state, shop_id: String) -> Dictionary:
	var shop: Dictionary = state.management_assets.get(shop_id, {})
	if shop.get("asset_kind") != "pawnshop":
		return {}
	var expenses := 0
	var revenue := 0
	var principal_outstanding := 0
	var bad_debt := 0
	for contract in state.economic_contracts.values():
		if contract.get("shop_id") == shop_id:
			if contract.contract_kind in ["lease", "setup", "maintenance"]:
				for receipt in contract.execution_refs:
					expenses += int(state.resource_journal[receipt].amount)
			elif contract.contract_kind == "pawn_loan":
				revenue += int(contract.fee_received)
				bad_debt += int(contract.principal_written_off)
				principal_outstanding += int(contract.principal) - int(contract.principal_repaid) - int(contract.principal_written_off)
		if contract.get("contract_kind") == "employment" and (contract.get("office_id") == shop.office_id or contract.get("shop_id") == shop_id):
			for receipt in contract.execution_refs:
				expenses += int(state.resource_journal[receipt].amount)
	return {"shop_id": shop_id, "name": shop.name, "status": shop.status, "cash": Accounts.new().balance(state, shop.account_id), "expenses": expenses, "realized_interest": revenue, "principal_outstanding": principal_outstanding, "bad_debt": bad_debt, "realized_profit": revenue - expenses - bad_debt, "office_id": shop.office_id, "manager_id": state.office_state[shop.office_id].holder_id, "contract_refs": shop.contract_refs.duplicate(true)}

static func _pay(state, execution: String, source: String, destination: String, amount: int, actor: String, reason: String, reservation: String = "") -> Dictionary:
	return Accounts.new().apply(state, "transfer", {"execution_id": execution, "source_account_id": source, "destination_account_id": destination, "amount": amount, "actor_id": actor, "reason_ref": reason, "reservation_id": reservation})

static func _operator(state, account_id: String, actor: String) -> bool:
	return state.resource_accounts.has(account_id) and state.resource_accounts[account_id].operator_refs.any(func(ref): return ref.get("entity_kind") == "character" and ref.get("entity_id") == actor)

static func _living_here(state, actor: String, location: String) -> bool:
	var character: Dictionary = state.character_states.get(actor, {})
	return not character.is_empty() and character.get("status") not in ["dead", "executed", "departed", "exiled"] and str(character.get("location_id", "")).trim_suffix("_node") == location.trim_suffix("_node")
