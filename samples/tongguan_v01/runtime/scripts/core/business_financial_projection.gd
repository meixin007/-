extends RefCounted
## Rebuild statements from the one account journal. Reports never settle trades.
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Calendar = preload("res://scripts/core/strategic_time_service.gd")

static func project(state, shop_id: String, viewer_id: String) -> Dictionary:
	var shop: Dictionary = state.management_assets.get(shop_id,{})
	if shop.get("asset_kind") not in ["pawnshop","retail_shop","manufacturing_shop","managed_farm","modeled_business"] or not Accounts.new().can_operate(state,str(shop.get("account_id","")),viewer_id): return {}
	if state.character_states.get(viewer_id,{}).get("location_id")!=shop.location_id:
		return _received(state,shop_id,viewer_id)
	var current := monthly(state,shop_id,0)
	var previous := monthly(state,shop_id,1)
	var year_start: int = int(state.current_day)-int(state.current_date.day)+1-(int(state.current_date.month)-1)*Calendar.DAYS_PER_MONTH
	return {"current":current,"previous":previous,"year_to_date_profit":statement(state,shop_id,maxi(0,year_start),int(state.current_day)).net_profit,"lifetime_profit":statement(state,shop_id,0,int(state.current_day)).net_profit,"basis":"生产口径：实际销售收入减已售生产成本与已付经营费用；未完工投入、未售成品和营造资金分列。" if shop.asset_kind=="manufacturing_shop" else "零售口径：实收销售款减已售存货成本与已付经营成本；未售库存、注资与营造投入分列，欠付款另列。" if shop.asset_kind=="retail_shop" else "已实现经营口径：实收收入减已付经营成本及已确认本金损失；本金、注资、筹办投入分列。欠付款另列，不代表完整权责发生制利润。"}

static func _received(state, shop_id: String, viewer_id: String) -> Dictionary:
	var result := {"current":{},"previous":{},"received":[],"knowledge_status":"unknown","year_to_date_profit":null,"lifetime_profit":null,"basis":"远地账目以已经送达的负责人月报为准；尚未收报的月份、当前现金和完整累计盈亏保留未知。"}
	var previous_end: int = int(state.current_day)-int(state.current_date.day)
	for report in state.active_intelligence_reports.values():
		if report.get("report_kind")!="business_monthly" or report.get("status")!="delivered" or report.get("shop_id")!=shop_id or report.get("recipient_id")!=viewer_id: continue
		var statement: Dictionary = report.statement.duplicate(true)
		statement.merge({"report_id":report.report_id,"sender_id":report.sender_id,"issued_day":report.created_day,"delivered_day":report.delivered_day})
		result.received.append(statement)
		if int(statement.through_day)==previous_end: result.previous=statement.duplicate(true)
	result.received.sort_custom(func(a,b):return int(a.through_day)>int(b.through_day))
	if not result.received.is_empty(): result.knowledge_status="reported"
	return result

static func monthly(state, shop_id: String, months_ago: int = 0) -> Dictionary:
	if months_ago < 0: return {}
	var start: int = int(state.current_day)-int(state.current_date.day)+1-months_ago*Calendar.DAYS_PER_MONTH
	var end: int = mini(int(state.current_day),start+Calendar.DAYS_PER_MONTH-1)
	if end < 0: return {}
	var month_index: int = (int(state.current_date.year)-1)*Calendar.MONTHS_PER_YEAR+int(state.current_date.month)-1-months_ago
	var result := statement(state,shop_id,maxi(0,start),end)
	if result.is_empty(): return {}
	result["period_label"] = "%s%d年%d月" % [str(state.current_date.era),1+month_index/Calendar.MONTHS_PER_YEAR,1+posmod(month_index,Calendar.MONTHS_PER_YEAR)]
	result["complete"] = months_ago > 0
	result["partial_campaign_month"] = start < 0
	return result

