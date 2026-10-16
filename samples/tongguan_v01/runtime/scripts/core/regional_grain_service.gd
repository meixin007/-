extends RefCounted
const Rules = preload("res://scripts/core/management_state_contract.gd")
const Logistics = preload("res://scripts/core/logistics_service.gd")
const Reports = preload("res://scripts/core/grain_transport_reports.gd")
const KINDS := ["commission_grain_transport", "await_grain_report"]

static func initialize(state, data: Dictionary) -> Dictionary:
	var rule: Dictionary = data.get("management", {}).get("regional_grain", {})
	if rule.is_empty(): return {"ok": true}
	if state.flags.has("regional_grain_rules"): return Rules.fail("地方粮仓来源已经登记")
	state.flags["regional_grain_rules"] = rule.duplicate(true)
	for source in rule.depots:
		if state.depot_states.has(source.depot_id): return Rules.fail("地方粮仓初始来源重复")
		var depot: Dictionary = source.duplicate(true)
		depot["source_id"] = rule.source_id
		depot["owner_organization_id"] = "tang_court"
		depot["authority_office_id"] = "imperial_court"
		depot["stock"] = {"grain": int(source.initial_grain)}
		state.depot_states[source.depot_id] = depot
	return {"ok": true}

static func managed(state, id: String) -> bool:
	return state.depot_states.get(id, {}).get("source_id") == "scenario:regional_grain_756"

static func authority(state, id: String, actor: String) -> bool:
	if not managed(state, id) or not available_person(state, actor): return false
	var depot: Dictionary = state.depot_states[id]
	var control: Dictionary = state.control_relations.get("ctrl|depot|" + id, {})
	var holder: String = str(control.get("controller_id", depot.owner_character_id))
	if not available_person(state, holder): return false
	if actor == holder: return true
	if control.get("control_type", "de_jure") in ["usurped", "disputed"]: return false
	if depot.has("military_force_id"):
		var force: Dictionary = state.military_forces.get(depot.military_force_id, {})
		if force.get("faction_id") != "tang_court" or force.get("commander_id") != holder or int(state.obedience_relations.get("obed|%s|%s|military" % [holder, actor], {}).get("strength", 80)) < 40: return false
	var office: Dictionary = state.office_state.get(depot.authority_office_id, {})
	return office.get("status") == "appointed" and office.get("holder_id") == actor and int(state.obedience_relations.get("obed|%s|%s|all" % [holder, actor], {}).get("strength", 80)) >= 40

static func available_person(state, id: String) -> bool:
	return state.character_states.has(id) and state.character_states[id].get("status") not in ["dead", "deceased", "executed", "missing", "imprisoned", "departed", "exiled", "unreachable", "defected", "irreconcilable"]

static func path(state, origin: String, destination: String) -> Dictionary:
	var route := Logistics.new().find_supply_route(state, origin, destination, "tang_court")
	if not route.get("ok", false): return Rules.fail("现有实际道路不能送达命令或粮队")
	var cursor := origin
	var legs: Array = []
	for id in route.corridor_ids:
		var road: Dictionary = state.transit_corridors[id]
		if not Rules.amount(road.get("base_travel_days"), true): return Rules.fail("实际道路缺少行程依据")
		var next: String = road.to_node_id if road.from_node_id == cursor else road.from_node_id
		legs.append({"corridor_id": id, "from_node_id": cursor, "to_node_id": next, "base_days": int(road.base_travel_days)})
		cursor = next
	return {"ok": true, "legs": legs}

static func cost_for(state, kind: String, params: Dictionary) -> Dictionary:
	if kind == "await_grain_report":
		var row := find_order(state, str(params.get("order_id", "")))
		if row.is_empty(): return {"ok": false, "code": "asset_not_ready", "error": "尚无该笔实际调粮记录"}
		if row.get("from_depot_id") != params.get("source_depot_id") or row.get("target_id") != params.get("target_depot_id"): return Rules.fail("回报跟进不能换成另一笔调粮")
		return {"ok": true, "account_id": "", "amount": 0}
	if not managed(state, str(params.get("source_depot_id", ""))) or not managed(state, str(params.get("target_depot_id", ""))) or params.source_depot_id == params.target_depot_id or not Rules.amount(params.get("grain_amount"), true): return Rules.fail("调粮须指定两个实际地方仓廪及正整数粮额")
	return {"ok": true, "account_id": "", "amount": 0}

