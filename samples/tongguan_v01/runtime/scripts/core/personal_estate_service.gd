extends RefCounted
const Rules = preload("res://scripts/core/management_state_contract.gd")
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Presence = preload("res://scripts/core/production_service.gd")
const Continuation = preload("res://scripts/core/estate_production_continuation.gd")
const ResourceDistribution = preload("res://scripts/core/estate_resource_distribution.gd")
const SOURCE := "scenario:mei_estate_756"
const KINDS := ["record_personal_estate", "settle_personal_estate", "request_estate_settlement", "collect_estate_production"]
const PaidProduction = preload("res://scripts/core/estate_paid_production_service.gd")
const Workload = preload("res://scripts/core/character_workload_service.gd")

static func merge_definitions(data: Dictionary, config: Variant) -> Dictionary:
	if not config is Dictionary or config.get("source_id") != SOURCE or not config.get("rules") is Array or not config.get("characters") is Array or not config.get("initial_assets") is Array or not config.get("cash_grants") is Array: return Rules.fail("遗产定义缺少实际来源")
	for person in config.characters:
		if not person is Dictionary or data.characters.any(func(old): return old.id == person.get("id")): return Rules.fail("遗产人物重复")
		data.characters.append(person.duplicate(true))
		data.management.character_cash_grants.append({"character_id": person.id, "location_id": person.location_id, "amount": 0, "source_id": SOURCE})
		data.management.ration_grants.append({"character_id": person.id, "amount": 40, "source_id": SOURCE})
		data.management.initial_presence.append({"character_id": person.id, "location_id": person.location_id, "source_id": SOURCE})
		data.management.life_models[person.id] = {"minimum_reserve": 5, "dependants": 0, "tie_bonus": 0, "application_wait_days": 3, "review_interval_days": 1, "unpaid_grace_days": 3, "stable_goal": "support_family", "preferred_employer_id": "mei_qing", "source_id": SOURCE}
	for grant in config.cash_grants:
		var old: Array = data.management.character_cash_grants.filter(func(row): return row.character_id == grant.character_id)
		if old.size() != 1 or int(old[0].amount) != 0: return Rules.fail("遗产初始私款须替换唯一零额来源，不能重复发放")
		old[0]["amount"] = grant.amount
		old[0]["source_id"] = SOURCE
	data.management.initial_assets.append_array(config.initial_assets.duplicate(true))
	data.management["estate_rules"] = {"source_id": SOURCE, "rules": config.rules.duplicate(true)}
	return {"ok": true}

static func initialize(state, data: Dictionary) -> Dictionary:
	state.flags["estate_rules"] = data.get("management", {}).get("estate_rules", {}).duplicate(true)
	return {"ok": true}

static func rule_for(state, id: String) -> Dictionary:
	for rule in state.flags.get("estate_rules", {}).get("rules", []):
		if rule.estate_id == id: return rule
	return {}

static func cost_for(state, _kind: String, params: Dictionary) -> Dictionary:
	if rule_for(state, str(params.get("estate_id", ""))).is_empty(): return Rules.fail("没有有来源的个人遗产安排")
	return {"ok": true, "account_id": "", "amount": 0}

