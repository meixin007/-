extends RefCounted

class_name DailySettlementCoordinator

const GameStateScript = preload("res://scripts/core/game_state.gd")
const StrategicTimeServiceScript = preload("res://scripts/core/strategic_time_service.gd")
const GovernanceOrderServiceScript = preload("res://scripts/core/governance_order_service.gd")
const GovernanceReportServiceScript = preload("res://scripts/core/governance_report_service.gd")
const GovernanceMemorialServiceScript = preload("res://scripts/core/governance_memorial_service.gd")
const CharacterArcServiceScript = preload("res://scripts/core/character_arc_service.gd")
const PoliticalSeasonSettlementServiceScript = preload("res://scripts/core/political_season_settlement_service.gd")
const PoliticalSeasonReviewServiceScript = preload("res://scripts/core/political_season_review_service.gd")
const PhaseEndingEvaluatorScript = preload("res://scripts/core/phase_ending_evaluator.gd")

const STEP_ORDER: Array[String] = [
	"activate_events",
	"expire_events",
	"settle_tasks",
	"expire_memorials",
	"activate_memorials",
	"settle_governance_orders",
	"routine_requests",
	"promises",
	"propagation",
	"reactions",
	"npc_actions",
	"npc_interactions",
	"political_chains",
	"deliver_reports",
	"settle_office_performance",
	"settle_accountability_cases",
	"character_arcs",
	"phase_checkpoint"
]

const LEGACY_ALIASES := {
	"activate_events": "activate",
	"expire_events": "expire",
	"settle_tasks": "tasks",
	"settle_governance_orders": "governance_orders"
}

func settle_day(context, steps: Dictionary = {}) -> Dictionary:
	var context_validation := _validate_context(context)
	if not bool(context_validation.get("ok", false)):
		return context_validation
	var steps_validation := _validate_steps(steps)
	if not bool(steps_validation.get("ok", false)):
		return steps_validation
	var original_state = context.state
	var snapshot_value: Variant = original_state.to_dictionary()
	if not (snapshot_value is Dictionary):
		return _fail("state to_dictionary must return a Dictionary")
	var working_state = GameStateScript.new()
	working_state.load_dictionary((snapshot_value as Dictionary).duplicate(true))
	var working_context: Dictionary = context.with_state(working_state)
	if not bool(working_context.get("ok", false)):
		return _fail(str(working_context.get("error", "working context creation failed")))
	var execution: Dictionary = {"current_step": ""}
	var settlement_steps: Array = []
	for step_name in STEP_ORDER:
		settlement_steps.append(Callable(self, "_run_step").bind(step_name, steps, execution, working_context.get("context")))
	var advance_result: Dictionary = StrategicTimeServiceScript.new().advance_one_day(working_state, settlement_steps)
	if not bool(advance_result.get("ok", false)):
		var failure := {
			"ok": false,
			"code": str(advance_result.get("code", "daily_settlement_failed")),
			"step": str(execution.get("current_step", "advance")),
			"error": str(advance_result.get("error", "daily settlement failed")),
			"message": str(advance_result.get("error", "daily settlement failed"))
		}
		for key in ["reason_code", "blocking_review_id", "route_required", "next_step"]:
			if advance_result.has(key):
				failure[key] = advance_result.get(key)
		return failure
	if int(working_state.state_revision) == int(original_state.state_revision):
		working_state.state_revision = int(original_state.state_revision) + 1
	var final_validation: Dictionary = working_state.try_load_dictionary(working_state.to_dictionary())
	if not final_validation.get("ok", false):
		return _fail(str(final_validation.get("error", "daily state failed validation")))
	var replacement: Dictionary = context.replace_state(working_state, false)
	if not bool(replacement.get("ok", false)):
		return _fail(str(replacement.get("error", "runtime context replacement failed")))
	if context.has_method("_note_fully_validated_state"): context._note_fully_validated_state()
	return {"ok": true, "steps": STEP_ORDER.duplicate(), "current_day": int(working_state.current_day)}

