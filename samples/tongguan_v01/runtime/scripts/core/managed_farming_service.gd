extends RefCounted

const Contract = preload("res://scripts/core/management_state_contract.gd")
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Storage = preload("res://scripts/core/resource_storage_adapter.gd")
const Presence = preload("res://scripts/core/production_service.gd")
const Workload = preload("res://scripts/core/character_workload_service.gd")
const Season = preload("res://scripts/core/agricultural_season.gd")
const Numbers = preload("res://scripts/core/public_works_service.gd")
const Retail = preload("res://scripts/core/retail_trading_service.gd")
const Products = preload("res://scripts/core/resource_commodity_definitions.gd")
const KINDS := ["commission_farm_season", "sell_farm_product"]

static func land_for(state, farm: Dictionary) -> Dictionary:
	return state.management_assets[state.management_assets[farm.building_id].land_id]

# Tree age comes from the original completed planting project, never a new
# appointment, purchase, opening date or mutable second clock.
static func crop_readiness(state, farm: Dictionary) -> Dictionary:
	var terms: Dictionary = farm.get("agricultural_terms", {})
	var recipe: Dictionary = terms.get("recipe", {})
	var seasonal := Season.validate(recipe)
	if not seasonal.ok: return seasonal
	if not Contract.amount(state.current_day) or Numbers.date_serial(state.current_date)<0: return Contract.fail("农季缺少有效的共同日历")
	var result := {"ok":true,"season_year":Season.season_year(recipe,state.current_date)}
	if terms.get("good_id")=="tea":
		var building: Dictionary = state.management_assets.get(farm.get("building_id"),{})
		var source: Dictionary = building.get("source_ref",{})
		var project: Dictionary = state.economic_contracts.get(source.get("entity_id"),{})
		var maturity := 3*Season.Calendar.MONTHS_PER_YEAR*Season.Calendar.DAYS_PER_MONTH
		if recipe.get("maturity_days")!=maturity: return Contract.fail("茶树成园等待须采用已定义的三年游戏农时")
		if not recipe.harvest_months.all(func(month): return int(month) in [2,3,4]): return Contract.fail("当前茶园规则仅登记春季二至四月采制")
		if building.get("asset_kind")!="estate_building" or building.get("industry_kind")!="tea_garden" or building.get("status") not in ["completed","in_use"] or source.get("entity_kind")!="contract" or project.get("contract_kind")!="estate_construction" or project.get("status")!="completed" or project.get("building_id")!=farm.get("building_id") or project.get("recipe",{}).get("industry_kind")!="tea_garden" or project.get("recipe",{}).get("agricultural_terms")!=terms or not Contract.amount(project.get("completed_day")) or int(project.completed_day)>int(state.current_day): return Contract.fail("茶树树龄缺少本园已竣工建园合同")
		var seedlings := 0
		if not project.recipe.get("inputs") is Array: return Contract.fail("建园合同缺少苗木投入")
		for input in project.recipe.inputs:
			if not input is Dictionary: return Contract.fail("建园材料记录无效")
			var stock: Dictionary = state.management_assets.get(input.get("stock_id"),{})
			if stock.get("material_key")!="tea_seedlings": continue
			if stock.get("asset_kind")!="material_stock" or not Contract.amount(input.get("quantity"),true) or stock.get("consumptions",{}).get(project.get("contract_id"))!=input.quantity: return Contract.fail("茶苗没有随实际建园工程消耗")
			seedlings+=int(input.quantity)
		if seedlings==0: return Contract.fail("房屋竣工不能凭空附送茶树")
		var age := int(state.current_day)-int(project.completed_day)
		result.merge({"established_day":int(project.completed_day),"age_days":age,"remaining_days":maxi(0,maturity-age)})
		if age<maturity:
			result.merge({"ok":false,"code":"immature_perennial","error":"茶树尚未成园，还需等待 %d 日；不提前采购采制或记收获。" % (maturity-age)},true)
			return result
	elif terms.get("good_id") not in ["grain","tea"]: return Contract.fail("未登记的农业产品不能推定农时")
	if int(result.season_year)<1 or not Season.contains_month(recipe.plant_months,int(state.current_date.month)):
		result.merge({"ok":false,"code":"outside_crop_season","error":"未到本季农事窗口，保留资金和库存等待农时。"},true)
	return result

static func spent(state, id: String) -> int:
	var total := 0
	for order in state.economic_contracts.values():
		if order.get("contract_kind")=="managed_cultivation" and order.shop_id==id and int(order.created_day)>=Retail.month_start(state): total += int(order.recipe.price)
	return total

static func sale_quote(state, farm: Dictionary, manager: String) -> Dictionary:
	var terms: Dictionary = farm.agricultural_terms
	var buyer: Dictionary = terms.buyer
	if int(buyer.valid_until_day)<int(state.current_day) or not Presence.present(state,buyer.buyer_id,farm.location_id) or not Accounts.new().can_operate(state,buyer.account_id,buyer.buyer_id): return Contract.fail("粮食买方未到场、没有付款权或购买约定已过期")
	var capacity := Retail.capacity(state,farm,manager)
	if not capacity.ok: return capacity
	var sold := 0
	for sale in state.economic_contracts.values():
		if sale.get("contract_kind")!="farm_sale" or int(sale.day)<Retail.month_start(state): continue
		if sale.buyer_id==buyer.buyer_id and sale.get("good_id")==terms.good_id and state.management_assets[sale.shop_id].location_id==farm.location_id: sold += int(sale.quantity)
	var demand := maxi(0,int(buyer.monthly_quantity)-sold)
	var cash := Accounts.new().available(state,buyer.account_id)
	var quantity := mini(Retail.held(farm),mini(demand,mini(cash/int(terms.unit_sale_price),int(capacity.capacity))))
	return {"ok":true,"quantity":quantity,"remaining_demand":demand,"buyer_cash":cash,"capacity":capacity.capacity,"suitability":capacity.suitability,"security":capacity.security,"stock_on_hand":Retail.held(farm)}

