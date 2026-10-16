extends RefCounted

class_name NPCActiveActionSystem

const AutoPausePolicyScript = preload("res://scripts/core/auto_pause_policy.gd")
const RoutineRequestServiceScript = preload("res://scripts/core/routine_request_service.gd")
const UPDATE_INTERVAL_DAYS := 1
const FIRST_ACTION_DAY := 2
const FIRST_FATE_BARGAIN_DAY := 10
const BARGAIN_MIN_INTERVAL_DAYS := 10
const ACTION_COOLDOWN_DAYS := 10
const MAX_FATE_INITIATIVES_PER_UPDATE := 1
const CORE_NPC_IDS := [
	"guo_ziyi", "li_bi", "li_fuguo", "li_guangbi", "pugu_huaien", "li_chu",
	"uighur_envoy", "hardline_old_court_official", "grain_official_lingwu",
	"lingwu_merchant_refugee", "regional_jiedushi_rep", "eunuch_deputy_gate",
	"zhang_liangdi"
]

func get_capable_npc_ids(characters: Array) -> Array:
	var capable: Array = []
	for character_id in CORE_NPC_IDS:
		var character := _find_character(characters, character_id)
		var model: Dictionary = character.get("active_action_model", {})
		if not character.is_empty() and model.get("action_rules", []).size() >= 3:
			capable.append(character_id)
	return capable

func get_rule_input_sources() -> Dictionary:
	return {
		"registration_control_bypassed": "ConversationConsequenceService formal-authority object -> GameState.dialogue_action_records.object_id",
		"guo_formal_authority_promise": "ConversationConsequenceService -> GameState.obligation_ledger + structured_memories",
		"grain_audit_due": "EventQueue.activate_due_events -> GameState.active_events.available_decisions",
		"grain_account_report_due": "EventQueue.activate_due_events -> GameState.active_events.available_decisions",
		"grain_relief_needed": "GameState.resources.grain",
		"guo_supply_order_needed": "GameState.resources.grain + GameState.strategic_routes.support_shuofang",
		"guo_command_audience_needed": "StructuredMemoryService -> GameState.structured_memories",
		"li_fuguo_channel_risk": "StructuredMemoryService -> GameState.structured_memories",
		"political_chain_settlement": "PoliticalChainResolver -> GameState.flags.political_chain_states with occurrence provenance",
		"li_fuguo_memorial_risk": "GameState.character_states.relationships",
		"li_bi_faction_capture": "GameState.faction_states.pressure",
		"li_bi_sunset_clause_needed": "ObligationLedgerService -> GameState.obligation_ledger",
		"li_bi_intelligence_gap": "StructuredMemoryService -> GameState.structured_memories",
		"uighur_terms_unwritten": "GameState.strategic_routes.uighur_push",
		"uighur_private_channel_needed": "ObligationLedgerService -> GameState.obligation_ledger",
		"uighur_memorial_needed": "GameState.strategic_routes.uighur_push",
		"old_court_procedure_bypassed": "StructuredMemoryService -> GameState.structured_memories",
		"old_court_ritual_breach": "StructuredMemoryService -> GameState.structured_memories",
		"old_court_precedent_disputed": "ObligationLedgerService -> GameState.obligation_ledger",
		"li_guangbi_order_conflict": "GameState.battlefront_states.hedong_front.threat",
		"li_guangbi_supply_gap": "GameState.resources.grain",
		"li_guangbi_front_report_due": "ObligationLedgerService -> GameState.obligation_ledger",
		"zhang_household_security_threat": "GameState.character_states.relationships",
		"zhang_appointment_opening": "StructuredMemoryService -> GameState.structured_memories",
		"zhang_private_access_needed": "GameState.character_states.relationships",
		"baseline_shuofang_supply": "GameState.battlefront_states.shuofang_front supply and threat",
		"baseline_guanzhong_threat": "GameState.battlefront_states.guanzhong_front threat",
		"baseline_eunuch_pressure": "GameState.faction_states.eunuch_network pressure",
		"baseline_uighur_pressure": "GameState.faction_states.uighur_envoys pressure",
		"merchant_levy_pressure": "GameState.resources.grain + GameState.public_order",
		"merchant_market_complaint": "StructuredMemoryService -> GameState.structured_memories",
		"merchant_relief_plea": "GameState.resources.grain",
		"pugu_cavalry_supply_gap": "GameState.resources.grain + GameState.battlefront_states",
		"pugu_reward_due": "ObligationLedgerService -> GameState.obligation_ledger",
		"pugu_front_report_due": "GameState.battlefront_states",
		"li_chu_succession_risk": "GameState.character_states.relationships",
		"li_chu_private_counsel_needed": "StructuredMemoryService -> GameState.structured_memories",
		"li_chu_audience_needed": "GameState.faction_states.pressure",
		"regional_emergency_grain": "GameState.resources.grain",
		"regional_front_report_due": "GameState.battlefront_states",
		"regional_audience_needed": "GameState.faction_states.pressure",
		"gate_witness_report_due": "StructuredMemoryService -> GameState.structured_memories",
		"gate_amnesty_plea": "GameState.character_states.relationships",
		"gate_private_audience_needed": "GameState.faction_states.eunuch_network pressure",
		"baseline_old_court_pressure": "GameState.faction_states.old_court pressure"
	}

