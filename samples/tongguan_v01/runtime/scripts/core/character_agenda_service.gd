# scripts/core/character_agenda_service.gd
extends RefCounted

class_name CharacterAgendaService

const CharacterSchemeStateScript = preload("res://scripts/core/character_scheme_state.gd")
const ControlRelationStateScript = preload("res://scripts/core/control_relation_state.gd")
const PositionClaimStateScript = preload("res://scripts/core/position_claim_state.gd")
const ManagementContract = preload("res://scripts/core/management_state_contract.gd")
const ResourceAccounts = preload("res://scripts/core/resource_account_service.gd")
const Subsistence = preload("res://scripts/core/household_subsistence_service.gd")
const FamilyOfficeRules = preload("res://scripts/core/family_office_rules.gd")
const GameActionDispatcher = preload("res://scripts/core/game_action_dispatcher.gd")
const WorldTransaction = preload("res://scripts/core/game_state_transaction.gd")

static func get_social_opportunities(state, actor_id: String) -> Array:
	return load("res://scripts/core/npc_social_reaction_service.gd").opportunities(state, actor_id)

# This evaluation is called by the existing NPC active-action update, never by UI.
func update_livelihood(state, data: Dictionary, settlement_context = null) -> Dictionary:
	var model_check := _validate_livelihood_models(state, data)
	if not model_check.get("ok", false):
		return model_check
	var models: Dictionary = data.get("management", {}).get("life_models", {})
	if models.is_empty() or int(state.flags.get("last_livelihood_update_day", -1)) == int(state.current_day):
		return {"ok": true, "updated": false}
	for id in models:
		if not state.character_states.has(id):
			return ManagementContract.fail("生计模型引用缺失人物：" + str(id))
		var character: Dictionary = state.character_states[id]
		if character.get("status") in ["dead", "deceased", "executed", "departed", "exiled", "missing", "imprisoned", "unreachable", "defected", "irreconcilable"]:
			continue
		var model: Dictionary = models[id]
		var account_id := str(id) + "_cash"
		if not state.resource_accounts.has(account_id):
			return ManagementContract.fail("生计模型缺少个人资金来源：" + str(id))
		var goal: Dictionary = character.get("life_goal", {})
		if goal.is_empty():
			goal = {"character_id": id, "goal_kind": "secure_livelihood", "goal_stage": "seeking", "evidence_refs": [], "opportunity_refs": [], "next_review_day": 0, "last_review_day": -1, "last_input_hash": "", "public_expression": "", "application": {}, "rejected_offices": {}, "history": [], "private_priorities": {}}
			character["life_goal"] = goal
		var food := Subsistence.settle(state, data, id, model, goal, settlement_context)
		if not food.get("ok", false):
			return food
		var hungry: bool = int(goal.subsistence.missing_today) > 0
		var cash: int = ResourceAccounts.new().available(state, account_id)
		var held: Array = state.office_state.values().filter(func(o): return o.get("holder_id") == id)
		var employment: Array = state.economic_contracts.values().filter(func(c): return c.get("contract_kind") == "employment" and c.get("employee_id") == id and c.get("status") == "active")
		var options := _known_jobs(state, data, id, model)
		var facts := {"cash": cash, "held": held.map(func(o): return o.office_id), "employment": employment, "options": options, "dependants": model.dependants, "hungry": hungry}
		var fingerprint := str(preload("res://scripts/core/canonical_json.gd").hash_value(facts).get("hash", ""))
		var application: Dictionary = goal.application
		var response_due: bool = application.get("status") == "waiting" and int(state.current_day) >= int(application.get("response_due_day", 0))
		if goal.last_input_hash == fingerprint and int(state.current_day) < int(goal.next_review_day) and not response_due:
			continue
		goal.last_review_day = int(state.current_day)
		goal.next_review_day = int(state.current_day) + int(model.review_interval_days)
		goal.last_input_hash = fingerprint
		goal.evidence_refs = [{"entity_kind": "account", "entity_id": account_id}, {"entity_kind": "character", "entity_id": id}, {"entity_kind": "account", "entity_id": str(id) + "_rations"}]
		goal.opportunity_refs = options.map(func(option): return option.office_id)
		goal.private_priorities = {"available_cash": cash, "reserve_target": int(model.minimum_reserve) + int(model.dependants) * 5, "scored_opportunities": options.duplicate(true)}
		var insecure: bool = cash < int(model.minimum_reserve) + int(model.dependants) * 5
		var stable_goal := _stable_goal(data, id, model)
		goal.goal_kind = "secure_food" if hungry else ("secure_livelihood" if insecure else stable_goal)
		for old_job in employment:
			if int(old_job.arrears) <= 0 or int(state.current_day) < int(old_job.next_due_day) + int(model.unpaid_grace_days): continue
			var resigned := _employment_action(state, data, id, "resign_family", {"office_id": old_job.office_id}, "unpaid-resignation:%s:%d" % [old_job.contract_id, int(state.current_day)])
			if not resigned.get("ok", false):
				return resigned
			goal.history.append({"kind": "resigned_unpaid", "office_id": old_job.office_id, "day": int(state.current_day), "contract_ref": old_job.contract_id})
			goal.rejected_offices[old_job.office_id] = int(state.current_day) + int(model.unpaid_grace_days)
			var old_employer := str(state.resource_accounts[old_job.remuneration_terms.account_id].operator_refs[0].entity_id)
			character.relationships[old_employer] = clampi(int(character.relationships.get(old_employer, 0)) - 15, -100, 100)
			if application.get("office_id") == old_job.office_id:
				goal.application = {}
				application = goal.application
			state.state_revision += 1
		held = state.office_state.values().filter(func(o): return o.get("holder_id") == id)
		employment = state.economic_contracts.values().filter(func(c): return c.get("contract_kind") == "employment" and c.get("employee_id") == id and c.get("status") == "active")
		if not held.is_empty():
			goal.goal_stage = "working_to_build_reserve" if insecure else "stable"
			goal.public_expression = "工资已有拖欠，盼在宽限期内结清；否则将另谋生计。" if employment.any(func(job): return int(job.arrears) > 0) else ("正在本职任上积攒家用。" if insecure else _stable_expression(stable_goal))
			if application.get("status") == "waiting":
				application.status = "hired" if held.any(func(office): return office.office_id == application.office_id) else "withdrawn"
				if application.status == "hired":
					var matching: Array = employment.filter(func(job): return job.office_id == application.office_id)
					if matching.size() == 1: application.contract_ref = matching[0].contract_id
			continue
		if application.get("status") == "waiting":
			var office: Dictionary = state.office_state.get(application.office_id, {})
			if office.get("holder_id", "") != "":
				application.status = "closed"
				goal.rejected_offices[application.office_id] = int(state.current_day) + 7
			elif response_due:
				application.status = "expired"
				goal.rejected_offices[application.office_id] = int(state.current_day) + 7
				goal.history.append({"kind": "no_response", "office_id": application.office_id, "day": int(state.current_day)})
			else:
				goal.goal_stage = "awaiting_employer"
				continue
		var chosen := {}
		for option in options:
			if not option.get("known_commitment_refs", []).is_empty(): continue
			if int(goal.rejected_offices.get(option.office_id, -1)) > int(state.current_day):
				continue
			chosen = option
			break
		if chosen.is_empty():
			goal.goal_stage = "seeking"
			goal.public_expression = "正在打听能维持生计的差事。" if insecure else "愿找能发挥所长的差事。"
			continue
		goal.application = {"office_id": chosen.office_id, "employer_id": chosen.employer_id, "requested_wage": chosen.requested_wage, "requested_period_days": chosen.period_days, "applied_day": int(state.current_day), "response_due_day": int(state.current_day) + int(model.application_wait_days), "status": "waiting", "contract_ref": ""}
		goal.goal_stage = "awaiting_employer"
		goal.public_expression = "愿任%s，每 %d 日需 %d 记账单位；盼有稳定收入。" % [str(state.office_state[chosen.office_id].name), int(chosen.period_days), int(chosen.requested_wage)]
		goal.history.append({"kind": "applied", "office_id": chosen.office_id, "day": int(state.current_day)})
		if chosen.employer_id != state.player_character_id:
			var hired := _accept_application(state, data, id, chosen.employer_id, "npc-employment:%s:%s:%d" % [id, chosen.office_id, int(state.current_day)])
			if not hired.get("ok", false):
				goal.application.status = "declined"
				goal.rejected_offices[chosen.office_id] = int(state.current_day) + 7
				goal.public_expression = "未能谈妥受雇条件，继续寻找别的机会。"
			else:
				state.state_revision += 1
	for id in models:
		var goal: Dictionary = state.character_states[id].get("life_goal", {})
		if goal.is_empty(): continue
		var crops: Array = state.economic_contracts.values().filter(func(order): return order.get("contract_kind") == "cultivation" and order.get("owner_id") == id and order.get("status") in ["growing", "mature"])
		if not crops.is_empty() and goal.application.get("status", "") != "waiting":
			goal.goal_stage = "tending_fields"
			goal.public_expression = "正照料自家的庄稼，等待农时收割；收粮要供家人生活。"
		goal.public_expression = str(goal.get("public_expression", "")).trim_prefix("家中口粮不足，急需解决吃饭问题。")
		var education: Array = state.economic_contracts.values().filter(func(order): return order.get("contract_kind") in ["school_teaching", "school_enrollment"] and order.get("supplier_id") == id)
		if not education.is_empty() and goal.application.get("status", "") != "waiting":
			var course: Dictionary = education[-1]
			goal.goal_stage = "stable"
			goal.public_expression = "正依约授课谋生，须兑现约定的教学工日。" if course.contract_kind == "school_teaching" else ("基础学业已完成，等待后续考核；名额与任官仍须另行争取。" if course.assessment_eligible else "正到学舍学习；有生活与既有职责需要时，须暂停到课。")
			if course.contract_kind == "school_teaching" and course.status == "completed": goal.public_expression = "这一期授课已完成，正在寻找下一份教学差事。"
		var candidacies: Array = state.economic_contracts.values().filter(func(order): return order.get("contract_kind") == "school_candidacy" and order.get("supplier_id") == id)
		if not candidacies.is_empty() and goal.application.get("status", "") != "waiting":
			goal.public_expression = preload("res://scripts/core/school_assessment_service.gd").outcome_text(state, candidacies[-1])
		if int(goal.get("subsistence", {}).get("missing_today", 0)) > 0:
			goal.public_expression = "家中口粮不足，急需解决吃饭问题。" + str(goal.get("public_expression", ""))
	state.flags["last_livelihood_update_day"] = int(state.current_day)
	return {"ok": true, "updated": true}

