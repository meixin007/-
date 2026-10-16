extends RefCounted
## Monthly observations and their actual delivery live in the existing report registry.
const Finance = preload("res://scripts/core/business_financial_projection.gd")
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Staff = preload("res://scripts/core/business_staff_service.gd")
const Roads = preload("res://scripts/core/runtime_corridor_reader.gd")
const Calendar = preload("res://scripts/core/strategic_time_service.gd")
const MONEY := ["revenue","expenses","goods_cost","bad_debt","net_profit","closing_cash","principal_outstanding","inventory_value","work_in_progress_value","capital_investment"]

static func _id(shop_id: String, through_day: int, recipient: String) -> String:
	return "business-month:"+shop_id+":"+str(through_day)+":"+recipient

static func _first_day(state, shop_id: String) -> int:
	var result := 2147483647
	for receipt in state.action_receipts.values():
		if receipt.get("effect_refs",[]).has(shop_id): result=mini(result,int(receipt.day))
	return result

static func settle_daily(state) -> Dictionary:
	var recipient: String = state.player_character_id
	for shop in state.management_assets.values():
		if shop.get("asset_kind") not in ["pawnshop","retail_shop","manufacturing_shop","managed_farm","modeled_business"] or not Accounts.new().can_operate(state,shop.account_id,recipient): continue
		var first := _first_day(state,shop.asset_id)
		var end: int = int(state.current_day)-int(state.current_date.day)
		var ago := 1
		while end>=first:
			var id := _id(shop.asset_id,end,recipient)
			if not state.active_intelligence_reports.has(id):
				var sender := Staff.resolve(state,shop)
				if not sender.ok: break # A vacant or unreachable post cannot invent a signed return.
				var term := ""
				for office_term in state.office_terms.values():
					if office_term.get("office_id")==sender.office_id and office_term.get("holder_id")==sender.person_id and int(office_term.end_day)<0: term=office_term.term_id
				if term.is_empty(): break
				var statement := Finance.monthly(state,shop.asset_id,ago)
				var report := {"report_id":id,"report_kind":"business_monthly","shop_id":shop.asset_id,"shop_name":shop.name,"owner_ref":shop.owner_ref.duplicate(true),"recipient_id":recipient,"sender_id":sender.person_id,"term_id":term,"source_node_id":shop.location_id,"current_node_id":shop.location_id,"statement":statement,"created_day":int(state.current_day),"last_advanced_day":int(state.current_day),"status":"in_transit","delivered_day":-1,"recipient_node_id":"","leg":{},"travel_log":[]}
				state.active_intelligence_reports[id]=report
				_deliver_here(state,report)
			end-=Calendar.DAYS_PER_MONTH; ago+=1
	for report in state.active_intelligence_reports.values():
		if report.get("report_kind")=="business_monthly": _advance(state,report)
	return {"ok":true}

static func _advance(state, report: Dictionary) -> void:
	preload("res://scripts/core/dispatch_transport.gd").advance(state,report)

static func _deliver_here(state, report: Dictionary) -> bool:
	return preload("res://scripts/core/dispatch_transport.gd")._deliver_here(state,report)

