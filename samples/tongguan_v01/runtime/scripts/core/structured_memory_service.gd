extends RefCounted

class_name StructuredMemoryService

const DayValueValidatorScript = preload("res://scripts/core/day_value_validator.gd")
const BoundedValueValidatorScript = preload("res://scripts/core/bounded_value_validator.gd")
const MAX_LIFECYCLE_HISTORY := 16
const MEMORY_FIELDS := ["id", "version", "history", "day", "created_day", "type", "memory_type", "participants", "source_id", "target_id", "related_event_id", "related_task_id", "location", "original_intent", "political_object", "visibility", "known_by", "emotional_tags", "meaning_tags", "fulfillment_status", "importance", "clarity", "related_npcs", "related_npc_ids", "original_evidence", "source_context", "intended_audience", "secrecy", "propagation_candidates", "sentiment", "weight", "summary", "tags", "evidence", "relationship_effects", "conditions", "revision_reason"]

func create_memory(state, memory_data: Dictionary) -> Dictionary:
	if state == null:
		return _fail("missing state")
	if memory_data.is_empty():
		return _fail("missing memory")
	var validation := _validate_memory_input(memory_data)
	if not validation.get("ok", false):
		return validation
	var memory_id := str(memory_data.get("id", "memory_%d_%d" % [int(state.current_day), state.structured_memories.size()]))
	if _find_memory_index(state, memory_id) >= 0:
		return _fail("duplicate memory id: " + memory_id)
	var participants: Array = memory_data.get("participants", []).duplicate(true)
	var source_id := str(memory_data.get("source_id", participants[0] if not participants.is_empty() else "li_heng"))
	var target_id := str(memory_data.get("target_id", participants[1] if participants.size() > 1 else ""))
	if participants.is_empty():
		for character_id in [source_id, target_id]:
			if character_id != "" and not participants.has(character_id):
				participants.append(character_id)
	var created_result: Dictionary = DayValueValidatorScript.validate(memory_data.get("created_day", memory_data.get("day", state.current_day)), "memory created_day", 0)
	if not created_result.get("ok", false):
		return created_result
	var created_day := int(created_result.get("value", state.current_day))
	var entry := {
		"id": memory_id,
		"version": 1,
		"history": [],
		"day": created_day,
		"created_day": created_day,
		"type": str(memory_data.get("type", memory_data.get("memory_type", "private_talk"))),
		"memory_type": str(memory_data.get("memory_type", memory_data.get("type", "private_talk"))),
		"participants": participants,
		"source_id": source_id,
		"target_id": target_id,
		"related_event_id": str(memory_data.get("related_event_id", "")),
		"related_task_id": str(memory_data.get("related_task_id", "")),
		"location": str(memory_data.get("location", "")),
		"original_intent": str(memory_data.get("original_intent", "")),
		"political_object": memory_data.get("political_object", "").duplicate(true) if memory_data.get("political_object", "") is Dictionary or memory_data.get("political_object", "") is Array else memory_data.get("political_object", ""),
		"visibility": str(memory_data.get("visibility", "private")),
		"known_by": memory_data.get("known_by", participants).duplicate(true),
		"emotional_tags": memory_data.get("emotional_tags", []).duplicate(true),
		"meaning_tags": memory_data.get("meaning_tags", memory_data.get("tags", [])).duplicate(true),
		"fulfillment_status": str(memory_data.get("fulfillment_status", "unresolved")),
		"importance": int(memory_data.get("importance", memory_data.get("weight", 3))),
		"clarity": int(memory_data.get("clarity", 5)),
		"related_npcs": memory_data.get("related_npcs", []).duplicate(true),
		"original_evidence": memory_data.get("original_evidence", {}).duplicate(true),
		"source_context": memory_data.get("source_context", {}).duplicate(true),
		"intended_audience": memory_data.get("intended_audience", []).duplicate(true),
		"secrecy": str(memory_data.get("secrecy", memory_data.get("visibility", "private"))),
		"propagation_candidates": memory_data.get("propagation_candidates", []).duplicate(true),
		"sentiment": str(memory_data.get("sentiment", "mixed")),
		"weight": int(memory_data.get("weight", 3)),
		"summary": str(memory_data.get("summary", "")),
		"tags": memory_data.get("tags", []).duplicate(true)
	}
	for optional_key in ["related_npc_ids", "evidence", "relationship_effects", "conditions", "revision_reason"]:
		if memory_data.has(optional_key):
			entry[optional_key] = memory_data[optional_key].duplicate(true) if memory_data[optional_key] is Dictionary or memory_data[optional_key] is Array else memory_data[optional_key]
	var next_memories: Array = state.structured_memories.duplicate(true)
	next_memories.append(entry.duplicate(true))
	state.structured_memories = next_memories
	# This legacy summary is used in the player's dossier. Private NPC memory
	# stays in observer-filtered structured records, not an omniscient summary.
	var visible_to_player: bool = known_to(entry, str(state.player_character_id))
	if visible_to_player and str(entry.get("target_id", "")) != "":
		state.add_character_memory(str(entry.get("target_id", "")), str(entry.get("summary", "")))
	if visible_to_player and str(entry.get("source_id", "")) != "" and str(entry.get("source_id", "")) != state.player_character_id and str(entry.get("source_id", "")) != str(entry.get("target_id", "")):
		state.add_character_memory(str(entry.get("source_id", "")), str(entry.get("summary", "")))
	return {"ok": true, "memory": entry}

