extends RefCounted

const Contract = preload("res://scripts/core/management_state_contract.gd")
const Transaction = preload("res://scripts/core/game_state_transaction.gd")
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Dispatcher = preload("res://scripts/core/game_action_dispatcher.gd")
const Segments = preload("res://scripts/core/management_plan_segments.gd")

func submit_plan(context, authorization: Dictionary, plan: Dictionary, execution_id: String) -> Dictionary:
	var input := {"authorization": authorization.duplicate(true), "plan": plan.duplicate(true), "execution_id": execution_id}
	return _transaction(context, "management_plan", input, func(working): return _submit(working, input))

func submit_npc_plan(context, bound_actor_id: String, plan: Dictionary, resource_limits: Array, execution_id: String) -> Dictionary:
	var input := {"execution_id": execution_id, "actor_id": bound_actor_id, "plan": plan.duplicate(true), "resource_limits": resource_limits.duplicate(true)}
	return _transaction(context, "management_plan", input, func(working): return apply_npc_plan(working, bound_actor_id, plan, resource_limits, execution_id))

static func apply_npc_plan(context, actor_id: String, proposal: Dictionary, resource_limits: Array, execution_id: String) -> Dictionary:
	var contract = load("res://scripts/core/npc_ai_state_contract.gd")
	if not context.state.character_states.has(actor_id) or execution_id.is_empty() or not contract.exact(proposal, ["name", "steps"]) or not proposal.steps is Array or proposal.steps.is_empty() or proposal.steps.size() > 8: return Contract.fail("自主计划缺少实际主体或超出步骤上限")
	var catalog = load("res://scripts/core/game_action_catalog.gd")
	var kinds: Array = []
	var targets: Array = []
	for step in proposal.steps:
		if not contract.exact(step, ["step_id", "action_kind", "parameters", "target_refs", "depends_on"]): return Contract.fail("自主计划不能指定其他经办人或写入权限")
		var valid: Dictionary = catalog.validate_selection({"action_kind": step.action_kind, "parameters": step.parameters, "target_refs": step.target_refs})
		if not valid.ok: return valid
		if not kinds.has(step.action_kind): kinds.append(step.action_kind)
		for target in step.target_refs:
			if not targets.has(target): targets.append(target)
	var auth := {"authorization_id": "npc-auth:" + execution_id, "principal_id": actor_id, "delegate_id": actor_id, "scope": {"action_kinds": kinds, "target_refs": targets, "allow_subdelegation": false}, "resource_limits": resource_limits.duplicate(true), "version": 1, "status": "active", "valid_until_day": null}
	var plan := {"task_id": "npc-task:" + execution_id, "name": proposal.name, "executor_id": actor_id, "steps": proposal.steps.duplicate(true)}
	return _submit(context, {"authorization": auth, "plan": plan, "execution_id": execution_id}, actor_id)

func submit_dialogue_plan(context, session_id: String) -> Dictionary:
	var pending: Dictionary = context.state.active_dialogue_sessions.get(session_id, {}).get("pending_entrustment", {})
	var proposal: Dictionary = pending.get("plan", {}).get("management_proposal", {})
	if not proposal.get("authority_terms") is Dictionary or not proposal.get("plan") is Dictionary: return Contract.fail("没有完整的已议定共同动作方案，请重新商定")
	var input := {"authorization": proposal.authority_terms.duplicate(true), "plan": proposal.plan.duplicate(true), "dialogue_session_id": session_id, "execution_id": "confirm:" + str(proposal.authority_terms.authorization_id)}
	return _transaction(context, "management_plan", input, func(working): return _submit(working, input))

