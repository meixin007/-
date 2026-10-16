extends RefCounted
## Standing policy lives in the existing authorization; work uses its root task.
const KINDS := ["authorize_business_management","revoke_business_management","handover_business_management","appoint_business_deputy","remove_business_deputy","set_business_strategy","set_business_budget","set_regional_business_budget","distribute_business_surplus","allocate_regional_business_budget","set_portfolio_business_budget","set_business_payroll","renegotiate_business_wage","set_business_profit_sharing","coordinate_business_relations","audit_business"]
const Strategy = preload("res://scripts/core/business_strategy_rules.gd")
const OPERATIONS := ["issue_pawn_loan","redeem_pawn","dispose_pawn"]
const Contract = preload("res://scripts/core/management_state_contract.gd")
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Pawnshop = preload("res://scripts/core/pawnshop_service.gd")
const Segments = preload("res://scripts/core/management_plan_segments.gd")
const Family = preload("res://scripts/core/family_office_rules.gd")
const Staff = preload("res://scripts/core/business_staff_service.gd")
const Manufacturing = preload("res://scripts/core/manufacturing_business_service.gd")
const Farming = preload("res://scripts/core/managed_farming_service.gd")
const Retail = preload("res://scripts/core/retail_trading_service.gd")
const Modeled = preload("res://scripts/core/modeled_business_service.gd")
const Credit = preload("res://scripts/core/business_credit_assessment.gd")

static func operations(shop: Dictionary) -> Array:
	if shop.get("asset_kind")=="modeled_business": return Modeled.KINDS
	if shop.get("asset_kind")=="managed_farm": return Farming.KINDS
	return Manufacturing.KINDS if shop.get("asset_kind")=="manufacturing_shop" else Retail.KINDS if shop.get("asset_kind")=="retail_shop" else OPERATIONS

static func current(state, shop_id: String) -> Dictionary:
	for auth in state.action_authorizations.values():
		if auth.get("status")=="active" and auth.get("business_policy",{}).get("shop_id")==shop_id: return auth
	return {}

static func cost_for(state, kind: String, params: Dictionary) -> Dictionary:
	if kind in ["coordinate_business_relations","audit_business"]:return preload("res://scripts/core/business_review_service.gd").cost_for(state,kind,params)
	if kind=="set_business_profit_sharing":return preload("res://scripts/core/business_profit_sharing_service.gd").cost_for(state,params)
	if kind=="renegotiate_business_wage":return preload("res://scripts/core/business_wage_service.gd").cost_for(state,params)
	if kind=="set_portfolio_business_budget": return preload("res://scripts/core/portfolio_business_budget_plan.gd").cost_for(state,params)
	if kind=="set_regional_business_budget": return preload("res://scripts/core/regional_business_policy_service.gd").cost_for(state,params)
	if kind=="allocate_regional_business_budget": return preload("res://scripts/core/regional_business_budget_service.gd").cost_for(state,params)
	if kind=="distribute_business_surplus": return preload("res://scripts/core/business_distribution_service.gd").cost_for(state,params)
	if kind == "authorize_business_management" and not state.management_assets.has(params.get("shop_id")): return {"ok":false,"code":"asset_not_ready","error":"等待筹办中的产业开业"}
	if state.management_assets.get(params.get("shop_id"),{}).get("asset_kind") not in ["pawnshop","retail_shop","manufacturing_shop","managed_farm","modeled_business"]: return Contract.fail("未找到实际产业")
	if kind=="set_business_payroll":
		var auth := current(state,str(params.shop_id))
		if not params.get("payroll_from_shop") is bool or not params.get("expected_authorization_id") is String or auth.is_empty() or auth.authorization_id!=params.expected_authorization_id:return Contract.fail("发薪来源须明确选择本店资金或原雇主账户，并核对当前授权")
		return {"ok":true,"account_id":"","amount":0}
	if kind=="set_business_budget":
		if not Contract.amount(params.get("monthly_limit"),true) or not params.get("expected_authorization_id") is String: return Contract.fail("调整预算须明确月度限额与原授权")
		var auth := current(state,params.shop_id)
		if auth.is_empty() or auth.authorization_id!=params.expected_authorization_id: return Contract.fail("经营授权已变化，请重新查看预算")
		if int(params.monthly_limit)<month_spent(state,params.shop_id): return Contract.fail("新月度限额不能低于本月已经使用的额度")
		var shop: Dictionary=state.management_assets[params.shop_id]
		if int(params.monthly_limit)>Accounts.new().available(state,shop.account_id)-int(auth.business_policy.cash_floor): return Contract.fail("经营资金不足支持新的月度限额与保留现金，请先安排到账资金")
		return {"ok":true,"account_id":"","amount":0}
	if kind=="set_business_strategy":
		if state.management_assets[params.shop_id].asset_kind!="modeled_business" or not Strategy.valid(params.get("strategy")) or not params.get("expected_authorization_id") is String: return Contract.fail("请选择已接入分类经营的产业、有效方针与当前授权")
		return {"ok":true,"account_id":"","amount":0}
	if kind in ["appoint_business_deputy","remove_business_deputy"]:
		if not params.get("candidate_id") is String or not params.get("expected_authorization_id") is String: return Contract.fail("副手安排须明确人物与当前经营授权")
		if kind=="remove_business_deputy": return {"ok":true,"account_id":"","amount":0}
		if not Contract.amount(params.get("wage_amount"),true): return Contract.fail("聘任副手须约定实际薪酬")
		var shop: Dictionary = state.management_assets[params.shop_id]
		return {"ok":true,"account_id":state.office_state[shop.office_id].remuneration_terms.account_id,"amount":int(params.wage_amount)}
	if kind=="handover_business_management":
		if not Contract.amount(params.get("wage_amount"),true) or not params.get("candidate_id") is String or not params.get("expected_manager_id") is String: return Contract.fail("交接须明确接替人、首期工资与原负责人")
		var shop: Dictionary = state.management_assets[params.shop_id]
		return {"ok":true,"account_id":state.office_state[shop.office_id].remuneration_terms.account_id,"amount":int(params.wage_amount)}
	if kind=="authorize_business_management":
		if params.has("payroll_from_shop") and not params.payroll_from_shop is bool:return Contract.fail("本店发薪授权须为明确选择")
		if params.has("strategy") and not Strategy.valid(params.strategy): return Contract.fail("经营方针无效")
		if params.has("strategy") and state.management_assets[params.shop_id].asset_kind!="modeled_business": return Contract.fail("该产业暂用原专项经营规则，请通过资金限额调整经营")
		for field in ["monthly_limit","loan_limit","cash_floor"]:
			if not Contract.amount(params.get(field),field!="cash_floor"): return Contract.fail("经营授权需要有效的每月限额、单笔上限与现金底线")
		if int(params.loan_limit)>int(params.monthly_limit): return Contract.fail("单笔上限不能超过每月限额")
	return {"ok":true,"account_id":"","amount":0}

