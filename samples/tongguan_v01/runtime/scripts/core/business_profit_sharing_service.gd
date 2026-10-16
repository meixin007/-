extends RefCounted
## Approved monthly allocations of realized surplus; no second clock or account balance.
const Contract=preload("res://scripts/core/management_state_contract.gd")
const Accounts=preload("res://scripts/core/resource_account_service.gd")
static func current(state, shop_id: String) -> Dictionary:
	var shop: Dictionary=state.management_assets.get(shop_id,{})
	return state.economic_contracts.get(shop.get("profit_policy_id"),{})
static func cost_for(state, params: Dictionary) -> Dictionary:
	var shop: Dictionary=state.management_assets.get(params.get("shop_id"),{})
	var auth: Dictionary=load("res://scripts/core/business_management_service.gd").current(state,str(params.get("shop_id","")))
	var destination: Dictionary=state.resource_accounts.get(params.get("destination_account_id"),{})
	if auth.is_empty() or auth.authorization_id!=params.get("expected_authorization_id") or not Contract.amount(params.get("manager_percent")) or not Contract.amount(params.get("remit_percent")) or int(params.manager_percent)+int(params.remit_percent)>100:return Contract.fail("须核对当前负责人授权；分红与上缴比例合计不能超过100%")
	if destination.get("unit_id")!="cash_unit" or destination.get("owner_ref")!=shop.get("owner_ref") or destination.get("account_id")==shop.get("account_id"):return Contract.fail("上缴账户须是同一真实产权主体的另一现金账户")
	return {"ok":true,"account_id":"","amount":0}
static func apply(state, params: Dictionary, principal: String, execution: String) -> Dictionary:
	var checked:=cost_for(state,params)
	if not checked.ok:return checked
	var shop: Dictionary=state.management_assets[params.shop_id]
	var auth: Dictionary=load("res://scripts/core/business_management_service.gd").current(state,shop.asset_id)
	if state.character_states[principal].location_id!=shop.location_id or not Accounts.new().can_operate(state,shop.account_id,principal) or not Accounts.new().can_operate(state,params.destination_account_id,principal):return Contract.fail("须由在当地且有店款、收款权限的真实持有人确认")
	var former:=current(state,shop.asset_id)
	if not former.is_empty():former.status="superseded"
	var id: String="business-profit-policy:"+execution
	var terms: Dictionary={"shop_id":shop.asset_id,"owner_ref":shop.owner_ref.duplicate(true),"manager_id":auth.business_policy.manager_id,"principal_id":principal,"manager_percent":int(params.manager_percent),"remit_percent":int(params.remit_percent),"destination_account_id":params.destination_account_id,"source_authorization_id":auth.authorization_id,"signed_day":int(state.current_day)}
	state.economic_contracts[id]={"contract_id":id,"contract_kind":"business_profit_policy","status":"active","terms":terms,"receipt_id":execution,"shop_id":shop.asset_id,"terms_version":1,"party_refs":[shop.owner_ref.entity_id,terms.manager_id],"execution_refs":[execution],"last_checked_day":int(state.current_day),"blocked_reason":""}
	shop["profit_policy_id"]=id;shop.contract_refs.append(id)
	return {"ok":true,"result_ref":id,"business_profit_policy":terms.duplicate(true),"visible_summary":"已约定负责人利润分红%d%%、产权主体上缴%d%%、其余留存；仅分配已实现可用结余，欠款、预留及未来支出优先，异地资金不即时转移。" % [terms.manager_percent,terms.remit_percent]}
