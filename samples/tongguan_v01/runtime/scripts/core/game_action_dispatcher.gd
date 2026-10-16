extends RefCounted

const Contract = preload("res://scripts/core/management_state_contract.gd")
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Family = preload("res://scripts/core/family_office_rules.gd")
const Canonical = preload("res://scripts/core/canonical_json.gd")
const Transaction = preload("res://scripts/core/game_state_transaction.gd")
const Pawnshop = preload("res://scripts/core/pawnshop_service.gd")
const Items = preload("res://scripts/core/managed_item_service.gd")
const PublicWorks = preload("res://scripts/core/public_works_service.gd")
const Initiative = preload("res://scripts/core/official_initiative_service.gd")
const LocalFiscal = preload("res://scripts/core/local_fiscal_policy_service.gd")
const Fiscal = preload("res://scripts/core/regional_fiscal_service.gd")
const Assessment = preload("res://scripts/core/school_assessment_service.gd")
const SchoolSupply = preload("res://scripts/core/school_supply_service.gd")
const ExamJourney = preload("res://scripts/core/exam_journey_service.gd")
const Grain = preload("res://scripts/core/regional_grain_service.gd")
const PlayerSuccession = preload("res://scripts/core/player_succession_service.gd")
const Partition = preload("res://scripts/core/family_partition_service.gd")
const Estate = preload("res://scripts/core/personal_estate_service.gd")
const Succession = preload("res://scripts/core/clan_succession_service.gd")
const Marriage = preload("res://scripts/core/marriage_service.gd")
const Envoy = preload("res://scripts/core/official_journey_service.gd")
const LivingAid = preload("res://scripts/core/school_living_aid_service.gd")
const Education = preload("res://scripts/core/education_service.gd")
const Production = preload("res://scripts/core/production_service.gd")
const Search = preload("res://scripts/core/character_search_service.gd")
const Food = preload("res://scripts/core/household_subsistence_service.gd")
const Official = preload("res://scripts/core/official_office_actions.gd")
const Construction = preload("res://scripts/core/estate_construction_service.gd")
const Lifecycle = preload("res://scripts/core/estate_lifecycle_service.gd")
const Land = preload("res://scripts/core/land_property_service.gd")
const Manufacturing = preload("res://scripts/core/manufacturing_business_service.gd")
const Farming = preload("res://scripts/core/managed_farming_service.gd")
const Retail = preload("res://scripts/core/retail_trading_service.gd")
const Modeled = preload("res://scripts/core/modeled_business_service.gd")
const ControlDispatch = preload("res://scripts/core/control_dispatch_actions.gd")
const Visit = preload("res://scripts/core/regional_visit_service.gd")
const Business = preload("res://scripts/core/business_management_service.gd")
const KINDS := ["hire_family", "dismiss_family", "resign_family", "pay_employment_debt", "offer_family_wage", "transfer_cash"]
const Property=preload("res://scripts/core/estate_property_transaction_service.gd")
const Social = preload("res://scripts/core/social_agreement_service.gd")
const Gifts = preload("res://scripts/core/gift_delivery_service.gd")
const Criminal = preload("res://scripts/core/criminal_case_service.gd")

func execute(context, request: Dictionary) -> Dictionary:
	if context == null or context.state == null:
		return Contract.fail("玩家直接操作缺少当前世界")
	if request.get("actor_id") != context.state.player_character_id and not PlayerSuccession.allows_successor_request(context.state, request):
		# The committed identity action changes its own caller. Only that exact
		# request may retrieve its receipt; apply still checks the complete hash.
		var prior: Dictionary = context.state.action_receipts.get(request.get("execution_id", ""), {}).get("player_succession", {})
		if request.get("action_kind") in PlayerSuccession.KINDS and prior.get("from_id") == request.get("actor_id") and prior.get("to_id") == context.state.player_character_id:
			return apply(context.state, context.scenario_data, request)
		return Contract.fail("玩家直接操作必须使用当前玩家主体；代办由共同任务队列执行")
	if context.state.action_receipts.has(request.get("execution_id", "")):
		return apply(context.state, context.scenario_data, request)
	var transaction = Transaction.new()
	var preview := transaction.preview_command(context.state, "game_action", request)
	if not preview.get("ok", false):
		return preview
	var result: Dictionary = transaction.execute_command(context, transaction.build_command_envelope("game_action", request, preview.preview_token), func(working): return apply(working.state, working.scenario_data, request))
	if result.get("ok", false):
		if context.has_method("sync_scenario_player_identity"): context.sync_scenario_player_identity()
		else: context.scenario_data["player_character_id"] = context.state.player_character_id
	return result

