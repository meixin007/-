extends RefCounted
const C = preload("res://scripts/core/npc_ai_state_contract.gd")
const Items = preload("res://scripts/core/managed_item_service.gd")
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Travel = preload("res://scripts/core/regional_visit_service.gd")
const KINDS := ["respond_gift_delivery", "cancel_gift_delivery", "receive_gift_report"]
const FIELDS := ["contract_id", "contract_kind", "agreement_ref", "sender_id", "carrier_id", "recipient_id", "item_id", "origin", "destination", "journey_ref", "return_journey_ref", "status", "created_day", "resolution_day", "reported_day", "report_due_day", "cancel_requested", "resolution_receipt", "blocked_reason"]

func respond(context, actor: String, delivery: String, choice: String, execution: String) -> Dictionary:
	return _execute(context, actor, "respond_gift_delivery", {"delivery_id": delivery, "choice": choice}, execution)

func _execute(context, actor: String, kind: String, params: Dictionary, execution: String) -> Dictionary:
	var dispatcher = load("res://scripts/core/game_action_dispatcher.gd").new()
	var selection := {"action_kind": kind, "parameters": params, "target_refs": [params.delivery_id]}
	return dispatcher.execute(context, dispatcher.bind_npc_request(context.state, actor, selection, execution)) if actor == context.state.player_character_id else dispatcher.execute_npc(context, actor, selection, execution)

static func validate_terms(state, terms: Variant) -> Dictionary:
	if not C.exact(terms, ["item_id", "recipient_id", "destination_id", "fee_amount", "funding_account_id"]) or not state.management_assets.has(terms.item_id) or not state.character_states.has(terms.recipient_id) or not Travel.destinations(state).has(terms.destination_id) or not C.whole(terms.fee_amount, 1) or state.resource_accounts.get(terms.funding_account_id, {}).get("unit_id") != "cash_unit": return C.fail("递送条件须引用实物、受赠人、目的地和实际旅费账户")
	return {"ok": true}

static func offer_allowed(state, actor: String, carrier: String, terms: Dictionary) -> Dictionary:
	var allowed: Dictionary = Items.disposition(state, terms.item_id, actor)
	if not allowed.ok: return allowed
	if carrier == terms.recipient_id or actor == terms.recipient_id or not Accounts.new().can_operate(state, terms.funding_account_id, actor): return C.fail("递送三方及付款权源无效")
	if state.management_assets[terms.item_id].location_id != state.character_states[actor].location_id: return C.fail("实际礼物尚未在交付地点")
	return {"ok": true}

static func start(state, agreement: Dictionary, execution: String, reservation: String = "") -> Dictionary:
	var terms: Dictionary = agreement.terms
	var sender: String = agreement.principal_id
	var carrier: String = agreement.participant_ids[1]
	var valid := offer_allowed(state, sender, carrier, terms)
	if not valid.ok: return valid
	if state.character_states[carrier].get("location_id") != state.character_states[sender].get("location_id") or Accounts.new().location(state, terms.funding_account_id) != state.character_states[sender].get("location_id"): return C.fail("使者或旅费账户不在实物交付地点，不能远程改变保管人")
	var quote: Dictionary = Travel.quote(state, terms.destination_id, carrier)
	if not quote.ok: return quote
	if terms.fee_amount < 2 * quote.amount: return C.fail("约定旅费不足覆盖去程与拒收返程，须重议实际费用")
	var paid: Dictionary = Accounts.new().apply(state, "transfer", {"execution_id": execution + ":allowance", "source_account_id": terms.funding_account_id, "destination_account_id": carrier + "_cash", "amount": terms.fee_amount, "actor_id": sender, "reason_ref": agreement.contract_id, "reservation_id": reservation})
	if not paid.ok: return paid
	var trip: Dictionary = Travel.apply(state, {"destination_id": terms.destination_id}, carrier, carrier, execution)
	if not trip.ok: return trip
	var id := "gift:" + execution
	state.economic_contracts[id] = {"contract_id": id, "contract_kind": "gift_delivery", "agreement_ref": agreement.contract_id, "sender_id": sender, "carrier_id": carrier, "recipient_id": terms.recipient_id, "item_id": terms.item_id, "origin": quote.origin, "destination": terms.destination_id, "journey_ref": execution, "return_journey_ref": "", "status": "en_route", "created_day": state.current_day, "resolution_day": -1, "reported_day": -1, "report_due_day": -1, "cancel_requested": false, "resolution_receipt": "", "blocked_reason": ""}
	var asset: Dictionary = state.management_assets[terms.item_id]
	asset.custodian_ref = {"entity_kind": "character", "entity_id": carrier}
	asset.location_id = state.character_states[carrier].location_id
	asset.equipped_by = ""
	asset.contract_refs.append(id)
	return {"ok": true, "result_ref": id, "journal_refs": [paid.result_ref, execution + ":fare"], "regional_visit": {"person_id": carrier, "destination": terms.destination_id, "origin": quote.origin}, "visible_summary": "礼物交由本人保管，已支付约定旅费并实际启程；受赠人尚未接受。"}

