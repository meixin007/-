extends RefCounted
## Undivided title shares use original parties, accounts, consents and transfer history.
const Accounts=preload("res://scripts/core/resource_account_service.gd")
const Contract=preload("res://scripts/core/management_state_contract.gd")
const KINDS=["offer_land_share","approve_land_share_offer","buy_land_share"]
static func _same(a: Variant, b: Variant) -> bool:
	var left: Dictionary=preload("res://scripts/core/canonical_json.gd").encode(a)
	var right: Dictionary=preload("res://scripts/core/canonical_json.gd").encode(b)
	return left.ok and right.ok and left.text==right.text
static func key(ref: Dictionary) -> String:
	return str(ref.get("entity_kind",""))+":"+str(ref.get("entity_id",""))
static func shares(land: Dictionary) -> Array:
	return land.get("ownership_shares",[{"owner_ref":land.owner_ref.duplicate(true),"share_units":100}]).duplicate(true)
static func title(land_id: String, rows: Array) -> Dictionary:
	return rows[0].owner_ref.duplicate(true) if rows.size()==1 and int(rows[0].share_units)==100 else {"entity_kind":"coownership","entity_id":land_id}
static func units(rows: Array, ref: Dictionary) -> int:
	for row in rows:
		if row.owner_ref==ref:return int(row.share_units)
	return 0
static func _move(rows: Array, seller: Dictionary, buyer: Dictionary, amount: int) -> Array:
	var result: Array=rows.duplicate(true)
	for row in result:
		if row.owner_ref==seller:row.share_units=int(row.share_units)-amount
	var found:=false
	for row in result:
		if row.owner_ref==buyer:row.share_units=int(row.share_units)+amount;found=true
	if not found:result.append({"owner_ref":buyer.duplicate(true),"share_units":amount})
	result=result.filter(func(row):return int(row.share_units)>0)
	result.sort_custom(func(a,b):return key(a.owner_ref)<key(b.owner_ref))
	return result
static func cost_for(state, kind: String, params: Dictionary) -> Dictionary:
	var land: Dictionary=state.management_assets.get(params.get("land_id"),{})
	if land.get("asset_kind")!="land":return Contract.fail("没有可办理的土地份额")
	if land.disputed or not str(land.lien_contract_id).is_empty() or int(land.used_area_units)>0 or not load("res://scripts/core/land_lease_service.gd").current(state,land).is_empty() or land.rights.any(func(right):return not right is Dictionary or right.get("right_kind")!="land_lease"):return Contract.fail("先处理土地争议、抵押、租约及工程占用，再接洽产权份额")
	if kind=="offer_land_share":
		var payee: Dictionary=state.resource_accounts.get(params.get("payee_account_id"),{})
		if payee.get("unit_id")!="cash_unit" or not Contract.amount(params.get("share_units"),true) or int(params.share_units)>units(shares(land),payee.get("owner_ref",{})) or not Contract.amount(params.get("amount"),true) or not Contract.amount(params.get("valid_until_day")) or int(params.valid_until_day)<int(state.current_day):return Contract.fail("报价须指明真实持有份额内的比例、价款、期限及本人收款账户")
		return {"ok":true,"account_id":"","amount":0}
	var offer: Dictionary=land.get("share_offers",{}).get(params.get("seller_key"),{})
	if offer.is_empty() or offer.version!=params.get("quote_version") or int(offer.valid_until_day)<int(state.current_day) or not _same(offer.before_shares,shares(land)):return Contract.fail("土地份额或报价已变化，请重新接洽并取得各方同意")
	if kind=="approve_land_share_offer":return {"ok":true,"account_id":"","amount":0}
	for row in shares(land):
		if row.owner_ref==offer.seller_ref:continue
		if not offer.consents.any(func(consent):return consent.owner_ref==row.owner_ref):return Contract.fail("共有处分尚缺其他持有人的本次报价同意；请先请其确认份额和价款")
	return {"ok":true,"account_id":str(params.get("funding_account_id","")),"amount":int(offer.amount)}
