extends RefCounted
## Paid batches use the shared clock, artisan workload, material stocks and account journal.
const Contract = preload("res://scripts/core/management_state_contract.gd")
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Presence = preload("res://scripts/core/production_service.gd")
const Workload = preload("res://scripts/core/character_workload_service.gd")
const Retail = preload("res://scripts/core/retail_trading_service.gd")
const KINDS := ["commission_business_batch","sell_business_batch"]

static func spent(state, shop_id: String) -> int:
	var amount := 0
	for order in state.economic_contracts.values():
		if order.get("contract_kind")=="manufacturing_batch" and order.shop_id==shop_id and int(order.created_day)>=Retail.month_start(state): amount += int(order.recipe.price)
	return amount

static func sold(state, shop: Dictionary) -> int:
	var quantity := 0
	for sale in state.economic_contracts.values():
		if sale.get("contract_kind")!="manufacturing_sale" or int(sale.day)<Retail.month_start(state): continue
		var other: Dictionary = state.management_assets[sale.shop_id]
		if other.location_id==shop.location_id and other.manufacturing_terms.good_id==shop.manufacturing_terms.good_id and sale.buyer_id==shop.manufacturing_terms.buyer.buyer_id: quantity += int(sale.quantity)
	return quantity

static func sale_quote(state, shop: Dictionary, manager: String) -> Dictionary:
	var terms: Dictionary = shop.manufacturing_terms
	var buyer: Dictionary = terms.buyer
	if int(buyer.valid_until_day)<int(state.current_day) or not Presence.present(state,buyer.buyer_id,shop.location_id) or not Accounts.new().can_operate(state,buyer.account_id,buyer.buyer_id): return Contract.fail("买方不在场、不能付款或购买约定已过期")
	var assessed := Retail.capacity(state,shop,manager)
	if not assessed.ok: return assessed
	var demand := maxi(0,int(buyer.monthly_quantity)-sold(state,shop))
	var cash := Accounts.new().available(state,buyer.account_id)
	var quantity := mini(Retail.held(shop),mini(demand,mini(cash/int(terms.unit_sale_price),int(assessed.capacity))))
	return {"ok":true,"quantity":quantity,"remaining_demand":demand,"buyer_cash":cash,"capacity":assessed.capacity,"suitability":assessed.suitability,"security":assessed.security,"stock_on_hand":Retail.held(shop)}

static func cost_for(state, kind: String, params: Dictionary) -> Dictionary:
	var shop: Dictionary = state.management_assets.get(params.get("shop_id"),{})
	if shop.get("asset_kind")!="manufacturing_shop" or kind not in KINDS: return Contract.fail("生产经营需要实际工坊")
	if kind=="sell_business_batch" and not Contract.amount(params.get("quantity"),true): return Contract.fail("销售须指定实际成品数量")
	return {"ok":true,"account_id":shop.account_id if kind=="commission_business_batch" else "","amount":int(shop.manufacturing_terms.recipe.price) if kind=="commission_business_batch" else 0}

static func guard(state, auth: Dictionary, kind: String, params: Dictionary, executor: String = "") -> Dictionary:
	var policy: Dictionary = auth.business_policy
	if kind not in KINDS or policy.shop_id!=params.get("shop_id"): return Contract.fail("超出工坊经营授权")
	var checked := cost_for(state,kind,params)
	if not checked.ok: return checked
	var shop: Dictionary = state.management_assets[policy.shop_id]
	var ready: Dictionary = load("res://scripts/core/pawnshop_service.gd")._ready_to_trade(state,shop)
	if not ready.ok: return ready
	if shop.status!="open" or (executor!="" and executor!=ready.person_id): return Contract.fail("工坊未营业或经办人已不能履职")
	var quote := sale_quote(state,shop,ready.person_id)
	if not quote.ok: return quote
	if kind=="sell_business_batch":
		if int(params.quantity)>int(quote.quantity): return Contract.fail("销售超过成品、接待能力、真实资金或剩余需求")
		return {"ok":true}
	if quote.remaining_demand<=0 or quote.buyer_cash<int(shop.manufacturing_terms.unit_sale_price) or quote.capacity<=0: return Contract.fail("当前没有可支付的剩余需求或当地无法开工")
	var recipe: Dictionary = shop.manufacturing_terms.recipe
	if Retail.held(shop)+int(recipe.output_quantity)>int(shop.manufacturing_terms.target_stock): return Contract.fail("现有库存已达到备货上限")
	if int(recipe.price)>int(policy.loan_limit) or spent(state,shop.asset_id)+int(recipe.price)>int(policy.monthly_limit): return Contract.fail("生产批次超过单笔或本月预算")
	if Accounts.new().available(state,shop.account_id,str(auth.reservation_refs.get(shop.account_id,"")))-int(recipe.price)<int(policy.cash_floor): return Contract.fail("本批生产会低于现金底线")
	if not Presence.present(state,recipe.supplier_id,shop.location_id) or not Workload.can_schedule(state,recipe.supplier_id,"manufacturing_batch",str(auth.principal_id)): return Contract.fail("工匠未到场或已有任职占满工时")
	if int(state.character_states[recipe.supplier_id].get("relationships",{}).get(auth.principal_id,0)) < -15: return Contract.fail("工匠不愿承接此项生产")
	for other in state.economic_contracts.values():
		if other.get("status")=="working" and (other.get("supplier_id")==recipe.supplier_id or other.get("shop_id")==shop.asset_id): return Contract.fail("本工坊或工匠尚有未完成的批次")
	for input in recipe.inputs:
		var stock: Dictionary = state.management_assets[input.stock_id]
		if int(stock.remaining_quantity)<int(input.quantity): return Contract.fail("实际原料不足，不能先收款后凭空生产")
	return {"ok":true}

