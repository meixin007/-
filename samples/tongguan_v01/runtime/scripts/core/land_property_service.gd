extends RefCounted
const Contract = preload("res://scripts/core/management_state_contract.gd")
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const KINDS := ["buy_land","offer_land","withdraw_land_offer","offer_land_lease","lease_land","end_land_lease","offer_land_share","approve_land_share_offer","buy_land_share"]

static func authority(state, asset: Dictionary, actor: String) -> bool:
	if asset.get("owner_ref") == {"entity_kind":"character","entity_id":actor}: return true
	for account in state.resource_accounts.values():
		if account.owner_ref == asset.get("owner_ref") and Accounts.new().can_operate(state,account.account_id,actor): return true
	return false

static func cost_for(state, kind: String, params: Dictionary) -> Dictionary:
	if kind in preload("res://scripts/core/land_coownership_service.gd").KINDS:return preload("res://scripts/core/land_coownership_service.gd").cost_for(state,kind,params)
	if kind in preload("res://scripts/core/land_lease_service.gd").KINDS:return preload("res://scripts/core/land_lease_service.gd").cost_for(state,kind,params)
	var land: Dictionary = state.management_assets.get(params.get("land_id",""),{})
	if kind not in KINDS or land.get("asset_kind") != "land": return Contract.fail("未找到可办理的土地")
	if kind == "buy_land":
		var quote: Dictionary = land.get("sale_offer",{})
		if not quote.get("active",false) or not quote.get("seller_consent",false) or params.get("quote_version") != quote.get("version") or int(quote.get("valid_until_day",-1)) < int(state.current_day): return Contract.fail("报价已失效或卖方尚未同意，请重新接洽")
		if not Contract.amount(quote.get("amount"),true) or not state.resource_accounts.has(params.get("funding_account_id")): return Contract.fail("缺少明确价款或付款账户")
		return {"ok":true,"account_id":params.funding_account_id,"amount":int(quote.amount)}
	if kind == "offer_land":
		if not Contract.amount(params.get("amount"),true) or not Contract.amount(params.get("valid_until_day")) or int(params.valid_until_day) < int(state.current_day) or not state.resource_accounts.has(params.get("payee_account_id")): return Contract.fail("出售须填写有效价格、期限和收款账户")
	return {"ok":true,"account_id":"","amount":0}

static func apply(state, kind: String, params: Dictionary, principal: String, execution: String, reservation: String = "") -> Dictionary:
	if kind in preload("res://scripts/core/land_coownership_service.gd").KINDS:return preload("res://scripts/core/land_coownership_service.gd").apply(state,kind,params,principal,execution,reservation)
	if kind in preload("res://scripts/core/land_lease_service.gd").KINDS:return preload("res://scripts/core/land_lease_service.gd").apply(state,kind,params,principal,execution,reservation)
	var checked := cost_for(state,kind,params)
	if not checked.ok: return checked
	var land: Dictionary = state.management_assets[params.land_id]
	var unknown_rights: bool=land.rights.any(func(right):return not right is Dictionary or right.get("right_kind")!="land_lease")
	if land.get("disputed",false) or not str(land.get("lien_contract_id","")).is_empty() or unknown_rights or not preload("res://scripts/core/land_lease_service.gd").current(state,land).is_empty() or int(land.get("used_area_units",0)) > 0: return Contract.fail("土地存在争议、抵押、使用权或在建占用，须先处理相关负担")
	if kind != "buy_land":
		if not authority(state,land,principal): return Contract.fail("没有这块土地的处分权")
		var version := int(land.get("sale_offer",{}).get("version",0))+1
		if kind == "withdraw_land_offer": land.sale_offer = {"active":false,"version":version}
		else:
			if state.resource_accounts[params.payee_account_id].owner_ref != land.owner_ref: return Contract.fail("卖方收款账户必须归属产权主体")
			land.sale_offer = {"active":true,"seller_consent":true,"seller_ref":land.owner_ref.duplicate(true),"amount":int(params.amount),"payee_account_id":params.payee_account_id,"valid_until_day":int(params.valid_until_day),"version":version,"consent_receipt":execution}
		return {"ok":true,"result_ref":land.asset_id,"visible_summary":"土地报价已更新"}
	var quote: Dictionary = land.sale_offer.duplicate(true)
	var buyer: Dictionary = state.resource_accounts[params.funding_account_id]
	if buyer.unit_id != "cash_unit" or buyer.owner_ref == land.owner_ref or not Accounts.new().can_operate(state,params.funding_account_id,principal): return Contract.fail("付款主体无权购买或已经拥有此地")
	var seller: Dictionary = state.resource_accounts.get(quote.get("payee_account_id",""),{})
	if quote.get("seller_ref") != land.owner_ref or seller.get("owner_ref") != land.owner_ref or seller.get("unit_id") != "cash_unit": return Contract.fail("产权或卖方收款主体已经变化")
	var id := "land-sale:"+execution
	if state.economic_contracts.has(id): return Contract.fail("交割合同已存在")
	var paid := Accounts.new().apply(state,"transfer",{"execution_id":execution,"source_account_id":params.funding_account_id,"destination_account_id":quote.payee_account_id,"amount":int(quote.amount),"actor_id":principal,"reason_ref":id,"reservation_id":reservation})
	if not paid.ok: return paid
	var former: Dictionary = land.owner_ref.duplicate(true)
	land.owner_ref = buyer.owner_ref.duplicate(true)
	if land.has("ownership_shares"):land.ownership_shares=[{"owner_ref":land.owner_ref.duplicate(true),"share_units":100}]
	land.sale_offer = {"active":false,"version":int(quote.version)+1}
	if land.has("lease_offer"):land.lease_offer={"active":false,"version":int(land.lease_offer.get("version",0))+1}
	land.contract_refs.append(id)
	land.transfer_history.append(id)
	state.economic_contracts[id] = {"contract_id":id,"contract_kind":"land_sale","status":"settled","terms_version":1,"land_id":land.asset_id,"seller_ref":former,"buyer_ref":land.owner_ref.duplicate(true),"funding_account_id":params.funding_account_id,"payee_account_id":quote.payee_account_id,"quote":quote,"amount":int(quote.amount),"party_refs":[former.entity_id,land.owner_ref.entity_id],"execution_refs":[execution],"created_day":int(state.current_day),"receipt_id":execution}
	return {"ok":true,"result_ref":id,"journal_refs":[execution],"visible_summary":"土地已交割："+str(land.name)}

