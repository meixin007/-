extends RefCounted
## Approved local wages use the original employment calendar and account journal.
const Accounts=preload("res://scripts/core/resource_account_service.gd")
const Contract=preload("res://scripts/core/management_state_contract.gd")

static func source(state, employment: Dictionary, actor: String) -> Dictionary:
	var original: String=employment.remuneration_terms.account_id
	var due: int=int(load("res://scripts/core/business_wage_service.gd").terms_on_day(employment,int(employment.next_due_day)).amount)
	for shop in state.management_assets.values():
		if shop.get("asset_kind") not in ["pawnshop","retail_shop","manufacturing_shop","managed_farm","modeled_business"]:continue
		var deputy: bool=state.office_state.get(employment.office_id,{}).get("business_shop_id")==shop.asset_id
		if employment.office_id!=shop.office_id and not deputy:continue
		var auth: Dictionary=load("res://scripts/core/business_management_service.gd").current(state,shop.asset_id)
		if auth.is_empty() or not auth.business_policy.get("payroll_from_shop",false):continue
		if not _employee(auth.business_policy,employment,shop):return Contract.fail("本店发薪授权与实际雇约不一致")
		if state.resource_accounts[original].owner_ref!=shop.owner_ref or not Accounts.new().can_operate(state,shop.account_id,actor):return Contract.fail("本店发薪须有相同雇主的实际账户经办权")
		if Accounts.new().available(state,shop.account_id)<due+int(auth.business_policy.cash_floor):return Contract.fail("本店资金不足支付工资并保留现金底线，请安排当地到账资金")
		return {"ok":true,"account_id":shop.account_id,"authorization_id":auth.authorization_id}
	return {"ok":true,"account_id":original,"authorization_id":""}

static func _employee(policy: Dictionary, employment: Dictionary, shop: Dictionary) -> bool:
	if employment.office_id==shop.office_id:return employment.employee_id==policy.manager_id
	var deputy: Dictionary=policy.get("deputy",{})
	return deputy.get("office_id")==employment.office_id and deputy.get("character_id")==employment.employee_id and deputy.get("employment_contract_id")==employment.contract_id

static func validate(raw: Dictionary) -> Dictionary:
	for payment in raw.get("resource_journal",{}).values():
		if not payment.has("business_payroll_authorization_id"):continue
		var auth: Dictionary=raw.action_authorizations.get(payment.get("business_payroll_authorization_id"),{})
		var policy: Dictionary=auth.get("business_policy",{})
		var shop: Dictionary=raw.management_assets.get(policy.get("shop_id"),{})
		var employment: Dictionary=raw.economic_contracts.get(payment.get("reason_ref"),{})
		var receipt: Dictionary=raw.action_receipts.get(policy.get("grant_execution"),{})
		if policy.get("payroll_from_shop")!=true or receipt.get("business_policy")!=policy or employment.get("contract_kind")!="employment" or shop.get("asset_kind") not in ["pawnshop","retail_shop","manufacturing_shop","managed_farm","modeled_business"]:return Contract.fail("本店发薪缺少明确经营授权与原雇约")
		var terms: Dictionary=load("res://scripts/core/business_wage_service.gd").terms_on_day(employment,int(payment.get("wage_due_day",payment.get("day",-1))))
		if payment.get("entry_kind")!="transfer" or payment.get("source_account_id")!=shop.account_id or payment.get("destination_account_id")!=employment.employee_id+"_cash" or payment.get("amount")!=terms.amount or not employment.execution_refs.has(payment.entry_id) or not _employee(policy,employment,shop):return Contract.fail("本店工资与实际负责人、当期签约金额或付款来源不符")
		if raw.resource_accounts[employment.remuneration_terms.account_id].owner_ref!=shop.owner_ref or int(payment.day)<int(receipt.get("day",2147483647)):return Contract.fail("本店发薪不得改换雇主或冒充批准前付款")
	return {"ok":true}