func _validate_livelihood_models(state, data: Dictionary) -> Dictionary:
	var models: Variant = data.get("management", {}).get("life_models", {})
	if not models is Dictionary:
		return ManagementContract.fail("生计模型必须是人物配置表")
	for id in models:
		var model: Variant = models[id]
		if not model is Dictionary or not state.character_states.has(id) or not state.resource_accounts.has(str(id) + "_cash"):
			return ManagementContract.fail("生计模型缺少实际人物或个人账户：" + str(id))
		for field in ["minimum_reserve", "dependants", "tie_bonus"]:
			if not ManagementContract.amount(model.get(field)):
				return ManagementContract.fail("生计模型无效字段：" + str(id) + "/" + field)
		for field in ["application_wait_days", "review_interval_days", "unpaid_grace_days"]:
			if not ManagementContract.amount(model.get(field), true):
				return ManagementContract.fail("生计模型无效周期：" + str(id) + "/" + field)
		if model.get("stable_goal") not in ["household_service", "support_family", "build_reputation", "learn_trade"] or not state.character_states.has(model.get("preferred_employer_id")) or not str(model.get("source_id", "")).begins_with("scenario:"):
			return ManagementContract.fail("生计模型缺少目标、关系来源或配置来源：" + str(id))
	return {"ok": true}

