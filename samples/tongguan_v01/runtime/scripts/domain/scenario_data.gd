extends RefCounted

class_name ScenarioData

const Beta10ContentValidatorScript = preload("res://scripts/domain/beta_1_0_content_validator.gd")
const CampaignManifestScript = preload("res://scripts/domain/campaign_manifest.gd")
const Beta108CampaignLoaderScript = preload("res://scripts/domain/beta_1_08_campaign_loader.gd")
const Beta109CampaignLoaderScript = preload("res://scripts/domain/beta_1_09_campaign_loader.gd")
const Beta110CampaignLoaderScript = preload("res://scripts/domain/beta_1_10_campaign_loader.gd")
const UnifiedCampaignLoaderScript = preload("res://scripts/domain/unified_campaign_loader.gd")

func load_campaign(manifest_path: String) -> Dictionary:
	var raw_manifest_result := _load_json(manifest_path)
	if bool(raw_manifest_result.get("ok", false)) and raw_manifest_result.get("data") is Dictionary:
		var manifest_dict: Dictionary = raw_manifest_result.get("data", {})
		var schema_ver := int(manifest_dict.get("schema_version", 0))
		if schema_ver == 113 or manifest_dict.has("domain_files"):
			return UnifiedCampaignLoaderScript.compose(manifest_dict, manifest_path.get_base_dir())
		if schema_ver == 110:
			var base_result := load_scenario(manifest_path.get_base_dir())
			if not base_result.get("ok", false):
				return base_result
			var base_data := base_result.duplicate(true)
			base_data.erase("ok")
			return Beta110CampaignLoaderScript.compose(base_data, manifest_dict, manifest_path.get_base_dir())
	if bool(raw_manifest_result.get("ok", false)) and raw_manifest_result.get("data") is Dictionary and int((raw_manifest_result.get("data", {}) as Dictionary).get("schema_version", 0)) == 109:
		var base_result := load_scenario(manifest_path.get_base_dir())
		if not base_result.get("ok", false):
			return base_result
		var base_data := base_result.duplicate(true)
		base_data.erase("ok")
		return Beta109CampaignLoaderScript.compose(base_data, raw_manifest_result.get("data", {}) as Dictionary, manifest_path.get_base_dir())
	if bool(raw_manifest_result.get("ok", false)) and raw_manifest_result.get("data") is Dictionary and int((raw_manifest_result.get("data", {}) as Dictionary).get("schema_version", 0)) == 108:
		var base_result := load_scenario(manifest_path.get_base_dir())
		if not base_result.get("ok", false):
			return base_result
		var base_data := base_result.duplicate(true)
		base_data.erase("ok")
		return Beta108CampaignLoaderScript.compose(base_data, raw_manifest_result.get("data", {}) as Dictionary, manifest_path.get_base_dir())
	if bool(raw_manifest_result.get("ok", false)) and raw_manifest_result.get("data") is Dictionary and int((raw_manifest_result.get("data", {}) as Dictionary).get("schema_version", 0)) == 107:
		return _load_split_governance_campaign(manifest_path, raw_manifest_result.get("data", {}) as Dictionary)
	var manifest_result: Dictionary = CampaignManifestScript.load_from_path(manifest_path)
	if not manifest_result.get("ok", false):
		return _fail(str(manifest_result.get("error", "invalid campaign manifest")))
	var manifest: Dictionary = manifest_result.data.duplicate(true)
	var loaded: Dictionary = load_scenario(manifest_path.get_base_dir())
	if not loaded.get("ok", false):
		return loaded
	var character_ids := PackedStringArray(manifest.get("character_ids", PackedStringArray()))
	var important_event_ids := PackedStringArray(manifest.get("important_event_ids", PackedStringArray()))
	var characters := _select_by_ids(loaded.get("characters", []), character_ids, "id")
	var campaign_events_result := _apply_campaign_event_overrides(loaded.get("events", []), manifest.get("content_files", {}), manifest_path.get_base_dir())
	if not campaign_events_result.get("ok", false):
		return campaign_events_result
	var important_events := _select_by_ids(campaign_events_result.get("events", []), important_event_ids, "id")
	if characters.size() != character_ids.size():
		return _fail("campaign manifest references missing character")
	if important_events.size() != important_event_ids.size():
		return _fail("campaign manifest references missing important event")
	var campaign_key_scenes_result := _apply_campaign_key_scenes(loaded.get("key_scenes", []), manifest.get("content_files", {}), manifest_path.get_base_dir())
	if not campaign_key_scenes_result.get("ok", false):
		return campaign_key_scenes_result
	var campaign_data := loaded.duplicate(true)
	campaign_data["key_scenes"] = campaign_key_scenes_result.get("key_scenes", [])
	campaign_data["campaign_id"] = str(manifest.get("campaign_id", ""))
	campaign_data["campaign_days"] = int(manifest.get("campaign_days", 0))
	campaign_data["phases"] = (manifest.get("phases", []) as Array).duplicate(true)
	campaign_data["content_files"] = (manifest.get("content_files", {}) as Dictionary).duplicate(true)
	campaign_data["characters"] = characters
	campaign_data["important_events"] = important_events
	return {"ok": true, "data": campaign_data}

