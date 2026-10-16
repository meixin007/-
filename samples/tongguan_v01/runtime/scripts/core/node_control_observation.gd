extends RefCounted
## Dated, delivered control claims in the existing intelligence registry.
## Never reads current military control to repair a report.
const FACTIONS := ["tang_court","tang_rebel","foreign_huihe","disputed"]

static func observe_local(state) -> Dictionary:
	if str(state.flags.get("campaign_id",""))!=preload("res://scripts/domain/current_campaign.gd").CAMPAIGN_ID: return {"ok":true}
	var viewer: String=str(state.player_character_id)
	var location: String=str(state.character_states.get(viewer,{}).get("location_id",""))
	if viewer.is_empty() or location.is_empty(): return {"ok":true}
	var local: Dictionary=state.local_node_state.get(location,{})
	var strategic_id: String=str(local.get("strategic_node_id",location))
	var strategic: Dictionary=state.strategic_nodes.get(strategic_id,{})
	var faction: String=str(strategic.get("control_faction_id",local.get("dominant_faction","")))
	if faction=="yan_rebels": faction="tang_rebel"
	if faction not in FACTIONS: return {"ok":true}
	var day: int=int(state.current_day)
	var id := "local_control:%s:%s" % [viewer,location]
	state.active_intelligence_reports[id]={"report_id":id,"report_kind":"node_control","target_node_id":location,"recipient_id":viewer,"status":"verified","created_day":day,"verified_day":day,"delivered_day":day,"control_observation":{"schema_version":1,"observed_day":day,"visible_faction":faction,"source_ref":("strategic_node:"+strategic_id) if not strategic.is_empty() else ("local_node:"+location)}}
	var fact_id := "control_observation:%s:%s:%d" % [viewer,location,day]
	if not state.information_truths.has(fact_id):
		var source: String=state.active_intelligence_reports[id].control_observation.source_ref
		var fact: Dictionary=preload("res://scripts/core/information_propagation_service.gd").new().create_fact(state,{"fact_id":fact_id,"truth_payload":{"kind":"node_control","target_node_id":location,"observed_day":day,"visible_faction":faction,"source_ref":source},"holders":[viewer],"secrecy":"local_observation","source_context":{"context_id":fact_id,"context_kind":"control_observation","related_report_id":id}})
		if not fact.ok: return fact
	return {"ok":true}

static func validate_snapshot(raw: Dictionary) -> Dictionary:
	var registry: Variant=raw.get("active_intelligence_reports",{})
	if not registry is Dictionary: return {"ok":false,"error":"控制情报注册表类型无效"}
	for id in registry:
		var report: Variant=registry[id]
		if not report is Dictionary or report.get("report_kind")!="node_control": continue
		var recipient: Variant=report.get("recipient_id")
		if not recipient is String or not raw.get("character_states",{}).has(recipient): return {"ok":false,"error":"控制情报接收人无效"}
		# Pending arrival is permitted in saves, but future observation is not.
		if not integer(report.get("delivered_day")) or not integer(raw.get("current_day")): return {"ok":false,"error":"控制情报日期无效"}
		if report.get("status") not in ["active","verified","rejected"]: return {"ok":false,"error":"控制情报状态无效"}
		var candidate: Dictionary=report.duplicate(true)
		if candidate.status=="rejected": candidate.status="active"
		var parsed: Dictionary=parse(candidate,recipient,maxi(int(raw.current_day),int(report.delivered_day)))
		if parsed.is_empty() or report.get("report_id")!=id: return {"ok":false,"error":"控制情报记录或身份无效"}
		if report.created_day>raw.current_day or (report.status=="verified" and report.verified_day>raw.current_day): return {"ok":false,"error":"控制情报不能来自未来"}
	return {"ok":true}

