extends RefCounted

class_name GameRuntimeContext

const ScenarioDataScript = preload("res://scripts/domain/scenario_data.gd")
const GameStateScript = preload("res://scripts/core/game_state.gd")
const EventQueueScript = preload("res://scripts/core/event_queue.gd")
const RuleEngineScript = preload("res://scripts/core/rule_engine.gd")
const SaveManagerScript = preload("res://scripts/core/save_manager.gd")
const TimeControllerScript = preload("res://scripts/core/time_controller.gd")
const CourtWorkbenchRouterScript = preload("res://scripts/core/court_workbench_router.gd")
const MapConversationRouterScript = preload("res://scripts/core/map_conversation_router.gd")
const ImportantEventProjectionScript = preload("res://scripts/core/important_event_projection.gd")
const GovernanceWorkflowCoordinatorScript = preload("res://scripts/core/governance_workflow_coordinator.gd")
const GovernanceOrderResolverScript = preload("res://scripts/core/governance_order_resolver.gd")
const GovernanceOrderServiceScript = preload("res://scripts/core/governance_order_service.gd")
const GovernanceReportServiceScript = preload("res://scripts/core/governance_report_service.gd")
const GovernanceMemorialServiceScript = preload("res://scripts/core/governance_memorial_service.gd")
const OfficeServiceScript = preload("res://scripts/core/office_service.gd")
const AccountabilityCaseServiceScript = preload("res://scripts/core/accountability_case_service.gd")
const AccountabilityWorkflowCoordinatorScript = preload("res://scripts/core/accountability_workflow_coordinator.gd")
const DailySettlementCoordinatorScript = preload("res://scripts/core/daily_settlement_coordinator.gd")
const PoliticalSeasonSettlementServiceScript = preload("res://scripts/core/political_season_settlement_service.gd")
const PoliticalSeasonReviewServiceScript = preload("res://scripts/core/political_season_review_service.gd")
const PoliticalSeasonRouteServiceScript = preload("res://scripts/core/political_season_route_service.gd")
const PoliticalSeasonProgressionGuardScript = preload("res://scripts/core/political_season_progression_guard.gd")
const TangCharacterTraitServiceScript = preload("res://scripts/core/tang_character_trait_service.gd")
const EmperorStressServiceScript = preload("res://scripts/core/emperor_stress_service.gd")
const CurrentCampaignScript = preload("res://scripts/domain/current_campaign.gd")

var scenario_data: Dictionary = {}
var state = null
var services: Dictionary = {}
static var _epoch_sequence: int = 0
var world_epoch: String = ""
var world_generation: int = 0
var restored_world: bool = false
var _sealed_scenario_data: Dictionary = {}
var _track_background_validation: bool = false
var _validated_native_state: PackedByteArray = PackedByteArray()
var _validated_state_owner: WeakRef
var _validated_definition: Dictionary = {}
var _validated_world_epoch := ""
var _validated_world_generation := -1
var _native_guard_seals: Dictionary = {}
var _native_history_seals: Dictionary = {}
var _track_native_history: bool = false

func _init(assign_world_identity: bool = true) -> void:
	if not assign_world_identity: return
	_epoch_sequence += 1
	world_generation = _epoch_sequence
	world_epoch = "world:%s:%s" % [Time.get_ticks_usec(), _epoch_sequence]

