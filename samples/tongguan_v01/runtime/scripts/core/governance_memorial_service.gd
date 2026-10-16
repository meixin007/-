extends RefCounted

class_name GovernanceMemorialService

const CHOICES := ["adopted", "rejected", "bypassed"]
const CONSULTATION_PHASES := ["talking", "selecting", "drafted"]
const CONSULTATION_TURN_SOURCES := ["ai", "offline"]
const MAX_CONSULTATION_TEXT_CHARS := 1200
const Beta109TestScopeScript = preload("res://scripts/core/beta_1_09_test_scope.gd")
const CanonicalJSONScript = preload("res://scripts/core/canonical_json.gd")
const TangOfficeCatalogScript = preload("res://scripts/domain/tang_office_catalog.gd")
const BETA110_CAMPAIGN_ID := "anshi_beta_1_10"
const BETA110_FOLLOWUP_RECEIPT_FLAG := "beta110_followup_receipts"
const BETA110_FOLLOWUP_RECEIPT_LIMIT := 64
const LEGAL := {
	"unread": ["read", "expired"],
	"read": ["consulting", "council", "expired"],
	"consulting": ["council", "decreed", "expired"],
	"council": ["decreed"],
	"decreed": ["executing"],
	"executing": ["closed"],
	"closed": [],
	"expired": []
}

func project_inbox(state, data: Dictionary) -> Dictionary:
	if state == null: return {"ok": false, "items": [], "error": "missing state"}
	var items_by_id: Dictionary = {}
	var memorials: Dictionary = state.governance_state.get("memorials", {}) if state.governance_state.get("memorials", {}) is Dictionary else {}
	var memorial_ids: Array = memorials.keys()
	memorial_ids.sort()
	for raw_memorial_id in memorial_ids:
		var raw_memorial: Variant = memorials.get(raw_memorial_id)
		if not raw_memorial is Dictionary:
			continue
		var memorial: Dictionary = (raw_memorial as Dictionary).duplicate(true)
		if str(memorial.get("memorial_id", "")).strip_edges().is_empty():
			memorial["memorial_id"] = str(raw_memorial_id)
		if str(memorial.get("source_kind", "")) == "accountability_case":
			continue
		if not Beta109TestScopeScript.is_memorial_visible(memorial, state, data):
			continue
		var projected_memorial: Dictionary = _project_memorial(memorial, data, false)
		var test_label := Beta109TestScopeScript.memorial_label(str(projected_memorial.get("memorial_id", "")))
		if not test_label.is_empty() and Beta109TestScopeScript.is_current(state, data):
			projected_memorial["test_line_label"] = test_label
		_append_inbox_item(items_by_id, projected_memorial)
	for raw_request in state.pending_requests:
		if not raw_request is Dictionary or str((raw_request as Dictionary).get("status", "pending")) != "pending":
			continue
		var req_dict: Dictionary = raw_request as Dictionary
		var req_id: String = str(req_dict.get("request_id", req_dict.get("memorial_id", "")))
		var is_memorial_req: bool = str(req_dict.get("document_kind", "")) == "奏折" or str(req_dict.get("kind", "")) == "memorial" or req_dict.has("source_memorial_id")
		if not is_memorial_req:
			continue
		if not Beta109TestScopeScript.is_current(state, data) and Beta109TestScopeScript.is_request_visible(req_dict, state, data):
			_append_inbox_item(items_by_id, _project_legacy_request(req_dict, data))
	var items: Array = items_by_id.values()
	items.sort_custom(func(left, right): return _sort_key(left) < _sort_key(right))
	var result := {"ok": true, "items": items}
	var scope_summary := _scope_summary(state, data)
	if not scope_summary.is_empty():
		result["scope_summary"] = scope_summary
	return result

func open_memorial(state, data: Dictionary, memorial_id: String) -> Dictionary:
	if state == null: return _fail("missing state", "missing_state")
	var memorial := _find_memorial(state, memorial_id)
	if memorial.is_empty(): return _fail("memorial is not available", "memorial_unavailable")
	if str(memorial.get("source_kind", "")) != "legacy" and str(memorial.get("status", "")) == "unread":
		var transitioned := transition(state, memorial_id, "read", {})
		if not bool(transitioned.get("ok", false)): return transitioned
		memorial = (transitioned.get("memorial", {}) as Dictionary).duplicate(true)
	return {"ok": true, "memorial": _project_legacy_request(memorial, data) if str(memorial.get("source_kind", "")) == "legacy" else _project_memorial(memorial, data, false)}

func project_consultation_candidates(state, data: Dictionary, memorial_id: String) -> Dictionary:
	if state == null: return _fail("missing state", "missing_state")
	var memorial := _find_memorial(state, memorial_id)
	if memorial.is_empty(): return _fail("memorial is not available", "memorial_unavailable")
	var candidates: Array = []
	var topic := str(memorial.get("topic", ""))
	var recommended_ids: Array = memorial.get("recommended_executor_ids", []) if memorial.get("recommended_executor_ids", []) is Array else []
	for raw_character in data.get("characters", []):
		if not raw_character is Dictionary:
			continue
		var character: Dictionary = raw_character
		var adviser_id := str(character.get("id", "")).strip_edges()
		if adviser_id.is_empty() or adviser_id == _player_character_id(state):
			continue
		if _is_placeholder_character(character):
			continue
		if str(character.get("status", "")) not in ["active", "distant"] or not _is_in_lingwu_court(character):
			continue
		if not _has_governance_identity(character):
			continue
		var ability := int(character.get("governance_ability", character.get("stats", {}).get("governance", 0)))
		var office_titles := _office_titles_for(state, adviser_id)
		var topic_authority := _has_matching_office(state, adviser_id, topic)
		candidates.append({
			"adviser_id": adviser_id,
			"display_name": str(character.get("name", adviser_id)),
			"role": str(character.get("role", "朝臣")),
			"governance_ability": ability,
			"office_titles": office_titles,
			"topic_authority": topic_authority
		})
	candidates.sort_custom(func(left, right):
		var left_rec := recommended_ids.has(str(left.get("adviser_id", "")))
		var right_rec := recommended_ids.has(str(right.get("adviser_id", "")))
		if left_rec != right_rec:
			return left_rec
		if bool(left.get("topic_authority", false)) != bool(right.get("topic_authority", false)):
			return bool(left.get("topic_authority", false))
		if int(left.get("governance_ability", 0)) != int(right.get("governance_ability", 0)):
			return int(left.get("governance_ability", 0)) > int(right.get("governance_ability", 0))
		return str(left.get("adviser_id", "")) < str(right.get("adviser_id", ""))
	)
	return {"ok": true, "items": candidates.slice(0, 3)}

