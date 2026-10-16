extends RefCounted
## Coarse scenario journeys: explicit time/cost, one shared world clock.
const Rules=preload("res://scripts/core/management_state_contract.gd")
const Accounts=preload("res://scripts/core/resource_account_service.gd")
const KIND="visit_region"
const KEY="regional_player_journeys"
const SOURCE="rule:regional_visit_756"
const DESTINATIONS={"refugee_market_node":{"name":"市集","days":3},"zhou_dezhou":{"name":"平原","days":5},"lingwu_court_node":{"name":"灵武","days":8},"chengdou_rear_hub_node":{"name":"成都","days":12},"taiyuan_hub_node":{"name":"太原","days":6},"yangzhou_tribute_hub_node":{"name":"扬州","days":10}}
# Coarse campaign pacing, not measured distances or historical travel times.
# Keep existing six destination costs stable for saved journeys.
const REGION_DAYS={"京畿道":8,"都畿道":7,"关内道":8,"河南道":6,"河东道":6,"河北道":5,"山南东道":10,"山南西道":10,"陇右道":12,"淮南道":10,"江南东道":14,"江南西道":14,"黔中道":16,"剑南道":12,"岭南道":18,"安西都护府":24,"北庭都护府":24}

static func destinations(state) -> Dictionary:
	var result: Dictionary=DESTINATIONS.duplicate(true)
	for row in state.flags.get("regional_census",{}).get("prefectures",{}).values():
		var node: String=str(row.get("city",{}).get("domain_id",""))
		var region: String=str(row.get("region_id","")).trim_prefix("region:唐:")
		if node.is_empty() or result.has(node) or not state.local_node_state.has(node) or not REGION_DAYS.has(region): continue
		result[node]={"name":str(row.name),"days":REGION_DAYS[region]}
	return result

static func current(state, person: String = "") -> Dictionary:
	if person.is_empty(): person = state.player_character_id
	for row in state.flags.get(KEY,{}).values():
		if row.person_id==person and row.status=="travelling": return row
	return {}

static func quote(state, destination: String, person: String = "") -> Dictionary:
	if person.is_empty(): person = state.player_character_id
	if not state.character_states.has(person): return Rules.fail("行程本人不存在")
	var origin: String=str(state.character_states[person].get("location_id",""))
	if not current(state, person).is_empty(): return Rules.fail("已有行程在途，请等候到达")
	if not preload("res://scripts/core/character_workload_service.gd").can_schedule(state, person, "personal_travel", person): return Rules.fail("本人已有不能兼顾的职责或行程")
	var available: Dictionary=destinations(state)
	if not available.has(origin) or not available.has(destination) or origin==destination or not state.local_node_state.has(destination): return Rules.fail("尚无该出发地至目的地的地区行程配置")
	var days: int=maxi(int(available[origin].days),int(available[destination].days))
	return {"ok":true,"account_id":person+"_cash","amount":days,"days":days,"origin":origin,"destination":destination}

static func cost_for(state,params: Dictionary, person: String = "") -> Dictionary:
	return quote(state,str(params.get("destination_id","")), person)

static func apply(state,params: Dictionary,principal: String,executor: String,execution: String) -> Dictionary:
	if executor!=principal: return Rules.fail("本人行程不能代替其他人物办理")
	var terms: Dictionary=cost_for(state,params,principal)
	if not terms.ok: return terms
	if not state.depot_states.has("personal_"+principal): return Rules.fail("缺少本人的随身账户")
	if state.character_states[principal].get("status") in ["dead","deceased","imprisoned","missing","departed"]: return Rules.fail("本人目前无法出行")
	var fee_ref: String=execution+":fare"
	var paid: Dictionary=Accounts.new().apply(state,"consume",{"execution_id":fee_ref,"account_id":terms.account_id,"amount":terms.amount,"actor_id":principal,"reason_ref":SOURCE})
	if not paid.ok: return paid
	if not state.flags.has(KEY): state.flags[KEY]={}
	var transit: String="regional-journey:"+execution
	state.flags[KEY][execution]={"journey_id":execution,"person_id":principal,"origin":terms.origin,"destination":terms.destination,"required_days":terms.days,"elapsed_days":0,"created_day":int(state.current_day),"last_day":int(state.current_day),"status":"travelling","transit":transit,"fare_ref":fee_ref,"source_id":SOURCE,"blocked_reason":""}
	preload("res://scripts/core/official_journey_service.gd").move(state,principal,transit)
	return {"ok":true,"result_ref":execution,"journal_refs":[fee_ref],"visible_summary":"已启程前往%s，预计%d日；旅费%d（地区行程游戏估算）。" % [destinations(state)[terms.destination].name,terms.days,terms.amount]}