static func _submit(context, input: Dictionary, trusted_npc_actor: String = "", accepted_agreement_id: String = "") -> Dictionary:
	var state = context.state
	var auth: Dictionary = input.authorization.duplicate(true)
	if auth.has("business_policy"): return Contract.fail("持续经营条款须通过产业授权入口签发")
	var plan: Dictionary = input.plan
	if auth.has("consent_source"): return Contract.fail("调用方不能自行签发受托人同意记录")
	var valid := validate_authorization(state, auth)
	if not valid.get("ok", false):
		return valid
	if (auth.principal_id != state.player_character_id and auth.principal_id != trusted_npc_actor) or (trusted_npc_actor != "" and (auth.principal_id != trusted_npc_actor or (auth.delegate_id != trusted_npc_actor and accepted_agreement_id == ""))) or state.action_authorizations.has(auth.authorization_id):
		return Contract.fail("只能提交本人新授权；重复授权不得重置预算")
	var consent := {}
	if accepted_agreement_id != "":
		var row: Dictionary = state.economic_contracts.get(accepted_agreement_id, {})
		if row.get("purpose") != "delegated_plan" or row.get("status") != "accepted" or row.get("participant_ids", []) != [auth.principal_id, auth.delegate_id] or not row.participant_ids.all(func(id): return row.accepted_versions.get(id) == row.terms_version) or row.terms.resource_limits != auth.resource_limits or row.terms.plan.steps != plan.steps: return Contract.fail("双方尚未接受这份具体委托及预算")
		consent = {"kind": "social_agreement", "agreement_id": accepted_agreement_id, "terms_version": row.terms_version, "accepted_day": state.current_day, "principal_id": auth.principal_id, "delegate_id": auth.delegate_id, "terms_hash": row.terms_hash}
	elif input.has("dialogue_session_id"):
		var session: Dictionary = state.active_dialogue_sessions.get(input.dialogue_session_id, {})
		var pending: Dictionary = session.get("pending_entrustment", {})
		var proposal: Dictionary = pending.get("plan", {}).get("management_proposal", {})
		if session.get("status") != "active" or session.get("npc_id") != auth.delegate_id or proposal.get("authority_terms") != auth or proposal.get("plan") != plan or pending.get("willingness", {}).get("willingness") != "accept": return Contract.fail("受托人尚未接受这份具体方案")
		var place := str(state.character_states[auth.principal_id].get("location_id", ""))
		if not preload("res://scripts/core/production_service.gd").present(state, auth.delegate_id, place) or not preload("res://scripts/core/production_service.gd").present(state, auth.principal_id, place) or int(state.character_states[auth.delegate_id].get("relationships", {}).get(auth.principal_id, 0)) < 0: return Contract.fail("受托人已离场或不愿按原约经办，请重新商议")
		consent = {"kind": "private_dialogue", "session_id": input.dialogue_session_id, "terms_version": pending.terms_version, "principal_id": auth.principal_id, "delegate_id": auth.delegate_id, "accepted_day": int(state.current_day), "agreement": proposal.duplicate(true), "agreement_hash": str(preload("res://scripts/core/canonical_json.gd").hash_value(proposal).get("hash", ""))}
	elif auth.delegate_id != auth.principal_id:
		var willing: Dictionary = preload("res://scripts/core/player_assistant_service.gd").eligible(state, context.scenario_data, auth.delegate_id)
		if not willing.get("ok", false):
			return Contract.fail("受托人尚未同意或无法经办：" + str(willing.get("error", "")))
	valid = validate_plan(state, auth, plan)
	if not valid.get("ok", false):
		return valid
	if _find_task(state, plan.task_id) != null:
		return Contract.fail("任务标识已存在")
	auth["reservation_refs"] = {}
	auth["delegate_ids"] = [auth.delegate_id]
	auth["root_task_id"] = plan.task_id
	if not consent.is_empty(): auth["consent_source"] = consent
	for limit in auth.resource_limits:
		var reserve_id := "authorization:%s:%s" % [auth.authorization_id, limit.account_id]
		var reserved := Accounts.new().apply(state, "reserve", {"execution_id": reserve_id, "account_id": limit.account_id, "amount": int(limit.amount), "actor_id": auth.principal_id, "task_id": plan.task_id})
		if not reserved.get("ok", false):
			return reserved
		auth.reservation_refs[limit.account_id] = reserve_id
	state.action_authorizations[auth.authorization_id] = auth
	var created := _task(auth, plan, state.current_day, "", [plan.executor_id])
	if consent.get("kind") == "social_agreement":
		created["source_type"] = "social_agreement"
		created["source_agreement_id"] = consent.agreement_id
		created["terms_version"] = consent.terms_version
		created.visible_feedback = ["已按双方同意的委托预留预算，等待实际经办。"]
	elif not consent.is_empty():
		created["source_type"] = "private_talk"
		created["source_session_id"] = consent.session_id
		created["terms_version"] = consent.terms_version
		created.visible_feedback = ["已按对话条款预留预算，等待经办。", str(consent.agreement.summary)]
	state.active_tasks.append(created)
	return {"ok": true, "result_ref": plan.task_id}

static func validate_authorization(state, auth: Dictionary) -> Dictionary:
	for field in ["authorization_id", "principal_id", "delegate_id"]:
		if not auth.get(field) is String or str(auth[field]).is_empty():
			return Contract.fail("授权缺少字段：" + field)
	if not state.character_states.has(auth.principal_id) or not state.character_states.has(auth.delegate_id):
		return Contract.fail("授权引用缺失人物")
	if not auth.get("scope") is Dictionary or not auth.scope.get("action_kinds") is Array or not auth.scope.get("target_refs") is Array or not auth.scope.get("allow_subdelegation") is bool:
		return Contract.fail("授权缺少动作、对象或转委托范围")
	if not Contract.amount(auth.get("version"), true) or auth.get("status") != "active" or not auth.has("valid_until_day") or (auth.valid_until_day != null and not Contract.amount(auth.valid_until_day)):
		return Contract.fail("授权版本、状态或期限无效")
	if not auth.get("resource_limits") is Array:
		return Contract.fail("授权缺少累计预算")
	var sources: Array = []
	for limit in auth.resource_limits:
		if not limit is Dictionary or not state.resource_accounts.has(limit.get("account_id")) or not Contract.amount(limit.get("amount"), true) or limit.get("unit_id") != "cash_unit":
			return Contract.fail("授权预算的来源、金额或单位无效")
		var account: Dictionary = state.resource_accounts[limit.account_id]
		if account.unit_id != limit.unit_id: return Contract.fail("授权预算单位与真实库存单位不一致")
		if not account.operator_refs.any(func(ref): return ref.get("entity_kind") == "character" and ref.get("entity_id") == auth.principal_id):
			return Contract.fail("委托人无权使用授权账户")
		if sources.has(account.storage_ref):
			return Contract.fail("同一存量的账户别名不能重复领取预算")
		sources.append(account.storage_ref)
	return {"ok": true}

