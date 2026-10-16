extends RefCounted

# Scenario gameplay audit timing, not a claim about historical Tang procedures.
const AUDIT_DELAY := 2
const GRACE_DAYS := 7
const NOTICE_LOSS := 8
const OVERDUE_LOSS := 12
const KINDS := ["repay_public_cash"]
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Contract = preload("res://scripts/core/management_state_contract.gd")

static func public_account(raw: Dictionary, id: String) -> bool:
	var account: Dictionary = raw.get("resource_accounts", {}).get(id, {})
	return account.get("unit_id") == "cash_unit" and account.get("owner_ref", {}).get("entity_kind") == "office" and raw.get("office_state", {}).get(account.get("owner_ref", {}).get("entity_id"), {}).get("office_kind") == "regional"

# A reason string alone is not a public expenditure voucher.
static func vouched(raw: Dictionary, journal_id: String) -> bool:
	for term in raw.get("office_terms", {}).values():
		if term.get("payroll", {}).get("payment_refs", []).has(journal_id): return true
	for order in raw.get("economic_contracts", {}).values():
		if order.get("contract_kind") == "school_exam_journey" and order.get("journal_refs", []).slice(0, 2).has(journal_id): return true
		if order.get("contract_kind") == "school_living_aid" and journal_id in [order.get("cash_ref"), order.get("purchase_ref")]: return true
		if order.get("contract_kind") == "public_work" and order.get("commission_receipt") == journal_id: return true
		if order.get("contract_kind") in ["school_teaching", "school_assessment", "school_supply"] and order.get("commission_receipt") == journal_id: return true
	return false

static func reconcile(state) -> Dictionary:
	var raw: Dictionary = state.to_dictionary()
	for entry in state.resource_journal.values():
		if entry.get("entry_kind") != "transfer" or not public_account(raw, str(entry.get("source_account_id", ""))): continue
		if public_account(raw, str(entry.get("destination_account_id", ""))) or vouched(raw, str(entry.entry_id)): continue
		var id := "public-cash:" + str(entry.entry_id)
		if state.economic_contracts.has(id): continue
		# Old receipts without a recorded principal remain unattributed; do not
		# silently attach a predecessor's outgoing payment to today's prefect.
		state.economic_contracts[id] = {"contract_id": id, "contract_kind": "public_cash_liability", "transfer_ref": entry.entry_id, "public_account_id": entry.source_account_id, "recipient_account_id": entry.destination_account_id, "responsible_id": str(entry.get("actor_id", "")), "amount": int(entry.amount), "remaining_amount": int(entry.amount), "created_day": int(entry.day), "status": "pending_review", "repayment_refs": [], "review_events": [], "due_day": -1, "source_id": "rule:regional_fiscal_review"}
	return {"ok": true}

static func settle_daily(state) -> Dictionary:
	reconcile(state)
	for case in state.economic_contracts.values():
		if case.get("contract_kind") != "public_cash_liability" or case.responsible_id.is_empty(): continue
		if case.review_events.is_empty() and int(state.current_day) >= int(case.created_day) + AUDIT_DELAY:
			var reviewer := _reviewer(state, case)
			if reviewer.is_empty(): continue
			_review(state, case, reviewer, "notice", NOTICE_LOSS)
			case.due_day = int(state.current_day) + GRACE_DAYS
			case.status = "repaid" if int(case.remaining_amount) == 0 else "notified"
		elif case.review_events.size() == 1 and int(case.remaining_amount) > 0 and int(state.current_day) > int(case.due_day):
			var reviewer := _reviewer(state, case)
			if reviewer.is_empty(): continue
			_review(state, case, reviewer, "overdue", OVERDUE_LOSS)
			case.status = "overdue"
	return {"ok": true}

static func _reviewer(state, case: Dictionary) -> Dictionary:
	var account: Dictionary = state.resource_accounts[case.public_account_id]
	for role in ["investigator", "judge", "secretary"]:
		for office in state.office_state.values():
			if office.get("role_key") != role or office.get("organization_id") != account.get("organization_id") or office.get("status") != "appointed": continue
			var holder := str(office.get("holder_id", ""))
			var person: Dictionary = state.character_states.get(holder, {})
			if holder == case.responsible_id or person.get("status") != "alive" or person.get("location_id") != account.get("location_id"): continue
			for term in state.office_terms.values():
				if term.get("office_id") == office.office_id and term.get("holder_id") == holder and int(term.get("end_day", -1)) < 0:
					return {"reviewer_id": holder, "office_id": office.office_id, "term_id": term.term_id}
	return {}