static func apply(state, kind: String, params: Dictionary, principal: String, execution: String, data: Dictionary = {}, reservation_id: String = "", executor: String = "") -> Dictionary:
	if kind in ["coordinate_business_relations","audit_business"]:return preload("res://scripts/core/business_review_service.gd").apply(state,kind,params,principal,execution)
	if kind=="set_business_profit_sharing":return preload("res://scripts/core/business_profit_sharing_service.gd").apply(state,params,principal,execution)
	if kind=="renegotiate_business_wage":return preload("res://scripts/core/business_wage_service.gd").apply(state,data,params,principal,execution)
	if kind=="set_portfolio_business_budget": return preload("res://scripts/core/portfolio_business_budget_plan.gd").apply(state,data,params,principal,execution)
	if kind=="set_regional_business_budget": return preload("res://scripts/core/regional_business_policy_service.gd").apply(state,data,params,principal,execution)
	if kind=="allocate_regional_business_budget": return preload("res://scripts/core/regional_business_budget_service.gd").apply(state,params,principal,execution,reservation_id,executor)
	if kind=="distribute_business_surplus": return preload("res://scripts/core/business_distribution_service.gd").apply(state,params,principal,execution)
	var shop: Dictionary = state.management_assets[params.shop_id]
	if not Accounts.new().can_operate(state,shop.account_id,principal): return Contract.fail("无权安排该产业资金与经办人")
	if kind in ["appoint_business_deputy","remove_business_deputy"]: return _change_deputy(state,data,shop,params,principal,execution,kind)
	if kind=="handover_business_management": return _handover(state,data,shop,params,principal,execution)
	var prior := current(state,shop.asset_id)
	if kind=="set_business_payroll":
		var checked := cost_for(state,kind,params)
		if not checked.ok:return checked
		if state.office_state.get(shop.office_id,{}).get("holder_id")!=prior.business_policy.manager_id:return Contract.fail("负责人已变化，请先办理交接")
		var agreed: Dictionary=prior.business_policy.duplicate(true)
		agreed["payroll_from_shop"]=params.payroll_from_shop
		var revoked: Dictionary=apply(state,"revoke_business_management",{"shop_id":shop.asset_id},principal,execution+":revoke",data)
		if not revoked.ok:return revoked
		var changed: Dictionary=_grant(state,shop,agreed,principal,execution)
		changed["business_payroll_change"]={"previous_authorization_id":prior.authorization_id,"payroll_from_shop":params.payroll_from_shop}
		changed["visible_summary"]="已批准从本店资金支付原约定工资，保留现金底线及其他任务预留；首期工资和雇约保留。" if params.payroll_from_shop else "已恢复原雇主账户发薪；异地工资仍需实际运款交割。"
		return changed
	if kind=="set_business_budget":
		var checked := cost_for(state,kind,params)
		if not checked.ok: return checked
		# Changing a ceiling does not schedule another work shift for the manager.
		if state.office_state.get(shop.office_id,{}).get("holder_id")!=prior.business_policy.manager_id: return Contract.fail("负责人已变化，请先完成经营交接")
		var agreed: Dictionary=prior.business_policy.duplicate(true)
		agreed.monthly_limit=int(params.monthly_limit)
		agreed.loan_limit=mini(int(agreed.loan_limit),int(params.monthly_limit))
		var revoked: Dictionary=apply(state,"revoke_business_management",{"shop_id":shop.asset_id},principal,execution+":revoke",data)
		if not revoked.ok: return revoked
		var changed: Dictionary=_grant(state,shop,agreed,principal,execution)
		changed["business_budget_change"]={"previous_authorization_id":prior.authorization_id,"monthly_limit":int(params.monthly_limit)}
		changed["visible_summary"]="已调整经营月度限额为%d；本月已用额度保留，不移动资金。" % int(params.monthly_limit)
		return changed
	if kind=="set_business_strategy":
		if prior.is_empty() or prior.authorization_id!=params.expected_authorization_id: return Contract.fail("经营授权已变化，请刷新后调整方针")
		var ready: Dictionary=Pawnshop._ready_to_trade(state,shop)
		if not ready.ok: return ready
		var agreed: Dictionary=prior.business_policy.duplicate(true)
		agreed["strategy"]=params.strategy
		var revoked: Dictionary=apply(state,"revoke_business_management",{"shop_id":shop.asset_id},principal,execution+":revoke",data)
		if not revoked.ok: return revoked
		var changed: Dictionary=_grant(state,shop,agreed,principal,execution)
		changed["business_strategy_change"]={"previous_authorization_id":prior.authorization_id,"strategy":params.strategy}
		changed["visible_summary"]=Strategy.success_message(params.strategy)
		return changed
	if kind=="revoke_business_management":
		if prior.is_empty(): return Contract.fail("该产业没有持续经营授权")
		prior.status = "revoked"
		prior.version += 1
		for task in state.active_tasks.duplicate():
			if task.get("authorization_id")!=prior.authorization_id: continue
			task.status = "cancelled"
			task["completed_day"] = int(state.current_day)
			state.completed_tasks.append(task)
			state.active_tasks.erase(task)
		for ref in prior.reservation_refs.values():
			var released := Accounts.new().apply(state,"release",{"reservation_id":ref,"actor_id":principal})
			if not released.ok: return released
		return {"ok":true,"result_ref":prior.authorization_id,"visible_summary":"已撤回自动经营；既有借据、款项和必要义务保留。"}
	if not prior.is_empty(): return Contract.fail("已有持续授权；修改条款须先撤回原授权")
	if shop.status!="open": return Contract.fail("请先落实负责人、设施和本钱并开业")
	var ready := Pawnshop._ready_to_trade(state,shop)
	if not ready.ok: return ready
	return _grant(state,shop,params,principal,execution)