static func settle(state) -> Dictionary:
	for row in state.flags.get(KEY,{}).values():
		if row.status!="travelling" or int(row.last_day)>=int(state.current_day): continue
		row.last_day=int(state.current_day)
		if state.character_states.get(row.person_id,{}).get("status") in ["dead","deceased","imprisoned","missing","departed","exiled","unreachable"]:
			row.blocked_reason="本人目前无法继续行程"
			continue
		var origin: Dictionary=state.local_node_state.get(row.origin,{})
		var destination: Dictionary=state.local_node_state.get(row.destination,{})
		if mini(int(origin.get("security",0)),int(destination.get("security",0)))<20:
			row.blocked_reason="起讫地区局势危险，行程暂缓"
			continue
		row.blocked_reason=""
		row.elapsed_days+=1
		if row.elapsed_days>=row.required_days:
			row.status="arrived"; row["arrived_day"]=int(state.current_day)
			preload("res://scripts/core/official_journey_service.gd").move(state,row.person_id,row.destination)
	return {"ok":true}

static func project(state,nodes: Array) -> Dictionary:
	var result := {"options":[],"status":""}
	var available: Dictionary=destinations(state)
	var underway: Dictionary=current(state)
	if not underway.is_empty():
		result.status="前往%s · 行程%d/%d日。%s" % [available[underway.destination].name,underway.elapsed_days,underway.required_days,underway.blocked_reason]
		return result
	for node in nodes:
		var terms: Dictionary=quote(state,str(node))
		if not terms.ok: continue
		result.options.append({"destination_id":node,"name":available[node].name,"days":terms.days,"cost":terms.amount})
	return result

static func validate(raw: Dictionary) -> Dictionary:
	var registry: Variant=raw.get("flags",{}).get(KEY,{})
	if not registry is Dictionary: return Rules.fail("地区行程记录无效")
	var available: Dictionary=destinations(raw)
	var travelling := {}
	for id in registry:
		var row: Variant=registry[id]
		if not row is Dictionary or row.get("journey_id")!=id or row.get("source_id")!=SOURCE or not raw.character_states.has(row.get("person_id")): return Rules.fail("地区行程身份或来源无效")
		if not available.has(row.get("origin")) or not available.has(row.get("destination")) or row.origin==row.destination or row.get("status") not in ["travelling","arrived"] or row.get("transit")!="regional-journey:"+str(id): return Rules.fail("地区行程端点或状态无效")
		for key in ["required_days","elapsed_days","created_day","last_day"]:
			if not Rules.amount(row.get(key)): return Rules.fail("地区行程日期或进度无效")
		var duration: int=maxi(int(available[row.origin].days),int(available[row.destination].days))
		if row.required_days!=duration or row.elapsed_days>duration or row.created_day>row.last_day or row.last_day>raw.current_day or row.elapsed_days>row.last_day-row.created_day: return Rules.fail("地区行程进度不符")
		var fee: Dictionary=raw.resource_journal.get(row.get("fare_ref"),{})
		var receipt: Dictionary=raw.action_receipts.get(id,{})
		if fee.get("entry_kind")!="rule_consumption" or fee.get("source_account_id")!=row.person_id+"_cash" or fee.get("amount")!=duration or fee.get("reason_ref")!=SOURCE or fee.get("day")!=row.created_day or not receipt.get("journal_refs",[]).has(row.fare_ref) or receipt.get("regional_visit")!={"person_id":row.person_id,"destination":row.destination,"origin":row.origin}: return Rules.fail("地区行程缺少原旅费与动作回执")
		if row.status=="travelling":
			if travelling.has(row.person_id) or row.elapsed_days>=duration or raw.character_states[row.person_id].get("location_id")!=row.transit or raw.depot_states.get("personal_"+row.person_id,{}).get("location_node_id")!=row.transit: return Rules.fail("在途人物与随身账户位置不一致")
			travelling[row.person_id]=true
		elif row.elapsed_days!=duration or row.get("arrived_day")!=row.last_day: return Rules.fail("地区到达记录不符")
	return {"ok":true}
