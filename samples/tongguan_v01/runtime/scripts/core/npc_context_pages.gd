extends RefCounted
const Canonical = preload("res://scripts/core/canonical_json.gd")
const Contract = preload("res://scripts/core/npc_ai_state_contract.gd")
const PAGE_SIZE := 32
const TEXT_SIZE := 1024
const MAX_PAGES := Contract.MAX_CONTEXT_PAGES
const QUERY_FIELDS := ["name", "location_id", "asset_kind", "status", "action_kind"]
var source: Dictionary = {}
var binding: Dictionary = {}
var snapshot_hash := ""
var seen: Dictionary = {}
var page_size := PAGE_SIZE
var priority_keys: Dictionary = {}

func create(visible: Dictionary, request_id: String, epoch: String) -> Dictionary:
	source = visible.duplicate(true)
	binding = {"actor_id": visible.get("actor_id", ""), "request_id": request_id, "world_epoch": epoch}
	snapshot_hash = Canonical.hash_value({"binding": binding, "source": source}).get("hash", "")
	seen.clear()
	priority_keys = build_priority(source)
	page_size = PAGE_SIZE
	var result: Dictionary = preview(source, [], false, page_size, priority_keys)
	while JSON.stringify(result).length() > 30000 and page_size > 1:
		page_size = maxi(1, page_size / 4)
		result = preview(source, [], false, page_size, priority_keys)
	result["context_paging"] = {"snapshot_hash": snapshot_hash, "page_size": page_size, "max_extra_pages": MAX_PAGES, "query_fields": QUERY_FIELDS.duplicate()}
	return result

static func preview(value: Variant, path: Array, page_container: bool = true, width: int = PAGE_SIZE, priorities: Dictionary = {}) -> Variant:
	if value is Dictionary:
		var keys: Array = ordered_keys(value, path, priorities)
		var result := {}
		for key in keys.slice(0, width if page_container else keys.size()): result[key] = preview(value[key], path + [key], true, width, priorities)
		for key in ["character_id", "task_id", "asset_id", "contract_id", "account_id", "office_id"]:
			if value.get(key) is String: result[key] = value[key]
		if page_container and keys.size() > width: return {"page_ref": {"path": path, "total_count": keys.size(), "next_offset": width}, "preview": result}
		return result
	if value is Array:
		var result: Array = []
		for index in ordered_indices(value, path, priorities).slice(0, width): result.append(preview(value[index], path + [index], true, width, priorities))
		return {"page_ref": {"path": path, "total_count": value.size(), "next_offset": width}, "preview": result} if value.size() > width else result
	if value is String and value.length() > TEXT_SIZE: return {"page_ref": {"path": path, "total_count": value.length(), "next_offset": TEXT_SIZE}, "text_preview": value.left(TEXT_SIZE)}
	return value

static func ordered_keys(value: Dictionary, path: Array, priorities: Dictionary) -> Array:
	var keys: Array = value.keys()
	var ranks: Dictionary = priorities.get(path[0], {}) if path.size() == 1 else {}
	var fields: Array = []
	if path == ["survival_guidance"]: fields = ["needs_food", "daily_ration_units", "available_ration_units", "urgency", "source_id", "ration_account_id"]
	elif path.size() == 2 and path[0] == "own_contracts": fields = ["contract_id", "status", "contract_kind", "purpose", "terms", "terms_version", "accepted_versions", "known_day"]
	elif path.size() == 2 and path[0] == "own_tasks": fields = ["task_id", "status", "due_day", "steps", "id", "completed_day"]
	elif path.size() == 2 and path[0] == "employment_guidance": fields = ["terms_version", "blockers", "wage_amount", "period_days", "work_days_per_week", "travel", "qualification", "source_refs"]
	elif path.size() == 2 and path[0] == "decision_guidance": fields = ["goal_kind", "urgency", "source_refs", "feasible_actions", "continuation", "blockers", "due_day"]
	elif path.size() == 2 and path[0] == "public_work_guidance": fields = ["qualification", "blockers", "wage_amount", "period_days", "work_days_per_week", "application", "continuation", "source_refs"]
	if not fields.is_empty():
		ranks = {}
		for index in fields.size(): ranks[fields[index]] = index
	keys.sort_custom(func(a, b): return int(ranks.get(a, 1000000000)) < int(ranks.get(b, 1000000000)) if ranks.get(a, 1000000000) != ranks.get(b, 1000000000) else str(a) < str(b))
	return keys

static func ordered_indices(value: Array, path: Array, priorities: Dictionary) -> Array:
	var indices: Array = range(value.size())
	var ranks: Dictionary = priorities.get(path[0], {}) if path.size() == 1 else {}
	if not ranks.is_empty(): indices.sort_custom(func(a, b): return int(ranks.get(a, a)) < int(ranks.get(b, b)))
	return indices

