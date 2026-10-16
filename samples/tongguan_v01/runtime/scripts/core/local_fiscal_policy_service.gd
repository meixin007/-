extends RefCounted

# Explicit scenario levies, not a claim about historical Tang taxation.
const SOURCE := "scenario:pingyuan_local_fiscal_756"
const KINDS := ["issue_local_levy", "remit_local_levy", "pay_local_levy"]
const Rules = preload("res://scripts/core/management_state_contract.gd")
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Presence = preload("res://scripts/core/production_service.gd")

static func initialize(state, data: Dictionary) -> Dictionary:
	var config: Dictionary = data.get("management", {}).get("regional_administration", {}).get("local_fiscal_policy", {})
	if config.is_empty(): return {"ok": true}
	state.flags["local_fiscal_policy"] = config.duplicate(true)
	return {"ok": true}

static func authority(state, office: String, person: String) -> bool:
	var rule: Dictionary = state.flags.get("local_fiscal_policy", {})
	return office == rule.get("office_id") and state.office_state.get(office, {}).get("holder_id") == person and state.office_state[office].get("status") == "appointed" and Accounts.new().can_operate(state, str(rule.get("account_id", "")), person)

static func location(state) -> String:
	return str(state.flags.get("local_fiscal_policy", {}).get("location_id", ""))

static func issue_ready(state, office: String, principal: String) -> bool:
	if not authority(state, office, principal): return false
	var rule: Dictionary = state.flags.local_fiscal_policy
	for row in state.economic_contracts.values():
		if row.get("contract_kind") == "local_levy" and row.office_id == office and int(state.current_day) < int(row.created_day) + int(rule.interval_days): return false
	return true

static func cost_for(state, kind: String, params: Dictionary) -> Dictionary:
	var rule: Dictionary = state.flags.get("local_fiscal_policy", {})
	if rule.is_empty() or params.get("office_id") != rule.office_id: return Rules.fail("地方征收没有实际管辖与来源")
	if kind == "issue_local_levy":
		if not params.get("levy_id") is String or not params.levy_id.begins_with("levy:") or not rule.rates.has(params.get("policy")): return Rules.fail("征收标识或政策无效")
		return {"ok": true, "account_id": rule.account_id, "amount": 0}
	var levy: Dictionary = state.economic_contracts.get(params.get("levy_id"), {})
	if levy.get("contract_kind") != "local_levy" or levy.get("office_id") != params.office_id or not levy.obligations.has(params.get("person_id")): return Rules.fail("没有该人物的实际征收责任")
	var item: Dictionary = levy.obligations[params.person_id]
	return {"ok": true, "account_id": str(params.person_id) + "_cash" if kind == "pay_local_levy" else rule.account_id, "amount": int(item.remaining) if kind == "pay_local_levy" else 0}