func _load_split_governance_campaign(manifest_path: String, campaign: Dictionary) -> Dictionary:
	var base_path := manifest_path.get_base_dir()
	var manifest_result := _load_json(base_path.path_join(str(campaign.get("governance_manifest", ""))))
	if not bool(manifest_result.get("ok", false)) or not manifest_result.get("data") is Dictionary: return _fail("invalid governance manifest")
	var author_manifest: Dictionary = manifest_result.get("data", {})
	if int(author_manifest.get("schema_version", 0)) != 107: return _fail("invalid governance manifest schema")
	var governance := {"case_chains": [], "memorial_templates": [], "topic_rules": {}, "command_actions": {}, "report_templates": {}, "score_thresholds": (author_manifest.get("score_thresholds", {}) as Dictionary).duplicate(true), "special_councils": []}
	var seen: Dictionary = {}
	for file_name in author_manifest.get("case_files", []):
		var case_result := _load_json(base_path.path_join(str(file_name)))
		if not bool(case_result.get("ok", false)) or not case_result.get("data") is Dictionary: return _fail("invalid governance case file")
		var case_data: Dictionary = case_result.get("data", {})
		for raw_memorial in case_data.get("memorial_templates", []):
			if not raw_memorial is Dictionary or str((raw_memorial as Dictionary).get("memorial_id", "")).is_empty() or seen.has(str((raw_memorial as Dictionary).get("memorial_id", ""))): return _fail("duplicate governance id")
			seen[str((raw_memorial as Dictionary).get("memorial_id", ""))] = true
			governance["memorial_templates"].append((raw_memorial as Dictionary).duplicate(true))
		for key in ["case_chains"]: governance[key].append_array((case_data.get(key, []) as Array).duplicate(true))
		for key in ["topic_rules", "command_actions"]:
			for id in (case_data.get(key, {}) as Dictionary).keys():
				if (governance[key] as Dictionary).has(id): return _fail("duplicate governance id")
				(governance[key] as Dictionary)[id] = ((case_data.get(key, {}) as Dictionary)[id] as Dictionary).duplicate(true)
	var reports_result := _load_json(base_path.path_join(str(author_manifest.get("report_file", ""))))
	if not bool(reports_result.get("ok", false)) or not reports_result.get("data") is Dictionary: return _fail("invalid governance report file")
	governance["report_templates"] = (reports_result.get("data", {}) as Dictionary).duplicate(true)
	if _has_followup_cycle(governance.get("memorial_templates", []) as Array): return _fail("followup cycle")
	var validation := _validate_governance_data(governance, campaign.get("characters", []) as Array, campaign.get("offices", []) as Array, campaign.get("local_nodes", []) as Array, campaign.get("resources", {}) as Dictionary)
	if not bool(validation.get("ok", false)): return _fail(str(validation.get("error", "invalid governance data")))
	return {"ok": true, "data": {"campaign_id": str(campaign.get("campaign_id", "")), "campaign_days": 90, "scenario": (campaign.get("scenario", {"start_phase": "opening"}) as Dictionary).duplicate(true), "characters": (campaign.get("characters", []) as Array).duplicate(true), "factions": (campaign.get("factions", []) as Array).duplicate(true), "offices": (campaign.get("offices", []) as Array).duplicate(true), "local_nodes": (campaign.get("local_nodes", []) as Array).duplicate(true), "resources": (campaign.get("resources", {}) as Dictionary).duplicate(true), "governance": validation.get("data", {}).duplicate(true)}}