static func settle_daily(state) -> Dictionary:
	for shop in state.management_assets.values():
		var rule: Dictionary=current(state,str(shop.asset_id))
		if rule.is_empty() or rule.status!="active" or int(rule.last_checked_day)>=int(state.current_day):continue
		var end: int=int(state.current_day)-int(state.current_date.day)
		var id: String="business-profit-distribution:"+shop.asset_id+":"+str(end)
		if end<int(rule.terms.signed_day) or state.economic_contracts.has(id):continue
		rule.last_checked_day=int(state.current_day)
		var terms: Dictionary=rule.terms
		var auth: Dictionary=load("res://scripts/core/business_management_service.gd").current(state,shop.asset_id)
		if auth.is_empty() or auth.principal_id!=terms.principal_id or auth.business_policy.manager_id!=terms.manager_id or state.office_state[shop.office_id].holder_id!=terms.manager_id:
			rule.blocked_reason="原经营授权或具名受领负责人已变化，先核对并重新确认分配。";continue
		var manager_cash: String=terms.manager_id+"_cash"
		if not load("res://scripts/core/production_service.gd").present(state,terms.manager_id,shop.location_id) or Accounts.new().location(state,manager_cash)!=Accounts.new().location(state,shop.account_id) or Accounts.new().location(state,terms.destination_account_id)!=Accounts.new().location(state,shop.account_id):
			rule.blocked_reason="分红或上缴收款方不在同一交割地点；店款保留，须先按原规则安排到账。";continue
		var source: Dictionary=load("res://scripts/core/business_financial_projection.gd").statement(state,shop.asset_id,maxi(0,end-29),end)
		var quote: Dictionary=load("res://scripts/core/business_distribution_service.gd").quote(state,shop.asset_id)
		var base: int=mini(maxi(0,int(source.net_profit)),int(quote.available))
		var manager_amount: int=base*int(terms.manager_percent)/100
		var owner_amount: int=base*int(terms.remit_percent)/100
		if manager_amount+owner_amount<=0:rule.blocked_reason="本期无足额可分配的已实现结余；优先保留欠款、预留及未来合同支出。";continue
		if Accounts.new().balance(state,manager_cash)>Contract.MAX_AMOUNT-manager_amount or Accounts.new().balance(state,terms.destination_account_id)>Contract.MAX_AMOUNT-owner_amount:rule.blocked_reason="收款账户已达金额边界，店款保留待处理。";continue
		var available: int=Accounts.new().available(state,shop.account_id)
		var cash_before: int=Accounts.new().balance(state,shop.account_id)
		var refs: Array=[]
		for item in [{"part":"manager","amount":manager_amount,"account":manager_cash},{"part":"owner","amount":owner_amount,"account":terms.destination_account_id}]:
			if int(item.amount)==0:continue
			var paid_id: String=id+":"+item.part
			var paid: Dictionary=Accounts.new().apply(state,"transfer",{"execution_id":paid_id,"source_account_id":shop.account_id,"destination_account_id":item.account,"amount":int(item.amount),"actor_id":terms.principal_id,"reason_ref":id})
			if not paid.ok:paid["rollback_required"]=true;return paid
			refs.append(paid_id)
		state.economic_contracts[id]={"contract_id":id,"contract_kind":"business_profit_distribution","status":"settled","shop_id":shop.asset_id,"policy_id":rule.contract_id,"manager_id":terms.manager_id,"manager_amount":manager_amount,"owner_amount":owner_amount,"base":base,"source_from_day":maxi(0,end-29),"source_through_day":end,"source_profit":int(source.net_profit),"available_before":int(quote.available),"cash_before":cash_before,"cash_floor":int(quote.cash_floor),"obligations":int(quote.obligations),"reserved":cash_before-available,"day":int(state.current_day),"source_authorization_id":auth.authorization_id,"terms_version":1,"party_refs":[shop.owner_ref.entity_id,terms.manager_id],"execution_refs":refs}
		shop.contract_refs.append(id);rule.blocked_reason=""
	return {"ok":true}
