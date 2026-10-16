extends RefCounted

# Private scenario priorities choose between actual local opportunities. A request
# never substitutes for the existing appointment, construction or fiscal action.
const Rules = preload("res://scripts/core/management_state_contract.gd")
const Work = preload("res://scripts/core/character_workload_service.gd")
const Presence = preload("res://scripts/core/production_service.gd")
const Fiscal = preload("res://scripts/core/local_fiscal_policy_service.gd")
const SOURCE := "scenario:pingyuan_official_motives_756"
const KINDS := ["present_official_initiative", "decline_official_initiative"]

static func initialize(state, data: Dictionary) -> Dictionary:
	var config: Dictionary = data.get("management", {}).get("regional_administration", {}).get("official_motives", {})
	if not config.is_empty(): state.flags["official_motives"] = config.duplicate(true)
	return {"ok": true}

static func serving(state, person: String) -> Dictionary:
	var config: Dictionary = state.flags.get("official_motives", {})
	for office in state.office_state.values():
		if office.get("office_kind") != "regional" or office.get("holder_id") != person or office.get("status") != "appointed" or office.get("authority_ref", {}).get("entity_id") != config.get("head_office_id"): continue
		for term in state.office_terms.values():
			if term.get("office_id") == office.office_id and term.get("holder_id") == person and int(term.get("end_day", 0)) < 0: return {"office_id": office.office_id, "term_id": term.term_id}
	return {}

static func opportunities(state, person: String) -> Array:
	var config: Dictionary = state.flags.get("official_motives", {})
	var model: Dictionary = config.get("people", {}).get(person, {})
	var held := serving(state, person)
	if model.is_empty() or held.is_empty(): return []
	var choices: Array = []
	var target: Dictionary = state.office_state.get(model.career_office_id, {})
	var current: Dictionary = state.office_state[held.office_id]
	if target.get("status") != "appointed" and target.get("holder_id", "") == "" and int(target.get("remuneration_terms", {}).get("daily_amount", 0)) > int(current.remuneration_terms.daily_amount):
		choices.append({"kind": "promotion", "target_id": target.office_id, "person_id": person, "text": "愿争取%s；请先核对原职交接与任用条件，未获任命前仍履行本职。" % target.name, "evidence": {"vacant_office": target.office_id, "current_daily_pay": current.remuneration_terms.daily_amount, "target_daily_pay": target.remuneration_terms.daily_amount}})
	var canal: Dictionary = state.management_assets.get(config.canal_id, {})
	if canal.get("status") == "damaged":
		choices.append({"kind": "public_work", "target_id": canal.asset_id, "person_id": "", "text": "接渠田地供水不足，请优先修复%s；开工、验收与收成须分别落实。" % canal.name, "evidence": {"canal_id": canal.asset_id, "status": canal.status, "price": canal.repair_offer.price}})
	var prefect: String = str(state.office_state.get(config.head_office_id, {}).get("holder_id", ""))
	for levy in Fiscal.project(state, prefect).levies:
		for payer in levy.people:
			if payer.person_id in model.kin_ids and payer.can_remit:
				choices.append({"kind": "family_interest", "target_id": levy.levy_id, "person_id": payer.person_id, "text": "请准予%s的本期减免请求；其尚欠 %d，减免须由当前刺史决定。" % [payer.name, int(payer.remaining)], "evidence": {"levy_id": levy.levy_id, "person_id": payer.person_id, "remaining": payer.remaining, "request": payer.expression}})
	var result: Array = []
	for choice in choices:
		choice["initiative_id"] = "initiative:%s:%s" % [person, (str(choice.kind) + ":" + str(choice.target_id)).sha256_text().substr(0, 16)]
		choice["priority"] = int(model.priorities[choice.kind])
		if not state.economic_contracts.has(choice.initiative_id): result.append(choice)
	result.sort_custom(func(a, b): return a.priority > b.priority if a.priority != b.priority else a.initiative_id < b.initiative_id)
	return result

