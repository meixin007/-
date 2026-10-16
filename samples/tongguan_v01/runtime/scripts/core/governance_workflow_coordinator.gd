extends RefCounted

class_name GovernanceWorkflowCoordinator

const GameStateTransactionScript = preload("res://scripts/core/game_state_transaction.gd")
const MemorialServiceScript = preload("res://scripts/core/governance_memorial_service.gd")
const CouncilServiceScript = preload("res://scripts/core/governance_council_service.gd")
const OrderServiceScript = preload("res://scripts/core/governance_order_service.gd")
const GovernanceAdvicePresenterScript = preload("res://scripts/core/governance_advice_presenter.gd")

const ALLOWED_INTENTS := ["open_memorial", "consult", "record_consultation_exchange", "save_consultation_draft", "create_consultation_decree", "create_direct_decree", "create_oral_order", "publish_consultation_draft", "confirm_oral_order", "start_council", "submit_opening_question", "continue_council_round", "submit_intervention", "skip_intervention", "toggle_clause", "include_clause", "nominate_drafter", "generate_edict", "revise_edict", "preview_edict", "seal_edict", "create_correction", "retry_wording", "use_offline_wording", "back_to_inbox", "withdraw_order", "finalize_council"]

var _wording_adapter: Callable
var _seal_fault_injector: Callable
var _memorials = MemorialServiceScript.new()
var _councils = CouncilServiceScript.new()
var _orders = OrderServiceScript.new()

func _init(wording_adapter: Callable = Callable(), seal_fault_injector: Callable = Callable()) -> void:
	_wording_adapter = wording_adapter
	_seal_fault_injector = seal_fault_injector

func handle_intent(context, intent: String, payload: Dictionary) -> Dictionary:
	if context == null or context.state == null:
		return _result(context, false, "invalid_governance_context", "治理上下文不可用")
	if not ALLOWED_INTENTS.has(intent):
		return _result(context, false, "unknown_governance_intent", "未知的治理意图")
	var result: Dictionary = {}
	match intent:
		"open_memorial": result = _open_memorial(context, str(payload.get("memorial_id", "")))
		"consult": result = _memorials.start_consultation(context.state, context.scenario_data, str(payload.get("memorial_id", "")), str(payload.get("adviser_id", "")))
		"record_consultation_exchange": result = _record_consultation_exchange(context, payload)
		"save_consultation_draft": result = _save_consultation_draft(context, payload)
		"create_consultation_decree": result = _create_consultation_decree(context, payload)
		"create_direct_decree": result = _create_memorial_draft(context, payload, "edict")
		"create_oral_order": result = _create_memorial_draft(context, payload, "oral")
		"publish_consultation_draft": result = _publish_consultation_draft(context, payload)
		"start_council": result = _start_council(context, payload)
		"submit_opening_question": result = _councils.record_opening_question(context.state, str(payload.get("council_id", "")), str(payload.get("text", "")))
		"continue_council_round": result = _record_or_continue_round(context, payload)
		"submit_intervention": result = _councils.record_player_intervention(context.state, str(payload.get("council_id", "")), str(payload.get("text", "")), int(payload.get("number", 0)))
		"skip_intervention": result = _councils.record_player_intervention(context.state, str(payload.get("council_id", "")), "", int(payload.get("number", 0)))
		"toggle_clause": result = _councils.toggle_selected_clause(context.state, str(payload.get("council_id", "")), str(payload.get("clause_id", "")))
		"include_clause": result = _councils.include_clause(context.state, str(payload.get("council_id", "")), str(payload.get("clause_id", "")))
		"nominate_drafter": result = _councils.nominate_drafter(context.state, str(payload.get("council_id", "")), str(payload.get("adviser_id", "")))
		"generate_edict": result = _generate_edict(context, payload)
		"revise_edict": result = _orders.revise_council_draft(context.state, str(payload.get("order_id", "")), payload.get("changes", {}) as Dictionary)
		"preview_edict": result = _preview_edict(context, str(payload.get("order_id", "")))
		"seal_edict": result = _seal_transaction(context, payload)
		"confirm_oral_order": result = _confirm_oral_transaction(context, payload)
		"withdraw_order": result = _orders.withdraw(context.state, str(payload.get("order_id", "")))
		"finalize_council": result = _councils.finalize_round_two(context.state, str(payload.get("council_id", "")))
		"back_to_inbox": result = _back_to_inbox(context)
		_: result = {"ok": false, "code": "intent_not_ready", "error": "该治理意图尚未进入可执行阶段"}
	return _result(context, bool(result.get("ok", false)), str(result.get("code", "")), str(result.get("error", "")), result)

func complete_wording(context, token: String, reply: Dictionary) -> Dictionary:
	if token.strip_edges().is_empty() or not _wording_adapter.is_valid():
		return _result(context, false, "wording_task_unavailable", "文辞任务不可用")
	var result: Variant = _wording_adapter.call(context, token, reply.duplicate(true))
	return _result(context, result is Dictionary and bool((result as Dictionary).get("ok", false)), str((result as Dictionary).get("code", "")) if result is Dictionary else "invalid_wording_result", str((result as Dictionary).get("error", "")) if result is Dictionary else "文辞服务返回无效", result as Dictionary if result is Dictionary else {})

