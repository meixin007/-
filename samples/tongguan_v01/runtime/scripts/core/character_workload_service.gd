extends RefCounted

# Planned office duties and actual work share the same day. Employer-authorized
# administration/search can fulfill a matching duty; outside work cannot.
static func occupied_today(state, person: String, except_contract: String = "", principal: String = "", kind: String = "outside_work") -> bool:
	if state.flags.get("regional_player_journeys", {}).values().any(func(row): return row.person_id == person and row.status == "travelling"): return true
	if not duty_reason(state, person, kind, principal, int(state.current_day) % 7).is_empty(): return true
	if state.action_receipts.values().any(func(receipt): return receipt.get("executor_id") == person and (receipt.get("task_id", "") != "" or receipt.has("estate_work") or receipt.has("estate_collection")) and int(receipt.get("day", -1)) == int(state.current_day)): return true
	for contract in state.economic_contracts.values():
		if contract.get("contract_id") == except_contract: continue
		if contract.get("contract_kind") == "personal_estate" and contract.get("status") == "settled":
			var receipt: Dictionary = state.action_receipts.get(contract.get("settlement_receipt", ""), {})
			if receipt.get("executor_id") == person and int(receipt.get("day", -1)) == int(state.current_day): return true
		if contract.get("contract_kind") in ["school_exam_journey", "official_journey"] and contract.get("supplier_id") == person and contract.get("status") in ["en_route", "awaiting_reception"]: return true
		if contract.get("contract_kind") in ["manufacturing_batch", "estate_construction", "estate_improvement", "production", "character_search", "setup", "public_work", "cultivation", "managed_cultivation", "school_teaching", "school_enrollment", "school_assessment", "school_candidacy", "school_supply", "school_exam_journey", "official_journey", "official_initiative"] and contract.get("supplier_id", contract.get("executor_id", "")) == person and contract.get("work_log", []).any(func(row): return int(row.get("day", -1)) == int(state.current_day)): return true
	return false

static func overlaps(first: Dictionary, second: Dictionary) -> bool:
	for office in [first, second]:
		var schedule: Variant = office.get("work_schedule")
		if not schedule is Dictionary or not schedule.get("days") is Array: return true
		for day in schedule.days:
			if typeof(day) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(day)): return true
	return first.work_schedule.days.any(func(day): return second.work_schedule.days.any(func(other): return int(other) == int(day)))

static func duty_reason(state, person: String, kind: String, principal: String, weekday: int, additional: Dictionary = {}) -> String:
	var offices: Array = state.office_state.values().filter(func(office): return office.get("office_kind") in ["family", "regional"] and office.get("holder_id") == person and office.get("office_id") != additional.get("office_id"))
	if not additional.is_empty(): offices.append(additional)
	for office in offices:
		var schedule: Dictionary = office.get("work_schedule", {})
		if not schedule.get("days", []).any(func(day): return int(day) == weekday): continue
		var operators: Array = state.resource_accounts.get(office.remuneration_terms.account_id, {}).get("operator_refs", [])
		if schedule.get("duty_work_kinds", []).has(kind) and operators.has({"entity_kind": "character", "entity_id": principal}): continue
		return "今日须履行%s职责；请改在空闲日办理或先安排交接。" % str(office.name)
	return ""

static func can_schedule(state, person: String, kind: String, principal: String = "", additional: Dictionary = {}) -> bool:
	if state.flags.get("regional_player_journeys", {}).values().any(func(row): return row.person_id == person and row.status == "travelling"): return false
	if state.economic_contracts.values().any(func(row): return row.get("contract_kind") in ["school_exam_journey", "official_journey"] and row.get("supplier_id") == person and row.get("status") in ["en_route", "awaiting_reception"]): return false
	for weekday in 7:
		if duty_reason(state, person, kind, principal, weekday, additional).is_empty(): return true
	return false

static func record_work(state, order: Dictionary) -> void:
	order.work_log.append({"day": int(state.current_day), "attempt": int(order.get("attempt", 0))})
	order.work_days += 1
	order.last_work_day = int(state.current_day)

static func validate(raw: Dictionary) -> Dictionary:
	var occupied := {}
	var estate_receipts := {}
	for estate in raw.get("economic_contracts", {}).values():
		if estate.get("contract_kind") == "personal_estate" and estate.get("status") == "settled": estate_receipts[estate.get("settlement_receipt", "")] = true
	for receipt in raw.get("action_receipts", {}).values():
		if receipt.get("task_id", "") == "" and not receipt.has("estate_work") and not receipt.has("estate_collection") and not estate_receipts.has(receipt.get("execution_id", "")): continue
		var key := "%s:%d" % [receipt.get("executor_id", ""), int(receipt.get("day", -1))]
		if occupied.has(key): return {"ok": false, "error": "同一人物同日执行了两项整日事务"}
		occupied[key] = true
	for order in raw.get("economic_contracts", {}).values():
		if order.get("contract_kind") not in ["manufacturing_batch", "estate_construction", "estate_improvement", "production", "character_search", "setup", "public_work", "cultivation", "managed_cultivation", "school_teaching", "school_enrollment", "school_assessment", "school_candidacy", "school_supply", "school_exam_journey", "official_journey", "official_initiative"]: continue
		if not order.get("work_log") is Array: return {"ok": false, "error": "实际工序缺少工日凭据"}
		var current_count := 0
		var previous_day := int(order.get("created_day", 0)) - (1 if order.get("contract_kind") in ["cultivation", "managed_cultivation", "official_initiative"] else 0)
		var previous_attempt := 0
		var attempt_counts := {}
		for row in order.work_log:
			if not row is Dictionary or typeof(row.get("day")) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(row.day)) or float(row.day) != floor(float(row.day)) or int(row.day) <= previous_day or int(row.day) > int(raw.current_day) or typeof(row.get("attempt")) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(row.attempt)) or float(row.attempt) != floor(float(row.attempt)) or int(row.attempt) < 0 or int(row.attempt) > int(order.get("attempt", 0)): return {"ok": false, "error": "实际工日重复、越界或丢失尝试来源"}
			previous_day = int(row.day)
			if int(row.attempt) < previous_attempt: return {"ok": false, "error": "寻访工日倒退到已结束的尝试"}
			previous_attempt = int(row.attempt)
			attempt_counts[previous_attempt] = int(attempt_counts.get(previous_attempt, 0)) + 1
			if int(row.attempt) < int(order.get("attempt", 0)) and int(row.day) > int(order.failure_history[int(row.attempt)].day): return {"ok": false, "error": "已结束的寻访尝试仍在新增工日"}
			if int(row.attempt) == int(order.get("attempt", 0)): current_count += 1
			var key := "%s:%d" % [order.get("supplier_id", order.get("executor_id", "")), int(row.day)]
			if occupied.has(key): return {"ok": false, "error": "同一人物同日重复投入实际工时"}
			occupied[key] = true
		if current_count != int(order.get("work_days", -1)) or previous_day > int(order.get("last_work_day", -1)): return {"ok": false, "error": "累计工日与实际工作记录不符"}
		for attempt in int(order.get("attempt", 0)):
			if int(attempt_counts.get(attempt, 0)) != int(order.duration_days): return {"ok": false, "error": "寻访重试丢失此前失败尝试的实际工时"}
	return {"ok": true}
