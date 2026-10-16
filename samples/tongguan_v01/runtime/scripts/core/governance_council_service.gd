extends RefCounted

class_name GovernanceCouncilService

const PHASE_TURN_COUNTS := {"opening": 3, "cross_examination": 3, "final_position": 3}
const COUNCIL_PHASES := ["awaiting_opening_question", "opening", "awaiting_round_one_decision", "awaiting_intervention_1", "cross_examination", "awaiting_intervention_2", "final_position", "adoption", "drafting"]

func start_regular_council(state, data: Dictionary, memorial_id: String) -> Dictionary:
	if state == null:
		return _fail("missing state", "missing_state")
	var memorial: Dictionary = state.governance_state.get("memorials", {}).get(memorial_id, {}).duplicate(true)
	if memorial.is_empty():
		return _fail("memorial is unavailable", "memorial_unavailable")
	var topic := str(memorial.get("topic", ""))
	var rule: Dictionary = data.get("governance", {}).get("topic_rules", {}).get(topic, {}).duplicate(true)
	var council_rules: Dictionary = rule.get("council_rules", {}).duplicate(true)
	if council_rules.is_empty():
		return _fail("council topic is unavailable", "council_topic_unavailable")
	var candidates := _rank_candidates(state, data, memorial)
	var seats := _ordered_seat_ids(candidates, council_rules)
	if seats.size() < 3:
		return _fail("not enough eligible council members", "insufficient_members")
	var clauses := _topic_clauses(rule, seats)
	if clauses.size() < 3:
		return _fail("council clauses are unavailable", "council_clauses_unavailable")
	var council_id := "council_%06d" % int(state.governance_state.get("next_sequence", 1))
	state.governance_state["next_sequence"] = int(state.governance_state.get("next_sequence", 1)) + 1
	var council := {
		"council_id": council_id,
		"memorial_id": memorial_id,
		"topic": topic,
		"seat_ids": seats.duplicate(true),
		"candidate_ids": candidates.duplicate(true),
		"adviser_profiles": _adviser_profiles(council_rules),
		"status": "active",
		"phase": "awaiting_opening_question",
		"current_turn_index": 0,
		"opening_question_default": str(rule.get("opening_question", "")).replace("\n", " ").strip_edges(),
		"opening_question": "",
		"turns": [],
		"player_interventions": [],
		"clauses": clauses,
		"selected_clause_ids": [],
		"included_clause_ids": [],
		"nominated_drafter_id": "",
		"draft_order_id": "",
		"edict_text": "",
		"revision": 0,
		"preview_token": "",
		"round": 1,
		"round_one": _initial_opinions(state, memorial, rule, seats, council_rules),
		"round_two": [],
		"summary": {}
	}
	council.merge(_draft_defaults(state, memorial, rule), true)
	state.governance_state["councils"][council_id] = council
	return {"ok": true, "council": council.duplicate(true)}

func mark_sealed(state, council_id: String, order_id: String) -> Dictionary:
	var council := _active_council(state, council_id)
	if council.is_empty():
		return _fail("council is unavailable", "council_unavailable")
	if str(council.get("draft_order_id", "")) != order_id:
		return _fail("council draft is no longer linked", "council_draft_unlinked")
	council["status"] = "sealed"
	council["phase"] = "sealed"
	state.governance_state["councils"][council_id] = council
	return {"ok": true, "council": council.duplicate(true)}

func replace_one_seat(state, council_id: String, seat_index: int, replacement_id: String) -> Dictionary:
	return _fail("this council uses fixed three seats", "seat_replacement_unavailable")

func current_turn(state, council_id: String) -> Dictionary:
	var council := _active_council(state, council_id)
	var phase := str(council.get("phase", ""))
	if council.is_empty() or not PHASE_TURN_COUNTS.has(phase):
		return {}
	var index := int(council.get("current_turn_index", 0))
	var seat_ids: Array = council.get("seat_ids", [])
	if index < 0 or index >= seat_ids.size():
		return {}
	return _turn_dto(council, str(seat_ids[index]), index)

