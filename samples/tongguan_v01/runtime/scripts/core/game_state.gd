extends RefCounted

class_name GameState

const TimeControllerScript = preload("res://scripts/core/time_controller.gd")
const CharacterKnowledgeServiceScript = preload("res://scripts/core/character_knowledge_service.gd")
const CharacterStateServiceScript = preload("res://scripts/core/character_state_service.gd")
const CanonicalJSONScript = preload("res://scripts/core/canonical_json.gd")
const TangOfficeCatalogScript = preload("res://scripts/domain/tang_office_catalog.gd")
const SAVE_VERSION := 22
const DEFAULT_PLAYER_CHARACTER_ID := "li_heng"
const GOVERNANCE_ORDER_RESULTS := ["completed", "partial", "delayed", "blocked", "lost_contact", "failed"]
const TRANSIENT_WORKBENCH_KEYS := [
	"settings_open", "free_dialogue_open", "time_overlay_lock_order",
	"right_context_kind", "right_context_payload"
]
const TRANSIENT_WORKBENCH_DEFAULTS := {
	"settings_open": false,
	"free_dialogue_open": false,
	"time_overlay_lock_order": [],
	"right_context_kind": "court",
	"right_context_payload": {}
}
const TRANSIENT_OVERLAY_PAUSE_REASONS := [
	"settings", "character_overlay", "character_context_menu", "free_dialogue",
	"event_detail", "character_interaction", "political_confirmation", "office_appointment_confirmation",
	"governance_consultation_dialog", "accountability_consultation_dialog", "emperor_coping",
	"corridor_logistics", "battle_vignette"
]
const GOVERNANCE_RECORD_FIELDS := {
	"memorials": ["memorial_id", "sender_id", "topic", "location_id", "resource_keys", "deadline_days", "recommended_executor_ids", "visible_facts", "visible_resistance", "request_text", "filed_day", "status", "source_kind", "case_chain_id", "case_phase", "activated_day", "deadline_day", "consultation_ids", "active_council_id", "order_id", "closed_day", "outcome", "activation_variant", "followup_id", "previous_memorial_id", "linked_case_id", "node_id", "source_paths", "previous_order_id", "predecessor_result", "source_result_hash"],
	"consultations": ["consultation_id", "case_id", "memorial_id", "adviser_id", "day", "position", "recommended_action", "required_offices", "required_resources", "location_id", "deadline_day", "visible_risks", "known_basis", "status", "ability", "reason", "choice", "public_text", "tone", "wording_source", "conversation_phase", "turns", "selected_turn_ids", "draft_text", "draft_source", "draft_order_id"],
	"councils": ["council_id", "memorial_id", "topic", "seat_ids", "candidate_ids", "adviser_profiles", "status", "phase", "current_turn_index", "opening_question_default", "opening_question", "turns", "player_interventions", "clauses", "selected_clause_ids", "included_clause_ids", "nominated_drafter_id", "draft_order_id", "edict_text", "revision", "preview_token", "round", "round_one", "round_two", "summary", "concluded_after_round", "default_recipient_id", "default_action_id", "default_location_id", "default_resources", "default_authority_tags", "default_report_due_day", "drafted_by_office_id", "reviewed_by_office_id"],
	"orders": ["order_id", "council_id", "source_memorial_id", "parent_order_id", "correction_kind", "order_kind", "recipient_id", "assistant_ids", "action_id", "location_id", "resources", "authority_tags", "report_due_day", "required_office_id", "route_id", "drafted_by_office_id", "reviewed_by_office_id", "seal_status", "player_supplement", "edict_text", "edict_basis", "nominated_drafter_id", "revision", "preview_token", "stage", "status", "issued_day", "condition", "outcome", "correction_ids", "rule_seed", "forced_result"],
	"reports": ["report_id", "order_id", "case_chain_id", "status", "kind", "condition", "outcome", "day", "created_day", "arrival_day", "delivered_day", "title", "summary", "source_label", "confidence", "related_character_ids", "related_location_ids", "causes", "effects", "available_actions", "execution_details", "template_family", "template_id", "public_text", "wording_source", "source_kind", "review_id", "node_id", "source_ids"]
}
const LEGACY_GOVERNANCE_REPORT_FIELDS := ["source_memorial_id"]
const MEMORIAL_STATUSES := ["unread", "read", "consulting", "council", "decreed", "executing", "closed", "expired"]
const BETA110_CONTINUATION_ALLOWED_FIELDS := [
	"source_campaign_id",
	"source_save_version",
	"source_checkpoint_id",
	"source_fingerprint"
]
const BETA110_CONTINUATION_CHECKPOINT_ID := "beta109_phase_1_checkpoint"
const BETA110_REVIEW_IDS := [
	"beta110_supply_review",
	"beta110_authority_review",
	"beta110_final_assessment"
]

var current_time_minutes: int = 0
var current_day: int = 0
var player_character_id: String = DEFAULT_PLAYER_CHARACTER_ID
var current_viewer_id: String = ""
var current_date: Dictionary = {}
var time_speed: int = 1
var is_time_paused: bool = false
var pause_reason: String = ""
var auto_pause_preferences: Dictionary = {}
var phase: String = ""
var resources: Dictionary = {}
var flags: Dictionary = {}
var active_events: Array = []
var resolved_events: Array = []
var event_history: Array = []
var active_tasks: Array = []
var completed_tasks: Array = []
var inventory: Array = []
var resource_accounts: Dictionary = {}
var resource_reservations: Dictionary = {}
var resource_journal: Dictionary = {}
var economic_contracts: Dictionary = {}
var management_assets: Dictionary = {}
var player_assistant_assignment: Dictionary = {}
var assistant_advice_state: Dictionary = {}
var assistant_conversation_state: Dictionary = {}
var action_authorizations: Dictionary = {}
var action_receipts: Dictionary = {}
var npc_ai_runtime: Dictionary = preload("res://scripts/core/npc_ai_state_contract.gd").default_runtime()
var npc_decision_records: Dictionary = {}
var character_states: Dictionary = {}
var character_knowledge: Dictionary = {}
var observer_character_knowledge: Dictionary = {}
var character_political_states: Dictionary = {}
var character_state_history: Array = []
var faction_states: Dictionary = {}
var battlefront_states: Dictionary = {}
var battlefront_reports: Array = []
var battle_situation_state: Dictionary = {}
var active_npc_actions: Array = []
var npc_action_feed: Array = []
var npc_interaction_feed: Array = []
var pending_requests: Array = []
var resolved_requests: Array = []
var key_scene_consequences: Dictionary = {}
var strategic_routes: Dictionary = {}
var phase_ending: Dictionary = {}
var structured_memories: Array = []
var dialogue_history_summary: Array = []
var pending_dialogue_intent: Dictionary = {}
var pending_dialogue_response: Dictionary = {}
var active_conversation_target_id: String = ""
var dialogue_action_records: Array = []
var scene_stack: Array = []
var active_dialogue_sessions: Dictionary = {}
var dialogue_session_history: Array = []
var obligation_ledger: Array = []
var revealed_relationship_edges: Array = []
var court_workbench_state: Dictionary = {}
var office_state: Dictionary = {}
var office_history: Array = []
var faction_agenda_state: Dictionary = {}
var local_node_state: Dictionary = {}
var court_meeting_state: Dictionary = {}
var court_meeting_history: Array = []
var delayed_consequence_chains: Array = []
var chronicle_causal_references: Array = []
var route_network_state: Dictionary = {}
var active_intelligence_reports: Dictionary = {}
var intelligence_report_history: Array = []
var report_contradictions: Dictionary = {}
var active_regional_operations: Dictionary = {}
var regional_operation_history: Array = []
var beta_0_9_dialogue_state: Dictionary = {}
var information_truths: Dictionary = {}
var information_claims: Dictionary = {}
var information_transmissions: Array = []
var information_notifications: Array = []
var information_pending_transmissions: Array = []
var political_reactions: Array = []
var governance_state: Dictionary = {}
var office_terms: Dictionary = {}
var position_claims: Dictionary = {}
var control_relations: Dictionary = {}
var obedience_relations: Dictionary = {}
var depot_states: Dictionary = {}
var strategic_nodes: Dictionary = {}
var transit_corridors: Dictionary = {}
var military_forces: Dictionary = {}
var grain_transports: Array = []
var character_schemes: Dictionary = {}
var strategic_directives: Dictionary = {}
var macro_pacing_state: Dictionary = {}
var accountability_cases: Dictionary = {}
var political_debts: Dictionary = {}
var processed_transactions: Dictionary = {}
var clan_favor: Dictionary = {}
var clan_relations: Dictionary = {}
var minister_roster: Array = []
var state_revision: int = 0
# Runtime only: save reloads invalidate asynchronous callbacks; ordinary commits do not.
var runtime_load_epoch: int = 0

func get_clan_favor(clan_id: String) -> int:
	var val: int = 50
	if flags.has("clan_opinion_modifiers") and flags["clan_opinion_modifiers"] is Dictionary:
		val += int(flags["clan_opinion_modifiers"].get(clan_id, 0))
	if clan_favor.has(clan_id):
		val = int(clan_favor.get(clan_id, val))
	return val

func get_clan_relation(clan_id: String) -> int:
	return get_clan_favor(clan_id)

func _init() -> void:
	player_character_id = DEFAULT_PLAYER_CHARACTER_ID
	current_date = _default_current_date()
	auto_pause_preferences = _default_auto_pause_preferences()

