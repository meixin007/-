extends RefCounted
## A prepaid, explicitly scoped land lease in the original contract registry.
const Accounts=preload("res://scripts/core/resource_account_service.gd")
const Contract=preload("res://scripts/core/management_state_contract.gd")
const KINDS := ["offer_land_lease","lease_land","end_land_lease"]
static func current(state, land: Dictionary) -> Dictionary:
	for right in land.get("rights",[]):
		var lease: Dictionary=state.economic_contracts.get(right.get("contract_id"),{}) if right is Dictionary else {}
		if lease.get("contract_kind")=="land_lease" and lease.get("status")=="active" and int(lease.from_day)<=int(state.current_day) and int(state.current_day)<int(lease.until_day):return lease
	return {}
static func building_access(state, building: Dictionary) -> bool:
	if not building.get("property_history",[]).is_empty():return load("res://scripts/core/estate_property_transaction_service.gd").ground_until(state,building)>int(state.current_day)
	var order: Dictionary=state.economic_contracts.get(building.get("source_ref",{}).get("entity_id"),{})
	if str(order.get("land_lease_id","")).is_empty():return true
	var land: Dictionary=state.management_assets.get(order.get("land_id"),{})
	var lease: Dictionary=current(state,land)
	return not lease.is_empty() and lease.lessee_ref==building.owner_ref and lease.allow_build
static func permission(state, land: Dictionary, owner: Dictionary, actor: String) -> Dictionary:
	if land.get("disputed",false) or not str(land.get("lien_contract_id","")).is_empty():return {}
	for right in land.get("rights",[]):
		if not right is Dictionary or right.get("right_kind")!="land_lease":return {}
	var lease: Dictionary=current(state,land)
	if not lease.is_empty():
		if lease.lessee_ref==owner and lease.allow_build and (owner=={"entity_kind":"character","entity_id":actor} or Accounts.new().can_operate(state,lease.funding_account_id,actor)):return lease
		return {}
	# Historical leases with a retained tenant building still require a renewed lease.
	if not land.get("rights",[]).is_empty() and int(land.get("used_area_units",0))>0:return {}
	if owner==land.owner_ref and load("res://scripts/core/land_property_service.gd").authority(state,land,actor):return {"contract_id":"","lessee_ref":owner.duplicate(true)}
	return {}
static func cost_for(state,kind: String,params: Dictionary) -> Dictionary:
	var land: Dictionary=state.management_assets.get(params.get("land_id"),{})
	if land.get("asset_kind")!="land":return Contract.fail("租用须指定真实地块")
	if kind=="lease_land":
		var offer: Dictionary=land.get("lease_offer",{})
		if not offer.get("active",false) or params.get("quote_version")!=offer.get("version") or int(offer.get("valid_until_day",-1))<int(state.current_day):return Contract.fail("出租报价已失效，请重新接洽地主")
		if not state.resource_accounts.has(params.get("funding_account_id")):return Contract.fail("租用缺少实际付款账户")
		return {"ok":true,"amount":int(offer.amount),"account_id":params.funding_account_id}
	if kind=="offer_land_lease" and (not Contract.amount(params.get("amount"),true) or not Contract.amount(params.get("duration_days"),true) or not Contract.amount(params.get("valid_until_day")) or int(params.valid_until_day)<int(state.current_day) or not params.get("allow_build") is bool or not state.resource_accounts.has(params.get("payee_account_id"))):return Contract.fail("出租须明确预付租金、期限、建设权和收款账户")
	return {"ok":true,"amount":0,"account_id":""}
