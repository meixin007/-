extends RefCounted

const Visible = preload("res://scripts/core/assistant_context_projection.gd")
const Binding = preload("res://scripts/core/player_assistant_service.gd")

static func nonexecuting(text: String) -> bool:
	for phrase in ["不用再确认", "不用再次确认", "不必再问", "无需再确认", "无需再次确认"]: text = text.replace(phrase, "")
	return ["如果", "假如", "假设", "要是", "是否", "能否", "有什么", "建议", "商议", "讨论", "先拟", "供我决定", "暂不", "别", "不要", "不用", "不许", "？", "?", "他说", "她说", "有人说", "听说", "据说", "比如", "例如", "解释", "翻译", "复述", "“", "”", "‘", "’", "\"", "'"].any(func(marker): return text.contains(marker))

static func control(context, text: String) -> Dictionary:
	var clean := text.strip_edges()
	while clean.ends_with("。") or clean.ends_with("！") or clean.ends_with("!"): clean = clean.left(-1).strip_edges()
	var inquiry := clean.trim_suffix("？").trim_suffix("?")
	if inquiry in ["进展如何", "进度如何", "进度呢", "办得怎么样", "办得怎样了", "查一下进度", "看看进度", "当前进展", "当前进度"]: return {"kind": "progress"}
	if clean in ["好", "好的", "好吧", "行", "可以", "没问题", "同意", "同意这个方案", "按这个办", "按你列的条件办成", "按你说的办", "就按这个方案办", "那就这么办", "就这么办", "照这个办", "照办"]: return {"kind": "accept"}
	if clean in ["先别办", "先不办", "暂不办理", "不要办", "以后再说", "这个方案不办", "取消这个方案", "先放一放"]: return {"kind": "dismiss"}
	if nonexecuting(clean) or not clean.begins_with("取消"): return {"kind": "network"}
	var target := clean.trim_prefix("取消").strip_edges()
	for suffix in ["的未办部分", "的后续步骤", "的后续办理", "未办部分", "后续步骤", "后续办理"]:
		if target.ends_with(suffix): target = target.trim_suffix(suffix).strip_edges(); break
	var tasks: Array = context.state.active_tasks.filter(func(task): return task.get("task_kind") == "management" and preload("res://scripts/core/clan_succession_service.gd").controls_task(context.state, task, context.state.player_character_id) and task.get("parent_task_id", "") == "" and task.get("status") not in ["completed", "cancelled"])
	if target in ["这项任务", "这个任务", "当前任务"]:
		var journal: Dictionary = context.state.assistant_conversation_state
		var record: Dictionary = journal.get("records", {}).get(journal.get("latest_id", ""), {})
		if Binding.accepts_reply(context.state, record.get("binding", {})):
			target = str(record.get("task_id", ""))
			if target.is_empty(): target = str(record.get("dto", {}).get("task_id", ""))
			if target.is_empty(): return {"kind": "clarify", "message": "当前交代尚未指向实际任务，请指出要取消的任务。"}
	if target != "": tasks = tasks.filter(func(task): return target in [str(task.task_id), str(task.name)])
	if tasks.size() != 1:
		var reason := "没有匹配的本人在办任务，请指出要取消的任务。" if tasks.is_empty() else "有多项在办任务，请指出要取消哪一项：" + "、".join(tasks.map(func(task): return str(task.name)))
		return {"kind": "clarify", "message": reason}
	return {"kind": "cancel", "dto": {"schema_version": 1, "kind": "cancel", "message": "按交代取消这项任务的后续办理，既成合同和已花费用保留。", "basis": [tasks[0].task_id], "risks": [], "task_id": tasks[0].task_id, "plan": {}, "resource_limits": []}}

static func progress(context) -> String:
	var visible := Visible.project(context)
	var lines: Array[String] = []
	for task in visible.tasks:
		lines.append("%s：%s" % [str(task.name), str({"reserved": "已预留，等待办理", "running": "办理中", "blocked": "受阻", "completed": "已完成", "cancelled": "已取消"}.get(task.status, task.status))])
		for budget in task.budgets: lines.append("已花 %d，未用预留 %d。" % [int(budget.spent), int(budget.unused)])
		for message in task.feedback: lines.append(str(message))
	return "\n".join(lines) if not lines.is_empty() else "目前没有已授权的待办。尚未采用的方案不会占用资金或自动执行。"