static func choose(state, auth: Dictionary) -> Dictionary:
	var shop: Dictionary = state.management_assets[auth.business_policy.shop_id]
	var ready: Dictionary = load("res://scripts/core/business_staff_service.gd").resolve(state,shop)
	if not ready.ok: return {"reason":ready.error}
	var quote := sale_quote(state,shop,ready.person_id)
	if quote.ok and quote.quantity>0: return {"kind":"sell_business_batch","parameters":{"shop_id":shop.asset_id,"quantity":quote.quantity}}
	var params := {"shop_id":shop.asset_id}
	var checked := guard(state,auth,"commission_business_batch",params,ready.person_id)
	return {"kind":"commission_business_batch","parameters":params} if checked.ok else {"reason":checked.error}

static func apply(state, kind: String, params: Dictionary, principal: String, executor: String, execution: String, reservation: String = "") -> Dictionary:
	var shop: Dictionary = state.management_assets[params.shop_id]
	var auth: Dictionary = load("res://scripts/core/business_management_service.gd").current(state,shop.asset_id)
	if auth.is_empty() or auth.principal_id!=principal: return Contract.fail("生产经营须由已获授权的负责人办理")
	var checked := guard(state,auth,kind,params,executor)
	if not checked.ok: return checked
	var terms: Dictionary = shop.manufacturing_terms
	var id := "manufacturing:"+execution
	if kind=="commission_business_batch":
		var recipe: Dictionary = terms.recipe
		var paid := Accounts.new().apply(state,"transfer",{"execution_id":execution,"source_account_id":shop.account_id,"destination_account_id":recipe.payee_account_id,"amount":int(recipe.price),"actor_id":principal,"reason_ref":id,"reservation_id":reservation})
		if not paid.ok: return paid
		for input in recipe.inputs:
			var stock: Dictionary = state.management_assets[input.stock_id]
			stock.remaining_quantity -= int(input.quantity); stock.consumptions[id] = int(input.quantity)
		state.economic_contracts[id] = {"contract_id":id,"contract_kind":"manufacturing_batch","status":"working","party_refs":[shop.owner_ref.entity_id,recipe.supplier_id],"terms_version":1,"execution_refs":[execution],"shop_id":shop.asset_id,"customer_id":principal,"supplier_id":recipe.supplier_id,"manager_id":executor,"recipe":recipe.duplicate(true),"created_day":int(state.current_day),"last_work_day":int(state.current_day),"work_days":0,"work_log":[],"blocked_reason":""}
		shop.contract_refs.append(id)
		return {"ok":true,"result_ref":id,"journal_refs":[execution],"visible_summary":"已安排工匠生产并支付用料工款 %d；待 %d 个实际工日完工。" % [recipe.price,recipe.duration_days]}
	var quote := sale_quote(state,shop,executor)
	var quantity := int(params.quantity); var remaining := quantity; var cost := 0; var allocations := {}
	var lots: Array = shop.stock_lots.keys()
	lots.sort_custom(func(a,b):return int(state.economic_contracts[a].completed_day)<int(state.economic_contracts[b].completed_day) if state.economic_contracts[a].completed_day!=state.economic_contracts[b].completed_day else str(a)<str(b))
	for lot_id in lots:
		var take := mini(remaining,int(shop.stock_lots[lot_id].remaining))
		if take>0: allocations[lot_id]=take; cost += take*int(shop.stock_lots[lot_id].unit_cost); remaining -= take
		if remaining==0: break
	if remaining!=0: return Contract.fail("没有足够已完工成品")
	var amount := quantity*int(terms.unit_sale_price)
	var paid := Accounts.new().apply(state,"transfer",{"execution_id":execution,"source_account_id":terms.buyer.account_id,"destination_account_id":shop.account_id,"amount":amount,"actor_id":terms.buyer.buyer_id,"reason_ref":id})
	if not paid.ok: return paid
	for lot_id in allocations: shop.stock_lots[lot_id].remaining -= int(allocations[lot_id])
	quote.quantity = quantity
	state.economic_contracts[id] = {"contract_id":id,"contract_kind":"manufacturing_sale","status":"settled","party_refs":[shop.owner_ref.entity_id,terms.buyer.buyer_id],"terms_version":1,"execution_refs":[execution],"shop_id":shop.asset_id,"manager_id":executor,"buyer_id":terms.buyer.buyer_id,"quantity":quantity,"unit_price":int(terms.unit_sale_price),"amount":amount,"goods_cost":cost,"day":int(state.current_day),"lot_allocations":allocations,"review":quote}
	shop.contract_refs.append(id)
	return {"ok":true,"result_ref":id,"journal_refs":[execution],"visible_summary":"已售成品 %d，实收 %d，已售生产成本 %d。" % [quantity,amount,cost]}