func _has_followup_cycle(memorials: Array) -> bool:
	var parent_by_id: Dictionary = {}
	for raw_memorial in memorials:
		if raw_memorial is Dictionary:
			var memorial: Dictionary = raw_memorial
			parent_by_id[str(memorial.get("memorial_id", ""))] = str(memorial.get("previous_memorial_id", ""))
	for memorial_id in parent_by_id.keys():
		var seen: Dictionary = {}
		var cursor := str(memorial_id)
		while not cursor.is_empty() and parent_by_id.has(cursor):
			if seen.has(cursor): return true
			seen[cursor] = true
			cursor = str(parent_by_id.get(cursor, ""))
	return false

func _apply_campaign_key_scenes(base_scenes: Array, content_files: Variant, base_path: String) -> Dictionary:
	var merged: Array = base_scenes.duplicate(true)
	var seen: Dictionary = {}
	for raw_scene in merged:
		if raw_scene is Dictionary:
			seen[str((raw_scene as Dictionary).get("id", ""))] = true
	if not (content_files is Dictionary):
		return {"ok": true, "key_scenes": merged}
	for file_name in (content_files as Dictionary).get("key_scenes", []):
		var normalized_file := str(file_name)
		if not normalized_file.begins_with("beta_1_05_key_scenes_"):
			continue
		var scenes_result := _load_json(base_path.path_join(normalized_file))
		if not scenes_result.get("ok", false):
			return _fail(str(scenes_result.get("error", "campaign key scene load failed")))
		if not (scenes_result.get("data") is Array):
			return _fail("campaign key scene file must be an Array: " + normalized_file)
		for raw_scene in scenes_result.get("data", []):
			if not (raw_scene is Dictionary):
				return _fail("campaign key scene entry must be a Dictionary: " + normalized_file)
			var scene_id := str((raw_scene as Dictionary).get("id", ""))
			if scene_id.is_empty():
				return _fail("campaign key scene requires an id: " + normalized_file)
			if seen.has(scene_id):
				return _fail("duplicate campaign key scene id: " + scene_id)
			seen[scene_id] = true
			merged.append((raw_scene as Dictionary).duplicate(true))
	return {"ok": true, "key_scenes": merged}

func _apply_campaign_event_overrides(base_events: Array, content_files: Variant, base_path: String) -> Dictionary:
	var indexed: Dictionary = {}
	for raw_event in base_events:
		if raw_event is Dictionary:
			indexed[str((raw_event as Dictionary).get("id", ""))] = (raw_event as Dictionary).duplicate(true)
	if not (content_files is Dictionary):
		return {"ok": true, "events": base_events.duplicate(true)}
	for file_name in (content_files as Dictionary).get("events", []):
		var normalized_file := str(file_name)
		if not normalized_file.begins_with("beta_1_05_important_events_"):
			continue
		var override_result := _load_json(base_path.path_join(normalized_file))
		if not override_result.get("ok", false):
			return _fail(str(override_result.get("error", "campaign event override load failed")))
		if not (override_result.get("data") is Array):
			return _fail("campaign event override must be an Array: " + normalized_file)
		for raw_override in override_result.get("data", []):
			if not (raw_override is Dictionary) or str((raw_override as Dictionary).get("id", "")).is_empty():
				return _fail("campaign event override requires event id: " + normalized_file)
			indexed[str((raw_override as Dictionary).get("id", ""))] = (raw_override as Dictionary).duplicate(true)
	var merged: Array = []
	for raw_event in base_events:
		if raw_event is Dictionary:
			var event_id := str((raw_event as Dictionary).get("id", ""))
			if indexed.has(event_id):
				merged.append((indexed[event_id] as Dictionary).duplicate(true))
				indexed.erase(event_id)
	for event_id in indexed.keys():
		merged.append((indexed[event_id] as Dictionary).duplicate(true))
	return {"ok": true, "events": merged}

