extends RefCounted
const Contract = preload("res://scripts/core/management_state_contract.gd")
const Production = preload("res://scripts/core/production_service.gd")
const Authorization = preload("res://scripts/core/action_authorization_service.gd")
const Canonical = preload("res://scripts/core/canonical_json.gd")

static func applies(plan: Dictionary) -> bool:
	if plan.get("capability_id") in ["craft_item", "compile_or_process_work", "find_person_and_introduce"] or plan.get("target_type") in ["item", "manuscript", "character"]: return true
	return plan.get("steps", []).any(func(step): return step.get("capability_id") in ["craft_item", "compile_or_process_work", "find_person_and_introduce"])

static func quote(state, plan: Dictionary, executor: String, session: String, version: int) -> Dictionary:
	var principal: String = state.player_character_id
	var place := str(state.character_states.get(principal, {}).get("location_id", ""))
	if not Production.present(state, principal, place) or not Production.present(state, executor, place): return Contract.fail("委托人与经办人须实际在场，才能商定托付条款。")
	var goals: Array = plan.get("steps", []).duplicate(true)
	if goals.is_empty(): goals = [{"step_id": "production", "capability_id": plan.get("capability_id", "find_person_and_introduce" if plan.get("target_type") == "character" else ("compile_or_process_work" if plan.get("target_type") == "manuscript" else "craft_item")), "arguments": plan.duplicate(true)}]
	var steps: Array = []
	var quotes: Array = []
	var searches: Array = []
	var kinds: Array = []
	var targets: Array = []
	var names: Array[String] = []
	var total := 0
	var work_days := 0
	var previous := ""
	var task_id := "dialogue-production:%s:%d" % [session, version]
	var budget: Dictionary = plan.get("budget", {}).duplicate(true)
	var instruction := str(plan.get("proposal_player_text", ""))
	if ["不许花钱", "不花钱", "不费分文", "不给钱", "零预算"].any(func(marker): return instruction.contains(marker)): budget["amount"] = 0
	var amount_pattern := RegEx.new()
	amount_pattern.compile("(?:不超过|不得超过|最多|至多|预算(?:上限)?)[：:\\s]*([0-9零〇一二两三四五六七八九十百千万]+)")
	var ceilings := amount_pattern.search_all(instruction)
	if ceilings.size() > 1: return Contract.fail("出现多个预算条件，请明确本次累计金额。")
	if ceilings.size() == 1:
		budget["amount"] = load("res://scripts/ai/assistant_plan_parser.gd").new()._instruction_amount(ceilings[0].get_string(1))
	if instruction.contains("家族公账") or instruction.contains("家族主账户"):
		var family: Array = state.resource_accounts.values().filter(func(account): return account.unit_id == "cash_unit" and account.owner_ref == {"entity_kind": "clan", "entity_id": state.flags.get("player_organization_id")})
		if family.size() != 1: return Contract.fail("未找到唯一的本人家族公账，请明确付款账户。")
		budget["account_id"] = family[0].account_id
	var account := str(budget.get("account_id", principal + "_cash"))
	for goal in goals:
		if goal.get("capability_id") not in ["craft_item", "compile_or_process_work", "find_person_and_introduce"]: return Contract.fail("计划含尚无共同动作执行器的步骤，不能丢掉该步后办理其余部分。")
		var args: Dictionary = goal.get("arguments", {})
		var quantity: Variant = args.get("quantity", args.get("volume_count", 1))
		if not Contract.amount(quantity, true) or int(quantity) != 1 or args.get("is_plural", false): return Contract.fail("请列明逐件生产的整数数量与要求，不能把多件或分数数量当作一件交付。")
		if goal.capability_id == "find_person_and_introduce":
			if str(args.get("source_org", "")) != "": return Contract.fail("指定营伍或组织的人事调取须先核实原属关系，当前不能把当地寻访当作兵员划拨。")
			var archetype := str(args.get("archetype_id", args.get("target_archetype", "generic_retainer")))
			var labels := {"physician_retainer": "郎中", "finance_retainer": "账房", "governance_retainer": "治事门客", "strategist_retainer": "谋士", "assassin_retainer": "武勇门客"}
			var role := str(args.get("target_role", labels.get(archetype, "可用门客")))
			var search_id := "search:%s:%s:%d" % [principal, task_id, steps.size()]
			var parameters := {"search_id": search_id, "location_id": place, "archetype_id": archetype, "target_role": role, "specialty": str(args.get("specialty", "")), "duration_days": args.get("due_days", 3)}
			var supported: Dictionary = preload("res://scripts/core/character_search_service.gd").cost_for(state, "start_character_search", parameters)
			if not supported.get("ok", false): return supported
			var start_id := "search_%d" % steps.size()
			var finish_id := "introduce_%d" % steps.size()
			steps.append({"step_id": start_id, "action_kind": "start_character_search", "parameters": parameters, "target_refs": [place], "depends_on": [] if previous.is_empty() else [previous]})
			steps.append({"step_id": finish_id, "action_kind": "finish_character_search", "parameters": {"search_id": search_id}, "target_refs": [search_id], "depends_on": [start_id]})
			previous = finish_id
			for target in [place, search_id]:
				if not targets.has(target): targets.append(target)
			for kind in ["start_character_search", "finish_character_search"]:
				if not kinds.has(kind): kinds.append(kind)
			searches.append(parameters.duplicate(true))
			work_days += int(parameters.duration_days) + 2
			names.append("当地寻访%s：%d 个工作日，不另收现金；线索不保证成功，引见后再决定是否纳用" % [role, int(parameters.duration_days)])
			continue
		var found := _find_quote(state, args, str(goal.capability_id), place)
		if not found.ok: return found
		var workshop: Dictionary = found.workshop
		var recipe: Dictionary = found.recipe
		var index := steps.size()
		var order_id := "production:%s:%s:%d" % [principal, task_id, index]
		var commission_id := "order_%d" % index
		var collection_id := "collect_%d" % index
		steps.append({"step_id": commission_id, "action_kind": "commission_production", "parameters": {"workshop_id": workshop.asset_id, "recipe_id": found.recipe_id, "funding_account_id": account, "order_id": order_id}, "target_refs": [workshop.asset_id], "depends_on": [] if previous.is_empty() else [previous]})
		steps.append({"step_id": collection_id, "action_kind": "collect_production", "parameters": {"order_id": order_id}, "target_refs": [order_id], "depends_on": [commission_id]})
		previous = collection_id
		for kind in ["commission_production", "collect_production"]:
			if not kinds.has(kind): kinds.append(kind)
		for target in [workshop.asset_id, order_id]:
			if not targets.has(target): targets.append(target)
		quotes.append({"workshop_id": workshop.asset_id, "recipe_id": found.recipe_id, "recipe": recipe.duplicate(true)})
		total += int(recipe.price)
		work_days += int(recipe.duration_days) + 2
		names.append("%s：%d 钱，%d 个工作日%s" % [recipe.output_definition.name, int(recipe.price), int(recipe.duration_days), "，底本《" + str(state.management_assets[recipe.source_work_id].get("name", "现有底本")) + "》" if recipe.source_work_id != "" else ""])
	var limit: Variant = budget.get("amount", budget.get("max_amount", total))
	if not Contract.amount(limit) or int(limit) < total: return Contract.fail("所议预算不足：实际报价合计 %d 钱，须调整范围或金额。" % total)
	var deadline: Dictionary = plan.get("deadline", {}).duplicate(true)
	var spoken_deadline: Dictionary = preload("res://scripts/ai/generic_entrustment_slot_extractor.gd").new().extract_deadline(instruction, int(state.current_day))
	if spoken_deadline.get("mentioned", false) and not spoken_deadline.get("is_vague", true): deadline = spoken_deadline
	var until: Variant = null
	if deadline.has("exact_days"):
		if not Contract.amount(deadline.exact_days, true): return Contract.fail("明确期限须为正整数日数。")
		if int(deadline.exact_days) < work_days: return Contract.fail("所议期限不足以完成实际工序与经办，至少预留 %d 日。" % work_days)
		until = int(deadline.target_day) if deadline.get("is_absolute_day", false) else int(state.current_day) + int(deadline.exact_days)
		if int(until) <= int(state.current_day): return Contract.fail("明确截止日已经过去，请重新核对期限。")
	var auth := {"authorization_id": "authorization:" + task_id, "principal_id": principal, "delegate_id": executor, "version": 1, "status": "active", "valid_until_day": until, "scope": {"action_kinds": kinds, "target_refs": targets, "allow_subdelegation": false}, "resource_limits": [{"account_id": account, "amount": int(limit), "unit_id": "cash_unit"}] if int(limit) > 0 else []}
	var valid := Authorization.validate_authorization(state, auth)
	if not valid.ok: return valid
	var executable := {"task_id": task_id, "name": str(plan.get("task_name", "代办生产与领取")), "executor_id": executor, "steps": steps}
	valid = Authorization.validate_plan(state, auth, executable)
	if not valid.ok: return valid
	var account_name := "本人私款" if account == principal + "_cash" else ("家族公账" if state.resource_accounts[account].owner_ref.entity_kind == "clan" else "国帑")
	var payment := "本次不另收现金。" if int(limit) == 0 else "使用%s；累计上限 %d 钱，实际报价合计 %d 钱。" % [account_name, int(limit), total]
	var delivery := "" if quotes.is_empty() else "产物完工后由经办人领取；已付款订单不会因取消代办而退款。"
	return {"ok": true, "proposal": {"authority_terms": auth, "plan": executable, "quotes": quotes, "searches": searches, "summary": "%s。%s%s%s" % ["；".join(names), payment, delivery, "未指定截止日。" if until == null else "截止第 %d 日。" % int(until)]}}