static func validate_plan(state, auth: Dictionary, plan: Dictionary) -> Dictionary:
	if not plan.get("task_id") is String or str(plan.task_id).is_empty() or not plan.get("name") is String or not plan.get("steps") is Array or plan.steps.is_empty() or not state.character_states.has(plan.get("executor_id")):
		return Contract.fail("计划缺少任务、实际执行人或步骤")
	if plan.executor_id != auth.delegate_id and not auth.get("delegate_ids", []).has(plan.executor_id):
		return Contract.fail("执行人不在授权内")
	var ids: Array = []
	var future_shops := {}
	var future_buildings := {}
	var future_business_offices := {}
	var future_orders := {}
	var future_works := {}
	var future_school_supplies := {}
	var future_exam_journeys := {}
	var future_official_journeys := {}
	var future_marriages := {}
	var future_grain := {}
	var future_school_aid := {}
	var future_students := {}
	var future_teachers := {}
	var future_teacher_contracts := {}
	var future_searches := {}
	var ancestors := {}
	for step in plan.steps:
		if not step is Dictionary or not step.get("step_id") is String or str(step.step_id).is_empty() or ids.has(step.step_id) or not step.get("depends_on") is Array or not step.get("parameters") is Dictionary or not step.get("target_refs") is Array:
			return Contract.fail("步骤缺少字段或标识重复")
		for dependency in step.depends_on:
			if not ids.has(dependency):
				return Contract.fail("步骤依赖必须引用前面的已登记步骤，不能循环")
		var inherited: Array = step.depends_on.duplicate()
		for dependency in step.depends_on:
			for ancestor in ancestors.get(dependency, []):
				if not inherited.has(ancestor): inherited.append(ancestor)
		ancestors[step.step_id] = inherited
		ids.append(step.step_id)
		if not auth.scope.action_kinds.has(step.get("action_kind")):
			return Contract.fail("计划动作超出授权范围")
		for target in step.target_refs:
			if not auth.scope.target_refs.has(target):
				return Contract.fail("计划对象超出授权范围")
		var cost := Dispatcher.cost_for(state, str(step.action_kind), step.parameters, str(auth.principal_id))
		if step.action_kind=="hire_family" and future_business_offices.has(step.parameters.get("office_id")):
			var future: Dictionary = future_business_offices[step.parameters.office_id]
			if not inherited.has(future.step_id): return Contract.fail("聘任产业掌柜必须依赖实际产业与岗位设立")
			cost={"ok":true,"account_id":future.account_id,"amount":future.wage}
		if not cost.get("ok", false):
			var producer := str(future_shops.get(step.parameters.get("shop_id", ""), ""))
			var existing_delivery := false
			if step.action_kind in ["establish_owned_pawnshop","establish_owned_retail","establish_owned_manufacturing","establish_owned_farm","establish_owned_modeled"]:
				producer = str(future_buildings.get(step.parameters.get("building_id", ""), ""))
				existing_delivery = cost.get("code") == "awaiting_delivery"
			if step.action_kind == "receive_marriage_terms":
				var inquiry: Dictionary = future_marriages.get(step.parameters.get("proposal_id", ""), {})
				if inquiry.get("match_id") == step.parameters.get("match_id"): producer = str(inquiry.get("step_id", ""))
			if step.action_kind == "receive_official_report":
				var journey: Dictionary = future_official_journeys.get(step.parameters.get("journey_id", ""), {})
				if journey.get("person_id") == step.parameters.get("person_id") and journey.get("target_depot_id") == step.parameters.get("target_depot_id"): producer = str(journey.get("step_id", ""))
			if step.action_kind == "await_grain_report":
				var order: Dictionary = future_grain.get(step.parameters.get("order_id", ""), {})
				if order.get("source_depot_id") == step.parameters.get("source_depot_id") and order.get("target_depot_id") == step.parameters.get("target_depot_id"): producer = str(order.get("step_id", ""))
			if step.action_kind == "finish_public_work": producer = str(future_works.get(step.parameters.get("order_id", ""), ""))
			if step.action_kind == "receive_exam_arrival_report":
				var journey: Dictionary = future_exam_journeys.get(step.parameters.get("journey_id", ""), {})
				producer = str(journey.get("step_id", "")) if journey.get("school_id") == step.parameters.get("school_id") else ""
			if step.action_kind == "receive_school_supply":
				var supply: Dictionary = future_school_supplies.get(step.parameters.get("order_id", ""), {})
				producer = str(supply.get("step_id", "")) if supply.get("school_id") == step.parameters.get("school_id") else ""
			if step.action_kind == "collect_production": producer = str(future_orders.get(step.parameters.get("order_id", ""), ""))
			if step.action_kind == "finish_character_search": producer = str(future_searches.get(step.parameters.get("search_id", ""), ""))
			if not existing_delivery and (cost.get("code") != "asset_not_ready" or producer.is_empty() or not inherited.has(producer)):
				return cost
		if step.action_kind in ["start_construction","refit_estate"]:
			var building_id := "building:" + str(plan.task_id) + ":" + str(step.step_id)
			if future_buildings.has(building_id) or state.management_assets.has(building_id): return Contract.fail("筹建房屋标识重复")
			var land_id: String=str(step.parameters.get("land_id",""))
			if step.action_kind=="refit_estate":land_id=str(state.management_assets[state.management_assets[step.parameters.shop_id].building_id].land_id)
			var land: Dictionary = state.management_assets[land_id]
			if land.development_offers[step.parameters.blueprint_id].industry_kind in ["pawnshop","cloth_shop","smithy","grain_estate","tea_garden"] or land.development_offers[step.parameters.blueprint_id].has("operation_terms"): future_buildings[building_id] = step.step_id
		if step.action_kind in ["rent_shop", "establish_owned_pawnshop", "establish_owned_retail", "establish_owned_manufacturing","establish_owned_farm","establish_owned_modeled"]:
			var shop_id := str(step.parameters.get("shop_id", ""))
			if shop_id.is_empty() or future_shops.has(shop_id) or state.management_assets.has(shop_id):
				return Contract.fail("计划的经营标识缺失或重复")
			future_shops[shop_id] = step.step_id
			if step.parameters.has("office_template_id"):
				var drafted: Dictionary = load("res://scripts/core/business_manager_office.gd").draft(state,str(step.parameters.office_template_id),shop_id,str(step.parameters.get("funding_account_id","")),step.parameters.get("wage_amount"))
				if not drafted.ok: return drafted
				if drafted.office.office_id!=step.parameters.get("office_id") or future_business_offices.has(drafted.office.office_id): return Contract.fail("未来产业岗位标识错误或重复")
				future_business_offices[drafted.office.office_id]={"step_id":step.step_id,"account_id":drafted.office.remuneration_terms.account_id,"wage":int(drafted.office.remuneration_terms.amount)}
		if step.action_kind == "start_public_work":
			var work_id := str(step.parameters.get("order_id", ""))
			if work_id.is_empty() or future_works.has(work_id) or state.economic_contracts.has(work_id): return Contract.fail("公共工程合同标识缺失或重复")
			future_works[work_id] = step.step_id
		if step.action_kind == "send_exam_candidate":
			var journey_id := str(step.parameters.get("journey_id", ""))
			if future_exam_journeys.has(journey_id) or state.economic_contracts.has(journey_id): return Contract.fail("赴试行程标识重复")
			future_exam_journeys[journey_id] = {"step_id": step.step_id, "school_id": step.parameters.school_id}
		if step.action_kind == "inquire_marriage":
			var proposal_id := str(step.parameters.get("proposal_id", ""))
			if future_marriages.has(proposal_id) or state.economic_contracts.has(proposal_id): return Contract.fail("婚配探询标识重复")
			future_marriages[proposal_id] = {"step_id": step.step_id, "match_id": step.parameters.match_id}
		if step.action_kind == "send_official_envoy":
			var journey_id: String = str(step.parameters.get("journey_id", ""))
			if journey_id.is_empty() or future_official_journeys.has(journey_id) or state.economic_contracts.has(journey_id): return Contract.fail("实际差遣标识重复")
			future_official_journeys[journey_id] = {"step_id": step.step_id, "person_id": step.parameters.person_id, "target_depot_id": step.parameters.target_depot_id}
		if step.action_kind == "commission_grain_transport":
			var order_id: String = str(step.parameters.get("order_id", ""))
			if order_id.is_empty() or future_grain.has(order_id) or not preload("res://scripts/core/regional_grain_service.gd").find_order(state, order_id).is_empty(): return Contract.fail("同一计划不能复用已签发或前序调粮的标识")
			future_grain[order_id] = {"step_id": step.step_id, "source_depot_id": step.parameters.source_depot_id, "target_depot_id": step.parameters.target_depot_id}
		if step.action_kind == "enroll_school_student":
			future_students[str(step.parameters.get("school_id", "")) + ":" + str(step.parameters.get("student_id", ""))] = step.step_id
		if step.action_kind == "sponsor_school_student":
			var aid_id := str(step.parameters.get("aid_id", ""))
			var student_key := str(step.parameters.get("school_id", "")) + ":" + str(step.parameters.get("student_id", ""))
			if future_school_aid.has(aid_id) or state.economic_contracts.has(aid_id): return Contract.fail("生活资助不能复用已承诺或已交付的记录")
			var enrolled: bool = state.economic_contracts.values().any(func(row): return row.get("contract_kind") == "school_enrollment" and row.get("school_id") == step.parameters.school_id and row.get("supplier_id") == step.parameters.student_id and row.get("status") == "studying")
			if not enrolled and not inherited.has(future_students.get(student_key, "")): return Contract.fail("未来生活资助必须依赖该学生在对应学舍的实际入学步骤")
			future_school_aid[aid_id] = true
		if step.action_kind == "hire_school_teacher":
			var teacher_id := str(step.parameters.get("teacher_id", ""))
			var teaching_id := str(step.parameters.get("contract_id", ""))
			if future_teachers.has(teacher_id) or future_teacher_contracts.has(teaching_id) or state.economic_contracts.has(teaching_id): return Contract.fail("同一计划不能重复聘同一先生或复用师资合同标识")
			future_teachers[teacher_id] = true
			future_teacher_contracts[teaching_id] = true
		if step.action_kind == "commission_school_supply":
			var supply_id := str(step.parameters.get("order_id", ""))
			if supply_id.is_empty() or future_school_supplies.has(supply_id) or state.economic_contracts.has(supply_id): return Contract.fail("学舍供给合同标识缺失或重复")
			future_school_supplies[supply_id] = {"step_id": step.step_id, "school_id": step.parameters.school_id}
		if step.action_kind == "commission_production":
			var order_id := str(step.parameters.get("order_id", ""))
			if order_id.is_empty() or future_orders.has(order_id) or state.economic_contracts.has(order_id): return Contract.fail("生产订单标识缺失或重复")
			future_orders[order_id] = step.step_id
		if step.action_kind == "start_character_search":
			var search_id := str(step.parameters.get("search_id", ""))
			if search_id.is_empty() or future_searches.has(search_id) or state.economic_contracts.has(search_id): return Contract.fail("寻访标识缺失或重复")
			future_searches[search_id] = step.step_id
	return {"ok": true}

