extends RefCounted

# Match complete clauses to existing visible objects. This derives local scope;
# it neither adopts a plan nor supplies missing clauses from the model response.
const Visible = preload("res://scripts/core/assistant_context_projection.gd")
const Rules = preload("res://scripts/core/management_state_contract.gd")
const ROLE_NAMES := {"steward": ["管家"], "estate_head": ["田庄主事"], "shopkeeper": ["掌柜"], "guard_captain": ["护卫首领"]}

static func quote(context, text: String) -> Dictionary:
	var instruction = load("res://scripts/core/assistant_instruction_authority.gd")
	if instruction.nonexecuting(text): return _fail("当前交代包含否定、咨询、假设或引述")
	var split := RegEx.new()
	split.compile("[，,；;。]|然后|接着|最后|再(?=聘用|聘请|雇用|任命|破格|免去|强制|赠|将|把|找|寻访|打造|抄)")
	var clauses: PackedStringArray = split.sub(text, "\n", true).split("\n", false)
	var visible := Visible.project(context)
	var budgets: Dictionary = {}
	var funding_clauses: Array[String] = []
	var work_clauses: Array[String] = []
	for part in clauses:
		var clause := str(part).strip_edges().trim_prefix("先").trim_prefix("再").strip_edges()
		var budget := _budget(context, visible, clause)
		if budget.get("matched", false):
			if not budget.get("ok", false): return budget
			if budgets.has(budget.account_id): return _fail("同一账户重复声明预算，请明确累计上限")
			budgets[budget.account_id] = budget.amount
			funding_clauses.append(clause)
			continue
		if clause in ["直接办理", "现在办理", "即刻办理", "全权安排", "交给你办", "有劳了", "允许转委托", "可以转委托", "允许转派", "可以转派", "不允许转委托", "不可以转委托", "不允许转派", "不可以转派", "禁止转委托", "禁止转派"]: continue
		if instruction._term_clause(clause): continue
		if clause in ["不用再确认", "不用再次确认", "不必再问", "无需再确认", "无需再次确认"]: continue
		if not clause.is_empty(): work_clauses.append(clause)
	var result: Array = []
	var previous := ""
	for clause in work_clauses:
		var local := _action(context, visible, clause)
		var public_work := _public_work(context, visible, clause)
		var actions: Array = []
		if public_work.get("ok", false): actions = public_work.steps
		elif local.get("ok", false): actions = local.steps if local.has("steps") else [local.step]
		else:
			# Existing workshop/search clauses retain their source quotes and full quantity.
			var legacy: Dictionary = instruction.instruction_quote(context, "请" + _clean(clause) + ("，" + "，".join(funding_clauses) if not funding_clauses.is_empty() else ""))
			if not legacy.get("ok", false): return _fail("尚未完整对应这段交代的对象、动作或条件：" + clause)
			actions = legacy.proposal.plan.steps.duplicate(true)
		var mapped: Dictionary = {}
		for action in actions:
			var row: Dictionary = action.duplicate(true)
			var id := "instruction-step:%d" % result.size()
			for key in ["order_id", "search_id", "aid_id", "journey_id"]:
				if row.parameters.has(key):
					var old: String = row.parameters[key]
					if not mapped.has(old): mapped[old] = old + ":clause:%d" % result.size()
					row.parameters[key] = mapped[old]
			row.target_refs = row.target_refs.map(func(target): return mapped.get(target, target))
			row["step_id"] = id
			row["depends_on"] = [] if previous.is_empty() else [previous]
			result.append(row)
			previous = id
			if row.action_kind in ["hire_family", "appoint_office", "dismiss_family", "dismiss_office", "force_dismiss_office"]:
				for office in visible.offices + visible.official_offices:
					if office.office_id == row.parameters.office_id: office.holder_id = row.parameters.get("candidate_id", "")
			if row.action_kind == "give_item":
				for item in visible.assets:
					if item.get("asset_id") == row.parameters.item_id: item["can_dispose"] = false
	if result.is_empty(): return _fail("尚未指明实际办理事项")
	return {"ok": true, "steps": result, "budgets": budgets}