static func _find_quote(state, args: Dictionary, capability: String, place: String) -> Dictionary:
	var matches: Array = []
	var wanted := str(args.get("target_item", args.get("item_name", args.get("target_name", ""))))
	var source := str(args.get("source_work_id", ""))
	for workshop in state.management_assets.values():
		if workshop.get("asset_kind") != "workshop" or workshop.get("offer_visibility") != "public" or str(workshop.location_id).trim_suffix("_node") != place.trim_suffix("_node"): continue
		if args.get("workshop_id", workshop.asset_id) != workshop.asset_id: continue
		for recipe_id in workshop.recipes:
			var recipe: Dictionary = workshop.recipes[recipe_id]
			if args.has("recipe_id"):
				if args.recipe_id != recipe_id: continue
			else:
				if capability == "compile_or_process_work" and recipe.source_work_id == "": continue
				if source.is_empty() and (wanted.length() < 2 or not str(recipe.output_definition.name).contains(wanted)): continue
			if not source.is_empty() and recipe.source_work_id != source: continue
			matches.append({"ok": true, "workshop": workshop, "recipe": recipe, "recipe_id": recipe_id})
	if matches.size() != 1: return Contract.fail("尚无唯一且有真实材料/底本的当地报价符合所托物品，请明确现有工坊报价或已有底本；不能凭描述制造成品。")
	return matches[0]