static func apply(state, kind: String, params: Dictionary, principal: String, execution: String, reservation: String) -> Dictionary:
	var checked := cost_for(state, kind, params)
	if not checked.ok: return checked
	var rule: Dictionary = state.flags.local_fiscal_policy
	if kind != "pay_local_levy" and not authority(state, params.office_id, principal): return Rules.fail("本人不是当前地方征收权源")
	if kind == "issue_local_levy":
		if not issue_ready(state, params.office_id, principal) or state.economic_contracts.has(params.levy_id): return Rules.fail("本期已有征收，不能更换标识重复加派")
		var obligations := {}
		for model in rule.people:
			obligations[model.person_id] = {"person_id": model.person_id, "assessed": int(rule.rates[params.policy]), "remaining": int(rule.rates[params.policy]), "paid": 0, "remitted": 0, "events": [], "status": "awaiting_response", "public_expression": "尚未收到本人回应。"}
		state.economic_contracts[params.levy_id] = {"contract_id": params.levy_id, "contract_kind": "local_levy", "source_id": SOURCE, "office_id": params.office_id, "principal_id": principal, "account_id": rule.account_id, "location_id": rule.location_id, "created_day": int(state.current_day), "policy": params.policy, "amount_each": int(rule.rates[params.policy]), "obligations": obligations, "issue_receipt": execution, "last_update_day": int(state.current_day)}
		return {"ok": true, "result_ref": params.levy_id, "levy_order": order_record(state.economic_contracts[params.levy_id]), "visible_summary": "已签发本期地方征收；逐人等待实际缴纳或请求，不预增州库。"}
	var levy: Dictionary = state.economic_contracts[params.levy_id]
	var item: Dictionary = levy.obligations[params.person_id]
	if int(item.remaining) <= 0: return Rules.fail("该项已缴清或减免，不能重复处理")
	var amount: int = int(item.remaining)
	if kind == "pay_local_levy":
		if principal != params.person_id or not Presence.present(state, principal, levy.location_id): return Rules.fail("缴纳须由本人在实际征收地办理")
		var payment := Accounts.new().apply(state, "transfer", {"execution_id": execution, "source_account_id": str(principal) + "_cash", "destination_account_id": levy.account_id, "amount": amount, "actor_id": principal, "reason_ref": levy.contract_id, "reservation_id": reservation})
		if not payment.get("ok", false): return payment
		item.paid += amount
		item.remaining = 0
		item.status = "paid"
		item.public_expression = "已从本人私款实际缴入州库 %d。" % amount
		event(state, levy, item, "paid", 1, execution, amount)
		return {"ok": true, "result_ref": levy.contract_id, "journal_refs": [execution], "fiscal_response": response_record(levy, item, "paid", int(state.current_day), amount), "visible_summary": item.public_expression}
	if item.status != "petitioning": return Rules.fail("尚未收到该人物的减免请求")
	item.remitted += amount
	item.remaining = 0
	item.status = "remitted"
	item.public_expression = "已获准免去本期未缴 %d；此前实缴不退回，原征收与请求保留。" % amount
	event(state, levy, item, "remitted", 3, execution, amount)
	return {"ok": true, "result_ref": levy.contract_id, "fiscal_response": response_record(levy, item, "remitted", int(state.current_day), amount), "visible_summary": item.public_expression}

static func response_record(levy: Dictionary, item: Dictionary, kind: String, day: Variant, amount: Variant) -> Dictionary:
	return {"levy_id": levy.contract_id, "person_id": item.person_id, "kind": kind, "day": day, "amount": amount}

static func order_record(levy: Dictionary) -> Dictionary:
	var result := {}
	for key in ["contract_id", "office_id", "principal_id", "account_id", "location_id", "created_day", "policy", "amount_each"]: result[key] = levy[key]
	result["people"] = levy.obligations.keys()
	result.people.sort()
	return result

static func event(state, levy: Dictionary, item: Dictionary, kind: String, delta: int, receipt: String, amount: int) -> void:
	var person: Dictionary = state.character_states[item.person_id]
	var before: int = int(person.relationships.get(levy.principal_id, 0))
	var after := clampi(before + delta, -100, 100)
	person.relationships[levy.principal_id] = after
	item.events.append({"kind": kind, "day": int(state.current_day), "receipt": receipt, "amount": amount, "trust_before": before, "trust_after": after})

static func settle_daily(state, data: Dictionary) -> Dictionary:
	var rule: Dictionary = state.flags.get("local_fiscal_policy", {})
	if rule.is_empty(): return {"ok": true}
	for levy in state.economic_contracts.values():
		if levy.get("contract_kind") != "local_levy" or int(levy.last_update_day) >= int(state.current_day): continue
		levy.last_update_day = int(state.current_day)
		for model in rule.people:
			var item: Dictionary = levy.obligations[model.person_id]
			if int(item.remaining) == 0 or not Presence.present(state, model.person_id, levy.location_id): continue
			var funds: int = Accounts.new().available(state, str(model.person_id) + "_cash")
			if funds - int(item.remaining) >= int(model.reserve):
				var execution := "local-levy-payment:%s:%s" % [levy.contract_id, model.person_id]
				var params := {"office_id": levy.office_id, "levy_id": levy.contract_id, "person_id": model.person_id}
				var paid: Dictionary = load("res://scripts/core/game_action_dispatcher.gd").apply(state, data, {"execution_id": execution, "request_id": execution, "actor_id": model.person_id, "principal_id": model.person_id, "executor_id": model.person_id, "action_kind": "pay_local_levy", "parameters": params, "target_refs": [levy.office_id, levy.contract_id, model.person_id], "expected_state_revision": state.state_revision})
				if not paid.get("ok", false): continue # Existing account/location authority may prevent payment.
			elif item.status == "awaiting_response":
				item.status = "petitioning"
				item.public_expression = str(model.petition)
				event(state, levy, item, "petition", -4, "", int(item.remaining))
	return {"ok": true}