static func payments_for(state, rule: Dictionary) -> Dictionary:
	var account: String = rule.account_id
	var person: String = rule.owner_id
	var source := {"entity_kind": "character", "entity_id": person}
	if Accounts.new().available(state, account) != Accounts.new().balance(state, account): return Rules.fail("私款仍有原任务预留，须先处理原任务的义务")
	for task in state.active_tasks:
		if task.get("principal_id") == person and task.get("status") not in ["completed", "cancelled", "failed"]: return Rules.fail("仍有本人未完成委托，保留任务及遗产等待交接")
	var payments: Array = []
	var cash := Accounts.new().available(state, account)
	for contract in state.economic_contracts.values():
		if contract.get("contract_kind") == "pawn_loan" and contract.get("borrower_id") == person and int(contract.get("remaining_debt", 0)) > 0:
			if contract.status not in ["outstanding", "overdue"] or not contract.allow_redemption_collection: return Rules.fail("原借据仍有未能按原约清偿的债务，遗产保留")
			var item: Dictionary = state.management_assets[contract.collateral_id]
			if int(item.condition) <= 0 or item.location_id != rule.location_id: return Rules.fail("抵押物损毁或不在交割地，须先处理债权")
			payments.append({"kind": "debt", "destination_account_id": contract.lender_account_id, "amount": int(contract.remaining_debt), "reason_ref": contract.contract_id})
			cash -= int(contract.remaining_debt)
		elif contract.get("contract_kind") not in ["personal_estate", "pawn_loan", "marriage"] and (contract.get("party_refs", []).has(person) or contract.get("principal_id") == person or contract.get("customer_id") == person) and contract.get("status") not in ["completed", "ended", "cancelled", "delivered", "settled"]:
			return Rules.fail("仍有未结个人合同，遗产和债权保留等待处理")
	if cash < 0: return Rules.fail("实际私款不足清偿全部债务；不分配、不抹债，也不动用家族公账")
	var weight := 0
	for heir in rule.heirs:
		if not heir.willing or not Presence.present(state, heir.character_id, rule.location_id): return Rules.fail("继承人尚未同意或未实际到场")
		weight += int(heir.weight)
	var remaining := cash
	for index in rule.heirs.size():
		var heir: Dictionary = rule.heirs[index]
		var value := remaining if index == rule.heirs.size() - 1 else int(cash * int(heir.weight) / weight)
		remaining -= value
		if value > 0: payments.append({"kind": "share", "destination_account_id": heir.account_id, "amount": value, "reason_ref": rule.estate_id})
	for item in state.management_assets.values():
		if item.owner_ref != source: continue
		if item.get("asset_kind") != "movable" or heir_for(rule, item.asset_id).is_empty(): return Rules.fail("有未配置分配方式的私产，须补齐安排后办理")
		if item.status == "pledged" and not payments.any(func(payment): return payment.kind == "debt" and payment.reason_ref == item.lien_contract_id): return Rules.fail("设权物品须先清偿实际债务")
		if item.status not in ["available", "pledged"] or item.location_id != rule.location_id: return Rules.fail("私产不在可交割状态或地点")
	var resources := ResourceDistribution.plan(state, rule)
	if not resources.ok: return resources
	payments.append_array(resources.payments)
	for payment in payments:
		if Accounts.new().location(state, payment.destination_account_id) != rule.location_id or Accounts.new().balance(state, payment.destination_account_id) > Rules.MAX_AMOUNT - int(payment.amount): return Rules.fail("收款账户不在交割地或超过容量")
	return {"ok": true, "payments": payments, "net_cash": cash, "resource_totals": resources.totals}