func revise_memory(state, memory_id, revision: Dictionary) -> Dictionary:
	if state == null:
		return _fail("missing state")
	if typeof(memory_id) != TYPE_STRING or str(memory_id) == "":
		return _fail("invalid memory id")
	if revision.is_empty():
		return _fail("missing revision")
	var revision_validation := _validate_memory_fields(revision, false)
	if not revision_validation.get("ok", false):
		return revision_validation
	for protected_key in ["id", "version", "history", "original_evidence", "created_day"]:
		if revision.has(protected_key):
			return _fail("memory revision cannot replace " + protected_key)
	var index := _find_memory_index(state, memory_id)
	if index < 0:
		return _fail("unknown memory: " + memory_id)
	var previous: Dictionary = state.structured_memories[index].duplicate(true)
	if revision.has("day"):
		var revision_day_result: Dictionary = DayValueValidatorScript.validate(revision.get("day"), "memory revision day", int(previous.get("day", previous.get("created_day", 0))))
		if not revision_day_result.get("ok", false):
			return revision_day_result
	var revised := previous.duplicate(true)
	var history: Array = previous.get("history", []).duplicate(true)
	var historical_version := previous.duplicate(true)
	historical_version.erase("history")
	history.append(historical_version)
	history = _compact_history(history)
	for key in revision.keys():
		if str(key) in ["id", "version", "history", "original_evidence", "created_day"]:
			continue
		revised[key] = revision[key].duplicate(true) if revision[key] is Dictionary or revision[key] is Array else revision[key]
	revised["id"] = memory_id
	revised["version"] = int(previous.get("version", 1)) + 1
	revised["history"] = history
	revised["original_evidence"] = previous.get("original_evidence", {}).duplicate(true)
	if not state.replace_structured_memory(index, revised):
		return _fail("memory replacement failed")
	return {"ok": true, "memory": revised.duplicate(true)}

func get_relevant_memories(state, character_id: String, tags: Array = [], limit: int = 5, observer_id: String = "") -> Array:
	var result: Array = []
	if state == null or limit <= 0:
		return result
	var observer := observer_id
	if observer.is_empty() and state.get("player_character_id") is String and state.character_states.has(state.player_character_id): observer = state.player_character_id
	for index in range(state.structured_memories.size() - 1, -1, -1):
		var memory: Dictionary = state.structured_memories[index]
		if not observer.is_empty() and not known_to(memory, observer): continue
		if _matches(memory, character_id, tags):
			result.append(memory.duplicate(true))
		if result.size() >= limit:
			break
	return result

static func known_to(memory: Dictionary, observer_id: String) -> bool:
	# A target or related_npc may only have been mentioned. Rich memories record
	# actual witnesses explicitly; legacy source/participants mean firsthand.
	if memory.has("known_by"): return memory.known_by is Array and memory.known_by.has(observer_id)
	return memory.get("participants", []).has(observer_id) or memory.get("source_id") == observer_id

func create_relationship_reveal_memory(state, edge: Dictionary) -> Dictionary:
	if edge.is_empty():
		return _fail("missing edge")
	var visibility := str(edge.get("visibility", "private"))
	return create_memory(state, {
		"memory_type": "rumor" if visibility == "rumor" else "private_talk",
		"source_id": str(edge.get("source_id", "")),
		"target_id": str(edge.get("target_id", "")),
		"visibility": visibility,
		"sentiment": "mixed",
		"weight": int(edge.get("weight", 3)),
		"summary": str(edge.get("summary", "")),
		"tags": ["relationship_edge", str(edge.get("edge_type", ""))]
	})

func _matches(memory: Dictionary, character_id: String, tags: Array) -> bool:
	if character_id != "" and (str(memory.get("source_id", "")) == character_id or str(memory.get("target_id", "")) == character_id):
		return true
	if tags.is_empty():
		return false
	var memory_tags: Array = memory.get("tags", [])
	for tag in tags:
		if memory_tags.has(tag):
			return true
	return false

