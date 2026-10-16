extends RefCounted
## Small on-site reviews use the original journal, employment and relationship graph.
const Contract=preload("res://scripts/core/management_state_contract.gd")
const Accounts=preload("res://scripts/core/resource_account_service.gd")
static func cost_for(state, kind: String, params: Dictionary) -> Dictionary:
	var shop: Dictionary=state.management_assets.get(params.get("shop_id"),{})
	if shop.get("asset_kind") not in ["pawnshop","retail_shop","manufacturing_shop","managed_farm","modeled_business"]:return Contract.fail("须选择真实经营产业")
	if kind=="audit_business":return {"ok":true,"account_id":"","amount":0}
	var office: Dictionary=state.office_state.get(shop.get("office_id"),{})
	var account: Dictionary=state.resource_accounts.get(params.get("funding_account_id"),{})
	if office.get("holder_id","")=="" or office.get("holder_id")!=params.get("expected_manager_id") or account.get("unit_id")!="cash_unit" or account.get("owner_ref")!=shop.owner_ref or account.get("account_id")==shop.account_id:return Contract.fail("关系协调须核对在任负责人，由同产权主体的原账户承担费用")
	return {"ok":true,"account_id":account.account_id,"amount":5}
static func audit(state, shop: Dictionary) -> Dictionary:
	var account: String=shop.account_id
	var expected: int=0
	var entries: Array=[]
	var unknown: Array=[]
	var unknown_amount: int=0
	for row in state.resource_journal.values():
		if row.get("unit_id")!="cash_unit":continue
		var incoming: int=int(row.amount) if row.get("destination_account_id")==account else 0
		var outgoing: int=int(row.amount) if row.get("source_account_id")==account else 0
		if incoming+outgoing==0:continue
		expected+=incoming-outgoing;entries.append(row.entry_id)
		if outgoing>0 and str(row.reason_ref).begins_with("action:") and not state.economic_contracts.has(row.reason_ref):
			unknown.append(row.entry_id);unknown_amount+=outgoing
	entries.sort();unknown.sort()
	var actual: int=Accounts.new().balance(state,account)
	return {"shop_id":shop.asset_id,"account_id":account,"ledger_cash":expected,"actual_cash":actual,"difference":actual-expected,"unclassified_outflow":unknown_amount,"unclassified_entries":unknown,"journal_refs":entries,"day":int(state.current_day)}
static func latest_audit(state, shop_id: String) -> Dictionary:
	var selected: Dictionary={}
	for row in state.economic_contracts.values():
		if row.get("contract_kind")=="business_audit" and row.get("shop_id")==shop_id and (selected.is_empty() or int(state.action_receipts.get(row.receipt_id,{}).get("state_revision_after",0))>int(state.action_receipts.get(selected.receipt_id,{}).get("state_revision_after",0))):selected=row
	return selected
static func apply(state, kind: String, params: Dictionary, principal: String, execution: String) -> Dictionary:
	var checked:=cost_for(state,kind,params)
	if not checked.ok:return checked
	var shop: Dictionary=state.management_assets[params.shop_id]
	if not Accounts.new().can_operate(state,shop.account_id,principal) or state.character_states[principal].location_id!=shop.location_id:return Contract.fail("须由有权经办的真实主体在当地核对；远地先看已送达月报")
	var terms: Dictionary={}
	var id: String=("business-audit:" if kind=="audit_business" else "business-coordination:")+execution
	var refs: Array=[]
	if kind=="audit_business":
		terms=audit(state,shop)
		terms["principal_id"]=principal
	else:
		var person: String=params.expected_manager_id
		if not load("res://scripts/core/production_service.gd").present(state,person,shop.location_id):return Contract.fail("在任负责人不在当地，不能凭空完成关系协调")
		var employment: Dictionary={}
		for job in state.economic_contracts.values():
			if job.get("contract_kind")=="employment" and job.get("office_id")==shop.office_id and job.get("status")=="active":employment=job;break
		if employment.get("contract_kind")!="employment" or employment.get("status")!="active" or employment.get("employee_id")!=person:return Contract.fail("须有当前有效的具名任职与雇约")
		for row in state.economic_contracts.values():
			if row.get("contract_kind")=="business_coordination" and row.terms.manager_id==person and row.terms.principal_id==principal and int(state.current_day)-int(row.terms.day)<30:return Contract.fail("同一负责人三十日内已协调，先观察经营与关系变化")
		var old: int=state.get_relationship(person,principal)
		var delta: int=maxi(0,mini(5,100-old))
		var paid: Dictionary=Accounts.new().apply(state,"transfer",{"execution_id":execution,"source_account_id":params.funding_account_id,"destination_account_id":person+"_cash","amount":5,"actor_id":principal,"reason_ref":id})
		if not paid.ok:return paid
		refs.append(execution)
		state.apply_relationship_delta(person,delta,principal)
		terms={"shop_id":shop.asset_id,"principal_id":principal,"manager_id":person,"employment_id":employment.contract_id,"funding_account_id":params.funding_account_id,"before_relation":old,"delta":delta,"after_relation":old+delta,"day":int(state.current_day)}
	state.economic_contracts[id]={"contract_id":id,"contract_kind":"business_audit" if kind=="audit_business" else "business_coordination","status":"completed","shop_id":shop.asset_id,"terms":terms,"receipt_id":execution,"terms_version":1,"party_refs":[shop.owner_ref.entity_id,principal],"execution_refs":refs}
	shop.contract_refs.append(id)
	return {"ok":true,"result_ref":id,"business_review":terms.duplicate(true),"visible_summary":"已核对原流水与现场现金；用途未注明的款项待核实，不能据此认定舞弊。" if kind=="audit_business" else "已与在任负责人协调并支付约定费用5；原人物关系变化影响已有经营规则，不保证订单或利润。"}
