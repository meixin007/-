extends RefCounted
## Prospective changes remain on the actual employment, without resetting old wages.
const Contract=preload("res://scripts/core/management_state_contract.gd")
const Accounts=preload("res://scripts/core/resource_account_service.gd")
static func terms_on_day(employment: Dictionary, due_day: int) -> Dictionary:
	var result: Dictionary=employment.remuneration_terms.duplicate(true)
	for amendment in employment.get("wage_amendments",[]):
		if amendment is Dictionary and int(amendment.get("effective_day",2147483647))<=due_day:result.amount=int(amendment.get("amount",result.amount))
	return result
static func due_total(employment: Dictionary, through_day: int) -> int:
	var day: int=int(employment.next_due_day)
	var result:=0
	while day<=through_day:
		result+=int(terms_on_day(employment,day).amount)
		day+=int(employment.remuneration_terms.period_days)
	return result
static func cost_for(state, params: Dictionary) -> Dictionary:
	var shop: Dictionary=state.management_assets.get(params.get("shop_id"),{})
	var job: Dictionary=state.economic_contracts.get(params.get("employment_contract_id"),{})
	if shop.get("asset_kind") not in ["pawnshop","retail_shop","manufacturing_shop","managed_farm","modeled_business"] or job.get("contract_kind")!="employment" or job.get("status")!="active" or job.get("office_id")!=shop.get("office_id") or state.office_state.get(shop.get("office_id"),{}).get("holder_id")!=job.get("employee_id") or not Contract.amount(params.get("wage_amount"),true):return Contract.fail("须指明本店实际在任负责人、原雇约及新工资")
	if int(job.arrears)>0 or int(job.next_due_day)<=int(state.current_day):return Contract.fail("先按原约清付到期工资，再商议下一期薪酬")
	if int(params.wage_amount)==int(terms_on_day(job,int(job.next_due_day)).amount):return Contract.fail("本期工资未变化，无需重签")
	return {"ok":true,"account_id":"","amount":0}
static func apply(state, data: Dictionary, params: Dictionary, principal: String, execution: String) -> Dictionary:
	var checked:=cost_for(state,params)
	if not checked.ok:return checked
	var shop: Dictionary=state.management_assets[params.shop_id]
	var job: Dictionary=state.economic_contracts[params.employment_contract_id]
	var family=load("res://scripts/core/family_office_rules.gd")
	if state.character_states[principal].location_id!=shop.location_id or state.character_states[job.employee_id].location_id!=shop.location_id or not Accounts.new().can_operate(state,shop.account_id,principal) or not family.authority(state,shop.office_id,principal):return Contract.fail("双方须在履职地，由同一雇主有权经办人重议")
	var willingness: Dictionary=family.assess(state,data,shop.office_id,job.employee_id,int(params.wage_amount))
	if willingness.grade!="eligible":return Contract.fail("负责人未接受新薪酬："+str(willingness.reason))
	var amendment: Dictionary={"shop_id":shop.asset_id,"employment_contract_id":job.contract_id,"employee_id":job.employee_id,"principal_id":principal,"before_amount":int(terms_on_day(job,int(job.next_due_day)).amount),"amount":int(params.wage_amount),"signed_day":int(state.current_day),"effective_day":int(job.next_due_day),"receipt_id":execution}
	if not job.has("wage_amendments"):job["wage_amendments"]=[]
	job.wage_amendments.append(amendment)
	state.office_state[shop.office_id].remuneration_terms.amount=int(params.wage_amount)
	return {"ok":true,"result_ref":job.contract_id,"business_wage_amendment":amendment.duplicate(true),"visible_summary":"按原聘用意愿规则重议；第%d日原发薪时起每期%d，原任职、已付工资与发薪来源保留。" % [amendment.effective_day,amendment.amount]}
static func validate(raw: Dictionary) -> Dictionary:
	for job in raw.economic_contracts.values():
		if not job.has("wage_amendments"):continue
		if job.get("contract_kind")!="employment" or not job.wage_amendments is Array or job.wage_amendments.is_empty():return Contract.fail("薪酬变更须附属于原雇约")
		var previous: int=int(job.remuneration_terms.amount)
		var last_effective:=-1
		var last_revision:=-1
		for amendment in job.wage_amendments:
			if not amendment is Dictionary:return Contract.fail("薪酬重议记录损坏")
			var shop: Dictionary=raw.management_assets.get(amendment.get("shop_id"),{})
			var receipt: Dictionary=raw.action_receipts.get(amendment.get("receipt_id"),{})
			if shop.get("office_id")!=job.office_id or amendment.get("employment_contract_id")!=job.contract_id or amendment.get("employee_id")!=job.employee_id or raw.resource_accounts.get(shop.get("account_id"),{}).get("owner_ref",{}).get("entity_id")!=job.organization_id or amendment.get("before_amount")!=previous or not Contract.amount(amendment.get("amount"),true) or int(amendment.amount)==previous or not Contract.amount(amendment.get("signed_day")) or not Contract.amount(amendment.get("effective_day")) or int(amendment.effective_day)<=int(amendment.signed_day) or int(amendment.effective_day)>int(amendment.signed_day)+int(job.remuneration_terms.period_days) or int(amendment.effective_day)<last_effective or int(amendment.signed_day)>int(raw.current_day) or receipt.get("business_wage_amendment")!=amendment or receipt.get("executor_id")!=amendment.get("principal_id") or receipt.get("day")!=amendment.signed_day or int(receipt.get("state_revision_after",-1))<=last_revision or not receipt.get("effect_refs",[]).has(job.contract_id):return Contract.fail("薪酬重议缺少同一雇约、真实签署及下期生效来源")
			previous=int(amendment.amount);last_effective=int(amendment.effective_day);last_revision=int(receipt.state_revision_after)
		if job.status=="active" and raw.office_state[job.office_id].remuneration_terms.amount!=previous:return Contract.fail("在任薪酬报价与实际重议记录不符")
		for id in job.execution_refs:
			var paid: Dictionary=raw.resource_journal.get(id,{})
			if not str(id).begins_with("wage:"):continue
			var due: int=int(paid.get("wage_due_day",paid.get("day",-1)))
			if paid.get("amount")!=terms_on_day(job,due).amount:return Contract.fail("实际工资与当期签约金额不符")
			if paid.has("wage_due_day") and (not Contract.amount(paid.wage_due_day) or str(id)!="wage:%s:%d" % [job.contract_id,due] or due>int(paid.day)):return Contract.fail("工资期次与原执行标识不符")
	return {"ok":true}
