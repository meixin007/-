extends RefCounted
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Contract = preload("res://scripts/core/management_state_contract.gd")
const Education = preload("res://scripts/core/education_service.gd")
const Presence = preload("res://scripts/core/production_service.gd")
const KINDS := ["sponsor_school_student"]

static func awards(state, school_id: String, student_id: String = "") -> Array:
	var rows: Array = state.economic_contracts.values().filter(func(row): return row.get("contract_kind") == "school_living_aid" and row.get("school_id") == school_id and (student_id.is_empty() or row.get("student_id") == student_id))
	rows.sort_custom(func(a, b): return int(a.created_day) < int(b.created_day) if int(a.created_day) != int(b.created_day) else str(a.contract_id) < str(b.contract_id))
	return rows

static func cost_for(state, params: Dictionary) -> Dictionary:
	var school: Dictionary = state.management_assets.get(params.get("school_id", ""), {})
	var rule: Dictionary = school.get("living_aid_rule", {})
	var student: Dictionary = Education.student_offer(school, str(params.get("student_id", "")))
	var stall: Dictionary = state.management_assets.get(rule.get("stall_id", ""), {})
	var offer: Dictionary = stall.get("food_offer", {})
	if school.get("asset_kind") != "school" or rule.is_empty() or student.is_empty() or not student.get("aid_willing", false) or str(params.get("aid_id", "")).is_empty(): return Contract.fail("生活资助须有学舍规则、实际求学者及本人同意")
	if stall.get("asset_kind") != "food_stall" or stall.get("status") != "available" or stall.get("offer_visibility") != "public" or not Contract.amount(offer.get("price"), true) or not Contract.amount(offer.get("lot_units"), true): return Contract.fail("生活资助没有实际在售口粮报价")
	if not Contract.amount(rule.get("cash_amount"), true) or not Contract.amount(rule.get("food_lots"), true) or int(rule.food_lots) > (Contract.MAX_AMOUNT - int(rule.cash_amount)) / int(offer.price) or int(rule.food_lots) > Contract.MAX_AMOUNT / int(offer.lot_units): return Contract.fail("生活资助款粮数量越界")
	if state.resource_accounts.get(params.get("funding_account_id", ""), {}).get("unit_id") != "cash_unit": return Contract.fail("生活资助缺少实际货币来源")
	return {"ok": true, "account_id": params.funding_account_id, "amount": int(rule.cash_amount) + int(rule.food_lots) * int(offer.price)}

static func location_for(state, params: Dictionary) -> String:
	return str(state.management_assets.get(params.get("school_id", ""), {}).get("location_id", ""))