static func _grant(state, shop: Dictionary, params: Dictionary, principal: String, execution: String, absent_manager: String = "") -> Dictionary:
	var manager: String = state.office_state[shop.office_id].holder_id if absent_manager=="" else absent_manager
	var willing: Dictionary=preload("res://scripts/core/business_personnel_conditions.gd").accepts(state,manager,principal)
	if not willing.ok:return willing
	var policy := {"shop_id":shop.asset_id,"manager_id":manager,"monthly_limit":int(params.monthly_limit),"loan_limit":int(params.loan_limit),"cash_floor":int(params.cash_floor),"grant_execution":execution}
	if params.has("strategy"): policy["strategy"]=params.strategy
	if params.has("payroll_from_shop"):policy["payroll_from_shop"]=params.payroll_from_shop
	var deputy := Staff.terms(state,shop.asset_id)
	if not deputy.is_empty(): policy["deputy"] = deputy
	var id := "business-auth:"+execution
	var task_id := "business-task:"+execution
	var auth := {"authorization_id":id,"principal_id":principal,"delegate_id":manager,"delegate_ids":[manager],"scope":{"action_kinds":operations(shop).duplicate(),"target_refs":[shop.asset_id],"allow_subdelegation":false},"resource_limits":[],"reservation_refs":{},"root_task_id":task_id,"version":1,"status":"active","valid_until_day":null,"business_policy":policy}
	if not deputy.is_empty(): auth.delegate_ids.append(deputy.character_id)
	state.action_authorizations[id] = auth
	var task := {"id":task_id,"task_id":task_id,"task_kind":"management","name":shop.name+" · 掌柜持续经营","principal_id":principal,"executor_id":manager,"authorization_id":id,"plan_revision":1,"authorization_version":1,"steps":[],"status":"reserved","created_day":int(state.current_day),"due_day":int(state.current_day)+1,"last_execution_day":-1,"parent_task_id":"","delegation_chain":[manager],"visible_feedback":["庄头将按农时和预算委托真实农工、投入种粮并安排售粮；日常农事无需逐笔确认。" if shop.asset_kind=="managed_farm" else "掌柜将按预算安排实际用料、工匠生产和成品销售；无需逐笔确认。" if shop.asset_kind=="manufacturing_shop" else "掌柜将按预算办理实际采购与销售；无需逐笔确认。" if shop.asset_kind=="retail_shop" else "掌柜将按预算办理实际借贷、到期收款及依约处置；无需逐笔确认。"]}
	Segments.refresh(task)
	if shop.asset_kind=="modeled_business":
		task.visible_feedback=["负责人将在原预算内按经营方针处理日常供销，月末结账；无需逐笔确认。"]
	task["credit_reviews"] = []
	state.active_tasks.append(task)
	return {"ok":true,"result_ref":id,"business_policy":policy.duplicate(true),"visible_summary":("已授权庄头经营；每月投入上限 %d，单季投入上限 %d，保留现金 %d。" if shop.asset_kind=="managed_farm" else "已授权掌柜自动经营；每月生产上限 %d，单批上限 %d，保留现金 %d。" if shop.asset_kind=="manufacturing_shop" else "已授权掌柜自动经营；每月进货上限 %d，单笔上限 %d，保留现金 %d。" if shop.asset_kind=="retail_shop" else "已授权掌柜自动经营；每月放款上限 %d，单笔上限 %d，保留现金 %d。") % [policy.monthly_limit,policy.loan_limit,policy.cash_floor]}

