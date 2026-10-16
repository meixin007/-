extends RefCounted

class_name InformationPropagationService

const BoundedValueValidatorScript = preload("res://scripts/core/bounded_value_validator.gd")

func create_fact(state, raw_fact: Variant) -> Dictionary:
	if state == null:
		return _fail("missing state")
	var validation := BoundedValueValidatorScript.validate_and_copy_dictionary(raw_fact, "information fact")
	if not validation.get("ok", false):
		return validation
	var fact: Dictionary = validation.value
	var fact_id := str(fact.get("fact_id", "")).strip_edges()
	var truth_payload: Variant = fact.get("truth_payload", null)
	var holders: Variant = fact.get("holders", null)
	if fact_id.is_empty() or not (truth_payload is Dictionary) or not (holders is Array) or holders.is_empty():
		return _fail("information fact requires fact_id, truth_payload, and holders")
	var context_validation := _source_context(fact.get("source_context", {}), "information source_context")
	if not context_validation.get("ok", false):
		return context_validation
	if str(fact.get("secrecy", "")).strip_edges().is_empty():
		return _fail("information fact requires secrecy")
	if state.information_truths.has(fact_id):
		return _fail("information fact already exists: " + fact_id)
	var holders_validation := _validate_string_array(holders, "holders")
	if not holders_validation.get("ok", false):
		return holders_validation
	var holder_ids: Array = holders_validation.value
	var stored_fact := {
		"fact_id": fact_id,
		"truth_payload": truth_payload.duplicate(true),
		"holder_ids": holder_ids,
		"secrecy": str(fact.get("secrecy")),
		"secrecy_lost": false,
		"created_day": int(state.current_day),
		"source_context": context_validation.value
	}
	var next_truths: Dictionary = state.information_truths.duplicate(true)
	next_truths[fact_id] = stored_fact
	var next_claims: Dictionary = state.information_claims.duplicate(true)
	var claims_for_fact: Dictionary = {}
	for actor_id in holder_ids:
		claims_for_fact[actor_id] = _claim(actor_id, truth_payload, "direct", context_validation.value, int(state.current_day))
	next_claims[fact_id] = claims_for_fact
	state.information_truths = next_truths
	state.information_claims = next_claims
	return {"ok": true, "fact": fact.duplicate(true)}

func transmit_fact(state, fact_id: String, raw_transmission: Variant) -> Dictionary:
	if state == null:
		return _fail("missing state")
	if not state.information_truths.has(fact_id):
		return _fail("unknown information fact: " + fact_id)
	var validation := BoundedValueValidatorScript.validate_and_copy_dictionary(raw_transmission, "information transmission")
	if not validation.get("ok", false):
		return validation
	var transmission: Dictionary = validation.value
	var from_actor_id := str(transmission.get("from_actor_id", "")).strip_edges()
	var to_actor_id := str(transmission.get("to_actor_id", "")).strip_edges()
	var channel := str(transmission.get("channel", "")).strip_edges()
	if from_actor_id.is_empty() or to_actor_id.is_empty() or channel.is_empty():
		return _fail("information transmission requires from_actor_id, to_actor_id, and channel")
	var current_claim := get_claim(state, fact_id, from_actor_id)
	if current_claim.is_empty():
		return _fail("transmitter does not hold a claim")
	var context_validation := _source_context(transmission.get("source_context", {}), "transmission source_context")
	if not context_validation.get("ok", false):
		return context_validation
	var watchers_validation := _validate_string_array(transmission.get("watched_by", []), "watched_by")
	if not watchers_validation.get("ok", false):
		return watchers_validation
	var omitted_fields_validation := _validate_string_array(transmission.get("omit_fields", []), "omit_fields")
	if not omitted_fields_validation.get("ok", false):
		return omitted_fields_validation
	var watchers: Array = watchers_validation.value
	var omitted_fields: Array = omitted_fields_validation.value
	var transmitted_payload: Dictionary = current_claim.get("payload", {}).duplicate(true)
	for field_name in omitted_fields:
		transmitted_payload.erase(field_name)
	var stored_transmission := {
		"fact_id": fact_id,
		"from_actor_id": from_actor_id,
		"to_actor_id": to_actor_id,
		"channel": channel,
		"watched_by": watchers,
		"omit_fields": omitted_fields.duplicate(true),
		"day": int(state.current_day),
		"source_occurrence_id": str(context_validation.value.get("context_id", "")),
		"source_context": context_validation.value
	}
	var next_claims: Dictionary = state.information_claims.duplicate(true)
	var claims_for_fact: Dictionary = next_claims.get(fact_id, {}).duplicate(true)
	claims_for_fact[to_actor_id] = _claim(to_actor_id, transmitted_payload, "relay", context_validation.value, int(state.current_day))
	next_claims[fact_id] = claims_for_fact
	var next_transmissions: Array = state.information_transmissions.duplicate(true)
	next_transmissions.append(stored_transmission)
	var next_notifications: Array = state.information_notifications.duplicate(true)
	next_notifications.append({"fact_id": fact_id, "actor_id": to_actor_id, "kind": "transmission", "day": int(state.current_day), "channel": channel})
	var next_truths: Dictionary = state.information_truths.duplicate(true)
	var stored_fact: Dictionary = next_truths[fact_id].duplicate(true)
	if not watchers.is_empty():
		stored_fact["secrecy_lost"] = true
	next_truths[fact_id] = stored_fact
	state.information_claims = next_claims
	state.information_transmissions = next_transmissions
	state.information_notifications = next_notifications
	state.information_truths = next_truths
	return {"ok": true, "transmission": transmission.duplicate(true), "record": stored_transmission.duplicate(true)}

