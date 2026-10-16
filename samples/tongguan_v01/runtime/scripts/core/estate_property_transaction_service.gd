extends RefCounted
## Buildings and fixed-term exclusive operating rights are separate transaction targets.
const Contract=preload("res://scripts/core/management_state_contract.gd")
const Accounts=preload("res://scripts/core/resource_account_service.gd")
const KINDS=["offer_estate_property","buy_estate_property","offer_estate_operation","buy_estate_operation","withdraw_estate_offer","contact_estate_property_buyer"]
static func buyer_assessment(state, data: Dictionary, building: Dictionary, buyer: String, seller: String) -> Dictionary:
	var policy: Dictionary=data.get("management",{}).get("estate_trade_preferences",{}).get(buyer,{})
	var quote: Dictionary=building.get("property_offer",{})
	var account: Dictionary=state.resource_accounts.get(policy.get("account_id"),{})
	if policy.is_empty() or not str(policy.get("source_id","")).begins_with("scenario:") or not Contract.amount(policy.get("maximum_price"),true) or not Contract.amount(policy.get("minimum_cash_retained")) or not policy.get("industry_kinds") is Array or not policy.industry_kinds.has(building.get("industry_kind")) or buyer==state.player_character_id or account.get("owner_ref")!={"entity_kind":"character","entity_id":buyer}:return Contract.fail("此人物没有该类房产的明确接洽意愿")
	if not load("res://scripts/core/production_service.gd").present(state,buyer,building.location_id) or not Accounts.new().can_operate(state,str(policy.account_id),buyer):return Contract.fail("买方不在当地或不能支用其实际资金")
	if not quote.get("active",false) or int(quote.get("amount",Contract.MAX_AMOUNT))>int(policy.maximum_price) or int(quote.amount)+int(policy.minimum_cash_retained)>Accounts.new().available(state,str(policy.account_id)) or int(state.character_states[buyer].get("relationships",{}).get(seller,0)) < -15:return Contract.fail("买方按当前意愿、价款及保留资金拒绝接单；不替其自动批准")
	return {"ok":true,"funding_account_id":policy.account_id,"policy_source":policy.source_id}
static func owner_on_day(state, building: Dictionary, day: int) -> Dictionary:
	var original: Dictionary=state.economic_contracts.get(building.get("source_ref",{}).get("entity_id"),{})
	var owner: Dictionary=original.get("owner_ref",{}).duplicate(true)
	for ref in building.get("property_history",[]):
		var sale: Dictionary=state.economic_contracts.get(ref,{})
		if int(sale.get("day",2147483647))<=day:owner=sale.get("buyer_ref",{}).duplicate(true)
	return owner
static func ground_until(state, building: Dictionary) -> int:
	if not building.get("property_history",[]).is_empty():return int(state.economic_contracts.get(building.property_history.back(),{}).get("use_until_day",-1))
	var original: Dictionary=state.economic_contracts.get(building.get("source_ref",{}).get("entity_id"),{})
	var land: Dictionary=state.management_assets.get(building.get("land_id"),{})
	return Contract.MAX_AMOUNT if original.get("land_lease_id","")=="" and building.get("owner_ref")==land.get("owner_ref") else -1
static func owner_before_receipt(state, building: Dictionary, receipt_id: String) -> Dictionary:
	var original: Dictionary=state.economic_contracts.get(building.get("source_ref",{}).get("entity_id"),{})
	var title: Dictionary=original.get("owner_ref",{}).duplicate(true)
	var revision: int=int(state.action_receipts.get(receipt_id,{}).get("state_revision_after",0))
	for ref in building.get("property_history",[]):
		var sale: Dictionary=state.economic_contracts.get(ref,{})
		if int(state.action_receipts.get(sale.get("receipt_id"),{}).get("state_revision_after",2147483647))<revision:title=sale.get("buyer_ref",{}).duplicate(true)
	return title
