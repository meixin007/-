extends RefCounted

class_name Beta109CampaignLoader

const Beta108CampaignLoaderScript = preload("res://scripts/domain/beta_1_08_campaign_loader.gd")
const ContentValidatorScript = preload("res://scripts/domain/beta_1_09_content_validator.gd")

const REQUIRED_CONTENT_KEYS := [
	"political_season",
	"governance_followups",
	"political_echoes",
	"political_season_review"
]

static func compose(base_data: Dictionary, campaign: Dictionary, base_path: String) -> Dictionary:
	var base_result := Beta108CampaignLoaderScript.compose_base(base_data, campaign, base_path)
	if not bool(base_result.get("ok", false)):
		return base_result
	var content_files: Variant = campaign.get("content_files", null)
	if not content_files is Dictionary:
		return _fail("BETA 1.09 content_files must be a dictionary")

	var loaded_content: Dictionary = {}
	for key in REQUIRED_CONTENT_KEYS:
		var content_result := _load_required_json(base_path, content_files as Dictionary, key)
		if not bool(content_result.get("ok", false)):
			return content_result
		loaded_content[key] = content_result.get("data")

	var working: Dictionary = (base_result.get("data", {}) as Dictionary).duplicate(true)
	working["schema_version"] = 109
	working["campaign_id"] = str(campaign.get("campaign_id", "anshi_beta_1_09"))
	working["campaign_days"] = int(campaign.get("campaign_days", 90))
	working["scenario"] = (campaign.get("scenario", working.get("scenario", {})) as Dictionary).duplicate(true)
	working["phases"] = (campaign.get("phases", []) as Array).duplicate(true)
	working["content_files"] = (content_files as Dictionary).duplicate(true)
	working["political_season"] = loaded_content["political_season"]
	working["governance_followups"] = loaded_content["governance_followups"]
	working["political_echoes"] = loaded_content["political_echoes"]
	working["political_season_review"] = loaded_content["political_season_review"]

	var governance_result := _apply_governance_memorial_overrides(working, loaded_content["governance_followups"])
	if not bool(governance_result.get("ok", false)):
		return governance_result
	working = governance_result.get("data", working)
	var report_template_result := _apply_governance_report_overrides(working, loaded_content["political_season"])
	if not bool(report_template_result.get("ok", false)):
		return report_template_result
	working = report_template_result.get("data", working)

	var validation := ContentValidatorScript.validate(working)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "error": "BETA 1.09 content contract: " + ",".join(validation.get("errors", []))}
	return {"ok": true, "data": working.duplicate(true)}