static func project(state) -> Array:
	var groups := {}
	var registry: Dictionary = state.get("active_intelligence_reports",{}) if state is Dictionary else state.active_intelligence_reports
	var viewer: String = str(state.get("player_character_id","")) if state is Dictionary else str(state.player_character_id)
	var ids: Array = registry.keys(); ids.sort()
	for id in ids:
		var report: Dictionary = registry[id]
		if report.get("report_kind")!="business_monthly" or report.get("status")!="delivered" or report.get("recipient_id")!=viewer: continue
		var statement: Dictionary = report.statement
		var key := str(statement.through_day)
		if not groups.has(key): groups[key]={"event_id":"business-monthly:"+viewer+":"+key,"title":str(statement.period_label)+"经营月报","summary":"","source_label":"掌柜月报","feed_kind":"report","severity":"notice","day":0,"confidence":1.0,"related_character_ids":[],"profit":0,"rows":[],"count":0}
		var item: Dictionary = groups[key]
		item.day=maxi(int(item.day),int(report.delivered_day)); item.profit+=int(statement.net_profit); item.count+=1
		if not item.related_character_ids.has(report.sender_id): item.related_character_ids.append(report.sender_id)
		if item.rows.size()<8: item.rows.append("%s：收入 %d，已售成本 %d，经营费用 %d，确认损失 %d，盈亏 %+d。" % [report.shop_name,statement.revenue,statement.goods_cost,statement.expenses,statement.bad_debt,statement.net_profit])
		if report.travel_log.any(func(tick):return tick.get("journey_kind")=="regional_estimate") and not item.rows.has("部分月报按地区行程游戏估算送达；没有据此补造道路或产业交通资料。"):
			item.rows.append("部分月报按地区行程游戏估算送达；没有据此补造道路或产业交通资料。")
	var result: Array = []
	for item in groups.values():
		item.summary="已收到 %d 家产业月报，合计已实现盈亏 %+d（钱款记账单位）。\n%s\n结账至第 %d 日；仅合计已送达的账目，不代表当前现金或可共同支用的资金。" % [item.count,item.profit,"\n".join(item.rows),int(str(item.event_id).get_slice(":",2))]
		if item.count>8: item.summary+="\n其余产业可在地区经营汇总查看。"
		for field in ["profit","rows","count"]: item.erase(field)
		result.append(item)
	return result.duplicate(true)

static func validate(raw: Dictionary) -> Dictionary:
	for id in raw.get("active_intelligence_reports",{}):
		var report: Variant = raw.active_intelligence_reports[id]
		if not report is Dictionary or report.get("report_kind")!="business_monthly": continue
		var shop: Dictionary = raw.management_assets.get(report.get("shop_id"),{})
		if shop.get("asset_kind") not in ["pawnshop","retail_shop","manufacturing_shop","managed_farm","modeled_business"] or not report.get("statement") is Dictionary: return _fail("经营月报缺少真实产业与账目")
		var statement: Dictionary = report.statement
		var term: Dictionary = raw.office_terms.get(report.get("term_id"),{})
		for field in ["created_day","last_advanced_day"]:
			if not _integer(report.get(field),0) or int(report[field])>int(raw.current_day): return _fail("经营月报日期无效")
		if int(report.last_advanced_day)<int(report.created_day) or not _integer(statement.get("through_day"),0) or int(statement.through_day)>=int(report.created_day) or not _integer(statement.get("from_day"),0): return _fail("经营月报结账日期无效")
		if id!=_id(shop.asset_id,int(statement.through_day),str(report.get("recipient_id",""))) or report.get("report_id")!=id or report.get("source_node_id")!=shop.location_id or report.get("owner_ref")!=shop.owner_ref or not raw.character_states.has(report.get("recipient_id")): return _fail("经营月报来源或收件人无效")
		if term.get("holder_id")!=report.get("sender_id") or term.get("office_id") not in [shop.office_id,Staff.office_id(shop.asset_id)] or int(term.get("start_day",2147483647))>int(report.created_day) or (int(term.get("end_day",-1))>=0 and int(term.end_day)<int(report.created_day)): return _fail("经营月报签发人缺少真实任职")
		var boundary: int = int(raw.current_day)-int(raw.current_date.day)
		if int(statement.through_day)>boundary or (boundary-int(statement.through_day))%Calendar.DAYS_PER_MONTH!=0 or int(statement.from_day)!=maxi(0,int(statement.through_day)-Calendar.DAYS_PER_MONTH+1): return _fail("经营月报必须来自已结束月份")
		if int(statement.through_day)<_first_day(raw,shop.asset_id): return _fail("产业登记前不能签发经营月报")
		var expected_period := Finance.monthly(raw,shop.asset_id,1+(boundary-int(statement.through_day))/Calendar.DAYS_PER_MONTH)
		for field in ["period_label","complete","partial_campaign_month"]:
			if statement.get(field)!=expected_period.get(field): return _fail("经营月报月份口径不符")
		var actual := Finance.statement(raw,shop.asset_id,int(statement.from_day),int(statement.through_day))
		for key in MONEY+["journal_refs"]:
			if statement.get(key)!=actual.get(key): return _fail("经营月报金额与实际流水不符")
		var travel := _validate_travel(raw,report)
		if not travel.ok: return travel
	return {"ok":true}

