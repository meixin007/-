extends RefCounted

class_name Beta110CampaignLoader

const Beta109CampaignLoaderScript = preload("res://scripts/domain/beta_1_09_campaign_loader.gd")
const ContentValidatorScript = preload("res://scripts/domain/beta_1_10_content_validator.gd")

const EXPECTED_BASE_MANIFEST := "campaign_beta_1_09.json"
const EXPECTED_BASE_CAMPAIGN_ID := "anshi_beta_1_09"
const REQUIRED_CONTENT_KEYS := [
	"political_season",
	"governance_followups",
	"political_echoes",
	"political_season_review",
	"accountability_effects",
	"character_arcs"
]

static func compose(base_data: Dictionary, campaign: Dictionary, base_path: String) -> Dictionary:
	var base_manifest_reference := str(campaign.get("base_manifest", "")).strip_edges()
	if base_manifest_reference != EXPECTED_BASE_MANIFEST:
		return _fail("BETA 1.10 base_manifest must be campaign_beta_1_09.json")
	var base_manifest_result := _load_manifest(base_path, base_manifest_reference)
	if not bool(base_manifest_result.get("ok", false)):
		return base_manifest_result
	var base_manifest: Dictionary = base_manifest_result.get("data", {})
	if int(base_manifest.get("schema_version", 0)) != 109 or str(base_manifest.get("campaign_id", "")) != EXPECTED_BASE_CAMPAIGN_ID:
		return _fail("BETA 1.10 base_manifest must reference schema 109 campaign anshi_beta_1_09")

	var inherited_result := Beta109CampaignLoaderScript.compose(base_data, base_manifest, base_path)
	if not bool(inherited_result.get("ok", false)):
		return _fail("BETA 1.10 base campaign: " + str(inherited_result.get("error", "invalid base campaign")))
	var inherited: Dictionary = inherited_result.get("data", {})

	var content_files: Variant = campaign.get("content_files", null)
	if not content_files is Dictionary:
		return _fail("BETA 1.10 content_files must be a dictionary")
	var loaded_content: Dictionary = {}
	for key in REQUIRED_CONTENT_KEYS:
		var content_result := _load_required_json(base_path, content_files as Dictionary, key)
		if not bool(content_result.get("ok", false)):
			return content_result
		loaded_content[key] = content_result.get("data")
	var initiatives_result := _load_required_json(base_path, content_files as Dictionary, "character_initiatives")
	if not bool(initiatives_result.get("ok", false)):
		return initiatives_result
	var initiatives_payload: Variant = initiatives_result.get("data")
	if not initiatives_payload is Dictionary or not (initiatives_payload as Dictionary).get("initiatives", {}) is Dictionary:
		return _fail("BETA 1.11 character initiatives must provide an initiatives dictionary")

	var bargains_payload: Dictionary = {}
	if (content_files as Dictionary).has("faction_bargains"):
		var bargains_result := _load_required_json(base_path, content_files as Dictionary, "faction_bargains")
		if not bool(bargains_result.get("ok", false)):
			return bargains_result
		if not bargains_result.get("data") is Dictionary or not (bargains_result.get("data") as Dictionary).get("bargains", []) is Array:
			return _fail("BETA 1.11 faction bargains must provide a bargains array")
		bargains_payload = (bargains_result.get("data") as Dictionary).duplicate(true)

	var working := inherited.duplicate(true)
	working["base_core_character_ids"] = (inherited.get("core_character_ids", []) as Array).duplicate(true)
	working["schema_version"] = 110
	working["campaign_id"] = str(campaign.get("campaign_id", ""))
	working["campaign_days"] = int(campaign.get("campaign_days", 0))
	working["base_manifest"] = base_manifest_reference
	working["base_campaign_id"] = EXPECTED_BASE_CAMPAIGN_ID
	working["scenario"] = (campaign.get("scenario", working.get("scenario", {})) as Dictionary).duplicate(true)
	working["phases"] = (campaign.get("phases", []) as Array).duplicate(true)
	working["base_content_files"] = (base_manifest.get("content_files", {}) as Dictionary).duplicate(true)
	working["content_files"] = (content_files as Dictionary).duplicate(true)
	working["base_political_season"] = inherited.get("political_season", {}).duplicate(true)
	working["base_governance_followups"] = inherited.get("governance_followups", {}).duplicate(true)
	working["base_political_echoes"] = inherited.get("political_echoes", {}).duplicate(true)
	working["base_political_season_review"] = inherited.get("political_season_review", {}).duplicate(true)

	var season: Dictionary = loaded_content["political_season"] as Dictionary
	var followups: Dictionary = loaded_content["governance_followups"] as Dictionary
	var materialized_result := _materialize_followup_execution_defaults(inherited, followups)
	if not bool(materialized_result.get("ok", false)):
		return materialized_result
	followups = materialized_result.get("followups", followups)
	working["governance"] = materialized_result.get("governance", working.get("governance", {}))
	var echoes: Dictionary = loaded_content["political_echoes"] as Dictionary
	var reviews: Dictionary = loaded_content["political_season_review"] as Dictionary
	working["political_season"] = season.duplicate(true)
	working["governance_followups"] = _merge_collection(inherited.get("governance_followups", {}), followups, "followups")
	working["political_echoes"] = _merge_collection(inherited.get("political_echoes", {}), echoes, "echoes")
	working["political_season_review"] = reviews.duplicate(true)
	working["political_season_reviews"] = (reviews.get("reviews", []) as Array).duplicate(true)
	working["accountability_effects"] = (loaded_content["accountability_effects"] as Dictionary).duplicate(true)
	working["beta110_nodes"] = (season.get("nodes", []) as Array).duplicate(true)
	working["beta110_routes"] = (season.get("routes", []) as Array).duplicate(true)
	working["beta110_followups"] = (followups.get("followups", []) as Array).duplicate(true)
	working["beta110_execution_defaults"] = (followups.get("execution_defaults", {}) as Dictionary).duplicate(true)
	working["beta110_echoes"] = (echoes.get("echoes", []) as Array).duplicate(true)
	working["beta110_reviews"] = (reviews.get("reviews", []) as Array).duplicate(true)
	working["beta110_accountability_effects"] = ((loaded_content["accountability_effects"] as Dictionary).get("case_effects", []) as Array).duplicate(true)
	var character_arcs: Dictionary = loaded_content["character_arcs"] as Dictionary
	working["core_character_ids"] = (character_arcs.get("core_character_ids", working.get("core_character_ids", [])) as Array).duplicate(true)
	working["character_arcs_beta_1_10"] = (character_arcs.get("arcs", {}) as Dictionary).duplicate(true)
	working["beta110_character_arcs"] = character_arcs.duplicate(true)
	working["character_initiatives_beta_1_11"] = (initiatives_payload as Dictionary).duplicate(true)
	working["faction_bargains_beta_1_11"] = bargains_payload.duplicate(true)
	working["beta111_faction_bargains"] = (bargains_payload.get("bargains", []) as Array).duplicate(true)
	working["characters"] = _attach_character_initiatives(
		working.get("characters", []),
		(initiatives_payload as Dictionary).get("initiatives", {})
	)

	var governance_result := Beta109CampaignLoaderScript._apply_governance_memorial_overrides(working, followups)
	if not bool(governance_result.get("ok", false)):
		return governance_result
	working = governance_result.get("data", working)
	var report_template_result := Beta109CampaignLoaderScript._apply_governance_report_overrides(working, season)
	if not bool(report_template_result.get("ok", false)):
		return report_template_result
	working = report_template_result.get("data", working)

	var tang_content_keys := [
		"offices_catalog",
		"recruitment_events",
		"audience_dialogues",
		"examination_questions",
		"clan_petitions",
		"tang_clans_definition",
		"tang_traits_definition",
		"tang_clan_characters_expansion"
	]
	for content_key in tang_content_keys:
		if (content_files as Dictionary).has(content_key):
			var res := _load_required_json(base_path, content_files as Dictionary, content_key)
			if bool(res.get("ok", false)) and res.get("data") is Dictionary:
				working[content_key] = (res.get("data") as Dictionary).duplicate(true)

	if working.has("tang_clan_characters_expansion") and working.get("tang_clan_characters_expansion") is Dictionary:
		working["characters"] = _merge_clan_characters_expansion(
			working.get("characters", []),
			working.get("tang_clan_characters_expansion") as Dictionary
		)

	var validation := ContentValidatorScript.validate(working)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "error": "BETA 1.10 content contract: " + ",".join(validation.get("errors", []))}
	return {"ok": true, "data": working.duplicate(true)}

