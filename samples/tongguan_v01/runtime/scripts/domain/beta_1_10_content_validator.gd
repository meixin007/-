extends RefCounted

class_name Beta110ContentValidator

const Beta109ContentValidatorScript = preload("res://scripts/domain/beta_1_09_content_validator.gd")

const EXPECTED_SCHEMA_VERSION := 110
const EXPECTED_CAMPAIGN_ID := "anshi_beta_1_10"
const EXPECTED_BASE_MANIFEST := "campaign_beta_1_09.json"
const EXPECTED_BASE_CAMPAIGN_ID := "anshi_beta_1_09"
const EXPECTED_PHASES := [
	{"id": "foundation", "start_day": 1, "end_day": 30},
	{"id": "supply_accountability", "start_day": 31, "end_day": 45},
	{"id": "palace_authority", "start_day": 46, "end_day": 65},
	{"id": "alliance_cost", "start_day": 66, "end_day": 90}
]
const EXPECTED_NODE_IDS := [
	"beta110_grain_case_open", "beta110_front_supply_delay", "beta110_palace_order_leak",
	"beta110_supply_review", "beta110_edict_legitimacy", "beta110_uighur_aid_cost",
	"beta110_authority_review", "beta110_final_assessment", "beta110_day90_settlement"
]
const EXPECTED_ROUTE_IDS := [
	"beta110_route_audit_continuity", "beta110_route_frontline_urgency", "beta110_route_court_consolidation"
]
const EXPECTED_ECHO_IDS := [
	"beta110_echo_grain_audit_trust", "beta110_echo_grain_continuity_cost", "beta110_echo_frontline_delivery_confidence", "beta110_echo_supply_debt", "beta110_echo_gate_authority", "beta110_echo_old_court_precedent", "beta110_echo_edict_procedure", "beta110_echo_court_authority", "beta110_echo_uighur_terms", "beta110_echo_military_credit", "beta110_echo_assessment_record", "beta110_echo_final_legacy"
]
const EXPECTED_FOLLOWUP_IDS := [
	"memorial_beta110_supply_completed", "memorial_beta110_supply_partial", "memorial_beta110_supply_delayed", "memorial_beta110_supply_blocked", "memorial_beta110_palace_completed", "memorial_beta110_palace_partial", "memorial_beta110_palace_delayed", "memorial_beta110_palace_blocked", "memorial_beta110_alliance_completed", "memorial_beta110_alliance_partial", "memorial_beta110_alliance_delayed", "memorial_beta110_alliance_blocked"
]
const EXPECTED_REVIEW_IDS := ["beta110_supply_review", "beta110_authority_review", "beta110_final_assessment"]
const EXPECTED_CASE_IDS := [
	"beta108_case_grain_ledger_shortfall", "beta108_case_military_grain_delay", "beta108_case_palace_order_leak", "beta108_case_edict_legitimacy", "beta108_case_uighur_aid_cost", "beta108_case_final_assessment"
]
const EFFECT_KEYS := ["resource_delta", "faction_reactions", "relationship_effects", "memories", "route_effects", "node_effects", "political_debt", "chronicle"]
const VALID_CONDITIONS := ["normal", "delayed", "blocked", "lost_contact", "expired"]
const VALID_OUTCOMES := ["completed", "partial", "failed", "expired"]
const EXPECTED_EXECUTION_DEFAULTS := {
	"supply_accountability": {"action_id": "verify_rations", "required_offices": ["household_supply", "censorate"], "opening_question": "粮册核验已经形成结果，如何公开凭据、补足缺页并追明责任？", "recommended_executor_ids": ["grain_official_lingwu", "li_bi"], "resource_keys": ["grain"]},
	"frontline_supply": {"action_id": "prioritize_grain_transport", "required_offices": ["war_mobilization", "household_supply"], "opening_question": "前线军粮通道受阻，应如何改道、核验收讫并保障军期？", "recommended_executor_ids": ["guo_ziyi", "li_bi"], "resource_keys": ["grain"]},
	"palace_authority": {"action_id": "review_gate_records", "required_offices": ["inner_court_gatekeeper", "censorate"], "opening_question": "宫门副本与传令记录已经汇集，应公开到何种范围并由谁留痕复核？", "recommended_executor_ids": ["li_fuguo", "chen_xuanli", "li_bi"], "resource_keys": ["court_authority"]},
	"edict_legitimacy": {"action_id": "review_gate_records", "required_offices": ["censorate", "menxia_review"], "opening_question": "诏令复核受阻，应如何保存异议、核验程序并决定暂缓范围？", "recommended_executor_ids": ["chen_xuanli", "li_bi"], "resource_keys": ["court_authority", "legitimacy"]},
	"alliance_cost": {"action_id": "verify_rations", "required_offices": ["envoy_negotiator", "household_supply"], "opening_question": "援助条款与付款凭据已经到案，应如何核定交换代价并登记履约？", "recommended_executor_ids": ["li_fuguo", "grain_official_lingwu", "li_bi"], "resource_keys": ["treasury"]},
	"final_assessment": {"action_id": "review_gate_records", "required_offices": ["zhongshu_drafting", "censorate"], "opening_question": "终局证据链尚未闭合，应如何保存异议、复核因果并完成结算？", "recommended_executor_ids": ["li_bi", "chen_xuanli"], "resource_keys": ["legitimacy", "court_authority"]}
}
const CHARACTER_FATE_IDS := ["guo_ziyi", "li_bi", "li_fuguo", "li_guangbi", "pugu_huaien", "li_chu", "uighur_envoy", "hardline_old_court_official", "grain_official_lingwu", "lingwu_merchant_refugee", "regional_jiedushi_rep", "eunuch_deputy_gate"]
const FATE_CATEGORIES := ["gained_position", "constrained", "paid_cost"]
const FATE_PREDICATE_KINDS := ["route", "case", "office", "debt", "memory", "obligation", "day"]
const FATE_REASON_KINDS := ["route", "case", "office", "review", "chronicle"]