func load_scenario(base_path: String) -> Dictionary:
	var scenario_result := _load_json(base_path + "/scenario.json")
	if not scenario_result.ok:
		return _fail(scenario_result.error)
	var resources_result := _load_json(base_path + "/resources.json")
	if not resources_result.ok:
		return _fail(resources_result.error)
	var factions_result := _load_json(base_path + "/factions.json")
	if not factions_result.ok:
		return _fail(factions_result.error)
	var battlefronts_result := _load_json(base_path + "/battlefronts.json")
	if not battlefronts_result.ok:
		return _fail(battlefronts_result.error)
	var vertical_slice_result := _load_json(base_path + "/vertical_slice_definition.json")
	if not vertical_slice_result.ok:
		return _fail(vertical_slice_result.error)
	var characters_result := _load_json(base_path + "/characters.json")
	if not characters_result.ok:
		return _fail(characters_result.error)
	var decisions_result := _load_json(base_path + "/decisions.json")
	if not decisions_result.ok:
		return _fail(decisions_result.error)
	var events_result := _load_json(base_path + "/chapter_1_events.json")
	if not events_result.ok:
		return _fail(events_result.error)
	var beta_1_0_events_result := _load_optional_json(base_path + "/beta_1_0_important_events.json", [])
	if not beta_1_0_events_result.ok:
		return _fail(beta_1_0_events_result.error)
	var key_scenes_result := _load_optional_json(base_path + "/key_scenes.json", [])
	if not key_scenes_result.ok:
		return _fail(key_scenes_result.error)
	var npc_interactions_result := _load_optional_json(base_path + "/npc_interactions_beta_0_4.json", {})
	if not npc_interactions_result.ok:
		return _fail(npc_interactions_result.error)
	var dialogue_topics_result := _load_optional_json(base_path + "/npc_dialogue_topics_beta_0_5.json", [])
	if not dialogue_topics_result.ok:
		return _fail(dialogue_topics_result.error)
	var relationship_edges_result := _load_optional_json(base_path + "/npc_relationship_edges_beta_0_5.json", [])
	if not relationship_edges_result.ok:
		return _fail(relationship_edges_result.error)
	var npc_stances_result := _load_optional_json(base_path + "/npc_stances_beta_0_5.json", {})
	if not npc_stances_result.ok:
		return _fail(npc_stances_result.error)
	var obligation_ledger_result := _load_optional_json(base_path + "/obligation_ledger_beta_0_5.json", {"templates": [], "reports": [], "consequences": []})
	if not obligation_ledger_result.ok:
		return _fail(obligation_ledger_result.error)
	var offices_result := _load_optional_json(base_path + "/offices_beta_0_6.json", [])
	if not offices_result.ok:
		return _fail(offices_result.error)
	var governance_result := _load_optional_json(base_path + "/governance_beta_1_06.json", {})
	if not governance_result.ok:
		return _fail(governance_result.error)
	var faction_agendas_result := _load_optional_json(base_path + "/faction_agendas_beta_0_6.json", [])
	if not faction_agendas_result.ok:
		return _fail(faction_agendas_result.error)
	var court_meetings_result := _load_optional_json(base_path + "/court_meetings_beta_0_6.json", [])
	if not court_meetings_result.ok:
		return _fail(court_meetings_result.error)
	var local_nodes_result := _load_optional_json(base_path + "/local_nodes_beta_0_6.json", [])
	if not local_nodes_result.ok:
		return _fail(local_nodes_result.error)
	var consequence_chains_result := _load_optional_json(base_path + "/consequence_chains_beta_0_6.json", [])
	if not consequence_chains_result.ok:
		return _fail(consequence_chains_result.error)
	var branch_evaluations_result := _load_optional_json(base_path + "/branch_evaluations_beta_0_6.json", [])
	if not branch_evaluations_result.ok:
		return _fail(branch_evaluations_result.error)
	var intelligence_reports_result := _load_optional_json(base_path + "/intelligence_reports_beta_0_7.json", [])
	if not intelligence_reports_result.ok:
		return _fail(intelligence_reports_result.error)
	var route_network_result := _load_optional_json(base_path + "/route_network_beta_0_7.json", {"nodes": [], "routes": []})
	if not route_network_result.ok:
		return _fail(route_network_result.error)
	var regional_operations_result := _load_optional_json(base_path + "/regional_operations_beta_0_7.json", [])
	if not regional_operations_result.ok:
		return _fail(regional_operations_result.error)
	var intelligence_contradictions_result := _load_optional_json(base_path + "/intelligence_contradictions_beta_0_7.json", [])
	if not intelligence_contradictions_result.ok:
		return _fail(intelligence_contradictions_result.error)
	var npc_political_profiles_result := _load_optional_json(base_path + "/npc_political_profiles_beta_0_9.json", [])
	if not npc_political_profiles_result.ok:
		return _fail(npc_political_profiles_result.error)
	var dialogue_intents_beta_0_9_result := _load_optional_json(base_path + "/dialogue_intents_beta_0_9.json", [])
	if not dialogue_intents_beta_0_9_result.ok:
		return _fail(dialogue_intents_beta_0_9_result.error)
	var conversation_consequences_result := _load_optional_json(base_path + "/conversation_consequences_beta_0_9.json", {"objects": [], "reports": [], "chains": []})
	if not conversation_consequences_result.ok:
		return _fail(conversation_consequences_result.error)
	var map_conversation_routes_result := _load_optional_json(base_path + "/map_conversation_routes_beta_0_9.json", [])
	if not map_conversation_routes_result.ok:
		return _fail(map_conversation_routes_result.error)
	var character_models_result := _load_optional_json(base_path + "/beta_0_95_character_models.json", [])
	if not character_models_result.ok:
		return _fail(character_models_result.error)
	var character_arcs_result := _load_optional_json(base_path + "/beta_1_0_character_arcs.json", {"schema_version": 1, "arcs": {}})
	if not character_arcs_result.ok:
		return _fail(character_arcs_result.error)
	var information_rules_result := _load_optional_json(base_path + "/beta_0_95_information_rules.json", {"reaction_rules": []})
	if not information_rules_result.ok:
		return _fail(information_rules_result.error)
	var political_chains_result := _load_optional_json(base_path + "/beta_0_95_political_chains.json", {"chains": [], "cross_links": [], "representative_branches": []})
	if not political_chains_result.ok:
		return _fail(political_chains_result.error)

	var scenario: Dictionary = scenario_result.data
	var governance_validation := _validate_governance_data(governance_result.data, characters_result.data, offices_result.data, local_nodes_result.data, resources_result.data)
	if not bool(governance_validation.get("ok", false)):
		return _fail("governance_beta_1_06.json: " + str(governance_validation.get("error", "invalid")))
	var existing_ids: Dictionary = {}
	for event in events_result.data:
		existing_ids[str(event.get("id", ""))] = true
	var references := _build_beta_1_0_references(resources_result.data, factions_result.data, battlefronts_result.data, characters_result.data, decisions_result.data, npc_interactions_result.data, local_nodes_result.data, consequence_chains_result.data, route_network_result.data, political_chains_result.data, conversation_consequences_result.data)
	var beta_1_0_validation := Beta10ContentValidatorScript.new().validate_events(beta_1_0_events_result.data, references, existing_ids)
	if not beta_1_0_validation.get("ok", false):
		return _fail("beta_1_0_important_events.json: " + str(beta_1_0_validation.get("error", "invalid")))
	var character_ids: Array = []
	for character in characters_result.data:
		if character is Dictionary:
			character_ids.append(str(character.get("id", "")))
	var arcs_validation := Beta10ContentValidatorScript.new().validate_character_arcs(character_arcs_result.data, character_ids)
	if not arcs_validation.get("ok", false):
		return _fail("beta_1_0_character_arcs.json: " + str(arcs_validation.get("error", "invalid")))
	for raw_model in character_models_result.data:
		var depth_validation := Beta10ContentValidatorScript.new().validate_character_depth_model(raw_model)
		if not depth_validation.get("ok", false):
			return _fail("beta_0_95_character_models.json: " + str(depth_validation.get("error", "invalid")))
	var merged_events := _merge_events_by_trigger_day(events_result.data, beta_1_0_validation.data)
	for key in ["id", "title", "player_character_id", "start_time", "start_phase", "time_mode"]:
		if not scenario.has(key):
			return _fail("scenario.json missing key: " + key)

	var offices_catalog_result := _load_optional_json(base_path + "/offices_catalog.json", {})
	var recruitment_events_result := _load_optional_json(base_path + "/tang_recruitment_events.json", {})
	var audience_dialogues_result := _load_optional_json(base_path + "/audience_dialogues.json", {})
	var examination_questions_result := _load_optional_json(base_path + "/examination_questions.json", {})
	var clan_petitions_result := _load_optional_json(base_path + "/clan_petitions.json", {})
	var tang_clans_definition_result := _load_optional_json(base_path + "/tang_clans_definition.json", {})
	var tang_traits_definition_result := _load_optional_json(base_path + "/tang_traits_definition.json", {})
	var tang_clan_characters_expansion_result := _load_optional_json(base_path + "/tang_clan_characters_expansion.json", {})

	return {
		"ok": true,
		"scenario": scenario,
		"resources": resources_result.data,
		"factions": factions_result.data,
		"battlefronts": battlefronts_result.data,
		"vertical_slice": vertical_slice_result.data,
		"characters": _attach_character_models(characters_result.data, character_models_result.data, arcs_validation.data),
		"decisions": decisions_result.data,
		"events": merged_events,
		"important_events_beta_1_0": beta_1_0_validation.data.duplicate(true),
		"key_scenes": key_scenes_result.data,
		"npc_interactions": npc_interactions_result.data,
		"dialogue_topics": dialogue_topics_result.data,
		"relationship_edges": relationship_edges_result.data,
		"npc_stances": npc_stances_result.data,
		"obligation_ledger": obligation_ledger_result.data,
		"offices": offices_result.data,
		"governance": governance_validation.get("data", {}).duplicate(true),
		"faction_agendas": faction_agendas_result.data,
		"court_meetings": court_meetings_result.data,
		"local_nodes": local_nodes_result.data,
		"consequence_chains": consequence_chains_result.data,
		"branch_evaluations": branch_evaluations_result.data,
		"intelligence_reports": intelligence_reports_result.data,
		"route_network": route_network_result.data,
		"regional_operations": regional_operations_result.data,
		"intelligence_contradictions": intelligence_contradictions_result.data,
		"npc_political_profiles": npc_political_profiles_result.data,
		"dialogue_intents_beta_0_9": dialogue_intents_beta_0_9_result.data,
		"conversation_consequences": conversation_consequences_result.data,
		"map_conversation_routes": map_conversation_routes_result.data,
		"character_models_beta_0_95": character_models_result.data,
		"character_arcs_beta_1_0": arcs_validation.data,
		"information_rules": information_rules_result.data,
		"political_chains": political_chains_result.data,
		"offices_catalog": offices_catalog_result.get("data", {}),
		"recruitment_events": recruitment_events_result.get("data", {}),
		"audience_dialogues": audience_dialogues_result.get("data", {}),
		"examination_questions": examination_questions_result.get("data", {}),
		"clan_petitions": clan_petitions_result.get("data", {}),
		"tang_clans_definition": tang_clans_definition_result.get("data", {}),
		"tang_traits_definition": tang_traits_definition_result.get("data", {}),
		"tang_clan_characters_expansion": tang_clan_characters_expansion_result.get("data", {})
	}