static func _load_required_json(base_path: String, content_files: Dictionary, key: String) -> Dictionary:
	var reference: Variant = content_files.get(key, null)
	if not reference is String or str(reference).strip_edges().is_empty():
		return _fail("BETA 1.09 content reference missing: " + key)
	var relative_path := str(reference).strip_edges()
	if relative_path.begins_with("/") or relative_path.begins_with("\\") or relative_path.contains(":") or relative_path.contains("..") or not relative_path.to_lower().ends_with(".json"):
		return _fail("BETA 1.09 content reference invalid: " + key)
	var path := base_path.path_join(relative_path)
	if not FileAccess.file_exists(path):
		return _fail("BETA 1.09 content file missing: " + relative_path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null or not (parsed is Dictionary or parsed is Array):
		return _fail("BETA 1.09 content file invalid: " + relative_path)
	return {"ok": true, "data": parsed}

static func _apply_governance_memorial_overrides(working: Dictionary, raw_followups: Variant) -> Dictionary:
	var governance: Variant = working.get("governance", null)
	if not governance is Dictionary:
		return _fail("BETA 1.09 governance data is missing")
	var templates: Variant = (governance as Dictionary).get("memorial_templates", null)
	if not templates is Array:
		return _fail("BETA 1.09 governance memorial_templates must be an array")
	var entries := _extract_memorial_entries(raw_followups)
	var updated_templates: Array = (templates as Array).duplicate(true)
	var seen_entries: Dictionary = {}
	for raw_entry in entries:
		if not raw_entry is Dictionary:
			return _fail("BETA 1.09 followup entry must be a dictionary")
		var entry := _normalise_memorial_entry(raw_entry as Dictionary)
		var memorial_id := str(entry.get("memorial_id", ""))
		if memorial_id.is_empty():
			return _fail("BETA 1.09 followup entry has no memorial_id")
		if seen_entries.has(memorial_id):
			return _fail("BETA 1.09 duplicate followup memorial_id: " + memorial_id)
		seen_entries[memorial_id] = true
		var existing_index := _find_memorial_index(updated_templates, memorial_id)
		if existing_index >= 0:
			var merged := (updated_templates[existing_index] as Dictionary).duplicate(true)
			merged.merge(entry, true)
			updated_templates[existing_index] = merged
		else:
			updated_templates.append(entry.duplicate(true))

	var seen_memorial_ids: Dictionary = {}
	for raw_template in updated_templates:
		if not raw_template is Dictionary:
			return _fail("BETA 1.09 governance memorial must be a dictionary")
		var memorial_id := str((raw_template as Dictionary).get("memorial_id", ""))
		if memorial_id.is_empty() or seen_memorial_ids.has(memorial_id):
			return _fail("BETA 1.09 duplicate governance memorial_id: " + memorial_id)
		seen_memorial_ids[memorial_id] = true
	var merged_governance := (governance as Dictionary).duplicate(true)
	merged_governance["memorial_templates"] = updated_templates
	var result := working.duplicate(true)
	result["governance"] = merged_governance
	return {"ok": true, "data": result}

static func _apply_governance_report_overrides(working: Dictionary, raw_season: Variant) -> Dictionary:
	if not raw_season is Dictionary:
		return _fail("BETA 1.09 political_season is missing")
	var season: Dictionary = raw_season
	var raw_templates: Variant = season.get("report_templates", {})
	var raw_topic_families: Variant = season.get("report_template_families_by_topic", {})
	if not raw_templates is Dictionary or not raw_topic_families is Dictionary:
		return _fail("BETA 1.09 report template overrides are invalid")
	var governance: Variant = working.get("governance", null)
	if not governance is Dictionary:
		return _fail("BETA 1.09 governance data is missing")
	var merged_governance := (governance as Dictionary).duplicate(true)
	var report_templates: Variant = merged_governance.get("report_templates", {})
	if not report_templates is Dictionary:
		return _fail("BETA 1.09 governance report_templates must be a dictionary")
	var merged_templates := (report_templates as Dictionary).duplicate(true)
	merged_templates.merge((raw_templates as Dictionary).duplicate(true), true)
	merged_governance["report_templates"] = merged_templates
	var topic_rules: Variant = merged_governance.get("topic_rules", {})
	if not topic_rules is Dictionary:
		return _fail("BETA 1.09 governance topic_rules must be a dictionary")
	var updated_topic_rules := (topic_rules as Dictionary).duplicate(true)
	for raw_topic in (raw_topic_families as Dictionary).keys():
		var topic := str(raw_topic).strip_edges()
		var family := str((raw_topic_families as Dictionary).get(raw_topic, "")).strip_edges()
		if topic.is_empty() or family.is_empty() or not updated_topic_rules.has(topic) or not updated_topic_rules[topic] is Dictionary:
			return _fail("BETA 1.09 report template topic is invalid: " + topic)
		var rule := (updated_topic_rules[topic] as Dictionary).duplicate(true)
		rule["report_template_family"] = family
		updated_topic_rules[topic] = rule
	merged_governance["topic_rules"] = updated_topic_rules
	var result := working.duplicate(true)
	result["governance"] = merged_governance
	return {"ok": true, "data": result}

static func _extract_memorial_entries(raw_followups: Variant) -> Array:
	if raw_followups is Array:
		return (raw_followups as Array).duplicate(true)
	if not raw_followups is Dictionary:
		return []
	var followups: Dictionary = raw_followups
	for key in ["memorial_overrides", "followups", "memorial_templates", "overlays", "entries"]:
		if followups.get(key, null) is Array:
			return (followups.get(key) as Array).duplicate(true)
		if followups.get(key, null) is Dictionary:
			var mapped_entries: Array = []
			for memorial_id in (followups.get(key) as Dictionary).keys():
				var mapped_value: Variant = (followups.get(key) as Dictionary)[memorial_id]
				if mapped_value is Dictionary:
					var mapped_entry := (mapped_value as Dictionary).duplicate(true)
					if not mapped_entry.has("memorial_id"):
						mapped_entry["memorial_id"] = str(memorial_id)
					mapped_entries.append(mapped_entry)
			return mapped_entries
	if followups.has("memorial_id") or followups.has("id"):
		return [followups.duplicate(true)]
	return []

static func _normalise_memorial_entry(raw_entry: Dictionary) -> Dictionary:
	var entry := raw_entry.duplicate(true)
	for wrapper_key in ["template", "memorial", "memorial_template", "override"]:
		if entry.get(wrapper_key, null) is Dictionary:
			var wrapped := (entry.get(wrapper_key) as Dictionary).duplicate(true)
			for key in entry.keys():
				if key != wrapper_key and not wrapped.has(key):
					wrapped[key] = entry[key]
			entry = wrapped
			break
	if not entry.has("memorial_id") and entry.has("id"):
		entry["memorial_id"] = str(entry.get("id", ""))
	return entry

static func _find_memorial_index(templates: Array, memorial_id: String) -> int:
	for index in range(templates.size()):
		if templates[index] is Dictionary and str((templates[index] as Dictionary).get("memorial_id", "")) == memorial_id:
			return index
	return -1

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