static func apply(state, kind: String, params: Dictionary, principal: String, execution: String) -> Dictionary:
	var rule := rule_for(state, str(params.get("estate_id", "")))
	if rule.is_empty(): return Rules.fail("遗产缺少实际规则")
	if kind == "record_personal_estate":
		if principal != rule.owner_id or int(state.current_day) < int(rule.death_day) or state.economic_contracts.has(rule.estate_id): return Rules.fail("尚未到本人剧本事件日期或已登记实际遗产")
		state.character_states[rule.owner_id]["status"] = "dead"
		if rule.owner_id == state.player_character_id:
			state.is_time_paused = true
			state.pause_reason = "player_death"
		state.economic_contracts[rule.estate_id] = {"contract_id": rule.estate_id, "contract_kind": "personal_estate", "source_id": SOURCE, "owner_id": rule.owner_id, "executor_id": rule.executor_id, "account_id": rule.account_id, "location_id": rule.location_id, "created_day": int(state.current_day), "status": "pending", "death_receipt": execution, "settlement_receipt": "", "payments": [], "items": [], "blocked_reason": "待经办人核验原债务与实际遗产后分配。"}
		var continuations := Continuation.capture(state, rule)
		if rule.get("continue_private_production", false): state.economic_contracts[rule.estate_id]["production_continuations"] = continuations
		return {"ok": true, "result_ref": rule.estate_id, "estate_continuations": continuations.duplicate(true), "visible_summary": "已登记剧本人物死亡与个人遗产；家族共有资产、旧合同和预留继续保留。"}
	var estate: Dictionary = state.economic_contracts.get(rule.estate_id, {})
	if estate.get("status") != "pending" or state.character_states[rule.owner_id].get("status") != "dead": return Rules.fail("没有待分配的实际遗产")
	if kind == "request_estate_settlement":
		if not rule.heirs.any(func(heir): return heir.character_id == principal and heir.willing) or not Presence.present(state, principal, rule.location_id): return Rules.fail("只有实际在场且同意的继承人可请求原经办人处理")
		if estate.has("settlement_request"): return Rules.fail("原经办请求已经登记，等待实际处理")
		var asked := {"execution_id": execution, "estate_id": rule.estate_id, "requester_id": principal, "executor_id": rule.executor_id, "day": int(state.current_day)}
		estate["settlement_request"] = asked
		estate["blocked_reason"] = "已请求原受托人；待其到场、有空且愿意办理时核验原债务和分配。"
		return {"ok": true, "result_ref": rule.estate_id, "estate_request": asked.duplicate(true), "visible_summary": estate.blocked_reason}
	if kind == "collect_estate_production": return PaidProduction.collect(state, rule, str(params.get("order_id", "")), principal, execution)
	if principal != rule.executor_id or not Presence.present(state, principal, rule.location_id): return Rules.fail("本人不是实际受托且到场的遗产经办人")
	if Workload.occupied_today(state, principal, "", principal): return Rules.fail("经办人今日已有职责或实际事务，遗产继续保留等待办理")
	var planned := payments_for(state, rule)
	if not planned.ok: return planned
	estate["status"] = "settling"
	estate["processing_plan"] = []
	for index in planned.payments.size():
		var payment: Dictionary = planned.payments[index].duplicate(true)
		payment["execution_id"] = execution + ":payment:" + str(index)
		estate.processing_plan.append(payment)
	var journals: Array = []
	for payment in estate.processing_plan:
		var request := {"execution_id": payment.execution_id, "source_account_id": payment.get("source_account_id", rule.account_id), "destination_account_id": payment.destination_account_id, "amount": payment.amount, "actor_id": principal, "reason_ref": payment.reason_ref, "estate_id": rule.estate_id}
		var paid: Dictionary = Accounts.new().apply(state, "transfer", request)
		if not paid.ok: return paid
		if payment.kind == "debt":
			var loan: Dictionary = state.economic_contracts[payment.reason_ref]
			var redeemed: Dictionary = load("res://scripts/core/pawnshop_service.gd").finish_redemption(state, loan, payment.execution_id)
			if not redeemed.ok: return redeemed
		journals.append(payment.execution_id)
		estate.payments.append(payment.duplicate(true))
	for id in state.management_assets:
		var item: Dictionary = state.management_assets[id]
		if item.owner_ref != {"entity_kind": "character", "entity_id": rule.owner_id}: continue
		var heir := heir_for(rule, id)
		var delivery := {"execution_id": execution, "from_ref": item.owner_ref.duplicate(true), "to_ref": {"entity_kind": "character", "entity_id": heir}, "day": int(state.current_day), "consent_rule": "estate_distribution", "estate_id": rule.estate_id}
		item["owner_ref"] = delivery.to_ref.duplicate(true)
		item["custodian_ref"] = item.owner_ref.duplicate(true)
		item["equipped_by"] = ""
		item.erase("pledge_offer"); item.erase("purchase_offer")
		if not item.has("transfer_history"): item["transfer_history"] = []
		item.transfer_history.append(delivery)
		estate.items.append({"asset_id": id, "heir_id": heir})
		state.inventory = state.inventory.filter(func(ref): return ref.get("asset_ref") != id)
		if heir == state.player_character_id: state.inventory.append({"id": id, "asset_ref": id})
	estate.erase("processing_plan")
	estate["status"] = "settled"
	estate["settlement_receipt"] = execution
	estate["net_cash"] = planned.net_cash
	estate["blocked_reason"] = "已清偿所列债务并实际交付余款与动产；家族公账保留。"
	var result := {"ok": true, "result_ref": rule.estate_id, "journal_refs": journals, "estate_work": rule.estate_id, "visible_summary": estate.blocked_reason}
	if rule.has("resource_shares"):
		estate["resource_totals"] = planned.resource_totals.duplicate(true)
		result["estate_resources"] = planned.resource_totals.duplicate(true)
	return result