static func validate_quotes(state, proposal: Dictionary) -> Dictionary:
	if not proposal.get("authority_terms") is Dictionary or not proposal.get("plan") is Dictionary or not proposal.get("quotes") is Array or (proposal.quotes.is_empty() and proposal.get("searches", []).is_empty()): return Contract.fail("托付条款不完整，请重新商定")
	for quote_entry in proposal.get("quotes", []):
		if not quote_entry is Dictionary or not quote_entry.get("workshop_id") is String or not quote_entry.get("recipe_id") is String or not quote_entry.get("recipe") is Dictionary: return Contract.fail("生产报价缺少工坊、配方或实际条款")
		var current := Canonical.hash_value(state.management_assets.get(quote_entry.workshop_id, {}).get("recipes", {}).get(quote_entry.recipe_id))
		var agreed := Canonical.hash_value(quote_entry.recipe)
		if not current.get("ok", false) or not agreed.get("ok", false) or current.hash != agreed.hash: return Contract.fail("工坊报价已变化，请重新商定具体差异后确认。")
	return {"ok": true}

static func progress(state, task: Dictionary) -> String:
	var labels := {"reserved": "已预留预算", "running": "办理中", "blocked": "办理受阻", "completed": "已办妥", "cancelled": "已取消未办部分"}
	var lines: Array[String] = ["%s：%s。" % [str(task.get("name", "生产托付")), str(labels.get(task.get("status"), "等待办理"))]]
	for step in task.get("steps", []):
		if step.get("action_kind") == "start_character_search":
			var search: Dictionary = state.economic_contracts.get(step.parameters.search_id, {})
			lines.append(search_progress(state, search) if not search.is_empty() else "尚未开始寻访%s。" % str(step.parameters.target_role))
			continue
		if step.get("action_kind") != "commission_production": continue
		var order: Dictionary = state.economic_contracts.get(step.parameters.order_id, {})
		if order.is_empty():
			lines.append("尚未向工坊下单或付款。")
		else:
			var label := "已交割" if order.status == "delivered" else ("已完工，待领取" if order.status == "ready" else "制作中")
			lines.append("%s：%s，实际工日 %d / %d。%s" % [order.recipe.output_definition.name, label, int(order.work_days), int(order.recipe.duration_days), str(order.blocked_reason)])
	if task.get("block_reason", "") != "": lines.append(str(task.block_reason))
	if task.get("status") == "cancelled": lines.append("未办步骤已停止；已付款合同继续履行。")
	return "\n".join(lines)