static func _change_deputy(state, data: Dictionary, shop: Dictionary, params: Dictionary, principal: String, execution: String, kind: String) -> Dictionary:
	var prior := current(state,shop.asset_id)
	if str(prior.get("authorization_id",""))!=params.expected_authorization_id or not Family.authority(state,shop.office_id,principal): return Contract.fail("授权或任用权已变化，请重新查看副手安排")
	if not prior.is_empty() and state.office_state[shop.office_id].holder_id not in ["",prior.business_policy.manager_id]: return Contract.fail("掌柜任职与原授权不符，请先办理负责人交接")
	var appoint: bool = kind=="appoint_business_deputy"
	var id := Staff.office_id(shop.asset_id)
	var previous: Dictionary = state.office_state.get(id,{})
	if appoint:
		if prior.is_empty(): return Contract.fail("请先明确掌柜的持续经营授权，再安排副手")
		if previous.get("holder_id","")!="": return Contract.fail("已有受聘副手，请先办理其离任")
		if params.candidate_id==prior.business_policy.manager_id: return Contract.fail("原负责人不能同时成为自己的副手")
		var assessed := Staff.assess(state,data,shop,params.candidate_id,int(params.wage_amount))
		if assessed.grade!="eligible": return Contract.fail(assessed.reason)
		var office := Staff.definition(state,shop,int(params.wage_amount)) if previous.is_empty() else previous.duplicate(true)
		office.remuneration_terms.amount = int(params.wage_amount)
		if Accounts.new().available(state,office.remuneration_terms.account_id)<int(params.wage_amount): return Contract.fail("雇主可用资金不足支付副手首期工资")
		if previous.is_empty(): office["created_by"] = execution
		state.office_state[id] = office
	else:
		if previous.get("holder_id","")=="" or previous.holder_id!=params.candidate_id: return Contract.fail("副手任职已变化，请重新查看")
	var employment := {}
	if appoint:
		employment = Family.appoint(state,data,{"office_id":id,"candidate_id":params.candidate_id,"actor_id":principal,"remuneration_terms":state.office_state[id].remuneration_terms.duplicate(true)},execution)
		if not employment.ok: employment["rollback_required"] = true; return employment
		state.economic_contracts[employment.result_ref]["shop_id"] = shop.asset_id
		shop.contract_refs.append(employment.result_ref)
	else:
		employment = Family.dismiss(state,id,execution)
		if not employment.ok: employment["rollback_required"] = true; return employment
	var result := {"ok":true,"result_ref":id}
	if not prior.is_empty():
		var agreed: Dictionary = prior.business_policy.duplicate(true)
		var revoked := apply(state,"revoke_business_management",{"shop_id":shop.asset_id},principal,execution,data)
		if not revoked.ok: revoked["rollback_required"] = true; return revoked
		result = _grant(state,shop,agreed,principal,execution,agreed.manager_id)
	result["journal_refs"] = ["wage:"+execution] if appoint else []
	result["business_staff_change"] = {"operation":"appoint" if appoint else "remove","shop_id":shop.asset_id,"office_id":id,"candidate_id":params.candidate_id,"previous_authorization_id":str(prior.get("authorization_id","")),"employment_contract_id":str(employment.result_ref) if appoint else "","wage_amount":int(params.get("wage_amount",0)) if appoint else 0}
	result["visible_summary"] = "已聘%s为副手并支付首期工资 %d；掌柜无法履职时在原额度内暂代。" % [state.character_states[params.candidate_id].name,int(params.wage_amount)] if appoint else "已解除副手任职和代管权限；原账目及欠付义务保留。"
	return result

static func _handover(state, data: Dictionary, shop: Dictionary, params: Dictionary, principal: String, execution: String) -> Dictionary:
	var prior := current(state,shop.asset_id)
	var office: Dictionary = state.office_state[shop.office_id]
	if prior.is_empty() or not Family.authority(state,shop.office_id,principal): return Contract.fail("交接需要原经营授权及雇主的实际任用权")
	if office.holder_id!=params.expected_manager_id: return Contract.fail("原负责人已变化，请重新查看交接对象")
	if office.holder_id not in ["",prior.business_policy.manager_id]: return Contract.fail("在任人员与原授权不符，请先核对任职")
	if params.candidate_id==office.holder_id: return Contract.fail("接替人与当前负责人相同，无须重新支付工资")
	var assessment := Family.assess(state,data,shop.office_id,params.candidate_id,int(params.wage_amount))
	if assessment.grade!="eligible": return Contract.fail(assessment.reason)
	var funding: String = office.remuneration_terms.account_id
	if Accounts.new().available(state,funding)<int(params.wage_amount): return Contract.fail("雇主可用资金不足支付接替人的首期工资")
	var former_terms: Array = []
	for term in state.office_terms.values():
		if term.office_id==office.office_id and int(term.end_day)<0: former_terms.append(term.term_id)
	var agreed: Dictionary = prior.business_policy.duplicate(true)
	var revoked := apply(state,"revoke_business_management",{"shop_id":shop.asset_id},principal,execution,data)
	if not revoked.ok: return revoked
	if office.holder_id!="":
		var dismissed := Family.dismiss(state,office.office_id,execution)
		if not dismissed.ok: dismissed["rollback_required"] = true; return dismissed
	office.remuneration_terms.amount = int(params.wage_amount)
	var hired := Family.appoint(state,data,{"office_id":office.office_id,"candidate_id":params.candidate_id,"actor_id":principal,"remuneration_terms":office.remuneration_terms.duplicate(true)},execution)
	if not hired.ok: hired["rollback_required"] = true; return hired
	var granted := _grant(state,shop,agreed,principal,execution)
	granted["journal_refs"] = ["wage:"+execution]
	granted["business_handover"] = {"shop_id":shop.asset_id,"from_manager_id":agreed.manager_id,"to_manager_id":params.candidate_id,"previous_authorization_id":prior.authorization_id,"former_term_ids":former_terms,"employment_contract_id":hired.result_ref,"wage_amount":int(params.wage_amount)}
	granted.visible_summary = "已由%s接替掌柜，支付首期工资 %d；原借据、欠款与本月已用额度保留。" % [str(state.character_states[params.candidate_id].name),int(params.wage_amount)]
	return granted

static func month_spent(state, shop_id: String) -> int:
	if state.management_assets.get(shop_id,{}).get("asset_kind")=="modeled_business": return Modeled.spent(state,shop_id)
	if state.management_assets.get(shop_id,{}).get("asset_kind")=="managed_farm": return Farming.spent(state,shop_id)
	if state.management_assets.get(shop_id,{}).get("asset_kind")=="manufacturing_shop": return Manufacturing.spent(state,shop_id)
	if state.management_assets.get(shop_id,{}).get("asset_kind")=="retail_shop": return Retail.spent(state,shop_id)
	var start: int = int(state.current_day)-int(state.current_date.day)+1
	var spent := 0
	for contract in state.economic_contracts.values():
		if contract.get("contract_kind")!="pawn_loan" or contract.get("shop_id")!=shop_id: continue
		var payment: Dictionary = state.resource_journal[contract.execution_refs[0]]
		if int(payment.day)>=start and int(payment.day)<=int(state.current_day): spent += int(payment.amount)
	return spent

