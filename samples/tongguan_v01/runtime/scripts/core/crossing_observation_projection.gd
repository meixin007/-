extends RefCounted
## Local eyewitness projection only. No remote weather or stock inference.
const Conditions=preload("res://scripts/domain/river_crossing_conditions.gd")
const Reader=preload("res://scripts/core/runtime_corridor_reader.gd")
const LOCAL_NODES={"wei_chencang_ferry":"zhou_fengxiang","liangzhou_han_ferry":"zhou_liangzhou_south"}
static func project(state, viewer_id: String) -> Dictionary:
	if state == null:return {}
	var character: Dictionary=state.character_states.get(viewer_id,{})
	var location: String=str(character.get("location_id",""))
	var observations: Dictionary={}
	var transports: Dictionary={}
	for route_id: String in Conditions.ROUTES:
		var crossing_id: String=Conditions.ROUTES[route_id]
		if location.is_empty() or location!=LOCAL_NODES[crossing_id]:continue
		var route: Dictionary=Reader.transport_route(state,route_id)
		if route.is_empty():continue
		var passage: Dictionary=Reader.passage(state,route)
		var surface: Dictionary=Conditions.passage(state,route)
		var surface_state: String="high_water" if surface.reason_code=="high_water" else ("normal" if surface.is_passable else "unknown")
		var description: String="可渡" if passage.is_passable else ("高水位 · 停渡" if passage.reason_code=="high_water" else str(passage.reason))
		if passage.reason_code=="wet_road":description="可渡 · 沿线雨后缓行"
		if passage.reason_code=="snow_blocked":description="沿线山口雪阻 · 暂停启程"
		observations[crossing_id]={"crossing_id":crossing_id,"corridor_id":route_id,"observed_day":int(state.current_day),"evidence":"local_observation","reason_code":passage.reason_code,"label":str(Conditions.CROSSINGS[crossing_id].name)+" · "+description}
		observations[crossing_id]["surface_state"]=surface_state
		observations[crossing_id]["road_surface_state"]=preload("res://scripts/domain/road_surface_conditions.gd").effect(state,route).surface_state
		for raw: Variant in state.grain_transports:
			if not raw is Dictionary or str(raw.get("corridor_id",""))!=route_id:continue
			if str(raw.get("status","")) not in ["in_transit","waiting_crossing","waiting_snow"]:continue
			# A local departure queue is observable. Being at one endpoint does not
			# reveal a convoy anywhere along the complete inter-city route.
			var depot: Dictionary=state.depot_states.get(str(raw.get("from_depot_id","")),{})
			if str(depot.get("location_node_id",""))!=location:continue
			if int(raw.get("remaining_days",-1))!=int(raw.get("total_days",-2)):continue
			if int(raw.get("surface_progress_quarters",0))>0:continue
			var id: String=str(raw.get("transport_id",""))
			transports[id]={"transport_id":id,"corridor_id":route_id,"from_depot_id":str(raw.get("from_depot_id","")),"total_days":int(raw.get("total_days",1)),"remaining_days":int(raw.get("remaining_days",1)),"status":str(raw.get("status","")),"label":"粮队 · 候水退" if raw.get("status")=="waiting_crossing" else "粮队 · 待出发"}
			if raw.get("status")=="waiting_snow":transports[id]["label"]="粮队 · 候山路恢复"
	var result: Dictionary={}
	if not observations.is_empty():result["crossing_observations"]=observations
	if not transports.is_empty():result["visible_crossing_transports"]=transports
	return result
