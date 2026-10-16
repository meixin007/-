extends RefCounted
## Paid deputy is an ordinary family office, bound to one real business.
const Family = preload("res://scripts/core/family_office_rules.gd")
const Contract = preload("res://scripts/core/management_state_contract.gd")
const Workload = preload("res://scripts/core/character_workload_service.gd")
const UNAVAILABLE := ["dead","deceased","executed","missing","imprisoned","departed","exiled","unreachable"]

static func office_id(shop_id: String) -> String:
	return "business-deputy:"+shop_id

static func definition(state, shop: Dictionary, wage: int) -> Dictionary:
	var office: Dictionary = state.office_state[shop.office_id].duplicate(true)
	office.office_id = office_id(shop.asset_id)
	office.name = shop.name+"副掌柜"
	office.display_name = office.name
	office.holder_id = ""
	office.status = "vacant"
	office.remuneration_terms.amount = wage
	office.erase("recruitment_notice")
	office.erase("business_manager_shop_id")
	office.erase("manager_template_office_id")
	office["business_shop_id"] = shop.asset_id
	office.duties = ["平时协助照管本铺；按雇主授权在掌柜无法履职时暂代，不另领经营额度。"]
	office.responsibility_text = office.duties[0]
	return office

static func assess(state, data: Dictionary, shop: Dictionary, candidate: String, wage: int) -> Dictionary:
	var office := definition(state,shop,wage)
	if candidate==state.office_state[shop.office_id].holder_id: return {"grade":"prohibited","reason":"掌柜不能同时担任自己的副手"}
	return Family.assess(state,data,office.office_id,candidate,wage,office)

static func terms(state, shop_id: String) -> Dictionary:
	var office: Dictionary = state.office_state.get(office_id(shop_id),{})
	if office.get("holder_id","")=="": return {}
	for employment in state.economic_contracts.values():
		if employment.get("contract_kind")=="employment" and employment.get("office_id")==office.office_id and employment.get("status")=="active":
			return {"character_id":office.holder_id,"office_id":office.office_id,"employment_contract_id":employment.contract_id}
	return {}

static func readiness(state, shop: Dictionary, office: Dictionary, person: String) -> Dictionary:
	var character: Dictionary = state.character_states.get(person,{})
	if person=="" or office.get("holder_id")!=person or character.is_empty() or character.get("status") in UNAVAILABLE or character.get("location_id")!=shop.location_id:
		return Contract.fail("负责人空缺、离开或无法履职")
	var operators: Array = state.resource_accounts[office.remuneration_terms.account_id].operator_refs
	var employer := str(operators[0].entity_id) if not operators.is_empty() else ""
	if Workload.occupied_today(state,person,"",employer,"pawnshop"): return Contract.fail("负责人今日已有任职或履约工时占用")
	for employment in state.economic_contracts.values():
		if employment.get("contract_kind")=="employment" and employment.get("office_id")==office.office_id and employment.get("status")=="active" and int(employment.get("arrears",0))>0: return Contract.fail("负责人工资欠付，需先处理雇用关系")
	return {"ok":true,"person_id":person,"office_id":office.office_id}

static func resolve(state, shop: Dictionary) -> Dictionary:
	var office: Dictionary = state.office_state.get(shop.office_id,{})
	var mandate := {}
	for authorization in state.action_authorizations.values():
		if authorization.get("status")=="active" and authorization.get("business_policy",{}).get("shop_id")==shop.asset_id: mandate = authorization; break
	if not mandate.is_empty() and office.get("holder_id","") not in ["",mandate.business_policy.manager_id]: return Contract.fail("在任掌柜与原授权不同，请先办理交接")
	var ready := readiness(state,shop,office,str(office.get("holder_id","")))
	if ready.ok:
		ready["acting"] = false
		return ready
	var deputy: Dictionary = mandate.get("business_policy",{}).get("deputy",{})
	if deputy.is_empty(): return ready
	if deputy!=terms(state,shop.asset_id): return Contract.fail("掌柜无法履职，副手任职已变化；暂停经营并保留已有义务")
	var fallback := readiness(state,shop,state.office_state[deputy.office_id],deputy.character_id)
	if not fallback.ok: return Contract.fail("掌柜及指定副手均无法履职；"+str(fallback.error))
	fallback["acting"] = true
	fallback["reason"] = ready.error
	return fallback

static func validate(raw: Dictionary) -> Dictionary:
	for office in raw.office_state.values():
		if not str(office.get("office_id","")).begins_with("business-deputy:") and not office.has("business_shop_id"): continue
		var shop: Dictionary = raw.management_assets.get(office.get("business_shop_id"),{})
		if shop.get("asset_kind") not in ["pawnshop","retail_shop","manufacturing_shop","managed_farm","modeled_business"] or office.get("office_id")!=office_id(shop.asset_id): return Contract.fail("副手岗位失去真实产业来源")
		var main: Dictionary = raw.office_state[shop.office_id]
		for key in ["office_kind","role_key","organization_id","scope_ref","authority_ref","work_schedule"]:
			if office.get(key)!=main.get(key): return Contract.fail("副手岗位改变了雇主、职责、地点或工时")
		var receipt: Dictionary = raw.action_receipts.get(office.get("created_by"),{})
		if receipt.get("business_staff_change",{}).get("office_id")!=office.office_id or receipt.business_staff_change.get("operation")!="appoint": return Contract.fail("副手岗位缺少实际聘任来源")
		for employment in raw.economic_contracts.values():
			if employment.get("contract_kind")!="employment" or employment.get("office_id")!=office.office_id: continue
			var term: Dictionary = raw.office_terms[employment.term_id]
			var signed: Dictionary = raw.action_receipts.get(term.appointment_transaction_id,{})
			var proof: Dictionary = signed.get("business_staff_change",{})
			if proof.get("operation")!="appoint" or proof.get("office_id")!=office.office_id or proof.get("employment_contract_id")!=employment.contract_id or proof.get("candidate_id")!=employment.employee_id or employment.get("shop_id")!=shop.asset_id or proof.get("wage_amount")!=employment.remuneration_terms.amount or not employment.execution_refs.has("wage:"+str(term.appointment_transaction_id)): return Contract.fail("副手雇约、工资或人员来源不符")
	return {"ok":true}
