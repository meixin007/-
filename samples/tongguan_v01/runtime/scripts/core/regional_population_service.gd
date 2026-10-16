extends RefCounted
## Opening census remains immutable. Movements are conserved rule events,
## not a second census, and do not make remote observers know current counts.
const KEY := "regional_population_movements"
const Number = preload("res://scripts/core/node_control_observation.gd")

static func _opening(state, node: String) -> Dictionary:
	var flags: Dictionary=state.get("flags")
	for row in flags.get("regional_census",{}).get("prefectures",{}).values():
		var aliases: Array=[str(row.city.place_id).trim_prefix("city:")]
		if not str(row.city.get("domain_id","")).is_empty(): aliases.append(str(row.city.domain_id))
		if not aliases.has(node): continue
		return {"population":int(row.population),"households":int(row.households),"city_population":int(row.city.population),"city_households":int(row.city.households),"baseline_city_population":int(row.city.population),"source_ref":str(row.place_id),"node_ids":aliases}
	return {}

static func _transfer(counts: Dictionary, people: int, households: int, sign_value: int) -> void:
	counts.population+=people*sign_value
	counts.households+=households*sign_value
	counts.city_population+=people*sign_value
	counts.city_households+=households*sign_value

static func at_node(state, node: String, through_day: int = -1, movement_count: int = -1) -> Dictionary:
	var counts: Dictionary=_opening(state,node)
	if counts.is_empty(): return counts
	for row in state.get("flags").get(KEY,{}).values():
		if movement_count>=0 and int(row.sequence)>=movement_count: continue
		if through_day>=0 and int(row.day)>through_day: continue
		if counts.node_ids.has(row.from_node): _transfer(counts,int(row.people),int(row.households),-1)
		if counts.node_ids.has(row.to_node): _transfer(counts,int(row.people),int(row.households),1)
	return counts

static func _valid(counts: Dictionary) -> bool:
	return counts.city_households>=0 and counts.city_population>=counts.city_households and counts.city_population<=counts.city_households*12 and counts.population>=counts.city_population and counts.households>=counts.city_households

static func move_households(state, id: String, origin: String, destination: String, people: int, households: int, source: String) -> Dictionary:
	if id.is_empty() or source.is_empty() or origin==destination or people<households or households<=0 or people>households*12: return {"ok":false,"error":"迁居须有来源及有效的不同起讫家庭人数"}
	var registry: Dictionary=state.flags.get(KEY,{})
	if registry.has(id):
		var prior: Dictionary=registry[id]
		return {"ok":true,"code":"idempotent_replay"} if prior.from_node==origin and prior.to_node==destination and prior.people==people and prior.households==households and prior.source_ref==source else {"ok":false,"error":"迁居标识已被其他事件使用"}
	var from: Dictionary=at_node(state,origin)
	var to: Dictionary=at_node(state,destination)
	if from.is_empty() or to.is_empty(): return {"ok":false,"error":"迁居地点缺少人口来源"}
	if from.source_ref==to.source_ref: return {"ok":false,"error":"起讫属于同一人口登记，不能作为跨地迁居"}
	_transfer(from,people,households,-1); _transfer(to,people,households,1)
	if not _valid(from) or not _valid(to): return {"ok":false,"error":"迁居人数超过来源或户口结构无效"}
	if not state.flags.has(KEY): state.flags[KEY]={}
	state.flags[KEY][id]={"movement_id":id,"sequence":registry.size(),"from_node":origin,"to_node":destination,"people":people,"households":households,"day":int(state.current_day),"source_ref":source}
	return {"ok":true,"result_ref":id}

static func factor(state, node: String, through_day: int = -1, movement_count: int = -1) -> float:
	var counts: Dictionary=at_node(state,node,through_day,movement_count)
	if counts.is_empty() or counts.baseline_city_population<=0: return 1.0
	return float(counts.city_population)/float(counts.baseline_city_population)

static func validate(raw: Dictionary) -> Dictionary:
	var flags: Variant=raw.get("flags",{})
	if not flags is Dictionary: return {"ok":false,"error":"人口记录标记无效"}
	var registry: Variant=flags.get(KEY,{})
	if not registry is Dictionary: return {"ok":false,"error":"迁居记录结构无效"}
	var ordered: Array=[]
	for id in registry:
		var row: Variant=registry[id]
		if not row is Dictionary or row.get("movement_id")!=id: return {"ok":false,"error":"迁居记录身份无效"}
		for key in ["from_node","to_node","source_ref"]:
			if not row.get(key) is String or row[key].is_empty(): return {"ok":false,"error":"迁居记录来源无效"}
		for key in ["sequence","people","households","day"]:
			if not Number.integer(row.get(key)): return {"ok":false,"error":"迁居数量或日期无效"}
		if row.day>raw.get("current_day",0): return {"ok":false,"error":"迁居不能来自未来"}
		ordered.append(row)
	ordered.sort_custom(func(a,b): return a.sequence<b.sequence)
	var replay := {"flags":{KEY:{},"regional_census":flags.get("regional_census",{})},"current_day":raw.get("current_day",0)}
	for row in ordered:
		if int(row.sequence)!=replay.flags[KEY].size(): return {"ok":false,"error":"迁居顺序不连续"}
		var result: Dictionary=move_households(replay,row.movement_id,row.from_node,row.to_node,int(row.people),int(row.households),row.source_ref)
		if not result.ok: return result
	return {"ok":true}