static func cost_for(state, _kind: String, params: Dictionary) -> Dictionary:
	if state.economic_contracts.get(params.get("delivery_id"), {}).get("contract_kind") != "gift_delivery": return C.fail("不存在这份实际递送")
	return {"ok": true, "account_id": "", "amount": 0}

static func apply(state, kind: String, params: Dictionary, actor: String, execution: String) -> Dictionary:
	var row: Dictionary = state.economic_contracts[params.delivery_id]
	if kind == "cancel_gift_delivery":
		if actor != row.sender_id or row.status not in ["en_route", "awaiting_response"]: return C.fail("仅原送礼者可撤销尚未交割的递送")
		row.cancel_requested = true
		return {"ok": true, "result_ref": row.contract_id, "visible_summary": "已撤销未交割礼物，保管人将按实际行程返还；已花旅费仍保留。"}
	if kind == "receive_gift_report":
		var claim: Dictionary = state.information_claims.get("gift-report:" + str(row.contract_id) + ":" + str(row.status), {}).get(actor, {})
		if actor != row.sender_id or claim.is_empty(): return C.fail("实际回报尚未送达本人")
		row.reported_day = state.current_day
		return {"ok": true, "result_ref": row.contract_id, "visible_summary": "已收到递送回报：" + row.status}
	if actor != row.recipient_id or row.status != "awaiting_response" or params.get("choice") not in ["accept", "reject"]: return C.fail("只能由实际受赠人回应待接洽礼物")
	if state.character_states[actor].get("status") in Items.UNAVAILABLE_STATUSES or state.character_states[actor].get("location_id") != row.destination or state.character_states[row.carrier_id].get("location_id") != row.destination: return C.fail("受赠人或保管人尚不能在交割地点办理")
	if row.cancel_requested: return C.fail("原送礼者已经撤销，不能继续交割")
	row.resolution_receipt = execution
	row.resolution_day = state.current_day
	row.report_due_day = state.current_day + state.flags[Travel.KEY][row.journey_ref].required_days
	if params.choice == "reject":
		row.status = "return_pending"
		var notified := notify_report(state, row, actor)
		if not notified.ok: return notified
		return {"ok": true, "result_ref": row.contract_id, "visible_summary": "本人拒收；实物仍由保管人负责返还。"}
	var asset: Dictionary = state.management_assets[row.item_id]
	asset.owner_ref = {"entity_kind": "character", "entity_id": actor}
	asset.custodian_ref = asset.owner_ref.duplicate(true)
	var history: Array = asset.get("transfer_history", []).duplicate(true)
	history.append({"execution_id": execution, "from_ref": {"entity_kind": "character", "entity_id": row.sender_id}, "to_ref": asset.owner_ref.duplicate(true), "day": state.current_day, "consent_rule": "gift_agreement", "contract_id": row.contract_id})
	asset["transfer_history"] = history
	if row.sender_id == state.player_character_id: state.inventory = state.inventory.filter(func(ref): return ref.id != row.item_id)
	if actor == state.player_character_id: state.inventory.append({"id": row.item_id, "asset_ref": row.item_id})
	row.status = "received"
	var notified := notify_report(state, row, actor)
	if not notified.ok: return notified
	return {"ok": true, "result_ref": row.contract_id, "effect_refs": [row.contract_id, row.item_id], "visible_summary": "本人已接受，礼物实际交割；远方送礼者须等回报。"}