static func find_order(state, id: String) -> Dictionary:
	for row in state.grain_transports:
		if row.get("transport_kind") == "regional_grain" and row.get("transport_id") == id: return row
	return {}

static func apply(state, params: Dictionary, principal: String, execution: String, kind: String = "commission_grain_transport") -> Dictionary:
	var quote := cost_for(state, kind, params)
	if not quote.ok: return quote
	if kind == "await_grain_report":
		var actual := find_order(state, str(params.order_id))
		if actual.principal_id != principal: return Rules.fail("本人无权跟进另一人的调粮")
		if actual.status != "reported":
			var visible: Array = project(state, principal).filter(func(row): return row.transport_id == actual.transport_id)
			return {"ok": false, "code": "awaiting_delivery", "error": str(visible[0].status_text) + "；仍跟进原调令，不重复签发或扣粮。"}
		return {"ok": true, "result_ref": actual.transport_id, "visible_summary": "已核对实际入库回报：实收 %d、途损 %d；调粮委托完成。" % [int(actual.received_grain), int(actual.lost_grain)]}
	var order_id: String = str(params.get("order_id", "regional:" + execution))
	if order_id.is_empty() or not find_order(state, order_id).is_empty(): return Rules.fail("调粮标识缺失或已用于另一笔调令")
	if state.grain_transports.filter(func(row): return row.get("transport_kind") == "regional_grain").size() >= 128: return Rules.fail("地方粮运履历容量已满，保留原有调令，不再签发")
	for id in [params.source_depot_id, params.target_depot_id]:
		if not authority(state, id, principal): return Rules.fail("本人没有所选仓廪的实际征调或接收权")
	var source: Dictionary = state.depot_states[params.source_depot_id]
	var target: Dictionary = state.depot_states[params.target_depot_id]
	var origin: String = str(state.character_states[principal].get("location_id", ""))
	var command := path(state, origin, source.location_node_id)
	var cargo := path(state, source.location_node_id, target.location_node_id)
	var report := path(state, target.location_node_id, origin)
	var military = preload("res://scripts/core/military_grain_service.gd")
	if not military.at_node(state, params.source_depot_id, source.location_node_id) or not military.at_node(state, params.target_depot_id, target.location_node_id): return Rules.fail("随军粮正在行军，须明确驻止的实际交割地点")
	for route in [command, cargo, report]:
		if not route.ok: return route
	if int(source.stock.grain) < int(params.grain_amount): return Rules.fail("起运仓目前实粮不足")
	var row := {"transport_id": order_id, "transport_kind": "regional_grain", "source_id": state.flags.regional_grain_rules.source_id, "principal_id": principal, "origin_node_id": origin, "from_depot_id": params.source_depot_id, "target_id": params.target_depot_id, "target_type": "depot", "initial_grain": int(params.grain_amount), "current_grain": 0, "lost_grain": 0, "received_grain": 0, "command_legs": command.legs, "legs": cargo.legs, "report_legs": report.legs, "command_index": 0, "leg_index": 0, "leg_quarters": 0, "report_index": 0, "start_day": int(state.current_day), "last_advanced_day": int(state.current_day), "status": "awaiting_dispatch", "dispatch_receipt": execution, "history": [], "blocking_reason": ""}
	row["source_node_id"] = str(source.location_node_id)
	row["target_node_id"] = str(target.location_node_id)
	state.grain_transports.append(row)
	return {"ok": true, "result_ref": row.transport_id, "grain_order": order_record(row), "visible_summary": "调粮文牒已签发；须待送达后由实际管仓者出粮，接收及回报另行等待。"}

static func order_record(row: Dictionary) -> Dictionary:
	var result := {}
	for key in ["transport_id", "source_id", "principal_id", "origin_node_id", "from_depot_id", "target_id", "initial_grain", "command_legs", "legs", "report_legs", "start_day"]: result[key] = row.get(key)
	for key in ["source_node_id", "target_node_id"]: result[key] = row.get(key)
	return result.duplicate(true)

static func passage(state, leg: Dictionary) -> Dictionary:
	var road: Dictionary = state.transit_corridors.get(leg.corridor_id, {})
	if road.get("from_node_id") not in [leg.from_node_id, leg.to_node_id] or road.get("to_node_id") not in [leg.from_node_id, leg.to_node_id] or road.get("from_node_id") == road.get("to_node_id"): return {"is_passable": false, "reason": "道路端点已变化，等待核对"}
	return Logistics.new().is_corridor_passable(state, leg.corridor_id, "tang_court")

