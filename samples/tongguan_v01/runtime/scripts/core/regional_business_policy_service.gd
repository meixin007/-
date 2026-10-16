extends RefCounted
## Regional operating ceilings reuse existing per-shop authorizations and cash.
const Accounts=preload("res://scripts/core/resource_account_service.gd")
const Contract=preload("res://scripts/core/management_state_contract.gd")
const KIND="set_regional_business_budget"

static func options(state, assets: Array, location_names: Dictionary = {}) -> Array:
	var business=load("res://scripts/core/business_management_service.gd")
	var actor: String=state.player_character_id
	var groups := {}
	for visible in assets:
		if not visible.has("financials"): continue
		var shop: Dictionary=state.management_assets.get(visible.asset_id,{})
		var auth: Dictionary=business.current(state,visible.asset_id)
		if auth.is_empty() or auth.principal_id!=actor or not Accounts.new().can_operate(state,shop.account_id,actor): continue
		var local: bool=state.character_states[actor].get("location_id")==shop.location_id
		var available := 0
		var minimum := 1
		if local:
			available=Accounts.new().available(state,shop.account_id)
			minimum=maxi(1,business.month_spent(state,shop.asset_id))
		else:
			var reports: Array=visible.financials.get("received",[])
			if reports.is_empty(): continue
			available=int(reports[0].closing_cash)
		var key: String=shop.location_id+":"+str(shop.owner_ref.entity_kind)+":"+str(shop.owner_ref.entity_id)
		var location_name: String=str(location_names.get(shop.location_id,state.local_node_state.get(shop.location_id,{}).get("name","当地")))
		if location_name==shop.location_id: location_name="当地"
		if not groups.has(key): groups[key]={"id":key,"location_id":shop.location_id,"name":location_name+" · "+str(visible.owner_name),"local":local,"minimum":0,"maximum":0,"current":0,"shops":[]}
		var maximum: int=maxi(0,available-int(auth.business_policy.cash_floor))
		var row := {"shop_id":shop.asset_id,"name":shop.name,"expected_authorization_id":auth.authorization_id,"minimum":minimum,"maximum":maximum}
		groups[key].shops.append(row)
		groups[key].minimum+=minimum
		groups[key].maximum+=maximum
		groups[key].current+=int(auth.business_policy.monthly_limit)
	var result: Array=[]
	var keys: Array=groups.keys(); keys.sort()
	for key in keys:
		groups[key].shops.sort_custom(func(a,b):return a.shop_id<b.shop_id)
		var included: Array=groups[key].shops.map(func(row):return row.shop_id)
		var first: Dictionary=state.management_assets[included[0]]
		if state.management_assets.values().any(func(shop):return shop.get("location_id")==first.location_id and shop.get("owner_ref")==first.owner_ref and not business.current(state,shop.asset_id).is_empty() and not included.has(shop.asset_id)): continue
		result.append(groups[key])
	return result.duplicate(true)

static func parameters(option: Dictionary, total: int) -> Dictionary:
	var rows: Array=[]
	for shop in option.shops: rows.append({"shop_id":shop.shop_id,"monthly_limit":int(shop.minimum),"expected_authorization_id":shop.expected_authorization_id})
	var remaining: int=maxi(0,total-int(option.minimum))
	while remaining>0:
		var eligible: Array=[]
		for i in rows.size():
			if int(rows[i].monthly_limit)<int(option.shops[i].maximum): eligible.append(i)
		if eligible.is_empty(): break
		var share: int=maxi(1,remaining/eligible.size())
		for i in eligible:
			var addition: int=mini(remaining,mini(share,int(option.shops[i].maximum)-int(rows[i].monthly_limit)))
			rows[i].monthly_limit+=addition
			remaining-=addition
	return {"location_id":option.location_id,"total_budget":total,"allocations":rows}

static func cost_for(state, params: Dictionary) -> Dictionary:
	if not params.get("location_id") is String or not Contract.amount(params.get("total_budget"),true) or not params.get("allocations") is Array or params.allocations.is_empty(): return Contract.fail("地区经营预算须列明地点、总限额和逐店分配")
	var business=load("res://scripts/core/business_management_service.gd")
	var owner := {}
	var seen: Array=[]
	var total := 0
	var included: Array=[]
	for row in params.allocations:
		if not row is Dictionary: return Contract.fail("产业预算条款无效")
		var checked: Dictionary=business.cost_for(state,"set_business_budget",row)
		if not checked.ok: return checked
		var shop: Dictionary=state.management_assets[row.shop_id]
		if shop.location_id!=params.location_id: return Contract.fail("请按产业所在地区分别安排经营预算")
		if owner.is_empty(): owner=shop.owner_ref
		if owner!=shop.owner_ref: return Contract.fail("不同产权主体的经营预算须分别安排")
		var storage: Dictionary=state.resource_accounts[shop.account_id].storage_ref
		if seen.has(storage): return Contract.fail("同一产业资金不可重复取得经营限额")
		seen.append(storage)
		included.append(shop.asset_id)
		if int(row.monthly_limit)>int(params.total_budget)-total: return Contract.fail("分配的店铺限额超过地区总预算")
		total+=int(row.monthly_limit)
	if total!=int(params.total_budget): return Contract.fail("各店限额之和须等于地区经营总预算")
	if state.management_assets.values().any(func(shop):return shop.get("location_id")==params.location_id and shop.get("owner_ref")==owner and not business.current(state,shop.asset_id).is_empty() and not included.has(shop.asset_id)): return Contract.fail("地区总预算须包含本主体在当地全部已授权产业")
	return {"ok":true,"account_id":"","amount":0}

static func apply(state, data: Dictionary, params: Dictionary, principal: String, execution: String) -> Dictionary:
	var checked := cost_for(state,params)
	if not checked.ok: return checked
	# Validate every account before replacing any grant; the caller owns the world transaction.
	for row in params.allocations:
		if not Accounts.new().can_operate(state,state.management_assets[row.shop_id].account_id,principal): return Contract.fail("本人无权调整所选产业的经营预算")
	var dispatcher=load("res://scripts/core/game_action_dispatcher.gd")
	for row in params.allocations:
		var id: String=execution+":"+row.shop_id
		var changed: Dictionary=dispatcher.apply(state,data,{"execution_id":id,"request_id":id,"actor_id":principal,"principal_id":principal,"executor_id":principal,"action_kind":"set_business_budget","target_refs":[row.shop_id],"parameters":row.duplicate(true),"expected_state_revision":state.state_revision})
		if not changed.ok: return changed
	return {"ok":true,"result_ref":params.location_id,"visible_summary":"已调整%d家产业的月度限额，地区合计%d；本月已用额度保留，资金位置不变。" % [params.allocations.size(),int(params.total_budget)]}