static func cost_for(state, kind: String, params: Dictionary) -> Dictionary:
	var config: Dictionary = state.flags.get("official_motives", {})
	if config.is_empty() or params.get("office_id") != config.head_office_id or not params.get("initiative_id") is String: return Rules.fail("幕僚请求缺少实际管辖或标识")
	if kind == "decline_official_initiative" and state.economic_contracts.get(params.initiative_id, {}).get("contract_kind") != "official_initiative": return Rules.fail("没有该实际幕僚请求")
	return {"ok": true, "account_id": "", "amount": 0}

static func apply(state, kind: String, params: Dictionary, principal: String, execution: String) -> Dictionary:
	var checked := cost_for(state, kind, params)
	if not checked.ok: return checked
	var config: Dictionary = state.flags.official_motives
	var prefect: String = str(state.office_state[config.head_office_id].get("holder_id", ""))
	if kind == "decline_official_initiative":
		if not Fiscal.authority(state, params.office_id, principal): return Rules.fail("驳回幕僚请求须由实际刺史决定")
		var row: Dictionary = state.economic_contracts[params.initiative_id]
		if row.status != "pending": return Rules.fail("这项请求已经有结果")
		var person: Dictionary = state.character_states[row.supplier_id]
		var before: int = int(person.relationships.get(principal, 0))
		person.relationships[principal] = clampi(before - 3, -100, 100)
		row.status = "declined"
		row["resolution"] = {"kind": "declined", "ref": execution, "day": int(state.current_day), "principal_id": principal, "trust_before": before, "trust_after": person.relationships[principal]}
		return {"ok": true, "result_ref": row.contract_id, "initiative_response": {"initiative_id": row.contract_id, "person_id": row.supplier_id, "decision": "declined"}, "visible_summary": "已驳回这次请求；既有职务、工程和债务不因此改变。"}
	var held := serving(state, principal)
	if principal == prefect or held.is_empty() or not Presence.present(state, principal, config.location_id) or not Presence.present(state, prefect, config.location_id) or Work.occupied_today(state, principal, "", prefect, "management"): return Rules.fail("本人没有实际幕职、在场或空闲值勤日")
	for old in state.economic_contracts.values():
		if old.get("contract_kind") == "official_initiative" and old.supplier_id == principal and (old.status == "pending" or int(state.current_day) < int(old.created_day) + int(config.review_days)): return Rules.fail("已有待答请求或尚未到下次复议日")
	var choices := opportunities(state, principal)
	if choices.is_empty() or choices[0].initiative_id != params.initiative_id: return Rules.fail("请求不是本人当前实际优先机会")
	var row := {"contract_id": params.initiative_id, "contract_kind": "official_initiative", "source_id": SOURCE, "supplier_id": principal, "customer_id": prefect, "office_id": held.office_id, "term_id": held.term_id, "head_office_id": config.head_office_id, "location_id": config.location_id, "created_day": int(state.current_day), "work_days": 0, "last_work_day": int(state.current_day), "work_log": [], "choice": choices[0].duplicate(true), "considered": choices.duplicate(true), "status": "pending", "presentation_receipt": execution}
	Work.record_work(state, row)
	state.economic_contracts[row.contract_id] = row
	return {"ok": true, "result_ref": row.contract_id, "initiative_record": record(row), "visible_summary": row.choice.text}

static func record(row: Dictionary) -> Dictionary:
	var result := {}
	for key in ["contract_id", "supplier_id", "customer_id", "office_id", "term_id", "head_office_id", "location_id", "created_day", "choice", "considered"]: result[key] = row[key]
	return result

