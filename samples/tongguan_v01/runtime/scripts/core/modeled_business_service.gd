extends RefCounted
## Coarse monthly activity shares the world calendar, task engine and account journal.
const Contract = preload("res://scripts/core/management_state_contract.gd")
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Strategy = preload("res://scripts/core/business_strategy_rules.gd")
const Maintenance = preload("res://scripts/core/business_maintenance_condition.gd")
const Transport = preload("res://scripts/core/business_transport_conditions.gd")
const Labor = preload("res://scripts/core/business_labor_conditions.gd")
const Personnel = preload("res://scripts/core/business_personnel_conditions.gd")
const KINDS := ["settle_business_month"]
const MODELS := ["farm","extraction","processing","trade","service","logistics","finance"]

static func validate_config(value: Variant) -> Dictionary:
	if not value is Dictionary or value.get("model") not in MODELS: return Contract.fail("产业缺少有效的分类经营规则")
	for field in ["capacity","unit_revenue","unit_cost","monthly_demand","monthly_supply","build_cost","build_days","area_units","maturity_days","interest_percent","bad_debt_percent"]:
		if not Contract.amount(value.get(field),field in ["capacity","monthly_demand","monthly_supply","build_cost","build_days","area_units"]): return Contract.fail("产业经营参数无效："+field)
	if int(value.interest_percent)>100 or int(value.bad_debt_percent)>100 or not value.get("harvest_months") is Array or not value.get("market_key") is String or value.market_key.is_empty(): return Contract.fail("产业季节、需求或金融比例无效")
	for month in value.harvest_months:
		if not Contract.amount(month,true) or int(month)>12: return Contract.fail("产业采收月份无效")
	if value.model=="farm" and value.harvest_months.is_empty(): return Contract.fail("农牧产业须明确采收季节")
	if value.model!="finance" and int(value.unit_revenue)<=0: return Contract.fail("非金融产业须有实际单位收入")
	return {"ok":true}