func initialize_from_data(data: Dictionary) -> void:
	runtime_load_epoch += 1
	current_time_minutes = 0
	current_day = 0
	player_character_id = _normalize_player_character_id(data.get("player_character_id", DEFAULT_PLAYER_CHARACTER_ID))
	current_date = _default_current_date()
	time_speed = 1
	is_time_paused = false
	pause_reason = ""
	auto_pause_preferences = _default_auto_pause_preferences()
	phase = data.scenario.start_phase
	resources = data.resources.duplicate(true) if data.has("resources") and data.resources is Dictionary else {}
	# Personal funds require an explicit definition, never a copy of the treasury.
	if not resources.has("silver"):
		resources["silver"] = 0
	flags = {
		"lingwu_enthroned": true,
		"xuanzong_recognized_suzong": false,
		"adopted_strategies": [],
		"clan_opinions": {},
		"court_power_balance": {
			"clan_seats": 0,
			"scholar_seats": 0,
			"balance_status": "court_equilibrium"
		}
	}
	if data.get("regional_census") is Dictionary:
		flags["regional_census"] = data.regional_census.duplicate(true)
	if data.get("regional_economic_baselines") is Dictionary:
		flags["regional_economic_baselines"] = data.regional_economic_baselines.duplicate(true)
	if str(data.get("campaign_id", "")) == "anshi_beta_1_10" and data.get("core_character_ids", []) is Array:
		flags["beta110_core_character_ids"] = (data.get("core_character_ids", []) as Array).duplicate(true)
	active_events = []
	resolved_events = []
	event_history = []
	active_tasks = []
	completed_tasks = []
	inventory = []
	resource_accounts = {}
	resource_reservations = {}
	resource_journal = {}
	economic_contracts = {}
	management_assets = {}
	player_assistant_assignment = {}
	assistant_advice_state = {}
	assistant_conversation_state = {}
	action_authorizations = {}
	action_receipts = {}
	npc_ai_runtime = preload("res://scripts/core/npc_ai_state_contract.gd").default_runtime()
	npc_decision_records = {}
	character_knowledge = {}
	observer_character_knowledge = {}
	character_political_states = {}
	character_state_history = []
	battlefront_reports = []
	battle_situation_state = {}
	active_npc_actions = []
	npc_action_feed = []
	npc_interaction_feed = []
	pending_requests = []
	resolved_requests = []
	key_scene_consequences = {}
	structured_memories = []
	dialogue_history_summary = []
	pending_dialogue_intent = {}
	pending_dialogue_response = {}
	active_conversation_target_id = "guo_ziyi"
	dialogue_action_records = []
	scene_stack = []
	active_dialogue_sessions = {}
	dialogue_session_history = []
	obligation_ledger = []
	revealed_relationship_edges = []
	office_state = {}
	office_history = []
	var catalog_offices: Array = []
	var catalog_dict: Dictionary = data.get("offices_catalog", {}) if data.get("offices_catalog", {}) is Dictionary else {}
	if catalog_dict.has("offices") and catalog_dict.get("offices") is Array and not (catalog_dict.get("offices") as Array).is_empty():
		catalog_offices = catalog_dict.get("offices") as Array
	elif not TangOfficeCatalogScript.get_all_offices().is_empty():
		catalog_offices = TangOfficeCatalogScript.get_all_offices()

	if not catalog_offices.is_empty():
		for raw_off in catalog_offices:
			if not raw_off is Dictionary:
				continue
			var off: Dictionary = raw_off as Dictionary
			var off_id: String = str(off.get("id", ""))
			var is_core: bool = bool(off.get("is_core_cabinet", false))
			var runtime_record: Dictionary = {
				"office_id": off_id,
				"holder_id": "",
				"status": "vacant",
				"rank": str(off.get("rank", "从五品")),
				"branch": str(off.get("branch", "central_executive")),
				"name": str(off.get("name", off_id)),
				"runtime_kind": "core" if is_core else "supplemental",
				"vacancy_reason": "initial_overlay",
				"appointment": {"player_may_appoint_if_vacant": true},
				"required_stats": (off.get("required_stats", {}) as Dictionary).duplicate(true),
				"preferred_traits": (off.get("preferred_traits", []) as Array).duplicate(true),
				"output_multipliers": (off.get("output_multipliers", {}) as Dictionary).duplicate(true),
				"vacant_penalties": (off.get("vacant_penalties", {}) as Dictionary).duplicate(true),
				"authority_tags": (off.get("authority_tags", []) as Array).duplicate(true),
				"jurisdiction": (off.get("jurisdiction", []) as Array).duplicate(true),
				"aliases": (off.get("aliases", []) as Array).duplicate(true),
				"responsibility_text": str(off.get("responsibility_text", ""))
			}
			for field in ["authority_ref", "organization_id", "office_kind", "parent_office_id", "source_id", "hierarchy_source_id", "content_basis", "service_offers"]:
				if off.has(field): runtime_record[field] = off[field].duplicate(true) if off[field] is Dictionary or off[field] is Array else off[field]
			office_state[off_id] = runtime_record
	else:
		for office in data.get("offices", []):
			office_state[str(office.get("office_id", office.get("id", "")))] = office.duplicate(true)

	for default_overlay in TangOfficeCatalogScript.build_initial_24_overlay():
		var def_id: String = str(default_overlay.get("office_id", ""))
		var def_holder: String = str(default_overlay.get("holder_id", ""))
		if office_state.has(def_id) and not def_holder.is_empty():
			var rec: Dictionary = office_state[def_id] as Dictionary
			rec["holder_id"] = def_holder
			rec["status"] = "appointed"

	var overlays: Array = data.get("initial_office_overlay", []) as Array
	if overlays.is_empty() and data.get("beta108_appointments", {}) is Dictionary:
		overlays = (data.get("beta108_appointments", {}) as Dictionary).get("initial_office_overlay", []) as Array
	var explicitly_assigned_offices := {}
	for raw_overlay in overlays:
		if not raw_overlay is Dictionary:
			continue
		var overlay: Dictionary = raw_overlay as Dictionary
		var raw_id: String = str(overlay.get("office_id", ""))
		var canonical: String = TangOfficeCatalogScript.canonical_id(raw_id)
		explicitly_assigned_offices[canonical] = true
		var holder_id: String = str(overlay.get("holder_id", ""))
		if office_state.has(canonical):
			var rec: Dictionary = office_state[canonical] as Dictionary
			rec["holder_id"] = holder_id
			rec["status"] = "appointed" if not holder_id.is_empty() else "vacant"
			if overlay.has("vacancy_reason"):
				rec["vacancy_reason"] = str(overlay.get("vacancy_reason", ""))
		elif office_state.has(raw_id):
			var rec: Dictionary = office_state[raw_id] as Dictionary
			rec["holder_id"] = holder_id
			rec["status"] = "appointed" if not holder_id.is_empty() else "vacant"

	for raw_legacy in data.get("offices", []):
		if not raw_legacy is Dictionary:
			continue
		var legacy_dict: Dictionary = raw_legacy as Dictionary
		var leg_id: String = str(legacy_dict.get("office_id", legacy_dict.get("id", "")))
		var leg_holder: String = str(legacy_dict.get("holder_id", ""))
		var leg_canonical: String = TangOfficeCatalogScript.canonical_id(leg_id)
		if office_state.has(leg_canonical):
			var rec: Dictionary = office_state[leg_canonical] as Dictionary
			# Current scenario assignments, including explicit vacancies, outrank
			# old aliases. Otherwise the last legacy alias replaces the real holder.
			if not leg_holder.is_empty() and not (data.get("campaign_id") == "anshi_beta_1_14" and explicitly_assigned_offices.has(leg_canonical)):
				rec["holder_id"] = leg_holder
				rec["status"] = "appointed"
			if legacy_dict.has("authority_tags"):
				rec["authority_tags"] = (legacy_dict.get("authority_tags", []) as Array).duplicate(true)
			if legacy_dict.has("jurisdiction"):
				rec["jurisdiction"] = (legacy_dict.get("jurisdiction", []) as Array).duplicate(true)

	for legacy_id in TangOfficeCatalogScript.LEGACY_ALIASES.keys():
		var canonical_key: String = str(TangOfficeCatalogScript.LEGACY_ALIASES[legacy_id])
		if office_state.has(canonical_key):
			var mirror: Dictionary = (office_state[canonical_key] as Dictionary).duplicate(true)
			mirror["office_id"] = str(legacy_id)
			office_state[str(legacy_id)] = mirror

	for raw_legacy_office in data.get("offices", []):
		if raw_legacy_office is Dictionary:
			var legacy_dict: Dictionary = raw_legacy_office as Dictionary
			var legacy_id_str: String = str(legacy_dict.get("office_id", legacy_dict.get("id", "")))
			if not office_state.has(legacy_id_str):
				office_state[legacy_id_str] = legacy_dict.duplicate(true)
			elif legacy_dict.has("authority_tags"):
				var curr_rec: Dictionary = office_state[legacy_id_str]
				if (curr_rec.get("authority_tags", []) as Array).is_empty():
					curr_rec["authority_tags"] = (legacy_dict.get("authority_tags", []) as Array).duplicate(true)
	faction_agenda_state = {}
	for agenda in data.get("faction_agendas", []):
		faction_agenda_state[str(agenda.get("faction_id", ""))] = agenda.duplicate(true)
	local_node_state = {}
	for node in data.get("local_nodes", []):
		local_node_state[str(node.get("node_id", node.get("id", "")))] = node.duplicate(true)
	court_meeting_state = {}
	court_meeting_history = []
	delayed_consequence_chains = []
	chronicle_causal_references = []
	route_network_state = {"nodes": {}, "routes": {}}
	for node in data.get("route_network", {}).get("nodes", []):
		route_network_state.nodes[str(node.get("node_id", node.get("id", "")))] = node.duplicate(true)
	for route in data.get("route_network", {}).get("routes", []):
		route_network_state.routes[str(route.get("route_id", route.get("id", "")))] = route.duplicate(true)
	active_intelligence_reports = {}
	intelligence_report_history = []
	report_contradictions = {}
	for contradiction in data.get("intelligence_contradictions", []):
		report_contradictions[str(contradiction.get("contradiction_id", contradiction.get("id", "")))] = contradiction.duplicate(true)
	active_regional_operations = {}
	regional_operation_history = []
	beta_0_9_dialogue_state = _default_beta_0_9_dialogue_state()
	information_truths = {}
	information_claims = {}
	information_transmissions = []
	information_notifications = []
	information_pending_transmissions = []
	political_reactions = []
	governance_state = _default_governance_state()
	office_terms = {}
	position_claims = {}
	control_relations = {}
	obedience_relations = {}
	depot_states = {}
	strategic_nodes = {}
	transit_corridors = {}
	military_forces = {}
	grain_transports = []
	for raw_node in data.get("strategic_nodes", []):
		if raw_node is Dictionary:
			var n_id := str((raw_node as Dictionary).get("node_id", ""))
			if not n_id.is_empty():
				strategic_nodes[n_id] = (raw_node as Dictionary).duplicate(true)
	for raw_corr in data.get("transit_corridors", []):
		if raw_corr is Dictionary:
			var c_id := str((raw_corr as Dictionary).get("corridor_id", ""))
			if not c_id.is_empty():
				transit_corridors[c_id] = (raw_corr as Dictionary).duplicate(true)
	for raw_depot in data.get("depots", []):
		if raw_depot is Dictionary:
			var d_id := str((raw_depot as Dictionary).get("depot_id", ""))
			if not d_id.is_empty():
				depot_states[d_id] = (raw_depot as Dictionary).duplicate(true)
	for raw_force in data.get("military_forces", []):
		if raw_force is Dictionary:
			var f_id := str((raw_force as Dictionary).get("force_id", ""))
			if not f_id.is_empty():
				military_forces[f_id] = (raw_force as Dictionary).duplicate(true)
	character_schemes = {}
	strategic_directives = {}
	macro_pacing_state = {}
	accountability_cases = {}
	political_debts = {}
	processed_transactions = {}
	state_revision = 0
	if str(data.get("campaign_id", "")) == "anshi_beta_1_07":
		governance_state["tutorial"] = {"case_id": "grain_authority_origin", "step": "read_facts", "completed": false}
	var governance: Dictionary = data.get("governance", {})
	for raw_memorial in governance.get("memorial_templates", []):
		if not (raw_memorial is Dictionary):
			continue
		var memorial: Dictionary = (raw_memorial as Dictionary).duplicate(true)
		if memorial.has("previous_memorial_id") or memorial.has("activation_window"):
			continue
		var memorial_id := str(memorial.get("memorial_id", ""))
		if memorial_id.is_empty():
			continue
		memorial["filed_day"] = 0
		memorial["status"] = "unread"
		memorial["source_kind"] = "scenario"
		memorial["case_chain_id"] = str(memorial.get("case_chain_id", memorial_id))
		memorial["case_phase"] = str(memorial.get("case_phase", "origin"))
		memorial["activated_day"] = int(memorial.get("activated_day", 0))
		memorial["deadline_day"] = int(memorial.get("deadline_day", int(memorial.get("filed_day", 0)) + int(memorial.get("deadline_days", 0))))
		memorial["consultation_ids"] = []
		memorial["active_council_id"] = ""
		memorial["order_id"] = ""
		memorial["closed_day"] = -1
		memorial["outcome"] = ""
		memorial["activation_variant"] = "normal"
		governance_state["memorials"][memorial_id] = memorial
	court_workbench_state = {
		"mode": "Court",
		"settings_open": false,
		"free_dialogue_open": false,
		"time_overlay_lock_order": [],
		"selected_character_id": "guo_ziyi",
		"selected_office_id": "",
		"selected_faction_id": "",
		"selected_node_id": "",
		"selected_front_id": "",
		"selected_route_id": "",
		"selected_report_id": "",
		"selected_task_id": "",
		"selected_memorial_id": "",
		"selected_governance_council_id": "",
		"political_season_reviews_acknowledged": {},
		"right_context_kind": "court",
		"right_context_payload": {}
	}
	strategic_routes = {
		"defend_lingwu": 0,
		"support_shuofang": 0,
		"uighur_push": 0
	}
	phase_ending = {}
	character_states = {}
	for character in data.get("characters", []):
		if not character is Dictionary:
			continue
		var char_id := str(character.get("id", ""))
		if char_id.is_empty():
			continue
		var char_dict: Dictionary = (character as Dictionary).duplicate(true)
		char_dict["id"] = char_id
		char_dict["name"] = str(character.get("name", char_id))
		char_dict["status"] = str(character.get("status", "alive"))
		if not char_dict.has("relationships") or not (char_dict["relationships"] is Dictionary):
			char_dict["relationships"] = {}
		if not char_dict.has("memory_summary") or not (char_dict["memory_summary"] is Array):
			char_dict["memory_summary"] = []
		character_states[char_id] = char_dict
	faction_states = {}
	for raw_faction in data.get("factions", []):
		if raw_faction is Dictionary:
			var f_id: String = str((raw_faction as Dictionary).get("id", ""))
			if not f_id.is_empty():
				faction_states[f_id] = (raw_faction as Dictionary).duplicate(true)
	battlefront_states = {}
	for front in data.get("battlefronts", []):
		var front_state: Dictionary = front.duplicate(true)
		if not front_state.has("momentum"):
			front_state["momentum"] = "stable"
		if not front_state.has("last_change_reason"):
			front_state["last_change_reason"] = "战线初始态势。"
		battlefront_states[front.id] = front_state
	refresh_battle_situation_state()
	if player_character_id == DEFAULT_PLAYER_CHARACTER_ID:
		seed_starter_inventory_if_empty()

func get_relationship(character_id: String, target_id: String = "") -> int:
	if not character_states.has(character_id):
		return 0
	var relationships: Dictionary = character_states[character_id].get("relationships", {})
	var target := target_id if not target_id.is_empty() else player_character_id
	return int(relationships.get(target, relationships.get("li_heng", 0)))

func apply_resource_delta(resource_id: String, value: int, rule_ref: String = "", execution_id: String = "") -> Dictionary:
	return load("res://scripts/core/resource_rule_settlement.gd").apply(self, resource_id, value, rule_ref, execution_id)

func personal_cash_balance() -> int:
	var storage_adapter = preload("res://scripts/core/resource_storage_adapter.gd")
	var account_id: String = storage_adapter.personal_account(self, player_character_id)
	return storage_adapter.balance(self, resource_accounts[account_id].storage_ref) if not account_id.is_empty() else int(resources.get("silver", 0))

func apply_relationship_delta(character_id: String, value: int, target_id: String = "") -> void:
	if not character_states.has(character_id):
		return
	var relationships: Dictionary = character_states[character_id].get("relationships", {})
	var target := target_id if not target_id.is_empty() else player_character_id
	relationships[target] = int(relationships.get(target, relationships.get("li_heng", 0))) + value
	character_states[character_id]["relationships"] = relationships

func can_register_dynamic_character() -> bool:
	return character_states.size() < 256

func register_dynamic_character(char_record: Dictionary) -> Dictionary:
	if not char_record is Dictionary:
		return {"ok": false, "error": "invalid_character_record"}
	var char_id := str(char_record.get("id", "")).strip_edges()
	if char_id.is_empty():
		return {"ok": false, "error": "character_id_required"}
	if not can_register_dynamic_character():
		return {"ok": false, "error": "character_capacity_reached", "capacity": 256}
	if character_states.has(char_id):
		return {"ok": false, "error": "character_already_exists", "character_id": char_id}
	if char_record.has("appearance"):
		var appearance_validation: Dictionary = preload("res://scripts/core/character_appearance_contract.gd").validate_profile(char_record.appearance,char_id)
		if not appearance_validation.ok: return appearance_validation
	var next_states := character_states.duplicate(true)
	next_states[char_id] = char_record.duplicate(true)
	character_states = next_states
	return {"ok": true, "character_id": char_id}

func get_inventory() -> Array:
	if flags.get("managed_inventory_initialized", false):
		var result: Array = []
		var items = load("res://scripts/core/managed_item_service.gd")
		for ref in inventory:
			var item: Dictionary = items.project(self, str(ref.get("asset_ref", "")), player_character_id)
			if not item.is_empty(): result.append(item)
		return result
	return inventory.duplicate(true)

func add_inventory_item(item: Dictionary) -> Dictionary:
	if flags.get("managed_inventory_initialized", false):
		var id := str(item.get("id", ""))
		var known: Dictionary = load("res://scripts/core/managed_item_service.gd").project(self, id, player_character_id)
		if known.is_empty(): return {"ok": false, "error": "物品缺少已登记的真实来源或交割，不能凭回报文字创建"}
		if inventory.any(func(ref): return ref.get("id") == id): return {"ok": false, "error": "item_already_exists"}
		inventory.append({"id": id, "asset_ref": id})
		return {"ok": true, "id": id, "item": known}
	if item.is_empty():
		return {"ok": false, "error": "item_empty"}
	item = item.duplicate(true)
	var item_id := str(item.get("id", "")).strip_edges()
	if item_id.is_empty():
		var sequence := int(flags.get("next_inventory_sequence", 1))
		item_id = "item_%s_%d" % [player_character_id, sequence]
		while inventory.any(func(existing): return existing is Dictionary and existing.get("id") == item_id):
			sequence += 1
			item_id = "item_%s_%d" % [player_character_id, sequence]
		flags["next_inventory_sequence"] = sequence + 1
		item["id"] = item_id
	for existing in inventory:
		if existing is Dictionary and str(existing.get("id", "")) == item_id:
			return {"ok": false, "error": "item_already_exists", "id": item_id}
	inventory.append(item.duplicate(true))
	return {"ok": true, "id": item_id, "item": item}

func remove_inventory_item(item_id: String) -> Dictionary:
	if flags.get("managed_inventory_initialized", false): return {"ok": false, "error": "真实物品必须通过交割或消耗规则处理，不能直接删除所有权"}
	var idx := -1
	for i in range(inventory.size()):
		if inventory[i] is Dictionary and str(inventory[i].get("id", "")) == item_id:
			idx = i
			break
	if idx >= 0:
		var removed = inventory[idx]
		inventory.remove_at(idx)
		return {"ok": true, "removed": removed}
	return {"ok": false, "error": "item_not_found"}

func get_inventory_item(item_id: String) -> Dictionary:
	for it in get_inventory():
		if it is Dictionary and str(it.get("id", "")) == item_id:
			return (it as Dictionary).duplicate(true)
	return {}

func equip_inventory_item(item_id: String, equip: bool) -> Dictionary:
	if flags.get("managed_inventory_initialized", false): return load("res://scripts/core/managed_item_service.gd").equip_direct(self, item_id, equip)
	for i in range(inventory.size()):
		if inventory[i] is Dictionary and str(inventory[i].get("id", "")) == item_id:
			var item = (inventory[i] as Dictionary).duplicate(true)
			item["equipped"] = equip
			inventory[i] = item
			return {"ok": true, "item": item}
	return {"ok": false, "error": "item_not_found"}

func seed_starter_inventory_if_empty() -> void:
	if not inventory.is_empty() or flags.get("starter_inventory_granted", false) or player_character_id != DEFAULT_PLAYER_CHARACTER_ID:
		return
	flags["starter_inventory_granted"] = true
	flags["starter_inventory_source_id"] = "scenario:lingwu_imperial_regalia"
	var p_id := player_character_id if not player_character_id.is_empty() else "li_heng"
	var p_name := "天子李亨" if p_id == "li_heng" else "当前主公"

	inventory = [
		{
			"id": "item_tally_lingwu",
			"name": "朔方玄金虎符",
			"category": "TOKEN",
			"tier": 4,
			"tier_name": "绝品御用",
			"owner_id": p_id,
			"holder_name": p_name,
			"equipped": true,
			"lore": "天宝十四载安禄山反，肃宗受命即位于灵武，朔方军吏奉进玄金虎符。左半在朝，右半授大将，错金篆书'如朕亲临'，乃发兵征伐之首要凭信。",
			"effects_summary": "行营威慑+15，关中与河北调度响应提升，朔方部属忠诚不易动摇。",
			"effects": {"authority": 15, "military_readiness": 10},
			"actions": ["equip", "inspect"]
		},
		{
			"id": "item_sword_chengying",
			"name": "承影斩蛇御剑",
			"category": "EQUIPMENT",
			"tier": 3,
			"tier_name": "上品随身",
			"owner_id": p_id,
			"holder_name": p_name,
			"equipped": true,
			"lore": "灵武行在随身佩剑，剑身隐见松纹蟠龙，刃不卷芒。虽不如太阿巨阙之沉雄，然剑光澄澈，常佩于御座之侧以戒惰慢、威慑宵小。",
			"effects_summary": "随身武备防卫提升，禁卫宿卫警觉度+10。",
			"effects": {"prowess": 8, "security": 10},
			"actions": ["equip", "inspect", "bestow"]
		},
		{
			"id": "item_book_duzhi",
			"name": "天宝十四载度支要略",
			"category": "DOCUMENTS",
			"tier": 3,
			"tier_name": "上品秘籍",
			"owner_id": p_id,
			"holder_name": p_name,
			"equipped": false,
			"lore": "前任度支使与户部所留账卷残篇，详载天下两税、常平仓米斛、盐铁专卖与西北边防岁支之实数，非亲信枢要不可披阅。",
			"effects_summary": "明察政务钱粮底细，行在赋税与仓廪损耗识别更为精确。",
			"effects": {"governance": 6, "finance": 8},
			"actions": ["equip", "inspect"]
		},
		{
			"id": "item_curio_amber",
			"name": "西域沉香透雕如意",
			"category": "CURIOS",
			"tier": 2,
			"tier_name": "官造珍玩",
			"owner_id": p_id,
			"holder_name": p_name,
			"equipped": false,
			"lore": "安西四镇节度入贡之沉香珍玩，镂刻胡旋与宝相花纹，芳香郁烈经年不散。可随身把玩宁神，亦宜赏赐重臣安定人心。",
			"effects_summary": "可作厚赏之用；赏赐臣属或世家名士可大幅增进好感与亲睦。",
			"effects": {"diplomacy": 5, "opinion_gift": 25},
			"actions": ["inspect", "bestow"]
		},
		{
			"id": "item_scroll_secret_edict",
			"name": "灵武即位起居密录",
			"category": "DOCUMENTS",
			"tier": 4,
			"tier_name": "绝品重器",
			"owner_id": p_id,
			"holder_name": p_name,
			"equipped": false,
			"lore": "内侍省密录册页，记录马嵬坡分道之后，殿下北上灵武、诸将劝进受命之详实起居。字句严整，关涉太上皇与新君法统之枢轴。",
			"effects_summary": "法统正朔宣示；在朝堂合议或安抚蜀中旧臣时具备无可辩驳之政治分量。",
			"effects": {"legitimacy": 20, "stability": 10},
			"actions": ["inspect"]
		}
	]

