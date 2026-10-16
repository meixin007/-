extends RefCounted

class_name UnifiedCampaignLoader

const DOMAIN_KEYS := [
	"bureaucracy",
	"characters",
	"governance",
	"military",
	"events",
	"dialogues"
]

static func compose_from_manifest(manifest_path: String) -> Dictionary:
	var manifest_res := _load_json(manifest_path)
	if not bool(manifest_res.get("ok", false)):
		return manifest_res
	if not manifest_res.get("data") is Dictionary:
		return _fail("manifest payload is not a dictionary: " + manifest_path)
	var manifest: Dictionary = manifest_res.get("data", {})
	var base_dir := manifest_path.get_base_dir()
	return compose(manifest, base_dir)

static func compose(manifest: Dictionary, base_dir: String) -> Dictionary:
	var domain_files: Dictionary = manifest.get("domain_files", {}) if manifest.get("domain_files", {}) is Dictionary else {}
	var loaded_domains: Dictionary = {}
	for domain_key in DOMAIN_KEYS:
		var rel_path := str(domain_files.get(domain_key, domain_key + ".json"))
		var file_path := base_dir.path_join(rel_path)
		var file_res := _load_json(file_path)
		if not bool(file_res.get("ok", false)):
			return _fail("missing required domain file: " + rel_path + " (" + str(file_res.get("error", "")) + ")")
		if not file_res.get("data") is Dictionary:
			return _fail("domain file payload must be a dictionary: " + rel_path)
		loaded_domains[domain_key] = (file_res.get("data") as Dictionary).duplicate(true)

	var working: Dictionary = {
		"ok": true
	}

	# 1. 注入 Manifest 元数据
	working["schema_version"] = int(manifest.get("schema_version", 113))
	if str(manifest.get("campaign_id", "")).is_empty():
		return _fail("manifest requires campaign_id")
	working["campaign_id"] = str(manifest.campaign_id)
	if manifest.has("start_profiles"):
		if not manifest.start_profiles is Dictionary:
			return _fail("start_profiles must be a dictionary")
		working["start_profiles"] = manifest.start_profiles.duplicate(true)
		working["default_start_profile_id"] = str(manifest.get("default_start_profile_id", ""))
	if manifest.has("management"):
		if not manifest.management is Dictionary:
			return _fail("management configuration must be a dictionary")
		working["management"] = manifest.management.duplicate(true)
	working["campaign_title"] = str(manifest.get("campaign_title", "安史之乱"))
	working["campaign_days"] = int(manifest.get("campaign_days", 90))
	working["scenario"] = (manifest.get("scenario", {"start_phase": "opening"}) as Dictionary).duplicate(true)
	working["resources"] = (manifest.get("resources", {}) as Dictionary).duplicate(true)
	working["phases"] = (manifest.get("phases", []) as Array).duplicate(true)
	working["vertical_slice"] = (manifest.get("vertical_slice", {}) as Dictionary).duplicate(true)
	working["domain_files"] = domain_files.duplicate(true)

	# 2. 注入 Bureaucracy 领域数据
	var bur: Dictionary = loaded_domains.get("bureaucracy", {})
	working["offices_catalog"] = (bur.get("offices_catalog", {}) as Dictionary).duplicate(true)
	working["offices"] = (bur.get("offices", []) as Array).duplicate(true)
	var beta_app: Dictionary = bur.get("beta108_appointments", {}) if bur.get("beta108_appointments", {}) is Dictionary else {}
	var init_overlay: Array = bur.get("initial_office_overlay", []) as Array
	if init_overlay.is_empty() and beta_app.get("initial_office_overlay", []) is Array:
		init_overlay = beta_app.get("initial_office_overlay", []) as Array
	working["initial_office_overlay"] = init_overlay.duplicate(true)
	working["office_priority"] = (bur.get("office_priority", []) as Array).duplicate(true)
	var qual_matrix: Dictionary = bur.get("qualification_matrix", {}) if bur.get("qualification_matrix", {}) is Dictionary else {}
	if qual_matrix.is_empty() and beta_app.get("qualification_matrix", {}) is Dictionary:
		qual_matrix = beta_app.get("qualification_matrix", {}) as Dictionary
	working["qualification_matrix"] = qual_matrix.duplicate(true)
	working["examination_questions"] = (bur.get("examination_questions", {}) as Dictionary).duplicate(true)
	working["clan_petitions"] = (bur.get("clan_petitions", {}) as Dictionary).duplicate(true)
	working["beta108_appointments"] = beta_app.duplicate(true)
	working["beta108_catalog"] = (bur.get("beta108_catalog", {}) as Dictionary).duplicate(true)

	# 3. 注入 Characters 领域数据
	var cha: Dictionary = loaded_domains.get("characters", {})
	var raw_chars: Array = cha.get("characters", []) as Array
	var clean_chars: Array = []
	for c in raw_chars:
		if c is Dictionary:
			var c_id := str(c.get("id", ""))
			if not c_id.begins_with("beta06_") and not c_id.begins_with("beta07_"):
				clean_chars.append((c as Dictionary).duplicate(true))
	working["characters"] = clean_chars
	working["core_character_ids"] = (cha.get("core_character_ids", []) as Array).duplicate(true)
	working["tang_clans_definition"] = (cha.get("tang_clans_definition", {}) as Dictionary).duplicate(true)
	working["tang_traits_definition"] = (cha.get("tang_traits_definition", {}) as Dictionary).duplicate(true)
	working["tang_clan_characters_expansion"] = (cha.get("tang_clan_characters_expansion", {}) as Dictionary).duplicate(true)
	working["character_arcs"] = (cha.get("character_arcs", {}) as Dictionary).duplicate(true)
	working["character_arcs_beta_1_10"] = (cha.get("character_arcs", {}) as Dictionary).get("arcs", {})
	working["beta110_character_arcs"] = (cha.get("character_arcs", {}) as Dictionary).duplicate(true)
	working["character_initiatives_beta_1_11"] = (cha.get("character_initiatives", {}) as Dictionary).duplicate(true)
	working["faction_bargains_beta_1_11"] = (cha.get("faction_bargains", {}) as Dictionary).duplicate(true)
	working["beta111_faction_bargains"] = ((cha.get("faction_bargains", {}) as Dictionary).get("bargains", []) as Array).duplicate(true)
	working["factions"] = (cha.get("factions", []) as Array).duplicate(true)
	working["faction_agendas"] = (cha.get("faction_agendas", []) as Array).duplicate(true)

	# 4. 注入 Governance 领域数据
	var gov: Dictionary = loaded_domains.get("governance", {})
	working["governance"] = (gov.get("governance", {}) as Dictionary).duplicate(true)
	working["governance_followups"] = (gov.get("governance_followups", {}) as Dictionary).duplicate(true)
	working["political_echoes"] = (gov.get("political_echoes", {}) as Dictionary).duplicate(true)
	working["political_season"] = (gov.get("political_season", {}) as Dictionary).duplicate(true)
	working["political_season_review"] = (gov.get("political_season_review", {}) as Dictionary).duplicate(true)
	working["political_season_reviews"] = (gov.get("political_season_reviews", []) as Array).duplicate(true)
	working["accountability_effects"] = (gov.get("accountability_effects", {}) as Dictionary).duplicate(true)
	working["accountability_case_templates"] = (gov.get("accountability_case_templates", []) as Array).duplicate(true)
	working["court_meetings"] = (gov.get("court_meetings", []) as Array).duplicate(true)
	working["beta108_accountability"] = (gov.get("beta108_accountability", {}) as Dictionary).duplicate(true)
	working["beta108_case_content"] = (gov.get("beta108_case_content", {}) as Dictionary).duplicate(true)
	working["first_political_loop"] = (gov.get("first_political_loop", {}) as Dictionary).duplicate(true)
	working["beta110_followups"] = ((gov.get("governance_followups", {}) as Dictionary).get("followups", []) as Array).duplicate(true)
	working["beta110_echoes"] = ((gov.get("political_echoes", {}) as Dictionary).get("echoes", []) as Array).duplicate(true)
	working["beta110_reviews"] = (gov.get("political_season_reviews", []) as Array).duplicate(true)

	# 5. 注入 Military 领域数据
	var mil: Dictionary = loaded_domains.get("military", {})
	working["battlefronts"] = (mil.get("battlefronts", []) as Array).duplicate(true)
	working["local_nodes"] = (mil.get("local_nodes", []) as Array).duplicate(true)
	working["route_network"] = (mil.get("route_network", {}) as Dictionary).duplicate(true)
	working["regional_operations"] = (mil.get("regional_operations", []) as Array).duplicate(true)
	working["intelligence_reports"] = (mil.get("intelligence_reports", []) as Array).duplicate(true)
	working["intelligence_contradictions"] = (mil.get("intelligence_contradictions", []) as Array).duplicate(true)
	working["strategic_routes"] = (mil.get("strategic_routes", {}) as Dictionary).duplicate(true)
	working["beta110_nodes"] = (mil.get("local_nodes", []) as Array).duplicate(true)
	working["beta110_routes"] = ((mil.get("route_network", {}) as Dictionary).get("routes", []) as Array).duplicate(true)

	# 6. 注入 Events 领域数据
	var eve: Dictionary = loaded_domains.get("events", {})
	working["events"] = (eve.get("events", []) as Array).duplicate(true)
	working["important_events"] = (eve.get("important_events", []) as Array).duplicate(true)
	working["important_events_beta_1_0"] = (eve.get("important_events", []) as Array).duplicate(true)
	working["recruitment_events"] = (eve.get("recruitment_events", {}) as Dictionary).duplicate(true)
	working["key_scenes"] = (eve.get("key_scenes", []) as Array).duplicate(true)
	working["decisions"] = (eve.get("decisions", []) as Array).duplicate(true)
	working["consequence_chains"] = (eve.get("consequence_chains", []) as Array).duplicate(true)
	working["branch_evaluations"] = (eve.get("branch_evaluations", []) as Array).duplicate(true)

	# 7. 注入 Dialogues 领域数据
	var dia: Dictionary = loaded_domains.get("dialogues", {})
	working["audience_dialogues"] = (dia.get("audience_dialogues", {}) as Dictionary).duplicate(true)
	working["npc_interactions"] = (dia.get("npc_interactions", {}) as Dictionary).duplicate(true)
	working["dialogue_topics"] = (dia.get("dialogue_topics", []) as Array).duplicate(true)
	working["relationship_edges"] = (dia.get("relationship_edges", []) as Array).duplicate(true)
	working["npc_stances"] = (dia.get("npc_stances", {}) as Dictionary).duplicate(true)
	working["obligation_ledger"] = (dia.get("obligation_ledger", {}) as Dictionary).duplicate(true)
	working["npc_political_profiles"] = (dia.get("npc_political_profiles", []) as Array).duplicate(true)
	working["dialogue_intents"] = (dia.get("dialogue_intents", []) as Array).duplicate(true)
	working["dialogue_intents_beta_0_9"] = (dia.get("dialogue_intents", []) as Array).duplicate(true)
	working["conversation_consequences"] = (dia.get("conversation_consequences", {}) as Dictionary).duplicate(true)
	working["map_conversation_routes"] = (dia.get("map_conversation_routes", []) as Array).duplicate(true)
	working["information_rules"] = (dia.get("information_rules", {}) as Dictionary).duplicate(true)
	working["political_chains"] = (dia.get("political_chains", {}) as Dictionary).duplicate(true)

	# 8. 注入 Tang Recruitment Events & Clan Nominations
	var rec_path: String = "res://data/scenarios/anshi_rebellion/tang_recruitment_events.json"
	if FileAccess.file_exists(rec_path):
		var rec_res: Dictionary = _load_json(rec_path)
		if bool(rec_res.get("ok", false)) and rec_res.get("data") is Dictionary:
			var rec_data: Dictionary = rec_res["data"] as Dictionary
			working["recruitment_events"] = (rec_data.get("recruitment_events", []) as Array).duplicate(true)
			working["clan_nominations"] = (rec_data.get("clan_nominations", []) as Array).duplicate(true)
			working["camp_wanderers_pool"] = (rec_data.get("camp_wanderers_pool", []) as Array).duplicate(true)
			working["gentry_selection_pool"] = (rec_data.get("gentry_selection_pool", []) as Array).duplicate(true)

	var marriage_file := str(working.get("management", {}).get("marriage_file", ""))
	if not marriage_file.is_empty():
		var marriage_result := _load_json(base_dir.path_join(marriage_file))
		if not marriage_result.get("ok", false): return marriage_result
		var marriage_merged: Dictionary = preload("res://scripts/core/marriage_service.gd").merge_definitions(working, marriage_result.data)
		if not marriage_merged.get("ok", false): return marriage_merged
	var estate_file := str(working.get("management", {}).get("estate_file", ""))
	if not estate_file.is_empty():
		var estate_result := _load_json(base_dir.path_join(estate_file))
		if not estate_result.get("ok", false): return estate_result
		var estate_merged: Dictionary = preload("res://scripts/core/personal_estate_service.gd").merge_definitions(working, estate_result.data)
		if not estate_merged.get("ok", false): return estate_merged
	var partition_file := str(working.get("management", {}).get("partition_file", ""))
	if not partition_file.is_empty():
		var partition_result := _load_json(base_dir.path_join(partition_file))
		if not partition_result.get("ok", false): return partition_result
		var merged: Dictionary = preload("res://scripts/core/family_partition_service.gd").merge_definitions(working, partition_result.data)
		if not merged.get("ok", false): return merged
	var player_succession_file := str(working.get("management", {}).get("player_succession_file", ""))
	if not player_succession_file.is_empty():
		var loaded := _load_json(base_dir.path_join(player_succession_file))
		if not loaded.get("ok", false): return loaded
		if not loaded.data is Dictionary or loaded.data.get("source_id") != "scenario:qinghe_player_succession_756" or not loaded.data.get("rules") is Array or not loaded.data.get("content_basis") is String: return _fail("玩家接续缺少明确场景来源")
		working.management["player_succession_rules"] = loaded.data.duplicate(true)
	var succession_file := str(working.get("management", {}).get("succession_file", ""))
	if not succession_file.is_empty():
		var loaded := _load_json(base_dir.path_join(succession_file))
		if not loaded.get("ok", false): return loaded
		if not loaded.data is Dictionary or loaded.data.get("source_id") != "scenario:clan_handover_756" or not loaded.data.get("clans") is Array: return _fail("家族交接缺少实际配置来源")
		working.management["succession_rules"] = loaded.data.duplicate(true)
	var industry_file := str(working.get("management", {}).get("industry_catalog_file", ""))
	if not industry_file.is_empty():
		var loaded := _load_json(base_dir.path_join(industry_file))
		if not loaded.get("ok",false): return loaded
		var checked: Dictionary = preload("res://scripts/core/industry_catalog.gd").validate(loaded.data)
		if not checked.ok: return checked
		working["industry_catalog"] = loaded.data.duplicate(true)
	var estates_file := str(working.get("management", {}).get("regional_estates_file", ""))
	var demography_file := str(working.get("management", {}).get("regional_demography_file", ""))
	if not demography_file.is_empty():
		var loaded := _load_json(base_dir.path_join(demography_file))
		if not loaded.get("ok", false): return loaded
		var checked: Dictionary = preload("res://scripts/core/regional_demography.gd").validate(loaded.data)
		if not checked.ok: return checked
		working["regional_census"] = loaded.data.duplicate(true)
	var geography_file := str(working.get("management", {}).get("administrative_geography_file", ""))
	if not geography_file.is_empty():
		var geography_result := _load_json(base_dir.path_join(geography_file))
		if not geography_result.get("ok", false): return geography_result
		var geography: Variant = geography_result.data
		if not geography is Dictionary or geography.get("source_id") != "scenario:administrative_geography_756" or not geography.get("regional_node_bindings") is Array: return _fail("行政范围关联缺少来源与地点绑定")
		var bound_nodes := {}
		for binding in geography.regional_node_bindings:
			if not binding is Dictionary or str(binding.get("node_id", "")).is_empty() or not str(binding.get("scope_id", "")).begins_with("region:") or bound_nodes.has(binding.node_id): return _fail("行政范围关联无效或重复")
			bound_nodes[binding.node_id] = true
		if not geography.get("office_display_bindings",[]) is Array: return _fail("岗位展示范围须为数组")
		var bound_offices := {}
		for binding in geography.get("office_display_bindings",[]):
			if not binding is Dictionary or not binding.get("office_id") is String or bound_offices.has(binding.office_id) or not binding.get("scope_ids") is Array or binding.scope_ids.is_empty(): return _fail("岗位展示范围无效或重复")
			if binding.get("source_ref")!="office_catalog:"+binding.office_id or not binding.get("basis") is String or binding.basis.is_empty(): return _fail("岗位展示范围缺少原官制职责依据")
			if not working.offices_catalog.offices.any(func(office):return office.id==binding.office_id and office.get("branch") in ["wartime_commission","regional_command"] and not str(office.get("responsibility_text","")).is_empty()): return _fail("岗位展示引用不存在或不适用的使职")
			var seen_scopes := {}
			for scope_id in binding.scope_ids:
				if not scope_id is String or seen_scopes.has(scope_id) or (scope_id!="country:唐" and not working.get("regional_census",{}).get("regions",{}).has(scope_id)): return _fail("岗位展示范围没有对应行政来源或重复")
				seen_scopes[scope_id]=true
			bound_offices[binding.office_id]=true
		working["administrative_geography"] = geography.duplicate(true)
	if not estates_file.is_empty():
		var estates_result := _load_json(base_dir.path_join(estates_file))
		if not estates_result.get("ok",false): return estates_result
		var estates: Variant = estates_result.get("data")
		if not estates is Dictionary or estates.get("source_id") != "scenario:regional_estates_756" or not estates.get("content_basis") is String or not estates.get("initial_assets") is Array: return _fail("地产内容缺少明确来源与资产定义")
		for asset in estates.initial_assets:
			if not asset is Dictionary or str(asset.get("asset_id","")).is_empty() or working.management.initial_assets.any(func(existing):return existing.get("asset_id")==asset.asset_id): return _fail("地产内容资产重复或无效")
			working.management.initial_assets.append(asset.duplicate(true))
		for key in ["characters", "character_cash_grants", "ration_grants", "commodity_grants"]:
			if not estates.get(key, []) is Array: return _fail("地产人物与初始资源须为数组")
		if not estates.get("life_models", {}) is Dictionary: return _fail("地产人物生活配置无效")
		for person in estates.get("characters", []):
			if not person is Dictionary or str(person.get("id", "")).is_empty() or working.characters.any(func(old): return old.id == person.id): return _fail("地产人物重复或缺少标识")
			working.characters.append(person.duplicate(true))
		for grant in estates.get("character_cash_grants", []):
			working.management.character_cash_grants.append(grant.duplicate(true))
			working.management.initial_presence.append({"character_id":grant.get("character_id"),"location_id":grant.get("location_id"),"source_id":estates.source_id})
		working.management.ration_grants.append_array(estates.get("ration_grants", []).duplicate(true))
		if not working.management.get("commodity_grants", []) is Array: return _fail("商品初始库存须为数组")
		if not working.management.has("commodity_grants"): working.management["commodity_grants"] = []
		working.management.commodity_grants.append_array(estates.get("commodity_grants", []).duplicate(true))
		for id in estates.get("life_models", {}):
			if working.management.life_models.has(id): return _fail("地产人物生活配置重复")
			working.management.life_models[id] = estates.life_models[id].duplicate(true)
	var regional_file := str(working.get("management", {}).get("regional_administration_file", ""))
	var criminal_file := str(working.get("management", {}).get("criminal_cases_file", ""))
	if not criminal_file.is_empty():
		var criminal_result := _load_json(base_dir.path_join(criminal_file))
		if not criminal_result.get("ok", false): return criminal_result
		var config: Variant = criminal_result.get("data")
		if not config is Dictionary or config.get("source_id") != "scenario:criminal_case_game_model_756" or not config.get("characters") is Array or not config.get("initial_cases") is Array or not config.get("jurisdictions") is Array or not config.get("historical_sources") is Array or not config.get("content_basis") is String: return _fail("刑事场景缺少来源与领域配置")
		working.management["criminal_cases"] = config.duplicate(true)
		for character in config.characters:
			if not character is Dictionary or character.get("source_id") != config.source_id: return _fail("刑事场景人物没有世界来源")
			if not character.get("id") is String or character.id.is_empty() or working.characters.any(func(existing): return existing.get("id") == character.id): return _fail("刑事场景人物重复或缺少身份")
			working.characters.append(character.duplicate(true))
			working.management.character_cash_grants.append({"character_id": character.id, "location_id": character.location_id, "amount": 0, "source_id": config.source_id})
			working.management.initial_presence.append({"character_id": character.id, "location_id": character.location_id, "source_id": config.source_id})
	if not regional_file.is_empty():
		var regional_result := _load_json(base_dir.path_join(regional_file))
		if not regional_result.get("ok", false): return regional_result
		var regional: Variant = regional_result.get("data")
		if not regional is Dictionary or not str(regional.get("source_id", "")).begins_with("scenario:") or not regional.get("content_basis") is String:
			return _fail("regional administration has no declared scenario basis")
		for field in ["characters", "local_nodes", "offices", "organizations", "initial_terms", "public_accounts", "character_cash_grants"]:
			if not regional.get(field) is Array: return _fail("regional administration requires " + field)
		working.management["regional_administration"] = regional.duplicate(true)
		if not regional.get("clan_definitions", []) is Array or not regional.get("clan_cash_locations", []) is Array: return _fail("regional family estate definitions are invalid")
		for clan in regional.get("clan_definitions", []):
			if not clan is Dictionary or str(clan.get("clan_id", "")).is_empty() or not str(clan.get("source_id", "")).begins_with("scenario:") or str(clan.get("content_basis", "")).is_empty(): return _fail("regional family estate has no declared source")
			if working.tang_clans_definition.clans.any(func(existing): return existing.get("clan_id") == clan.clan_id): return _fail("regional family estate is duplicated")
			working.tang_clans_definition.clans.append(clan.duplicate(true))
		for location in regional.get("clan_cash_locations", []):
			if not location is Dictionary or not regional.get("clan_definitions", []).any(func(clan): return clan.clan_id == location.get("clan_id") and clan.source_id == location.get("source_id")): return _fail("regional family estate location has no matching source")
			if working.management.clan_cash_locations.any(func(existing): return existing.get("clan_id") == location.clan_id): return _fail("regional family estate location is duplicated")
			working.management.clan_cash_locations.append(location.duplicate(true))
		for field in ["characters", "local_nodes"]:
			var key := "id" if field == "characters" else "node_id"
			for entry in regional[field]:
				if not entry is Dictionary or str(entry.get(key, "")).is_empty() or working[field].any(func(existing): return existing.get(key) == entry[key]): return _fail("regional administration has duplicate or invalid " + field)
				working[field].append(entry.duplicate(true))
		for office in regional.offices:
			if not office is Dictionary or str(office.get("id", "")).is_empty() or working.offices_catalog.offices.any(func(existing): return existing.get("id") == office.id): return _fail("regional administration has duplicate or invalid office")
			working.offices_catalog.offices.append(office.duplicate(true))
		for term in regional.initial_terms:
			if not term is Dictionary: return _fail("invalid regional initial term")
			working.initial_office_overlay.append(term.duplicate(true))
		if not regional.get("initial_assets", []) is Array: return _fail("regional initial assets are invalid")
		for asset in regional.get("initial_assets", []):
			if not asset is Dictionary or str(asset.get("asset_id", "")).is_empty() or working.management.initial_assets.any(func(existing): return existing.get("asset_id") == asset.asset_id): return _fail("regional initial asset is duplicated or invalid")
			working.management.initial_assets.append(asset.duplicate(true))
		working.management.character_cash_grants.append_array(regional.character_cash_grants.duplicate(true))
		if not regional.get("ration_grants", []) is Array or not regional.get("life_models", {}) is Dictionary: return _fail("regional subsistence definitions are invalid")
		working.management.ration_grants.append_array(regional.get("ration_grants", []).duplicate(true))
		for person_id in regional.get("life_models", {}):
			if working.management.life_models.has(person_id): return _fail("regional livelihood model is duplicated")
			working.management.life_models[person_id] = regional.life_models[person_id].duplicate(true)
		for grant in regional.character_cash_grants:
			if not grant is Dictionary: return _fail("invalid regional personal cash source")
			working.management.initial_presence.append({"character_id": grant.get("character_id"), "location_id": grant.get("location_id"), "source_id": regional.source_id})
	var central_file := str(working.get("management", {}).get("central_administration_file", ""))
	if not central_file.is_empty():
		var central_result := _load_json(base_dir.path_join(central_file))
		if not central_result.get("ok", false): return central_result
		var merged: Dictionary = preload("res://scripts/core/central_office_rules.gd").merge_definitions(working, central_result.get("data"))
		if not merged.get("ok", false): return merged
	var baselines_file := str(working.get("management",{}).get("regional_economic_baselines_file",""))
	if not baselines_file.is_empty():
		var loaded := _load_json(base_dir.path_join(baselines_file))
		if not loaded.get("ok",false): return loaded
		if not loaded.get("data") is Dictionary: return _fail("地区经营基准配置须为字典")
		var merged: Dictionary=preload("res://scripts/core/regional_economic_baselines.gd").merge_definitions(working,loaded.data)
		if not merged.ok: return merged
	return {"ok": true, "data": working}

static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("missing file: " + path)
	var content := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(content)
	if parsed == null:
		return _fail("invalid json syntax: " + path)
	return {"ok": true, "data": parsed}

static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}
