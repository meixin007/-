extends RefCounted

const Traits = preload("res://scripts/core/tang_character_trait_service.gd")
const Contract = preload("res://scripts/core/npc_ai_state_contract.gd")

func build(state, data: Dictionary, actor_id: String) -> Dictionary:
	if state == null or not state.character_states.has(actor_id): return Contract.fail("unknown self profile actor")
	var traits = Traits.new()
	var definition: Dictionary = traits._find_char_data(data, actor_id)
	var person: Dictionary = state.character_states[actor_id]
	var ids: Array = []
	for id in definition.get("tang_traits", []) + definition.get("hidden_traits", []) + person.get("tang_traits", []):
		if not ids.has(id): ids.append(id)
	var custom: Dictionary = state.flags.get("custom_character_traits", {}).get(actor_id, {})
	for id in custom.get("added_public", []) + custom.get("added_hidden", []):
		if not ids.has(id): ids.append(id)
	for id in custom.get("removed", []): ids.erase(id)
	var vectors := {"boldness": 0, "compassion": 0, "greed": 0, "honor": 0, "rationality": 0, "vengefulness": 0, "zeal": 0}
	for id in ids:
		var modifiers: Dictionary = traits.get_trait_definition(id).get("ai_modifiers", {})
		for key in vectors: vectors[key] = clampi(int(vectors[key]) + int(modifiers.get(key, 0)), -100, 100)
	var abilities := {}
	for key in ["military", "governance", "finance", "intrigue", "diplomacy", "prowess"]:
		abilities[key] = person.get("stats", {}).get(key, person.get(key, definition.get("stats", {}).get(key, definition.get("abilities", {}).get(key, 0))))
	# These are the same authored preferences used by livelihood/hiring rules.
	# Only this actor's fields enter a private decision projection.
	var preferences := own_fields(definition.get("employment_preferences", {}), ["roles", "organization_ids", "minimum_wage"])
	var livelihood := own_fields(data.get("management", {}).get("life_models", {}).get(actor_id, {}), ["minimum_reserve", "dependants", "tie_bonus", "stable_goal", "preferred_employer_id", "source_id"])
	return {"ok": true, "profile": {"character_id": actor_id, "trait_ids": ids, "ordinary_traits": definition.get("traits", []).duplicate(true), "employment_preferences": preferences, "livelihood_model": livelihood, "vectors": vectors, "abilities": abilities, "condition": person.get("status", ""), "location_id": person.get("location_id", ""), "life_goal": person.get("life_goal", {}).duplicate(true), "social_opportunities": load("res://scripts/core/npc_social_reaction_service.gd").opportunities(state, actor_id), "pressure": state.character_political_states.get(actor_id, {}).duplicate(true), "relationships": person.get("relationships", {}).duplicate(true)}}

static func own_fields(source: Dictionary, fields: Array) -> Dictionary:
	var result := {}
	for key in fields:
		if not source.has(key): continue
		var value = source[key]
		result[key] = value.duplicate(true) if value is Array or value is Dictionary else value
	return result
