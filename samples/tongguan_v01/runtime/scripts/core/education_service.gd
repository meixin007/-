extends RefCounted
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Contract = preload("res://scripts/core/management_state_contract.gd")
const Workload = preload("res://scripts/core/character_workload_service.gd")
const Presence = preload("res://scripts/core/production_service.gd")
const KINDS := ["hire_school_teacher", "enroll_school_student"]

static func initialize(state, data: Dictionary) -> Dictionary:
	for school in data.get("management", {}).get("regional_administration", {}).get("education_assets", []) + data.get("management", {}).get("regional_administration", {}).get("examination_assets", []):
		if not school is Dictionary or state.management_assets.has(school.get("asset_id")): return Contract.fail("学舍来源重复或无效")
		state.management_assets[school.asset_id] = school.duplicate(true)
	var route_seed: Dictionary = load("res://scripts/core/exam_journey_service.gd").initialize(state)
	if not route_seed.ok: return route_seed
	return validate(state.to_dictionary())

static func authority(state, school: Dictionary, actor: String) -> bool:
	return school.get("asset_kind") in ["school", "examination_hall"] and Accounts.new().can_operate(state, str(school.get("account_id", "")), actor)

static func teacher_offer(school: Dictionary, person: String) -> Dictionary:
	for offer in school.get("teacher_offers", []):
		if offer.teacher_id == person: return offer
	return {}

static func student_offer(school: Dictionary, person: String) -> Dictionary:
	for offer in school.get("student_offers", []):
		if offer.character_id == person: return offer
	return {}

static func faculty(state, school: Dictionary, active_only: bool = false) -> Array:
	var rows: Array = state.economic_contracts.values().filter(func(order): return order.get("contract_kind") == "school_teaching" and order.get("school_id") == school.asset_id and (not active_only or order.get("status") == "active"))
	rows.sort_custom(func(a, b): return int(a.created_day) < int(b.created_day) if int(a.created_day) != int(b.created_day) else str(a.contract_id) < str(b.contract_id))
	return rows

static func capacity(state, school: Dictionary) -> int:
	var total := 0
	for teaching in faculty(state, school, true): total += int(teaching.offer.capacity)
	return mini(mini(int(school.get("seats", 0)), int(school.get("book_sets", 0))), total)

static func available_capacity(state, school: Dictionary) -> int:
	var total := 0
	for teaching in faculty(state, school, true):
		if _ready(state, teaching.supplier_id, school, teaching, "teaching"): total += int(teaching.offer.capacity)
	return mini(mini(int(school.seats), int(school.book_sets)), total)

static func enrollments(state, school: Dictionary, active_only: bool = false) -> Array:
	return state.economic_contracts.values().filter(func(order): return order.get("contract_kind") == "school_enrollment" and order.get("school_id") == school.asset_id and (not active_only or order.get("status") == "studying"))

static func cost_for(state, kind: String, params: Dictionary) -> Dictionary:
	var school: Dictionary = state.management_assets.get(params.get("school_id", ""), {})
	if school.get("asset_kind") != "school": return Contract.fail("未找到实际学舍")
	if kind == "enroll_school_student":
		if student_offer(school, str(params.get("student_id", ""))).is_empty() or str(params.get("enrollment_id", "")).is_empty(): return Contract.fail("入学须有实际求学人物及独立记录")
		return {"ok": true, "amount": 0, "account_id": ""}
	var offer := teacher_offer(school, str(params.get("teacher_id", "")))
	if offer.is_empty() or params.get("funding_account_id") != school.account_id or str(params.get("contract_id", "")).is_empty(): return Contract.fail("聘师须对应先生实际报价、州学款源与合同")
	return {"ok": true, "amount": int(offer.price), "account_id": school.account_id}

static func location_for(state, params: Dictionary) -> String:
	return str(state.management_assets.get(params.get("school_id", ""), {}).get("location_id", ""))