static func property_basis(state, building: Dictionary, before_revision: int=2147483647) -> int:
	var original: Dictionary=state.economic_contracts.get(building.get("source_ref",{}).get("entity_id"),{})
	var amount: int=int(original.get("recipe",{}).get("price",0))
	var bought: bool=false
	for ref in building.get("property_history",[]):
		var sale: Dictionary=state.economic_contracts.get(ref,{})
		if int(state.action_receipts.get(sale.get("receipt_id"),{}).get("state_revision_after",2147483647))<before_revision:amount=int(sale.get("amount",0));bought=true
	if not bought:
		for row in state.economic_contracts.values():
			if row.get("contract_kind")=="estate_improvement" and row.get("building_id")==building.asset_id and int(state.action_receipts.get(row.get("receipt_id"),{}).get("state_revision_after",2147483647))<before_revision:amount+=int(row.amount)
	return amount
static func operation(state, building: Dictionary) -> Dictionary:
	for row in state.economic_contracts.values():
		if row.get("contract_kind")=="estate_operating_right" and row.get("building_id")==building.asset_id and row.get("status")=="active" and int(state.current_day)<int(row.until_day):return row
	return {}
static func operating_access(state, shop: Dictionary) -> bool:
	var row: Dictionary=state.economic_contracts.get(shop.get("operating_right_id"),{})
	var building: Dictionary=state.management_assets.get(shop.get("building_id"),{})
	return row.get("contract_kind")=="estate_operating_right" and row.get("operating_shop_id")==shop.asset_id and row.get("operator_ref")==shop.owner_ref and row.get("status")=="active" and int(state.current_day)<int(row.get("until_day",-1)) and ground_until(state,building)>int(state.current_day)
static func _free(state, building: Dictionary) -> Dictionary:
	var land: Dictionary=state.management_assets.get(building.get("land_id"),{})
	if building.get("asset_kind")!="estate_building" or building.get("status") not in ["completed","in_use"] or land.get("disputed",false) or land.get("lien_contract_id","")!="" or building.get("lien_contract_id","")!="" or ground_until(state,building)<=int(state.current_day) or not operation(state,building).is_empty():return Contract.fail("房产有争议、抵押、有效经营权或场所权利未落实，不能重复交割")
	if not load("res://scripts/core/estate_lifecycle_service.gd").working(state,building.asset_id).is_empty():return Contract.fail("扩建尚未结束，先处理原工程")
	for shop in state.management_assets.values():
		if shop.get("building_id")!=building.asset_id or shop.get("premises_kind")=="retired":continue
		if shop.get("status")!="closed" or not load("res://scripts/core/business_management_service.gd").current(state,shop.asset_id).is_empty():return Contract.fail("请先停业并撤回经营授权；房产交易不接走原店款或日常合同")
		var statement: Dictionary=load("res://scripts/core/business_financial_projection.gd").statement(state,shop.asset_id,0,int(state.current_day))
		if int(statement.principal_outstanding)>0 or int(statement.inventory_quantity)>0 or int(statement.work_in_progress_value)>0 or int(statement.current_arrears)>0:return Contract.fail("先处理未收款、库存、在制品及欠款，不能无声丢弃义务")
		for job in state.economic_contracts.values():
			if job.get("contract_kind")=="employment" and job.get("status")=="active" and (job.get("office_id")==shop.office_id or job.get("office_id")==load("res://scripts/core/business_staff_service.gd").office_id(shop.asset_id)):return Contract.fail("请先明确解任原店负责人及副手，工资历史与欠薪仍保留")
		for reserve in state.resource_reservations.values():
			if reserve.get("account_id")==shop.account_id and reserve.get("status")=="active":return Contract.fail("原店尚有预留款，先处理相关委托")
	return {"ok":true}
