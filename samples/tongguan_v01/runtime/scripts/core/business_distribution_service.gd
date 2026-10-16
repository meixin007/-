extends RefCounted
const Accounts=preload("res://scripts/core/resource_account_service.gd")
const Finance=preload("res://scripts/core/business_financial_projection.gd")
const Contract=preload("res://scripts/core/management_state_contract.gd")
const KIND="distribute_business_surplus"

static func quote(state, shop_id: String) -> Dictionary:
	var shop: Dictionary=state.management_assets.get(shop_id,{})
	var statement: Dictionary=Finance.statement(state,shop_id,0,int(state.current_day))
	if statement.is_empty(): return {"available":0,"profit_remaining":0,"cash_floor":0,"obligations":0}
	var auth: Dictionary=load("res://scripts/core/business_management_service.gd").current(state,shop_id)
	var floor_cash: int=int(auth.get("business_policy",{}).get("cash_floor",0))
	var obligations := 0
	var horizon: int=int(state.current_day)+30
	for row in state.economic_contracts.values():
		if row.get("contract_kind") not in ["employment","lease","maintenance"]: continue
		var terms: Dictionary=row.remuneration_terms if row.contract_kind=="employment" else {"account_id":row.funding_account_id,"amount":row.amount,"period_days":row.period_days}
		if row.contract_kind=="employment":
			terms=load("res://scripts/core/business_wage_service.gd").terms_on_day(row,int(row.next_due_day))
			if auth.get("business_policy",{}).get("payroll_from_shop",false) and load("res://scripts/core/business_payroll_service.gd")._employee(auth.business_policy,row,shop):terms.account_id=shop.account_id
		if terms.account_id!=shop.account_id: continue
		if row.status=="active":
			var count: int=maxi(0,1+(horizon-int(row.next_due_day))/int(terms.period_days)) if horizon>=int(row.next_due_day) else 0
			obligations+=load("res://scripts/core/business_wage_service.gd").due_total(row,horizon) if row.contract_kind=="employment" else count*int(terms.amount)
		else: obligations+=int(row.get("arrears",0))
	var profit: int=maxi(0,int(statement.net_profit)-int(statement.capital_withdrawn))
	var liquid: int=maxi(0,Accounts.new().available(state,shop.account_id)-floor_cash-obligations)
	return {"available":mini(profit,liquid) if int(statement.current_arrears)==0 else 0,"profit_remaining":profit,"cash_floor":floor_cash,"obligations":obligations}

static func cost_for(state, params: Dictionary) -> Dictionary:
	var shop: Dictionary=state.management_assets.get(params.get("shop_id"),{})
	var destination: Dictionary=state.resource_accounts.get(params.get("destination_account_id"),{})
	if shop.get("asset_kind") not in ["pawnshop","retail_shop","manufacturing_shop","managed_farm","modeled_business"] or not Contract.amount(params.get("amount"),true): return Contract.fail("结余转回须指定产业和有效金额")
	if destination.get("owner_ref")!=shop.owner_ref or destination.get("unit_id")!="cash_unit" or destination.get("account_id")==shop.account_id: return Contract.fail("经营结余只能转回同一产权主体的资金账户")
	if Accounts.new().location(state,shop.account_id)!=Accounts.new().location(state,destination.account_id): return Contract.fail("异地结余须通过原运输或交割规则，不可即时汇兑")
	if int(params.amount)>int(quote(state,shop.asset_id).available): return Contract.fail("金额超过可转回结余；须先清偿产业欠付款，并保留资金预留、现金底线及本店账户未来30日合同支出")
	return {"ok":true,"account_id":shop.account_id,"amount":int(params.amount)}

static func apply(state, params: Dictionary, principal: String, execution: String) -> Dictionary:
	var checked := cost_for(state,params)
	if not checked.ok: return checked
	var shop: Dictionary=state.management_assets[params.shop_id]
	if state.character_states[principal].get("location_id")!=shop.location_id or not Accounts.new().can_operate(state,shop.account_id,principal) or not Accounts.new().can_operate(state,params.destination_account_id,principal): return Contract.fail("本人没有同地产业及收款账户的交割权限")
	var paid := Accounts.new().apply(state,"transfer",{"execution_id":execution,"source_account_id":shop.account_id,"destination_account_id":params.destination_account_id,"amount":int(params.amount),"actor_id":principal,"reason_ref":shop.asset_id})
	if not paid.ok: return paid
	return {"ok":true,"result_ref":shop.asset_id,"journal_refs":[execution],"visible_summary":"已转回经营结余%d；不重复计作营业利润。" % int(params.amount)}
