extends RefCounted

class_name FactionAgendaService

func get_agenda(state, faction_id: String) -> Dictionary:
	if state == null:
		return {}
	return state.faction_agenda_state.get(faction_id, {}).duplicate(true)

func apply_reaction(state, data: Dictionary, faction_id: String, reaction: Dictionary) -> Dictionary:
	if state == null:
		return _fail("missing state")
	if not state.faction_agenda_state.has(faction_id):
		var template := _find_agenda(data, faction_id)
		if template.is_empty():
			return _fail("unknown faction agenda: " + faction_id)
		state.faction_agenda_state[faction_id] = template.duplicate(true)
	var agenda: Dictionary = state.faction_agenda_state[faction_id].duplicate(true)
	agenda["influence"] = clampi(int(agenda.get("influence", 0)) + int(reaction.get("influence_delta", 0)), 0, 100)
	agenda["pressure"] = clampi(int(agenda.get("pressure", 0)) + int(reaction.get("pressure_delta", 0)), 0, 100)
	var reactions: Array = agenda.get("recent_reactions", []).duplicate(true)
	reactions.append({
		"reaction_type": str(reaction.get("reaction_type", "")),
		"summary": str(reaction.get("summary", "")),
		"day": int(state.current_day)
	})
	agenda["recent_reactions"] = reactions
	state.faction_agenda_state[faction_id] = agenda
	state.record_event_history("faction__" + faction_id, "reaction", {
		"reaction_type": str(reaction.get("reaction_type", "")),
		"summary": str(reaction.get("summary", ""))
	})
	state.chronicle_causal_references.append({
		"kind": "faction_agenda",
		"id": faction_id,
		"reaction_type": str(reaction.get("reaction_type", "")),
		"day": int(state.current_day)
	})
	return {"ok": true, "agenda": agenda.duplicate(true)}

func build_report(state, faction_id: String) -> Dictionary:
	var agenda := get_agenda(state, faction_id)
	return {
		"id": "faction_report__" + faction_id + "__" + str(int(state.current_day) if state != null else 0),
		"type": "faction_report",
		"title": "Faction pressure: " + faction_id,
		"source_character_id": "",
		"deadline_days": 2,
		"urgency": int(agenda.get("pressure", 50)),
		"visible_summary": _summarize_agenda(agenda),
		"available_decisions": []
	}

func appointment_pressure_effects(candidate_id: String, office_id: String, mode: String, cost_record: Dictionary = {}) -> Dictionary:
	var effects: Array = []
	if mode == "exceptional":
		effects.append({"type": "faction_pressure_delta", "faction_id": "old_court", "value": int(cost_record.get("political_debt", 0))})
		effects.append({"type": "relationship_debt", "character_id": candidate_id, "office_id": office_id, "value": int(cost_record.get("political_debt", 0))})
	return {"ok": true, "effects": effects}

func _summarize_agenda(agenda: Dictionary) -> String:
	return "%s influence=%d pressure=%d actions=%s" % [
		str(agenda.get("faction_id", "")),
		int(agenda.get("influence", 0)),
		int(agenda.get("pressure", 0)),
		", ".join(agenda.get("likely_actions", []))
	]

func _find_agenda(data: Dictionary, faction_id: String) -> Dictionary:
	for agenda in data.get("faction_agendas", []):
		if str(agenda.get("faction_id", "")) == faction_id:
			return agenda.duplicate(true)
	return {}

func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