func apply_faction_delta(faction_id: String, field: String, value: int) -> void:
	if not faction_states.has(faction_id):
		return
	var faction: Dictionary = faction_states[faction_id]
	faction[field] = int(faction.get(field, 0)) + value
	faction_states[faction_id] = faction

func apply_battlefront_delta(front_id: String, field: String, value: int) -> void:
	if not battlefront_states.has(front_id):
		return
	var front: Dictionary = battlefront_states[front_id]
	front[field] = clampi(int(front.get(field, 0)) + value, 0, 100)
	battlefront_states[front_id] = front
	refresh_battle_situation_state()

func set_battlefront_reason(front_id: String, reason: String) -> void:
	if not battlefront_states.has(front_id):
		return
	var front: Dictionary = battlefront_states[front_id]
	front["last_change_reason"] = reason
	battlefront_states[front_id] = front
	refresh_battle_situation_state()

func apply_strategy_route_delta(route_id: String, value: int) -> void:
	if route_id == "":
		return
	strategic_routes[route_id] = int(strategic_routes.get(route_id, 0)) + value
	flags["dominant_strategy_route"] = get_dominant_strategy_route()

func get_dominant_strategy_route() -> String:
	var best_route := ""
	var best_score := -999
	for route_id in strategic_routes.keys():
		var score := int(strategic_routes.get(route_id, 0))
		if score > best_score:
			best_route = str(route_id)
			best_score = score
	return best_route

func record_battlefront_report(report: Dictionary) -> void:
	battlefront_reports.append(report.duplicate(true))
	if battlefront_reports.size() > 12:
		battlefront_reports = battlefront_reports.slice(battlefront_reports.size() - 12, battlefront_reports.size())
	refresh_battle_situation_state()

func refresh_battle_situation_state() -> void:
	var fronts: Dictionary = {}
	for front_id in battlefront_states.keys():
		var front: Dictionary = battlefront_states[front_id]
		fronts[front_id] = {
			"name": str(front.get("name", front_id)),
			"control": int(front.get("control", 0)),
			"supply": int(front.get("supply", 0)),
			"threat": int(front.get("threat", 0)),
			"momentum": str(front.get("momentum", "stable")),
			"commander_id": str(front.get("commander_id", "")),
			"eta_risk": str(front.get("eta_risk", _infer_eta_risk(front))),
			"last_change_reason": str(front.get("last_change_reason", "")),
			"available_orders": front.get("available_orders", []).duplicate(true),
			"route_tag": str(front.get("route_tag", "neutral"))
		}
	battle_situation_state = {
		"nodes": ["lingwu", "shuofang", "hedong", "guanzhong", "changan_luoyang", "hebei", "uighur_direction"],
		"lines": [
			{"id": "supply_route", "from": "lingwu", "to": "shuofang", "kind": "supply"},
			{"id": "relay_route", "from": "lingwu", "to": "guanzhong", "kind": "relay"},
			{"id": "rebel_pressure_route", "from": "hebei", "to": "guanzhong", "kind": "pressure"},
			{"id": "external_aid_route", "from": "uighur_direction", "to": "hedong", "kind": "external_aid"}
		],
		"fronts": fronts,
		"last_updated_day": current_day
	}

func record_npc_active_action(action: Dictionary) -> void:
	active_npc_actions.append(action.duplicate(true))
	npc_action_feed.append(action.duplicate(true))
	if active_npc_actions.size() > 12:
		active_npc_actions = active_npc_actions.slice(active_npc_actions.size() - 12, active_npc_actions.size())
	if npc_action_feed.size() > 30:
		npc_action_feed = npc_action_feed.slice(npc_action_feed.size() - 30, npc_action_feed.size())

func record_npc_interaction(item: Dictionary) -> void:
	npc_interaction_feed.append(item.duplicate(true))
	if npc_interaction_feed.size() > 30:
		npc_interaction_feed = npc_interaction_feed.slice(npc_interaction_feed.size() - 30, npc_interaction_feed.size())

func record_pending_request(request: Dictionary) -> void:
	pending_requests.append(request.duplicate(true))
	if pending_requests.size() > 24:
		pending_requests = pending_requests.slice(pending_requests.size() - 24, pending_requests.size())

func record_resolved_request(request: Dictionary) -> void:
	resolved_requests.append(request.duplicate(true))
	if resolved_requests.size() > 48:
		resolved_requests = resolved_requests.slice(resolved_requests.size() - 48, resolved_requests.size())

func record_key_scene_consequence(scene_id: String, option_id: String, consequence: Dictionary) -> void:
	if scene_id == "":
		return
	var entry := consequence.duplicate(true)
	entry["scene_id"] = scene_id
	entry["option_id"] = option_id
	entry["day"] = current_day
	key_scene_consequences[scene_id] = entry

func record_dialogue_action(record: Dictionary) -> void:
	var entry := record.duplicate(true)
	if not entry.has("day"):
		entry["day"] = current_day
	dialogue_action_records.append(entry)
	if dialogue_action_records.size() > 40:
		dialogue_action_records = dialogue_action_records.slice(dialogue_action_records.size() - 40, dialogue_action_records.size())

func _infer_eta_risk(front: Dictionary) -> String:
	var supply := int(front.get("supply", 0))
	var threat := int(front.get("threat", 0))
	if supply < 30 or threat > 75:
		return "urgent"
	if supply < 45 or threat > 60:
		return "watch"
	return "steady"

func set_flag(flag_id: String, value: Variant) -> void:
	flags[flag_id] = value

func add_character_memory(character_id: String, memory_text: String) -> void:
	if not character_states.has(character_id):
		return
	var next_character_states := character_states.duplicate(true)
	var character: Dictionary = next_character_states[character_id].duplicate(true)
	var memories: Array = character.get("memory_summary", []).duplicate(true)
	memories.append(memory_text)
	character["memory_summary"] = memories
	next_character_states[character_id] = character
	character_states = next_character_states

func replace_structured_memory(index: int, memory: Dictionary) -> bool:
	if index < 0 or index >= structured_memories.size():
		return false
	var next_memories := structured_memories.duplicate(true)
	next_memories[index] = memory.duplicate(true)
	structured_memories = next_memories
	return true

func replace_obligation(index: int, obligation: Dictionary) -> bool:
	if index < 0 or index >= obligation_ledger.size():
		return false
	var next_ledger := obligation_ledger.duplicate(true)
	next_ledger[index] = obligation.duplicate(true)
	obligation_ledger = next_ledger
	return true

func record_event_history(event_id: String, status: String, details: Dictionary = {}) -> void:
	if event_id == "":
		return
	var entry := {
		"event_id": event_id,
		"status": status,
		"day": current_day,
		"details": details.duplicate(true)
	}
	event_history.append(entry)

func _initialize_beta108_state(data: Dictionary) -> void:
	var campaign_id := str(data.get("campaign_id", ""))
	if campaign_id not in ["anshi_beta_1_08", "anshi_beta_1_09", "anshi_beta_1_10"]:
		return
	var next_flags := flags.duplicate(true)
	next_flags["campaign_id"] = campaign_id
	next_flags["campaign_days"] = int(data.get("campaign_days", 90))
	next_flags.erase("beta108_initialized")
	next_flags.erase("beta109_initialized")
	next_flags.erase("beta110_initialized")
	var flag_prefix := "beta108" if campaign_id == "anshi_beta_1_08" else ("beta109" if campaign_id == "anshi_beta_1_09" else "beta110")
	next_flags["%s_initialized" % flag_prefix] = true
	if campaign_id == "anshi_beta_1_10" and data.get("core_character_ids", []) is Array:
		next_flags["beta110_core_character_ids"] = (data.get("core_character_ids", []) as Array).duplicate(true)
	flags = next_flags
	var next_terms: Dictionary = {}
	for raw_overlay in data.get("initial_office_overlay", []):
		if not raw_overlay is Dictionary or str((raw_overlay as Dictionary).get("status", "")) != "appointed":
			continue
		var overlay: Dictionary = raw_overlay
		var office_id := str(overlay.get("office_id", ""))
		var holder_id := str(overlay.get("holder_id", ""))
		if office_id.is_empty() or holder_id.is_empty():
			continue
		var term_id := "term|bootstrap|%s|%s" % [office_id, holder_id]
		next_terms[term_id] = {
			"term_id": term_id,
			"office_id": office_id,
			"holder_id": holder_id,
			"start_day": 1,
			"end_day": -1,
			"appointment_mode": "initial",
			"appointment_transaction_id": "bootstrap|%s" % campaign_id,
			"ended_by": "",
			"performance_refs": [],
			"settled_reward_keys": []
		}
	office_terms = next_terms
	var next_cases: Dictionary = {}
	for raw_case in data.get("accountability_case_templates", []):
		if raw_case is Dictionary and not str((raw_case as Dictionary).get("case_id", "")).is_empty():
			var case_record: Dictionary = (raw_case as Dictionary).duplicate(true)
			next_cases[str(case_record.get("case_id", ""))] = case_record
	accountability_cases = next_cases

func to_dict() -> Dictionary:
	return to_dictionary()

func to_dictionary() -> Dictionary:
	var serialized_campaign_id := str(flags.get("campaign_id", "anshi_beta_1_07"))
	var safe_character_states: Dictionary = _normalize_character_states(character_states, serialized_campaign_id)
	# Preserve the invalid payload so save/transaction validation can reject it;
	# silently truncating here would destroy creditor and assistant references.
	if character_states.size() > 256:
		safe_character_states = character_states.duplicate(true)
	var valid_character_ids: Array = safe_character_states.keys()
	var safe_character_knowledge: Dictionary = CharacterKnowledgeServiceScript.normalize_saved_knowledge(character_knowledge, valid_character_ids)
	var safe_character_political_states: Dictionary = CharacterStateServiceScript.normalize_saved_states(character_political_states, valid_character_ids)
	var safe_character_state_history: Array = CharacterStateServiceScript.normalize_saved_history(character_state_history, valid_character_ids)
	var safe_court_workbench_state := _sanitized_court_workbench_state()
	var safe_pause_reason := _sanitized_pause_reason()
	var safe_pending_dialogue_intent: Variant = _sanitize_dialogue_persistence(pending_dialogue_intent)
	var safe_pending_dialogue_response: Variant = _sanitize_dialogue_persistence(pending_dialogue_response)
	var safe_active_dialogue_sessions: Variant = _sanitize_dialogue_persistence(active_dialogue_sessions)
	var safe_dialogue_session_history: Variant = _sanitize_dialogue_persistence(dialogue_session_history)
	var serialized_campaign_days := int(flags.get("campaign_days", 90))
	var serialized := {
		"save_version": SAVE_VERSION,
		"campaign_id": serialized_campaign_id,
		"campaign_days": serialized_campaign_days,
		"current_time_minutes": current_time_minutes,
		"current_day": _normalize_current_day(current_day),
		"player_character_id": _normalize_player_character_id(player_character_id),
		"current_date": _normalize_current_date(current_date),
		"time_speed": _normalize_time_speed(time_speed),
		"is_time_paused": is_time_paused,
		"pause_reason": safe_pause_reason,
		"auto_pause_preferences": _normalize_auto_pause_preferences(auto_pause_preferences),
		"phase": phase,
		"resources": resources,
		"flags": flags,
		"active_events": active_events,
		"resolved_events": resolved_events,
		"event_history": event_history,
		"active_tasks": active_tasks,
		"completed_tasks": completed_tasks,
		"inventory": inventory,
		"resource_accounts": resource_accounts,
		"resource_reservations": resource_reservations,
		"resource_journal": resource_journal,
		"economic_contracts": economic_contracts,
		"management_assets": management_assets,
		"player_assistant_assignment": player_assistant_assignment,
		"assistant_advice_state": assistant_advice_state,
		"assistant_conversation_state": assistant_conversation_state,
		"action_authorizations": action_authorizations,
		"action_receipts": action_receipts,
		"npc_ai_runtime": npc_ai_runtime,
		"npc_decision_records": npc_decision_records,
		"observer_character_knowledge": observer_character_knowledge,
		"battlefront_reports": battlefront_reports,
		"battle_situation_state": battle_situation_state,
		"active_npc_actions": active_npc_actions,
		"npc_action_feed": npc_action_feed,
		"npc_interaction_feed": npc_interaction_feed,
		"pending_requests": pending_requests,
		"resolved_requests": resolved_requests,
		"key_scene_consequences": key_scene_consequences,
		"strategic_routes": strategic_routes,
		"phase_ending": phase_ending,
		"structured_memories": structured_memories,
		"dialogue_history_summary": _sanitize_dialogue_persistence(dialogue_history_summary),
		"pending_dialogue_intent": safe_pending_dialogue_intent,
		"pending_dialogue_response": safe_pending_dialogue_response,
		"active_conversation_target_id": active_conversation_target_id,
		"dialogue_action_records": dialogue_action_records,
		"scene_stack": scene_stack,
		"active_dialogue_sessions": safe_active_dialogue_sessions,
		"dialogue_session_history": safe_dialogue_session_history,
		"obligation_ledger": obligation_ledger,
		"revealed_relationship_edges": revealed_relationship_edges,
		"office_state": office_state,
		"office_history": office_history,
		"faction_agenda_state": faction_agenda_state,
		"local_node_state": local_node_state,
		"court_meeting_state": court_meeting_state,
		"court_meeting_history": court_meeting_history,
		"delayed_consequence_chains": delayed_consequence_chains,
		"chronicle_causal_references": chronicle_causal_references,
		"route_network_state": route_network_state,
		"active_intelligence_reports": active_intelligence_reports,
		"intelligence_report_history": intelligence_report_history,
		"report_contradictions": report_contradictions,
		"active_regional_operations": active_regional_operations,
		"regional_operation_history": regional_operation_history,
		"beta_0_9_dialogue_state": beta_0_9_dialogue_state,
		"information_truths": information_truths,
		"information_claims": information_claims,
		"information_transmissions": information_transmissions,
		"information_notifications": information_notifications,
		"information_pending_transmissions": information_pending_transmissions,
		"political_reactions": political_reactions,
		"governance_state": _governance_state_for_serialization(),
		"office_terms": office_terms,
		"position_claims": position_claims,
		"control_relations": control_relations,
		"obedience_relations": obedience_relations,
		"depot_states": depot_states,
		"strategic_nodes": strategic_nodes,
		"transit_corridors": transit_corridors,
		"military_forces": military_forces,
		"grain_transports": grain_transports,
		"character_schemes": character_schemes,
		"strategic_directives": strategic_directives,
		"macro_pacing_state": macro_pacing_state,
		"accountability_cases": accountability_cases,
		"political_debts": political_debts,
		"processed_transactions": processed_transactions,
		"state_revision": state_revision,
		"court_workbench_state": safe_court_workbench_state,
		"character_states": safe_character_states,
		"character_knowledge": safe_character_knowledge,
		"character_political_states": safe_character_political_states,
		"character_state_history": safe_character_state_history,
		"faction_states": faction_states,
		"battlefront_states": battlefront_states
	}
	# Sanitation owns one deep copy of the complete snapshot. Intermediate
	# containers above are read-only until that independent copy exists.
	return _sanitize_long_term_state(serialized)