# Extract local scope from the player's words and actual visible offers, before
# comparing it to the model's plan. The model never supplies its own authority.
static func instruction_quote(context, text: String) -> Dictionary:
	if nonexecuting(text): return {"ok": false, "error": "当前话语为商议、否定、假设或引述"}
	if not ["替我", "帮我", "为我", "给我", "直接办理", "全权安排", "交给你办", "请"].any(func(marker): return text.contains(marker)) and not text.begins_with("找") and not text.begins_with("寻访") and not text.begins_with("打造") and not text.begins_with("抄"): return {"ok": false, "error": "尚未明确交代办理"}
	var split := RegEx.new()
	split.compile("[，,；;。]|然后|接着|最后|再(?=打造|锻造|铸造|做|找|寻访|寻找|物色|抄|誊写|整理|装订)")
	var clauses := split.sub(text, "\n", true).split("\n", false)
	var visible := Visible.project(context)
	var goals: Array = []
	var extractor = preload("res://scripts/ai/generic_entrustment_slot_extractor.gd").new()
	for part in clauses:
		var clause := str(part).strip_edges().trim_prefix("先").trim_prefix("再").strip_edges()
		if clause.is_empty() or _term_clause(clause): continue
		var numbers := RegEx.new()
		numbers.compile("([0-9零〇一二两三四五六七八九十百千万]+)(把|柄|件|本|册|卷|个|位|名)")
		var counts := numbers.search_all(clause)
		if counts.size() > 1: return {"ok": false, "error": "请分别说明各件物品或人选的数量"}
		var quantity: int = 1 if counts.is_empty() else load("res://scripts/ai/assistant_plan_parser.gd").new()._instruction_amount(counts[0].get_string(1))
		if quantity < 1 or (goals.size() + quantity) * 1200 > preload("res://scripts/core/game_state_transaction.gd").MAX_COMMAND_PAYLOAD_LENGTH: return {"ok": false, "error": "该数量须另行分批安排，未截断后办理"}
		var object_text := numbers.sub(clause, "", true)
		for word in ["请帮我", "替我", "帮我", "为我", "给我", "请", "并引见", "并领回来", "并领取", "带回", "送来", "来见我"]: object_text = object_text.replace(word, "")
		var production := RegEx.new()
		production.compile("打造|锻造|铸造|制作|抄写|抄录|誊写|誊抄|抄|整理|装订")
		if production.search(clause) != null:
			var wanted := production.sub(object_text, "", true).strip_edges()
			var matches: Array = []
			for workshop in visible.assets:
				if workshop.get("asset_kind") != "workshop": continue
				var target := wanted.replace(str(workshop.name), "").trim_prefix("在").strip_edges()
				for recipe in workshop.recipes:
					if (target.length() >= 2 and str(recipe.name).contains(target)) or target == str(recipe.recipe_id): matches.append({"workshop": workshop, "recipe": recipe})
			if matches.size() != 1: return {"ok": false, "error": "这段物品要求未对应唯一实际报价：" + clause}
			var match_offer: Dictionary = matches[0]
			for index in quantity:
				goals.append({"capability_hint": "craft_item" if match_offer.recipe.source_work_id == "" else "compile_or_process_work", "arguments": {"archetype_id": "generic_item" if match_offer.recipe.source_work_id == "" else "manuscript_book", "quantity": 1, "target_item": match_offer.recipe.name, "recipe_id": match_offer.recipe.recipe_id, "workshop_id": match_offer.workshop.asset_id, "source_work_id": match_offer.recipe.source_work_id}, "requirements": []})
		else:
			var slot: Dictionary = extractor.extract(clause, {"current_day": int(context.state.current_day)})
			var aliases := {"physician_retainer": ["郎中", "医者", "医生"], "finance_retainer": ["账房", "账房先生"], "governance_retainer": ["治事门客", "治事人才"], "strategist_retainer": ["谋士"], "assassin_retainer": ["武勇门客", "武勇之士"], "generic_retainer": ["门客", "可用门客"]}
			for word in ["寻访", "寻找", "物色", "找"]: object_text = object_text.replace(word, "")
			var archetype := str(slot.get("target_archetype", ""))
			if slot.get("domain") != "seek_person" or not aliases.get(archetype, []).has(object_text.strip_edges()): return {"ok": false, "error": "这段寻访条件仍需核实，未改成普通寻人：" + clause}
			for index in quantity: goals.append({"capability_hint": "find_person_and_introduce", "arguments": {"quantity": 1, "archetype_id": archetype, "target_role": object_text.strip_edges(), "specialty": "", "due_days": 3}, "requirements": []})
	if goals.is_empty(): return {"ok": false, "error": "尚无可对应的明确目标"}
	var deadline: Dictionary = extractor.extract_deadline(text, int(context.state.current_day))
	var dto := {"speech_act": "request_favor", "evidence_text": text, "proposed_goals": goals, "unmapped_requirements": [], "deadline": deadline if deadline.get("mentioned", false) else {}}
	var compiled: Dictionary = preload("res://scripts/core/entrustment_request_compiler.gd").new().compile_request(dto, {"executor_id": context.state.player_assistant_assignment.assistant_id, "requester_id": context.state.player_character_id}, context.state)
	if compiled.get("resolution_class") not in ["supported", "composable"]: return {"ok": false, "error": "原交代仍有未对应的目标或条件"}
	var plan: Dictionary = compiled.compiled_plan
	plan["proposal_player_text"] = text
	return preload("res://scripts/core/dialogue_production_adapter.gd").quote(context.state, plan, context.state.player_assistant_assignment.assistant_id, "instruction-scope", 1)