static func create_new(manifest_path: String, start_profile_id: String = "", seed_appearance: bool = true) -> Dictionary:
	var scenario_result: Dictionary = ScenarioDataScript.new().load_campaign(manifest_path)
	if not scenario_result.get("ok", false):
		return _fail(str(scenario_result.get("error", "campaign load failed")))
	var context = load("res://scripts/core/game_runtime_context.gd").new()
	var prepared: Dictionary = preload("res://scripts/core/start_profile_service.gd").prepare(scenario_result.get("data", {}), start_profile_id)
	if not prepared.get("ok", false):
		return prepared
	context.scenario_data = prepared.data
	context.state = GameStateScript.new()
	context.state.initialize_from_data(context.scenario_data)
	if seed_appearance and str(context.scenario_data.get("campaign_id", "")) == CurrentCampaignScript.CAMPAIGN_ID:
		var appearance_seed: Dictionary = preload("res://scripts/core/character_appearance_contract.gd").seed_new_game(context.state,context.scenario_data)
		if not appearance_seed.ok: return appearance_seed
	var profile_seed: Dictionary = preload("res://scripts/core/start_profile_service.gd").initialize(context.state, context.scenario_data)
	if not profile_seed.get("ok", false):
		return profile_seed
	if str(context.scenario_data.get("campaign_id", "")) == CurrentCampaignScript.CAMPAIGN_ID:
		var map_seed: Dictionary = preload("res://scripts/core/liang_map_definition_bootstrap.gd").apply(context.state, true)
		if not map_seed.get("ok", false):
			return _fail(str(map_seed.get("error", "map definition bootstrap failed")))
	if str(context.scenario_data.get("campaign_id", "")) == CurrentCampaignScript.CAMPAIGN_ID:
		var weather_seed: Dictionary = preload("res://scripts/domain/river_weather_events.gd").seed_new_campaign(context.state)
		if not weather_seed.get("ok", false):return _fail(str(weather_seed.get("error", "weather seed failed")))
		var road_weather_seed: Dictionary = preload("res://scripts/domain/road_surface_conditions.gd").seed_new_campaign(context.state)
		if not road_weather_seed.get("ok", false):return _fail(str(road_weather_seed.get("error", "road weather seed failed")))
	context.state.flags["campaign_id"] = str(context.scenario_data.get("campaign_id", ""))
	context.state.flags["campaign_days"] = int(context.scenario_data.get("campaign_days", 0))
	context.services = context._build_services()
	var control_observation: Dictionary = preload("res://scripts/core/node_control_observation.gd").observe_local(context.state)
	if not control_observation.ok: return control_observation
	preload("res://scripts/core/regional_office_knowledge.gd").seed(context.state)
	var criminal_seed: Dictionary = preload("res://scripts/core/criminal_case_service.gd").initialize(context.state, context.scenario_data)
	if not criminal_seed.ok: return criminal_seed
	var campaign_id := str(context.scenario_data.get("campaign_id", ""))
	if campaign_id in ["anshi_beta_1_08", "anshi_beta_1_09", "anshi_beta_1_10"]:
		var office_seed: Dictionary = context.services.get("office_service").seed_initial_terms(context.state, context.scenario_data)
		if not bool(office_seed.get("ok", false)):
			return _fail(str(office_seed.get("error", "derived campaign office bootstrap failed")))
		var case_seed: Dictionary = context.services.get("accountability_case_service").seed_cases(context.state, context.scenario_data)
		if not bool(case_seed.get("ok", false)):
			return _fail(str(case_seed.get("error", "derived campaign case bootstrap failed")))
		var next_flags: Dictionary = context.state.flags.duplicate(true)
		next_flags.erase("beta108_initialized")
		next_flags.erase("beta109_initialized")
		next_flags.erase("beta110_initialized")
		var flag_prefix := "beta108" if campaign_id == "anshi_beta_1_08" else ("beta109" if campaign_id == "anshi_beta_1_09" else "beta110")
		next_flags["%s_initialized" % flag_prefix] = true
		context.state.flags = next_flags
		var bootstrap_validation: Dictionary = context.state.try_load_dictionary(context.state.to_dictionary().duplicate(true))
		if not bool(bootstrap_validation.get("ok", false)):
			return _fail(str(bootstrap_validation.get("error", "derived campaign bootstrap validation failed")))
	return {"ok": true, "context": context}

static func create_current(start_profile_id: String = "") -> Dictionary:
	var created: Dictionary = create_new(CurrentCampaignScript.MANIFEST_PATH, start_profile_id)
	if not bool(created.get("ok", false)):
		return created
	var context = created.get("context")
	var paused: Dictionary = context.services.get("time_controller").pause(context.state, "campaign_intro")
	if not bool(paused.get("ok", false)):
		return _fail(str(paused.get("error", "current campaign intro pause failed")))
	return created

static func create_from_snapshot(snapshot: Dictionary, manifest_path: String = CurrentCampaignScript.MANIFEST_PATH) -> Dictionary:
	if not (snapshot is Dictionary):
		return _fail("runtime context snapshot is invalid")
	var snapshot_flags: Variant = snapshot.get("flags", {})
	if not snapshot_flags is Dictionary:
		return _fail("snapshot flags are invalid")
	# Restore consumes persisted envelopes, including explicit absence in legacy
	# saves. Do not even create throwaway founder genomes on the load path.
	var created: Dictionary = create_new(manifest_path, str(snapshot_flags.get("start_profile_id", "")), false)
	if not bool(created.get("ok", false)):
		return created
	var context = created.get("context")
	var loaded: Dictionary = context.state.try_load_dictionary(snapshot.duplicate(true))
	if not bool(loaded.get("ok", false)):
		return _fail(str(loaded.get("error", "runtime context snapshot failed validation")))
	context.sync_scenario_player_identity()
	preload("res://scripts/core/npc_ai_state_contract.gd").cancel_pending(context.state)
	context.restored_world = true
	return {"ok": true, "context": context}

func replace_state(replacement, new_world: bool = true) -> Dictionary:
	if replacement == null or not replacement.has_method("to_dictionary") or not replacement.has_method("load_dictionary"):
		return _fail("runtime context replacement state is invalid")
	state = replacement
	if new_world:
		_epoch_sequence += 1
		world_generation = _epoch_sequence
		restored_world = true
		world_epoch = "world:%s:%s" % [Time.get_ticks_usec(), _epoch_sequence]
		preload("res://scripts/core/npc_ai_state_contract.gd").cancel_pending(state)
	sync_scenario_player_identity()
	return {"ok": true}