static func _task(auth: Dictionary, plan: Dictionary, day: int, parent: String, chain: Array) -> Dictionary:
	var steps: Array = plan.steps.duplicate(true)
	for step in steps:
		step["status"] = "planned"
		step["execution_id"] = "%s:%s" % [plan.task_id, step.step_id]
		step["receipt_ref"] = ""
	var task := {"id": plan.task_id, "task_id": plan.task_id, "task_kind": "management", "name": plan.name, "principal_id": auth.principal_id, "executor_id": plan.executor_id, "authorization_id": auth.authorization_id, "plan_revision": 1, "authorization_version": auth.version, "steps": steps, "status": "reserved", "created_day": day, "due_day": day + 1, "last_execution_day": -1, "parent_task_id": parent, "delegation_chain": chain, "visible_feedback": ["授权已登记，预算已预留。"]}
	Segments.refresh(task)
	return task

static func settle_task(state, data: Dictionary, task: Dictionary) -> Dictionary:
	if state.action_authorizations.get(task.get("authorization_id"),{}).has("business_policy"):
		return load("res://scripts/core/business_management_service.gd").settle(state,data,task)
	if task.status in ["completed", "cancelled", "blocked"] or int(state.current_day) < int(task.due_day) or int(task.last_execution_day) == int(state.current_day):
		return {"ok": true}
	var auth: Dictionary = state.action_authorizations.get(task.authorization_id, {})
	if auth.get("status") != "active" or auth.get("version") != task.authorization_version:
		return _block(task, "授权已撤回或条款已修改")
	var segments_valid := Segments.validate(task)
	if not segments_valid.ok: return segments_valid
	for index in range(Segments.start_index(task), task.steps.size()):
		var step: Dictionary = task.steps[index]
		if step.status == "completed":
			continue
		if step.status == "delegated":
			var child: Variant = _find_task(state, str(step.get("child_task_id", "")))
			if child == null or child.status != "completed":
				return {"ok": true}
			step.status = "completed"
			step.receipt_ref = "task:" + str(child.task_id)
			Segments.refresh(task)
			continue
		for dependency in step.depends_on:
			if not task.steps.any(func(other): return other.step_id == dependency and other.status == "completed"):
				return {"ok": true}
		if step.action_kind == "fulfill_social_agreement":
			step.execution_id = "%s:%s:day:%d" % [task.task_id, step.step_id, state.current_day]
			Segments.refresh(task)
		var request := {"execution_id": step.execution_id, "request_id": "task-request:" + step.execution_id, "actor_id": task.executor_id, "principal_id": task.principal_id, "executor_id": task.executor_id, "action_kind": step.action_kind, "target_refs": step.target_refs.duplicate(true), "parameters": step.parameters.duplicate(true), "expected_state_revision": int(state.state_revision), "task_id": task.task_id, "step_id": step.step_id, "authorization_id": task.authorization_id}
		var result := Dispatcher.apply(state, data, request)
		if not result.get("ok", false):
			if result.get("rollback_required", false): return result
			if result.get("code") in ["executor_busy_today", "awaiting_delivery"]:
				task.visible_feedback = [str(result.error)]
				return {"ok": true, "waiting": true}
			return _block(task, str(result.get("error", "办理受阻")))
		if result.get("receipt", {}).get("social_record", {}).get("outcome") == "blocked":
			task.last_execution_day = int(state.current_day)
			task.visible_feedback = [str(result.receipt.visible_summary)]
			return {"ok": true, "waiting": true}
		step.status = "completed"
		step.receipt_ref = result.result_ref
		Segments.refresh(task)
		task.last_execution_day = int(state.current_day)
		task.status = "running"
		task.visible_feedback = [str(result.receipt.visible_summary)]
		state.state_revision += 1
		break
	if task.steps.all(func(step): return step.status == "completed"):
		task.status = "completed"
		task["completed_day"] = int(state.current_day)
		var released := _release_if_finished(state, task.authorization_id)
		if not released.ok:
			released["rollback_required"] = true
			return released
	return {"ok": true}