static func cost_for(state, kind: String, params: Dictionary) -> Dictionary:
	var farm: Dictionary = state.management_assets.get(params.get("shop_id"),{})
	if farm.get("asset_kind")!="managed_farm" or kind not in KINDS: return Contract.fail("农事经营须指定实际田庄")
	if kind=="sell_farm_product" and not Contract.amount(params.get("quantity"),true): return Contract.fail("售粮数量须为实际正整数")
	return {"ok":true,"account_id":farm.account_id if kind=="commission_farm_season" else "","amount":int(farm.agricultural_terms.recipe.price) if kind=="commission_farm_season" else 0}

static func guard(state, auth: Dictionary, kind: String, params: Dictionary, executor: String = "") -> Dictionary:
	var policy: Dictionary = auth.business_policy
	if kind not in KINDS or policy.shop_id!=params.get("shop_id"): return Contract.fail("农事超出具体田庄授权")
	var valid := cost_for(state,kind,params)
	if not valid.ok: return valid
	var farm: Dictionary = state.management_assets[policy.shop_id]
	var ready: Dictionary = load("res://scripts/core/pawnshop_service.gd")._ready_to_trade(state,farm)
	if not ready.ok: return ready
	if farm.status!="open" or (executor!="" and executor!=ready.person_id): return Contract.fail("田庄未营业或庄头不能履职")
	if kind=="sell_farm_product":
		var quote := sale_quote(state,farm,ready.person_id)
		if not quote.ok: return quote
		if int(params.quantity)>int(quote.quantity): return Contract.fail("售粮超过实际库存、买方资金、接待能力或剩余需求")
		return {"ok":true}
	var recipe: Dictionary = farm.agricultural_terms.recipe
	var readiness := crop_readiness(state,farm)
	if not readiness.ok: return readiness
	var year := int(readiness.season_year)
	if state.economic_contracts.has("farm-season:%s:%d" % [farm.asset_id,year]): return Contract.fail("本田庄本生产季已投入，不能重播重扣种粮")
	if recipe.supplier_id==ready.person_id or not Presence.present(state,recipe.supplier_id,farm.location_id) or Workload.occupied_today(state,recipe.supplier_id,"",auth.principal_id,"managed_cultivation"): return Contract.fail("农工未到场或今日已有工作；庄头不能凭任命代替农工")
	if int(state.character_states[recipe.supplier_id].get("relationships",{}).get(auth.principal_id,0)) < -15: return Contract.fail("农工不愿承接这份农季合同")
	if farm.agricultural_terms.good_id=="grain" and (not Accounts.new().can_operate(state,recipe.seed_account_id,recipe.supplier_id) or Accounts.new().available(state,recipe.seed_account_id)<int(recipe.seed_units)): return Contract.fail("供种农工没有实际可用种粮")
	for other in state.economic_contracts.values():
		if other.get("contract_kind")=="managed_cultivation" and other.get("supplier_id")==recipe.supplier_id and other.status in ["growing","mature"]: return Contract.fail("农工还有未收割农季，不能同时承诺另一田庄")
	if int(recipe.price)>int(policy.loan_limit) or spent(state,farm.asset_id)+int(recipe.price)>int(policy.monthly_limit): return Contract.fail("本季工种粮投入超过获准单笔或本月额度")
	if Accounts.new().available(state,farm.account_id,str(auth.reservation_refs.get(farm.account_id,"")))-int(recipe.price)<int(policy.cash_floor): return Contract.fail("支付本季投入会低于现金底线")
	var assessed := Retail.capacity(state,farm,ready.person_id)
	if not assessed.ok: return assessed
	if int(assessed.security)<20: return Contract.fail("地方战乱或秩序过低，暂缓新播")
	return {"ok":true,"suitability":int(assessed.suitability),"manager_id":ready.person_id}

static func choose(state, auth: Dictionary) -> Dictionary:
	var farm: Dictionary = state.management_assets[auth.business_policy.shop_id]
	var ready: Dictionary = load("res://scripts/core/business_staff_service.gd").resolve(state,farm)
	if not ready.ok: return {"reason":ready.error}
	var quote := sale_quote(state,farm,ready.person_id)
	if quote.ok and quote.quantity>0: return {"kind":"sell_farm_product","parameters":{"shop_id":farm.asset_id,"quantity":quote.quantity}}
	var params := {"shop_id":farm.asset_id}
	var checked := guard(state,auth,"commission_farm_season",params,ready.person_id)
	return {"kind":"commission_farm_season","parameters":params} if checked.ok else {"reason":checked.error}

