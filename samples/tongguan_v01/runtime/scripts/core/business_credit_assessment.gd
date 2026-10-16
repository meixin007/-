extends RefCounted
## Versioned game parameters, not historical price estimates or a profit generator.
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Contract = preload("res://scripts/core/management_state_contract.gd")
const VERSION := 1
const REASONS := {"acceptable":"抵押保障满足当前审慎要求", "security":"当地治安或秩序过低，暂缓新增放款", "liquidity":"当前到场买方的实际承接能力不足，暂缓放款", "coverage":"负责人估价把握及当地风险要求下，抵押保障不足"}

static func assess(state, shop: Dictionary, manager: String, item: Dictionary) -> Dictionary:
	var stats: Dictionary = state.character_states.get(manager,{}).get("stats",{})
	var node: Dictionary = state.local_node_state.get(shop.location_id,{})
	for field in ["finance","governance","diplomacy"]:
		if not _index(stats.get(field)): return Contract.fail("负责人经营能力资料不足，暂不新增放款")
	for field in ["security","public_order"]:
		if not _index(node.get(field)): return Contract.fail("当地治安与秩序资料不足，暂不新增放款")
	var offer: Dictionary = item.get("pledge_offer",{})
	var purchase: Dictionary = item.get("purchase_offer",{})
	var quote_support := 0
	if not purchase.is_empty():
		var buyer: Dictionary = state.character_states.get(purchase.get("buyer_id"),{})
		var valid: bool = buyer.get("location_id")==shop.location_id and buyer.get("status") not in ["dead","deceased","executed","missing","imprisoned","departed","exiled","unreachable"] and int(purchase.get("valid_until_day",-1))>=int(state.current_day) and int(item.get("condition",0))>=int(purchase.get("minimum_condition",101))
		if valid and state.resource_accounts.has(purchase.get("account_id")) and Accounts.new().can_operate(state,purchase.account_id,str(purchase.get("buyer_id",""))):
			quote_support = mini(int(purchase.get("price",0)),Accounts.new().available(state,purchase.account_id))
	var inputs := {"finance":int(stats.finance),"governance":int(stats.governance),"diplomacy":int(stats.diplomacy),"security":int(node.security),"public_order":int(node.public_order),"condition":int(item.get("condition",0)),"valuation":int(offer.get("valuation",0)),"principal":int(offer.get("principal",0)),"fee":int(offer.get("fee",0)),"quote_present":not purchase.is_empty(),"quote_support":quote_support}
	var review := {"version":VERSION,"day":int(state.current_day),"shop_id":shop.asset_id,"location_id":shop.location_id,"manager_id":manager,"item_id":item.asset_id,"inputs":inputs,"assessment":calculate(inputs)}
	return {"ok":true,"review":review}

static func calculate(inputs: Dictionary) -> Dictionary:
	var suitability := (int(inputs.finance)*60+int(inputs.governance)*25+int(inputs.diplomacy)*15)/100
	var appraisal_percent := 70+suitability*30/100
	var appraised := int(inputs.valuation)*int(inputs.condition)*appraisal_percent/10000
	var support: int = mini(appraised,int(inputs.quote_support)) if inputs.quote_present else appraised
	var risk_percent := 100+maxi(0,60-int(inputs.security))/2+maxi(0,60-int(inputs.public_order))/2
	var required := (int(inputs.principal)*risk_percent+99)/100
	var reason := "acceptable"
	if mini(int(inputs.security),int(inputs.public_order))<20: reason = "security"
	elif support<required: reason = "liquidity" if inputs.quote_present and int(inputs.quote_support)<mini(appraised,required) else "coverage"
	# Only ranks actual finite, affordable quotes; never creates customers or money.
	var priority := int(inputs.fee)*10000/maxi(1,int(inputs.principal))+(support-required)*100/maxi(1,required)
	return {"allowed":reason=="acceptable","reason_code":reason,"suitability":suitability,"appraisal_percent":appraisal_percent,"appraised_value":appraised,"realizable_support":support,"risk_percent":risk_percent,"required_support":required,"priority":priority}

static func validate(review: Variant) -> Dictionary:
	if not review is Dictionary or review.size()!=8 or review.get("version")!=VERSION or not Contract.amount(review.get("day")) or not review.get("inputs") is Dictionary or not review.get("assessment") is Dictionary: return Contract.fail("经营评估记录缺少版本、日期或输入")
	for field in ["shop_id","location_id","manager_id","item_id"]:
		if not review.get(field) is String or str(review[field]).is_empty(): return Contract.fail("经营评估缺少实际对象")
	var inputs: Dictionary = review.inputs
	if inputs.size()!=11 or not inputs.get("quote_present") is bool: return Contract.fail("经营评估输入结构损坏")
	for field in ["finance","governance","diplomacy","security","public_order","condition"]:
		if not _index(inputs.get(field)): return Contract.fail("经营评估能力或地区指标越界")
	for field in ["valuation","principal","fee","quote_support"]:
		if not Contract.amount(inputs.get(field),field in ["valuation","principal"]): return Contract.fail("经营评估资金或估值越界")
	if not inputs.quote_present and int(inputs.quote_support)!=0: return Contract.fail("没有报价却生成买方资金")
	# JSON restores integer-valued numbers as floats; compare canonical values,
	# while retaining exact keys, booleans and rejection of non-finite numbers.
	var encoded := preload("res://scripts/core/canonical_json.gd").encode(review.assessment)
	if not encoded.ok or encoded.text!=preload("res://scripts/core/canonical_json.gd").encode(calculate(inputs)).text: return Contract.fail("经营评估结论与当时输入不符")
	return {"ok":true}

static func _index(value: Variant) -> bool:
	return Contract.amount(value) and int(value)<=100

static func public_reason(review: Dictionary) -> String:
	return str(REASONS.get(review.get("assessment",{}).get("reason_code"),"经营评估资料不足"))

static func summary(state, shop_id: String, from_day: int, through_day: int) -> Dictionary:
	var result := {"assessments":0,"deferred":0,"reason_counts":{},"source_task_ids":[]}
	for task in state.active_tasks+state.completed_tasks:
		if task.get("task_kind")!="management" or state.action_authorizations.get(task.get("authorization_id"),{}).get("business_policy",{}).get("shop_id")!=shop_id: continue
		for review in task.get("credit_reviews",[]):
			if int(review.day)<from_day or int(review.day)>through_day: continue
			result.assessments += 1
			if not result.source_task_ids.has(task.task_id): result.source_task_ids.append(task.task_id)
			if not review.assessment.allowed:
				result.deferred += 1
				var reason: String = review.assessment.reason_code
				result.reason_counts[reason] = int(result.reason_counts.get(reason,0))+1
	return result
