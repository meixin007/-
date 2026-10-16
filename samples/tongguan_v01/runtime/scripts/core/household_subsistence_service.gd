extends RefCounted
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Contract = preload("res://scripts/core/management_state_contract.gd")

static func decision_need(state, data: Dictionary, actor: String) -> Dictionary:
	var model: Dictionary = data.get("management", {}).get("life_models", {}).get(actor, {})
	var rules: Dictionary = data.get("management", {}).get("subsistence_rules", {})
	var account := actor + "_rations"
	if model.is_empty() or not state.resource_accounts.has(account) or not Contract.amount(model.get("dependants")) or not Contract.amount(rules.get("daily_rations_per_person"), true): return {}
	var household: int = int(model.dependants) + 1
	var per_person: int = int(rules.daily_rations_per_person)
	if household > Contract.MAX_AMOUNT / per_person: return {}
	var daily: int = household * per_person
	var owned: int = Accounts.new().available(state, account)
	var accessible: bool = Accounts.new().location(state, account) == state.character_states[actor].get("location_id")
	return {"source_id": rules.get("source_id", ""), "ration_account_id": account, "household_size": household, "daily_ration_units": daily, "available_ration_units": owned if accessible else 0, "needs_food": not accessible or owned < daily, "recorded_missing_today": state.character_states[actor].get("life_goal", {}).get("subsistence", {}).get("missing_today", 0), "urgency": "next_meal" if not accessible or owned < daily else "pantry_sufficient"}

static func initialize(state, data: Dictionary) -> Dictionary:
	for grant in data.get("management", {}).get("ration_grants", []):
		if not grant is Dictionary or not state.character_states.has(grant.get("character_id")) or not Contract.amount(grant.get("amount")) or not str(grant.get("source_id", "")).begins_with("scenario:"): return Contract.fail("口粮初始来源无效")
		var id: String = grant.character_id
		var depot_id := "personal_" + id
		var account_id := id + "_rations"
		if not state.depot_states.has(depot_id) or state.resource_accounts.has(account_id) or state.depot_states[depot_id].stock.has("rations"): return Contract.fail("口粮须使用既有本人仓储，且不能重复发放")
		var owner := {"entity_kind": "character", "entity_id": id}
		state.depot_states[depot_id].stock["rations"] = int(grant.amount)
		state.resource_accounts[account_id] = {"account_id": account_id, "owner_ref": owner, "resource_key": "rations", "unit_id": "ration_unit", "storage_ref": {"storage_kind": "depot", "storage_id": depot_id, "resource_key": "rations"}, "operator_refs": [owner.duplicate(true)]}
		if int(grant.amount) > 0:
			var entry := "initial:" + account_id
			state.resource_journal[entry] = {"entry_id": entry, "execution_id": entry, "entry_kind": "initial_grant", "source_ref": {"entity_kind": "rule", "entity_id": id, "rule_id": grant.source_id}, "destination_ref": owner, "destination_account_id": account_id, "amount": int(grant.amount), "unit_id": "ration_unit", "reason_ref": grant.source_id, "day": 0}
	return {"ok": true}

static func cost_for(state, params: Dictionary) -> Dictionary:
	var stall: Dictionary = state.management_assets.get(params.get("stall_id"), {})
	var offer: Dictionary = stall.get("food_offer", {})
	if stall.get("asset_kind") != "food_stall" or stall.get("status") != "available" or stall.get("offer_visibility") != "public" or not Contract.amount(params.get("lots"), true) or not Contract.amount(offer.get("price"), true) or not Contract.amount(offer.get("lot_units"), true): return Contract.fail("口粮交易缺少实际在售报价或整批数量")
	if int(params.lots) > Contract.MAX_AMOUNT / int(offer.price) or int(params.lots) > Contract.MAX_AMOUNT / int(offer.lot_units): return Contract.fail("口粮交易数量或价款越界")
	if not state.resource_accounts.has(params.get("funding_account_id")) or state.resource_accounts[params.funding_account_id].unit_id != "cash_unit": return Contract.fail("口粮采购缺少实际货币账户")
	return {"ok": true, "account_id": str(params.get("funding_account_id", "")), "amount": int(params.lots) * int(offer.price)}

