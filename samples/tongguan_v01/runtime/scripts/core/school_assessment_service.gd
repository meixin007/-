extends RefCounted
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Education = preload("res://scripts/core/education_service.gd")
const Workload = preload("res://scripts/core/character_workload_service.gd")
const Presence = preload("res://scripts/core/production_service.gd")
const KINDS := ["open_school_assessment", "register_school_candidate"]
const CONTRACT_KINDS := ["school_assessment", "school_candidacy"]

# Shared assessment contracts retain separate venue identity and qualification.
static func student_offers(state, school: Dictionary) -> Array:
	return load("res://scripts/core/central_examination_service.gd").offers(state, school) if school.get("asset_kind") == "examination_hall" else school.get("student_offers", [])

static func student_offer(state, school: Dictionary, person: String) -> Dictionary:
	for offer in student_offers(state, school):
		if offer.character_id == person: return offer
	return {}

static func fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}

static func assessments(state, school_id: String) -> Array:
	var rows: Array = state.economic_contracts.values().filter(func(row): return row.get("contract_kind") == "school_assessment" and row.get("school_id") == school_id)
	rows.sort_custom(func(a, b): return int(a.created_day) < int(b.created_day))
	return rows

static func candidates(state, assessment_id: String) -> Array:
	return state.economic_contracts.values().filter(func(row): return row.get("contract_kind") == "school_candidacy" and row.get("assessment_id") == assessment_id)

static func course_for(state, school_id: String, person: String) -> Dictionary:
	if state.management_assets.get(school_id, {}).get("asset_kind") == "examination_hall": return load("res://scripts/core/central_examination_service.gd").course_for(state, school_id, person)
	for row in state.economic_contracts.values():
		if row.get("contract_kind") == "school_enrollment" and row.get("school_id") == school_id and row.get("supplier_id") == person and row.get("assessment_eligible", false): return row
	return {}

static func admitted(state, school_id: String, person: String) -> bool:
	return state.economic_contracts.values().any(func(row): return row.get("contract_kind") == "school_candidacy" and row.get("school_id") == school_id and row.get("supplier_id") == person and row.get("status") == "admitted")

static func location_for(state, params: Dictionary) -> String:
	return str(state.management_assets.get(params.get("school_id", ""), {}).get("location_id", ""))

static func cost_for(state, kind: String, params: Dictionary) -> Dictionary:
	var school: Dictionary = state.management_assets.get(params.get("school_id", ""), {})
	var rule: Dictionary = school.get("assessment_rule", {})
	if school.get("asset_kind") not in ["school", "examination_hall"] or rule.is_empty(): return fail("该学舍尚无有来源的考核规则")
	if str(params.get("assessment_id", "")).is_empty(): return fail("考核须有独立场次记录")
	if kind == "open_school_assessment":
		if params.get("funding_account_id") != school.account_id: return fail("考核经费须来自该学舍账户")
		return {"ok": true, "amount": int(rule.fee), "account_id": school.account_id}
	if kind != "register_school_candidate" or student_offer(state, school, str(params.get("student_id", ""))).is_empty(): return fail("报考须对应已知真实求学者")
	return {"ok": true, "amount": 0, "account_id": ""}