# Only a bound game caller supplies the actor and execution identity. A model
# supplies the same action/parameter proposal used by the player assistant.
func execute_npc(context, bound_actor_id: String, selection: Dictionary, execution_id: String) -> Dictionary:
	var catalog = load("res://scripts/core/game_action_catalog.gd")
	var valid: Dictionary = catalog.validate_selection(selection)
	if not valid.ok: return valid
	if context == null or context.state == null or not context.state.character_states.has(bound_actor_id) or execution_id.is_empty(): return Contract.fail("NPC 操作缺少受信任主体或执行标识")
	var request := bind_npc_request(context.state, bound_actor_id, selection, execution_id)
	if context.state.action_receipts.has(execution_id): return apply(context.state, context.scenario_data, request)
	var transaction = Transaction.new()
	var preview: Dictionary = transaction.preview_command(context.state, "game_action", request)
	if not preview.ok: return preview
	return transaction.execute_command(context, transaction.build_command_envelope("game_action", request, preview.preview_token), func(working): return apply(working.state, working.scenario_data, request))

static func bind_npc_request(state, actor_id: String, selection: Dictionary, execution_id: String) -> Dictionary:
	return {"execution_id": execution_id, "request_id": execution_id, "actor_id": actor_id, "principal_id": actor_id, "executor_id": actor_id, "viewer_character_id": actor_id, "action_kind": selection.action_kind, "parameters": selection.parameters.duplicate(true), "target_refs": selection.target_refs.duplicate(true), "expected_state_revision": int(state.state_revision)}