static func settle_daily(state) -> Dictionary:
	for row in state.grain_transports:
		if row.get("transport_kind") != "regional_grain": continue
		Reports.advance(state, row)
		_sync_followup_feedback(state, row)
		if row.status == "reported" or int(row.last_advanced_day) >= int(state.current_day): continue
		row.last_advanced_day = int(state.current_day)
		row.blocking_reason = ""
		if row.status == "awaiting_dispatch":
			if int(row.command_index) < row.command_legs.size():
				var permitted := passage(state, row.command_legs[int(row.command_index)])
				if not permitted.is_passable: Reports.record(state, row, str(permitted.reason)); continue
				row.history.append({"day": int(state.current_day), "event": "command", "index": int(row.command_index)})
				row.command_index += 1
				if int(row.command_index) < row.command_legs.size(): continue
			if not authority(state, row.from_depot_id, row.principal_id): Reports.record(state, row, "调令已到，但实际管仓者尚不接受征调"); continue
			if not preload("res://scripts/core/military_grain_service.gd").at_node(state, row.from_depot_id, row.source_node_id): Reports.record(state, row, "调令送达原定地点，但随军粮已随部队移动，不能出库"); continue
			var source: Dictionary = state.depot_states[row.from_depot_id]
			if int(source.stock.grain) < int(row.initial_grain): Reports.record(state, row, "命令送达时实粮不足，尚未出库"); continue
			source.stock.grain -= int(row.initial_grain)
			row.current_grain = int(row.initial_grain)
			row.status = "in_transit"
			row["dispatched_day"] = int(state.current_day)
			row.history.append({"day": int(state.current_day), "event": "dispatch", "amount": int(row.initial_grain)})
			if row.legs.is_empty():
				row.status = "awaiting_receipt"
				row["arrived_day"] = int(state.current_day)
			continue
		if row.status == "in_transit":
			var leg: Dictionary = row.legs[int(row.leg_index)]
			var permitted := passage(state, leg)
			if not permitted.is_passable: Reports.record(state, row, str(permitted.reason)); continue
			var quarters: int = mini(int(permitted.get("speed_quarters", 4)), int(leg.base_days) * 4 - int(row.leg_quarters))
			var loss: int = mini(int(row.current_grain), int(ceil(float(row.current_grain) * int(state.flags.regional_grain_rules.loss_per_mille) / 1000.0)))
			row.current_grain -= loss
			row.lost_grain += loss
			row.history.append({"day": int(state.current_day), "event": "travel", "index": int(row.leg_index), "quarters": quarters, "loss": loss})
			row.leg_quarters += quarters
			if int(row.leg_quarters) == int(leg.base_days) * 4: row.leg_index += 1; row.leg_quarters = 0
			if int(row.leg_index) < row.legs.size(): continue
			row.status = "awaiting_receipt"
			row["arrived_day"] = int(state.current_day)
		if row.status == "awaiting_receipt":
			if not preload("res://scripts/core/military_grain_service.gd").at_node(state, row.target_id, row.target_node_id): Reports.record(state, row, "粮队抵达原定交割点，但接收军队不在此地，粮食仍在队中"); continue
			if not authority(state, row.target_id, row.principal_id): Reports.record(state, row, "粮队已到，但接收仓实控或服从关系不接受本次调拨"); continue
			var target: Dictionary = state.depot_states[row.target_id]
			if int(target.stock.grain) > int(target.capacity) - int(row.current_grain): Reports.record(state, row, "接收仓实际容量不足，粮食仍在队中"); continue
			target.stock.grain += int(row.current_grain)
			row.received_grain = int(row.current_grain)
			row.current_grain = 0
			row.status = "reporting"
			row["received_day"] = int(state.current_day)
			row.history.append({"day": int(state.current_day), "event": "receive", "amount": int(row.received_grain)})
			continue
		if row.status == "reporting":
			if int(row.report_index) < row.report_legs.size():
				var permitted := passage(state, row.report_legs[int(row.report_index)])
				if not permitted.is_passable: Reports.record(state, row, str(permitted.reason)); continue
				row.history.append({"day": int(state.current_day), "event": "report", "index": int(row.report_index)})
				row.report_index += 1
				if int(row.report_index) < row.report_legs.size(): continue
			row.status = "reported"
			row["reported_day"] = int(state.current_day)
			row.history.append({"day": int(state.current_day), "event": "reported"})
	preload("res://scripts/core/military_grain_service.gd").refresh_all(state)
	return {"ok": true}

