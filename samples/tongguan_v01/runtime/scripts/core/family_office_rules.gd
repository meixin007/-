extends RefCounted

const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Contract = preload("res://scripts/core/management_state_contract.gd")
const Transaction = preload("res://scripts/core/game_state_transaction.gd")
const Workload = preload("res://scripts/core/character_workload_service.gd")

static func is_family(state, office_id: String) -> bool:
	return state != null and state.office_state.get(office_id, {}).get("office_kind") == "family"

static func authority(state, office_id: String, actor_id: String) -> bool:
	var office: Dictionary = state.office_state.get(office_id, {})
	var ref: Dictionary = office.get("authority_ref", {})
	var account: Dictionary = state.resource_accounts.get(ref.get("entity_id", ""), {})
	return ref.get("entity_kind") == "account_operator" and (account.get("operator_refs", []) as Array).any(func(operator): return operator.get("entity_kind") == "character" and operator.get("entity_id") == actor_id)

static func offer_wage(context, office_id: String, amount: Variant) -> Dictionary:
	if context == null or context.state == null or not Contract.amount(amount, true):
		return Contract.fail("工资必须是正整数记账单位")
	var input := {"office_id": office_id, "amount": int(amount), "actor_id": context.state.player_character_id}
	var transaction = Transaction.new()
	var preview := transaction.preview_command(context.state, "family_office_terms", input)
	if not preview.get("ok", false):
		return preview
	return transaction.execute_command(context, transaction.build_command_envelope("family_office_terms", input, preview.preview_token), func(working):
		if not authority(working.state, office_id, input.actor_id):
			return Contract.fail("无权调整该家族的聘用报价")
		var office: Dictionary = working.state.office_state[office_id]
		if not str(office.holder_id).is_empty():
			return Contract.fail("在任雇用合同需双方重议；不能单方面改写已签工资")
		office.remuneration_terms.amount = int(amount)
		return {"ok": true, "result_ref": office_id}
	)

static func assess(state, data: Dictionary, office_id: String, candidate_id: String, proposed_wage: int = -1, proposed_office: Dictionary = {}) -> Dictionary:
	var office: Dictionary = state.office_state.get(office_id, {}) if proposed_office.is_empty() else proposed_office
	var reason := ""
	var candidate: Dictionary = {}
	for character in data.get("characters", []):
		if character.get("id") == candidate_id:
			candidate = character
	var preferences: Dictionary = candidate.get("employment_preferences", {})
	var salary: int = proposed_wage if proposed_wage >= 0 else int(office.get("remuneration_terms", {}).get("amount", 0))
	var agreed: bool = load("res://scripts/core/social_agreement_service.gd").employment_consent(state, office_id, candidate_id, salary)
	var conflict := ""
	for other in state.office_state.values():
		if other.get("office_id") != office_id and other.get("holder_id") == candidate_id and not candidate_id.is_empty() and (other.get("office_kind") != "family" or other.get("organization_id") != office.get("organization_id") or Workload.overlaps(office, other)):
			conflict = str(other.office_id)
	for obligation in state.economic_contracts.values():
		if obligation.get("contract_kind") in ["production", "manufacturing_batch", "setup", "character_search"] and obligation.get("status") == "working" and obligation.get("supplier_id", obligation.get("executor_id", "")) == candidate_id and not Workload.can_schedule(state, candidate_id, str(obligation.contract_kind), str(obligation.get("principal_id", obligation.get("customer_id", ""))), office):
			conflict = str(obligation.contract_id)
	if not state.character_states.has(candidate_id) or state.character_states[candidate_id].get("status") in ["dead", "deceased", "executed", "missing", "imprisoned", "departed", "exiled", "unreachable"]:
		reason = "人物不存在或已无法履职"
	elif not agreed and not (preferences.get("roles", []) as Array).has(office.get("role_key")):
		reason = "本人未表示愿意从事这一职责"
	elif not agreed and not (preferences.get("organization_ids", []) as Array).has(office.get("organization_id")):
		reason = "本人不愿接受该家的聘用"
	elif str(state.character_states[candidate_id].get("location_id", "")) != str(office.get("scope_ref", {}).get("entity_id", "")):
		reason = "人物尚未到履职地，需要先安排赴任"
	elif not agreed and salary < int(preferences.get("minimum_wage", 0)):
		reason = "本人要求每期至少 %d 记账单位，现报价 %d" % [int(preferences.minimum_wage), salary]
	elif not conflict.is_empty():
		reason = "任职排班或已有履约工时冲突，需先完成原事务或办理交接"
	else:
		reason = "本人愿按每 %d 日 %d 记账单位受雇" % [int(office.remuneration_terms.period_days), salary]
		return {"ok": true, "grade": "eligible", "reasons": [reason], "reason": reason, "conflict_office": "", "cost_effects": [{"cash": salary}], "candidate_id": candidate_id, "office_id": office_id, "rule_fingerprint": (office_id + candidate_id + str(salary)).sha256_text()}
	return {"ok": true, "grade": "prohibited", "reasons": [reason], "reason": reason, "conflict_office": conflict, "cost_effects": [], "candidate_id": candidate_id, "office_id": office_id, "rule_fingerprint": reason.sha256_text()}