static func apply(state, kind: String, params: Dictionary, principal: String, executor: String, execution: String, reservation: String = "") -> Dictionary:
	var farm: Dictionary = state.management_assets[params.shop_id]
	var auth: Dictionary = load("res://scripts/core/business_management_service.gd").current(state,farm.asset_id)
	if auth.is_empty() or auth.principal_id!=principal: return Contract.fail("田庄须由实际获准庄头办理")
	var checked := guard(state,auth,kind,params,executor)
	if not checked.ok: return checked
	if kind=="sell_farm_product": return _sell(state,farm,params,principal,executor,execution)
	var recipe: Dictionary = farm.agricultural_terms.recipe
	var year := Season.season_year(recipe,state.current_date)
	var id := "farm-season:%s:%d" % [farm.asset_id,year]
	var paid := Accounts.new().apply(state,"transfer",{"execution_id":execution,"source_account_id":farm.account_id,"destination_account_id":recipe.payee_account_id,"amount":int(recipe.price),"actor_id":principal,"reason_ref":id,"reservation_id":reservation})
	if not paid.ok: return paid
	var seed_receipt := ""
	var journal_refs := [execution]
	if farm.agricultural_terms.good_id=="grain":
		var seed := Accounts.new().apply(state,"consume",{"execution_id":"seed:"+execution,"account_id":recipe.seed_account_id,"actor_id":recipe.supplier_id,"amount":int(recipe.seed_units),"reason_ref":"rule:farm_seed:"+id})
		if not seed.ok: seed["rollback_required"]=true; return seed
		seed_receipt="seed:"+execution
		journal_refs.append(seed_receipt)
	var order := {"contract_id":id,"contract_kind":"managed_cultivation","status":"growing","terms_version":1,"party_refs":[farm.owner_ref.entity_id,recipe.supplier_id],"execution_refs":[execution],"shop_id":farm.asset_id,"customer_id":principal,"supplier_id":recipe.supplier_id,"manager_id":executor,"manager_suitability":checked.suitability,"recipe":recipe.duplicate(true),"season_year":year,"created_day":int(state.current_day),"created_date":state.current_date.duplicate(true),"last_update_day":int(state.current_day),"last_work_day":int(state.current_day),"work_days":0,"work_log":[],"growth_log":[],"harvest_quantity":0,"harvest_receipt":"","seed_receipt":seed_receipt,"failure_code":"","blocked_reason":"等待作物生长"}
	_work(state,order,work_stages(farm)[0])
	state.economic_contracts[id]=order
	farm.contract_refs.append(id)
	return {"ok":true,"result_ref":id,"journal_refs":journal_refs,"visible_summary":("庄头已支付本季茶园管护采制工款 %d，工人实际整备，等待本季生长与采制。" if farm.agricultural_terms.good_id=="tea" else "庄头已支付本季种粮及农工款 %d；农工实际播种，等待生长与采收。") % recipe.price}

static func work_stages(farm: Dictionary) -> Array:
	return ["prepare","tend","harvest_process"] if farm.agricultural_terms.good_id=="tea" else ["plant","tend","harvest"]

static func _work(state, order: Dictionary, kind: String) -> void:
	Workload.record_work(state,order)
	order.work_log[-1]["kind"]=kind
	order.work_log[-1]["date"]=state.current_date.duplicate(true)

static func yield_quantity(land: Dictionary, order: Dictionary) -> int:
	if order.growth_log.size()!=int(order.recipe.growth_days): return 0
	var exposure := 0
	for row in order.growth_log: exposure += int(row.water_supply)*int(row.security)
	return int(land.agricultural_resources.cultivated_area_units)*int(order.recipe.units_per_area)*exposure*(750+int(order.manager_suitability)*5)/(10000000*int(order.recipe.growth_days))

static func settle_daily(state) -> Dictionary:
	var ids: Array = state.economic_contracts.keys(); ids.sort()
	for id in ids:
		var order: Dictionary = state.economic_contracts[id]
		if order.get("contract_kind")!="managed_cultivation" or order.status not in ["growing","mature"] or int(order.last_update_day)>=int(state.current_day): continue
		order.last_update_day=int(state.current_day)
		var farm: Dictionary = state.management_assets[order.shop_id]
		var land := land_for(state,farm)
		if not Season.within(order.recipe,int(order.season_year),state.current_date):
			_fail_crop(order,state.current_day,"out_of_season","已错过采收窗口，本季已付工种粮费用列为失收损失。")
			continue
		var node: Dictionary = state.local_node_state[farm.location_id]
		var security := mini(int(node.security),int(node.public_order))
		if order.growth_log.size()<int(order.recipe.growth_days): order.growth_log.append({"day":int(state.current_day),"date":state.current_date.duplicate(true),"water_supply":int(land.agricultural_resources.water_supply),"security":security})
		var can_work := security>=20 and Presence.present(state,order.supplier_id,farm.location_id) and not Workload.occupied_today(state,order.supplier_id,id,order.customer_id,"managed_cultivation")
		if int(order.work_days)<2 and can_work:
			_work(state,order,"tend"); can_work=false
		if order.growth_log.size()<int(order.recipe.growth_days): continue
		order.status="mature"
		if int(order.work_days)<2:
			_fail_crop(order,state.current_day,"untended","整个生长期无人实际照料，本季投入列为失收损失。")
			continue
		order.blocked_reason="等待采收月份、农工到场与安全空闲工日；原合同继续履行。"
		if not can_work or not Season.contains_month(order.recipe.harvest_months,int(state.current_date.month)): continue
		var quantity := yield_quantity(land,order)
		if quantity==0:
			_fail_crop(order,state.current_day,"zero_yield","实际水源与战乱影响导致零收获，本季投入列为损失。")
			continue
		var balance := Accounts.new().balance(state,farm.product_account_id)
		if balance>Contract.MAX_AMOUNT-quantity: return Contract.fail("田庄粮仓达到容量，日结未提交")
		_work(state,order,work_stages(farm)[2])
		var ref := "farm-harvest:"+str(id)
		if state.resource_journal.has(ref): return Contract.fail("同季收粮凭据已经存在")
		var account: Dictionary = state.resource_accounts[farm.product_account_id]
		Storage.write_balance(state,account.storage_ref,balance+quantity)
		state.resource_journal[ref]={"entry_id":ref,"execution_id":ref,"entry_kind":"rule_income","source_ref":{"entity_kind":"rule","entity_id":"rule:farm_harvest:"+id,"rule_id":"rule:farm_harvest:"+id},"destination_account_id":farm.product_account_id,"destination_ref":farm.owner_ref.duplicate(true),"amount":quantity,"unit_id":account.unit_id,"reason_ref":"rule:farm_harvest:"+str(id),"day":int(state.current_day)}
		order.status="harvested"; order.harvest_quantity=quantity; order.harvest_receipt=ref; order["ended_day"]=int(state.current_day)
		order.blocked_reason="本季茶叶已采制入库；尚未售出的成茶不是销售收入。" if farm.agricultural_terms.good_id=="tea" else "本季已收粮，存入田庄粮仓；尚未售出的粮食不是销售收入。"
		farm.stock_lots[id]={"remaining":quantity,"total_quantity":quantity,"total_cost":int(order.recipe.price)}
	return {"ok":true}

