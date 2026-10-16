extends RefCounted

class_name CharacterQueryService

const TangClanServiceScript = preload("res://scripts/core/tang_clan_service.gd")

func get_character(state, data: Dictionary, character_id: String) -> Dictionary:
	return find_character(data, state, character_id)

func find_character(data: Dictionary, state, character_id: String) -> Dictionary:
	var cid := character_id.strip_edges()
	if cid.is_empty():
		return {}

	# 1. Check dynamic characters in state first
	if state != null and state.get("character_states") is Dictionary:
		var char_states: Dictionary = state.character_states
		if char_states.get(cid) is Dictionary:
			var rec: Dictionary = char_states[cid]
			if bool(rec.get("is_dynamic", false)):
				return _format_dynamic_character_record(rec)

	# 2. Check static scenario data
	for ch in data.get("characters", []):
		if str(ch.get("id", "")) == cid:
			var character: Dictionary = ch.duplicate(true)
			if state!=null and state.get("character_states") is Dictionary and state.character_states.get(cid) is Dictionary:
				var current_stats: Dictionary = state.character_states[cid].get("stats",{}) if state.character_states[cid].get("stats",{}) is Dictionary else {}
				var stats: Dictionary = character.get("stats",{}).duplicate(true)
				for field in ["finance","governance","diplomacy","scholarship"]:
					if current_stats.has(field): stats[field] = current_stats[field]
				character["stats"] = stats
				for field in ["allegiance", "patron_id", "location_id", "status"]:
					if state.character_states[cid].has(field): character[field] = state.character_states[cid][field]
			return character

	# 3. Check clan characters
	var clan_service := TangClanServiceScript.new()
	var clan_char: Dictionary = clan_service._find_character_all(data, cid)
	if not clan_char.is_empty():
		return clan_char.duplicate(true)

	# 4. Fallback: if character_states has record even if not marked dynamic
	if state != null and state.get("character_states") is Dictionary and state.character_states.get(cid) is Dictionary:
		var fallback_rec: Dictionary = state.character_states[cid]
		return {
			"id": cid,
			"name": str(fallback_rec.get("name", cid)),
			"role": str(fallback_rec.get("role", "人物")),
			"faction_id": "independent",
			"stats": fallback_rec.get("stats", {}),
			"relationships": fallback_rec.get("relationships", {}),
			"memory_summary": fallback_rec.get("memory_summary", [])
		}

	return {}

func get_all_summonable_npc_ids(data: Dictionary, state) -> Array[String]:
	var result: Array[String] = []
	var interactions: Dictionary = data.get("npc_interactions", {})
	var profiles: Dictionary = interactions.get("profiles", {})
	for npc_id in interactions.get("core_npc_ids", []):
		var id := str(npc_id)
		var profile: Dictionary = profiles.get(id, {})
		if bool(profile.get("summonable", false)) and not find_character(data, state, id).is_empty():
			result.append(id)

	# Add summonable dynamic characters (e.g. accepted retainers)
	if state != null and state.get("character_states") is Dictionary:
		for cid in state.character_states.keys():
			var rec: Dictionary = state.character_states[cid]
			if bool(rec.get("is_dynamic", false)) and bool(rec.get("summonable", false)):
				if not result.has(cid):
					result.append(cid)

	return result

func _format_dynamic_character_record(rec: Dictionary) -> Dictionary:
	var allegiance: Dictionary = rec.get("allegiance", {})
	var is_retainer := str(allegiance.get("kind", "")) == "retainer"
	return {
		"id": str(rec.get("id", "")),
		"name": str(rec.get("name", "")),
		"role": str(rec.get("role", "武勇门客")),
		"faction_id": "player_court" if is_retainer else "independent",
		"stats": rec.get("stats", {}).duplicate(true),
		"tang_traits": rec.get("tang_traits", []).duplicate(true),
		"background": str(rec.get("background", "")),
		"origin": str(rec.get("origin", "")),
		"public_goal": str(rec.get("public_goal", "")),
		"hidden_goal": str(rec.get("hidden_goal", "")),
		"is_dynamic": true,
		"summonable": bool(rec.get("summonable", false)),
		"introduced_by": str(rec.get("introduced_by", "")),
		"patron_id": str(rec.get("patron_id", allegiance.get("target_id", ""))),
		"allegiance": allegiance.duplicate(true),
		"relationships": rec.get("relationships", {}).duplicate(true),
		"memory_summary": rec.get("memory_summary", []).duplicate(true),
		"status": str(rec.get("status", "available"))
	}