# Only the transient, all-or-nothing estate transaction can pay from the dead owner's account.
# No generic account operator is added; validation rejects a saved transient plan.
static func permits_payment(state, action: String, request: Dictionary) -> bool:
	if Continuation.permits_resource(state, action, request): return true
	var row: Dictionary = state.economic_contracts.get(request.get("estate_id", ""), {})
	if action != "transfer" or row.get("status") != "settling" or row.get("executor_id") != request.get("actor_id") or state.character_states.get(row.get("owner_id"), {}).get("status") != "dead": return false
	return row.get("processing_plan", []).any(func(payment): return payment.get("source_account_id", row.account_id) == request.get("source_account_id") and payment.execution_id == request.get("execution_id") and payment.destination_account_id == request.get("destination_account_id") and payment.amount == request.get("amount") and payment.reason_ref == request.get("reason_ref") and not state.resource_journal.has(payment.execution_id))

static func settle_daily(state, data: Dictionary) -> Dictionary:
	for rule in state.flags.get("estate_rules", {}).get("rules", []):
		if int(state.current_day) < int(rule.death_day): continue
		if not state.economic_contracts.has(rule.estate_id):
			var recorded: Dictionary = load("res://scripts/core/game_action_dispatcher.gd").apply(state, data, request(state, rule.owner_id, "record_personal_estate", {"estate_id": rule.estate_id}, [rule.estate_id], rule.estate_id + ":death"))
			if not recorded.ok: return recorded
		var estate: Dictionary = state.economic_contracts[rule.estate_id]
		if load("res://scripts/core/clan_succession_service.gd").head(state, rule.clan_id) == rule.owner_id:
			var result: Dictionary = load("res://scripts/core/game_action_dispatcher.gd").apply(state, data, request(state, rule.successor_id, "assume_clan_head", {"clan_id": rule.clan_id, "successor_id": rule.successor_id, "estate_id": rule.estate_id}, [rule.clan_id, rule.successor_id], rule.estate_id + ":succession"))
			estate["succession_reason"] = "已由实际到场继任者承接家族经营权。" if result.ok else str(result.get("error", "等待接任条件"))
		if estate.status == "pending":
			var planned := payments_for(state, rule)
			estate["blocked_reason"] = "可按已配置的份额清偿及分配；等待经办人确认。" if planned.ok else planned.error
			if estate.has("settlement_request"):
				if not rule.get("executor_willing", false):
					estate["blocked_reason"] = "原受托人目前不愿办理；原请求与遗产继续保留。"
				elif not Presence.present(state, rule.executor_id, rule.location_id):
					estate["blocked_reason"] = "原受托人尚未到场或无法办理；原请求与遗产继续保留。"
				elif planned.ok:
					var settled: Dictionary = load("res://scripts/core/game_action_dispatcher.gd").apply(state, data, request(state, rule.executor_id, "settle_personal_estate", {"estate_id": rule.estate_id}, [rule.estate_id], estate.settlement_request.execution_id + ":settle"))
					if not settled.ok:
						if estate.status != "pending": return settled
						estate["blocked_reason"] = str(settled.get("error", "等待实际经办"))
				elif rule.get("collect_paid_production", false):
					for order in PaidProduction.orders_for(state, rule):
						if order.status != "ready" or PaidProduction.active_collector(state, order.contract_id): continue
						var ready := PaidProduction.assess(state, rule, order.contract_id)
						if not ready.ok:
							estate["blocked_reason"] = ready.error
							continue
						var collected: Dictionary = load("res://scripts/core/game_action_dispatcher.gd").apply(state, data, request(state, rule.executor_id, "collect_estate_production", {"estate_id": rule.estate_id, "order_id": order.contract_id}, [rule.estate_id, order.contract_id], estate.settlement_request.execution_id + ":collect:" + order.contract_id))
						estate["blocked_reason"] = "已依原付款合同接管产物；待下一实际经办日核验并分配。" if collected.ok else str(collected.get("error", "等待原订单实际交付"))
						break
	return {"ok": true}