func load_dictionary(data: Dictionary) -> void:
	# Opening census/basis records are immutable estimates, separate from the
	# current population and local-node state. Preserve an already frozen
	# record only when the incoming exact bytes prove it is unchanged.
	var frozen_baselines := preload("res://scripts/core/native_state_snapshot.gd").frozen_baselines(self)
	runtime_load_epoch += 1
	current_time_minutes = int(data.get("current_time_minutes", 0))
	var has_current_day := data.has("current_day")
	var should_migrate_legacy_minutes := _should_migrate_legacy_minutes(data)
	current_day = _normalize_current_day(data.get("current_day", 0)) if has_current_day else (_legacy_minutes_to_day(current_time_minutes) if should_migrate_legacy_minutes else 0)
	player_character_id = _normalize_player_character_id(data.get("player_character_id", DEFAULT_PLAYER_CHARACTER_ID))
	current_date = _normalize_current_date(data.get("current_date", _default_current_date()))
	time_speed = _normalize_time_speed(data.get("time_speed", 1))
	is_time_paused = bool(data.get("is_time_paused", false))
	pause_reason = str(data.get("pause_reason", ""))
	pause_reason = _sanitized_pause_reason()
	auto_pause_preferences = _normalize_auto_pause_preferences(data.get("auto_pause_preferences", _default_auto_pause_preferences()))
	phase = str(data.get("phase", ""))
	var raw_flags: Variant = data.get("flags", {})
	var loaded_campaign_id := str(data.get("campaign_id", raw_flags.get("campaign_id", "") if raw_flags is Dictionary else ""))
	character_states = _normalize_character_states(data.get("character_states", {}), loaded_campaign_id)
	resources = data.get("resources", {}).duplicate(true)
	flags = data.get("flags", {}).duplicate(true)
	for key in frozen_baselines:
		if flags.has(key) and var_to_bytes(flags[key]) == var_to_bytes(frozen_baselines[key]): flags[key] = frozen_baselines[key]
	if not flags.has("adopted_strategies"):
		flags["adopted_strategies"] = []
	if not flags.has("clan_opinions"):
		flags["clan_opinions"] = {}
	if not flags.has("court_power_balance"):
		flags["court_power_balance"] = {
			"clan_seats": 0,
			"scholar_seats": 0,
			"balance_status": "court_equilibrium"
		}
	if should_migrate_legacy_minutes:
		flags["legacy_minute_save_migrated"] = true
	active_events = data.get("active_events", []).duplicate(true)
	resolved_events = data.get("resolved_events", []).duplicate(true)
	event_history = data.get("event_history", []).duplicate(true)
	active_tasks = data.get("active_tasks", []).duplicate(true)
	completed_tasks = data.get("completed_tasks", []).duplicate(true)
	inventory = data.get("inventory", []).duplicate(true)
	resource_accounts = data.get("resource_accounts", {}).duplicate(true)
	resource_reservations = data.get("resource_reservations", {}).duplicate(true)
	resource_journal = data.get("resource_journal", {}).duplicate(true)
	economic_contracts = data.get("economic_contracts", {}).duplicate(true)
	management_assets = data.get("management_assets", {}).duplicate(true)
	player_assistant_assignment = data.get("player_assistant_assignment", {}).duplicate(true)
	assistant_advice_state = data.get("assistant_advice_state", {}).duplicate(true)
	assistant_conversation_state = data.get("assistant_conversation_state", {}).duplicate(true)
	action_authorizations = data.get("action_authorizations", {}).duplicate(true)
	action_receipts = data.get("action_receipts", {}).duplicate(true)
	npc_ai_runtime = data.get("npc_ai_runtime", preload("res://scripts/core/npc_ai_state_contract.gd").default_runtime()).duplicate(true)
	npc_decision_records = data.get("npc_decision_records", {}).duplicate(true)
	observer_character_knowledge = data.get("observer_character_knowledge", {}).duplicate(true)
	battlefront_reports = data.get("battlefront_reports", []).duplicate(true)
	battle_situation_state = data.get("battle_situation_state", {}).duplicate(true)
	active_npc_actions = data.get("active_npc_actions", []).duplicate(true)
	npc_action_feed = data.get("npc_action_feed", []).duplicate(true)
	npc_interaction_feed = data.get("npc_interaction_feed", []).duplicate(true)
	pending_requests = _normalize_pending_requests(data.get("pending_requests", []), loaded_campaign_id)
	resolved_requests = data.get("resolved_requests", []).duplicate(true)
	key_scene_consequences = data.get("key_scene_consequences", {}).duplicate(true)
	structured_memories = data.get("structured_memories", []).duplicate(true)
	dialogue_history_summary = data.get("dialogue_history_summary", []).duplicate(true)
	pending_dialogue_intent = data.get("pending_dialogue_intent", {}).duplicate(true)
	pending_dialogue_response = data.get("pending_dialogue_response", {}).duplicate(true)
	active_conversation_target_id = str(data.get("active_conversation_target_id", "guo_ziyi"))
	dialogue_action_records = data.get("dialogue_action_records", []).duplicate(true)
	scene_stack = data.get("scene_stack", []).duplicate(true)
	active_dialogue_sessions = data.get("active_dialogue_sessions", {}).duplicate(true)
	dialogue_session_history = data.get("dialogue_session_history", []).duplicate(true)
	obligation_ledger = data.get("obligation_ledger", []).duplicate(true)
	revealed_relationship_edges = data.get("revealed_relationship_edges", []).duplicate(true)
	office_state = data.get("office_state", {}).duplicate(true)
	office_history = data.get("office_history", []).duplicate(true)
	faction_agenda_state = data.get("faction_agenda_state", {}).duplicate(true)
	local_node_state = data.get("local_node_state", {}).duplicate(true)
	court_meeting_state = data.get("court_meeting_state", {}).duplicate(true)
	court_meeting_history = data.get("court_meeting_history", []).duplicate(true)
	delayed_consequence_chains = data.get("delayed_consequence_chains", []).duplicate(true)
	chronicle_causal_references = data.get("chronicle_causal_references", []).duplicate(true)
	route_network_state = data.get("route_network_state", {"nodes": {}, "routes": {}}).duplicate(true)
	if not route_network_state.has("nodes"):
		route_network_state["nodes"] = {}
	if not route_network_state.has("routes"):
		route_network_state["routes"] = {}
	active_intelligence_reports = data.get("active_intelligence_reports", {}).duplicate(true)
	intelligence_report_history = data.get("intelligence_report_history", []).duplicate(true)
	report_contradictions = data.get("report_contradictions", {}).duplicate(true)
	active_regional_operations = data.get("active_regional_operations", {}).duplicate(true)
	regional_operation_history = data.get("regional_operation_history", []).duplicate(true)
	beta_0_9_dialogue_state = data.get("beta_0_9_dialogue_state", _default_beta_0_9_dialogue_state()).duplicate(true)
	information_truths = data.get("information_truths", {}).duplicate(true)
	information_claims = data.get("information_claims", {}).duplicate(true)
	information_transmissions = data.get("information_transmissions", []).duplicate(true)
	information_notifications = data.get("information_notifications", []).duplicate(true)
	information_pending_transmissions = data.get("information_pending_transmissions", []).duplicate(true)
	political_reactions = data.get("political_reactions", []).duplicate(true)
	governance_state = _normalize_governance_state(data.get("governance_state", {}))
	office_terms = _normalize_record_map(data.get("office_terms", {}))
	position_claims = _normalize_record_map(data.get("position_claims", {}))
	control_relations = _normalize_record_map(data.get("control_relations", {}))
	obedience_relations = _normalize_record_map(data.get("obedience_relations", {}))
	depot_states = _normalize_record_map(data.get("depot_states", {}))
	strategic_nodes = _normalize_record_map(data.get("strategic_nodes", {}))
	transit_corridors = _normalize_record_map(data.get("transit_corridors", {}))
	military_forces = _normalize_record_map(data.get("military_forces", {}))
	grain_transports = data.get("grain_transports", []).duplicate(true)
	character_schemes = _normalize_record_map(data.get("character_schemes", {}))
	strategic_directives = _normalize_record_map(data.get("strategic_directives", {}))
	macro_pacing_state = data.get("macro_pacing_state", {}).duplicate(true)
	accountability_cases = _normalize_record_map(data.get("accountability_cases", {}))
	political_debts = _normalize_record_map(data.get("political_debts", {}))
	processed_transactions = _normalize_record_map(data.get("processed_transactions", {}))
	state_revision = int(data.get("state_revision", 0))
	for key in _default_beta_0_9_dialogue_state().keys():
		if not beta_0_9_dialogue_state.has(key):
			beta_0_9_dialogue_state[key] = {}
	var default_workbench_state := {
		"mode": "Court",
		"settings_open": false,
		"free_dialogue_open": false,
		"time_overlay_lock_order": [],
		"selected_character_id": active_conversation_target_id,
		"selected_office_id": "",
		"selected_faction_id": "",
		"selected_node_id": "",
		"selected_front_id": "",
		"selected_route_id": "",
		"selected_report_id": "",
		"selected_task_id": "",
		"selected_memorial_id": "",
		"selected_governance_council_id": "",
		"political_season_reviews_acknowledged": {},
		"right_context_kind": "court",
		"right_context_payload": {}
	}
	court_workbench_state = _copied_dictionary_or_default(data.get("court_workbench_state", default_workbench_state), default_workbench_state)
	if not court_workbench_state.has("political_season_reviews_acknowledged"):
		court_workbench_state["political_season_reviews_acknowledged"] = {}
	if not court_workbench_state.has("mode"):
		court_workbench_state["mode"] = "Court"
	if not court_workbench_state.has("settings_open"):
		court_workbench_state["settings_open"] = false
	if not court_workbench_state.has("free_dialogue_open") or typeof(court_workbench_state.get("free_dialogue_open")) != TYPE_BOOL:
		court_workbench_state["free_dialogue_open"] = false
	court_workbench_state["time_overlay_lock_order"] = TimeControllerScript.normalize_overlay_lock_order(
		court_workbench_state.get("time_overlay_lock_order", [])
	)
	if not court_workbench_state.has("right_context_kind"):
		court_workbench_state["right_context_kind"] = "court"
	if not court_workbench_state.has("right_context_payload"):
		court_workbench_state["right_context_payload"] = {}
	for key in ["selected_character_id", "selected_office_id", "selected_faction_id", "selected_node_id", "selected_front_id", "selected_route_id", "selected_report_id", "selected_task_id", "selected_memorial_id", "selected_governance_council_id"]:
		if not court_workbench_state.has(key):
			court_workbench_state[key] = active_conversation_target_id if key == "selected_character_id" else ""
	court_workbench_state = _sanitized_court_workbench_state()
	strategic_routes = data.get("strategic_routes", {
		"defend_lingwu": 0,
		"support_shuofang": 0,
		"uighur_push": 0
	}).duplicate(true)
	phase_ending = data.get("phase_ending", {}).duplicate(true)
	var valid_character_ids: Array = character_states.keys()
	character_knowledge = CharacterKnowledgeServiceScript.normalize_saved_knowledge(data.get("character_knowledge", {}), valid_character_ids)
	character_political_states = CharacterStateServiceScript.normalize_saved_states(data.get("character_political_states", {}), valid_character_ids)
	character_state_history = CharacterStateServiceScript.normalize_saved_history(data.get("character_state_history", []), valid_character_ids)
	faction_states = data.get("faction_states", {}).duplicate(true)
	battlefront_states = data.get("battlefront_states", {}).duplicate(true)
	if battle_situation_state.is_empty():
		refresh_battle_situation_state()

func try_load_dictionary(raw: Dictionary) -> Dictionary:
	if not (raw is Dictionary):
		return {"ok": false, "error": "save payload must be a dictionary"}
	var appearance_validation: Dictionary = preload("res://scripts/core/character_appearance_contract.gd").validate_snapshot(raw)
	if not appearance_validation.ok: return appearance_validation
	var control_report_validation: Dictionary = preload("res://scripts/core/node_control_observation.gd").validate_snapshot(raw)
	if not control_report_validation.ok: return control_report_validation
	var dispatch_validation: Dictionary = preload("res://scripts/core/dispatch_transport.gd").validate_pending(raw)
	if not dispatch_validation.ok: return dispatch_validation
	var office_knowledge_validation: Dictionary = preload("res://scripts/core/regional_office_knowledge.gd").validate(raw)
	if not office_knowledge_validation.ok: return office_knowledge_validation
	var population_validation: Dictionary = preload("res://scripts/core/regional_population_service.gd").validate(raw)
	if not population_validation.ok: return population_validation
	var visit_validation: Dictionary = preload("res://scripts/core/regional_visit_service.gd").validate(raw)
	if not visit_validation.ok: return visit_validation
	var management_validation: Dictionary = preload("res://scripts/core/management_state_contract.gd").validate(raw)
	if not management_validation.get("ok", false):
		return management_validation
	var npc_validation: Dictionary = preload("res://scripts/core/npc_ai_state_contract.gd").validate(raw)
	if not npc_validation.ok: return npc_validation
	var observer_validation: Dictionary = CharacterKnowledgeServiceScript.validate_observers(raw)
	if not observer_validation.ok: return observer_validation
	# The normalizer owns a deep copy; loader inputs remain untouched.
	var normalized_raw := _normalize_pre_repair_v19(raw)
	var supplied_save_version := int(normalized_raw.get("save_version", SAVE_VERSION))
	var raw_campaign_id := str(normalized_raw.get("campaign_id", normalized_raw.get("flags", {}).get("campaign_id", "") if normalized_raw.get("flags", {}) is Dictionary else ""))
	var is_historical_beta107_snapshot := supplied_save_version == 16 and raw_campaign_id == "anshi_beta_1_07"
	if raw.has("save_version") and supplied_save_version != SAVE_VERSION and not is_historical_beta107_snapshot:
		return {"ok": false, "code": "incompatible_save", "error": "save version is incompatible with the current campaign"}
	var authoritative_validation := _validate_beta108_authoritative_fields(normalized_raw)
	if not bool(authoritative_validation.get("ok", false)):
		return authoritative_validation
	var governance_validation := _validate_governance_snapshot(normalized_raw.get("governance_state", {}), normalized_raw.has("governance_state"))
	if not bool(governance_validation.get("ok", false)):
		return governance_validation
	var candidate = GameState.new()
	candidate.load_dictionary(normalized_raw)
	load_dictionary(candidate.to_dictionary())
	return {"ok": true}

func _validate_beta108_authoritative_fields(raw: Dictionary) -> Dictionary:
	for key in ["office_terms", "accountability_cases", "political_debts", "processed_transactions"]:
		if raw.has(key) and not (raw.get(key) is Dictionary):
			return {"ok": false, "error": "invalid %s" % key}
	if raw.has("state_revision") and typeof(raw.get("state_revision")) not in [TYPE_INT, TYPE_FLOAT]:
		return {"ok": false, "error": "invalid state_revision"}
	if raw.has("state_revision") and int(raw.get("state_revision", 0)) < 0:
		return {"ok": false, "error": "invalid state_revision"}
	var flags_value: Variant = raw.get("flags", {})
	var campaign_id := str(raw.get("campaign_id", flags_value.get("campaign_id", "")) if flags_value is Dictionary else raw.get("campaign_id", ""))
	var continuation_validation := _validate_beta110_continuation(flags_value.get("beta110_continuation", null), campaign_id, (flags_value as Dictionary).has("beta110_continuation")) if flags_value is Dictionary else {"ok": true, "data": {}}
	if not bool(continuation_validation.get("ok", false)):
		return continuation_validation
	var continuation_provenance: Dictionary = continuation_validation.get("data", {}) if continuation_validation.get("data", {}) is Dictionary else {}
	if not raw.get("office_state", {}) is Dictionary: return {"ok": false, "error": "invalid office_state"}
	var office_validation := _validate_office_terms(raw.get("office_terms", {}), campaign_id, continuation_provenance, raw.get("office_state", {}))
	if not bool(office_validation.get("ok", false)):
		return office_validation
	var case_validation := _validate_accountability_cases(raw.get("accountability_cases", {}))
	if not bool(case_validation.get("ok", false)):
		return case_validation
	var criminal_validation: Dictionary = load("res://scripts/core/criminal_case_service.gd").validate(raw)
	if not criminal_validation.ok: return criminal_validation
	var reactions_validation: Dictionary = load("res://scripts/core/npc_social_reaction_service.gd").validate(raw)
	if not reactions_validation.ok: return reactions_validation
	var debt_validation := _validate_political_debts(raw.get("political_debts", {}))
	if not bool(debt_validation.get("ok", false)):
		return debt_validation
	var receipt_validation := _validate_transaction_receipts(raw.get("processed_transactions", {}))
	if not bool(receipt_validation.get("ok", false)):
		return receipt_validation
	if campaign_id == "anshi_beta_1_10":
		var followup_receipt_validation := _validate_beta110_followup_receipts(raw)
		if not bool(followup_receipt_validation.get("ok", false)):
			return followup_receipt_validation
		var review_ack_validation := _validate_beta110_review_acknowledgements(raw)
		if not bool(review_ack_validation.get("ok", false)):
			return review_ack_validation
	if campaign_id == "anshi_beta_1_10":
		var route_validation := _validate_beta110_route_record(raw)
		if not bool(route_validation.get("ok", false)):
			return route_validation
	if flags_value is Dictionary and raw.has("campaign_id") and str(raw.get("campaign_id", "")) != str((flags_value as Dictionary).get("campaign_id", raw.get("campaign_id", ""))):
		return {"ok": false, "error": "campaign identity mismatch"}
	if flags_value is Dictionary and raw.has("campaign_days") and int(raw.get("campaign_days", 90)) != int((flags_value as Dictionary).get("campaign_days", raw.get("campaign_days", 90))):
		return {"ok": false, "error": "campaign days mismatch"}
	if campaign_id in ["anshi_beta_1_08", "anshi_beta_1_09", "anshi_beta_1_10"]:
		var expected_flag := "beta108_initialized" if campaign_id == "anshi_beta_1_08" else ("beta109_initialized" if campaign_id == "anshi_beta_1_09" else "beta110_initialized")
		var other_flags := ["beta108_initialized", "beta109_initialized", "beta110_initialized"]
		other_flags.erase(expected_flag)
		if not flags_value is Dictionary or not bool((flags_value as Dictionary).get(expected_flag, false)):
			if not (flags_value is Dictionary and (flags_value as Dictionary).has("campaign_id")):
				return {"ok": true}
			return {"ok": false, "error": "derived campaign initialization flag is missing"}
		for other_flag in other_flags:
			if bool((flags_value as Dictionary).get(other_flag, false)):
				return {"ok": false, "error": "derived campaign initialization flags are inconsistent"}
		return _validate_beta108_snapshot(raw, campaign_id, continuation_provenance)
	return {"ok": true}