static func _fail_crop(order: Dictionary, day: int, code: String, reason: String) -> void:
	order.status="failed"; order.failure_code=code; order["ended_day"]=day; order.blocked_reason=reason

# Cumulative integer allocation assigns the rounding residue to the last units.
# Selling an entire harvest always removes exactly its actual production cost.
static func allocated_cost(cost: int, quantity: int, sold: int, take: int) -> int:
	return cost*(sold+take)/quantity-cost*sold/quantity

static func _sell(state, farm: Dictionary, params: Dictionary, principal: String, executor: String, execution: String) -> Dictionary:
	var quantity := int(params.quantity); var remaining := quantity; var cost := 0; var allocations := {}
	var lots: Array = farm.stock_lots.keys(); lots.sort_custom(func(a,b): return int(state.economic_contracts[a].ended_day)<int(state.economic_contracts[b].ended_day) if state.economic_contracts[a].ended_day!=state.economic_contracts[b].ended_day else str(a)<str(b))
	for id in lots:
		var lot: Dictionary = farm.stock_lots[id]
		var take := mini(remaining,int(lot.remaining))
		if take>0:
			allocations[id]=take
			cost += allocated_cost(int(lot.total_cost),int(lot.total_quantity),int(lot.total_quantity)-int(lot.remaining),take)
			remaining-=take
		if remaining==0: break
	if remaining!=0: return Contract.fail("尚无足量实际收获粮食")
	var buyer: Dictionary = farm.agricultural_terms.buyer
	var id := "farm-sale:"+execution
	var amount := quantity*int(farm.agricultural_terms.unit_sale_price)
	var quote := sale_quote(state,farm,executor); quote.quantity=quantity
	var paid := Accounts.new().apply(state,"transfer",{"execution_id":execution,"source_account_id":buyer.account_id,"destination_account_id":farm.account_id,"amount":amount,"actor_id":buyer.buyer_id,"reason_ref":id})
	if not paid.ok: return paid
	var delivered := Accounts.new().apply(state,"transfer",{"execution_id":"product:"+execution,"source_account_id":farm.product_account_id,"destination_account_id":buyer.product_account_id,"amount":quantity,"actor_id":principal,"reason_ref":id})
	if not delivered.ok: delivered["rollback_required"]=true; return delivered
	for lot_id in allocations: farm.stock_lots[lot_id].remaining-=int(allocations[lot_id])
	state.economic_contracts[id]={"contract_id":id,"contract_kind":"farm_sale","status":"settled","terms_version":1,"party_refs":[farm.owner_ref.entity_id,buyer.buyer_id],"execution_refs":[execution],"shop_id":farm.asset_id,"manager_id":executor,"buyer_id":buyer.buyer_id,"good_id":farm.agricultural_terms.good_id,"quantity":quantity,"amount":amount,"unit_price":int(farm.agricultural_terms.unit_sale_price),"goods_cost":cost,"lot_allocations":allocations,"day":int(state.current_day),"product_receipt":"product:"+execution,"review":quote}
	farm.contract_refs.append(id)
	return {"ok":true,"result_ref":id,"journal_refs":[execution,"product:"+execution],"visible_summary":("实际售茶 %d，收款 %d，结转管护采制成本 %d。" if farm.agricultural_terms.good_id=="tea" else "实际售粮 %d，收款 %d，结转种粮农工成本 %d。") % [quantity,amount,cost]}

