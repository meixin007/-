extends RefCounted
## Coordinate signed regional ceilings over existing local money and shop mandates.
const Regional=preload("res://scripts/core/regional_business_policy_service.gd")
const Contract=preload("res://scripts/core/management_state_contract.gd")
const Accounts=preload("res://scripts/core/resource_account_service.gd")
const KIND="set_portfolio_business_budget"

static func executors(state, data: Dictionary) -> Array:
	var result: Array=[]
	var ids: Array=state.character_states.keys(); ids.sort()
	for id in ids:
		if not preload("res://scripts/core/player_assistant_service.gd").eligible(state,data,id).ok: continue
		var workload=preload("res://scripts/core/character_workload_service.gd")
		if workload.can_schedule(state,id,"management",state.player_character_id) or workload.can_schedule(state,id,"pawnshop",state.player_character_id): result.append({"id":id,"name":str(state.character_states[id].name)})
	return result

static func options(state, data: Dictionary, assets: Array, regional_options: Array) -> Array:
	var groups := {}
	for region in regional_options:
		var first: Dictionary=state.management_assets[region.shops[0].shop_id]
		var owner: Dictionary=first.owner_ref
		var key: String=str(owner.entity_kind)+":"+str(owner.entity_id)
		if not groups.has(key):
			var visible: Array=assets.filter(func(row):return row.asset_id==first.asset_id)
			groups[key]={"id":key,"owner_ref":owner.duplicate(true),"name":visible[0].owner_name,"regions":[],"minimum":0,"maximum":0,"current":0}
		groups[key].regions.append(region.duplicate(true))
		for field in ["minimum","maximum","current"]: groups[key][field]+=int(region[field])
	var result: Array=[]
	var keys: Array=groups.keys(); keys.sort()
	keys=keys.filter(func(key):return groups[key].regions.size()>=2)
	if keys.is_empty(): return result
	var candidates: Array=executors(state,data)
	for key in keys:
		var option: Dictionary=groups[key]
		if option.regions.size()<2: continue
		option.regions.sort_custom(func(a,b):return a.location_id<b.location_id)
		option["executors"]=candidates.duplicate(true)
		option["unknown_regions"]=[]
		for row in assets:
			if not row.has("financials") or row.owner_ref!=option.owner_ref: continue
			if option.regions.any(func(region):return region.location_id==row.location_id): continue
			if not option.unknown_regions.has(row.location_id): option.unknown_regions.append(row.location_id)
		option["basis"]="各州分别保留当地资金、负责人及现金底线；只调整已批准的经营限额。远地候选依据最新已收月报，执行时复核实际资金，资料不足的地区另列。"
		result.append(option)
	return result.duplicate(true)

static func parameters(option: Dictionary, total: int, executor: String, regional_totals: Array = []) -> Dictionary:
	var bounds := {"location_id":"","minimum":option.minimum,"shops":[]}
	for region in option.regions: bounds.shops.append({"shop_id":region.location_id,"minimum":region.minimum,"maximum":region.maximum,"expected_authorization_id":""})
	var split: Dictionary=Regional.parameters(bounds,total)
	var regions: Array=[]
	for i in option.regions.size():
		var regional_total: int=int(regional_totals[i]) if regional_totals.size()==option.regions.size() else int(split.allocations[i].monthly_limit)
		regions.append(Regional.parameters(option.regions[i],regional_total))
	return {"owner_ref":option.owner_ref.duplicate(true),"total_budget":total,"regions":regions,"executor_id":executor}

static func targets(params: Dictionary) -> Array:
	var result: Array=[params.owner_ref.entity_id]
	for region in params.regions:
		result.append(region.location_id)
		for row in region.allocations: result.append(row.shop_id)
	return result

static func cost_for(state, params: Dictionary) -> Dictionary:
	var owner: Variant=params.get("owner_ref")
	if not owner is Dictionary or owner.get("entity_kind") not in ["character","clan","organization"] or not owner.get("entity_id") is String or str(owner.entity_id).is_empty() or not Contract.amount(params.get("total_budget"),true) or not params.get("regions") is Array or params.regions.size()<2: return Contract.fail("跨州经营预算须列明同一产权主体、至少两处地区及总限额")
	var seen := {}
	var storage_refs: Array=[]
	var total := 0
	for region in params.regions:
		if not region is Dictionary or not region.get("location_id") is String or seen.has(region.location_id): return Contract.fail("同一地区不能重复分配经营预算")
		var checked := Regional.cost_for(state,region)
		if not checked.ok: return checked
		seen[region.location_id]=true
		for row in region.allocations:
			var shop: Dictionary=state.management_assets[row.shop_id]
			if shop.owner_ref!=params.owner_ref: return Contract.fail("跨州总预算不能混用不同产权主体的产业")
			var storage: Dictionary=state.resource_accounts[shop.account_id].storage_ref
			if storage_refs.has(storage): return Contract.fail("跨州产业不能重复使用同一实际资金")
			storage_refs.append(storage)
		if int(region.total_budget)>int(params.total_budget)-total: return Contract.fail("各州经营限额超过已批准总预算")
		total+=int(region.total_budget)
	if total!=int(params.total_budget): return Contract.fail("各州经营限额之和须等于已批准总预算")
	return {"ok":true,"account_id":"","amount":0}