static func contract_priority(row: Dictionary, actor: String) -> int:
	if row.get("contract_kind") == "social_agreement":
		if row.get("status") in ["proposed", "countered"] and row.get("accepted_versions", {}).get(actor) != row.get("terms_version"): return 0
		if row.get("status") == "accepted": return 1
		if row.get("status") in ["proposed", "countered"]: return 2
	if row.get("contract_kind") == "gift_delivery" and row.get("status") == "awaiting_response" and row.get("recipient_id") == actor: return 0
	if row.get("status") in ["active", "working", "en_route", "awaiting_reception"]: return 2
	return 3

static func build_priority(visible: Dictionary) -> Dictionary:
	# Rank only the already-authorized snapshot, never consult live world state.
	var actor: String = visible.get("actor_id", "")
	var contracts: Dictionary = visible.get("own_contracts", {})
	var keys: Array = contracts.keys()
	keys.sort_custom(func(a, b):
		var left: int = contract_priority(contracts[a], actor)
		var right: int = contract_priority(contracts[b], actor)
		if left != right: return left < right
		var day_a: int = int(contracts[a].get("known_day", contracts[a].get("day", 0)))
		var day_b: int = int(contracts[b].get("known_day", contracts[b].get("day", 0)))
		return day_a > day_b if day_a != day_b else str(a) < str(b))
	var result := {"own_contracts": {}, "own_tasks": {}, "known_characters": {actor: 0}, "travel_destinations": {}, "information_claims": {}, "decision_guidance": {}}
	for index in keys.size():
		var id: String = keys[index]
		result.own_contracts[id] = index
		if contract_priority(contracts[id], actor) > 1: continue
		for person in contracts[id].get("participant_ids", []):
			if not result.known_characters.has(person): result.known_characters[person] = result.known_characters.size()
	var location: String = visible.get("self_profile", {}).get("location_id", "")
	_prioritize_known(result, visible, "travel_destinations", location)
	# Use only the destination already communicated in this observer's own
	# authorized offer/guidance. Sorting reveals no new world objects.
	for id in keys:
		if contract_priority(contracts[id], actor) > 1: continue
		_prioritize_known(result, visible, "travel_destinations", contracts[id].get("terms", {}).get("destination_id", ""))
		var scope: Dictionary = contracts[id].get("employment_offer", {}).get("office", {}).get("scope_ref", {})
		if scope.get("entity_kind") == "location": _prioritize_known(result, visible, "travel_destinations", scope.get("entity_id", ""))
	for row in visible.get("employment_guidance", []) + visible.get("public_work_guidance", []):
		var travel: Dictionary = row.get("travel", {})
		if travel.get("known", false) and travel.get("required", false): _prioritize_known(result, visible, "travel_destinations", travel.get("destination_id", ""))
	var claims: Dictionary = visible.get("information_claims", {})
	var claim_keys: Array = claims.keys()
	claim_keys.sort_custom(func(a, b):
		var day_a: int = int(claims[a].get("known_day", 0))
		var day_b: int = int(claims[b].get("known_day", 0))
		return day_a > day_b if day_a != day_b else str(a) < str(b))
	for index in claim_keys.size(): result.information_claims[claim_keys[index]] = index
	var goals: Array = visible.get("decision_guidance", [])
	var goal_indices: Array = range(goals.size())
	var urgency := {"next_meal": 0, "due": 1, "response_pending": 2, "scheduled": 3, "pantry_sufficient": 4, "longer_term": 5}
	goal_indices.sort_custom(func(a, b):
		var rank_a: int = int(urgency.get(goals[a].get("urgency", ""), 10))
		var rank_b: int = int(urgency.get(goals[b].get("urgency", ""), 10))
		return rank_a < rank_b if rank_a != rank_b else a < b)
	for index in goal_indices.size(): result.decision_guidance[goal_indices[index]] = index
	var tasks: Array = visible.get("own_tasks", [])
	var indices: Array = range(tasks.size())
	indices.sort_custom(func(a, b):
		var done_a: bool = tasks[a].get("status") in ["completed", "cancelled", "failed"]
		var done_b: bool = tasks[b].get("status") in ["completed", "cancelled", "failed"]
		if done_a != done_b: return not done_a
		var day_a: int = int(tasks[a].get("completed_day", 0)) if done_a else int(tasks[a].get("due_day", 1000000000))
		var day_b: int = int(tasks[b].get("completed_day", 0)) if done_b else int(tasks[b].get("due_day", 1000000000))
		if day_a != day_b: return day_a > day_b if done_a else day_a < day_b
		return a < b)
	for index in indices.size(): result.own_tasks[indices[index]] = index
	for index in indices:
		if tasks[index].get("status") in ["completed", "cancelled", "failed"]: continue
		for step in tasks[index].get("steps", []):
			if not step is Dictionary: continue
			if step.get("status") == "completed": continue
			_prioritize_known(result, visible, "travel_destinations", step.get("parameters", {}).get("destination_id", ""))
	return result