static func validate_terms(raw: Dictionary, land: Dictionary, terms: Variant) -> Dictionary:
	var resources: Variant = land.get("agricultural_resources")
	if not resources is Dictionary or resources.get("arable")!=true or not Numbers.number(resources.get("cultivated_area_units"),1,1000000) or int(resources.cultivated_area_units)>int(land.area_units) or not Numbers.number(resources.get("water_supply"),0,100) or not str(resources.get("source_id","")).begins_with("scenario:"): return Contract.fail("田庄缺少真实可耕面积、水源或配置来源")
	if not terms is Dictionary or terms.get("good_id") not in ["grain","tea"] or not terms.get("recipe") is Dictionary or not terms.get("buyer") is Dictionary: return Contract.fail("田庄缺少作物及购粮约定")
	for key in ["base_capacity","unit_sale_price"]:
		if not Contract.amount(terms.get(key),true): return Contract.fail("售粮设施与报价无效")
	var recipe: Dictionary = terms.recipe
	var season := Season.validate(recipe)
	if not season.ok: return season
	for key in ["price","growth_days","units_per_area"]:
		if not Numbers.number(recipe.get(key),1,360 if key=="growth_days" else 100 if key=="units_per_area" else 1000000): return Contract.fail("农季工种粮投入或生长期无效")
	if terms.good_id=="tea":
		if resources.get("tea_suitable")!=true or recipe.get("seed_units")!=0 or recipe.get("seed_account_id")!="" or recipe.get("maturity_days")!=1080 or not recipe.harvest_months.all(func(month):return int(month) in [2,3,4]): return Contract.fail("茶园需要宜茶登记、三年成园及春季采制，不能每季扣种粮")
	elif not Numbers.number(recipe.get("seed_units"),1,1000000): return Contract.fail("年度作物须有实际种粮投入")
	if not recipe.get("name") is String or not str(recipe.get("source_id","")).begins_with("scenario:") or not raw.character_states.has(recipe.get("supplier_id")): return Contract.fail("作物或农工来源无效")
	for account_key in ["payee_account_id","seed_account_id"]:
		if account_key=="seed_account_id" and terms.good_id=="tea": continue
		var account: Dictionary = raw.resource_accounts.get(recipe.get(account_key),{})
		if account.get("owner_ref")!={"entity_kind":"character","entity_id":recipe.supplier_id} or account.get("unit_id")!=("cash_unit" if account_key=="payee_account_id" else "ration_unit") or Accounts.new().location(raw,recipe[account_key])!=land.location_id: return Contract.fail("农工种粮及收款账户不在当地或不属于本人")
	var buyer: Dictionary = terms.buyer
	for key in ["monthly_quantity","maximum_unit_price","valid_until_day"]:
		if not Contract.amount(buyer.get(key),true): return Contract.fail("购粮约定缺少实际数量、价格或期限")
	if not raw.character_states.has(buyer.get("buyer_id")) or int(terms.unit_sale_price)>int(buyer.maximum_unit_price): return Contract.fail("粮价超过具名买方接受范围")
	for key in ["account_id","product_account_id"]:
		var account: Dictionary = raw.resource_accounts.get(buyer.get(key),{})
		if account.get("owner_ref")!={"entity_kind":"character","entity_id":buyer.buyer_id} or account.get("unit_id")!=("cash_unit" if key=="account_id" else Products.agricultural_unit(terms.good_id)) or (key=="product_account_id" and account.get("resource_key")!=Products.agricultural_resource(terms.good_id)) or Accounts.new().location(raw,buyer[key])!=land.location_id: return Contract.fail("买方实际钱粮仓储不在当地或产权不符")
	return {"ok":true}