func _run_step(working_state, step_name: String, steps: Dictionary, execution: Dictionary, working_context) -> Dictionary:
	execution["current_step"] = step_name
	var callback_name := step_name
	if not steps.has(callback_name) and LEGACY_ALIASES.has(step_name):
		callback_name = str(LEGACY_ALIASES.get(step_name, step_name))
	if step_name == "activate_events":
		var estate: Dictionary = preload("res://scripts/core/personal_estate_service.gd").settle_daily(working_state, working_context.scenario_data)
		if not estate.get("ok", false): return estate
	if step_name == "settle_tasks":
		var legacy_transport: Dictionary = preload("res://scripts/core/logistics_service.gd").new().settle_daily_transports(working_state)
		if not legacy_transport.ok:
			execution["current_step"] = "grain_transports"
			return legacy_transport
		var profit_distribution: Dictionary=preload("res://scripts/core/business_profit_sharing_service.gd").settle_daily(working_state)
		if not profit_distribution.ok:return profit_distribution
		# Close the previous month's books before today's authorized trading consumes staff time.
		var business_reports: Dictionary = preload("res://scripts/core/business_report_delivery.gd").settle_daily(working_state)
		if not business_reports.get("ok",false): return business_reports
	if step_name == "npc_actions":
		var visit: Dictionary = preload("res://scripts/core/regional_visit_service.gd").settle(working_state)
		if not visit.ok: return visit
		var gifts: Dictionary = preload("res://scripts/core/gift_delivery_service.gd").settle(working_state, working_context.scenario_data)
		if not gifts.ok: return gifts
		var military_grain: Dictionary = preload("res://scripts/core/military_grain_service.gd").settle_daily(working_state)
		if not military_grain.get("ok", false): return military_grain
		var grain: Dictionary = preload("res://scripts/core/regional_grain_service.gd").settle_daily(working_state)
		if not grain.get("ok", false): return grain
		var envoy: Dictionary = preload("res://scripts/core/official_journey_service.gd").settle_daily(working_state)
		if not envoy.get("ok", false): return envoy
		var journey: Dictionary = preload("res://scripts/core/exam_journey_service.gd").settle_daily(working_state)
		if not journey.get("ok", false): return journey
		var central: Dictionary = preload("res://scripts/core/central_examination_service.gd").settle_daily(working_state, working_context.scenario_data)
		if not central.get("ok", false): return central
		var assessment: Dictionary = preload("res://scripts/core/school_assessment_service.gd").settle_daily(working_state)
		if not assessment.get("ok", false): return assessment
		var school_supply: Dictionary = preload("res://scripts/core/school_supply_service.gd").settle_daily(working_state)
		if not school_supply.get("ok", false): return school_supply
		var education: Dictionary = preload("res://scripts/core/education_service.gd").settle_daily(working_state)
		if not education.get("ok", false): return education
		var crops: Dictionary = preload("res://scripts/core/farmland_service.gd").settle_daily(working_state)
		if not crops.get("ok", false): return crops
	if step_name == "npc_actions" and working_context != null and working_context.scenario_data.get("campaign_id") == "anshi_beta_1_14":
		# Run livelihood in the ORIGINAL daily working context before a scene's
		# optional NPC presentation callback. Its later legacy update sees the
		# ordinary day cursor and cannot choose or consume a second time.
		var livelihood: Dictionary = preload("res://scripts/core/character_agenda_service.gd").new().update_livelihood(working_state, working_context.scenario_data, working_context)
		if not livelihood.ok: return livelihood
	var step: Callable = steps.get(callback_name, Callable())
	var result: Variant = _default_step(working_context, step_name) if not step.is_valid() else step.call(working_state)
	if not (result is Dictionary) or not result.has("ok") or typeof(result.get("ok")) != TYPE_BOOL:
		return {"ok": false, "error": "%s step must return a Dictionary with explicit boolean ok" % step_name}
	if result.get("ok",false) and step_name == "deliver_reports":
		var control_observation: Dictionary = preload("res://scripts/core/node_control_observation.gd").observe_local(working_state)
		if not control_observation.ok: return control_observation
		var office_observation: Dictionary = preload("res://scripts/core/regional_office_knowledge.gd").observe_local(working_state)
		if not office_observation.ok: return office_observation
	if result.get("ok", false) and step_name == "settle_office_performance":
		var wages: Dictionary = preload("res://scripts/core/family_office_rules.gd").settle_daily(working_state)
		var regional_wages: Dictionary = preload("res://scripts/core/regional_office_rules.gd").settle_daily(working_state)
		if not regional_wages.get("ok", false): return regional_wages
		if not wages.get("ok", false):
			return wages
		var business: Dictionary = preload("res://scripts/core/pawnshop_service.gd").settle_daily(working_state)
		if not business.get("ok", false):
			return business
		var construction: Dictionary = preload("res://scripts/core/estate_construction_service.gd").settle_daily(working_state)
		if not construction.get("ok",false): return construction
		var improvements: Dictionary=preload("res://scripts/core/estate_lifecycle_service.gd").settle_daily(working_state)
		if not improvements.ok:return improvements
		var public_works: Dictionary = preload("res://scripts/core/public_works_service.gd").settle_daily(working_state)
		if not public_works.get("ok", false): return public_works
		var production: Dictionary = preload("res://scripts/core/production_service.gd").settle_daily(working_state)
		if not production.get("ok", false): return production
		var local_fiscal: Dictionary = preload("res://scripts/core/local_fiscal_policy_service.gd").settle_daily(working_state, working_context.scenario_data)
		if not local_fiscal.get("ok", false): return local_fiscal
		var marriage: Dictionary = preload("res://scripts/core/marriage_service.gd").settle_daily(working_state, working_context.scenario_data)
		if not marriage.get("ok", false): return marriage
		var initiative: Dictionary = preload("res://scripts/core/official_initiative_service.gd").settle_daily(working_state, working_context.scenario_data)
		if not initiative.get("ok", false): return initiative
		var fiscal: Dictionary = preload("res://scripts/core/regional_fiscal_service.gd").settle_daily(working_state)
		if not fiscal.get("ok", false): return fiscal
		var searches: Dictionary = preload("res://scripts/core/character_search_service.gd").settle_daily(working_state)
		if not searches.get("ok", false): return searches
		var binding: Dictionary = preload("res://scripts/core/player_assistant_service.gd").reconcile(working_state, working_context.scenario_data)
		if not binding.get("ok", false): return binding
		return preload("res://scripts/core/assistant_advice_service.gd").update(working_state, working_context.scenario_data)
	return result