func project(context, selection: Dictionary = {}) -> Dictionary:
	if context == null or context.state == null: return _result(context, false, "invalid_governance_context", "治理上下文不可用")
	var memorial_id := str(selection.get("memorial_id", context.state.court_workbench_state.get("selected_memorial_id", "")))
	var council_id := str(selection.get("council_id", context.state.court_workbench_state.get("selected_governance_council_id", "")))
	var view := {"inbox": _memorials.project_inbox(context.state, context.scenario_data), "memorial": {}, "council": {}, "order": {}}
	if not memorial_id.is_empty(): view["memorial"] = _memorials.open_memorial(context.state, context.scenario_data, memorial_id).get("memorial", {})
	if not council_id.is_empty(): view["council"] = context.state.governance_state.get("councils", {}).get(council_id, {}).duplicate(true)
	var order_id := str(selection.get("order_id", ""))
	if not order_id.is_empty(): view["order"] = context.state.governance_state.get("orders", {}).get(order_id, {}).duplicate(true)
	return {"ok": true, "code": "", "feedback": "", "view": view, "rule_state_hash": context.state.rule_state_hash()}

func resume(context) -> Dictionary:
	return project(context)

func clear_transient_requests() -> void:
	_wording_adapter = Callable()

func _start_council(context, payload: Dictionary) -> Dictionary:
	var memorial_id := str(payload.get("memorial_id", "")).strip_edges()
	if _is_legacy_governance_request(context.state, memorial_id):
		return {"ok": false, "code": "legacy_governance_request_unavailable", "error": "旧请愿未包含可供朝议使用的核验事实。"}
	return GameStateTransactionScript.new().execute(context, func(working_context):
		var opened: Dictionary = _open_memorial(working_context, memorial_id)
		if not bool(opened.get("ok", false)): return opened
		var started: Dictionary = _councils.start_regular_council(working_context.state, working_context.scenario_data, memorial_id)
		if not bool(started.get("ok", false)): return started
		var council_id := str((started.get("council", {}) as Dictionary).get("council_id", ""))
		var bound: Dictionary = _memorials.bind_council(working_context.state, memorial_id, council_id)
		if not bool(bound.get("ok", false)): return bound
		var locked: Dictionary = working_context.services.time_controller.acquire_overlay_lock(working_context.state, "governance_council")
		if bool(locked.get("ok", false)): locked["council"] = started.get("council", {}).duplicate(true)
		return locked
	)

func _is_legacy_governance_request(state, memorial_id: String) -> bool:
	if state == null or memorial_id.is_empty():
		return false
	for raw_request in state.pending_requests:
		if raw_request is Dictionary and str((raw_request as Dictionary).get("request_id", "")) == memorial_id and str((raw_request as Dictionary).get("status", "pending")) == "pending":
			return true
	return false

func _open_memorial(context, memorial_id: String) -> Dictionary:
	var opened: Dictionary = _memorials.open_memorial(context.state, context.scenario_data, memorial_id)
	if not bool(opened.get("ok", false)): return opened
	context.state.court_workbench_state["selected_memorial_id"] = memorial_id
	context.state.court_workbench_state.erase("selected_governance_council_id")
	var router = context.services.get("court_workbench_router")
	if router != null and router.has_method("select_mode"): router.call("select_mode", context.state, "Memorials")
	return opened

func _back_to_inbox(context) -> Dictionary:
	var active_council_id := str(context.state.court_workbench_state.get("selected_governance_council_id", ""))
	if not active_council_id.is_empty():
		var unlocked: Dictionary = context.services.time_controller.release_overlay_lock(context.state, "governance_council")
		if not bool(unlocked.get("ok", false)): return unlocked
	context.state.court_workbench_state.erase("selected_memorial_id")
	context.state.court_workbench_state.erase("selected_governance_council_id")
	return {"ok": true}

func _record_or_continue_round(context, payload: Dictionary) -> Dictionary:
	if payload.has("turn_index"):
		return _councils.record_turn(context.state, str(payload.get("council_id", "")), int(payload.get("turn_index", -1)), str(payload.get("adviser_id", "")), payload.get("speech", {}) as Dictionary)
	return _councils.adopt_after_opening(context.state, str(payload.get("council_id", ""))) if bool(payload.get("adopt", false)) else _councils.continue_after_opening(context.state, str(payload.get("council_id", "")))