static func _review(state, case: Dictionary, reviewer: Dictionary, kind: String, loss: int) -> void:
	var person: Dictionary = state.character_states[reviewer.reviewer_id]
	if not person.has("relationships"): person["relationships"] = {}
	var before := int(person.relationships.get(case.responsible_id, 0))
	var after := clampi(before - loss, -100, 100)
	person.relationships[case.responsible_id] = after
	var event := reviewer.duplicate(true)
	event.merge({"kind": kind, "day": int(state.current_day), "trust_before": before, "trust_after": after, "outstanding_amount": int(case.remaining_amount)})
	case.review_events.append(event)

static func cost_for(state, params: Dictionary) -> Dictionary:
	var case: Dictionary = state.economic_contracts.get(params.get("case_id", ""), {})
	var account: Dictionary = state.resource_accounts.get(params.get("funding_account_id", ""), {})
	if case.get("contract_kind") != "public_cash_liability" or not Contract.amount(params.get("amount"), true) or int(params.amount) > int(case.remaining_amount): return Contract.fail("归还金额必须为正整数且不超过尚欠公款")
	if account.get("unit_id") != "cash_unit" or account.get("owner_ref", {}).get("entity_kind") not in ["character", "clan"]: return Contract.fail("归还须使用实际私款或家族款，不能挪用另一公账")
	return {"ok": true, "account_id": str(params.funding_account_id), "amount": int(params.amount)}

static func location_for(state, params: Dictionary) -> String:
	return Accounts.new().location(state, str(state.economic_contracts.get(params.get("case_id", ""), {}).get("public_account_id", "")))

static func apply(state, params: Dictionary, principal: String, execution: String, reservation: String) -> Dictionary:
	var cost := cost_for(state, params)
	if not cost.ok: return cost
	var case: Dictionary = state.economic_contracts[params.case_id]
	if case.responsible_id != principal: return Contract.fail("只能为本人已记录的公款责任办理归还")
	var result := Accounts.new().apply(state, "transfer", {"execution_id": execution, "source_account_id": params.funding_account_id, "destination_account_id": case.public_account_id, "amount": int(params.amount), "actor_id": principal, "reason_ref": case.contract_id, "reservation_id": reservation})
	if not result.get("ok", false): return result
	case.repayment_refs.append(execution)
	case.remaining_amount -= int(params.amount)
	if int(case.remaining_amount) == 0: case.status = "repaid"
	return {"ok": true, "result_ref": case.contract_id, "journal_refs": [execution], "visible_summary": "已归还公款 %d；原支出及核账记录保留。" % int(params.amount)}

static func project(state, viewer: String) -> Array:
	var result: Array = []
	for case in state.economic_contracts.values():
		if case.get("contract_kind") != "public_cash_liability": continue
		if case.responsible_id != viewer and not Accounts.new().can_operate(state, case.public_account_id, viewer): continue
		var row: Dictionary = case.duplicate(true)
		for event in row.review_events:
			event.erase("trust_before")
			event.erase("trust_after")
			event["public_expression"] = "要求说明凭据并归还公款。" if event.kind == "notice" else "对逾期未归还表示不满，继续追偿。"
		row["source_refs"] = [case.contract_id, case.transfer_ref]
		row["explanation"] = "此项公款转出尚无已核验的公共合同或俸给凭据；核账记录不等于司法定罪。"
		result.append(row)
	return result