static func validate(raw: Dictionary) -> Dictionary:
	for row in raw.economic_contracts.values():
		if row.get("contract_kind")=="business_profit_policy":
			var terms: Variant=row.get("terms")
			if not terms is Dictionary:return Contract.fail("利润分配约定损坏")
			var shop: Dictionary=raw.management_assets.get(terms.get("shop_id"),{})
			var auth: Dictionary=raw.action_authorizations.get(terms.get("source_authorization_id"),{})
			var receipt: Dictionary=raw.action_receipts.get(row.get("receipt_id"),{})
			if not auth.get("business_policy",{}) is Dictionary or not Contract.amount(row.get("last_checked_day")) or int(row.last_checked_day)>int(raw.current_day) or not row.get("blocked_reason") is String or not Contract.amount(terms.get("signed_day")):return Contract.fail("利润约定缺少原日期、授权或处理状态")
			if row.get("status") not in ["active","superseded"] or shop.get("owner_ref")!=terms.get("owner_ref") or auth.get("business_policy",{}).get("shop_id")!=shop.get("asset_id") or auth.get("business_policy",{}).get("manager_id")!=terms.get("manager_id") or auth.get("principal_id")!=terms.get("principal_id") or not Contract.amount(terms.get("manager_percent")) or not Contract.amount(terms.get("remit_percent")) or int(terms.manager_percent)+int(terms.remit_percent)>100 or raw.resource_accounts.get(terms.get("destination_account_id"),{}).get("owner_ref")!=shop.get("owner_ref") or receipt.get("business_profit_policy")!=terms or receipt.get("executor_id")!=terms.principal_id or receipt.get("day")!=terms.get("signed_day") or not receipt.get("effect_refs",[]).has(row.contract_id) or not shop.get("contract_refs",[]).has(row.contract_id) or (row.status=="active" and shop.get("profit_policy_id")!=row.contract_id):return Contract.fail("利润分配缺少真实主体、比例、原授权及明确确认")
		elif row.get("contract_kind")=="business_profit_distribution":
			var rule: Dictionary=raw.economic_contracts.get(row.get("policy_id"),{})
			var terms: Dictionary=rule.get("terms",{})
			var shop: Dictionary=raw.management_assets.get(row.get("shop_id"),{})
			var auth: Dictionary=raw.action_authorizations.get(row.get("source_authorization_id"),{})
			if shop.get("asset_kind") not in ["pawnshop","retail_shop","manufacturing_shop","managed_farm","modeled_business"] or not auth.get("business_policy",{}) is Dictionary or auth.get("business_policy",{}).get("shop_id")!=shop.get("asset_id"):return Contract.fail("利润分配不得借用其他产业的授权")
			if rule.get("contract_kind")!="business_profit_policy" or terms.get("shop_id")!=row.get("shop_id") or row.get("manager_id")!=terms.get("manager_id") or auth.get("business_policy",{}).get("manager_id")!=terms.get("manager_id") or auth.get("principal_id")!=terms.get("principal_id") or row.get("status")!="settled" or not Contract.amount(row.get("day")) or int(row.day)>int(raw.current_day) or not Contract.amount(row.get("source_through_day")) or int(row.source_through_day)<int(terms.get("signed_day",2147483647)) or int(row.source_through_day)>=int(row.day) or int(row.day)-int(row.source_through_day)>30 or row.get("source_from_day")!=maxi(0,int(row.source_through_day)-29) or row.contract_id!="business-profit-distribution:"+str(shop.get("asset_id"))+":"+str(int(row.source_through_day)):return Contract.fail("分红期次、真实负责人或原经营授权不符")
			for field in ["base","manager_amount","owner_amount","available_before","cash_before","cash_floor","obligations","reserved"]:
				if not Contract.amount(row.get(field)):return Contract.fail("分红金额或现金保护边界损坏")
			var source: Dictionary=load("res://scripts/core/business_financial_projection.gd").statement(raw,shop.asset_id,int(row.source_from_day),int(row.source_through_day))
			var prior: Dictionary=load("res://scripts/core/business_financial_projection.gd").statement(raw,shop.asset_id,0,int(row.day)-1)
			var actual_cash: Dictionary=load("res://scripts/core/business_financial_projection.gd").statement(raw,shop.asset_id,int(row.day),int(row.day))
			if actual_cash.opening_cash!=row.cash_before:return Contract.fail("利润分配前现金与原账户流水不符")
			if source.net_profit!=row.get("source_profit") or int(row.base)!=mini(maxi(0,int(source.net_profit)),int(row.available_before)) or int(row.available_before)>maxi(0,int(prior.net_profit)-int(prior.capital_withdrawn)) or int(row.available_before)>maxi(0,int(row.cash_before)-int(row.cash_floor)-int(row.obligations)-int(row.reserved)) or row.cash_floor!=auth.business_policy.cash_floor or int(row.manager_amount)!=int(row.base)*int(terms.manager_percent)/100 or int(row.owner_amount)!=int(row.base)*int(terms.remit_percent)/100 or int(row.manager_amount)+int(row.owner_amount)<=0:return Contract.fail("分红超出实际利润、现金或已签比例")
			var expected: Array=[]
			for part in ["manager","owner"]:
				var amount: int=int(row.manager_amount if part=="manager" else row.owner_amount)
				if amount==0:continue
				var id: String=row.contract_id+":"+part
				var paid: Dictionary=raw.resource_journal.get(id,{})
				if paid.get("source_account_id")!=shop.account_id or paid.get("destination_account_id")!=(str(terms.manager_id)+"_cash" if part=="manager" else terms.destination_account_id) or paid.get("amount")!=amount or paid.get("day")!=row.day or paid.get("reason_ref")!=row.contract_id:return Contract.fail("分红缺少原账户实际付款回执")
				expected.append(id)
			if row.get("execution_refs")!=expected or not shop.get("contract_refs",[]).has(row.contract_id):return Contract.fail("分红不能复制或丢失原交割来源")
	for shop in raw.management_assets.values():
		if shop.has("profit_policy_id") and raw.economic_contracts.get(shop.profit_policy_id,{}).get("contract_kind")!="business_profit_policy":return Contract.fail("产业利润规则引用失效")
	return {"ok":true}