static func apply(state, kind: String, params: Dictionary, principal: String, execution: String, reservation: String="") -> Dictionary:
	var checked:=cost_for(state,kind,params)
	if not checked.ok:return checked
	var land: Dictionary=state.management_assets[params.land_id]
	if kind=="offer_land_share":
		if not Accounts.new().can_operate(state,params.payee_account_id,principal):return Contract.fail("无权代表这份实际产权及收款主体报价")
		var seller: Dictionary=state.resource_accounts[params.payee_account_id].owner_ref
		var offers: Dictionary=land.get("share_offers",{})
		land["share_quote_version"]=int(land.get("share_quote_version",0))+1
		var quote: Dictionary={"land_id":land.asset_id,"seller_ref":seller.duplicate(true),"share_units":int(params.share_units),"amount":int(params.amount),"valid_until_day":int(params.valid_until_day),"payee_account_id":params.payee_account_id,"version":int(land.share_quote_version),"before_shares":shares(land),"consent_receipt":execution,"consents":[]}
		offers[key(seller)]=quote;land["share_offers"]=offers
		return {"ok":true,"result_ref":land.asset_id,"land_share_offer":quote.duplicate(true),"visible_summary":"已发布本人实际持有的%d%%土地份额报价；共有处分仍须其他持有人同意。" % int(params.share_units)}
	var offer: Dictionary=land.share_offers[params.seller_key]
	if kind=="approve_land_share_offer":
		var account: Dictionary=state.resource_accounts.get(params.get("consenting_account_id"),{})
		var owner: Dictionary=account.get("owner_ref",{})
		if account.get("unit_id")!="cash_unit" or not Accounts.new().can_operate(state,str(params.get("consenting_account_id","")),principal) or units(shares(land),owner)==0 or owner==offer.seller_ref or offer.consents.any(func(row):return row.owner_ref==owner):return Contract.fail("本次同意须由另一实际共有持有人签署，不能重复或代替他人")
		var signed: Dictionary={"owner_ref":owner.duplicate(true),"seller_key":params.seller_key,"quote_version":offer.version,"offer_receipt":offer.consent_receipt,"receipt_id":execution}
		offer.consents.append(signed)
		return {"ok":true,"result_ref":land.asset_id,"land_share_consent":signed.duplicate(true),"visible_summary":"已同意这份土地份额报价；仅适用于本次版本，不增加任何建设权。"}
	var fund: Dictionary=state.resource_accounts.get(params.get("funding_account_id"),{})
	if fund.get("unit_id")!="cash_unit" or fund.get("owner_ref")==offer.seller_ref or not Accounts.new().can_operate(state,str(params.get("funding_account_id","")),principal):return Contract.fail("买方须使用不同真实主体的有权付款账户")
	var id: String="land-share-sale:"+execution
	var paid: Dictionary=Accounts.new().apply(state,"transfer",{"execution_id":execution,"source_account_id":params.funding_account_id,"destination_account_id":offer.payee_account_id,"amount":offer.amount,"actor_id":principal,"reason_ref":id,"reservation_id":reservation})
	if not paid.ok:return paid
	var before: Array=shares(land)
	var after: Array=_move(before,offer.seller_ref,fund.owner_ref,int(offer.share_units))
	state.economic_contracts[id]={"contract_id":id,"contract_kind":"land_share_sale","status":"settled","land_id":land.asset_id,"seller_ref":offer.seller_ref.duplicate(true),"buyer_party_ref":fund.owner_ref.duplicate(true),"buyer_ref":title(land.asset_id,after),"quote":offer.duplicate(true),"before_shares":before,"after_shares":after,"amount":offer.amount,"funding_account_id":params.funding_account_id,"payee_account_id":offer.payee_account_id,"created_day":int(state.current_day),"receipt_id":execution,"party_refs":[offer.seller_ref.entity_id,fund.owner_ref.entity_id],"terms_version":1,"execution_refs":[execution]}
	land["ownership_shares"]=after;land.owner_ref=title(land.asset_id,after)
	land.contract_refs.append(id);land.transfer_history.append(id)
	land["share_offers"]={};land.sale_offer={"active":false,"version":int(land.sale_offer.version)+1}
	if land.has("lease_offer"):land.lease_offer={"active":false,"version":int(land.lease_offer.get("version",0))+1}
	return {"ok":true,"result_ref":id,"journal_refs":[execution],"visible_summary":"已按真实付款交割%d%%土地份额；其余持有人、土地面积和建设权分别保留。" % int(offer.share_units)}
static func _valid_shares(raw: Dictionary, rows: Variant) -> bool:
	if not rows is Array or rows.is_empty():return false
	var total:=0
	var seen:=[]
	for row in rows:
		if not row is Dictionary or not row.get("owner_ref") is Dictionary or not Contract.amount(row.get("share_units"),true) or seen.has(row.owner_ref) or not raw.resource_accounts.values().any(func(account):return account.owner_ref==row.owner_ref):return false
		total+=int(row.share_units);seen.append(row.owner_ref)
	return total==100