func start_consultation(state, data: Dictionary, memorial_id: String, adviser_id: String) -> Dictionary:
	if state == null: return _fail("missing state", "missing_state")
	var memorial := _find_memorial(state, memorial_id)
	if memorial.is_empty(): return _fail("memorial is not available", "memorial_unavailable")
	if str(memorial.get("source_kind", "")) == "legacy":
		return _fail("legacy requests do not include verified governance facts", "legacy_governance_request_unavailable")
	var adviser := _find_character(data, adviser_id)
	if adviser.is_empty() or str(adviser.get("status", "")) not in ["active", "distant"]: return _fail("adviser is unavailable", "adviser_unavailable")
	var consultation_ids: Array = memorial.get("consultation_ids", []) if memorial.get("consultation_ids", []) is Array else []
	if not consultation_ids.is_empty() or str(memorial.get("status", "")) == "consulting":
		for existing_id in consultation_ids:
			var existing_record: Dictionary = (state.governance_state.get("consultations", {}) as Dictionary).get(str(existing_id), {})
			if not existing_record.is_empty() and str(existing_record.get("status", "")) == "open":
				return {"ok": true, "consultation_id": str(existing_id), "consultation": existing_record.duplicate(true), "resumed": true}
		return _fail("memorial consultation is unavailable", "consultation_unavailable")
	if str(memorial.get("status", "")) not in ["unread", "read"]:
		return _fail("memorial consultation is unavailable", "consultation_unavailable")
	var topic := str(memorial.get("topic", ""))
	var rule: Dictionary = _get_topic_rule(data, topic)
	var consultation_id := "consultation_%06d" % int(state.governance_state.get("next_sequence", 1))
	var has_authority := _has_matching_office(state, adviser_id, topic)
	var record := {
		"consultation_id": consultation_id, "memorial_id": memorial_id, "adviser_id": adviser_id, "day": int(state.current_day),
		"position": "conditional_support" if has_authority else "insufficient_authority", "recommended_action": str(rule.get("action_id", "")),
		"required_offices": (rule.get("required_offices", []) as Array).duplicate(true), "required_resources": _resources_for(memorial),
		"location_id": str(memorial.get("location_id", "")), "deadline_day": int(memorial.get("deadline_day", int(state.current_day) + int(memorial.get("deadline_days", 0)))),
		"visible_risks": memorial.get("visible_resistance", []).duplicate(true), "known_basis": memorial.get("visible_facts", []).duplicate(true), "status": "open",
		"ability": int(adviser.get("governance_ability", adviser.get("stats", {}).get("governance", 0)))
	}
	if not has_authority: record["reason"] = "adviser lacks the required office authority"
	var transitioned := transition(state, memorial_id, "consulting", {})
	if not bool(transitioned.get("ok", false)): return transitioned
	state.governance_state["next_sequence"] = int(state.governance_state.get("next_sequence", 1)) + 1
	state.governance_state["consultations"][consultation_id] = record
	var stored: Dictionary = state.governance_state["memorials"][memorial_id].duplicate(true)
	stored["consultation_ids"] = [consultation_id]
	state.governance_state["memorials"][memorial_id] = stored
	return {"ok": true, "consultation_id": consultation_id, "consultation": record.duplicate(true)}

func append_consultation_turn(state, consultation_id: String, player_text: String, adviser_text: String, adviser_name: String, source: String) -> Dictionary:
	var consultation_result := _get_open_consultation(state, consultation_id)
	if not bool(consultation_result.get("ok", false)):
		return consultation_result
	var clean_player := player_text.replace("\n", " ").strip_edges()
	var clean_adviser := adviser_text.replace("\n", " ").strip_edges()
	if clean_player.is_empty() or clean_adviser.is_empty() or clean_player.length() > MAX_CONSULTATION_TEXT_CHARS or clean_adviser.length() > MAX_CONSULTATION_TEXT_CHARS:
		return _fail("consultation text is invalid", "invalid_consultation_text")
	if not CONSULTATION_TURN_SOURCES.has(source):
		return _fail("consultation source is invalid", "invalid_consultation_source")
	var consultation: Dictionary = (consultation_result.get("consultation", {}) as Dictionary).duplicate(true)
	var turns: Array = consultation.get("turns", []).duplicate(true) if consultation.get("turns", []) is Array else []
	var exchange_index := floori(float(turns.size()) / 2.0) + 1
	var question_id := "%s_question_%02d" % [consultation_id, exchange_index]
	var answer_id := "%s_answer_%02d" % [consultation_id, exchange_index]
	turns.append({
		"turn_id": question_id, "speaker": "player", "speaker_id": _player_character_id(state),
		"text": clean_player, "source": "player", "selectable": false, "day": int(state.current_day)
	})
	turns.append({
		"turn_id": answer_id, "speaker": "adviser", "speaker_id": str(consultation.get("adviser_id", "")),
		"speaker_name": adviser_name.strip_edges(), "text": clean_adviser, "source": source,
		"selectable": true, "day": int(state.current_day)
	})
	consultation["turns"] = turns
	consultation["conversation_phase"] = "talking"
	state.governance_state["consultations"][consultation_id] = consultation
	return {"ok": true, "consultation": consultation.duplicate(true), "question_turn_id": question_id, "answer_turn_id": answer_id}

