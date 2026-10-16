extends RefCounted
const Rules = preload("res://scripts/core/management_state_contract.gd")

static func origin_for(row: Dictionary, depots: Dictionary) -> String:
	if row.status == "awaiting_dispatch":
		return str(row.command_legs[int(row.command_index)].from_node_id) if int(row.command_index) < row.command_legs.size() else str(row.source_node_id)
	if row.status == "in_transit": return str(row.legs[int(row.leg_index)].from_node_id)
	if row.status == "reporting" and int(row.report_index) < row.report_legs.size(): return str(row.report_legs[int(row.report_index)].from_node_id)
	return str(row.target_node_id)

# Choose an existing itinerary, then recheck passage each actual messenger day.
static func itinerary(state, origin: String, destination: String) -> Dictionary:
	var queue: Array = [{"node": origin, "legs": []}]
	var seen := {origin: true}
	while not queue.is_empty():
		var current: Dictionary = queue.pop_front()
		if current.node == destination: return {"ok": true, "legs": current.legs}
		for id in state.transit_corridors:
			var road: Dictionary = state.transit_corridors[id]
			if not Rules.amount(road.get("base_travel_days"), true): continue
			var next: String = str(road.get("to_node_id", "")) if road.get("from_node_id") == current.node else (str(road.get("from_node_id", "")) if road.get("to_node_id") == current.node else "")
			if next.is_empty() or seen.has(next): continue
			seen[next] = true
			var legs: Array = current.legs.duplicate(true)
			legs.append({"corridor_id": id, "from_node_id": current.node, "to_node_id": next, "base_days": int(road.base_travel_days)})
			queue.append({"node": next, "legs": legs})
	return {"ok": false}

static func evidence(notice: Dictionary) -> Dictionary:
	var result := {}
	for key in ["notice_id", "key", "observed_day", "observed_phase", "message", "from_node_id", "to_node_id", "legs"]: result[key] = notice.get(key)
	return result.duplicate(true)

static func record(state, row: Dictionary, message: String) -> void:
	row.blocking_reason = message
	if not row.has("notices"): row["notices"] = []
	var key: String = "%s:%d:%d:%d:%d:%s" % [row.status, int(row.command_index), int(row.leg_index), int(row.leg_quarters), int(row.report_index), message]
	if row.notices.any(func(notice): return notice.key == key): return
	var origin := origin_for(row, state.depot_states)
	var route := itinerary(state, origin, row.origin_node_id)
	if not route.ok: return # No connected messenger itinerary means no delivered information.
	var notice := {"notice_id": "%s:notice:%d" % [row.transport_id, row.notices.size()], "key": key, "observed_day": int(state.current_day), "observed_phase": row.status, "message": message, "from_node_id": origin, "to_node_id": row.origin_node_id, "legs": route.legs, "leg_index": 0, "last_advanced_day": int(state.current_day), "travel_log": [], "status": "in_transit", "history_index": row.history.size()}
	row.history.append({"day": int(state.current_day), "event": "exception", "notice": evidence(notice)})
	row.notices.append(notice)

static func advance(state, row: Dictionary) -> void:
	for notice in row.get("notices", []):
		if notice.status == "delivered" or int(notice.last_advanced_day) >= int(state.current_day): continue
		notice.last_advanced_day = int(state.current_day)
		if int(notice.leg_index) < notice.legs.size():
			var passable: Dictionary = load("res://scripts/core/regional_grain_service.gd").passage(state, notice.legs[int(notice.leg_index)])
			if not passable.is_passable: continue
			notice.travel_log.append({"day": int(state.current_day), "index": int(notice.leg_index)})
			notice.leg_index += 1
			if int(notice.leg_index) < notice.legs.size(): continue
		notice.status = "delivered"
		notice["delivered_day"] = int(state.current_day)

static func latest(row: Dictionary) -> Dictionary:
	var delivered: Array = row.get("notices", []).filter(func(notice): return notice.status == "delivered")
	if delivered.is_empty(): return {}
	var actual: Dictionary = delivered[-1]
	return {"notice_id": actual.notice_id, "message": actual.message, "observed_day": actual.observed_day, "delivered_day": actual.delivered_day}

static func validate(row: Dictionary, today: int) -> Dictionary:
	if not row.get("notices", []) is Array or row.get("notices", []).size() > 128: return Rules.fail("粮运异常回报容量或类型无效")
	var ids := {}
	var history_refs := {}
	for notice in row.get("notices", []):
		if not notice is Dictionary or not notice.get("notice_id") is String or ids.has(notice.notice_id) or not notice.get("message") is String or not notice.get("travel_log") is Array or not Rules.amount(notice.get("history_index")) or int(notice.history_index) >= row.history.size(): return Rules.fail("粮运异常回报缺少实际观察")
		ids[notice.notice_id] = true
		if history_refs.has(notice.history_index): return Rules.fail("同一粮运观察不能复制回报")
		history_refs[notice.history_index] = true
		var entry: Dictionary = row.history[int(notice.history_index)]
		if entry.get("event") != "exception" or entry.get("day") != notice.get("observed_day") or entry.get("notice") != evidence(notice): return Rules.fail("异常回报与实际观察履历不符")
		if not load("res://scripts/core/regional_grain_service.gd").valid_path(notice.get("legs"), str(notice.get("from_node_id", "")), str(row.origin_node_id)) or notice.get("to_node_id") != row.origin_node_id: return Rules.fail("异常回报没有实际通信路线")
		var last_day: int = int(notice.observed_day)
		var index := 0
		for travel in notice.travel_log:
			if not travel is Dictionary or not Rules.amount(travel.get("day")) or int(travel.day) <= last_day or int(travel.day) > today or travel.get("index") != index or index >= notice.legs.size(): return Rules.fail("异常回报驿递履历不连续")
			index += 1
			last_day = int(travel.day)
		if not Rules.amount(notice.get("last_advanced_day")) or int(notice.last_advanced_day) < last_day or int(notice.last_advanced_day) > today or notice.get("leg_index") != index or notice.get("status") not in ["in_transit", "delivered"]: return Rules.fail("异常回报实际进度无效")
		if notice.status == "delivered":
			if index != notice.legs.size() or not Rules.amount(notice.get("delivered_day")) or int(notice.delivered_day) <= int(notice.observed_day) or int(notice.delivered_day) > today or (not notice.legs.is_empty() and int(notice.delivered_day) != last_day): return Rules.fail("异常回报尚未实际到达却已获知")
		elif notice.has("delivered_day"): return Rules.fail("未送达回报不能具有收报日期")
	if row.history.filter(func(entry): return entry.get("event") == "exception").size() != history_refs.size(): return Rules.fail("粮运观察丢失对应回报")
	return {"ok": true}