static func prepare(state, data: Dictionary, params: Dictionary) -> Dictionary:
	var checked := cost_for(state,params)
	if not checked.ok: return checked
	var executor: String=str(params.get("executor_id",""))
	if not executors(state,data).any(func(row):return row.id==executor): return Contract.fail("总管须在身边、愿意受托且有可安排的工作日")
	for region in params.regions:
		for row in region.allocations:
			if not Accounts.new().can_operate(state,state.management_assets[row.shop_id].account_id,state.player_character_id): return Contract.fail("委托人无权安排所选产业预算")
	var id := "portfolio-budget:%s:%d" % [executor,int(state.state_revision)]
	var action_params: Dictionary=params.duplicate(true); action_params.erase("executor_id")
	var refs := targets(params)
	var auth := {"authorization_id":"auth:"+id,"principal_id":state.player_character_id,"delegate_id":executor,"scope":{"action_kinds":[KIND],"target_refs":refs,"allow_subdelegation":false},"resource_limits":[],"version":1,"status":"active","valid_until_day":null}
	var plan := {"task_id":id,"name":"跨州经营预算 · "+str(state.character_states[executor].name),"executor_id":executor,"steps":[{"step_id":"regional-ceilings","action_kind":KIND,"target_refs":refs.duplicate(),"parameters":action_params,"depends_on":[]}]}
	return {"ok":true,"authorization":auth,"plan":plan}

static func submit(context, params: Dictionary, revision: int, execution: String) -> Dictionary:
	if int(context.state.state_revision)!=revision: return Contract.fail("跨州预算预览已变化，请重新查看")
	var prepared := prepare(context.state,context.scenario_data,params)
	if not prepared.ok: return prepared
	var result: Dictionary=load("res://scripts/core/action_authorization_service.gd").new().submit_plan(context,prepared.authorization,prepared.plan,execution)
	if result.ok: result["visible_summary"]="已委派%s统筹%d处地区，月度经营限额合计%d；随每日推进复核办理，各店资金保留原地。" % [context.state.character_states[params.executor_id].name,params.regions.size(),int(params.total_budget)]
	return result

static func apply(state, data: Dictionary, params: Dictionary, principal: String, execution: String) -> Dictionary:
	var checked := cost_for(state,params)
	if not checked.ok: return checked
	for region in params.regions:
		for row in region.allocations:
			if not Accounts.new().can_operate(state,state.management_assets[row.shop_id].account_id,principal): return Contract.fail("本人无权调整所选产业预算")
			var shop: Dictionary=state.management_assets[row.shop_id]
			var mandate: Dictionary=load("res://scripts/core/business_management_service.gd").current(state,row.shop_id)
			if state.office_state.get(shop.office_id,{}).get("holder_id")!=mandate.business_policy.manager_id: return Contract.fail("有地区负责人已变化，请先办理交接后重新安排总预算")
	var dispatcher=load("res://scripts/core/game_action_dispatcher.gd")
	for region in params.regions:
		var id: String=execution+":"+str(region.location_id)
		var refs: Array=[region.location_id]
		for row in region.allocations: refs.append(row.shop_id)
		var changed: Dictionary=dispatcher.apply(state,data,{"execution_id":id,"request_id":id,"actor_id":principal,"principal_id":principal,"executor_id":principal,"action_kind":Regional.KIND,"target_refs":refs,"parameters":region.duplicate(true),"expected_state_revision":state.state_revision})
		if not changed.ok:
			changed["rollback_required"]=true
			return changed
	return {"ok":true,"result_ref":params.owner_ref.entity_id,"visible_summary":"已按批准总额%d调整%d处地区经营限额；各店资金、负责人和现金底线保留。" % [int(params.total_budget),params.regions.size()]}