func _create_memorial_draft(context, payload: Dictionary, order_kind: String) -> Dictionary:
	var memorial_id := str(payload.get("memorial_id", context.state.court_workbench_state.get("selected_memorial_id", "")))
	var memorial: Dictionary = context.state.governance_state.get("memorials", {}).get(memorial_id, {})
	if memorial.is_empty() or str(memorial.get("status", "")) != "consulting" or not str(memorial.get("active_council_id", "")).is_empty() or not str(memorial.get("order_id", "")).is_empty(): return {"ok": false, "code": "memorial_draft_unavailable", "error": "奏折当前不能直接拟令"}
	var fields: Dictionary = (payload.get("fields", {}) as Dictionary).duplicate(true)
	fields["source_memorial_id"] = memorial_id
	fields["order_kind"] = order_kind
	fields["council_id"] = ""
	var created: Dictionary = _orders.create_draft(context.state, fields)
	if bool(created.get("ok", false)) and order_kind == "oral": created["restatement"] = _orders.prepare_oral_restatement(context.state, str(created.get("order_id", "")))
	return created

func _record_consultation_exchange(context, payload: Dictionary) -> Dictionary:
	return GameStateTransactionScript.new().execute(context, func(working_context): return _record_consultation_exchange_transaction(working_context, payload.duplicate(true)))

func _record_consultation_exchange_transaction(context, payload: Dictionary) -> Dictionary:
	var memorial_id := str(payload.get("memorial_id", "")).strip_edges()
	var adviser_id := str(payload.get("adviser_id", "")).strip_edges()
	var consultation_id := str(payload.get("consultation_id", "")).strip_edges()
	if consultation_id.is_empty():
		if memorial_id.is_empty() or adviser_id.is_empty():
			return {"ok": false, "code": "consultation_context_missing", "error": "商议需要奏折与大臣。"}
		var started: Dictionary = _memorials.start_consultation(context.state, context.scenario_data, memorial_id, adviser_id)
		if not bool(started.get("ok", false)):
			return started
		consultation_id = str(started.get("consultation_id", ""))
	else:
		var stored: Dictionary = context.state.governance_state.get("consultations", {}).get(consultation_id, {}).duplicate(true)
		if stored.is_empty() or str(stored.get("status", "")) != "open":
			return {"ok": false, "code": "consultation_unavailable", "error": "商议记录不可用或已结束。"}
		if memorial_id.is_empty():
			memorial_id = str(stored.get("memorial_id", ""))
		if str(stored.get("memorial_id", "")) != memorial_id:
			return {"ok": false, "code": "consultation_memorial_mismatch", "error": "商议与奏折不匹配。"}
		var stored_adviser_id := str(stored.get("adviser_id", ""))
		if adviser_id.is_empty():
			adviser_id = stored_adviser_id
		if adviser_id != stored_adviser_id:
			return {"ok": false, "code": "consultation_adviser_mismatch", "error": "商议大臣与既有记录不匹配。"}
	var exchange := _offline_exchange(context, memorial_id, adviser_id)
	var player_text := str(payload.get("player_text", exchange.get("player_text", ""))).replace("\n", " ").strip_edges()
	var adviser_text := str(payload.get("adviser_text", exchange.get("adviser_text", ""))).replace("\n", " ").strip_edges()
	if player_text.is_empty() or adviser_text.is_empty():
		return {"ok": false, "code": "consultation_exchange_missing", "error": "商议往返内容不可为空。"}
	var existing: Dictionary = _find_consultation_exchange(context.state, consultation_id, player_text, adviser_text)
	if not existing.is_empty():
		return {"ok": true, "code": "no_op", "consultation_id": consultation_id, "consultation": context.state.governance_state.get("consultations", {}).get(consultation_id, {}).duplicate(true), "answer_turn_id": str(existing.get("answer_turn_id", ""))}
	var adviser_name := _character_name(context.scenario_data, adviser_id)
	var source := str(payload.get("source", "offline")).strip_edges()
	var appended: Dictionary = _memorials.append_consultation_turn(context.state, consultation_id, player_text, adviser_text, adviser_name, source)
	if not bool(appended.get("ok", false)):
		return appended
	var answer_turn_id := str(appended.get("answer_turn_id", ""))
	var should_select := bool(payload.get("auto_select", true))
	var result_consultation: Dictionary = (appended.get("consultation", {}) as Dictionary).duplicate(true)
	if should_select:
		var selected: Dictionary = _memorials.set_consultation_turn_selected(context.state, consultation_id, answer_turn_id, true)
		if not bool(selected.get("ok", false)):
			return selected
		result_consultation = (selected.get("consultation", {}) as Dictionary).duplicate(true)
	return {"ok": true, "code": "consultation_exchange_recorded", "consultation_id": consultation_id, "answer_turn_id": answer_turn_id, "consultation": result_consultation}