static func authorizes(context, text: String, compiled: Dictionary) -> bool:
	if not compiled.get("ok", false) or compiled.get("dto", {}).get("kind") != "proposal": return false
	var scope := quote(context, text)
	if not scope.get("ok", false): return false
	var instruction = load("res://scripts/core/assistant_instruction_authority.gd")
	if not instruction._same_steps(compiled.plan.steps, scope.steps): return false
	for limit in compiled.authorization.resource_limits:
		if not scope.budgets.has(limit.account_id) or int(limit.amount) > int(scope.budgets[limit.account_id]): return false
	var terms: Dictionary = instruction.terms(context, text, compiled.plan.steps, int(compiled.get("instruction_day", -1)))
	if not terms.get("ok", false): return false
	compiled.authorization.valid_until_day = terms.valid_until_day
	compiled.authorization.scope.allow_subdelegation = terms.allow_subdelegation
	return true

static func _clean(text: String) -> String:
	var result := text.strip_edges()
	for prefix in ["请帮我", "请替我", "请你", "请", "帮我", "替我", "为我"]:
		if result.begins_with(prefix): result = result.trim_prefix(prefix).strip_edges(); break
	return result

static func _budget(context, visible: Dictionary, text: String) -> Dictionary:
	var pattern := RegEx.new()
	pattern.compile("^(?:从|用)?(家族公账|家族主账户|我的私款|个人私款|私款|国帑|州库公款|州库|本州公款)(?:拿|花)?(?:不超过|不得超过|最多|至多|累计预算|预算上限|预算)[：:\\s]*([0-9零〇一二两三四五六七八九十百千万]+)(?:钱|记账单位)?$")
	var found := pattern.search(text)
	if found == null: return {"matched": false}
	var amount: int = load("res://scripts/ai/assistant_plan_parser.gd").new()._instruction_amount(found.get_string(2))
	if not Rules.amount(amount, true): return {"ok": false, "matched": true, "error": "预算须是实际正整数"}
	var source_name := found.get_string(1)
	var owner_kind := "clan" if source_name.begins_with("家族") else ("office" if source_name in ["国帑", "州库公款", "州库", "本州公款"] else "character")
	var matches: Array = visible.accounts.filter(func(account): return context.state.resource_accounts[account.account_id].owner_ref.entity_kind == owner_kind)
	if source_name == "国帑": matches = matches.filter(func(account): return account.account_id == "court_treasury")
	elif owner_kind == "office": matches = matches.filter(func(account): return context.state.resource_accounts[account.account_id].get("organization_id") == context.state.flags.get("player_organization_id") and context.state.resource_accounts[account.account_id].storage_ref.storage_kind == "depot")
	if matches.size() != 1: return {"ok": false, "matched": true, "error": "资金来源未对应唯一可支配账户"}
	return {"ok": true, "matched": true, "account_id": matches[0].account_id, "amount": amount}