static func apply(state, kind: String, params: Dictionary, principal: String, execution: String, reservation: String) -> Dictionary:
	var quote := cost_for(state, kind, params)
	if not quote.ok: return quote
	var school: Dictionary = state.management_assets[params.school_id]
	if not authority(state, school, principal): return Contract.fail("当前没有该学舍经办权")
	if kind == "enroll_school_student": return _enroll(state, school, params, principal, execution)
	if state.economic_contracts.has(params.contract_id): return Contract.fail("师资合同标识已使用，不能重复聘付")
	var offer := teacher_offer(school, params.teacher_id)
	if not Presence.present(state, params.teacher_id, school.location_id) or not Workload.can_schedule(state, params.teacher_id, "teaching", principal): return Contract.fail("先生未在当地或没有空闲授课日")
	if int(state.character_states[params.teacher_id].get("stats", {}).get("scholarship", 0)) < int(school.curriculum.assessment_threshold): return Contract.fail("先生当前学业不足以教授这门课程")
	if int(state.character_states[params.teacher_id].get("relationships", {}).get(principal, 0)) < -15: return Contract.fail("先生目前不愿接受聘请")
	if state.economic_contracts.values().any(func(order): return order.get("contract_kind") == "school_teaching" and order.get("supplier_id") == params.teacher_id and order.get("status") == "active"): return Contract.fail("先生已承接未完授课，不可重复许诺同一师资")
	var paid := Accounts.new().apply(state, "transfer", {"execution_id": execution, "actor_id": principal, "source_account_id": school.account_id, "destination_account_id": offer.payee_account_id, "amount": int(offer.price), "reason_ref": params.contract_id, "reservation_id": reservation})
	if not paid.get("ok", false): return paid
	state.economic_contracts[params.contract_id] = {"contract_id": params.contract_id, "contract_kind": "school_teaching", "school_id": school.asset_id, "customer_id": principal, "supplier_id": params.teacher_id, "funding_account_id": school.account_id, "offer": offer.duplicate(true), "commission_receipt": execution, "status": "active", "created_day": int(state.current_day), "last_work_day": int(state.current_day), "work_days": 0, "work_log": [], "blocked_reason": "等待学生入学。"}
	school.active_teaching_id = params.contract_id
	school.status = "teaching"
	school.contract_refs.append(params.contract_id)
	return {"ok": true, "result_ref": params.contract_id, "journal_refs": [execution], "visible_summary": "已聘%s：付酬 %d，须履行 %d 个真实授课日；未产生考试名额或任官。" % [state.character_states[params.teacher_id].name, int(offer.price), int(offer.teaching_days)]}

static func _enroll(state, school: Dictionary, params: Dictionary, principal: String, execution: String) -> Dictionary:
	var offer := student_offer(school, params.student_id)
	if not offer.willing or not offer.identity_eligible or not Presence.present(state, params.student_id, school.location_id): return Contract.fail("求学者尚未同意、身份资格不足或未到学舍")
	if int(state.character_states[params.student_id].get("relationships", {}).get(principal, 0)) < -15: return Contract.fail("求学者目前不愿接受这一安排")
	if not Workload.can_schedule(state, params.student_id, "study", principal): return Contract.fail("求学者没有可投入学习的空闲日")
	if enrollments(state, school, true).size() >= capacity(state, school): return Contract.fail("实际学舍、课书或师资容量已满；保留求学机会等待空位")
	if state.economic_contracts.has(params.enrollment_id) or state.economic_contracts.values().any(func(order): return order.get("contract_kind") == "school_enrollment" and order.get("supplier_id") == params.student_id): return Contract.fail("人物已有学习记录，不可重复占席或重发学习成果")
	state.economic_contracts[params.enrollment_id] = {"contract_id": params.enrollment_id, "contract_kind": "school_enrollment", "school_id": school.asset_id, "customer_id": principal, "supplier_id": params.student_id, "enrollment_receipt": execution, "offer": offer.duplicate(true), "curriculum": school.curriculum.duplicate(true), "status": "studying", "created_day": int(state.current_day), "last_work_day": int(state.current_day), "work_days": 0, "work_log": [], "learning_score": int(offer.initial_score), "assessment_eligible": false, "blocked_reason": "等待实际授课。"}
	school.contract_refs.append(params.enrollment_id)
	for teaching in faculty(state, school, true):
		if teaching.get("blocked_reason") in ["等待学生入学。", "暂无实际到课学生，保留未履行授课日。"]: teaching.blocked_reason = "学生已登记，等待实际授课日。"
	return {"ok": true, "result_ref": params.enrollment_id, "visible_summary": "已登记%s入学；学习、应试资格、名额、录取和任命分别核对。" % state.character_states[params.student_id].name}