static func calculate(config: Dictionary, inputs: Dictionary) -> Dictionary:
	var result := {"quantity":0,"revenue":0,"cost":0,"loss":0,"exposure":0,"reason":"当前需求、供给或营运资金不足"}
	if inputs.has("personnel"):result["personnel_loss"]=0
	if not validate_config(config).ok: result.reason="经营配置无效"; return result
	var strategy_id: String=str(inputs.get("strategy","balanced"))
	if not Strategy.valid(strategy_id): result.reason="经营方针无效"; return result
	var strategy: Dictionary=Strategy.MODES[strategy_id]
	if int(inputs.get("age_days",0))<int(config.maturity_days): result.reason="等待成园或养殖成熟"; return result
	if config.model=="farm" and not config.harvest_months.any(func(month):return int(month)==int(inputs.get("month",0))): result.reason="等待采收季节；工资与维护仍按约支付"; return result
	var efficiency: float=clampf(float(inputs.get("efficiency",1.0)),0.0,1.5)
	if inputs.has("personnel"):efficiency*=float(inputs.personnel.efficiency_factor)
	var order: float=clampf(float(inputs.get("order",1.0)),0.0,1.0)
	var wealth: float=clampf(float(inputs.get("wealth",1.0)),0.0,1.5)
	var relations: float=clampf(float(inputs.get("relations",1.0)),0.8,1.2)
	var fraction: float=clampf(float(inputs.get("period_days",30))/30.0,0.0,1.0)
	var capacity: int=int(float(config.capacity)*efficiency*order*fraction*float(strategy.capacity)*Maintenance.factor(inputs.get("maintenance",{})))
	capacity=int(float(capacity)*float(inputs.get("facility",{}).get("capacity_factor",1.0)))
	if config.model=="logistics": capacity=int(float(capacity)*Transport.availability(inputs.get("transport",{})))
	capacity=int(float(capacity)*Labor.factor(inputs.get("labor",{})))
	var population_factor: float=maxf(0.0,float(inputs.get("population_factor",1.0)))
	var demand: int=mini(int(inputs.get("demand",0)),int(float(config.monthly_demand)*population_factor*wealth*relations*fraction))
	var supply: int=mini(int(inputs.get("supply",0)),int(config.monthly_supply))
	if config.model!="finance": supply=int(float(supply)*Transport.supply_factor(inputs.get("transport",{})))
	var cash: int=maxi(0,int(inputs.get("cash",0)))
	if cash==0 or order==0.0: return result
	var unit_cost: int=int(ceil(float(config.unit_cost)*float(strategy.cost)/maxf(0.6,efficiency)))
	var financed: int=cash if config.model=="finance" else cash/maxi(1,unit_cost+int(ceil(float(unit_cost)*float(strategy.waste))))
	var quantity: int=maxi(0,mini(mini(capacity,demand),mini(supply,financed)))
	result.quantity=quantity
	result.cost=quantity*unit_cost if config.model!="finance" else 0
	result.revenue=quantity*int(config.unit_revenue) if config.model!="finance" else quantity*int(config.interest_percent)/100
	result.loss=int(float(quantity)*minf(100.0,float(config.bad_debt_percent)*float(strategy.bad_debt))/100.0) if config.model=="finance" else int(ceil(float(result.cost)*float(strategy.waste)))
	result.exposure=quantity if config.model=="finance" else 0
	if inputs.has("personnel"):
		var risk_base: int=quantity if config.model=="finance" else int(result.cost)
		result["personnel_loss"]=mini(maxi(0,cash-int(result.cost)-int(result.loss)),int(ceil(float(risk_base)*float(inputs.personnel.loss_percent)/100.0)))
		result.loss+=int(result.personnel_loss)
	if quantity>0: result.reason="本期产能 %d，需求上限 %d，供给上限 %d；实际经营 %d。负责人效率与地方秩序影响产能，财富与关系影响需求。" % [capacity,maxi(0,demand),maxi(0,supply),quantity]
	if inputs.has("population_factor"):
		result.reason+=" 城内客源为开局登记的%.1f%%（迁居收支口径）。" % (population_factor*100.0) if inputs.get("population_source_known",true) else " 当地无人口登记，客源暂按经营配置基准。"
	if inputs.has("strategy"): result.reason+=" 经营方针：%s；扩张提高规模与单位投入，并计入周转损耗或较高坏账。" % strategy.name
	var turnover_loss: int=int(result.loss)-int(result.get("personnel_loss",0))
	if inputs.has("strategy") and config.model!="finance" and turnover_loss>0: result.reason+=" 本期周转损耗 %d，计入经营成本。" % turnover_loss
	if inputs.has("maintenance"): result.reason+=" "+Maintenance.description(inputs.maintenance)
	if inputs.has("transport"): result.reason+=" "+Transport.description(inputs.transport)
	if inputs.has("labor"): result.reason+=" "+Labor.description(inputs.labor)
	if inputs.has("personnel"):result.reason+=" 原负责人伤病、压力与兼任作用于有效能力；本期经办差错风险损失%d，沿原损耗交割，不作为已确认侵吞。" % int(result.personnel_loss)
	return result

static func site_ready(land: Dictionary, spec: Dictionary) -> bool:
	if spec.get("chronology")!="current_scope": return false
	var features: Array=land.get("site_features",[])
	for key in spec.requirements:
		if key=="premises": continue
		if key=="arable" and land.get("agricultural_resources",{}).get("arable",false): continue
		if key=="tea_soil" and land.development_offers.has("tea_garden"): continue
		if not features.has(key): return false
	if spec.model=="extraction" and int(land.get("resource_deposits",{}).get(spec.industry_id,{}).get("remaining",0))<=0: return false
	return true

static func _month(state) -> int:
	return int(state.current_day)-int(state.current_date.day)+1

static func spent(state, shop_id: String) -> int:
	var result := 0
	for row in state.economic_contracts.values():
		if row.get("contract_kind")=="business_month" and row.shop_id==shop_id and int(row.month_start)==_month(state): result+=int(row.result.cost)+int(row.result.loss)
	return result