static func settle_daily(state) -> Dictionary:
	for order in state.economic_contracts.values():
		if order.get("contract_kind")!="manufacturing_batch" or order.status!="working" or int(order.last_work_day)>=int(state.current_day): continue
		var shop: Dictionary = state.management_assets[order.shop_id]
		var node: Dictionary = state.local_node_state[shop.location_id]
		if shop.status!="open" or not Presence.present(state,order.supplier_id,shop.location_id) or mini(int(node.security),int(node.public_order))<20:
			order.blocked_reason = "工坊停业、工匠离场或地方不安；已付工款和已领原料保留在本批次。"; continue
		if Workload.occupied_today(state,order.supplier_id,order.contract_id,order.customer_id,"manufacturing_batch"):
			order.blocked_reason = "工匠今日须履行其他事务；本批次等待实际空闲工日。"; continue
		order.blocked_reason = ""
		Workload.record_work(state,order)
		if int(order.work_days)<int(order.recipe.duration_days): continue
		order.status="completed"; order["completed_day"]=int(state.current_day)
		shop.stock_lots[order.contract_id]={"remaining":int(order.recipe.output_quantity),"unit_cost":int(order.recipe.price)/int(order.recipe.output_quantity)}
	return {"ok":true}

static func validate(raw: Dictionary) -> Dictionary:
	var assets: Dictionary = raw.management_assets
	for asset in assets.values():
		if asset.get("asset_kind")=="land":
			for offer in asset.development_offers.values():
				if offer.get("industry_kind")=="smithy":
					var checked := validate_terms(raw,offer.get("manufacturing_terms"),asset.location_id)
					if not checked.ok: return checked
		if asset.get("asset_kind")!="manufacturing_shop" and not (asset.get("asset_kind")=="estate_building" and asset.get("industry_kind")=="smithy"): continue
		var checked := validate_terms(raw,asset.get("manufacturing_terms"),asset.location_id)
		if not checked.ok: return checked
		var building: Dictionary = assets.get(asset.get("building_id"),{}) if asset.asset_kind=="manufacturing_shop" else asset
		if raw.economic_contracts.get(building.source_ref.entity_id,{}).get("recipe",{}).get("manufacturing_terms")!=asset.manufacturing_terms: return Contract.fail("工坊生产方案失去已签工程来源")
		if asset.asset_kind=="manufacturing_shop" and (asset.get("industry_kind")!="smithy" or not asset.get("stock_lots") is Dictionary): return Contract.fail("工坊缺少产业类型或真实库存")
	var lots := {}; var used := {}; var totals := {}
	for order in raw.economic_contracts.values():
		if order.get("contract_kind") not in ["manufacturing_batch","manufacturing_sale"]: continue
		var shop: Dictionary = assets.get(order.get("shop_id"),{})
		if shop.get("asset_kind")!="manufacturing_shop" or not shop.contract_refs.has(order.contract_id) or not order.get("execution_refs") is Array or order.execution_refs.size()!=1: return Contract.fail("生产经营凭据缺少实际工坊或回执")
		var terms: Dictionary = shop.manufacturing_terms
		var execution: String = str(order.execution_refs[0])
		var receipt: Dictionary = raw.action_receipts.get(execution,{})
		var paid: Dictionary = raw.resource_journal.get(execution,{})
		if receipt.get("executor_id")!=order.get("manager_id") or not receipt.get("effect_refs",[]).has(order.contract_id) or paid.get("reason_ref")!=order.contract_id or paid.get("entry_kind")!="transfer": return Contract.fail("生产经营缺少实际经办与付款")
		var tasks: Array = (raw.active_tasks+raw.completed_tasks).filter(func(row):return row.get("task_id")==receipt.get("task_id"))
		if tasks.size()!=1: return Contract.fail("生产经营丢失持续授权任务")
		var steps: Array = tasks[0].steps.filter(func(row):return row.get("execution_id")==execution)
		if steps.size()!=1 or steps[0].parameters.get("shop_id")!=shop.asset_id: return Contract.fail("生产经营丢失对应获准步骤")
		if order.contract_kind=="manufacturing_batch":
			if order.get("recipe")!=terms.recipe or order.get("supplier_id")!=terms.recipe.supplier_id or order.get("customer_id")!=paid.get("actor_id") or order.get("party_refs")!=[shop.owner_ref.entity_id,terms.recipe.supplier_id] or order.get("status") not in ["working","completed"] or not order.get("blocked_reason") is String or steps[0].action_kind!="commission_business_batch": return Contract.fail("生产批次更改了实际工匠或方案")
			for field in ["created_day","last_work_day","work_days"]:
				if not Contract.amount(order.get(field)): return Contract.fail("生产批次工日损坏")
			if int(order.work_days)>int(order.recipe.duration_days) or int(order.last_work_day)>int(raw.current_day) or int(order.last_work_day)<int(order.created_day)+int(order.work_days) or receipt.get("day")!=order.created_day: return Contract.fail("生产批次工序早于实际投入")
			if paid.get("amount")!=order.recipe.price or paid.get("source_account_id")!=shop.account_id or paid.get("destination_account_id")!=order.recipe.payee_account_id: return Contract.fail("生产工款与真实批次不符")
			for input in order.recipe.inputs:
				if assets[input.stock_id].consumptions.get(order.contract_id)!=input.quantity: return Contract.fail("生产未实际领用约定原料")
			if order.status=="working":
				if int(order.work_days)>=int(order.recipe.duration_days) or shop.stock_lots.has(order.contract_id) or order.has("completed_day"): return Contract.fail("未完工批次已经生成成品")
			else:
				if int(order.work_days)!=int(order.recipe.duration_days) or order.get("completed_day")!=order.last_work_day: return Contract.fail("成品缺少实际完工工日")
				lots[order.contract_id]={"shop_id":shop.asset_id,"remaining":int(order.recipe.output_quantity),"unit_cost":int(order.recipe.price)/int(order.recipe.output_quantity)}
		else:
			for field in ["day","quantity","amount","goods_cost","unit_price"]:
				if not Contract.amount(order.get(field),field in ["quantity","amount","unit_price"]): return Contract.fail("成品销售数额损坏")
			if order.get("status")!="settled" or order.get("buyer_id")!=terms.buyer.buyer_id or order.unit_price!=terms.unit_sale_price or int(order.amount)!=int(order.quantity)*int(order.unit_price) or int(order.day)>int(raw.current_day) or int(order.day)>int(terms.buyer.valid_until_day) or not order.get("lot_allocations") is Dictionary: return Contract.fail("成品销售与购买约定不符")
			if steps[0].action_kind!="sell_business_batch" or steps[0].parameters.get("quantity")!=order.quantity or receipt.get("day")!=order.day or paid.get("source_account_id")!=terms.buyer.account_id or paid.get("destination_account_id")!=shop.account_id or paid.get("amount")!=order.amount: return Contract.fail("成品销售缺少实际获准交易与收款")
			var quantity := 0; var cost := 0
			for id in order.lot_allocations:
				var batch: Dictionary = raw.economic_contracts.get(id,{})
				var count: Variant = order.lot_allocations[id]
				if not Contract.amount(count,true) or batch.get("contract_kind")!="manufacturing_batch" or batch.get("shop_id")!=shop.asset_id or batch.get("status")!="completed" or int(batch.get("completed_day",2147483647))>int(order.day): return Contract.fail("销售引用了未完成或他人的批次")
				quantity += int(count); cost += int(count)*int(batch.recipe.price)/int(batch.recipe.output_quantity); used[id]=int(used.get(id,0))+int(count)
			if quantity!=int(order.quantity) or cost!=int(order.goods_cost): return Contract.fail("成品销售成本与实际出库不符")
			var review: Variant = order.get("review")
			if not review is Dictionary: return Contract.fail("销售缺少当时市场判断")
			for field in ["quantity","remaining_demand","buyer_cash","capacity","suitability","security","stock_on_hand"]:
				if not Contract.amount(review.get(field)): return Contract.fail("生产经营评估损坏")
			if review.quantity!=order.quantity or int(review.suitability)>100 or int(review.security)>100 or int(review.security)<20 or int(review.capacity)!=int(terms.base_capacity)*(6000+int(review.suitability)*80)*int(review.security)/1000000 or int(order.quantity)>mini(int(review.stock_on_hand),mini(int(review.capacity),mini(int(review.remaining_demand),int(review.buyer_cash)/int(order.unit_price)))): return Contract.fail("销售超过当时生产经营能力或市场")
			var month := int(floor(float(int(order.day)-int(raw.current_day)+int(raw.current_date.day)-1)/float(preload("res://scripts/core/strategic_time_service.gd").DAYS_PER_MONTH)))
			var key := "%s:%s:%s:%d" % [shop.location_id,terms.good_id,order.buyer_id,month]
			totals[key]=int(totals.get(key,0))+int(order.quantity)
			if int(totals[key])>int(terms.buyer.monthly_quantity): return Contract.fail("重复耗用同市场每月需求")
	for shop in assets.values():
		if shop.get("asset_kind")!="manufacturing_shop": continue
		var expected_count := 0
		for id in lots:
			if lots[id].shop_id!=shop.asset_id: continue
			expected_count += 1
			var remaining := int(lots[id].remaining)-int(used.get(id,0))
			var actual: Variant = shop.stock_lots.get(id)
			if remaining<0 or not actual is Dictionary or not Contract.amount(actual.get("remaining")) or not Contract.amount(actual.get("unit_cost"),true) or int(actual.remaining)!=remaining or int(actual.unit_cost)!=int(lots[id].unit_cost): return Contract.fail("工坊成品库存与真实产销不守恒")
		if shop.stock_lots.size()!=expected_count: return Contract.fail("工坊存在无生产来源的库存")
	return {"ok":true}