static func validate(raw: Dictionary) -> Dictionary:
	for row in raw.economic_contracts.values():
		if row.get("contract_kind") not in ["business_audit","business_coordination"]:continue
		var terms: Variant=row.get("terms")
		if not terms is Dictionary:return Contract.fail("经营查核或协调记录损坏")
		var shop: Dictionary=raw.management_assets.get(row.get("shop_id"),{})
		var receipt: Dictionary=raw.action_receipts.get(row.get("receipt_id"),{})
		if shop.get("asset_kind") not in ["pawnshop","retail_shop","manufacturing_shop","managed_farm","modeled_business"] or terms.get("shop_id")!=shop.asset_id or not Contract.amount(terms.get("day")) or int(terms.day)>int(raw.current_day) or row.get("status")!="completed" or receipt.get("business_review")!=terms or receipt.get("day")!=terms.day or receipt.get("executor_id")!=terms.get("principal_id") or not receipt.get("effect_refs",[]).has(row.contract_id) or not shop.get("contract_refs",[]).has(row.contract_id):return Contract.fail("查核或协调缺少原经办主体、日期和确认来源")
		if row.contract_kind=="business_coordination":
			var employment: Dictionary=raw.economic_contracts.get(terms.get("employment_id"),{})
			var paid: Dictionary=raw.resource_journal.get(row.receipt_id,{})
			if employment.get("employee_id")!=terms.get("manager_id") or employment.get("office_id")!=shop.office_id or not _relation(terms.get("before_relation")) or terms.get("delta")!=maxi(0,mini(5,100-int(terms.before_relation))) or terms.get("after_relation")!=int(terms.before_relation)+int(terms.delta) or raw.resource_accounts.get(terms.get("funding_account_id"),{}).get("owner_ref")!=shop.owner_ref or paid.get("source_account_id")!=terms.get("funding_account_id") or paid.get("destination_account_id")!=str(terms.manager_id)+"_cash" or paid.get("amount")!=5 or paid.get("reason_ref")!=row.contract_id or paid.get("day")!=terms.day or row.get("execution_refs")!=[row.receipt_id]:return Contract.fail("关系协调须保留实际雇约、费用及原关系变化")
		else:
			if terms.get("account_id")!=shop.account_id or not Contract.amount(terms.get("actual_cash")) or not terms.get("journal_refs") is Array or not terms.get("unclassified_entries") is Array:return Contract.fail("查账未保留实际账户及流水来源")
			var balance: int=0
			var unknown: Array=[]
			var unknown_amount: int=0
			var seen: Dictionary={}
			for ref in terms.journal_refs:
				var paid: Dictionary=raw.resource_journal.get(ref,{})
				if seen.has(ref) or paid.get("unit_id")!="cash_unit" or int(paid.get("day",2147483647))>int(terms.day) or (paid.get("source_account_id")!=shop.account_id and paid.get("destination_account_id")!=shop.account_id):return Contract.fail("查账重复或借用其他账户流水")
				seen[ref]=true
				var outgoing: int=int(paid.amount) if paid.get("source_account_id")==shop.account_id else 0
				balance+=(int(paid.amount) if paid.get("destination_account_id")==shop.account_id else 0)-outgoing
				if outgoing>0 and str(paid.reason_ref).begins_with("action:") and not raw.economic_contracts.has(paid.reason_ref):unknown.append(ref);unknown_amount+=outgoing
			unknown.sort()
			if terms.get("ledger_cash")!=balance or terms.get("difference")!=int(terms.actual_cash)-balance or terms.get("unclassified_entries")!=unknown or terms.get("unclassified_outflow")!=unknown_amount or row.get("execution_refs")!=[]:return Contract.fail("查账账面金额与实际引用流水不符")
	return {"ok":true}
static func _relation(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floorf(float(value)) and absf(float(value))<=100