func _attach_character_models(characters: Array, models: Array, arcs: Dictionary = {}) -> Array:
	var models_by_character_id: Dictionary = {}
	for raw_model in models:
		if not (raw_model is Dictionary):
			continue
		var model: Dictionary = raw_model
		var character_id := str(model.get("character_id", ""))
		if character_id != "":
			models_by_character_id[character_id] = model.duplicate(true)
	var enriched_characters: Array = []
	for raw_character in characters:
		if not (raw_character is Dictionary):
			continue
		var character: Dictionary = raw_character.duplicate(true)
		var character_id := str(character.get("id", ""))
		if models_by_character_id.has(character_id):
			var model_copy: Dictionary = models_by_character_id[character_id].duplicate(true)
			if arcs.has(character_id):
				model_copy["political_arc"] = (arcs[character_id] as Dictionary).duplicate(true)
			character["active_action_model"] = model_copy
			if arcs.has(character_id):
				character["political_arc"] = (arcs[character_id] as Dictionary).duplicate(true)
		enriched_characters.append(character)
	return enriched_characters

func _merge_events_by_trigger_day(existing_events: Array, beta_events: Array) -> Array:
	var merged: Array = existing_events.duplicate(true)
	for beta_event in beta_events:
		var insert_at := merged.size()
		for existing_index in range(merged.size()):
			if int(merged[existing_index].get("trigger_day", 0)) > int(beta_event.get("trigger_day", 0)):
				insert_at = existing_index
				break
		merged.insert(insert_at, beta_event.duplicate(true))
	return merged