static func _sync_followup_feedback(state, row: Dictionary) -> void:
	if row.status == "reported": return
	var notice := Reports.latest(row)
	if notice.is_empty() or int(notice.delivered_day) != int(state.current_day): return
	for task in state.active_tasks:
		if task.get("task_kind") != "management" or task.get("principal_id") != row.principal_id or task.get("status") in ["completed", "cancelled", "blocked"]: continue
		for step in task.steps:
			if step.action_kind != "await_grain_report" or step.status in ["completed", "delegated"] or step.parameters.get("order_id") != row.transport_id: continue
			task.visible_feedback = ["第 %d 日观察 / 第 %d 日收到回报：%s；仍跟进原调令，不重复签发或扣粮。" % [int(notice.observed_day), int(notice.delivered_day), notice.message]]
			break

static func project(state, viewer: String) -> Array:
	var rows: Array = []
	for row in state.grain_transports:
		if row.get("transport_kind") != "regional_grain" or row.principal_id != viewer: continue
		var visible := {"transport_id": row.transport_id, "source_name": state.depot_states[row.from_depot_id].name, "target_name": state.depot_states[row.target_id].name, "ordered_grain": row.initial_grain, "status_text": "文牒已发，等候实际送达与回报"}
		if row.status == "reported": visible.merge({"status_text": "已收到入库回报", "received_grain": row.received_grain, "lost_grain": row.lost_grain, "received_day": row.received_day, "reported_day": row.reported_day}, true)
		else:
			var notice := Reports.latest(row)
			if not notice.is_empty():
				visible["notice"] = notice
				visible.status_text = "第 %d 日观察 / 第 %d 日收到回报：%s" % [int(notice.observed_day), int(notice.delivered_day), notice.message]
		rows.append(visible)
	return rows

static func known_depots(state, viewer: String) -> Array:
	var result: Array = []
	for source in state.flags.get("regional_grain_rules", {}).get("depots", []):
		var id: String = str(source.depot_id)
		if not authority(state, id, viewer): continue
		var depot: Dictionary = state.depot_states[id]
		var row := {"depot_id": id, "name": depot.name, "location_id": depot.location_node_id}
		if state.character_states[viewer].get("location_id") == depot.location_node_id and preload("res://scripts/core/military_grain_service.gd").at_node(state, id, depot.location_node_id):
			row["grain"] = int(depot.stock.grain)
			if depot.has("military_force_id"):
				var force: Dictionary = state.military_forces[depot.military_force_id]
				row["daily_grain"] = preload("res://scripts/core/military_grain_service.gd").daily_need(state, force)
				row["troops"] = preload("res://scripts/core/military_grain_service.gd").troop_count(force)
				if not force.grain_meals.is_empty(): row["last_meal"] = force.grain_meals[-1].duplicate(true)
		result.append(row)
	return result