func set_consultation_turn_selected(state, consultation_id: String, turn_id: String, selected: bool) -> Dictionary:
	var consultation_result := _get_open_consultation(state, consultation_id)
	if not bool(consultation_result.get("ok", false)):
		return consultation_result
	var consultation: Dictionary = (consultation_result.get("consultation", {}) as Dictionary).duplicate(true)
	var found := false
	var selectable := false
	for raw_turn in consultation.get("turns", []) if consultation.get("turns", []) is Array else []:
		if raw_turn is Dictionary and str((raw_turn as Dictionary).get("turn_id", "")) == turn_id:
			found = true
			selectable = bool((raw_turn as Dictionary).get("selectable", false)) and str((raw_turn as Dictionary).get("speaker", "")) == "adviser"
			break
	if not found:
		return _fail("consultation turn is unavailable", "turn_unavailable")
	if not selectable:
		return _fail("only adviser replies can be selected", "turn_not_selectable")
	var selected_ids: Array = consultation.get("selected_turn_ids", []).duplicate(true) if consultation.get("selected_turn_ids", []) is Array else []
	if selected and not selected_ids.has(turn_id):
		selected_ids.append(turn_id)
	elif not selected:
		selected_ids.erase(turn_id)
	consultation["selected_turn_ids"] = selected_ids
	consultation["conversation_phase"] = "selecting" if not selected_ids.is_empty() else "talking"
	state.governance_state["consultations"][consultation_id] = consultation
	return {"ok": true, "consultation": consultation.duplicate(true)}

func set_consultation_phase(state, consultation_id: String, phase: String) -> Dictionary:
	var consultation_result := _get_open_consultation(state, consultation_id)
	if not bool(consultation_result.get("ok", false)):
		return consultation_result
	if not CONSULTATION_PHASES.has(phase):
		return _fail("consultation phase is invalid", "invalid_consultation_phase")
	var consultation: Dictionary = (consultation_result.get("consultation", {}) as Dictionary).duplicate(true)
	consultation["conversation_phase"] = phase
	state.governance_state["consultations"][consultation_id] = consultation
	return {"ok": true, "consultation": consultation.duplicate(true)}

func save_consultation_draft(state, consultation_id: String, draft_text: String, source: String) -> Dictionary:
	var consultation_result := _get_open_consultation(state, consultation_id)
	if not bool(consultation_result.get("ok", false)):
		return consultation_result
	var clean_draft := draft_text.replace("\n", " ").strip_edges()
	if clean_draft.is_empty() or clean_draft.length() > 1200:
		return _fail("consultation draft is invalid", "invalid_consultation_draft")
	if source not in ["ai", "ai_edited", "manual"]:
		return _fail("consultation draft source is invalid", "invalid_consultation_draft_source")
	var consultation: Dictionary = (consultation_result.get("consultation", {}) as Dictionary).duplicate(true)
	consultation["draft_text"] = clean_draft
	consultation["draft_source"] = source
	consultation["conversation_phase"] = "drafted"
	state.governance_state["consultations"][consultation_id] = consultation
	return {"ok": true, "consultation": consultation.duplicate(true)}

func link_consultation_draft_order(state, consultation_id: String, order_id: String) -> Dictionary:
	var consultation_result := _get_open_consultation(state, consultation_id)
	if not bool(consultation_result.get("ok", false)):
		return consultation_result
	var clean_order_id := order_id.strip_edges()
	if clean_order_id.is_empty():
		return _fail("consultation draft order is invalid", "invalid_consultation_draft_order")
	var consultation: Dictionary = (consultation_result.get("consultation", {}) as Dictionary).duplicate(true)
	var existing_order_id := str(consultation.get("draft_order_id", "")).strip_edges()
	if not existing_order_id.is_empty() and existing_order_id != clean_order_id:
		return _fail("consultation already has a draft order", "consultation_draft_order_exists")
	var order: Dictionary = state.governance_state.get("orders", {}).get(clean_order_id, {})
	if order.is_empty() or str(order.get("source_memorial_id", "")) != str(consultation.get("memorial_id", "")):
		return _fail("consultation draft order does not match memorial", "invalid_consultation_draft_order")
	consultation["draft_order_id"] = clean_order_id
	state.governance_state["consultations"][consultation_id] = consultation
	return {"ok": true, "consultation": consultation.duplicate(true), "order_id": clean_order_id}

func project_consultation_summary_basis(state, consultation_id: String) -> Dictionary:
	var consultation_result := _get_open_consultation(state, consultation_id)
	if not bool(consultation_result.get("ok", false)):
		return consultation_result
	var consultation: Dictionary = consultation_result.get("consultation", {})
	var turns: Array = consultation.get("turns", []) if consultation.get("turns", []) is Array else []
	var selected_ids: Array = consultation.get("selected_turn_ids", []) if consultation.get("selected_turn_ids", []) is Array else []
	var selected_turns: Array = []
	var adjacent_player_turns: Array = []
	for index in range(turns.size()):
		if not turns[index] is Dictionary:
			continue
		var turn: Dictionary = turns[index]
		var turn_id := str(turn.get("turn_id", ""))
		if str(turn.get("speaker", "")) == "adviser" and selected_ids.has(turn_id):
			selected_turns.append({"turn_id": turn_id, "adviser_id": str(turn.get("speaker_id", "")), "text": str(turn.get("text", "")).left(MAX_CONSULTATION_TEXT_CHARS), "source": str(turn.get("source", ""))})
			if index > 0 and turns[index - 1] is Dictionary and str((turns[index - 1] as Dictionary).get("speaker", "")) == "player":
				var player_turn: Dictionary = turns[index - 1]
				adjacent_player_turns.append({"turn_id": str(player_turn.get("turn_id", "")), "text": str(player_turn.get("text", "")).left(MAX_CONSULTATION_TEXT_CHARS)})
	if selected_turns.is_empty():
		return _fail("at least one adviser reply must be selected", "consultation_basis_empty")
	return {"ok": true, "selected_turns": selected_turns, "adjacent_player_turns": adjacent_player_turns}

func _get_open_consultation(state, consultation_id: String) -> Dictionary:
	if state == null:
		return _fail("missing state", "missing_state")
	var consultation: Dictionary = state.governance_state.get("consultations", {}).get(consultation_id, {}).duplicate(true)
	if consultation.is_empty() or str(consultation.get("status", "")) != "open":
		return _fail("consultation is not open", "consultation_unavailable")
	return {"ok": true, "consultation": consultation}

func record_consultation_choice(state, consultation_id: String, choice: String) -> Dictionary:
	if state == null or not CHOICES.has(choice): return _fail("consultation choice is invalid", "invalid_choice")
	var consultation: Dictionary = state.governance_state.get("consultations", {}).get(consultation_id, {}).duplicate(true)
	if consultation.is_empty() or str(consultation.get("status", "")) != "open": return _fail("consultation is not open", "consultation_unavailable")
	consultation["status"] = choice
	state.governance_state["consultations"][consultation_id] = consultation
	state.structured_memories.append({"memory_type": "governance_consultation", "memorial_id": str(consultation.get("memorial_id", "")), "adviser_id": str(consultation.get("adviser_id", "")), "choice": choice, "tags": ["governance_consultation", str(consultation.get("memorial_id", "")), str(consultation.get("adviser_id", "")), choice], "day": int(state.current_day)})
	return {"ok": true, "consultation": consultation.duplicate(true)}