static func _action(context, visible: Dictionary, raw_text: String) -> Dictionary:
	var text := _clean(raw_text)
	var fiscal := _fiscal(context, visible, text)
	if fiscal.get("ok", false): return fiscal
	var school := _school(context, visible, text)
	if school.get("ok", false): return school
	var matches: Array = []
	for initiative in visible.get("official_initiatives", []):
		if initiative.status == "pending" and text == "驳回%s这次请求" % initiative.name: _add(matches, "decline_official_initiative", {"office_id": initiative.head_office_id, "initiative_id": initiative.initiative_id}, [initiative.head_office_id, initiative.initiative_id])
	var local_fiscal: Dictionary = visible.get("local_fiscal", {})
	if local_fiscal.get("office_id", "") != "":
		if text in ["按常额办理本期地方征收", "按急征办理本期地方征收"]:
			_add(matches, "issue_local_levy", {"office_id": local_fiscal.office_id, "levy_id": "levy:%s:%d" % [context.state.player_character_id, int(context.state.state_revision)], "policy": "ordinary" if text.contains("常额") else "emergency"}, [local_fiscal.office_id])
		for levy in local_fiscal.levies:
			for person in levy.people:
				if person.can_remit and text == "减免%s本期未缴款" % person.name: _add(matches, "remit_local_levy", {"office_id": local_fiscal.office_id, "levy_id": levy.levy_id, "person_id": person.person_id}, [local_fiscal.office_id, levy.levy_id, person.person_id])
	for match_row in visible.get("marriages", []):
		if text == "探询%s的婚事" % match_row.name:
			var id := "marriage:%s:%d" % [context.state.player_character_id, int(context.state.state_revision)]
			return {"ok": true, "steps": [{"action_kind": "inquire_marriage", "parameters": {"match_id": match_row.match_id, "proposal_id": id, "offered_gift": 20}, "target_refs": [match_row.match_id]}, {"action_kind": "receive_marriage_terms", "parameters": {"match_id": match_row.match_id, "proposal_id": id}, "target_refs": [match_row.match_id]}]}
		if text == "完整安排%s的婚事" % match_row.name:
			for proposal in match_row.proposals:
				if proposal.status != "offered": continue
				var steps: Array = []
				for kind in ["accept_marriage_terms", "deliver_marriage_gift", "complete_marriage"]:
					steps.append({"action_kind": kind, "parameters": {"match_id": match_row.match_id, "proposal_id": proposal.proposal_id}, "target_refs": [match_row.match_id]})
				return {"ok": true, "steps": steps}
	for person in visible.get("official_journeys", {}).get("candidates", []):
		for depot in visible.get("grain_depots", []):
			if text == "派%s到%s核仓并回报" % [person.name, depot.name]:
				var id := "envoy:%s:%d" % [context.state.player_character_id, int(context.state.state_revision)]
				var targets: Array = [person.person_id, depot.depot_id]
				return {"ok": true, "steps": [{"action_kind": "send_official_envoy", "parameters": {"journey_id": id, "person_id": person.person_id, "target_depot_id": depot.depot_id, "funding_account_id": str(context.state.player_character_id) + "_cash"}, "target_refs": targets}, {"action_kind": "receive_official_report", "parameters": {"journey_id": id, "person_id": person.person_id, "target_depot_id": depot.depot_id}, "target_refs": targets.duplicate()}]}
	for source in visible.get("grain_depots", []):
		for target in visible.get("grain_depots", []):
			if source.depot_id == target.depot_id: continue
			var pattern := RegEx.new()
			pattern.compile("^从" + str(source.name) + "调粮([0-9零〇一二两三四五六七八九十百千万]+)到" + str(target.name) + "$")
			var match_result := pattern.search(text)
			if match_result != null:
				var amount: int = load("res://scripts/ai/assistant_plan_parser.gd").new()._instruction_amount(match_result.get_string(1))
				if Rules.amount(amount, true):
					var order_id := "grain:%s:%d" % [context.state.player_character_id, int(context.state.state_revision)]
					var targets: Array = [source.depot_id, target.depot_id]
					return {"ok": true, "steps": [{"action_kind": "commission_grain_transport", "parameters": {"order_id": order_id, "source_depot_id": source.depot_id, "target_depot_id": target.depot_id, "grain_amount": amount}, "target_refs": targets}, {"action_kind": "await_grain_report", "parameters": {"order_id": order_id, "source_depot_id": source.depot_id, "target_depot_id": target.depot_id}, "target_refs": targets.duplicate()}]}
	for office in visible.offices:
		var names: Array = [office.name]
		names.append_array(ROLE_NAMES.get(office.role_key, []))
		for person in office.candidates:
			for name in names:
				for verb in ["聘用", "聘请", "雇用"]:
					if text in [verb + str(person.name) + "担任" + str(name), verb + str(person.name) + "做" + str(name), verb + str(person.name) + "为" + str(name)]: _add(matches, "hire_family", {"office_id": office.office_id, "candidate_id": person.character_id}, [office.office_id])
		if office.holder_id != "":
			var holder: String = context.state.character_states[office.holder_id].name
			for name in names:
				if text in ["免去" + holder + "的" + str(name) + "职务", "辞退" + holder, "让" + holder + "卸任" + str(name)]: _add(matches, "dismiss_family", {"office_id": office.office_id}, [office.office_id])
	for office in visible.official_offices:
		var names: Array = [office.name, preload("res://scripts/domain/tang_office_catalog.gd").get_office_definition(office.office_id).get("name", office.name)]
		for candidate in office.candidates:
			var person: String = context.state.character_states[candidate.character_id].name
			var prefix := "破格" if candidate.mode == "exceptional" else ""
			for name in names:
				if text in [prefix + "任命" + person + "为" + str(name), prefix + "任命" + person + "担任" + str(name)]: _add(matches, "appoint_office", {"office_id": office.office_id, "candidate_id": candidate.character_id, "mode": candidate.mode}, [office.office_id, candidate.character_id])
		if office.holder_id != "":
			var holder: String = context.state.character_states[office.holder_id].name
			for name in names:
				for prefix in ["", "强制", "强行"]:
					if text == prefix + "免去" + holder + "的" + str(name) + "职务": _add(matches, "dismiss_office" if prefix == "" else "force_dismiss_office", {"office_id": office.office_id, "holder_id": office.holder_id}, [office.office_id, office.holder_id])
	for item in visible.assets:
		if item.get("asset_kind") != "movable" or not item.get("can_dispose", false): continue
		for person in visible.local_people:
			for verb in ["赠给", "送给", "赏赐给"]:
				if text in ["将" + str(item.name) + verb + str(person.name), "把" + str(item.name) + verb + str(person.name)]: _add(matches, "give_item", {"item_id": item.asset_id, "recipient_id": person.character_id}, [item.asset_id, person.character_id])
			if text == "赠送" + str(item.name) + "给" + str(person.name): _add(matches, "give_item", {"item_id": item.asset_id, "recipient_id": person.character_id}, [item.asset_id, person.character_id])
	return {"ok": true, "step": matches[0]} if matches.size() == 1 else _fail("动作或对象未唯一对应")