static func quote(state, shop: Dictionary, policy: Dictionary) -> Dictionary:
	var config: Dictionary=shop.operation_terms.config
	var start: int=_month(state)
	if int(state.current_date.day)!=30: return {"reason":"日常由负责人处理；月末结算经营收支"}
	var id: String="business-month:"+shop.asset_id+":"+str(start)
	if state.economic_contracts.has(id): return {"reason":"本月已结算，等待下一经营月份"}
	var ready: Dictionary=load("res://scripts/core/pawnshop_service.gd")._ready_to_trade(state,shop)
	if not ready.ok: return {"reason":str(ready.error)}
	var stats: Dictionary=state.character_states[ready.person_id].get("stats",{})
	var node: Dictionary=state.local_node_state[shop.location_id]
	var fit: float=Personnel.fit(stats,str(config.model))
	var order: float=float(mini(int(node.get("security",0)),int(node.get("public_order",0))))/100.0
	if order<0.2: order=0.0
	var population_factor: float=preload("res://scripts/core/regional_population_service.gd").factor(state,str(shop.location_id))
	var demand: int=int(float(config.monthly_demand)*population_factor)
	var supply: int=int(config.monthly_supply)
	for other in state.economic_contracts.values():
		if other.get("contract_kind")!="business_month" or other.location_id!=shop.location_id or int(other.month_start)!=start: continue
		if other.config.market_key==config.market_key: demand-=int(other.result.quantity); supply-=int(other.result.quantity)
	var land: Dictionary=state.management_assets[state.management_assets[shop.building_id].land_id]
	if config.model=="extraction": supply=mini(supply,int(land.get("resource_deposits",{}).get(shop.industry_kind,{}).get("remaining",0)))
	var cash: int=maxi(0,Accounts.new().available(state,shop.account_id,str(policy.get("reservation_ref","")))-int(policy.cash_floor))
	cash=mini(cash,mini(int(policy.monthly_limit)-spent(state,shop.asset_id),int(policy.loan_limit)))
	var relations: float=clampf(1.0+float(state.character_states[ready.person_id].get("relationships",{}).get(state.player_character_id,0))/500.0,0.8,1.2)
	var inputs := {"efficiency":0.6+fit*0.008,"wealth":clampf(float(node.get("prosperity",50))/50.0,0.4,1.5),"order":order,"relations":relations,"demand":maxi(0,demand),"supply":maxi(0,supply),"cash":cash,"age_days":int(state.current_day)-int(shop.opened_day),"month":int(state.current_date.month),"period_days":mini(30,int(state.current_day)-maxi(start,int(shop.opened_day))+1)}
	inputs["population_factor"]=population_factor
	inputs["strategy"]=str(policy.get("strategy","balanced"))
	inputs["maintenance"]=Maintenance.snapshot(state,shop.asset_id)
	inputs["facility"]=preload("res://scripts/core/estate_lifecycle_service.gd").facility_snapshot(state,str(shop.asset_id))
	inputs["transport"]=Transport.snapshot(state,shop.location_id)
	inputs["labor"]=Labor.snapshot(state,shop.location_id)
	inputs["personnel"]=Personnel.snapshot(state,shop,ready.person_id)
	inputs["population_source_known"]=not preload("res://scripts/core/regional_population_service.gd").at_node(state,str(shop.location_id)).is_empty()
	inputs["population_movement_count"]=state.flags.get("regional_population_movements",{}).size()
	var result := calculate(config,inputs)
	var buyer: String=shop.operation_terms.market_account_id
	var buyer_cash: int=maxi(0,Accounts.new().available(state,buyer))
	# A finite account pays the aggregated regional customer demand.
	if int(result.revenue)>buyer_cash:
		inputs.demand=mini(int(inputs.demand),buyer_cash/int(config.unit_revenue)) if config.model!="finance" else mini(int(inputs.demand),buyer_cash*100/maxi(1,int(config.interest_percent)))
		result=calculate(config,inputs)
	return {"month_id":id,"month_start":start,"inputs":inputs,"result":result,"manager_id":ready.person_id,"reason":result.reason}

