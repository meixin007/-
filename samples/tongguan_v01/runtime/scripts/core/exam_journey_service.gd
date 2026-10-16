extends RefCounted
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Contract = preload("res://scripts/core/management_state_contract.gd")
const Education = preload("res://scripts/core/education_service.gd")
const Assessment = preload("res://scripts/core/school_assessment_service.gd")
const Workload = preload("res://scripts/core/character_workload_service.gd")
const Presence = preload("res://scripts/core/production_service.gd")
const Logistics = preload("res://scripts/core/logistics_service.gd")
const SOURCE := "res://data/scenarios/anshi_rebellion/map_strategy_nodes.json"
const KINDS := ["send_exam_candidate", "receive_exam_arrival_report"]

static func initialize(state) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	if not data is Dictionary or not data.get("transit_corridors") is Array: return Contract.fail("赴试道路定义来源无效")
	for school in state.management_assets.values():
		if school.get("asset_kind") != "school" or not school.has("exam_journey_rule"): continue
		var rule: Dictionary = school.exam_journey_rule
		var cursor: String = school.location_id
		var additions := {}
		for id in rule.corridor_ids:
			var found: Array = data.transit_corridors.filter(func(row): return row.get("corridor_id") == id)
			if found.size() != 1: return Contract.fail("赴试行程缺少唯一实际道路：" + str(id))
			var row: Dictionary = found[0].duplicate(true)
			if cursor not in [row.from_node_id, row.to_node_id] or not Contract.amount(row.get("base_travel_days"), true): return Contract.fail("赴试道路定义没有连续接通")
			cursor = row.to_node_id if cursor == row.from_node_id else row.from_node_id
			row["definition_source"] = SOURCE
			additions[id] = row
		if cursor != rule.destination_id: return Contract.fail("赴试行程未到实际目的地")
		# This explicitly sourced itinerary activates only its transport definitions.
		# Existing runtime records, closures and control remain authoritative.
		for id in additions:
			if not state.transit_corridors.has(id): state.transit_corridors[id] = additions[id]
	return {"ok": true}

static func journeys(state, school_id: String) -> Array:
	return state.economic_contracts.values().filter(func(row): return row.get("contract_kind") == "school_exam_journey" and row.get("school_id") == school_id)

static func recommendation(state, school_id: String, person: String) -> Dictionary:
	for row in state.economic_contracts.values():
		if row.get("contract_kind") == "school_candidacy" and row.get("school_id") == school_id and row.get("supplier_id") == person and row.get("status") == "admitted": return row
	return {}

static func itinerary(state, school: Dictionary) -> Dictionary:
	var legs: Array = []
	var cursor: String = school.location_id
	var total := 0
	for id in school.get("exam_journey_rule", {}).get("corridor_ids", []):
		var road: Dictionary = state.transit_corridors.get(id, {})
		if cursor not in [road.get("from_node_id"), road.get("to_node_id")] or not Contract.amount(road.get("base_travel_days"), true): return Contract.fail("当前实际交通表没有连续赴试道路")
		var destination: String = road.to_node_id if road.from_node_id == cursor else road.from_node_id
		legs.append({"corridor_id": id, "from_node_id": cursor, "to_node_id": destination, "base_days": int(road.base_travel_days)})
		total += int(road.base_travel_days)
		cursor = destination
	if legs.is_empty() or cursor != school.exam_journey_rule.destination_id: return Contract.fail("实际道路未接通赴试目的地")
	return {"ok": true, "legs": legs, "base_days": total}