static func project(state, viewer: String) -> Dictionary:
	var rule: Dictionary = state.flags.get("local_fiscal_policy", {})
	var result := {"office_id": "", "can_issue": false, "levies": []}
	if rule.is_empty() or not authority(state, rule.office_id, viewer) or state.character_states[viewer].get("location_id") != rule.location_id: return result
	result.office_id = rule.office_id
	result.can_issue = issue_ready(state, rule.office_id, viewer)
	result["rates"] = rule.rates.duplicate(true)
	for levy in state.economic_contracts.values():
		if levy.get("contract_kind") != "local_levy" or levy.office_id != rule.office_id: continue
		var row := {"levy_id": levy.contract_id, "created_day": levy.created_day, "policy": levy.policy, "amount_each": levy.amount_each, "people": [], "paid": 0, "remaining": 0, "remitted": 0}
		for model in rule.people:
			var item: Dictionary = levy.obligations[model.person_id]
			row.people.append({"person_id": model.person_id, "name": state.character_states[model.person_id].name, "group": model.group, "status": item.status, "expression": item.public_expression, "paid": item.paid, "remaining": item.remaining, "remitted": item.remitted, "can_remit": item.status == "petitioning"})
			for key in ["paid", "remaining", "remitted"]: row[key] += int(item[key])
		result.levies.append(row)
	return result