static func preview(context, office_id: String, candidate_id: String) -> Dictionary:
	var state = context.state
	if not authority(state, office_id, state.player_character_id):
		return Contract.fail("没有该家族职位的任用权")
	var assessment := assess(state, context.scenario_data, office_id, candidate_id)
	if assessment.grade != "eligible":
		return Contract.fail(assessment.reason)
	var office: Dictionary = state.office_state[office_id]
	if not str(office.holder_id).is_empty():
		return Contract.fail("职位已有任职者，请先办理卸任交接")
	var terms: Dictionary = office.remuneration_terms
	if Accounts.new().available(state, terms.account_id) < int(terms.amount):
		return Contract.fail("家族可用款不足支付首期工资")
	var input := {"office_id": office_id, "candidate_id": candidate_id, "actor_id": state.player_character_id, "mode": "normal", "remuneration_terms": terms.duplicate(true)}
	var transaction = Transaction.new()
	var result := transaction.preview_command(state, "appoint_office", input, office_id)
	if not result.get("ok", false):
		return result
	return {"ok": true, "code": "preview_ready", "office_id": office_id, "candidate_id": candidate_id, "mode": "normal", "qualification": assessment, "rapid_reversal": {"cost": "%d 记账单位首期工资" % int(terms.amount)}, "envelope": transaction.build_command_envelope("appoint_office", input, result.preview_token), "preview_token": result.preview_token}

# The authorized ordered pool and quoted terms are immutable. Choosing an
# available member changes only the actual employment result, never the plan.
static func pool_cost(state, params: Dictionary) -> Dictionary:
	var office: Dictionary = state.office_state.get(params.get("office_id", ""), {})
	var ids: Variant = params.get("candidate_ids")
	if office.get("office_kind") != "family" or not ids is Array or ids.is_empty() or not Contract.amount(params.get("wage_amount"), true) or not Contract.amount(params.get("period_days"), true): return Contract.fail("候选范围与薪酬约定不完整")
	var seen := {}
	for id in ids:
		if not id is String or not state.character_states.has(id) or seen.has(id): return Contract.fail("候选范围包含缺失或重复人物")
		seen[id] = true
	return {"ok": true, "account_id": office.remuneration_terms.account_id, "amount": int(params.wage_amount)}

static func appoint_from_pool(state, data: Dictionary, params: Dictionary, actor: String, execution: String, reservation: String) -> Dictionary:
	var cost := pool_cost(state, params)
	if not cost.ok: return cost
	var office: Dictionary = state.office_state[params.office_id]
	if int(office.remuneration_terms.amount) != int(params.wage_amount) or int(office.remuneration_terms.period_days) != int(params.period_days): return Contract.fail("薪酬条件已超出原约定，请重新商议；未扩大授权或付款")
	var unavailable: Array[String] = []
	for id in params.candidate_ids:
		var assessment := assess(state, data, params.office_id, id)
		if assessment.grade != "eligible":
			unavailable.append(str(state.character_states[id].name) + "：" + str(assessment.reason))
			continue
		var result := appoint(state, data, {"office_id": params.office_id, "candidate_id": id, "actor_id": actor, "remuneration_terms": office.remuneration_terms.duplicate(true), "reservation_id": reservation}, execution)
		if result.get("ok", false): result["visible_summary"] = "已按约定候选范围聘用%s，每 %d 日 %d；%s" % [state.character_states[id].name, int(params.period_days), int(params.wage_amount), "首选可用" if unavailable.is_empty() else "；".join(unavailable)]
		return result
	return Contract.fail("约定候选均无法受聘，请商议调整范围；" + "；".join(unavailable))

