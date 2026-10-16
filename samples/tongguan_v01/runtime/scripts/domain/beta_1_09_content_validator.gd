extends RefCounted

class_name Beta109ContentValidator

const Beta108ContentValidatorScript = preload("res://scripts/domain/beta_1_08_content_validator.gd")

const EXPECTED_CONTENT_KEYS := [
	"appointments", "accountability", "first_political_loop",
	"political_season", "governance_followups", "political_echoes", "political_season_review"
]
const EXPECTED_SEASON_ID := "beta109_political_season"
const EXPECTED_MEMORIAL_IDS := [
	"memorial_shuofang_grain_001",
	"memorial_lingwu_ration_001",
	"memorial_gate_review_001"
]
const EXPECTED_ACTION_IDS := [
	"prioritize_grain_transport", "verify_rations", "review_gate_records"
]
const EXPECTED_NOMINAL_WINDOWS := [[1, 3], [4, 8], [9, 14], [15, 21], [22, 27], [28, 30]]
const ALLOWED_PREDECESSOR_OUTCOMES := ["completed", "partial", "failed"]
const ALLOWED_PREDECESSOR_CONDITIONS := ["normal", "delayed", "blocked", "lost_contact"]
const ALLOWED_VARIANTS := ["normal", "partial", "failed", "delayed", "blocked", "missed"]
const REQUIRED_REVIEW_STATE_PATHS := [
	"resources.grain",
	"resources.court_authority",
	"faction_agenda_state",
	"political_debts",
	"structured_memories",
	"office_terms",
	"chronicle_causal_references"
]