func revise(context, authorization_id: String, scope: Dictionary, resource_limits: Array, valid_until_day: Variant, execution_id: String) -> Dictionary:
	var input := {"authorization_id": authorization_id, "scope": scope.duplicate(true), "resource_limits": resource_limits.duplicate(true), "valid_until_day": valid_until_day, "execution_id": execution_id, "operation": "revise"}
	return _transaction(context, "management_task_control", input, func(working):
		return _apply_revision(working.state, authorization_id, scope, resource_limits, valid_until_day, execution_id)
	)

static func _apply_revision(state, authorization_id: String, scope: Dictionary, resource_limits: Array, valid_until_day: Variant, execution_id: String, trusted_actor: String = "") -> Dictionary:
	var current: Dictionary = state.action_authorizations.get(authorization_id, {})
	if current.has("business_policy"): return Contract.fail("经营条款变更须撤回原授权后重新签发，不改写原有回执")
	var principal: String = state.player_character_id if trusted_actor.is_empty() else trusted_actor
	if current.get("principal_id") != principal or current.get("status") != "active":
		return Contract.fail("只能修改本人尚在进行的授权")
	var revised := current.duplicate(true)
	revised.scope = scope.duplicate(true)
	revised.resource_limits = resource_limits.duplicate(true)
	revised.valid_until_day = valid_until_day
	var valid := validate_authorization(state, revised)
	if not valid.get("ok", false): return valid
	for old in current.resource_limits:
		if not resource_limits.any(func(limit): return limit.account_id == old.account_id):
			return Contract.fail("既有资金来源须保留支出记录；可将限额降至已花金额")
	for limit in resource_limits:
		var reserve_id := str(current.reservation_refs.get(limit.account_id, ""))
		if reserve_id.is_empty():
			reserve_id = "authorization:%s:%s" % [authorization_id, limit.account_id]
			var reserved := Accounts.new().apply(state, "reserve", {"execution_id": reserve_id, "account_id": limit.account_id, "amount": limit.amount, "actor_id": current.principal_id, "task_id": current.root_task_id})
			if not reserved.get("ok", false): return reserved
			revised.reservation_refs[limit.account_id] = reserve_id
		else:
			var resized := Accounts.new().apply(state, "resize", {"execution_id": execution_id + ":" + limit.account_id, "account_id": limit.account_id, "amount": limit.amount, "actor_id": current.principal_id, "reservation_id": reserve_id})
			if not resized.get("ok", false): return resized
	revised.version += 1
	state.action_authorizations[authorization_id] = revised
	for task in state.active_tasks:
		if task.get("authorization_id") == authorization_id:
			task.authorization_version = revised.version
			if task.status == "blocked":
				task.status = "running"
				task.erase("block_reason")
	return {"ok": true, "result_ref": authorization_id}