static func _valid_offer(raw: Dictionary, quote: Variant) -> bool:
	if not quote is Dictionary or not _valid_shares(raw,quote.get("before_shares")) or not quote.get("seller_ref") is Dictionary or not Contract.amount(quote.get("share_units"),true) or int(quote.share_units)>units(quote.before_shares,quote.seller_ref) or not Contract.amount(quote.get("amount"),true) or not Contract.amount(quote.get("version"),true) or not Contract.amount(quote.get("valid_until_day")) or not quote.get("consents") is Array or raw.resource_accounts.get(quote.get("payee_account_id"),{}).get("owner_ref")!=quote.seller_ref:return false
	var proof: Dictionary=raw.action_receipts.get(quote.get("consent_receipt"),{}).get("land_share_offer",{}).duplicate(true)
	var unsigned: Dictionary=quote.duplicate(true);unsigned.consents=[]
	if not _same(proof,unsigned) or not raw.action_receipts.get(quote.consent_receipt,{}).get("effect_refs",[]).has(quote.get("land_id")):return false
	var seen:=[]
	for consent in quote.consents:
		if not consent is Dictionary or not consent.get("owner_ref") is Dictionary or seen.has(consent.get("owner_ref")) or consent.get("owner_ref")==quote.seller_ref or units(quote.before_shares,consent.get("owner_ref",{}))==0 or consent.get("offer_receipt")!=quote.consent_receipt or consent.get("seller_key")!=key(quote.seller_ref) or consent.get("quote_version")!=quote.version or raw.action_receipts.get(consent.get("receipt_id"),{}).get("land_share_consent")!=consent:return false
		seen.append(consent.owner_ref)
	return true
static func validate_history(raw: Dictionary, land: Dictionary) -> Dictionary:
	if not land.get("share_offers",{}) is Dictionary or (land.has("ownership_shares") and not _valid_shares(raw,land.ownership_shares)):return Contract.fail("土地份额或报价记录类型损坏")
	var previous: Array=[{"owner_ref":land.initial_owner_ref.duplicate(true),"share_units":100}]
	var seen:=[]
	for id in land.transfer_history:
		var row: Dictionary=raw.economic_contracts.get(id,{})
		if seen.has(id) or not land.contract_refs.has(id) or row.get("land_id")!=land.asset_id:return Contract.fail("土地产权来源或份额交割链断裂")
		seen.append(id)
		if row.get("contract_kind")=="land_sale":
			if row.seller_ref!=title(land.asset_id,previous) or previous.size()!=1:return Contract.fail("共有地不能跳过份额及同意直接整体过户")
			previous=[{"owner_ref":row.buyer_ref.duplicate(true),"share_units":100}]
		elif row.get("contract_kind")=="land_share_sale":
			if not _same(row.get("before_shares"),previous) or not _valid_offer(raw,row.get("quote")) or row.quote.get("land_id")!=land.asset_id or not _same(row.quote.before_shares,previous) or row.quote.seller_ref!=row.get("seller_ref") or not row.get("buyer_party_ref") is Dictionary or row.buyer_party_ref==row.seller_ref:return Contract.fail("土地份额交割缺少有效权源和签署报价")
			for owner in previous:
				if owner.owner_ref!=row.seller_ref and not row.quote.consents.any(func(consent):return consent.owner_ref==owner.owner_ref):return Contract.fail("共有处分缺少相关持有人同意")
			previous=_move(previous,row.seller_ref,row.buyer_party_ref,int(row.quote.share_units))
			var paid: Dictionary=raw.resource_journal.get(row.get("receipt_id"),{})
			if not _same(row.get("after_shares"),previous) or row.get("buyer_ref")!=title(land.asset_id,previous) or row.get("amount")!=row.quote.amount or not Contract.amount(row.get("created_day")) or int(row.created_day)>int(row.quote.valid_until_day) or paid.get("reason_ref")!=id or paid.get("amount")!=row.amount or paid.get("source_account_id")!=row.get("funding_account_id") or paid.get("destination_account_id")!=row.quote.payee_account_id or raw.resource_accounts.get(row.get("funding_account_id"),{}).get("owner_ref")!=row.buyer_party_ref or not raw.action_receipts.get(row.get("receipt_id"),{}).get("effect_refs",[]).has(id):return Contract.fail("土地份额、价款或实际交割回执不符")
		else:return Contract.fail("土地产权交割类别未知")
	if land.owner_ref!=title(land.asset_id,previous) or (land.has("ownership_shares") and not _same(land.ownership_shares,previous)) or (previous.size()>1 and not land.has("ownership_shares")):return Contract.fail("当前土地产权份额与实际交割历史不符")
	for offer in land.get("share_offers",{}).values():
		if not _valid_offer(raw,offer) or offer.get("land_id")!=land.asset_id or not _same(offer.before_shares,previous):return Contract.fail("当前份额报价丢失权利人同意")
	if land.has("share_quote_version") or land.has("ownership_shares") or not land.get("share_offers",{}).is_empty():
		if not land.has("share_quote_version"):return Contract.fail("土地份额报价版本丢失")
		if not Contract.amount(land.share_quote_version,true):return Contract.fail("土地份额报价版本失效")
		var actual_version:=0
		for receipt in raw.action_receipts.values():
			var signed: Variant=receipt.get("land_share_offer",{})
			if not signed is Dictionary:return Contract.fail("土地份额签署回执损坏")
			if signed.get("land_id")==land.asset_id:actual_version=maxi(actual_version,int(signed.get("version",2147483647)))
		if int(land.share_quote_version)!=actual_version:return Contract.fail("土地份额报价版本须与实际签署记录一致")
	return {"ok":true}