func transition(state, memorial_id: String, target_status: String, patch: Dictionary = {}) -> Dictionary:
	if state == null or not LEGAL.has(target_status): return _fail("memorial transition is invalid", "invalid_memorial_transition")
	var memorial := _find_memorial(state, memorial_id)
	if memorial.is_empty() or str(memorial.get("source_kind", "")) == "legacy": return _fail("memorial is unavailable", "memorial_unavailable")
	var current_status := str(memorial.get("status", ""))
	if not LEGAL.has(current_status) or not (LEGAL[current_status] as Array).has(target_status): return _fail("memorial transition is not allowed", "invalid_memorial_transition")
	for key in patch.keys():
		if str(key) not in ["closed_day", "outcome"]: return _fail("memorial transition patch is invalid", "invalid_memorial_transition")
	var updated := memorial.duplicate(true)
	updated["status"] = target_status
	if patch.has("closed_day"):
		if typeof(patch.get("closed_day")) not in [TYPE_INT, TYPE_FLOAT]: return _fail("memorial transition patch is invalid", "invalid_memorial_transition")
		updated["closed_day"] = int(patch.get("closed_day"))
	if patch.has("outcome"): updated["outcome"] = str(patch.get("outcome", ""))
	state.governance_state["memorials"][memorial_id] = updated
	return {"ok": true, "memorial": updated.duplicate(true)}

func bind_council(state, memorial_id: String, council_id: String) -> Dictionary:
	if council_id.strip_edges().is_empty(): return _fail("council id is required", "invalid_council_binding")
	var memorial := _find_memorial(state, memorial_id)
	if memorial.is_empty() or not str(memorial.get("active_council_id", "")).is_empty() or str(memorial.get("status", "")) not in ["unread", "read", "consulting"]: return _fail("memorial council is unavailable", "council_unavailable")
	var council: Dictionary = state.governance_state.get("councils", {}).get(council_id, {})
	if council.is_empty() or str(council.get("memorial_id", "")) != memorial_id: return _fail("council does not match memorial", "invalid_council_binding")
	var transitioned := transition(state, memorial_id, "council", {})
	if not bool(transitioned.get("ok", false)): return transitioned
	var updated: Dictionary = state.governance_state["memorials"][memorial_id].duplicate(true)
	updated["active_council_id"] = council_id
	state.governance_state["memorials"][memorial_id] = updated
	return {"ok": true, "memorial": updated.duplicate(true)}

func bind_decree(state, memorial_id: String, order_id: String) -> Dictionary:
	if order_id.strip_edges().is_empty(): return _fail("order id is required", "invalid_decree_binding")
	var memorial := _find_memorial(state, memorial_id)
	if memorial.is_empty() or not str(memorial.get("order_id", "")).is_empty() or str(memorial.get("status", "")) not in ["consulting", "council"]: return _fail("memorial decree is unavailable", "decree_unavailable")
	var order: Dictionary = state.governance_state.get("orders", {}).get(order_id, {})
	if order.is_empty(): return _fail("order is unavailable", "order_unavailable")
	if not str(order.get("source_memorial_id", "")).is_empty() and str(order.get("source_memorial_id", "")) != memorial_id: return _fail("order does not match memorial", "invalid_decree_binding")
	var council_id := str(order.get("council_id", ""))
	if not council_id.is_empty() and council_id != str(memorial.get("active_council_id", "")): return _fail("order council does not match memorial", "invalid_decree_binding")
	var transitioned := transition(state, memorial_id, "decreed", {})
	if not bool(transitioned.get("ok", false)): return transitioned
	order["source_memorial_id"] = memorial_id
	state.governance_state["orders"][order_id] = order
	var updated: Dictionary = state.governance_state["memorials"][memorial_id].duplicate(true)
	updated["order_id"] = order_id
	state.governance_state["memorials"][memorial_id] = updated
	return {"ok": true, "memorial": updated.duplicate(true)}

func mark_executing(state, memorial_id: String) -> Dictionary:
	return transition(state, memorial_id, "executing", {})

func close_order_chain(state, memorial_id: String, outcome: String, effects: Dictionary) -> Dictionary:
	var closed := transition(state, memorial_id, "closed", {"closed_day": int(state.current_day), "outcome": outcome})
	if not bool(closed.get("ok", false)): return closed
	if not effects.is_empty():
		var applied: Dictionary = (state.flags.get("governance_memorial_effects", {}) as Dictionary).duplicate(true)
		applied[memorial_id] = effects.duplicate(true)
		state.flags["governance_memorial_effects"] = applied
	return closed

func settle_deadlines(state, _governance_data: Dictionary) -> Dictionary:
	if state == null: return _fail("missing state", "missing_state")
	var expired: Array = []
	for memorial_id in (state.governance_state.get("memorials", {}) as Dictionary).keys():
		var memorial: Dictionary = state.governance_state["memorials"][memorial_id]
		if str(memorial.get("status", "")) in ["unread", "read", "consulting"] and int(state.current_day) >= int(memorial.get("deadline_day", 0)):
			var transition_result := transition(state, str(memorial_id), "expired", {})
			if not bool(transition_result.get("ok", false)): return transition_result
			expired.append(str(memorial_id))
	return {"ok": true, "expired_memorial_ids": expired}