func _save_consultation_draft(context, payload: Dictionary) -> Dictionary:
	return GameStateTransactionScript.new().execute(context, func(working_context):
		var consultation_id := str(payload.get("consultation_id", "")).strip_edges()
		if consultation_id.is_empty():
			return {"ok": false, "code": "consultation_context_missing", "error": "保存拟诏需要商议记录。"}
		var consultation: Dictionary = working_context.state.governance_state.get("consultations", {}).get(consultation_id, {}).duplicate(true)
		if consultation.is_empty() or str(consultation.get("status", "")) != "open":
			return {"ok": false, "code": "consultation_unavailable", "error": "商议记录不可用或已结束。"}
		var draft_text := str(payload.get("draft_text", "")).replace("\n", " ").strip_edges()
		if draft_text.is_empty():
			draft_text = _offline_draft_text(working_context, str(consultation.get("memorial_id", "")))
		var saved: Dictionary = _memorials.save_consultation_draft(working_context.state, consultation_id, draft_text, "manual")
		if not bool(saved.get("ok", false)):
			return saved
		return {"ok": true, "code": "consultation_draft_saved", "consultation_id": consultation_id, "consultation": saved.get("consultation", {}).duplicate(true)}
	)

func _create_consultation_decree(context, payload: Dictionary) -> Dictionary:
	return GameStateTransactionScript.new().execute(context, func(working_context): return _create_consultation_decree_transaction(working_context, payload.duplicate(true)))

func _create_consultation_decree_transaction(context, payload: Dictionary) -> Dictionary:
	var consultation_id := str(payload.get("consultation_id", "")).strip_edges()
	if consultation_id.is_empty():
		return {"ok": false, "code": "consultation_context_missing", "error": "拟诏需要商议记录。"}
	var consultation: Dictionary = context.state.governance_state.get("consultations", {}).get(consultation_id, {}).duplicate(true)
	if consultation.is_empty() or str(consultation.get("status", "")) != "open":
		return {"ok": false, "code": "consultation_unavailable", "error": "商议记录不可用或已结束。"}
	var memorial_id := str(consultation.get("memorial_id", "")).strip_edges()
	var requested_memorial_id := str(payload.get("memorial_id", memorial_id)).strip_edges()
	if memorial_id.is_empty() or requested_memorial_id != memorial_id:
		return {"ok": false, "code": "consultation_memorial_mismatch", "error": "拟诏与奏折不匹配。"}
	var selected_turn_ids: Array = consultation.get("selected_turn_ids", []) if consultation.get("selected_turn_ids", []) is Array else []
	if selected_turn_ids.is_empty():
		return {"ok": false, "code": "consultation_basis_empty", "error": "至少需要一条已选中的大臣回话作为拟诏依据。"}
	var existing_order_id := str(consultation.get("draft_order_id", "")).strip_edges()
	if not existing_order_id.is_empty():
		var existing_order: Dictionary = context.state.governance_state.get("orders", {}).get(existing_order_id, {}).duplicate(true)
		if not existing_order.is_empty() and str(existing_order.get("source_memorial_id", "")) == memorial_id and str(existing_order.get("stage", "")) == "draft":
			return {"ok": true, "code": "no_op", "order_id": existing_order_id, "memorial_id": memorial_id, "order": existing_order}
		return {"ok": false, "code": "consultation_draft_unavailable", "error": "商议已经关联了不可替换的圣旨草稿。"}
	var memorial: Dictionary = context.state.governance_state.get("memorials", {}).get(memorial_id, {}).duplicate(true)
	if memorial.is_empty() or str(memorial.get("status", "")) != "consulting" or not str(memorial.get("active_council_id", "")).is_empty() or not str(memorial.get("order_id", "")).is_empty():
		return {"ok": false, "code": "memorial_draft_unavailable", "error": "该奏折当前不能直接拟令。"}
	var draft_text := str(consultation.get("draft_text", "")).replace("\n", " ").strip_edges()
	if draft_text.is_empty():
		return {"ok": false, "code": "invalid_consultation_draft", "error": "请先保存一份有效的圣旨草稿。"}
	var fields := _consultation_draft_fields(context, consultation, memorial, draft_text)
	if fields.is_empty():
		return {"ok": false, "code": "consultation_draft_fields_unavailable", "error": "当前奏折缺少可发布的执行人与授权信息。"}
	var created: Dictionary = _orders.create_draft(context.state, fields)
	if not bool(created.get("ok", false)):
		return created
	var order_id := str(created.get("order_id", ""))
	var linked: Dictionary = _memorials.link_consultation_draft_order(context.state, consultation_id, order_id)
	if not bool(linked.get("ok", false)):
		return linked
	return {"ok": true, "code": "consultation_decree_created", "order_id": order_id, "memorial_id": memorial_id, "order": context.state.governance_state.get("orders", {}).get(order_id, {}).duplicate(true)}

func _publish_consultation_draft(context, payload: Dictionary) -> Dictionary:
	var consultation_id := str(payload.get("consultation_id", "")).strip_edges()
	var consultation: Dictionary = context.state.governance_state.get("consultations", {}).get(consultation_id, {}).duplicate(true)
	if not str(consultation.get("case_id", "")).is_empty():
		return {"ok": false, "code": "accountability_consultation_requires_case_workflow", "error": "问责口供必须从对应案卷归档。"}
	return GameStateTransactionScript.new().execute(context, func(working_context): return _publish_consultation_transaction(working_context, payload))