static func _term_clause(text: String) -> bool:
	if text in ["直接办理", "现在办理", "即刻办理", "全权安排", "交给你办", "有劳了", "允许转委托", "可以转委托", "允许转派", "可以转派"]: return true
	var budget := RegEx.new()
	budget.compile("^(?:从|用)?(?:家族公账|家族主账户|我的私款|个人私款|私款)(?:拿|花)?(?:不超过|不得超过|最多|至多|累计预算|预算上限|预算)[：:\\s]*[0-9零〇一二两三四五六七八九十百千万]+(?:钱|记账单位)?$")
	if budget.search(text) != null: return true
	var deadline := RegEx.new()
	deadline.compile("^(?:在)?(?:第)?[0-9零〇一二两三四五六七八九十百]+(?:天|日)(?:内|之前|前)(?:办完|办妥|完成|交付|回话)?$")
	return deadline.search(text) != null

static func authorizes_entrustment(context, text: String, compiled: Dictionary) -> bool:
	if not compiled.get("ok", false) or compiled.get("dto", {}).get("kind") != "proposal": return false
	var quoted := instruction_quote(context, text)
	if not quoted.get("ok", false): return false
	var expected: Dictionary = quoted.proposal
	if not _same_steps(compiled.plan.steps, expected.plan.steps): return false
	if not compiled.authorization.resource_limits.is_empty():
		var budget := RegEx.new()
		budget.compile("(?:不超过|不得超过|最多|至多|累计预算|预算上限|预算)[：:\\s]*([0-9零〇一二两三四五六七八九十百千万]+)")
		if budget.search_all(text).size() != 1 or not ["家族公账", "家族主账户", "私款"].any(func(marker): return text.contains(marker)): return false
	for limit in compiled.authorization.resource_limits:
		var matches: Array = expected.authority_terms.resource_limits.filter(func(item): return item.account_id == limit.account_id and int(limit.amount) <= int(item.amount))
		if matches.size() != 1: return false
	var allowed_terms := terms(context, text, compiled.plan.steps, int(compiled.get("instruction_day", -1)))
	if not allowed_terms.get("ok", false): return false
	compiled.authorization.valid_until_day = allowed_terms.valid_until_day
	compiled.authorization.scope.allow_subdelegation = allowed_terms.allow_subdelegation
	return true

static func _same_steps(actual: Array, expected: Array) -> bool:
	return preload("res://scripts/core/canonical_json.gd").hash_value(_normalize_steps(actual)).get("hash") == preload("res://scripts/core/canonical_json.gd").hash_value(_normalize_steps(expected)).get("hash")

static func pawnshop_scope(context, text: String, compiled: Dictionary) -> bool:
	if not compiled.get("ok", false): return false
	# The bounded startup shortcut must account for the complete utterance and
	# the complete operating sequence, not merely find the words "open a shop".
	var remainder := text
	var money := RegEx.new()
	money.compile("(?:不超过|不得超过|最多|至多|累计预算|预算上限)[：:\\s]*[0-9零〇一二两三四五六七八九十百千万]+(?:钱|记账单位)?")
	remainder = money.sub(remainder, "", true)
	var date := RegEx.new()
	date.compile("(?:在)?(?:第)?[0-9零〇一二两三四五六七八九十百]+(?:天|日)(?:内|之前|前)(?:办完|办妥|完成|交付|回话)?")
	remainder = date.sub(remainder, "", true)
	for asset in Visible.project(context).assets:
		if asset.get("asset_kind") == "building": remainder = remainder.replace(str(asset.name), "")
	for character in context.scenario_data.characters:
		if character.has("employment_preferences"): remainder = remainder.replace(str(character.name), "")
	for word in ["家族主账户", "家族公账", "开一家当铺", "开设当铺", "开当铺", "不允许转委托", "不可以转委托", "禁止转委托", "不允许转派", "不可以转派", "禁止转派", "允许转委托", "可以转委托", "允许转派", "可以转派", "全权安排", "直接办理", "现在办理", "即刻办理", "交给你办", "招聘掌柜", "安排掌柜", "租铺", "租下", "聘用", "雇用", "替我", "帮我", "请", "你", "从", "拿", "用", "在", "，", ",", "。", "；", ";", " "]:
		remainder = remainder.replace(word, "")
	if not remainder.is_empty(): return false
	var kinds: Array = compiled.plan.steps.map(func(step): return str(step.action_kind))
	var expected := ["rent_shop", "hire_family", "prepare_pawnshop", "fund_pawnshop", "open_pawnshop"]
	var without_wage: Array = kinds.filter(func(kind): return kind != "offer_family_wage")
	if without_wage != expected or kinds.count("offer_family_wage") > 1: return false
	if kinds.has("offer_family_wage") and kinds.find("offer_family_wage") > kinds.find("hire_family"): return false
	var shop_id: String = compiled.plan.steps[0].parameters.shop_id
	for step in compiled.plan.steps:
		if step.parameters.has("shop_id") and step.parameters.shop_id != shop_id: return false
	return true

