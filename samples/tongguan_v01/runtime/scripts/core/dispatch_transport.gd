extends RefCounted
## Shared dispatch movement over the existing transport network.
const Staff = preload("res://scripts/core/business_staff_service.gd")
const Roads = preload("res://scripts/core/runtime_corridor_reader.gd")

static func validate_pending(raw: Dictionary) -> Dictionary:
	var pending: Variant=raw.get("information_pending_transmissions",[])
	if not pending is Array: return {"ok":false,"error":"消息待传队列无效"}
	for entry in pending:
		if not entry is Dictionary: return {"ok":false,"error":"消息待传记录无效"}
		if not entry.has("transport"): continue
		var t: Variant=entry.transport
		if not t is Dictionary or not t.get("leg") is Dictionary or not t.get("travel_log") is Array: return {"ok":false,"error":"消息行程结构无效"}
		if t.get("status")!="in_transit" or not t.get("current_node_id") is String or t.current_node_id.is_empty(): return {"ok":false,"error":"消息行程状态无效"}
		if not raw.get("character_states",{}).has(t.get("recipient_id")) or entry.get("transmission",{}).get("to_actor_id")!=t.recipient_id: return {"ok":false,"error":"消息行程接收人无效"}
		if not _count(t.get("last_advanced_day")) or t.last_advanced_day>raw.get("current_day",0): return {"ok":false,"error":"消息行程日期无效"}
		if not t.leg.is_empty():
			if t.leg.get("journey_kind") == "regional_estimate":
				var places: Dictionary = load("res://scripts/core/regional_visit_service.gd").destinations(raw)
				if t.get("report_kind") not in ["business_monthly", "social_agreement", "gift_delivery", "judicial_notice"] or t.leg.get("source_id") != load("res://scripts/core/regional_visit_service.gd").SOURCE or t.leg.get("from_node_id") != t.current_node_id or not places.has(t.leg.get("from_node_id")) or not places.has(t.leg.get("to_node_id")) or not _count(t.leg.get("quarters")) or t.leg.quarters >= t.leg.get("required_quarters", 0) or t.leg.get("required_quarters") != maxi(int(places[t.leg.from_node_id].days), int(places[t.leg.to_node_id].days))*4: return {"ok": false, "error": "地区消息行程缺少实际合同、来源或时间"}
				continue
			var road: Dictionary=raw.get("transit_corridors",{}).get(t.leg.get("corridor_id"),{})
			if road.is_empty() or not _count(t.leg.get("required_quarters")) or t.leg.required_quarters<4 or not _count(t.leg.get("quarters")) or t.leg.quarters>=t.leg.required_quarters: return {"ok":false,"error":"消息道路进度无效"}
			if t.leg.get("from_node_id")!=t.current_node_id or not ((road.from_node_id==t.leg.from_node_id and road.to_node_id==t.leg.get("to_node_id")) or (road.to_node_id==t.leg.from_node_id and road.from_node_id==t.leg.get("to_node_id"))): return {"ok":false,"error":"消息道路端点无效"}
	return {"ok":true}

static func _count(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and value>=0 and value<=2000000000 and float(value)==floor(float(value))

static func _deliver_here(state, report: Dictionary) -> bool:
	var person: Dictionary = state.character_states.get(report.recipient_id,{})
	if person.get("location_id")!=report.current_node_id or person.get("status") in Staff.UNAVAILABLE: return false
	if not report.leg.is_empty(): return false
	report.status="delivered"; report.delivered_day=int(state.current_day); report.recipient_node_id=report.current_node_id
	return true

static func _route(state, origin: String, destination: String, structural: bool = false) -> Dictionary:
	var queue: Array = [{"node":origin,"first":{}}]
	var seen := {origin:true}
	var ids: Array = state.transit_corridors.keys(); ids.sort()
	while not queue.is_empty():
		var cursor: Dictionary = queue.pop_front()
		if cursor.node==destination: return cursor.first
		for id in ids:
			var road: Dictionary = state.transit_corridors[id]
			var next := str(road.to_node_id) if road.from_node_id==cursor.node else str(road.from_node_id) if road.to_node_id==cursor.node else ""
			if next.is_empty() or seen.has(next) or (road.get("pending_dependencies",false) if structural else not Roads.passage(state,road).is_passable): continue
			seen[next]=true
			var leg: Dictionary = cursor.first if not cursor.first.is_empty() else {"corridor_id":id,"from_node_id":cursor.node,"to_node_id":next,"required_quarters":maxi(1,int(road.base_travel_days)+int(road.get("message_delay",0)))*4,"quarters":0}
			queue.append({"node":next,"first":leg})
	return {}

static func regional_leg(state, origin: String, destination: String) -> Dictionary:
	var visits=load("res://scripts/core/regional_visit_service.gd")
	var places: Dictionary=visits.destinations(state)
	if origin==destination or not places.has(origin) or not places.has(destination):return {}
	# This is the existing game pacing rule, not an invented transit corridor.
	return {"corridor_id":"","journey_kind":"regional_estimate","source_id":visits.SOURCE,"from_node_id":origin,"to_node_id":destination,"required_quarters":maxi(int(places[origin].days),int(places[destination].days))*4,"quarters":0}

static func advance(state, report: Dictionary) -> void:
	if report.status=="delivered" or int(report.last_advanced_day)>=int(state.current_day): return
	report.last_advanced_day=int(state.current_day)
	if _deliver_here(state,report): return
	if report.leg.is_empty():
		var destination: String=str(state.character_states.get(report.recipient_id,{}).get("location_id",""))
		report.leg=_route(state,report.current_node_id,destination)
		# Do not replace a known blocked route. Ordinary monthly mail can use the
		# coarse approved regional journey where the network has no registered path.
		if report.leg.is_empty() and report.get("report_kind") in ["business_monthly", "social_agreement", "gift_delivery", "judicial_notice"] and _route(state,report.current_node_id,destination,true).is_empty():report.leg=regional_leg(state,report.current_node_id,destination)
		if report.leg.is_empty(): return
	var leg: Dictionary = report.leg
	var estimated: bool=leg.get("journey_kind")=="regional_estimate"
	if estimated and mini(int(state.local_node_state.get(leg.from_node_id,{}).get("security",0)),int(state.local_node_state.get(leg.to_node_id,{}).get("security",0)))<20:return
	var passage: Dictionary = {"is_passable":true,"speed_quarters":4} if estimated else Roads.passage(state,state.transit_corridors[leg.corridor_id])
	if not passage.is_passable: return
	var quarters: int = mini(4,maxi(1,int(passage.get("speed_quarters",4))))
	var tick := {"day":int(state.current_day),"corridor_id":leg.corridor_id,"from_node_id":leg.from_node_id,"to_node_id":leg.to_node_id,"required_quarters":leg.required_quarters,"quarters":quarters}
	if estimated:tick.merge({"journey_kind":leg.journey_kind,"source_id":leg.source_id})
	report.travel_log.append(tick)
	leg.quarters+=quarters
	if int(leg.quarters)>=int(leg.required_quarters):
		report.current_node_id=leg.to_node_id; report.leg={}
		_deliver_here(state,report)