static func cost_for(state, kind: String, params: Dictionary) -> Dictionary:
	var school: Dictionary = state.management_assets.get(params.get("school_id", ""), {})
	if school.get("asset_kind") != "school" or not school.has("exam_journey_rule") or str(params.get("journey_id", "")).is_empty(): return Contract.fail("赴试须有实际学舍、行程来源及独立记录")
	if kind == "receive_exam_arrival_report":
		var journey: Dictionary = state.economic_contracts.get(params.journey_id, {})
		if journey.get("contract_kind") != "school_exam_journey" or journey.get("school_id") != school.asset_id: return {"ok": false, "code": "asset_not_ready", "error": "尚无对应实际赴试行程"}
		return {"ok": true, "amount": 0, "account_id": ""}
	var rule: Dictionary = school.exam_journey_rule
	var offer: Dictionary = state.management_assets.get(rule.stall_id, {}).get("food_offer", {})
	if Education.student_offer(school, str(params.get("student_id", ""))).is_empty() or state.resource_accounts.get(params.get("funding_account_id"), {}).get("unit_id") != "cash_unit" or not Contract.amount(offer.get("price"), true) or not Contract.amount(offer.get("lot_units"), true): return Contract.fail("赴试缺少实际人物、款源或行粮报价")
	if int(rule.food_lots) > (Contract.MAX_AMOUNT - int(rule.allowance)) / int(offer.price) or int(rule.food_lots) > Contract.MAX_AMOUNT / int(offer.lot_units): return Contract.fail("赴试款粮越界")
	return {"ok": true, "amount": int(rule.allowance) + int(rule.food_lots) * int(offer.price), "account_id": params.funding_account_id}

static func location_for(state, params: Dictionary) -> String:
	return str(state.management_assets.get(params.get("school_id", ""), {}).get("location_id", ""))