static func notify_report(state, row: Dictionary, reporter: String) -> Dictionary:
	var fact: String = "gift-report:" + str(row.contract_id) + ":" + str(row.status)
	if state.information_truths.has(fact): return {"ok": true}
	var local: bool = state.character_states[reporter].get("location_id") == state.character_states[row.sender_id].get("location_id")
	var holders: Array = [reporter]
	for person in [row.carrier_id, row.sender_id]:
		if not holders.has(person) and state.character_states[person].get("location_id") == state.character_states[reporter].get("location_id"): holders.append(person)
	var info = load("res://scripts/core/information_propagation_service.gd").new()
	var made: Dictionary = info.create_fact(state, {"fact_id": fact, "truth_payload": {"delivery_id": row.contract_id, "status": row.status, "summary": "礼物递送已办理：" + row.status}, "holders": holders, "secrecy": "private", "source_context": {"context_kind": "office_observation", "context_id": fact, "related_report_id": row.resolution_receipt if row.resolution_receipt != "" else row.return_journey_ref}})
	if not made.ok or local: return made
	return info.queue_dispatch(state, fact, reporter, row.sender_id)

static func project(state, row: Dictionary, viewer: String) -> Dictionary:
	if row.carrier_id == viewer or (row.recipient_id == viewer and state.character_states[viewer].get("location_id") == row.destination and state.character_states[row.carrier_id].get("location_id") == row.destination): return row.duplicate(true)
	if row.sender_id != viewer: return {}
	var known := "en_route"
	var known_day := -1
	for holders in state.information_claims.values():
		var report: Dictionary = holders.get(viewer, {})
		if report.get("payload", {}).get("delivery_id") == row.contract_id and report.known_day > known_day:
			known = report.payload.status
			known_day = report.known_day
	return {"contract_id": row.contract_id, "contract_kind": "gift_delivery", "agreement_ref": row.agreement_ref, "sender_id": row.sender_id, "carrier_id": row.carrier_id, "recipient_id": row.recipient_id, "item_id": row.item_id, "destination": row.destination, "status": known, "known_day": known_day}

static func settle(state, data: Dictionary) -> Dictionary:
	var dispatcher = load("res://scripts/core/game_action_dispatcher.gd")
	for row in state.economic_contracts.values():
		if row.get("contract_kind") != "gift_delivery": continue
		var trip: Dictionary = state.flags.get(Travel.KEY, {}).get(row.journey_ref, {})
		if row.status == "en_route": row.blocked_reason = trip.get("blocked_reason", "")
		if row.status in ["en_route", "awaiting_response", "return_pending", "returning"]:
			state.management_assets[row.item_id].location_id = state.character_states[row.carrier_id].get("location_id", "")
		if row.status == "en_route" and trip.get("status") == "arrived": row.status = "return_pending" if row.cancel_requested else "awaiting_response"
		if row.status == "awaiting_response" and row.cancel_requested: row.status = "return_pending"
		if row.status == "return_pending":
			var execution: String = row.contract_id + ":return"
			var selection := {"action_kind": "visit_region", "parameters": {"destination_id": row.origin}, "target_refs": [row.origin]}
			var returned: Dictionary = dispatcher.apply(state, data, dispatcher.bind_npc_request(state, row.carrier_id, selection, execution))
			if returned.ok:
				row.return_journey_ref = execution
				row.status = "returning"
				row.blocked_reason = ""
			else: row.blocked_reason = returned.get("error", "返程受阻，实际保管责任仍保留。")
		if row.status == "returning" and state.flags[Travel.KEY].get(row.return_journey_ref, {}).get("status") == "arrived":
			row.status = "returned"
			var asset: Dictionary = state.management_assets[row.item_id]
			asset.custodian_ref = asset.owner_ref.duplicate(true)
			row.resolution_day = state.current_day
			row.report_due_day = state.current_day
			var notified := notify_report(state, row, row.carrier_id)
			if not notified.ok: return notified
	return {"ok": true}