static func integer(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and value>=0 and value<=2000000000 and float(value)==floor(float(value))

static func parse(raw: Variant, viewer: String, day: int) -> Dictionary:
	if not raw is Dictionary or raw.get("report_kind")!="node_control": return {}
	if viewer.is_empty() or raw.get("recipient_id")!=viewer: return {}
	if raw.get("status") not in ["active","verified"]: return {}
	for key in ["report_id","target_node_id"]:
		if not raw.get(key) is String or raw[key].strip_edges().is_empty(): return {}
	var payload: Variant=raw.get("control_observation")
	if not payload is Dictionary or payload.get("schema_version")!=1: return {}
	if payload.get("visible_faction") not in FACTIONS: return {}
	if not payload.get("source_ref") is String or payload.source_ref.strip_edges().is_empty(): return {}
	for key in ["created_day","delivered_day"]:
		if not integer(raw.get(key)): return {}
	if not integer(payload.get("observed_day")): return {}
	if payload.observed_day>raw.created_day or raw.created_day>raw.delivered_day or raw.delivered_day>day: return {}
	if raw.status=="verified":
		if not integer(raw.get("verified_day")) or raw.verified_day<raw.created_day or raw.verified_day>day: return {}
	return raw.duplicate(true)

static func project(state, viewer: String) -> Dictionary:
	var result := {}
	var raw_day: Variant=state.get("current_day")
	if not integer(raw_day): return result
	var day: int=int(raw_day)
	var reports: Variant=state.get("active_intelligence_reports")
	if not reports is Dictionary: return result
	reports=reports.duplicate(true)
	# Only this viewer's received claim is projected. Never fill omitted fields
	# from information_truths, even when the original fact is still available.
	var claims: Variant=state.get("information_claims")
	if claims is Dictionary:
		for fact_id in claims:
			if not claims[fact_id] is Dictionary: continue
			var claim: Variant=claims[fact_id].get(viewer,{})
			if not claim is Dictionary or claim.get("actor_id")!=viewer: continue
			var payload: Variant=claim.get("payload")
			if not payload is Dictionary or payload.get("kind")!="node_control": continue
			if claim.get("confidence") not in ["direct","relay"] or not integer(claim.get("known_day")): continue
			var id: String="claim:"+str(fact_id)
			reports[id]={"report_id":id,"report_kind":"node_control","recipient_id":viewer,"target_node_id":payload.get("target_node_id"),"status":"verified","created_day":payload.get("observed_day"),"verified_day":payload.get("observed_day"),"delivered_day":claim.known_day,"control_observation":{"schema_version":1,"observed_day":payload.get("observed_day"),"visible_faction":payload.get("visible_faction"),"source_ref":payload.get("source_ref")}}
	var groups := {}
	for raw in reports.values():
		var report: Dictionary=parse(raw,viewer,day)
		if report.is_empty(): continue
		var node: String=report.target_node_id
		if not groups.has(node): groups[node]=[]
		groups[node].append(report)
	for node in groups:
		var newest := -1
		for report in groups[node]: newest=maxi(newest,int(report.control_observation.observed_day))
		var factions: Array=[]
		var sources: Array=[]
		var ids: Array=[]
		var unverified := false
		for report in groups[node]:
			if report.control_observation.observed_day!=newest: continue
			if not factions.has(report.control_observation.visible_faction): factions.append(report.control_observation.visible_faction)
			if not sources.has(report.control_observation.source_ref): sources.append(report.control_observation.source_ref)
			ids.append(report.report_id)
			unverified=unverified or report.status!="verified"
		ids.sort(); sources.sort()
		var uncertain: bool=unverified or factions.size()!=1
		result[node]={"status":"rumor" if uncertain else ("confirmed" if newest==day else "delayed"),"visible_faction":"unknown" if uncertain else factions[0],"observed_day":newest,"latency_days":day-newest,"report_ids":ids,"source_refs":sources,"intelligence_note":"第 %d 日控制回报%s" % [newest,"，待核实或存在矛盾" if uncertain else "，已送达；不代表此后控制未变"]}
	return result