static func apply(state, params: Dictionary, principal: String, execution: String, reservation: String) -> Dictionary:
	var quoted := cost_for(state, params)
	if not quoted.ok: return quoted
	var stall: Dictionary = state.management_assets[params.stall_id]
	var offer: Dictionary = stall.food_offer
	var seller: String = stall.owner_ref.entity_id
	var recipient := principal + "_rations"
	var accounts := Accounts.new()
	var units := int(params.lots) * int(offer.lot_units)
	# The shared model catalog omits a beneficiary for this personal action.
	# Bind it to the trusted principal; an explicit different recipient remains
	# invalid, and payment/stock still use the original account transactions.
	if params.get("recipient_id", principal) != principal or params.get("funding_account_id") != principal + "_cash" or principal == seller: return Contract.fail("本人口粮采购须使用本人资金和本人库存")
	for id in [quoted.account_id, recipient, offer.stock_account_id, offer.payee_account_id]:
		if not state.resource_accounts.has(id) or accounts.location(state, id) != stall.location_id: return Contract.fail("口粮交割账户不在实际摊位所在地点")
	if state.resource_accounts[quoted.account_id].unit_id != "cash_unit" or state.resource_accounts[offer.payee_account_id].unit_id != "cash_unit" or state.resource_accounts[recipient].unit_id != "ration_unit" or state.resource_accounts[offer.stock_account_id].unit_id != "ration_unit": return Contract.fail("口粮与货币单位不能混用")
	if not accounts.can_operate(state, quoted.account_id, principal) or not accounts.can_operate(state, offer.stock_account_id, seller) or state.character_states[seller].get("location_id") != stall.location_id or state.character_states[seller].get("status") in ["dead", "executed", "departed", "exiled", "missing", "imprisoned"]: return Contract.fail("口粮摊主或付款人已无法交割")
	if accounts.available(state, quoted.account_id, reservation) < int(quoted.amount) or accounts.available(state, offer.stock_account_id) < units or accounts.balance(state, recipient) > Contract.MAX_AMOUNT - units or accounts.balance(state, offer.payee_account_id) > Contract.MAX_AMOUNT - int(quoted.amount): return Contract.fail("实际可用货款或口粮不足，不能占用其他任务预留")
	var contract_id := "food:" + execution
	var paid := accounts.apply(state, "transfer", {"actor_id": principal, "execution_id": execution + ":cash", "source_account_id": quoted.account_id, "destination_account_id": offer.payee_account_id, "amount": quoted.amount, "reservation_id": reservation, "reason_ref": contract_id})
	if not paid.ok: return paid
	var delivered := accounts.apply(state, "transfer", {"actor_id": seller, "execution_id": execution + ":food", "source_account_id": offer.stock_account_id, "destination_account_id": recipient, "amount": units, "reason_ref": contract_id})
	if not delivered.ok: return delivered
	state.economic_contracts[contract_id] = {"contract_id": contract_id, "contract_kind": "food_purchase", "status": "delivered", "buyer_id": principal, "seller_id": seller, "stall_id": params.stall_id, "quantity": units, "amount": int(quoted.amount), "day": int(state.current_day), "offer": offer.duplicate(true), "lots": int(params.lots), "execution_id": execution, "cash_ref": paid.result_ref, "food_ref": delivered.result_ref}
	return {"ok": true, "result_ref": contract_id, "journal_refs": [paid.result_ref, delivered.result_ref]}

