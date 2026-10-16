extends RefCounted
## Explicit game estimate, not a historical employment census or a second population ledger.
const Population=preload("res://scripts/core/regional_population_service.gd")
const Contract=preload("res://scripts/core/management_state_contract.gd")
const Grain=preload("res://scripts/core/military_grain_service.gd")

static func _workers(people: int, named: int) -> int:
	return maxi(0,int(float(people)*0.4)-named)

static func snapshot(state, node: String) -> Dictionary:
	var counts: Dictionary=Population.at_node(state,node)
	var value := {"known":not counts.is_empty(),"source_ref":"","movement_count":state.flags.get(Population.KEY,{}).size(),"named_people":[],"forces":[],"baseline_workers":0,"available_workers":0,"military_support":0}
	if counts.is_empty(): return value
	value.source_ref=counts.source_ref
	for id in state.character_states:
		var person: Dictionary=state.character_states[id]
		if counts.node_ids.has(person.get("location_id")) and person.get("status") not in ["dead","deceased","executed","missing","departed","exiled"]: value.named_people.append(id)
	value.named_people.sort()
	for id in state.military_forces:
		var force: Dictionary=state.military_forces[id]
		if not counts.node_ids.has(force.get("current_node_id")) or not str(force.get("current_corridor_id","")).is_empty(): continue
		var troops: int=Grain.troop_count(force)
		if troops<=0: continue
		value.forces.append({"force_id":id,"troops":troops})
		value.military_support+=int(ceil(float(troops)/20.0))
	value.forces.sort_custom(func(a,b):return a.force_id<b.force_id)
	value.baseline_workers=_workers(int(counts.baseline_city_population),value.named_people.size())
	value.available_workers=maxi(0,_workers(int(counts.city_population),value.named_people.size())-int(value.military_support))
	return value

static func factor(value: Dictionary) -> float:
	if not value.get("known",false): return 1.0
	if int(value.baseline_workers)<=0: return 0.0
	return clampf(float(value.available_workers)/float(value.baseline_workers),0.0,1.0)

static func description(value: Dictionary) -> String:
	if not value.get("known",false): return "群体劳力未知：缺少人口来源，暂按产业配置基准。"
	return "群体劳力可用能力%d%%（按城内人口四成估算，具名人物不重复计入）；驻军支应占用%d份劳力，每20名驻军折1份，行军部队不占用出发地。" % [roundi(factor(value)*100),int(value.military_support)]

static func validate(raw, node: String, day: int, value: Variant) -> Dictionary:
	if not value is Dictionary or value.size()!=8 or not value.get("known") is bool or not value.get("source_ref") is String or not value.get("named_people") is Array or not value.get("forces") is Array: return Contract.fail("群体劳力快照结构无效")
	for key in ["movement_count","baseline_workers","available_workers","military_support"]:
		if not Contract.amount(value.get(key)): return Contract.fail("劳力数量无效")
	if int(value.movement_count)>raw.flags.get(Population.KEY,{}).size(): return Contract.fail("劳力迁居序号超出来源")
	var counts: Dictionary=Population.at_node(raw,node,day,int(value.movement_count))
	if counts.is_empty():
		return {"ok":true} if not value.known and value.source_ref=="" and value.named_people.is_empty() and value.forces.is_empty() and value.baseline_workers==0 and value.available_workers==0 and value.military_support==0 else Contract.fail("无人口来源不能生成已知劳力")
	if not value.known or value.source_ref!=counts.source_ref: return Contract.fail("劳力人口来源不符")
	var seen := {}
	for person in value.named_people:
		if not person is String or not raw.character_states.has(person) or seen.has(person): return Contract.fail("具名人物来源缺失或重复")
		seen[person]=true
	seen.clear()
	var support := 0
	for force in value.forces:
		if not force is Dictionary or force.size()!=2 or not force.get("force_id") is String or not raw.military_forces.has(force.force_id) or seen.has(force.force_id) or not Contract.amount(force.get("troops"),true): return Contract.fail("驻军支应来源无效")
		seen[force.force_id]=true
		support+=int(ceil(float(force.troops)/20.0))
	if int(value.military_support)!=support or int(value.baseline_workers)!=_workers(int(counts.baseline_city_population),value.named_people.size()) or int(value.available_workers)!=maxi(0,_workers(int(counts.city_population),value.named_people.size())-support): return Contract.fail("可用劳力与人口、具名人物及驻军支应不符")
	return {"ok":true}