static func validate(raw_campaign: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if int(raw_campaign.get("schema_version", 0)) != EXPECTED_SCHEMA_VERSION: errors.append("schema_version")
	if str(raw_campaign.get("campaign_id", "")) != EXPECTED_CAMPAIGN_ID: errors.append("campaign_id")
	if int(raw_campaign.get("campaign_days", 0)) != 90: errors.append("campaign_days")
	if str(raw_campaign.get("base_manifest", "")) != EXPECTED_BASE_MANIFEST: errors.append("base_manifest")
	if str(raw_campaign.get("base_campaign_id", "")) != EXPECTED_BASE_CAMPAIGN_ID: errors.append("base_campaign_id")
	_validate_phases(raw_campaign.get("phases", []), errors)
	_validate_content_files(raw_campaign.get("content_files", {}), errors)
	_validate_base_payload(raw_campaign, errors)
	_validate_nodes(raw_campaign.get("beta110_nodes", []), raw_campaign, errors)
	_validate_routes(raw_campaign.get("beta110_routes", []), raw_campaign, errors)
	_validate_followups(raw_campaign.get("beta110_followups", []), raw_campaign, errors)
	_validate_echoes(raw_campaign.get("beta110_echoes", []), raw_campaign, errors)
	_validate_reviews(raw_campaign.get("beta110_reviews", []), raw_campaign, errors)
	_validate_accountability_effects(raw_campaign.get("beta110_accountability_effects", []), raw_campaign, errors)
	_validate_character_arcs(raw_campaign.get("beta110_character_arcs", {}), raw_campaign, errors)
	return {"ok": errors.is_empty(), "errors": errors.duplicate()}

static func _validate_character_arcs(raw_payload: Variant, campaign: Dictionary, errors: Array[String]) -> void:
	if not raw_payload is Dictionary:
		errors.append("character_arcs.payload")
		return
	var payload: Dictionary = raw_payload
	if int(payload.get("schema_version", 0)) != EXPECTED_SCHEMA_VERSION:
		errors.append("character_arcs.schema_version")
	if str(payload.get("campaign_id", "")) != EXPECTED_CAMPAIGN_ID:
		errors.append("character_arcs.campaign_id")
	var raw_ids: Variant = payload.get("core_character_ids", null)
	if not raw_ids is Array or (raw_ids as Array) != CHARACTER_FATE_IDS:
		errors.append("character_arcs.core_character_ids")
	var arcs: Variant = payload.get("arcs", null)
	if not arcs is Dictionary:
		errors.append("character_arcs.arcs")
		return
	var arc_map: Dictionary = arcs
	for character_id in CHARACTER_FATE_IDS:
		var rules: Variant = arc_map.get(character_id, null)
		if not rules is Array or (rules as Array).size() < 3:
			errors.append("character_arcs.%s.count" % character_id)
			continue
		var seen_ids: Dictionary = {}
		var baseline_count := 0
		for raw_rule in rules as Array:
			_validate_character_fate_rule(raw_rule, character_id, campaign, seen_ids, errors)
			if raw_rule is Dictionary and bool((raw_rule as Dictionary).get("is_baseline", false)):
				baseline_count += 1
		if baseline_count != 1:
			errors.append("character_arcs.%s.baseline" % character_id)
	for raw_id in arc_map.keys():
		if not CHARACTER_FATE_IDS.has(str(raw_id)):
			errors.append("character_arcs.unknown_character.%s" % str(raw_id))

static func _validate_character_fate_rule(raw_rule: Variant, character_id: String, campaign: Dictionary, seen_ids: Dictionary, errors: Array[String]) -> void:
	if not raw_rule is Dictionary:
		errors.append("character_arcs.%s.entry" % character_id)
		return
	var rule: Dictionary = raw_rule
	var arc_id := str(rule.get("arc_id", ""))
	if arc_id.is_empty() or seen_ids.has(arc_id):
		errors.append("character_arcs.%s.arc_id" % character_id)
	seen_ids[arc_id] = true
	if str(rule.get("character_id", "")) != character_id:
		errors.append("character_arcs.%s.character_id" % character_id)
	if not _is_integer_number(rule.get("priority", null)):
		errors.append("character_arcs.%s.priority" % character_id)
	for key in ["day_min", "day_max"]:
		if not _is_integer_number(rule.get(key, null)):
			errors.append("character_arcs.%s.%s" % [character_id, key])
	if int(rule.get("day_min", 0)) < 1 or int(rule.get("day_max", 0)) < int(rule.get("day_min", 0)) or int(rule.get("day_max", 0)) > 90:
		errors.append("character_arcs.%s.day_window" % character_id)
	for key in ["result_fate_status", "public_label", "primary_public_reason"]:
		if typeof(rule.get(key, null)) != TYPE_STRING or str(rule.get(key, "")).strip_edges().is_empty():
			errors.append("character_arcs.%s.%s" % [character_id, key])
	var category := str(rule.get("aftermath_category", ""))
	if not FATE_CATEGORIES.has(category):
		errors.append("character_arcs.%s.aftermath_category" % character_id)
	for predicate_key in ["all", "any", "none"]:
		var predicates: Variant = rule.get(predicate_key, null)
		if not predicates is Array:
			errors.append("character_arcs.%s.%s" % [character_id, predicate_key])
			continue
		for raw_predicate in predicates as Array:
			_validate_character_predicate(raw_predicate, character_id, campaign, errors)
	var reason_refs: Variant = rule.get("reason_refs", null)
	if not reason_refs is Array or (reason_refs as Array).is_empty():
		errors.append("character_arcs.%s.reason_refs" % character_id)
	else:
		for raw_reason in reason_refs as Array:
			if not raw_reason is Dictionary or not FATE_REASON_KINDS.has(str((raw_reason as Dictionary).get("kind", ""))) or not _known_fate_reference(campaign, str((raw_reason as Dictionary).get("kind", "")), str((raw_reason as Dictionary).get("id", ""))):
				errors.append("character_arcs.%s.reason_ref" % character_id)
	var identity := str(rule.get("result_fate_status", "")) + "|" + JSON.stringify(rule.get("all", [])) + "|" + JSON.stringify(rule.get("any", [])) + "|" + JSON.stringify(rule.get("none", []))
	if seen_ids.has("__branch__" + identity):
		errors.append("character_arcs.%s.title_only_branch" % character_id)
	seen_ids["__branch__" + identity] = true
	if character_id == "guo_ziyi" and _predicate_has_value(rule, "case", "beta108_case_military_grain_delay", "forced_removal"):
		errors.append("character_arcs.guo_ziyi.forced_removal_not_available")

static func _validate_character_predicate(raw_predicate: Variant, character_id: String, campaign: Dictionary, errors: Array[String]) -> void:
	if not raw_predicate is Dictionary:
		errors.append("character_arcs.%s.predicate" % character_id)
		return
	var predicate: Dictionary = raw_predicate
	var kind := str(predicate.get("kind", ""))
	if not FATE_PREDICATE_KINDS.has(kind):
		errors.append("character_arcs.%s.predicate_kind" % character_id)
		return
	match kind:
		"route":
			if not EXPECTED_ROUTE_IDS.has(str(predicate.get("route_id", ""))): errors.append("character_arcs.%s.route" % character_id)
		"case":
			if not EXPECTED_CASE_IDS.has(str(predicate.get("case_id", ""))) or not predicate.get("verdict_ids", []) is Array or (predicate.get("verdict_ids", []) as Array).is_empty(): errors.append("character_arcs.%s.case" % character_id)
			else:
				for verdict_id in predicate.get("verdict_ids", []):
					var case_record: Dictionary = campaign.get("beta108_case_content", {}).get(str(predicate.get("case_id", "")), {}) if campaign.get("beta108_case_content", {}) is Dictionary else {}
					var allowed: Array = case_record.get("available_verdicts", []) if case_record.get("available_verdicts", []) is Array else []
					if not allowed.has(str(verdict_id)): errors.append("character_arcs.%s.verdict" % character_id)
		"office":
			if not _known_fate_reference(campaign, "office", str(predicate.get("office_id", ""))) or not ["active", "removed"].has(str(predicate.get("status", ""))): errors.append("character_arcs.%s.office" % character_id)
		"debt":
			if not _known_fate_fact_reference(campaign, "debt", str(predicate.get("debt_id", ""))) or not ["open", "resolved"].has(str(predicate.get("status", ""))): errors.append("character_arcs.%s.debt" % character_id)
		"memory":
			if not _known_fate_fact_reference(campaign, "memory", str(predicate.get("memory_id", ""))) or str(predicate.get("status", "")) != "confirmed": errors.append("character_arcs.%s.memory" % character_id)
		"obligation":
			if not _known_fate_fact_reference(campaign, "obligation", str(predicate.get("target_id", ""))) or not ["fulfilled", "breached", "pending"].has(str(predicate.get("status", ""))): errors.append("character_arcs.%s.obligation" % character_id)
		"day":
			if not _is_integer_number(predicate.get("min", null)) and not _is_integer_number(predicate.get("max", null)): errors.append("character_arcs.%s.day" % character_id)

static func _known_fate_reference(campaign: Dictionary, kind: String, id: String) -> bool:
	if id.is_empty(): return false
	match kind:
		"route": return EXPECTED_ROUTE_IDS.has(id)
		"case": return EXPECTED_CASE_IDS.has(id)
		"office": return _known_office_ids(campaign).has(id)
		"review": return EXPECTED_REVIEW_IDS.has(id)
		"chronicle": return EXPECTED_ECHO_IDS.has(id) or id.begins_with("transaction|")
	return false

static func _known_fate_fact_reference(campaign: Dictionary, kind: String, id: String) -> bool:
	if id.is_empty():
		return false
	if kind == "obligation":
		var ledger: Variant = campaign.get("obligation_ledger", {})
		if ledger is Dictionary:
			for raw_template in (ledger as Dictionary).get("templates", []) if (ledger as Dictionary).get("templates", []) is Array else []:
				if raw_template is Dictionary and str((raw_template as Dictionary).get("template_id", "")) == id:
					return true
		return false
	if kind == "debt":
		for raw_echo in campaign.get("beta110_echoes", []) if campaign.get("beta110_echoes", []) is Array else []:
			if raw_echo is Dictionary:
				var effects: Variant = (raw_echo as Dictionary).get("effects", {})
				if effects is Dictionary:
					var debt: Variant = (effects as Dictionary).get("political_debt", {})
					if debt is Dictionary and str((debt as Dictionary).get("debt_id", "")) == id:
						return true
		return false
	if kind == "memory":
		for raw_echo in campaign.get("beta110_echoes", []) if campaign.get("beta110_echoes", []) is Array else []:
			if raw_echo is Dictionary:
				var effects: Variant = (raw_echo as Dictionary).get("effects", {})
				if effects is Dictionary:
					for raw_memory in (effects as Dictionary).get("memories", []) if (effects as Dictionary).get("memories", []) is Array else []:
						if raw_memory is Dictionary and str((raw_memory as Dictionary).get("memory_id", raw_memory.get("id", ""))) == id:
							return true
			# Accountability verdict memories are also authoritative state facts.
		for raw_case in campaign.get("beta110_accountability_effects", []) if campaign.get("beta110_accountability_effects", []) is Array else []:
			if raw_case is Dictionary:
				var verdict_effects: Variant = (raw_case as Dictionary).get("verdict_effects", {})
				if verdict_effects is Dictionary:
					for raw_effect in (verdict_effects as Dictionary).values():
						if raw_effect is Dictionary:
							for raw_memory in (raw_effect as Dictionary).get("memories", []) if (raw_effect as Dictionary).get("memories", []) is Array else []:
								if raw_memory is Dictionary and str((raw_memory as Dictionary).get("memory_id", raw_memory.get("id", ""))) == id:
									return true
		return false
	return false

static func _predicate_has_value(rule: Dictionary, kind: String, id: String, value: String) -> bool:
	for key in ["all", "any", "none"]:
		for raw_predicate in rule.get(key, []) if rule.get(key, []) is Array else []:
			if raw_predicate is Dictionary and str((raw_predicate as Dictionary).get("kind", "")) == kind and str((raw_predicate as Dictionary).get("case_id", "")) == id and (raw_predicate as Dictionary).get("verdict_ids", []).has(value):
				return true
	return false

static func _is_integer_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT or not is_finite(float(value)):
		return false
	return is_equal_approx(float(value), round(float(value)))

static func _validate_base_payload(raw_campaign: Dictionary, errors: Array[String]) -> void:
	var base_payload := raw_campaign.duplicate(true)
	base_payload["schema_version"] = 109
	base_payload["campaign_id"] = EXPECTED_BASE_CAMPAIGN_ID
	base_payload["phases"] = [
		{"id": "foundation", "start_day": 1, "end_day": 30},
		{"id": "accountability", "start_day": 31, "end_day": 60},
		{"id": "crisis_reorganization", "start_day": 61, "end_day": 90}
	]
	base_payload.erase("base_manifest")
	base_payload.erase("base_campaign_id")
	base_payload["core_character_ids"] = (raw_campaign.get("base_core_character_ids", raw_campaign.get("core_character_ids", [])) as Array).duplicate(true)
	base_payload.erase("base_content_files")
	base_payload["content_files"] = raw_campaign.get("base_content_files", {})
	for key in ["political_season", "governance_followups", "political_echoes", "political_season_review"]:
		var base_key: String = "base_" + key
		if raw_campaign.has(base_key): base_payload[key] = raw_campaign.get(base_key)
	var validation := Beta109ContentValidatorScript.validate(base_payload)
	if not bool(validation.get("ok", false)):
		for base_error in validation.get("errors", []): errors.append("base." + str(base_error))

static func _validate_content_files(raw_files: Variant, errors: Array[String]) -> void:
	if not raw_files is Dictionary:
		errors.append("content_files")
		return
	for key in ["political_season", "governance_followups", "political_echoes", "political_season_review", "accountability_effects"]:
		var reference: Variant = (raw_files as Dictionary).get(key, null)
		if not reference is String or str(reference).strip_edges().is_empty() or str(reference).contains("..") or str(reference).begins_with("/") or str(reference).contains(":") or not str(reference).to_lower().ends_with(".json"):
			errors.append("content_files.%s" % key)

static func _validate_phases(raw_phases: Variant, errors: Array[String]) -> void:
	if not raw_phases is Array or (raw_phases as Array).size() != EXPECTED_PHASES.size():
		errors.append("phases")
		return
	for index in range(EXPECTED_PHASES.size()):
		var phase: Variant = (raw_phases as Array)[index]
		var expected: Dictionary = EXPECTED_PHASES[index]
		if not phase is Dictionary or str((phase as Dictionary).get("id", "")) != str(expected.get("id", "")) or int((phase as Dictionary).get("start_day", 0)) != int(expected.get("start_day", 0)) or int((phase as Dictionary).get("end_day", 0)) != int(expected.get("end_day", 0)):
			errors.append("phases[%d]" % index)

static func _validate_nodes(raw_nodes: Variant, campaign: Dictionary, errors: Array[String]) -> void:
	if not raw_nodes is Array or (raw_nodes as Array).size() != EXPECTED_NODE_IDS.size():
		errors.append("nodes.count")
		return
	var seen: Dictionary = {}
	var known_cases := _known_case_ids(campaign)
	var known_nodes := _known_node_ids(campaign)
	for raw_node in raw_nodes:
		if not raw_node is Dictionary:
			errors.append("nodes.entry")
			continue
		var node: Dictionary = raw_node
		var node_id := str(node.get("node_id", ""))
		if not EXPECTED_NODE_IDS.has(node_id) or seen.has(node_id): errors.append("nodes.id.%s" % node_id)
		seen[node_id] = true
		if int(node.get("day", 0)) < 31 or int(node.get("day", 0)) > 90: errors.append("nodes.day.%s" % node_id)
		var case_id := str(node.get("case_id", ""))
		if not case_id.is_empty() and not known_cases.has(case_id): errors.append("nodes.case.%s" % node_id)
		var strategic_node_id := str(node.get("strategic_node_id", ""))
		if not strategic_node_id.is_empty() and not known_nodes.has(strategic_node_id): errors.append("nodes.strategic_node.%s" % node_id)
	_validate_exact_ids(seen, EXPECTED_NODE_IDS, "nodes.missing", errors)

static func _validate_routes(raw_routes: Variant, campaign: Dictionary, errors: Array[String]) -> void:
	if not raw_routes is Array or (raw_routes as Array).size() != EXPECTED_ROUTE_IDS.size():
		errors.append("routes.count")
		return
	var seen: Dictionary = {}
	var node_ids: Dictionary = {}
	for node_id in EXPECTED_NODE_IDS: node_ids[node_id] = true
	for raw_route in raw_routes:
		if not raw_route is Dictionary:
			errors.append("routes.entry")
			continue
		var route: Dictionary = raw_route
		var route_id := str(route.get("route_id", ""))
		if not EXPECTED_ROUTE_IDS.has(route_id) or seen.has(route_id): errors.append("routes.id.%s" % route_id)
		seen[route_id] = true
		var steps: Variant = route.get("steps", [])
		if not steps is Array or (steps as Array).size() < 3: errors.append("routes.steps.%s" % route_id)
		else:
			for raw_step in steps:
				if not raw_step is Dictionary or not node_ids.has(str((raw_step as Dictionary).get("node_id", ""))): errors.append("routes.step_node.%s" % route_id)
	_validate_exact_ids(seen, EXPECTED_ROUTE_IDS, "routes.missing", errors)

static func _validate_followups(raw_followups: Variant, campaign: Dictionary, errors: Array[String]) -> void:
	if not raw_followups is Array or (raw_followups as Array).size() != EXPECTED_FOLLOWUP_IDS.size():
		errors.append("followups.count")
		return
	var seen: Dictionary = {}
	var known_cases := _known_case_ids(campaign)
	var known_memorials := _known_base_memorial_ids(campaign)
	var governance: Dictionary = campaign.get("governance", {}) if campaign.get("governance", {}) is Dictionary else {}
	var topic_rules: Dictionary = governance.get("topic_rules", {}) if governance.get("topic_rules", {}) is Dictionary else {}
	var command_actions: Variant = governance.get("command_actions", [])
	var known_characters := _known_character_ids(campaign)
	var known_resources := _known_resource_ids(campaign)
	var known_offices := _known_office_ids(campaign)
	var execution_defaults: Dictionary = campaign.get("beta110_execution_defaults", {}) if campaign.get("beta110_execution_defaults", {}) is Dictionary else {}
	for raw_followup in raw_followups:
		if not raw_followup is Dictionary:
			errors.append("followups.entry")
			continue
		var followup: Dictionary = raw_followup
		var memorial_id := str(followup.get("memorial_id", ""))
		if not EXPECTED_FOLLOWUP_IDS.has(memorial_id) or seen.has(memorial_id): errors.append("followups.id.%s" % memorial_id)
		seen[memorial_id] = true
		if not known_memorials.has(str(followup.get("previous_memorial_id", ""))): errors.append("followups.predecessor.%s" % memorial_id)
		if not known_cases.has(str(followup.get("linked_case_id", ""))): errors.append("followups.case.%s" % memorial_id)
		var window: Variant = followup.get("activation_window", null)
		if not window is Dictionary or int((window as Dictionary).get("start_day", 0)) < 31 or int((window as Dictionary).get("end_day", 0)) > 90: errors.append("followups.window.%s" % memorial_id)
		if not followup.get("source_paths", []) is Array or (followup.get("source_paths", []) as Array).is_empty(): errors.append("followups.sources.%s" % memorial_id)
		if not followup.get("recommended_executor_ids", []) is Array or (followup.get("recommended_executor_ids", []) as Array).is_empty(): errors.append("followups.executors.%s" % memorial_id)
		if not followup.get("resource_keys", []) is Array or (followup.get("resource_keys", []) as Array).is_empty(): errors.append("followups.resources.%s" % memorial_id)
		for raw_executor_id in followup.get("recommended_executor_ids", []):
			if not known_characters.has(str(raw_executor_id)): errors.append("followups.executor_id.%s" % memorial_id)
		for raw_resource_key in followup.get("resource_keys", []):
			if not known_resources.has(str(raw_resource_key)): errors.append("followups.resource_id.%s" % memorial_id)
		var topic := str(followup.get("topic", "")).strip_edges()
		var rule: Dictionary = topic_rules.get(topic, {}) if topic_rules.get(topic, {}) is Dictionary else {}
		var action_id := str(rule.get("action_id", "")).strip_edges()
		var expected: Dictionary = EXPECTED_EXECUTION_DEFAULTS.get(topic, {}) if EXPECTED_EXECUTION_DEFAULTS.get(topic, {}) is Dictionary else {}
		var defaults: Dictionary = execution_defaults.get(topic, {}) if execution_defaults.get(topic, {}) is Dictionary else {}
		if expected.is_empty() or defaults != expected: errors.append("followups.execution_defaults.%s" % memorial_id)
		elif action_id != str(expected.get("action_id", "")) or rule.get("required_offices", []) != expected.get("required_offices", []) or str(rule.get("opening_question", "")) != str(expected.get("opening_question", "")) or followup.get("recommended_executor_ids", []) != expected.get("recommended_executor_ids", []) or followup.get("resource_keys", []) != expected.get("resource_keys", []) or rule.get("council_rules", null) != {} or rule.get("clauses", null) != []: errors.append("followups.execution_semantics.%s" % memorial_id)
		if rule.is_empty() or action_id.is_empty(): errors.append("followups.topic_rule.%s" % memorial_id)
		if not rule.get("required_offices", []) is Array or (rule.get("required_offices", []) as Array).is_empty(): errors.append("followups.required_offices.%s" % memorial_id)
		for raw_office_id in rule.get("required_offices", []):
			if not known_offices.has(str(raw_office_id)): errors.append("followups.office_id.%s" % memorial_id)
		if not _command_action_exists(command_actions, action_id): errors.append("followups.action.%s" % memorial_id)
		_validate_predicates(followup.get("predecessor_outcomes", []), VALID_OUTCOMES, "followups.outcomes.%s" % memorial_id, errors)
		_validate_predicates(followup.get("predecessor_conditions", []), VALID_CONDITIONS, "followups.conditions.%s" % memorial_id, errors)
	_validate_exact_ids(seen, EXPECTED_FOLLOWUP_IDS, "followups.missing", errors)
	_validate_followup_result_coverage(raw_followups, errors)

static func _command_action_exists(command_actions: Variant, action_id: String) -> bool:
	if action_id.is_empty():
		return false
	if command_actions is Array:
		return (command_actions as Array).has(action_id)
	if command_actions is Dictionary:
		return (command_actions as Dictionary).has(action_id)
	return false

static func _validate_echoes(raw_echoes: Variant, campaign: Dictionary, errors: Array[String]) -> void:
	if not raw_echoes is Array or (raw_echoes as Array).size() != EXPECTED_ECHO_IDS.size():
		errors.append("echoes.count")
		return
	var seen: Dictionary = {}
	var known_followups := {}
	for followup_id in EXPECTED_FOLLOWUP_IDS: known_followups[followup_id] = true
	var known_characters := _known_character_ids(campaign)
	var known_factions := _known_faction_ids(campaign)
	for raw_echo in raw_echoes:
		if not raw_echo is Dictionary:
			errors.append("echoes.entry")
			continue
		var echo: Dictionary = raw_echo
		var echo_id := str(echo.get("echo_id", ""))
		if not EXPECTED_ECHO_IDS.has(echo_id) or seen.has(echo_id): errors.append("echoes.id.%s" % echo_id)
		seen[echo_id] = true
		if not known_followups.has(str(echo.get("source_memorial_id", ""))): errors.append("echoes.source.%s" % echo_id)
		if not known_characters.has(str(echo.get("target_character_id", ""))): errors.append("echoes.character.%s" % echo_id)
		if not known_factions.has(str(echo.get("target_faction_id", ""))): errors.append("echoes.faction.%s" % echo_id)
		var public_sources: Variant = echo.get("public_sources", [])
		if not public_sources is Array or (public_sources as Array).is_empty(): errors.append("echoes.public_sources.%s" % echo_id)
		var effects: Variant = echo.get("effects", {})
		if not effects is Dictionary: errors.append("echoes.effects.%s" % echo_id)
		else: _validate_effect_keys(effects as Dictionary, "echoes.effects.%s" % echo_id, errors)
	_validate_exact_ids(seen, EXPECTED_ECHO_IDS, "echoes.missing", errors)

static func _validate_reviews(raw_reviews: Variant, campaign: Dictionary, errors: Array[String]) -> void:
	if not raw_reviews is Array or (raw_reviews as Array).size() != EXPECTED_REVIEW_IDS.size():
		errors.append("reviews.count")
		return
	var seen: Dictionary = {}
	for raw_review in raw_reviews:
		if not raw_review is Dictionary:
			errors.append("reviews.entry")
			continue
		var review: Dictionary = raw_review
		var review_id := str(review.get("review_id", ""))
		if not EXPECTED_REVIEW_IDS.has(review_id) or seen.has(review_id): errors.append("reviews.id.%s" % review_id)
		seen[review_id] = true
		var day := int(review.get("day", 0))
		if day not in [45, 65, 90]: errors.append("reviews.day.%s" % review_id)
		var sources: Variant = review.get("sources", [])
		if not sources is Array or (sources as Array).size() < 3: errors.append("reviews.sources.%s" % review_id)
		var requirements: Variant = review.get("source_requirements", [])
		if not requirements is Array or (requirements as Array).size() < 3: errors.append("reviews.requirements.%s" % review_id)
		if not review.get("state_paths", []) is Array or (review.get("state_paths", []) as Array).is_empty(): errors.append("reviews.state_paths.%s" % review_id)
	_validate_exact_ids(seen, EXPECTED_REVIEW_IDS, "reviews.missing", errors)

static func _validate_accountability_effects(raw_effects: Variant, campaign: Dictionary, errors: Array[String]) -> void:
	if not raw_effects is Array or (raw_effects as Array).size() != EXPECTED_CASE_IDS.size():
		errors.append("accountability_effects.count")
		return
	var seen: Dictionary = {}
	for raw_case in raw_effects:
		if not raw_case is Dictionary:
			errors.append("accountability_effects.entry")
			continue
		var effect_case: Dictionary = raw_case
		var case_id := str(effect_case.get("case_id", ""))
		if not EXPECTED_CASE_IDS.has(case_id) or seen.has(case_id): errors.append("accountability_effects.id.%s" % case_id)
		seen[case_id] = true
		var verdicts: Variant = effect_case.get("verdict_effects", null)
		if not verdicts is Dictionary:
			errors.append("accountability_effects.verdicts.%s" % case_id)
			continue
		for verdict_id in ["dismiss", "reform", "forced_removal"]:
			if not (verdicts as Dictionary).get(verdict_id, null) is Dictionary: errors.append("accountability_effects.%s.%s" % [case_id, verdict_id])
			else: _validate_effect_keys((verdicts as Dictionary)[verdict_id] as Dictionary, "accountability_effects.%s.%s" % [case_id, verdict_id], errors)
	_validate_exact_ids(seen, EXPECTED_CASE_IDS, "accountability_effects.missing", errors)

static func _validate_effect_keys(effects: Dictionary, path: String, errors: Array[String]) -> void:
	for key in effects.keys():
		if not EFFECT_KEYS.has(str(key)): errors.append(path + ".unknown_key." + str(key))

static func _validate_predicates(values: Variant, allowed: Array, path: String, errors: Array[String]) -> void:
	if not values is Array or (values as Array).is_empty():
		errors.append(path)
		return
	for value in values:
		if not allowed.has(str(value)): errors.append(path + "." + str(value))

static func _validate_followup_result_coverage(raw_followups: Variant, errors: Array[String]) -> void:
	if not raw_followups is Array:
		return
	var by_predecessor: Dictionary = {}
	for raw_followup in raw_followups as Array:
		if not raw_followup is Dictionary:
			continue
		var followup: Dictionary = raw_followup
		var predecessor_id := str(followup.get("previous_memorial_id", "")).strip_edges()
		if predecessor_id.is_empty():
			continue
		var group: Array = by_predecessor.get(predecessor_id, []) if by_predecessor.get(predecessor_id, []) is Array else []
		group.append(followup)
		by_predecessor[predecessor_id] = group
	for predecessor_id in by_predecessor.keys():
		var group: Array = by_predecessor[predecessor_id]
		var completed := false
		var partial := false
		var degraded := false
		var failure := false
		for followup in group:
			var predicate: Dictionary = followup.get("activation_predicate", {}) if followup.get("activation_predicate", {}) is Dictionary else {}
			var outcomes: Array = predicate.get("predecessor_outcomes", []) if predicate.get("predecessor_outcomes", []) is Array else []
			var conditions: Array = predicate.get("predecessor_conditions", []) if predicate.get("predecessor_conditions", []) is Array else []
			completed = completed or (outcomes.has("completed") and conditions.has("normal"))
			partial = partial or (outcomes.has("partial") and conditions.has("normal"))
			degraded = degraded or _contains_any(conditions, ["delayed", "blocked", "lost_contact"])
			failure = failure or outcomes.has("failed") or conditions.has("expired")
		for left_index in range(group.size()):
			for right_index in range(left_index + 1, group.size()):
				var left: Dictionary = group[left_index]
				var right: Dictionary = group[right_index]
				if _followup_predicates_overlap(left, right) and not left.has("activation_priority") and not right.has("activation_priority"):
					errors.append("followups.overlap.%s" % str(predecessor_id))
		if not completed: errors.append("followups.coverage.completed.%s" % str(predecessor_id))
		if not partial: errors.append("followups.coverage.partial.%s" % str(predecessor_id))
		if not degraded: errors.append("followups.coverage.degraded.%s" % str(predecessor_id))
		if not failure: errors.append("followups.coverage.failure.%s" % str(predecessor_id))

static func _followup_predicates_overlap(left: Dictionary, right: Dictionary) -> bool:
	var left_predicate: Dictionary = left.get("activation_predicate", {}) if left.get("activation_predicate", {}) is Dictionary else {}
	var right_predicate: Dictionary = right.get("activation_predicate", {}) if right.get("activation_predicate", {}) is Dictionary else {}
	var left_outcomes: Array = left_predicate.get("predecessor_outcomes", []) if left_predicate.get("predecessor_outcomes", []) is Array else []
	var right_outcomes: Array = right_predicate.get("predecessor_outcomes", []) if right_predicate.get("predecessor_outcomes", []) is Array else []
	var left_conditions: Array = left_predicate.get("predecessor_conditions", []) if left_predicate.get("predecessor_conditions", []) is Array else []
	var right_conditions: Array = right_predicate.get("predecessor_conditions", []) if right_predicate.get("predecessor_conditions", []) is Array else []
	var outcome_overlap := left_outcomes.is_empty() or right_outcomes.is_empty() or _contains_any(left_outcomes, right_outcomes)
	var condition_overlap := left_conditions.is_empty() or right_conditions.is_empty() or _contains_any(left_conditions, right_conditions)
	return outcome_overlap and condition_overlap

static func _contains_any(values: Array, candidates: Array) -> bool:
	for value in candidates:
		if values.has(value):
			return true
	return false

static func _validate_exact_ids(seen: Dictionary, expected: Array, path: String, errors: Array[String]) -> void:
	for expected_id in expected:
		if not seen.has(expected_id): errors.append(path + "." + str(expected_id))

static func _known_character_ids(campaign: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for character_id in campaign.get("core_character_ids", []): result[str(character_id)] = true
	for raw_character in campaign.get("characters", []):
		if raw_character is Dictionary: result[str((raw_character as Dictionary).get("id", ""))] = true
	return result

static func _known_faction_ids(campaign: Dictionary) -> Dictionary:
	var result: Dictionary = {"military_commanders": true, "merchant_refugees": true, "eunuch_network": true, "xuanzong_old_court": true, "suzong_court": true, "uighur_envoys": true}
	for raw_faction in campaign.get("factions", []):
		if raw_faction is Dictionary: result[str((raw_faction as Dictionary).get("id", (raw_faction as Dictionary).get("faction_id", "")))] = true
	return result

static func _known_resource_ids(campaign: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for resource_id in (campaign.get("resources", {}) as Dictionary).keys(): result[str(resource_id)] = true
	return result

static func _known_office_ids(campaign: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for raw_office in campaign.get("offices", []):
		if raw_office is Dictionary: result[str((raw_office as Dictionary).get("office_id", ""))] = true
	return result

static func _known_case_ids(campaign: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for case_id in EXPECTED_CASE_IDS: result[case_id] = true
	for case_id in campaign.get("core_case_ids", []): result[str(case_id)] = true
	return result

static func _known_base_memorial_ids(campaign: Dictionary) -> Dictionary:
	var result: Dictionary = {"memorial_shuofang_grain_001": true, "memorial_lingwu_ration_001": true, "memorial_gate_review_001": true}
	for raw_template in (campaign.get("governance", {}) as Dictionary).get("memorial_templates", []):
		if raw_template is Dictionary: result[str((raw_template as Dictionary).get("memorial_id", ""))] = true
	return result

static func _known_node_ids(campaign: Dictionary) -> Dictionary:
	var result: Dictionary = {"shuofang_front_node": true, "grain_road_node": true, "palace_inner_channel_node": true, "lingwu_court_node": true, "uighur_route_node": true, "guanzhong_approach_node": true}
	for raw_node in campaign.get("local_nodes", []):
		if raw_node is Dictionary: result[str((raw_node as Dictionary).get("node_id", (raw_node as Dictionary).get("id", "")))] = true
	return result