static func apply(state,kind: String,params: Dictionary,principal: String,execution: String,reservation: String="") -> Dictionary:
	var valid: Dictionary=cost_for(state,kind,params)
	if not valid.ok:return valid
	var land: Dictionary=state.management_assets[params.land_id]
	if land.disputed or land.lien_contract_id!="":return Contract.fail("须先处理土地争议或抵押")
	if kind=="offer_land_lease":
		if not load("res://scripts/core/land_property_service.gd").authority(state,land,principal) or state.resource_accounts[params.payee_account_id].owner_ref!=land.owner_ref:return Contract.fail("出租报价须由土地权利人签署，款项归属同一主体")
		if not current(state,land).is_empty():return Contract.fail("现有租约尚在履行，请先处理原约")
		for right in land.rights:
			if not right is Dictionary or right.get("right_kind")!="land_lease":return Contract.fail("其他土地权利须先处理")
		var offer := {"active":true,"version":int(land.get("lease_offer",{}).get("version",0))+1,"lessor_ref":land.owner_ref.duplicate(true),"amount":int(params.amount),"duration_days":int(params.duration_days),"allow_build":params.allow_build,"payee_account_id":params.payee_account_id,"valid_until_day":int(params.valid_until_day),"consent_receipt":execution}
		land["lease_offer"]=offer
		return {"ok":true,"result_ref":land.asset_id,"land_lease_offer":offer.duplicate(true)}
	if kind=="end_land_lease":
		var lease: Dictionary=state.economic_contracts.get(params.get("lease_id"),{})
		if lease.get("contract_kind")!="land_lease" or lease.get("land_id")!=land.asset_id or lease.status!="active" or not Accounts.new().can_operate(state,lease.funding_account_id,principal):return Contract.fail("只可由承租主体退还其原租约")
		if int(land.used_area_units)>0:return Contract.fail("土地已有在建或保留房产，不能无声解除其场所权利")
		lease.status="ended";lease["end_receipt"]=execution;lease["ended_day"]=int(state.current_day)
		return {"ok":true,"result_ref":lease.contract_id,"visible_summary":"未使用土地已退还；原预付租金与历史约定保留。"}
	if not current(state,land).is_empty():return Contract.fail("该地已有生效租约，不能重复出租")
	for right in land.rights:
		if not right is Dictionary or right.get("right_kind")!="land_lease":return Contract.fail("尚有其他土地权利未处理")
	var offer: Dictionary=land.lease_offer.duplicate(true)
	var payer: Dictionary=state.resource_accounts[params.funding_account_id]
	if payer.unit_id!="cash_unit" or payer.owner_ref==land.owner_ref or not Accounts.new().can_operate(state,params.funding_account_id,principal) or state.resource_accounts[offer.payee_account_id].owner_ref!=land.owner_ref or offer.lessor_ref!=land.owner_ref:return Contract.fail("租用的地主、承租主体或实际付款权限已经变化")
	for building in state.management_assets.values():
		if building.get("asset_kind")=="estate_building" and building.get("land_id")==land.asset_id and building.owner_ref!=payer.owner_ref:return Contract.fail("土地仍有他人房产，须取得其同意后另行接洽")
	var id := "land-lease:"+execution
	var paid: Dictionary=Accounts.new().apply(state,"transfer",{"execution_id":execution,"source_account_id":params.funding_account_id,"destination_account_id":offer.payee_account_id,"amount":int(offer.amount),"actor_id":principal,"reason_ref":id,"reservation_id":reservation})
	if not paid.ok:return paid
	var lease := {"contract_id":id,"contract_kind":"land_lease","status":"active","land_id":land.asset_id,"lessor_ref":land.owner_ref.duplicate(true),"lessee_ref":payer.owner_ref.duplicate(true),"funding_account_id":params.funding_account_id,"payee_account_id":offer.payee_account_id,"amount":int(offer.amount),"allow_build":offer.allow_build,"from_day":int(state.current_day),"until_day":int(state.current_day)+int(offer.duration_days),"quote":offer,"receipt_id":execution,"ownership_ref":land.transfer_history.back() if not land.transfer_history.is_empty() else "initial","execution_refs":[execution]}
	state.economic_contracts[id]=lease;land.rights.append({"right_kind":"land_lease","contract_id":id});land.contract_refs.append(id)
	land.lease_offer={"active":false,"version":int(offer.version)+1}
	land.sale_offer={"active":false,"version":int(land.sale_offer.version)+1}
	return {"ok":true,"result_ref":id,"journal_refs":[execution],"visible_summary":"已取得预付期限内的土地使用权；"+("另有明确建设权，房屋归承租主体。" if offer.allow_build else "未获建设权，不能开工。")}
static func _consent(raw: Dictionary,land: Dictionary,quote: Dictionary) -> bool:
	var receipt: Dictionary=raw.action_receipts.get(quote.get("consent_receipt"),{})
	if not receipt.is_empty():return receipt.get("land_lease_offer")==quote and receipt.effect_refs.has(land.asset_id)
	var definitions: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/anshi_rebellion/regional_estates.json"))
	for original in definitions.initial_assets:
		if original.asset_id==land.asset_id:return original.get("lease_offer",{})==quote
	return false