func record_turn(state, council_id: String, turn_index: int, adviser_id: String, speech: Dictionary) -> Dictionary:
	var expected := current_turn(state, council_id)
	if expected.is_empty() or int(expected.get("turn_index", -1)) != turn_index or str(expected.get("speaker_id", "")) != adviser_id:
		return _fail("council turn is out of order", "turn_out_of_order")
	var text := str(speech.get("text", "")).strip_edges()
	if text.is_empty():
		return _fail("speech is empty", "empty_speech")
	if text.length() > 600:
		return _fail("speech is too long", "speech_too_long")
	var council := _active_council(state, council_id)
	var turns: Array = council.get("turns", []).duplicate(true)
	turns.append({
		"turn_id": "turn_%d_%d" % [_phase_number(str(council.get("phase", ""))), turn_index],
		"phase": str(council.get("phase", "")),
		"turn_index": turn_index,
		"speaker_id": adviser_id,
		"position": str(expected.get("position", "")),
		"reply_mode": str(expected.get("reply_mode", "")),
		"reply_to_turn_ids": (expected.get("reply_to_turn_ids", []) as Array).duplicate(true),
		"text": text,
		"tone": str(speech.get("tone", "measured")),
		"source": str(speech.get("source", "ai"))
	})
	council["turns"] = turns
	council["current_turn_index"] = turn_index + 1
	_advance_phase_if_complete(council)
	state.governance_state["councils"][council_id] = council
	return {"ok": true, "council": council.duplicate(true)}

func record_opening_question(state, council_id: String, text: String) -> Dictionary:
	var council := _active_council(state, council_id)
	if council.is_empty() or str(council.get("phase", "")) != "awaiting_opening_question":
		return _fail("opening question is out of order", "opening_question_out_of_order")
	var clean := text.replace("\n", " ").strip_edges()
	if clean.is_empty():
		return _fail("opening question is empty", "opening_question_empty")
	if clean.length() > 240:
		return _fail("opening question is too long", "opening_question_too_long")
	council["opening_question"] = clean
	council["phase"] = "opening"
	council["current_turn_index"] = 0
	state.governance_state["councils"][council_id] = council
	return {"ok": true, "council": council.duplicate(true)}

func record_player_intervention(state, council_id: String, text: String, number: int) -> Dictionary:
	var council := _active_council(state, council_id)
	var expected_phase := "awaiting_intervention_%d" % number
	if council.is_empty() or str(council.get("phase", "")) != expected_phase:
		return _fail("intervention is out of order", "intervention_out_of_order")
	var clean := text.strip_edges()
	if clean.length() > 240:
		return _fail("intervention is too long", "intervention_too_long")
	var interventions: Array = council.get("player_interventions", []).duplicate(true)
	interventions.append({"number": number, "text": clean})
	council["player_interventions"] = interventions
	council["phase"] = "cross_examination" if number == 1 else "final_position"
	council["current_turn_index"] = 0
	state.governance_state["councils"][council_id] = council
	return {"ok": true, "council": council.duplicate(true)}

func continue_after_opening(state, council_id: String) -> Dictionary:
	var council := _active_council(state, council_id)
	if council.is_empty() or str(council.get("phase", "")) != "awaiting_round_one_decision":
		return _fail("opening round is not ready for continuation", "round_one_decision_unavailable")
	council["phase"] = "awaiting_intervention_1"
	council["current_turn_index"] = 0
	state.governance_state["councils"][council_id] = council
	return {"ok": true, "council": council.duplicate(true)}

func adopt_after_opening(state, council_id: String) -> Dictionary:
	var council := _active_council(state, council_id)
	if council.is_empty() or str(council.get("phase", "")) != "awaiting_round_one_decision":
		return _fail("opening round is not ready for adoption", "round_one_decision_unavailable")
	council["phase"] = "adoption"
	council["current_turn_index"] = 0
	council["concluded_after_round"] = 1
	state.governance_state["councils"][council_id] = council
	return {"ok": true, "council": council.duplicate(true)}

func toggle_selected_clause(state, council_id: String, clause_id: String) -> Dictionary:
	var council := _active_council(state, council_id)
	if council.is_empty() or str(council.get("phase", "")) != "adoption":
		return _fail("council is not ready for adoption", "adoption_unavailable")
	if _find_clause(council.get("clauses", []), clause_id).is_empty():
		return _fail("council clause is unavailable", "clause_unavailable")
	var selected: Array = council.get("selected_clause_ids", []).duplicate(true)
	if selected.has(clause_id):
		selected.erase(clause_id)
	else:
		selected.append(clause_id)
	council["selected_clause_ids"] = selected
	state.governance_state["councils"][council_id] = council
	return {"ok": true, "council": council.duplicate(true)}

func include_clause(state, council_id: String, clause_id: String) -> Dictionary:
	var council := _active_council(state, council_id)
	if council.is_empty() or str(council.get("phase", "")) != "adoption":
		return _fail("council is not ready for adoption", "adoption_unavailable")
	if _find_clause(council.get("clauses", []), clause_id).is_empty():
		return _fail("council clause is unavailable", "clause_unavailable")
	var included: Array = council.get("included_clause_ids", []).duplicate(true)
	if not included.has(clause_id):
		included.append(clause_id)
	council["included_clause_ids"] = included
	state.governance_state["councils"][council_id] = council
	return {"ok": true, "council": council.duplicate(true)}