func _publish_consultation_transaction(context, payload: Dictionary) -> Dictionary:
	var consultation_id := str(payload.get("consultation_id", "")).strip_edges()
	var consultation: Dictionary = context.state.governance_state.get("consultations", {}).get(consultation_id, {}).duplicate(true)
	if consultation.is_empty() or str(consultation.get("status", "")) != "open":
		return {"ok": false, "code": "consultation_unavailable", "error": "商议记录不可用或已结束。"}
	if not str(consultation.get("case_id", "")).is_empty():
		return {"ok": false, "code": "accountability_consultation_requires_case_workflow", "error": "问责口供必须从对应案卷归档。"}
	var existing_order_id := str(consultation.get("draft_order_id", "")).strip_edges()
	if not existing_order_id.is_empty():
		var existing_order: Dictionary = context.state.governance_state.get("orders", {}).get(existing_order_id, {}).duplicate(true)
		if existing_order.is_empty() or str(existing_order.get("source_memorial_id", "")) != str(consultation.get("memorial_id", "")):
			return {"ok": false, "code": "consultation_draft_unavailable", "error": "商议草稿引用的圣旨与奏折不匹配。"}
		if str(existing_order.get("stage", "")) == "issued":
			return {"ok": true, "order_id": existing_order_id, "already_published": true, "order": existing_order}
		if str(existing_order.get("stage", "")) != "draft":
			return {"ok": false, "code": "consultation_draft_unavailable", "error": "商议草稿已不可发布。"}
	var memorial_id := str(consultation.get("memorial_id", "")).strip_edges()
	var memorial: Dictionary = context.state.governance_state.get("memorials", {}).get(memorial_id, {}).duplicate(true)
	if memorial.is_empty() or str(memorial.get("status", "")) != "consulting" or not str(memorial.get("active_council_id", "")).is_empty() or not str(memorial.get("order_id", "")).is_empty():
		return {"ok": false, "code": "memorial_draft_unavailable", "error": "该奏折当前不能直接发布圣旨。"}
	var draft_text := str(consultation.get("draft_text", "")).replace("\n", " ").strip_edges()
	if draft_text.is_empty() or draft_text.length() > 1200:
		return {"ok": false, "code": "invalid_consultation_draft", "error": "请先保存一份有效的圣旨草稿。"}
	var order_id := existing_order_id
	if order_id.is_empty():
		var fields := _consultation_draft_fields(context, consultation, memorial, draft_text)
		if fields.is_empty():
			return {"ok": false, "code": "consultation_draft_fields_unavailable", "error": "当前奏折缺少可发布的执行人与授权信息。"}
		var created: Dictionary = _orders.create_draft(context.state, fields)
		if not bool(created.get("ok", false)):
			return created
		order_id = str(created.get("order_id", ""))
		var linked := _memorials.link_consultation_draft_order(context.state, consultation_id, order_id)
		if not bool(linked.get("ok", false)):
			return linked
	var preview: Dictionary = _orders.preview_direct_edict(context.state, order_id)
	if not bool(preview.get("ok", false)):
		return preview
	if not bool(preview.get("can_seal", false)):
		return {"ok": false, "code": "command_conflict", "error": "圣旨与现有资源或执行安排冲突，请先处理冲突。", "conflicts": preview.get("conflicts", []), "order_id": order_id}
	var sealed := _seal(context, {"order_id": order_id, "preview_token": str(preview.get("preview_token", ""))})
	if not bool(sealed.get("ok", false)):
		return sealed
	return {"ok": true, "order_id": order_id, "memorial_id": memorial_id, "published": true, "order": context.state.governance_state.get("orders", {}).get(order_id, {}).duplicate(true)}

