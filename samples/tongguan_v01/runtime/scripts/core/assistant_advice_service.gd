extends RefCounted
const Contract = preload("res://scripts/core/management_state_contract.gd")
const Canonical = preload("res://scripts/core/canonical_json.gd")
const VisibleContext = preload("res://scripts/core/assistant_context_projection.gd")
const Planner = preload("res://scripts/core/management_plan_builder.gd")
const Parser = preload("res://scripts/ai/assistant_plan_parser.gd")
const Authorization = preload("res://scripts/core/action_authorization_service.gd")
const Transaction = preload("res://scripts/core/game_state_transaction.gd")
const CATEGORIES := ["business", "hiring", "task_risk"]

static func initialize(state, data: Dictionary) -> Dictionary:
	if not state.assistant_advice_state.is_empty(): return Contract.fail("助手建议状态不可重复初始化")
	var rules: Dictionary = data.get("management", {}).get("assistant_advice_rules", {})
	if not Contract.amount(rules.get("summary_days"), true) or not Contract.amount(rules.get("startup_capital"), true): return Contract.fail("缺少助手建议周期与营运资金规则")
	state.assistant_advice_state = {"principal_id": state.player_character_id, "summary_days": int(rules.summary_days), "last_summary_day": int(state.current_day), "frequencies": {"business": "regular", "hiring": "regular", "task_risk": "regular"}, "last_issued_days": {}, "suggestions": {}}
	return update(state, data, true)

static func _dto(name: String, message: String, basis: Array, risks: Array, steps: Array, limits: Array) -> Dictionary:
	return {"schema_version": 1, "kind": "proposal" if not steps.is_empty() else "advice", "message": message, "basis": basis, "risks": risks, "task_id": "", "plan": {"name": name, "steps": steps} if not steps.is_empty() else {}, "resource_limits": limits}