func nominate_drafter(state, council_id: String, adviser_id: String) -> Dictionary:
	var council := _active_council(state, council_id)
	if council.is_empty() or str(council.get("phase", "")) != "adoption":
		return _fail("council is not ready for drafting", "drafting_unavailable")
	if not (council.get("seat_ids", []) as Array).has(adviser_id):
		return _fail("drafter is not a council adviser", "invalid_drafter")
	council["nominated_drafter_id"] = adviser_id
	state.governance_state["councils"][council_id] = council
	return {"ok": true, "council": council.duplicate(true)}

func begin_drafting(state, council_id: String) -> Dictionary:
	var council := _active_council(state, council_id)
	if council.is_empty() or str(council.get("phase", "")) != "adoption":
		return _fail("council is not ready for drafting", "drafting_unavailable")
	if (council.get("included_clause_ids", []) as Array).is_empty():
		return _fail("no council clause is included", "basis_required")
	if str(council.get("nominated_drafter_id", "")).is_empty():
		return _fail("drafter is required", "drafter_required")
	council["phase"] = "drafting"
	state.governance_state["councils"][council_id] = council
	return {"ok": true, "council": council.duplicate(true)}

func public_packet(state, council_id: String, adviser_id: String) -> Dictionary:
	var council := _active_council(state, council_id)
	if council.is_empty() or not (council.get("seat_ids", []) as Array).has(adviser_id):
		return {}
	var memorial: Dictionary = state.governance_state.get("memorials", {}).get(str(council.get("memorial_id", "")), {})
	var current := current_turn(state, council_id)
	return {
		"council_id": council_id,
		"topic": str(council.get("topic", "")),
		"phase": str(council.get("phase", "")),
		"adviser_id": adviser_id,
		"opening_question": str(council.get("opening_question", "")).replace("\n", " ").strip_edges(),
		"visible_facts": (memorial.get("visible_facts", []) as Array).duplicate(true),
		"visible_resistance": (memorial.get("visible_resistance", []) as Array).duplicate(true),
		"current_turn": current.duplicate(true),
		"public_transcript": council_public_transcript(state, council_id),
		"player_intervention": pending_intervention(state, council_id),
		"opinions": _public_opinions(council.get("round_one", []))
	}

func council_public_transcript(state, council_id: String) -> Array:
	var council := _active_council(state, council_id)
	var transcript: Array = []
	var opening_question := str(council.get("opening_question", "")).replace("\n", " ").strip_edges()
	if not opening_question.is_empty():
		transcript.append({"source": "emperor", "turn_id": "opening_question", "text": opening_question})
	for raw_turn in council.get("turns", []):
		if raw_turn is Dictionary:
			var turn: Dictionary = raw_turn
			transcript.append({"turn_id": str(turn.get("turn_id", "")), "speaker_id": str(turn.get("speaker_id", "")), "phase": str(turn.get("phase", "")), "text": str(turn.get("text", ""))})
	return transcript

func pending_intervention(state, council_id: String) -> Dictionary:
	var council := _active_council(state, council_id)
	var interventions: Array = council.get("player_interventions", [])
	if interventions.is_empty() or not interventions.back() is Dictionary:
		return {}
	var intervention: Dictionary = interventions.back()
	return {"number": int(intervention.get("number", 0)), "text": str(intervention.get("text", ""))}

func council_draft_basis(state, council_id: String) -> Array:
	var council := _active_council(state, council_id)
	var included: Array = council.get("included_clause_ids", [])
	var basis: Array = []
	for raw_clause in council.get("clauses", []):
		if raw_clause is Dictionary and included.has(str((raw_clause as Dictionary).get("clause_id", ""))):
			basis.append((raw_clause as Dictionary).duplicate(true))
	return basis

func finalize_round_two(state, council_id: String) -> Dictionary:
	return _fail("sequential council turns are required", "sequential_turns_required")

func start_special_council(state, data: Dictionary, special_id: String) -> Dictionary:
	for raw_special in data.get("governance", {}).get("special_councils", []):
		if raw_special is Dictionary and str((raw_special as Dictionary).get("special_id", "")) == special_id:
			return _fail("special council content is not implemented", "special_council_not_authorized")
	return _fail("special council is not authorized", "special_council_not_authorized")