func _validate_office_terms(value: Variant, campaign_id: String = "", continuation_provenance: Dictionary = {}, offices: Dictionary = {}) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "error": "invalid office_terms"}
	var active_office_holders: Dictionary = {}
	var active_holder_offices: Dictionary = {}
	for term_id in (value as Dictionary).keys():
		var raw_term: Variant = (value as Dictionary)[term_id]
		if not raw_term is Dictionary:
			return {"ok": false, "error": "invalid office term"}
		var term: Dictionary = raw_term
		if str(term.get("term_id", term_id)) != str(term_id) or str(term.get("office_id", "")).is_empty() or str(term.get("holder_id", "")).is_empty():
			return {"ok": false, "error": "invalid office term identity"}
		if typeof(term.get("start_day", 0)) not in [TYPE_INT, TYPE_FLOAT] or int(term.get("start_day", 0)) < 0:
			return {"ok": false, "error": "invalid office term start"}
		var mode := str(term.get("appointment_mode", ""))
		if mode not in ["initial", "legacy_seeded", "normal", "exceptional", "transfer"]:
			return {"ok": false, "error": "invalid office term mode"}
		if mode == "initial":
			var provenance := str(term.get("appointment_transaction_id", ""))
			if not _is_allowed_initial_office_term_provenance(provenance, campaign_id, continuation_provenance):
				return {"ok": false, "error": "invalid initial office term provenance"}
		if mode == "legacy_seeded" and str(term.get("appointment_transaction_id", "")) != "migration|v17":
			return {"ok": false, "error": "invalid legacy office term provenance"}
		var end_day := int(term.get("end_day", 0))
		if end_day < 0:
			var office_id := str(term.get("office_id", ""))
			var holder_id := str(term.get("holder_id", ""))
			if active_office_holders.has(office_id):
				return {"ok": false, "error": "duplicate active office term"}
			for previous_id in active_holder_offices.get(holder_id, []):
				var first: Variant = offices.get(office_id, {})
				var previous: Variant = offices.get(previous_id, {})
				if not first is Dictionary or not previous is Dictionary:
					return {"ok": false, "error": "invalid active office record"}
				if first.get("office_kind") != "family" or previous.get("office_kind") != "family" or preload("res://scripts/core/character_workload_service.gd").overlaps(first, previous):
					return {"ok": false, "error": "duplicate active office term"}
			active_office_holders[office_id] = term_id
			if not active_holder_offices.has(holder_id): active_holder_offices[holder_id] = []
			active_holder_offices[holder_id].append(office_id)
	return {"ok": true}

func _validate_accountability_cases(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "error": "invalid accountability_cases"}
	var allowed_lifecycles := ["dormant", "open", "investigating", "ready", "decided", "closed"]
	for case_id in (value as Dictionary).keys():
		var raw_case: Variant = (value as Dictionary)[case_id]
		if not raw_case is Dictionary:
			return {"ok": false, "error": "invalid accountability case"}
		var case_record: Dictionary = raw_case
		if case_record.get("case_kind", "official_accountability") not in ["official_accountability", "criminal"]: return {"ok": false, "error": "unknown accountability case kind"}
		if str(case_record.get("case_id", case_id)) != str(case_id) or str(case_record.get("lifecycle", "")) not in allowed_lifecycles:
			return {"ok": false, "error": "invalid accountability case lifecycle"}
		for key in ["subject_ids", "office_ids", "term_ids", "causal_refs", "facts", "claims", "evidence"]:
			if case_record.has(key) and not (case_record.get(key) is Array):
				return {"ok": false, "error": "invalid accountability case %s" % key}
		if case_record.get("decision", {}) != null and not (case_record.get("decision", {}) is Dictionary):
			return {"ok": false, "error": "invalid accountability decision"}
		if str(case_record.get("lifecycle", "")) == "decided" and str(case_record.get("decision_transaction_id", "")).is_empty():
			return {"ok": false, "error": "decided case has no decision transaction"}
	return {"ok": true}

func _validate_political_debts(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "error": "invalid political_debts"}
	for debt_id in (value as Dictionary).keys():
		if not (value as Dictionary)[debt_id] is Dictionary or str(debt_id).is_empty():
			return {"ok": false, "error": "invalid political debt"}
	return {"ok": true}

func _validate_transaction_receipts(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "error": "invalid processed_transactions"}
	for transaction_id in (value as Dictionary).keys():
		var raw_receipt: Variant = (value as Dictionary)[transaction_id]
		if not raw_receipt is Dictionary:
			return {"ok": false, "error": "invalid transaction receipt"}
		var receipt: Dictionary = raw_receipt
		if str(receipt.get("transaction_id", transaction_id)) != str(transaction_id) and receipt.has("transaction_id"):
			return {"ok": false, "error": "transaction receipt identity mismatch"}
		if receipt.has("status") and str(receipt.get("status", "")) != "committed":
			return {"ok": false, "error": "invalid transaction receipt status"}
		if receipt.has("committed_revision") and (typeof(receipt.get("committed_revision")) not in [TYPE_INT, TYPE_FLOAT] or int(receipt.get("committed_revision")) < 1):
			return {"ok": false, "error": "invalid transaction receipt revision"}
	return {"ok": true}

func _validate_beta110_followup_receipts(raw: Dictionary) -> Dictionary:
	var flags_value: Variant = raw.get("flags", {})
	if not flags_value is Dictionary or not (flags_value as Dictionary).has("beta110_followup_receipts"):
		return {"ok": true}
	var receipts_value: Variant = (flags_value as Dictionary).get("beta110_followup_receipts")
	if not receipts_value is Dictionary or (receipts_value as Dictionary).size() > 64:
		return {"ok": false, "error": "invalid beta110 followup receipts"}
	var memorials: Dictionary = raw.get("governance_state", {}).get("memorials", {}) if raw.get("governance_state", {}) is Dictionary and (raw.get("governance_state", {}) as Dictionary).get("memorials", {}) is Dictionary else {}
	for raw_predecessor_id in (receipts_value as Dictionary).keys():
		var predecessor_id := str(raw_predecessor_id)
		if not _is_stable_governance_id(predecessor_id) or not memorials.has(predecessor_id):
			return {"ok": false, "error": "invalid beta110 followup predecessor"}
		var raw_receipt: Variant = (receipts_value as Dictionary).get(raw_predecessor_id)
		if not raw_receipt is Dictionary:
			return {"ok": false, "error": "invalid beta110 followup receipt"}
		var receipt: Dictionary = raw_receipt
		if not _is_bounded_string(receipt.get("branch_id", ""), 128, false) or not _is_bounded_string(receipt.get("memorial_id", ""), 128, false) or str(receipt.get("memorial_id", "")) != predecessor_id:
			return {"ok": false, "error": "invalid beta110 followup receipt identity"}
		if not _is_bounded_string(receipt.get("source_result_hash", ""), 64, false) or str(receipt.get("source_result_hash", "")).length() != 64:
			return {"ok": false, "error": "invalid beta110 followup source hash"}
		if typeof(receipt.get("activation_day", null)) not in [TYPE_INT, TYPE_FLOAT] or int(receipt.get("activation_day", -1)) < 0:
			return {"ok": false, "error": "invalid beta110 followup activation day"}
		var branch_id := str(receipt.get("branch_id", ""))
		if not memorials.has(branch_id) or not memorials.get(branch_id) is Dictionary:
			return {"ok": false, "error": "invalid beta110 followup branch"}
		var branch: Dictionary = memorials.get(branch_id)
		if str(branch.get("previous_memorial_id", "")) != predecessor_id or str(branch.get("source_result_hash", "")) != str(receipt.get("source_result_hash", "")):
			return {"ok": false, "error": "beta110 followup receipt does not match branch"}
	return {"ok": true}

func _validate_beta110_review_acknowledgements(raw: Dictionary) -> Dictionary:
	var workbench_value: Variant = raw.get("court_workbench_state", {})
	if not workbench_value is Dictionary:
		return {"ok": false, "error": "invalid court_workbench_state"}
	var workbench: Dictionary = workbench_value as Dictionary
	if not workbench.has("political_season_reviews_acknowledged"):
		return {"ok": true}
	var acknowledged_value: Variant = workbench.get("political_season_reviews_acknowledged")
	if not acknowledged_value is Dictionary or (acknowledged_value as Dictionary).size() > BETA110_REVIEW_IDS.size():
		return {"ok": false, "error": "invalid beta110 review acknowledgements"}
	for raw_review_id in (acknowledged_value as Dictionary).keys():
		var review_id := str(raw_review_id)
		if not BETA110_REVIEW_IDS.has(review_id):
			return {"ok": false, "error": "unknown beta110 review acknowledgement"}
		if typeof((acknowledged_value as Dictionary).get(raw_review_id, null)) != TYPE_BOOL:
			return {"ok": false, "error": "beta110 review acknowledgement must be boolean"}
	return {"ok": true}

func _validate_beta110_route_record(raw: Dictionary) -> Dictionary:
	var flags: Dictionary = raw.get("flags", {}) if raw.get("flags", {}) is Dictionary else {}
	var route_record_fields := [
		"beta110_route_id",
		"beta110_public_route_id",
		"beta110_route_selected_day",
		"beta110_route_source_refs", "beta110_route_rule_hash"
	]
	var has_route_record_marker := false
	for key in route_record_fields:
		if flags.has(key):
			has_route_record_marker = true
			break
	var route_references: Array = []
	var references: Variant = raw.get("chronicle_causal_references", [])
	if references is Array:
		for raw_reference in references as Array:
			if raw_reference is Dictionary and str((raw_reference as Dictionary).get("kind", "")) == "political_season_route_selection":
				has_route_record_marker = true
				route_references.append((raw_reference as Dictionary).duplicate(true))
	var selection_receipts: Array = []
	var selection_receipt_ids: Array = []
	var receipts: Variant = raw.get("processed_transactions", {})
	if receipts is Dictionary:
		for receipt_key in (receipts as Dictionary).keys():
			var raw_receipt: Variant = (receipts as Dictionary).get(receipt_key)
			if raw_receipt is Dictionary and str((raw_receipt as Dictionary).get("kind", "")) == "select_political_season_route":
				has_route_record_marker = true
				selection_receipts.append((raw_receipt as Dictionary).duplicate(true))
				selection_receipt_ids.append(str(receipt_key))
	# Legacy BETA 1.10 simulation fixtures may carry only the old route flags.
	# The authoritative record starts when any new provenance field is present.
	if not has_route_record_marker:
		return {"ok": true}
	var route_id := str(flags.get("beta110_route_id", "")).strip_edges()
	var public_route_id := str(flags.get("beta110_public_route_id", "")).strip_edges()
	var selected_day: Variant = flags.get("beta110_route_selected_day", null)
	var source_refs: Variant = flags.get("beta110_route_source_refs", null)
	var rule_hash := str(flags.get("beta110_route_rule_hash", "")).strip_edges()
	if route_id.is_empty() or public_route_id.is_empty() or selected_day == null or source_refs == null or rule_hash.is_empty():
		return {"ok": false, "error": "incomplete_beta110_route_record"}
	if typeof(selected_day) not in [TYPE_INT, TYPE_FLOAT] or int(selected_day) < 0:
		return {"ok": false, "error": "incomplete_beta110_route_record"}
	if not source_refs is Array or (source_refs as Array).is_empty():
		return {"ok": false, "error": "incomplete_beta110_route_record"}
	var normalized_sources: Array = []
	for raw_source in source_refs as Array:
		if typeof(raw_source) != TYPE_STRING or str(raw_source).strip_edges().is_empty() or normalized_sources.has(str(raw_source)):
			return {"ok": false, "error": "incomplete_beta110_route_record"}
		normalized_sources.append(str(raw_source))
	if rule_hash.length() != 64:
		return {"ok": false, "error": "incomplete_beta110_route_record"}
	if route_references.size() != 1 or selection_receipts.size() != 1:
		return {"ok": false, "error": "incomplete_beta110_route_record"}
	var reference: Dictionary = route_references[0]
	var expected_reference_id := route_id
	if str(reference.get("id", "")) != expected_reference_id or str(reference.get("route_id", "")) != route_id or str(reference.get("public_route_id", "")) != public_route_id:
		return {"ok": false, "error": "incomplete_beta110_route_record"}
	if int(reference.get("day", -1)) != int(selected_day) or str(reference.get("rule_hash", "")) != rule_hash:
		return {"ok": false, "error": "incomplete_beta110_route_record"}
	if reference.get("source_refs", null) != normalized_sources:
		return {"ok": false, "error": "incomplete_beta110_route_record"}
	var receipt: Dictionary = selection_receipts[0]
	if str(receipt.get("status", "")) != "committed" or str(receipt.get("result_ref", "")) != "political_season_route|%s" % route_id:
		return {"ok": false, "error": "incomplete_beta110_route_record"}
	var transaction_id := str(receipt.get("transaction_id", "")).strip_edges()
	if transaction_id.is_empty() or selection_receipt_ids.size() != 1 or str(selection_receipt_ids[0]) != transaction_id:
		return {"ok": false, "error": "incomplete_beta110_route_record"}
	if not receipts is Dictionary or not (receipts as Dictionary).has(transaction_id) or (receipts as Dictionary).get(transaction_id) != receipt:
		return {"ok": false, "error": "incomplete_beta110_route_record"}
	var committed_revision := int(receipt.get("committed_revision", -1))
	if committed_revision < 1 or committed_revision > int(raw.get("state_revision", -1)):
		return {"ok": false, "error": "incomplete_beta110_route_record"}
	var expected_input_hash_result: Dictionary = CanonicalJSONScript.hash_value({"route_id": route_id, "rule_hash": rule_hash})
	if not bool(expected_input_hash_result.get("ok", false)) or str(receipt.get("input_hash", "")) != str(expected_input_hash_result.get("hash", "")):
		return {"ok": false, "error": "incomplete_beta110_route_record"}
	return {"ok": true}