static func prepare_revision(state, task_id: String, plan: Dictionary, trusted_actor: String = "") -> Dictionary:
	var task: Variant = _find_task(state, task_id)
	var principal: String = state.player_character_id if trusted_actor.is_empty() else trusted_actor
	if task == null or task.principal_id != principal or task.status in ["completed", "cancelled"] or task.get("parent_task_id", "") != "":
		return Contract.fail("只能修改本人尚在办理的根任务")
	if plan.get("executor_id") != task.executor_id or plan.get("task_id") != task_id or not plan.get("name") is String or str(plan.name).is_empty() or not plan.get("steps") is Array or plan.steps.is_empty():
		return Contract.fail("修改计划不得暗中更换任务或执行人")
	var merged: Array = []
	var frozen: Array = []
	var ids: Array = []
	for old in task.steps:
		if old.status in ["completed", "delegated"]:
			frozen.append(old.step_id)
			var found: Array = plan.steps.filter(func(s): return s.get("step_id") == old.step_id)
			if found.size() != 1: return Contract.fail("不能删除已办理或已转委托的步骤")
			for key in ["action_kind", "target_refs", "parameters", "depends_on"]:
				if found[0].get(key) != old.get(key): return Contract.fail("不能改写已办理或已转委托的步骤")
	var scope: Dictionary = state.action_authorizations[task.authorization_id].scope.duplicate(true)
	for step in plan.steps:
		if not step is Dictionary or not step.get("step_id") is String or ids.has(step.step_id) or not step.get("depends_on") is Array:
			return Contract.fail("修改步骤缺少标识、依赖或标识重复")
		for dependency in step.depends_on:
			if not ids.has(dependency): return Contract.fail("修改步骤依赖循环或不在前序")
		ids.append(step.step_id)
		var old: Array = task.steps.filter(func(s): return s.step_id == step.step_id)
		if frozen.has(step.step_id):
			merged.append(old[0].duplicate(true))
		else:
			var next: Dictionary = step.duplicate(true)
			next.merge({"status": "planned", "execution_id": "%s:%s" % [task_id, step.step_id], "receipt_ref": ""}, true)
			merged.append(next)
		if not scope.action_kinds.has(step.get("action_kind")): scope.action_kinds.append(step.get("action_kind"))
		for target in step.get("target_refs", []):
			if not scope.target_refs.has(target): scope.target_refs.append(target)
	var remaining := plan.duplicate(true)
	remaining.steps = plan.steps.filter(func(s): return not frozen.has(s.step_id)).duplicate(true)
	for step in remaining.steps:
		step.depends_on = step.depends_on.filter(func(id): return not frozen.has(id))
	var auth: Dictionary = state.action_authorizations[task.authorization_id].duplicate(true)
	auth.scope = scope
	if not remaining.steps.is_empty():
		var valid := validate_plan(state, auth, remaining)
		if not valid.ok: return valid
	return {"ok": true, "merged_steps": merged, "frozen_ids": frozen, "remaining_plan": remaining, "scope": scope}