static func apply(state, params: Dictionary, principal: String, execution: String, reservation: String) -> Dictionary:
	var quote := cost_for(state, params)
	if not quote.ok: return quote
	var school: Dictionary = state.management_assets[params.school_id]
	var rule: Dictionary = school.living_aid_rule
	var stall: Dictionary = state.management_assets[rule.stall_id]
	var offer: Dictionary = stall.food_offer
	var seller: String = stall.owner_ref.entity_id
	var student: String = params.student_id
	var accounts := Accounts.new()
	if not Education.authority(state, school, principal) or not accounts.can_operate(state, params.funding_account_id, principal): return Contract.fail("没有实际学舍经办权或资助款项处分权")
	var source: Dictionary = state.resource_accounts[params.funding_account_id]
	if params.funding_account_id != school.account_id and source.owner_ref.entity_kind not in ["character", "clan"]: return Contract.fail("不能挪用另一公账作为学舍生活资助")
	if state.economic_contracts.has(params.aid_id): return Contract.fail("资助记录标识已使用")
	var enrolled: Array = Education.enrollments(state, school, true).filter(func(row): return row.supplier_id == student)
	if enrolled.size() != 1: return Contract.fail("须先实际入学；生活资助不替代入学或替结业者购买录取")
	var previous := awards(state, school.asset_id, student)
	if not previous.is_empty() and int(state.current_day) < int(previous[-1].created_day) + int(rule.interval_days): return {"ok": false, "code": "awaiting_delivery", "error": "本期已实际领取生活资助；最早第 %d 日再按实际求学状态办理。" % (int(previous[-1].created_day) + int(rule.interval_days))}
	if student in [principal, seller] or not Presence.present(state, student, school.location_id) or not Presence.present(state, seller, school.location_id) or stall.location_id != school.location_id: return Contract.fail("学生或粮商尚未在实际交割地")
	if int(state.character_states[student].get("relationships", {}).get(principal, 0)) < -15: return Contract.fail("学生目前不愿接受这笔资助")
	var student_cash := student + "_cash"
	var student_food := student + "_rations"
	for id in [quote.account_id, student_cash, student_food, offer.payee_account_id, offer.stock_account_id]:
		if not state.resource_accounts.has(id) or accounts.location(state, id) != school.location_id: return Contract.fail("生活款粮交割账户不在学舍所在地")
	var units := int(rule.food_lots) * int(offer.lot_units)
	var food_price := int(rule.food_lots) * int(offer.price)
	if accounts.available(state, quote.account_id, reservation) < int(quote.amount) or accounts.available(state, offer.stock_account_id) < units: return Contract.fail("资助可用款项或粮商实际库存不足，不得挪用其他预留")
	if not accounts.can_operate(state, offer.stock_account_id, seller): return Contract.fail("粮商没有实际口粮处分权")
	if accounts.balance(state, student_cash) > Contract.MAX_AMOUNT - int(rule.cash_amount) or accounts.balance(state, student_food) > Contract.MAX_AMOUNT - units or accounts.balance(state, offer.payee_account_id) > Contract.MAX_AMOUNT - food_price: return Contract.fail("资助收款或口粮库存越界")
	var cash_ref := execution + ":stipend"
	var purchase_ref := execution + ":purchase"
	var food_ref := execution + ":food"
	var paid := accounts.apply(state, "transfer", {"actor_id": principal, "execution_id": cash_ref, "source_account_id": quote.account_id, "destination_account_id": student_cash, "amount": int(rule.cash_amount), "reason_ref": params.aid_id, "reservation_id": reservation})
	if not paid.ok: return paid
	paid = accounts.apply(state, "transfer", {"actor_id": principal, "execution_id": purchase_ref, "source_account_id": quote.account_id, "destination_account_id": offer.payee_account_id, "amount": food_price, "reason_ref": params.aid_id, "reservation_id": reservation})
	if not paid.ok: return paid
	var delivered := accounts.apply(state, "transfer", {"actor_id": seller, "execution_id": food_ref, "source_account_id": offer.stock_account_id, "destination_account_id": student_food, "amount": units, "reason_ref": params.aid_id})
	if not delivered.ok: return delivered
	state.economic_contracts[params.aid_id] = {"contract_id": params.aid_id, "contract_kind": "school_living_aid", "status": "delivered", "school_id": school.asset_id, "student_id": student, "principal_id": principal, "seller_id": seller, "funding_account_id": quote.account_id, "enrollment_ref": enrolled[0].contract_id, "rule": rule.duplicate(true), "offer": offer.duplicate(true), "created_day": int(state.current_day), "amount": int(quote.amount), "cash_amount": int(rule.cash_amount), "food_amount": food_price, "food_units": units, "cash_ref": cash_ref, "purchase_ref": purchase_ref, "food_ref": food_ref, "execution_id": execution, "consent": true}
	return {"ok": true, "result_ref": params.aid_id, "journal_refs": [cash_ref, purchase_ref, food_ref], "visible_summary": "%s已收到生活款 %d、实际口粮 %d；学习仍须本人逐日到课，不保证录取或任官。" % [state.character_states[student].name, int(rule.cash_amount), units]}

static func project(state, school: Dictionary, viewer: String) -> Dictionary:
	var result := {"living_aid_awards": [], "living_aid_candidates": [], "living_aid_sources": []}
	if not school.has("living_aid_rule") or not Education.authority(state, school, viewer): return result
	result.living_aid_awards = awards(state, school.asset_id).duplicate(true)
	var accounts := Accounts.new()
	for account in state.resource_accounts.values():
		if account.unit_id == "cash_unit" and accounts.can_operate(state, account.account_id, viewer) and (account.account_id == school.account_id or account.owner_ref.entity_kind in ["character", "clan"]):
			result.living_aid_sources.append({"account_id": account.account_id, "name": "州库" if account.account_id == school.account_id else ("私款" if account.owner_ref.entity_kind == "character" else "家族款")})
	var offer: Dictionary = state.management_assets.get(school.living_aid_rule.stall_id, {}).get("food_offer", {})
	result["living_aid_cost"] = int(school.living_aid_rule.cash_amount) + int(school.living_aid_rule.food_lots) * int(offer.get("price", 0))
	result["living_aid_units"] = int(school.living_aid_rule.food_lots) * int(offer.get("lot_units", 0))
	for student in Education.enrollments(state, school, true):
		if not Education.student_offer(school, student.supplier_id).get("aid_willing", false): continue
		var previous := awards(state, school.asset_id, student.supplier_id)
		var next_day := 0 if previous.is_empty() else int(previous[-1].created_day) + int(school.living_aid_rule.interval_days)
		result.living_aid_candidates.append({"student_id": student.supplier_id, "can_receive": int(state.current_day) >= next_day, "next_day": next_day, "proposed_aid_id": "school-aid:%s:%s:%d" % [school.asset_id, student.supplier_id, previous.size() + 1], "public_request": "本人表示口粮不足，希望获得资助继续求学。" if accounts.available(state, student.supplier_id + "_rations") <= 0 else "本人同意接受求学生活资助；资助不承诺成绩或录取。"})
	return result