func _validate_beta108_snapshot(raw: Dictionary, campaign_id: String = "anshi_beta_1_08", continuation_provenance: Dictionary = {}) -> Dictionary:
	var cases: Dictionary = raw.get("accountability_cases", {})
	if cases.size() != 6:
		return {"ok": false, "error": "derived campaign requires six accountability case skeletons"}
	var required_case_ids := [
		"beta108_case_grain_ledger_shortfall", "beta108_case_military_grain_delay", "beta108_case_palace_order_leak",
		"beta108_case_edict_legitimacy", "beta108_case_uighur_aid_cost", "beta108_case_final_assessment"
	]
	for case_id in required_case_ids:
		if not cases.has(case_id):
			return {"ok": false, "error": "missing derived campaign case skeleton"}
	var flags_value: Dictionary = raw.get("flags", {})
	if str(raw.get("campaign_id", flags_value.get("campaign_id", ""))) != str(flags_value.get("campaign_id", "")):
		return {"ok": false, "error": "campaign identity mismatch"}
	var expected_flag := "beta108_initialized" if campaign_id == "anshi_beta_1_08" else ("beta109_initialized" if campaign_id == "anshi_beta_1_09" else "beta110_initialized")
	if not bool(flags_value.get(expected_flag, false)):
		return {"ok": false, "error": "derived campaign initialization flag is missing"}
	var terms: Dictionary = raw.get("office_terms", {})
	for raw_term in terms.values():
		if raw_term is Dictionary and str((raw_term as Dictionary).get("appointment_mode", "")) == "initial" and not _is_allowed_initial_office_term_provenance(str((raw_term as Dictionary).get("appointment_transaction_id", "")), campaign_id, continuation_provenance):
			return {"ok": false, "error": "initial office term provenance does not match campaign"}
	for raw_case in cases.values():
		if raw_case is Dictionary and str((raw_case as Dictionary).get("lifecycle", "")) == "decided" and ((raw_case as Dictionary).get("decision", {}) as Dictionary).is_empty():
			return {"ok": false, "error": "decided case has empty decision"}
	for receipt in (raw.get("processed_transactions", {}) as Dictionary).values():
		if receipt is Dictionary and str((receipt as Dictionary).get("result_ref", "")).is_empty():
			return {"ok": false, "error": "committed transaction has no result ref"}
	return {"ok": true}

func to_transaction_dictionary() -> Dictionary:
	return {
		"persistent": to_dictionary(),
		"transient": {
			"time_overlay_lock_order": court_workbench_state.get("time_overlay_lock_order", []).duplicate(true),
			"is_time_paused": is_time_paused,
			"pause_reason": pause_reason
		},
		"runtime": {
			"dialogue_history_summary": dialogue_history_summary.duplicate(true),
			"pending_dialogue_intent": pending_dialogue_intent.duplicate(true),
			"pending_dialogue_response": pending_dialogue_response.duplicate(true),
			"active_dialogue_sessions": active_dialogue_sessions.duplicate(true),
			"dialogue_session_history": dialogue_session_history.duplicate(true)
		}
	}

func load_transaction_dictionary(snapshot: Dictionary) -> Dictionary:
	if not (snapshot is Dictionary) or not (snapshot.get("persistent", {}) is Dictionary):
		return {"ok": false, "error": "invalid transaction snapshot"}
	var previous_load_epoch := runtime_load_epoch
	var loaded := try_load_dictionary(snapshot.get("persistent", {}) as Dictionary)
	if not bool(loaded.get("ok", false)): return loaded
	_restore_transaction_runtime(snapshot, previous_load_epoch)
	return {"ok": true}

# Internal companion to the strict transaction loader. The transaction engine
# also uses it after publishing a working state it has just fully validated.
func _restore_transaction_runtime(snapshot: Dictionary, previous_load_epoch: int) -> void:
	runtime_load_epoch = previous_load_epoch
	var transient: Dictionary = snapshot.get("transient", {}) if snapshot.get("transient", {}) is Dictionary else {}
	court_workbench_state["time_overlay_lock_order"] = TimeControllerScript.normalize_overlay_lock_order(transient.get("time_overlay_lock_order", []))
	is_time_paused = bool(transient.get("is_time_paused", false))
	pause_reason = str(transient.get("pause_reason", ""))
	var runtime: Dictionary = snapshot.get("runtime", {}) if snapshot.get("runtime", {}) is Dictionary else {}
	for key in ["dialogue_history_summary", "pending_dialogue_intent", "pending_dialogue_response", "active_dialogue_sessions", "dialogue_session_history"]:
		if runtime.has(key): set(key, runtime[key].duplicate(true) if runtime[key] is Dictionary or runtime[key] is Array else runtime[key])

func to_rule_state_dictionary() -> Dictionary:
	var projected: Dictionary = to_dictionary()
	projected["governance_state"] = _project_governance_rule_paths(governance_state)
	for transient_key in ["pending_dialogue_intent", "pending_dialogue_response", "active_dialogue_sessions", "dialogue_session_history", "dialogue_history_summary"]:
		projected.erase(transient_key)
	return projected

func rule_payload_hash_without_revision() -> String:
	var payload := to_rule_state_dictionary()
	payload.erase("state_revision")
	var encoded: Dictionary = CanonicalJSONScript.hash_value(payload)
	return str(encoded.get("hash", "")) if bool(encoded.get("ok", false)) else ""

func finalize_authoritative_mutation(before_hash: String) -> bool:
	var after_hash := rule_payload_hash_without_revision()
	if before_hash.is_empty() or after_hash.is_empty() or before_hash == after_hash:
		return false
	state_revision += 1
	return true

func rule_state_hash_result() -> Dictionary:
	var encoded: Dictionary = CanonicalJSONScript.encode(to_rule_state_dictionary())
	if not bool(encoded.get("ok", false)): return encoded
	return {"ok": true, "hash": str(encoded.get("text", "")).sha256_text()}

func _normalize_pre_repair_v19(raw: Dictionary) -> Dictionary:
	var working := raw.duplicate(true)
	var flags: Dictionary = working.get("flags", {}) if working.get("flags", {}) is Dictionary else {}
	var campaign_id := str(working.get("campaign_id", flags.get("campaign_id", "")))
	if int(working.get("save_version", SAVE_VERSION)) != SAVE_VERSION or campaign_id != "anshi_beta_1_10":
		return working
	var workbench: Dictionary = working.get("court_workbench_state", {}) if working.get("court_workbench_state", {}) is Dictionary else {}
	var legacy_review_acknowledged := bool(workbench.get("beta110_season_review_acknowledged", false))
	if legacy_review_acknowledged:
		var acknowledged: Dictionary = workbench.get("political_season_reviews_acknowledged", {}) if workbench.get("political_season_reviews_acknowledged", {}) is Dictionary else {}
		acknowledged["beta110_supply_review"] = true
		workbench["political_season_reviews_acknowledged"] = acknowledged
	workbench.erase("beta110_season_review_acknowledged")
	if not workbench.has("political_season_reviews_acknowledged"):
		workbench["political_season_reviews_acknowledged"] = {}
	working["court_workbench_state"] = workbench
	return working

func _validate_beta110_continuation(value: Variant, campaign_id: String, provided: bool = false) -> Dictionary:
	if campaign_id != "anshi_beta_1_10":
		if not provided:
			return {"ok": true, "data": {}}
		return {"ok": false, "error": "unexpected beta110 continuation provenance"}
	if not provided:
		return {"ok": true, "data": {}}
	if not (value is Dictionary):
		return {"ok": false, "error": "invalid beta110 continuation provenance"}
	var continuation: Dictionary = value
	if continuation.is_empty():
		return {"ok": false, "error": "invalid beta110 continuation provenance"}
	for key in continuation.keys():
		if typeof(key) != TYPE_STRING or not BETA110_CONTINUATION_ALLOWED_FIELDS.has(key):
			return {"ok": false, "error": "invalid beta110 continuation provenance"}
	for key in BETA110_CONTINUATION_ALLOWED_FIELDS:
		if not continuation.has(key):
			return {"ok": false, "error": "invalid beta110 continuation provenance"}
	if str(continuation.get("source_campaign_id", "")) != "anshi_beta_1_09":
		return {"ok": false, "error": "invalid beta110 continuation provenance"}
	if typeof(continuation.get("source_save_version", null)) not in [TYPE_INT, TYPE_FLOAT] or int(continuation.get("source_save_version", 0)) != 18:
		return {"ok": false, "error": "invalid beta110 continuation provenance"}
	if str(continuation.get("source_checkpoint_id", "")) != BETA110_CONTINUATION_CHECKPOINT_ID:
		return {"ok": false, "error": "invalid beta110 continuation provenance"}
	var source_fingerprint := str(continuation.get("source_fingerprint", "")).strip_edges()
	if source_fingerprint.length() != 64:
		return {"ok": false, "error": "invalid beta110 continuation provenance"}
	return {"ok": true, "data": continuation.duplicate(true)}

func _is_allowed_initial_office_term_provenance(provenance: String, campaign_id: String, continuation_provenance: Dictionary = {}) -> bool:
	if campaign_id == "anshi_beta_1_14":
		return provenance == "bootstrap|anshi_beta_1_14"
	if campaign_id == "anshi_beta_1_10":
		if provenance == "bootstrap|anshi_beta_1_10":
			return true
		return provenance == "bootstrap|anshi_beta_1_09" and not continuation_provenance.is_empty()
	if campaign_id in ["anshi_beta_1_08", "anshi_beta_1_09"]:
		return provenance == "bootstrap|%s" % campaign_id
	return provenance in ["bootstrap|anshi_beta_1_08", "bootstrap|anshi_beta_1_09"]

func rule_state_hash() -> String:
	var result := rule_state_hash_result()
	return str(result.get("hash", "")) if bool(result.get("ok", false)) else ""

func _normalize_player_character_id(value: Variant) -> String:
	var character_id := str(value).strip_edges()
	return character_id if not character_id.is_empty() else DEFAULT_PLAYER_CHARACTER_ID

func _sanitize_dialogue_persistence(value: Variant) -> Variant:
	if value is Dictionary:
		var sanitized := {}
		for key in value.keys():
			var key_str := str(key)
			if key_str.to_lower() in ["api_key", "secret", "authorization", "private_audit", "hidden_truth"]:
				continue
			sanitized[key] = _sanitize_dialogue_persistence(value[key])
		return sanitized
	if value is Array:
		var sanitized: Array = []
		for item in value:
			sanitized.append(_sanitize_dialogue_persistence(item))
		return sanitized
	if value is String:
		return _redact_dialogue_secret_string(str(value))
	return value

func _redact_dialogue_secret_string(text: String) -> String:
	if text.is_empty():
		return text
	var lower := text.to_lower()
	if lower.contains("sk-") or lower.contains("bearer ") or lower.contains("api_key") or lower.contains("rk-") or lower.contains("pk-"):
		var regex := RegEx.new()
		regex.compile("(?i)(sk-[a-z0-9_\\-]+|rk-[a-z0-9_\\-]+|pk-[a-z0-9_\\-]+|bearer\\s+[a-z0-9_.\\-]+)")
		return regex.sub(text, "[REDACTED_SECRET]", true)
	return text

func _sanitize_long_term_state(value: Variant) -> Variant:
	if not value is Dictionary and not value is Array:
		return value
	var sanitized: Variant = value.duplicate(true)
	return _sanitize_long_term_containers(sanitized)

# Called only on containers owned by this snapshot. Scalar leaves need no
# recursive call; allocating and copying every ancestor again is unnecessary.
func _sanitize_long_term_containers(value: Variant) -> Variant:
	if value is Dictionary:
		if value.is_typed():
			var untyped: Dictionary = {}
			untyped.merge(value)
			value = untyped
		for key in value.keys():
			var field := str(key)
			if field in ["active_dialogue_sessions", "dialogue_session_history", "assistant_conversation_state"]:
				value[key] = _sanitize_dialogue_persistence(value[key])
				continue
			if field.to_lower() in ["raw_text", "original_text", "user_text", "player_text", "free_input"]:
				value.erase(key)
				continue
			var child: Variant = value[key]
			if field == "accountability_cases" and child is Dictionary:
				if child.is_typed():
					var untyped_cases: Dictionary = {}
					untyped_cases.merge(child)
					child = untyped_cases
				for case_id in child:
					var case_record: Variant = child[case_id]
					if case_record is Dictionary:
						if case_record.is_typed():
							var untyped_case: Dictionary = {}
							untyped_case.merge(case_record)
							case_record = untyped_case
						for derived_key in ["available_verdicts", "required_fact_kinds", "minimum_independent_sources", "forced_removal_available"]:
							case_record.erase(derived_key)
					if case_record is Dictionary or case_record is Array:
						child[case_id] = _sanitize_long_term_containers(case_record)
				value[key] = child
				continue
			if child is Dictionary or child is Array:
				value[key] = _sanitize_long_term_containers(child)
	elif value is Array:
		if value.is_typed():
			var untyped: Array = []
			untyped.assign(value)
			value = untyped
		for index in value.size():
			var item: Variant = value[index]
			if item is Dictionary or item is Array:
				value[index] = _sanitize_long_term_containers(item)
	return value

func _sanitize_accountability_case_policies(value: Dictionary) -> Dictionary:
	var sanitized: Dictionary = {}
	for case_id in value.keys():
		var raw_case: Variant = value[case_id]
		if not raw_case is Dictionary:
			sanitized[case_id] = _sanitize_long_term_state(raw_case)
			continue
		var case_record: Dictionary = (raw_case as Dictionary).duplicate(true)
		for derived_key in ["available_verdicts", "required_fact_kinds", "minimum_independent_sources", "forced_removal_available"]:
			case_record.erase(derived_key)
		sanitized[case_id] = _sanitize_long_term_state(case_record)
	return sanitized

func _default_current_date() -> Dictionary:
	return {
		"era": "至德",
		"year": 1,
		"month": 7,
		"day": 12
	}

func _default_governance_state() -> Dictionary:
	return {
		"memorials": {}, "consultations": {}, "councils": {}, "orders": {},
		"reports": [], "corrections": {}, "case_progress": {}, "rule_seed": 107,
		"tutorial": {"case_id": "", "step": "", "completed": false},
		"reservations": {"resources": {}, "characters": {}, "offices": {}, "routes": {}},
		"next_sequence": 1
	}

func _normalize_governance_state(value: Variant) -> Dictionary:
	var normalized := _default_governance_state()
	if not (value is Dictionary):
		return normalized
	var source: Dictionary = value
	for key in ["memorials", "consultations", "councils", "orders", "reservations"]:
		if source.get(key) is Dictionary:
			normalized[key] = (source.get(key) as Dictionary).duplicate(true)
	var consultations: Dictionary = normalized.get("consultations", {})
	for consultation_id in consultations.keys():
		if not consultations[consultation_id] is Dictionary:
			continue
		var consultation: Dictionary = consultations[consultation_id].duplicate(true)
		consultation["conversation_phase"] = str(consultation.get("conversation_phase", "talking"))
		consultation["turns"] = (consultation.get("turns", []) as Array).duplicate(true) if consultation.get("turns", []) is Array else []
		consultation["selected_turn_ids"] = (consultation.get("selected_turn_ids", []) as Array).duplicate(true) if consultation.get("selected_turn_ids", []) is Array else []
		consultation["draft_text"] = str(consultation.get("draft_text", ""))
		consultation["draft_source"] = str(consultation.get("draft_source", ""))
		consultation["draft_order_id"] = str(consultation.get("draft_order_id", ""))
		consultations[consultation_id] = consultation
	normalized["consultations"] = consultations
	if source.get("reports") is Array:
		normalized["reports"] = _normalize_governance_reports(source.get("reports", []))
	var reservations: Dictionary = normalized.get("reservations", {})
	for key in ["resources", "characters", "offices", "routes"]:
		if not (reservations.get(key) is Dictionary):
			reservations[key] = {}
	normalized["reservations"] = reservations
	normalized["next_sequence"] = maxi(int(source.get("next_sequence", 1)), 1)
	if source.get("corrections") is Dictionary: normalized["corrections"] = (source.get("corrections") as Dictionary).duplicate(true)
	if source.get("case_progress") is Dictionary: normalized["case_progress"] = (source.get("case_progress") as Dictionary).duplicate(true)
	normalized["rule_seed"] = maxi(int(source.get("rule_seed", 107)), 0)
	if source.get("tutorial") is Dictionary:
		normalized["tutorial"] = {
			"case_id": str((source.get("tutorial") as Dictionary).get("case_id", "")),
			"step": str((source.get("tutorial") as Dictionary).get("step", "")),
			"completed": bool((source.get("tutorial") as Dictionary).get("completed", false))
		}
	return normalized

func _normalize_governance_reports(value: Variant) -> Array:
	var normalized: Array = []
	if not value is Array:
		return normalized
	for raw_report in value:
		if not raw_report is Dictionary:
			continue
		var report := (raw_report as Dictionary).duplicate(true)
		# source_memorial_id was briefly emitted by BETA 1.09 report projection.
		# It is derived from the order/memorial link and must not be persisted in
		# the strict authoritative report record.
		report.erase("source_memorial_id")
		normalized.append(report)
	return normalized

func _governance_state_for_serialization() -> Dictionary:
	var serialized := governance_state.duplicate(true)
	serialized["reports"] = _normalize_governance_reports(serialized.get("reports", []))
	return serialized

