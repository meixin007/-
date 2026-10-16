extends RefCounted
## Coarse use of original abilities, traits, condition and employment; no new meter.
const WEIGHTS={"farm":[0.20,0.70,0.10],"extraction":[0.30,0.60,0.10],"processing":[0.40,0.50,0.10],"trade":[0.60,0.20,0.20],"service":[0.50,0.35,0.15],"logistics":[0.30,0.50,0.20],"finance":[0.60,0.25,0.15]}
static func index(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and float(value)==floor(float(value)) and value>=0 and value<=100
static func validate_character(character: Dictionary) -> Dictionary:
	for field in ["stress","loyalty"]:
		if character.has(field) and not index(character[field]):return {"ok":false,"error":"原人物压力或忠诚状态必须在0至100以内"}
	if character.has("traits"):
		if not character.traits is Array or character.traits.size()>32:return {"ok":false,"error":"原人物品性资料结构无效"}
		for trait_id in character.traits:
			if not trait_id is String or trait_id.is_empty() or trait_id.length()>64:return {"ok":false,"error":"原人物品性资料无效"}
	return {"ok":true}
static func fit(stats: Dictionary, model: String) -> float:
	var weights: Array=WEIGHTS.get(model,WEIGHTS.service)
	return clampf(float(stats.get("finance",0))*weights[0]+float(stats.get("governance",0))*weights[1]+float(stats.get("diplomacy",0))*weights[2],0.0,100.0)
static func accepts(state, person: String, principal: String) -> Dictionary:
	var character: Dictionary=state.character_states.get(person,{})
	if int(character.get("loyalty",50))<30 and int(character.get("relationships",{}).get(principal,0)) < -20:return {"ok":false,"error":"负责人当前不愿承接新授权，请先协调关系或办理交接；旧雇约及债务保留"}
	return {"ok":true}
static func snapshot(state, shop: Dictionary, person: String) -> Dictionary:
	var character: Dictionary=state.character_states[person]
	var posts: Array=[]
	for office in state.office_state.values():
		if office.get("holder_id")==person and office.get("office_kind") in ["family","regional"]:posts.append(office.office_id)
	posts.sort()
	var traits: Array=character.get("traits",[])
	var impaired: bool=character.get("status") in ["wounded","injured","sick","ill"]
	var factor: float=(0.5 if impaired else 1.0)*(0.8 if int(character.get("stress",0))>=70 else 1.0)*(0.8 if posts.size()>1 else 1.0)
	var loss: int=loss_percent(traits)
	return {"version":1,"manager_id":person,"day":int(state.current_day),"condition":str(character.get("status","alive")),"stress":int(character.get("stress",0)),"office_refs":posts,"efficiency_factor":factor,"conduct_traits":traits.duplicate(),"loss_percent":loss,"source":"original_character_and_offices"}
static func loss_percent(traits: Array) -> int:
	return 0 if traits.has("honest") else 2 if traits.has("dishonest") or traits.has("deceitful") or traits.has("corrupt") else 0
static func validate(value: Variant, person: String, day: int) -> Dictionary:
	if not value is Dictionary or value.get("version")!=1 or value.get("manager_id")!=person or value.get("day")!=day or value.get("source")!="original_character_and_offices" or not value.get("condition") is String or not index(value.get("stress")) or not value.get("office_refs") is Array or value.office_refs.size()>256 or not index(value.get("loss_percent")) or int(value.loss_percent)>2:return {"ok":false,"error":"月結负责人状态来源或风险参数无效"}
	if not value.get("conduct_traits") is Array or not validate_character({"traits":value.conduct_traits}).ok or int(value.loss_percent)!=loss_percent(value.conduct_traits):return {"ok":false,"error":"月结经办风险与当时品性来源不符"}
	var factor: float=(0.5 if value.condition in ["wounded","injured","sick","ill"] else 1.0)*(0.8 if int(value.stress)>=70 else 1.0)*(0.8 if value.office_refs.size()>1 else 1.0)
	if not value.get("efficiency_factor") is float and not value.get("efficiency_factor") is int:return {"ok":false,"error":"负责人有效能力系数无效"}
	if not is_equal_approx(float(value.efficiency_factor),factor):return {"ok":false,"error":"负责人能力系数与当期伤病压力兼任不符"}
	var seen: Dictionary={}
	for ref in value.office_refs:
		if not ref is String or ref.is_empty() or seen.has(ref):return {"ok":false,"error":"负责人职责引用重复或无效"}
		seen[ref]=true
	return {"ok":true}
