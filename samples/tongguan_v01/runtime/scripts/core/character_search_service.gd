extends RefCounted
const Contract = preload("res://scripts/core/management_state_contract.gd")
const Presence = preload("res://scripts/core/production_service.gd")
const Workload = preload("res://scripts/core/character_workload_service.gd")
const KINDS := ["start_character_search", "finish_character_search", "resolve_character_search"]

static func cost_for(state, kind: String, params: Dictionary) -> Dictionary:
	if not params.get("search_id") is String or str(params.search_id).is_empty(): return Contract.fail("寻访须有稳定标识")
	if kind == "start_character_search":
		if not state.local_node_state.has(params.get("location_id")) or not params.get("archetype_id") is String or not params.get("target_role") is String or str(params.target_role).is_empty() or not params.get("specialty") is String or not Contract.amount(params.get("duration_days"), true): return Contract.fail("寻访需要实际地点、目标与工日")
		var valid: Dictionary = preload("res://scripts/core/entrustment_capability_registry.gd").new().validate_arguments("find_person_and_introduce", {"archetype_id": params.archetype_id, "quantity": 1})
		if not valid.get("ok", false): return valid
	elif state.economic_contracts.get(params.search_id, {}).get("contract_kind") != "character_search": return {"ok": false, "code": "asset_not_ready", "error": "尚无该项寻访委托"}
	# This rule is local, voluntary introduction work: no travel purchases or cash grants.
	return {"ok": true, "account_id": "", "amount": 0}

static func location_for(state, kind: String, params: Dictionary) -> String:
	return str(params.get("location_id", "")) if kind == "start_character_search" else str(state.economic_contracts.get(params.get("search_id"), {}).get("location_id", ""))

static func apply(state, kind: String, params: Dictionary, principal: String, executor: String, execution: String, authorization_id: String = "") -> Dictionary:
	if kind == "start_character_search":
		if state.economic_contracts.has(params.search_id): return Contract.fail("寻访标识已使用")
		if not Workload.can_schedule(state, executor, "character_search", principal): return Contract.fail("经办人的现职没有空闲寻访日，须改派经办人或先办理交接")
		if state.economic_contracts.values().any(func(order): return order.get("contract_kind") == "character_search" and order.get("executor_id") == executor and order.get("status") == "working"): return Contract.fail("经办人仍有正在履行的寻访，请先完成原委托")
		var seed := (str(execution).sha256_text().substr(0, 7).hex_to_int() + int(state.flags.get("rule_seed", 107))) & 0x7fffffff
		var plan := {"capability_id": "find_person_and_introduce", "target_type": "character", "target_archetype": params.archetype_id, "target_role": params.target_role, "specialty": params.specialty, "task_name": "寻访" + params.target_role, "due_days": int(params.duration_days)}
		var legacy = load("res://scripts/core/private_entrustment_service.gd").new()
		var created: Dictionary = legacy.create_entrustment_task(state, plan, executor, principal, seed, false)
		if not created.get("ok", false): return created
		created.task.id = params.search_id
		created.task.task_id = params.search_id
		state.economic_contracts[params.search_id] = {"contract_id": params.search_id, "contract_kind": "character_search", "status": "working", "terms_version": 1, "party_refs": [principal, executor], "principal_id": principal, "executor_id": executor, "authorization_id": authorization_id, "location_id": params.location_id, "created_day": int(state.current_day), "duration_days": int(params.duration_days), "work_days": 0, "last_work_day": int(state.current_day), "start_receipt": execution, "resolution_receipts": [], "finish_receipt": "", "candidate_id": "", "attempt": 0, "failure_history": [], "search_state": created.task, "original_plan": plan, "seed": seed, "blocked_reason": ""}
		state.economic_contracts[params.search_id]["work_log"] = []
		return {"ok": true, "result_ref": params.search_id}
	var order: Dictionary = state.economic_contracts[params.search_id]
	if order.principal_id != principal: return Contract.fail("无权处置他人的寻访结果")
	if kind == "finish_character_search":
		if order.status in ["working", "awaiting_choice"]: return {"ok": false, "code": "awaiting_delivery", "error": "寻访尚在进行，或引见结果仍待实际处置。"}
		if order.status != "resolved": return Contract.fail("寻访未达成引见处置，须查阅失败原因并重试或取消，不能宣称完成")
		order.status = "completed"
		order.finish_receipt = execution
		return {"ok": true, "result_ref": order.contract_id}
	var choice := str(params.get("choice", ""))
	if choice == "retry_search":
		if order.status != "failed": return Contract.fail("只有确有失败回报的寻访可以重试")
		if order.authorization_id != "" and state.action_authorizations.get(order.authorization_id, {}).get("status") != "active": return Contract.fail("原授权已结束，继续寻访须重新委托")
		var deadline: Variant = state.action_authorizations.get(order.authorization_id, {}).get("valid_until_day")
		if deadline != null and int(state.current_day) > int(deadline): return Contract.fail("已超过原授权截止日，须先调整期限")
		order.failure_history.append({"attempt": order.attempt, "day": int(state.current_day), "outcome_code": order.search_state.outcome_code, "feedback": order.search_state.visible_feedback.duplicate(true)})
		order.attempt += 1
		var renewed: Dictionary = load("res://scripts/core/private_entrustment_service.gd").new().create_entrustment_task(state, order.original_plan, order.executor_id, principal, int(order.seed) + int(order.attempt) * 37, false)
		if not renewed.get("ok", false): return renewed
		renewed.task.id = order.contract_id
		renewed.task.task_id = order.contract_id
		order.search_state = renewed.task
		order.status = "working"
		order.work_days = 0
		order.last_work_day = int(state.current_day)
		order.blocked_reason = ""
		for task in state.active_tasks:
			if task.get("authorization_id", "") == order.authorization_id and order.authorization_id != "" and task.get("status") == "blocked" and task.get("steps", []).any(func(step): return step.get("action_kind") == "finish_character_search" and step.get("parameters", {}).get("search_id") == order.contract_id and step.get("status") != "completed"):
				var resumed: Dictionary = load("res://scripts/core/action_authorization_service.gd").retry_task(state, task)
				if not resumed.get("ok", false): return resumed
	else:
		if order.status != "awaiting_choice" or choice not in ["accept_retainer", "decline_politely", "inquire_test"]: return Contract.fail("当前没有与此处置相符的实际引见")
		var candidate: Dictionary = state.character_states.get(order.candidate_id, {})
		if not Presence.present(state, order.candidate_id, order.location_id) or not Presence.present(state, principal, order.location_id): return Contract.fail("委托人或实际人选未到引见地点")
		if choice == "accept_retainer" and (str(candidate.get("patron_id", "")) not in ["", principal] or int(candidate.get("relationships", {}).get(principal, 0)) < -15): return Contract.fail("人选已有其他效力约定或不愿受聘")
		var result: Dictionary = load("res://scripts/core/private_entrustment_service.gd").new().apply_candidate_choice(state, order.search_state, choice)
		if not result.get("ok", false): return result
		if choice != "inquire_test": order.status = "resolved"
	order.resolution_receipts.append(execution)
	return {"ok": true, "result_ref": order.contract_id}