func _default_step(working_context, step_name: String) -> Dictionary:
	if step_name == "propagation":
		var propagated: Dictionary = preload("res://scripts/core/information_propagation_service.gd").new().settle(working_context.state)
		if not propagated.ok: return propagated
		return preload("res://scripts/core/npc_social_reaction_service.gd").new().settle(working_context.state, working_context.scenario_data)
	if working_context == null:
		return {"ok": true}
	if step_name == "settle_tasks":
		var task_queue = preload("res://scripts/core/task_queue.gd").new()
		var rules = preload("res://scripts/core/rule_engine.gd").new()
		var event_q = preload("res://scripts/core/event_queue.gd").new()
		var decisions: Array = working_context.scenario_data.get("decisions", []) if working_context.scenario_data is Dictionary else []
		return task_queue.update_tasks(working_context.state, rules, decisions, event_q, working_context.scenario_data)
	if step_name == "npc_actions" and working_context.scenario_data.get("campaign_id") == "anshi_beta_1_14":
		var relevance: Dictionary = preload("res://scripts/core/npc_relevance_service.gd").new().update(working_context.state)
		if not relevance.ok: return relevance
		return preload("res://scripts/core/npc_active_action_system.gd").new().update(working_context.state, working_context.scenario_data.get("characters", []), preload("res://scripts/core/event_queue.gd").new(), working_context.scenario_data)
	if step_name == "settle_governance_orders":
		var order_service: Variant = working_context.services.get("governance_order_service")
		if order_service == null:
			order_service = GovernanceOrderServiceScript.new()
		return order_service.settle_daily(working_context.state, working_context.scenario_data.get("governance", {}))
	if step_name == "expire_memorials":
		return GovernanceMemorialServiceScript.new().settle_deadlines(working_context.state, working_context.scenario_data.get("governance", {}))
	if step_name == "activate_memorials":
		return GovernanceMemorialServiceScript.new().activate_followups(working_context.state, working_context.scenario_data.get("governance", {}))
	if step_name == "deliver_reports":
		var report_service: Variant = working_context.services.get("governance_report_service")
		if report_service == null:
			report_service = GovernanceReportServiceScript.new()
		return report_service.deliver_due(working_context.state, working_context.scenario_data.get("governance", {}))
	if step_name == "political_chains":
		var season_service: Variant = working_context.services.get("political_season_settlement_service")
		if season_service == null:
			season_service = PoliticalSeasonSettlementServiceScript.new()
		var season_result: Dictionary = season_service.settle_daily(working_context.state, working_context.scenario_data, int(working_context.state.current_day))
		if not bool(season_result.get("ok", false)):
			return season_result
		if str(working_context.scenario_data.get("campaign_id", "")) in ["anshi_beta_1_09", "anshi_beta_1_10"]:
			var followup_result: Dictionary = GovernanceMemorialServiceScript.new().activate_followups(working_context.state, working_context.scenario_data.get("governance", {}))
			if not bool(followup_result.get("ok", false)):
				return followup_result
			season_result["activated_memorial_ids"] = (followup_result.get("activated_memorial_ids", []) as Array).duplicate(true)
		var review_service: Variant = working_context.services.get("political_season_review_service")
		if review_service == null:
			review_service = PoliticalSeasonReviewServiceScript.new()
		var review_result: Dictionary = review_service.settle_daily(working_context.state, working_context.scenario_data, int(working_context.state.current_day))
		if not bool(review_result.get("ok", false)):
			return review_result
		season_result["created_review_report_ids"] = (review_result.get("created_report_ids", []) as Array).duplicate(true)
		return season_result
	if step_name == "settle_office_performance":
		var office_service: Variant = working_context.services.get("office_service")
		if office_service == null:
			return {"ok": true, "code": "no_op", "effects": [], "refs": []}
		return office_service.settle_daily_performance(working_context.state, working_context.scenario_data, int(working_context.state.current_day))
	if step_name == "settle_accountability_cases":
		var case_service: Variant = working_context.services.get("accountability_case_service")
		if case_service == null:
			return {"ok": true, "code": "no_op", "effects": [], "refs": []}
		return case_service.settle_daily(working_context.state, working_context.scenario_data, int(working_context.state.current_day))
	if step_name == "character_arcs":
		return CharacterArcServiceScript.new().settle_daily(working_context.state, working_context.scenario_data, int(working_context.state.current_day))
	if step_name == "phase_checkpoint":
		var checkpoint_result: Dictionary = PhaseEndingEvaluatorScript.new().evaluate(working_context.state)
		if bool(checkpoint_result.get("ok", false)):
			return checkpoint_result
		var checkpoint_error := str(checkpoint_result.get("error", ""))
		if checkpoint_error in ["phase_not_due", "phase_window_closed"]:
			return {"ok": true, "code": "no_op"}
		return checkpoint_result
	return {"ok": true}

func _validate_context(context) -> Dictionary:
	if context == null or not context.has_method("with_state") or not context.has_method("replace_state"):
		return _fail("runtime context must support state replacement")
	if context.state == null or not context.state.has_method("to_dictionary") or not context.state.has_method("load_dictionary"):
		return _fail("runtime context state must support serialization")
	return {"ok": true}

func _validate_steps(steps: Dictionary) -> Dictionary:
	for step_name in steps.keys():
		if not STEP_ORDER.has(str(step_name)) and not LEGACY_ALIASES.values().has(str(step_name)):
			return _fail("unknown daily settlement step: %s" % str(step_name))
		var step: Variant = steps.get(step_name)
		if not (step is Callable) or not (step as Callable).is_valid():
			return _fail("daily settlement step must be a valid Callable: %s" % str(step_name))
	return {"ok": true}

func _fail(message: String) -> Dictionary:
	return {"ok": false, "code": "daily_settlement_error", "error": message, "message": message}