func replace_plan(context, task_id: String, plan: Dictionary, limits: Array, execution_id: String) -> Dictionary:
	return _transaction(context, "management_task_control", {"task_id": task_id, "plan": plan, "resource_limits": limits, "execution_id": execution_id, "operation": "replace_plan"}, func(working):
		return _replace_plan(working, task_id, plan, limits, execution_id)
	)

static func _replace_plan(context, task_id: String, plan: Dictionary, limits: Array, execution_id: String, trusted_actor: String = "") -> Dictionary:
	var prepared := prepare_revision(context.state, task_id, plan, trusted_actor)
	if not prepared.ok: return prepared
	var task: Dictionary = _find_task(context.state, task_id)
	var auth: Dictionary = context.state.action_authorizations[task.authorization_id]
	var changed := _apply_revision(context.state, auth.authorization_id, prepared.scope, limits, auth.valid_until_day, execution_id, trusted_actor)
	if not changed.ok: return changed
	task.steps = prepared.merged_steps
	task.name = plan.name
	task.plan_revision += 1
	Segments.refresh(task)
	task.visible_feedback.append("已保留办妥事项，后续步骤与累计预算按新授权办理。")
	return {"ok": true, "result_ref": task_id}

static func apply_npc_revision(context, actor: String, proposal: Dictionary, limits: Array, execution_id: String) -> Dictionary:
	var state = context.state
	var task: Variant = _find_task(state, proposal.get("task_id", ""))
	if actor == state.player_character_id or task == null or task.get("principal_id") != actor or task.get("executor_id") != actor or task.get("source_agreement_id", "") != "": return Contract.fail("自主修订只能调整本人经办的原计划；他人委托须重新取得同意")
	var auth: Dictionary = state.action_authorizations.get(task.authorization_id, {})
	if auth.get("principal_id") != actor or auth.get("delegate_id") != actor or auth.has("business_policy"): return Contract.fail("原计划不属于本人的自主授权")
	var plan := {"task_id": task.task_id, "executor_id": task.executor_id, "name": proposal.name, "steps": proposal.steps.duplicate(true)}
	return _replace_plan(context, task.task_id, plan, limits, execution_id, actor)

func cancel(context, task_id: String, execution_id: String) -> Dictionary:
	return _transaction(context, "management_task_control", {"task_id": task_id, "execution_id": execution_id, "operation": "cancel"}, func(working): return cancel_actor_plan(working.state, task_id, working.state.player_character_id))

static func cancel_actor_plan(state, task_id: String, actor: String) -> Dictionary:
	var task: Variant = _find_task(state, task_id)
	if task == null or not preload("res://scripts/core/clan_succession_service.gd").controls_task(state, task, actor): return Contract.fail("未找到本人有权撤回的任务")
	if task.status in ["completed", "cancelled"]: return {"ok": true, "code": "no_op", "result_ref": task_id}
	var auth: Dictionary = state.action_authorizations[task.authorization_id]
	auth.status = "revoked"
	auth.version += 1
	for pending in state.active_tasks.duplicate():
		if pending.get("authorization_id") == auth.authorization_id:
			pending.status = "cancelled"
			pending["completed_day"] = int(state.current_day)
			state.completed_tasks.append(pending.duplicate(true))
			state.active_tasks.erase(pending)
	var released := _release_if_finished(state, auth.authorization_id)
	if not released.ok: return released
	return {"ok": true, "result_ref": task_id}

func retry(context, task_id: String, execution_id: String) -> Dictionary:
	return _transaction(context, "management_task_control", {"task_id":task_id,"execution_id":execution_id,"operation":"retry"}, func(working):
		var task: Variant = _find_task(working.state,task_id)
		if task == null or not preload("res://scripts/core/clan_succession_service.gd").controls_task(working.state,task,working.state.player_character_id): return Contract.fail("无权恢复这项委托")
		var retried := retry_task(working.state,task)
		if not retried.ok: return retried
		return {"ok":true,"result_ref":task_id}
	)

