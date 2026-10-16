# scripts/core/route_network_service.gd
extends RefCounted

class_name RouteNetworkService

const CorridorReader = preload("res://scripts/core/runtime_corridor_reader.gd")

const CLAMPED_FIELDS := ["supply_flow", "security", "rebel_pressure", "uncertainty"]
const GeoMapDataContractScript = preload("res://scripts/core/geo_map_data_contract.gd")

var _geo_contract = null

func _init(geo_contract = null) -> void:
	if geo_contract != null:
		_geo_contract = geo_contract
	else:
		_geo_contract = GeoMapDataContractScript.new()
		_geo_contract.load_all()

func get_route(state, route_id: String) -> Dictionary:
	return CorridorReader.network_route(state, route_id, _geo_contract)

## Internal diagnostics only; public UI still requires observer filtering.
func inspect_corridor_sources(state, route_id: String) -> Dictionary:
	return CorridorReader.inspect_sources(state, route_id, _geo_contract)

func get_node(state, node_id: String) -> Dictionary:
	if state == null:
		return _geo_contract.get_node(node_id)
	var state_nodes: Dictionary = state.route_network_state.get("nodes", {}) if (state != null and "route_network_state" in state and state.route_network_state is Dictionary) else {}
	if state_nodes.has(node_id):
		return state_nodes[node_id].duplicate(true)
	return _geo_contract.get_node(node_id)

func get_routes_for_node(state, node_id: String) -> Array:
	var result: Array = []
	var all_routes := _get_merged_routes(state)
	for route_id in all_routes.keys():
		var route: Dictionary = all_routes[route_id]
		if str(route.get("from_node_id", "")) == node_id or str(route.get("to_node_id", "")) == node_id:
			result.append(route.duplicate(true))
	return result

func apply_route_effects(state, route_id: String, effects: Array, options: Dictionary = {}) -> Dictionary:
	if state == null:
		return _fail("missing state")
	if not ("route_network_state" in state and state.route_network_state is Dictionary):
		state.route_network_state = {"routes": {}, "nodes": {}}
	if not state.route_network_state.has("routes"):
		state.route_network_state["routes"] = {}
		
	var existing_route: Dictionary = state.route_network_state.routes.get(route_id, _geo_contract.get_corridor(route_id)).duplicate(true)
	if existing_route.is_empty():
		return _fail("unknown route: " + route_id)
		
	for effect in effects:
		var field := str(effect.get("field", ""))
		if field == "":
			continue
		var next_value := int(existing_route.get(field, 0)) + int(effect.get("value", 0))
		if CLAMPED_FIELDS.has(field):
			next_value = clampi(next_value, 0, 100)
		if field == "message_delay" or field == "base_travel_days":
			next_value = maxi(1, next_value)
		if field == "is_blocked":
			existing_route["is_blocked"] = bool(effect.get("value", false))
			continue
		existing_route[field] = next_value
		
	var history: Array = existing_route.get("recent_changes", []).duplicate(true)
	history.append({
		"reason": str(options.get("reason", "route effect")),
		"day": int(state.current_day) if "current_day" in state else 1,
		"effects": effects.duplicate(true)
	})
	existing_route["recent_changes"] = history
	state.route_network_state.routes[route_id] = existing_route
	
	if "chronicle_causal_references" in state and state.chronicle_causal_references is Array:
		state.chronicle_causal_references.append({
			"kind": "route",
			"id": route_id,
			"reason": str(options.get("reason", "route effect")),
			"day": int(state.current_day) if "current_day" in state else 1
		})
	return {"ok": true, "route": existing_route.duplicate(true)}