static func _add(matches: Array, kind: String, params: Dictionary, targets: Array) -> void:
	var row := {"action_kind": kind, "parameters": params, "target_refs": targets}
	if not matches.has(row): matches.append(row)

static func _fiscal(context, visible: Dictionary, text: String) -> Dictionary:
	var pattern := RegEx.new()
	var sources := "(家族公账|家族主账户|我的私款|个人私款|私款|州库公款|州库|本州公款)"
	var amount_text := "([0-9零〇一二两三四五六七八九十百千万]+)"
	pattern.compile("^用" + sources + "归还" + amount_text + "(?:钱)?公款$")
	var found := pattern.search(text)
	if found != null:
		var source := _budget(context, visible, found.get_string(1) + "预算1")
		var amount: int = load("res://scripts/ai/assistant_plan_parser.gd").new()._instruction_amount(found.get_string(2))
		var cases: Array = visible.get("fiscal_cases", []).filter(func(case): return case.responsible_id == context.state.player_character_id and int(case.remaining_amount) > 0)
		if not source.get("ok", false) or cases.size() != 1 or not Rules.amount(amount, true) or amount > int(cases[0].remaining_amount): return _fail("归还须明确唯一欠款、可用来源和金额")
		if context.state.resource_accounts[source.account_id].owner_ref.entity_kind not in ["character", "clan"]: return _fail("归还公款不能继续挪用公款")
		return {"ok": true, "step": {"action_kind": "repay_public_cash", "target_refs": [cases[0].contract_id], "parameters": {"case_id": cases[0].contract_id, "funding_account_id": source.account_id, "amount": amount}}}
	pattern.compile("^从" + sources + "转" + amount_text + "(?:钱)?到" + sources + "$")
	found = pattern.search(text)
	if found == null: return _fail("未明确资金划转")
	var source := _budget(context, visible, found.get_string(1) + "预算1")
	var destination := _budget(context, visible, found.get_string(3) + "预算1")
	var amount: int = load("res://scripts/ai/assistant_plan_parser.gd").new()._instruction_amount(found.get_string(2))
	if not source.get("ok", false) or not destination.get("ok", false) or not Rules.amount(amount, true) or source.account_id == destination.account_id: return _fail("资金划转须明确两个不同的真实账户与金额")
	return {"ok": true, "step": {"action_kind": "transfer_cash", "target_refs": [destination.account_id], "parameters": {"source_account_id": source.account_id, "destination_account_id": destination.account_id, "amount": amount}}}