static func validate_terms(raw: Dictionary, value: Variant, location: String) -> Dictionary:
	if not value is Dictionary or value.get("good_id")!="tools" or not value.get("recipe") is Dictionary or not value.get("buyer") is Dictionary: return Contract.fail("工坊缺少真实产品、配方或购买约定")
	for field in ["unit_sale_price","base_capacity","target_stock"]:
		if not Contract.amount(value.get(field),true): return Contract.fail("工坊售价或设施能力错误")
	var recipe: Dictionary = value.recipe; var buyer: Dictionary = value.buyer
	if not raw.character_states.has(recipe.get("supplier_id")) or raw.resource_accounts.get(recipe.get("payee_account_id"),{}).get("owner_ref")!={"entity_kind":"character","entity_id":recipe.get("supplier_id")}: return Contract.fail("生产方案缺少实际工匠与收款账户")
	for field in ["price","duration_days","output_quantity"]:
		if not Contract.amount(recipe.get(field),true): return Contract.fail("生产批次报价或投入产出错误")
	if int(recipe.price)%int(recipe.output_quantity)!=0 or int(recipe.output_quantity)>int(value.target_stock) or not recipe.get("inputs") is Array or recipe.inputs.is_empty(): return Contract.fail("批次成本或原料方案无效")
	var seen := {}
	for input in recipe.inputs:
		if not input is Dictionary or not Contract.amount(input.get("quantity"),true) or seen.has(input.get("stock_id")): return Contract.fail("批次原料重复或数量错误")
		var stock: Dictionary = raw.management_assets.get(input.get("stock_id"),{})
		if stock.get("asset_kind")!="material_stock" or stock.get("location_id")!=location or stock.get("owner_ref")!={"entity_kind":"character","entity_id":recipe.supplier_id}: return Contract.fail("工匠没有约定的当地原料")
		seen[input.stock_id]=true
	if not raw.character_states.has(buyer.get("buyer_id")) or raw.resource_accounts.get(buyer.get("account_id"),{}).get("owner_ref")!={"entity_kind":"character","entity_id":buyer.get("buyer_id")}: return Contract.fail("成品购买人缺少真实账户")
	for field in ["monthly_quantity","maximum_unit_price","valid_until_day"]:
		if not Contract.amount(buyer.get(field),true): return Contract.fail("成品购买约定数额无效")
	if int(value.unit_sale_price)>int(buyer.maximum_unit_price): return Contract.fail("成品报价超过买方约定")
	return {"ok":true}