static func _normalize_steps(steps: Array) -> Array:
	var ids := {}
	var result: Array = []
	for index in steps.size():
		var step: Dictionary = steps[index]
		ids[step.step_id] = "step:%d" % index
		if step.action_kind in ["commission_production", "start_public_work"]: ids[step.parameters.order_id] = "order:%d" % index
		if step.action_kind == "start_character_search": ids[step.parameters.search_id] = "search:%d" % index
	for step in steps:
		var params: Dictionary = step.parameters.duplicate(true)
		if step.action_kind in ["appoint_office", "dismiss_office", "force_dismiss_office"] and params.has("office_id"): params.office_id = preload("res://scripts/domain/tang_office_catalog.gd").canonical_id(params.office_id)
		for key in ["order_id", "search_id"]:
			if params.has(key): params[key] = ids.get(params[key], params[key])
		result.append({"action_kind": step.action_kind, "parameters": params, "depends_on": step.depends_on.map(func(id): return ids.get(id, id))})
	return result

static func terms(context, text: String, steps: Array, instruction_day: int = -1) -> Dictionary:
	var origin_day: int = int(context.state.current_day) if instruction_day < 0 else instruction_day
	var deadline: Dictionary = preload("res://scripts/ai/generic_entrustment_slot_extractor.gd").new().extract_deadline(text, origin_day)
	var until: Variant = null
	if deadline.get("mentioned", false):
		if deadline.get("is_vague", false): return {"ok": false, "error": "期限尚不明确，请说明截止日，或明确不设期限。"}
		until = int(deadline.target_day) if deadline.get("is_absolute_day", false) else origin_day + int(deadline.exact_days)
		if int(until) <= int(context.state.current_day) or int(until) - int(context.state.current_day) < _minimum_days(context, steps): return {"ok": false, "error": "所给期限不足以完成已列步骤与实际工序，请调整期限或范围。"}
	var delegation := text
	for phrase in ["不允许转委托", "不可以转委托", "不允许转派", "不可以转派", "禁止转委托", "禁止转派"]: delegation = delegation.replace(phrase, "")
	var allowed: bool = ["允许转委托", "可以转委托", "允许转派", "可以转派"].any(func(marker): return delegation.contains(marker))
	return {"ok": true, "valid_until_day": until, "allow_subdelegation": allowed}

static func _minimum_days(context, steps: Array) -> int:
	var day := 0
	var ready := {}
	var shops := {}
	for step in steps:
		day += 1
		var params: Dictionary = step.parameters
		match str(step.action_kind):
			"start_public_work":
				var offer: Dictionary = context.state.management_assets.get(params.canal_id, {}).get("repair_offer", {})
				var needed := int(offer.get("duration_days", 0))
				var cursor := day
				var calendar: Dictionary = context.state.current_date.duplicate(true)
				var clock = preload("res://scripts/core/strategic_time_service.gd").new()
				for offset in day: calendar = clock.next_date(calendar)
				while needed > 0 and cursor < day + 360 * (needed + 1):
					cursor += 1
					calendar = clock.next_date(calendar)
					if offer.get("work_months", []).any(func(month): return int(month) == int(calendar.month)): needed -= 1
				ready[params.order_id] = cursor
			"finish_public_work": day = maxi(day, int(ready.get(params.order_id, 0)))
			"commission_production": ready[params.order_id] = day + int(context.state.management_assets.get(params.workshop_id, {}).get("recipes", {}).get(params.recipe_id, {}).get("duration_days", 0))
			"collect_production": day = maxi(day, int(ready.get(params.order_id, 0)))
			"start_character_search": day += int(params.duration_days)
			"rent_shop": shops[params.shop_id] = params.building_id
			"prepare_pawnshop": ready[params.shop_id] = day + int(context.state.management_assets.get(shops.get(params.shop_id, ""), {}).get("setup_offer", {}).get("duration_days", 0))
			"open_pawnshop": day = maxi(day, int(ready.get(params.shop_id, 0)))
	return day