func _known_jobs(state, data: Dictionary, character_id: String, model: Dictionary, observed_contracts: Variant = null) -> Array:
	var definitions: Array = data.get("characters", []).filter(func(c): return c.get("id") == character_id)
	if definitions.size() != 1:
		return []
	var preferences: Dictionary = definitions[0].get("employment_preferences", {})
	var traits: Array = definitions[0].get("traits", [])
	var hungry: bool = int(state.character_states[character_id].get("life_goal", {}).get("subsistence", {}).get("missing_today", 0)) > 0
	# Static definition traits adjust known offers; hunger overrides ordinary attachment.
	var wage_weight := 4 if hungry else (2 if traits.has("pragmatic") else 1)
	var tie_weight := 1 if hungry else (2 if traits.has("loyal") else 1)
	var location := str(state.character_states[character_id].get("location_id", ""))
	var commitments: Array = []
	if observed_contracts == null:
		observed_contracts = {}
		for record in state.economic_contracts.values():
			if record.get("contract_kind") != "social_agreement" or record.get("purpose") != "employment" or record.participant_ids[1] != character_id: continue
			var visible: Dictionary = load("res://scripts/core/social_agreement_service.gd").project(state, record, character_id)
			if not visible.is_empty(): observed_contracts[visible.contract_id] = visible
	for promise in observed_contracts.values():
		if promise.get("contract_kind") == "social_agreement" and promise.get("purpose") == "employment" and promise.participant_ids[1] == character_id and promise.status in ["proposed", "countered", "accepted"] and promise.accepted_versions.get(character_id) == promise.terms_version: commitments.append(promise)
	var options: Array = []
	for office in state.office_state.values():
		var notice: Dictionary = office.get("recruitment_notice", {})
		if office.get("office_kind") != "family" or office.get("holder_id", "") != "" or notice.get("visibility") != "public" or notice.get("location_id") != location:
			continue
		if not preferences.get("roles", []).has(office.get("role_key")) or not preferences.get("organization_ids", []).has(office.get("organization_id")):
			continue
		var account: Dictionary = state.resource_accounts.get(office.remuneration_terms.account_id, {})
		if account.is_empty() or account.operator_refs.is_empty():
			continue
		var employer := str(account.operator_refs[0].entity_id)
		var wage: int = maxi(int(office.remuneration_terms.amount), int(preferences.get("minimum_wage", 0)))
		var period: int = int(office.remuneration_terms.period_days)
		if period <= 0: continue
		var work_days: Array = []
		for day in office.get("work_schedule", {}).get("days", []):
			if not work_days.has(int(day)): work_days.append(int(day))
		if work_days.is_empty(): continue
		# Compare the advertised rate on the same 30-day basis. This does not
		# change the actual first wage, pay calendar or negotiated minimum.
		var comparable_wage: int = int(office.remuneration_terms.amount) * 30 / period
		# Keep the actual calendar wage for the application. Compare the same
		# advertised pay against required whole workdays, never invented hours.
		var comparable_workday_return: int = int(office.remuneration_terms.amount) * 30 * 7 / (period * work_days.size())
		var score := comparable_workday_return * wage_weight
		if employer == str(model.get("preferred_employer_id", "")):
			score += int(model.get("tie_bonus", 0)) * tie_weight
		score += (int(state.character_states[character_id].get("relationships", {}).get(employer, 0)) / 10) * tie_weight
		var seed := (character_id + str(office.office_id) + str(state.flags.get("rule_seed", 107))).sha256_text()
		var known_commitment_refs: Array = []
		for promise in commitments:
			var promised: Dictionary = load("res://scripts/core/npc_opportunity_projection.gd").observed_office(state, promise, character_id)
			if promise.terms.office_id == office.office_id or promised.is_empty() or promised.get("organization_id") != office.organization_id or preload("res://scripts/core/character_workload_service.gd").overlaps(promised, office): known_commitment_refs.append(promise.contract_id)
		options.append({"office_id": office.office_id, "employer_id": employer, "requested_wage": wage, "period_days": period, "quoted_wage": int(office.remuneration_terms.amount), "comparison_days": 30, "comparable_wage": comparable_wage, "work_days_per_week": work_days.size(), "comparable_workday_return": comparable_workday_return, "known_commitment_refs": known_commitment_refs, "score": score, "stable_tie": seed, "notice_source": str(notice.source_id)})
	options.sort_custom(func(a, b): return a.score > b.score if a.score != b.score else a.stable_tie < b.stable_tie)
	return options