# Internal daily/task operation. Caller runs inside the shared world transaction.
static func apply(state, data: Dictionary, request: Dictionary) -> Dictionary:
	var shape := validate_request(state, request)
	if not shape.get("ok", false):
		return shape
	var execution := str(request.execution_id)
	var semantic_request := request.duplicate(true)
	semantic_request.erase("expected_state_revision")
	semantic_request.erase("request_id")
	var fingerprint := str(Canonical.hash_value(semantic_request).get("hash", ""))
	if state.action_receipts.has(execution):
		var prior: Dictionary = state.action_receipts[execution]
		return {"ok": true, "code": "idempotent_replay", "result_ref": execution, "receipt": prior.duplicate(true)} if prior.input_hash == fingerprint else Contract.fail("执行标识已被另一请求使用")
	var principal := str(request.principal_id)
	var actor := str(request.actor_id)
	var executor := str(request.executor_id)
	var kind := str(request.action_kind)
	var params: Dictionary = request.parameters
	var authorization: Dictionary = state.action_authorizations.get(request.get("authorization_id", ""), {})
	# A personally approved plan may include the exact opening business policy.
	# Scope, saved step parameters and principal's account authority are checked below.
	if kind in Business.KINDS and kind not in ["authorize_business_management","allocate_regional_business_budget","set_portfolio_business_budget"] and not authorization.is_empty(): return Contract.fail("交接、副手及撤回须由资金经办主体本人确认")
	var reservation_id := ""
	var business_credit_review := {}
	if kind == "collect_estate_production" and executor != principal: return Contract.fail("原已付款订单须由具名遗产经办人本人现场接管")
	# Quote against this task's earmarked cash. The exact task, scope and remaining
	# reservation are validated below before any transfer can occur.
	if kind == "allocate_regional_business_budget" and not authorization.is_empty():
		reservation_id = str(authorization.reservation_refs.get(params.get("funding_account_id",""),""))
	var cost: Dictionary = preload("res://scripts/core/regional_business_budget_service.gd").cost_for(state,params,reservation_id) if kind == "allocate_regional_business_budget" else cost_for(state, kind, params, principal)
	if not cost.get("ok", false):
		return cost
	if authorization.is_empty():
		if principal != actor or actor != executor or request.get("task_id", "") != "":
			return Contract.fail("代办需要有效授权")
		if int(request.expected_state_revision) != int(state.state_revision):
			return Contract.fail("操作预览已变化，请重新查看")
	else:
		var tasks: Array = state.active_tasks.filter(func(task): return task.get("task_kind") == "management" and task.get("task_id") == request.get("task_id"))
		if tasks.size() != 1 or tasks[0].get("authorization_id") != authorization.authorization_id or tasks[0].get("executor_id") != executor or tasks[0].get("authorization_version") != authorization.version:
			return Contract.fail("动作缺少匹配的已授权任务")
		var steps: Array = tasks[0].steps.filter(func(step): return step.step_id == request.get("step_id"))
		if steps.size() != 1 or steps[0].execution_id != execution or steps[0].action_kind != kind or steps[0].parameters != params or steps[0].target_refs != request.target_refs:
			return Contract.fail("动作与获准任务步骤不一致")
		if authorization.status != "active" or authorization.principal_id != principal or not (authorization.delegate_ids as Array).has(executor) or actor != executor:
			return Contract.fail("授权已失效或执行人不在授权范围")
		if authorization.valid_until_day != null and int(state.current_day) > int(authorization.valid_until_day):
			return Contract.fail("授权已到约定期限")
		# Installing the already-approved operating policy is part of shop work.
		# Otherwise a newly hired full-time manager can open their shop but never
		# finish the last step of the same delegated startup plan.
		var workload=preload("res://scripts/core/character_workload_service.gd")
		var busy: bool=workload.occupied_today(state, executor, "", Succession.effective_principal(state, authorization), "pawnshop" if kind in Pawnshop.KINDS + Retail.KINDS + Manufacturing.KINDS + Farming.KINDS + Modeled.KINDS + ["authorize_business_management"] else "management")
		if busy and kind=="set_portfolio_business_budget": busy=workload.occupied_today(state,executor,"",Succession.effective_principal(state,authorization),"pawnshop")
		if busy:
			return {"ok": false, "code": "executor_busy_today", "error": "经办人今日有任职或其他事务占用；请等候空闲日或安排交接"}
		if not authorization.scope.action_kinds.has(kind):
			return Contract.fail("动作不在授权范围")
		for target in request.target_refs:
			if not authorization.scope.target_refs.has(target):
				return Contract.fail("对象不在授权范围：" + str(target))
		if authorization.has("business_policy"):
			var permitted := Business.guard(state,authorization,kind,params,executor)
			if not permitted.ok: return permitted
			business_credit_review = permitted.get("credit_review",{}).duplicate(true)
		if int(cost.amount) > 0:
			reservation_id = str(authorization.reservation_refs.get(cost.account_id, ""))
			if reservation_id.is_empty() or int(state.resource_reservations.get(reservation_id, {}).get("remaining_amount", 0)) < int(cost.amount):
				return Contract.fail("本授权的累计剩余额度不足，子任务不得另领预算")
	var estate_continuation: Dictionary = Estate.Continuation.proof(state, request)
	if not estate_continuation.is_empty() and int(state.character_states[executor].get("relationships", {}).get(principal, 0)) < 0:
		return {"ok": false, "code": "awaiting_delivery", "error": "原受托人目前不愿续办；原款项、合同及任务保留等待处理。"}
	if not authorization.is_empty(): principal = Succession.effective_principal(state, authorization)
	for id in [principal, executor]:
		if id == principal and principal != executor and not estate_continuation.is_empty(): continue
		if state.character_states[id].get("status") in ["dead", "deceased", "executed", "missing", "imprisoned", "departed", "exiled", "unreachable"]:
			if state.character_states[id].get("status") == "imprisoned" and kind == "petition_criminal_case" and state.accountability_cases.get(params.get("case_id"), {}).get("subject_ids", []).has(id): continue
			return Contract.fail("委托人或执行人已无法继续办理")
	var place := str(state.character_states[executor].get("location_id", ""))
	var expected_location := Pawnshop.location_for(state, kind, params) if kind in Pawnshop.KINDS else str(state.office_state.get(params.get("office_id"), {}).get("scope_ref", {}).get("entity_id", ""))
	if kind == ControlDispatch.KIND: expected_location = place
	if kind in Social.KINDS: expected_location = place
	if kind == "cancel_management_task": expected_location = place
	if kind in Gifts.KINDS: expected_location = place
	if kind in Criminal.KINDS: expected_location = place
	if kind == Visit.KIND: expected_location = place
	# Issuing an appointment is done at the principal's seat; it does not move the appointee.
	if kind in Official.KINDS: expected_location = str(state.character_states[principal].get("location_id", ""))
	if kind in Manufacturing.KINDS: expected_location = Pawnshop.location_for(state,kind,params)
	if kind in Modeled.KINDS: expected_location = Pawnshop.location_for(state,kind,params)
	if kind in Farming.KINDS: expected_location = Pawnshop.location_for(state,kind,params)
	if kind in Retail.KINDS: expected_location = Pawnshop.location_for(state,kind,params)
	if kind in Business.KINDS:
		# A preapproved local startup grant is carried out at the shop, even if its owner travels.
		expected_location = Pawnshop.location_for(state,kind,params) if kind=="authorize_business_management" and not authorization.is_empty() else str(state.character_states[principal].get("location_id", ""))
		if kind == "allocate_regional_business_budget": expected_location = str(params.location_id)
	if kind in Grain.KINDS: expected_location = str(state.character_states[principal].get("location_id", ""))
	if kind in PlayerSuccession.KINDS:
		if not authorization.is_empty(): return Contract.fail("玩家身份接续须本人确认，不能由任务代办")
		expected_location = str(PlayerSuccession.rule_for(state, str(params.get("succession_id", ""))).get("location_id", ""))
	if kind in Partition.KINDS: expected_location = str(Partition.rule_for(state, str(params.get("partition_id", ""))).get("location_id", ""))
	if kind in Estate.KINDS: expected_location = str(Estate.rule_for(state, str(params.get("estate_id", ""))).get("location_id", ""))
	if kind == "record_personal_estate": expected_location = place
	if kind in Succession.KINDS: expected_location = str(Succession.definition(state, str(params.get("clan_id", ""))).get("location_id", ""))
	if kind in Marriage.KINDS: expected_location = str(Marriage.match_for(state, str(params.get("match_id", ""))).get("location_id", ""))
	if kind in Envoy.KINDS: expected_location = str(state.character_states[principal].get("location_id", ""))
	if kind in Land.KINDS + Construction.KINDS: expected_location = str(state.management_assets.get(params.get("land_id",""),{}).get("location_id",""))
	if kind in Lifecycle.KINDS:expected_location=str(state.management_assets.get(params.get("shop_id"),{}).get("location_id",""))
	if kind in Property.KINDS:expected_location=str(state.management_assets.get(params.get("building_id"),{}).get("location_id",""))
	if kind in Items.KINDS: expected_location = str(state.management_assets.get(params.get("item_id"), {}).get("location_id", ""))
	if kind in PublicWorks.KINDS: expected_location = PublicWorks.location_for(state, kind, params)
	if kind in LocalFiscal.KINDS: expected_location = LocalFiscal.location(state)
	if kind in Fiscal.KINDS: expected_location = Fiscal.location_for(state, params)
	if kind in Assessment.KINDS: expected_location = Assessment.location_for(state, params)
	if kind in SchoolSupply.KINDS: expected_location = SchoolSupply.location_for(state, params)
	if kind in ExamJourney.KINDS: expected_location = ExamJourney.location_for(state, params)
	if kind in LivingAid.KINDS: expected_location = LivingAid.location_for(state, params)
	if kind in Education.KINDS: expected_location = Education.location_for(state, params)
	if kind in Production.KINDS: expected_location = Production.location_for(state, kind, params)
	if kind in Search.KINDS: expected_location = Search.location_for(state, kind, params)
	if kind == "buy_food": expected_location = str(state.management_assets.get(params.get("stall_id"), {}).get("location_id", ""))
	if kind != "transfer_cash" and place.trim_suffix("_node") != expected_location.trim_suffix("_node"):
		return Contract.fail("经办人尚未到履职地")
	var result := {}
	if kind == "cancel_management_task": result = load("res://scripts/core/action_authorization_service.gd").cancel_actor_plan(state, params.task_id, principal)
	elif kind in Social.KINDS: result = Social.apply(state, data, kind, params, principal, execution, reservation_id)
	if kind in Gifts.KINDS: result = Gifts.apply(state, kind, params, principal, execution)
	if kind in Criminal.KINDS: result = Criminal.apply(state, kind, params, principal, execution)
	if kind == ControlDispatch.KIND: result = ControlDispatch.apply(state,params,principal,executor)
	if kind == Visit.KIND: result = Visit.apply(state,params,principal,executor,execution)
	if kind in Modeled.KINDS:
		result = Modeled.apply(state,kind,params,principal,execution,reservation_id)
	elif kind in Manufacturing.KINDS:
		result = Manufacturing.apply(state,kind,params,principal,executor,execution,reservation_id)
	if kind in Farming.KINDS:
		result = Farming.apply(state,kind,params,principal,executor,execution,reservation_id)
	if kind in Retail.KINDS:
		result = Retail.apply(state,kind,params,principal,executor,execution,reservation_id)
	elif kind in Lifecycle.KINDS:
		result=Lifecycle.apply(state,kind,params,principal,execution,reservation_id)
	elif kind in Construction.KINDS:
		result = Construction.apply(state,kind,params,principal,execution,reservation_id)
	elif kind in Land.KINDS:
		result = Land.apply(state,kind,params,principal,execution,reservation_id)
	elif kind in Official.KINDS:
		result = Official.apply(state, data, kind, params, principal, execution)
	elif kind in Grain.KINDS:
		result = Grain.apply(state, params, principal, execution, kind)
	elif kind == "buy_food":
		result = Food.apply(state, params, principal, execution, reservation_id)
	elif kind in Search.KINDS:
		result = Search.apply(state, kind, params, principal, executor, execution, str(request.get("authorization_id", "")))
	elif kind in Items.KINDS:
		result = Items.apply(state, kind, params, principal, execution)
	elif kind in PublicWorks.KINDS:
		result = PublicWorks.apply(state, kind, params, principal, execution, reservation_id)
	elif kind in Initiative.KINDS:
		result = Initiative.apply(state, kind, params, principal, execution)
	elif kind in LocalFiscal.KINDS:
		result = LocalFiscal.apply(state, kind, params, principal, execution, reservation_id)
	elif kind in Fiscal.KINDS:
		result = Fiscal.apply(state, params, principal, execution, reservation_id)
	elif kind in Assessment.KINDS:
		result = Assessment.apply(state, kind, params, principal, execution, reservation_id)
	elif kind in SchoolSupply.KINDS:
		result = SchoolSupply.apply(state, kind, params, principal, execution, reservation_id)
	elif kind in PlayerSuccession.KINDS:
		result = PlayerSuccession.apply(state, data, params, principal, execution)
	elif kind in Partition.KINDS:
		result = Partition.apply(state, data, params, principal, execution, reservation_id)
	elif kind in Estate.KINDS:
		result = Estate.apply(state, kind, params, principal, execution)
	elif kind in Succession.KINDS:
		result = Succession.apply(state, params, principal, execution, kind)
	elif kind in Marriage.KINDS:
		result = Marriage.apply(state, kind, params, principal, execution, reservation_id)
	elif kind in Envoy.KINDS:
		result = Envoy.apply(state, kind, params, principal, execution, reservation_id)
	elif kind in ExamJourney.KINDS:
		result = ExamJourney.apply(state, kind, params, principal, execution, reservation_id)
	elif kind in LivingAid.KINDS:
		result = LivingAid.apply(state, params, principal, execution, reservation_id)
	elif kind in Education.KINDS:
		result = Education.apply(state, kind, params, principal, execution, reservation_id)
	elif kind in Production.KINDS:
		result = Production.apply(state, kind, params, principal, execution, reservation_id, estate_continuation)
	elif kind in Business.KINDS:
		result = Business.apply(state,kind,params,principal,execution,data,reservation_id,executor)
	elif kind in Property.KINDS:result=Property.apply(state,kind,params,principal,execution,reservation_id,data)
	elif kind in Pawnshop.KINDS:
		result = Pawnshop.apply(state, kind, params, principal, execution, reservation_id)
	elif kind == "hire_family":
		var input := {"office_id": params.office_id, "candidate_id": params.get("candidate_id", ""), "actor_id": principal, "remuneration_terms": state.office_state[params.office_id].remuneration_terms.duplicate(true), "reservation_id": reservation_id}
		result = Family.appoint(state, data, input, execution)
	elif kind == "hire_family_from_pool":
		result = Family.appoint_from_pool(state, data, params, principal, execution, reservation_id)
	elif kind == "resign_family":
		if state.office_state[params.office_id].get("holder_id") != principal:
			return Contract.fail("辞任须由实际任职者本人提出")
		result = Family.dismiss(state, params.office_id, execution)
	elif kind == "pay_employment_debt":
		result = Family.pay_debt(state, str(params.get("contract_id", "")), principal, execution, reservation_id)
	elif kind in ["dismiss_family", "offer_family_wage"]:
		if not Family.authority(state, params.office_id, principal):
			return Contract.fail("委托人没有该职位的雇用权")
		if kind == "dismiss_family":
			result = Family.dismiss(state, params.office_id, execution)
		else:
			if not str(state.office_state[params.office_id].holder_id).is_empty():
				return Contract.fail("在任工资须双方重议")
			state.office_state[params.office_id].remuneration_terms.amount = int(params.amount)
			result = {"ok": true, "result_ref": params.office_id}
	elif kind == "transfer_cash":
		var account: Dictionary = state.resource_accounts[params.source_account_id]
		if place.trim_suffix("_node") != Accounts.new().location(state, account.account_id).trim_suffix("_node"):
			return Contract.fail("经办人不在交割地点")
		var capital_shop: Dictionary=state.management_assets.get(params.get("business_capital_return_shop_id"),{})
		if params.has("business_capital_return_shop_id") and (capital_shop.get("premises_kind")!="retired" or capital_shop.get("account_id")!=params.source_account_id or state.resource_accounts[params.destination_account_id].owner_ref!=capital_shop.get("owner_ref")):return Contract.fail("撤出旧店资金须有真实已移交场所及同产权收款账户")
		result = Accounts.new().apply(state, "transfer", {"execution_id": execution, "source_account_id": params.source_account_id, "destination_account_id": params.destination_account_id, "amount": params.amount, "actor_id": principal, "reason_ref": capital_shop.asset_id if params.has("business_capital_return_shop_id") else "action:" + execution, "reservation_id": reservation_id})
	if not result.get("ok", false):
		return result
	Fiscal.reconcile(state)
	var effects: Array = [str(result.result_ref)]
	if result.has("effect_refs"):effects=result.effect_refs.duplicate()
	var journal_refs: Array = []
	if int(cost.amount) > 0:
		journal_refs.append("wage:" + execution if kind in ["hire_family", "hire_family_from_pool"] else execution)
	if result.has("journal_refs"):
		journal_refs = result.journal_refs.duplicate()
	var receipt := {"execution_id": execution, "request_id": request.request_id, "status": "committed", "reason_code": "applied", "effect_refs": effects, "journal_refs": journal_refs, "authorization_id": request.get("authorization_id", ""), "task_id": request.get("task_id", ""), "step_id": request.get("step_id", ""), "executor_id": executor, "day": int(state.current_day), "input_hash": fingerprint, "state_revision_after": int(state.state_revision) + 1, "visible_summary": "已办理：" + kind}
	state.action_receipts[execution] = receipt
	if kind in Social.KINDS:
		receipt["social_record"] = {"result_ref": result.result_ref, "outcome": result.get("outcome", "recorded")}
		receipt.visible_summary = result.get("visible_summary", receipt.visible_summary)
		if result.get("outcome") == "blocked": receipt.reason_code = "blocked"
	if result.has("regional_visit"): receipt["regional_visit"] = result.regional_visit.duplicate(true)
	if kind == ControlDispatch.KIND: receipt.visible_summary = "控制消息已寄出，送达后对方才能获知。"
	if kind == Visit.KIND:
		receipt.visible_summary = str(result.get("visible_summary","已启程"))
		receipt["regional_visit"]={"person_id":principal,"destination":params.destination_id,"origin":place}
	if result.has("business_office_creation"): receipt["business_office_creation"] = result.business_office_creation.duplicate(true)
	if result.has("land_lease_offer"):receipt["land_lease_offer"]=result.land_lease_offer.duplicate(true)
	if result.has("land_share_offer"):receipt["land_share_offer"]=result.land_share_offer.duplicate(true)
	if result.has("land_share_consent"):receipt["land_share_consent"]=result.land_share_consent.duplicate(true)
	if result.has("business_wage_amendment"):receipt["business_wage_amendment"]=result.business_wage_amendment.duplicate(true)
	if result.has("business_profit_policy"):receipt["business_profit_policy"]=result.business_profit_policy.duplicate(true)
	if result.has("business_review"):receipt["business_review"]=result.business_review.duplicate(true)
	if result.has("estate_property_offer"):receipt["estate_property_offer"]=result.estate_property_offer.duplicate(true)
	if not business_credit_review.is_empty(): receipt["business_credit_review"] = business_credit_review
	if result.has("business_policy"): receipt["business_policy"] = result.business_policy.duplicate(true)
	if result.has("business_budget_change"): receipt["business_budget_change"]=result.business_budget_change.duplicate(true)
	if result.has("business_payroll_change"):receipt["business_payroll_change"]=result.business_payroll_change.duplicate(true)
	if result.has("business_strategy_change"):
		receipt["business_strategy_change"]=result.business_strategy_change.duplicate(true)
		receipt.visible_summary=str(result.visible_summary)
	if result.has("business_staff_change"): receipt["business_staff_change"] = result.business_staff_change.duplicate(true)
	if result.has("business_handover"): receipt["business_handover"] = result.business_handover.duplicate(true)
	if result.has("official_record"): receipt["official_record"] = result.official_record.duplicate(true)
	if result.has("grain_order"): receipt["grain_order"] = result.grain_order.duplicate(true)
	if result.has("initiative_record"): receipt["initiative_record"] = result.initiative_record.duplicate(true)
	if result.has("initiative_response"): receipt["initiative_response"] = result.initiative_response.duplicate(true)
	if result.has("fiscal_response"): receipt["fiscal_response"] = result.fiscal_response.duplicate(true)
	if result.has("levy_order"): receipt["levy_order"] = result.levy_order.duplicate(true)
	if result.has("clan_handover"): receipt["clan_handover"] = result.clan_handover.duplicate(true)
	if result.has("player_succession"): receipt["player_succession"] = result.player_succession.duplicate(true)
	if result.has("estate_request"): receipt["estate_request"] = result.estate_request.duplicate(true)
	if result.has("estate_collection"): receipt["estate_collection"] = result.estate_collection.duplicate(true)
	if result.has("estate_work"): receipt["estate_work"] = result.estate_work
	if result.has("estate_resources"): receipt["estate_resources"] = result.estate_resources.duplicate(true)
	if result.has("estate_continuations"): receipt["estate_continuations"] = result.estate_continuations.duplicate(true)
	if not estate_continuation.is_empty(): receipt["estate_continuation"] = estate_continuation.duplicate(true)
	if result.has("partition_record"): receipt["partition_record"] = result.partition_record.duplicate(true)
	if authorization.has("clan_mandate"): receipt["clan_mandate"] = authorization.clan_mandate.duplicate(true)
	if result.has("marriage_record"): receipt["marriage_record"] = result.marriage_record.duplicate(true)
	if result.has("mission_order"): receipt["mission_order"] = result.mission_order.duplicate(true)
	if result.has("visible_summary"): receipt.visible_summary = result.visible_summary
	Initiative.reconcile(state)
	var response := {"ok": true, "result_ref": execution, "receipt": receipt.duplicate(true)}
	if kind in Official.KINDS: response["domain_result"] = result.duplicate(true)
	return response