func update(state, characters: Array, event_queue, scenario_data: Dictionary = {}) -> Dictionary:
	if state == null:
		return {"ok": false, "error": "missing state", "updated": false, "actions": []}
	var livelihood: Dictionary = preload("res://scripts/core/character_agenda_service.gd").new().update_livelihood(state, scenario_data)
	if not livelihood.get("ok", false):
		return livelihood
	if int(state.current_day) < FIRST_ACTION_DAY:
		return {"ok": true, "updated": false, "actions": []}
	var last_update := int(state.flags.get("last_npc_action_update_day", 0))
	if int(state.current_day) - last_update < UPDATE_INTERVAL_DAYS:
		return {"ok": true, "updated": false, "actions": []}

	var actions: Array = []
	var fate_initiative_count := 0
	for character_id in CORE_NPC_IDS:
		# Settling obligations continues above; only the new choice is exclusive.
		if state.get("npc_ai_runtime") is Dictionary and state.npc_ai_runtime.get("actors", {}).get(character_id, {}).get("pending_request_id", "") != "": continue
		if _has_primary_demand_in_settlement(actions, character_id):
			continue
		var character := _find_character(characters, character_id)
		if character.is_empty():
			continue
		var action := _build_action(state, character, fate_initiative_count < MAX_FATE_INITIATIVES_PER_UPDATE)
		if action.is_empty():
			continue
		if bool(action.get("fate_initiative", false)):
			fate_initiative_count += 1
			state.set_flag("last_faction_bargain_day", int(state.current_day))
		state.record_npc_active_action(action)
		actions.append(action.duplicate(true))
		if _is_routine_request_action(action):
			# Legacy routine requests to pending_requests are discontinued per design overhaul.
			continue
		_enqueue_action_event(state, action, event_queue)
		_apply_significant_pause(state, action)
	state.set_flag("last_npc_action_update_day", int(state.current_day))
	return {"ok": true, "updated": true, "actions": actions.duplicate(true)}

func get_actionable_candidates(state, character: Dictionary) -> Array:
	if state == null:
		return []
	var model: Dictionary = character.get("active_action_model", {})
	if model.get("action_rules", []).size() < 3:
		return []
	var actor_id := str(character.get("id", ""))
	var candidates: Array = []
	var fate_initiative := _fate_initiative_candidate(state, character, model)
	if not fate_initiative.is_empty():
		candidates.append(fate_initiative)
	for raw_rule in model.get("action_rules", []):
		if not (raw_rule is Dictionary):
			continue
		var rule: Dictionary = raw_rule
		var evaluation := _evaluate_rule(state, character, model, rule)
		if not evaluation.get("ok", false):
			continue
		candidates.append({
			"action_type": str(rule.get("action_type", "")),
			"action_family": str(rule.get("action_family", rule.get("action_type", ""))),
			"score": int(evaluation.get("score", 0)),
			"severity": _severity_for_action(str(rule.get("action_type", ""))),
			"pause_category": _pause_category_for_action(str(rule.get("action_type", ""))),
			"target_ids": _target_ids_for_action(actor_id, str(rule.get("action_type", ""))),
			"selection_evidence": evaluation.get("evidence", {}).duplicate(true)
		})
	return candidates

func select_actionable_candidate(state, character: Dictionary, allow_fate_initiative: bool = true) -> Dictionary:
	var actor_id := str(character.get("id", ""))
	var available_candidates: Array = []
	for candidate in get_actionable_candidates(state, character):
		if bool(candidate.get("fate_initiative", false)) and not allow_fate_initiative:
			continue
		if not _is_action_family_on_cooldown(state, actor_id, str(candidate.get("action_family", ""))):
			available_candidates.append(candidate.duplicate(true))
	return _select_best_candidate(state, actor_id, available_candidates)

func _build_action(state, character: Dictionary, allow_fate_initiative: bool = true) -> Dictionary:
	var actor_id := str(character.get("id", ""))
	var selected := select_actionable_candidate(state, character, allow_fate_initiative)
	if selected.is_empty():
		return {}
	var action_type := str(selected.get("action_type", ""))
	var action_id := _next_action_id(state, actor_id, action_type)
	var character_name := _display_character_name(character)
	var reason_payload: Dictionary = selected.get("selection_evidence", {}).duplicate(true)
	var reason_ids := _reason_ids(reason_payload)
	var is_fate_initiative := bool(selected.get("fate_initiative", false))
	var fate_context: Dictionary = reason_payload.get("fate", {}) if reason_payload.get("fate", {}) is Dictionary else {}
	var public_summary := str(selected.get("public_summary", "")).strip_edges()
	if public_summary.is_empty():
		public_summary = _summary_for_action(actor_id, action_type, character_name)
	if is_fate_initiative:
		public_summary += " 当前政治命运：%s。" % str(fate_context.get("public_label", fate_context.get("status", "走向未明")))
	var faction_id := str(character.get("faction_id", ""))
	var action: Dictionary = {
		"id": action_id,
		"action_id": action_id,
		"source_campaign_id": str(state.flags.get("campaign_id", "")),
		"character_id": actor_id,
		"actor_id": actor_id,
		"character_name": character_name,
		"action_type": action_type,
		"action_family": str(selected.get("action_family", action_type)),
		"reason_ids": reason_ids,
		"reason_payload": reason_payload,
		"target_ids": selected.get("target_ids", ["li_heng"]).duplicate(true),
		"severity": str(selected.get("severity", "notice")),
		"pause_category": str(selected.get("pause_category", "npc_action")),
		"cooldown_until_day": int(state.current_day) + ACTION_COOLDOWN_DAYS,
		"created_day": int(state.current_day),
		"visible_channel": _visible_channel(action_type),
		"visible_title": str(selected.get("public_title", _visible_title(character_name, action_type))),
		"summary": public_summary,
		"request_class": "routine_request" if _is_routine_request_action({"action_type": action_type, "severity": str(selected.get("severity", "notice")), "fate_initiative": is_fate_initiative}) else "",
		"delegation_candidates": _delegation_candidates_for_action(actor_id),
		"requester_faction_id": faction_id,
		"request_tags": ["politics", "fate", faction_id] if is_fate_initiative else [],
		"personal_effects": {},
		"fate_initiative": is_fate_initiative,
		"fate_ref_id": str(fate_context.get("ref_id", "")),
		"related_route": _related_route(actor_id),
		"status": "visible"
	}
	if is_fate_initiative:
		var bargain := _match_faction_bargain(actor_id, action_type)
		if not bargain.is_empty():
			action["bargain_id"] = str(bargain.get("bargain_id", ""))
			action["bargain_topic"] = str(bargain.get("topic", ""))
			action["public_dispute"] = str(bargain.get("public_dispute", ""))
			action["public_risk"] = str(bargain.get("public_risk", ""))
			action["counterpart_character_id"] = str(bargain.get("counterpart_character_id", ""))
			action["counterpart_faction_id"] = str(bargain.get("counterpart_faction_id", ""))
			action["bargain_outcomes"] = (bargain.get("outcomes", {}) as Dictionary).duplicate(true)
			if not action["request_tags"].has("bargain"):
				action["request_tags"].append("bargain")
			var cou_fac := str(bargain.get("counterpart_faction_id", "")).strip_edges()
			if not cou_fac.is_empty() and not action["request_tags"].has(cou_fac):
				action["request_tags"].append(cou_fac)
			action["personal_effects"] = _fate_personal_effects(actor_id, faction_id, str(fate_context.get("public_label", "当前命运")), bargain)
		else:
			action["personal_effects"] = _fate_personal_effects(actor_id, faction_id, str(fate_context.get("public_label", "当前命运")), {})
	return action