static func _attach_character_initiatives(characters: Array, initiatives: Dictionary) -> Array:
	var enriched: Array = []
	for raw_character in characters:
		if not raw_character is Dictionary:
			continue
		var character: Dictionary = (raw_character as Dictionary).duplicate(true)
		var character_id := str(character.get("id", ""))
		var model: Dictionary = character.get("active_action_model", {}).duplicate(true) if character.get("active_action_model", {}) is Dictionary else {}
		if initiatives.get(character_id, null) is Array:
			model["fate_initiatives"] = (initiatives.get(character_id) as Array).duplicate(true)
			character["active_action_model"] = model
		enriched.append(character)
	return enriched

static func _merge_clan_characters_expansion(existing_characters: Array, expansion_dict: Dictionary) -> Array:
	var result := existing_characters.duplicate(true)
	var existing_ids: Dictionary = {}
	for c in result:
		if c is Dictionary:
			existing_ids[str(c.get("id", ""))] = true
	var pools: Array = [
		expansion_dict.get("tier_2_elites", []),
		expansion_dict.get("tier_3_backups", [])
	]
	for pool in pools:
		if pool is Array:
			for raw in pool:
				if raw is Dictionary:
					var char_id := str((raw as Dictionary).get("id", ""))
					if not char_id.is_empty() and not existing_ids.has(char_id):
						result.append((raw as Dictionary).duplicate(true))
						existing_ids[char_id] = true
	return result