static func validate(raw: Dictionary) -> Dictionary:
	for land in raw.get("management_assets",{}).values():
		if land.get("asset_kind") != "land": continue
		if not Contract.amount(land.get("area_units"),true) or not Contract.amount(land.get("used_area_units")) or land.used_area_units > land.area_units or not land.get("initial_owner_ref") is Dictionary or not land.get("transfer_history") is Array or not land.get("sale_offer") is Dictionary or not land.get("development_offers") is Dictionary or not land.get("disputed") is bool or not land.get("lien_contract_id") is String: return Contract.fail("土地面积、权利或来源不完整")
		var history: Dictionary=preload("res://scripts/core/land_coownership_service.gd").validate_history(raw,land)
		if not history.ok:return history
		var quote: Dictionary = land.sale_offer
		if not Contract.amount(quote.get("version"),true) or not quote.get("active") is bool: return Contract.fail("土地报价版本丢失")
		if quote.active:
			if quote.get("seller_consent") != true or quote.get("seller_ref") != land.owner_ref or not Contract.amount(quote.get("amount"),true) or not Contract.amount(quote.get("valid_until_day")) or raw.resource_accounts.get(quote.get("payee_account_id"),{}).get("owner_ref") != land.owner_ref: return Contract.fail("土地报价缺少所有者同意或收款来源")
	for sale in raw.get("economic_contracts",{}).values():
		if sale.get("contract_kind") != "land_sale": continue
		var land: Dictionary = raw.management_assets.get(sale.get("land_id",""),{})
		var quote: Dictionary = sale.get("quote",{})
		var paid: Dictionary = raw.resource_journal.get(sale.get("receipt_id",""),{})
		var receipt: Dictionary = raw.action_receipts.get(sale.get("receipt_id",""),{})
		if sale.get("status") != "settled" or not land.get("transfer_history",[]).has(sale.contract_id) or not receipt.get("effect_refs",[]).has(sale.contract_id) or not receipt.get("journal_refs",[]).has(sale.receipt_id): return Contract.fail("土地交割缺少提交回执")
		if quote.get("seller_ref") != sale.get("seller_ref") or quote.get("seller_consent") != true or sale.get("amount") != quote.get("amount") or not Contract.amount(sale.get("created_day")) or int(sale.created_day) > int(quote.get("valid_until_day",-1)): return Contract.fail("土地交割缺少有效同意与价格")
		if paid.get("amount") != sale.get("amount") or paid.get("reason_ref") != sale.contract_id or paid.get("source_account_id") != sale.get("funding_account_id") or paid.get("destination_account_id") != sale.get("payee_account_id") or raw.resource_accounts.get(sale.get("funding_account_id"),{}).get("owner_ref") != sale.get("buyer_ref") or raw.resource_accounts.get(sale.get("payee_account_id"),{}).get("owner_ref") != sale.get("seller_ref"): return Contract.fail("土地交割缺少真实双方资金流水")
	return {"ok":true}
