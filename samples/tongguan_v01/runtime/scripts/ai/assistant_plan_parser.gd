extends RefCounted

const Contract = preload("res://scripts/core/management_state_contract.gd")
const Authorization = preload("res://scripts/core/action_authorization_service.gd")
const Dispatcher = preload("res://scripts/core/game_action_dispatcher.gd")
const Family = preload("res://scripts/core/family_office_rules.gd")
const PARAMETERS = preload("res://scripts/core/game_action_catalog.gd").PARAMETERS
const TOP_FIELDS := ["schema_version", "kind", "message", "basis", "risks", "task_id", "plan", "resource_limits"]

func parse(value: Variant) -> Dictionary:
	var shape := _exact(value, TOP_FIELDS, "response")
	if not shape.ok:
		return shape
	if value.schema_version != 1 or value.kind not in ["advice", "clarification", "proposal", "revise", "cancel"]:
		return _fail("response.kind/schema_version", "未知助手协议或回应种类")
	if not _text(value.message, 4096) or not _text(value.task_id, 256, true) or not _strings(value.basis) or not _strings(value.risks):
		return _fail("response", "说明、依据、风险或任务引用无效")
	if not value.plan is Dictionary or not value.resource_limits is Array:
		return _fail("response.plan/resource_limits", "计划和预算类型无效")
	if value.kind in ["advice", "clarification", "cancel"]:
		if not value.plan.is_empty() or not value.resource_limits.is_empty():
			return _fail("response.plan", "咨询或取消不能夹带新的执行步骤")
	else:
		shape = _exact(value.plan, ["name", "steps"], "plan")
		if not shape.ok:
			return shape
		if not _text(value.plan.name, 256) or not value.plan.steps is Array or value.plan.steps.is_empty():
			return _fail("plan", "需要名称和实际步骤")
		for index in value.plan.steps.size():
			var step: Variant = value.plan.steps[index]
			var path := "plan.steps[%d]" % index
			shape = _exact(step, ["step_id", "action_kind", "target_refs", "parameters", "depends_on"], path)
			if not shape.ok:
				return shape
			if not _text(step.step_id, 128) or not PARAMETERS.has(step.action_kind) or not _strings(step.target_refs) or step.target_refs.is_empty() or not _strings(step.depends_on):
				return _fail(path, "动作、步骤或引用无效")
			shape = _exact(step.parameters, PARAMETERS[step.action_kind], path + ".parameters")
			if not shape.ok:
				return shape
			for key in step.parameters:
				if key == "equipped":
					if not step.parameters[key] is bool: return _fail(path + ".parameters.equipped", "佩带状态必须是布尔值")
				elif key == "candidate_ids":
					if not _strings(step.parameters[key]) or step.parameters[key].is_empty(): return _fail(path + ".parameters.candidate_ids", "需要明确且非空的候选范围")
				elif key in ["amount", "duration_days", "grain_amount", "offered_gift", "wage_amount", "period_days"]:
					if not Contract.amount(step.parameters[key], true):
						return _fail(path + ".parameters." + key, "金额或工日必须为正整数")
				elif not _text(step.parameters[key], 256, key == "specialty"):
					return _fail(path + ".parameters." + key, "需要实际对象标识")
			var targets: Array = []
			for target in step.target_refs:
				if targets.has(target) or (not step.parameters.values().has(target) and not step.parameters.get("candidate_ids", []).has(target)):
					return _fail(path + ".target_refs", "目标必须是该动作参数中的实际对象，且不能重复")
				targets.append(target)
	for index in value.resource_limits.size():
		var limit: Variant = value.resource_limits[index]
		shape = _exact(limit, ["account_id", "amount", "unit_id"], "resource_limits[%d]" % index)
		if not shape.ok:
			return shape
		if not _text(limit.account_id, 256) or not Contract.amount(limit.amount, true) or limit.unit_id != "cash_unit":
			return _fail("resource_limits[%d]" % index, "无效的账户、金额或单位")
	if (value.kind in ["cancel", "revise"]) != (value.task_id != ""):
		return _fail("task_id", "修改或取消必须引用现有任务；新建议不得冒用旧任务")
	# Wire size is bounded in parse_transport. A locally assembled, fully
	# validated plan may exceed one response without losing any steps.
	var normalized: Dictionary = value.duplicate(true)
	normalized.schema_version = 1
	for limit in normalized.resource_limits:
		limit.amount = int(limit.amount)
	for step in normalized.plan.get("steps", []):
		if step.parameters.has("amount"):
			step.parameters.amount = int(step.parameters.amount)
		if step.parameters.has("duration_days"):
			step.parameters.duration_days = int(step.parameters.duration_days)
	return {"ok": true, "dto": normalized}