func _consultation_draft_fields(context, consultation: Dictionary, memorial: Dictionary, draft_text: String) -> Dictionary:
	var topic := str(memorial.get("topic", ""))
	var rule: Dictionary = _consultation_execution_rule(context, topic)
	var authorized_action_id := str(rule.get("action_id", "")).strip_edges()
	var requested_action := str(consultation.get("recommended_action", "")).strip_edges()
	if authorized_action_id.is_empty() or (not requested_action.is_empty() and requested_action != authorized_action_id):
		return {}
	var stored_offices: Variant = consultation.get("required_offices", [])
	var required_offices: Array = []
	if stored_offices is Array and not (stored_offices as Array).is_empty():
		required_offices = (stored_offices as Array).duplicate(true)
	elif rule.get("required_offices", []) is Array:
		required_offices = (rule.get("required_offices", []) as Array).duplicate(true)
	var executors: Array = memorial.get("recommended_executor_ids", []) if memorial.get("recommended_executor_ids", []) is Array else []
	if executors.is_empty():
		var defaults: Dictionary = _beta110_execution_defaults(context, topic)
		executors = defaults.get("recommended_executor_ids", []) as Array if defaults.get("recommended_executor_ids", []) is Array else []
	var recipient_id := str(executors[0]) if not executors.is_empty() else str(consultation.get("adviser_id", ""))
	var adviser_id := str(consultation.get("adviser_id", ""))
	var assistant_ids: Array = []
	for raw_executor_id in executors:
		var executor_id := str(raw_executor_id).strip_edges()
		if not executor_id.is_empty() and executor_id != recipient_id and not assistant_ids.has(executor_id):
			assistant_ids.append(executor_id)
	if not adviser_id.is_empty() and adviser_id != recipient_id and not assistant_ids.has(adviser_id):
		assistant_ids.append(adviser_id)
	if recipient_id.is_empty() or not context.state.character_states.has(recipient_id):
		if not adviser_id.is_empty() and context.state.character_states.has(adviser_id):
			recipient_id = adviser_id
		else:
			for assistant_id in assistant_ids:
				if context.state.character_states.has(str(assistant_id)):
					recipient_id = str(assistant_id)
					break
	if recipient_id.is_empty():
		return {}
	var authority_tags := _authority_tags_for_participants(context.state, recipient_id, assistant_ids, required_offices)
	if authority_tags.is_empty():
		authority_tags = _authority_tags_for_participants(context.state, recipient_id, assistant_ids, [])
	if authority_tags.is_empty():
		for office_id in context.state.office_state.keys():
			var office: Dictionary = context.state.office_state[office_id] as Dictionary
			var holder_id := str(office.get("holder_id", ""))
			if str(office.get("status", "")) == "appointed" and not holder_id.is_empty():
				var holder_tags: Array = office.get("authority_tags", [])
				if not holder_tags.is_empty():
					if not assistant_ids.has(holder_id) and holder_id != recipient_id:
						assistant_ids.append(holder_id)
					for tag in holder_tags:
						if not str(tag).is_empty() and not authority_tags.has(str(tag)):
							authority_tags.append(str(tag))
	if authority_tags.is_empty():
		authority_tags = ["execute"]
	var resources: Dictionary = consultation.get("required_resources", {}) if consultation.get("required_resources", {}) is Dictionary else {}
	if resources.is_empty():
		var resource_keys: Array = memorial.get("resource_keys", []) if memorial.get("resource_keys", []) is Array else []
		if resource_keys.is_empty():
			var defaults: Dictionary = _beta110_execution_defaults(context, topic)
			resource_keys = defaults.get("resource_keys", []) as Array if defaults.get("resource_keys", []) is Array else []
		for raw_key in resource_keys:
			var resource_key := str(raw_key)
			if not resource_key.is_empty() and context.state.resources.has(resource_key):
				resources[resource_key] = maxi(mini(int(context.state.resources.get(resource_key, 0)), 10), 1)
	if resources.is_empty():
		resources["grain"] = maxi(mini(int(context.state.resources.get("grain", 10)), 10), 1)
	var report_due_day := maxi(int(consultation.get("deadline_day", 0)), int(context.state.current_day) + 1)
	var first_loop: Variant = context.scenario_data.get("first_political_loop", {})
	if first_loop is Dictionary and str((first_loop as Dictionary).get("memorial_id", "")) == str(memorial.get("memorial_id", "")):
		var first_loop_offset := int((first_loop as Dictionary).get("report_due_day_offset", 0))
		if first_loop_offset <= 0:
			return {}
		report_due_day = int(context.state.current_day) + first_loop_offset
	var drafting_office_id := _office_id_by_category(context.state, "drafting")
	var reviewing_office_id := _office_id_by_category(context.state, "review")
	if drafting_office_id.is_empty() and not required_offices.is_empty():
		drafting_office_id = str(required_offices[0])
	if reviewing_office_id.is_empty():
		reviewing_office_id = str(required_offices[1] if required_offices.size() > 1 else (required_offices[0] if not required_offices.is_empty() else drafting_office_id))
	var location_id := str(consultation.get("location_id", memorial.get("location_id", "")))
	if location_id.is_empty() or not context.state.local_node_state.has(location_id):
		location_id = "lingwu_court_node"
	return {
		"source_memorial_id": str(memorial.get("memorial_id", "")), "order_kind": "edict", "council_id": "",
		"recipient_id": recipient_id, "assistant_ids": assistant_ids, "action_id": authorized_action_id,
		"location_id": location_id, "resources": resources.duplicate(true),
		"authority_tags": authority_tags.slice(0, 1), "required_office_id": str(required_offices[0]) if not required_offices.is_empty() else "",
		"report_due_day": report_due_day, "drafted_by_office_id": drafting_office_id, "reviewed_by_office_id": reviewing_office_id,
		"seal_status": "ready", "player_supplement": "经指定大臣商议后拟定。", "edict_text": draft_text,
		"edict_basis": (consultation.get("selected_turn_ids", []) as Array).duplicate(true) if consultation.get("selected_turn_ids", []) is Array else [],
		"revision": 0, "preview_token": ""
	}