func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}

func _find_memory_index(state, memory_id: String) -> int:
	for index in range(state.structured_memories.size()):
		if str(state.structured_memories[index].get("id", "")) == memory_id:
			return index
	return -1

func _validate_memory_input(memory_data: Dictionary) -> Dictionary:
	var fields_validation := _validate_memory_fields(memory_data, true)
	if not fields_validation.get("ok", false):
		return fields_validation
	for lifecycle_key in ["version", "history"]:
		if memory_data.has(lifecycle_key):
			return _fail("memory creation cannot supply " + lifecycle_key)
	var rich := memory_data.has("type") or memory_data.has("participants") or memory_data.has("created_day") or memory_data.has("original_evidence")
	if rich:
		if typeof(memory_data.get("id")) != TYPE_STRING or str(memory_data.get("id", "")) == "":
			return _fail("rich memory requires id")
		if typeof(memory_data.get("type")) != TYPE_STRING or str(memory_data.get("type", "")) == "":
			return _fail("rich memory requires type")
		if not _is_string_array(memory_data.get("participants"), true):
			return _fail("rich memory requires participants")
		if not memory_data.has("original_evidence") or typeof(memory_data.get("original_evidence")) != TYPE_DICTIONARY:
			return _fail("rich memory requires original evidence")
	return {"ok": true}

func _validate_memory_fields(fields: Dictionary, _for_create: bool) -> Dictionary:
	var bounded := BoundedValueValidatorScript.validate_and_copy_dictionary(fields, "memory")
	if not bounded.get("ok", false):
		return _fail(str(bounded.get("error", "invalid memory structure")))
	for key in fields.keys():
		if not MEMORY_FIELDS.has(str(key)):
			return _fail("unsupported memory field: " + str(key))
	for key in ["known_by", "emotional_tags", "meaning_tags", "related_npcs", "related_npc_ids", "propagation_candidates", "intended_audience", "tags", "conditions"]:
		if fields.has(key) and not _is_string_array(fields.get(key), false):
			return _fail("invalid memory array: " + key)
	if fields.has("participants") and not _is_string_array(fields.get("participants"), true):
		return _fail("invalid memory participants")
	if fields.has("source_context") and typeof(fields.get("source_context")) != TYPE_DICTIONARY:
		return _fail("invalid source_context")
	if fields.has("secrecy") and not _is_valid_secrecy(fields.get("secrecy")):
		return _fail("invalid secrecy")
	for key in ["original_evidence", "evidence", "relationship_effects"]:
		if fields.has(key) and typeof(fields.get(key)) != TYPE_DICTIONARY:
			return _fail("invalid memory dictionary: " + key)
	if fields.has("history") and typeof(fields.get("history")) != TYPE_ARRAY:
		return _fail("invalid memory history")
	if fields.has("revision_reason"):
		var reason = fields.get("revision_reason")
		if typeof(reason) != TYPE_STRING or str(reason).strip_edges() == "" or str(reason).length() > 500:
			return _fail("invalid memory revision_reason")
	return {"ok": true}

func _compact_history(history: Array) -> Array:
	if history.size() <= MAX_LIFECYCLE_HISTORY:
		return history.duplicate(true)
	var compacted: Array = [history[0].duplicate(true)]
	for index in range(history.size() - (MAX_LIFECYCLE_HISTORY - 1), history.size()):
		compacted.append(history[index].duplicate(true))
	return compacted

func _is_valid_secrecy(value) -> bool:
	return typeof(value) == TYPE_STRING and str(value) in ["private", "public", "court", "rumor", "secret", "sealed_private", "confidential"]

func _is_string_array(value, require_nonempty: bool) -> bool:
	if typeof(value) != TYPE_ARRAY or (require_nonempty and value.is_empty()):
		return false
	for item in value:
		if typeof(item) != TYPE_STRING or str(item) == "":
			return false
	return true

func _is_safe_value(value, ancestors: Array = [], depth: int = 0) -> bool:
	if depth > 24:
		return false
	var value_type := typeof(value)
	if value_type != TYPE_ARRAY and value_type != TYPE_DICTIONARY:
		return value_type in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_VECTOR2, TYPE_VECTOR2I]
	for ancestor in ancestors:
		if is_same(value, ancestor):
			return false
	var next_ancestors := ancestors.duplicate(false)
	next_ancestors.append(value)
	if value_type == TYPE_ARRAY:
		for item in value:
			if not _is_safe_value(item, next_ancestors, depth + 1):
				return false
	else:
		for key in value.keys():
			if typeof(key) != TYPE_STRING or not _is_safe_value(value[key], next_ancestors, depth + 1):
				return false
	return true
