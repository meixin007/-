extends RefCounted
const KIND := "send_control_dispatch"

static func project(state, viewer: String, nodes: Array) -> Dictionary:
	var result := {"messages":[],"contacts":[],"pending":[]}
	var contacts: Dictionary=state.character_states.get(viewer,{}).get("relationships",{})
	var ids: Array=contacts.keys(); ids.sort()
	for id in ids:
		if id==viewer or not state.character_states.has(id): continue
		result.contacts.append({"id":id,"name":str(state.character_states[id].get("name",id))})
	var newest := {}
	for fact_id in state.information_claims:
		var claim: Dictionary=state.information_claims[fact_id].get(viewer,{})
		var payload: Dictionary=claim.get("payload",{})
		if payload.get("kind") not in ["node_control","office_observation"] or not nodes.has(payload.get("target_node_id")): continue
		if not payload.has("observed_day"): continue
		if payload.kind=="node_control" and not payload.has("visible_faction"): continue
		if payload.kind=="office_observation" and not payload.get("record") is Dictionary: continue
		var node: String=payload.target_node_id
		var key: String=node if payload.kind=="node_control" else "office:"+str(payload.get("office_id",""))
		var category: String="控制消息" if payload.kind=="node_control" else "任职公文"
		var name: String=str(state.local_node_state.get(node,{}).get("name",node)) if payload.kind=="node_control" else str(payload.record.get("office",{}).get("name","任职"))
		if not newest.has(key) or int(payload.observed_day)>int(newest[key].observed_day): newest[key]={"fact_id":fact_id,"node_id":node,"observed_day":int(payload.observed_day),"category":category,"label":"%s · 第%d日%s" % [name,int(payload.observed_day),category]}
	for node in newest: result.messages.append(newest[node])
	result.messages.sort_custom(func(a,b): return a.fact_id<b.fact_id)
	for entry in state.information_pending_transmissions:
		var transmission: Dictionary=entry.get("transmission",{})
		if transmission.get("from_actor_id")!=viewer: continue
		var claim: Dictionary=state.information_claims.get(entry.get("fact_id"),{}).get(viewer,{})
		if not nodes.has(claim.get("payload",{}).get("target_node_id")): continue
		var recipient: String=str(transmission.get("to_actor_id",""))
		result.pending.append("寄往%s：在途，待送达" % state.character_states.get(recipient,{}).get("name",recipient))
	return result

static func apply(state, params: Dictionary, principal: String, executor: String) -> Dictionary:
	if principal!=executor: return {"ok":false,"error":"控制消息须由持有人本人寄送"}
	var recipient: String=str(params.get("recipient_id",""))
	if not state.character_states[principal].get("relationships",{}).has(recipient): return {"ok":false,"error":"尚无该人物的联络关系"}
	var fact: String=str(params.get("fact_id",""))
	var claim: Dictionary=state.information_claims.get(fact,{}).get(principal,{})
	if claim.get("payload",{}).get("kind") not in ["node_control","office_observation"]: return {"ok":false,"error":"未持有该地区消息"}
	var result: Dictionary=preload("res://scripts/core/information_propagation_service.gd").new().queue_dispatch(state,fact,principal,recipient)
	if result.ok: result["result_ref"] = fact
	return result