static func validate(raw_campaign: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var legacy_payload := raw_campaign.duplicate(true)
	legacy_payload["schema_version"] = 108
	legacy_payload["campaign_id"] = "anshi_beta_1_08"
	var base_validation := Beta108ContentValidatorScript.validate(legacy_payload)
	if not bool(base_validation.get("ok", false)):
		for base_error in base_validation.get("errors", []):
			errors.append("base." + str(base_error))
	if int(raw_campaign.get("schema_version", 0)) != 109:
		errors.append("schema_version")
	if str(raw_campaign.get("campaign_id", "")) != "anshi_beta_1_09":
		errors.append("campaign_id")
	if int(raw_campaign.get("campaign_days", 0)) != 90:
		errors.append("campaign_days")
	_validate_phases(raw_campaign.get("phases", []), errors)
	_validate_content_files(raw_campaign.get("content_files", {}), errors)

	var known := _known_ids(raw_campaign)
	_validate_political_season(raw_campaign.get("political_season", null), known, errors)
	_validate_followups(raw_campaign.get("governance_followups", null), known, errors)
	_validate_echoes(raw_campaign.get("political_echoes", null), known, errors)
	_validate_review(raw_campaign.get("political_season_review", null), known, errors)
	_validate_unknown_references(raw_campaign.get("political_season", null), known, "political_season", errors)
	_validate_unknown_references(raw_campaign.get("governance_followups", null), known, "governance_followups", errors)
	_validate_unknown_references(raw_campaign.get("political_echoes", null), known, "political_echoes", errors)
	_validate_unknown_references(raw_campaign.get("political_season_review", null), known, "political_season_review", errors)
	_validate_cross_collection_ids(raw_campaign, errors)
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

static func _validate_content_files(raw_files: Variant, errors: Array[String]) -> void:
	if not raw_files is Dictionary:
		errors.append("content_files")
		return
	var content_files: Dictionary = raw_files
	for key in EXPECTED_CONTENT_KEYS:
		var reference: Variant = content_files.get(key, null)
		if not reference is String or str(reference).strip_edges().is_empty() or not str(reference).to_lower().ends_with(".json") or str(reference).contains(".."):
			errors.append("content_files.%s" % key)

static func _validate_political_season(raw_season: Variant, known: Dictionary, errors: Array[String]) -> void:
	if not raw_season is Dictionary:
		errors.append("political_season")
		return
	var season: Dictionary = raw_season
	if str(season.get("season_id", "")) != EXPECTED_SEASON_ID:
		errors.append("political_season.season_id")
	if season.has("schema_version") and int(season.get("schema_version", 0)) != 109:
		errors.append("political_season.schema_version")
	if season.has("campaign_id") and str(season.get("campaign_id", "")) != "anshi_beta_1_09":
		errors.append("political_season.campaign_id")
	for window_key in ["day_window", "window", "activation_window"]:
		if season.has(window_key) and not _valid_day_window(season.get(window_key)):
			errors.append("political_season.%s" % window_key)
	if season.has("branches") and _collection_from_first_key(season, ["branches"]).is_empty():
		errors.append("political_season.branches")
	if season.has("outcome_variants"):
		var season_variants: Variant = season.get("outcome_variants")
		if _collection_from_first_key(season, ["outcome_variants"]).is_empty():
			errors.append("political_season.outcome_variants")
		else:
			_validate_outcome_variants(season_variants, "political_season.outcome_variants", errors)

	var memorial_ids := _array_from_first_key(season, ["memorial_ids", "main_memorial_ids"])
	if memorial_ids.size() != EXPECTED_MEMORIAL_IDS.size() or not _same_set(memorial_ids, EXPECTED_MEMORIAL_IDS):
		errors.append("political_season.memorial_ids")
	_validate_unique_strings(memorial_ids, "political_season.memorial_ids", errors)
	for memorial_id in memorial_ids:
		if not known.memorial_ids.has(str(memorial_id)):
			errors.append("political_season.unknown_memorial.%s" % str(memorial_id))

	var action_ids := _array_from_first_key(season, ["action_ids", "main_action_ids"])
	if action_ids.size() != EXPECTED_ACTION_IDS.size() or not _same_set(action_ids, EXPECTED_ACTION_IDS):
		errors.append("political_season.action_ids")
	_validate_unique_strings(action_ids, "political_season.action_ids", errors)
	for action_id in action_ids:
		if not known.action_ids.has(str(action_id)):
			errors.append("political_season.unknown_action.%s" % str(action_id))

	var windows := _array_from_first_key(season, ["windows", "day_windows", "stages"])
	if windows.size() < EXPECTED_NOMINAL_WINDOWS.size():
		errors.append("political_season.windows")
	else:
		for index in range(EXPECTED_NOMINAL_WINDOWS.size()):
			var window: Variant = windows[index]
			if not _valid_day_window(window):
				errors.append("political_season.window.%d" % index)
				continue
			if int((window as Dictionary).get("start_day", 0)) != EXPECTED_NOMINAL_WINDOWS[index][0] or int((window as Dictionary).get("end_day", 0)) != EXPECTED_NOMINAL_WINDOWS[index][1]:
				errors.append("political_season.nominal_window.%d" % index)

	var appointment_window: Variant = season.get("appointment_window", null)
	if not _valid_day_window(appointment_window):
		errors.append("political_season.appointment_window")
	else:
		var appointment: Dictionary = appointment_window
		if int(appointment.get("start_day", 0)) != 12 or int(appointment.get("end_day", 0)) != 20:
			errors.append("political_season.appointment_window.days")
		if str(appointment.get("office_id", "")) != "menxia_review" or not known.office_ids.has(str(appointment.get("office_id", ""))):
			errors.append("political_season.appointment_window.office")

	var meanings := _array_from_first_key(season, ["appointment_meanings", "appointment_options", "appointment_candidates"])
	if meanings.size() < 2:
		errors.append("political_season.appointment_meanings")
	else:
		var meaning_ids: Array = []
		for raw_meaning in meanings:
			if not raw_meaning is Dictionary:
				errors.append("political_season.appointment_meaning_entry")
				continue
			var meaning: Dictionary = raw_meaning
			var candidate_id := str(meaning.get("candidate_id", meaning.get("character_id", "")))
			if candidate_id.is_empty() or not known.character_ids.has(candidate_id):
				errors.append("political_season.appointment_candidate.%s" % candidate_id)
			else:
				meaning_ids.append(candidate_id)
			if str(meaning.get("meaning_id", meaning.get("id", ""))).is_empty() or _public_text(meaning).is_empty():
				errors.append("political_season.appointment_meaning_text")
		_validate_unique_strings(meaning_ids, "political_season.appointment_candidates", errors)

	var routes: Variant = season.get("routes", null)
	if not routes is Array or (routes as Array).size() < 2:
		errors.append("political_season.routes")
	else:
		var route_ids: Array = []
		for raw_route in routes:
			if not raw_route is Dictionary:
				errors.append("political_season.route_entry")
				continue
			var route: Dictionary = raw_route
			var route_id := str(route.get("route_id", route.get("id", "")))
			if route_id.is_empty():
				errors.append("political_season.route_id")
			else:
				route_ids.append(route_id)
			var branches: Variant = _collection_from_first_key(route, ["branches", "steps", "decisions"])
			if branches.is_empty():
				errors.append("political_season.route_branches.%s" % route_id)
			var outcomes: Variant = _collection_from_first_key(route, ["outcome_variants", "outcomes", "variants"])
			if outcomes.is_empty():
				errors.append("political_season.route_outcomes.%s" % route_id)
			else:
				_validate_outcome_variants(outcomes, "political_season.route_outcomes.%s" % route_id, errors)
		_validate_unique_strings(route_ids, "political_season.route_ids", errors)
		if not route_ids.has("audit_then_transport") or not route_ids.has("frontline_urgent"):
			errors.append("political_season.required_routes")

	var participants := _collect_participants(season, meanings, routes)
	if participants.size() > 8:
		errors.append("political_season.participating_core_characters")

static func _validate_followups(raw_followups: Variant, known: Dictionary, errors: Array[String]) -> void:
	var entries := _content_entries(raw_followups, ["followups", "memorial_overrides", "memorial_templates", "overlays", "entries"])
	if entries.is_empty():
		errors.append("governance_followups.entries")
		return
	var ids: Array = []
	for raw_entry in entries:
		if not raw_entry is Dictionary:
			errors.append("governance_followups.entry")
			continue
		var entry: Dictionary = raw_entry
		var memorial_id := str(entry.get("memorial_id", entry.get("id", "")))
		if memorial_id.is_empty() or not known.memorial_ids.has(memorial_id):
			errors.append("governance_followups.unknown_memorial.%s" % memorial_id)
		else:
			ids.append(memorial_id)
		var predecessor_id := str(entry.get("previous_memorial_id", entry.get("predecessor_memorial_id", entry.get("source_memorial_id", ""))))
		if not predecessor_id.is_empty():
			if not known.memorial_ids.has(predecessor_id) or predecessor_id == memorial_id:
				errors.append("governance_followups.predecessor.%s" % memorial_id)
		var window: Variant = entry.get("activation_window", entry.get("day_window", null))
		if window != null and not _valid_day_window(window):
			errors.append("governance_followups.window.%s" % memorial_id)
		_validate_predicate_array(entry.get("predecessor_outcomes", []), ALLOWED_PREDECESSOR_OUTCOMES, "governance_followups.outcomes.%s" % memorial_id, errors)
		_validate_predicate_array(entry.get("predecessor_conditions", []), ALLOWED_PREDECESSOR_CONDITIONS, "governance_followups.conditions.%s" % memorial_id, errors)
		var variants: Variant = _collection_from_first_key(entry, ["variants", "outcome_variants", "activation_variants"])
		if not variants.is_empty():
			_validate_outcome_variants(variants, "governance_followups.variants.%s" % memorial_id, errors)
	_validate_unique_strings(ids, "governance_followups.ids", errors)

static func _validate_echoes(raw_echoes: Variant, known: Dictionary, errors: Array[String]) -> void:
	var entries := _content_entries(raw_echoes, ["echoes", "items", "entries"])
	if entries.size() < 4:
		errors.append("political_echoes.count")
	var ids: Array = []
	for raw_echo in entries:
		if not raw_echo is Dictionary:
			errors.append("political_echoes.entry")
			continue
		var echo: Dictionary = raw_echo
		var echo_id := str(echo.get("echo_id", echo.get("id", "")))
		if echo_id.is_empty():
			errors.append("political_echoes.id")
		else:
			ids.append(echo_id)
		var source_memorial_id := str(echo.get("source_memorial_id", ""))
		var source_order_id := str(echo.get("source_order_id", ""))
		if source_memorial_id.is_empty() and source_order_id.is_empty():
			errors.append("political_echoes.source.%s" % echo_id)
		if not source_memorial_id.is_empty() and not known.memorial_ids.has(source_memorial_id):
			errors.append("political_echoes.unknown_memorial.%s" % echo_id)
		var trigger_outcomes := _string_array(echo.get("trigger_outcomes", []))
		var trigger_conditions := _string_array(echo.get("trigger_conditions", []))
		if trigger_outcomes.is_empty() and trigger_conditions.is_empty():
			errors.append("political_echoes.triggers.%s" % echo_id)
		var window: Variant = echo.get("day_window", echo.get("window", null))
		if not _valid_day_window(window):
			errors.append("political_echoes.window.%s" % echo_id)
		var has_target := not str(echo.get("target_character_id", "")).is_empty() or not str(echo.get("target_faction_id", "")).is_empty() or not str(echo.get("target_npc_action_id", "")).is_empty()
		if not has_target:
			errors.append("political_echoes.target.%s" % echo_id)
		if _public_text(echo).is_empty():
			errors.append("political_echoes.public_text.%s" % echo_id)
	_validate_unique_strings(ids, "political_echoes.ids", errors)

static func _validate_review(raw_review: Variant, known: Dictionary, errors: Array[String]) -> void:
	if not raw_review is Dictionary:
		errors.append("political_season_review")
		return
	var review: Dictionary = raw_review
	if str(review.get("review_id", review.get("id", ""))).is_empty():
		errors.append("political_season_review.id")
	if review.has("day") and int(review.get("day", 0)) != 30:
		errors.append("political_season_review.day")
	var sources := _array_from_first_key(review, ["sources", "source_paths", "source_refs", "source_references"])
	if sources.is_empty():
		errors.append("political_season_review.sources")
	var state_paths := _string_array(review.get("state_paths", review.get("fields", [])))
	for required_path in REQUIRED_REVIEW_STATE_PATHS:
		if not state_paths.has(required_path):
			errors.append("political_season_review.state_path.%s" % required_path)
	var preview: Variant = review.get("accountability_preview", review.get("next_phase_preview", null))
	if not preview is Dictionary:
		errors.append("political_season_review.accountability_preview")
	else:
		var case_id := str((preview as Dictionary).get("case_id", ""))
		if case_id.is_empty() or not known.case_ids.has(case_id):
			errors.append("political_season_review.case_id")
		if int((preview as Dictionary).get("open_day", 0)) != 31:
			errors.append("political_season_review.open_day")

static func _validate_cross_collection_ids(raw_campaign: Dictionary, errors: Array[String]) -> void:
	var seen: Dictionary = {}
	for collection_spec in [
		{"root": raw_campaign.get("political_season", {}), "keys": ["routes", "appointment_meanings", "appointment_options", "appointment_candidates"], "label": "political_season"},
		{"root": raw_campaign.get("political_echoes", {}), "keys": ["echoes", "items", "entries"], "label": "political_echoes"}
	]:
		var root: Variant = collection_spec["root"]
		if not root is Dictionary:
			continue
		for key in collection_spec["keys"]:
			var entries: Variant = (root as Dictionary).get(key, null)
			if not entries is Array:
				continue
			for raw_entry in entries:
				if not raw_entry is Dictionary:
					continue
				var entry: Dictionary = raw_entry
				var entry_id := str(entry.get("echo_id", entry.get("route_id", entry.get("meaning_id", entry.get("id", "")))))
				if entry_id.is_empty():
					continue
				if seen.has(entry_id):
					errors.append("duplicate_id.%s" % entry_id)
				seen[entry_id] = true

static func _validate_unknown_references(raw: Variant, known: Dictionary, label: String, errors: Array[String]) -> void:
	if raw is Array:
		for item in raw:
			_validate_unknown_references(item, known, label, errors)
		return
	if not raw is Dictionary:
		return
	for key in (raw as Dictionary).keys():
		var value: Variant = (raw as Dictionary)[key]
		var key_name := str(key)
		var kind := ""
		if key_name.ends_with("character_id") or key_name.ends_with("character_ids"):
			kind = "character_ids"
		elif key_name.ends_with("office_id") or key_name.ends_with("office_ids"):
			kind = "office_ids"
		elif key_name.ends_with("memorial_id") or key_name.ends_with("memorial_ids"):
			kind = "memorial_ids"
		elif key_name.ends_with("action_id") or key_name.ends_with("action_ids"):
			kind = "action_ids"
		if not kind.is_empty():
			var values := _string_array(value) if value is Array else [str(value)]
			for referenced_id in values:
				if referenced_id.is_empty():
					continue
				if not (known.get(kind, {}) as Dictionary).has(referenced_id):
					errors.append("%s.unknown_%s.%s" % [label, kind.trim_suffix("_ids"), referenced_id])
		_validate_unknown_references(value, known, label, errors)

static func _validate_predicate_array(raw: Variant, allowed: Array, label: String, errors: Array[String]) -> void:
	if raw == null:
		return
	if not raw is Array:
		errors.append(label + ".type")
		return
	if (raw as Array).is_empty():
		return
	for value in raw:
		if not allowed.has(str(value)):
			errors.append(label + ".value")

static func _validate_outcome_variants(raw: Variant, label: String, errors: Array[String]) -> void:
	var names: Array = []
	if raw is Dictionary:
		for key in (raw as Dictionary).keys():
			names.append(str(key))
	elif raw is Array:
		for item in raw:
			if item is Dictionary:
				names.append(str((item as Dictionary).get("variant", (item as Dictionary).get("outcome", (item as Dictionary).get("id", "")))))
			else:
				names.append(str(item))
	else:
		errors.append(label + ".type")
		return
	if names.is_empty():
		errors.append(label + ".empty")
		return
	var has_success := names.has("normal") or names.has("completed") or names.has("partial")
	var has_non_success := names.has("failed") or names.has("delayed") or names.has("blocked") or names.has("missed")
	if not has_success or not has_non_success:
		errors.append(label + ".missing_variant")
	for name in names:
		if not ALLOWED_VARIANTS.has(name) and name != "completed":
			errors.append(label + ".unknown_variant.%s" % name)

static func _known_ids(raw_campaign: Dictionary) -> Dictionary:
	var characters: Dictionary = {}
	for character_id in _string_array(raw_campaign.get("core_character_ids", [])):
		characters[character_id] = true
	for raw_character in raw_campaign.get("characters", []) if raw_campaign.get("characters", []) is Array else []:
		if raw_character is Dictionary:
			var character_id := str((raw_character as Dictionary).get("id", ""))
			if not character_id.is_empty():
				characters[character_id] = true
	var offices: Dictionary = {}
	for office_id in _string_array(raw_campaign.get("core_office_ids", [])):
		offices[office_id] = true
	for raw_office in raw_campaign.get("offices", []) if raw_campaign.get("offices", []) is Array else []:
		if raw_office is Dictionary:
			var office_id := str((raw_office as Dictionary).get("office_id", (raw_office as Dictionary).get("id", "")))
			if not office_id.is_empty():
				offices[office_id] = true
	var memorials: Dictionary = {}
	var governance: Dictionary = raw_campaign.get("governance", {}) if raw_campaign.get("governance", {}) is Dictionary else {}
	for raw_memorial in governance.get("memorial_templates", []) if governance.get("memorial_templates", []) is Array else []:
		if raw_memorial is Dictionary:
			var memorial_id := str((raw_memorial as Dictionary).get("memorial_id", ""))
			if not memorial_id.is_empty():
				memorials[memorial_id] = true
	var actions: Dictionary = {}
	var command_actions: Variant = governance.get("command_actions", [])
	if command_actions is Array:
		for action_id in command_actions:
			actions[str(action_id)] = true
	elif command_actions is Dictionary:
		for action_id in (command_actions as Dictionary).keys():
			actions[str(action_id)] = true
	var topic_rules: Variant = governance.get("topic_rules", {})
	if topic_rules is Dictionary:
		for raw_rule in (topic_rules as Dictionary).values():
			if raw_rule is Dictionary:
				var action_id := str((raw_rule as Dictionary).get("action_id", ""))
				if not action_id.is_empty():
					actions[action_id] = true
	var cases: Dictionary = {}
	for raw_case in raw_campaign.get("core_case_ids", []) if raw_campaign.get("core_case_ids", []) is Array else []:
		cases[str(raw_case)] = true
	for raw_case_template in raw_campaign.get("accountability_case_templates", []) if raw_campaign.get("accountability_case_templates", []) is Array else []:
		if raw_case_template is Dictionary:
			var case_id := str((raw_case_template as Dictionary).get("case_id", ""))
			if not case_id.is_empty():
				cases[case_id] = true
	return {
		"character_ids": characters,
		"office_ids": offices,
		"memorial_ids": memorials,
		"action_ids": actions,
		"case_ids": cases
	}

static func _collect_participants(season: Dictionary, meanings: Array, routes: Variant) -> Dictionary:
	var participants: Dictionary = {}
	for character_id in _string_array(season.get("participating_character_ids", season.get("participant_character_ids", []))):
		participants[character_id] = true
	for raw_meaning in meanings:
		if raw_meaning is Dictionary:
			var candidate_id := str((raw_meaning as Dictionary).get("candidate_id", (raw_meaning as Dictionary).get("character_id", "")))
			if not candidate_id.is_empty():
				participants[candidate_id] = true
	if routes is Array:
		for raw_route in routes:
			_collect_character_fields(raw_route, participants)
	return participants

static func _collect_character_fields(raw: Variant, result: Dictionary) -> void:
	if raw is Array:
		for item in raw:
			_collect_character_fields(item, result)
		return
	if not raw is Dictionary:
		return
	for key in (raw as Dictionary).keys():
		var key_name := str(key)
		var value: Variant = (raw as Dictionary)[key]
		if key_name.ends_with("character_id"):
			var character_id := str(value)
			if not character_id.is_empty():
				result[character_id] = true
		elif key_name.ends_with("character_ids"):
			for character_id in _string_array(value):
				result[character_id] = true
		_collect_character_fields(value, result)

static func _valid_day_window(raw: Variant) -> bool:
	if not raw is Dictionary:
		return false
	var start_day := int((raw as Dictionary).get("start_day", 0))
	var end_day := int((raw as Dictionary).get("end_day", 0))
	return start_day >= 1 and end_day <= 90 and start_day <= end_day

static func _array_from_first_key(raw: Dictionary, keys: Array) -> Array:
	for key in keys:
		if raw.get(key, null) is Array:
			return (raw.get(key) as Array).duplicate(true)
	return []

static func _collection_from_first_key(raw: Dictionary, keys: Array) -> Variant:
	for key in keys:
		var value: Variant = raw.get(key, null)
		if value is Array or value is Dictionary:
			return value
	return []

static func _content_entries(raw: Variant, keys: Array) -> Array:
	if raw is Array:
		return (raw as Array).duplicate(true)
	if raw is Dictionary:
		var content: Dictionary = raw
		for key in keys:
			if content.get(key, null) is Array:
				return (content.get(key) as Array).duplicate(true)
		if content.has("memorial_id") or content.has("echo_id") or content.has("id"):
			return [content.duplicate(true)]
	return []

static func _same_set(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	for value in right:
		if not left.has(value):
			return false
	return true

static func _validate_unique_strings(values: Array, label: String, errors: Array[String]) -> void:
	var seen: Dictionary = {}
	for value in values:
		var normalized := str(value)
		if normalized.is_empty() or seen.has(normalized):
			errors.append(label + ".duplicate")
		seen[normalized] = true

static func _string_array(raw: Variant) -> Array:
	var result: Array = []
	if raw is Array or raw is PackedStringArray:
		for value in raw:
			result.append(str(value))
	return result

static func _public_text(record: Dictionary) -> String:
	for key in ["public_summary", "summary", "public_text", "display_text", "title", "text"]:
		var value := str(record.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	return ""