func activate_followups(state, governance_data: Dictionary) -> Dictionary:
	if state == null: return _fail("missing state", "missing_state")
	var templates: Array = []
	for raw_template in governance_data.get("followup_memorial_templates", []):
		if raw_template is Dictionary: templates.append(raw_template)
	for raw_template in governance_data.get("memorial_templates", []):
		if raw_template is Dictionary and ((raw_template as Dictionary).has("previous_memorial_id") or (raw_template as Dictionary).has("activation_window")): templates.append(raw_template)
	templates.sort_custom(func(left, right): return str((left as Dictionary).get("memorial_id", "")) < str((right as Dictionary).get("memorial_id", "")))
	var beta110 := str(state.flags.get("campaign_id", "")) == BETA110_CAMPAIGN_ID
	if not beta110:
		return _activate_followups_legacy(state, templates)
	var templates_by_predecessor: Dictionary = {}
	for raw_template in templates:
		var template: Dictionary = raw_template as Dictionary
		var predecessor_id := str(template.get("previous_memorial_id", "")).strip_edges()
		if predecessor_id.is_empty():
			continue
		var grouped: Array = templates_by_predecessor.get(predecessor_id, []) if templates_by_predecessor.get(predecessor_id, []) is Array else []
		grouped.append(template)
		templates_by_predecessor[predecessor_id] = grouped
	var predecessor_ids: Array = templates_by_predecessor.keys()
	predecessor_ids.sort()
	var receipts: Dictionary = {}
	var stale_receipts_removed := false
	if beta110:
		var raw_receipts: Variant = state.flags.get(BETA110_FOLLOWUP_RECEIPT_FLAG, {})
		if raw_receipts is Dictionary:
			for raw_predecessor_id in (raw_receipts as Dictionary).keys():
				var raw_receipt: Variant = (raw_receipts as Dictionary).get(raw_predecessor_id, {})
				if not raw_receipt is Dictionary:
					continue
				var branch_id := str((raw_receipt as Dictionary).get("branch_id", ""))
				# BETA 1.10 receipts must not claim the older BETA 1.09
				# chain. Those legacy branches share predecessors with the new
				# aftershock templates and would otherwise suppress valid content.
				if not branch_id.begins_with("memorial_beta110_"):
					stale_receipts_removed = true
					continue
				receipts[str(raw_predecessor_id)] = (raw_receipt as Dictionary).duplicate(true)
	var activated: Array = []
	for predecessor_id in predecessor_ids:
		if activated.size() >= 2: break
		if beta110 and receipts.has(str(predecessor_id)):
			continue
		var predecessor: Dictionary = (state.governance_state.get("memorials", {}) as Dictionary).get(predecessor_id, {})
		if predecessor.is_empty():
			continue
		var predecessor_result := _predecessor_order_result(state, predecessor)
		var predecessor_status := str(predecessor_result.get("status", ""))
		var predecessor_has_result := not str(predecessor_result.get("outcome", "")).is_empty() or not str(predecessor_result.get("condition", "")).is_empty()
		if predecessor_status not in ["closed", "expired"] and not predecessor_has_result:
			continue
		var candidates: Array = []
		var grouped_candidates: Array = templates_by_predecessor.get(predecessor_id, []) if templates_by_predecessor.get(predecessor_id, []) is Array else []
		for raw_candidate in grouped_candidates:
			var candidate: Dictionary = raw_candidate as Dictionary
			var candidate_id := str(candidate.get("memorial_id", "")).strip_edges()
			var candidate_window: Dictionary = candidate.get("activation_window", {}) if candidate.get("activation_window", {}) is Dictionary else {}
			if candidate_id.is_empty() or (state.governance_state.get("memorials", {}) as Dictionary).has(candidate_id):
				continue
			if int(state.current_day) < int(candidate_window.get("start_day", 0)) or int(state.current_day) > int(candidate_window.get("end_day", 2147483647)):
				continue
			if _activation_predicate_matches(state, candidate.get("activation_predicate", {}), predecessor):
				candidates.append(candidate)
		if candidates.is_empty():
			continue
		candidates.sort_custom(func(left, right): return _template_selection_key(left as Dictionary, predecessor_result) < _template_selection_key(right as Dictionary, predecessor_result))
		var template: Dictionary = candidates[0] as Dictionary
		var memorial_id := str(template.get("memorial_id", "")).strip_edges()
		var created := {}
		for key in ["sender_id", "topic", "location_id", "resource_keys", "deadline_days", "recommended_executor_ids", "visible_facts", "visible_resistance", "request_text", "followup_id", "previous_memorial_id", "linked_case_id", "node_id", "source_paths"]:
			if template.has(key): created[key] = template[key].duplicate(true) if template[key] is Dictionary or template[key] is Array else template[key]
		created["source_kind"] = "scenario"; created["memorial_id"] = memorial_id; created["case_chain_id"] = str(template.get("case_chain_id", memorial_id)); created["case_phase"] = str(template.get("case_phase", "followup")); created["status"] = "unread"
		created["activated_day"] = int(state.current_day); created["deadline_day"] = int(state.current_day) + maxi(int(template.get("deadline_days", 0)), 0); created["consultation_ids"] = []; created["active_council_id"] = ""; created["order_id"] = ""; created["closed_day"] = -1; created["outcome"] = ""
		created["activation_variant"] = _activation_variant_for(predecessor, predecessor_result, template)
		created["previous_order_id"] = str(predecessor_result.get("order_id", ""))
		created["predecessor_result"] = predecessor_result.duplicate(true)
		var source_hash := _predecessor_result_hash(predecessor_result)
		created["source_result_hash"] = source_hash
		state.governance_state["memorials"][memorial_id] = created
		activated.append(memorial_id)
		if beta110 and memorial_id.begins_with("memorial_beta110_"):
			receipts[str(predecessor_id)] = {
				"branch_id": memorial_id,
				"memorial_id": str(predecessor_id),
				"activation_day": int(state.current_day),
				"source_result_hash": source_hash
			}
	if not activated.is_empty() or stale_receipts_removed:
		var next_flags: Dictionary = state.flags.duplicate(true)
		if not activated.is_empty():
			next_flags["governance_followup_activation_day"] = int(state.current_day)
		if beta110:
			if receipts.size() > BETA110_FOLLOWUP_RECEIPT_LIMIT:
				return _fail("too many BETA 1.10 followup receipts", "followup_receipt_limit")
			next_flags[BETA110_FOLLOWUP_RECEIPT_FLAG] = receipts
		state.flags = next_flags
	return {"ok": true, "activated_memorial_ids": activated}