static func _prioritize_known(priorities: Dictionary, visible: Dictionary, collection: String, key: Variant) -> void:
	if not key is String or key.is_empty() or not visible.get(collection, {}).has(key): return
	if not priorities[collection].has(key): priorities[collection][key] = priorities[collection].size()

static func parse_request(value: Variant) -> Dictionary:
	if not value is Dictionary: return Contract.fail("invalid NPC page control")
	var required := ["schema_version", "kind", "snapshot_hash", "path", "offset"]
	if not Contract.exact(value, required + (["query"] if value.has("query") else [])): return Contract.fail("invalid NPC page fields")
	if value.schema_version != 2 or value.kind != "context_request" or not Contract.hash_string(value.snapshot_hash) or not value.path is Array or value.path.is_empty() or value.path.size() > 12 or not Contract.whole(value.offset, 0): return Contract.fail("invalid NPC page position")
	for part in value.path:
		if not Contract.text_id(part) and not Contract.whole(part, 0): return Contract.fail("invalid NPC page path")
	if value.has("query"):
		if not value.query is Dictionary or value.query.is_empty(): return Contract.fail("invalid NPC page filter")
		for key in value.query:
			if key not in QUERY_FIELDS or not Contract.text_id(value.query[key]): return Contract.fail("unauthorized NPC page filter")
	return {"ok": true, "context_request": value.duplicate(true)}

func read(request: Dictionary, actor: String, request_id: String, epoch: String) -> Dictionary:
	var parsed := parse_request(request)
	if not parsed.ok: return parsed
	if binding != {"actor_id": actor, "request_id": request_id, "world_epoch": epoch} or request.snapshot_hash != snapshot_hash: return Contract.fail("NPC snapshot binding changed")
	var signature: String = Canonical.hash_value(request).hash
	if seen.has(signature) or seen.size() >= MAX_PAGES: return Contract.fail("NPC page repeated or limit reached")
	var value: Variant = source
	for part in request.path:
		if value is Dictionary and part is String and value.has(part): value = value[part]
		elif value is Array and Contract.whole(part, 0) and int(part) < value.size(): value = value[int(part)]
		else: return Contract.fail("NPC page is outside visible snapshot")
	var original_indices: Array = []
	if value is Array:
		original_indices = ordered_indices(value, request.path, priority_keys)
		var ordered: Array = []
		for index in original_indices: ordered.append(value[index])
		value = ordered
	if request.has("query"):
		if value is Dictionary:
			var filtered := {}
			for key in value:
				if _matches(value[key], request.query): filtered[key] = value[key]
			value = filtered
		elif value is Array:
			var filtered: Array = []
			var filtered_indices: Array = []
			for index in value.size():
				if _matches(value[index], request.query):
					filtered.append(value[index])
					filtered_indices.append(original_indices[index])
			value = filtered
			original_indices = filtered_indices
		else: return Contract.fail("NPC filter requires a record collection")
	var offset := int(request.offset)
	var total: int = value.length() if value is String else (value.size() if value is Dictionary or value is Array else 0)
	if offset >= total and not (offset == 0 and total == 0 and (value is Dictionary or value is Array)): return Contract.fail("NPC page is outside collection")
	var end := mini(total, offset + (TEXT_SIZE if value is String else page_size))
	var page := {"snapshot_hash": snapshot_hash, "path": request.path.duplicate(), "offset": offset, "total_count": total, "next_offset": end if end < total else -1}
	if request.has("query"): page["query"] = request.query.duplicate(true)
	if value is Dictionary:
		var keys: Array = ordered_keys(value, request.path, priority_keys)
		page["values"] = {}
		for key in keys.slice(offset, end): page.values[key] = preview(value[key], request.path + [key], true, page_size, priority_keys)
	elif value is Array:
		page["values"] = []
		for index in range(offset, end): page.values.append(preview(value[index], request.path + [original_indices[index] if not original_indices.is_empty() else index], true, page_size, priority_keys))
	elif value is String: page["text"] = value.substr(offset, TEXT_SIZE)
	else: return Contract.fail("NPC page is not a collection")
	seen[signature] = true
	return {"ok": true, "page": page}

static func _matches(row: Variant, query: Dictionary) -> bool:
	if not row is Dictionary: return false
	for field in query:
		if row.get(field) != query[field]: return false
	return true