func _stable_goal(data: Dictionary, id: String, model: Dictionary) -> String:
	var definitions: Array = data.get("characters", []).filter(func(c): return c.get("id") == id)
	var traits: Array = definitions[0].get("traits", []) if definitions.size() == 1 else []
	if traits.has("curious"): return "learn_trade"
	if traits.has("ambitious"): return "build_reputation"
	if traits.has("loyal") and int(model.dependants) == 0: return "household_service"
	return str(model.stable_goal)

func _accept_application(state, data: Dictionary, candidate_id: String, employer_id: String, execution_id: String) -> Dictionary:
	var goal: Dictionary = state.character_states[candidate_id].get("life_goal", {})
	var application: Dictionary = goal.get("application", {})
	if application.get("status") != "waiting" or application.get("employer_id") != employer_id:
		return ManagementContract.fail("该求职已失效或不是向本人递交")
	var office: Dictionary = state.office_state.get(application.office_id, {})
	if not FamilyOfficeRules.authority(state, str(application.office_id), employer_id):
		return ManagementContract.fail("雇主没有该职位的任用权")
	var wage := int(application.requested_wage)
	if int(office.remuneration_terms.period_days) != int(application.get("requested_period_days", -1)):
		return ManagementContract.fail("工资周期已变化，须按新周期重新商议，不能沿用旧申请")
	if int(office.remuneration_terms.amount) > wage:
		return ManagementContract.fail("职位报价高于这次确认的求职条件，请重新洽谈后办理")
	if employer_id != state.player_character_id:
		var policy: Dictionary = data.get("management", {}).get("employer_hiring_policies", {}).get(office.organization_id, {})
		if wage > int(policy.get("maximum_wage", 0)):
			return ManagementContract.fail("该雇主不愿支付所求工资")
	if ResourceAccounts.new().available(state, office.remuneration_terms.account_id) < wage:
		return ManagementContract.fail("雇主可用资金不足支付实际首期工资")
	if wage > int(office.remuneration_terms.amount):
		var quote := _employment_action(state, data, employer_id, "offer_family_wage", {"office_id": application.office_id, "amount": wage}, execution_id + ":offer")
		if not quote.get("ok", false):
			return quote
	var hired := _employment_action(state, data, employer_id, "hire_family", {"office_id": application.office_id, "candidate_id": candidate_id}, execution_id + ":hire")
	if not hired.get("ok", false):
		return hired
	application.status = "hired"
	application.contract_ref = str(hired.receipt.effect_refs[0])
	goal.goal_stage = "employed"
	goal.public_expression = "已按谈妥的报酬受雇，正在履职。"
	goal.history.append({"kind": "hired", "office_id": application.office_id, "day": int(state.current_day), "contract_ref": application.contract_ref})
	var relations: Dictionary = state.character_states[candidate_id].get("relationships", {})
	relations[employer_id] = clampi(int(relations.get(employer_id, 0)) + 5, -100, 100)
	state.character_states[candidate_id].relationships = relations
	return {"ok": true, "result_ref": application.contract_ref}