static func choose(state, auth: Dictionary) -> Dictionary:
	var shop: Dictionary=state.management_assets[auth.business_policy.shop_id]
	var prepared := quote(state,shop,auth.business_policy)
	if not prepared.has("month_id"): return prepared
	return {"kind":"settle_business_month","parameters":{"shop_id":shop.asset_id,"month_start":prepared.month_start}}

static func cost_for(state, kind: String, params: Dictionary) -> Dictionary:
	var shop: Dictionary=state.management_assets.get(params.get("shop_id"),{})
	if kind not in KINDS or shop.get("asset_kind")!="modeled_business" or not Contract.amount(float(params.get("month_start",-30))+29): return Contract.fail("月度经营须指定实际产业与结算月份")
	var auth: Dictionary=load("res://scripts/core/business_management_service.gd").current(state,shop.asset_id)
	if auth.is_empty(): return Contract.fail("产业尚无有效负责人经营授权")
	var policy: Dictionary=auth.business_policy.duplicate(true)
	policy["reservation_ref"]=auth.reservation_refs.get(shop.account_id,"")
	var prepared := quote(state,shop,policy)
	if not prepared.has("result") or int(params.month_start)!=int(prepared.month_start): return Contract.fail(str(prepared.reason))
	return {"ok":true,"account_id":shop.account_id,"amount":int(prepared.result.cost)+int(prepared.result.loss)}

static func guard(state, auth: Dictionary, kind: String, params: Dictionary, executor: String = "") -> Dictionary:
	if kind not in KINDS or params.get("shop_id")!=auth.business_policy.shop_id: return Contract.fail("月度经营超出授权产业")
	var shop: Dictionary=state.management_assets[params.shop_id]
	var policy: Dictionary=auth.business_policy.duplicate(true)
	policy["reservation_ref"]=auth.reservation_refs.get(shop.account_id,"")
	var prepared := quote(state,shop,policy)
	if shop.status!="open" or not prepared.has("result") or params.month_start!=prepared.month_start: return Contract.fail("产业停业、本月已结算或月份已变化")
	if executor!="" and executor!=prepared.manager_id: return Contract.fail("当前负责人已变化")
	return {"ok":true}

static func apply(state, kind: String, params: Dictionary, principal: String, execution: String, reservation: String = "") -> Dictionary:
	var auth: Dictionary=load("res://scripts/core/business_management_service.gd").current(state,params.shop_id)
	var allowed := guard(state,auth,kind,params)
	if not allowed.ok: return allowed
	var shop: Dictionary=state.management_assets[params.shop_id]
	var policy: Dictionary=auth.business_policy.duplicate(true); policy["reservation_ref"]=reservation
	var prepared := quote(state,shop,policy)
	var outcome: Dictionary=prepared.result
	var terms: Dictionary=shop.operation_terms
	var payments := [{"suffix":"cost","source":shop.account_id,"target":terms.supplier_account_id,"amount":int(outcome.cost),"actor":principal},{"suffix":"loss","source":shop.account_id,"target":terms.market_account_id,"amount":int(outcome.loss),"actor":principal},{"suffix":"income","source":terms.market_account_id,"target":shop.account_id,"amount":int(outcome.revenue),"actor":terms.market_operator_id}]
	for payment in payments:
		if payment.amount==0: continue
		if not Accounts.new().can_operate(state,payment.source,payment.actor) or Accounts.new().available(state,payment.source,reservation if payment.source==shop.account_id else "")<payment.amount or Accounts.new().balance(state,payment.target)>Contract.MAX_AMOUNT-payment.amount: return Contract.fail("经营付款账户、余额或收款容量不满足条件")
	var refs: Array=[]
	for payment in payments:
		if payment.amount==0: continue
		var ref: String=execution+":"+str(payment.suffix)
		var paid := Accounts.new().apply(state,"transfer",{"execution_id":ref,"source_account_id":payment.source,"destination_account_id":payment.target,"amount":payment.amount,"actor_id":payment.actor,"reason_ref":prepared.month_id,"reservation_id":reservation if payment.source==shop.account_id else ""})
		if not paid.ok: return paid
		refs.append(ref)
	var land: Dictionary=state.management_assets[state.management_assets[shop.building_id].land_id]
	if shop.operation_terms.config.model=="extraction": land.resource_deposits[shop.industry_kind].remaining-=int(outcome.quantity)
	state.economic_contracts[prepared.month_id]={"contract_id":prepared.month_id,"contract_kind":"business_month","status":"settled","shop_id":shop.asset_id,"location_id":shop.location_id,"month_start":prepared.month_start,"day":int(state.current_day),"manager_id":prepared.manager_id,"config":terms.config.duplicate(true),"inputs":prepared.inputs,"result":outcome,"execution_id":execution,"execution_refs":refs,"terms_version":1}
	shop.contract_refs.append(prepared.month_id)
	return {"ok":true,"result_ref":prepared.month_id,"journal_refs":refs,"visible_summary":"月度经营收入 %d，经营投入 %d，损耗或坏账 %d；%s。" % [outcome.revenue,outcome.cost,outcome.loss,outcome.reason]}