static func _ready(state, person: String, school: Dictionary, contract: Dictionary, kind: String) -> bool:
	if kind == "teaching" and int(state.character_states.get(person, {}).get("stats", {}).get("scholarship", 0)) < int(school.curriculum.assessment_threshold): return false
	return Presence.present(state, person, school.location_id) and not Workload.occupied_today(state, person, contract.contract_id, contract.customer_id, kind) and Accounts.new().available(state, person + "_rations") > 0

static func settle_daily(state) -> Dictionary:
	for school in state.management_assets.values():
		if school.get("asset_kind") != "school": continue
		var teachers := faculty(state, school, true)
		var students := enrollments(state, school, true)
		students.sort_custom(func(a, b): return int(a.work_days) < int(b.work_days) if int(a.work_days) != int(b.work_days) else str(a.contract_id) < str(b.contract_id))
		for student in students:
			if int(student.last_work_day) >= int(state.current_day): continue
			if not _ready(state, student.supplier_id, school, student, "study"):
				student.blocked_reason = "本人未到场、缺口粮或今日另有职责；没有增加学业。"
			else:
				student.blocked_reason = "师资合同已到期，保留学业等待续聘。" if teachers.is_empty() else "当前可到课师资不足，保留学业等待实际授课；优先安排学习进度较少的学生。"
		var occupied: int = enrollments(state, school).filter(func(row): return row.work_log.any(func(day): return int(day.day) == int(state.current_day))).size()
		var remaining := maxi(0, mini(int(school.seats), int(school.book_sets)) - occupied)
		for teaching in teachers:
			if int(teaching.last_work_day) >= int(state.current_day): continue
			if not _ready(state, teaching.supplier_id, school, teaching, "teaching"):
				teaching.blocked_reason = "先生未到场、缺口粮或今日另有职责，未计授课。"
				continue
			var attended: Array = []
			for student in students:
				if student.status != "studying" or int(student.created_day) >= int(state.current_day) or int(student.last_work_day) >= int(state.current_day): continue
				if not _ready(state, student.supplier_id, school, student, "study"):
					student.blocked_reason = "本人未到场、缺口粮或今日另有职责；没有增加学业。"
					continue
				if attended.size() >= int(teaching.offer.capacity) or remaining <= 0: break
				Workload.record_work(state, student)
				student.work_log[-1]["teaching_ref"] = teaching.contract_id
				student.learning_score = mini(100, int(student.offer.initial_score) + int(student.work_days) * int(student.curriculum.score_per_lesson))
				state.character_states[student.supplier_id].stats["scholarship"] = int(student.learning_score)
				student.blocked_reason = ""
				if int(student.work_days) == int(student.curriculum.required_lessons):
					student.status = "completed"
					student["completed_day"] = int(state.current_day)
					student.assessment_eligible = bool(student.offer.identity_eligible) and int(student.learning_score) >= int(student.curriculum.assessment_threshold)
				attended.append(student.contract_id)
				remaining -= 1
			if attended.is_empty():
				teaching.blocked_reason = "暂无实际到课学生，保留未履行授课日。"
				continue
			Workload.record_work(state, teaching)
			teaching.work_log[-1]["student_refs"] = attended
			teaching.work_log[-1]["teacher_skill"] = int(state.character_states[teaching.supplier_id].stats.scholarship)
			teaching.blocked_reason = ""
			if int(teaching.work_days) == int(teaching.offer.teaching_days): teaching.status = "completed"
		school.status = "awaiting_teacher" if faculty(state, school, true).is_empty() else "teaching"
	return {"ok": true}