func with_state(replacement) -> Dictionary:
	if replacement == null:
		return _fail("runtime context replacement state is null")
	var working = GameRuntimeContext.new(false)
	if has_sealed_scenario_data():
		working._accept_sealed_scenario_data(scenario_data)
	else:
		working.scenario_data = scenario_data.duplicate(true)
	working.state = replacement
	working.world_epoch = world_epoch
	working.world_generation = world_generation
	working.restored_world = restored_world
	working.services = working._build_services()
	return {
		"ok": true,
		"context": working
	}

# Sealing is performed on an owned copy by the background runner. Identity is
# a cheap proof that this exact recursively read-only definition is still used.
func has_sealed_scenario_data() -> bool:
	return is_same(scenario_data, _sealed_scenario_data) and scenario_data.is_read_only()

func _accept_sealed_scenario_data(owned_read_only: Dictionary) -> void:
	scenario_data = owned_read_only
	_sealed_scenario_data = owned_read_only

func sync_scenario_player_identity() -> void:
	if scenario_data.get("player_character_id") == state.player_character_id: return
	if has_sealed_scenario_data():
		var updated: Dictionary = scenario_data.duplicate(false)
		updated["player_character_id"] = state.player_character_id
		updated.make_read_only()
		_accept_sealed_scenario_data(updated)
	else:
		scenario_data["player_character_id"] = state.player_character_id

func _note_fully_validated_state() -> void:
	if _track_background_validation:
		_validated_native_state = preload("res://scripts/core/native_state_snapshot.gd").exact_bytes(state)
		_validated_state_owner = weakref(state)
		_validated_definition = scenario_data
		_validated_world_epoch = world_epoch
		_validated_world_generation = world_generation
	elif _track_native_history:
		# Invoked only immediately after the original complete validator and
		# publication. A main-thread command/day replacement installs fresh rows,
		# so renew their immutable ownership proof before another NPC capture.
		var native = preload("res://scripts/core/native_state_snapshot.gd")
		var fields: Dictionary = native.reference_view(state)
		native.freeze_publication_baselines(fields)
		native.freeze_publication_history(fields)
		_native_guard_seals = native.frozen_baselines(state)
		_native_history_seals = native.frozen_history_fields(fields)

func _can_reuse_validated_state() -> bool:
	if not _track_background_validation or not has_sealed_scenario_data() or _validated_native_state.is_empty(): return false
	if _validated_state_owner == null or _validated_state_owner.get_ref() != state or not is_same(_validated_definition, scenario_data): return false
	if _validated_world_epoch != world_epoch or _validated_world_generation != world_generation: return false
	# Revision alone is insufficient: every raw property must still match the
	# exact state just published after the complete domain validator.
	return preload("res://scripts/core/native_state_snapshot.gd").exact_bytes(state) == _validated_native_state

func _build_services() -> Dictionary:
	return {
		"character_birth_service": preload("res://scripts/core/character_birth_service.gd").new(),
		"character_portrait_service": preload("res://scripts/core/character_portrait_service.gd").new(),
		"character_style_service": preload("res://scripts/core/character_style_service.gd").new(),
		"resource_account_service": preload("res://scripts/core/resource_account_service.gd").new(),
		"npc_autonomy_coordinator": preload("res://scripts/core/npc_autonomy_coordinator.gd").new(),
		"npc_relevance_service": preload("res://scripts/core/npc_relevance_service.gd").new(),
		"npc_decision_service": preload("res://scripts/core/npc_decision_service.gd").new(),
		"player_assistant_service": preload("res://scripts/core/player_assistant_service.gd").new(),
		"event_queue": EventQueueScript.new(),
		"rule_engine": RuleEngineScript.new(),
		"save_manager": SaveManagerScript.new(),
		"time_controller": TimeControllerScript.new(),
		"court_workbench_router": CourtWorkbenchRouterScript.new(),
		"map_conversation_router": MapConversationRouterScript.new(),
		"important_event_projection": ImportantEventProjectionScript.new(),
		"governance_workflow_coordinator": GovernanceWorkflowCoordinatorScript.new(),
		"governance_order_resolver": GovernanceOrderResolverScript.new(),
		"governance_order_service": GovernanceOrderServiceScript.new(),
		"governance_report_service": GovernanceReportServiceScript.new(),
		"governance_memorial_service": GovernanceMemorialServiceScript.new(),
		"office_service": OfficeServiceScript.new(),
		"accountability_case_service": AccountabilityCaseServiceScript.new(),
		"accountability_workflow_coordinator": AccountabilityWorkflowCoordinatorScript.new(),
		"daily_settlement_coordinator": DailySettlementCoordinatorScript.new(),
		"political_season_settlement_service": PoliticalSeasonSettlementServiceScript.new(),
		"political_season_review_service": PoliticalSeasonReviewServiceScript.new(),
		"political_season_route_service": PoliticalSeasonRouteServiceScript.new(),
		"political_season_progression_guard": PoliticalSeasonProgressionGuardScript.new(),
		"tang_character_trait_service": TangCharacterTraitServiceScript.new(),
		"emperor_stress_service": EmperorStressServiceScript.new()
	}

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "code": "runtime_context_error", "error": message, "message": message}