static func outcome(raw: Dictionary, row: Dictionary) -> Dictionary:
	var choice: Dictionary = row.choice
	if choice.kind == "promotion":
		for term in raw.office_terms.values():
			if term.get("office_id") == choice.target_id and term.get("holder_id") == row.supplier_id and int(term.get("start_day", -1)) >= int(row.created_day): return {"kind": "fulfilled", "ref": term.term_id, "day": term.start_day}
	elif choice.kind == "public_work":
		for order in raw.economic_contracts.values():
			if order.get("contract_kind") == "public_work" and order.get("canal_id") == choice.target_id and order.get("status") == "accepted" and int(order.created_day) >= int(row.created_day):
				var receipt: Dictionary = raw.action_receipts.get(order.collection_receipt, {})
				if not receipt.is_empty(): return {"kind": "fulfilled", "ref": order.collection_receipt, "day": receipt.day}
	elif choice.kind == "family_interest":
		var item: Dictionary = raw.economic_contracts.get(choice.target_id, {}).get("obligations", {}).get(choice.person_id, {})
		for event in item.get("events", []):
			if event.kind == "remitted" and int(event.day) >= int(row.created_day): return {"kind": "fulfilled", "ref": event.receipt, "day": event.day}
	return {}

static func reconcile(state) -> void:
	var pending: Array = state.economic_contracts.values().filter(func(row): return row.get("contract_kind") == "official_initiative" and row.status == "pending")
	if pending.is_empty(): return
	var raw: Dictionary = state.to_dictionary()
	for row in pending:
		var result := outcome(raw, row)
		if not result.is_empty(): row.status = "fulfilled"; row["resolution"] = result

static func settle_daily(state, data: Dictionary) -> Dictionary:
	reconcile(state)
	var config: Dictionary = state.flags.get("official_motives", {})
	for person in config.get("people", {}):
		var choices := opportunities(state, person)
		if choices.is_empty(): continue
		var id: String = choices[0].initiative_id
		var result: Dictionary = load("res://scripts/core/game_action_dispatcher.gd").apply(state, data, {"execution_id": "present:" + id, "request_id": "present:" + id, "actor_id": person, "principal_id": person, "executor_id": person, "action_kind": "present_official_initiative", "parameters": {"office_id": config.head_office_id, "initiative_id": id}, "target_refs": [config.head_office_id, id], "expected_state_revision": state.state_revision})
		if not result.get("ok", false) and result.get("rollback_required", false): return result
	return {"ok": true}

static func project(state, viewer: String) -> Array:
	var config: Dictionary = state.flags.get("official_motives", {})
	if config.is_empty() or not Fiscal.authority(state, config.head_office_id, viewer) or not Presence.present(state, viewer, config.location_id): return []
	var result: Array = []
	for row in state.economic_contracts.values():
		if row.get("contract_kind") != "official_initiative": continue
		result.append({"initiative_id": row.contract_id, "person_id": row.supplier_id, "name": state.character_states[row.supplier_id].name, "office_id": row.office_id, "head_office_id": row.head_office_id, "kind": "fiscal_petition" if row.choice.kind == "family_interest" else row.choice.kind, "target_id": row.choice.target_id, "subject_id": row.choice.person_id, "text": row.choice.text, "status": row.status, "day": row.created_day})
	return result