static func guard(state, auth: Dictionary, kind: String, params: Dictionary, executor: String = "") -> Dictionary:
	if state.management_assets.get(auth.business_policy.shop_id,{}).get("asset_kind")=="modeled_business": return Modeled.guard(state,auth,kind,params,executor)
	if state.management_assets.get(auth.business_policy.shop_id,{}).get("asset_kind")=="managed_farm": return Farming.guard(state,auth,kind,params,executor)
	if state.management_assets.get(auth.business_policy.shop_id,{}).get("asset_kind")=="manufacturing_shop": return Manufacturing.guard(state,auth,kind,params,executor)
	if state.management_assets.get(auth.business_policy.shop_id,{}).get("asset_kind")=="retail_shop": return Retail.guard(state,auth,kind,params,executor)
	var policy: Dictionary = auth.business_policy
	var shop: Dictionary = state.management_assets.get(policy.shop_id,{})
	if kind not in OPERATIONS or params.get("shop_id")!=policy.shop_id: return Contract.fail("经营动作超出具体产业授权")
	if shop.is_empty() or shop.get("status")!="open": return Contract.fail("产业暂停营业，已有义务保留")
	var staff := Staff.resolve(state,shop)
	if not staff.ok: return staff
	if executor!="" and executor!=staff.person_id: return Contract.fail("经办人不是当前应履职的掌柜或获准副手")
	var ready := Pawnshop._ready_to_trade(state,shop)
	if not ready.ok: return ready
	if kind=="issue_pawn_loan":
		var cost := Pawnshop.cost_for(state,kind,params)
		if not cost.ok: return cost
		if int(cost.amount)>int(policy.loan_limit): return Contract.fail("该笔放款超过单笔上限")
		if month_spent(state,policy.shop_id)+int(cost.amount)>int(policy.monthly_limit): return Contract.fail("本月放款限额已用尽，回收本金不重置限额")
		var reservation: String = auth.reservation_refs.get(shop.account_id,"")
		if Accounts.new().available(state,shop.account_id,reservation)-int(cost.amount)<int(policy.cash_floor): return Contract.fail("该笔放款会低于保留现金底线")
		var assessed := Credit.assess(state,shop,staff.person_id,state.management_assets.get(params.get("collateral_id"),{}))
		if not assessed.ok: return assessed
		return {"ok":assessed.review.assessment.allowed,"error":Credit.public_reason(assessed.review),"credit_review":assessed.review}
	else:
		var loan: Dictionary = state.economic_contracts.get(params.get("loan_id"),{})
		if loan.get("shop_id")!=shop.asset_id or int(loan.get("due_day",2147483647))>int(state.current_day): return Contract.fail("掌柜只能办理本铺已到期借据")
	return {"ok":true}

static func settle(state, data: Dictionary, task: Dictionary) -> Dictionary:
	if task.status in ["completed","cancelled"] or int(state.current_day)<int(task.due_day) or int(task.last_execution_day)==int(state.current_day): return {"ok":true}
	var auth: Dictionary = state.action_authorizations[task.authorization_id]
	if auth.status!="active": return _wait(task,"授权已撤回",state.current_day)
	var policy: Dictionary = auth.business_policy
	var shop: Dictionary = state.management_assets[policy.shop_id]
	var principal: String = load("res://scripts/core/clan_succession_service.gd").effective_principal(state,auth)
	if not Accounts.new().can_operate(state,shop.account_id,principal): return _wait(task,"委托主体已无法经办资金，等待正式交接。",state.current_day)
	if shop.status!="open": return _wait(task,"产业暂停营业，已有义务保留。",state.current_day)
	var staff := Staff.resolve(state,shop)
	if not staff.ok: return _wait(task,str(staff.error),state.current_day)
	task.executor_id = staff.person_id
	task.delegation_chain = [staff.person_id]
	var ready := Pawnshop._ready_to_trade(state,shop)
	if not ready.ok: return _wait(task,str(ready.error),state.current_day)
	var proposal := Modeled.choose(state,auth) if shop.asset_kind=="modeled_business" else Farming.choose(state,auth) if shop.asset_kind=="managed_farm" else Manufacturing.choose(state,auth) if shop.asset_kind=="manufacturing_shop" else Retail.choose(state,auth) if shop.asset_kind=="retail_shop" else _choose(state,auth)
	task.credit_reviews.append_array(proposal.get("credit_reviews",[]))
	var who: String = ("副手暂代 · " if staff.acting else "掌柜 · ")+str(state.character_states[staff.person_id].name)+"："
	if not proposal.has("kind"): return _wait(task,who+str(proposal.get("reason","目前没有可办理的实际交易。")),state.current_day)
	var cost: Dictionary = load("res://scripts/core/game_action_dispatcher.gd").cost_for(state,proposal.kind,proposal.parameters)
	if not cost.ok: return _wait(task,str(cost.error),state.current_day)
	var account: String = shop.account_id
	var previous_limit := 0
	if int(cost.amount)>0:
		var ref: String = auth.reservation_refs.get(account,"")
		var reserved: Dictionary
		if ref.is_empty():
			ref = "authorization:%s:%s" % [auth.authorization_id,account]
			reserved = Accounts.new().apply(state,"reserve",{"execution_id":ref,"account_id":account,"amount":int(cost.amount),"actor_id":principal,"task_id":task.task_id})
		else:
			previous_limit = int(state.resource_reservations[ref].amount)
			reserved = Accounts.new().apply(state,"resize",{"account_id":account,"amount":previous_limit+int(cost.amount),"actor_id":principal,"reservation_id":ref})
		if not reserved.ok: return _wait(task,str(reserved.error),state.current_day)
		auth.reservation_refs[account] = ref
		auth.resource_limits = [{"account_id":account,"amount":previous_limit+int(cost.amount),"unit_id":"cash_unit"}]
	var step_id := "day:%d" % int(state.current_day)
	var step := {"step_id":step_id,"action_kind":proposal.kind,"target_refs":[shop.asset_id],"parameters":proposal.parameters,"depends_on":[],"status":"planned","execution_id":task.task_id+":"+step_id,"receipt_ref":""}
	task.steps.append(step)
	Segments.refresh(task)
	var request := {"execution_id":step.execution_id,"request_id":"business:"+step.execution_id,"actor_id":task.executor_id,"principal_id":task.principal_id,"executor_id":task.executor_id,"action_kind":step.action_kind,"target_refs":step.target_refs,"parameters":step.parameters,"expected_state_revision":int(state.state_revision),"task_id":task.task_id,"step_id":step.step_id,"authorization_id":auth.authorization_id}
	var result: Dictionary = load("res://scripts/core/game_action_dispatcher.gd").apply(state,data,request)
	if not result.ok:
		if result.get("rollback_required",false): return result
		task.steps.pop_back()
		Segments.refresh(task)
		if int(cost.amount)>0:
			var ref: String = auth.reservation_refs[account]
			if previous_limit>0:
				var restored := Accounts.new().apply(state,"resize",{"account_id":account,"amount":previous_limit,"actor_id":principal,"reservation_id":ref})
				if not restored.ok: return restored
				auth.resource_limits[0].amount = previous_limit
			else:
				state.resource_reservations.erase(ref)
				auth.reservation_refs.clear()
				auth.resource_limits.clear()
		return _wait(task,str(result.error),state.current_day)
	step.status = "completed"
	step.receipt_ref = result.result_ref
	Segments.refresh(task)
	state.state_revision += 1
	return _wait(task,who+str({"issue_pawn_loan":"已按抵押约定支付本金，实物由本铺保管。","redeem_pawn":"已收回到期本金及息费，并归还抵押物。","dispose_pawn":"已按逾期约定完成实际处置，余款与损益已入账。"}.get(proposal.kind,result.receipt.visible_summary)),state.current_day)