func _draft_defaults(state, memorial: Dictionary, rule: Dictionary) -> Dictionary:
	var resource_values := {}
	for resource_key in memorial.get("resource_keys", []):
		var available := int(state.resources.get(str(resource_key), 0))
		if available > 0:
			resource_values[str(resource_key)] = mini(available, 10)
	var offices: Array = rule.get("required_offices", []).duplicate(true)
	var executors: Array = memorial.get("recommended_executor_ids", []).duplicate(true)
	var recipient_id := str(executors[0]) if not executors.is_empty() else ""
	var drafting_office_id := str(offices[0]) if not offices.is_empty() else ""
	var reviewing_office_id := str(offices[1]) if offices.size() > 1 else drafting_office_id
	return {
		"default_recipient_id": recipient_id,
		"default_action_id": str(rule.get("action_id", "")),
		"default_location_id": str(memorial.get("location_id", "")),
		"default_resources": resource_values,
		"default_authority_tags": offices.duplicate(true),
		"default_report_due_day": int(state.current_day) + int(memorial.get("deadline_days", 0)),
		"drafted_by_office_id": drafting_office_id,
		"reviewed_by_office_id": reviewing_office_id
	}

func _ordered_seat_ids(candidates: Array, council_rules: Dictionary) -> Array:
	var order: Array = council_rules.get("seat_order", [])
	var seats: Array = []
	for raw_adviser_id in order:
		var adviser_id := str(raw_adviser_id)
		if candidates.has(adviser_id) and not seats.has(adviser_id):
			seats.append(adviser_id)
	return seats

func _adviser_profiles(council_rules: Dictionary) -> Dictionary:
	var profiles := {}
	for raw_adviser_id in council_rules.get("seat_order", []):
		var adviser_id := str(raw_adviser_id)
		var profile: Dictionary = council_rules.get(adviser_id, {})
		if not profile.is_empty():
			profiles[adviser_id] = profile.duplicate(true)
	return profiles

func _topic_clauses(rule: Dictionary, seats: Array) -> Array:
	var clauses: Array = []
	for raw_clause in rule.get("clauses", []):
		if not raw_clause is Dictionary:
			continue
		var clause: Dictionary = (raw_clause as Dictionary).duplicate(true)
		var clause_id := str(clause.get("clause_id", ""))
		if clause_id.is_empty() or not seats.has(str(clause.get("adviser_id", ""))):
			continue
		clauses.append(clause)
	return clauses

func _initial_opinions(state, memorial: Dictionary, rule: Dictionary, seats: Array, council_rules: Dictionary) -> Array:
	var opinions: Array = []
	for adviser_id in seats:
		var profile: Dictionary = council_rules.get(str(adviser_id), {})
		opinions.append({"adviser_id": str(adviser_id), "position": str(profile.get("position", "conditional_support")), "reply_mode": str(profile.get("reply_mode", "weigh")), "recommended_action": str(rule.get("action_id", "")), "required_offices": (rule.get("required_offices", []) as Array).duplicate(true), "required_resources": {}, "location_id": str(memorial.get("location_id", "")), "deadline_day": int(state.current_day) + int(memorial.get("deadline_days", 0)), "visible_risks": (memorial.get("visible_resistance", []) as Array).duplicate(true), "known_basis": (memorial.get("visible_facts", []) as Array).duplicate(true)})
	return opinions

func _turn_dto(council: Dictionary, adviser_id: String, turn_index: int) -> Dictionary:
	var profile := _profile_for(council, adviser_id)
	return {"turn_index": turn_index, "speaker_id": adviser_id, "phase": str(council.get("phase", "")), "position": str(profile.get("position", "conditional_support")), "reply_mode": str(profile.get("reply_mode", "weigh")), "reply_to_turn_ids": _reply_targets(council, turn_index, profile)}

func _profile_for(council: Dictionary, adviser_id: String) -> Dictionary:
	var declared: Dictionary = council.get("adviser_profiles", {}).get(adviser_id, {})
	if not declared.is_empty():
		return {"position": str(declared.get("position", "conditional_support")), "reply_mode": str(declared.get("reply_mode", "weigh")), "reply_to": str(declared.get("reply_to", "all_previous"))}
	for raw_opinion in council.get("round_one", []):
		if raw_opinion is Dictionary and str((raw_opinion as Dictionary).get("adviser_id", "")) == adviser_id:
			return {"position": str((raw_opinion as Dictionary).get("position", "conditional_support")), "reply_mode": str((raw_opinion as Dictionary).get("reply_mode", "weigh")), "reply_to": "previous" if str((raw_opinion as Dictionary).get("reply_mode", "")) == "rebut" else "all_previous"}
	return {"position": "conditional_support", "reply_mode": "weigh", "reply_to": "all_previous"}