func _validate_governance_snapshot(value: Variant, provided: bool = true) -> Dictionary:
	if not (value is Dictionary): return {"ok": true} if not provided else {"ok": false, "error": "invalid governance state"}
	var source: Dictionary = value
	var allowed := _default_governance_state()
	for key in source.keys():
		if not allowed.has(key): return {"ok": false, "error": "unknown governance field: " + str(key)}
	for container_name in ["memorials", "consultations", "councils", "orders", "corrections", "case_progress"]:
		if source.has(container_name) and not (source.get(container_name) is Dictionary): return {"ok": false, "error": "invalid governance container: " + container_name}
	if source.has("reports") and not (source.get("reports") is Array): return {"ok": false, "error": "invalid governance reports"}
	if source.has("reservations") and not (source.get("reservations") is Dictionary): return {"ok": false, "error": "invalid governance reservations"}
	for container_name in ["memorials", "consultations", "councils", "orders"]:
		var container: Dictionary = source.get(container_name, {}) if source.get(container_name, {}) is Dictionary else {}
		for record_id in container.keys():
			if not _is_stable_governance_id(record_id) or not (container[record_id] is Dictionary): return {"ok": false, "error": "invalid governance record"}
			var record: Dictionary = container[record_id]
			if not _has_only_governance_fields(record, GOVERNANCE_RECORD_FIELDS.get(container_name, [])):
				return {"ok": false, "error": "unknown governance record field"}
			var primary_id_key: String = str({"memorials": "memorial_id", "consultations": "consultation_id", "councils": "council_id", "orders": "order_id"}.get(container_name, ""))
			if typeof(record.get(primary_id_key, null)) != TYPE_STRING or str(record.get(primary_id_key)) != str(record_id): return {"ok": false, "error": "invalid governance record id"}
			if container_name == "memorials":
				for required_key in ["case_chain_id", "case_phase", "status", "activated_day", "deadline_day", "consultation_ids", "active_council_id", "order_id", "closed_day", "outcome", "activation_variant"]:
					if not record.has(required_key): return {"ok": false, "error": "incomplete memorial lifecycle record"}
				if str(record.get("status", "")) not in MEMORIAL_STATUSES or typeof(record.get("case_chain_id")) != TYPE_STRING or typeof(record.get("case_phase")) != TYPE_STRING or not _is_integral_at_least(record.get("activated_day"), 0) or not _is_integral_at_least(record.get("deadline_day"), 0) or typeof(record.get("consultation_ids")) != TYPE_ARRAY or typeof(record.get("active_council_id")) != TYPE_STRING or typeof(record.get("order_id")) != TYPE_STRING or not _is_integral_at_least(record.get("closed_day"), -1) or typeof(record.get("outcome")) != TYPE_STRING or typeof(record.get("activation_variant")) != TYPE_STRING: return {"ok": false, "error": "invalid memorial lifecycle record"}
			if container_name == "consultations":
				if record.has("status") and str(record.get("status")) not in ["open", "adopted", "rejected", "bypassed"]: return {"ok": false, "error": "invalid consultation status"}
				if record.has("conversation_phase") and str(record.get("conversation_phase")) not in ["talking", "selecting", "drafted"]: return {"ok": false, "error": "invalid consultation phase"}
				if record.has("turns") and not (record.get("turns") is Array): return {"ok": false, "error": "invalid consultation turns"}
				if record.has("selected_turn_ids") and not (record.get("selected_turn_ids") is Array): return {"ok": false, "error": "invalid consultation selections"}
			if container_name == "councils" and ((record.has("status") and str(record.get("status")) not in ["active", "sealed", "completed"]) or (record.has("phase") and str(record.get("phase")) not in ["legacy_completed", "awaiting_opening_question", "opening", "awaiting_round_one_decision", "awaiting_intervention_1", "cross_examination", "awaiting_intervention_2", "final_position", "adoption", "drafting", "sealed"])): return {"ok": false, "error": "invalid council stage"}
			if container_name == "orders" and record.has("stage") and str(record.get("stage")) not in ["draft", "issued", "delivered", "acknowledged", "gathering", "executing", "closed", "withdrawn"]: return {"ok": false, "error": "invalid order stage"}
			if container_name == "orders" and record.has("forced_result") and (typeof(record.get("forced_result")) != TYPE_STRING or (not str(record.get("forced_result", "")).is_empty() and not GOVERNANCE_ORDER_RESULTS.has(str(record.get("forced_result", ""))))): return {"ok": false, "error": "invalid forced result"}
			if record.has("revision") and (typeof(record.get("revision")) not in [TYPE_INT, TYPE_FLOAT] or int(record.get("revision")) < 0): return {"ok": false, "error": "invalid governance revision"}
	var memorials: Dictionary = source.get("memorials", {}) if source.get("memorials", {}) is Dictionary else {}
	var councils: Dictionary = source.get("councils", {}) if source.get("councils", {}) is Dictionary else {}
	var orders: Dictionary = source.get("orders", {}) if source.get("orders", {}) is Dictionary else {}
	var consultations: Dictionary = source.get("consultations", {}) if source.get("consultations", {}) is Dictionary else {}
	if not _validate_governance_reports(source.get("reports", [])): return {"ok": false, "error": "invalid governance report"}
	for extra_name in ["corrections", "case_progress"]:
		var extras: Dictionary = source.get(extra_name, {}) if source.get(extra_name, {}) is Dictionary else {}
		if not extras.is_empty(): return {"ok": false, "error": "unsupported governance extension state: " + extra_name}
	if typeof(source.get("next_sequence", 1)) not in [TYPE_INT, TYPE_FLOAT] or int(source.get("next_sequence", 1)) < 1: return {"ok": false, "error": "invalid governance sequence"}
	if typeof(source.get("rule_seed", 107)) not in [TYPE_INT, TYPE_FLOAT] or int(source.get("rule_seed", 107)) < 0: return {"ok": false, "error": "invalid governance seed"}
	if not _validate_reservations(source.get("reservations", {}), orders): return {"ok": false, "error": "invalid governance reservations"}
	if source.has("tutorial"):
		var tutorial: Variant = source.get("tutorial")
		if not _has_only_governance_fields(tutorial, ["case_id", "step", "completed"]) or typeof((tutorial as Dictionary).get("case_id", "")) != TYPE_STRING or typeof((tutorial as Dictionary).get("step", "")) != TYPE_STRING or typeof((tutorial as Dictionary).get("completed", false)) != TYPE_BOOL: return {"ok": false, "error": "invalid governance tutorial"}
	for council in councils.values():
		if council is Dictionary:
			var council_data: Dictionary = council
			if not str(council_data.get("memorial_id", "")).is_empty() and not memorials.has(str(council_data.get("memorial_id", ""))): return {"ok": false, "error": "council memorial reference is invalid"}
			if str(council_data.get("status", "")) in ["active", "sealed"] and not str(council_data.get("memorial_id", "")).is_empty() and str((memorials[str(council_data.get("memorial_id", ""))] as Dictionary).get("active_council_id", "")) != str(council_data.get("council_id", "")): return {"ok": false, "error": "council memorial reverse link is invalid"}
			if not str(council_data.get("draft_order_id", "")).is_empty() and (not orders.has(str(council_data.get("draft_order_id", ""))) or str((orders[str(council_data.get("draft_order_id", ""))] as Dictionary).get("council_id", "")) != str(council_data.get("council_id", ""))): return {"ok": false, "error": "council order reference is invalid"}
	for order in orders.values():
		if order is Dictionary:
			var order_data: Dictionary = order
			if not str(order_data.get("council_id", "")).is_empty() and (not councils.has(str(order_data.get("council_id", ""))) or str((councils[str(order_data.get("council_id", ""))] as Dictionary).get("draft_order_id", "")) != str(order_data.get("order_id", ""))): return {"ok": false, "error": "order council reference is invalid"}
			var source_memorial_id := str(order_data.get("source_memorial_id", ""))
			if not source_memorial_id.is_empty() and (not memorials.has(source_memorial_id) or (not str(order_data.get("council_id", "")).is_empty() and str((councils[str(order_data.get("council_id", ""))] as Dictionary).get("memorial_id", "")) != source_memorial_id)): return {"ok": false, "error": "order memorial reference is invalid"}
			if str(order_data.get("stage", "")) not in ["draft", "withdrawn"] and not source_memorial_id.is_empty() and str((memorials[source_memorial_id] as Dictionary).get("order_id", "")) != str(order_data.get("order_id", "")): return {"ok": false, "error": "order memorial reverse link is invalid"}
	for consultation in consultations.values():
		if consultation is Dictionary:
			var consultation_data: Dictionary = consultation
			var consultation_memorial_id := str(consultation_data.get("memorial_id", ""))
			if not consultation_memorial_id.is_empty() and (not memorials.has(consultation_memorial_id) or not ((memorials[consultation_memorial_id] as Dictionary).get("consultation_ids", []) as Array).has(str(consultation_data.get("consultation_id", "")))): return {"ok": false, "error": "consultation memorial reference is invalid"}
	for memorial in memorials.values():
		if memorial is Dictionary:
			var memorial_data: Dictionary = memorial
			var active_council_id := str(memorial_data.get("active_council_id", ""))
			if not active_council_id.is_empty() and (not councils.has(active_council_id) or str((councils[active_council_id] as Dictionary).get("memorial_id", "")) != str(memorial_data.get("memorial_id", ""))): return {"ok": false, "error": "memorial council reference is invalid"}
			var consultation_ids: Variant = memorial_data.get("consultation_ids", [])
			if not (consultation_ids is Array): return {"ok": false, "error": "invalid memorial consultations"}
			for consultation_id in consultation_ids:
				if not consultations.has(str(consultation_id)) or str((consultations[str(consultation_id)] as Dictionary).get("memorial_id", "")) != str(memorial_data.get("memorial_id", "")): return {"ok": false, "error": "memorial consultation reference is invalid"}
			var order_id := str(memorial_data.get("order_id", ""))
			if not order_id.is_empty():
				if not orders.has(order_id): return {"ok": false, "error": "memorial order reference is invalid"}
				var memorial_order: Dictionary = orders[order_id] as Dictionary
				if str(memorial_order.get("source_memorial_id", "")) != str(memorial_data.get("memorial_id", "")): return {"ok": false, "error": "memorial order source is invalid"}
				var memorial_order_council_id := str(memorial_order.get("council_id", ""))
				if not memorial_order_council_id.is_empty() and (not councils.has(memorial_order_council_id) or str((councils[memorial_order_council_id] as Dictionary).get("memorial_id", "")) != str(memorial_data.get("memorial_id", ""))): return {"ok": false, "error": "memorial order council is invalid"}
	return {"ok": true}

func _has_only_governance_fields(value: Variant, allowed_fields: Array) -> bool:
	if not (value is Dictionary): return false
	for key in (value as Dictionary).keys():
		if typeof(key) != TYPE_STRING or not allowed_fields.has(key): return false
	return true

func _validate_governance_reports(value: Variant) -> bool:
	if not (value is Array): return false
	var allowed_fields: Array = (GOVERNANCE_RECORD_FIELDS.reports as Array).duplicate()
	allowed_fields.append_array(LEGACY_GOVERNANCE_REPORT_FIELDS)
	for raw_report in value:
		if not _has_only_governance_fields(raw_report, allowed_fields): return false
		var report: Dictionary = raw_report
		if not _is_stable_governance_id(report.get("report_id", "")) or typeof(report.get("status", "")) != TYPE_STRING or (report.has("day") and (typeof(report.get("day")) not in [TYPE_INT, TYPE_FLOAT] or int(report.get("day")) < 0)) or (report.has("confidence") and typeof(report.get("confidence")) not in [TYPE_INT, TYPE_FLOAT]): return false
		if report.has("execution_details") and not (report.get("execution_details") is Dictionary): return false
		if report.has("source_memorial_id") and typeof(report.get("source_memorial_id")) != TYPE_STRING: return false
		for field in ["source_kind", "review_id", "node_id"]:
			if report.has(field) and typeof(report.get(field)) != TYPE_STRING: return false
		if report.has("source_ids"):
			if not (report.get("source_ids") is Array): return false
			var seen_source_ids: Dictionary = {}
			for raw_source_id in report.get("source_ids", []) as Array:
				if typeof(raw_source_id) != TYPE_STRING or str(raw_source_id).strip_edges().is_empty() or seen_source_ids.has(str(raw_source_id)): return false
				seen_source_ids[str(raw_source_id)] = true
	return true

func _validate_reservations(value: Variant, orders: Dictionary) -> bool:
	if not (value is Dictionary) or not _has_only_governance_fields(value, ["resources", "characters", "offices", "routes"]): return false
	for bucket in ["resources", "characters", "offices", "routes"]:
		var entries: Variant = (value as Dictionary).get(bucket, {})
		if not (entries is Dictionary): return false
		for key in (entries as Dictionary).keys():
			if typeof(key) != TYPE_STRING or not orders.has(str((entries as Dictionary).get(key, ""))): return false
	return true