static func validate(raw: Dictionary) -> Dictionary:
	for land in raw.management_assets.values():
		if land.get("asset_kind")!="land": continue
		for offer in land.development_offers.values():
			if offer.get("industry_kind") not in ["grain_estate","tea_garden"]: continue
			var checked := validate_terms(raw,land,offer.get("agricultural_terms"))
			if not checked.ok: return checked
			if offer.industry_kind!=("tea_garden" if offer.agricultural_terms.good_id=="tea" else "grain_estate"): return Contract.fail("农产建设方案与实际产品不符")
	var lots := {}; var used := {}; var demand := {}
	for farm in raw.management_assets.values():
		if farm.get("asset_kind")!="managed_farm" and not (farm.get("asset_kind")=="estate_building" and farm.get("industry_kind") in ["grain_estate","tea_garden"]): continue
		var building: Dictionary = raw.management_assets.get(farm.get("building_id"),{}) if farm.asset_kind=="managed_farm" else farm
		var land: Dictionary = raw.management_assets.get(building.get("land_id"),{})
		if land.get("asset_kind")!="land" or farm.get("agricultural_terms")!=raw.economic_contracts.get(building.source_ref.entity_id,{}).get("recipe",{}).get("agricultural_terms"): return Contract.fail("田庄失去真实农村地产与竣工方案")
		var checked := validate_terms(raw,land,farm.get("agricultural_terms"))
		if not checked.ok: return checked
		if farm.asset_kind=="managed_farm":
			var grain: Dictionary = raw.resource_accounts.get(farm.get("product_account_id"),{})
			if farm.get("industry_kind")!=("tea_garden" if farm.agricultural_terms.good_id=="tea" else "grain_estate") or not farm.get("stock_lots") is Dictionary or grain.get("owner_ref")!=farm.owner_ref or grain.get("unit_id")!=Products.agricultural_unit(farm.agricultural_terms.good_id) or grain.get("resource_key")!=Products.agricultural_resource(farm.agricultural_terms.good_id) or Accounts.new().location(raw,farm.product_account_id)!=farm.location_id: return Contract.fail("田庄产品仓储或库存归属无效")
	for order in raw.economic_contracts.values():
		if order.get("contract_kind") not in ["managed_cultivation","farm_sale"]: continue
		var farm: Dictionary = raw.management_assets.get(order.get("shop_id"),{})
		if farm.get("asset_kind")!="managed_farm" or not farm.contract_refs.has(order.contract_id) or not order.get("execution_refs") is Array or order.execution_refs.size()!=1: return Contract.fail("农季或售粮记录失去田庄与执行来源")
		var ref: String = order.execution_refs[0]
		var receipt: Dictionary = raw.action_receipts.get(ref,{})
		var paid: Dictionary = raw.resource_journal.get(ref,{})
		if receipt.get("executor_id")!=order.get("manager_id") or not receipt.get("effect_refs",[]).has(order.contract_id) or paid.get("entry_kind")!="transfer" or paid.get("reason_ref")!=order.contract_id: return Contract.fail("农事缺少实际庄头、动作回执或付款")
		var tasks: Array = (raw.active_tasks+raw.completed_tasks).filter(func(task):return task.get("task_id")==receipt.get("task_id"))
		if tasks.size()!=1: return Contract.fail("农事丢失已授权经营任务")
		var steps: Array = tasks[0].steps.filter(func(step):return step.get("execution_id")==ref)
		if steps.size()!=1 or steps[0].parameters.get("shop_id")!=farm.asset_id or steps[0].action_kind!=("commission_farm_season" if order.contract_kind=="managed_cultivation" else "sell_farm_product"): return Contract.fail("农事与获准执行步骤不符")
		if order.contract_kind=="farm_sale": continue
		var checked := _validate_crop(raw,farm,order,receipt,paid)
		if not checked.ok: return checked
		if order.status=="harvested": lots[order.contract_id]={"shop_id":farm.asset_id,"quantity":int(order.harvest_quantity),"cost":int(order.recipe.price)}
	var sales: Array = raw.economic_contracts.values().filter(func(order):return order.get("contract_kind")=="farm_sale")
	sales.sort_custom(func(a,b):return int(a.get("day",0))<int(b.get("day",0)) if a.get("day")!=b.get("day") else str(a.contract_id)<str(b.contract_id))
	for sale in sales:
		var farm: Dictionary = raw.management_assets[sale.shop_id]
		var buyer: Dictionary = farm.agricultural_terms.buyer
		for key in ["day","quantity","amount","unit_price","goods_cost"]:
			if not Contract.amount(sale.get(key),key in ["quantity","amount","unit_price"]): return Contract.fail("售粮数额无效")
		if sale.status!="settled" or sale.get("good_id")!=farm.agricultural_terms.good_id or sale.get("buyer_id")!=buyer.buyer_id or sale.unit_price!=farm.agricultural_terms.unit_sale_price or int(sale.amount)!=int(sale.quantity)*int(sale.unit_price) or int(sale.day)>int(raw.current_day) or int(sale.day)>int(buyer.valid_until_day) or not sale.get("lot_allocations") is Dictionary: return Contract.fail("销售与实际产品和购买约定不符")
		var paid: Dictionary = raw.resource_journal[sale.execution_refs[0]]
		var grain: Dictionary = raw.resource_journal.get(sale.get("product_receipt"),{})
		if paid.get("amount")!=sale.amount or paid.get("day")!=sale.day or paid.get("source_account_id")!=buyer.account_id or paid.get("destination_account_id")!=farm.account_id or grain.get("entry_kind")!="transfer" or grain.get("source_account_id")!=farm.product_account_id or grain.get("destination_account_id")!=buyer.product_account_id or grain.get("amount")!=sale.quantity or grain.get("day")!=sale.day or grain.get("reason_ref")!=sale.contract_id: return Contract.fail("售粮缺少真实钱粮交割")
		var quantity := 0; var cost := 0
		for id in sale.lot_allocations:
			var count: Variant = sale.lot_allocations[id]
			if not lots.has(id) or lots[id].shop_id!=farm.asset_id or not Contract.amount(count,true) or int(raw.economic_contracts[id].ended_day)>int(sale.day): return Contract.fail("售粮使用了他人或未收割作物")
			var prior := int(used.get(id,0)); var lot: Dictionary = lots[id]
			if prior+int(count)>int(lot.quantity): return Contract.fail("售粮超过真实产量")
			cost += allocated_cost(lot.cost,lot.quantity,prior,int(count)); quantity+=int(count); used[id]=prior+int(count)
		if quantity!=int(sale.quantity) or cost!=int(sale.goods_cost): return Contract.fail("售粮成本分摊或实际数量不守恒")
		var review: Variant = sale.get("review")
		if not review is Dictionary: return Contract.fail("售粮缺少当时接待及购买资金依据")
		for key in ["quantity","remaining_demand","buyer_cash","capacity","suitability","security","stock_on_hand"]:
			if not Contract.amount(review.get(key)): return Contract.fail("售粮经营判断损坏")
		if review.quantity!=sale.quantity or int(review.suitability)>100 or int(review.security)>100 or int(review.security)<20 or int(review.capacity)!=int(farm.agricultural_terms.base_capacity)*(6000+int(review.suitability)*80)*int(review.security)/1000000 or int(sale.quantity)>mini(int(review.stock_on_hand),mini(int(review.remaining_demand),mini(int(review.capacity),int(review.buyer_cash)/int(sale.unit_price)))): return Contract.fail("售粮超过当时实际市场承接能力")
		var month := int(floor(float(int(sale.day)-int(raw.current_day)+int(raw.current_date.day)-1)/30.0))
		var key := "%s:%s:%s:%d" % [farm.location_id,buyer.buyer_id,sale.good_id,month]
		demand[key]=int(demand.get(key,0))+quantity
		if int(demand[key])>int(buyer.monthly_quantity): return Contract.fail("同市场购粮需求被重复使用")
	for farm in raw.management_assets.values():
		if farm.get("asset_kind")!="managed_farm": continue
		var expected := {}; var quantity := 0
		for id in lots:
			if lots[id].shop_id!=farm.asset_id: continue
			var remaining := int(lots[id].quantity)-int(used.get(id,0))
			expected[id]={"remaining":remaining,"total_quantity":lots[id].quantity,"total_cost":lots[id].cost}; quantity+=remaining
		if farm.stock_lots.size()!=expected.size() or Accounts.new().balance(raw,farm.product_account_id)!=quantity: return Contract.fail("田庄实际粮仓与收获、售粮记录不守恒")
		for id in expected:
			var actual: Variant = farm.stock_lots.get(id)
			if not actual is Dictionary or actual.size()!=3: return Contract.fail("田庄粮食批次缺失或字段错误")
			for key in ["remaining","total_quantity","total_cost"]:
				if not Contract.amount(actual.get(key),key!="remaining") or int(actual[key])!=int(expected[id][key]): return Contract.fail("田庄粮食批次数额与真实产销不符")
	for entry in raw.resource_journal.values():
		var reason := str(entry.get("reason_ref",""))
		var id := reason.trim_prefix("rule:farm_seed:").trim_prefix("rule:farm_harvest:")
		if not reason.begins_with("rule:farm_seed:") and not reason.begins_with("rule:farm_harvest:") and not id.begins_with("farm-season:") and not id.begins_with("farm-sale:"): continue
		var order: Dictionary = raw.economic_contracts.get(id,{})
		if order.get("contract_kind") not in ["managed_cultivation","farm_sale"] or (not order.get("execution_refs",[]).has(entry.entry_id) and entry.entry_id not in [order.get("seed_receipt"),order.get("harvest_receipt"),order.get("product_receipt")]): return Contract.fail("农事钱粮流水丢失真实农季或交割合同")
	return {"ok":true}