static func cost_for(state, kind: String, params: Dictionary) -> Dictionary:
	var building: Dictionary=state.management_assets.get(params.get("building_id"),{})
	if kind not in KINDS or building.get("asset_kind")!="estate_building":return Contract.fail("请选择实际建成的房产")
	if kind=="contact_estate_property_buyer":
		var offer: Dictionary=building.get("property_offer",{})
		if not params.get("buyer_id") is String or not state.character_states.has(params.buyer_id) or not offer.get("active",false) or offer.get("version")!=params.get("quote_version") or int(offer.get("valid_until_day",-1))<int(state.current_day) or offer.get("seller_ref")!=building.owner_ref:return Contract.fail("须重新核对房产报价及真实接洽买家")
		return {"ok":true,"account_id":"","amount":0}
	if kind.begins_with("buy_"):
		var quote: Dictionary=building.get("property_offer" if kind=="buy_estate_property" else "operation_offer",{})
		if not quote.get("active",false) or quote.get("version")!=params.get("quote_version") or int(quote.get("valid_until_day",-1))<int(state.current_day) or quote.get("seller_ref")!=building.owner_ref or not Contract.amount(quote.get("amount"),true):return Contract.fail("房产或经营权报价已变化、过期或撤回，请重新接洽")
		return {"ok":true,"account_id":str(params.get("funding_account_id","")),"amount":int(quote.amount)}
	if kind=="withdraw_estate_offer":return {"ok":true,"account_id":"","amount":0} if params.get("offer_kind") in ["property","operation"] else Contract.fail("须指明撤回房产或经营权报价")
	if not Contract.amount(params.get("amount"),true) or not Contract.amount(params.get("duration_days"),true) or not Contract.amount(params.get("valid_until_day")) or int(params.valid_until_day)<int(state.current_day) or not state.resource_accounts.has(params.get("payee_account_id")):return Contract.fail("须写明实际价款、场所使用期限、报价期限及原收款账户")
	return {"ok":true,"account_id":"","amount":0}
static func _retire(state, building: Dictionary, contract_id: String) -> Array:
	var rows: Array=[]
	for shop in state.management_assets.values():
		if shop.get("building_id")!=building.asset_id or shop.get("premises_kind")=="retired":continue
		shop["premises_kind"]="retired";shop["retirement_contract_id"]=contract_id
		rows.append(shop.asset_id)
		for duty in state.economic_contracts.values():
			if duty.get("contract_kind")=="maintenance" and duty.get("shop_id")==shop.asset_id and duty.get("status")=="active":duty.status="terminated";duty["property_termination_ref"]=contract_id;duty["ended_day"]=int(state.current_day)
	building.status="completed"
	rows.sort();return rows