# Dedicated structured transport. This deliberately never calls dialogue display extraction.
func parse_transport(payload: Dictionary) -> Dictionary:
	var envelope := payload
	if payload.get("data") is Dictionary:
		envelope = payload.data
		if envelope.get("result") is Dictionary: envelope = envelope.result
	elif payload.get("result") is Dictionary:
		envelope = payload.result
	if not envelope.get("choices") is Array or envelope.choices.size() != 1 or not envelope.choices[0] is Dictionary:
		return _fail("transport.choices", "需要唯一结构化助手回复")
	var choice: Dictionary = envelope.choices[0]
	if choice.get("finish_reason", "stop") in ["length", "content_filter"]:
		return _fail("transport.finish_reason", "回复未完整生成，未采用动作")
	var message: Variant = choice.get("message")
	if not message is Dictionary:
		return _fail("transport.message", "缺少结构化消息")
	var content: Variant = message.get("content", "")
	if message.has("tool_calls"):
		var calls: Variant = message.tool_calls
		if not calls is Array or calls.size() != 1 or not calls[0] is Dictionary or not calls[0].get("function") is Dictionary or calls[0].function.get("name") != "submit_assistant_plan" or (content != null and content != ""):
			return _fail("transport.tool_calls", "工具回复必须唯一且使用助手协议")
		content = calls[0].function.get("arguments")
	if not content is String or content.length() > 65536:
		return _fail("transport.content", "需要有长度上限的 JSON 对象文本")
	var json := JSON.new()
	if json.parse(content) != OK:
		return _fail("transport.content", "JSON 无效，第 %d 行；未采用动作" % json.get_error_line())
	if json.data is Dictionary and json.data.get("schema_version") == 2:
		if json.data.get("kind") == "context_request": return load("res://scripts/core/assistant_context_pages.gd").parse_request(json.data)
		return load("res://scripts/core/assistant_plan_assembly.gd").parse_part(json.data)
	return parse(json.data)