func _employment_action(state, data: Dictionary, actor: String, kind: String, params: Dictionary, execution: String) -> Dictionary:
	return GameActionDispatcher.apply(state, data, {"execution_id": execution, "request_id": execution, "actor_id": actor, "principal_id": actor, "executor_id": actor, "action_kind": kind, "target_refs": [params.office_id], "parameters": params, "expected_state_revision": state.state_revision})

func respond_to_application(context, candidate_id: String, accept: bool, execution_id: String, expected_application: Dictionary = {}) -> Dictionary:
	if context == null or not context.state.character_states.has(candidate_id) or execution_id.is_empty():
		return ManagementContract.fail("缺少实际求职人物或执行标识")
	var current: Dictionary = context.state.character_states[candidate_id].get("life_goal", {}).get("application", {})
	var expected: Dictionary = current if expected_application.is_empty() else expected_application
	var offer := {}
	for field in ["office_id", "employer_id", "requested_wage", "requested_period_days", "applied_day", "response_due_day"]:
		if current.get(field) != expected.get(field):
			return ManagementContract.fail("求职条件已经改变，请重新查看后答复")
		offer[field] = expected.get(field)
	var transaction = WorldTransaction.new()
	var input := {"candidate_id": candidate_id, "accept": accept, "execution_id": execution_id, "actor_id": context.state.player_character_id, "offer": offer}
	var preview := transaction.preview_command(context.state, "employment_response", input)
	if not preview.get("ok", false):
		return preview
	return transaction.execute_command(context, transaction.build_command_envelope("employment_response", input, preview.preview_token), func(working):
		var goal: Dictionary = working.state.character_states[candidate_id].get("life_goal", {})
		var application: Dictionary = goal.get("application", {})
		if application.get("status") != "waiting" or application.get("employer_id") != input.actor_id:
			return ManagementContract.fail("该求职已失效或不是向本人递交")
		if accept:
			return _accept_application(working.state, working.scenario_data, candidate_id, input.actor_id, execution_id)
		application.status = "declined"
		goal.rejected_offices[application.office_id] = int(working.state.current_day) + 7
		goal.next_review_day = int(working.state.current_day) + 1
		goal.public_expression = "未获接纳，将另寻谋生机会。"
		goal.history.append({"kind": "declined", "office_id": application.office_id, "day": int(working.state.current_day)})
		return {"ok": true, "result_ref": "application:" + candidate_id}
	)

func livelihood_projection(state, viewer_id: String) -> Array:
	var rows: Array = []
	for character in state.character_states.values():
		var goal: Dictionary = character.get("life_goal", {})
		var application: Dictionary = goal.get("application", {})
		if application.get("employer_id") != viewer_id:
			continue
		rows.append({"character_id": character.id, "name": character.name, "office_id": application.office_id, "office_name": str(state.office_state[application.office_id].name), "requested_wage": application.requested_wage, "status": application.status, "public_expression": goal.public_expression, "contract_ref": application.get("contract_ref", ""), "application": application.duplicate(true)})
	return rows