static func search_progress(state, order: Dictionary) -> String:
	var labels := {"working": "寻访中", "awaiting_choice": "已引见，待决定是否纳用", "resolved": "引见已处置，继续后续事项", "completed": "引见已办妥", "failed": "未能寻得合适人选，可重试或取消", "cancelled": "未完成的寻访已停止"}
	var candidate := str(state.character_states.get(order.get("candidate_id"), {}).get("name", ""))
	return "寻访%s：%s，实际工日 %d / %d。%s%s" % [order.original_plan.target_role, labels.get(order.status, "等待办理"), int(order.work_days), int(order.duration_days), "人选：" + candidate + "。" if candidate != "" else "", str(order.blocked_reason)]

static func resolve_search_choice(state, data: Dictionary, executor: String, id: String, choice: String) -> Dictionary:
	var matches: Array = []
	for order in state.economic_contracts.values():
		if order.get("contract_kind") != "character_search" or order.get("executor_id") != executor or order.get("principal_id") != state.player_character_id: continue
		var root_id := str(state.action_authorizations.get(order.get("authorization_id"), {}).get("root_task_id", ""))
		if (not id.is_empty() and id in [order.contract_id, root_id]) or (id.is_empty() and order.status in ["awaiting_choice", "failed"]): matches.append(order)
	if matches.is_empty(): return {"handled": false}
	if matches.size() != 1: return {"handled": true, "ok": false, "error": "有多份寻访回报，请在对应回报卡片上选择。"}
	var order: Dictionary = matches[0]
	var mapped := "retry_search" if choice == "continue_search" else ("inquire_test" if choice == "view_dossier" else choice)
	if mapped == "acknowledge_report": return {"handled": true, "ok": true, "summary": search_progress(state, order) + "已阅；未完成事项仍保留，可继续寻访或取消未办部分。"}
	var execution := "search-choice:%s:%d:%s" % [order.contract_id, int(order.attempt), mapped]
	var player: String = state.player_character_id
	var result: Dictionary = load("res://scripts/core/game_action_dispatcher.gd").new().execute(context_for(state, data), {"execution_id": execution, "request_id": execution, "actor_id": player, "principal_id": player, "executor_id": player, "action_kind": "resolve_character_search", "parameters": {"search_id": order.contract_id, "choice": mapped}, "target_refs": [order.contract_id], "expected_state_revision": int(state.state_revision)})
	result["handled"] = true
	if result.get("ok", false): result["summary"] = search_progress(state, state.economic_contracts[order.contract_id])
	return result

static func latest_task(state, executor: String, id: String = "") -> Dictionary:
	for tasks in [state.active_tasks, state.completed_tasks.duplicate()]:
		var ordered: Array = tasks.duplicate()
		ordered.reverse()
		for task in ordered:
			if task.get("task_kind") == "management" and task.get("source_type") == "private_talk" and task.get("executor_id") == executor and task.get("principal_id") == state.player_character_id and (id.is_empty() or task.get("task_id") == id): return task
	return {}

static func context_for(state, data: Dictionary):
	var context = load("res://scripts/core/game_runtime_context.gd").new()
	context.state = state
	context.scenario_data = data
	return context

static func submit(state, data: Dictionary, session_id: String) -> Dictionary:
	var pending: Dictionary = state.active_dialogue_sessions[session_id].pending_entrustment
	var proposal: Dictionary = pending.plan.management_proposal
	var valid := validate_quotes(state, proposal)
	if not valid.ok: return valid
	var result := Authorization.new().submit_dialogue_plan(context_for(state, data), session_id)
	if not result.ok: return result
	var task: Variant = Authorization._find_task(state, proposal.plan.task_id)
	return {"ok": true, "task": task.duplicate(true)}