static func _validate_crop(raw: Dictionary, farm: Dictionary, order: Dictionary, receipt: Dictionary, paid: Dictionary) -> Dictionary:
	var recipe: Dictionary = farm.agricultural_terms.recipe
	if order.get("recipe")!=recipe or order.get("supplier_id")!=recipe.supplier_id or order.get("manager_id")==recipe.supplier_id or order.get("status") not in ["growing","mature","harvested","failed"]: return Contract.fail("农季失去原工种粮约定或阶段")
	for key in ["created_day","last_update_day","last_work_day","work_days","harvest_quantity","season_year","manager_suitability"]:
		if not Contract.amount(order.get(key)): return Contract.fail("农季日期、产量或工作记录损坏")
	var origin := Numbers.date_serial(order.get("created_date"))
	if origin<0 or origin+int(raw.current_day)-int(order.created_day)!=Numbers.date_serial(raw.current_date) or not Season.within(recipe,int(order.season_year),order.created_date) or not Season.contains_month(recipe.plant_months,int(order.created_date.month)) or order.contract_id!="farm-season:%s:%d" % [farm.asset_id,int(order.season_year)] or int(order.manager_suitability)>100: return Contract.fail("农季实际播种日期或季次不符")
	var historical := crop_readiness({"current_day":order.created_day,"current_date":order.created_date,"management_assets":raw.management_assets,"economic_contracts":raw.economic_contracts},farm)
	if not historical.ok: return Contract.fail("农季开工时尚不具备实际农时或成园条件："+str(historical.get("error","")))
	if paid.get("amount")!=recipe.price or paid.get("source_account_id")!=farm.account_id or paid.get("destination_account_id")!=recipe.payee_account_id or paid.get("day")!=order.created_day or receipt.get("day")!=order.created_day or paid.get("actor_id")!=order.get("customer_id"): return Contract.fail("农季工种粮没有实际支付")
	var seed: Dictionary = raw.resource_journal.get(order.get("seed_receipt"),{})
	if farm.agricultural_terms.good_id=="tea":
		if order.get("seed_receipt")!="" or not seed.is_empty(): return Contract.fail("茶园采制不能重复播种或消费口粮")
	elif seed.get("entry_kind")!="rule_consumption" or seed.get("source_account_id")!=recipe.seed_account_id or seed.get("amount")!=recipe.seed_units or seed.get("day")!=order.created_day or seed.get("reason_ref")!="rule:farm_seed:"+str(order.contract_id): return Contract.fail("农季没有实际投入种粮")
	if not order.get("growth_log") is Array or order.growth_log.size()>int(recipe.growth_days) or not order.get("work_log") is Array or order.work_log.size()!=int(order.work_days) or int(order.work_days) not in [1,2,3] or int(order.last_update_day)>int(raw.current_day): return Contract.fail("农季缺少真实生长和工序")
	var previous := int(order.created_day)
	for row in order.growth_log:
		if not row is Dictionary or not Contract.amount(row.get("day")) or int(row.day)<=previous or int(row.day)>int(raw.current_day) or Numbers.date_serial(row.get("date"))!=origin+int(row.day)-int(order.created_day) or not Season.within(recipe,int(order.season_year),row.date) or not Numbers.number(row.get("security"),0,100) or row.get("water_supply")!=land_for(raw,farm).agricultural_resources.water_supply: return Contract.fail("农季观察日期、水源或地方秩序记录损坏")
		previous=int(row.day)
	for index in order.work_log.size():
		var row: Variant = order.work_log[index]
		if not row is Dictionary or not Contract.amount(row.get("day")) or row.get("kind")!=work_stages(farm)[index] or Numbers.date_serial(row.get("date"))!=origin+int(row.get("day",-1))-int(order.created_day): return Contract.fail("农季缺少实际工序与日期")
	if order.work_log[0].day!=order.created_day or order.last_work_day!=order.work_log[-1].day: return Contract.fail("播种或最后农活没有对应工日")
	if order.work_log.size()>1 and (order.growth_log.is_empty() or int(order.work_log[1].day)>int(order.growth_log[-1].day)): return Contract.fail("农季照料不能在成熟后补记")
	if order.status=="growing" and order.growth_log.size()>=int(recipe.growth_days): return Contract.fail("生长阶段与实际天数不符")
	if order.status in ["mature","harvested"] and (order.growth_log.size()!=int(recipe.growth_days) or int(order.work_days)<2): return Contract.fail("成熟或收获缺少完整生长与照料")
	if order.status=="harvested":
		var harvest: Dictionary = raw.resource_journal.get(order.get("harvest_receipt"),{})
		if int(order.work_days)!=3 or order.get("ended_day")!=order.last_work_day or int(order.harvest_quantity)<=0 or int(order.harvest_quantity)!=yield_quantity(land_for(raw,farm),order) or not Season.within(recipe,int(order.season_year),order.work_log[-1].date) or not Season.contains_month(recipe.harvest_months,int(order.work_log[-1].date.month)): return Contract.fail("收获缺少农时、工序或实际条件依据")
		if harvest.get("entry_kind")!="rule_income" or harvest.get("destination_account_id")!=farm.product_account_id or harvest.get("amount")!=order.harvest_quantity or harvest.get("day")!=order.ended_day or harvest.get("reason_ref")!="rule:farm_harvest:"+str(order.contract_id): return Contract.fail("收获未进入真实田庄粮仓")
	else:
		if order.harvest_quantity!=0 or order.get("harvest_receipt")!="" or int(order.work_days)==3: return Contract.fail("未收割作物提前生成粮食")
	if order.status=="failed":
		if not Contract.amount(order.get("ended_day")) or int(order.ended_day)<previous or int(order.ended_day)>int(raw.current_day): return Contract.fail("失收缺少实际截止日期")
		var at := Season.at_serial(origin+int(order.ended_day)-int(order.created_day))
		match order.get("failure_code"):
			"out_of_season":
				if Season.within(recipe,int(order.season_year),at): return Contract.fail("农时未过却声明失收")
			"untended":
				if int(order.work_days)!=1 or order.growth_log.size()!=int(recipe.growth_days) or int(order.ended_day)!=int(order.growth_log[-1].day): return Contract.fail("失收缺少全季无人照料依据")
			"zero_yield":
				if int(order.work_days)!=2 or order.growth_log.size()!=int(recipe.growth_days) or yield_quantity(land_for(raw,farm),order)!=0: return Contract.fail("实际仍有产量却声明零收获")
			_: return Contract.fail("未知农季损失原因")
	elif order.get("failure_code")!="": return Contract.fail("未失收农季存在失败原因")
	return {"ok":true}