static func apply(state, kind: String, params: Dictionary, principal: String, execution: String, reservation: String) -> Dictionary:
	var quote := cost_for(state, kind, params)
	if not quote.ok: return quote
	var school: Dictionary = state.management_assets[params.school_id]
	if not Education.authority(state, school, principal): return Contract.fail("当前没有该学舍赴试经办权")
	if kind == "receive_exam_arrival_report":
		var journey: Dictionary = state.economic_contracts[params.journey_id]
		if journey.status == "reported": return Contract.fail("到场回报已登记，不重复领取")
		if journey.status != "arrived" or int(state.current_day) < int(journey.report_due_day): return {"ok": false, "code": "awaiting_delivery", "error": "尚未收到本人到场回报，不能凭预计日程宣告抵达。"}
		journey.status = "reported"
		journey["report_receipt"] = execution
		journey["reported_day"] = int(state.current_day)
		return {"ok": true, "result_ref": journey.contract_id, "visible_summary": "已收到%s抵达行在的回报；报名、考试和任官仍须分别办理。" % state.character_states[journey.supplier_id].name}
	var student: String = params.student_id
	var consent := Education.student_offer(school, student)
	var admitted := recommendation(state, school.asset_id, student)
	if not consent.get("travel_willing", false) or admitted.is_empty() or not Presence.present(state, student, school.location_id): return Contract.fail("本人未同意赴试、缺少实际荐举资格或未在出发地")
	if int(state.character_states[student].get("relationships", {}).get(principal, 0)) < -15: return Contract.fail("本人目前不愿接受这项赴试安排")
	if state.office_state.values().any(func(office): return office.get("holder_id") == student and office.get("status") == "appointed"): return Contract.fail("在任者须先正式交接，不能赴试同时在原地履职")
	if state.economic_contracts.has(params.journey_id) or not Workload.can_schedule(state, student, "exam_travel", principal): return Contract.fail("已有赴试记录或本人仍有不能离开的行程")
	var path := itinerary(state, school)
	if not path.ok: return path
	var first := Logistics.new().is_corridor_passable(state, path.legs[0].corridor_id, school.exam_journey_rule.faction_id)
	if not first.is_passable: return Contract.fail("出发道路受阻：" + str(first.reason))
	var rule: Dictionary = school.exam_journey_rule
	var stall: Dictionary = state.management_assets[rule.stall_id]
	var food: Dictionary = stall.food_offer
	var seller: String = stall.owner_ref.entity_id
	var accounts := Accounts.new()
	if not accounts.can_operate(state, quote.account_id, principal) or (quote.account_id != school.account_id and state.resource_accounts[quote.account_id].owner_ref.entity_kind not in ["character", "clan"]): return Contract.fail("赴试款项没有实际处分权或来自无关公账")
	if stall.get("status") != "available" or not Presence.present(state, seller, school.location_id) or not accounts.can_operate(state, food.stock_account_id, seller): return Contract.fail("行粮供应人未在交割地或已不能供粮")
	var units := int(rule.food_lots) * int(food.lot_units)
	var food_cost := int(rule.food_lots) * int(food.price)
	for id in [quote.account_id, student + "_cash", student + "_rations", food.stock_account_id, food.payee_account_id]:
		if accounts.location(state, id) != school.location_id: return Contract.fail("赴试款粮尚未在同一出发地点")
	if accounts.available(state, quote.account_id, reservation) < int(quote.amount) or accounts.available(state, food.stock_account_id) < units: return Contract.fail("实际旅费或行粮不足，不得凭空发遣")
	if accounts.balance(state, student + "_cash") > Contract.MAX_AMOUNT - int(rule.allowance) or accounts.balance(state, student + "_rations") > Contract.MAX_AMOUNT - units or accounts.balance(state, food.payee_account_id) > Contract.MAX_AMOUNT - food_cost: return Contract.fail("赴试款粮库存越界")
	var refs: Array = [execution + ":allowance", execution + ":purchase", execution + ":food"]
	for transfer in [{"actor_id": principal, "execution_id": refs[0], "source_account_id": quote.account_id, "destination_account_id": student + "_cash", "amount": int(rule.allowance), "reservation_id": reservation}, {"actor_id": principal, "execution_id": refs[1], "source_account_id": quote.account_id, "destination_account_id": food.payee_account_id, "amount": food_cost, "reservation_id": reservation}, {"actor_id": seller, "execution_id": refs[2], "source_account_id": food.stock_account_id, "destination_account_id": student + "_rations", "amount": units}]:
		transfer["reason_ref"] = params.journey_id
		var paid := accounts.apply(state, "transfer", transfer)
		if not paid.ok: return paid
	var row := {"contract_id": params.journey_id, "contract_kind": "school_exam_journey", "school_id": school.asset_id, "customer_id": principal, "supplier_id": student, "recommendation_ref": admitted.contract_id, "course_ref": admitted.course_id, "rule": rule.duplicate(true), "food_offer": food.duplicate(true), "funding_account_id": quote.account_id, "seller_id": seller, "amount": int(quote.amount), "food_units": units, "journal_refs": refs, "departure_receipt": execution, "created_day": int(state.current_day), "last_work_day": int(state.current_day), "work_days": 0, "work_log": [], "legs": path.legs, "leg_index": 0, "leg_quarters": 0, "status": "en_route", "blocked_reason": "已备款粮，等待实际出发日。", "consent": true}
	state.economic_contracts[params.journey_id] = row
	_move(state, student, _transit_location(student))
	return {"ok": true, "result_ref": params.journey_id, "journal_refs": refs, "visible_summary": "已交付%s旅费 %d、行粮 %d，安排依实际道路赴行在；须等真实行程及回报，不代表已经到场或录取。" % [state.character_states[student].name, int(rule.allowance), units]}

static func _transit_location(person: String) -> String:
	return "exam-travel:" + person

static func _move(state, person: String, location: String) -> void:
	state.character_states[person].location_id = location
	state.depot_states["personal_" + person].location_node_id = location