static func validate(raw: Dictionary) -> Dictionary:
	var supplied: Variant = raw.get("flags", {}).get("regional_grain_rules", {})
	if not supplied is Dictionary or not raw.get("grain_transports", []) is Array: return Rules.fail("地方粮运规则或记录类型错误")
	var rule: Dictionary = supplied
	if rule.is_empty():
		if raw.depot_states.values().any(func(depot): return depot.get("source_id") == "scenario:regional_grain_756") or raw.get("grain_transports", []).any(func(row): return row is Dictionary and row.get("transport_kind") == "regional_grain"): return Rules.fail("地方仓粮丢失初始来源")
		return {"ok": true}
	if rule.get("source_id") != "scenario:regional_grain_756" or rule.get("message_days_per_leg") != 1 or not Rules.amount(rule.get("loss_per_mille")) or int(rule.loss_per_mille) > 1000 or not rule.get("depots") is Array: return Rules.fail("地方粮运来源无效")
	var balances := {}
	for source in rule.depots:
		if not source is Dictionary or not source.get("depot_id") is String or balances.has(source.depot_id): return Rules.fail("地方粮仓初始来源重复或无效")
		var depot: Dictionary = raw.depot_states.get(source.get("depot_id"), {})
		var expected_node: Variant = raw.get("military_forces", {}).get(source.get("military_force_id", ""), {}).get("current_node_id") if source.has("military_force_id") else source.get("location_node_id")
		if depot.get("source_id") != rule.source_id or depot.get("name") != source.get("name") or depot.get("military_force_id", "") != source.get("military_force_id", "") or depot.get("location_node_id") != expected_node or not raw.character_states.has(depot.get("owner_character_id")) or depot.get("authority_office_id") != "imperial_court" or not Rules.amount(source.get("initial_grain")) or not Rules.amount(depot.get("stock", {}).get("grain")) or not Rules.amount(depot.get("capacity"), true): return Rules.fail("地方粮仓缺少实际地点、人物或初始来源")
		balances[source.depot_id] = int(source.initial_grain) - preload("res://scripts/core/military_grain_service.gd").consumed(raw, source.depot_id)
		if int(depot.stock.grain) > int(depot.capacity) or preload("res://scripts/core/geo_map_data_contract.gd").new().get_node(depot.location_node_id).is_empty(): return Rules.fail("地方粮仓缺少实际地点或库存超容")
	var ids := {}
	for row in raw.get("grain_transports", []):
		if not row is Dictionary: return Rules.fail("粮运记录类型无效")
		if row.get("transport_kind") != "regional_grain": continue
		if ids.has(row.get("transport_id")) or row.get("source_id") != rule.source_id or not balances.has(row.get("from_depot_id")) or not balances.has(row.get("target_id")) or not raw.character_states.has(row.get("principal_id")) or not row.get("history") is Array or row.get("status") not in ["awaiting_dispatch", "in_transit", "awaiting_receipt", "reporting", "reported"]: return Rules.fail("地方粮运实际主体或阶段无效")
		ids[row.transport_id] = true
		if ids.size() > 128: return Rules.fail("地方粮运履历容量越界")
		if not row.get("source_node_id") is String or not row.get("target_node_id") is String: return Rules.fail("调粮缺少签发时确定的交割地点")
		var source_node: String = row.source_node_id
		var target_node: String = row.target_node_id
		if not row.get("origin_node_id") is String or not valid_path(row.get("command_legs"), row.origin_node_id, source_node) or not valid_path(row.get("legs"), source_node, target_node) or not valid_path(row.get("report_legs"), target_node, row.origin_node_id): return Rules.fail("地方调粮路线不连续或没有实际抵达目标")
		for key in ["initial_grain", "current_grain", "lost_grain", "received_grain", "command_index", "leg_index", "leg_quarters", "report_index", "start_day", "last_advanced_day"]:
			if not Rules.amount(row.get(key)): return Rules.fail("地方粮运缺少数量或日期")
		if int(row.last_advanced_day) > int(raw.current_day) or row.command_index > row.get("command_legs", []).size() or row.leg_index > row.get("legs", []).size() or row.report_index > row.get("report_legs", []).size(): return Rules.fail("地方粮运进度越界")
		var receipt: Dictionary = raw.get("action_receipts", {}).get(row.get("dispatch_receipt"), {})
		if receipt.get("status") != "committed" or not receipt.get("effect_refs", []).has(row.transport_id) or receipt.get("day") != row.start_day: return Rules.fail("地方调粮缺少共同签发凭据")
		if receipt.get("grain_order") != order_record(row): return Rules.fail("地方调粮与共同签发的原始路线或数量不一致")
		var history := validate_history(row, int(raw.current_day), int(rule.loss_per_mille))
		if not history.ok: return history
		var notices := Reports.validate(row, int(raw.current_day))
		if not notices.ok: return notices
		if row.has("dispatched_day"):
			if int(row.initial_grain) != int(row.current_grain) + int(row.lost_grain) + int(row.received_grain): return Rules.fail("地方粮运实物不守恒")
			balances[row.from_depot_id] -= int(row.initial_grain)
		elif row.current_grain != 0 or row.received_grain != 0 or row.lost_grain != 0 or row.status != "awaiting_dispatch": return Rules.fail("未出库调令不能生成在途粮食")
		balances[row.target_id] += int(row.received_grain)
	for id in balances:
		if balances[id] != int(raw.depot_states[id].stock.grain): return Rules.fail("地方仓粮缺少出入库来源或重复交割")
	return {"ok": true}

static func valid_path(value: Variant, origin: String, destination: String) -> bool:
	if not value is Array or origin.is_empty() or destination.is_empty(): return false
	var cursor := origin
	var visited: Array = [cursor]
	for leg in value:
		if not leg is Dictionary or not leg.get("corridor_id") is String or str(leg.corridor_id).is_empty() or leg.get("from_node_id") != cursor or not leg.get("to_node_id") is String or str(leg.to_node_id).is_empty() or visited.has(leg.to_node_id) or not Rules.amount(leg.get("base_days"), true): return false
		cursor = leg.to_node_id
		visited.append(cursor)
	return cursor == destination

