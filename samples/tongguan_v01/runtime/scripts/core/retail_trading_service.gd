extends RefCounted
## Finite supplier stock, standing customer offers and the existing account journal.
const Contract = preload("res://scripts/core/management_state_contract.gd")
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Presence = preload("res://scripts/core/production_service.gd")
const KINDS := ["retail_restock","retail_sale"]

static func held(shop: Dictionary) -> int:
	var total := 0
	for lot in shop.get("stock_lots",{}).values(): total += int(lot.remaining)
	return total

static func month_start(state) -> int:
	return int(state.current_day)-int(state.current_date.day)+1

static func sold(state, stock_id: String, buyer: String, shop_id: String = "") -> int:
	var total := 0
	for trade in state.economic_contracts.values():
		if trade.get("contract_kind")=="retail_trade" and trade.operation=="retail_sale" and trade.stock_id==stock_id and trade.counterparty_id==buyer and int(trade.day)>=month_start(state) and (shop_id=="" or trade.shop_id==shop_id): total += int(trade.quantity)
	return total

static func spent(state, shop_id: String) -> int:
	var total := 0
	for trade in state.economic_contracts.values():
		if trade.get("contract_kind")=="retail_trade" and trade.operation=="retail_restock" and trade.shop_id==shop_id and int(trade.day)>=month_start(state): total += int(trade.amount)
	return total

static func capacity(state, shop: Dictionary, manager: String = "") -> Dictionary:
	if manager=="":
		var staff: Dictionary = load("res://scripts/core/business_staff_service.gd").resolve(state,shop)
		if not staff.ok: return staff
		manager = str(staff.person_id)
	var stats: Dictionary = state.character_states.get(manager,{}).get("stats",{})
	var node: Dictionary = state.local_node_state[shop.location_id]
	for field in ["finance","governance","diplomacy"]:
		if not Contract.amount(stats.get(field)) or int(stats[field])>100: return {"ok":false,"error":"负责人经营能力资料不足"}
	for field in ["security","public_order"]:
		if not Contract.amount(node.get(field)) or int(node[field])>100: return {"ok":false,"error":"当地秩序资料不足"}
	var fit := (int(stats.finance)*50+int(stats.governance)*35+int(stats.diplomacy)*15)/100
	var security := mini(int(node.security),int(node.public_order))
	var efficiency := 6000+fit*80
	var quantity := int(shop.get("retail_terms",shop.get("manufacturing_terms",shop.get("agricultural_terms",{}))).base_capacity)*efficiency*security/1000000 if security>=20 else 0
	return {"ok":true,"manager_id":manager,"suitability":fit,"security":security,"efficiency_bp":efficiency,"capacity":quantity,"weight":maxi(1,efficiency)}

# Largest-remainder allocation shares a customer's finite monthly demand among real open shops.
static func quota(state, shop: Dictionary, demand: int) -> int:
	var weights := {}; var total := 0
	for other in state.management_assets.values():
		if other.get("asset_kind")!="retail_shop" or other.status!="open" or other.location_id!=shop.location_id or other.retail_terms.stock_id!=shop.retail_terms.stock_id: continue
		var assessment := capacity(state,other)
		if not assessment.ok or assessment.capacity<=0: continue
		weights[other.asset_id] = int(assessment.weight); total += int(assessment.weight)
	if total==0 or not weights.has(shop.asset_id): return 0
	var allocated := {}; var remainders: Array = []; var used := 0
	for id in weights:
		allocated[id] = demand*int(weights[id])/total; used += int(allocated[id])
		remainders.append({"id":id,"remainder":demand*int(weights[id])%total})
	remainders_sort(remainders)
	for i in demand-used: allocated[remainders[i].id] += 1
	return int(allocated[shop.asset_id])

static func remainders_sort(rows: Array) -> void:
	rows.sort_custom(func(a,b):return a.remainder>b.remainder if a.remainder!=b.remainder else str(a.id)<str(b.id))

static func _buyers(state, shop: Dictionary) -> Array:
	var stock: Dictionary = state.management_assets[shop.retail_terms.stock_id]
	return stock.retail_offer.buyers