const FACTION_BARGAINS_PATH := "res://data/scenarios/anshi_rebellion/beta_1_11_faction_bargains.json"
var _cached_bargains: Array = []

func _get_faction_bargains() -> Array:
	if not _cached_bargains.is_empty():
		return _cached_bargains
	if FileAccess.file_exists(FACTION_BARGAINS_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FACTION_BARGAINS_PATH))
		if parsed is Dictionary and (parsed as Dictionary).get("bargains", []) is Array:
			_cached_bargains = ((parsed as Dictionary).get("bargains", []) as Array).duplicate(true)
	return _cached_bargains

func _match_faction_bargain(actor_id: String, action_type: String) -> Dictionary:
	var bargains := _get_faction_bargains()
	for raw in bargains:
		if not raw is Dictionary:
			continue
		var b: Dictionary = raw
		var pet_id := str(b.get("petitioner_id", ""))
		var cou_id := str(b.get("counterpart_id", ""))
		if actor_id != pet_id and actor_id != cou_id:
			continue
		for raw_trig in b.get("triggers", []):
			if not raw_trig is Dictionary:
				continue
			var trig: Dictionary = raw_trig
			if str(trig.get("character_id", "")) == actor_id:
				var actions: Array = trig.get("action_types", [])
				if actions.is_empty() or actions.has(action_type):
					var is_petitioner := (actor_id == pet_id)
					var other_id := cou_id if is_petitioner else pet_id
					var other_faction := str(b.get("counterpart_faction_id", "")) if is_petitioner else str(b.get("petitioner_faction_id", ""))
					var pet_faction := str(b.get("petitioner_faction_id", "")) if is_petitioner else str(b.get("counterpart_faction_id", ""))
					return {
						"bargain_id": str(b.get("bargain_id", "")),
						"topic": str(b.get("topic", "")),
						"public_dispute": str(b.get("public_dispute", "")),
						"public_risk": str(b.get("public_risk", "")),
						"counterpart_character_id": other_id,
						"counterpart_faction_id": other_faction,
						"petitioner_faction_id": pet_faction,
						"outcomes": (b.get("outcomes", {}) as Dictionary).duplicate(true)
					}
	return {}

func _has_pending_bargain(state) -> bool:
	if state == null:
		return false
	var pending: Array = state.pending_requests if state.get("pending_requests") is Array else []
	for raw_req in pending:
		if raw_req is Dictionary and not str((raw_req as Dictionary).get("bargain_id", "")).is_empty():
			return true
	return false

func _fate_initiative_candidate(state, character: Dictionary, model: Dictionary) -> Dictionary:
	var actor_id := str(character.get("id", ""))
	if state != null:
		if int(state.current_day) < FIRST_FATE_BARGAIN_DAY:
			return {}
		if _has_pending_bargain(state):
			return {}
		var last_bargain_day := int(state.flags.get("last_faction_bargain_day", -BARGAIN_MIN_INTERVAL_DAYS))
		if int(state.current_day) - last_bargain_day < BARGAIN_MIN_INTERVAL_DAYS:
			return {}
	var fate := _current_fate_context(state, actor_id)
	if fate.is_empty() or _has_emitted_fate_initiative(state, actor_id, str(fate.get("ref_id", ""))):
		return {}
	for raw_initiative in model.get("fate_initiatives", []):
		if not raw_initiative is Dictionary:
			continue
		var initiative: Dictionary = raw_initiative
		if str(initiative.get("fate_status", "")) != str(fate.get("status", "")):
			continue
		var action_type := str(initiative.get("action_type", "")).strip_edges()
		if action_type.is_empty():
			return {}
		return {
			"action_type": action_type,
			"action_family": "fate_initiative:" + str(fate.get("status", "")),
			"score": 1000,
			"severity": "notice",
			"pause_category": "npc_action",
			"target_ids": ["li_heng"],
			"selection_evidence": {"fate": fate.duplicate(true)},
			"public_title": str(initiative.get("public_title", "")),
			"public_summary": str(initiative.get("public_summary", "")),
			"fate_initiative": true
		}
	return {}