static func append_statement(state, farm: Dictionary, result: Dictionary, from_day: int, through_day: int) -> void:
	result["crop_loss"] = 0
	result["harvest_quantity"] = 0
	result["crop_seasons"] = []
	for order in state.economic_contracts.values():
		if order.get("shop_id")!=farm.asset_id: continue
		if order.get("contract_kind")=="managed_cultivation" and int(order.created_day)<=through_day:
			if int(order.created_day)>=from_day: result.purchases+=int(order.recipe.price)
			var ended: bool = order.status in ["harvested","failed"] and int(order.ended_day)<=through_day
			var seen: Array = order.growth_log.filter(func(row):return int(row.day)<=through_day)
			var stage: String = order.status if ended else "mature" if seen.size()==int(order.recipe.growth_days) else "growing"
			result.crop_seasons.append({"contract_id":order.contract_id,"season_year":order.season_year,"created_day":order.created_day,"manager_id":order.manager_id,"worker_id":order.supplier_id,"status":stage,"input_cost":int(order.recipe.price),"harvest_quantity":int(order.harvest_quantity) if ended and order.status=="harvested" else 0,"growth_days":seen.size(),"required_growth_days":int(order.recipe.growth_days),"ended_day":int(order.ended_day) if ended else -1})
			if not ended: result.work_in_progress_value+=int(order.recipe.price)
			elif order.status=="harvested":
				result.inventory_value+=int(order.recipe.price); result.inventory_quantity+=int(order.harvest_quantity)
				if int(order.ended_day)>=from_day: result.harvest_quantity+=int(order.harvest_quantity)
			elif int(order.ended_day)>=from_day: result.crop_loss+=int(order.recipe.price)
		elif order.get("contract_kind")=="farm_sale" and int(order.day)<=through_day:
			result.inventory_value-=int(order.goods_cost); result.inventory_quantity-=int(order.quantity)
			if int(order.day)>=from_day:
				result.revenue+=int(order.amount); result.goods_cost+=int(order.goods_cost); result.sold_quantity+=int(order.quantity)
	result.expenses+=int(result.crop_loss)
	result.cost_breakdown["crop_loss"]=int(result.crop_loss)
	result.causes.append(("本期实际制茶 %d、售茶 %d；已售管护采制成本 %d，尚未采制投入 %d，未售成茶成本 %d。" if farm.agricultural_terms.good_id=="tea" else "本期实际收粮 %d、售粮 %d；已售种粮农工成本 %d，尚未收获投入 %d，未售粮食成本 %d。") % [result.harvest_quantity,result.sold_quantity,result.goods_cost,result.work_in_progress_value,result.inventory_value])
	result.causes.append("作物按生产季收获，月内尚无销售不等于庄头失职；产量采用逐日水源、地方秩序及受托人的经营能力，销售另受真实购买资金和需求约束。")
	if int(result.crop_loss)>0: result.causes.append("本期农季失收损失 %d；实际工种粮投入已发生，不能退回或留作虚假库存。" % result.crop_loss)