func _activate_followups_legacy(state, templates: Array) -> Dictionary:
	if int(state.flags.get("governance_followup_activation_day", -1)) == int(state.current_day):
		return {"ok": true, "activated_memorial_ids": []}
	var activated: Array = []
	for raw_template in templates:
		if activated.size() >= 2:
			break
		var template: Dictionary = raw_template as Dictionary
		var memorial_id := str(template.get("memorial_id", "")).strip_edges()
		if memorial_id.is_empty() or (state.governance_state.get("memorials", {}) as Dictionary).has(memorial_id):
			continue
		var predecessor_id := str(template.get("previous_memorial_id", ""))
		var predecessor: Dictionary = (state.governance_state.get("memorials", {}) as Dictionary).get(predecessor_id, {})
		if not predecessor_id.is_empty() and (predecessor.is_empty() or str(predecessor.get("status", "")) not in ["closed", "expired"]):
			continue
		var window: Dictionary = template.get("activation_window", {}) if template.get("activation_window", {}) is Dictionary else {}
		if int(state.current_day) < int(window.get("start_day", 0)) or int(state.current_day) > int(window.get("end_day", 2147483647)) or not _activation_predicate_matches(state, template.get("activation_predicate", {}), predecessor):
			continue
		var predecessor_result := _predecessor_order_result(state, predecessor)
		var created := {}
		for key in ["sender_id", "topic", "location_id", "resource_keys", "deadline_days", "recommended_executor_ids", "visible_facts", "visible_resistance", "request_text", "followup_id", "previous_memorial_id", "linked_case_id", "node_id", "source_paths"]:
			if template.has(key):
				created[key] = template[key].duplicate(true) if template[key] is Dictionary or template[key] is Array else template[key]
		created["source_kind"] = "scenario"
		created["memorial_id"] = memorial_id
		created["case_chain_id"] = str(template.get("case_chain_id", memorial_id))
		created["case_phase"] = str(template.get("case_phase", "followup"))
		created["status"] = "unread"
		created["activated_day"] = int(state.current_day)
		created["deadline_day"] = int(state.current_day) + maxi(int(template.get("deadline_days", 0)), 0)
		created["consultation_ids"] = []
		created["active_council_id"] = ""
		created["order_id"] = ""
		created["closed_day"] = -1
		created["outcome"] = ""
		created["activation_variant"] = _activation_variant_for(predecessor, predecessor_result, template)
		state.governance_state["memorials"][memorial_id] = created
		activated.append(memorial_id)
	if not activated.is_empty():
		var next_flags: Dictionary = state.flags.duplicate(true)
		next_flags["governance_followup_activation_day"] = int(state.current_day)
		state.flags = next_flags
	return {"ok": true, "activated_memorial_ids": activated}

func project_chain(state, case_chain_id: String) -> Dictionary:
	if state == null: return _fail("missing state", "missing_state")
	var memorials: Array = []
	for raw_memorial in (state.governance_state.get("memorials", {}) as Dictionary).values():
		if raw_memorial is Dictionary and str((raw_memorial as Dictionary).get("case_chain_id", "")) == case_chain_id: memorials.append((raw_memorial as Dictionary).duplicate(true))
	memorials.sort_custom(func(left, right): return "%08d|%s" % [int((left as Dictionary).get("activated_day", 0)), str((left as Dictionary).get("memorial_id", ""))] < "%08d|%s" % [int((right as Dictionary).get("activated_day", 0)), str((right as Dictionary).get("memorial_id", ""))])
	return {"ok": true, "case_chain_id": case_chain_id, "memorials": memorials}

func _activation_predicate_matches(state, value: Variant, predecessor: Dictionary = {}) -> bool:
	if value == null or (value is Dictionary and (value as Dictionary).is_empty()): return true
	if not (value is Dictionary): return false
	var predicate: Dictionary = value
	var allowed_keys := ["flag", "equals", "predecessor_outcomes", "predecessor_conditions"]
	for key in predicate.keys():
		if str(key) not in allowed_keys: return false
	if predicate.has("flag"):
		var flag := str(predicate.get("flag", "")).strip_edges()
		if flag.is_empty() or state.flags.get(flag) != predicate.get("equals"): return false
	var predecessor_result := _predecessor_order_result(state, predecessor)
	if predicate.has("predecessor_outcomes"):
		var outcomes: Variant = predicate.get("predecessor_outcomes")
		if not outcomes is Array or (outcomes as Array).is_empty() or not _predecessor_result_matches(outcomes as Array, predecessor_result, "outcome"): return false
	if predicate.has("predecessor_conditions"):
		var conditions: Variant = predicate.get("predecessor_conditions")
		if not conditions is Array or (conditions as Array).is_empty(): return false
		if not _predecessor_result_matches(conditions as Array, predecessor_result, "condition"):
			# A closed failed order is authoritative even when the memorial's
			# stale condition is still normal. This keeps the failure branch
			# reachable through the order result without inventing a second flag.
			if str(predecessor_result.get("outcome", "")) != "failed":
				return false
	return true

func _predecessor_order_result(state, predecessor: Dictionary) -> Dictionary:
	var result := {
		"status": str(predecessor.get("status", "")).strip_edges(),
		"outcome": str(predecessor.get("outcome", "")).strip_edges(),
		"condition": str(predecessor.get("condition", "")).strip_edges(),
		"order_id": str(predecessor.get("order_id", "")).strip_edges()
	}
	var order_id := str(result.get("order_id", ""))
	if state != null and not order_id.is_empty():
		var orders: Dictionary = state.governance_state.get("orders", {}) if state.governance_state.get("orders", {}) is Dictionary else {}
		var linked: Variant = orders.get(order_id, {})
		if linked is Dictionary:
			var order: Dictionary = linked
			var resolved: Dictionary = order.get("resolved", {}) if order.get("resolved", {}) is Dictionary else {}
			var order_outcome := str(resolved.get("outcome", order.get("outcome", ""))).strip_edges()
			var order_condition := str(resolved.get("condition", order.get("condition", ""))).strip_edges()
			if not order_outcome.is_empty(): result["outcome"] = order_outcome
			if not order_condition.is_empty(): result["condition"] = order_condition
	if str(result.get("status", "")) == "expired" and str(result.get("condition", "")).is_empty():
		result["condition"] = "expired"
	return result

func _predecessor_result_matches(values: Array, result: Dictionary, field: String) -> bool:
	var actual_values: Array[String] = []
	var primary := str(result.get(field, "")).strip_edges()
	if not primary.is_empty(): actual_values.append(primary)
	var status := str(result.get("status", "")).strip_edges()
	if not status.is_empty() and not actual_values.has(status): actual_values.append(status)
	for raw_value in values:
		var expected := str(raw_value).strip_edges()
		if not expected.is_empty() and actual_values.has(expected): return true
	return false