static func settle(state, data: Dictionary, id: String, model: Dictionary, goal: Dictionary, settlement_context = null) -> Dictionary:
	if settlement_context != null and (settlement_context.state != state or settlement_context.scenario_data != data): return Contract.fail("生计结算须使用本次日结的实际工作上下文")
	var rules: Dictionary = data.get("management", {}).get("subsistence_rules", {})
	var account_id := id + "_rations"
	if not state.resource_accounts.has(account_id) or not Contract.amount(rules.get("daily_rations_per_person"), true) or not Contract.amount(rules.get("reserve_days"), true) or not str(rules.get("source_id", "")).begins_with("scenario:"): return Contract.fail("人物生计缺少实际口粮来源或消费规则：" + id)
	if not goal.has("subsistence"): goal["subsistence"] = {"last_day": 0, "total_required": 0, "total_consumed": 0, "total_missing": 0, "missing_today": 0, "consumption_refs": [], "purchase_refs": [], "periods": []}
	var needs: Dictionary = goal.subsistence
	var elapsed := int(state.current_day) - int(needs.last_day)
	if elapsed <= 0: return {"ok": true}
	var household := int(model.dependants) + 1
	var daily := int(rules.daily_rations_per_person)
	if household > Contract.MAX_AMOUNT / daily or elapsed > Contract.MAX_AMOUNT / (household * daily): return Contract.fail("家属口粮需求越界")
	var required := elapsed * household * daily
	if int(rules.reserve_days) > Contract.MAX_AMOUNT / (household * daily): return Contract.fail("家庭口粮储备需求越界")
	var target := maxi(required, int(rules.reserve_days) * household * daily)
	if int(needs.total_required) > Contract.MAX_AMOUNT - required: return Contract.fail("累计生计记录越界")
	var accounts := Accounts.new()
	var owned := accounts.available(state, account_id)
	var purchase := ""
	var location: String = state.character_states[id].get("location_id", "")
	if owned < required:
		var offers: Array = state.management_assets.values().filter(func(asset): return asset.get("asset_kind") == "food_stall" and asset.get("status") == "available" and asset.get("offer_visibility") == "public" and asset.get("location_id") == location)
		offers.sort_custom(func(a, b): return float(a.food_offer.price) / int(a.food_offer.lot_units) < float(b.food_offer.price) / int(b.food_offer.lot_units) if int(a.food_offer.price) * int(b.food_offer.lot_units) != int(b.food_offer.price) * int(a.food_offer.lot_units) else str(a.asset_id) < str(b.asset_id))
		for stall in offers:
			var offer: Dictionary = stall.food_offer
			var wanted := ceili(float(target - owned) / int(offer.lot_units))
			var shared_choice: bool = settlement_context != null and data.get("campaign_id") == "anshi_beta_1_14" and id != state.player_character_id
			var lots := mini(wanted, accounts.available(state, id + "_cash") / int(offer.price))
			if not shared_choice: lots = mini(lots, accounts.available(state, offer.stock_account_id) / int(offer.lot_units))
			if lots <= 0: continue
			var execution := "household-food:%s:%d" % [id, int(state.current_day)]
			var trade: Dictionary
			if shared_choice:
				trade = load("res://scripts/core/npc_decision_service.gd").settlement_food_choice(settlement_context, id, {"schema_version": 1, "kind": "action", "reason_code": "secure_household_meal_from_known_posted_offer", "action": {"action_kind": "buy_food", "parameters": {"stall_id": stall.asset_id, "lots": lots, "funding_account_id": id + "_cash"}, "target_refs": [stall.asset_id, id + "_cash"]}, "plan": {}, "resource_limits": []})
				if not trade.ok: return trade
			else:
				trade = load("res://scripts/core/game_action_dispatcher.gd").apply(state, data, {"execution_id": execution, "request_id": execution, "actor_id": id, "principal_id": id, "executor_id": id, "action_kind": "buy_food", "target_refs": [stall.asset_id], "parameters": {"stall_id": stall.asset_id, "lots": lots, "recipient_id": id, "funding_account_id": id + "_cash"}, "expected_state_revision": state.state_revision})
			if trade.get("ok", false) and trade.get("purchased", true):
				purchase = str(trade.result_ref)
				needs.purchase_refs.append(purchase)
				break
	var consumed := mini(required, accounts.available(state, account_id)) if accounts.location(state, account_id) == location else 0
	var receipt := ""
	if consumed > 0:
		receipt = "household-meal:%s:%d" % [id, int(state.current_day)]
		var ate := accounts.apply(state, "consume", {"actor_id": id, "execution_id": receipt, "source_account_id": account_id, "amount": consumed, "reason_ref": "rule:household_rations"})
		if not ate.ok: return ate
		needs.consumption_refs.append(receipt)
	needs.periods.append({"from_day": int(needs.last_day) + 1, "through_day": int(state.current_day), "household_size": household, "daily_units": daily, "required": required, "consumed": consumed, "missing": required - consumed, "receipt_ref": receipt, "purchase_ref": purchase})
	needs.last_day = int(state.current_day)
	needs.total_required += required
	needs.total_consumed += consumed
	needs.total_missing += required - consumed
	needs.missing_today = mini(household * daily, required - consumed)
	return {"ok": true}