static func _materialize_followup_execution_defaults(inherited: Dictionary, raw_followups: Dictionary) -> Dictionary:
	var governance: Dictionary = inherited.get("governance", {}).duplicate(true) if inherited.get("governance", {}) is Dictionary else {}
	var templates: Array = governance.get("memorial_templates", []) if governance.get("memorial_templates", []) is Array else []
	var templates_by_id: Dictionary = {}
	for raw_template in templates:
		if raw_template is Dictionary:
			templates_by_id[str((raw_template as Dictionary).get("memorial_id", ""))] = raw_template
	var topic_rules: Dictionary = governance.get("topic_rules", {}).duplicate(true) if governance.get("topic_rules", {}) is Dictionary else {}
	var execution_defaults: Dictionary = raw_followups.get("execution_defaults", {}) if raw_followups.get("execution_defaults", {}) is Dictionary else {}
	var materialized: Array = []
	for raw_entry in _collection_entries(raw_followups, "followups"):
		if not raw_entry is Dictionary:
			return _fail("BETA 1.10 followup entry must be a dictionary")
		var entry: Dictionary = (raw_entry as Dictionary).duplicate(true)
		var predecessor_id := str(entry.get("previous_memorial_id", "")).strip_edges()
		var predecessor: Dictionary = templates_by_id.get(predecessor_id, {}) if templates_by_id.get(predecessor_id, {}) is Dictionary else {}
		if predecessor.is_empty():
			return _fail("BETA 1.10 followup predecessor is unavailable: " + predecessor_id)
		var topic := str(entry.get("topic", "")).strip_edges()
		var defaults: Dictionary = execution_defaults.get(topic, {}) if execution_defaults.get(topic, {}) is Dictionary else {}
		if defaults.is_empty():
			return _fail("BETA 1.10 followup execution defaults are unavailable: " + topic)
		for key in ["resource_keys", "recommended_executor_ids"]:
			if not entry.has(key) and defaults.get(key, null) is Array:
				entry[key] = (defaults.get(key) as Array).duplicate(true)
		for key in ["visible_facts", "visible_resistance"]:
			if not entry.has(key) and predecessor.get(key, null) is Array:
				entry[key] = (predecessor.get(key) as Array).duplicate(true)
		var topic_rule := {
			"action_id": str(defaults.get("action_id", "")),
			"required_offices": (defaults.get("required_offices", []) as Array).duplicate(true),
			"opening_question": str(defaults.get("opening_question", "")),
			"council_rules": {},
			"clauses": []
		}
		topic_rules[topic] = topic_rule
		materialized.append(entry)
	governance["topic_rules"] = topic_rules
	var followups := raw_followups.duplicate(true)
	followups["followups"] = materialized
	return {"ok": true, "followups": followups, "governance": governance}