static func cost_for(state, kind: String, params: Dictionary, principal: String = "") -> Dictionary:
	if kind == "cancel_management_task":
		if not params.get("task_id") is String or params.task_id.is_empty(): return Contract.fail("撤回须引用实际任务")
		return {"ok": true, "amount": 0, "account_id": ""}
	if kind in Social.KINDS: return Social.cost_for(state, kind, params)
	if kind in Gifts.KINDS: return Gifts.cost_for(state, kind, params)
	if kind in Criminal.KINDS: return Criminal.cost_for(state, kind, params)
	if kind == ControlDispatch.KIND: return {"ok":true,"amount":0,"account_id":""}
	if kind == Visit.KIND: return Visit.cost_for(state,params,principal)
	if kind in Modeled.KINDS: return Modeled.cost_for(state,kind,params)
	if kind in Manufacturing.KINDS: return Manufacturing.cost_for(state,kind,params)
	if kind in Farming.KINDS: return Farming.cost_for(state,kind,params)
	if kind in Retail.KINDS: return Retail.cost_for(state,kind,params)
	if kind in Business.KINDS: return Business.cost_for(state,kind,params)
	if kind in Property.KINDS:return Property.cost_for(state,kind,params)
	if kind in Construction.KINDS: return Construction.cost_for(state,kind,params)
	if kind in Lifecycle.KINDS:return Lifecycle.cost_for(state,kind,params)
	if kind in Land.KINDS: return Land.cost_for(state,kind,params)
	if kind == "hire_family_from_pool": return Family.pool_cost(state, params)
	if kind in Initiative.KINDS: return Initiative.cost_for(state, kind, params)
	if kind in LocalFiscal.KINDS: return LocalFiscal.cost_for(state, kind, params)
	if kind in PlayerSuccession.KINDS: return PlayerSuccession.cost_for(state, kind, params)
	if kind in Partition.KINDS: return Partition.cost_for(state, kind, params)
	if kind in Estate.KINDS: return Estate.cost_for(state, kind, params)
	if kind in Succession.KINDS: return Succession.cost_for(state, kind, params)
	if kind in Marriage.KINDS: return Marriage.cost_for(state, kind, params)
	if kind in Envoy.KINDS: return Envoy.cost_for(state, kind, params)
	if kind in Grain.KINDS: return Grain.cost_for(state, kind, params)
	if kind in Assessment.KINDS: return Assessment.cost_for(state, kind, params)
	if kind in SchoolSupply.KINDS: return SchoolSupply.cost_for(state, kind, params)
	if kind in ExamJourney.KINDS: return ExamJourney.cost_for(state, kind, params)
	if kind in LivingAid.KINDS: return LivingAid.cost_for(state, params)
	if kind in Education.KINDS: return Education.cost_for(state, kind, params)
	if kind in Fiscal.KINDS: return Fiscal.cost_for(state, params)
	if kind in Official.KINDS: return Official.cost_for(state, kind, params)
	if kind == "buy_food": return Food.cost_for(state, params)
	if kind in Search.KINDS: return Search.cost_for(state, kind, params)
	if kind in PublicWorks.KINDS: return PublicWorks.cost_for(state, kind, params)
	if kind in Production.KINDS: return Production.cost_for(state, kind, params)
	if kind in Items.KINDS: return Items.cost_for(state, kind, params)
	if kind in Pawnshop.KINDS:
		return Pawnshop.cost_for(state, kind, params)
	if kind not in KINDS:
		return Contract.fail("该动作尚无可执行规则：" + kind)
	if kind == "transfer_cash":
		if not Contract.amount(params.get("amount"), true) or not state.resource_accounts.has(params.get("source_account_id")) or not state.resource_accounts.has(params.get("destination_account_id")):
			return Contract.fail("转账缺少真实账户或有效金额")
		if state.resource_accounts[params.source_account_id].unit_id != "cash_unit" or state.resource_accounts[params.destination_account_id].unit_id != "cash_unit": return Contract.fail("现金划转不能使用口粮等其他实物库存")
		return {"ok": true, "account_id": params.source_account_id, "amount": int(params.amount)}
	if not Family.is_family(state, str(params.get("office_id", ""))):
		return Contract.fail("未找到家族职位；朝廷任用须通过正式任命程序")
	if kind == "pay_employment_debt":
		var debt: Dictionary = state.economic_contracts.get(params.get("contract_id", ""), {})
		if debt.get("contract_kind") != "employment" or debt.get("office_id") != params.office_id or debt.get("status") != "ended_unpaid" or not Contract.amount(debt.get("arrears"), true):
			return Contract.fail("未找到该职位已结束雇约的欠薪")
		return {"ok": true, "account_id": debt.remuneration_terms.account_id, "amount": int(debt.arrears)}
	if kind == "offer_family_wage" and not Contract.amount(params.get("amount"), true):
		return Contract.fail("薪酬必须为正整数")
	var terms: Dictionary = state.office_state[params.office_id].remuneration_terms
	return {"ok": true, "account_id": terms.account_id, "amount": int(terms.amount) if kind == "hire_family" else 0}