static func settle_daily(state) -> Dictionary:
	for order in state.economic_contracts.values():
		if order.get("contract_kind") != "character_search" or order.status != "working" or int(order.last_work_day) >= int(state.current_day): continue
		if order.authorization_id != "":
			var auth: Dictionary = state.action_authorizations.get(order.authorization_id, {})
			if auth.get("status") != "active":
				order.status = "cancelled"
				order.blocked_reason = "授权已结束，停止尚未完成的寻访。"
				continue
			if auth.valid_until_day != null and int(state.current_day) > int(auth.valid_until_day):
				order.blocked_reason = "已超过玩家明确的截止日，等待重新商定。"
				continue
		if not Presence.present(state, order.executor_id, order.location_id):
			order.blocked_reason = "经办人离场或无法履职，寻访暂停。"
			continue
		if Workload.occupied_today(state, order.executor_id, order.contract_id, order.principal_id, "character_search"):
			order.blocked_reason = "经办人今日已履行另一项义务，下一日继续。"
			continue
		order.blocked_reason = ""
		Workload.record_work(state, order)
		if int(order.work_days) < int(order.duration_days): continue
		order.search_state.due_day = int(state.current_day)
		var settled: Dictionary = load("res://scripts/core/private_entrustment_service.gd").new().settle_task(state, order.search_state)
		if not settled.get("ok", false): return settled
		order.candidate_id = str(order.search_state.get("candidate_character_id", ""))
		order.status = "failed" if order.candidate_id.is_empty() else "awaiting_choice"
		if not order.candidate_id.is_empty():
			state.character_states[order.candidate_id]["location_id"] = order.location_id
			state.character_states[order.candidate_id]["search_source_ref"] = order.contract_id
	return {"ok": true}