func _activation_variant_for(predecessor: Dictionary, order_result: Dictionary, template: Dictionary) -> String:
	if predecessor.is_empty(): return "normal"
	var status := str(order_result.get("status", predecessor.get("status", ""))).strip_edges()
	var outcome := str(order_result.get("outcome", "")).strip_edges()
	var condition := str(order_result.get("condition", "")).strip_edges()
	var variant := "normal"
	if status == "expired" or condition == "expired" or outcome == "expired":
		variant = "missed"
	elif condition in ["blocked", "lost_contact"]:
		variant = "blocked"
	elif condition == "delayed" or outcome == "partial":
		variant = "delayed"
	elif outcome == "failed":
		variant = "missed"
	var declared_missed_variant := str(template.get("missed_precondition_variant", "")).strip_edges()
	if variant == "missed" and declared_missed_variant in ["normal", "delayed", "blocked", "missed"]:
		return declared_missed_variant
	return variant

func _template_selection_key(template: Dictionary, predecessor_result: Dictionary) -> String:
	var branch_priority := _result_priority(predecessor_result)
	var template_id := str(template.get("memorial_id", ""))
	var predicate: Dictionary = template.get("activation_predicate", {}) if template.get("activation_predicate", {}) is Dictionary else {}
	var specificity := 0
	var outcomes: Variant = predicate.get("predecessor_outcomes", [])
	var conditions: Variant = predicate.get("predecessor_conditions", [])
	if outcomes is Array and not str(predecessor_result.get("outcome", "")).is_empty() and (outcomes as Array).has(str(predecessor_result.get("outcome", ""))):
		specificity += 100
	if conditions is Array and not str(predecessor_result.get("condition", "")).is_empty() and (conditions as Array).has(str(predecessor_result.get("condition", ""))):
		specificity += 50
	if outcomes is Array:
		specificity -= (outcomes as Array).size()
	if conditions is Array:
		specificity -= (conditions as Array).size()
	var explicit_priority := int(template.get("activation_priority", 0))
	return "%04d|%04d|%04d|%s" % [9999 - branch_priority, 999 - explicit_priority, 999 - specificity, template_id]

func _result_priority(result: Dictionary) -> int:
	var status := str(result.get("status", "")).strip_edges()
	var outcome := str(result.get("outcome", "")).strip_edges()
	var condition := str(result.get("condition", "")).strip_edges()
	if status == "expired" or condition == "expired": return 800
	if outcome == "failed": return 700
	if condition == "lost_contact": return 600
	if condition == "blocked": return 500
	if condition == "delayed": return 400
	if outcome == "partial": return 300
	if outcome == "completed" or condition == "normal": return 200
	return 100

func _predecessor_result_hash(result: Dictionary) -> String:
	var hashed: Dictionary = CanonicalJSONScript.hash_value(result)
	return str(hashed.get("hash", "")) if bool(hashed.get("ok", false)) else ""

func _find_memorial(state, memorial_id: String) -> Dictionary:
	var stored: Dictionary = state.governance_state.get("memorials", {}).get(memorial_id, {}).duplicate(true)
	if not stored.is_empty(): return stored
	for raw_request in state.pending_requests:
		if raw_request is Dictionary and str((raw_request as Dictionary).get("request_id", "")) == memorial_id and str((raw_request as Dictionary).get("status", "pending")) == "pending":
			var legacy: Dictionary = (raw_request as Dictionary).duplicate(true)
			legacy["memorial_id"] = memorial_id; legacy["source_kind"] = "legacy"; legacy["topic"] = "legacy_request"
			return legacy
	return {}

func _project_memorial(memorial: Dictionary, data: Dictionary, legacy: bool) -> Dictionary:
	var topic := str(memorial.get("topic", ""))
	var rule: Dictionary = _get_topic_rule(data, topic)
	var council_rules: Variant = rule.get("council_rules", null)
	var clauses: Variant = rule.get("clauses", null)
	var can_start_council := not legacy and council_rules is Dictionary and not (council_rules as Dictionary).is_empty() and clauses is Array and not (clauses as Array).is_empty()
	return {"memorial_id": str(memorial.get("memorial_id", "")), "document_kind": "奏折", "sender_name": _character_name(data, str(memorial.get("sender_id", ""))), "topic": topic, "title": _memorial_title(memorial, data), "summary": str(memorial.get("request_text", "")), "visible_facts": memorial.get("visible_facts", []).duplicate(true), "visible_resistance": memorial.get("visible_resistance", []).duplicate(true), "deadline_day": int(memorial.get("deadline_day", int(memorial.get("filed_day", 0)) + int(memorial.get("deadline_days", 0)))), "recommended_executor_ids": memorial.get("recommended_executor_ids", []).duplicate(true), "can_start_council": can_start_council, "council_unavailable_reason": "本议题采用指定大臣商议，不适用三席朝议。" if not legacy and not can_start_council else "", "can_start_consultation": not legacy, "source_kind": "legacy" if legacy else str(memorial.get("source_kind", "scenario")), "status": "unread" if legacy else str(memorial.get("status", "unread"))}

func _get_topic_rule(data: Dictionary, topic: String) -> Dictionary:
	var rule: Dictionary = data.get("governance", {}).get("topic_rules", {}).get(topic, {}) if data.get("governance", {}).get("topic_rules", {}).get(topic, {}) is Dictionary else {}
	var defaults: Variant = data.get("beta110_execution_defaults", {})
	if defaults is Dictionary and (defaults as Dictionary).get(topic, {}) is Dictionary:
		var def_topic: Dictionary = (defaults as Dictionary).get(topic, {}) as Dictionary
		var merged := def_topic.duplicate(true)
		merged.merge(rule, true)
		if str(rule.get("action_id", "")).strip_edges().is_empty():
			merged["action_id"] = def_topic.get("action_id", "")
		for field in ["required_offices", "recommended_executor_ids", "resource_keys"]:
			var configured: Variant = rule.get(field, [])
			if not configured is Array or (configured as Array).is_empty():
				merged[field] = (def_topic.get(field, []) as Array).duplicate(true) if def_topic.get(field, []) is Array else []
		return merged
	return rule