func public_employment(state, viewer_id: String, character_id: String) -> Dictionary:
	var visible := {"positions": [], "applications": [], "wage_debts": [], "expression": ""}
	if state == null or not state.character_states.has(viewer_id) or not state.character_states.has(character_id):
		return visible
	var person: Dictionary = state.character_states[character_id]
	var local: bool = str(person.get("location_id", "")) != "" and person.get("location_id") == state.character_states[viewer_id].get("location_id")
	for office in state.office_state.values():
		if office.get("office_kind") != "family" or office.get("holder_id") != character_id:
			continue
		var own := FamilyOfficeRules.authority(state, str(office.office_id), viewer_id)
		if not own and viewer_id != character_id and not (local and office.get("recruitment_notice", {}).get("visibility") == "public"):
			continue
		var operators: Array = state.resource_accounts[office.remuneration_terms.account_id].operator_refs
		var employer := str(operators[0].entity_id) if not operators.is_empty() else ""
		var row := {"office_id": office.office_id, "office_name": office.name, "employer_name": str(state.character_states.get(employer, {}).get("name", "")), "source_kind": "own_employment" if own else "observed_local_employment"}
		if own or viewer_id == character_id:
			var contracts: Array = state.economic_contracts.values().filter(func(c): return c.get("contract_kind") == "employment" and c.get("office_id") == office.office_id and c.get("employee_id") == character_id and c.get("status") == "active")
			if contracts.size() == 1:
				row["wage"] = int(contracts[0].remuneration_terms.amount)
				row["period_days"] = int(contracts[0].remuneration_terms.period_days)
				row["contract_ref"] = contracts[0].contract_id
			visible.expression = str(person.get("life_goal", {}).get("public_expression", ""))
		visible.positions.append(row)
	for row in livelihood_projection(state, viewer_id):
		if row.character_id == character_id:
			visible.applications.append(row)
			visible.expression = row.public_expression
	for contract in state.economic_contracts.values():
		if contract.get("contract_kind") == "employment" and contract.get("employee_id") == character_id and int(contract.get("arrears", 0)) > 0 and (viewer_id == character_id or FamilyOfficeRules.authority(state, str(contract.office_id), viewer_id)):
			visible.wage_debts.append({"contract_ref": contract.contract_id, "amount": int(contract.arrears)})
	return visible

func _stable_expression(kind: String) -> String:
	match kind:
		"support_family": return "生计稍稳，盼顾好家中亲属。"
		"learn_trade": return "愿在任上精进手艺与账目本领。"
		"build_reputation": return "盼踏实办事，积攒名声。"
		_: return "愿把现有差事办稳。"

func get_character_schemes(state, actor_id: String) -> Array:
	if state == null:
		return []
	var results: Array = []
	for s_id in state.character_schemes.keys():
		var s: Dictionary = state.character_schemes[s_id]
		if str(s.get("actor_id", "")) == actor_id:
			results.append(s.duplicate(true))
	return results

func create_scheme(state, scheme_data: Dictionary) -> Dictionary:
	if state == null:
		return {"ok": false, "error": "invalid state"}
	var actor_id := str(scheme_data.get("actor_id", "")).strip_edges()
	if actor_id.is_empty():
		return {"ok": false, "error": "missing actor_id"}
		
	var scheme_id := str(scheme_data.get("scheme_id", ""))
	if scheme_id.is_empty():
		scheme_id = "scheme|%s|%s|%d" % [actor_id, str(scheme_data.get("scheme_kind", "usurp_office")), int(state.current_day)]
		
	var scheme_obj = CharacterSchemeStateScript.from_dict(scheme_data)
	scheme_obj.scheme_id = scheme_id
	scheme_obj.start_day = int(state.current_day)
	
	state.character_schemes[scheme_id] = scheme_obj.to_dict()
	return {"ok": true, "scheme_id": scheme_id, "scheme": state.character_schemes[scheme_id]}