static func _validate_travel(raw: Dictionary, report: Dictionary) -> Dictionary:
	if not report.get("travel_log") is Array or not report.get("leg") is Dictionary or report.get("status") not in ["in_transit","delivered"]: return _fail("经营月报传递记录无效")
	var node: String = report.source_node_id
	var last: int = int(report.created_day)
	var leg := {}
	for tick in report.travel_log:
		if not tick is Dictionary or not _integer(tick.get("day"),last+1) or int(tick.day)>int(report.last_advanced_day) or not _integer(tick.get("quarters"),1) or int(tick.quarters)>4 or not _integer(tick.get("required_quarters"),4): return _fail("经营月报传递日序或进度无效")
		var estimated: bool=tick.get("journey_kind")=="regional_estimate"
		var keys := ["corridor_id","from_node_id","to_node_id","required_quarters"]
		if estimated:
			var expected: Dictionary=preload("res://scripts/core/dispatch_transport.gd").regional_leg(raw,node,str(tick.get("to_node_id","")))
			if expected.is_empty() or tick.get("from_node_id")!=node or tick.get("corridor_id")!="" or tick.get("source_id")!=expected.source_id or tick.required_quarters!=expected.required_quarters or int(tick.quarters)!=4:return _fail("经营月报地区估算来源或进度无效")
			keys.append_array(["journey_kind","source_id"])
			if leg.is_empty():leg=expected
		else:
			var road: Dictionary = raw.transit_corridors.get(tick.get("corridor_id"),{})
			if road.is_empty() or tick.get("from_node_id")!=node or not ((road.from_node_id==node and road.to_node_id==tick.get("to_node_id")) or (road.to_node_id==node and road.from_node_id==tick.get("to_node_id"))): return _fail("经营月报没有实际通信道路")
			if leg.is_empty(): leg={"corridor_id":tick.corridor_id,"from_node_id":node,"to_node_id":tick.to_node_id,"required_quarters":tick.required_quarters,"quarters":0}
		for key in keys:
			if not leg.has(key) or not tick.has(key) or leg[key]!=tick[key]: return _fail("经营月报传递途中更换路径")
		leg.quarters+=int(tick.quarters); last=int(tick.day)
		if int(leg.quarters)>=int(leg.required_quarters): node=leg.to_node_id; leg={}
	if report.get("current_node_id")!=node: return _fail("经营月报位置与传递履历不符")
	# A blocked first day may retain a zero-progress leg without a travel tick.
	if leg.is_empty() and not report.leg.is_empty() and report.leg.get("quarters")==0:
		if report.leg.get("journey_kind")=="regional_estimate":
			if report.leg!=preload("res://scripts/core/dispatch_transport.gd").regional_leg(raw,node,str(report.leg.get("to_node_id",""))):return _fail("经营月报候行估算无效")
		else:
			var road: Dictionary = raw.transit_corridors.get(report.leg.get("corridor_id"),{})
			if road.is_empty() or report.leg.get("from_node_id")!=node or not _integer(report.leg.get("required_quarters"),4): return _fail("经营月报候行道路无效")
	else:
		if report.leg!=leg: return _fail("经营月报在途工日不符")
	if report.status=="delivered":
		if not report.leg.is_empty() or report.get("recipient_node_id")!=node or not _integer(report.get("delivered_day"),last) or int(report.delivered_day)>int(raw.current_day): return _fail("经营月报尚未到达却已送达")
	elif report.get("delivered_day")!=-1 or report.get("recipient_node_id")!="": return _fail("未送达经营月报不能具有收报日期")
	return {"ok":true}

static func _integer(value: Variant, minimum: int) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and floor(float(value))==float(value) and value>=minimum

static func _fail(message: String) -> Dictionary:
	return {"ok":false,"error":message}