func _current_fate_context(state, actor_id: String) -> Dictionary:
	if state == null or not state.character_states is Dictionary:
		return {}
	var character_state: Variant = state.character_states.get(actor_id, {})
	if not character_state is Dictionary:
		return {}
	var latest: Dictionary = {}
	for raw_ref in (character_state as Dictionary).get("fate_causal_refs", []):
		if not raw_ref is Dictionary:
			continue
		var ref: Dictionary = raw_ref
		if str(ref.get("kind", "")) != "character_fate" or str(ref.get("character_id", actor_id)) != actor_id:
			continue
		if latest.is_empty() or int(ref.get("day", 0)) >= int(latest.get("day", 0)):
			latest = ref.duplicate(true)
	if latest.is_empty():
		return {}
	var status := str(latest.get("result_fate_status", (character_state as Dictionary).get("status", "")))
	var ref_id := str(latest.get("id", ""))
	if status.is_empty() or ref_id.is_empty():
		return {}
	return {
		"status": status,
		"ref_id": ref_id,
		"public_label": str(latest.get("public_label", status)),
		"day": int(latest.get("day", 0))
	}

func _has_emitted_fate_initiative(state, actor_id: String, fate_ref_id: String) -> bool:
	if fate_ref_id.is_empty():
		return true
	for raw_action in state.npc_action_feed:
		if raw_action is Dictionary and str((raw_action as Dictionary).get("actor_id", "")) == actor_id and str((raw_action as Dictionary).get("fate_ref_id", "")) == fate_ref_id:
			return true
	return false

func _fate_personal_effects(actor_id: String, faction_id: String, fate_label: String, bargain: Dictionary = {}) -> Dictionary:
	if not bargain.is_empty():
		var outcomes: Dictionary = bargain.get("outcomes", {})
		var counterpart_id := str(bargain.get("counterpart_character_id", ""))
		var result: Dictionary = {}
		for key in ["approve", "reject", "defer"]:
			var outcome: Dictionary = outcomes.get(key, {})
			var effects: Array = []
			var pet_rel := int(outcome.get("petitioner_relationship", 0))
			if pet_rel != 0 and !actor_id.is_empty():
				effects.append({"type": "relationship_delta", "target": actor_id, "value": pet_rel})
			var pet_mem := str(outcome.get("petitioner_memory", "")).strip_edges()
			if !pet_mem.is_empty() and !actor_id.is_empty():
				effects.append({"type": "character_memory", "target": actor_id, "value": pet_mem})
			var cou_rel := int(outcome.get("counterpart_relationship", 0))
			if cou_rel != 0 and !counterpart_id.is_empty():
				effects.append({"type": "relationship_delta", "target": counterpart_id, "value": cou_rel})
			var cou_mem := str(outcome.get("counterpart_memory", "")).strip_edges()
			if !cou_mem.is_empty() and !counterpart_id.is_empty():
				effects.append({"type": "character_memory", "target": counterpart_id, "value": cou_mem})
			var faction_pressures: Dictionary = outcome.get("faction_pressures", {})
			for f_id in faction_pressures.keys():
				effects.append({"type": "faction_delta", "target": str(f_id), "field": "pressure", "value": int(faction_pressures[f_id])})
			result[key] = effects
		return result

	var approve: Array = [
		{"type": "relationship_delta", "target": actor_id, "value": 3},
		{"type": "character_memory", "target": actor_id, "value": "朝廷接受了因‘%s’提出的政治诉求。" % fate_label}
	]
	var reject: Array = [
		{"type": "relationship_delta", "target": actor_id, "value": -4},
		{"type": "character_memory", "target": actor_id, "value": "朝廷拒绝了因‘%s’提出的政治诉求。" % fate_label}
	]
	var defer: Array = [
		{"type": "relationship_delta", "target": actor_id, "value": -1},
		{"type": "character_memory", "target": actor_id, "value": "朝廷推迟处理因‘%s’提出的政治诉求。" % fate_label}
	]
	if not faction_id.is_empty():
		approve.append({"type": "faction_delta", "target": faction_id, "field": "pressure", "value": -2})
		reject.append({"type": "faction_delta", "target": faction_id, "field": "pressure", "value": 3})
		defer.append({"type": "faction_delta", "target": faction_id, "field": "pressure", "value": 1})
	return {"approve": approve, "reject": reject, "defer": defer}