func compile(context, raw: Variant, execution_id: String, instruction: String = "", instruction_day: int = -1) -> Dictionary:
	var parsed := parse(raw)
	if not parsed.ok:
		return parsed
	var dto: Dictionary = parsed.dto
	if context == null or context.state == null or execution_id.is_empty():
		return _fail("context", "缺少本局或执行标识")
	var state = context.state
	var player := str(state.player_character_id)
	var org := str(state.flags.get("player_organization_id", ""))
	var prior_task := {}
	if dto.kind in ["cancel", "revise"]:
		var tasks: Array = state.active_tasks.filter(func(t): return t.get("task_kind") == "management" and (t.get("principal_id") == player or (dto.kind == "cancel" and preload("res://scripts/core/clan_succession_service.gd").controls_task(state, t, player))) and t.get("task_id") == dto.task_id)
		if tasks.size() != 1:
			return _fail("task_id", "没有本人可调整的在办任务")
		prior_task = tasks[0]
	var executor := str(state.player_assistant_assignment.get("assistant_id", ""))
	if dto.kind == "revise": executor = str(prior_task.executor_id)
	if state.player_assistant_assignment.get("status") != "active":
		return _fail("assistant", "当前助手无法经办")
	var projected: Dictionary = state.to_dictionary().duplicate(true)
	var kinds: Array = []
	var targets: Array = []
	var required := {}
	var known: Array = [player, executor]
	var official = preload("res://scripts/core/official_office_actions.gd")
	for office in official.project(state, context.scenario_data, player):
		known.append(office.office_id)
		known.append_array(office.aliases)
		if office.holder_id != "": known.append(office.holder_id)
		for candidate in office.candidates: known.append(candidate.character_id)
	for person in preload("res://scripts/core/managed_item_service.gd").local_people(state, str(state.character_states[player].get("location_id", ""))):
		known.append(person.character_id)
	for account in state.resource_accounts.values():
		if account.operator_refs.any(func(r): return r.entity_id == player):
			known.append(account.account_id)
	for office in state.office_state.values():
		if Family.authority(state, str(office.office_id), player):
			known.append(office.office_id)
			for character in context.scenario_data.characters:
				if state.character_states.get(character.id, {}).get("location_id") == state.character_states[player].get("location_id") and character.get("employment_preferences", {}).get("roles", []).has(office.get("role_key")):
					known.append(character.id)
	for asset in state.management_assets.values():
		if asset.owner_ref.entity_id == org or asset.owner_ref.entity_id == player or (asset.location_id == state.character_states[player].get("location_id") and (asset.has("rental_offer") or asset.has("pledge_offer") or asset.get("offer_visibility") == "public")):
			known.append(asset.asset_id)
	for canal in preload("res://scripts/core/public_works_service.gd").project(state, player):
		known.append(canal.asset_id)
		if canal.active_contract_id != "": known.append(canal.active_contract_id)
	for initiative in preload("res://scripts/core/official_initiative_service.gd").project(state, player): known.append(initiative.initiative_id)
	for match_row in preload("res://scripts/core/marriage_service.gd").project(state, player):
		known.append(match_row.match_id)
		for proposal in match_row.proposals: known.append(proposal.proposal_id)
	var local_fiscal: Dictionary = preload("res://scripts/core/local_fiscal_policy_service.gd").project(state, player)
	if local_fiscal.office_id != "": known.append(local_fiscal.office_id)
	for levy in local_fiscal.levies:
		known.append(levy.levy_id)
		for person in levy.people: known.append(person.person_id)
	for depot in preload("res://scripts/core/regional_grain_service.gd").known_depots(state, player): known.append(depot.depot_id)
	for person in preload("res://scripts/core/official_journey_service.gd").project(state, player).candidates: known.append(person.person_id)
	for field in preload("res://scripts/core/farmland_service.gd").project(state, player):
		known.append_array(field.source_refs)
	for case in preload("res://scripts/core/regional_fiscal_service.gd").project(state, player):
		known.append_array(case.source_refs)
	for school in preload("res://scripts/core/education_service.gd").project(state, player):
		known.append(school.asset_id)
		for exam in school.assessments: known.append(exam.contract_id)
		for supply in school.supplies: known.append(supply.contract_id)
		for aid in school.living_aid_awards: known.append(aid.contract_id)
		for journey in school.exam_journeys: known.append(journey.contract_id)
		for teacher in school.teacher_offers: known.append(teacher.teacher_id)
		for student in school.student_offers: known.append(student.character_id)
	for order in state.economic_contracts.values():
		if order.get("contract_kind") == "production" and order.get("customer_id") == player: known.append(order.contract_id)
		if order.get("contract_kind") == "character_search" and order.get("principal_id") == player: known.append(order.contract_id)
	for task in state.active_tasks + state.completed_tasks:
		if task.get("task_kind") == "management" and preload("res://scripts/core/clan_succession_service.gd").controls_task(state, task, player):
			known.append(task.task_id)
	for basis in dto.basis:
		if not known.has(basis):
			return _fail("basis", "依据不是本人可知的实际对象：" + str(basis))
	if dto.kind not in ["proposal", "revise"]:
		return parsed
	var revision := {}
	if dto.kind == "revise":
		revision = Authorization.prepare_revision(state, dto.task_id, {"task_id": dto.task_id, "name": dto.plan.name, "steps": dto.plan.steps, "executor_id": executor})
		if not revision.ok: return _fail("plan", revision.error)
		var old_auth: Dictionary = state.action_authorizations[prior_task.authorization_id]
		for account in old_auth.reservation_refs:
			var reservation: Dictionary = state.resource_reservations[old_auth.reservation_refs[account]]
			required[account] = int(reservation.amount) - int(reservation.remaining_amount)
	for index in dto.plan.steps.size():
		var step: Dictionary = dto.plan.steps[index]
		if revision.get("frozen_ids", []).has(step.step_id): continue
		var params: Dictionary = step.parameters
		var path := "plan.steps[%d]" % index
		if step.action_kind == "hire_family_from_pool":
			for id in params.candidate_ids:
				if not known.has(id): return _fail(path, "备选人物不在本人已知范围")
		if step.action_kind == "decline_official_initiative" and not preload("res://scripts/core/official_initiative_service.gd").project(state, player).any(func(row): return row.initiative_id == params.initiative_id and row.head_office_id == params.office_id and row.status == "pending"): return _fail(path, "没有当前管辖内已收到的幕僚请求")
		if step.action_kind in ["issue_local_levy", "remit_local_levy"]:
			if params.office_id != local_fiscal.office_id: return _fail(path, "地方征收不在实际已知管辖内")
			if step.action_kind == "issue_local_levy" and (not local_fiscal.can_issue or not str(params.levy_id).begins_with("levy:" + player + ":")): return _fail(path, "本期征收不可重复或冒用他人标识")
			if step.action_kind == "remit_local_levy" and not local_fiscal.levies.any(func(row): return row.levy_id == params.levy_id and row.people.any(func(person): return person.person_id == params.person_id and person.can_remit)): return _fail(path, "没有已收到的本人减免请求")
		if step.action_kind in preload("res://scripts/core/marriage_service.gd").KINDS:
			if not known.has(params.match_id): return _fail(path, "婚配双方不在实际可知且有权经办的范围")
			if step.action_kind == "inquire_marriage":
				if not str(params.proposal_id).begins_with("marriage:" + player + ":") or projected.economic_contracts.has(params.proposal_id): return _fail(path, "探询须使用本人未用标识")
			elif step.action_kind == "receive_marriage_terms":
				if projected.economic_contracts.get(params.proposal_id, {}).get("principal_id") != player: return _fail(path, "没有本人实际或前序获准探询")
			elif not known.has(params.proposal_id) or state.economic_contracts.get(params.proposal_id, {}).get("status") not in ["offered", "committed"]: return _fail(path, "完整安排须先收到实际条件并另行授权")
		if step.action_kind == "send_official_envoy":
			if not str(params.journey_id).begins_with("envoy:" + player + ":") or projected.economic_contracts.has(params.journey_id) or not known.has(params.person_id) or not known.has(params.target_depot_id) or not preload("res://scripts/core/regional_grain_service.gd").authority(state, params.target_depot_id, player): return _fail(path, "差遣人物、标识或目标不在本人实际已知权源内")
		if step.action_kind == "receive_official_report" and projected.economic_contracts.get(params.journey_id, {}).get("customer_id") != player: return _fail(path, "没有本人签发或前序获准的差遣")
		if step.action_kind == "commission_grain_transport":
			if not str(params.order_id).begins_with("grain:" + player + ":") or not preload("res://scripts/core/regional_grain_service.gd").find_order(projected, params.order_id).is_empty(): return _fail(path, "调粮须引用本人未用过的调令标识")
			for depot_id in [params.source_depot_id, params.target_depot_id]:
				if not known.has(depot_id) or not preload("res://scripts/core/regional_grain_service.gd").authority(state, depot_id, player): return _fail(path, "调粮仓廪不在实际已知权源内")
		if step.action_kind == "await_grain_report" and preload("res://scripts/core/regional_grain_service.gd").find_order(projected, params.order_id).get("principal_id") != player: return _fail(path, "没有本人已签发或前序获准的调粮")
		if step.action_kind in ["open_school_assessment", "register_school_candidate", "commission_school_supply", "receive_school_supply", "receive_exam_arrival_report"]:
			if not known.has(params.school_id) or not preload("res://scripts/core/education_service.gd").authority(state, state.management_assets.get(params.school_id, {}), player): return _fail(path, "考核学舍不在实际已知经办范围")
			if step.action_kind == "register_school_candidate" and not known.has(params.student_id): return _fail(path, "报考人物不在实际已知范围")
		if step.action_kind in ["hire_school_teacher", "enroll_school_student", "sponsor_school_student", "send_exam_candidate"]:
			if not known.has(params.school_id) or not known.has(params.get("teacher_id", params.get("student_id", ""))) or not preload("res://scripts/core/education_service.gd").authority(state, state.management_assets.get(params.school_id, {}), player): return _fail(path, "学舍或教育人物不在实际已知经办范围")
		if step.action_kind == "repay_public_cash" and (not known.has(params.case_id) or state.economic_contracts.get(params.case_id, {}).get("responsible_id") != player): return _fail(path, "没有本人可知的公款归还责任")
		if step.action_kind == "start_character_search":
			if params.location_id != state.character_states[player].get("location_id"): return _fail(path, "当地寻访只能在本人当前已知地点安排")
			if not str(params.search_id).begins_with("search:" + player + ":") or projected.economic_contracts.has(params.search_id): return _fail(path, "寻访须使用本人未用过的标识")
		elif step.action_kind == "finish_character_search" and projected.economic_contracts.get(params.search_id, {}).get("principal_id") != player:
			return _fail(path, "没有本人已存在或前序委托的寻访")
		if step.action_kind == "start_public_work":
			if not known.has(params.canal_id) or not preload("res://scripts/core/public_works_service.gd").authority(state, state.management_assets.get(params.canal_id, {}), player): return _fail(path, "没有该公共渠道的经办权")
			if not str(params.order_id).begins_with("public-work:" + player + ":") or projected.economic_contracts.has(params.order_id): return _fail(path, "工程须使用本人未用过的合同标识")
		elif step.action_kind == "finish_public_work":
			var canal_id: String = projected.economic_contracts.get(params.order_id, {}).get("canal_id", "")
			if not known.has(canal_id): return _fail(path, "没有已知渠道的在办工程")
		if step.action_kind == "commission_production":
			if not known.has(params.workshop_id) or state.management_assets.get(params.workshop_id, {}).get("asset_kind") != "workshop": return _fail(path, "没有可见的实际工坊")
			if not str(params.order_id).begins_with("production:" + player + ":") or projected.economic_contracts.has(params.order_id): return _fail(path, "生产订单须使用本人未用过的标识")
		elif step.action_kind == "collect_production" and projected.economic_contracts.get(params.order_id, {}).get("customer_id") != player:
			return _fail(path, "没有本人已存在或前序委托的生产订单")
		if params.has("item_id"):
			if not known.has(params.item_id) or state.management_assets.get(params.item_id, {}).get("owner_ref") != {"entity_kind": "character", "entity_id": player}:
				return _fail(path + ".parameters.item_id", "没有该实物的处分权")
		if params.has("recipient_id") and not known.has(params.recipient_id):
			return _fail(path + ".parameters.recipient_id", "没有受赠人的可见依据")
		var official_action: bool = step.action_kind in official.KINDS
		if official_action and (not known.has(params.office_id) or not preload("res://scripts/core/office_service.gd").new().validate_actor_authority(state, params.office_id, player).get("ok", false)):
			return _fail(path + ".parameters.office_id", "没有该正式职位的任免权源")
		if params.has("office_id") and not official_action and step.action_kind not in ["issue_local_levy", "remit_local_levy", "decline_official_initiative"] and not Family.authority(state, params.office_id, player):
			return _fail(path + ".parameters.office_id", "没有该职位权源")
		if params.has("candidate_id"):
			if not known.has(params.candidate_id):
				return _fail(path + ".parameters.candidate_id", "没有该候选人的可见求职依据")
			if official_action:
				var assessed: Dictionary = preload("res://scripts/core/office_service.gd").new().assess_appointment_candidate(state, context.scenario_data, params.office_id, params.candidate_id, params.mode)
				if not assessed.get("appointment_available", false): return _fail(path, "候选不符合此项正式任命资格")
			else:
				var willing := Family.assess(projected, context.scenario_data, params.office_id, params.candidate_id)
				if willing.get("grade") != "eligible": return _fail(path + ".parameters.candidate_id", str(willing.get("reason", "人物不可用")))
		if official_action and params.has("holder_id") and projected.office_state.get(params.office_id, {}).get("holder_id") != params.holder_id:
			return _fail(path, "免职对象不是该职位当前或前序任命的人物")
		if step.action_kind == "rent_shop":
			if not known.has(params.building_id) or not state.management_assets.has(params.building_id) or state.management_assets[params.building_id].get("asset_kind") != "building":
				return _fail(path + ".parameters.building_id", "未获知该实际铺面")
			if params.shop_id != "pawnshop:%s:%s" % [org, params.building_id]:
				return _fail(path + ".parameters.shop_id", "经营单位标识必须对应本组织与实际铺面")
		elif params.has("shop_id") and (not projected.management_assets.has(params.shop_id) or projected.management_assets[params.shop_id].get("asset_kind") != "pawnshop" or projected.management_assets[params.shop_id].get("owner_ref", {}).get("entity_id") != org):
			return _fail(path + ".parameters.shop_id", "没有本人已存在或前序筹办的经营单位")
		for field in ["funding_account_id", "source_account_id"]:
			if params.has(field) and not known.has(params[field]):
				return _fail(path + ".parameters." + field, "没有这个资金来源的支配权")
		if params.has("destination_account_id") and not known.has(params.destination_account_id):
			return _fail(path + ".parameters.destination_account_id", "没有可见的收款账户依据")
		if params.has("collateral_id") and not known.has(params.collateral_id):
			return _fail(path + ".parameters.collateral_id", "未知实际抵押物")
		if params.has("borrower_id") and state.management_assets.get(params.get("collateral_id", ""), {}).get("pledge_offer", {}).get("borrower_id") != params.borrower_id:
			return _fail(path + ".parameters.borrower_id", "借款人不是该抵押意愿的实际当事人")
		if params.has("loan_id") and state.economic_contracts.get(params.loan_id, {}).get("shop_id") != params.shop_id:
			return _fail(path + ".parameters.loan_id", "借据不属于该经营单位")
		var request := {"execution_id": execution_id, "request_id": execution_id, "actor_id": executor, "principal_id": player, "executor_id": executor, "action_kind": step.action_kind, "target_refs": step.target_refs, "parameters": params, "expected_state_revision": state.state_revision}
		var valid := Dispatcher.validate_request(state, request)
		if not valid.ok:
			return _fail(path, valid.error)
		var cost := Dispatcher.cost_for(projected, step.action_kind, params)
		if not cost.ok:
			return _fail(path, cost.error)
		if int(cost.amount) > 0:
			required[cost.account_id] = int(required.get(cost.account_id, 0)) + int(cost.amount)
		if step.action_kind == "inquire_marriage":
			projected.economic_contracts[params.proposal_id] = {"contract_id": params.proposal_id, "contract_kind": "marriage", "match_id": params.match_id, "principal_id": player}
		if step.action_kind == "rent_shop":
			projected.management_assets[params.shop_id] = {"asset_id": params.shop_id, "asset_kind": "pawnshop", "building_id": params.building_id, "owner_ref": {"entity_kind": "clan", "entity_id": org}}
		if step.action_kind == "offer_family_wage":
			projected.office_state[params.office_id].remuneration_terms.amount = int(params.amount)
		if step.action_kind == "commission_grain_transport":
			projected.grain_transports.append({"transport_kind": "regional_grain", "transport_id": params.order_id, "principal_id": player, "from_depot_id": params.source_depot_id, "target_id": params.target_depot_id})
		if step.action_kind == "repay_public_cash":
			projected.economic_contracts[params.case_id].remaining_amount -= int(params.amount)
		if official_action:
			var catalog = preload("res://scripts/domain/tang_office_catalog.gd")
			var canonical: String = catalog.canonical_id(params.office_id)
			for office_id in [canonical, params.office_id] + catalog.get_legacy_aliases_for(canonical):
				if projected.office_state.has(office_id): projected.office_state[office_id].holder_id = params.get("candidate_id", "")
		if step.action_kind == "send_exam_candidate":
			projected.economic_contracts[params.journey_id] = {"contract_id": params.journey_id, "contract_kind": "school_exam_journey", "school_id": params.school_id}
		if step.action_kind == "send_official_envoy":
			projected.economic_contracts[params.journey_id] = {"contract_id": params.journey_id, "contract_kind": "official_journey", "customer_id": player, "supplier_id": params.person_id, "target_depot_id": params.target_depot_id}
		if step.action_kind == "commission_school_supply":
			projected.economic_contracts[params.order_id] = {"contract_id": params.order_id, "contract_kind": "school_supply", "school_id": params.school_id}
		if step.action_kind == "start_public_work":
			projected.economic_contracts[params.order_id] = {"contract_id": params.order_id, "contract_kind": "public_work", "canal_id": params.canal_id}
		if step.action_kind == "commission_production":
			projected.economic_contracts[params.order_id] = {"contract_id": params.order_id, "contract_kind": "production", "workshop_id": params.workshop_id, "customer_id": player}
		if step.action_kind == "start_character_search":
			projected.economic_contracts[params.search_id] = {"contract_id": params.search_id, "contract_kind": "character_search", "location_id": params.location_id, "principal_id": player}
		if not kinds.has(step.action_kind): kinds.append(step.action_kind)
		for target in step.target_refs:
			if not targets.has(target): targets.append(target)
	var auth := {"authorization_id": "assistant-auth:" + execution_id, "principal_id": player, "delegate_id": executor, "scope": {"action_kinds": kinds, "target_refs": targets, "allow_subdelegation": false}, "resource_limits": dto.resource_limits.duplicate(true), "version": 1, "status": "active", "valid_until_day": null}
	var plan := {"task_id": "assistant-task:" + execution_id, "name": dto.plan.name, "executor_id": executor, "steps": dto.plan.steps.duplicate(true)}
	if dto.kind == "revise":
		plan.task_id = dto.task_id
		auth.scope = revision.scope
	if dto.kind == "proposal" and instruction != "":
		var terms: Dictionary = load("res://scripts/core/assistant_instruction_authority.gd").terms(context, instruction, plan.steps, instruction_day)
		if not terms.get("ok", false): return _fail("instruction", str(terms.error))
		auth.valid_until_day = terms.valid_until_day
		auth.scope.allow_subdelegation = terms.allow_subdelegation
	var valid := Authorization.validate_authorization(state, auth)
	if not valid.ok:
		return _fail("resource_limits", valid.error)
	for account in required:
		var limits: Array = dto.resource_limits.filter(func(l): return l.account_id == account)
		if limits.size() != 1 or int(limits[0].amount) < int(required[account]):
			return _fail("resource_limits", "预算不足覆盖实际步骤累计费用：" + str(account))
	valid = {"ok": true} if dto.kind == "revise" else Authorization.validate_plan(state, auth, plan)
	if not valid.ok:
		return _fail("plan", valid.error)
	return {"ok": true, "dto": dto, "authorization": auth, "plan": plan, "execution_id": execution_id, "required_costs": required, "instruction_day": int(context.state.current_day) if instruction_day < 0 else instruction_day}