static func _choose(state, auth: Dictionary) -> Dictionary:
	var shop: Dictionary = state.management_assets[auth.business_policy.shop_id]
	var reason := "目前没有可办理的实际交易。"
	var contracts: Array = state.economic_contracts.keys(); contracts.sort()
	for id in contracts:
		var loan: Dictionary = state.economic_contracts[id]
		if loan.get("contract_kind")!="pawn_loan" or loan.get("shop_id")!=shop.asset_id or loan.status not in ["outstanding","overdue"] or int(loan.due_day)>int(state.current_day): continue
		var kind := ""
		var item: Dictionary = state.management_assets[loan.collateral_id]
		if loan.allow_redemption_collection and Pawnshop._living_here(state,loan.borrower_id,shop.location_id) and int(item.get("condition",0))>0 and Accounts.new().can_operate(state,loan.borrower_account_id,loan.borrower_id) and Accounts.new().available(state,loan.borrower_account_id)>=int(loan.remaining_debt): kind = "redeem_pawn"
		elif loan.status=="overdue" and int(loan.disposal_day)<=int(state.current_day):
			var offer: Dictionary = item.get("purchase_offer",{})
			if not offer.is_empty() and offer.get("buyer_id")!=loan.borrower_id and int(offer.get("valid_until_day",-1))>=int(state.current_day) and int(item.get("condition",0))>=int(offer.get("minimum_condition",101)) and Pawnshop._living_here(state,str(offer.get("buyer_id","")),shop.location_id) and Accounts.new().available(state,str(offer.get("account_id","")))>=int(offer.get("price",0)) and int(offer.get("price",0))>0: kind = "dispose_pawn"
		if kind.is_empty(): continue
		var params := {"shop_id":shop.asset_id,"loan_id":id}
		var allowed := guard(state,auth,kind,params)
		if allowed.ok: return {"kind":kind,"parameters":params}
		reason = str(allowed.error)
	var items: Array = state.management_assets.keys(); items.sort()
	var reviews: Array = []
	var candidates: Array = []
	for id in items:
		var item: Dictionary = state.management_assets[id]
		var offer: Dictionary = item.get("pledge_offer",{})
		if item.get("asset_kind")!="movable" or item.get("status")!="available" or offer.is_empty() or item.location_id!=shop.location_id or not offer.get("organization_ids",[]).has(shop.owner_ref.entity_id): continue
		if not Pawnshop._living_here(state,str(offer.borrower_id),shop.location_id) or item.owner_ref.get("entity_id")!=offer.borrower_id or item.custodian_ref!=item.owner_ref or item.get("lien_contract_id","")!="" or int(item.get("condition",0))<60 or int(offer.valuation)<int(offer.principal)+int(offer.fee): continue
		var params := {"shop_id":shop.asset_id,"collateral_id":id,"borrower_id":offer.borrower_id}
		var allowed := guard(state,auth,"issue_pawn_loan",params)
		if allowed.has("credit_review"): reviews.append(allowed.credit_review)
		if allowed.ok: candidates.append({"parameters":params,"priority":int(allowed.credit_review.assessment.priority)})
		else: reason = str(allowed.error)
	if not candidates.is_empty():
		candidates.sort_custom(func(a,b): return a.priority>b.priority if a.priority!=b.priority else str(a.parameters.collateral_id)<str(b.parameters.collateral_id))
		return {"kind":"issue_pawn_loan","parameters":candidates[0].parameters,"credit_reviews":reviews}
	return {"reason":reason,"credit_reviews":reviews}

static func _wait(task: Dictionary, message: String, day: int) -> Dictionary:
	task.last_execution_day = day
	task.status = "running"
	task.visible_feedback = [message]
	return {"ok":true}