static func validate(raw: Dictionary) -> Dictionary:
	var used := {}
	for entry in raw.get("resource_journal", {}).values():
		if entry.get("entry_kind") != "transfer": continue
		if entry.has("actor_id") and (not entry.actor_id is String or not raw.get("character_states", {}).has(entry.actor_id)): return Contract.fail("转账主体不是已记录人物")
		if entry.has("actor_id") and (not Contract.amount(entry.get("day")) or int(entry.day) > int(raw.get("current_day", 0))): return Contract.fail("转账日期不在已经发生的世界时间内")
		if not entry.has("actor_id") or not public_account(raw, str(entry.get("source_account_id", ""))) or public_account(raw, str(entry.get("destination_account_id", ""))) or vouched(raw, str(entry.entry_id)): continue
		if not raw.get("economic_contracts", {}).has("public-cash:" + str(entry.entry_id)): return Contract.fail("已记录的无公共凭据转出不能删除核账责任")
	for case in raw.get("economic_contracts", {}).values():
		if case.get("contract_kind") != "public_cash_liability": continue
		var entry: Dictionary = raw.get("resource_journal", {}).get(case.get("transfer_ref"), {})
		if entry.get("entry_kind") != "transfer" or case.get("contract_id") != "public-cash:" + str(entry.get("entry_id")) or not public_account(raw, str(entry.get("source_account_id", ""))) or public_account(raw, str(entry.get("destination_account_id", ""))) or vouched(raw, str(entry.get("entry_id", ""))): return Contract.fail("公款差额缺少未核销的真实转出")
		if case.get("public_account_id") != entry.source_account_id or case.get("recipient_account_id") != entry.destination_account_id or case.get("responsible_id") != str(entry.get("actor_id", "")) or case.get("amount") != entry.amount or case.get("created_day") != entry.day or case.get("source_id") != "rule:regional_fiscal_review": return Contract.fail("公款责任与原始凭据不符")
		if not str(case.responsible_id).is_empty() and not raw.get("character_states", {}).has(case.responsible_id): return Contract.fail("公款责任人物缺失")
		if not case.get("repayment_refs") is Array or not case.get("review_events") is Array or case.review_events.size() > 2 or not Contract.amount(case.get("remaining_amount")): return Contract.fail("公款归还或核账记录无效")
		if str(case.responsible_id).is_empty() and not case.review_events.is_empty(): return Contract.fail("未核实责任人的旧凭据不可编造个人追责")
		var repaid := 0
		for ref in case.repayment_refs:
			var payment: Dictionary = raw.resource_journal.get(ref, {})
			var source: Dictionary = raw.resource_accounts.get(payment.get("source_account_id"), {})
			if used.has(ref) or payment.get("entry_kind") != "transfer" or payment.get("reason_ref") != case.contract_id or payment.get("destination_account_id") != case.public_account_id or payment.get("actor_id") != case.responsible_id or source.get("owner_ref", {}).get("entity_kind") not in ["character", "clan"] or int(payment.get("day", -1)) < int(case.created_day): return Contract.fail("公款归还缺少独立的实际私款或族款支付")
			used[ref] = true
			repaid += int(payment.amount)
		if repaid + int(case.remaining_amount) != int(case.amount): return Contract.fail("公款差额与归还金额不守恒")
		var notice_day := -1
		for index in case.review_events.size():
			var event: Variant = case.review_events[index]
			if not event is Dictionary: return Contract.fail("核账事件结构无效")
			var term: Dictionary = raw.get("office_terms", {}).get(event.get("term_id"), {})
			var office: Dictionary = raw.get("office_state", {}).get(event.get("office_id"), {})
			var account: Dictionary = raw.resource_accounts[case.public_account_id]
			if term.get("holder_id") != event.get("reviewer_id") or term.get("office_id") != event.get("office_id") or event.get("reviewer_id") == case.responsible_id or office.get("organization_id") != account.get("organization_id") or office.get("role_key") not in ["investigator", "judge", "secretary"]: return Contract.fail("核账缺少实际独立任职者")
			if not Contract.amount(event.get("day")) or int(event.day) > int(raw.get("current_day", 0)) or int(term.get("start_day", -1)) > int(event.day) or (int(term.get("end_day", -1)) >= 0 and int(term.end_day) < int(event.day)): return Contract.fail("核账事件不在真实任期内")
			var loss := NOTICE_LOSS if index == 0 else OVERDUE_LOSS
			for key in ["trust_before", "trust_after"]:
				if not (event.get(key) is int or event.get(key) is float) or float(event[key]) != float(int(event[key])) or int(event[key]) < -100 or int(event[key]) > 100: return Contract.fail("核账关系记录无效")
			if event.trust_after != clampi(int(event.trust_before) - loss, -100, 100) or not Contract.amount(event.get("outstanding_amount")) or int(event.outstanding_amount) > int(case.amount): return Contract.fail("核账后果与记录不符")
			var paid_before := 0
			var paid_through := 0
			for ref in case.repayment_refs:
				var payment: Dictionary = raw.resource_journal[ref]
				if int(payment.day) < int(event.day): paid_before += int(payment.amount)
				if int(payment.day) <= int(event.day): paid_through += int(payment.amount)
			if int(event.outstanding_amount) < int(case.amount) - paid_through or int(event.outstanding_amount) > int(case.amount) - paid_before: return Contract.fail("核账时欠款与实际归还日期不符")
			if index == 0:
				if event.get("kind") != "notice" or int(event.day) < int(case.created_day) + AUDIT_DELAY: return Contract.fail("核账告知时间无效")
				notice_day = int(event.day)
			else:
				if event.get("kind") != "overdue" or int(event.day) <= notice_day + GRACE_DAYS or int(event.outstanding_amount) <= 0: return Contract.fail("逾期追偿缺少未归还款或期限")
		if case.get("due_day") != (-1 if notice_day < 0 else notice_day + GRACE_DAYS): return Contract.fail("公款归还期限无效")
		var expected := "repaid" if int(case.remaining_amount) == 0 else ("pending_review" if case.review_events.is_empty() else ("notified" if case.review_events.size() == 1 else "overdue"))
		if case.get("status") != expected: return Contract.fail("公款核账状态与证据不符")
	return {"ok": true}