func progress_schemes_daily(state, days: int = 1) -> Dictionary:
	if state == null:
		return {"ok": false, "error": "invalid state"}
		
	var executed_schemes: Array = []
	var progress_reports: Array = []
	
	for s_id in state.character_schemes.keys():
		var s: Dictionary = (state.character_schemes[s_id] as Dictionary).duplicate(true)
		if str(s.get("status", "")) != "active":
			continue
			
		var actor_id: String = str(s.get("actor_id", ""))
		var char_profile: Dictionary = state.character_states.get(actor_id, {})
		var intrigue: int = int(char_profile.get("intrigue", 50))
		var base_speed: int = int(s.get("progress_speed", 5))
		var speed_mult := 0.8 + (float(intrigue) / 100.0) * 0.4
		var delta_progress := int(round(float(base_speed) * speed_mult * float(days)))
		
		var cur_p: int = int(s.get("progress", 0)) + delta_progress
		s["progress"] = mini(100, cur_p)
		
		if s["progress"] >= 100:
			s["status"] = "executing"
			var exec_res := _execute_scheme(state, s)
			executed_schemes.append(exec_res)
			s["status"] = "completed" if bool(exec_res.get("ok", false)) else "foiled"
			
		state.character_schemes[s_id] = s
		progress_reports.append({
			"scheme_id": s_id,
			"actor_id": actor_id,
			"progress": s["progress"],
			"status": s["status"]
		})
		
	return {
		"ok": true,
		"executed_count": executed_schemes.size(),
		"executed": executed_schemes,
		"reports": progress_reports
	}

func investigate_scheme(state, target_actor_id: String, investigator_id: String, days: int = 3) -> Dictionary:
	if state == null:
		return {"ok": false, "error": "invalid state"}
		
	var inv_profile: Dictionary = state.character_states.get(investigator_id, {})
	var inv_intrigue: int = int(inv_profile.get("intrigue", 60))
	var base_evidence_gain := int(round(float(inv_intrigue) * 0.25 * float(days)))
	
	var discovered: Array = []
	for s_id in state.character_schemes.keys():
		var s: Dictionary = (state.character_schemes[s_id] as Dictionary).duplicate(true)
		if str(s.get("actor_id", "")) == target_actor_id and str(s.get("status", "")) == "active":
			var cur_ev: int = int(s.get("evidence_level", 0))
			var new_ev := mini(100, cur_ev + base_evidence_gain)
			s["evidence_level"] = new_ev
			if new_ev >= 60:
				s["is_revealed"] = true
				discovered.append({
					"scheme_id": s_id,
					"scheme_kind": str(s.get("scheme_kind", "")),
					"scheme_name": str(s.get("scheme_name", "")),
					"evidence_level": new_ev,
					"actor_id": target_actor_id
				})
			state.character_schemes[s_id] = s
			
	state.chronicle_causal_references.append({
		"kind": "scheme_investigation",
		"target_id": target_actor_id,
		"investigator_id": investigator_id,
		"evidence_gained": base_evidence_gain,
		"discovered_count": discovered.size(),
		"day": int(state.current_day)
	})
	
	return {
		"ok": true,
		"investigator_id": investigator_id,
		"target_id": target_actor_id,
		"evidence_gained": base_evidence_gain,
		"discovered_count": discovered.size(),
		"discovered": discovered
	}

func foil_scheme(state, scheme_id: String, foiler_id: String) -> Dictionary:
	if state == null or not state.character_schemes.has(scheme_id):
		return {"ok": false, "error": "scheme not found: " + scheme_id}
	var s: Dictionary = (state.character_schemes[scheme_id] as Dictionary).duplicate(true)
	s["status"] = "foiled"
	s["is_revealed"] = true
	state.character_schemes[scheme_id] = s
	
	var actor_id: String = str(s.get("actor_id", ""))
	if state.character_states.has(actor_id):
		var char_dict: Dictionary = (state.character_states[actor_id] as Dictionary).duplicate(true)
		var rel: Dictionary = (char_dict.get("relationships", {}) as Dictionary).duplicate(true)
		rel[foiler_id] = clampi(int(rel.get(foiler_id, 0)) - 30, -100, 100)
		char_dict["relationships"] = rel
		state.character_states[actor_id] = char_dict
		
	state.chronicle_causal_references.append({
		"kind": "scheme_foiled",
		"scheme_id": scheme_id,
		"actor_id": actor_id,
		"foiler_id": foiler_id,
		"day": int(state.current_day)
	})
	return {"ok": true, "scheme_id": scheme_id, "actor_id": actor_id, "status": "foiled"}

