extends RefCounted

## Internal rule-data reader, not an observer-safe UI projection.
## No persistent state, field merging, ID aliases, inferred topology or cost defaults.
const NETWORK_FIELDS := ["from_node_id", "to_node_id", "transit_type", "base_travel_days"]
const COMPARED_FIELDS := ["from_node_id", "to_node_id", "transit_type", "base_travel_days", "message_delay", "loss_rate_per_day", "is_blocked"]

static func is_definition_pending(record: Dictionary) -> bool:
	return str(record.get("activation_status", "")) == "pending_dependencies"

static func passage(state, record: Dictionary) -> Dictionary:
	if is_definition_pending(record):
		return {"is_passable":false, "reason_code":"pending_dependencies", "reason":"道路定义已登记，渡河依赖尚未启用"}
	if bool(record.get("is_blocked", false)):
		return {"is_passable":false, "reason_code":"blocked", "reason":str(record.get("blocking_reason", "通道受阻"))}
	var river: Dictionary = preload("res://scripts/domain/river_crossing_conditions.gd").passage(state, record)
	if not river.is_passable:return river
	return preload("res://scripts/domain/road_surface_conditions.gd").effect(state, record)

static func current_condition_travel_days(state, record: Dictionary, default_days: int = 3) -> int:
	var effect: Dictionary = preload("res://scripts/domain/road_surface_conditions.gd").effect(state, record)
	# Estimate under today's conditions; the transport clock rechecks each day.
	return int(ceil(float(record.get("base_travel_days", default_days))*4.0/maxi(1,int(effect.speed_quarters))))

static func network_route(state, route_id: String, geo_contract) -> Dictionary:
	var routes := _network_state_routes(state)
	if routes.has(route_id):
		return routes[route_id].duplicate(true)
	return geo_contract.get_corridor(route_id)

static func network_routes(state, geo_contract) -> Dictionary:
	var result: Dictionary = geo_contract.get_all_corridors()
	var routes := _network_state_routes(state)
	for route_id in routes:
		# Preserve the existing whole-record precedence, including empty records.
		result[route_id] = routes[route_id].duplicate(true)
	return result

static func transport_route(state, route_id: String) -> Dictionary:
	if state == null:
		return {}
	return state.transit_corridors.get(route_id, {}).duplicate(true)

static func inspect_sources(state, route_id: String, geo_contract) -> Dictionary:
	var routes := _network_state_routes(state)
	var definition: Dictionary = geo_contract.get_corridor(route_id)
	var has_override := routes.has(route_id)
	var override: Dictionary = routes.get(route_id, {}).duplicate(true)
	var transport := transport_route(state, route_id)
	var network := network_route(state, route_id, geo_contract)
	var source := "route_network_state.routes" if has_override else ("geo_definition" if not definition.is_empty() else "missing")
	var missing: Array[String] = []
	var shadowed: Array[String] = []
	for field in NETWORK_FIELDS:
		if not network.has(field):
			missing.append(field)
	if has_override:
		for field in definition:
			if not override.has(field):
				shadowed.append(str(field))
	shadowed.sort()
	var sources := {
		"geo_definition": {"present": not definition.is_empty(), "record": definition},
		"network_state": {"present": has_override, "record": override},
		"transport_state": {"present": state != null and state.transit_corridors.has(route_id), "record": transport.duplicate(true)}
	}
	var differences: Array[Dictionary] = []
	for pair in [["geo_definition", "network_state"], ["geo_definition", "transport_state"], ["network_state", "transport_state"]]:
		var left: Dictionary = sources[pair[0]].record
		var right: Dictionary = sources[pair[1]].record
		for field in COMPARED_FIELDS:
			# Missing is not a conflict and never receives a made-up default.
			if left.has(field) and right.has(field) and left[field] != right[field]:
				differences.append({"field": field, "left_source": pair[0], "left_value": left[field], "right_source": pair[1], "right_value": right[field]})
	return {
		"corridor_id": route_id,
		"network_source": source,
		"network_record": network,
		"transport_record": transport,
		"sources": sources,
		"missing_network_fields": missing,
		"shadowed_definition_fields": shadowed,
		"field_disagreements": differences
	}

static func _network_state_routes(state) -> Dictionary:
	if state != null and "route_network_state" in state and state.route_network_state is Dictionary:
		return state.route_network_state.get("routes", {})
	return {}