static func sale_quote(state, shop: Dictionary, buyer_id: String, manager: String = "") -> Dictionary:
	var entries: Array = _buyers(state,shop).filter(func(row):return row.buyer_id==buyer_id)
	if entries.size()!=1: return Contract.fail("没有该买方的实际购买约定")
	var buyer: Dictionary = entries[0]
	if not Presence.present(state,buyer_id,shop.location_id) or int(buyer.valid_until_day)<int(state.current_day) or not Accounts.new().can_operate(state,buyer.account_id,buyer_id): return Contract.fail("买方不在当地、约定过期或无法付款")
	var assessment := capacity(state,shop,manager)
	if not assessment.ok: return assessment
	var price := int(shop.retail_terms.unit_sale_price)
	if price>int(buyer.maximum_unit_price): return Contract.fail("售价超过买方接受的价格")
	var available := Accounts.new().available(state,buyer.account_id)
	var remaining := maxi(0,int(buyer.monthly_quantity)-sold(state,shop.retail_terms.stock_id,buyer_id))
	var share := maxi(0,quota(state,shop,int(buyer.monthly_quantity))-sold(state,shop.retail_terms.stock_id,buyer_id,shop.asset_id))
	var quantity := mini(mini(remaining,share),mini(held(shop),mini(available/price,int(assessment.capacity))))
	return {"ok":true,"quantity":quantity,"unit_price":price,"account_id":buyer.account_id,"review":{"version":1,"manager_id":assessment.manager_id,"day":int(state.current_day),"suitability":assessment.suitability,"security":assessment.security,"capacity":assessment.capacity,"buyer_cash":available,"remaining_demand":remaining,"allocated_demand":share,"stock_on_hand":held(shop),"quantity":quantity}}

static func cost_for(state, kind: String, params: Dictionary) -> Dictionary:
	var shop: Dictionary = state.management_assets.get(params.get("shop_id"),{})
	if shop.get("asset_kind")!="retail_shop" or kind not in KINDS or not Contract.amount(params.get("quantity"),true): return Contract.fail("零售动作缺少实际店铺或有效数量")
	var stock: Dictionary = state.management_assets[shop.retail_terms.stock_id]
	if kind=="retail_restock": return {"ok":true,"account_id":shop.account_id,"amount":int(params.quantity)*int(stock.retail_offer.unit_price)}
	if not params.get("buyer_id") is String: return Contract.fail("销售需要具名购买约定")
	return {"ok":true,"account_id":"","amount":0}

static func guard(state, auth: Dictionary, kind: String, params: Dictionary, executor: String = "") -> Dictionary:
	var policy: Dictionary = auth.business_policy
	if kind not in KINDS or params.get("shop_id")!=policy.shop_id: return Contract.fail("超出零售授权范围")
	var shop: Dictionary = state.management_assets[policy.shop_id]
	if shop.status!="open": return Contract.fail("店铺尚未开业或已经停业")
	var ready: Dictionary = load("res://scripts/core/pawnshop_service.gd")._ready_to_trade(state,shop)
	if not ready.ok: return ready
	if executor!="" and ready.person_id!=executor: return Contract.fail("销售经办人不具备当前履职资格")
	var checked := cost_for(state,kind,params)
	if not checked.ok: return checked
	if kind=="retail_sale":
		var sale := sale_quote(state,shop,params.buyer_id,ready.person_id)
		if not sale.ok: return sale
		if int(params.quantity)>int(sale.quantity): return Contract.fail("销售超过库存、产能、实际购买力或剩余需求")
	else:
		var stock: Dictionary = state.management_assets[shop.retail_terms.stock_id]
		var offer: Dictionary = stock.retail_offer
		if not Presence.present(state,offer.supplier_id,shop.location_id) or int(offer.valid_until_day)<int(state.current_day): return Contract.fail("供货人不在当地或供货约定过期")
		if int(params.quantity)>int(stock.remaining_quantity) or held(shop)+int(params.quantity)>int(shop.retail_terms.target_stock): return Contract.fail("供货不足或超过本铺库存目标")
		if int(checked.amount)>int(policy.loan_limit) or spent(state,shop.asset_id)+int(checked.amount)>int(policy.monthly_limit): return Contract.fail("进货超过单笔或本月授权上限")
		if Accounts.new().available(state,shop.account_id,str(auth.reservation_refs.get(shop.account_id,"")))-int(checked.amount)<int(policy.cash_floor): return Contract.fail("进货会低于现金底线")
	return {"ok":true}