func _scope_summary(state, data: Dictionary) -> String:
	if str(data.get("campaign_id", "")).strip_edges() != "anshi_beta_1_10":
		return ""
	var season: Variant = data.get("political_season", {})
	if not season is Dictionary or not (season as Dictionary).get("routes", []) is Array:
		return ""
	var route_labels: Array[String] = []
	for raw_route in (season as Dictionary).get("routes", []) as Array:
		if not raw_route is Dictionary:
			continue
		var label := str((raw_route as Dictionary).get("label", "")).strip_edges()
		if not label.is_empty():
			route_labels.append(label)
	if route_labels.is_empty():
		return ""
	var phase_prefix := "第 31 日起" if state != null and int(state.current_day) < 31 else "当前"
	return "BETA 1.10 %s余波线：%s" % [phase_prefix, "／".join(route_labels)]

func _memorial_title(memorial: Dictionary, data: Dictionary) -> String:
	var explicit_title := str(memorial.get("public_title", memorial.get("title", ""))).strip_edges()
	if not explicit_title.is_empty() and explicit_title != "待阅奏折":
		return explicit_title
	var node_id := str(memorial.get("node_id", "")).strip_edges()
	if not node_id.is_empty() and data.get("beta110_nodes", []) is Array:
		for raw_node in data.get("beta110_nodes", []) as Array:
			if raw_node is Dictionary and str((raw_node as Dictionary).get("node_id", "")).strip_edges() == node_id:
				var node_title := str((raw_node as Dictionary).get("title", "")).strip_edges()
				if not node_title.is_empty():
					return node_title
	var topic_titles := {
		"military_supply": "朔方粮道转运",
		"fiscal_supply": "灵武仓粮配给",
		"inner_court_oversight": "宫门传令复核",
		"supply_accountability": "粮册与供给问责",
		"frontline_supply": "前线军粮处置",
		"palace_authority": "宫门授权复核",
		"alliance_cost": "援助条款与代价"
	}
	return str(topic_titles.get(str(memorial.get("topic", "")), "待阅奏折"))

func _project_legacy_request(request: Dictionary, data: Dictionary) -> Dictionary:
	return {"memorial_id": str(request.get("request_id", request.get("memorial_id", ""))), "document_kind": "奏折", "sender_name": _character_name(data, str(request.get("requester_id", request.get("sender_id", "")))), "topic": "legacy_request", "title": str(request.get("title", "待阅奏折")), "summary": str(request.get("summary", request.get("request_text", ""))), "deadline_day": int(request.get("due_day", request.get("deadline_day", 0))), "can_personally_handle": true, "delegate_options": request.get("delegation_candidates", []).duplicate(true), "can_start_council": false, "can_start_consultation": false, "governance_unavailable_reason": "旧请愿未包含可供朝议或商议使用的核验事实。", "source_kind": "legacy", "status": "unread"}

func _append_inbox_item(items_by_id: Dictionary, item: Dictionary) -> void:
	var memorial_id := str(item.get("memorial_id", "")).strip_edges()
	if memorial_id.is_empty() or items_by_id.has(memorial_id):
		return
	items_by_id[memorial_id] = item.duplicate(true)

func _sort_key(item: Dictionary) -> String:
	return "%08d|%08d|%s" % [int(item.get("deadline_day", 99999999)), int(item.get("filed_day", 0)), str(item.get("memorial_id", ""))]

func _resources_for(memorial: Dictionary) -> Dictionary:
	var resources: Dictionary = {}
	for resource_key in memorial.get("resource_keys", []): resources[str(resource_key)] = 120
	return resources

func _has_matching_office(state, adviser_id: String, topic: String) -> bool:
	for office in state.office_state.values():
		if office is Dictionary and str((office as Dictionary).get("holder_id", "")) == adviser_id and ((office as Dictionary).get("council_topics", []) as Array).has(topic): return true
	return false

func _office_titles_for(state, adviser_id: String) -> Array:
	var titles: Array = []
	var seen_canonicals: Dictionary = {}
	if state == null or not (state.office_state is Dictionary):
		return titles
	for office in state.office_state.values():
		if office is Dictionary and str((office as Dictionary).get("holder_id", "")) == adviser_id:
			var raw_id := str((office as Dictionary).get("office_id", (office as Dictionary).get("id", "")))
			var canonical := TangOfficeCatalogScript.canonical_id(raw_id)
			if canonical.is_empty() or seen_canonicals.has(canonical):
				continue
			seen_canonicals[canonical] = true
			var title := str((office as Dictionary).get("name", (office as Dictionary).get("display_name", (office as Dictionary).get("title", "")))).strip_edges()
			if title.is_empty() or title == raw_id or title == canonical:
				title = TangOfficeCatalogScript.get_office_name(canonical)
			if not title.is_empty() and not titles.has(title):
				titles.append(title)
	return titles

func _is_in_lingwu_court(character: Dictionary) -> bool:
	return str(character.get("location_id", "")).strip_edges() in ["lingwu_court", "lingwu_court_node", "lingwu"]

func _is_placeholder_character(character: Dictionary) -> bool:
	var id := str(character.get("id", "")).strip_edges().to_lower()
	var name := str(character.get("name", "")).strip_edges().to_lower()
	if id.begins_with("beta") or name.begins_with("beta"):
		return true
	if id.begins_with("mock_") or id.begins_with("test_"):
		return true
	return false

func _has_governance_identity(character: Dictionary) -> bool:
	if character.get("governance_tags", []) is Array and not (character.get("governance_tags", []) as Array).is_empty():
		return true
	if character.has("governance_ability"):
		return true
	var stats = character.get("stats", {})
	if stats is Dictionary and (stats as Dictionary).has("governance"):
		return true
	return false

func _player_character_id(state) -> String:
	if state != null:
		var configured := str(state.player_character_id).strip_edges()
		if not configured.is_empty():
			return configured
	return "li_heng"

func _find_character(data: Dictionary, character_id: String) -> Dictionary:
	for raw_character in data.get("characters", []):
		if raw_character is Dictionary and str((raw_character as Dictionary).get("id", "")) == character_id: return (raw_character as Dictionary).duplicate(true)
	return {}

func _character_name(data: Dictionary, character_id: String) -> String:
	return str(_find_character(data, character_id).get("name", "上奏者"))

func _fail(message: String, code: String) -> Dictionary:
	return {"ok": false, "code": code, "error": message}