static func apply(state, kind: String, params: Dictionary, principal: String, execution: String, reservation: String="", data: Dictionary={}) -> Dictionary:
	var checked:=cost_for(state,kind,params)
	if not checked.ok:return checked
	var building: Dictionary=state.management_assets[params.building_id]
	var free:=_free(state,building)
	if not free.ok:return free
	if state.character_states[principal].location_id!=building.location_id:return Contract.fail("经办主体须在当地实际交割")
	var disposition=load("res://scripts/core/land_property_service.gd")
	if kind=="contact_estate_property_buyer":
		if not disposition.authority(state,building,principal):return Contract.fail("须由真实房产权利主体发起接洽")
		var accepted:=buyer_assessment(state,data,building,params.buyer_id,principal)
		if not accepted.ok:return accepted
		var npc_execution: String=execution+":npc-buy"
		var bought: Dictionary=load("res://scripts/core/game_action_dispatcher.gd").apply(state,data,{"execution_id":npc_execution,"request_id":npc_execution,"actor_id":params.buyer_id,"principal_id":params.buyer_id,"executor_id":params.buyer_id,"action_kind":"buy_estate_property","parameters":{"building_id":building.asset_id,"quote_version":params.quote_version,"funding_account_id":accepted.funding_account_id},"target_refs":[building.asset_id],"expected_state_revision":state.state_revision})
		if not bought.ok:return bought
		state.action_receipts[npc_execution]["npc_estate_trade_decision"]={"source_id":accepted.policy_source,"contact_receipt":execution,"buyer_id":params.buyer_id,"seller_id":principal,"building_id":building.asset_id,"day":int(state.current_day)}
		return {"ok":true,"result_ref":bought.receipt.effect_refs[0],"visible_summary":"具名买方按其当前意愿、实际资金与保留款接单，已由原交易服务交割房产；土地及旧店款仍保留原归属。"}
	if not kind.begins_with("buy_"):
		if not disposition.authority(state,building,principal):return Contract.fail("没有该房产或经营权的实际处分权")
		var field: String="property_offer" if kind in ["offer_estate_property","withdraw_estate_offer"] and params.get("offer_kind","property")=="property" else "operation_offer"
		if kind=="withdraw_estate_offer":
			if building.has(field):building[field].active=false
			return {"ok":true,"result_ref":building.asset_id,"visible_summary":"已撤回指定报价，产权及原资金不变。"}
		if state.resource_accounts[params.payee_account_id].owner_ref!=building.owner_ref or state.resource_accounts[params.payee_account_id].unit_id!="cash_unit":return Contract.fail("价款须进入原房产权利主体的现金账户")
		var limit: int=mini(ground_until(state,building),int(state.current_day)+int(params.duration_days))
		if limit<=int(state.current_day):return Contract.fail("土地使用期不足，不能出售超出原权利的经营或使用期限")
		building["estate_quote_version"]=int(building.get("estate_quote_version",0))+1
		var quote: Dictionary={"active":true,"version":building.estate_quote_version,"seller_ref":building.owner_ref.duplicate(true),"amount":int(params.amount),"duration_days":limit-int(state.current_day),"use_until_day":limit,"valid_until_day":int(params.valid_until_day),"payee_account_id":params.payee_account_id,"consent_receipt":execution,"kind":"property" if kind=="offer_estate_property" else "operation"}
		building[field]=quote
		building["offer_visibility"]="public"
		return {"ok":true,"result_ref":building.asset_id,"estate_property_offer":quote.duplicate(true),"visible_summary":"已明确报价及场所使用期限；房产、土地与经营权仍为分别登记的标的。"}
	var buying_property: bool=kind=="buy_estate_property"
	var quote: Dictionary=building["property_offer" if buying_property else "operation_offer"]
	var payer: Dictionary=state.resource_accounts.get(params.get("funding_account_id"),{})
	if payer.get("unit_id")!="cash_unit" or payer.get("owner_ref")==building.owner_ref or not Accounts.new().can_operate(state,str(params.get("funding_account_id","")),principal) or state.resource_accounts.get(quote.payee_account_id,{}).get("owner_ref")!=building.owner_ref:return Contract.fail("买方主体、价款或卖方收款权已经变化")
	var id: String=("estate-property-sale:" if buying_property else "estate-operating-right:")+execution
	var paid:=Accounts.new().apply(state,"transfer",{"execution_id":execution,"source_account_id":params.funding_account_id,"destination_account_id":quote.payee_account_id,"amount":int(quote.amount),"actor_id":principal,"reason_ref":id,"reservation_id":reservation})
	if not paid.ok:return paid
	var old_owner: Dictionary=building.owner_ref.duplicate(true)
	var old_rows:=_retire(state,building,id)
	var row: Dictionary={"contract_id":id,"contract_kind":"estate_property_sale" if buying_property else "estate_operating_right","status":"settled" if buying_property else "active","building_id":building.asset_id,"land_id":building.land_id,"seller_ref":old_owner,"buyer_ref":payer.owner_ref.duplicate(true),"operator_ref":payer.owner_ref.duplicate(true),"funding_account_id":params.funding_account_id,"payee_account_id":quote.payee_account_id,"amount":int(quote.amount),"quote":quote.duplicate(true),"day":int(state.current_day),"use_until_day":int(quote.use_until_day),"until_day":int(quote.use_until_day),"source_shops":old_rows,"receipt_id":execution,"terms_version":1,"party_refs":[old_owner.entity_id,payer.owner_ref.entity_id],"execution_refs":[execution]}
	if buying_property:
		var recovered: int=0
		for old_id in old_rows:
			var book: Dictionary=load("res://scripts/core/business_financial_projection.gd").statement(state,old_id,0,int(state.current_day))
			recovered+=int(book.capital_investment)
		if old_rows.is_empty():recovered=property_basis(state,building)
		row["book_value"]=recovered;row["disposal_loss"]=maxi(0,recovered-int(quote.amount));row["disposal_gain"]=maxi(0,int(quote.amount)-recovered)
		if not building.has("property_history"):building["property_history"]=[]
		building.property_history.append(id);building.owner_ref=payer.owner_ref.duplicate(true)
	else:row["operating_shop_id"]=""
	state.economic_contracts[id]=row;building.contract_refs.append(id)
	for field in ["property_offer","operation_offer"]:
		if building.has(field):building[field].active=false
	return {"ok":true,"result_ref":id,"visible_summary":"房产已交割，土地仍归原地主，使用期以原条款为准；旧店账户及历史义务保留。" if buying_property else "经营权已预付交割；房产、土地均未出售，仍须由新主体筹办并安排负责人及本钱。"}