func delegate(context, task_id: String, step_id: String, executor_id: String, execution_id: String) -> Dictionary:
	return _transaction(context, "management_task_control", {"task_id": task_id, "step_id": step_id, "executor_id": executor_id, "execution_id": execution_id, "operation": "delegate"}, func(working):
		var state = working.state
		var parent: Variant = _find_task(state, task_id)
		if parent == null or parent.get("principal_id") != state.player_character_id or parent.status in ["completed", "cancelled"]:
			return Contract.fail("未找到可转委托的本人任务")
		var auth: Dictionary = state.action_authorizations[parent.authorization_id]
		if auth.status != "active" or not auth.scope.allow_subdelegation or parent.delegation_chain.has(executor_id):
			return Contract.fail("未授权转委托或构成循环委托")
		if not state.character_states.has(executor_id) or state.character_states[executor_id].get("status") in ["dead", "executed", "departed", "exiled"]:
			return Contract.fail("接手人不存在或无法履职")
		var willing: Dictionary = preload("res://scripts/core/player_assistant_service.gd").eligible(state, working.scenario_data, executor_id)
		if not willing.get("ok", false):
			return willing
		var chosen: Dictionary = {}
		for step in parent.steps:
			if step.step_id == step_id and step.status == "planned":
				chosen = step
		if chosen.is_empty():
			return Contract.fail("该步骤已办理或已转交，不能重复委托")
		for dependency in chosen.depends_on:
			if not parent.steps.any(func(step): return step.step_id == dependency and step.status == "completed"):
				return Contract.fail("前置事项尚未完成，暂不能交接该步骤")
		var child_id := task_id + "/" + step_id
		var child_step: Dictionary = chosen.duplicate(true)
		child_step.depends_on = []
		var child_plan := {"task_id": child_id, "name": parent.name + "·转交", "executor_id": executor_id, "steps": [child_step]}
		if not auth.delegate_ids.has(executor_id):
			auth.delegate_ids.append(executor_id)
		var chain: Array = parent.delegation_chain.duplicate()
		chain.append(executor_id)
		state.active_tasks.append(_task(auth, child_plan, state.current_day, task_id, chain))
		chosen.status = "delegated"
		chosen["child_task_id"] = child_id
		return {"ok": true, "result_ref": child_id}
	)

static func retry_task(state, task: Dictionary) -> Dictionary:
	if task.status != "blocked":
		return Contract.fail("任务当前不需重试")
	var auth: Dictionary = state.action_authorizations.get(task.authorization_id, {})
	if auth.get("status") != "active" or auth.get("version") != task.authorization_version:
		return Contract.fail("请先调整或恢复授权")
	task.status = "running"
	task.erase("block_reason")
	return {"ok": true}

static func _block(task: Dictionary, reason: String) -> Dictionary:
	task.status = "blocked"
	task["block_reason"] = reason
	task.visible_feedback = [reason]
	return {"ok": true, "blocked": true, "reason": reason}

static func _find_task(state, id: String) -> Variant:
	for task in state.active_tasks + state.completed_tasks:
		if task.get("task_kind") == "management" and task.get("task_id") == id:
			return task
	return null

static func _release_if_finished(state, authorization_id: String) -> Dictionary:
	if state.active_tasks.any(func(task): return task.get("authorization_id") == authorization_id and task.get("status") not in ["completed", "cancelled"]):
		return {"ok": true}
	var auth: Dictionary = state.action_authorizations[authorization_id]
	var estate: Dictionary = load("res://scripts/core/estate_production_continuation.gd").estate_for(state, auth.root_task_id)
	var actor: String = preload("res://scripts/core/clan_succession_service.gd").effective_principal(state, auth) if estate.is_empty() else auth.delegate_id
	for reserve_id in auth.reservation_refs.values():
		var released := Accounts.new().apply(state, "release", {"actor_id": actor, "reservation_id": reserve_id, "estate_task_id": auth.root_task_id if not estate.is_empty() else ""})
		if not released.ok: return released
	if auth.status == "active":
		auth.status = "completed"
	return {"ok": true}

static func _transaction(context, kind: String, input: Dictionary, operation: Callable) -> Dictionary:
	if context == null or context.state == null or str(input.get("execution_id", "")).is_empty():
		return Contract.fail("操作缺少上下文或稳定执行标识")
	var transaction = Transaction.new()
	var command_input := input
	if JSON.stringify(input).length() > Transaction.MAX_COMMAND_PAYLOAD_LENGTH:
		var fingerprint := preload("res://scripts/core/canonical_json.gd").hash_value(input)
		if not fingerprint.get("ok", false): return Contract.fail("完整计划无法规范校验，未采用")
		command_input = {"execution_id": input.execution_id, "complete_input_hash": fingerprint.hash}
	var preview := transaction.preview_command(context.state, kind, command_input)
	if not preview.get("ok", false):
		return preview
	return transaction.execute_command(context, transaction.build_command_envelope(kind, command_input, preview.preview_token), operation)
