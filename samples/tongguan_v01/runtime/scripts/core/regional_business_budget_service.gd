extends RefCounted
## A budget is an atomic transfer into existing shop accounts, never a second balance.
const Accounts=preload("res://scripts/core/resource_account_service.gd")
const Contract=preload("res://scripts/core/management_state_contract.gd")
const KIND="allocate_regional_business_budget"

static func options(state, assets: Array) -> Array:
	var actor: String=state.player_character_id
	var place: String=state.character_states[actor].get("location_id","")
	var accounts=Accounts.new()
	var result: Array=[]
	for source in state.resource_accounts.values():
		if source.get("unit_id")!="cash_unit" or accounts.location(state,source.account_id)!=place or not accounts.can_operate(state,source.account_id,actor): continue
		# Shop tills cannot double as a common regional funding pool.
		if state.management_assets.values().any(func(shop):return shop.get("account_id")==source.account_id): continue
		var shops: Array=[]
		var minimum := 0
		for visible in assets:
			var shop: Dictionary=state.management_assets.get(visible.get("asset_id"),{})
			if shop.get("owner_ref")!=source.owner_ref or shop.get("location_id")!=place or not shop.has("account_id"): continue
			if not accounts.can_operate(state,shop.account_id,actor): continue
			var auth: Dictionary=load("res://scripts/core/business_management_service.gd").current(state,shop.asset_id)
			if auth.is_empty(): continue
			var policy: Dictionary=auth.business_policy
			var needed: int=maxi(1,int(policy.monthly_limit)+int(policy.cash_floor)-accounts.available(state,shop.account_id))
			shops.append({"shop_id":shop.asset_id,"name":shop.name,"minimum":needed})
			minimum+=needed
		if shops.is_empty(): continue
		shops.sort_custom(func(a,b):return a.shop_id<b.shop_id)
		var owner_name := "本主体资金"
		for visible in assets:
			if visible.get("owner_ref")==source.owner_ref: owner_name=str(visible.get("owner_name",owner_name)); break
		result.append({"funding_account_id":source.account_id,"name":owner_name,"location_id":place,"available":accounts.available(state,source.account_id),"minimum":minimum,"shops":shops})
	return result.duplicate(true)

static func parameters(option: Dictionary, total: int) -> Dictionary:
	var rows: Array=[]
	var extra: int=maxi(0,total-int(option.minimum))
	for i in option.shops.size():
		rows.append({"shop_id":option.shops[i].shop_id,"amount":int(option.shops[i].minimum)+extra/option.shops.size()+(1 if i<extra%option.shops.size() else 0)})
	return {"funding_account_id":option.funding_account_id,"location_id":option.location_id,"total_budget":total,"allocations":rows}

static func cost_for(state, params: Dictionary, reservation_id: String = "") -> Dictionary:
	var source: Dictionary=state.resource_accounts.get(params.get("funding_account_id"),{})
	if source.get("unit_id")!="cash_unit" or not Contract.amount(params.get("total_budget"),true): return Contract.fail("地区预算须指定资金账户及正整数总额")
	if not params.get("allocations") is Array or params.allocations.is_empty() or not params.get("location_id") is String: return Contract.fail("地区预算须列明地区及各产业拨款")
	var accounts=Accounts.new()
	if accounts.location(state,source.account_id)!=params.location_id: return Contract.fail("地区拨款须从本地账户交割；异地资金须先运输到账")
	var seen: Array=[source.storage_ref]
	var total := 0
	for row in params.allocations:
		if not row is Dictionary or not row.get("shop_id") is String or not Contract.amount(row.get("amount"),true): return Contract.fail("每笔拨款须列明产业及有效金额")
		var shop: Dictionary=state.management_assets.get(row.shop_id,{})
		if shop.get("asset_kind") not in ["pawnshop","retail_shop","manufacturing_shop","managed_farm","modeled_business"]: return Contract.fail("拨款目标必须是实际产业")
		var storage: Dictionary=state.resource_accounts[shop.account_id].storage_ref
		if seen.has(storage): return Contract.fail("预算不可重复拨给同一产业账户，也不可转给来源账户")
		seen.append(storage)
		if shop.owner_ref!=source.owner_ref or shop.location_id!=params.location_id: return Contract.fail("一份地区预算只向本地同一产权主体的产业拨款")
		if accounts.location(state,shop.account_id)!=params.location_id or accounts.balance(state,shop.account_id)>Contract.MAX_AMOUNT-int(row.amount): return Contract.fail("收款账户地点不符或拨款后余额超限")
		var auth: Dictionary=load("res://scripts/core/business_management_service.gd").current(state,shop.asset_id)
		if auth.is_empty(): return Contract.fail("请先为各产业落实负责人和经营授权")
		var policy: Dictionary=auth.business_policy
		if accounts.available(state,shop.account_id)+int(row.amount)<int(policy.monthly_limit)+int(policy.cash_floor): return Contract.fail("拨款后可用现金不足支持该店现有月度授权及保留现金，请调整预算或经营限额")
		if int(row.amount)>int(params.total_budget)-total: return Contract.fail("分配金额超过本次批准的总预算")
		total+=int(row.amount)
	if total!=int(params.total_budget): return Contract.fail("各店拨款合计须等于本次总预算")
	if total>accounts.available(state,source.account_id,reservation_id): return Contract.fail("总预算超过来源账户扣除其他任务预留后的可用资金")
	return {"ok":true,"account_id":source.account_id,"amount":total}

static func apply(state, params: Dictionary, principal: String, execution: String, reservation_id: String = "", executor: String = "") -> Dictionary:
	var checked := cost_for(state,params,reservation_id)
	if not checked.ok: return checked
	var accounts=Accounts.new()
	var operator := principal if executor.is_empty() else executor
	if state.character_states[operator].get("location_id")!=params.location_id or not accounts.can_operate(state,params.funding_account_id,principal): return Contract.fail("经办人须在交割地点，委托人须有资金账户权限")
	for row in params.allocations:
		if not accounts.can_operate(state,state.management_assets[row.shop_id].account_id,principal): return Contract.fail("本人无权向所选产业拨款")
	var journals: Array=[]
	for row in params.allocations:
		var id: String=execution+":"+row.shop_id
		var paid: Dictionary=accounts.apply(state,"transfer",{"execution_id":id,"source_account_id":params.funding_account_id,"destination_account_id":state.management_assets[row.shop_id].account_id,"amount":int(row.amount),"actor_id":principal,"reason_ref":row.shop_id,"reservation_id":reservation_id})
		if not paid.ok:
			paid["rollback_required"]=true
			return paid
		journals.append(id)
	return {"ok":true,"result_ref":params.funding_account_id,"journal_refs":journals,"visible_summary":"已向本地%d家产业拨款合计%d；沿用原经营授权，拨款不计营业收入。" % [params.allocations.size(),int(params.total_budget)]}