static func validate(raw: Dictionary, auth: Dictionary, task: Dictionary) -> Dictionary:
	var policy: Variant = auth.get("business_policy")
	if not policy is Dictionary or policy.size()!=6+int(policy.has("deputy"))+int(policy.has("strategy"))+int(policy.has("payroll_from_shop")) or raw.management_assets.get(policy.get("shop_id"),{}).get("asset_kind") not in ["pawnshop","retail_shop","manufacturing_shop","managed_farm","modeled_business"] or not raw.character_states.has(policy.get("manager_id")): return Contract.fail("持续经营授权丢失产业或具名负责人")
	var checked := cost_for(raw,"authorize_business_management",policy)
	if not checked.ok: return checked
	var receipt: Dictionary = raw.action_receipts.get(policy.get("grant_execution"),{})
	if receipt.get("business_policy")!=policy or not receipt.get("effect_refs",[]).has(auth.authorization_id) or (receipt.get("executor_id")!=auth.principal_id and not _planned_grant(raw,auth,receipt)): return Contract.fail("持续经营条款与本人批准的签发回执不符")
	if receipt.has("business_payroll_change"):
		var change: Variant=receipt.business_payroll_change
		if not change is Dictionary or change.get("payroll_from_shop")!=policy.get("payroll_from_shop"):return Contract.fail("发薪来源变更缺少明确批准")
		var former: Dictionary=raw.action_authorizations.get(change.get("previous_authorization_id"),{})
		if former.get("status")!="revoked":return Contract.fail("发薪来源变更缺少旧授权撤回")
		for field in ["shop_id","manager_id","monthly_limit","loan_limit","cash_floor","strategy","deputy"]:
			if former.get("business_policy",{}).get(field)!=policy.get(field):return Contract.fail("发薪来源变更不能扩大经营权限或更换人员")
	if receipt.has("business_strategy_change"):
		var change: Dictionary=receipt.business_strategy_change
		var former: Dictionary=raw.action_authorizations.get(change.get("previous_authorization_id"),{})
		if former.get("status")!="revoked" or change.get("strategy")!=policy.get("strategy"): return Contract.fail("方针调整缺少原授权终止记录")
		for field in ["shop_id","manager_id","monthly_limit","loan_limit","cash_floor","payroll_from_shop"]:
			if former.get("business_policy",{}).get(field)!=policy.get(field): return Contract.fail("调整方针不能暗中更换产业、负责人或资金限额")
	if receipt.has("business_budget_change"):
		var change: Variant=receipt.business_budget_change
		if not change is Dictionary: return Contract.fail("预算调整记录损坏")
		var former: Dictionary=raw.action_authorizations.get(change.get("previous_authorization_id"),{})
		if former.get("status")!="revoked" or change.get("monthly_limit")!=policy.monthly_limit: return Contract.fail("预算调整缺少原授权终止与批准限额")
		for field in ["shop_id","manager_id","cash_floor","strategy","deputy","payroll_from_shop"]:
			if former.get("business_policy",{}).get(field)!=policy.get(field): return Contract.fail("调整预算不能暗中更换负责人、保留现金或经营方针")
		if int(policy.loan_limit)!=mini(int(former.business_policy.loan_limit),int(policy.monthly_limit)): return Contract.fail("预算调整擅自扩大单笔用款权限")
	if receipt.has("business_handover"):
		var handover: Variant = receipt.business_handover
		if not handover is Dictionary or not handover.get("former_term_ids") is Array: return Contract.fail("负责人交接记录损坏")
		var former: Dictionary = raw.action_authorizations.get(handover.get("previous_authorization_id"),{})
		var employment: Dictionary = raw.economic_contracts.get(handover.get("employment_contract_id"),{})
		if former.get("status")!="revoked" or former.get("business_policy",{}).get("shop_id")!=policy.shop_id or former.business_policy.get("manager_id")!=handover.get("from_manager_id") or handover.get("to_manager_id")!=policy.manager_id or handover.get("shop_id")!=policy.shop_id: return Contract.fail("交接丢失前任授权或实际接替人")
		for field in ["monthly_limit","loan_limit","cash_floor","strategy","payroll_from_shop"]:
			if former.business_policy.get(field)!=policy.get(field): return Contract.fail("交接不能暗中扩大原经营条款")
		if employment.get("contract_kind")!="employment" or employment.get("employee_id")!=policy.manager_id or employment.get("office_id")!=raw.management_assets[policy.shop_id].office_id or employment.get("remuneration_terms",{}).get("amount")!=handover.get("wage_amount") or not employment.get("execution_refs",[]).has("wage:"+str(policy.grant_execution)): return Contract.fail("交接缺少接替人的实际雇约与工资")
		for id in handover.former_term_ids:
			var term: Dictionary = raw.office_terms.get(id,{})
			if term.get("holder_id")!=handover.from_manager_id or term.get("ended_by")!=policy.grant_execution or term.get("end_day")!=receipt.day: return Contract.fail("交接与原任职终止记录不符")
	var delegates: Array = [policy.manager_id]
	if policy.has("deputy"):
		var deputy: Variant = policy.deputy
		if not deputy is Dictionary or deputy.size()!=3 or not raw.character_states.has(deputy.get("character_id")) or deputy.character_id==policy.manager_id or deputy.get("office_id")!=Staff.office_id(policy.shop_id): return Contract.fail("经营副手身份或专属岗位损坏")
		var employment: Dictionary = raw.economic_contracts.get(deputy.get("employment_contract_id"),{})
		if employment.get("contract_kind")!="employment" or employment.get("employee_id")!=deputy.character_id or employment.get("office_id")!=deputy.office_id or employment.get("shop_id")!=policy.shop_id: return Contract.fail("经营副手缺少实际受雇依据")
		delegates.append(deputy.character_id)
	if receipt.has("business_staff_change"):
		var change: Variant = receipt.business_staff_change
		if not change is Dictionary or change.get("operation") not in ["appoint","remove"] or change.get("shop_id")!=policy.shop_id or change.get("office_id")!=Staff.office_id(policy.shop_id): return Contract.fail("副手安排缺少产业与操作依据")
		var prior: Dictionary = raw.action_authorizations.get(change.get("previous_authorization_id"),{})
		if prior.get("status")!="revoked" or prior.get("business_policy",{}).get("shop_id")!=policy.shop_id: return Contract.fail("副手安排丢失旧授权终止记录")
		for field in ["manager_id","monthly_limit","loan_limit","cash_floor","strategy","payroll_from_shop"]:
			if prior.business_policy.get(field)!=policy.get(field): return Contract.fail("副手安排不得暗中更换掌柜或扩大经营额度")
		if change.operation=="appoint" and (not policy.has("deputy") or policy.deputy.character_id!=change.get("candidate_id") or policy.deputy.employment_contract_id!=change.get("employment_contract_id")): return Contract.fail("副手批准与实际雇约不符")
		if change.operation=="remove" and policy.has("deputy"): return Contract.fail("解除副手后仍保留代管权")
	if auth.scope!={"action_kinds":operations(raw.management_assets[policy.shop_id]),"target_refs":[policy.shop_id],"allow_subdelegation":false} or auth.delegate_ids!=delegates or auth.delegate_id!=policy.manager_id or not delegates.has(task.executor_id) or task.get("parent_task_id","")!="": return Contract.fail("持续经营授权被扩大或绕过了具名负责人")
	var shop: Dictionary = raw.management_assets[policy.shop_id]
	if not task.get("credit_reviews") is Array: return Contract.fail("经营任务缺少历史授信评估")
	var previous_day := -1
	var seen_reviews := {}
	for review in task.credit_reviews:
		var valid_review := Credit.validate(review)
		if not valid_review.ok: return valid_review
		var key: String = "%d:%s" % [int(review.day),str(review.item_id)]
		if review.shop_id!=shop.asset_id or review.location_id!=shop.location_id or not delegates.has(review.manager_id) or not raw.management_assets.has(review.item_id) or int(review.day)<previous_day or int(review.day)<int(task.created_day) or int(review.day)>int(task.last_execution_day) or int(review.day)>int(raw.current_day) or seen_reviews.has(key): return Contract.fail("经营评估人员、范围、顺序或日期不符")
		previous_day = int(review.day)
		seen_reviews[key] = true
	if auth.status=="active":
		if not raw.active_tasks.any(func(row): return row.get("task_id")==task.task_id) or task.status in ["completed","cancelled"]: return Contract.fail("持续授权丢失活动任务")
		if raw.action_authorizations.values().filter(func(row): return row.get("status")=="active" and row.get("business_policy",{}).get("shop_id")==policy.shop_id).size()!=1: return Contract.fail("同一产业重复签发持续授权")
	for limit in auth.resource_limits:
		if limit.get("account_id")!=shop.account_id: return Contract.fail("持续经营不能另领其他账户资金")
	for step in task.steps:
		if step.action_kind not in operations(shop) or step.parameters.get("shop_id")!=policy.shop_id or step.target_refs!=[policy.shop_id] or step.status!="completed": return Contract.fail("持续经营保存了越权或未执行的动作")
		var executed: Dictionary = raw.action_receipts.get(step.receipt_ref,{})
		var executor: String = str(executed.get("executor_id",""))
		if not delegates.has(executor): return Contract.fail("经营回执由未获批准人员办理")
		if step.action_kind=="issue_pawn_loan":
			var review: Variant = executed.get("business_credit_review")
			var valid_review := Credit.validate(review)
			if not valid_review.ok: return valid_review
			var loan: Dictionary = raw.economic_contracts.get(executed.get("effect_refs",[])[0],{}) if not executed.get("effect_refs",[]).is_empty() else {}
			if not review.assessment.allowed or not task.credit_reviews.has(review) or review.manager_id!=executor or review.item_id!=step.parameters.collateral_id or review.day!=executed.day or loan.get("principal")!=review.inputs.principal or loan.get("fee")!=review.inputs.fee or loan.get("valuation")!=review.inputs.valuation: return Contract.fail("实际放款与当时评估不符")
		var command := {"execution_id":step.execution_id,"actor_id":executor,"principal_id":task.principal_id,"executor_id":executor,"action_kind":step.action_kind,"target_refs":step.target_refs,"parameters":step.parameters,"task_id":task.task_id,"step_id":step.step_id,"authorization_id":auth.authorization_id}
		if preload("res://scripts/core/canonical_json.gd").hash_value(command).get("hash")!=executed.get("input_hash"): return Contract.fail("持续经营步骤与真实办理回执不符")
	return {"ok":true}

