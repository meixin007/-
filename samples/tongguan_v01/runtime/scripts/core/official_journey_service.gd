extends RefCounted
const Rules = preload("res://scripts/core/management_state_contract.gd")
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Grain = preload("res://scripts/core/regional_grain_service.gd")
const Presence = preload("res://scripts/core/production_service.gd")
const Workload = preload("res://scripts/core/character_workload_service.gd")
const KINDS := ["send_official_envoy", "receive_official_report"]
const SOURCE := "scenario:official_journeys_756"

static func initialize(state, data: Dictionary) -> Dictionary:
	var rule: Dictionary = data.get("management", {}).get("official_journeys", {})
	if rule.is_empty(): return {"ok": true}
	if state.flags.has("official_journey_rules"): return Rules.fail("差遣来源已经登记")
	state.flags["official_journey_rules"] = rule.duplicate(true)
	return {"ok": true}

static func offer(state, person: String) -> Dictionary:
	for row in state.flags.get("official_journey_rules", {}).get("offers", []):
		if row.person_id == person: return row
	return {}

static func available(state, person: String, principal: String) -> Dictionary:
	var terms := offer(state, person)
	var origin: String = str(state.character_states.get(principal, {}).get("location_id", ""))
	if not terms.get("willing", false) or int(state.character_states.get(person, {}).get("relationships", {}).get(principal, 0)) < int(terms.get("minimum_relation", 0)): return Rules.fail("本人尚不愿接受这项差遣")
	if not Presence.present(state, person, origin): return Rules.fail("本人未在实际出发地或已不能办理")
	if state.office_state.values().any(func(row): return row.get("holder_id") == person and row.get("status") == "appointed"): return Rules.fail("本人仍在任职，须先完成原职离任交接")
	if not Workload.can_schedule(state, person, "official_travel", principal): return Rules.fail("本人正在履行另一项行程或职责")
	if Accounts.new().location(state, person + "_rations") != origin or Accounts.new().available(state, person + "_rations") < 1: return Rules.fail("本人没有在出发地的实际随行口粮")
	return {"ok": true}

static func cost_for(state, kind: String, params: Dictionary) -> Dictionary:
	if not params.get("journey_id") is String or str(params.journey_id).is_empty() or not Grain.managed(state, str(params.get("target_depot_id", ""))) or offer(state, str(params.get("person_id", ""))).is_empty(): return Rules.fail("派员需要实际人物、目标仓廪及独立行程")
	if kind == "receive_official_report":
		var row: Dictionary = state.economic_contracts.get(params.journey_id, {})
		if row.get("contract_kind") != "official_journey": return {"ok": false, "code": "asset_not_ready", "error": "尚无对应实际派员行程"}
		if row.get("supplier_id") != params.person_id or row.get("target_depot_id") != params.target_depot_id: return Rules.fail("回报不能替换原差遣人物或目标")
		return {"ok": true, "account_id": "", "amount": 0}
	var amount: Variant = state.flags.get("official_journey_rules", {}).get("allowance")
	if not Rules.amount(amount, true) or state.resource_accounts.get(params.get("funding_account_id"), {}).get("unit_id") != "cash_unit": return Rules.fail("差遣旅费缺少实际来源")
	return {"ok": true, "account_id": params.funding_account_id, "amount": int(amount)}

static func transit(person: String) -> String:
	return "official-travel:" + person

static func move(state, person: String, location: String) -> void:
	state.character_states[person].location_id = location
	state.depot_states["personal_" + person].location_node_id = location

static func order_record(row: Dictionary) -> Dictionary:
	var result := {}
	for key in ["contract_id", "supplier_id", "customer_id", "target_depot_id", "origin_id", "destination_id", "legs", "report_legs", "created_day", "amount", "funding_account_id", "consent"]: result[key] = row.get(key)
	return result.duplicate(true)