static func project(state, viewer: String) -> Array:
	var rows: Array = []
	for school in state.management_assets.values():
		if school.get("asset_kind") not in ["school", "examination_hall"] or not authority(state, school, viewer): continue
		var row: Dictionary = school.duplicate(true)
		if school.asset_kind == "examination_hall":
			row.merge(load("res://scripts/core/central_examination_service.gd").project(state, school))
			rows.append(row)
			continue
		row["capacity"] = capacity(state, school)
		row["available_capacity"] = available_capacity(state, school)
		row["faculty"] = faculty(state, school).duplicate(true)
		for offer in row.teacher_offers:
			offer["can_hire"] = not state.economic_contracts.values().any(func(order): return order.get("contract_kind") == "school_teaching" and order.get("supplier_id") == offer.teacher_id and order.get("status") == "active")
			offer["proposed_contract_id"] = "teaching:%s:%s:%d" % [school.asset_id, offer.teacher_id, row.faculty.filter(func(order): return order.supplier_id == offer.teacher_id).size() + 1]
		row["teaching"] = state.economic_contracts.get(school.active_teaching_id, {}).duplicate(true)
		row["students"] = enrollments(state, school).duplicate(true)
		row["waiting"] = school.student_offers.filter(func(offer): return offer.willing and not row.students.any(func(student): return student.supplier_id == offer.character_id)).duplicate(true)
		row["waiting_reason"] = "席位已满，等待下一空位；仍可另寻谋生与求学机会。" if enrollments(state, school, true).size() >= row.capacity else "本人表达求学意愿，等待入学安排。"
		if enrollments(state, school, true).size() >= row.capacity and row.capacity < mini(int(school.seats), int(school.book_sets)):
			row.waiting_reason = "现有师资容量已满，须等待先生空出授课名额或实际增聘师资；空教室不能自行授课。" if int(row.capacity) > 0 else "尚无可用师资，须先实际聘请先生。"
		row["proposed_contract_id"] = "teaching:%s:%d" % [school.asset_id, school.contract_refs.size()]
		row.merge(load("res://scripts/core/school_assessment_service.gd").project(state, school))
		row.merge(load("res://scripts/core/school_supply_service.gd").project(state, school))
		row.merge(load("res://scripts/core/school_living_aid_service.gd").project(state, school, viewer))
		row.merge(load("res://scripts/core/exam_journey_service.gd").project(state, school))
		rows.append(row)
	return rows

