extends RefCounted
const Rules = preload("res://scripts/core/management_state_contract.gd")
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Presence = preload("res://scripts/core/production_service.gd")
const Family = preload("res://scripts/core/family_office_rules.gd")
const Succession = preload("res://scripts/core/clan_succession_service.gd")
const SOURCE := "scenario:qinghe_partition_756"
const KINDS := ["partition_household"]

static func merge_definitions(data: Dictionary, config: Variant) -> Dictionary:
	if not config is Dictionary or config.get("source_id") != SOURCE or not config.get("rules") is Array: return Rules.fail("分家规则缺少实际来源")
	var prepared: Dictionary = config.duplicate(true)
	for rule in prepared.rules:
		if not rule is Dictionary or not rule.get("office_templates") is Array or not rule.get("employment_consents") is Array or not rule.get("members") is Array: return Rules.fail("分家定义缺少支户成员、岗位及本人聘用意愿")
		for member in rule.members:
			var people: Array = data.characters.filter(func(person): return person.id == member.get("character_id"))
			if people.size() != 1 or not Rules.amount(people[0].get("age"), true): return Rules.fail("分家成员缺少来源明确的年龄")
			member["age"] = int(people[0].age)
		rule["office_definitions"] = []
		for template in rule.office_templates:
			var found: Array = data.management.family_offices.filter(func(office): return office.office_id == template.get("template_id"))
			if found.size() != 1: return Rules.fail("支户岗位必须来自现有实际职责定义")
			var office: Dictionary = found[0].duplicate(true)
			office["office_id"] = template.office_id
			office["organization_id"] = rule.household_id
			office["name"] = rule.name + "·" + str(office.name)
			office["display_name"] = office.name
			office.authority_ref["entity_id"] = rule.account_id
			office.remuneration_terms["account_id"] = rule.account_id
			office.remuneration_terms["amount"] = template.wage
			rule.office_definitions.append(office)
		for id in rule.employment_consents:
			var people: Array = data.characters.filter(func(person): return person.id == id)
			if people.size() != 1 or not people[0].get("employment_preferences") is Dictionary: return Rules.fail("支户雇用意愿缺少实际人物")
			people[0].employment_preferences.organization_ids.append(rule.household_id)
		data.management.employer_hiring_policies[rule.household_id] = {"maximum_wage": int(rule.maximum_wage), "source_id": SOURCE}
	data.management["partition_rules"] = prepared
	return {"ok": true}

static func initialize(state, data: Dictionary) -> Dictionary:
	state.flags["partition_rules"] = data.get("management", {}).get("partition_rules", {}).duplicate(true)
	state.flags["family_households"] = {}
	return {"ok": true}

static func rule_for(state, id: String) -> Dictionary:
	for rule in state.flags.get("partition_rules", {}).get("rules", []):
		if rule.partition_id == id: return rule
	return {}

static func cost_for(state, _kind: String, params: Dictionary) -> Dictionary:
	var rule := rule_for(state, str(params.get("partition_id", "")))
	if rule.is_empty(): return Rules.fail("没有有来源的分家安排")
	return {"ok": true, "account_id": rule.source_account_id, "amount": int(rule.cash_amount)}

static func assess(state, rule: Dictionary, principal: String) -> Dictionary:
	if Succession.head(state, rule.clan_id) != principal or not Accounts.new().can_operate(state, rule.source_account_id, principal): return Rules.fail("只有实际家族经营人可确认本家分家安排")
	if state.flags.family_households.has(rule.household_id) or state.economic_contracts.has("partition:" + rule.partition_id): return Rules.fail("该支户已实际成立，不能再次分配开立款")
	if not Presence.present(state, principal, rule.location_id): return Rules.fail("原家族实际经办人尚未到场")
	for member in rule.members:
		var person: Dictionary = state.character_states.get(member.character_id, {})
		if person.get("clan_id") != rule.clan_id: return Rules.fail("立户成员不属于该实际宗族")
		if not str(person.get("household_id", "")).is_empty(): return Rules.fail("成员已有独立支户")
		if int(member.get("age", 0)) < 18: return Rules.fail("立户成员缺少来源明确的成年依据")
		if not member.willing or int(person.get("relationships", {}).get(principal, 0)) < int(member.minimum_relation): return Rules.fail("成员当前不愿依约分家")
		if not Presence.present(state, member.character_id, rule.location_id): return Rules.fail("分家成员须本人实际到场确认")
	if rule.head_id == principal: return Rules.fail("原经办人不能同时冒充独立接收方")
	var due := 0
	for contract in state.economic_contracts.values():
		if contract.get("funding_account_id", contract.get("remuneration_terms", {}).get("account_id", "")) == rule.source_account_id: due += int(contract.get("arrears", 0))
	if Accounts.new().available(state, rule.source_account_id) < int(rule.cash_amount) + int(rule.minimum_retained_cash) + due: return Rules.fail("分家后须保留原任务预留、已欠款及约定留存；当前可分现金不足")
	return {"ok": true, "arrears_retained": due}