static func validate(raw: Dictionary) -> Dictionary:
	for land in raw.management_assets.values():
		if land.get("asset_kind")!="land":continue
		var seen := {}
		for right in land.rights:
			if not right is Dictionary or right.get("right_kind")!="land_lease":continue
			var lease: Dictionary=raw.economic_contracts.get(right.get("contract_id"),{})
			if seen.has(right.contract_id) or lease.get("contract_kind")!="land_lease" or lease.get("land_id")!=land.asset_id or not land.contract_refs.has(right.contract_id):return Contract.fail("土地租用权缺少唯一有效原约")
			seen[right.contract_id]=true
		var offer: Dictionary=land.get("lease_offer",{})
		if offer.get("active",false) and (not _offer_valid(raw,land,offer) or offer.lessor_ref!=land.owner_ref):return Contract.fail("土地出租报价缺少真实权利人同意")
	for lease in raw.economic_contracts.values():
		if lease.get("contract_kind")!="land_lease":continue
		if not lease.get("quote") is Dictionary or not lease.get("lessor_ref") is Dictionary or not lease.get("lessee_ref") is Dictionary or not lease.get("land_id") is String or not lease.get("funding_account_id") is String or not lease.get("payee_account_id") is String or not lease.get("receipt_id") is String:return Contract.fail("土地租约主体、报价或付款引用结构无效")
		var land: Dictionary=raw.management_assets.get(lease.get("land_id"),{})
		var quote: Dictionary=lease.get("quote",{})
		var owner: Dictionary=land.get("initial_owner_ref",{}) if lease.get("ownership_ref")=="initial" else raw.economic_contracts.get(lease.get("ownership_ref"),{}).get("buyer_ref",{})
		if land.get("asset_kind")!="land" or lease.get("status") not in ["active","ended"] or not _offer_valid(raw,land,quote) or owner!=lease.get("lessor_ref") or quote.lessor_ref!=owner or quote.amount!=lease.get("amount") or quote.allow_build!=lease.get("allow_build"):return Contract.fail("土地租约缺少真实产权、明确同意或相应建设权")
		if not Contract.amount(lease.get("from_day")) or not Contract.amount(lease.get("until_day"),true) or lease.from_day>raw.current_day or lease.until_day!=int(lease.from_day)+int(quote.duration_days) or lease.from_day>quote.valid_until_day:return Contract.fail("土地租约期限或签署日无效")
		var payer: Dictionary=raw.resource_accounts.get(lease.get("funding_account_id"),{})
		var payment: Dictionary=raw.resource_journal.get(lease.get("receipt_id"),{})
		var receipt: Dictionary=raw.action_receipts.get(lease.get("receipt_id"),{})
		if payer.get("owner_ref")!=lease.get("lessee_ref") or payer.get("owner_ref")==owner or raw.resource_accounts.get(lease.get("payee_account_id"),{}).get("owner_ref")!=owner or payment.get("source_account_id")!=lease.funding_account_id or payment.get("destination_account_id")!=lease.payee_account_id or payment.get("amount")!=lease.amount or payment.get("reason_ref")!=lease.contract_id or payment.get("day")!=lease.from_day or not receipt.get("effect_refs",[]).has(lease.contract_id):return Contract.fail("土地租约缺少原资金交割回执")
		if not land.rights.has({"right_kind":"land_lease","contract_id":lease.contract_id}):return Contract.fail("已付租金的土地使用权不能丢失")
		if lease.status=="ended" and (not Contract.amount(lease.get("ended_day")) or int(lease.ended_day)<int(lease.from_day) or int(lease.ended_day)>int(raw.current_day) or not raw.action_receipts.get(lease.get("end_receipt"),{}).get("effect_refs",[]).has(lease.contract_id)):return Contract.fail("土地退还缺少真实确认")
	return {"ok":true}
static func _offer_valid(raw: Dictionary,land: Dictionary,quote: Dictionary) -> bool:
	return quote.get("active")==true and quote.get("lessor_ref") is Dictionary and Contract.amount(quote.get("version"),true) and Contract.amount(quote.get("amount"),true) and Contract.amount(quote.get("duration_days"),true) and Contract.amount(quote.get("valid_until_day")) and quote.get("allow_build") is bool and raw.resource_accounts.get(quote.get("payee_account_id"),{}).get("owner_ref")==quote.lessor_ref and _consent(raw,land,quote)