static func validate(raw: Dictionary) -> Dictionary:
	var assets: Dictionary = raw.get("management_assets", {})
	var contracts: Dictionary = raw.get("economic_contracts", {})
	var characters: Dictionary = raw.get("character_states", {})
	for order in contracts.values():
		if order.get("contract_kind") in ["school_teaching", "school_enrollment"]:
			if not order.get("work_log") is Array or order.work_log.any(func(day): return not day is Dictionary): return Contract.fail("教育工日须逐日记录实际对象")
	for school in assets.values():
		if school.get("asset_kind") != "school": continue
		if not Contract.amount(school.get("seats"), true) or not Contract.amount(school.get("book_sets"), true) or not school.get("curriculum") is Dictionary or not school.get("teacher_offers") is Array or not school.get("student_offers") is Array or not school.get("active_teaching_id") is String: return Contract.fail("学舍缺少实际容量、课书、课程或人物来源")
		if raw.get("resource_accounts", {}).get(school.get("account_id"), {}).get("owner_ref") != school.get("owner_ref") or not school.get("content_basis") is String: return Contract.fail("学舍归属与实际经费来源不符")
		for key in ["required_lessons", "score_per_lesson", "assessment_threshold"]:
			if not Contract.amount(school.curriculum.get(key), true) or int(school.curriculum[key]) > 100: return Contract.fail("学舍课程规则无效")
		var seen := {}
		for offer in school.teacher_offers:
			if not offer is Dictionary or not characters.has(offer.get("teacher_id")) or seen.has(offer.get("teacher_id")) or not str(offer.get("source_id", "")).begins_with("scenario:"): return Contract.fail("先生身份或报价来源无效")
			seen[offer.teacher_id] = true
			var skill: Variant = characters[offer.teacher_id].get("stats", {}).get("scholarship")
			if not Contract.amount(skill) or int(skill) > 100: return Contract.fail("先生学力必须在存档中保留有效数值")
			for key in ["price", "teaching_days", "capacity"]:
				if not Contract.amount(offer.get(key), true): return Contract.fail("授课报酬、工日或容量无效")
			if raw.resource_accounts.get(offer.get("payee_account_id"), {}).get("owner_ref") != {"entity_kind": "character", "entity_id": offer.teacher_id}: return Contract.fail("先生报酬未付给实际本人")
		seen.clear()
		for offer in school.student_offers:
			if not offer is Dictionary or not characters.has(offer.get("character_id")) or seen.has(offer.get("character_id")) or not offer.get("willing") is bool or not offer.get("identity_eligible") is bool or not Contract.amount(offer.get("initial_score")) or int(offer.initial_score) > 100 or not str(offer.get("source_id", "")).begins_with("scenario:"): return Contract.fail("求学者意愿、身份或初始学业来源无效")
			seen[offer.character_id] = true
		var teaching: Dictionary = contracts.get(school.active_teaching_id, {})
		if school.active_teaching_id != "" and (teaching.get("contract_kind") != "school_teaching" or teaching.get("school_id") != school.asset_id): return Contract.fail("学舍丢失当前师资合同")
		var school_faculty: Array = contracts.values().filter(func(order): return order.get("contract_kind") == "school_teaching" and order.get("school_id") == school.asset_id)
		if school.get("status") != ("teaching" if school_faculty.any(func(order): return order.get("status") == "active") else "awaiting_teacher"): return Contract.fail("学舍授课状态与全部真实师资不符")
		var active: Array = contracts.values().filter(func(order): return order.get("contract_kind") == "school_enrollment" and order.get("school_id") == school.asset_id and order.get("status") == "studying")
		if active.size() > mini(int(school.seats), int(school.book_sets)): return Contract.fail("同一学舍席位或课书被重复占用")
		# Existing enrollments survive a teacher's expiry. Check capacity when the
		# person entered instead of deleting their learning when faculty changes.
		var school_students: Array = contracts.values().filter(func(order): return order.get("contract_kind") == "school_enrollment" and order.get("school_id") == school.asset_id)
		for student in school_students:
			var enrolled_day := int(student.get("created_day", -1))
			var offered_capacity := 0
			for teacher in school_faculty:
				if int(teacher.get("created_day", enrolled_day + 1)) <= enrolled_day and (teacher.get("status") == "active" or int(teacher.get("last_work_day", -1)) >= enrolled_day): offered_capacity += int(teacher.get("offer", {}).get("capacity", 0))
			var simultaneous: int = school_students.filter(func(row): return int(row.get("created_day", enrolled_day + 1)) <= enrolled_day and int(row.get("completed_day", int(raw.current_day) + 1)) > enrolled_day).size()
			var supply = load("res://scripts/core/school_supply_service.gd")
			var physical: int = mini(supply.physical_capacity(school, contracts, "seats", enrolled_day), supply.physical_capacity(school, contracts, "book_sets", enrolled_day))
			if simultaneous > mini(physical, offered_capacity): return Contract.fail("入学时没有足够的真实师资、席位或课书")
		var references := {}
		for ref in school.get("contract_refs", []):
			var record: Dictionary = contracts.get(ref, {})
			if references.has(ref) or record.get("school_id") != school.asset_id or record.get("contract_kind") not in ["school_teaching", "school_enrollment"]: return Contract.fail("学舍合同目录重复或指向无关事务")
			references[ref] = true
	var classes := {}
	for teaching in contracts.values():
		if teaching.get("contract_kind") != "school_teaching": continue
		var school: Dictionary = assets.get(teaching.get("school_id"), {})
		for lesson in teaching.work_log:
			if not lesson.get("student_refs") is Array: return Contract.fail("分班授课缺少真实学生")
			var key := "%s:%d" % [school.get("asset_id", ""), int(lesson.get("day", -1))]
			classes[key] = int(classes.get(key, 0)) + lesson.student_refs.size()
			var supply = load("res://scripts/core/school_supply_service.gd")
			if int(classes[key]) > mini(supply.physical_capacity(school, contracts, "seats", int(lesson.get("day", -1))), supply.physical_capacity(school, contracts, "book_sets", int(lesson.get("day", -1)))): return Contract.fail("不同先生同日重复占用学舍席位或课书")
	var learners := {}
	var active_teachers := {}
	for order in contracts.values():
		if order.get("contract_kind") not in ["school_teaching", "school_enrollment"]: continue
		var school: Dictionary = assets.get(order.get("school_id"), {})
		if school.get("asset_kind") != "school" or not school.get("contract_refs", []).has(order.contract_id) or not characters.has(order.get("customer_id")) or not characters.has(order.get("supplier_id")) or not order.get("work_log") is Array or not Contract.amount(order.get("created_day")) or not Contract.amount(order.get("work_days")) or not order.get("blocked_reason") is String: return Contract.fail("教育合同缺少学舍、人物或实际工日")
		if int(order.created_day) > int(raw.get("current_day", 0)) or order.get("last_work_day") != (order.created_day if order.work_log.is_empty() else order.work_log[-1].get("day")): return Contract.fail("教育工日进度与最后实际到课日不符")
		if order.contract_kind == "school_teaching":
			if order.get("status") == "active":
				if active_teachers.has(order.supplier_id): return Contract.fail("同一先生存在重复未完师资合同")
				active_teachers[order.supplier_id] = true
			var offer := teacher_offer(school, order.supplier_id)
			if offer.is_empty() or order.get("offer") != offer or int(order.work_days) > int(offer.teaching_days) or order.get("status") != ("completed" if int(order.work_days) == int(offer.teaching_days) else "active"): return Contract.fail("师资合同与实际报价或授课量不符")
			if order.get("funding_account_id") != school.account_id: return Contract.fail("师资合同经费与学舍实际账户不符")
			var payment: Dictionary = raw.resource_journal.get(order.get("commission_receipt"), {})
			var receipt: Dictionary = raw.action_receipts.get(order.get("commission_receipt"), {})
			if payment.get("entry_kind") != "transfer" or payment.get("source_account_id") != school.account_id or payment.get("destination_account_id") != offer.payee_account_id or payment.get("amount") != offer.price or payment.get("reason_ref") != order.contract_id or payment.get("actor_id") != order.customer_id or payment.get("day") != order.created_day or not receipt.get("effect_refs", []).has(order.contract_id): return Contract.fail("师资缺少真实支付与聘请回执")
			for lesson in order.work_log:
				if not Contract.amount(lesson.get("teacher_skill")) or int(lesson.teacher_skill) < int(school.curriculum.assessment_threshold) or int(lesson.teacher_skill) > 100: return Contract.fail("授课缺少先生当时学力依据")
				if not lesson is Dictionary or not lesson.get("student_refs") is Array or lesson.student_refs.is_empty() or lesson.student_refs.size() > mini(int(offer.capacity), mini(int(school.seats), int(school.book_sets))): return Contract.fail("授课缺少实际学生或超过真实容量")
				var seen := {}
				for ref in lesson.student_refs:
					var student: Dictionary = contracts.get(ref, {})
					if seen.has(ref) or student.get("contract_kind") != "school_enrollment" or student.get("school_id") != school.asset_id or not student.get("work_log", []).any(func(day): return day.get("day") == lesson.get("day") and day.get("teaching_ref") == order.contract_id): return Contract.fail("授课学生与实际到课记录不符")
					seen[ref] = true
		else:
			var offer := student_offer(school, order.supplier_id)
			if learners.has(order.supplier_id) or offer.is_empty() or order.get("offer") != offer or not offer.willing or not offer.identity_eligible or order.get("curriculum") != school.curriculum: return Contract.fail("学生重复入学或缺少真实意愿与课程")
			learners[order.supplier_id] = true
			var receipt: Dictionary = raw.action_receipts.get(order.get("enrollment_receipt"), {})
			if receipt.get("day") != order.created_day or not receipt.get("effect_refs", []).has(order.contract_id): return Contract.fail("入学缺少实际登记回执")
			if int(order.work_days) > int(school.curriculum.required_lessons) or order.get("status") != ("completed" if int(order.work_days) == int(school.curriculum.required_lessons) else "studying") or order.get("learning_score") != mini(100, int(offer.initial_score) + int(order.work_days) * int(school.curriculum.score_per_lesson)): return Contract.fail("学习成果超过真实到课与课程")
			if order.get("assessment_eligible") != (order.status == "completed" and int(order.learning_score) >= int(school.curriculum.assessment_threshold)): return Contract.fail("应试资格没有实际学习依据")
			if characters[order.supplier_id].get("stats", {}).get("scholarship") != order.learning_score: return Contract.fail("人物学业与实际学习记录不一致")
			if order.status == "completed" and (order.work_log.is_empty() or order.get("completed_day") != order.work_log[-1].get("day")): return Contract.fail("结业缺少最后学习日")
			for day in order.work_log:
				if not day is Dictionary: return Contract.fail("学习日结构无效")
				var teacher: Dictionary = contracts.get(day.get("teaching_ref"), {})
				if teacher.get("contract_kind") != "school_teaching" or teacher.get("school_id") != school.asset_id or not teacher.get("work_log", []).any(func(lesson): return lesson.get("day") == day.get("day") and lesson.get("student_refs", []).has(order.contract_id)): return Contract.fail("学习日缺少同日先生授课依据")
	return {"ok": true}