static func choose(state, auth: Dictionary) -> Dictionary:
	var shop: Dictionary = state.management_assets[auth.business_policy.shop_id]
	var possible_demand := false
	for buyer in _buyers(state,shop):
		var sale := sale_quote(state,shop,buyer.buyer_id)
		if not sale.ok: continue
		if int(sale.quantity)>0: return {"kind":"retail_sale","parameters":{"shop_id":shop.asset_id,"buyer_id":buyer.buyer_id,"quantity":sale.quantity}}
		if sale.review.remaining_demand>0 and sale.review.allocated_demand>0 and sale.review.buyer_cash>=sale.unit_price and sale.review.capacity>0: possible_demand = true
	if not possible_demand: return {"reason":"当前实际需求、购买力或开工条件不足；保留现金与库存。"}
	var stock: Dictionary = state.management_assets[shop.retail_terms.stock_id]
	var cash := maxi(0,Accounts.new().available(state,shop.account_id)-int(auth.business_policy.cash_floor))
	var budget := mini(cash,mini(int(auth.business_policy.loan_limit),maxi(0,int(auth.business_policy.monthly_limit)-spent(state,shop.asset_id))))
	var quantity := mini(maxi(0,int(shop.retail_terms.target_stock)-held(shop)),mini(int(stock.remaining_quantity),budget/int(stock.retail_offer.unit_price)))
	if quantity<=0: return {"reason":"现有供货、库存目标或进货预算不足；没有额外采购。"}
	var params := {"shop_id":shop.asset_id,"quantity":quantity}
	var ready := guard(state,auth,"retail_restock",params)
	return {"kind":"retail_restock","parameters":params} if ready.ok else {"reason":ready.error}

static func apply(state, kind: String, params: Dictionary, principal: String, executor: String, execution: String, reservation: String = "") -> Dictionary:
	var shop: Dictionary = state.management_assets[params.shop_id]
	var auth: Dictionary = load("res://scripts/core/business_management_service.gd").current(state,shop.asset_id)
	if auth.is_empty() or auth.principal_id!=principal: return Contract.fail("日常进销须由已获持续授权的负责人经办")
	var checked := guard(state,auth,kind,params,executor)
	if not checked.ok: return checked
	var stock: Dictionary = state.management_assets[shop.retail_terms.stock_id]
	var id := "retail:"+execution
	var quantity := int(params.quantity)
	var source := str(shop.account_id); var destination := str(stock.retail_offer.payee_account_id); var actor := principal
	var price := int(stock.retail_offer.unit_price); var person := str(stock.retail_offer.supplier_id)
	var review := {}; var allocations := {}; var cost := 0
	if kind=="retail_sale":
		var sale := sale_quote(state,shop,params.buyer_id,executor)
		price = int(sale.unit_price); source = sale.account_id; destination = shop.account_id; actor = params.buyer_id; person = params.buyer_id; review = sale.review
		var remaining := quantity
		var lots: Array = shop.stock_lots.keys()
		lots.sort_custom(func(a,b):return int(state.economic_contracts[a].day)<int(state.economic_contracts[b].day) if state.economic_contracts[a].day!=state.economic_contracts[b].day else str(a)<str(b))
		for lot_id in lots:
			var take := mini(remaining,int(shop.stock_lots[lot_id].remaining))
			if take>0: allocations[lot_id] = take; cost += take*int(shop.stock_lots[lot_id].unit_cost); remaining -= take
			if remaining==0: break
		if remaining!=0: return Contract.fail("库存不足，不能形成空头销售")
	var paid := Accounts.new().apply(state,"transfer",{"execution_id":execution,"source_account_id":source,"destination_account_id":destination,"amount":quantity*price,"actor_id":actor,"reason_ref":id,"reservation_id":reservation if kind=="retail_restock" else ""})
	if not paid.ok: return paid
	var trade := {"contract_id":id,"contract_kind":"retail_trade","status":"settled","party_refs":[shop.owner_ref.entity_id,person],"terms_version":1,"execution_refs":[execution],"shop_id":shop.asset_id,"stock_id":stock.asset_id,"operation":kind,"day":int(state.current_day),"quantity":quantity,"unit_price":price,"amount":quantity*price,"goods_cost":cost,"counterparty_id":person,"source_account_id":source,"destination_account_id":destination,"manager_id":executor,"review":review,"lot_allocations":allocations,"recipe":{"inputs":[{"stock_id":stock.asset_id,"quantity":quantity}]} if kind=="retail_restock" else {"inputs":[]}}
	state.economic_contracts[id] = trade
	if kind=="retail_restock":
		stock.remaining_quantity -= quantity; stock.consumptions[id] = quantity
		shop.stock_lots[id] = {"remaining":quantity,"unit_cost":price}
	else:
		for lot_id in allocations: shop.stock_lots[lot_id].remaining -= int(allocations[lot_id])
	return {"ok":true,"result_ref":id,"journal_refs":[execution],"visible_summary":("已采购布帛 %d，支出 %d；未售库存保留。" if kind=="retail_restock" else "已售布帛 %d，实收 %d；对应存货成本另计。") % [quantity,quantity*price]}