func generate_spontaneous_memorials(state) -> Array[Dictionary]:
	if state == null:
		return []
		
	var new_memorials: Array[Dictionary] = []
	
	# 1. 前线将领断粮/缺饷自发告急请旨
	for f_id in state.military_forces.keys():
		var force: Dictionary = state.military_forces[f_id]
		var rations: int = int(force.get("rations_on_hand_days", 20))
		var commander_id: String = str(force.get("commander_id", ""))
		if rations <= 3 and not commander_id.is_empty():
			var mem_id := "mem_urgent_grain_%s_%d" % [f_id, int(state.current_day)]
			if not (state.governance_state.get("memorials", {}) as Dictionary).has(mem_id):
				var mem := {
					"memorial_id": mem_id,
					"title": "【告急】%s军中粮秣将尽，乞速发转运使调拨" % str(force.get("display_name", f_id)),
					"author_id": commander_id,
					"filed_day": int(state.current_day),
					"status": "unread",
					"category": "military_supply",
					"source_kind": "spontaneous_general",
					"body_text": "臣部转战关隘，所携糗粮仅支三日，士卒悬望朝廷转运。若粮道不继，恐军心震动，乞朝廷速赐敕旨，度支调发。",
					"suggested_action": "dispatch_grain_transport",
					"urgency": 90
				}
				(state.governance_state["memorials"] as Dictionary)[mem_id] = mem
				new_memorials.append(mem)
				
	# 2. 地方大员因府库丰盈自发请旨协饷或举荐
	for d_id in state.depot_states.keys():
		var depot: Dictionary = state.depot_states[d_id]
		var grain: int = int((depot.get("stock", {}) as Dictionary).get("grain", 0))
		var owner_id: String = str(depot.get("owner_character_id", ""))
		if grain >= 60000 and not owner_id.is_empty():
			var mem_id := "mem_depot_surplus_%s_%d" % [d_id, int(state.current_day)]
			if not (state.governance_state.get("memorials", {}) as Dictionary).has(mem_id):
				var mem := {
					"memorial_id": mem_id,
					"title": "【奏捷】太仓余粮充足，请旨调济关中行营",
					"author_id": owner_id,
					"filed_day": int(state.current_day),
					"status": "unread",
					"category": "fiscal_supply",
					"source_kind": "spontaneous_magistrate",
					"body_text": "臣辖下仓廪岁丰，储粮丰沛。伏闻行在军需孔亟，臣愿备漕车挽运，供奉军前。",
					"suggested_action": "requisition_grain",
					"urgency": 40
				}
				(state.governance_state["memorials"] as Dictionary)[mem_id] = mem
				new_memorials.append(mem)
				
	return new_memorials

func _execute_scheme(state, scheme: Dictionary) -> Dictionary:
	var kind: String = str(scheme.get("scheme_kind", ""))
	var actor_id: String = str(scheme.get("actor_id", ""))
	var target_id: String = str(scheme.get("target_id", ""))
	var target_type: String = str(scheme.get("target_type", ""))
	
	if kind == "usurp_office" or kind == "petition_autonomy":
		# 藩镇自立或夺取官印实控
		var ctrl_id := "ctrl|%s|%s" % [target_type, target_id]
		var ctrl := ControlRelationStateScript.new()
		ctrl.control_id = ctrl_id
		ctrl.target_type = target_type
		ctrl.target_id = target_id
		ctrl.controller_id = actor_id
		ctrl.strength = 90
		ctrl.control_type = "usurped"
		state.control_relations[ctrl_id] = ctrl.to_dict()
		
		var claim_id := "claim|usurp|%s|%s|%d" % [target_id, actor_id, int(state.current_day)]
		var claim := PositionClaimStateScript.new()
		claim.claim_id = claim_id
		claim.office_id = target_id
		claim.character_id = actor_id
		claim.issuer_id = actor_id
		claim.claim_status = "pending_confirmation"
		claim.issued_day = int(state.current_day)
		claim.basis_text = "军士拥立·专擅事权"
		state.position_claims[claim_id] = claim.to_dict()
		
		state.chronicle_causal_references.append({
			"kind": "scheme_executed_usurp",
			"scheme_id": str(scheme.get("scheme_id", "")),
			"actor_id": actor_id,
			"target_id": target_id,
			"day": int(state.current_day)
		})
		return {"ok": true, "kind": kind, "actor_id": actor_id, "target_id": target_id, "outcome": "office_usurped_pending_confirmation"}
		
	elif kind == "hoard_grain":
		# 私藏军粮府库
		if state.depot_states.has(target_id):
			var d: Dictionary = (state.depot_states[target_id] as Dictionary).duplicate(true)
			d["owner_character_id"] = actor_id
			state.depot_states[target_id] = d
		return {"ok": true, "kind": kind, "actor_id": actor_id, "target_id": target_id, "outcome": "grain_hoarded"}
		
	return {"ok": true, "kind": kind, "outcome": "custom_effect_applied"}