static func apply(state, data: Dictionary, params: Dictionary, principal: String, execution: String, reservation: String) -> Dictionary:
	var rule := rule_for(state, str(params.get("partition_id", "")))
	if rule.is_empty(): return Rules.fail("分家规则不存在")
	# Partition signs exact household membership and retained obligations; delegated financing
	# needs a distinct mandate, not an ordinary spending reservation.
	if not reservation.is_empty(): return Rules.fail("分家须由当前经办人直接确认成员及旧义务安排")
	var checked := assess(state, rule, principal)
	if not checked.ok: return checked
	var depot_id := "estate_" + str(rule.household_id)
	if state.resource_accounts.has(rule.account_id) or state.depot_states.has(depot_id): return Rules.fail("支户账户或库藏标识已存在")
	for office in rule.office_definitions:
		if state.office_state.has(office.office_id): return Rules.fail("支户岗位标识已存在")
	var parent := {"entity_kind": "clan", "entity_id": rule.clan_id}
	var retained := {"accounts": [], "assets": [], "contracts": [], "reservations": [], "tasks": []}
	for account in state.resource_accounts.values():
		if account.owner_ref == parent: retained.accounts.append(account.account_id)
	for asset in state.management_assets.values():
		if asset.owner_ref == parent: retained.assets.append(asset.asset_id)
	for contract in state.economic_contracts.values():
		if contract.get("party_refs", []).has(rule.clan_id) or contract.get("principal_id") == principal or contract.get("customer_id") == principal or retained.accounts.has(contract.get("funding_account_id", contract.get("remuneration_terms", {}).get("account_id", ""))): retained.contracts.append(contract.contract_id)
	for held in state.resource_reservations.values():
		if retained.accounts.has(held.account_id): retained.reservations.append(held.reservation_id)
	for task in state.active_tasks:
		if task.get("principal_id") == principal: retained.tasks.append(task.task_id)
	var members: Array = rule.members.map(func(member): return member.character_id)
	var owner := {"entity_kind": "household", "entity_id": rule.household_id}
	state.flags.family_households[rule.household_id] = {"household_id": rule.household_id, "name": rule.name, "lineage_clan_id": rule.clan_id, "head_id": rule.head_id, "members": members, "account_id": rule.account_id, "location_id": rule.location_id, "partition_id": rule.partition_id, "formed_day": int(state.current_day)}
	state.depot_states[depot_id] = {"depot_id": depot_id, "location_node_id": rule.location_id, "owner_organization_id": rule.household_id, "owner_character_id": "", "capacity": Rules.MAX_AMOUNT, "stock": {"silk_cash": 0}}
	state.resource_accounts[rule.account_id] = {"account_id": rule.account_id, "owner_ref": owner, "resource_key": "silk_cash", "unit_id": "cash_unit", "storage_ref": {"storage_kind": "depot", "storage_id": depot_id, "resource_key": "silk_cash"}, "operator_refs": [{"entity_kind": "character", "entity_id": rule.head_id}]}
	var id := "partition:" + str(rule.partition_id)
	var paid := Accounts.new().apply(state, "transfer", {"execution_id": execution, "source_account_id": rule.source_account_id, "destination_account_id": rule.account_id, "amount": int(rule.cash_amount), "actor_id": principal, "reason_ref": id})
	if not paid.ok: return paid
	var offices := Family.initialize(state, {"management": {"family_offices": rule.office_definitions, "family_work_schedules": data.management.family_work_schedules}})
	if not offices.ok: return offices
	for member in members: state.character_states[member]["household_id"] = rule.household_id
	state.economic_contracts[id] = {"contract_id": id, "contract_kind": "family_partition", "source_id": SOURCE, "partition_id": rule.partition_id, "household_id": rule.household_id, "parent_clan_id": rule.clan_id, "principal_id": principal, "head_id": rule.head_id, "members": members.duplicate(), "source_account_id": rule.source_account_id, "destination_account_id": rule.account_id, "amount": int(rule.cash_amount), "created_day": int(state.current_day), "status": "formed", "receipt_ref": execution, "retained": retained, "signatures": [principal] + members, "retention_policy": "retain_original_obligations"}
	return {"ok": true, "result_ref": id, "journal_refs": [execution], "partition_record": state.economic_contracts[id].duplicate(true), "visible_summary": "已向%s实际划付 %d 立户公款；原家族其余钱物、债权、旧合同和原任务保留原归属，宗族和人物关系不变。" % [rule.name, int(rule.cash_amount)]}