func _consultation_execution_rule(context, topic: String) -> Dictionary:
	var rule: Dictionary = {}
	var governance: Variant = context.scenario_data.get("governance", {})
	if governance is Dictionary:
		var topic_rules: Variant = (governance as Dictionary).get("topic_rules", {})
		if topic_rules is Dictionary and (topic_rules as Dictionary).get(topic, {}) is Dictionary:
			rule = ((topic_rules as Dictionary).get(topic, {}) as Dictionary).duplicate(true)
	var defaults := _beta110_execution_defaults(context, topic)
	if defaults.is_empty():
		return rule
	var merged := defaults.duplicate(true)
	merged.merge(rule, true)
	if str(rule.get("action_id", "")).strip_edges().is_empty():
		merged["action_id"] = defaults.get("action_id", "")
	for field in ["required_offices", "recommended_executor_ids", "resource_keys"]:
		var configured: Variant = rule.get(field, [])
		if not configured is Array or (configured as Array).is_empty():
			merged[field] = (defaults.get(field, []) as Array).duplicate(true) if defaults.get(field, []) is Array else []
	return merged

func _beta110_execution_defaults(context, topic: String) -> Dictionary:
	var defaults: Variant = context.scenario_data.get("beta110_execution_defaults", {})
	if defaults is Dictionary and (defaults as Dictionary).get(topic, {}) is Dictionary:
		return ((defaults as Dictionary).get(topic, {}) as Dictionary).duplicate(true)
	return {}

func _authority_tags_for_participants(state, recipient_id: String, assistant_ids: Array, preferred_offices: Array) -> Array:
	var participants: Array = [recipient_id]
	for assistant_id in assistant_ids:
		if not participants.has(str(assistant_id)):
			participants.append(str(assistant_id))
	var tags: Array = []
	for raw_office in state.office_state.values():
		if not raw_office is Dictionary:
			continue
		var office: Dictionary = raw_office
		if not preferred_offices.is_empty() and not preferred_offices.has(str(office.get("office_id", ""))):
			continue
		if not participants.has(str(office.get("holder_id", ""))):
			continue
		for raw_tag in office.get("authority_tags", []):
			var tag := str(raw_tag)
			if not tag.is_empty() and not tags.has(tag):
				tags.append(tag)
	if not tags.is_empty():
		return tags
	if not preferred_offices.is_empty():
		return []
	for raw_office in state.office_state.values():
		if raw_office is Dictionary and participants.has(str((raw_office as Dictionary).get("holder_id", ""))):
			for raw_tag in (raw_office as Dictionary).get("authority_tags", []):
				var tag := str(raw_tag)
				if not tag.is_empty() and not tags.has(tag):
					tags.append(tag)
	return tags

func _office_id_by_category(state, category: String) -> String:
	for raw_office in state.office_state.values():
		if raw_office is Dictionary and str((raw_office as Dictionary).get("category", "")) == category:
			return str((raw_office as Dictionary).get("office_id", ""))
	return ""

func _preview_edict(context, order_id: String) -> Dictionary:
	var order: Dictionary = context.state.governance_state.get("orders", {}).get(order_id, {})
	if order.is_empty(): return {"ok": false, "code": "order_unavailable", "error": "拟令不可用"}
	return _orders.preview_council_edict(context.state, order_id) if not str(order.get("council_id", "")).is_empty() else _orders.preview_direct_edict(context.state, order_id)

func _generate_edict(context, payload: Dictionary) -> Dictionary:
	var council_id := str(payload.get("council_id", ""))
	if not payload.has("edict_text"):
		return _councils.begin_drafting(context.state, council_id)
	var council: Dictionary = context.state.governance_state.get("councils", {}).get(council_id, {}).duplicate(true)
	if council.is_empty() or str(council.get("status", "")) != "active" or str(council.get("phase", "")) != "drafting" or not str(council.get("draft_order_id", "")).is_empty(): return {"ok": false, "code": "drafting_unavailable", "error": "当前朝议不能拟旨"}
	council["edict_text"] = str(payload.get("edict_text", "")).strip_edges()
	context.state.governance_state["councils"][council_id] = council
	return _orders.create_council_draft(context.state, council, payload.get("fields", {}) as Dictionary)

func _seal_transaction(context, payload: Dictionary) -> Dictionary:
	return GameStateTransactionScript.new().execute(context, func(working_context): return _seal(working_context, payload.duplicate(true)))

func _confirm_oral_transaction(context, payload: Dictionary) -> Dictionary:
	return GameStateTransactionScript.new().execute(context, func(working_context):
		var plan: Dictionary = _orders.build_oral_seal_plan(working_context.state, str(payload.get("order_id", "")), str(payload.get("summary_hash", "")))
		return _seal(working_context, {"order_id": str(payload.get("order_id", "")), "seal_plan": plan})
	)