static func apply(state, kind: String, params: Dictionary, principal: String, execution: String, reservation: String) -> Dictionary:
	var cost := cost_for(state, kind, params)
	if not cost.ok: return cost
	if kind == "receive_official_report":
		var row: Dictionary = state.economic_contracts[params.journey_id]
		if row.customer_id != principal: return Rules.fail("不能领取另一人的差遣回报")
		var notice := latest(row)
		if notice.is_empty() or not notice.accepted: return {"ok": false, "code": "awaiting_delivery", "error": "尚待实际查验回报。" if notice.is_empty() else notice_text(notice)}
		if row.status == "reported": return Rules.fail("差遣回报已经核收")
		row.status = "reported"
		row["report_receipt"] = execution
		row["reported_day"] = int(state.current_day)
		return {"ok": true, "result_ref": row.contract_id, "visible_summary": notice_text(notice)}
	var person: String = params.person_id
	var ready := available(state, person, principal)
	if not ready.ok: return ready
	if state.economic_contracts.has(params.journey_id) or not Grain.authority(state, params.target_depot_id, principal): return Rules.fail("差遣标识已使用或本人无目标仓廪的实际经办权")
	var origin: String = str(state.character_states[principal].location_id)
	var destination: String = str(state.depot_states[params.target_depot_id].location_node_id)
	var path := Grain.path(state, origin, destination)
	var report := Grain.path(state, destination, origin)
	if not path.ok or not report.ok or path.get("legs", []).is_empty(): return Rules.fail("跨区差遣缺少实际连通道路和回报路线")
	if not preload("res://scripts/core/military_grain_service.gd").at_node(state, params.target_depot_id, destination): return Rules.fail("接收对象正在移动，尚无确定交接地点")
	var accounts := Accounts.new()
	if not accounts.can_operate(state, cost.account_id, principal) or accounts.location(state, cost.account_id) != origin or accounts.location(state, person + "_cash") != origin: return Rules.fail("旅费没有同地款源或实际处分权")
	var paid := accounts.apply(state, "transfer", {"actor_id": principal, "execution_id": execution + ":allowance", "source_account_id": cost.account_id, "destination_account_id": person + "_cash", "amount": cost.amount, "reservation_id": reservation, "reason_ref": params.journey_id})
	if not paid.ok: return paid
	var row := {"contract_id": params.journey_id, "contract_kind": "official_journey", "source_id": SOURCE, "supplier_id": person, "customer_id": principal, "target_depot_id": params.target_depot_id, "origin_id": origin, "destination_id": destination, "legs": path.legs, "report_legs": report.legs, "created_day": int(state.current_day), "last_work_day": int(state.current_day), "work_days": 0, "work_log": [], "leg_index": 0, "leg_quarters": 0, "status": "en_route", "amount": cost.amount, "funding_account_id": cost.account_id, "journal_refs": [paid.result_ref], "departure_receipt": execution, "consent": offer(state, person).duplicate(true), "notices": [], "blocked_reason": ""}
	state.economic_contracts[params.journey_id] = row
	move(state, person, transit(person))
	return {"ok": true, "result_ref": row.contract_id, "journal_refs": row.journal_refs, "mission_order": order_record(row), "visible_summary": "已交付实际旅费并派出%s；须等本人行路、地方接纳和查验回报。" % state.character_states[person].name}

static func notice_text(notice: Dictionary) -> String:
	return "第 %d 日观察 / 第 %d 日收到回报：%s" % [int(notice.observed_day), int(notice.delivered_day), notice.message]

static func latest(row: Dictionary) -> Dictionary:
	var delivered: Array = row.notices.filter(func(notice): return notice.has("delivered_day"))
	return {} if delivered.is_empty() else delivered[-1].duplicate(true)

static func record_notice(state, row: Dictionary, accepted: bool, message: String) -> void:
	if row.notices.any(func(notice): return notice.accepted == accepted and notice.message == message): return
	var notice := {"observed_day": int(state.current_day), "accepted": accepted, "message": message, "leg_index": 0, "last_day": int(state.current_day), "travel_log": []}
	if accepted: notice["inspection"] = row.inspection.duplicate(true)
	row.notices.append(notice)