static func project(state, viewer: String) -> Array:
	var result: Array = []
	for rule in state.flags.get("partition_rules", {}).get("rules", []):
		var record: Dictionary = state.economic_contracts.get("partition:" + str(rule.partition_id), {})
		var head := Succession.head(state, rule.clan_id)
		var members: Array = rule.members.map(func(member): return member.character_id)
		if viewer != head and not members.has(viewer) and viewer != record.get("principal_id"): continue
		var ready := assess(state, rule, viewer)
		var row := {"partition_id": rule.partition_id, "name": rule.name, "head_name": state.character_states[rule.head_id].name, "cash_amount": int(rule.cash_amount), "minimum_retained_cash": int(rule.minimum_retained_cash), "formed": not record.is_empty(), "ready": ready.ok, "reason": ready.get("error", "各成员愿意且在场；实际款项和原义务待确认。"), "day": record.get("created_day", -1), "current_cash": null}
		if not record.is_empty() and Accounts.new().can_operate(state, rule.account_id, viewer): row.current_cash = Accounts.new().balance(state, rule.account_id)
		result.append(row)
	return result

static func validate(raw: Dictionary) -> Dictionary:
	var config: Variant = raw.get("flags", {}).get("partition_rules", {})
	var households: Variant = raw.get("flags", {}).get("family_households", {})
	if not config is Dictionary or not households is Dictionary: return Rules.fail("分家规则或支户名册类型错误")
	if config.is_empty():
		if not households.is_empty() or raw.get("economic_contracts", {}).values().any(func(row): return row.get("contract_kind") == "family_partition"): return Rules.fail("实际分家缺少来源规则")
		return {"ok": true}
	if config.get("source_id") != SOURCE or not config.get("rules") is Array: return Rules.fail("分家规则来源无效")
	var seen := {}
	var active := {}
	for rule in config.rules:
		if not rule is Dictionary or not rule.get("partition_id") is String or seen.has(rule.partition_id) or not rule.get("household_id") is String or not rule.get("name") is String or not rule.get("head_id") is String or not Rules.amount(rule.get("cash_amount"), true) or not Rules.amount(rule.get("minimum_retained_cash")) or not rule.get("members") is Array or rule.members.is_empty() or not rule.get("office_definitions") is Array: return Rules.fail("分家配置缺少成员、金额或职责")
		seen[rule.partition_id] = true
		if raw.resource_accounts.get(rule.get("source_account_id"), {}).get("owner_ref") != {"entity_kind": "clan", "entity_id": rule.get("clan_id")} or not raw.local_node_state.has(rule.get("location_id")): return Rules.fail("分家缺少原族公账及实际地点")
		var members: Array = []
		for member in rule.members:
			if not member is Dictionary or not raw.character_states.has(member.get("character_id")) or members.has(member.character_id) or raw.character_states[member.character_id].get("clan_id") != rule.clan_id or not member.get("willing") is bool or not Rules.amount(member.get("age"), true) or not (member.get("minimum_relation") is int or member.get("minimum_relation") is float): return Rules.fail("分家成员族属或本人意愿定义无效")
			members.append(member.character_id)
		if not members.has(rule.head_id): return Rules.fail("新户主不在实际立户成员中")
		var record: Dictionary = raw.economic_contracts.get("partition:" + str(rule.partition_id), {})
		if record.is_empty():
			if households.has(rule.household_id) or raw.resource_accounts.has(rule.get("account_id")): return Rules.fail("未交割分家不能凭空存在支户或账户")
			continue
		var house: Dictionary = households.get(rule.household_id, {})
		if house.get("household_id") != rule.household_id or house.get("lineage_clan_id") != rule.clan_id or house.get("name") != rule.name or house.get("members") != members or house.get("head_id") != rule.head_id or house.get("account_id") != rule.account_id or house.get("location_id") != rule.location_id or house.get("partition_id") != rule.partition_id: return Rules.fail("支户名册与实际分家不符")
		active[rule.household_id] = house
		if record.get("contract_kind") != "family_partition" or record.get("source_id") != SOURCE or record.get("partition_id") != rule.partition_id or record.get("household_id") != rule.household_id or record.get("parent_clan_id") != rule.clan_id or record.get("head_id") != rule.head_id or record.get("members") != members or record.get("source_account_id") != rule.source_account_id or record.get("destination_account_id") != rule.account_id or record.get("amount") != rule.cash_amount or record.get("status") != "formed" or record.get("retention_policy") != "retain_original_obligations" or not Rules.amount(record.get("created_day")) or int(record.created_day) > int(raw.current_day) or house.get("formed_day") != record.created_day: return Rules.fail("分家协议与实际人、钱、日期不符")
		if not raw.character_states.has(record.get("principal_id")) or record.get("signatures") != [record.principal_id] + members: return Rules.fail("分家缺少原经办人及全体成员确认")
		var account: Dictionary = raw.resource_accounts.get(rule.account_id, {})
		if account.get("owner_ref") != {"entity_kind": "household", "entity_id": rule.household_id} or account.get("operator_refs") != [{"entity_kind": "character", "entity_id": rule.head_id}]: return Rules.fail("独立支户失去原公账产权或实际经办人")
		for member in members:
			if raw.character_states[member].get("household_id") != rule.household_id: return Rules.fail("分家后实际支户成员丢失")
		var receipt: Dictionary = raw.action_receipts.get(record.get("receipt_ref"), {})
		var paid: Dictionary = raw.resource_journal.get(record.get("receipt_ref"), {})
		if receipt.get("partition_record") != record: return Rules.fail("分家协议改写了共同回执中的原财产、签署或义务记录")
		if not receipt.get("effect_refs", []).has(record.contract_id) or receipt.get("journal_refs") != [record.receipt_ref] or receipt.get("executor_id") != record.principal_id or receipt.get("day") != record.created_day or paid.get("source_account_id") != rule.source_account_id or paid.get("destination_account_id") != rule.account_id or paid.get("amount") != rule.cash_amount or paid.get("reason_ref") != record.contract_id or paid.get("actor_id") != record.principal_id: return Rules.fail("分家缺少准确的实际付款或共同动作回执")
		if not record.get("retained") is Dictionary: return Rules.fail("分家缺少原财产及义务记录")
		for key in ["accounts", "assets", "contracts", "reservations", "tasks"]:
			if not record.retained.get(key) is Array: return Rules.fail("分家丢失旧义务清单")
		for id in record.retained.accounts:
			if raw.resource_accounts.get(id, {}).get("owner_ref") != {"entity_kind": "clan", "entity_id": rule.clan_id}: return Rules.fail("分家丢失原公账或改写产权")
		for id in record.retained.assets:
			if not raw.management_assets.has(id): return Rules.fail("分家丢失原实际产业")
		for id in record.retained.contracts:
			if not raw.economic_contracts.has(id): return Rules.fail("分家丢失原借据或合同")
		for id in record.retained.reservations:
			if not raw.resource_reservations.has(id): return Rules.fail("分家丢失原预留记录")
		for id in record.retained.tasks:
			if not (raw.get("active_tasks", []) + raw.get("completed_tasks", [])).any(func(task): return task.get("task_id") == id): return Rules.fail("分家丢失原未完成事务")
		for definition in rule.office_definitions:
			var office: Dictionary = raw.office_state.get(definition.get("office_id"), {})
			if office.get("organization_id") != rule.household_id or office.get("role_key") != definition.get("role_key") or office.get("authority_ref") != definition.get("authority_ref"): return Rules.fail("分家支户岗位丢失或权源混入旧户")
	if active.size() != households.size(): return Rules.fail("存在没有实际分家交割的支户")
	for person in raw.character_states.values():
		if str(person.get("household_id", "")) != "" and not active.get(person.household_id, {}).get("members", []).has(person.get("id")): return Rules.fail("人物支户归属没有实际分家依据")
	for contract in raw.economic_contracts.values():
		if contract.get("contract_kind") == "family_partition" and not seen.has(contract.get("partition_id")): return Rules.fail("分家合同缺少配置")
	return {"ok": true}
