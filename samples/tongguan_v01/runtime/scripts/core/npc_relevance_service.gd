extends RefCounted

const Contract = preload("res://scripts/core/npc_ai_state_contract.gd")

static func refresh_basis(state, world_epoch: String) -> Dictionary:
	# Only the derived contributions and the inputs actually consumed below
	# decide whether focus needs another transaction. Personal cash remains an
	# opportunity/read-set input even when it leaves these contributions intact.
	var indexed: Dictionary = preload("res://scripts/core/npc_relevance_index.gd").collect(state, world_epoch)
	var actors := {}
	for id in indexed.scores.keys() + indexed.urgent.keys() + state.npc_ai_runtime.actors.keys():
		if actors.has(id): continue
		var person: Dictionary = state.character_states.get(id, {})
		var row: Dictionary = state.npc_ai_runtime.actors.get(id, {})
		var inputs := {"exists": state.character_states.has(id), "status": person.get("status", "")}
		for field in ["mode", "score", "pending_request_id", "below_since_day", "cooldown_until_day", "waiting_since_day", "model_service_order"]:
			inputs[field] = row.get(field)
		actors[id] = inputs
	return {"player": state.player_character_id, "day": state.current_day, "scores": indexed.scores, "urgent": indexed.urgent, "actors": actors}

func update(state, max_focus: int = 8, world_epoch: String = "") -> Dictionary:
	if state == null or not state.character_states.has(state.player_character_id) or max_focus < 0 or max_focus > 8: return Contract.fail("invalid relevance world or capacity")
	var player: String = state.player_character_id
	var indexed: Dictionary = preload("res://scripts/core/npc_relevance_index.gd").collect(state, world_epoch)
	var scores: Dictionary = indexed.scores
	var urgent: Dictionary = indexed.urgent
	var candidates: Array = []
	var runtime: Dictionary = state.npc_ai_runtime
	for id in scores.keys() + urgent.keys():
		if id == player or not state.character_states.has(id) or candidates.has(id): continue
		candidates.append(id)
	for id in runtime.actors:
		if not candidates.has(id) and id != player: candidates.append(id)
	var eligible: Array = []
	for id in candidates:
		if not runtime.actors.has(id): runtime.actors[id] = Contract.default_actor(state.current_day)
		var row: Dictionary = runtime.actors[id]
		var dims: Dictionary = scores.get(id, {})
		var score := 0
		for value in dims.values(): score += int(value)
		row.score = mini(100, score)
		if urgent.has(id): row.score = maxi(row.score, 60)
		if row.score < 35:
			if row.below_since_day < 0: row.below_since_day = state.current_day
		else: row.below_since_day = -1
		var alive: bool = state.character_states[id].get("status") not in ["dead", "deceased", "executed", "missing"]
		if alive and (row.score >= 60 or (row.mode == "focus_model" and row.below_since_day >= 0 and state.current_day - row.below_since_day < 3) or (row.mode == "focus_model" and row.score >= 35)) and state.current_day >= row.cooldown_until_day: eligible.append(id)
	sort_candidates(state, eligible, urgent)
	var focus: Array = eligible.slice(0, max_focus)
	for id in candidates:
		var row: Dictionary = runtime.actors[id]
		var previous: String = row.mode
		row.mode = "focus_model" if focus.has(id) else ("related_rules" if row.score > 0 else "background")
		if previous == "focus_model" and row.mode != "focus_model" and row.pending_request_id != "":
			var record: Dictionary = state.npc_decision_records[row.pending_request_id]
			record.status = "superseded"
			record.resolved_day = state.current_day
			row.pending_request_id = ""
	return {"ok": true, "focus_ids": focus, "candidate_count": candidates.size()}

static func sort_candidates(state, ids: Array, urgent: Dictionary) -> void:
	ids.sort_custom(func(a, b):
		var left: Dictionary = state.npc_ai_runtime.actors[a]
		var right: Dictionary = state.npc_ai_runtime.actors[b]
		if (left.pending_request_id != "") != (right.pending_request_id != ""): return left.pending_request_id != ""
		var left_aged: bool = state.current_day - int(left.waiting_since_day) >= 3
		var right_aged: bool = state.current_day - int(right.waiting_since_day) >= 3
		if left_aged != right_aged: return left_aged
		if urgent.has(a) != urgent.has(b): return urgent.has(a)
		if left.waiting_since_day != right.waiting_since_day: return left.waiting_since_day < right.waiting_since_day
		if left.model_service_order != right.model_service_order: return left.model_service_order < right.model_service_order
		if left.score != right.score: return left.score > right.score
		return a < b
	)

static func model_queue(state, world_epoch: String) -> Array:
	var ids: Array = state.npc_ai_runtime.actors.keys().filter(func(id):
		var row: Dictionary = state.npc_ai_runtime.actors[id]
		return id != state.player_character_id and row.mode == "focus_model" and not preload("res://scripts/core/npc_decision_opportunity.gd").next_slot(state, id).is_empty()
	)
	if ids.is_empty(): return ids
	var indexed: Dictionary = preload("res://scripts/core/npc_relevance_index.gd").collect(state, world_epoch)
	sort_candidates(state, ids, indexed.urgent)
	return ids

static func _add(scores: Dictionary, id: String, dimension: String, amount: int) -> void:
	if id.is_empty(): return
	if not scores.has(id): scores[id] = {}
	scores[id][dimension] = maxi(int(scores[id].get(dimension, 0)), amount)