static func custody_valid(raw: Dictionary, asset: Dictionary) -> bool:
	return raw.get("economic_contracts", {}).values().any(func(row): return row.get("contract_kind") == "gift_delivery" and row.get("item_id") == asset.asset_id and row.get("status") in ["en_route", "awaiting_response", "return_pending", "returning"] and asset.owner_ref == {"entity_kind": "character", "entity_id": row.sender_id} and asset.custodian_ref == {"entity_kind": "character", "entity_id": row.carrier_id} and asset.location_id == raw.character_states[row.carrier_id].get("location_id"))

static func validate(raw: Dictionary, row: Dictionary) -> Dictionary:
	if not C.exact(row, FIELDS) or row.status not in ["en_route", "awaiting_response", "received", "return_pending", "returning", "returned"] or not row.cancel_requested is bool: return C.fail("递送状态或字段无效")
	var agreement: Dictionary = raw.economic_contracts.get(row.agreement_ref, {})
	var asset: Dictionary = raw.management_assets.get(row.item_id, {})
	var trip: Dictionary = raw.flags.get(Travel.KEY, {}).get(row.journey_ref, {})
	if agreement.get("purpose") != "gift_delivery" or agreement.get("status") != "fulfilled" or agreement.get("principal_id") != row.sender_id or agreement.get("participant_ids", []).size() != 2 or agreement.participant_ids[1] != row.carrier_id or agreement.terms.recipient_id != row.recipient_id or agreement.terms.item_id != row.item_id or not agreement.result_refs.has(row.contract_id) or not raw.character_states.has(row.recipient_id): return C.fail("递送丢失真实双方约定")
	if trip.get("person_id") != row.carrier_id or trip.get("origin") != row.origin or trip.get("destination") != row.destination or trip.get("created_day") != row.created_day: return C.fail("递送丢失实际去程")
	var paid: Dictionary = raw.resource_journal.get(row.journey_ref + ":allowance", {})
	if paid.get("source_account_id") != agreement.terms.funding_account_id or paid.get("destination_account_id") != row.carrier_id + "_cash" or paid.get("amount") != agreement.terms.fee_amount or paid.get("reason_ref") != row.agreement_ref: return C.fail("递送旅费未实际交付")
	for field in ["created_day", "resolution_day", "reported_day", "report_due_day"]:
		if not C.whole(row[field], -1) or (field != "report_due_day" and row[field] > raw.current_day): return C.fail("递送日期无效")
	if row.status in ["en_route", "awaiting_response", "return_pending", "returning"] and not custody_valid(raw, asset): return C.fail("在途礼物丢失保管人或位置")
	if row.status == "received" and (not asset.get("transfer_history", []).any(func(entry): return entry.get("execution_id") == row.resolution_receipt and entry.get("to_ref") == {"entity_kind": "character", "entity_id": row.recipient_id} and entry.get("contract_id") == row.contract_id) or not raw.action_receipts.get(row.resolution_receipt, {}).get("effect_refs", []).has(row.item_id)): return C.fail("受赠结果丢失独立接受和实际交割")
	if row.reported_day >= 0 and not raw.get("information_claims", {}).values().any(func(holders): return holders.get(row.sender_id, {}).get("payload", {}).get("delivery_id") == row.contract_id): return C.fail("递送获报缺少本人实际收到的消息")
	if row.status in ["returning", "returned"] and raw.flags.get(Travel.KEY, {}).get(row.return_journey_ref, {}).get("destination") != row.origin: return C.fail("返还缺少实际返程")
	return {"ok": true}