func queue_dispatch(state, fact_id: String, sender: String, recipient: String) -> Dictionary:
	if state==null: return _fail("当前世界尚未就绪")
	var claim: Dictionary=get_claim(state,fact_id,sender)
	if claim.is_empty(): return _fail("寄信人尚未获知这份消息")
	if not state.character_states.has(sender) or not state.character_states.has(recipient): return _fail("寄信人或收件人不存在")
	var origin: String=str(state.character_states[sender].get("location_id",""))
	if origin.is_empty() or str(state.character_states[recipient].get("location_id","")).is_empty(): return _fail("暂缺可用投递地点，请待联络恢复后重试")
	for entry in state.information_pending_transmissions:
		if entry.get("fact_id")==fact_id and entry.get("transmission",{}).get("to_actor_id")==recipient: return _fail("这份消息已寄往该人物，请等待送达")
	var source: Dictionary=claim.get("source_context",{}).duplicate(true)
	var checked := _source_context(source,"dispatch source")
	if not checked.ok: return checked
	state.information_pending_transmissions.append({"fact_id":fact_id,"transmission":{"from_actor_id":sender,"to_actor_id":recipient,"channel":"courier_dispatch","source_context":source},"transport":{"recipient_id":recipient,"current_node_id":origin,"status":"in_transit","last_advanced_day":int(state.current_day),"leg":{},"travel_log":[]}})
	var payload: Dictionary = claim.get("payload", {})
	var social: Dictionary = state.economic_contracts.get(payload.get("agreement_id", ""), {})
	var gift: Dictionary = state.economic_contracts.get(payload.get("delivery_id", ""), {})
	var kind := ""
	if social.get("contract_kind") == "social_agreement" and social.participant_ids.has(sender) and social.participant_ids.has(recipient): kind = "social_agreement"
	elif gift.get("contract_kind") == "gift_delivery" and [gift.sender_id, gift.carrier_id, gift.recipient_id].has(sender) and [gift.sender_id, gift.carrier_id, gift.recipient_id].has(recipient): kind = "gift_delivery"
	elif state.accountability_cases.get(payload.get("case_id", ""), {}).get("case_kind") == "criminal" and payload.get("social_event_kind") in ["verdict", "release_order", "legal_release"]: kind = "judicial_notice"
	if kind != "": state.information_pending_transmissions[-1].transport["report_kind"] = kind
	return {"ok":true,"fact_id":fact_id}

func settle(state) -> Dictionary:
	if state == null:
		return _fail("missing state")
	var propagated: Array = []
	var pending: Array = state.information_pending_transmissions.duplicate(true)
	var remaining: Array=[]
	for raw_entry in pending:
		if not (raw_entry is Dictionary):
			return _fail("pending information transmission must be a Dictionary")
		var entry: Dictionary = raw_entry
		if entry.has("transport"):
			preload("res://scripts/core/dispatch_transport.gd").advance(state,entry.transport)
			if entry.transport.status!="delivered":
				remaining.append(entry)
				continue
		var result := transmit_fact(state, str(entry.get("fact_id", "")), entry.get("transmission", {}))
		if not result.get("ok", false):
			return result
		propagated.append(result.get("record", {}).duplicate(true))
	state.information_pending_transmissions = remaining
	return {"ok": true, "transmissions": propagated}

func get_fact(state, fact_id: String) -> Dictionary:
	if state == null or not state.information_truths.has(fact_id):
		return {}
	return state.information_truths[fact_id].duplicate(true)

func get_claim(state, fact_id: String, actor_id: String) -> Dictionary:
	if state == null:
		return {}
	var claims_for_fact: Dictionary = state.information_claims.get(fact_id, {})
	return claims_for_fact.get(actor_id, {}).duplicate(true)

func get_transmission_records(state, fact_id: String) -> Array:
	if state == null:
		return []
	var records: Array = []
	for raw_record in state.information_transmissions:
		if raw_record is Dictionary and str(raw_record.get("fact_id", "")) == fact_id:
			records.append(raw_record.duplicate(true))
	return records

func _claim(actor_id: String, payload: Dictionary, confidence: String, source_context: Dictionary, day: int) -> Dictionary:
	return {"actor_id": actor_id, "payload": payload.duplicate(true), "confidence": confidence, "known_day": day, "source_context": source_context.duplicate(true)}

func _validate_string_array(raw_values: Variant, label: String) -> Dictionary:
	if not (raw_values is Array):
		return _fail(label + " must be an Array")
	var values: Array = raw_values
	if values.size() > BoundedValueValidatorScript.MAX_CONTAINER_SIZE:
		return _fail(label + " contains an oversized array")
	var copied: Array = []
	for raw_value in values:
		if typeof(raw_value) != TYPE_STRING:
			return _fail(label + " entries must be Strings")
		var value := str(raw_value).strip_edges()
		if value.is_empty() or value.length() > BoundedValueValidatorScript.MAX_KEY_LENGTH:
			return _fail(label + " entries must be nonblank bounded Strings")
		if not copied.has(value):
			copied.append(value)
	copied.sort()
	return {"ok": true, "value": copied}

func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}

func _source_context(raw: Variant, label: String) -> Dictionary:
	# A control observation references its actual report/fact. It creates no
	# obligation or dialogue memory, so do not fabricate those occurrence links.
	if raw is Dictionary and raw.get("context_kind") in ["control_observation","control_dispatch","office_observation"]:
		var checked := BoundedValueValidatorScript.validate_and_copy_dictionary(raw,label)
		if not checked.ok: return checked
		for key in ["context_id","related_report_id"]:
			if not raw.get(key) is String or raw[key].strip_edges().is_empty(): return _fail(label+" missing "+key)
		return checked
	return BoundedValueValidatorScript.validate_and_copy_occurrence_source_context(raw,label)