# Candidates come only from the same player-visible facts supplied to the assistant.
static func candidates(state, data: Dictionary) -> Array:
	if state.assistant_advice_state.is_empty(): return []
	var visible := VisibleContext.project({"state": state, "scenario_data": data})
	if visible.assistant.status != "active": return []
	var rows: Array = []
	var business_offices: Array = []
	for canal in visible.get("public_works", []):
		if canal.status != "damaged" or not canal.fields.any(func(field): return int(field.water_supply) < int(canal.repaired_water_supply)): continue
		var order_id: String = canal.proposed_order_id
		var steps := [{"step_id": "repair", "action_kind": "start_public_work", "target_refs": [canal.asset_id], "parameters": {"canal_id": canal.asset_id, "funding_account_id": canal.account_id, "order_id": order_id}, "depends_on": []}, {"step_id": "accept", "action_kind": "finish_public_work", "target_refs": [order_id], "parameters": {"order_id": order_id}, "depends_on": ["repair"]}]
		var dto := _dto("修复" + str(canal.name), "接渠田地供水不足，可按现有材料和工匠报价修渠并验收。", [canal.asset_id], ["施工受季节、材料和工匠到场限制。", "通水从随后完整生长日改善作物；错过农时不能补算收成，也不会直接增加税粮或现金。"], steps, [{"account_id": canal.account_id, "amount": canal.repair_offer.price, "unit_id": "cash_unit"}])
		if not _funded(dto, visible.accounts) or not Parser.new().compile({"state": state, "scenario_data": data}, dto, "advice-preview").get("ok", false): continue
		rows.append(_row(state, "business", canal.asset_id, dto, "%s的接渠田地已登记供水不足；州库工款 %d，需 %d 个实际工日和现有木石。" % [canal.name, int(canal.repair_offer.price), int(canal.repair_offer.duration_days)], "改善实际接渠田地的后续生长条件；收成归实际农户并用于家庭生活。", 30))
	var capital := int(data.get("management", {}).get("assistant_advice_rules", {}).get("startup_capital", 0))
	for asset in visible.assets:
		if asset.get("asset_kind") != "building" or asset.get("status") != "available": continue
		for office in visible.offices:
			if office.role_key != "shopkeeper": continue
			var candidates_available: Array = office.candidates.filter(func(person): return person.assessment == "eligible")
			if office.holder_id == "" and candidates_available.is_empty(): continue
			var candidate: String = office.holder_id if office.holder_id != "" else candidates_available[0].character_id
			var quote := Planner.startup(state, data, asset.asset_id, capital, candidate)
			if not quote.get("ok", false): continue
			var dto := _dto(quote.plan.name, "当地有可租铺面和可办理的人员条件，可筹办当铺。", [asset.asset_id, office.office_id], ["候选可能另投别家；签约前报价可能变化。", "营运资金是内部划拨；租金、工资及维护仍会继续发生，盈利不保证。"], quote.plan.steps, quote.authorization.resource_limits)
			if not _funded(dto, visible.accounts): continue
			if not Parser.new().compile({"state": state, "scenario_data": data}, dto, "advice-preview").get("ok", false): continue
			var basis_text := "%s公开待租：首期租金 %d 钱、整理 %d 钱；%s首期工资 %d 钱。报价待最终签约核实。" % [asset.name, int(asset.rental_offer.amount), int(asset.setup_offer.amount), office.name, int(office.wage) if office.holder_id == "" else 0]
			rows.append(_row(state, "business", asset.asset_id, dto, basis_text, "建立可办理真实抵押业务的产业；没有固定赠送收入。", 20))
			business_offices.append(office.office_id)
	for office in visible.offices:
		if office.holder_id != "" or business_offices.has(office.office_id): continue
		var available: Array = office.candidates.filter(func(person): return person.assessment == "eligible")
		if available.is_empty(): continue
		var person: Dictionary = available[0]
		var steps := [{"step_id": "hire", "action_kind": "hire_family", "target_refs": [office.office_id], "parameters": {"office_id": office.office_id, "candidate_id": person.character_id}, "depends_on": []}]
		var dto := _dto("聘任" + str(office.name), "职位空缺，%s表达了可接受的任职条件。" % person.name, [office.office_id, person.character_id], ["任职需要持续支付约定工资，候选意愿仍可能变化。"], steps, [{"account_id": office.account_id, "amount": office.wage, "unit_id": "cash_unit"}])
		if not _funded(dto, visible.accounts): continue
		if not Parser.new().compile({"state": state, "scenario_data": data}, dto, "advice-preview").get("ok", false): continue
		rows.append(_row(state, "hiring", office.office_id, dto, str(person.expressed_conditions), "填补实际空缺；职责和后续薪酬按任职记录履行。", 10))
	for task in visible.tasks:
		if task.status != "blocked": continue
		var dto := _dto("办理受阻：" + str(task.name), "；".join(task.feedback), [task.task_id], ["已付费用、合同和未清义务不会因暂缓建议而消失。"], [], [])
		rows.append(_row(state, "task_risk", task.task_id, dto, "经办任务已报告受阻。", "核对原因后调整原任务，保留已完成步骤。", 100))
	return rows

static func _funded(dto: Dictionary, accounts: Array) -> bool:
	for limit in dto.resource_limits:
		if not accounts.any(func(account): return account.account_id == limit.account_id and int(account.available) >= int(limit.amount)): return false
	return true

static func _row(state, category: String, target: String, dto: Dictionary, basis_text: String, benefit: String, priority: int) -> Dictionary:
	var row := {"category": category, "target_id": target, "reason_key": category + ":" + target, "dto": dto, "basis_text": basis_text, "benefit": benefit, "priority": priority, "assistant_id": state.player_assistant_assignment.assistant_id, "binding_revision": state.player_assistant_assignment.binding_revision}
	row["fingerprint"] = Canonical.hash_value(row).hash
	row["suggestion_id"] = "advice:" + str(row.fingerprint)
	return row

static func update(state, data: Dictionary, identity_changed: bool = false) -> Dictionary:
	if state.assistant_advice_state.is_empty(): return {"ok": true}
	var memory: Dictionary = state.assistant_advice_state
	var summary_due := int(state.current_day) - int(memory.last_summary_day) >= int(memory.summary_days)
	var available := candidates(state, data)
	var current_ids: Array = available.map(func(row): return row.suggestion_id)
	for record in memory.suggestions.values():
		if record.status in ["pending", "deferred"] and not current_ids.has(record.suggestion_id): record.status = "expired"
	for row in available:
		var frequency: String = memory.frequencies[row.category]
		if frequency == "off": continue
		var existing: Dictionary = memory.suggestions.get(row.suggestion_id, {})
		if not existing.is_empty():
			if existing.status == "deferred" and int(state.current_day) >= int(existing.defer_until_day): existing.status = "pending"
			if existing.status == "expired": existing.status = "pending"
			continue
		if frequency == "less" and int(state.current_day) - int(memory.last_issued_days.get(row.category, -int(memory.summary_days) * 2)) < int(memory.summary_days) * 2: continue
		if row.category == "hiring" and not identity_changed and not summary_due: continue
		row["status"] = "pending"
		row["created_day"] = int(state.current_day)
		row["defer_until_day"] = 0
		row["task_id"] = ""
		memory.suggestions[row.suggestion_id] = row
		memory.last_issued_days[row.category] = int(state.current_day)
	if summary_due: memory.last_summary_day = int(state.current_day)
	return {"ok": true}