static func request(state, actor: String, kind: String, params: Dictionary, targets: Array, execution: String) -> Dictionary:
	return {"execution_id": execution, "request_id": execution, "actor_id": actor, "principal_id": actor, "executor_id": actor, "action_kind": kind, "parameters": params, "target_refs": targets, "expected_state_revision": state.state_revision}

static func heir_for(rule: Dictionary, item_id: String) -> String:
	return str(rule.bequests.get(item_id, rule.get("residual_movable_heir", "")))

static func project(state, viewer: String) -> Array:
	var result: Array = []
	for rule in state.flags.get("estate_rules", {}).get("rules", []):
		if rule.executor_id != viewer and rule.owner_id != viewer and not rule.heirs.any(func(heir): return heir.character_id == viewer): continue
		var row: Dictionary = state.economic_contracts.get(rule.estate_id, {})
		if row.is_empty(): continue
		var shares: Array[String] = []
		for heir in rule.heirs: shares.append("%s %d 份" % [state.character_states[heir.character_id].name, int(heir.weight)])
		var planned := payments_for(state, rule) if row.status == "pending" else {"ok": false, "error": row.blocked_reason}
		var preview: Array = []
		for payment in planned.get("payments", []) if row.status == "pending" else row.payments:
			var owner: Dictionary = state.resource_accounts[payment.destination_account_id].owner_ref
			var name: String = state.character_states.get(owner.entity_id, {}).get("name", "原债权人")
			preview.append({"kind": payment.kind, "name": name, "amount": payment.amount, "unit_id": payment.get("unit_id", "cash_unit")})
		var bequests: Array[String] = []
		for id in rule.bequests: bequests.append("%s交付%s" % [state.management_assets[id].name, state.character_states[rule.bequests[id]].name])
		if rule.has("residual_movable_heir"): bequests.append("其他剩余动产交付%s" % state.character_states[rule.residual_movable_heir].name)
		var obligations: Array = []
		for task_id in row.get("production_continuations", {}):
			var task := Continuation.task_for(state, task_id)
			var paid := 0
			var held := 0
			for step in task.get("steps", []): paid += int(state.resource_journal.get(step.execution_id, {}).get("amount", 0))
			for id in state.action_authorizations.get(task.get("authorization_id"), {}).get("reservation_refs", {}).values(): held += int(state.resource_reservations[id].remaining_amount)
			var reason := "仅延续原有生产条款；不能追加预算或改派。"
			if task.status != "completed":
				if not Presence.present(state, task.executor_id, rule.location_id): reason = "原受托人尚未到场或无法行动，原义务保留。"
				elif int(state.character_states[task.executor_id].get("relationships", {}).get(rule.owner_id, 0)) < 0: reason = "原受托人目前不愿续办，原义务保留。"
				elif not Presence.present(state, rule.executor_id, rule.location_id): reason = "遗产经办人未到交割地；原产物继续由工坊保管。"
			obligations.append({"executor_name": state.character_states[task.executor_id].name, "paid": paid, "held": held, "completed": task.status == "completed", "reason": reason})
		result.append({"estate_id": rule.estate_id, "name": state.character_states[rule.owner_id].name, "status": row.status, "summary": "先清偿私人债务；余款按 %s 分配。%s。家族共有资产另行保留。" % ["、".join(shares), "、".join(bequests)], "ready": planned.ok and rule.executor_id == viewer, "can_request": row.status == "pending" and not row.has("settlement_request") and rule.heirs.any(func(heir): return heir.character_id == viewer and heir.willing) and Presence.present(state, viewer, rule.location_id), "executor_name": state.character_states[rule.executor_id].name, "reason": row.blocked_reason if row.has("settlement_request") else planned.get("error", row.blocked_reason), "payments": preview, "succession_reason": row.get("succession_reason", "")})
		result[-1]["obligations"] = obligations
		result[-1]["paid_orders"] = PaidProduction.project(state, rule, viewer)
		if not rule.get("resource_shares", []).is_empty(): result[-1]["summary"] += " 其他实际库存按同份额现场交付，口粮与钱分别记账。"
	return result

