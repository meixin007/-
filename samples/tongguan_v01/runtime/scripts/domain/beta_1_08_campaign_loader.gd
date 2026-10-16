extends RefCounted

class_name Beta108CampaignLoader

const ContentValidatorScript = preload("res://scripts/domain/beta_1_08_content_validator.gd")
const OfficeCatalogScript = preload("res://scripts/domain/beta_1_08_office_catalog.gd")
const CaseCatalogScript = preload("res://scripts/domain/beta_1_08_case_catalog.gd")

static func compose(base_data: Dictionary, campaign: Dictionary, base_path: String) -> Dictionary:
	var merge_result := compose_base(base_data, campaign, base_path)
	if not bool(merge_result.get("ok", false)):
		return merge_result
	var validation := ContentValidatorScript.validate(merge_result.get("data", {}))
	if not bool(validation.get("ok", false)):
		return {"ok": false, "error": "BETA 1.08 content contract: " + ",".join(validation.get("errors", []))}
	return {"ok": true, "data": (merge_result.get("data", {}) as Dictionary).duplicate(true)}

static func compose_base(base_data: Dictionary, campaign: Dictionary, base_path: String) -> Dictionary:
	var working := base_data.duplicate(true)
	var merge_result := _merge_beta108_files(working, campaign, base_path)
	if not bool(merge_result.get("ok", false)):
		return merge_result
	return {"ok": true, "data": (merge_result.get("data", {}) as Dictionary).duplicate(true)}

static func _merge_beta108_files(working: Dictionary, campaign: Dictionary, base_path: String) -> Dictionary:
	var content_files: Dictionary = campaign.get("content_files", {}).duplicate(true)
	var appointments_result := _load_json(base_path.path_join(str(content_files.get("appointments", "appointments_beta_1_08.json"))))
	if not bool(appointments_result.get("ok", false)):
		return appointments_result
	var accountability_result := _load_json(base_path.path_join(str(content_files.get("accountability", "accountability_beta_1_08.json"))))
	if not bool(accountability_result.get("ok", false)):
		return accountability_result
	var first_loop_result := _load_json(base_path.path_join(str(content_files.get("first_political_loop", "first_political_loop_beta_1_08.json"))))
	if not bool(first_loop_result.get("ok", false)):
		return first_loop_result
	if not appointments_result.get("data") is Dictionary or not accountability_result.get("data") is Dictionary or not first_loop_result.get("data") is Dictionary:
		return _fail("BETA 1.08 content files must be dictionaries")
	var appointments: Dictionary = appointments_result.get("data", {})
	var accountability: Dictionary = accountability_result.get("data", {})
	var first_political_loop: Dictionary = first_loop_result.get("data", {})
	var merged := working.duplicate(true)
	merged["schema_version"] = 108
	merged["campaign_id"] = str(campaign.get("campaign_id", "anshi_beta_1_08"))
	merged["campaign_days"] = int(campaign.get("campaign_days", 90))
	merged["scenario"] = (campaign.get("scenario", merged.get("scenario", {})) as Dictionary).duplicate(true)
	merged["phases"] = (campaign.get("phases", []) as Array).duplicate(true)
	merged["content_files"] = content_files.duplicate(true)
	merged["core_character_ids"] = _string_array(campaign.get("core_character_ids", []))
	merged["core_office_ids"] = _string_array(campaign.get("core_office_ids", []))
	merged["core_case_ids"] = _string_array(campaign.get("core_case_ids", []))
	merged["qualification_matrix"] = (appointments.get("qualification_matrix", {}) as Dictionary).duplicate(true)
	merged["initial_office_overlay"] = (appointments.get("initial_office_overlay", []) as Array).duplicate(true)
	merged["office_priority"] = (appointments.get("office_priority", []) as Array).duplicate(true)
	merged["accountability_case_templates"] = (accountability.get("cases", []) as Array).duplicate(true)
	merged["beta108_appointments"] = appointments.duplicate(true)
	merged["beta108_accountability"] = accountability.duplicate(true)
	merged["first_political_loop"] = first_political_loop.duplicate(true)
	var case_content: Dictionary = {}
	for case_id in CaseCatalogScript.ids():
		var content_path := base_path.path_join(str((campaign.get("case_content_files", {}) as Dictionary).get(case_id, "")))
		var content_result := _load_json(content_path)
		if not bool(content_result.get("ok", false)):
			return content_result
		if not content_result.get("data") is Dictionary or str((content_result.get("data", {}) as Dictionary).get("case_id", "")) != case_id:
			return _fail("case content identity mismatch: " + case_id)
		case_content[case_id] = (content_result.get("data", {}) as Dictionary).duplicate(true)
	merged["beta108_case_content"] = case_content
	var arcs_result := _load_json(base_path.path_join(str(campaign.get("character_arcs_file", "beta_1_08_character_arcs.json"))))
	if not bool(arcs_result.get("ok", false)) or not arcs_result.get("data") is Dictionary:
		return _fail("BETA 1.08 character arcs are invalid")
	merged["character_arcs_beta_1_08"] = ((arcs_result.get("data", {}) as Dictionary).get("arcs", {}) as Dictionary).duplicate(true)
	merged["beta108_catalog"] = {
		"office_ids": OfficeCatalogScript.ids(),
		"case_ids": CaseCatalogScript.ids(),
		"case_template_ids": CaseCatalogScript.template_ids()
	}
	return {"ok": true, "data": merged}

static func _string_array(raw: Variant) -> Array:
	var result: Array = []
	if raw is Array or raw is PackedStringArray:
		for value in raw:
			result.append(str(value))
	return result

static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("missing file: " + path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null:
		return _fail("invalid json: " + path)
	return {"ok": true, "data": parsed}

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