static func _signed(raw: Dictionary, building: Dictionary, quote: Dictionary) -> bool:
	var receipt: Dictionary=raw.action_receipts.get(quote.get("consent_receipt"),{})
	return quote.get("seller_ref") is Dictionary and Contract.amount(quote.get("amount"),true) and Contract.amount(quote.get("version"),true) and Contract.amount(quote.get("use_until_day"),true) and Contract.amount(quote.get("duration_days"),true) and Contract.amount(quote.get("valid_until_day")) and quote.get("kind") in ["property","operation"] and receipt.get("estate_property_offer")==quote and owner_before_receipt(raw,building,str(quote.get("consent_receipt","")))==quote.seller_ref and receipt.get("effect_refs",[]).has(building.asset_id) and raw.resource_accounts.get(quote.get("payee_account_id"),{}).get("owner_ref")==quote.seller_ref and int(quote.use_until_day)==int(receipt.get("day",-2147483647))+int(quote.duration_days)
static func validate(raw: Dictionary) -> Dictionary:
	for building in raw.management_assets.values():
		if building.get("asset_kind")!="estate_building":continue
		var history: Variant=building.get("property_history",[])
		if not history is Array:return Contract.fail("房产交割历史结构损坏")
		var origin: Dictionary=raw.economic_contracts.get(building.source_ref.get("entity_id"),{})
		var title: Dictionary=origin.get("owner_ref",{}).duplicate(true)
		var seen: Dictionary={}
		for ref in history:
			var sale: Dictionary=raw.economic_contracts.get(ref,{})
			if seen.has(ref) or sale.get("contract_kind")!="estate_property_sale" or sale.get("building_id")!=building.asset_id or sale.get("seller_ref")!=title:return Contract.fail("房产产权无法沿唯一原交割历史回读")
			seen[ref]=true;title=sale.get("buyer_ref",{}).duplicate(true)
		if title!=building.owner_ref:return Contract.fail("当前房产产权与原工程及交割不符")
		for field in ["property_offer","operation_offer"]:
			var quote: Variant=building.get(field,{})
			if not quote is Dictionary:return Contract.fail("房产报价结构损坏")
			if quote.get("active",false) and (not _signed(raw,building,quote) or quote.seller_ref!=building.owner_ref):return Contract.fail("房产报价未获真实产权主体签署")
	for row in raw.economic_contracts.values():
		if row.get("contract_kind") not in ["estate_property_sale","estate_operating_right"]:continue
		var building: Dictionary=raw.management_assets.get(row.get("building_id"),{})
		var quote: Variant=row.get("quote")
		if not quote is Dictionary or building.get("asset_kind")!="estate_building" or not _signed(raw,building,quote) or row.get("seller_ref")!=quote.seller_ref or row.get("amount")!=quote.amount or row.get("payee_account_id")!=quote.payee_account_id or not Contract.amount(row.get("day")) or int(row.day)>int(raw.current_day) or row.day>quote.valid_until_day or row.get("use_until_day")!=quote.use_until_day or row.get("until_day")!=quote.use_until_day or int(row.day)>=int(row.until_day) or not row.get("source_shops") is Array:return Contract.fail("房产或经营权缺少明确原报价、期限与签署")
		var payment: Dictionary=raw.resource_journal.get(row.get("receipt_id"),{})
		var receipt: Dictionary=raw.action_receipts.get(row.get("receipt_id"),{})
		if receipt.has("npc_estate_trade_decision"):
			var decision: Variant=receipt.npc_estate_trade_decision
			if not decision is Dictionary or not str(decision.get("source_id","")).begins_with("scenario:") or decision.get("building_id")!=building.asset_id or decision.get("buyer_id")!=row.get("buyer_ref",{}).get("entity_id") or decision.get("day")!=row.day or not raw.action_receipts.get(decision.get("contact_receipt"),{}).get("effect_refs",[]).has(row.contract_id):return Contract.fail("具名NPC房产接洽缺少原决策及玩家接洽回执")
		if raw.resource_accounts.get(row.get("funding_account_id"),{}).get("owner_ref")!=row.get("buyer_ref") or payment.get("source_account_id")!=row.get("funding_account_id") or payment.get("destination_account_id")!=row.payee_account_id or payment.get("amount")!=row.amount or payment.get("reason_ref")!=row.contract_id or payment.get("day")!=row.day or not receipt.get("effect_refs",[]).has(row.contract_id) or not building.contract_refs.has(row.contract_id) or row.get("land_id")!=building.land_id or row.get("execution_refs")!=[row.receipt_id]:return Contract.fail("房产或经营权缺少原支付、权利及交割回执")
		if row.contract_kind=="estate_property_sale":
			if row.status!="settled" or not building.get("property_history",[]).has(row.contract_id) or not Contract.amount(row.get("book_value")) or row.get("disposal_loss")!=maxi(0,int(row.book_value)-int(row.amount)) or row.get("disposal_gain")!=maxi(0,int(row.amount)-int(row.book_value)):return Contract.fail("房产交割或处置损益不符")
			var invested: int=0
			for source_id in row.source_shops:invested+=int(load("res://scripts/core/business_financial_projection.gd").statement(raw,str(source_id),0,int(row.day)).capital_investment)
			if row.source_shops.is_empty():invested=property_basis(raw,building,int(receipt.state_revision_after))
			if invested!=int(row.book_value):return Contract.fail("房产处置投入与原工程、设施账目不符")
		else:
			if row.status not in ["active","ended"] or row.get("operator_ref")!=row.buyer_ref or not row.get("operating_shop_id") is String:return Contract.fail("经营权主体或状态损坏")
			if row.operating_shop_id!="" and raw.management_assets.get(row.operating_shop_id,{}).get("operating_right_id")!=row.contract_id:return Contract.fail("经营权未指向真实经营资产")
		var sources: Dictionary={}
		for id in row.source_shops:
			if sources.has(id):return Contract.fail("房产移交不得重复同一原经营资产")
			sources[id]=true
			var shop: Dictionary=raw.management_assets.get(id,{})
			if shop.get("premises_kind")!="retired" or shop.get("status")!="closed" or shop.get("retirement_contract_id")!=row.contract_id or shop.get("building_id")!=building.asset_id:return Contract.fail("原经营单位必须保留停业账目及明确场所移交")
	return {"ok":true}