static func advance_notices(state, row: Dictionary) -> void:
	for notice in row.notices:
		if notice.has("delivered_day") or int(notice.last_day) >= int(state.current_day): continue
		notice.last_day = int(state.current_day)
		if int(notice.leg_index) < row.report_legs.size():
			if not Grain.passage(state, row.report_legs[int(notice.leg_index)]).is_passable: continue
			notice.travel_log.append({"day": int(state.current_day), "index": int(notice.leg_index)})
			notice.leg_index += 1
			if int(notice.leg_index) < row.report_legs.size(): continue
		notice["delivered_day"] = int(state.current_day)
		var visible := latest(row)
		for task in state.active_tasks:
			if task.get("task_kind") != "management" or task.get("principal_id") != row.customer_id or task.get("status") in ["completed", "cancelled", "blocked"]: continue
			if task.get("steps", []).any(func(step): return step.get("action_kind") == "receive_official_report" and step.get("status") != "completed" and step.get("parameters", {}).get("journey_id") == row.contract_id): task.visible_feedback = [notice_text(visible)]

static func settle_daily(state) -> Dictionary:
	for row in state.economic_contracts.values():
		if row.get("contract_kind") != "official_journey": continue
		advance_notices(state, row)
		if row.status not in ["en_route", "awaiting_reception"] or int(row.last_work_day) >= int(state.current_day): continue
		var person: String = row.supplier_id
		var location: String = transit(person) if row.status == "en_route" else str(row.destination_id)
		if not Presence.present(state, person, location) or Workload.occupied_today(state, person, row.contract_id, row.customer_id, "official_travel"):
			row.blocked_reason = "本人目前不能继续履职，保留已经发生的行程和旅费。"
			continue
		var food: int = Accounts.new().available(state, person + "_rations")
		if food < 1: row.blocked_reason = "实际随行口粮不足，等待补给。"; continue
		if row.status == "en_route":
			var leg: Dictionary = row.legs[int(row.leg_index)]
			var passage := Grain.passage(state, leg)
			if not passage.is_passable: row.blocked_reason = str(passage.reason); continue
			var quarters: int = mini(int(passage.get("speed_quarters", 4)), int(leg.base_days) * 4 - int(row.leg_quarters))
			Workload.record_work(state, row)
			row.work_log[-1].merge({"phase": "travel", "leg_index": int(row.leg_index), "quarters": quarters, "ration_balance_before": food})
			row.leg_quarters += quarters
			if int(row.leg_quarters) == int(leg.base_days) * 4: row.leg_index += 1; row.leg_quarters = 0
			if int(row.leg_index) == row.legs.size():
				row.status = "awaiting_reception"
				row["arrived_day"] = int(state.current_day)
				move(state, person, row.destination_id)
			continue
		if not Grain.authority(state, row.target_depot_id, row.customer_id) or not preload("res://scripts/core/military_grain_service.gd").at_node(state, row.target_depot_id, row.destination_id):
			row.blocked_reason = "本人已经到场，地方实控或接收地点尚不认可本次查验。"
			record_notice(state, row, false, row.blocked_reason)
			continue
		Workload.record_work(state, row)
		row.work_log[-1].merge({"phase": "inspection", "ration_balance_before": food})
		row["inspection"] = {"day": int(state.current_day), "depot_id": row.target_depot_id, "location_id": row.destination_id, "grain": int(state.depot_states[row.target_depot_id].stock.grain), "receiver_id": str(state.control_relations.get("ctrl|depot|" + str(row.target_depot_id), {}).get("controller_id", state.depot_states[row.target_depot_id].owner_character_id))}
		row.status = "reporting"
		row.blocked_reason = ""
		record_notice(state, row, true, "本人已获地方接纳并完成核仓；当日实粮 %d，非今日即时库存。" % int(row.inspection.grain))
	return {"ok": true}

static func project(state, viewer: String) -> Dictionary:
	var result := {"candidates": [], "journeys": []}
	for consent in state.flags.get("official_journey_rules", {}).get("offers", []):
		if Grain.known_depots(state, viewer).is_empty(): break
		if not state.character_states.has(consent.person_id): continue
		var ready := available(state, consent.person_id, viewer)
		result.candidates.append({"person_id": consent.person_id, "name": state.character_states[consent.person_id].name, "available": ready.ok, "reason": ready.get("error", ""), "allowance": int(state.flags.official_journey_rules.allowance)})
	for row in state.economic_contracts.values():
		if row.get("contract_kind") != "official_journey" or row.customer_id != viewer: continue
		var notice := latest(row)
		result.journeys.append({"journey_id": row.contract_id, "person_id": row.supplier_id, "target_depot_id": row.target_depot_id, "status_text": "已经派出，等待实际行程与回报。" if notice.is_empty() else notice_text(notice), "can_receive": not notice.is_empty() and notice.accepted and row.status != "reported", "reported": row.status == "reported"})
	return result

