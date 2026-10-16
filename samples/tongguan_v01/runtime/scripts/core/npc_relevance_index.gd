extends RefCounted

# A disposable index of derived contributions, never a source of world effects.
# Compare the small input rows as well as world identity: direct rule edits need
# not have committed a revision yet, and a restored world must rebuild the index.
static var _world: WeakRef
static var _scope: String = ""
static var _owner_hash: String = ""
static var _entries: Dictionary = {}
const Canonical = preload("res://scripts/core/canonical_json.gd")

static func collect(state, world_epoch: String = "") -> Dictionary:
	var player: String = state.player_character_id
	var owner: Dictionary = state.character_states[player]
	var basis := {"player":player,"clan":owner.get("clan_id",""),"relationships":owner.get("relationships",{}).duplicate(true)}
	var basis_hash: String = Canonical.hash_value(basis).hash
	var different_world: bool = _scope != world_epoch if world_epoch != "" else (_scope != "" or _world == null or _world.get_ref() != state)
	if different_world or _owner_hash != basis_hash:
		_world = weakref(state); _scope = world_epoch; _owner_hash = basis_hash; _entries = {}
	var sources := {}
	for id in state.character_states:
		var person: Dictionary = state.character_states[id]
		sources["character:"+id] = {"kind":"character","id":id,"clan":person.get("clan_id",""),"patron":person.get("patron_id",""),"allegiance":person.get("allegiance",{}).get("target_id","")}
	for i in state.active_tasks.size():
		var row: Dictionary = state.active_tasks[i]
		sources["task:"+str(row.get("task_id",row.get("id",i)))] = _pick(row,["principal_id","executor_id"])
		sources["task:"+str(row.get("task_id",row.get("id",i)))]["kind"] = "task"
	for id in state.economic_contracts:
		sources["contract:"+id] = _pick(state.economic_contracts[id],["principal_id","employee_id","carrier_id","recipient_id","sender_id","participants","participant_ids","arrears","contract_kind","status"])
		sources["contract:"+id]["kind"] = "contract"
	for id in state.accountability_cases:
		var row: Dictionary = state.accountability_cases[id]
		var parties: Array = row.get("participant_ids",[]) + row.get("involved_character_ids",[]) + row.get("subject_ids",[]) + row.get("victim_kin_ids",[]) + [row.get("subject_id",""),row.get("jurisdiction_holder_id",""),row.get("detention",{}).get("custodian_id",""),state.office_state.get(row.get("jurisdiction_office_id",""),{}).get("holder_id","")]
		sources["case:"+id] = {"kind":"case","parties":parties,"status":row.get("status","")}
	for i in state.active_events.size():
		var row: Dictionary = state.active_events[i]
		var key := "event:"+str(row.get("id",i))
		sources[key] = _pick(row,["related_character_id","participant_ids","npc_ai_urgent"]); sources[key]["kind"] = "event"
	for id in state.active_dialogue_sessions:
		sources["dialogue:"+id] = _pick(state.active_dialogue_sessions[id],["status","player_id","npc_id"]); sources["dialogue:"+id]["kind"] = "dialogue"
	for id in state.management_assets:
		sources["asset:"+id] = _pick(state.management_assets[id],["owner_ref","custodian_ref"]); sources["asset:"+id]["kind"] = "asset"
	var scores := {}
	var urgent := {}
	var recomputed := 0
	for key in sources:
		var source_hash: String = Canonical.hash_value(sources[key]).hash
		if not _entries.has(key) or _entries[key].input_hash != source_hash:
			_entries[key] = {"input_hash":source_hash,"contribution":_contribution(sources[key],basis)}
			recomputed += 1
		var contribution: Dictionary = _entries[key].contribution
		for id in contribution.scores:
			for dimension in contribution.scores[id]: _add(scores,id,dimension,contribution.scores[id][dimension])
		for id in contribution.urgent: urgent[id] = true
	for key in _entries.keys():
		if not sources.has(key): _entries.erase(key)
	return {"ok":true,"scores":scores,"urgent":urgent,"recomputed":recomputed,"source_count":sources.size()}

static func _contribution(row: Dictionary, basis: Dictionary) -> Dictionary:
	var scores := {}
	var urgent := {}
	var player: String = basis.player
	match row.kind:
		"character":
			if basis.relationships.has(row.id): _add(scores,row.id,"structure",20)
			if (basis.clan != "" and basis.clan == row.clan) or row.patron == player or row.allegiance == player: _add(scores,row.id,"structure",35)
		"task":
			if row.get("principal_id") == player or row.get("executor_id") == player:
				for id in [row.get("principal_id",""),row.get("executor_id","")]: _add(scores,id,"dependency",30)
		"contract":
			if row.get("principal_id") == player or row.get("employee_id") == player or row.get("participants",[]).has(player) or row.get("participant_ids",[]).has(player) or row.get("sender_id") == player:
				for id in [row.get("principal_id",""),row.get("employee_id",""),row.get("carrier_id",""),row.get("recipient_id","")] + row.get("participants",[]) + row.get("participant_ids",[]):
					_add(scores,id,"dependency",30); _add(scores,id,"impact",25 if int(row.get("arrears",0))>0 else 10)
					if row.get("contract_kind") == "social_agreement" and row.get("status") in ["proposed","countered","accepted"]: urgent[id] = true
		"case":
			if row.parties.has(player) or row.parties.any(func(id):return basis.relationships.has(id)):
				for id in row.parties:
					_add(scores,id,"dependency",30); _add(scores,id,"impact",25)
					if row.status not in ["closed","resolved"]: urgent[id] = true
		"event":
			if row.get("related_character_id") == player or row.get("participant_ids",[]).has(player):
				for id in row.get("participant_ids",[]):
					_add(scores,id,"dependency",30); _add(scores,id,"impact",25)
					if row.get("npc_ai_urgent",false): urgent[id] = true
		"dialogue":
			if row.get("status") == "active" and row.get("player_id",player) == player: urgent[row.get("npc_id","")] = true
		"asset":
			var owner: Dictionary = row.get("owner_ref",{})
			var custodian: Dictionary = row.get("custodian_ref",{})
			if owner.get("entity_id") in [player,basis.clan] and custodian.get("entity_kind") == "character": _add(scores,str(custodian.get("entity_id","")),"dependency",30)
	return {"scores":scores,"urgent":urgent}

static func _pick(row: Dictionary, fields: Array) -> Dictionary:
	var result := {}
	for field in fields:
		if row.has(field):
			var value: Variant = row[field]
			result[field] = value.duplicate(true) if value is Dictionary or value is Array else value
	return result

static func _add(scores: Dictionary, id: String, dimension: String, amount: int) -> void:
	if id.is_empty(): return
	if not scores.has(id): scores[id] = {}
	scores[id][dimension] = maxi(int(scores[id].get(dimension,0)),amount)