static func settle_daily(state) -> Dictionary:
	for row in state.economic_contracts.values():
		if row.get("contract_kind") != "school_exam_journey" or row.status != "en_route" or int(row.last_work_day) >= int(state.current_day): continue
		var person: Dictionary = state.character_states[row.supplier_id]
		if person.get("status") != "alive" or not Presence.present(state, row.supplier_id, _transit_location(row.supplier_id)) or Workload.occupied_today(state, row.supplier_id, row.contract_id, row.customer_id, "exam_travel"):
			row.blocked_reason = "本人尚不能继续行程，保留已交付款粮和实际路程。"
			continue
		var food: int = Accounts.new().available(state, row.supplier_id + "_rations")
		if food <= 0:
			row.blocked_reason = "随行口粮不足，停留途中等待实际补给。"
			continue
		var leg: Dictionary = row.legs[int(row.leg_index)]
		var road: Dictionary = state.transit_corridors.get(leg.corridor_id, {})
		if road.get("from_node_id") not in [leg.from_node_id, leg.to_node_id] or road.get("to_node_id") not in [leg.from_node_id, leg.to_node_id] or road.get("from_node_id") == road.get("to_node_id"):
			row.blocked_reason = "实际道路来源已变化，等待核对行程。"
			continue
		var passage := Logistics.new().is_corridor_passable(state, leg.corridor_id, row.rule.faction_id)
		if not passage.is_passable:
			row.blocked_reason = "途中道路受阻：" + str(passage.reason)
			continue
		var quarters: int = mini(int(passage.get("speed_quarters", 4)), int(leg.base_days) * 4 - int(row.leg_quarters))
		Workload.record_work(state, row)
		row.work_log[-1].merge({"leg_index": int(row.leg_index), "corridor_id": leg.corridor_id, "quarters": quarters, "ration_balance_before": food})
		row.leg_quarters += quarters
		row.blocked_reason = ""
		if int(row.leg_quarters) == int(leg.base_days) * 4:
			row.leg_index += 1
			row.leg_quarters = 0
		if int(row.leg_index) == row.legs.size():
			row.status = "arrived"
			row["arrived_day"] = int(state.current_day)
			row["report_due_day"] = int(state.current_day) + int(row.rule.report_days)
			_move(state, row.supplier_id, row.rule.destination_id)
	return {"ok": true}

static func project(state, school: Dictionary) -> Dictionary:
	var result := {"exam_journeys": [], "exam_travel_candidates": []}
	if not school.has("exam_journey_rule"): return result
	var path := itinerary(state, school)
	result["exam_travel_estimate"] = int(path.get("base_days", -1))
	var food_offer: Dictionary = state.management_assets.get(school.exam_journey_rule.stall_id, {}).get("food_offer", {})
	result["exam_travel_cost"] = int(school.exam_journey_rule.allowance) + int(school.exam_journey_rule.food_lots) * int(food_offer.get("price", 0))
	for row in journeys(state, school.asset_id):
		var visible := {"contract_id": row.contract_id, "student_id": row.supplier_id, "created_day": row.created_day, "amount": row.amount, "food_units": row.food_units, "can_receive_report": row.status == "arrived" and int(state.current_day) >= int(row.report_due_day), "reported": row.status == "reported", "public_status": "已交付行装并发遣，尚待本人回报；预计行程不等于实际抵达。"}
		if visible.can_receive_report: visible.public_status = "本人到场回报已送到，等待核收。"
		if visible.reported:
			visible.public_status = "已核收到场回报；第 %d 日抵达，报名和考试仍须另办。" % int(row.arrived_day)
			visible["arrived_day"] = row.arrived_day
		result.exam_journeys.append(visible)
	for offer in school.student_offers:
		if not offer.get("travel_willing", false) or recommendation(state, school.asset_id, offer.character_id).is_empty() or not Presence.present(state, offer.character_id, school.location_id): continue
		result.exam_travel_candidates.append({"student_id": offer.character_id, "proposed_journey_id": "exam-journey:%s:%s:%d" % [school.asset_id, offer.character_id, journeys(state, school.asset_id).size() + 1]})
	return result