static func validate(raw: Dictionary) -> Dictionary:
	var assets: Dictionary = raw.management_assets
	for stock in assets.values():
		if not stock.has("retail_offer"): continue
		var offer: Variant = stock.retail_offer
		if stock.get("asset_kind")!="material_stock" or stock.get("material_key")!="cloth" or not offer is Dictionary: return Contract.fail("零售货源缺少真实材料库存")
		if stock.owner_ref!={"entity_kind":"character","entity_id":offer.get("supplier_id")} or raw.resource_accounts.get(offer.get("payee_account_id"),{}).get("owner_ref")!=stock.owner_ref: return Contract.fail("零售供货人与货权、收款账户不符")
		for key in ["unit_price","version","valid_until_day"]:
			if not Contract.amount(offer.get(key),true): return Contract.fail("零售供货价格、版本或期限错误")
		if not offer.get("buyers") is Array: return Contract.fail("购买约定无效")
		var seen := {}
		for buyer in offer.buyers:
			if not buyer is Dictionary or seen.has(buyer.get("buyer_id")) or not raw.character_states.has(buyer.get("buyer_id")) or raw.resource_accounts.get(buyer.get("account_id"),{}).get("owner_ref")!={"entity_kind":"character","entity_id":buyer.get("buyer_id")}: return Contract.fail("购买约定丢失具名买方与实际账户")
			for key in ["monthly_quantity","maximum_unit_price","valid_until_day"]:
				if not Contract.amount(buyer.get(key),true): return Contract.fail("购买约定缺少数量、价格或期限")
			seen[buyer.buyer_id] = true
	for asset in assets.values():
		if asset.get("asset_kind")=="land":
			for offer in asset.development_offers.values():
				if offer.get("industry_kind")=="cloth_shop":
					var checked := _validate_terms(offer.get("retail_terms"),raw,asset.location_id)
					if not checked.ok: return checked
		if asset.get("asset_kind") not in ["retail_shop","estate_building"] or (asset.get("asset_kind")=="estate_building" and asset.get("industry_kind")!="cloth_shop"): continue
		var checked := _validate_terms(asset.get("retail_terms"),raw,asset.location_id)
		if not checked.ok: return checked
		var building: Dictionary = assets.get(asset.get("building_id"),{}) if asset.asset_kind=="retail_shop" else asset
		var order: Dictionary = raw.economic_contracts.get(building.source_ref.get("entity_id"),{})
		if order.get("recipe",{}).get("retail_terms")!=asset.retail_terms: return Contract.fail("零售设施或经营条款失去已签工程来源")
		if asset.asset_kind=="retail_shop" and (asset.get("industry_kind")!="cloth_shop" or not asset.get("stock_lots") is Dictionary): return Contract.fail("零售店铺品类或库存记录无效")
	var lots := {}; var sold_lots := {}; var customer_totals := {}
	for trade in raw.economic_contracts.values():
		if trade.get("contract_kind")!="retail_trade": continue
		var shop: Dictionary = assets.get(trade.get("shop_id"),{})
		var stock: Dictionary = assets.get(trade.get("stock_id"),{})
		if shop.get("asset_kind")!="retail_shop" or stock.get("asset_id")!=shop.retail_terms.stock_id or trade.get("operation") not in KINDS or trade.get("status")!="settled": return Contract.fail("零售交易缺少实际店铺、货源或交割状态")
		for key in ["day","goods_cost","quantity","unit_price","amount"]:
			if not Contract.amount(trade.get(key),key in ["quantity","unit_price","amount"]): return Contract.fail("零售交易数额错误")
		if int(trade.day)>int(raw.current_day) or trade.amount!=int(trade.quantity)*int(trade.unit_price) or not trade.get("execution_refs") is Array or trade.execution_refs.size()!=1 or not trade.get("lot_allocations") is Dictionary: return Contract.fail("零售交易日期、金额或出库记录错误")
		var execution: String = str(trade.execution_refs[0])
		var receipt: Dictionary = raw.action_receipts.get(execution,{})
		var payment: Dictionary = raw.resource_journal.get(execution,{})
		if receipt.get("executor_id")!=trade.get("manager_id") or receipt.get("day")!=trade.day or not receipt.get("effect_refs",[]).has(trade.contract_id) or payment.get("reason_ref")!=trade.contract_id or payment.get("amount")!=trade.amount or payment.get("source_account_id")!=trade.get("source_account_id") or payment.get("destination_account_id")!=trade.get("destination_account_id"): return Contract.fail("零售交易与实际经办付款回执不符")
		var tasks: Array = raw.active_tasks+raw.completed_tasks
		var matching: Array = tasks.filter(func(task):return task.get("task_id")==receipt.get("task_id"))
		if matching.size()!=1: return Contract.fail("零售交割丢失持续经营任务")
		var steps: Array = matching[0].steps.filter(func(step):return step.get("execution_id")==execution)
		if steps.size()!=1 or steps[0].action_kind!=trade.operation or steps[0].parameters.get("quantity")!=trade.quantity or steps[0].parameters.get("shop_id")!=shop.asset_id: return Contract.fail("零售交割数量与获准动作不符")
		if trade.operation=="retail_restock":
			if trade.source_account_id!=shop.account_id or trade.destination_account_id!=stock.retail_offer.payee_account_id or trade.counterparty_id!=stock.retail_offer.supplier_id or trade.unit_price!=stock.retail_offer.unit_price or trade.goods_cost!=0 or not trade.lot_allocations.is_empty() or stock.consumptions.get(trade.contract_id)!=trade.quantity: return Contract.fail("采购价款或实际出库货源不符")
			lots[trade.contract_id] = {"shop_id":shop.asset_id,"quantity":int(trade.quantity),"unit_cost":int(trade.unit_price)}
		else:
			var buyers: Array = stock.retail_offer.buyers.filter(func(b):return b.buyer_id==trade.get("counterparty_id"))
			if buyers.size()!=1 or steps[0].parameters.get("buyer_id")!=trade.counterparty_id or trade.source_account_id!=buyers[0].account_id or trade.destination_account_id!=shop.account_id or trade.unit_price!=shop.retail_terms.unit_sale_price or int(trade.unit_price)>int(buyers[0].maximum_unit_price) or int(trade.day)>int(buyers[0].valid_until_day): return Contract.fail("实际销售不符合购买约定")
			var used := 0; var cost := 0
			for lot_id in trade.lot_allocations:
				var purchase: Dictionary = raw.economic_contracts.get(lot_id,{})
				var quantity: Variant = trade.lot_allocations[lot_id]
				if not Contract.amount(quantity,true) or purchase.get("operation")!="retail_restock" or purchase.get("shop_id")!=shop.asset_id or int(purchase.get("day",2147483647))>int(trade.day): return Contract.fail("销售缺少先前实际进货批次")
				used += int(quantity); cost += int(quantity)*int(purchase.unit_price)
				sold_lots[lot_id] = int(sold_lots.get(lot_id,0))+int(quantity)
			if used!=int(trade.quantity) or cost!=int(trade.goods_cost): return Contract.fail("已售库存与营业成本不符")
			var review: Variant = trade.get("review")
			if not review is Dictionary or review.get("version")!=1 or review.get("manager_id")!=trade.manager_id or review.get("day")!=trade.day or review.get("quantity")!=trade.quantity: return Contract.fail("销售丢失当时履职与市场核验")
			for key in ["suitability","security","capacity","buyer_cash","remaining_demand","allocated_demand","stock_on_hand","quantity"]:
				if not Contract.amount(review.get(key)): return Contract.fail("销售评估数据损坏")
			if int(review.suitability)>100 or int(review.security)>100 or int(review.security)<20 or int(review.capacity)!=int(shop.retail_terms.base_capacity)*(6000+int(review.suitability)*80)*int(review.security)/1000000: return Contract.fail("销售能力与当地秩序评估不符")
			if int(review.quantity)>mini(mini(int(review.capacity),int(review.remaining_demand)),mini(int(review.allocated_demand),mini(int(review.stock_on_hand),int(review.buyer_cash)/int(trade.unit_price)))): return Contract.fail("销售超过当时核验的库存、能力或需求")
			var month := int(floor(float(int(trade.day)-int(raw.current_day)+int(raw.current_date.day)-1)/float(preload("res://scripts/core/strategic_time_service.gd").DAYS_PER_MONTH)))
			var key := "%s:%s:%d" % [stock.asset_id,trade.counterparty_id,month]
			customer_totals[key] = int(customer_totals.get(key,0))+int(trade.quantity)
			if int(customer_totals[key])>int(buyers[0].monthly_quantity): return Contract.fail("同市场多店重复耗用了同一月需求")
	for shop in assets.values():
		if shop.get("asset_kind")!="retail_shop": continue
		var expected := {}
		for id in lots:
			if lots[id].shop_id!=shop.asset_id: continue
			var remaining := int(lots[id].quantity)-int(sold_lots.get(id,0))
			if remaining<0: return Contract.fail("销售超过真实进货库存")
			expected[id] = {"remaining":remaining,"unit_cost":lots[id].unit_cost}
		if shop.stock_lots.size()!=expected.size(): return Contract.fail("店铺库存与采购销售记录不守恒")
		for id in expected:
			var lot: Variant = shop.stock_lots.get(id)
			if not lot is Dictionary or lot.size()!=2 or not Contract.amount(lot.get("remaining")) or not Contract.amount(lot.get("unit_cost"),true) or int(lot.remaining)!=expected[id].remaining or int(lot.unit_cost)!=expected[id].unit_cost: return Contract.fail("店铺库存与采购销售记录不守恒")
	return {"ok":true}

static func _validate_terms(terms: Variant, raw: Dictionary, location: String) -> Dictionary:
	if not terms is Dictionary or terms.get("good_id")!="cloth": return Contract.fail("零售品类未配置")
	var stock: Dictionary = raw.management_assets.get(terms.get("stock_id"),{})
	if stock.get("material_key")!="cloth" or stock.get("location_id")!=location or not stock.has("retail_offer"): return Contract.fail("零售设施缺少同地实际供货来源")
	for key in ["unit_sale_price","base_capacity","target_stock"]:
		if not Contract.amount(terms.get(key),true): return Contract.fail("零售售价、设施能力或库存上限无效")
	return {"ok":true}
