extends RefCounted
## Audited new-campaign definitions; optional rule dependencies, never art geometry.
const SOURCE := "res://data/scenarios/anshi_rebellion/map_strategy_nodes.json"
const SPECS := {
	"c_fengxiang_liangzhou": ["zhou_fengxiang","zhou_liangzhou_south",3,"wei_chencang_shared_ferry_art"],
	"c_liangzhou_jianmen": ["zhou_liangzhou_south","jianmen_pass_node",2,"liangzhou_han_ferry_art"],
}
static func apply(state, enable_crossings: bool = false) -> Dictionary:
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	if not data is Dictionary or not data.get("strategic_nodes") is Array or not data.get("transit_corridors") is Array:
		return {"ok":false,"error":"Invalid map definition source"}
	var nodes: Dictionary={}
	var routes: Dictionary={}
	for raw: Variant in data.strategic_nodes:
		if not raw is Dictionary:return {"ok":false,"error":"Invalid strategic node record"}
		if raw.get("node_id") not in ["zhou_fengxiang","zhou_liangzhou_south","jianmen_pass_node"]:continue
		var coords: Variant=raw.get("coords")
		if nodes.has(raw.node_id) or not coords is Array or coords.size()!=2:
			return {"ok":false,"error":"Invalid or duplicate Liang endpoint"}
		for value: Variant in coords:
			if not (value is int or value is float) or not is_finite(float(value)) or value<0 or value>1:
				return {"ok":false,"error":"Invalid Liang endpoint coordinates"}
		# Static identity only: no control faction, stock, knowledge or pass strength.
		nodes[raw.node_id]={"node_id":raw.node_id,"id":raw.node_id,"name":raw.get("display_name",raw.node_id),"display_name":raw.get("display_name",raw.node_id),"coords":coords.duplicate(),"node_type":raw.get("node_type",""),"definition_source":SOURCE}
	for raw: Variant in data.transit_corridors:
		if not raw is Dictionary:return {"ok":false,"error":"Invalid map corridor record"}
		var id: String=str(raw.get("corridor_id",""))
		if not SPECS.has(id):continue
		var spec: Array=SPECS[id]
		if routes.has(id) or raw.get("from_node_id")!=spec[0] or raw.get("to_node_id")!=spec[1] or raw.get("transit_type")!="mountain_pass" or raw.get("base_travel_days")!=spec[2]:
			return {"ok":false,"error":"Audited Liang route definition changed: "+id}
		var row: Dictionary=raw.duplicate(true)
		row.merge({"id":id,"route_id":id,"name":raw.get("corridor_name",id),"activation_status":"pending_dependencies","pending_dependencies":[spec[3]],"is_blocked":true,"blocking_reason":"道路定义已登记，渡河依赖尚未启用","definition_source":SOURCE})
		if enable_crossings:
			var crossing_id: String = preload("res://scripts/domain/river_crossing_conditions.gd").ROUTES[id]
			row["activation_status"] = "active"
			row["pending_dependencies"] = []
			row["required_crossings"] = [crossing_id]
			row["is_blocked"] = false
			row["blocking_reason"] = ""
		routes[id]=row
	if nodes.size()!=3 or routes.size()!=2:
		return {"ok":false,"error":"Missing audited Liang definitions"}
	# Validate the complete batch before writes; whole existing records win even {}.
	if not state.route_network_state.has("nodes"):state.route_network_state.nodes={}
	if not state.route_network_state.has("routes"):state.route_network_state.routes={}
	for id: String in nodes:
		if not state.route_network_state.nodes.has(id):state.route_network_state.nodes[id]=nodes[id].duplicate(true)
		if not state.strategic_nodes.has(id):state.strategic_nodes[id]=nodes[id].duplicate(true)
	for id: String in routes:
		if not state.route_network_state.routes.has(id):state.route_network_state.routes[id]=routes[id].duplicate(true)
		if not state.transit_corridors.has(id):state.transit_corridors[id]=routes[id].duplicate(true)
	return {"ok":true}