func _is_stable_governance_id(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not str(value).strip_edges().is_empty() and str(value).length() <= 128

func _is_integral_at_least(value: Variant, minimum: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and floor(float(value)) == float(value) and int(value) >= minimum

func _project_governance_rule_paths(value: Variant) -> Dictionary:
	var projected: Dictionary = value.duplicate(true) if value is Dictionary else _default_governance_state()
	if projected.get("reports") is Array:
		var reports: Array = []
		for entry in projected.get("reports", []):
			var report: Dictionary = entry.duplicate(true) if entry is Dictionary else {}
			report.erase("public_text"); report.erase("wording_source")
			report.erase("source_memorial_id")
			reports.append(report)
		projected["reports"] = reports
	for container_name in ["councils", "orders", "consultations"]:
		var container: Dictionary = projected.get(container_name, {}).duplicate(true) if projected.get(container_name) is Dictionary else {}
		for item_id in container.keys():
			var item: Dictionary = container[item_id].duplicate(true) if container[item_id] is Dictionary else {}
			if container_name == "councils" and item.get("turns") is Array:
				var turns: Array = []
				for turn in item.get("turns", []):
					var copy: Dictionary = turn.duplicate(true) if turn is Dictionary else {}
					copy.erase("text"); copy.erase("tone"); copy.erase("source")
					turns.append(copy)
				item["turns"] = turns
			elif container_name == "orders":
				item.erase("edict_text"); item.erase("wording_source")
			elif container_name == "consultations":
				item.erase("public_text"); item.erase("tone"); item.erase("wording_source")
				item.erase("draft_text")
				if item.get("turns") is Array:
					var consultation_turns: Array = []
					for raw_turn in item.get("turns", []):
						var consultation_turn: Dictionary = raw_turn.duplicate(true) if raw_turn is Dictionary else {}
						consultation_turn.erase("text"); consultation_turn.erase("speaker_name")
						consultation_turns.append(consultation_turn)
					item["turns"] = consultation_turns
			container[item_id] = item
		projected[container_name] = container
	return projected

func _sanitized_court_workbench_state() -> Dictionary:
	var copy := court_workbench_state.duplicate(true)
	for key in TRANSIENT_WORKBENCH_KEYS:
		copy[key] = TRANSIENT_WORKBENCH_DEFAULTS[key].duplicate(true) if TRANSIENT_WORKBENCH_DEFAULTS[key] is Array or TRANSIENT_WORKBENCH_DEFAULTS[key] is Dictionary else TRANSIENT_WORKBENCH_DEFAULTS[key]
	return copy

func _copied_dictionary_or_default(value: Variant, fallback: Dictionary) -> Dictionary:
	return value.duplicate(true) if value is Dictionary else fallback.duplicate(true)

func _sanitized_pause_reason() -> String:
	if not TRANSIENT_OVERLAY_PAUSE_REASONS.has(pause_reason):
		return pause_reason
	return "paused_after_overlay" if is_time_paused else ""

func _normalize_character_states(value: Variant, campaign_id: String = "") -> Dictionary:
	if not (value is Dictionary):
		return {}
	var character_ids: Array = []
	for raw_character_id in value.keys():
		if _is_bounded_string(raw_character_id, 64):
			character_ids.append(raw_character_id)
	character_ids.sort()
	if character_ids.size() > 256:
		var prioritized: Array = []
		var non_living_dynamic: Array = []
		for cid in character_ids:
			var entry = value.get(cid)
			var is_dyn = entry is Dictionary and bool(entry.get("is_dynamic", false))
			var is_dead = entry is Dictionary and str(entry.get("status", "")) in ["dead", "executed"]
			if is_dyn and is_dead:
				non_living_dynamic.append(cid)
			else:
				prioritized.append(cid)
		if prioritized.size() <= 256:
			var need := 256 - prioritized.size()
			character_ids = prioritized + non_living_dynamic.slice(0, need)
		else:
			character_ids = prioritized.slice(0, 256)
	var normalized: Dictionary = {}
	for character_id in character_ids:
		var raw_entry = value.get(character_id)
		if not (raw_entry is Dictionary):
			continue
		if raw_entry.has("id") and (not _is_bounded_string(raw_entry.get("id"), 64) or str(raw_entry.get("id")) != str(character_id)):
			continue
		if raw_entry.has("name") and not _is_bounded_string(raw_entry.get("name"), 128, true):
			continue
		if raw_entry.has("status") and not _is_bounded_string(raw_entry.get("status"), 64, true):
			continue
		var raw_relationships = raw_entry.get("relationships", {})
		var raw_memories = raw_entry.get("memory_summary", [])
		if not (raw_relationships is Dictionary) or not (raw_memories is Array):
			continue
		var relationships: Dictionary = {}
		var relationship_ids: Array = []
		for raw_relationship_id in raw_relationships.keys():
			if _is_bounded_string(raw_relationship_id, 64):
				relationship_ids.append(raw_relationship_id)
		relationship_ids.sort()
		if relationship_ids.size() > 128:
			relationship_ids = relationship_ids.slice(0, 128)
		for relationship_id in relationship_ids:
			var relationship_value = raw_relationships.get(relationship_id)
			if _is_integral_finite_number(relationship_value):
				relationships[relationship_id] = int(round(float(relationship_value)))
		var memories: Array = []
		for raw_memory in raw_memories:
			if _is_bounded_string(raw_memory, 512):
				memories.append(str(raw_memory))
		if memories.size() > 100:
			memories = memories.slice(memories.size() - 100, memories.size())
		var fate_causal_refs := _normalize_character_fate_refs(raw_entry.get("fate_causal_refs", []), str(character_id), campaign_id)
		normalized[character_id] = {
			"id": str(character_id),
			"name": str(raw_entry.get("name", character_id)),
			"status": str(raw_entry.get("status", "")),
			"relationships": relationships,
			"memory_summary": memories,
			"fate_causal_refs": fate_causal_refs
		}
		# Location is a world fact used by local observation, not transient UI state.
		# Preserve even invalid appearance payloads so atomic save validation rejects
		# corruption instead of dropping DNA or replacing it from a seed.
		if raw_entry.has("appearance"):
			var appearance_value: Variant = raw_entry.appearance
			normalized[character_id]["appearance"] = appearance_value.duplicate(true) if appearance_value is Dictionary or appearance_value is Array else appearance_value
		# Preserve only explicit valid IDs; never infer a location for old snapshots.
		if _is_bounded_string(raw_entry.get("location_id"), 128):
			normalized[character_id]["location_id"] = str(raw_entry.location_id)
		if _is_bounded_string(raw_entry.get("clan_id"), 128):
			normalized[character_id]["clan_id"] = str(raw_entry.clan_id)
		if _is_bounded_string(raw_entry.get("household_id"), 128):
			normalized[character_id]["household_id"] = str(raw_entry.household_id)
		if _is_bounded_string(raw_entry.get("patron_id"), 64, true):
			normalized[character_id]["patron_id"] = str(raw_entry.patron_id)
		if campaign_id == "anshi_beta_1_14" and raw_entry.has("allegiance"):
			normalized[character_id]["allegiance"] = raw_entry.allegiance.duplicate(true) if raw_entry.allegiance is Dictionary else raw_entry.allegiance
		if _is_bounded_string(raw_entry.get("search_source_ref"), 512):
			normalized[character_id]["search_source_ref"] = str(raw_entry.search_source_ref)
		if raw_entry.has("life_goal"):
			var goal: Variant = raw_entry.life_goal
			normalized[character_id]["life_goal"] = goal.duplicate(true) if goal is Dictionary or goal is Array else goal

		# Preserve dynamic character attributes
		# School learning uses a persisted skill for authored people too; unlike
		# descriptive scenario attributes, this value is read during daily work.
		if not bool(raw_entry.get("is_dynamic", false)) and raw_entry.get("stats") is Dictionary and raw_entry.stats.has("scholarship"):
			normalized[character_id]["stats"] = {"scholarship": clampi(int(raw_entry.stats.scholarship), 0, 100)}
		# Authored managers' economic abilities are now used by actual daily work.
		if campaign_id=="anshi_beta_1_14":
			for field in ["traits","stress","loyalty"]:
				if raw_entry.has(field):normalized[character_id][field]=raw_entry[field].duplicate(true) if raw_entry[field] is Array else raw_entry[field]
				else:normalized[character_id].erase(field)
		# Preserve invalid values too, so transaction validation rejects corruption.
		if campaign_id=="anshi_beta_1_14" and not bool(raw_entry.get("is_dynamic",false)) and raw_entry.get("stats") is Dictionary:
			var economic_stats: Dictionary = normalized[character_id].get("stats",{})
			for field in ["finance","governance","diplomacy"]:
				if raw_entry.stats.has(field): economic_stats[field] = raw_entry.stats[field]
			if not economic_stats.is_empty(): normalized[character_id]["stats"] = economic_stats
		if campaign_id=="anshi_beta_1_14" and raw_entry.has("stats") and not raw_entry.stats is Dictionary:
			normalized[character_id]["stats"] = raw_entry.stats
		if bool(raw_entry.get("is_dynamic", false)):
			normalized[character_id]["is_dynamic"] = true
			if _is_bounded_string(raw_entry.get("archetype_id"), 64):
				normalized[character_id]["archetype_id"] = str(raw_entry.get("archetype_id"))
			if raw_entry.get("dominant_ability") in ["military", "governance", "finance", "intrigue", "diplomacy", "prowess", "medicine"]:
				normalized[character_id]["dominant_ability"] = str(raw_entry.dominant_ability)
			if _is_bounded_string(raw_entry.get("role"), 64):
				normalized[character_id]["role"] = str(raw_entry.get("role"))
			if _is_bounded_string(raw_entry.get("background"), 512):
				normalized[character_id]["background"] = str(raw_entry.get("background"))
			if _is_bounded_string(raw_entry.get("origin"), 128):
				normalized[character_id]["origin"] = str(raw_entry.get("origin"))
			if _is_bounded_string(raw_entry.get("introduced_by"), 64):
				normalized[character_id]["introduced_by"] = str(raw_entry.get("introduced_by"))
			if _is_bounded_string(raw_entry.get("public_goal"), 256):
				normalized[character_id]["public_goal"] = str(raw_entry.get("public_goal"))
			if _is_bounded_string(raw_entry.get("hidden_goal"), 256):
				normalized[character_id]["hidden_goal"] = str(raw_entry.get("hidden_goal"))
			normalized[character_id]["summonable"] = bool(raw_entry.get("summonable", false))

			var raw_stats = raw_entry.get("stats", {})
			if raw_stats is Dictionary:
				var stats: Dictionary = {}
				for field_id in ["military", "governance", "finance", "intrigue", "diplomacy", "prowess", "medicine", "scholarship"]:
					if raw_stats.has(field_id):
						stats[field_id] = raw_stats[field_id] if campaign_id=="anshi_beta_1_14" and field_id in ["finance","governance","diplomacy"] else clampi(int(raw_stats.get(field_id, 50)), 0, 100)
				normalized[character_id]["stats"] = stats

			var raw_traits = raw_entry.get("tang_traits", [])
			if raw_traits is Array:
				var traits: Array = []
				for t in raw_traits:
					if _is_bounded_string(t, 64) and not traits.has(str(t)):
						traits.append(str(t))
				normalized[character_id]["tang_traits"] = traits

			var raw_allegiance = raw_entry.get("allegiance", {})
			if raw_allegiance is Dictionary:
				normalized[character_id]["allegiance"] = {
					"target_id": str(raw_allegiance.get("target_id", "")),
					"kind": str(raw_allegiance.get("kind", "retainer")),
					"day": int(raw_allegiance.get("day", 0))
				}
	return normalized

func _normalize_character_fate_refs(value: Variant, character_id: String, campaign_id: String = "") -> Array:
	if campaign_id != "anshi_beta_1_10":
		return _normalize_legacy_character_fate_refs(value)
	if not (value is Array):
		return []
	var normalized: Array = []
	var seen: Dictionary = {}
	for raw_ref in value:
		if not (raw_ref is Dictionary):
			continue
		var record := _normalize_character_fate_ref(raw_ref as Dictionary, character_id)
		if record.is_empty():
			continue
		var identity := str(record.get("id", "")) + "|" + str(record.get("character_id", "")) + "|" + str(record.get("arc_id", ""))
		if seen.has(identity):
			continue
		seen[identity] = true
		normalized.append(record)
	normalized.sort_custom(Callable(self, "_sort_character_fate_refs"))
	if normalized.size() > 5:
		normalized = normalized.slice(normalized.size() - 5, normalized.size())
	return normalized

func _normalize_legacy_character_fate_refs(value: Variant) -> Array:
	if not (value is Array):
		return []
	var normalized: Array = []
	for raw_ref in value:
		if not raw_ref is Dictionary:
			continue
		var raw_record: Dictionary = raw_ref
		var kind := str(raw_record.get("kind", ""))
		var ref_id: Variant = raw_record.get("id", null)
		if not ["character_fate", "transaction"].has(kind) or not _is_bounded_string(ref_id, 128):
			continue
		var record := {"kind": kind, "id": str(ref_id)}
		if kind == "character_fate":
			if not _is_bounded_string(raw_record.get("arc_id", null), 128):
				continue
			if not _is_integral_finite_number(raw_record.get("day", null)) or int(raw_record.get("day", 0)) < 0 or int(raw_record.get("day", 0)) > 90:
				continue
			record["arc_id"] = str(raw_record.get("arc_id", ""))
			record["day"] = int(raw_record.get("day", 0))
		elif kind == "transaction":
			if not _is_bounded_string(raw_record.get("office_id", null), 128):
				continue
			record["office_id"] = str(raw_record.get("office_id", ""))
		normalized.append(record)
	return normalized

func _normalize_character_fate_ref(raw_ref: Dictionary, character_id: String) -> Dictionary:
	if str(raw_ref.get("kind", "")) != "character_fate":
		return {}
	var raw_character_id: Variant = raw_ref.get("character_id", null)
	var raw_arc_id: Variant = raw_ref.get("arc_id", null)
	if not _is_bounded_string(raw_character_id, 64) or str(raw_character_id) != character_id:
		return {}
	if not _is_bounded_string(raw_arc_id, 128):
		return {}
	var arc_id := str(raw_arc_id)
	var expected_id := "fate|%s|%s" % [character_id, arc_id]
	if str(raw_ref.get("id", "")) != expected_id:
		return {}
	if not _is_integral_finite_number(raw_ref.get("day", null)) or int(raw_ref.get("day", 0)) < 1 or int(raw_ref.get("day", 0)) > 90:
		return {}
	for key in ["result_fate_status", "public_label", "primary_public_reason"]:
		if not _is_bounded_string(raw_ref.get(key, null), 512):
			return {}
	var category := str(raw_ref.get("aftermath_category", ""))
	if not ["gained_position", "constrained", "paid_cost"].has(category):
		return {}
	var raw_reason_refs: Variant = raw_ref.get("reason_refs", null)
	if not raw_reason_refs is Array or (raw_reason_refs as Array).is_empty() or (raw_reason_refs as Array).size() > 8:
		return {}
	var reason_refs: Array = []
	var reason_seen: Dictionary = {}
	for raw_reason_ref in raw_reason_refs as Array:
		if not raw_reason_ref is Dictionary:
			return {}
		var reason_ref: Dictionary = raw_reason_ref
		var reason_kind := str(reason_ref.get("kind", ""))
		var reason_id := str(reason_ref.get("id", ""))
		if not ["route", "case", "office", "review", "chronicle"].has(reason_kind) or not _is_bounded_string(reason_id, 128):
			return {}
		var reason_identity := reason_kind + "|" + reason_id
		if reason_seen.has(reason_identity):
			continue
		reason_seen[reason_identity] = true
		reason_refs.append({"kind": reason_kind, "id": reason_id})
	return {
		"kind": "character_fate",
		"id": expected_id,
		"character_id": character_id,
		"arc_id": arc_id,
		"day": int(raw_ref.get("day", 0)),
		"result_fate_status": str(raw_ref.get("result_fate_status", "")),
		"public_label": str(raw_ref.get("public_label", "")),
		"aftermath_category": category,
		"primary_public_reason": str(raw_ref.get("primary_public_reason", "")),
		"reason_refs": reason_refs
	}

func _sort_character_fate_refs(left: Dictionary, right: Dictionary) -> bool:
	var left_day := int(left.get("day", 0))
	var right_day := int(right.get("day", 0))
	if left_day != right_day:
		return left_day < right_day
	return str(left.get("id", "")) < str(right.get("id", ""))

func _normalize_record_map(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var normalized: Dictionary = {}
	for raw_key in value.keys():
		var key := str(raw_key)
		if key.is_empty() or key.length() > 128 or not value[raw_key] is Dictionary:
			continue
		normalized[key] = (value[raw_key] as Dictionary).duplicate(true)
	return normalized

func _normalize_pending_requests(value: Variant, campaign_id: String = "") -> Array:
	if not (value is Array):
		return []
	var normalized: Array = []
	for raw_request in value:
		if not (raw_request is Dictionary):
			continue
		var request: Dictionary = raw_request.duplicate(true)
		# Older saves never had a proposal field.  Normalizing it here makes the
		# free-talk path explicit without inventing a result or contacting an AI.
		if not (request.get("talk_proposal", {}) is Dictionary):
			request["talk_proposal"] = {}
		if campaign_id in ["anshi_beta_1_09", "anshi_beta_1_10"] and str(request.get("source_campaign_id", "")).strip_edges().is_empty():
			var legacy_scope := str(request.get("test_scope", "")).strip_edges()
			if legacy_scope in ["anshi_beta_1_09", "anshi_beta_1_10"]:
				request["source_campaign_id"] = legacy_scope
			elif legacy_scope.is_empty() and _is_authoritative_routine_request(request):
				request["source_campaign_id"] = campaign_id
		normalized.append(request)
	return normalized

func _is_authoritative_routine_request(request: Dictionary) -> bool:
	var request_id := str(request.get("request_id", "")).strip_edges()
	var status := str(request.get("status", "")).strip_edges()
	return (
		request_id.begins_with("routine__")
		and not str(request.get("title", "")).strip_edges().is_empty()
		and not str(request.get("summary", "")).strip_edges().is_empty()
		and status in ["pending", "delegated", "personal_talk_pending"]
	)

func _is_bounded_string(value: Variant, max_length: int, allow_empty: bool = false) -> bool:
	if typeof(value) != TYPE_STRING or str(value).length() > max_length:
		return false
	return allow_empty or str(value).strip_edges() != ""

func _is_integral_finite_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT or not is_finite(float(value)):
		return false
	return is_equal_approx(float(value), round(float(value)))

func _normalize_current_date(value: Variant) -> Dictionary:
	var normalized := _default_current_date()
	if value is Dictionary:
		var source: Dictionary = value
		normalized["era"] = str(source.get("era", normalized["era"]))
		normalized["year"] = maxi(int(source.get("year", normalized["year"])), 1)
		normalized["month"] = clampi(int(source.get("month", normalized["month"])), 1, 12)
		normalized["day"] = clampi(int(source.get("day", normalized["day"])), 1, 31)
	return normalized

func _default_auto_pause_preferences() -> Dictionary:
	return {
		"audience": true,
		"promise": true,
		"war": true,
		"diplomacy": true,
		"intelligence": true,
		"npc_action": true,
		"task_blocked": true
	}

func _normalize_auto_pause_preferences(value: Variant) -> Dictionary:
	var normalized := _default_auto_pause_preferences()
	if value is Dictionary:
		var source: Dictionary = value
		for key in normalized.keys():
			if source.has(key):
				normalized[key] = bool(source.get(key, normalized[key]))
	return normalized

func _legacy_minutes_to_day(legacy_minutes: int) -> int:
	return maxi(floori(float(legacy_minutes) / 20.0), 0)

func _normalize_current_day(value: Variant) -> int:
	return maxi(int(value), 0)

func _normalize_time_speed(value: Variant) -> int:
	return clampi(int(value), 1, 3)

func _should_migrate_legacy_minutes(data: Dictionary) -> bool:
	if data.has("current_day") or not data.has("current_time_minutes"):
		return false
	if not data.has("save_version"):
		return true
	return int(data.get("save_version", SAVE_VERSION)) < SAVE_VERSION

func _default_beta_0_9_dialogue_state() -> Dictionary:
	return {
		"selected_map_context": {},
		"pending_political_object": {},
		"last_return_to_map_context": {}
	}