static func appoint(state, data: Dictionary, input: Dictionary, transaction_id: String) -> Dictionary:
	var office_id := str(input.get("office_id", ""))
	var candidate_id := str(input.get("candidate_id", ""))
	var actor_id := str(input.get("actor_id", ""))
	if not authority(state, office_id, actor_id):
		return Contract.fail("家族任用主体缺少权源")
	var office: Dictionary = state.office_state[office_id]
	if not str(office.holder_id).is_empty():
		return Contract.fail("职位已有任职者")
	var assessment := assess(state, data, office_id, candidate_id)
	if assessment.grade != "eligible":
		return Contract.fail(assessment.reason)
	if input.get("remuneration_terms") != office.remuneration_terms:
		return Contract.fail("工资条件已改变，请重新预览")
	var terms: Dictionary = office.remuneration_terms
	var contract_id := "employment:" + transaction_id
	var paid := Accounts.new().apply(state, "transfer", {"execution_id": "wage:" + transaction_id, "source_account_id": terms.account_id, "destination_account_id": candidate_id + "_cash", "amount": int(terms.amount), "actor_id": actor_id, "reason_ref": contract_id, "reservation_id": str(input.get("reservation_id", ""))})
	if not paid.get("ok", false):
		return paid
	_create_term(state, office_id, candidate_id, transaction_id, "normal", int(state.current_day) + int(terms.period_days), contract_id)
	state.economic_contracts[contract_id]["execution_refs"] = [paid.result_ref]
	return {"ok": true, "code": "appointed", "candidate_id": candidate_id, "office_id": office_id, "result_ref": contract_id}

static func _create_term(state, office_id: String, candidate_id: String, transaction_id: String, mode: String, next_due_day: int, contract_id: String) -> void:
	var office: Dictionary = state.office_state[office_id]
	var term_id := "term:" + contract_id
	state.office_terms[term_id] = {"term_id": term_id, "office_id": office_id, "holder_id": candidate_id, "start_day": int(state.current_day), "end_day": -1, "appointment_mode": mode, "appointment_transaction_id": transaction_id, "ended_by": "", "performance_refs": [], "settled_reward_keys": [], "contract_id": contract_id}
	state.economic_contracts[contract_id] = {"contract_id": contract_id, "contract_kind": "employment", "party_refs": [office.organization_id, candidate_id], "organization_id": office.organization_id, "employee_id": candidate_id, "office_id": office_id, "term_id": term_id, "terms_version": 1, "status": "active", "remuneration_terms": office.remuneration_terms.duplicate(true), "next_due_day": next_due_day, "arrears": 0, "execution_refs": []}
	office.holder_id = candidate_id
	office.status = "appointed"
	state.office_history.append({"office_id": office_id, "holder_id": candidate_id, "previous_holder_id": "", "day": state.current_day, "source": "family_employment", "transaction_id": transaction_id})

static func dismiss(state, office_id: String, transaction_id: String) -> Dictionary:
	var office: Dictionary = state.office_state[office_id]
	var holder_id := str(office.get("holder_id", ""))
	if holder_id.is_empty():
		return Contract.fail("职位已经空缺")
	for term in state.office_terms.values():
		if term.get("office_id") == office_id and int(term.get("end_day", 0)) < 0:
			term.end_day = int(state.current_day)
			term.ended_by = transaction_id
			var contract: Dictionary = state.economic_contracts[term.contract_id]
			contract.status = "terminated" if int(contract.arrears) == 0 else "ended_unpaid"
	office.holder_id = ""
	office.status = "vacant"
	state.office_history.append({"office_id": office_id, "previous_holder_id": holder_id, "holder_id": "", "day": state.current_day, "source": "family_handover", "transaction_id": transaction_id})
	load("res://scripts/core/household_membership_service.gd").sync_person(state, holder_id)
	return {"ok": true, "code": "removed", "holder_id": holder_id, "office_id": office_id, "result_ref": office_id}

static func pay_debt(state, contract_id: String, actor_id: String, execution_id: String, reservation_id: String = "") -> Dictionary:
	var debt: Dictionary = state.economic_contracts.get(contract_id, {})
	if debt.get("contract_kind") != "employment" or debt.get("status") != "ended_unpaid" or int(debt.get("arrears", 0)) <= 0:
		return Contract.fail("没有这份已结束雇约的未付工资")
	if not authority(state, debt.office_id, actor_id):
		return Contract.fail("没有该雇主的付款权源")
	var paid := Accounts.new().apply(state, "transfer", {"execution_id": execution_id, "source_account_id": debt.remuneration_terms.account_id, "destination_account_id": debt.employee_id + "_cash", "amount": int(debt.arrears), "actor_id": actor_id, "reason_ref": contract_id, "reservation_id": reservation_id})
	if not paid.get("ok", false):
		return paid
	debt.execution_refs.append(execution_id)
	debt.arrears = 0
	debt.status = "terminated"
	debt.erase("payment_blocked_reason")
	return {"ok": true, "result_ref": contract_id}