static func validate_stall(raw: Dictionary, stall: Dictionary) -> Dictionary:
	var offer: Variant = stall.get("food_offer")
	if not offer is Dictionary or stall.get("status") not in ["available", "closed"] or stall.get("offer_visibility") != "public" or stall.owner_ref.get("entity_kind") != "character" or not Contract.amount(offer.get("lot_units"), true) or not Contract.amount(offer.get("price"), true): return Contract.fail("口粮摊缺少有效公开报价")
	for field in ["stock_account_id", "payee_account_id"]:
		var account: Dictionary = raw.resource_accounts.get(offer.get(field), {})
		if account.get("owner_ref") != stall.owner_ref or account.get("unit_id") != ("ration_unit" if field == "stock_account_id" else "cash_unit") or Accounts.new().location(raw, str(offer.get(field, ""))) != stall.location_id: return Contract.fail("口粮摊丢失实际卖方货物、收款账户或交割地")
	return {"ok": true}

static func validate_purchase(raw: Dictionary, contract: Dictionary) -> Dictionary:
	var offer: Variant = contract.get("offer")
	if contract.get("status") != "delivered" or not raw.character_states.has(contract.get("buyer_id")) or not raw.character_states.has(contract.get("seller_id")) or raw.management_assets.get(contract.get("stall_id"), {}).get("asset_kind") != "food_stall" or not offer is Dictionary: return Contract.fail("口粮交易丢失实际双方或摊位")
	for field in ["quantity", "amount", "lots"]:
		if not Contract.amount(contract.get(field), true): return Contract.fail("口粮交易数量或价格无效")
	if not Contract.amount(contract.get("day")) or int(contract.day) > int(raw.current_day) or not Contract.amount(offer.get("lot_units"), true) or not Contract.amount(offer.get("price"), true) or int(contract.quantity) != int(contract.lots) * int(offer.lot_units) or int(contract.amount) != int(contract.lots) * int(offer.price): return Contract.fail("口粮成交与当时报价不符")
	var paid: Dictionary = raw.resource_journal.get(contract.get("cash_ref"), {})
	var delivered: Dictionary = raw.resource_journal.get(contract.get("food_ref"), {})
	if paid.get("entry_kind") != "transfer" or paid.get("unit_id") != "cash_unit" or paid.get("amount") != contract.amount or paid.get("source_account_id") != str(contract.buyer_id) + "_cash" or paid.get("destination_account_id") != offer.get("payee_account_id") or paid.get("destination_ref", {}).get("entity_id") != contract.seller_id: return Contract.fail("口粮采购缺少实际货款")
	if delivered.get("entry_kind") != "transfer" or delivered.get("unit_id") != "ration_unit" or delivered.get("amount") != contract.quantity or delivered.get("source_account_id") != offer.get("stock_account_id") or delivered.get("destination_account_id") != str(contract.buyer_id) + "_rations" or delivered.get("source_ref", {}).get("entity_id") != contract.seller_id: return Contract.fail("口粮采购缺少实际交货")
	for entry in [paid, delivered]:
		if entry.get("reason_ref") != contract.contract_id or entry.get("day") != contract.day: return Contract.fail("口粮采购错引其他交易或日期")
	var receipt: Dictionary = raw.action_receipts.get(contract.get("execution_id"), {})
	if not receipt.get("effect_refs", []).has(contract.contract_id) or receipt.get("journal_refs") != [contract.cash_ref, contract.food_ref] or receipt.get("day") != contract.day: return Contract.fail("口粮采购丢失共同动作回执")
	return {"ok": true}