static func _merge_collection(base_value: Variant, delta_value: Variant, collection_key: String) -> Dictionary:
	var merged: Array = _collection_entries(base_value, collection_key)
	var index_by_id: Dictionary = {}
	for entry in merged:
		if entry is Dictionary:
			var existing_id := str((entry as Dictionary).get("memorial_id", (entry as Dictionary).get("echo_id", "")))
			if not existing_id.is_empty(): index_by_id[existing_id] = merged.find(entry)
	for entry in _collection_entries(delta_value, collection_key):
		if not entry is Dictionary: continue
		var entry_id := str((entry as Dictionary).get("memorial_id", (entry as Dictionary).get("echo_id", "")))
		if entry_id.is_empty(): continue
		if index_by_id.has(entry_id):
			var updated := (merged[int(index_by_id[entry_id])] as Dictionary).duplicate(true)
			updated.merge((entry as Dictionary).duplicate(true), true)
			merged[int(index_by_id[entry_id])] = updated
		else:
			index_by_id[entry_id] = merged.size()
			merged.append((entry as Dictionary).duplicate(true))
	return {collection_key: merged}

static func _collection_entries(value: Variant, collection_key: String) -> Array:
	if value is Array:
		return (value as Array).duplicate(true)
	if not value is Dictionary:
		return []
	var dictionary: Dictionary = value
	if dictionary.get(collection_key, null) is Array:
		return (dictionary.get(collection_key) as Array).duplicate(true)
	for key in ["entries", "items", "memorial_overrides", "memorial_templates"]:
		if dictionary.get(key, null) is Array:
			return (dictionary.get(key) as Array).duplicate(true)
	return []

static func _load_manifest(base_path: String, reference: String) -> Dictionary:
	return _load_required_json(base_path, {"base_manifest": reference}, "base_manifest")

static func _load_required_json(base_path: String, content_files: Dictionary, key: String) -> Dictionary:
	var reference: Variant = content_files.get(key, null)
	if not reference is String or str(reference).strip_edges().is_empty():
		return _fail("BETA 1.10 content reference missing: " + key)
	var relative_path := str(reference).strip_edges()
	if relative_path.begins_with("/") or relative_path.begins_with("\\") or relative_path.contains(":") or relative_path.contains("..") or not relative_path.to_lower().ends_with(".json"):
		return _fail("BETA 1.10 content reference invalid: " + key)
	var path := base_path.path_join(relative_path)
	if not FileAccess.file_exists(path):
		return _fail("BETA 1.10 content file missing: " + relative_path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null or not (parsed is Dictionary or parsed is Array):
		return _fail("BETA 1.10 content file invalid: " + relative_path)
	return {"ok": true, "data": parsed}

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