static func apply(state, kind: String, params: Dictionary, principal: String, execution: String, reservation: String) -> Dictionary:
	var quote := cost_for(state, kind, params)
	if not quote.ok: return quote
	var school: Dictionary = state.management_assets[params.school_id]
	if not Education.authority(state, school, principal) and not (school.asset_kind == "examination_hall" and kind == "register_school_candidate" and params.get("student_id") == principal): return fail("当前没有该考核经办权")
	if kind == "register_school_candidate": return _register(state, school, params, principal, execution)
	var rule: Dictionary = school.assessment_rule
	var prior := assessments(state, school.asset_id)
	if state.economic_contracts.has(params.assessment_id): return fail("考核场次标识已使用")
	if not prior.is_empty() and (prior[-1].status != "completed" or int(state.current_day) < int(prior[-1].next_open_day)): return fail("当前场次尚未结束或尚未到下一期，不能重复增发名额")
	if student_offers(state, school).all(func(offer): return course_for(state, school.asset_id, offer.character_id).is_empty() or admitted(state, school.asset_id, offer.character_id)): return fail("当前没有尚待竞争名额的合格学员")
	if not Presence.present(state, rule.examiner_id, school.location_id) or not Workload.can_schedule(state, rule.examiner_id, "assessment", principal) or int(state.character_states[rule.examiner_id].get("stats", {}).get("scholarship", 0)) < int(rule.examiner_threshold): return fail("考官不在当地、学力不足或没有可履约的空闲日")
	var paid := Accounts.new().apply(state, "transfer", {"execution_id": execution, "actor_id": principal, "source_account_id": school.account_id, "destination_account_id": rule.payee_account_id, "amount": int(rule.fee), "reason_ref": params.assessment_id, "reservation_id": reservation})
	if not paid.get("ok", false): return paid
	var row := _record(state, params.assessment_id, "school_assessment", school.asset_id, principal, rule.examiner_id)
	row.merge({"rule": rule.duplicate(true), "commission_receipt": execution, "status": "registration", "deadline": int(state.current_day) + int(rule.registration_days), "next_open_day": int(state.current_day) + int(rule.interval_days), "candidate_refs": [], "ranked_refs": []})
	state.economic_contracts[params.assessment_id] = row
	return {"ok": true, "result_ref": params.assessment_id, "journal_refs": [execution], "visible_summary": "已开%s，名额 %d；报名截止第 %d 日，考官须履行两日考核。录取不自动任官。" % ["行在考试" if school.asset_kind == "examination_hall" else "州学荐举考核", int(rule.quota), int(row.deadline)]}

static func _record(state, id: String, kind: String, school: String, principal: String, person: String) -> Dictionary:
	return {"contract_id": id, "contract_kind": kind, "school_id": school, "customer_id": principal, "supplier_id": person, "created_day": int(state.current_day), "last_work_day": int(state.current_day), "work_days": 0, "work_log": [], "blocked_reason": ""}

static func _register(state, school: Dictionary, params: Dictionary, principal: String, execution: String) -> Dictionary:
	var exam: Dictionary = state.economic_contracts.get(params.assessment_id, {})
	var person: String = params.student_id
	var offer := student_offer(state, school, person)
	var course := course_for(state, school.asset_id, person)
	if exam.get("contract_kind") != "school_assessment" or exam.get("school_id") != school.asset_id or exam.get("status") != "registration" or int(state.current_day) > int(exam.deadline): return fail("报名场次不存在或已截止")
	if not offer.get("assessment_willing", false) or course.is_empty() or admitted(state, school.asset_id, person): return fail("本人未同意报考、学业资格不足或已取得本学舍荐举名额")
	if not Presence.present(state, person, school.location_id) or not Workload.can_schedule(state, person, "assessment", principal): return fail("报考者未到当地或没有可投入考核的空闲日")
	var id := "candidacy:%s:%s" % [params.assessment_id, person]
	if state.economic_contracts.has(id): return fail("同一人物不能重复报名同一场次")
	if exam.candidate_refs.size() >= mini(int(school.seats), int(school.book_sets)): return fail("本场实际席位或课书已满；保留学业与报考资格，等待下一期")
	var row := _record(state, id, "school_candidacy", school.asset_id, principal, person)
	row.merge({"assessment_id": exam.contract_id, "course_id": course.contract_id, "registration_receipt": execution, "status": "registered", "score": -1, "rank": 0})
	if school.asset_kind == "examination_hall": row["journey_ref"] = load("res://scripts/core/central_examination_service.gd").arrival(state, school.asset_id, person).contract_id
	state.economic_contracts[id] = row
	exam.candidate_refs.append(id)
	return {"ok": true, "result_ref": id, "visible_summary": "已为%s登记报考；须实际到考，成绩及格后按有限名额竞争。" % state.character_states[person].name}