static func validate(raw: Dictionary) -> Dictionary:
	var rule: Variant = raw.get("flags", {}).get("local_fiscal_policy", {})
	if not rule is Dictionary: return Rules.fail("地方征收规则类型无效")
	if rule.is_empty():
		if raw.get("economic_contracts", {}).values().any(func(row): return row.get("contract_kind") == "local_levy"): return Rules.fail("地方征收失去来源")
		return {"ok": true}
	if rule.get("source_id") != SOURCE or not raw.office_state.has(rule.get("office_id")) or not raw.resource_accounts.has(rule.get("account_id")) or raw.resource_accounts[rule.account_id].owner_ref != {"entity_kind": "office", "entity_id": rule.office_id} or not raw.local_node_state.has(rule.get("location_id")) or not rule.get("rates") is Dictionary or not rule.get("people") is Array or not Rules.amount(rule.get("interval_days"), true): return Rules.fail("地方征收缺少实际职位、账户或规则")
	for rate in rule.rates.values():
		if not Rules.amount(rate, true): return Rules.fail("地方征收额度无效")
	var people := {}
	for model in rule.people:
		if not model is Dictionary or not raw.character_states.has(model.get("person_id")) or not raw.resource_accounts.has(str(model.get("person_id", "")) + "_cash") or people.has(model.person_id) or not Rules.amount(model.get("reserve")) or not model.get("petition") is String or model.get("group") not in ["农户", "商户", "士人", "豪强"]: return Rules.fail("征收对象缺少独立人物、生计条件或公开请求")
		people[model.person_id] = true
	var dates: Array = []
	for levy in raw.get("economic_contracts", {}).values():
		if levy.get("contract_kind") != "local_levy": continue
		if levy.get("source_id") != SOURCE or levy.get("office_id") != rule.office_id or levy.get("account_id") != rule.account_id or levy.get("location_id") != rule.location_id or not raw.character_states.has(levy.get("principal_id")) or not rule.rates.has(levy.get("policy")) or levy.get("amount_each") != rule.rates[levy.policy] or not levy.get("obligations") is Dictionary or levy.obligations.size() != people.size(): return Rules.fail("征收责任缺少来源或实际对象")
		for key in ["created_day", "last_update_day"]:
			if not Rules.amount(levy.get(key)) or int(levy[key]) > int(raw.current_day): return Rules.fail("征收日期无效")
		for day in dates:
			if absi(int(day) - int(levy.created_day)) < int(rule.interval_days): return Rules.fail("同一期不能重复加派")
		dates.append(levy.created_day)
		var issued: Dictionary = raw.action_receipts.get(levy.get("issue_receipt"), {})
		if issued.get("levy_order") != order_record(levy) or issued.get("day") != levy.created_day or not issued.get("effect_refs", []).has(levy.contract_id): return Rules.fail("征收缺少共同签发回执")
		for person in people:
			var item: Variant = levy.obligations.get(person)
			if not item is Dictionary or item.get("person_id") != person or item.get("assessed") != levy.amount_each or not item.get("events") is Array or not item.get("public_expression") is String: return Rules.fail("逐人征收记录无效")
			for key in ["paid", "remaining", "remitted"]:
				if not Rules.amount(item.get(key)): return Rules.fail("征收余额无效")
			if int(item.paid) + int(item.remaining) + int(item.remitted) != int(item.assessed): return Rules.fail("征收实缴、欠额与减免不守恒")
			var status := "awaiting_response"
			var paid := 0
			var remitted := 0
			var last_day: int = int(levy.created_day)
			for entry in item.events:
				if not entry is Dictionary or not Rules.amount(entry.get("day")) or int(entry.day) < last_day or int(entry.day) > int(raw.current_day) or entry.get("amount") != item.assessed or not entry.get("receipt") is String: return Rules.fail("地方人物回应履历无效")
				last_day = int(entry.day)
				var delta := 0
				match entry.get("kind"):
					"petition":
						if status != "awaiting_response" or not entry.receipt.is_empty() or int(entry.day) <= int(levy.created_day): return Rules.fail("不能重复或预造地方请求")
						status = "petitioning"; delta = -4
					"paid":
						if status not in ["awaiting_response", "petitioning"]: return Rules.fail("地方征收重复缴纳")
						var payment: Dictionary = raw.resource_journal.get(entry.receipt, {})
						if payment.get("entry_kind") != "transfer" or payment.get("reason_ref") != levy.contract_id or payment.get("source_account_id") != str(person) + "_cash" or payment.get("destination_account_id") != levy.account_id or payment.get("amount") != entry.amount or payment.get("actor_id") != person or payment.get("day") != entry.day: return Rules.fail("实缴没有人物私款进入州库的凭据")
						paid += int(entry.amount); status = "paid"; delta = 1
					"remitted":
						if status != "petitioning": return Rules.fail("减免缺少实际人物请求")
						remitted += int(entry.amount); status = "remitted"; delta = 3
					_: return Rules.fail("未知地方回应")
				for key in ["trust_before", "trust_after"]:
					if not (entry.get(key) is int or entry.get(key) is float) or float(entry[key]) != float(int(entry[key])) or absf(float(entry[key])) > 100: return Rules.fail("地方人物关系履历无效")
				if entry.trust_after != clampi(int(entry.trust_before) + delta, -100, 100): return Rules.fail("地方人物关系后果与事件不符")
				if entry.kind != "petition":
					var receipt: Dictionary = raw.action_receipts.get(entry.receipt, {})
					if receipt.get("day") != entry.day or not receipt.get("effect_refs", []).has(levy.contract_id) or receipt.get("fiscal_response") != response_record(levy, item, entry.kind, entry.day, entry.amount): return Rules.fail("地方缴纳或减免缺少共同回执")
			if item.status != status or item.paid != paid or item.remitted != remitted: return Rules.fail("地方财政结果与实际回应不符")
	return {"ok": true}