func _exact(value: Variant, fields: Array, path: String) -> Dictionary:
	if not value is Dictionary:
		return _fail(path, "需要对象")
	for key in value:
		if not fields.has(key): return _fail(path + "." + str(key), "不接受未知字段")
	for key in fields:
		if not value.has(key): return _fail(path + "." + str(key), "缺少字段")
	return {"ok": true}

# Local authority comes from the player's instruction, never the model's disposition.
func explicitly_authorizes(context, text: String, compiled: Dictionary) -> bool:
	if compiled.get("dto", {}).get("kind") != "proposal": return false
	var instruction = load("res://scripts/core/assistant_instruction_authority.gd")
	if instruction.nonexecuting(text): return false
	if preload("res://scripts/core/assistant_action_instruction_scope.gd").authorizes(context, text, compiled): return true
	if instruction.authorizes_entrustment(context, text, compiled): return true
	if not instruction.pawnshop_scope(context, text, compiled): return false
	for marker in ["如果", "假如", "假设", "要是", "不要", "不用", "不许", "别", "是否", "能否", "先建议", "先讨论", "先拟", "供我决定", "？", "?"]:
		if text.contains(marker): return false
	if not ["全权安排", "直接办理", "现在办理", "即刻办理", "交给你办"].any(func(v): return text.contains(v)):
		return false
	if not ["家族公账", "家族主账户"].any(func(v): return text.contains(v)):
		return false
	var purpose := RegEx.new()
	purpose.compile("开(?:一家|设)?当铺")
	if purpose.search(text) == null: return false
	var budget := RegEx.new()
	budget.compile("(?:不超过|不得超过|最多|至多|累计预算|预算上限)[：:\\s]*([0-9零〇一二两三四五六七八九十百千万]+)")
	var matches := budget.search_all(text)
	if matches.size() != 1: return false
	var ceiling := _instruction_amount(matches[0].get_string(1))
	if not Contract.amount(ceiling, true): return false
	var roots: Array = context.state.office_state.values().filter(func(o): return o.get("office_kind") == "family" and o.get("organization_id") == context.state.flags.get("player_organization_id") and o.get("role_key") == "shopkeeper")
	if roots.size() != 1: return false
	var funding: String = roots[0].remuneration_terms.account_id
	if compiled.authorization.resource_limits.size() != 1 or compiled.authorization.resource_limits[0].account_id != funding or int(compiled.authorization.resource_limits[0].amount) > ceiling:
		return false
	for step in compiled.plan.steps:
		if step.action_kind not in ["rent_shop", "hire_family", "offer_family_wage", "prepare_pawnshop", "fund_pawnshop", "open_pawnshop"]:
			return false
		if step.parameters.has("office_id") and step.parameters.office_id != roots[0].office_id: return false
		if step.parameters.has("funding_account_id") and step.parameters.funding_account_id != funding: return false
		if step.parameters.has("candidate_id"):
			for character in context.scenario_data.characters:
				if character.has("employment_preferences") and text.contains(str(character.name)) and step.parameters.candidate_id != character.id: return false
		if step.action_kind == "rent_shop":
			for asset in context.state.management_assets.values():
				if asset.asset_kind == "building" and text.contains(str(asset.name)) and step.parameters.building_id != asset.asset_id: return false
	return true

func _instruction_amount(text: String) -> int:
	if text.is_valid_int(): return int(text)
	var digits := {"零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9}
	var units := {"十": 10, "百": 100, "千": 1000}
	var total := 0
	var section := 0
	var digit := 0
	var last_unit := 10000
	for character in text:
		if digits.has(character):
			if digit > 0: return -1
			digit = int(digits[character])
		elif units.has(character):
			var unit := int(units[character])
			if unit >= last_unit: return -1
			section += maxi(digit, 1) * unit
			digit = 0
			last_unit = unit
		elif character == "万":
			if total > 0: return -1
			total = (section + digit) * 10000
			section = 0
			digit = 0
			last_unit = 10000
		else: return -1
	return total + section + digit

func _text(value: Variant, maximum: int, empty: bool = false) -> bool:
	return value is String and value.length() <= maximum and (empty or not value.strip_edges().is_empty())

func _strings(value: Variant) -> bool:
	return value is Array and value.all(func(v): return _text(v, 512))

func _fail(path: String, message: String) -> Dictionary:
	return {"ok": false, "code": "invalid_assistant_plan", "error": path + "：" + message, "field_path": path}
