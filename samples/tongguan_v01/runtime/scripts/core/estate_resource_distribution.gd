extends RefCounted
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Rules = preload("res://scripts/core/management_state_contract.gd")
const Canonical = preload("res://scripts/core/canonical_json.gd")

static func validate_definition(raw: Dictionary, rule: Dictionary) -> Dictionary:
	if not rule.has("resource_shares"): return {"ok": true}
	if not rule.resource_shares is Array: return Rules.fail("其他遗产资源须有明确分配安排")
	var owner := {"entity_kind": "character", "entity_id": rule.owner_id}
	var stores: Array = [raw.resource_accounts[rule.account_id].storage_ref]
	for group in rule.resource_shares:
		if not group is Dictionary or group.size() != 3 or group.get("unit_id") != "ration_unit" or not group.get("recipient_accounts") is Dictionary: return Rules.fail("遗产资源缺少库存、单位或继承人收取账户")
		var source: Dictionary = raw.resource_accounts.get(group.get("account_id"), {})
		if source.get("owner_ref") != owner or source.get("operator_refs") != [owner] or source.get("unit_id") != group.unit_id or stores.has(source.get("storage_ref")): return Rules.fail("遗产资源必须属于死者原私有库存，不能重复分配同一存量")
		stores.append(source.storage_ref)
		if group.recipient_accounts.size() != rule.heirs.size(): return Rules.fail("其他资源必须说明每名继承人的收取账户")
		for heir in rule.heirs:
			var target: Dictionary = raw.resource_accounts.get(group.recipient_accounts.get(heir.character_id), {})
			if target.get("owner_ref") != {"entity_kind": "character", "entity_id": heir.character_id} or target.get("unit_id") != group.unit_id or target.get("storage_ref") == source.storage_ref: return Rules.fail("继承人须使用本人实际同单位资源账户")
	return {"ok": true}

static func plan(state, rule: Dictionary) -> Dictionary:
	var payments: Array = []
	var totals := {}
	if not rule.has("resource_shares"): return {"ok": true, "payments": payments, "totals": totals}
	var accounts := Accounts.new()
	var stores: Array = [state.resource_accounts[rule.account_id].storage_ref]
	for group in rule.resource_shares: stores.append(state.resource_accounts[group.account_id].storage_ref)
	for account in state.resource_accounts.values():
		if account.owner_ref == {"entity_kind": "character", "entity_id": rule.owner_id} and not stores.has(account.storage_ref) and accounts.balance(state, account.account_id) > 0: return Rules.fail("仍有未配置分配方式的实际私人资源，遗产保留等待安排")
	var weight := 0
	for heir in rule.heirs: weight += int(heir.weight)
	for group in rule.resource_shares:
		var amount := accounts.balance(state, group.account_id)
		if accounts.available(state, group.account_id) != amount: return Rules.fail("其他遗产资源仍有原义务预留，不能提前分配")
		if amount > 0 and accounts.location(state, group.account_id) != rule.location_id: return Rules.fail("实际遗产资源不在交割地，须先完成真实运输")
		totals[group.account_id] = {"amount": amount, "unit_id": group.unit_id}
		var remaining := amount
		for index in rule.heirs.size():
			var heir: Dictionary = rule.heirs[index]
			var value := remaining if index == rule.heirs.size() - 1 else int(amount * int(heir.weight) / weight)
			remaining -= value
			if value <= 0: continue
			var target: String = group.recipient_accounts[heir.character_id]
			if accounts.location(state, target) != rule.location_id or accounts.balance(state, target) > Rules.MAX_AMOUNT - value: return Rules.fail("继承人资源仓储不在交割地或容量不足")
			payments.append({"kind": "resource_share", "source_account_id": group.account_id, "destination_account_id": target, "unit_id": group.unit_id, "amount": value, "reason_ref": rule.estate_id})
	return {"ok": true, "payments": payments, "totals": totals}

static func validate_settlement(raw: Dictionary, rule: Dictionary, row: Dictionary, receipt: Dictionary) -> Dictionary:
	if not rule.has("resource_shares"):
		if row.has("resource_totals") or receipt.has("estate_resources") or row.payments.any(func(payment): return payment.get("kind") == "resource_share"): return Rules.fail("其他遗产资源交割丢失原配置")
		return {"ok": true}
	var totals: Variant = row.get("resource_totals")
	if not totals is Dictionary or totals.size() != rule.resource_shares.size() or Canonical.hash_value(totals) != Canonical.hash_value(receipt.get("estate_resources")): return Rules.fail("其他遗产资源总量与共同交割回执不符")
	var weight := 0
	for heir in rule.heirs: weight += int(heir.weight)
	var sources: Array = []
	for group in rule.resource_shares:
		sources.append(group.account_id)
		var total: Variant = totals.get(group.account_id)
		if not total is Dictionary or total.size() != 2 or not Rules.amount(total.get("amount")) or total.get("unit_id") != group.unit_id: return Rules.fail("遗产库存总量或计量单位无效")
		var remaining := int(total.amount)
		var distributed := {}
		for payment in row.payments:
			if payment.kind != "resource_share" or payment.get("source_account_id") != group.account_id: continue
			if payment.get("unit_id") != group.unit_id or payment.reason_ref != rule.estate_id or distributed.has(payment.destination_account_id): return Rules.fail("遗产资源交割重复、错用单位或丢失来源")
			distributed[payment.destination_account_id] = int(payment.amount)
		for index in rule.heirs.size():
			var heir: Dictionary = rule.heirs[index]
			var value := remaining if index == rule.heirs.size() - 1 else int(int(total.amount) * int(heir.weight) / weight)
			remaining -= value
			var target: String = group.recipient_accounts[heir.character_id]
			if int(distributed.get(target, 0)) != value: return Rules.fail("实际资源继承份额与原配置不符")
			distributed.erase(target)
		if not distributed.is_empty(): return Rules.fail("遗产资源流向未约定账户")
	for payment in row.payments:
		if payment.kind == "resource_share" and not sources.has(payment.get("source_account_id")): return Rules.fail("遗产动用了未配置的资源来源")
	return {"ok": true}
