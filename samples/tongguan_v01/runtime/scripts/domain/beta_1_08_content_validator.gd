extends RefCounted

class_name Beta108ContentValidator

const CORE_CHARACTER_IDS := [
	"guo_ziyi", "li_bi", "li_fuguo", "li_guangbi", "pugu_huaien", "li_chu",
	"uighur_envoy", "hardline_old_court_official", "grain_official_lingwu",
	"lingwu_merchant_refugee", "regional_jiedushi_rep", "eunuch_deputy_gate"
]
const CORE_OFFICE_IDS := [
	"zhongshu_drafting", "menxia_review", "shangshu_execution", "household_supply",
	"war_mobilization", "censorate", "inner_court_gatekeeper", "envoy_negotiator"
]
const QUALIFICATION_LEVELS := ["eligible", "exceptional", "prohibited"]
const CASE_IDS := [
	"beta108_case_grain_ledger_shortfall", "beta108_case_military_grain_delay",
	"beta108_case_palace_order_leak", "beta108_case_edict_legitimacy",
	"beta108_case_uighur_aid_cost", "beta108_case_final_assessment"
]

static func validate(raw_campaign: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if int(raw_campaign.get("schema_version", 0)) != 108:
		errors.append("schema_version")
	if str(raw_campaign.get("campaign_id", "")) != "anshi_beta_1_08":
		errors.append("campaign_id")
	if int(raw_campaign.get("campaign_days", 0)) != 90:
		errors.append("campaign_days")
	if _string_array(raw_campaign.get("core_character_ids", [])) != CORE_CHARACTER_IDS:
		errors.append("core_character_ids")
	if _string_array(raw_campaign.get("core_office_ids", [])) != CORE_OFFICE_IDS:
		errors.append("core_office_ids")
	_validate_phases(raw_campaign.get("phases", []), errors)
	_validate_base_data(raw_campaign, errors)
	_validate_qualifications(raw_campaign.get("qualification_matrix", {}), errors)
	_validate_cases(raw_campaign.get("accountability_case_templates", []), errors)
	_validate_first_political_loop(raw_campaign, errors)
	if raw_campaign.has("beta108_case_content"):
		_validate_case_content(raw_campaign.get("beta108_case_content", {}), errors)
	_validate_overlay(raw_campaign.get("initial_office_overlay", []), errors)
	return {"ok": errors.is_empty(), "errors": errors.duplicate()}

static func _validate_phases(raw_phases: Variant, errors: Array[String]) -> void:
	if not raw_phases is Array or (raw_phases as Array).size() != 3:
		errors.append("phases")
		return
	var expected := [[1, 30], [31, 60], [61, 90]]
	for index in range(expected.size()):
		var phase: Variant = (raw_phases as Array)[index]
		if not phase is Dictionary or int((phase as Dictionary).get("start_day", 0)) != expected[index][0] or int((phase as Dictionary).get("end_day", 0)) != expected[index][1]:
			errors.append("phases[%d]" % index)

static func _validate_base_data(campaign: Dictionary, errors: Array[String]) -> void:
	for key in ["characters", "offices", "resources", "governance", "character_arcs_beta_1_0"]:
		var value: Variant = campaign.get(key, null)
		if value == null or (value is Array and (value as Array).is_empty()) or (value is Dictionary and (value as Dictionary).is_empty()):
			errors.append("base.%s" % key)

static func _validate_qualifications(raw_matrix: Variant, errors: Array[String]) -> void:
	if not raw_matrix is Dictionary:
		errors.append("qualification_matrix")
		return
	var matrix: Dictionary = raw_matrix
	var cell_count := 0
	var office_counts: Dictionary = {}
	for office_id in CORE_OFFICE_IDS:
		office_counts[office_id] = 0
	for character_id in CORE_CHARACTER_IDS:
		var row: Variant = matrix.get(character_id, null)
		if not row is Dictionary:
			errors.append("qualification_matrix.%s" % character_id)
			continue
		for office_id in CORE_OFFICE_IDS:
			cell_count += 1
			var cell: Variant = (row as Dictionary).get(office_id, null)
			if not cell is Dictionary:
				errors.append("qualification_matrix.%s.%s" % [character_id, office_id])
				continue
			var level := str((cell as Dictionary).get("level", ""))
			if not QUALIFICATION_LEVELS.has(level):
				errors.append("qualification_level.%s.%s" % [character_id, office_id])
			if str((cell as Dictionary).get("reason", "")).is_empty():
				errors.append("qualification_reason.%s.%s" % [character_id, office_id])
			if level != "prohibited":
				office_counts[office_id] = int(office_counts[office_id]) + 1
	if cell_count != 96:
		errors.append("qualification_matrix_count")
	for office_id in CORE_OFFICE_IDS:
		if int(office_counts.get(office_id, 0)) < 3:
			errors.append("qualification_candidates.%s" % office_id)
	for character_id in CORE_CHARACTER_IDS:
		var row: Variant = matrix.get(character_id, {})
		var has_candidate := false
		if row is Dictionary:
			for cell in (row as Dictionary).values():
				if cell is Dictionary and str((cell as Dictionary).get("level", "")) != "prohibited":
					has_candidate = true
		if not has_candidate:
			errors.append("qualification_character.%s" % character_id)

static func _validate_cases(raw_cases: Variant, errors: Array[String]) -> void:
	if not raw_cases is Array or (raw_cases as Array).size() != 6:
		errors.append("accountability_case_templates")
		return
	var seen: Dictionary = {}
	for raw_case in (raw_cases as Array):
		if not raw_case is Dictionary:
			errors.append("accountability_case_entry")
			continue
		var case_id := str((raw_case as Dictionary).get("case_id", ""))
		if not CASE_IDS.has(case_id) or seen.has(case_id):
			errors.append("accountability_case_id.%s" % case_id)
		seen[case_id] = true
		if str((raw_case as Dictionary).get("lifecycle", "")) != "dormant":
			errors.append("accountability_case_lifecycle.%s" % case_id)
		for key in ["facts", "claims", "evidence"]:
			if not ((raw_case as Dictionary).get(key, null) is Array) or not ((raw_case as Dictionary).get(key) as Array).is_empty():
				errors.append("accountability_case_%s.%s" % [key, case_id])
	if seen.size() != CASE_IDS.size():
		errors.append("accountability_case_ids")

static func _validate_first_political_loop(raw_campaign: Dictionary, errors: Array[String]) -> void:
	var raw_loop: Variant = raw_campaign.get("first_political_loop", null)
	if not raw_loop is Dictionary:
		errors.append("first_political_loop")
		return
	var loop: Dictionary = raw_loop
	if int(loop.get("schema_version", 0)) != 1:
		errors.append("first_political_loop.schema_version")
	if str(loop.get("loop_id", "")) != "beta108_first_grain_command":
		errors.append("first_political_loop.loop_id")
	var memorial_id := str(loop.get("memorial_id", ""))
	var memorial: Dictionary = {}
	var governance: Dictionary = raw_campaign.get("governance", {}) if raw_campaign.get("governance", {}) is Dictionary else {}
	for raw_memorial in governance.get("memorial_templates", []) if governance.get("memorial_templates", []) is Array else []:
		if raw_memorial is Dictionary and str((raw_memorial as Dictionary).get("memorial_id", "")) == memorial_id:
			memorial = raw_memorial
			break
	if memorial.is_empty():
		errors.append("first_political_loop.memorial")
	var topic := str(memorial.get("topic", ""))
	var topic_rules: Dictionary = governance.get("topic_rules", {}) if governance.get("topic_rules", {}) is Dictionary else {}
	var topic_rule: Dictionary = topic_rules.get(topic, {}) if topic_rules.get(topic, {}) is Dictionary else {}
	if topic_rule.is_empty():
		errors.append("first_political_loop.topic")
	var action_id := str(loop.get("direct_action_id", ""))
	if action_id.is_empty() or action_id != str(topic_rule.get("action_id", "")):
		errors.append("first_political_loop.action")
	var command_actions: Variant = governance.get("command_actions", [])
	var action_reachable := command_actions is Array and (command_actions as Array).has(action_id)
	if command_actions is Dictionary:
		action_reachable = (command_actions as Dictionary).has(action_id)
	if not action_reachable:
		errors.append("first_political_loop.command_action")
	var character_ids: Dictionary = {}
	for raw_character in raw_campaign.get("characters", []) if raw_campaign.get("characters", []) is Array else []:
		if raw_character is Dictionary:
			character_ids[str((raw_character as Dictionary).get("id", ""))] = true
	var advisers: Variant = loop.get("recommended_adviser_ids", [])
	if not advisers is Array or (advisers as Array).is_empty():
		errors.append("first_political_loop.advisers")
	else:
		for adviser_id in advisers:
			if not character_ids.has(str(adviser_id)):
				errors.append("first_political_loop.adviser.%s" % str(adviser_id))
	var deadline_offset := int(loop.get("report_due_day_offset", 0))
	if deadline_offset <= 0 or deadline_offset > int(memorial.get("deadline_days", 0)):
		errors.append("first_political_loop.deadline")
	var report_match: Variant = loop.get("first_report_match", {})
	if not report_match is Dictionary or str((report_match as Dictionary).get("kind", "")).is_empty() or str((report_match as Dictionary).get("status", "")).is_empty():
		errors.append("first_political_loop.report_match")
	var offline_exchange: Variant = loop.get("offline_exchange", {})
	if not offline_exchange is Dictionary:
		errors.append("first_political_loop.offline_exchange")
	else:
		for exchange_key in ["player_text", "adviser_text", "adviser_name"]:
			if str((offline_exchange as Dictionary).get(exchange_key, "")).strip_edges().is_empty():
				errors.append("first_political_loop.offline_exchange.%s" % exchange_key)
	if str(loop.get("offline_draft_text", "")).strip_edges().is_empty():
		errors.append("first_political_loop.offline_draft_text")
	var guidance: Variant = loop.get("guidance", {})
	if not guidance is Dictionary:
		errors.append("first_political_loop.guidance")
		return
	for guidance_key in ["open_memorial", "choose_adviser", "choose_resolution", "preview", "advance", "report"]:
		if str((guidance as Dictionary).get(guidance_key, "")).strip_edges().is_empty():
			errors.append("first_political_loop.guidance.%s" % guidance_key)

static func _validate_overlay(raw_overlay: Variant, errors: Array[String]) -> void:
	if not raw_overlay is Array or (raw_overlay as Array).size() != CORE_OFFICE_IDS.size():
		errors.append("initial_office_overlay")
		return
	var seen_offices: Dictionary = {}
	var holders: Dictionary = {}
	var vacant_count := 0
	for raw_record in (raw_overlay as Array):
		if not raw_record is Dictionary:
			errors.append("initial_office_overlay_entry")
			continue
		var record: Dictionary = raw_record
		var office_id := str(record.get("office_id", ""))
		var holder_id := str(record.get("holder_id", ""))
		if not CORE_OFFICE_IDS.has(office_id) or seen_offices.has(office_id):
			errors.append("initial_office_overlay_office.%s" % office_id)
		seen_offices[office_id] = true
		if str(record.get("status", "")) == "vacant":
			vacant_count += 1
			if not holder_id.is_empty():
				errors.append("initial_office_overlay_vacancy.%s" % office_id)
		elif not CORE_CHARACTER_IDS.has(holder_id):
			errors.append("initial_office_overlay_holder.%s" % office_id)
		elif holders.has(holder_id):
			errors.append("initial_office_overlay_duplicate_holder.%s" % holder_id)
		else:
			holders[holder_id] = office_id
	if vacant_count != 3 or holders.size() != 5:
		errors.append("initial_office_overlay_counts")

static func _validate_case_content(raw_content: Variant, errors: Array[String]) -> void:
	if not raw_content is Dictionary or (raw_content as Dictionary).size() != CASE_IDS.size():
		errors.append("case_content_count")
		return
	for case_id in CASE_IDS:
		var content: Variant = (raw_content as Dictionary).get(case_id, null)
		if not content is Dictionary:
			errors.append("case_content.%s" % case_id)
			continue
		var record: Dictionary = content
		if int(record.get("phase_open_day", 0)) < 31 or int(record.get("phase_open_day", 0)) > 90:
			errors.append("case_content_phase.%s" % case_id)
		for key in ["facts", "claims", "evidence", "available_verdicts"]:
			if not record.get(key, null) is Array or (record.get(key) as Array).is_empty():
				errors.append("case_content_%s.%s" % [key, case_id])
		if int(record.get("minimum_independent_sources", 0)) < 2:
			errors.append("case_content_sources.%s" % case_id)

static func _string_array(raw: Variant) -> Array:
	var result: Array = []
	if raw is Array or raw is PackedStringArray:
		for value in raw:
			result.append(str(value))
	return result