static func statement(state, shop_id: String, from_day: int, through_day: int) -> Dictionary:
	var shop: Dictionary = state.management_assets.get(shop_id,{})
	if shop.get("asset_kind") not in ["pawnshop","retail_shop","manufacturing_shop","managed_farm","modeled_business"] or from_day < 0 or through_day < from_day or through_day > int(state.current_day): return {}
	var result := {"shop_id":shop_id,"from_day":from_day,"through_day":through_day,"revenue":0,"expenses":0,"bad_debt":0,"net_profit":0,"capital_investment":0,"principal_advanced":0,"principal_repaid":0,"principal_outstanding":0,"capital_injected":0,"capital_withdrawn":0,"cash_in":0,"cash_out":0,"cash_change":0,"opening_cash":0,"closing_cash":0,"current_arrears":0,"cost_breakdown":{"rent":0,"wages":0,"maintenance":0},"journal_refs":[],"causes":[]}
	var account: String = shop.account_id
	var cash_after := 0
	for receipt in state.resource_journal.values():
		if receipt.get("unit_id") != "cash_unit": continue
		var day := int(receipt.day)
		var incoming: int = int(receipt.amount) if receipt.get("destination_account_id")==account else 0
		var outgoing: int = int(receipt.amount) if receipt.get("source_account_id")==account else 0
		if day > through_day: cash_after += incoming-outgoing
		if day < from_day or day > through_day: continue
		result.cash_in += incoming
		result.cash_out += outgoing
		var reason: String = receipt.reason_ref
		var contract: Dictionary = state.economic_contracts.get(reason,{})
		var belongs: bool = contract.get("shop_id")==shop_id
		var kind: String = contract.get("contract_kind","")
		if kind=="land_lease":
			var building: Dictionary=state.management_assets.get(shop.get("building_id"),{})
			var construction: Dictionary=state.economic_contracts.get(building.get("source_ref",{}).get("entity_id"),{})
			if construction.get("land_lease_id")==contract.get("contract_id") and contract.get("lessee_ref")==shop.owner_ref:
				result.cost_breakdown.rent+=int(receipt.amount);result.expenses+=int(receipt.amount);belongs=true
		if kind=="estate_construction" and contract.get("building_id")==shop.building_id and contract.get("owner_ref")==shop.owner_ref and _first_building_business(state,shop.building_id,0,shop.owner_ref)==shop_id: belongs = true
		if kind=="estate_property_sale" and contract.get("building_id")==shop.building_id and contract.get("buyer_ref")==shop.owner_ref and _first_building_business(state,shop.building_id,int(state.action_receipts.get(contract.get("receipt_id"),{}).get("state_revision_after",0)),shop.owner_ref)==shop_id:result.capital_investment+=int(receipt.amount);belongs=true
		if kind=="estate_operating_right" and contract.get("operating_shop_id")==shop_id:result.expenses+=int(receipt.amount);result.cost_breakdown["operating_right"]=int(result.cost_breakdown.get("operating_right",0))+int(receipt.amount);belongs=true
		if kind == "employment" and contract.get("office_id")==shop.office_id:
			# A transferred office pays the newly established shop, not every old shop.
			belongs = _office_business_at(state,shop.office_id,day)==shop_id
		if belongs and kind in ["lease","employment","maintenance"]:
			var category: String = {"lease":"rent","employment":"wages","maintenance":"maintenance"}[kind]
			result.cost_breakdown[category] += int(receipt.amount)
			result.expenses += int(receipt.amount)
		elif belongs and kind=="business_coordination":
			result.expenses+=int(receipt.amount)
			result.cost_breakdown["relations"]=int(result.cost_breakdown.get("relations",0))+int(receipt.amount)
		elif belongs and kind in ["setup","estate_construction","estate_improvement"]: result.capital_investment += int(receipt.amount)
		elif belongs and kind=="business_profit_distribution":
			result.capital_withdrawn+=int(receipt.amount)
			var category: String="manager_profit_shared" if receipt.get("destination_account_id")==str(contract.manager_id)+"_cash" else "owner_profit_remitted"
			result[category]=int(result.get(category,0))+int(receipt.amount)
		if reason == shop_id:
			result.capital_injected += incoming
			result.capital_withdrawn += outgoing
		if belongs or incoming > 0 or outgoing > 0: result.journal_refs.append(str(receipt.entry_id))
	for loan in state.economic_contracts.values():
		if loan.get("contract_kind") != "pawn_loan" or loan.get("shop_id") != shop_id: continue
		var issued: Dictionary = state.resource_journal[loan.execution_refs[0]]
		if int(issued.day)>through_day: continue
		var remaining := int(loan.principal)
		if int(issued.day)>=from_day: result.principal_advanced += int(loan.principal)
		var receipts: Array = []
		for ref in loan.execution_refs:
			var payment: Dictionary = state.resource_journal[ref]
			if payment.get("destination_account_id")==account: receipts.append(payment)
		receipts.sort_custom(func(a,b): return int(a.day)<int(b.day) if a.day!=b.day else str(a.entry_id)<str(b.entry_id))
		for payment in receipts:
			if int(payment.day)>through_day: continue
			var repaid := mini(remaining,int(payment.amount))
			remaining -= repaid
			if int(payment.day)>=from_day:
				result.principal_repaid += repaid
				result.revenue += int(payment.amount)-repaid
		if int(loan.principal_written_off)>0 and not receipts.is_empty():
			var loss_day := int(receipts.back().day)
			if loss_day<=through_day:
				remaining -= int(loan.principal_written_off)
				if loss_day>=from_day: result.bad_debt += int(loan.principal_written_off)
		result.principal_outstanding += remaining
	for contract in state.economic_contracts.values():
		if through_day!=int(state.current_day): break
		if contract.get("shop_id")==shop_id or (contract.get("contract_kind")=="employment" and contract.get("office_id")==shop.office_id and _office_business_at(state,shop.office_id,through_day)==shop_id): result.current_arrears += int(contract.get("arrears",0))
	result.closing_cash = Accounts.new().balance(state,account)-cash_after
	result.cash_change = result.cash_in-result.cash_out
	result.opening_cash = result.closing_cash-result.cash_change
	result["goods_cost"] = 0
	result["inventory_value"] = 0
	result["inventory_quantity"] = 0
	result["purchases"] = 0
	result["sold_quantity"] = 0
	result["work_in_progress_value"] = 0
	result["industry_kind"] = shop.get("industry_kind","pawnshop")
	if shop.asset_kind=="retail_shop":
		for trade in state.economic_contracts.values():
			if trade.get("contract_kind")!="retail_trade" or trade.shop_id!=shop_id or int(trade.day)>through_day: continue
			if trade.operation=="retail_restock":
				result.inventory_value += int(trade.amount)
				result.inventory_quantity += int(trade.quantity)
				if int(trade.day)>=from_day: result.purchases += int(trade.amount)
			else:
				result.inventory_value -= int(trade.goods_cost)
				result.inventory_quantity -= int(trade.quantity)
				if int(trade.day)>=from_day:
					result.revenue += int(trade.amount); result.goods_cost += int(trade.goods_cost); result.sold_quantity += int(trade.quantity)
		result.causes.append("本期实际售出 %d 单位布帛，已售进货成本 %d；期末未售存货价值 %d。" % [result.sold_quantity,result.goods_cost,result.inventory_value])
		result.causes.append("销量受具名买方实际资金、同市场剩余需求、负责人履职能力与当地治安秩序约束；无销售时没有收入。")
	if shop.asset_kind=="manufacturing_shop":
		for order in state.economic_contracts.values():
			if order.get("shop_id")!=shop_id: continue
			if order.get("contract_kind")=="manufacturing_batch" and int(order.created_day)<=through_day:
				if int(order.created_day)>=from_day: result.purchases += int(order.recipe.price)
				if order.get("status")=="completed" and int(order.completed_day)<=through_day:
					result.inventory_value += int(order.recipe.price)
					result.inventory_quantity += int(order.recipe.output_quantity)
				else: result.work_in_progress_value += int(order.recipe.price)
			elif order.get("contract_kind")=="manufacturing_sale" and int(order.day)<=through_day:
				result.inventory_value -= int(order.goods_cost); result.inventory_quantity -= int(order.quantity)
				if int(order.day)>=from_day:
					result.revenue += int(order.amount); result.goods_cost += int(order.goods_cost); result.sold_quantity += int(order.quantity)
		result.causes.append("本期实际售出成品 %d，已售生产成本 %d；未完工投入 %d，未售成品成本 %d。" % [result.sold_quantity,result.goods_cost,result.work_in_progress_value,result.inventory_value])
		result.causes.append("批次须领用实际原料并由工匠投入工日；成品销售受本地订单、购买资金、管事能力与治安约束。")
	if shop.asset_kind=="managed_farm": preload("res://scripts/core/managed_farming_service.gd").append_statement(state,shop,result,from_day,through_day)
	if shop.asset_kind=="modeled_business": preload("res://scripts/core/modeled_business_service.gd").append_statement(state,shop,result,from_day,through_day)
	result["asset_writeoff"]=0
	for row in state.economic_contracts.values():
		if row.get("contract_kind")=="estate_demolition" and row.get("shop_id")==shop_id and int(row.day)>=from_day and int(row.day)<=through_day:
			result.asset_writeoff+=int(row.writeoff_amount)
	result.expenses+=int(result.asset_writeoff)
	for sale in state.economic_contracts.values():
		if sale.get("contract_kind")=="estate_property_sale" and sale.get("source_shops",[]).has(shop_id) and int(sale.day)>=from_day and int(sale.day)<=through_day:
			result.expenses+=int(sale.disposal_loss)
			result.revenue+=int(sale.disposal_gain)
			result["property_disposal_loss"]=int(sale.disposal_loss);result["property_recovery"]=int(sale.amount)
			result.causes.append("房产出售收回%d、原投入%d、处置损失%d；价款进入原产权账户，旧店现金另列，原土地未出售。" % [int(sale.amount),int(sale.book_value),int(sale.disposal_loss)])
	if int(result.asset_writeoff)>0:result.causes.append("拆除核销原工程、扩建及设施筹办投入 %d；为本期资产损失，无现金退款，不重复扣店款。" % int(result.asset_writeoff))
	result.net_profit = result.revenue-result.expenses-result.bad_debt-result.goods_cost
	result.journal_refs.sort()
	if result.revenue==0 and shop.asset_kind=="pawnshop": result.causes.append("本期尚无已实现的息费收入；未收回的借款本金仍列为占用资金。")
	if int(result.expenses)-int(result.asset_writeoff)>0: result.causes.append("已付经营成本 %d，其中租金 %d、人员薪酬 %d、维护 %d；设施核销损失另列。" % [int(result.expenses)-int(result.asset_writeoff),result.cost_breakdown.rent,result.cost_breakdown.wages,result.cost_breakdown.maintenance])
	if result.bad_debt>0: result.causes.append("抵押物实际处置形成本金损失 %d，已计入本期一次。" % result.bad_debt)
	if result.current_arrears>0: result.causes.append("当前另有欠付款 %d，需安排资金；尚未作为已付成本重复扣减。" % result.current_arrears)
	var credit: Dictionary = preload("res://scripts/core/business_credit_assessment.gd").summary(state,shop_id,from_day,through_day)
	result["credit_activity"] = credit
	if int(credit.assessments)>0:
		var reasons: Array[String] = []
		for code in ["security","liquidity","coverage"]:
			if int(credit.reason_counts.get(code,0))>0: reasons.append(str({"security":"治安秩序限制","liquidity":"买方承接能力不足","coverage":"估价与风险保障不足"}[code])+" %d 次" % int(credit.reason_counts[code]))
		result.causes.append("本期新增放款评估 %d 次，暂缓 %d 次%s；同一报价可在环境变化后复核，评估本身不产生收益或损失。" % [int(credit.assessments),int(credit.deferred),"（"+"、".join(reasons)+"）" if not reasons.is_empty() else ""])
	return result