static func validate_history(row: Dictionary, today: int, loss_per_mille: int) -> Dictionary:
	var command := 0
	var leg := 0
	var quarters := 0
	var report := 0
	var grain := 0
	var lost := 0
	var received := 0
	var phase := "awaiting_dispatch"
	var last_day: int = int(row.start_day)
	var last_event := ""
	for entry in row.history:
		if not entry is Dictionary or not Rules.amount(entry.get("day")) or int(entry.day) < last_day or int(entry.day) > today: return Rules.fail("调粮履历日期无效")
		var event: String = str(entry.get("event", ""))
		if int(entry.day) == last_day and not ((last_event == "command" and event in ["dispatch", "exception"]) or (last_event == "travel" and event in ["receive", "exception"]) or (last_event == "report" and event == "reported")): return Rules.fail("同日重复粮运工序")
		match event:
			"exception":
				if not entry.get("notice") is Dictionary or entry.notice.get("observed_phase") != phase or entry.notice.get("observed_day") != entry.day: return Rules.fail("粮运异常观察不属于实际阶段")
				var origin: String = str(row.target_node_id)
				if phase == "awaiting_dispatch": origin = str(row.command_legs[command].from_node_id) if command < row.command_legs.size() else str(row.source_node_id)
				elif phase == "in_transit": origin = str(row.legs[leg].from_node_id)
				elif phase == "reporting" and report < row.report_legs.size(): origin = str(row.report_legs[report].from_node_id)
				if entry.notice.get("from_node_id") != origin or entry.notice.get("to_node_id") != row.origin_node_id: return Rules.fail("异常回报不能伪造观察地点以省略通信距离")
			"command":
				if phase != "awaiting_dispatch" or entry.get("index") != command or command >= row.command_legs.size(): return Rules.fail("调令传送履历断裂")
				command += 1
			"dispatch":
				if phase != "awaiting_dispatch" or command != row.command_legs.size() or entry.get("amount") != row.initial_grain or row.get("dispatched_day") != entry.day: return Rules.fail("未收到完整命令便凭空出粮")
				grain = int(row.initial_grain)
				phase = "in_transit"
				if row.legs.is_empty():
					if row.get("arrived_day") != entry.day: return Rules.fail("同地交割缺少实际到场日")
					phase = "awaiting_receipt"
			"travel":
				if phase != "in_transit" or leg >= row.legs.size() or entry.get("index") != leg or not Rules.amount(entry.get("quarters"), true) or int(entry.quarters) > 4 or int(entry.quarters) > int(row.legs[leg].base_days) * 4 - quarters: return Rules.fail("粮队实际道路进度不符")
				var expected_loss: int = mini(grain, int(ceil(float(grain) * loss_per_mille / 1000.0)))
				if entry.get("loss") != expected_loss: return Rules.fail("粮队实际途损不符")
				grain -= expected_loss
				lost += expected_loss
				quarters += int(entry.quarters)
				if quarters == int(row.legs[leg].base_days) * 4: leg += 1; quarters = 0
				if leg == row.legs.size():
					if row.get("arrived_day") != entry.day: return Rules.fail("粮队实际到场日丢失")
					phase = "awaiting_receipt"
			"receive":
				if phase != "awaiting_receipt" or entry.get("amount") != grain or row.get("received_day") != entry.day: return Rules.fail("接收仓不能在实际抵达前收粮")
				received = grain
				grain = 0
				phase = "reporting"
			"report":
				if phase != "reporting" or entry.get("index") != report or report >= row.report_legs.size(): return Rules.fail("入库驿报履历断裂")
				report += 1
			"reported":
				if phase != "reporting" or report != row.report_legs.size() or row.get("reported_day") != entry.day: return Rules.fail("回报尚未实际送达")
				phase = "reported"
			_: return Rules.fail("未知粮运履历")
		last_day = int(entry.day)
		last_event = event
	if row.status != phase or row.command_index != command or row.leg_index != leg or row.leg_quarters != quarters or row.report_index != report or row.current_grain != grain or row.lost_grain != lost or row.received_grain != received or int(row.last_advanced_day) < last_day: return Rules.fail("粮队进度与实际出入库履历不符")
	return {"ok": true}