static func _planned_grant(raw: Dictionary, auth: Dictionary, receipt: Dictionary) -> bool:
	var source: Dictionary = raw.action_authorizations.get(receipt.get("authorization_id"),{})
	if source.get("principal_id")!=auth.principal_id or not source.get("delegate_ids",[]).has(receipt.get("executor_id")) or not source.get("scope",{}).get("action_kinds",[]).has("authorize_business_management") or not source.get("scope",{}).get("target_refs",[]).has(auth.business_policy.shop_id): return false
	for task in raw.get("active_tasks",[])+raw.get("completed_tasks",[]):
		if task.get("task_id")!=receipt.get("task_id") or task.get("authorization_id")!=source.get("authorization_id") or task.get("principal_id")!=auth.principal_id: continue
		for step in task.get("steps",[]):
			if step.get("action_kind")!="authorize_business_management" or step.get("receipt_ref")!=receipt.get("execution_id") or step.get("execution_id")!=receipt.get("execution_id") or step.get("status")!="completed": continue
			for key in ["shop_id","monthly_limit","loan_limit","cash_floor"]:
				if step.parameters.get(key)!=auth.business_policy.get(key): return false
			var command := {"execution_id":step.execution_id,"actor_id":receipt.executor_id,"principal_id":task.principal_id,"executor_id":receipt.executor_id,"action_kind":step.action_kind,"target_refs":step.target_refs,"parameters":step.parameters,"task_id":task.task_id,"step_id":step.step_id,"authorization_id":source.authorization_id}
			return preload("res://scripts/core/canonical_json.gd").hash_value(command).get("hash")==receipt.get("input_hash")
	return false