static func initialize(state, data: Dictionary) -> Dictionary:
	for definition in data.get("management", {}).get("family_offices", []):
		if definition is Dictionary and definition.has("personal_business_owner_id"):
			if definition.personal_business_owner_id!=definition.get("organization_id") or definition.get("remuneration_terms",{}).get("account_id")!=str(definition.personal_business_owner_id)+"_cash": return Contract.fail("个人经营岗位的本人账户来源无效")
			if definition.personal_business_owner_id!=state.player_character_id: continue
		if not definition is Dictionary or state.office_state.has(definition.get("office_id")):
			return Contract.fail("重复或损坏的家族职位定义")
		var office: Dictionary = definition.duplicate(true)
		office["work_schedule"] = data.get("management", {}).get("family_work_schedules", {}).get(office.get("role_key"), {}).duplicate(true)
		var days: Array = office.work_schedule.get("days", []).map(func(day): return str(7 if int(day) == 0 else int(day)))
		days.sort()
		office.duties.append("每七日轮值：第 %s 日；其他差事须避开值勤或属于获准本职事务。" % "、".join(days))
		office.responsibility_text = str(office.get("responsibility_text", "")) + "\n" + str(office.duties.back())
		var account: Dictionary = state.resource_accounts.get(office.get("remuneration_terms", {}).get("account_id", ""), {})
		if account.is_empty() or account.owner_ref.entity_id != office.get("organization_id") or not state.local_node_state.has(office.get("scope_ref", {}).get("entity_id")):
			return Contract.fail("家族职位缺少组织账户或履职地")
		office["holder_id"] = ""
		office["status"] = "vacant"
		state.office_state[office.office_id] = office
	for initial in data.get("management", {}).get("initial_family_terms", []):
		var assessment := assess(state, data, initial.office_id, initial.holder_id)
		if assessment.grade != "eligible":
			return Contract.fail("初始家族任职无效：" + assessment.reason)
		var period := int(state.office_state[initial.office_id].remuneration_terms.period_days)
		_create_term(state, initial.office_id, initial.holder_id, "bootstrap|anshi_beta_1_14", "initial", period, "initial_employment:" + initial.office_id)
	return {"ok": true}

# Called once by the shared daily coordinator, including when UI supplies callbacks.
static func settle_daily(state) -> Dictionary:
	var accounts = Accounts.new()
	for contract in state.economic_contracts.values():
		if contract.get("contract_kind") != "employment" or contract.get("status") != "active":
			continue
		var terms: Dictionary = contract.remuneration_terms
		var office: Dictionary = state.office_state[contract.office_id]
		while int(contract.next_due_day) <= int(state.current_day):
			terms=load("res://scripts/core/business_wage_service.gd").terms_on_day(contract,int(contract.next_due_day))
			var wage_id := "wage:%s:%d" % [contract.contract_id, int(contract.next_due_day)]
			if not state.resource_journal.has(wage_id):
				var operators: Array = state.resource_accounts[terms.account_id].operator_refs
				var actor := str(operators[0].entity_id) if not operators.is_empty() else ""
				var payroll: Dictionary=load("res://scripts/core/business_payroll_service.gd").source(state,contract,actor)
				var paid: Dictionary=accounts.apply(state, "transfer", {"execution_id": wage_id, "source_account_id": payroll.account_id, "destination_account_id": contract.employee_id + "_cash", "amount": int(terms.amount), "actor_id": actor, "reason_ref": contract.contract_id}) if payroll.ok else payroll
				if not paid.get("ok", false):
					contract["arrears"] = load("res://scripts/core/business_wage_service.gd").due_total(contract,int(state.current_day))
					contract["payment_blocked_reason"] = str(paid.get("error", "工资未支付"))
					break
				contract.execution_refs.append(wage_id)
				state.resource_journal[wage_id]["wage_due_day"]=int(contract.next_due_day)
				if not str(payroll.get("authorization_id","")).is_empty():state.resource_journal[wage_id]["business_payroll_authorization_id"]=payroll.authorization_id
			contract.next_due_day += int(terms.period_days)
			contract.arrears = 0
			contract.erase("payment_blocked_reason")
		if str(state.character_states[contract.employee_id].get("status", "")) in ["dead", "executed", "departed"] and not str(office.holder_id).is_empty():
			dismiss(state, contract.office_id, "unavailable:%s:%d" % [contract.employee_id, int(state.current_day)])
	return {"ok": true}