static func validate(raw: Dictionary) -> Dictionary:
	var rule: Variant = raw.get("flags", {}).get("official_journey_rules", {})
	if not rule is Dictionary: return Rules.fail("差遣来源类型无效")
	if not rule.is_empty() and (rule.get("source_id") != SOURCE or not Rules.amount(rule.get("allowance"), true) or not rule.get("offers") is Array): return Rules.fail("差遣规则缺少来源、旅费或意愿")
	var people := {}
	for terms in rule.get("offers", []):
		if not terms is Dictionary or not raw.character_states.has(terms.get("person_id")) or people.has(terms.person_id) or not terms.get("willing") is bool or not str(terms.get("source_id", "")).begins_with("scenario:"): return Rules.fail("差遣意愿缺少实际唯一人物及来源")
		people[terms.person_id] = terms
	var active := {}
	for row in raw.get("economic_contracts", {}).values():
		if row.get("contract_kind") != "official_journey": continue
		if rule.is_empty() or row.get("source_id") != SOURCE or not people.has(row.get("supplier_id")) or not raw.character_states.has(row.get("customer_id")) or not raw.depot_states.has(row.get("target_depot_id")) or row.get("status") not in ["en_route", "awaiting_reception", "reporting", "reported"]: return Rules.fail("实际派员缺少来源、人物或目标")
		if not row.get("consent") is Dictionary or row.consent.get("person_id") != row.supplier_id or row.consent.get("source_id") != people[row.supplier_id].source_id or row.consent.get("willing") != true: return Rules.fail("差遣缺少本人出发时的同意")
		for key in ["created_day", "last_work_day", "work_days", "leg_index", "leg_quarters", "amount"]:
			if not Rules.amount(row.get(key)): return Rules.fail("差遣数量、日期或行程进度无效")
		if int(row.created_day) > int(raw.current_day) or row.amount != rule.allowance or not row.get("work_log") is Array or not row.get("notices") is Array: return Rules.fail("差遣旅费或实际履历无效")
		if not row.get("origin_id") is String or not row.get("destination_id") is String or not Grain.valid_path(row.get("legs"), row.origin_id, row.destination_id) or row.legs.is_empty() or not Grain.valid_path(row.get("report_legs"), row.destination_id, row.origin_id): return Rules.fail("差遣没有连续的实际行程和回报路线")
		var departure: Dictionary = raw.action_receipts.get(row.get("departure_receipt"), {})
		if departure.get("mission_order") != order_record(row) or not departure.get("effect_refs", []).has(row.contract_id) or departure.get("day") != row.created_day or departure.get("journal_refs") != row.get("journal_refs"): return Rules.fail("差遣缺少共同签发的原始指令")
		if not row.get("journal_refs") is Array or row.journal_refs.size() != 1: return Rules.fail("差遣缺少实际旅费交割")
		var paid: Dictionary = raw.resource_journal.get(row.journal_refs[0], {})
		if paid.get("source_account_id") != row.get("funding_account_id") or paid.get("destination_account_id") != str(row.supplier_id) + "_cash" or paid.get("amount") != row.amount or paid.get("day") != row.created_day or paid.get("actor_id") != row.customer_id or paid.get("entry_kind") != "transfer" or paid.get("reason_ref") != row.contract_id: return Rules.fail("差遣旅费没有从实际授权款源交给本人")
		var leg := 0
		var quarters := 0
		var last_day: int = int(row.created_day)
		var arrival := -1
		var inspected := -1
		for work in row.work_log:
			if not work is Dictionary or not Rules.amount(work.get("day"), true) or int(work.day) <= last_day or int(work.day) > int(raw.current_day) or not Rules.amount(work.get("ration_balance_before"), true): return Rules.fail("差遣实际工日重复或没有口粮")
			last_day = int(work.day)
			if work.get("phase") == "travel":
				if leg >= row.legs.size() or work.get("leg_index") != leg or not Rules.amount(work.get("quarters"), true) or int(work.quarters) > 4 or inspected >= 0: return Rules.fail("差遣行程虚增或顺序错误")
				quarters += int(work.quarters)
				if quarters > int(row.legs[leg].base_days) * 4: return Rules.fail("差遣行程超过实际路段")
				if quarters == int(row.legs[leg].base_days) * 4: leg += 1; quarters = 0
				if leg == row.legs.size(): arrival = last_day
			elif work.get("phase") == "inspection":
				if arrival < 0 or inspected >= 0: return Rules.fail("本人未到场或重复核仓")
				inspected = last_day
			else: return Rules.fail("差遣履历包含未知工序")
			var meal: Dictionary = raw.resource_journal.get("household-meal:%s:%d" % [row.supplier_id, last_day], {})
			if meal.get("source_account_id") != str(row.supplier_id) + "_rations" or int(meal.get("amount", 0)) < 1: return Rules.fail("差遣实际工日缺少本人进食凭据")
		if row.leg_index != leg or row.leg_quarters != quarters or row.work_days != row.work_log.size() or row.last_work_day != last_day or (row.status == "en_route") != (arrival < 0): return Rules.fail("差遣阶段与实际履历不符")
		if arrival >= 0 and row.get("arrived_day") != arrival: return Rules.fail("差遣到场日期不符")
		if row.status in ["en_route", "awaiting_reception"]:
			var place: String = transit(row.supplier_id) if row.status == "en_route" else str(row.destination_id)
			if active.has(row.supplier_id) or raw.character_states[row.supplier_id].get("location_id") != place or raw.depot_states.get("personal_" + str(row.supplier_id), {}).get("location_node_id") != place: return Rules.fail("派出人物及随身钱粮重复占位或丢失")
			active[row.supplier_id] = true
		if (row.status in ["reporting", "reported"]) != (inspected >= 0): return Rules.fail("没有实际核仓就生成完成回报")
		if inspected >= 0:
			var inspection: Variant = row.get("inspection")
			if not inspection is Dictionary or inspection.get("day") != inspected or inspection.get("depot_id") != row.target_depot_id or inspection.get("location_id") != row.destination_id or not Rules.amount(inspection.get("grain")) or not raw.character_states.has(inspection.get("receiver_id")): return Rules.fail("核仓缺少实际地点、日期、接收方和观测")
		var accepted_count := 0
		for notice in row.notices:
			if not notice is Dictionary or not notice.get("accepted") is bool or not notice.get("message") is String or not Rules.amount(notice.get("observed_day"), true) or int(notice.observed_day) <= arrival or int(notice.observed_day) > int(raw.current_day) or not notice.get("travel_log") is Array: return Rules.fail("差遣消息缺少真实到场后的观察")
			if notice.accepted:
				accepted_count += 1
				if inspected < 0 or notice.get("inspection") != row.inspection or notice.observed_day != inspected: return Rules.fail("完成回报没有对应本人核仓")
			var index := 0
			var report_day: int = int(notice.observed_day)
			for travel in notice.travel_log:
				if not travel is Dictionary or not Rules.amount(travel.get("day"), true) or int(travel.day) <= report_day or int(travel.day) > int(raw.current_day) or travel.get("index") != index or index >= row.report_legs.size(): return Rules.fail("差遣回报未按实际日期逐段送达")
				index += 1
				report_day = int(travel.day)
			if notice.get("leg_index") != index or not Rules.amount(notice.get("last_day")) or int(notice.last_day) < report_day or int(notice.last_day) > int(raw.current_day): return Rules.fail("差遣消息进度无效")
			if notice.has("delivered_day") and (index != row.report_legs.size() or notice.delivered_day != report_day): return Rules.fail("差遣消息没有实际送达便提前获知")
		if accepted_count != (1 if inspected >= 0 else 0): return Rules.fail("核仓与完成回报数量不符")
		if row.status == "reported":
			var notice := latest(row)
			var receipt: Dictionary = raw.action_receipts.get(row.get("report_receipt"), {})
			if not notice.get("accepted", false) or not receipt.get("effect_refs", []).has(row.contract_id) or receipt.get("day") != row.get("reported_day") or int(row.reported_day) < int(notice.delivered_day): return Rules.fail("差遣回报缺少真实核收凭据")
	return {"ok": true}