static func append_statement(state, shop: Dictionary, result: Dictionary, from_day: int, through_day: int) -> void:
	for row in state.economic_contracts.values():
		if row.get("contract_kind")!="business_month" or row.shop_id!=shop.asset_id or int(row.day)<from_day or int(row.day)>through_day: continue
		result.revenue+=int(row.result.revenue); result.goods_cost+=int(row.result.cost); result.sold_quantity+=int(row.result.quantity)
		if row.config.model=="finance": result.bad_debt+=int(row.result.loss)
		else: result.goods_cost+=int(row.result.loss)
		result.causes.append(str(row.result.reason))
	result.causes.append("按月合并普通供销；分类模型 %s。建设款、营运本钱和本金周转不计利润，工资与维护另列。" % shop.operation_terms.config.model)

static func validate(raw: Dictionary) -> Dictionary:
	var seen := {}
	for shop in raw.management_assets.values():
		if shop.get("asset_kind")!="modeled_business": continue
		var terms: Variant=shop.get("operation_terms")
		if not terms is Dictionary or not validate_config(terms.get("config")).ok or not raw.resource_accounts.has(terms.get("market_account_id")) or not raw.resource_accounts.has(terms.get("supplier_account_id")) or not Accounts.new().can_operate(raw,terms.market_account_id,str(terms.get("market_operator_id",""))): return Contract.fail("分类产业缺少经营配置或地区供销账户")
		if terms!=raw.management_assets[shop.building_id].get("operation_terms"): return Contract.fail("产业经营条款与竣工来源不符")
	for row in raw.economic_contracts.values():
		if row.get("contract_kind")!="business_month": continue
		var shop: Dictionary=raw.management_assets.get(row.get("shop_id"),{})
		if shop.get("asset_kind")!="modeled_business" or row.get("config")!=shop.operation_terms.config or not row.get("inputs") is Dictionary or not row.get("result") is Dictionary: return Contract.fail("月度经营结果与分类规则不符")
		if row.inputs.has("maintenance"):
			if row.inputs.has("facility"):
				var facilities: Dictionary=preload("res://scripts/core/estate_lifecycle_service.gd").validate_facility(raw,str(shop.asset_id),int(row.get("day",0)),row.inputs.facility)
				if not facilities.ok:return facilities
			var checked := Maintenance.validate(raw,shop.asset_id,int(row.get("day",0)),row.inputs.maintenance)
			if not checked.ok: return checked
		if row.inputs.has("transport"):
			var checked := Transport.validate(raw,shop.location_id,row.inputs.transport)
			if not checked.ok: return checked
		if row.inputs.has("labor"):
			var checked := Labor.validate(raw,shop.location_id,int(row.get("day",0)),row.inputs.labor)
			if not checked.ok: return checked
		if row.inputs.has("personnel"):
			var checked: Dictionary=Personnel.validate(row.inputs.personnel,str(row.get("manager_id","")),int(row.get("day",0)))
			if not checked.ok:return checked
		var expected_result := calculate(row.config,row.inputs)
		if row.inputs.has("population_factor"):
			var movement_count: int=int(row.inputs.get("population_movement_count",-1))
			if row.inputs.has("population_movement_count") and (not Contract.amount(row.inputs.population_movement_count) or movement_count>raw.flags.get("regional_population_movements",{}).size()): return Contract.fail("月结人口来源序号无效")
			var expected_population: float=preload("res://scripts/core/regional_population_service.gd").factor(raw,str(shop.location_id),int(row.get("day",0)),movement_count)
			if not is_equal_approx(float(row.inputs.population_factor),expected_population): return Contract.fail("月结客源与当日迁居来源不符")
		if row.result.size()!=expected_result.size() or row.result.get("reason")!=expected_result.reason: return Contract.fail("月度经营结果与分类规则不符")
		# JSON numbers reload as floats; compare validated integer amounts, not Variant dictionary types.
		for field in ["quantity","revenue","cost","loss","exposure"]:
			if not Contract.amount(row.result.get(field)) or int(row.result[field])!=int(expected_result[field]): return Contract.fail("月度经营结果与分类规则不符")
		if row.inputs.has("personnel") and (not Contract.amount(row.result.get("personnel_loss")) or int(row.result.personnel_loss)!=int(expected_result.personnel_loss)):return Contract.fail("负责人经办损失与原结算不符")
		var key: String=str(row.shop_id)+":"+str(int(row.get("month_start",0)))
		if seen.has(key) or not Contract.amount(row.get("day")) or int(row.day)>int(raw.current_day) or int(row.month_start)!=int(row.day)-29 or row.contract_id!="business-month:"+key: return Contract.fail("经营月份重复或日期无效")
		seen[key]=true
		var receipt: Dictionary=raw.action_receipts.get(row.get("execution_id"),{})
		if row.inputs.has("strategy"):
			var policy: Dictionary=raw.action_authorizations.get(receipt.get("authorization_id"),{}).get("business_policy",{})
			if not Strategy.valid(row.inputs.strategy) or row.inputs.strategy!=policy.get("strategy","balanced"): return Contract.fail("月结方针与当时批准的经营授权不符")
		if not receipt.get("effect_refs",[]).has(row.contract_id) or receipt.get("executor_id")!=row.get("manager_id") or int(receipt.get("day",-1))!=int(row.day): return Contract.fail("月度经营缺少实际负责人回执")
		var expected: Array=[]
		for suffix in ["cost","loss","income"]:
			var amount: int=int(row.result[{"cost":"cost","loss":"loss","income":"revenue"}[suffix]])
			if amount==0: continue
			var ref: String=row.execution_id+":"+suffix
			var paid: Dictionary=raw.resource_journal.get(ref,{})
			var source: String=shop.operation_terms.market_account_id if suffix=="income" else shop.account_id
			var target: String=shop.operation_terms.supplier_account_id if suffix=="cost" else shop.account_id if suffix=="income" else shop.operation_terms.market_account_id
			if paid.get("reason_ref")!=row.contract_id or paid.get("source_account_id")!=source or paid.get("destination_account_id")!=target or int(paid.get("amount",-1))!=amount or int(paid.get("day",-1))!=int(row.day): return Contract.fail("月度经营款项与原账户流水不符")
			expected.append(ref)
		if row.execution_refs!=expected or receipt.get("journal_refs")!=expected: return Contract.fail("月度经营资金凭据缺失或重复")
	for land in raw.management_assets.values():
		if land.get("asset_kind")!="land": continue
		for id in land.get("resource_deposits",{}):
			var deposit: Dictionary=land.resource_deposits[id]
			if not Contract.amount(deposit.get("initial"),true) or not Contract.amount(deposit.get("remaining")): return Contract.fail("资源储量不能为负")
			var used := 0
			for row in raw.economic_contracts.values():
				if row.get("contract_kind")!="business_month": continue
				var shop: Dictionary=raw.management_assets[row.shop_id]
				if shop.industry_kind==id and raw.management_assets[shop.building_id].land_id==land.asset_id: used+=int(row.result.quantity)
			if int(deposit.remaining)!=int(deposit.initial)-used: return Contract.fail("开采量与登记剩余储量不符")
	return {"ok":true}