func _seal(working_context, payload: Dictionary) -> Dictionary:
	var order_id := str(payload.get("order_id", ""))
	var seal_plan: Dictionary = payload.get("seal_plan", {}) as Dictionary
	if seal_plan.is_empty(): seal_plan = _orders.build_seal_plan(working_context.state, order_id, str(payload.get("preview_token", "")))
	if not bool(seal_plan.get("ok", false)): return seal_plan
	if str((seal_plan.get("order", {}) as Dictionary).get("order_kind", "edict")) == "edict" and str(seal_plan.get("council_id", "")).is_empty() and (str(payload.get("preview_token", "")).is_empty() or str(payload.get("preview_token", "")) != str((seal_plan.get("order", {}) as Dictionary).get("preview_token", ""))): return {"ok": false, "code": "stale_preview", "error": "御批预览已过期"}
	var memorial_id := str(seal_plan.get("memorial_id", ""))
	if memorial_id.is_empty(): return {"ok": false, "code": "sealed_order_missing_memorial"}
	var council_id := str(seal_plan.get("council_id", ""))
	if not council_id.is_empty():
		var persist_fault := _fault("persist_council")
		if not bool(persist_fault.get("ok", false)): return persist_fault
		var sealed: Dictionary = _councils.mark_sealed(working_context.state, council_id, order_id)
		if not bool(sealed.get("ok", false)): return sealed
	var bind_fault := _fault("bind_memorial")
	if not bool(bind_fault.get("ok", false)): return bind_fault
	var bound: Dictionary = _memorials.bind_decree(working_context.state, memorial_id, order_id)
	if not bool(bound.get("ok", false)): return bound
	var issued: Dictionary = _orders.apply_seal_plan(working_context.state, seal_plan, _seal_fault_injector)
	if not bool(issued.get("ok", false)): return issued
	var release_fault := _fault("release_pause_lock")
	if not bool(release_fault.get("ok", false)): return release_fault
	var unlocked: Dictionary = working_context.services.time_controller.release_overlay_lock(working_context.state, "governance_council")
	if not bool(unlocked.get("ok", false)): return unlocked
	return {"ok": true, "order_id": order_id, "memorial_id": memorial_id}

func _offline_exchange(context, memorial_id: String, adviser_id: String) -> Dictionary:
	var loop: Variant = context.scenario_data.get("first_political_loop", {})
	if loop is Dictionary and str((loop as Dictionary).get("memorial_id", "")) == memorial_id:
		var configured: Variant = (loop as Dictionary).get("offline_exchange", {})
		if configured is Dictionary:
			return (configured as Dictionary).duplicate(true)
	var memorial: Dictionary = context.state.governance_state.get("memorials", {}).get(memorial_id, {})
	var topic := str(memorial.get("topic", ""))
	var rule: Dictionary = _consultation_execution_rule(context, topic)
	return {
		"player_text": str(rule.get("opening_question", "请说明此事的事实、风险与处置次序。")),
		"adviser_text": "先核验已知账册与收讫记录，再按期限执行并具报。",
		"adviser_name": _character_name(context.scenario_data, adviser_id)
	}

func _offline_draft_text(context, memorial_id: String) -> String:
	var loop: Variant = context.scenario_data.get("first_political_loop", {})
	if loop is Dictionary and str((loop as Dictionary).get("memorial_id", "")) == memorial_id:
		return str((loop as Dictionary).get("offline_draft_text", "")).strip_edges()
	var rendered: Dictionary = GovernanceAdvicePresenterScript.new().render_offline_edict({"memorial_id": memorial_id})
	var rendered_text := str(rendered.get("text", "")).strip_edges()
	return rendered_text if not rendered_text.is_empty() else "奉旨：核验事实、按授权执行，限期具报。"

func _find_consultation_exchange(state, consultation_id: String, player_text: String, adviser_text: String) -> Dictionary:
	var consultation: Dictionary = state.governance_state.get("consultations", {}).get(consultation_id, {})
	var turns: Array = consultation.get("turns", []) if consultation.get("turns", []) is Array else []
	for index in range(turns.size() - 1):
		if not turns[index] is Dictionary or not turns[index + 1] is Dictionary:
			continue
		var player_turn: Dictionary = turns[index]
		var adviser_turn: Dictionary = turns[index + 1]
		if str(player_turn.get("speaker", "")) == "player" and str(adviser_turn.get("speaker", "")) == "adviser" and str(player_turn.get("text", "")) == player_text and str(adviser_turn.get("text", "")) == adviser_text:
			return {"answer_turn_id": str(adviser_turn.get("turn_id", ""))}
	return {}

func _character_name(data: Dictionary, character_id: String) -> String:
	for raw_character in data.get("characters", []) if data.get("characters", []) is Array else []:
		if raw_character is Dictionary and str((raw_character as Dictionary).get("id", "")) == character_id:
			return str((raw_character as Dictionary).get("name", character_id))
	return character_id

func _fault(stage: String) -> Dictionary:
	if not _seal_fault_injector.is_valid(): return {"ok": true}
	var result: Variant = _seal_fault_injector.call(stage)
	return result as Dictionary if result is Dictionary else {"ok": false, "code": "invalid_seal_fault_injector"}

func _result(context, ok: bool, code: String, feedback: String, extra: Dictionary = {}) -> Dictionary:
	var result := {"ok": ok, "code": code, "feedback": feedback, "view": {}, "rule_state_hash": context.state.rule_state_hash() if context != null and context.state != null else ""}
	for key in extra.keys(): result[key] = extra[key]
	return result