static func validate(raw: Dictionary) -> Dictionary:
	var config: Variant = raw.get("flags", {}).get("estate_rules", {})
	if not config is Dictionary: return Rules.fail("遗产配置类型无效")
	if config.is_empty():
		return Rules.fail("已有遗产合同不能丢失规则来源") if raw.get("economic_contracts", {}).values().any(func(row): return row.get("contract_kind") == "personal_estate") else {"ok": true}
	if config.get("source_id") != SOURCE or not config.get("rules") is Array: return Rules.fail("遗产规则没有来源")
	var seen := {}
	for rule in config.rules:
		if not rule is Dictionary or not rule.get("estate_id") is String or seen.has(rule.estate_id) or not Rules.amount(rule.get("death_day"), true) or not rule.get("heirs") is Array or rule.heirs.is_empty() or not rule.get("bequests") is Dictionary: return Rules.fail("遗产规则缺少日期、份额或动产安排")
		if rule.has("collect_paid_production") and not rule.collect_paid_production is bool: return Rules.fail("原已付款生产订单接管安排无效")
		if rule.has("executor_willing") and not rule.executor_willing is bool: return Rules.fail("受托人办理意愿无效")
		seen[rule.estate_id] = true
		for field in ["owner_id", "executor_id", "successor_id"]:
			if not raw.character_states.has(rule.get(field)): return Rules.fail("遗产规则引用缺失人物")
		var owner := {"entity_kind": "character", "entity_id": rule.owner_id}
		var account: Dictionary = raw.resource_accounts.get(rule.get("account_id"), {})
		if account.get("owner_ref") != owner or account.get("operator_refs") != [owner] or not raw.local_node_state.has(rule.get("location_id")): return Rules.fail("遗产必须保留原本人私账与经办权，不能授予执行人任意取款权")
		if not raw.flags.get("clan_succession", {}).get("rules", []).any(func(clan): return clan.get("clan_id") == rule.get("clan_id") and clan.get("candidates", []).any(func(candidate): return candidate.get("character_id") == rule.successor_id)) or raw.character_states[rule.owner_id].get("clan_id") != rule.get("clan_id"): return Rules.fail("遗产继任缺少实际同族配置")
		var heirs := {}
		for heir in rule.heirs:
			if not heir is Dictionary or not raw.character_states.has(heir.get("character_id")) or heirs.has(heir.character_id) or heir.character_id == rule.owner_id or not Rules.amount(heir.get("weight"), true) or not heir.get("willing") is bool or raw.resource_accounts.get(heir.get("account_id"), {}).get("owner_ref") != {"entity_kind": "character", "entity_id": heir.character_id}: return Rules.fail("继承人份额或私账无效")
			heirs[heir.character_id] = heir
		for id in rule.bequests:
			if not raw.management_assets.has(id) or not heirs.has(rule.bequests[id]): return Rules.fail("动产遗赠引用缺失物品或继承人")
		if rule.has("continue_private_production") and not rule.continue_private_production is bool: return Rules.fail("原私人生产委托延续安排无效")
		if rule.has("residual_movable_heir") and not heirs.has(rule.residual_movable_heir): return Rules.fail("剩余动产受赠人不是所列继承人")
		var resource_definition := ResourceDistribution.validate_definition(raw, rule)
		if not resource_definition.ok: return resource_definition
		var row: Dictionary = raw.economic_contracts.get(rule.estate_id, {})
		if row.is_empty(): continue
		if row.get("contract_kind") != "personal_estate" or row.get("source_id") != SOURCE or row.get("owner_id") != rule.owner_id or row.get("executor_id") != rule.executor_id or row.get("account_id") != rule.account_id or row.get("location_id") != rule.location_id or row.get("status") not in ["pending", "settled"] or row.has("processing_plan") or not row.get("payments") is Array or not row.get("items") is Array or not Rules.amount(row.get("created_day")) or int(row.created_day) < int(rule.death_day) or int(row.created_day) > int(raw.current_day) or raw.character_states[rule.owner_id].get("status") != "dead": return Rules.fail("遗产登记与实际死者、来源或处理状态不符")
		var death: Dictionary = raw.action_receipts.get(row.get("death_receipt"), {})
		if not death.get("effect_refs", []).has(rule.estate_id) or death.get("executor_id") != rule.owner_id or death.get("day") != row.created_day: return Rules.fail("死亡登记缺少对应本人、日期和实际动作回执")
		var paid_orders_valid := PaidProduction.validate(raw, rule, row)
		if not paid_orders_valid.ok: return paid_orders_valid
		var continuation_valid := Continuation.validate(raw, rule, row, death)
		if not continuation_valid.ok: return continuation_valid
		if row.has("settlement_request"):
			var asked: Variant = row.settlement_request
			if not asked is Dictionary or asked.size() != 5 or asked.get("estate_id") != rule.estate_id or not heirs.has(asked.get("requester_id")) or asked.get("executor_id") != rule.executor_id or not Rules.amount(asked.get("day")) or int(asked.day) < int(row.created_day) or int(asked.day) > int(raw.current_day): return Rules.fail("遗产请求缺少实际继承人、受托人或日期")
			var asking_receipt: Dictionary = raw.action_receipts.get(asked.get("execution_id"), {})
			if asking_receipt.get("estate_request") != asked or asking_receipt.get("executor_id") != asked.requester_id or asking_receipt.get("day") != asked.day or not asking_receipt.get("effect_refs", []).has(rule.estate_id): return Rules.fail("遗产请求与真实继承人确认回执不符")
		if row.status == "pending":
			if not row.payments.is_empty() or not row.items.is_empty() or row.has("resource_totals") or row.get("settlement_receipt") != "": return Rules.fail("待办遗产不能已有半笔分配")
			continue
		var receipt: Dictionary = raw.action_receipts.get(row.get("settlement_receipt"), {})
		var legacy_manual: bool = not rule.has("executor_willing") and not row.has("settlement_request") and not receipt.has("estate_work")
		if not receipt.get("effect_refs", []).has(rule.estate_id) or receipt.get("executor_id") != rule.executor_id or (not legacy_manual and receipt.get("estate_work") != rule.estate_id) or not Rules.amount(row.get("net_cash")): return Rules.fail("遗产分配缺少实际经办人、工日回执或实际余款")
		if row.has("settlement_request") and int(receipt.day) < int(row.settlement_request.day): return Rules.fail("遗产不能在继承人请求前声称完成经办")
		var journal_ids: Array = []
		var shares := {}
		for payment in row.payments:
			if not payment is Dictionary or not Rules.amount(payment.get("amount"), true) or payment.get("kind") not in ["debt", "share", "resource_share"] or journal_ids.has(payment.get("execution_id")): return Rules.fail("遗产支付记录无效或重复")
			var journal: Dictionary = raw.resource_journal.get(payment.get("execution_id"), {})
			if journal.get("source_account_id") != payment.get("source_account_id", rule.account_id) or journal.get("unit_id") != payment.get("unit_id", "cash_unit") or journal.get("destination_account_id") != payment.get("destination_account_id") or journal.get("amount") != payment.amount or journal.get("reason_ref") != payment.get("reason_ref") or journal.get("actor_id") != rule.executor_id: return Rules.fail("遗产分配与实际转账不符")
			if payment.kind != "resource_share" and (payment.get("source_account_id", rule.account_id) != rule.account_id or payment.get("unit_id", "cash_unit") != "cash_unit"): return Rules.fail("现金债务与份额不能改用其他资源支付")
			journal_ids.append(payment.execution_id)
			if payment.kind == "share":
				if payment.reason_ref != rule.estate_id or shares.has(payment.destination_account_id): return Rules.fail("遗产份额重复或缺失来源")
				shares[payment.destination_account_id] = int(payment.amount)
			elif payment.kind == "debt":
				var loan: Dictionary = raw.economic_contracts.get(payment.reason_ref, {})
				if loan.get("contract_kind") != "pawn_loan" or loan.get("borrower_id") != rule.owner_id or loan.get("status") != "redeemed" or loan.get("lender_account_id") != payment.destination_account_id or not loan.get("execution_refs", []).has(payment.execution_id) or int(loan.get("principal", -1)) + int(loan.get("fee", -1)) != int(payment.amount): return Rules.fail("遗产还债未保留实际借据及清偿")
		var resource_settlement := ResourceDistribution.validate_settlement(raw, rule, row, receipt)
		if not resource_settlement.ok: return resource_settlement
		if journal_ids != receipt.get("journal_refs"): return Rules.fail("遗产回执丢失实际支付")
		var total_weight := 0
		for heir in rule.heirs: total_weight += int(heir.weight)
		var remaining := int(row.net_cash)
		for index in rule.heirs.size():
			var heir: Dictionary = rule.heirs[index]
			var expected := remaining if index == rule.heirs.size() - 1 else int(int(row.net_cash) * int(heir.weight) / total_weight)
			remaining -= expected
			if shares.get(heir.account_id, 0) != expected: return Rules.fail("实际继承份额与配置不符")
			shares.erase(heir.account_id)
		if not shares.is_empty(): return Rules.fail("遗产流向未约定继承人")
		var item_ids: Array = []
		for item in row.items:
			if not item is Dictionary or item_ids.has(item.get("asset_id")) or heir_for(rule, str(item.get("asset_id", ""))) != item.get("heir_id"): return Rules.fail("遗赠物品无配置或重复")
			item_ids.append(item.asset_id)
			if not raw.management_assets[item.asset_id].get("transfer_history", []).any(func(delivery): return delivery.get("estate_id") == rule.estate_id and delivery.get("execution_id") == row.settlement_receipt and delivery.get("from_ref") == {"entity_kind": "character", "entity_id": rule.owner_id} and delivery.get("to_ref") == {"entity_kind": "character", "entity_id": item.heir_id}): return Rules.fail("遗赠缺少实际产权交割")
		for asset in raw.management_assets.values():
			if asset.owner_ref == owner: return Rules.fail("已分配遗产不能遗漏死者原有实物")
			if asset.get("transfer_history", []).any(func(delivery): return delivery.get("estate_id") == rule.estate_id) and not item_ids.has(asset.asset_id): return Rules.fail("遗产清单丢失实际动产交割")
	for row in raw.economic_contracts.values():
		if row.get("contract_kind") == "personal_estate" and not seen.has(row.contract_id): return Rules.fail("遗产合同缺少配置来源")
	for receipt in raw.action_receipts.values():
		if receipt.has("estate_collection"):
			var record: Variant = receipt.estate_collection
			if not record is Dictionary or record.size() != 3 or raw.economic_contracts.get(record.get("estate_id"), {}).get("collected_orders", {}).get(record.get("order_id")) != receipt.execution_id: return Rules.fail("原已付款订单接管回执丢失实际遗产记录")
		if receipt.has("estate_resources") and (not receipt.has("estate_work") or not Continuation.same(raw.economic_contracts.get(receipt.get("estate_work"), {}).get("resource_totals"), receipt.estate_resources)): return Rules.fail("其他遗产资源回执缺少实际结算总量")
		if receipt.has("estate_continuation"):
			var proof: Variant = receipt.estate_continuation
			if not proof is Dictionary or not raw.economic_contracts.get(proof.get("estate_id"), {}).get("production_continuations", {}).get(proof.get("task_id"), {}).get("pending_execution_ids", []).has(receipt.execution_id): return Rules.fail("遗产原委托执行回执丢失承继来源")
		if receipt.has("estate_request"):
			var asked: Variant = receipt.estate_request
			if not asked is Dictionary or raw.economic_contracts.get(asked.get("estate_id"), {}).get("settlement_request") != asked: return Rules.fail("遗产遗漏已确认的经办请求")
		if receipt.has("estate_work"):
			if not receipt.estate_work is String: return Rules.fail("遗产工日引用无效")
			var estate: Dictionary = raw.economic_contracts.get(receipt.estate_work, {})
			if estate.get("contract_kind") != "personal_estate" or estate.get("status") != "settled" or estate.get("settlement_receipt") != receipt.execution_id: return Rules.fail("遗产工日没有实际完成记录")
	return {"ok": true}