func _evaluate_rule(state, character: Dictionary, model: Dictionary, rule: Dictionary) -> Dictionary:
	var requirements: Dictionary = rule.get("requirements", {})
	var evidence: Dictionary = {}
	var actor_id := str(character.get("id", ""))
	if requirements.has("production_signal"):
		var production_signal := str(requirements.get("production_signal", ""))
		var signal_evidence := _production_signal_evidence(state, actor_id, production_signal)
		if signal_evidence.is_empty():
			return {"ok": false}
		evidence["production_signal"] = production_signal
		for evidence_key in signal_evidence.keys():
			evidence[evidence_key] = signal_evidence[evidence_key]
	if requirements.has("personality_rule"):
		var personality_rule := str(requirements.get("personality_rule", ""))
		if personality_rule == "" or not model.get("personality_rules", []).has(personality_rule):
			return {"ok": false}
		evidence["personality"] = [personality_rule]
	if requirements.has("office_faction_id"):
		var faction_id := str(requirements.get("office_faction_id", ""))
		if faction_id == "" or str(character.get("faction_id", "")) != faction_id:
			return {"ok": false}
		evidence["office"] = {"role": str(character.get("role", "")), "faction_id": faction_id}
	if requirements.has("relationship"):
		var relationship_requirement: Dictionary = requirements.get("relationship", {})
		var target_id := str(relationship_requirement.get("target_id", "li_heng"))
		var relationship_value := int(state.get_relationship(actor_id)) if state.has_method("get_relationship") else int(character.get("relationships", {}).get(target_id, 0))
		if relationship_requirement.has("minimum") and relationship_value < int(relationship_requirement.get("minimum", 0)):
			return {"ok": false}
		if relationship_requirement.has("maximum") and relationship_value > int(relationship_requirement.get("maximum", 0)):
			return {"ok": false}
		evidence["relationship"] = {"target_id": target_id, "value": relationship_value}
	if requirements.has("information_id"):
		var information := _find_information_evidence(state, actor_id, str(requirements.get("information_id", "")))
		if information.is_empty():
			return {"ok": false}
		evidence["information"] = [information]
	if bool(requirements.get("information_participant", false)):
		var participant_information := _find_participant_information(state, actor_id)
		if participant_information.is_empty():
			return {"ok": false}
		evidence["information"] = [participant_information]
	if requirements.has("obligation_statuses"):
		var obligation := _find_matching_obligation(state, actor_id, requirements.get("obligation_statuses", []))
		if requirements.has("obligation_object_id"):
			obligation = _find_object_obligation(state, actor_id, requirements.get("obligation_statuses", []), str(requirements.get("obligation_object_id", "")))
		if obligation.is_empty():
			return {"ok": false}
		evidence["obligation"] = obligation
		if not evidence.has("pressure"):
			evidence["pressure"] = {"kind": "expiring_obligation", "due_day": int(obligation.get("due_day", 0))}
	if requirements.has("pressure"):
		var pressure_requirement: Dictionary = requirements.get("pressure", {})
		var pressure: Dictionary = evidence.get("pressure", {}).duplicate(true)
		if pressure_requirement.has("resource_id"):
			var resource_id := str(pressure_requirement.get("resource_id", ""))
			var resource_value := int(state.resources.get(resource_id, 0))
			if resource_value > int(pressure_requirement.get("maximum", resource_value)):
				return {"ok": false}
			pressure["resource_id"] = resource_id
			pressure["resource_value"] = resource_value
		if pressure_requirement.has("faction_minimum"):
			var faction_pressure := int(state.faction_states.get(str(character.get("faction_id", "")), {}).get("pressure", 0))
			if faction_pressure < int(pressure_requirement.get("faction_minimum", 0)):
				return {"ok": false}
			pressure["faction_pressure"] = faction_pressure
		evidence["pressure"] = pressure
	if requirements.has("map_battle"):
		var map_requirement: Dictionary = requirements.get("map_battle", {})
		var map_battle: Dictionary = {}
		if map_requirement.has("route_id"):
			var route_id := str(map_requirement.get("route_id", ""))
			var route_value := int(state.strategic_routes.get(route_id, 0))
			if route_value < int(map_requirement.get("minimum", 0)):
				return {"ok": false}
			map_battle["route"] = {"route_id": route_id, "pressure": route_value}
		if map_requirement.has("front_id"):
			var front_id := str(map_requirement.get("front_id", ""))
			var front: Dictionary = state.battlefront_states.get(front_id, {})
			var threat := int(front.get("threat", 0))
			if threat < int(map_requirement.get("threat_minimum", 0)):
				return {"ok": false}
			map_battle["front"] = {"front_id": front_id, "threat": threat}
		evidence["map_battle"] = map_battle
	var score := int(rule.get("base_score", 0))
	var weights: Dictionary = rule.get("score_weights", {})
	for evidence_key in evidence.keys():
		score += int(weights.get(evidence_key, 0))
	return {"ok": true, "score": score, "evidence": evidence.duplicate(true)}