static func validate(raw: Dictionary) -> Dictionary:
	var contracts: Dictionary = raw.get("economic_contracts", {})
	for school in raw.get("management_assets", {}).values():
		if school.get("asset_kind") != "school" or not school.has("exam_journey_rule"): continue
		var rule: Variant = school.exam_journey_rule
		if not rule is Dictionary or not str(rule.get("source_id", "")).begins_with("scenario:") or rule.get("map_source") != SOURCE or not rule.get("corridor_ids") is Array or rule.corridor_ids.is_empty() or not raw.local_node_state.has(rule.get("destination_id")) or not rule.get("content_basis") is String or not rule.get("faction_id") is String or rule.faction_id.is_empty(): return Contract.fail("赴试行程缺少实际来源或目的地")
		for key in ["allowance", "food_lots", "report_days"]:
			if not Contract.amount(rule.get(key), true): return Contract.fail("赴试款粮或回报日期规则无效")
	var active := {}
	for row in contracts.values():
		if row.get("contract_kind") != "school_exam_journey": continue
		var school: Dictionary = raw.management_assets.get(row.get("school_id"), {})
		var rule: Dictionary = school.get("exam_journey_rule", {})
		var admitted: Dictionary = contracts.get(row.get("recommendation_ref"), {})
		if rule.is_empty() or row.get("rule") != rule or row.get("consent") != true or row.get("status") not in ["en_route", "arrived", "reported"] or not raw.character_states.has(row.get("supplier_id")) or not raw.character_states.has(row.get("customer_id")): return Contract.fail("赴试记录缺少实际人物、同意或规则")
		for key in ["created_day", "last_work_day", "work_days", "leg_index", "leg_quarters"]:
			if not Contract.amount(row.get(key)): return Contract.fail("赴试日期或累计路程数值无效")
		if admitted.get("contract_kind") != "school_candidacy" or admitted.get("school_id") != school.asset_id or admitted.get("supplier_id") != row.supplier_id or admitted.get("status") != "admitted" or admitted.get("course_id") != row.get("course_ref") or int(admitted.get("result_day", raw.current_day + 1)) > int(row.get("created_day", -1)): return Contract.fail("赴试缺少出发前的真实荐举及学习来源")
		if not row.get("legs") is Array or row.legs.size() != rule.corridor_ids.size() or not row.get("work_log") is Array or not row.get("blocked_reason") is String: return Contract.fail("赴试缺少连续行程及实际工日")
		var cursor: String = school.location_id
		for index in row.legs.size():
			var leg: Variant = row.legs[index]
			var road: Dictionary = raw.transit_corridors.get(rule.corridor_ids[index], {})
			if not leg is Dictionary or leg.get("corridor_id") != rule.corridor_ids[index] or leg.get("from_node_id") != cursor or not Contract.amount(leg.get("base_days"), true) or leg.base_days != road.get("base_travel_days") or leg.get("from_node_id") not in [road.get("from_node_id"), road.get("to_node_id")] or leg.get("to_node_id") not in [road.get("from_node_id"), road.get("to_node_id")] or leg.from_node_id == leg.to_node_id: return Contract.fail("赴试路段与实际道路来源不符")
			cursor = leg.to_node_id
		if cursor != rule.destination_id: return Contract.fail("赴试道路未达到目的地")
		var leg_index := 0
		var quarters := 0
		for work in row.work_log:
			if not work is Dictionary or leg_index >= row.legs.size() or work.get("leg_index") != leg_index or work.get("corridor_id") != row.legs[leg_index].corridor_id or not Contract.amount(work.get("quarters"), true) or int(work.quarters) > 4 or not Contract.amount(work.get("ration_balance_before"), true): return Contract.fail("赴试逐日路程虚增或跳过路段")
			quarters += int(work.quarters)
			if quarters > int(row.legs[leg_index].base_days) * 4: return Contract.fail("赴试每日路程超过实际路段")
			if quarters == int(row.legs[leg_index].base_days) * 4: leg_index += 1; quarters = 0
			var meal: Dictionary = raw.resource_journal.get("household-meal:%s:%d" % [row.supplier_id, int(work.get("day", -1))], {})
			if meal.get("source_account_id") != row.supplier_id + "_rations" or int(meal.get("amount", 0)) < 1: return Contract.fail("实际行路日缺少随行口粮消耗")
		if row.get("leg_index") != leg_index or row.get("leg_quarters") != quarters or row.get("work_days") != row.work_log.size() or row.get("last_work_day") != (row.created_day if row.work_log.is_empty() else row.work_log[-1].day): return Contract.fail("赴试累计进度与实际工日不符")
		if (row.status == "en_route") != (leg_index < row.legs.size()): return Contract.fail("未完成实际行程便宣告到场")
		if row.status == "en_route":
			if active.has(row.supplier_id) or raw.character_states[row.supplier_id].get("location_id") != _transit_location(row.supplier_id) or raw.depot_states.get("personal_" + row.supplier_id, {}).get("location_node_id") != _transit_location(row.supplier_id): return Contract.fail("赴试人物或随行款粮重复占位")
			active[row.supplier_id] = true
		else:
			if row.work_log.is_empty() or row.get("arrived_day") != row.work_log[-1].day or row.get("report_due_day") != int(row.arrived_day) + int(rule.report_days): return Contract.fail("到场或回报缺少实际日期")
		if row.status == "reported":
			var receipt: Dictionary = raw.action_receipts.get(row.get("report_receipt"), {})
			if not receipt.get("effect_refs", []).has(row.contract_id) or receipt.get("day") != row.get("reported_day") or int(row.reported_day) < int(row.report_due_day): return Contract.fail("到场回报缺少真实收讫回执或早于传递日期")
		var food: Variant = row.get("food_offer")
		var source: Dictionary = raw.resource_accounts.get(row.get("funding_account_id"), {})
		if source.get("unit_id") != "cash_unit" or (row.funding_account_id != school.account_id and source.get("owner_ref", {}).get("entity_kind") not in ["character", "clan"]): return Contract.fail("赴试引用无关公账或无效款源")
		var stall: Dictionary = raw.management_assets.get(rule.stall_id, {})
		if not food is Dictionary or food.get("stock_account_id") != stall.get("food_offer", {}).get("stock_account_id") or food.get("payee_account_id") != stall.get("food_offer", {}).get("payee_account_id") or row.get("seller_id") != stall.get("owner_ref", {}).get("entity_id") or not Contract.amount(food.get("price"), true) or not Contract.amount(food.get("lot_units"), true): return Contract.fail("赴试行粮缺少实际卖方和报价")
		if row.get("food_units") != int(rule.food_lots) * int(food.lot_units) or row.get("amount") != int(rule.allowance) + int(rule.food_lots) * int(food.price) or not row.get("journal_refs") is Array or row.journal_refs.size() != 3: return Contract.fail("赴试款粮报价或交割凭据无效")
		var sources: Array = [row.get("funding_account_id"), row.get("funding_account_id"), food.stock_account_id]
		var destinations: Array = [row.supplier_id + "_cash", food.payee_account_id, row.supplier_id + "_rations"]
		var amounts: Array = [int(rule.allowance), int(rule.food_lots) * int(food.price), int(row.food_units)]
		for index in 3:
			var entry: Dictionary = raw.resource_journal.get(row.journal_refs[index], {})
			if entry.get("source_account_id") != sources[index] or entry.get("destination_account_id") != destinations[index] or entry.get("amount") != amounts[index] or entry.get("entry_kind") != "transfer" or entry.get("reason_ref") != row.contract_id or entry.get("day") != row.created_day or entry.get("actor_id") != (row.seller_id if index == 2 else row.customer_id) or entry.get("unit_id") != ("ration_unit" if index == 2 else "cash_unit"): return Contract.fail("赴试款粮并未实际交付")
		var departure: Dictionary = raw.action_receipts.get(row.get("departure_receipt"), {})
		if not departure.get("effect_refs", []).has(row.contract_id) or departure.get("journal_refs") != row.journal_refs or departure.get("day") != row.created_day: return Contract.fail("赴试发遣没有共同动作回执")
	return {"ok": true}