func _select_by_ids(items: Array, ids: PackedStringArray, id_key: String) -> Array:
	var indexed: Dictionary = {}
	for item in items:
		if item is Dictionary:
			indexed[str(item.get(id_key, ""))] = (item as Dictionary).duplicate(true)
	var selected: Array = []
	for item_id in ids:
		if indexed.has(item_id):
			selected.append((indexed[item_id] as Dictionary).duplicate(true))
	return selected

func _build_beta_1_0_references(resources: Dictionary, factions: Array, battlefronts: Array, characters: Array, decisions: Array, npc_interactions: Dictionary, local_nodes: Array, consequence_chains: Array, route_network: Dictionary, political_chains: Dictionary, conversation_consequences: Dictionary) -> Dictionary:
	var decision_ids := _collect_ids(decisions, "id")
	var task_ids := _collect_task_object_ids(conversation_consequences.get("objects", []))
	var interaction_target_ids: Array = []
	var profiles: Dictionary = npc_interactions.get("profiles", {})
	for profile in profiles.values():
		if not (profile is Dictionary):
			continue
		for interaction in profile.get("available_interactions", []):
			_append_unique(interaction_target_ids, interaction)
	var map_ids := _collect_ids(local_nodes, "node_id")
	for node in route_network.get("nodes", []):
		if node is Dictionary:
			_append_unique(map_ids, node.get("node_id", ""))
	var chain_ids := _collect_ids(consequence_chains, "chain_id")
	for chain in political_chains.get("chains", []):
		if chain is Dictionary:
			_append_unique(chain_ids, chain.get("chain_id", ""))
	return {"character_ids": _collect_ids(characters, "id"), "interaction_target_ids": interaction_target_ids, "decision_ids": decision_ids, "task_ids": task_ids, "map_ids": map_ids, "chain_ids": chain_ids, "resource_ids": resources.keys(), "faction_ids": _collect_ids(factions, "id"), "battlefront_ids": _collect_ids(battlefronts, "id"), "strategy_route_ids": _collect_effect_targets(decisions, "strategy_route_delta"), "faction_fields_by_id": _collect_numeric_fields_by_id(factions), "battlefront_fields_by_id": _collect_numeric_fields_by_id(battlefronts)}