static func _ready(state, row: Dictionary, school: Dictionary) -> bool:
	return Presence.present(state, row.supplier_id, school.location_id) and Accounts.new().available(state, row.supplier_id + "_rations") > 0 and not Workload.occupied_today(state, row.supplier_id, row.contract_id, row.customer_id, "assessment")

static func settle_daily(state) -> Dictionary:
	for exam in state.economic_contracts.values():
		if exam.get("contract_kind") != "school_assessment" or exam.status == "completed" or int(state.current_day) <= int(exam.deadline) or int(exam.last_work_day) >= int(state.current_day): continue
		var school: Dictionary = state.management_assets[exam.school_id]
		if not _ready(state, exam, school) or int(state.character_states[exam.supplier_id].get("stats", {}).get("scholarship", 0)) < int(exam.rule.examiner_threshold):
			exam.blocked_reason = "考官缺席、缺粮、学力不足或今日已有职责，保留报名及付费义务等待履约。"
			continue
		Workload.record_work(state, exam)
		exam.work_log[-1]["examiner_skill"] = int(state.character_states[exam.supplier_id].stats.scholarship)
		exam.blocked_reason = ""
		if exam.status == "registration":
			exam.work_log[-1]["candidate_refs"] = []
			for row in candidates(state, exam.contract_id):
				if not _ready(state, row, school):
					row.status = "absent"
					row.blocked_reason = "本场未能到考：缺席、缺粮或当日职责冲突；原学业保留，可等待下一期。"
					continue
				Workload.record_work(state, row)
				row.work_log[-1]["assessment_ref"] = exam.contract_id
				row.score = int(state.economic_contracts[row.course_id].learning_score)
				row.status = "awaiting_result"
				exam.work_log[-1].candidate_refs.append(row.contract_id)
			exam.status = "marking"
		else:
			var ranked: Array = candidates(state, exam.contract_id).filter(func(row): return row.work_days == 1)
			ranked.sort_custom(func(a, b): return int(a.score) > int(b.score) if int(a.score) != int(b.score) else str(a.supplier_id) < str(b.supplier_id))
			for index in ranked.size():
				var row: Dictionary = ranked[index]
				row.rank = index + 1
				row.status = "below_threshold" if int(row.score) < int(exam.rule.pass_score) else ("admitted" if index < int(exam.rule.quota) else "not_selected")
				exam.ranked_refs.append(row.contract_id)
			for row in candidates(state, exam.contract_id): row["result_day"] = int(state.current_day)
			exam.status = "completed"
			exam["completed_day"] = int(state.current_day)
	return {"ok": true}

static func outcome_text(state, row: Dictionary) -> String:
	var exam: Dictionary = state.economic_contracts.get(row.get("assessment_id", ""), {})
	if state.management_assets.get(row.get("school_id"), {}).get("asset_kind") == "examination_hall" and row.get("status") == "admitted":
		for term in state.office_terms.values():
			if term.get("education_ref") == row.contract_id and int(term.get("end_day", 0)) < 0:
				return "中央考试录取后已正式任为%s，实际任期保留原资格与到任来源。" % str(state.office_state.get(term.office_id, {}).get("name", term.office_id))
		return "行在考试录取，保留实际学业、地方荐举和到场来源；尚须有权者正式任命，不自动授官。"
	match row.get("status"):
		"registered": return "已报名，等待第 %d 日截止后实际考核。" % int(exam.get("deadline", 0))
		"awaiting_result": return "已完成实际到考，等待考官下一工作日评定。"
		"admitted":
			for office in state.office_state.values():
				if office.get("entry_school_id") == row.school_id and office.get("holder_id") == row.supplier_id and office.get("status") == "appointed": return "考核录取后已正式辟用为%s，按实际任期履职与领取俸给。" % str(office.name)
			return "考核录取，取得州学荐举资格；尚须正式任命程序，不自动授予官职。"
		"not_selected": return "成绩及格，但本期名额不足；学业保留，等待第 %d 日起下一期，期间仍须谋生。" % int(exam.get("next_open_day", 0))
		"below_threshold": return "成绩未达本期门槛；原学业保留，可等待第 %d 日起下一期。" % int(exam.get("next_open_day", 0))
		"absent": return str(row.blocked_reason) + "下一期开办日不早于第 %d 日。" % int(exam.get("next_open_day", 0))
	return "等待实际考核记录。"

