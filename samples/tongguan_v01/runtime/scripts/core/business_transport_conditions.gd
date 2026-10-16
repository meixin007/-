extends RefCounted
## Coarse local market effect of existing transport rules, not a second route graph.
const Reader=preload("res://scripts/core/runtime_corridor_reader.gd")
const Contract=preload("res://scripts/core/management_state_contract.gd")

static func snapshot(state, node_id: String) -> Dictionary:
	var routes: Array=[]
	for id in state.transit_corridors:
		var route: Dictionary=state.transit_corridors[id]
		if node_id not in [route.get("from_node_id"),route.get("to_node_id")] or Reader.is_definition_pending(route): continue
		var condition: Dictionary=Reader.passage(state,route)
		routes.append({"corridor_id":id,"from_node_id":route.from_node_id,"to_node_id":route.to_node_id,"speed_quarters":clampi(int(condition.get("speed_quarters",4)),0,4) if condition.is_passable else 0,"reason":str(condition.get("reason",""))})
	routes.sort_custom(func(a,b):return a.corridor_id<b.corridor_id)
	return {"routes":routes}

static func availability(value: Dictionary) -> float:
	if value.get("routes",[]).is_empty(): return 1.0
	var quarters := 0
	for route in value.routes: quarters+=int(route.speed_quarters)
	return float(quarters)/(4.0*value.routes.size())

static func supply_factor(value: Dictionary) -> float:
	return 0.5+0.5*availability(value)

static func description(value: Dictionary) -> String:
	if value.get("routes",[]).is_empty(): return "交通条件未知：没有已启用的相接道路登记，暂按产业配置基准供给。"
	return "交通可用能力%d%%；运输业按此折减，普通供给按%d%%计（保留一半本地供给）。依据%d条相接道路的当前通行条件。" % [roundi(availability(value)*100),roundi(supply_factor(value)*100),value.routes.size()]

static func validate(raw, node_id: String, value: Variant) -> Dictionary:
	if not value is Dictionary or value.size()!=1 or not value.get("routes") is Array: return Contract.fail("交通经营快照无效")
	var seen := {}
	for route in value.routes:
		if not route is Dictionary or route.size()!=5 or not route.get("corridor_id") is String or seen.has(route.corridor_id): return Contract.fail("交通来源缺失或重复")
		var source: Dictionary=raw.transit_corridors.get(route.corridor_id,{})
		if source.is_empty() or route.get("from_node_id")!=source.get("from_node_id") or route.get("to_node_id")!=source.get("to_node_id") or node_id not in [route.from_node_id,route.to_node_id]: return Contract.fail("交通来源未连接本产业地点")
		if not Contract.amount(route.get("speed_quarters")) or int(route.speed_quarters)>4 or not route.get("reason") is String: return Contract.fail("交通可用能力无效")
		seen[route.corridor_id]=true
	return {"ok":true}
