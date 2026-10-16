extends RefCounted

const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Contract = preload("res://scripts/core/management_state_contract.gd")

static func initialize(state, data: Dictionary) -> Dictionary:
	var config: Dictionary = data.get("management", {}).get("regional_administration", {})
	if config.is_empty(): return {"ok": true}
	for definition in config.offices:
		var id: String = definition.id
		if not state.office_state.has(id): return Contract.fail("地方职位未装载：" + id)
		var office: Dictionary = state.office_state[id]
		for field in ["role_key", "remuneration_terms"]: office[field] = definition[field].duplicate(true) if definition[field] is Dictionary else definition[field]
		if definition.has("entry_school_id"): office["entry_school_id"] = str(definition.entry_school_id)
		office["scope_ref"] = {"entity_kind": "local_node", "entity_id": str(definition.jurisdiction[0])}
		office["work_schedule"] = config.work_schedule.duplicate(true)
		office["content_basis"] = config.content_basis
		office["source_id"] = config.source_id
	for initial in config.public_accounts:
		var id: String = initial.account_id
		var depot := "public_" + id
		if state.resource_accounts.has(id) or state.depot_states.has(depot) or not state.office_state.has(initial.office_id) or not state.local_node_state.has(initial.location_id) or not Contract.amount(initial.amount): return Contract.fail("地方公账来源或实库无效")
		var owner := {"entity_kind": "office", "entity_id": initial.office_id}
		state.depot_states[depot] = {"depot_id": depot, "location_node_id": initial.location_id, "owner_office_id": initial.office_id, "owner_character_id": "", "owner_organization_id": initial.organization_id, "capacity": Contract.MAX_AMOUNT, "stock": {"silk_cash": int(initial.amount)}}
		state.resource_accounts[id] = {"account_id": id, "owner_ref": owner, "organization_id": initial.organization_id, "location_id": initial.location_id, "resource_key": "silk_cash", "unit_id": "cash_unit", "storage_ref": {"storage_kind": "depot", "storage_id": depot, "resource_key": "silk_cash"}, "operator_refs": []}
		if int(initial.amount) > 0:
			var entry := "initial:" + id
			state.resource_journal[entry] = {"entry_id": entry, "execution_id": entry, "entry_kind": "initial_grant", "source_ref": {"entity_kind": "rule", "entity_id": initial.office_id, "rule_id": initial.source_id}, "destination_ref": owner.duplicate(true), "destination_account_id": id, "amount": int(initial.amount), "unit_id": "cash_unit", "reason_ref": initial.source_id, "day": 0}
	for initial in config.initial_terms:
		if not state.character_states.has(initial.holder_id) or not state.office_state.has(initial.office_id): return Contract.fail("地方初始任期人物或职位缺失")
		var id := "initial_regional:" + str(initial.office_id)
		if state.office_terms.has(id): return Contract.fail("重复地方初始任期")
		state.office_terms[id] = {"term_id": id, "office_id": initial.office_id, "holder_id": initial.holder_id, "start_day": 0, "end_day": -1, "appointment_mode": "initial", "appointment_transaction_id": "bootstrap|anshi_beta_1_14", "ended_by": "", "performance_refs": [], "settled_reward_keys": []}
		attach_payroll(state, id)
	sync_operators(state)
	return validate(state.to_dictionary())

static func sync_operators(state) -> void:
	for account in state.resource_accounts.values():
		if account.get("owner_ref", {}).get("entity_kind") != "office" or account.get("storage_ref", {}).get("storage_kind") != "depot": continue
		var office: Dictionary = state.office_state.get(account.owner_ref.entity_id, {})
		var holder := str(office.get("holder_id", ""))
		account.operator_refs = [{"entity_kind": "character", "entity_id": holder}] if office.get("status") == "appointed" and not holder.is_empty() else []

static func attach_payroll(state, term_id: String) -> void:
	var term: Dictionary = state.office_terms[term_id]
	var office: Dictionary = state.office_state.get(term.office_id, {})
	if office.get("office_kind") != "regional" or not office.has("remuneration_terms") or term.has("payroll"): return
	term["payroll"] = {"terms": office.remuneration_terms.duplicate(true), "last_accrual_day": int(term.start_day), "accrued": 0, "paid": 0, "arrears": 0, "next_due_day": int(term.start_day) + int(office.remuneration_terms.period_days), "payment_refs": []}

static func after_office_change(state, office_id: String) -> Dictionary:
	if state.office_state.get(office_id, {}).get("office_kind") != "regional": return {"ok": true}
	sync_operators(state)
	for id in state.office_terms:
		if state.office_terms[id].get("office_id") == office_id: attach_payroll(state, id)
	return settle_daily(state, office_id)