func _production_signal_evidence(state, actor_id: String, signal_id: String) -> Dictionary:
	match signal_id:
		"registration_control_bypassed":
			for record in state.dialogue_action_records:
				if actor_id == "li_fuguo" and str(record.get("kind", "")) == "conversation_consequence" and str(record.get("object_id", "")) == "guo_formal_authority_promise" and record.get("authority_effects", {}).get("registration_excluded_authority_ids", []).has(actor_id):
					return {"pressure": {"production_signal": signal_id, "record_id": str(record.get("object_id", record.get("id", "")))}}
		"guo_formal_authority_promise":
			if not _find_matching_obligation(state, actor_id, ["proposed", "accepted"]).is_empty() and not _find_participant_information(state, actor_id).is_empty():
				return {"pressure": {"production_signal": signal_id}}
		"grain_audit_due", "grain_account_report_due":
			for event in state.active_events:
				if event.get("available_decisions", []).has("audit_grain_register") or event.get("available_decisions", []).has("investigate_grain_official"):
					return {"pressure": {"production_signal": signal_id, "event_id": str(event.get("id", ""))}}
		"grain_relief_needed", "li_guangbi_supply_gap":
			if int(state.resources.get("grain", 0)) < 700:
				return {"pressure": {"production_signal": signal_id, "grain": int(state.resources.get("grain", 0))}}
		"guo_supply_order_needed":
			if int(state.resources.get("grain", 0)) < 700 and int(state.strategic_routes.get("support_shuofang", 0)) > 0:
				return {"pressure": {"production_signal": signal_id, "grain": int(state.resources.get("grain", 0))}}
		"li_fuguo_channel_risk":
			var palace_state: Dictionary = state.flags.get("political_chain_states", {}).get("palace_channel_precedent", {})
			if ["escalation", "breach", "counteraction"].has(str(palace_state.get("settlement_kind", ""))):
				return {"pressure": {"production_signal": "political_chain_settlement", "chain_id": "palace_channel_precedent", "branch_id": str(palace_state.get("branch_id", "")), "source_occurrence_id": str(palace_state.get("source_occurrence_id", ""))}}
			var channel_information := _find_participant_information(state, actor_id)
			if not channel_information.is_empty():
				return {"information": [channel_information]}
		"guo_command_audience_needed", "li_bi_intelligence_gap", "old_court_procedure_bypassed", "old_court_ritual_breach", "zhang_appointment_opening":
			var information := _find_participant_information(state, actor_id)
			if not information.is_empty():
				return {"information": [information]}
		"li_fuguo_memorial_risk", "zhang_private_access_needed":
			if int(state.get_relationship(actor_id)) >= 15:
				return {"relationship": {"target_id": "li_heng", "value": int(state.get_relationship(actor_id))}}
		"li_bi_faction_capture":
			if int(state.faction_states.get("suzong_court", {}).get("pressure", 0)) >= 50:
				return {"pressure": {"production_signal": signal_id, "faction_pressure": int(state.faction_states.get("suzong_court", {}).get("pressure", 0))}}
		"li_bi_sunset_clause_needed", "uighur_private_channel_needed", "old_court_precedent_disputed", "li_guangbi_front_report_due":
			var obligation := _find_matching_obligation(state, actor_id, ["accepted"])
			if not obligation.is_empty():
				return {"obligation": obligation}
		"uighur_terms_unwritten":
			if int(state.strategic_routes.get("uighur_push", 0)) >= 2:
				return {"map_battle": {"route": {"route_id": "uighur_push", "pressure": int(state.strategic_routes.get("uighur_push", 0))}}}
		"uighur_memorial_needed":
			if int(state.strategic_routes.get("uighur_push", 0)) >= 2:
				return {"map_battle": {"route": {"route_id": "uighur_push", "pressure": int(state.strategic_routes.get("uighur_push", 0))}}}
		"li_guangbi_order_conflict":
			if int(state.battlefront_states.get("hedong_front", {}).get("threat", 0)) >= 70:
				return {"map_battle": {"front": {"front_id": "hedong_front", "threat": int(state.battlefront_states.get("hedong_front", {}).get("threat", 0))}}}
		"zhang_household_security_threat":
			if int(state.get_relationship(actor_id)) >= 30:
				return {"relationship": {"target_id": "li_heng", "value": int(state.get_relationship(actor_id))}}
		"baseline_shuofang_supply":
			var shuofang: Dictionary = state.battlefront_states.get("shuofang_front", {})
			if int(shuofang.get("supply", 100)) <= 40 and int(shuofang.get("threat", 0)) >= 60:
				return {"pressure": {"production_signal": signal_id, "front_id": "shuofang_front", "supply": int(shuofang.get("supply", 0)), "threat": int(shuofang.get("threat", 0))}}
		"baseline_guanzhong_threat":
			var guanzhong: Dictionary = state.battlefront_states.get("guanzhong_front", {})
			if int(guanzhong.get("threat", 0)) >= 75:
				return {"pressure": {"production_signal": signal_id, "front_id": "guanzhong_front", "threat": int(guanzhong.get("threat", 0))}}
		"baseline_eunuch_pressure":
			var eunuch_pressure := int(state.faction_states.get("eunuch_network", {}).get("pressure", 0))
			if eunuch_pressure >= 40:
				return {"pressure": {"production_signal": signal_id, "faction_id": "eunuch_network", "value": eunuch_pressure}}
		"baseline_uighur_pressure":
			var uighur_pressure := int(state.faction_states.get("uighur_envoys", {}).get("pressure", 0))
			if uighur_pressure >= 60:
				return {"pressure": {"production_signal": signal_id, "faction_id": "uighur_envoys", "value": uighur_pressure}}
		"baseline_old_court_pressure":
			var old_court_pressure := int(state.faction_states.get("old_court", {}).get("pressure", 0))
			if old_court_pressure >= 60:
				return {"pressure": {"production_signal": signal_id, "faction_id": "old_court", "value": old_court_pressure}}
	return {}

func _select_best_candidate(state, actor_id: String, candidates: Array) -> Dictionary:
	if candidates.is_empty():
		return {}
	var best_score := -1
	var ties: Array = []
	for candidate in candidates:
		var candidate_score := int(candidate.get("score", 0))
		if candidate_score > best_score:
			best_score = candidate_score
			ties = [candidate.duplicate(true)]
		elif candidate_score == best_score:
			ties.append(candidate.duplicate(true))
	ties.sort_custom(func(left, right): return str(left.get("action_type", "")) < str(right.get("action_type", "")))
	# Equal scores are resolved solely from the supplied save-state seed, actor id, and day.
	var seed := int(state.flags.get("npc_action_seed", 0)) + int(state.current_day) * 31
	for index in range(actor_id.length()):
		seed += actor_id.unicode_at(index)
	return ties[posmod(seed, ties.size())].duplicate(true)

func _has_primary_demand_in_settlement(actions: Array, actor_id: String) -> bool:
	for action in actions:
		if str(action.get("actor_id", action.get("character_id", ""))) == actor_id:
			return true
	return false

