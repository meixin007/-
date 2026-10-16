extends RefCounted
## Per-business posts remain ordinary family offices with actual terms and wages.
const Contract = preload("res://scripts/core/management_state_contract.gd")
const KINDS := ["pawnshop","retail_shop","manufacturing_shop","managed_farm","modeled_business"]

static func office_id(shop_id: String) -> String:
	return "business-manager:"+shop_id

static func used(state, id: String) -> bool:
	if state.management_assets.values().any(func(asset):return asset.get("asset_kind") in KINDS and asset.get("office_id")==id): return true
	for task in state.active_tasks:
		if task.get("status") in ["completed","cancelled"]: continue
		if task.get("steps",[]).any(func(step):return step.get("action_kind") in ["rent_shop","establish_owned_pawnshop","establish_owned_retail","establish_owned_manufacturing","establish_owned_farm","establish_owned_modeled"] and step.get("parameters",{}).get("office_id")==id): return true
	return false

static func candidate_reserved(state, person: String) -> bool:
	for task in state.active_tasks:
		if task.get("principal_id")!=state.player_character_id or task.get("status") in ["completed","cancelled"]: continue
		if task.get("steps",[]).any(func(step):return step.get("action_kind")=="hire_family" and step.get("status")!="completed" and step.get("parameters",{}).get("candidate_id")==person): return true
	return false

static func draft(state, template_id: String, shop_id: String, account_id: String, wage: Variant) -> Dictionary:
	var template: Dictionary = state.office_state.get(template_id,{})
	var account: Dictionary = state.resource_accounts.get(account_id,{})
	if template.get("office_kind")!="family" or template.get("role_key")!="shopkeeper" or template.has("business_manager_shop_id") or template.has("business_shop_id") or template.get("remuneration_terms",{}).get("account_id")!=account_id or template.get("organization_id")!=account.get("owner_ref",{}).get("entity_id") or shop_id.is_empty() or not Contract.amount(wage,true): return Contract.fail("新产业岗位需要本家的当地掌柜职责、真实薪酬账户与工资")
	var id := office_id(shop_id)
	if state.office_state.has(id): return Contract.fail("该产业岗位已经存在，不能重复设立")
	var office: Dictionary = template.duplicate(true)
	office.office_id=id; office.holder_id=""; office.status="vacant"
	office.name="产业掌柜"; office.display_name="产业掌柜"
	office.remuneration_terms.amount=int(wage)
	office.erase("recruitment_notice")
	office["business_manager_shop_id"]=shop_id
	office["manager_template_office_id"]=template_id
	return {"ok":true,"office":office,"template_id":template_id,"new_office":true}

static func select(state, land: Dictionary, account_id: String, shop_id: String, wage: int = -1) -> Dictionary:
	var templates: Array = state.office_state.values().filter(func(row):return row.get("office_kind")=="family" and row.get("role_key")=="shopkeeper" and row.get("organization_id")==state.resource_accounts.get(account_id,{}).get("owner_ref",{}).get("entity_id") and row.get("scope_ref",{}).get("entity_id")==land.location_id and row.get("remuneration_terms",{}).get("account_id")==account_id and not row.has("business_manager_shop_id") and not row.has("business_shop_id"))
	if templates.size()!=1: return Contract.fail("须有本组织在当地的掌柜职责及薪酬来源")
	var template: Dictionary = templates[0]
	var amount := int(template.remuneration_terms.amount) if wage<0 else wage
	if used(state,template.office_id): return draft(state,template.office_id,shop_id,account_id,amount)
	if not Contract.amount(amount,true): return Contract.fail("掌柜工资须为正整数")
	if template.holder_id!="" and amount!=int(template.remuneration_terms.amount): return Contract.fail("现任掌柜已有雇约，须另行协商工资，不能在筹建时改写")
	var office: Dictionary = template.duplicate(true)
	office.remuneration_terms.amount=amount
	return {"ok":true,"office":office,"template_id":template.office_id,"new_office":false}

static func validate(raw: Dictionary) -> Dictionary:
	for office in raw.office_state.values():
		if not str(office.get("office_id","")).begins_with("business-manager:") and not office.has("business_manager_shop_id"): continue
		var shop: Dictionary = raw.management_assets.get(office.get("business_manager_shop_id"),{})
		if shop.get("asset_kind") not in KINDS or shop.get("office_id")!=office.get("office_id") or office.office_id!=office_id(shop.asset_id): return Contract.fail("产业掌柜岗位失去独立经营实体来源")
		var receipt: Dictionary = raw.action_receipts.get(office.get("created_by"),{})
		var proof: Dictionary = receipt.get("business_office_creation",{})
		var definition: Variant = proof.get("definition")
		if not definition is Dictionary or proof.get("office_id")!=office.office_id or proof.get("shop_id")!=shop.asset_id or not receipt.get("effect_refs",[]).has(shop.asset_id) or proof.get("template_office_id")!=office.get("manager_template_office_id"): return Contract.fail("产业掌柜岗位缺少实际设立回执")
		var template: Dictionary = raw.office_state.get(proof.template_office_id,{})
		if template.get("office_kind")!="family" or template.get("role_key")!="shopkeeper" or template.get("organization_id")!=shop.owner_ref.entity_id or template.get("scope_ref",{}).get("entity_id")!=shop.location_id: return Contract.fail("产业岗位的当地家族职责来源不符")
		for key in ["office_id","office_kind","role_key","organization_id","scope_ref","authority_ref","work_schedule","business_manager_shop_id","manager_template_office_id"]:
			if office.get(key)!=definition.get(key): return Contract.fail("产业岗位的职责、薪酬权源或地点被改写")
		for key in ["account_id","unit_id","period_days"]:
			if office.remuneration_terms.get(key)!=definition.get("remuneration_terms",{}).get(key): return Contract.fail("产业岗位的实际发薪来源被改写")
		var rivals: Array = raw.management_assets.values().filter(func(asset):return asset.get("asset_kind") in KINDS and asset.get("office_id")==office.office_id)
		if rivals.size()!=1: return Contract.fail("同一产业岗位不能同时绑定多家店铺")
	return {"ok":true}