# Public salary is earned by actual elapsed days of a recorded term. The public
# depot pays the person's private depot; a failed payment remains an obligation.
static func settle_daily(state, office_id: String = "") -> Dictionary:
	var accounts = Accounts.new()
	for term in state.office_terms.values():
		if not office_id.is_empty() and term.get("office_id") != office_id: continue
		if not term.has("payroll"): continue
		var payroll: Dictionary = term.payroll
		var through := int(state.current_day) if int(term.end_day) < 0 else mini(int(state.current_day), int(term.end_day))
		if through < int(payroll.last_accrual_day): return Contract.fail("地方任期俸给日期倒退")
		var elapsed := through - int(payroll.last_accrual_day)
		if elapsed > (Contract.MAX_AMOUNT - int(payroll.accrued)) / int(payroll.terms.daily_amount): return Contract.fail("地方俸给累计越界")
		payroll.accrued += elapsed * int(payroll.terms.daily_amount)
		payroll.last_accrual_day = through
		payroll.arrears = int(payroll.accrued) - int(payroll.paid)
		if int(payroll.arrears) == 0 or (int(term.end_day) < 0 and int(state.current_day) < int(payroll.next_due_day)): continue
		var account: Dictionary = state.resource_accounts.get(payroll.terms.account_id, {})
		var operators: Array = account.get("operator_refs", [])
		var execution := "regional-wage:%s:%d" % [str(term.term_id), int(payroll.accrued)]
		var paid := accounts.apply(state, "transfer", {"execution_id": execution, "source_account_id": payroll.terms.account_id, "destination_account_id": str(term.holder_id) + "_cash", "actor_id": str(operators[0].entity_id) if not operators.is_empty() else "", "amount": int(payroll.arrears), "reason_ref": str(term.term_id)})
		if not paid.get("ok", false):
			payroll["payment_blocked_reason"] = str(paid.get("error", "州库俸给尚未支付"))
			continue
		payroll.payment_refs.append(paid.result_ref)
		payroll.paid = int(payroll.accrued)
		payroll.arrears = 0
		payroll.next_due_day = through + int(payroll.terms.period_days)
		payroll.erase("payment_blocked_reason")
	return {"ok": true}

static func validate(raw: Dictionary) -> Dictionary:
	var offices: Dictionary = raw.get("office_state", {})
	var accounts: Dictionary = raw.get("resource_accounts", {})
	var characters: Dictionary = raw.get("character_states", {})
	for office in offices.values():
		if office.get("office_kind") != "regional": continue
		var terms: Variant = office.get("remuneration_terms")
		if not terms is Dictionary or not Contract.amount(terms.get("daily_amount"), true) or not Contract.amount(terms.get("period_days"), true) or terms.get("unit_id") != "cash_unit" or not accounts.has(terms.get("account_id")): return Contract.fail("地方职位缺少俸给来源或周期")
		if accounts[terms.account_id].get("organization_id") != office.get("organization_id"): return Contract.fail("地方俸给不可借用其他组织公账")
		if not office.get("work_schedule") is Dictionary or not office.work_schedule.get("days") is Array or office.work_schedule.days.size() != 7 or not office.work_schedule.get("duty_work_kinds") is Array or not str(office.work_schedule.get("source_id", "")).begins_with("scenario:"): return Contract.fail("地方职位缺少实际值勤规则")
		var weekdays: Array = []
		for day in office.work_schedule.days:
			if not Contract.amount(day) or int(day) > 6 or weekdays.has(int(day)): return Contract.fail("地方值勤日期重复或越界")
			weekdays.append(int(day))
		if not raw.get("local_node_state", {}).has(office.get("scope_ref", {}).get("entity_id")) or not str(office.get("source_id", "")).begins_with("scenario:"): return Contract.fail("地方职位缺少实际履职地或场景依据")
		var holder := str(office.get("holder_id", ""))
		if not holder.is_empty():
			var active: Array = raw.get("office_terms", {}).values().filter(func(term): return term.get("office_id") == office.office_id and int(term.get("end_day", 0)) < 0 and term.get("holder_id") == holder)
			if not characters.has(holder) or active.size() != 1: return Contract.fail("地方在任者缺少唯一实际任期")
	for term in raw.get("office_terms", {}).values():
		var office: Dictionary = offices.get(term.get("office_id", ""), {})
		if office.get("office_kind") != "regional":
			if term.has("payroll"): return Contract.fail("地方俸给指向其他职位")
			continue
		var payroll: Variant = term.get("payroll")
		if not payroll is Dictionary or payroll.get("terms") != office.get("remuneration_terms") or not payroll.get("payment_refs") is Array: return Contract.fail("地方任期丢失俸给合同")
		for field in ["last_accrual_day", "accrued", "paid", "arrears", "next_due_day"]:
			if not Contract.amount(payroll.get(field)): return Contract.fail("地方俸给金额或日期无效")
		if int(payroll.next_due_day) < int(term.start_day) + int(payroll.terms.period_days): return Contract.fail("地方俸给首次结付日早于实际合同")
		var limit := int(raw.get("current_day", 0)) if int(term.end_day) < 0 else int(term.end_day)
		if int(payroll.last_accrual_day) < int(term.start_day) or int(payroll.last_accrual_day) > limit or int(payroll.accrued) != (int(payroll.last_accrual_day) - int(term.start_day)) * int(payroll.terms.daily_amount) or int(payroll.paid) > int(payroll.accrued) or int(payroll.arrears) != int(payroll.accrued) - int(payroll.paid): return Contract.fail("地方俸给与实际任期不符")
		var paid_total := 0
		var seen: Array = []
		for id in payroll.payment_refs:
			var journal: Dictionary = raw.get("resource_journal", {}).get(id, {})
			if seen.has(id) or journal.get("entry_kind") != "transfer" or journal.get("source_account_id") != payroll.terms.account_id or journal.get("destination_account_id") != str(term.holder_id) + "_cash" or journal.get("reason_ref") != term.term_id or not Contract.amount(journal.get("amount"), true): return Contract.fail("地方俸给缺少实际公私转账凭据")
			seen.append(id)
			paid_total += int(journal.amount)
		if paid_total != int(payroll.paid): return Contract.fail("地方俸给已付数与账簿不符")
	return {"ok": true}