static func validate(raw: Dictionary) -> Dictionary:
	var contracts: Dictionary = raw.get("economic_contracts", {})
	for school in raw.get("management_assets", {}).values():
		if school.get("asset_kind") != "school" or not school.has("living_aid_rule"): continue
		var rule: Variant = school.living_aid_rule
		if not rule is Dictionary or not str(rule.get("source_id", "")).begins_with("scenario:") or not rule.get("content_basis") is String: return Contract.fail("学舍生活资助缺少规则来源")
		for field in ["cash_amount", "food_lots", "interval_days"]:
			if not Contract.amount(rule.get(field), true): return Contract.fail("生活资助规则数量无效")
		if raw.management_assets.get(rule.get("stall_id"), {}).get("asset_kind") != "food_stall": return Contract.fail("生活资助丢失实际粮商")
		for student in school.student_offers:
			if not student.get("aid_willing") is bool: return Contract.fail("生活资助缺少求学者明确意愿")
	var prior := {}
	var rows: Array = contracts.values().filter(func(row): return row.get("contract_kind") == "school_living_aid")
	rows.sort_custom(func(a, b): return int(a.get("created_day", -1)) < int(b.get("created_day", -1)))
	for row in rows:
		var school: Dictionary = raw.management_assets.get(row.get("school_id"), {})
		var rule: Dictionary = school.get("living_aid_rule", {})
		var stall: Dictionary = raw.management_assets.get(rule.get("stall_id"), {})
		var enrollment: Dictionary = contracts.get(row.get("enrollment_ref"), {})
		if row.get("status") != "delivered" or rule.is_empty() or row.get("rule") != rule or not row.get("offer") is Dictionary or row.get("seller_id") != stall.get("owner_ref", {}).get("entity_id") or row.get("consent") != true: return Contract.fail("生活资助与实际报价、来源或同意不符")
		for field in ["stock_account_id", "payee_account_id"]:
			if row.offer.get(field) != stall.get("food_offer", {}).get(field): return Contract.fail("生活资助丢失实际粮商库存或收款来源")
		for field in ["lot_units", "price"]:
			if not Contract.amount(row.offer.get(field), true): return Contract.fail("生活资助缺少成交当时报价")
		if not raw.character_states.has(row.get("principal_id")) or not raw.character_states.has(row.get("student_id")) or enrollment.get("contract_kind") != "school_enrollment" or enrollment.get("school_id") != school.asset_id or enrollment.get("supplier_id") != row.student_id: return Contract.fail("生活资助丢失实际入学对象")
		var source: Dictionary = raw.resource_accounts.get(row.get("funding_account_id"), {})
		if source.get("unit_id") != "cash_unit" or (row.funding_account_id != school.account_id and source.get("owner_ref", {}).get("entity_kind") not in ["character", "clan"]): return Contract.fail("生活资助引用无关公账或无效款源")
		if not Contract.amount(row.get("created_day")) or int(row.created_day) > int(raw.current_day) or int(row.created_day) < int(enrollment.created_day) or int(row.created_day) > int(enrollment.get("completed_day", raw.current_day)): return Contract.fail("生活资助日期不在实际求学期间")
		var key: String = school.asset_id + ":" + str(row.student_id)
		if prior.has(key) and int(row.created_day) < int(prior[key]) + int(rule.interval_days): return Contract.fail("同一求学者本期生活资助重复发放")
		prior[key] = int(row.created_day)
		if row.get("cash_amount") != rule.cash_amount or row.get("food_units") != int(rule.food_lots) * int(row.offer.lot_units) or row.get("food_amount") != int(rule.food_lots) * int(row.offer.price) or row.get("amount") != int(row.cash_amount) + int(row.food_amount): return Contract.fail("生活款粮与来源报价不守恒")
		var journals: Array = [row.get("cash_ref"), row.get("purchase_ref"), row.get("food_ref")]
		var sources: Array = [row.get("funding_account_id"), row.get("funding_account_id"), row.offer.stock_account_id]
		var destinations: Array = [str(row.student_id) + "_cash", row.offer.payee_account_id, str(row.student_id) + "_rations"]
		var amounts: Array = [row.cash_amount, row.food_amount, row.food_units]
		for index in 3:
			var entry: Dictionary = raw.resource_journal.get(journals[index], {})
			if entry.get("entry_kind") != "transfer" or entry.get("source_account_id") != sources[index] or entry.get("destination_account_id") != destinations[index] or entry.get("amount") != amounts[index] or entry.get("reason_ref") != row.contract_id or entry.get("day") != row.created_day or entry.get("actor_id") != (row.seller_id if index == 2 else row.principal_id) or entry.get("unit_id") != ("ration_unit" if index == 2 else "cash_unit"): return Contract.fail("生活资助缺少实际款粮交割凭据")
		var receipt: Dictionary = raw.action_receipts.get(row.get("execution_id"), {})
		if not receipt.get("effect_refs", []).has(row.contract_id) or receipt.get("journal_refs") != journals or receipt.get("day") != row.created_day: return Contract.fail("生活资助丢失共同动作回执")
	return {"ok": true}