func _is_action_family_on_cooldown(state, actor_id: String, action_family: String) -> bool:
	for action in state.npc_action_feed:
		if str(action.get("actor_id", action.get("character_id", ""))) != actor_id:
			continue
		if str(action.get("action_family", action.get("action_type", ""))) != action_family:
			continue
		if int(action.get("cooldown_until_day", 0)) > int(state.current_day):
			return true
	return false

func _find_matching_obligation(state, actor_id: String, valid_statuses: Array) -> Dictionary:
	for entry in state.obligation_ledger:
		if str(entry.get("target_id", "")) != actor_id:
			continue
		var status := str(entry.get("status", ""))
		if not valid_statuses.has(status):
			continue
		if int(entry.get("due_day", 0)) <= int(state.current_day) + 1:
			return entry.duplicate(true)
	return {}

func _find_object_obligation(state, actor_id: String, valid_statuses: Array, object_id: String) -> Dictionary:
	for entry in state.obligation_ledger:
		if str(entry.get("target_id", "")) == actor_id and str(entry.get("conversation_object_id", "")) == object_id and valid_statuses.has(str(entry.get("status", "")) ) and int(entry.get("due_day", 0)) <= int(state.current_day) + 1:
			return entry.duplicate(true)
	return {}

func _find_information_evidence(state, actor_id: String, information_id: String) -> Dictionary:
	if information_id == "":
		return {}
	for memory in state.structured_memories:
		if str(memory.get("id", "")) == information_id and (memory.get("participants", []).has(actor_id) or str(memory.get("target_id", "")) == actor_id):
			return {"id": information_id, "summary": str(memory.get("summary", ""))}
	return {}

func _find_participant_information(state, actor_id: String) -> Dictionary:
	for memory in state.structured_memories:
		if memory.get("participants", []).has(actor_id) or str(memory.get("target_id", "")) == actor_id:
			return {"id": str(memory.get("id", "")), "summary": str(memory.get("summary", ""))}
	return {}

func _reason_ids(reason_payload: Dictionary) -> Array:
	var reason_ids: Array = []
	var fate_ref_id := str(reason_payload.get("fate", {}).get("ref_id", "")) if reason_payload.get("fate", {}) is Dictionary else ""
	if not fate_ref_id.is_empty():
		reason_ids.append("fate:" + fate_ref_id)
	var trigger_id := str(reason_payload.get("production_signal", reason_payload.get("pressure", {}).get("production_signal", reason_payload.get("pressure", {}).get("trigger_flag", ""))))
	if trigger_id != "":
		reason_ids.append("pressure:" + trigger_id)
	for personality_rule in reason_payload.get("personality", []):
		reason_ids.append("personality:" + str(personality_rule))
	var obligation_id := str(reason_payload.get("obligation", {}).get("id", ""))
	if obligation_id != "":
		reason_ids.append("obligation:" + obligation_id)
	var relationship_target := str(reason_payload.get("relationship", {}).get("target_id", ""))
	if relationship_target != "":
		reason_ids.append("relationship:" + relationship_target)
	var office_role := str(reason_payload.get("office", {}).get("role", ""))
	if office_role != "":
		reason_ids.append("office:" + office_role)
	for information in reason_payload.get("information", []):
		var information_id := str(information.get("id", ""))
		if information_id != "":
			reason_ids.append("information:" + information_id)
	var route: Dictionary = reason_payload.get("map_battle", {}).get("route", {})
	if not route.is_empty():
		reason_ids.append("map_route:" + str(route.get("route_id", "")))
	var front: Dictionary = reason_payload.get("map_battle", {}).get("front", {})
	if not front.is_empty():
		reason_ids.append("map_front:" + str(front.get("front_id", "")))
	return reason_ids

func _severity_for_action(action_type: String) -> String:
	return "major" if action_type in ["request_formal_authority", "lobby_registration_control"] else "notice"

func _pause_category_for_action(action_type: String) -> String:
	return "promise" if action_type == "request_formal_authority" else "npc_action"

func _target_ids_for_action(actor_id: String, action_type: String) -> Array:
	if actor_id == "grain_official_lingwu" and action_type == "shift_audit_blame":
		return ["li_heng", "li_fuguo"]
	return ["li_heng"]

func _next_action_id(state, actor_id: String, action_type: String) -> String:
	var base_id := "%s_%s_%d" % [actor_id, action_type, int(state.current_day)]
	var occurrence := 1
	for action in state.npc_action_feed:
		if str(action.get("action_id", action.get("id", ""))).begins_with(base_id):
			occurrence += 1
	return base_id if occurrence == 1 else "%s__%d" % [base_id, occurrence]