static func validate(raw: Dictionary) -> Dictionary:
	var config: Variant = raw.get("flags", {}).get("official_motives", {})
	if not config is Dictionary: return Rules.fail("幕僚动机配置类型无效")
	if not config.is_empty():
		if config.get("source_id") != SOURCE or not raw.office_state.has(config.get("head_office_id")) or not raw.management_assets.has(config.get("canal_id")) or not raw.local_node_state.has(config.get("location_id")) or not Rules.amount(config.get("review_days"), true) or not config.get("people") is Dictionary: return Rules.fail("幕僚动机缺少实际权源、地点或机会来源")
		for person in config.people:
			var model: Variant = config.people[person]
			if not raw.character_states.has(person) or not model is Dictionary or not model.get("priorities") is Dictionary or not model.get("kin_ids") is Array or not raw.office_state.has(model.get("career_office_id")): return Rules.fail("幕僚动机缺少人物或机会")
			for key in ["promotion", "public_work", "family_interest"]:
				if not Rules.amount(model.priorities.get(key)): return Rules.fail("幕僚机会优先序无效")
			for kin in model.kin_ids:
				if not raw.character_states.has(kin): return Rules.fail("幕僚亲属关系指向缺失人物")
	for row in raw.get("economic_contracts", {}).values():
		if row.get("contract_kind") != "official_initiative": continue
		if config.is_empty() or row.get("source_id") != SOURCE or not config.people.has(row.get("supplier_id")) or not raw.character_states.has(row.get("customer_id")) or row.get("head_office_id") != config.head_office_id or row.get("location_id") != config.location_id or not row.get("choice") is Dictionary or not row.get("considered") is Array or row.considered.is_empty() or row.choice != row.considered[0] or row.choice.get("initiative_id") != row.contract_id: return Rules.fail("幕僚请求缺少本人机会选择与来源")
		var term: Dictionary = raw.office_terms.get(row.get("term_id"), {})
		if not Rules.amount(row.get("created_day"), true) or int(row.created_day) > int(raw.current_day) or term.get("holder_id") != row.supplier_id or term.get("office_id") != row.get("office_id") or int(term.get("start_day", -1)) > int(row.created_day) or (int(term.get("end_day", -1)) >= 0 and int(term.end_day) < int(row.created_day)): return Rules.fail("幕僚请求没有真实在任工作日")
		if row.get("work_days") != 1 or row.get("last_work_day") != row.created_day or row.get("work_log") != [{"day": row.created_day, "attempt": row.created_day - row.created_day}]: return Rules.fail("幕僚请求丢失实际工作日")
		var receipt: Dictionary = raw.action_receipts.get(row.get("presentation_receipt"), {})
		if receipt.get("initiative_record") != record(row) or receipt.get("executor_id") != row.supplier_id or receipt.get("day") != row.created_day or not receipt.get("effect_refs", []).has(row.contract_id): return Rules.fail("幕僚请求缺少本人共同动作回执")
		for choice in row.considered:
			if not choice is Dictionary or choice.get("kind") not in ["promotion", "public_work", "family_interest"] or not choice.get("text") is String or not choice.get("target_id") is String or not choice.get("evidence") is Dictionary or choice.get("priority") != config.people[row.supplier_id].priorities[choice.kind] or int(choice.priority) > int(row.choice.priority): return Rules.fail("幕僚选择与本人机会优先序不符")
		if row.status == "pending":
			if row.has("resolution"): return Rules.fail("待答请求不能预造结果")
		elif row.status == "fulfilled":
			if outcome(raw, row).is_empty() or row.get("resolution") != outcome(raw, row): return Rules.fail("幕僚请求没有实际任命、验收或减免结果")
		elif row.status == "declined":
			var reply: Variant = row.get("resolution")
			if not reply is Dictionary or reply.get("kind") != "declined" or not raw.character_states.has(reply.get("principal_id")) or not Rules.amount(reply.get("day")) or int(reply.day) < int(row.created_day) or int(reply.day) > int(raw.current_day): return Rules.fail("幕僚驳回记录无效")
			for key in ["trust_before", "trust_after"]:
				if not (reply.get(key) is int or reply.get(key) is float) or float(reply[key]) != floor(float(reply[key])) or absf(float(reply[key])) > 100: return Rules.fail("幕僚驳回关系记录无效")
			if reply.trust_after != clampi(int(reply.trust_before) - 3, -100, 100): return Rules.fail("幕僚驳回关系后果无效")
			var decision: Dictionary = raw.action_receipts.get(reply.get("ref"), {})
			if decision.get("initiative_response") != {"initiative_id": row.contract_id, "person_id": row.supplier_id, "decision": "declined"} or decision.get("day") != reply.day: return Rules.fail("幕僚驳回缺少针对本人的共同回执")
		else: return Rules.fail("幕僚请求状态无效")
	return {"ok": true}