static func project(state, school: Dictionary) -> Dictionary:
	var exams := assessments(state, school.asset_id)
	var latest: Dictionary = exams[-1] if not exams.is_empty() else {}
	var available: Array = student_offers(state, school).filter(func(offer): return offer.get("assessment_willing", false) and not course_for(state, school.asset_id, offer.character_id).is_empty() and not admitted(state, school.asset_id, offer.character_id))
	var rows: Array = []
	for exam in exams:
		var row: Dictionary = exam.duplicate(true)
		row["candidates"] = candidates(state, exam.contract_id).duplicate(true)
		for candidate in row.candidates: candidate["outcome_text"] = outcome_text(state, candidate)
		rows.append(row)
	return {"assessments": rows, "eligible_candidates": available, "can_open_assessment": school.has("assessment_rule") and not available.is_empty() and (latest.is_empty() or (latest.status == "completed" and int(state.current_day) >= int(latest.next_open_day))), "proposed_assessment_id": "assessment:%s:%d" % [school.asset_id, exams.size() + 1]}

static func validate(raw: Dictionary) -> Dictionary:
	var contracts: Dictionary = raw.get("economic_contracts", {})
	var schools: Dictionary = raw.get("management_assets", {})
	var characters: Dictionary = raw.get("character_states", {})
	var amount = load("res://scripts/core/management_state_contract.gd")
	for school in schools.values():
		if school.get("asset_kind") not in ["school", "examination_hall"] or not school.has("assessment_rule"): continue
		if school.asset_kind == "examination_hall" and (not amount.amount(school.get("seats"), true) or not amount.amount(school.get("book_sets"), true) or raw.resource_accounts.get(school.get("account_id"), {}).get("unit_id") != "cash_unit"): return fail("行在试场缺少实际容量和公款来源")
		var rule: Variant = school.assessment_rule
		if not rule is Dictionary or not characters.has(rule.get("examiner_id")) or not str(rule.get("source_id", "")).begins_with("scenario:") or not rule.get("content_basis") is String: return fail("学舍考核缺少真实考官或规则来源")
		for key in ["fee", "quota", "registration_days", "interval_days", "pass_score", "examiner_threshold"]:
			if not amount.amount(rule.get(key), true): return fail("考核名额、期限或报酬无效")
		if int(rule.interval_days) <= int(rule.registration_days) + 2 or int(rule.pass_score) > 100 or int(rule.examiner_threshold) > 100 or raw.resource_accounts.get(rule.get("payee_account_id"), {}).get("owner_ref") != {"entity_kind": "character", "entity_id": rule.examiner_id}: return fail("考核规则或考官收款人不符")
	var periods := {}
	var admitted_people := {}
	for row in contracts.values():
		if row.get("contract_kind") not in CONTRACT_KINDS: continue
		var school: Dictionary = schools.get(row.get("school_id"), {})
		if not school.has("assessment_rule") or not characters.has(row.get("customer_id")) or not characters.has(row.get("supplier_id")) or not row.get("work_log") is Array or not row.get("blocked_reason") is String or not amount.amount(row.get("created_day")) or int(row.created_day) > int(raw.current_day) or not amount.amount(row.get("work_days")) or int(row.work_days) != row.work_log.size(): return fail("考核合同缺少人物、规则或工日依据")
		if row.work_log.any(func(day): return not day is Dictionary) or row.get("last_work_day") != (row.created_day if row.work_log.is_empty() else row.work_log[-1].get("day")): return fail("考核工日与最后履约日不符")
		if row.contract_kind == "school_assessment":
			var rule: Dictionary = school.assessment_rule
			if row.get("rule") != rule or row.supplier_id != rule.examiner_id or row.get("deadline") != int(row.created_day) + int(rule.registration_days) or row.get("next_open_day") != int(row.created_day) + int(rule.interval_days) or int(row.work_days) > 2 or row.get("status") != ["registration", "marking", "completed"][int(row.work_days)]: return fail("考核阶段、工日或本期名额规则不符")
			if not periods.has(school.asset_id): periods[school.asset_id] = []
			periods[school.asset_id].append(row)
			var payment: Dictionary = raw.resource_journal.get(row.get("commission_receipt"), {})
			var receipt: Dictionary = raw.action_receipts.get(row.get("commission_receipt"), {})
			if payment.get("entry_kind") != "transfer" or payment.get("source_account_id") != school.account_id or payment.get("destination_account_id") != rule.payee_account_id or payment.get("amount") != rule.fee or payment.get("reason_ref") != row.contract_id or payment.get("actor_id") != row.customer_id or payment.get("day") != row.created_day or not receipt.get("effect_refs", []).has(row.contract_id): return fail("考核缺少真实经费支付及开办回执")
			if not row.get("candidate_refs") is Array or not row.get("ranked_refs") is Array: return fail("考核缺少报名与排名目录")
			if row.candidate_refs.size() > mini(int(school.seats), int(school.book_sets)): return fail("本场报名人数超过实际席位与课书")
			var seen := {}
			var ranked: Array = []
			for ref in row.candidate_refs:
				var candidate: Dictionary = contracts.get(ref, {})
				if seen.has(ref) or candidate.get("contract_kind") != "school_candidacy" or candidate.get("assessment_id") != row.contract_id: return fail("报名目录重复或人物来源不符")
				seen[ref] = true
				var registration_day: int = int(candidate.get("created_day", -1))
				var capacity_rule = load("res://scripts/core/school_supply_service.gd")
				var seats: int = mini(capacity_rule.physical_capacity(school, contracts, "seats", registration_day), capacity_rule.physical_capacity(school, contracts, "book_sets", registration_day))
				var concurrent: int = row.candidate_refs.filter(func(id): return int(contracts.get(id, {}).get("created_day", int(raw.current_day) + 1)) <= registration_day).size()
				if concurrent > seats: return fail("报名不能借用未来交验的学舍席位或课书")
				if candidate.get("work_days") == 1: ranked.append(candidate)
			ranked.sort_custom(func(a, b): return int(a.get("score", -1)) > int(b.get("score", -1)) if int(a.get("score", -1)) != int(b.get("score", -1)) else str(a.get("supplier_id", "")) < str(b.get("supplier_id", "")))
			for day in row.work_log:
				if not amount.amount(day.get("examiner_skill")) or int(day.examiner_skill) < int(rule.examiner_threshold) or int(day.examiner_skill) > 100 or int(day.get("day", -1)) <= int(row.deadline): return fail("考核工日缺少合格考官或早于报名截止")
			if not row.work_log.is_empty():
				var refs: Variant = row.work_log[0].get("candidate_refs")
				if not refs is Array or refs.size() != ranked.size(): return fail("实际到考与考官工日不符")
				var attendance := {}
				for candidate in ranked:
					if attendance.has(candidate.contract_id) or refs.count(candidate.contract_id) != 1: return fail("同一考生重复到考或缺少考官凭据")
					attendance[candidate.contract_id] = true
			if row.status == "completed":
				if row.get("completed_day") != row.work_log[-1].get("day") or row.ranked_refs != ranked.map(func(c): return c.contract_id): return fail("排名没有实际评定工日或次序错误")
				for index in ranked.size():
					var candidate: Dictionary = ranked[index]
					var expected := "below_threshold" if int(candidate.score) < int(rule.pass_score) else ("admitted" if index < int(rule.quota) else "not_selected")
					if candidate.get("status") != expected or candidate.get("rank") != index + 1: return fail("录取超过有限名额或未遵循公开成绩排序")
			elif not row.ranked_refs.is_empty(): return fail("未评定便产生录取排名")
		else:
			var exam: Dictionary = contracts.get(row.get("assessment_id"), {})
			var course: Dictionary = contracts.get(row.get("course_id"), {})
			var source_school: Dictionary = schools.get(course.get("school_id"), {}) if school.get("asset_kind") == "examination_hall" else school
			var offer := Education.student_offer(source_school, row.supplier_id)
			if school.get("asset_kind") == "examination_hall":
				var journey: Dictionary = contracts.get(row.get("journey_ref"), {})
				if not offer.get("central_exam_willing", false) or journey.get("contract_kind") != "school_exam_journey" or journey.get("supplier_id") != row.supplier_id or journey.get("course_ref") != row.get("course_id") or journey.get("status") not in ["arrived", "reported"] or journey.get("rule", {}).get("destination_id") != school.location_id or int(journey.get("arrived_day", raw.current_day + 1)) > int(row.created_day): return fail("中央报考缺少真实赴试到场、本人意愿及原学业")
			if exam.get("contract_kind") != "school_assessment" or exam.get("school_id") != school.asset_id or not exam.get("candidate_refs", []).has(row.contract_id) or row.contract_id != "candidacy:%s:%s" % [exam.contract_id, row.supplier_id] or int(row.created_day) < int(exam.created_day) or int(row.created_day) > int(exam.deadline): return fail("报考重复或缺少有效场次")
			if not offer.get("assessment_willing", false) or course.get("contract_kind") != "school_enrollment" or course.get("school_id") != source_school.get("asset_id") or course.get("supplier_id") != row.supplier_id or not course.get("assessment_eligible", false) or int(course.get("completed_day", int(raw.current_day) + 1)) > int(row.created_day): return fail("报考缺少本人意愿或当时实际学业资格")
			if not raw.action_receipts.get(row.get("registration_receipt"), {}).get("effect_refs", []).has(row.contract_id): return fail("报考缺少经办回执")
			if int(row.work_days) > 1 or row.get("score") != (course.learning_score if int(row.work_days) == 1 else -1): return fail("考核成绩缺少真实到考和学业依据")
			if int(row.work_days) == 1 and (exam.get("work_log", []).is_empty() or row.work_log[0].get("day") != exam.work_log[0].get("day") or row.work_log[0].get("assessment_ref") != exam.contract_id): return fail("学生到考与考官记录不符")
			if exam.get("status") == "registration" and (row.get("status") != "registered" or int(row.work_days) != 0): return fail("报名阶段不能提前考核")
			if exam.get("status") != "registration" and int(row.work_days) == 0 and row.get("status") != "absent": return fail("未到考者不能取得成绩")
			if exam.get("status") == "marking" and int(row.work_days) == 1 and row.get("status") != "awaiting_result": return fail("尚未评定不能提前录取")
			if (exam.get("status") != "completed" or int(row.work_days) == 0) and row.get("rank") != 0: return fail("未评定或缺考者不能取得排名")
			if exam.get("status") == "completed" and row.get("result_day") != exam.get("completed_day"): return fail("考生结果缺少实际评定日期")
			if row.get("status") == "admitted":
				var key := "%s:%s" % [school.asset_id, row.supplier_id]
				if admitted_people.has(key): return fail("同一人物重复取得同一荐举资格")
				admitted_people[key] = true
	for rows in periods.values():
		rows.sort_custom(func(a, b): return int(a.created_day) < int(b.created_day))
		for index in range(1, rows.size()):
			if rows[index - 1].status != "completed" or int(rows[index].created_day) < maxi(int(rows[index - 1].next_open_day), int(rows[index - 1].completed_day)): return fail("同一期考核被重复开办以增发名额")
	return {"ok": true}
