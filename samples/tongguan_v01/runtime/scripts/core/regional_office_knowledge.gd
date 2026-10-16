extends RefCounted
const KEY := "regional_office_observations"
const FIELDS := ["office_id","name","holder_id","status","office_kind","branch","scope_ref","jurisdiction"]

static func _capture(state, id: String) -> Dictionary:
	var office: Dictionary=state.office_state[id]
	var snapshot := {}
	for key in FIELDS:
		if office.has(key): snapshot[key]=office[key]
	var holder: String=str(office.get("holder_id",""))
	var person: Dictionary=state.character_states.get(holder,{})
	return {"office":snapshot.duplicate(true),"holder":{"id":holder,"name":str(person.get("name",holder)),"status":str(person.get("status",""))},"observed_day":int(state.current_day),"source":"local_observation"}

static func seed(state) -> void:
	if str(state.flags.get("campaign_id",""))!=preload("res://scripts/domain/current_campaign.gd").CAMPAIGN_ID: return
	var records := {}
	for id in state.office_state:
		var record: Dictionary=_capture(state,id)
		record.source="opening_public_register"
		records[id]=record
	state.flags[KEY]={str(state.player_character_id):records}

static func observe_local(state) -> Dictionary:
	if str(state.flags.get("campaign_id",""))!=preload("res://scripts/domain/current_campaign.gd").CAMPAIGN_ID: return {"ok":true}
	var viewer: String=state.player_character_id
	var location: String=str(state.character_states.get(viewer,{}).get("location_id",""))
	if location.is_empty(): return {"ok":true}
	if not state.flags.has(KEY): state.flags[KEY]={}
	if not state.flags[KEY].has(viewer): state.flags[KEY][viewer]={}
	for id in state.office_state:
		var office: Dictionary=state.office_state[id]
		if office.get("office_kind")!="regional": continue
		if office.get("scope_ref",{}).get("entity_id")!=location: continue
		state.flags[KEY][viewer][id]=_capture(state,id)
		var record: Dictionary=state.flags[KEY][viewer][id]
		var fact_id := "office_observation:%s:%s:%d:%s" % [viewer,id,int(state.current_day),str(hash(var_to_str(record.office)+var_to_str(record.holder)))]
		if state.information_truths.has(fact_id): continue
		var fact: Dictionary=preload("res://scripts/core/information_propagation_service.gd").new().create_fact(state,{"fact_id":fact_id,"truth_payload":{"kind":"office_observation","office_id":id,"target_node_id":location,"observed_day":int(state.current_day),"record":record.duplicate(true)},"holders":[viewer],"secrecy":"local_office_observation","source_context":{"context_id":fact_id,"context_kind":"office_observation","related_report_id":"office_register:"+viewer+":"+id}})
		if not fact.ok: return fact
	return {"ok":true}

static func view(state, viewer: String = "") -> Dictionary:
	if viewer.is_empty(): viewer=str(state.player_character_id)
	var offices := {}
	var characters := {}
	var records: Dictionary=state.flags.get(KEY,{}).get(viewer,{}).duplicate(true)
	for fact_id in state.information_claims:
		var claim: Dictionary=state.information_claims[fact_id].get(viewer,{})
		var payload: Dictionary=claim.get("payload",{})
		if payload.get("kind")!="office_observation" or not payload.get("office_id") is String or not payload.get("record") is Dictionary: continue
		var record: Dictionary=payload.record
		var checked: Dictionary=validate({"flags":{KEY:{viewer:{payload.office_id:record}}},"character_states":{viewer:{}},"current_day":state.current_day})
		if not checked.ok or claim.get("actor_id")!=viewer: continue
		if not preload("res://scripts/core/node_control_observation.gd").integer(claim.get("known_day")) or claim.known_day>state.current_day or claim.known_day<record.observed_day: continue
		if not records.has(payload.office_id) or int(record.observed_day)>int(records[payload.office_id].observed_day) or (int(record.observed_day)==int(records[payload.office_id].observed_day) and records[payload.office_id].source=="opening_public_register"):
			records[payload.office_id]=record.duplicate(true)
			records[payload.office_id].source="received_report"
		elif int(record.observed_day)==int(records[payload.office_id].observed_day) and records[payload.office_id].source=="received_report":
			var prior: Dictionary=records[payload.office_id]
			if prior.office!=record.office or prior.holder!=record.holder: prior["uncertain"]=true
	for id in records:
		var record: Dictionary=records[id]
		var office: Dictionary=record.office.duplicate(true)
		# JSON restores numeric values as floats; observation days remain whole days
		# at the read-model boundary, just as they are when first captured.
		office["observed_day"]=int(record.observed_day)
		office["knowledge_source"]=record.source
		office["observed_holder"]=record.holder.duplicate(true)
		if record.get("uncertain",false):
			office["knowledge_uncertain"]=true
			office["holder_id"]=""
			office["status"]="unconfirmed"
			office["observed_holder"]={}
		offices[id]=office
		if not record.get("uncertain",false) and not str(record.holder.id).is_empty(): characters[record.holder.id]=record.holder.duplicate(true)
	return {"office_state":offices,"character_states":characters}

static func validate(raw: Dictionary) -> Dictionary:
	if not raw.get("flags",{}) is Dictionary: return {"ok":false,"error":"任职观察标记无效"}
	var registry: Variant=raw.get("flags",{}).get(KEY,{})
	if not registry is Dictionary: return {"ok":false,"error":"任职观察登记无效"}
	for viewer in registry:
		if not raw.get("character_states",{}).has(viewer) or not registry[viewer] is Dictionary: return {"ok":false,"error":"任职观察者无效"}
		for id in registry[viewer]:
			if not id is String or id.is_empty(): return {"ok":false,"error":"任职观察岗位身份无效"}
			var row: Variant=registry[viewer][id]
			if not row is Dictionary or not row.get("office") is Dictionary or not row.get("holder") is Dictionary: return {"ok":false,"error":"任职观察结构无效"}
			if not preload("res://scripts/core/node_control_observation.gd").integer(row.get("observed_day")) or row.observed_day>raw.get("current_day",0): return {"ok":false,"error":"任职观察日期无效"}
			if row.get("source") not in ["opening_public_register","local_observation"]: return {"ok":false,"error":"任职观察来源无效"}
			for key in ["id","name","status"]:
				if not row.holder.get(key) is String: return {"ok":false,"error":"任职观察人物无效"}
			if row.holder.id!=str(row.office.get("holder_id","")): return {"ok":false,"error":"任职观察持有人不一致"}
			for key in ["office_id","name","holder_id","status","office_kind","branch"]:
				if row.office.has(key) and not row.office[key] is String: return {"ok":false,"error":"任职观察岗位字段无效"}
			if not row.office.get("scope_ref",{}) is Dictionary or not row.office.get("jurisdiction",[]) is Array: return {"ok":false,"error":"任职观察辖区结构无效"}
			for node in row.office.get("jurisdiction",[]):
				if not node is String: return {"ok":false,"error":"任职观察辖区身份无效"}
	return {"ok":true}