static func validate_household(raw: Dictionary, id: String, needs: Variant) -> Dictionary:
	if not needs is Dictionary: return Contract.fail("人物口粮记录不是对象")
	for field in ["last_day", "total_required", "total_consumed", "total_missing", "missing_today"]:
		if not Contract.amount(needs.get(field)): return Contract.fail("人物口粮记录缺少有效数量或日期：" + field)
	for field in ["consumption_refs", "purchase_refs", "periods"]:
		if not needs.get(field) is Array: return Contract.fail("人物口粮记录缺少实际凭据")
	if int(needs.last_day) > int(raw.current_day) or raw.resource_accounts.get(id + "_rations", {}).get("owner_ref") != {"entity_kind": "character", "entity_id": id}: return Contract.fail("人物口粮记录丢失本人库存或引用未来日")
	var through := 0
	var total_required := 0
	var total_consumed := 0
	var consumption_refs: Array = []
	var purchase_refs: Array = []
	var last_missing := 0
	for period in needs.periods:
		if not period is Dictionary: return Contract.fail("人物口粮期间无效")
		for field in ["from_day", "through_day", "household_size", "daily_units", "required"]:
			if not Contract.amount(period.get(field), true): return Contract.fail("人物口粮期间缺少有效需求")
		if not Contract.amount(period.get("consumed")) or not Contract.amount(period.get("missing")) or int(period.from_day) != through + 1 or int(period.through_day) < int(period.from_day) or int(period.household_size) > Contract.MAX_AMOUNT / int(period.daily_units): return Contract.fail("人物口粮期间重复、断裂或越界")
		var daily := int(period.household_size) * int(period.daily_units)
		if int(period.through_day) - int(period.from_day) + 1 > Contract.MAX_AMOUNT / daily or total_required > Contract.MAX_AMOUNT - int(period.required): return Contract.fail("人物口粮期间累计越界")
		if int(period.required) != (int(period.through_day) - int(period.from_day) + 1) * daily or int(period.consumed) + int(period.missing) != int(period.required): return Contract.fail("人物口粮消耗与实际家属需求不符")
		if not period.get("receipt_ref") is String or not period.get("purchase_ref") is String: return Contract.fail("人物口粮期间缺少凭据标识")
		if int(period.consumed) > 0:
			var consumed: Dictionary = raw.resource_journal.get(period.receipt_ref, {})
			if consumed.get("entry_kind") != "rule_consumption" or consumed.get("source_account_id") != id + "_rations" or consumed.get("amount") != period.consumed or consumed.get("reason_ref") != "rule:household_rations" or consumed.get("day") != period.through_day or consumption_refs.has(period.receipt_ref): return Contract.fail("人物口粮消耗没有唯一实际凭据")
			consumption_refs.append(period.receipt_ref)
		elif not period.receipt_ref.is_empty(): return Contract.fail("未进食却声称已有消耗凭据")
		if not period.purchase_ref.is_empty():
			var receipt: Dictionary = raw.action_receipts.get(period.purchase_ref, {})
			if not receipt.get("effect_refs", []).any(func(ref): return raw.economic_contracts.get(ref, {}).get("contract_kind") == "food_purchase" and raw.economic_contracts[ref].get("buyer_id") == id) or receipt.get("day") != period.through_day or purchase_refs.has(period.purchase_ref): return Contract.fail("人物买粮缺少唯一实际交易")
			purchase_refs.append(period.purchase_ref)
		through = int(period.through_day)
		total_required += int(period.required)
		total_consumed += int(period.consumed)
		last_missing = mini(daily, int(period.missing))
	if through != int(needs.last_day) or total_required != int(needs.total_required) or total_consumed != int(needs.total_consumed) or total_required - total_consumed != int(needs.total_missing) or last_missing != int(needs.missing_today) or consumption_refs != needs.consumption_refs or purchase_refs != needs.purchase_refs: return Contract.fail("人物生计汇总与真实期间或凭据不一致")
	return {"ok": true}