static func project(state, expanded: bool = false) -> Array:
	var memory: Dictionary = state.assistant_advice_state
	if memory.is_empty() or not preload("res://scripts/core/player_assistant_service.gd").accepts_reply(state, state.player_assistant_assignment): return []
	var rows: Array = []
	for record in memory.suggestions.values():
		if record.status != "pending" or memory.frequencies[record.category] == "off" or record.assistant_id != state.player_assistant_assignment.assistant_id or record.binding_revision != state.player_assistant_assignment.binding_revision: continue
		rows.append(record.duplicate(true))
	rows.sort_custom(func(a, b): return a.priority > b.priority if a.priority != b.priority else a.suggestion_id < b.suggestion_id)
	if expanded: return rows
	var risks: Array = rows.filter(func(row): return row.category == "task_risk")
	var regular: Array = rows.filter(func(row): return row.category != "task_risk")
	return risks.slice(0, 2) + regular.slice(0, 3)

func respond(context, suggestion_id: String, choice: String, execution_id: String) -> Dictionary:
	return _transaction(context, {"suggestion_id": suggestion_id, "choice": choice, "execution_id": execution_id}, func(working):
		var record: Dictionary = working.state.assistant_advice_state.suggestions.get(suggestion_id, {})
		if record.is_empty(): return Contract.fail("没有这份助手建议")
		if choice not in ["accept", "defer", "dismiss"]: return Contract.fail("未知建议处置")
		if choice == "accept" and record.status == "accepted": return {"ok": true, "result_ref": record.task_id}
		if record.status != "pending" or not project(working.state, true).any(func(row): return row.suggestion_id == suggestion_id): return Contract.fail("这份建议已经失效、暂缓或不属于当前助手")
		if choice == "defer":
			record.status = "deferred"
			record.defer_until_day = int(working.state.current_day) + int(working.state.assistant_advice_state.summary_days)
		elif choice == "dismiss": record.status = "dismissed"
		else:
			if not candidates(working.state, working.scenario_data).any(func(row): return row.suggestion_id == suggestion_id): return Contract.fail("建议依据或人物条件已经变化，请查看新的建议或重新商议")
			if record.dto.kind != "proposal": return Contract.fail("这份风险报告需要商议处理方式，不能直接宣称办妥")
			var compiled := Parser.new().compile(working, record.dto, "adopt:" + suggestion_id)
			if not compiled.get("ok", false): return compiled
			var submitted := Authorization._submit(working, {"authorization": compiled.authorization, "plan": compiled.plan, "execution_id": execution_id})
			if not submitted.get("ok", false): return submitted
			record.status = "accepted"
			record.task_id = compiled.plan.task_id
		return {"ok": true, "result_ref": record.task_id if record.status == "accepted" else suggestion_id}
	)

func set_frequency(context, category: String, frequency: String, execution_id: String) -> Dictionary:
	return _transaction(context, {"category": category, "frequency": frequency, "execution_id": execution_id}, func(working):
		if category not in CATEGORIES or frequency not in ["regular", "less", "off"]: return Contract.fail("未知建议类别或频率")
		working.state.assistant_advice_state.frequencies[category] = frequency
		return {"ok": true, "result_ref": "advice-preference:" + category}
	)

func _transaction(context, input: Dictionary, operation: Callable) -> Dictionary:
	if context == null or context.state.assistant_advice_state.is_empty() or input.get("execution_id", "") == "": return Contract.fail("缺少当前玩家的建议上下文")
	input["principal_id"] = context.state.player_character_id
	var transaction := Transaction.new()
	var preview := transaction.preview_command(context.state, "assistant_advice", input)
	if not preview.get("ok", false): return preview
	return transaction.execute_command(context, transaction.build_command_envelope("assistant_advice", input, preview.preview_token), operation)