func _collect_ids(items: Array, key: String) -> Array:
	var ids: Array = []
	for item in items:
		if item is Dictionary:
			_append_unique(ids, item.get(key, ""))
	return ids

func _collect_effect_targets(decisions: Array, effect_type: String) -> Array:
	var targets: Array = []
	for decision in decisions:
		if not (decision is Dictionary):
			continue
		for effect in decision.get("effects", []):
			if effect is Dictionary and effect.get("type", "") == effect_type:
				_append_unique(targets, effect.get("target", ""))
	return targets

func _collect_task_object_ids(objects: Array) -> Array:
	var ids: Array = []
	for object in objects:
		if object is Dictionary and object.get("political_object_type", "") == "task":
			_append_unique(ids, object.get("object_id", ""))
	return ids

func _collect_numeric_fields_by_id(items: Array) -> Dictionary:
	var fields_by_id: Dictionary = {}
	for item in items:
		if not (item is Dictionary):
			continue
		var item_id := str(item.get("id", ""))
		if item_id.is_empty():
			continue
		var fields: Array = []
		for key in item.keys():
			if typeof(item[key]) == TYPE_INT or typeof(item[key]) == TYPE_FLOAT:
				_append_unique(fields, key)
		fields_by_id[item_id] = fields
	return fields_by_id