static func validate_request(state, request: Dictionary) -> Dictionary:
	for field in ["execution_id", "request_id", "actor_id", "principal_id", "executor_id", "action_kind"]:
		if not request.get(field) is String or str(request[field]).is_empty():
			return Contract.fail("动作缺少字段：" + field)
	for field in ["actor_id", "principal_id", "executor_id"]:
		if not state.character_states.has(request[field]):
			return Contract.fail("动作引用缺失人物：" + field)
	if not request.get("parameters") is Dictionary or not request.get("target_refs") is Array or not Contract.amount(request.get("expected_state_revision")):
		return Contract.fail("动作参数、目标或版本无效")
	var params: Dictionary = request.parameters
	if request.action_kind == "hire_family_from_pool":
		var pool := Family.pool_cost(state, params)
		if not pool.ok: return pool
		for id in params.candidate_ids:
			if not request.target_refs.has(id): return Contract.fail("每名备选人物必须在明确获准范围内")
	var target := str(params.get("destination_account_id", "")) if request.action_kind == "transfer_cash" else str(params.get("office_id", ""))
	if request.action_kind in Social.KINDS: target = str(params.get("agreement_id", ""))
	if request.action_kind == "cancel_management_task": target = str(params.get("task_id", ""))
	if request.action_kind in Gifts.KINDS: target = str(params.get("delivery_id", ""))
	if request.action_kind in Criminal.KINDS: target = str(params.get("case_id", ""))
	if request.action_kind == Visit.KIND: target = str(params.get("destination_id",""))
	if request.action_kind == ControlDispatch.KIND:
		target = str(params.get("fact_id",""))
		if not request.target_refs.has(params.get("recipient_id")): return Contract.fail("寄送须明确收件人")
	if request.action_kind in Initiative.KINDS and not request.target_refs.has(params.get("initiative_id")): return Contract.fail("幕僚请求必须包含在明确动作范围")
	if request.action_kind in ["remit_local_levy", "pay_local_levy"]:
		if not request.target_refs.has(params.get("levy_id")) or not request.target_refs.has(params.get("person_id")): return Contract.fail("逐人缴纳或减免须明确征收和人物范围")
	if request.action_kind in PlayerSuccession.KINDS: target = str(params.get("succession_id", ""))
	if request.action_kind in Partition.KINDS: target = str(params.get("partition_id", ""))
	if request.action_kind in Estate.KINDS: target = str(params.get("estate_id", ""))
	if request.action_kind == "collect_estate_production" and not request.target_refs.has(params.get("order_id")): return Contract.fail("接管须明确原已付款订单")
	if request.action_kind in Succession.KINDS:
		target = str(params.get("clan_id", ""))
		if not request.target_refs.has(params.get("successor_id")): return Contract.fail("移交必须明确接任者")
	if request.action_kind in Marriage.KINDS: target = str(params.get("match_id", ""))
	if request.action_kind in Envoy.KINDS:
		target = str(params.get("target_depot_id", ""))
		if not request.target_refs.has(params.get("person_id")): return Contract.fail("差遣人物必须包含在明确获准范围")
	if request.action_kind in Grain.KINDS:
		target = str(params.get("source_depot_id", ""))
		if not request.target_refs.has(params.get("target_depot_id")): return Contract.fail("调粮接收仓必须包含在明确获准范围")
	if request.action_kind in Land.KINDS + Construction.KINDS: target = str(params.get("land_id",""))
	if request.action_kind in Lifecycle.KINDS:target=str(params.get("shop_id",""))
	if request.action_kind in Property.KINDS:target=str(params.get("building_id",""))
	if request.action_kind in Business.KINDS + Retail.KINDS + Manufacturing.KINDS + Farming.KINDS + Modeled.KINDS: target = str(params.get("shop_id",""))
	if request.action_kind=="allocate_regional_business_budget":
		target=str(params.get("funding_account_id",""))
		if not params.get("allocations") is Array: return Contract.fail("地区预算须列明产业范围")
		for row in params.allocations:
			if not row is Dictionary or not request.target_refs.has(row.get("shop_id")): return Contract.fail("各产业须包含在本次批准的预算范围内")
	if request.action_kind=="set_regional_business_budget":
		target=str(params.get("location_id",""))
		if not params.get("allocations") is Array: return Contract.fail("地区经营预算须明确产业范围")
		for row in params.allocations:
			if not row is Dictionary or not request.target_refs.has(row.get("shop_id")): return Contract.fail("每家产业须包含在批准的预算范围内")
	if request.action_kind=="set_portfolio_business_budget":
		if not params.get("owner_ref") is Dictionary or not params.get("regions") is Array: return Contract.fail("跨州经营预算须明确产权和地区范围")
		target=str(params.owner_ref.get("entity_id",""))
		for region in params.regions:
			if not region is Dictionary or not request.target_refs.has(region.get("location_id")) or not region.get("allocations") is Array: return Contract.fail("各州须包含在批准的总预算范围内")
			for row in region.allocations:
				if not row is Dictionary or not request.target_refs.has(row.get("shop_id")): return Contract.fail("每家产业须包含在跨州预算授权范围内")
	if request.action_kind in Items.KINDS: target = str(params.get("item_id", ""))
	if request.action_kind in Fiscal.KINDS: target = str(params.get("case_id", ""))
	if request.action_kind in Education.KINDS + Assessment.KINDS + SchoolSupply.KINDS + LivingAid.KINDS + ExamJourney.KINDS: target = str(params.get("school_id", ""))
	if request.action_kind in PublicWorks.KINDS: target = str(params.get("canal_id", "")) if request.action_kind == "start_public_work" else str(params.get("order_id", ""))
	if request.action_kind in Production.KINDS: target = str(params.get("workshop_id", "")) if request.action_kind == "commission_production" else str(params.get("order_id", ""))
	if request.action_kind in Search.KINDS: target = str(params.get("location_id", "")) if request.action_kind == "start_character_search" else str(params.get("search_id", ""))
	if request.action_kind == "buy_food": target = str(params.get("stall_id", ""))
	if request.action_kind in Pawnshop.KINDS:
		target = str(params.get("building_id", "")) if request.action_kind in ["rent_shop","establish_owned_pawnshop","establish_owned_retail","establish_owned_manufacturing","establish_owned_farm","establish_owned_modeled"] else str(params.get("shop_id", ""))
	if target.is_empty() or not request.target_refs.has(target):
		return Contract.fail("动作目标与参数不一致")
	if request.action_kind == "send_exam_candidate" and not request.target_refs.has(params.get("student_id")): return Contract.fail("赴试人物必须在明确获准范围内")
	if request.action_kind in LivingAid.KINDS and not request.target_refs.has(params.get("student_id")): return Contract.fail("生活资助对象必须包含在获准范围")
	if request.action_kind == "give_item" and not request.target_refs.has(params.get("recipient_id")):
		return Contract.fail("赠予对象必须包含在获准目标中")
	if request.action_kind in Official.KINDS and not request.target_refs.has(params.get("candidate_id", params.get("holder_id"))):
		return Contract.fail("任免人物必须包含在获准目标中")
	return {"ok": true}