static func _school(context, visible: Dictionary, text: String) -> Dictionary:
	var matches: Array = []
	for school in visible.get("schools", []):
		for offer in school.available_supply_offers:
			var clause: String = "扩建" + str(school.name) + "并验收" if offer.output_kind == "seats" else "补充" + str(school.name) + "课书并验收"
			if text == clause and int(offer.remaining_orders) > 0:
				return {"ok": true, "steps": [{"action_kind": "commission_school_supply", "target_refs": [school.asset_id], "parameters": {"school_id": school.asset_id, "supply_id": offer.supply_id, "order_id": offer.proposed_order_id, "funding_account_id": school.account_id}}, {"action_kind": "receive_school_supply", "target_refs": [school.asset_id], "parameters": {"school_id": school.asset_id, "order_id": offer.proposed_order_id}}]}
		if text == "开办" + str(school.name) + "考核" and school.can_open_assessment:
			_add(matches, "open_school_assessment", {"school_id": school.asset_id, "assessment_id": school.proposed_assessment_id, "funding_account_id": school.account_id}, [school.asset_id])
		for student in school.eligible_candidates:
			var name: String = context.state.character_states[student.character_id].name
			if text == "安排" + name + "参加" + str(school.name) + "考核":
				var current: Array = school.assessments.filter(func(exam): return exam.status == "registration" and int(context.state.current_day) <= int(exam.deadline))
				if current.size() == 1 or school.can_open_assessment:
					var id: String = current[0].contract_id if current.size() == 1 else school.proposed_assessment_id
					_add(matches, "register_school_candidate", {"school_id": school.asset_id, "assessment_id": id, "student_id": student.character_id}, [school.asset_id])
		for candidate in school.exam_travel_candidates:
			var name: String = context.state.character_states[candidate.student_id].name
			if text == "安排" + name + "从" + str(school.name) + "赴行在候试并核收到场回报":
				return {"ok": true, "steps": [{"action_kind": "send_exam_candidate", "target_refs": [school.asset_id, candidate.student_id], "parameters": {"school_id": school.asset_id, "student_id": candidate.student_id, "journey_id": candidate.proposed_journey_id, "funding_account_id": school.account_id}}, {"action_kind": "receive_exam_arrival_report", "target_refs": [school.asset_id], "parameters": {"school_id": school.asset_id, "journey_id": candidate.proposed_journey_id}}]}
		for student in school.student_offers:
			var name: String = context.state.character_states[student.character_id].name
			if not student.get("aid_willing", false) or not school.has("living_aid_rule"): continue
			for source in school.living_aid_sources:
				if text == "用" + str(source.name) + "资助" + name + "在" + str(school.name) + "求学":
					var prior: Array = school.living_aid_awards.filter(func(row): return row.student_id == student.character_id)
					_add(matches, "sponsor_school_student", {"school_id": school.asset_id, "student_id": student.character_id, "aid_id": "school-aid:%s:%s:%d" % [school.asset_id, student.character_id, prior.size() + 1], "funding_account_id": source.account_id}, [school.asset_id, student.character_id])
		for teacher in school.teacher_offers:
			var name: String = context.state.character_states[teacher.teacher_id].name
			if text == "聘请" + name + "在" + str(school.name) + "授课" and teacher.can_hire:
				_add(matches, "hire_school_teacher", {"school_id": school.asset_id, "teacher_id": teacher.teacher_id, "funding_account_id": school.account_id, "contract_id": teacher.proposed_contract_id}, [school.asset_id])
		for student in school.waiting:
			var name: String = context.state.character_states[student.character_id].name
			if text == "安排" + name + "到" + str(school.name) + "入学":
				_add(matches, "enroll_school_student", {"school_id": school.asset_id, "student_id": student.character_id, "enrollment_id": "school-study:%s:%s" % [school.asset_id, student.character_id]}, [school.asset_id])
	return {"ok": true, "step": matches[0]} if matches.size() == 1 else _fail("未唯一明确学舍、先生或求学者")

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}

static func _public_work(context, visible: Dictionary, clause: String) -> Dictionary:
	var text := _clean(clause)
	for canal in visible.get("public_works", []):
		if text in ["修复" + str(canal.name) + "并验收通水", "修缮" + str(canal.name) + "并验收通水"] and canal.status == "damaged":
			var id := "public-work:%s:%s" % [context.state.player_character_id, canal.asset_id]
			return {"ok": true, "steps": [{"step_id": "start", "action_kind": "start_public_work", "parameters": {"canal_id": canal.asset_id, "funding_account_id": canal.account_id, "order_id": id}, "target_refs": [canal.asset_id], "depends_on": []}, {"step_id": "finish", "action_kind": "finish_public_work", "parameters": {"order_id": id}, "target_refs": [id], "depends_on": ["start"]}]}
	return _fail("未明确修渠与验收范围")