func _append_unique(values: Array, value: Variant) -> void:
	if value is String and not value.is_empty() and not values.has(value):
		values.append(value)

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("missing file: " + path)
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if parsed == null:
		return _fail("invalid json: " + path)
	return {"ok": true, "data": parsed}

func _validate_governance_data(raw: Variant, characters: Array, offices: Array, local_nodes: Array, resources: Dictionary) -> Dictionary:
	if not (raw is Dictionary):
		return _fail("governance data must be a dictionary")
	var governance: Dictionary = raw
	for key in ["memorial_templates", "topic_rules", "command_actions", "report_templates", "special_councils"]:
		if not governance.has(key):
			return _fail("missing governance key: " + key)
	if not (governance.get("memorial_templates") is Array):
		return _fail("memorial_templates must be an array")
	var character_ids := _collect_ids(characters, "id")
	var office_ids := _collect_ids(offices, "office_id")
	var node_ids := _collect_ids(local_nodes, "node_id")
	for raw_memorial in governance.get("memorial_templates", []):
		if not (raw_memorial is Dictionary):
			return _fail("memorial must be a dictionary")
		var memorial: Dictionary = raw_memorial
		if str(memorial.get("memorial_id", "")).is_empty() or not character_ids.has(str(memorial.get("sender_id", ""))):
			return _fail("memorial has unknown sender")
		if not node_ids.has(str(memorial.get("location_id", ""))) or int(memorial.get("deadline_days", 0)) <= 0:
			return _fail("memorial has invalid location or deadline")
		if not (memorial.get("visible_facts") is Array) or (memorial.get("visible_facts") as Array).is_empty():
			return _fail("memorial has no public facts")
		for executor_id in memorial.get("recommended_executor_ids", []):
			if not character_ids.has(str(executor_id)):
				return _fail("memorial has unknown executor")
		for resource_key in memorial.get("resource_keys", []):
			if not resources.has(str(resource_key)):
				return _fail("memorial has unknown resource")
	for topic_rule in (governance.get("topic_rules", {}) as Dictionary).values():
		if not (topic_rule is Dictionary):
			return _fail("topic rule must be a dictionary")
		for office_id in (topic_rule as Dictionary).get("required_offices", []):
			if not office_ids.has(str(office_id)):
				return _fail("topic rule has unknown office")
	for special in governance.get("special_councils", []):
		if special is Dictionary and int((special as Dictionary).get("seat_count", 0)) > 5:
			return _fail("special council exceeds five seats")
	return {"ok": true, "data": governance.duplicate(true)}

func _load_optional_json(path: String, default_value: Variant) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": true, "data": default_value}
	return _load_json(path)

func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
