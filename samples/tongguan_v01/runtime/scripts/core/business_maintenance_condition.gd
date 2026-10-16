extends RefCounted
## Capacity follows the original periodic maintenance contract and paid journal.
const Contract=preload("res://scripts/core/management_state_contract.gd")

static func _first_due(row: Dictionary) -> int:
	return int(row.next_due_day)-row.execution_refs.size()*int(row.period_days)

static func _arrears(row: Dictionary, day: int, paid: int) -> int:
	if row.get("status")=="terminated":day=mini(day,int(row.get("ended_day",day))-1)
	var due := maxi(0,1+(day-_first_due(row))/int(row.period_days)) if day>=_first_due(row) else 0
	return maxi(0,due-paid)*int(row.amount)

static func snapshot(state, shop_id: String) -> Dictionary:
	var items: Array=[]
	for row in state.economic_contracts.values():
		if row.get("contract_kind")!="maintenance" or row.get("shop_id")!=shop_id: continue
		items.append({"contract_id":row.contract_id,"paid_count":row.execution_refs.size(),"period_amount":int(row.amount),"arrears":_arrears(row,int(state.current_day),row.execution_refs.size())})
	items.sort_custom(func(a,b):return a.contract_id<b.contract_id)
	return {"items":items}

static func factor(value: Dictionary) -> float:
	var periods := 0
	for item in value.get("items",[]):
		periods=maxi(periods,int(item.arrears)/maxi(1,int(item.period_amount)))
	return maxf(0.5,1.0-float(periods)*0.25)

static func description(value: Dictionary) -> String:
	var debt := 0
	for item in value.get("items",[]): debt+=int(item.arrears)
	if debt==0: return "维护款已按约支付，经营能力正常。"
	return "维护欠付 %d；经营能力按正常的%d%%计算，补足营运款并完成原维护付款后恢复。" % [debt,roundi(factor(value)*100.0)]

static func validate(raw, shop_id: String, day: int, value: Variant) -> Dictionary:
	if not value is Dictionary or value.size()!=1 or not value.get("items") is Array: return Contract.fail("维护状况快照无效")
	var seen := {}
	for item in value.items:
		if not item is Dictionary or item.size()!=4 or not item.get("contract_id") is String or seen.has(item.contract_id): return Contract.fail("维护来源缺失或重复")
		var row: Dictionary=raw.economic_contracts.get(item.contract_id,{})
		if row.get("contract_kind")!="maintenance" or row.get("shop_id")!=shop_id: return Contract.fail("维护来源不属于本产业")
		for key in ["paid_count","period_amount","arrears"]:
			if not Contract.amount(item.get(key),key=="period_amount"): return Contract.fail("维护金额或付款序号无效")
		var paid := int(item.paid_count)
		if paid>row.execution_refs.size() or int(item.period_amount)!=int(row.amount) or int(item.arrears)!=_arrears(row,day,paid): return Contract.fail("维护欠付与合同期间不符")
		for index in row.execution_refs.size():
			var entry: Dictionary=raw.resource_journal.get(row.execution_refs[index],{})
			if entry.is_empty() or (index<paid and int(entry.day)>day) or (index>=paid and int(entry.day)<day): return Contract.fail("维护快照与当时付款来源不符")
		seen[item.contract_id]=true
	for row in raw.economic_contracts.values():
		if row.get("contract_kind")=="maintenance" and row.get("shop_id")==shop_id and _first_due(row)-int(row.period_days)<=day and not seen.has(row.contract_id): return Contract.fail("月结遗漏原维护合同")
	return {"ok":true}