static func _office_business_at(state, office_id: String, day: int) -> String:
	var latest_day := -1
	var selected := ""
	for asset in state.management_assets.values():
		if asset.get("asset_kind") not in ["pawnshop","retail_shop","manufacturing_shop","managed_farm","modeled_business"] or asset.get("office_id")!=office_id: continue
		var first_day := 2147483647
		for receipt in state.action_receipts.values():
			if receipt.get("effect_refs",[]).has(asset.asset_id): first_day = mini(first_day,int(receipt.day))
		if first_day<=day and (first_day>latest_day or (first_day==latest_day and str(asset.asset_id)>selected)):
			latest_day = first_day
			selected = asset.asset_id
	return selected

static func _first_building_business(state, building_id: String, after_revision: int, owner: Dictionary) -> String:
	var first: int=2147483647
	var selected: String=""
	for asset in state.management_assets.values():
		if asset.get("asset_kind") not in ["pawnshop","retail_shop","manufacturing_shop","managed_farm","modeled_business"] or asset.get("building_id")!=building_id or asset.get("owner_ref")!=owner:continue
		for receipt in state.action_receipts.values():
			var revision: int=int(receipt.get("state_revision_after",0))
			if revision>=after_revision and revision<first and receipt.get("effect_refs",[]).has(asset.asset_id):first=revision;selected=asset.asset_id
	return selected