func find_shortest_path(state, start_node_id: String, end_node_id: String) -> Dictionary:
	if start_node_id == end_node_id:
		return {
			"ok": true,
			"path_nodes": [start_node_id],
			"corridors": [],
			"total_travel_days": 0,
			"total_loss_rate": 0.0,
			"is_blocked": false
		}
		
	var all_routes := _get_merged_routes(state)
	var adjacency := _build_adjacency(all_routes)
	
	if not adjacency.has(start_node_id) or not adjacency.has(end_node_id):
		return {"ok": false, "error": "Start or end node not in route topology"}
		
	# Dijkstra 最短路计算 (权重为 travel_days)
	var dist: Dictionary = {}
	var prev_node: Dictionary = {}
	var prev_corridor: Dictionary = {}
	var unvisited: Array[String] = []
	
	for node in adjacency.keys():
		dist[node] = 999999
		unvisited.append(str(node))
	dist[start_node_id] = 0
	
	while not unvisited.is_empty():
		# 提取未访问中最小距离节点
		var current_node := ""
		var current_min_dist := 999999
		for node in unvisited:
			if dist[node] < current_min_dist:
				current_min_dist = dist[node]
				current_node = node
				
		if current_node.is_empty() or current_min_dist == 999999:
			break
		if current_node == end_node_id:
			break
			
		unvisited.erase(current_node)
		
		for edge in adjacency.get(current_node, []):
			var neighbor: String = str(edge["neighbor"])
			var corridor: Dictionary = edge["corridor"]
			if not CorridorReader.passage(state, corridor).is_passable:
				continue # 阻断走廊不可通行
				
			var weight: int = CorridorReader.current_condition_travel_days(state, corridor) + int(corridor.get("message_delay", 0))
			var alt: int = dist[current_node] + weight
			if alt < dist.get(neighbor, 999999):
				dist[neighbor] = alt
				prev_node[neighbor] = current_node
				prev_corridor[neighbor] = corridor
				
	if not prev_node.has(end_node_id):
		return {"ok": false, "error": "No connected path between %s and %s" % [start_node_id, end_node_id]}
		
	# 回溯路径
	var path_nodes: Array[String] = []
	var path_corridors: Array[Dictionary] = []
	var curr := end_node_id
	var total_loss := 0.0
	
	while curr != start_node_id:
		path_nodes.push_front(curr)
		var c: Dictionary = prev_corridor[curr]
		path_corridors.push_front(c)
		total_loss += float(c.get("loss_rate_per_day", 0.002)) * float(c.get("base_travel_days", 3))
		curr = prev_node[curr]
	path_nodes.push_front(start_node_id)
	
	return {
		"ok": true,
		"path_nodes": path_nodes,
		"corridors": path_corridors,
		"total_travel_days": dist[end_node_id],
		"total_loss_rate": total_loss,
		"is_blocked": false
	}

func calculate_courier_travel_days(state, from_node_id: String, to_node_id: String) -> int:
	var path_result := find_shortest_path(state, from_node_id, to_node_id)
	if not bool(path_result.get("ok", false)):
		return -1 # 不可达或路线断绝
	return int(path_result.get("total_travel_days", 0))

func get_route_pressure_summary(state, route_id: String) -> String:
	var route := get_route(state, route_id)
	if route.is_empty():
		return ""
	return "Route %s supply=%d delay=%d security=%d rebel=%d uncertainty=%d" % [
		route_id,
		int(route.get("supply_flow", 0)),
		int(route.get("message_delay", 0)),
		int(route.get("security", 0)),
		int(route.get("rebel_pressure", 0)),
		int(route.get("uncertainty", 0))
	]

func _get_merged_routes(state) -> Dictionary:
	return CorridorReader.network_routes(state, _geo_contract)

func _build_adjacency(routes: Dictionary) -> Dictionary:
	var adj: Dictionary = {}
	for r in routes.values():
		if not (r is Dictionary):
			continue
		var u := str(r.get("from_node_id", ""))
		var v := str(r.get("to_node_id", ""))
		if u.is_empty() or v.is_empty():
			continue
		if not adj.has(u): adj[u] = []
		if not adj.has(v): adj[v] = []
		adj[u].append({"neighbor": v, "corridor": r})
		adj[v].append({"neighbor": u, "corridor": r})
	return adj

func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