func _summary_for_action(_actor_id: String, action_type: String, character_name: String) -> String:
	var petitioner := character_name if not character_name.strip_edges().is_empty() else "来访者"
	match action_type:
		"ask_for_grain": return "%s称眼前粮道不继，请先拨付一批军粮并核定转运次序。" % petitioner
		"request_grain_relief": return "%s请核查灵武仓粮与赈给名册，决定是否先行发放救济。" % petitioner
		"request_emergency_grain": return "%s报称一处供给将断，请以紧急名义调拨粮草并指定优先受领者。" % petitioner
		"request_audience": return "%s请求当面陈述近日所见，并请朝廷决定是否立即召见。" % petitioner
		"request_intelligence_review": return "%s称军报与传闻互相抵牾，请设人复核消息来源和传递渠道。" % petitioner
		"request_clear_orders": return "%s称前后命令相抵，请明定军令的节制范围与执行次序。" % petitioner
		"request_formal_authority": return "%s请将将令与此前承诺一并明文化，免得军令再受掣肘。" % petitioner
		"demand_reward": return "%s请明确军功赏赐与给养条件，并划定后续调度边界。" % petitioner
		"demand_reward_terms": return "%s要求先议定赏赐数额、交付时点与验功凭据，再作承诺。" % petitioner
		"request_cavalry_supply": return "%s称骑兵补给不足，请核定草料、市易与军纪约束的条件。" % petitioner
		"lobby_appointment": return "%s荐举一人补授要职，请一并厘清该职掌管的钱粮与文书权限。" % petitioner
		"lobby_registration_control": return "%s称登记权被绕开，要求重新收束宫门与文书通道。" % petitioner
		"propose_sunset_clause": return "%s请让临时授权先行生效，但须写明复核日期与撤销条件。" % petitioner
		"request_household_protection": return "%s请核定随驾家眷的名册、口粮与值守安排，避免内廷人心不安。" % petitioner
		"request_succession_assurance": return "%s请明定继嗣与内廷传令的处置原则，以平息朝中疑议。" % petitioner
		"request_amnesty": return "%s请划定一批涉乱军民可赦与不可赦的范围，以安定归附者。" % petitioner
		"seek_private_advice": return "%s请求私下进言一项不宜公开展开的建议，并请决定是否留档。" % petitioner
		"seek_private_audience": return "%s请求密见，称有一事涉及朝中人物，不便在众人面前陈述。" % petitioner
		"accuse_another_npc": return "%s递上对同僚的指控，请求先行核验人证与文书。" % petitioner
		"demand_ritual_review": return "%s请复核仪制与名分，称仓促行事会损及朝廷号令。" % petitioner
		"intercept_memorial": return "%s报称一封奏牍在传递中受阻，请查明经手人与阻截缘由。" % petitioner
		"privately_negotiate": return "%s正私下试探各方条件，盼朝廷先给出可谈的底线。" % petitioner
		"shift_audit_blame": return "%s因核账将至，试图把亏空归咎于下属与转运环节。" % petitioner
		"submit_account_report": return "%s呈上账目，称其中有数笔收支与原先簿册不合。" % petitioner
		"submit_front_report": return "%s呈报前线军情，称敌军动向与粮道状况都需尽快裁定。" % petitioner
		"submit_memorial": return "%s上呈奏疏，请朝廷就其中所列军政事项给出明断。" % petitioner
		"submit_secret_report": return "%s递来密报，称所得消息尚待与其他渠道交叉核验。" % petitioner
		"submit_witness_report": return "%s呈上目击证词，请先核对证人与事发时序。" % petitioner
		_: return "%s呈上一份尚待核实的陈情，说明了所涉人事与处置缘由。" % petitioner

func _is_routine_request_action(action: Dictionary) -> bool:
	if bool(action.get("fate_initiative", false)):
		return true
	if str(action.get("severity", "notice")) == "major":
		return false
	var action_type := str(action.get("action_type", ""))
	return action_type.begins_with("request_") \
		or action_type.begins_with("ask_for_") \
		or action_type.begins_with("seek_") \
		or action_type.begins_with("propose_") \
		or action_type in ["lobby_appointment", "demand_reward", "demand_reward_terms"]

func _delegation_candidates_for_action(actor_id: String) -> Array:
	var candidates := ["li_bi", "guo_ziyi", "li_fuguo"]
	candidates.erase(actor_id)
	return candidates

func _display_character_name(character: Dictionary) -> String:
	var display_name := str(character.get("name", "")).strip_edges()
	return display_name if not display_name.is_empty() else "来访者"

func _visible_channel(action_type: String) -> String:
	if action_type in ["submit_memorial", "submit_front_report", "submit_account_report"]:
		return "奏报"
	if action_type in ["submit_secret_report", "submit_private_report"]:
		return "密报"
	return "主动请求"

func _visible_title(character_name: String, action_type: String) -> String:
	match action_type:
		"submit_secret_report", "submit_private_report": return "%s递来密报" % character_name
		"submit_front_report": return "%s呈上军情" % character_name
		"submit_account_report": return "%s呈上账目" % character_name
		"submit_memorial": return "%s上呈奏疏" % character_name
		_: return "%s提出请求" % character_name

func _related_route(actor_id: String) -> String:
	match actor_id:
		"guo_ziyi", "li_guangbi": return "support_shuofang"
		"uighur_envoy": return "uighur_push"
		_: return "mixed"

func _enqueue_action_event(state, action: Dictionary, event_queue) -> void:
	if event_queue == null:
		return
	if _is_routine_request_action(action):
		return
	var action_id := str(action.get("action_id", action.get("id", "")))
	var event := {
		"id": "npc_action__" + action_id,
		"type": "npc_active_action",
		"title": str(action.get("visible_title", _visible_title(str(action.get("character_name", "")), str(action.get("action_type", ""))))),
		"source_character_id": str(action.get("actor_id", action.get("character_id", ""))),
		"trigger_day": int(state.current_day),
		"deadline_days": 3,
		"urgency": 70 if str(action.get("severity", "notice")) == "major" else 45,
		"visible_summary": str(action.get("summary", "")),
		"available_decisions": [],
		"npc_action_id": action_id,
		"on_expire": []
	}
	event_queue.enqueue_event(state, event)

func _apply_significant_pause(state, action: Dictionary) -> void:
	if str(action.get("severity", "notice")) != "major":
		return
	AutoPausePolicyScript.new().apply_request(state, {
		"severity": "major",
		"category": str(action.get("pause_category", "npc_action")),
		"reason": str(action.get("summary", ""))
	})

func _find_character(characters: Array, character_id: String) -> Dictionary:
	for character in characters:
		if str(character.get("id", "")) == character_id:
			return character.duplicate(true)
	return {}