func _reply_targets(council: Dictionary, turn_index: int, profile: Dictionary) -> Array:
	var prior_turns: Array = council.get("turns", [])
	if prior_turns.is_empty():
		return []
	var phase := str(council.get("phase", ""))
	if phase == "opening":
		var reply_to := str(profile.get("reply_to", ""))
		if reply_to == "previous":
			return [str((prior_turns.back() as Dictionary).get("turn_id", ""))]
		if reply_to == "all_previous":
			return _turn_ids_for_phase(prior_turns, phase)
		return []
	var ids: Array = []
	for raw_turn in prior_turns:
		if raw_turn is Dictionary:
			ids.append(str((raw_turn as Dictionary).get("turn_id", "")))
	return ids

func _turn_ids_for_phase(turns: Array, phase: String) -> Array:
	var ids: Array = []
	for raw_turn in turns:
		if raw_turn is Dictionary and str((raw_turn as Dictionary).get("phase", "")) == phase:
			ids.append(str((raw_turn as Dictionary).get("turn_id", "")))
	return ids

func _advance_phase_if_complete(council: Dictionary) -> void:
	var phase := str(council.get("phase", ""))
	if int(council.get("current_turn_index", 0)) < int(PHASE_TURN_COUNTS.get(phase, 0)):
		return
	match phase:
		"opening":
			council["phase"] = "awaiting_round_one_decision"
		"cross_examination":
			council["phase"] = "awaiting_intervention_2"
		"final_position":
			council["phase"] = "adoption"
	council["current_turn_index"] = 0

func _phase_number(phase: String) -> int:
	match phase:
		"opening": return 1
		"cross_examination": return 2
		"final_position": return 3
	return 0

func _find_clause(clauses: Array, clause_id: String) -> Dictionary:
	for raw_clause in clauses:
		if raw_clause is Dictionary and str((raw_clause as Dictionary).get("clause_id", "")) == clause_id:
			return (raw_clause as Dictionary).duplicate(true)
	return {}

func _rank_candidates(state, data: Dictionary, memorial: Dictionary) -> Array:
	var topic := str(memorial.get("topic", ""))
	var scored: Array = []
	for raw_character in data.get("characters", []):
		if not raw_character is Dictionary:
			continue
		var character: Dictionary = raw_character
		if str(character.get("status", "")) not in ["active", "distant"]:
			continue
		var character_id := str(character.get("id", ""))
		if character_id.is_empty() or character_id == _player_character_id(state):
			continue
		var office_match := 0
		for office in state.office_state.values():
			if office is Dictionary and str((office as Dictionary).get("holder_id", "")) == character_id and ((office as Dictionary).get("council_topics", []) as Array).has(topic):
				office_match = 1
		var relationship := clampi(int(character.get("relationships", {}).get(_player_character_id(state), 0)), -10, 10)
		var score := office_match * 100 + int(character.get("governance_ability", character.get("stats", {}).get("governance", 0))) + relationship
		scored.append({"id": character_id, "score": score})
	scored.sort_custom(func(left, right): return int(left.score) > int(right.score) or (int(left.score) == int(right.score) and str(left.id) < str(right.id)))
	var result: Array = []
	for item in scored:
		result.append(str((item as Dictionary).get("id", "")))
	return result

func _public_opinions(opinions: Array) -> Array:
	var result: Array = []
	for raw_opinion in opinions:
		if raw_opinion is Dictionary:
			var opinion: Dictionary = raw_opinion
			result.append({"adviser_id": str(opinion.get("adviser_id", "")), "position": str(opinion.get("position", "")), "reply_mode": str(opinion.get("reply_mode", "")), "recommended_action": str(opinion.get("recommended_action", "")), "visible_risks": (opinion.get("visible_risks", []) as Array).duplicate(true), "known_basis": (opinion.get("known_basis", []) as Array).duplicate(true)})
	return result

func _active_council(state, council_id: String) -> Dictionary:
	if state == null:
		return {}
	var council: Dictionary = state.governance_state.get("councils", {}).get(council_id, {}).duplicate(true)
	return council if str(council.get("status", "")) == "active" else {}

func _player_character_id(state) -> String:
	if state != null:
		var configured := str(state.player_character_id).strip_edges()
		if not configured.is_empty():
			return configured
	return "li_heng"

func _fail(message: String, code: String) -> Dictionary:
	return {"ok": false, "code": code, "error": message}
