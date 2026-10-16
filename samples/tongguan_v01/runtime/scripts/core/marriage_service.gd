extends RefCounted
const Rules = preload("res://scripts/core/management_state_contract.gd")
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Presence = preload("res://scripts/core/production_service.gd")
const SOURCE := "scenario:marriage_cui_mei_756"
const KINDS := ["inquire_marriage", "receive_marriage_terms", "accept_marriage_terms", "deliver_marriage_gift", "pay_marriage_dowry", "complete_marriage"]

static func merge_definitions(data: Dictionary, config: Variant) -> Dictionary:
	if not config is Dictionary or config.get("source_id") != SOURCE or not config.get("characters") is Array or not config.get("clan") is Dictionary or not config.get("matches") is Array or config.matches.is_empty() or not config.get("cash_grants") is Array or not config.get("ration_grants") is Array: return Rules.fail("联姻定义缺少明确人物、家庭及来源")
	for person in config.characters:
		if not person is Dictionary or data.characters.any(func(old): return old.id == person.get("id")): return Rules.fail("联姻人物重复")
		data.characters.append(person.duplicate(true))
	if data.tang_clans_definition.clans.any(func(old): return old.clan_id == config.clan.clan_id): return Rules.fail("联姻家庭重复")
	data.tang_clans_definition.clans.append(config.clan.duplicate(true))
	data.management.clan_cash_locations.append({"clan_id": config.clan.clan_id, "location_id": config.matches[0].location_id})
	data.management.character_cash_grants.append_array(config.cash_grants.duplicate(true))
	data.management.ration_grants.append_array(config.ration_grants.duplicate(true))
	for person in config.characters:
		data.management.initial_presence.append({"character_id": person.id, "location_id": person.location_id, "source_id": SOURCE})
		data.management.life_models[person.id] = {"minimum_reserve": 5, "dependants": 0, "tie_bonus": 0, "application_wait_days": 3, "review_interval_days": 1, "unpaid_grace_days": 3, "stable_goal": "support_family", "preferred_employer_id": config.clan.default_patriarch_id, "source_id": SOURCE}
	data.management["marriage_rules"] = {"source_id": SOURCE, "matches": config.matches.duplicate(true)}
	return {"ok": true}

static func initialize(state, data: Dictionary) -> Dictionary:
	state.flags["marriage_rules"] = data.get("management", {}).get("marriage_rules", {}).duplicate(true)
	return {"ok": true}

static func match_for(state, id: String) -> Dictionary:
	for match_row in state.flags.get("marriage_rules", {}).get("matches", []):
		if match_row.match_id == id: return match_row
	return {}

static func representative(state, account: String) -> String:
	for operator in state.resource_accounts.get(account, {}).get("operator_refs", []):
		if Accounts.new().can_operate(state, account, operator.entity_id): return operator.entity_id
	return ""

static func ready(state, match_row: Dictionary, except_id: String = "") -> Dictionary:
	var actual_consent: bool = state.economic_contracts.values().any(func(row): return row.get("purpose") == "person_arrangement" and row.get("status") == "fulfilled" and row.terms.get("arrangement_kind") == "marriage" and row.terms.get("role_ref") == match_row.match_id and row.participant_ids.all(func(person): return row.accepted_versions.get(person) == row.terms_version))
	for person in [match_row.party_a, match_row.party_b]:
		var other: String = match_row.party_b if person == match_row.party_a else match_row.party_a
		var consent: Dictionary = match_row.consent[person]
		if int(consent.age) < 18 or (not actual_consent and (not consent.willing or int(state.character_states[person].get("relationships", {}).get(other, 0)) < int(consent.minimum_relation))): return Rules.fail("至少一方尚未表达当前婚配意愿或不符合成年条件")
		if not Presence.present(state, person, match_row.location_id): return Rules.fail("婚配本人尚未实际到场或已不能办理")
		for row in state.economic_contracts.values():
			if row.get("contract_kind") == "marriage" and row.contract_id != except_id and row.get("status") in ["committed", "married"] and person in [row.party_a, row.party_b]: return Rules.fail("本人已有另一项婚约或婚配，不能重复安排")
	var counter := representative(state, match_row.counter_account)
	if not match_row.counter_willing or counter == "" or not Presence.present(state, counter, match_row.location_id): return Rules.fail("对方家庭未同意或实际代表未在场")
	return {"ok": true, "counter_id": counter}

static func cost_for(state, kind: String, params: Dictionary) -> Dictionary:
	var match_row := match_for(state, str(params.get("match_id", "")))
	if match_row.is_empty() or not params.get("proposal_id") is String or not params.proposal_id.begins_with("marriage:"): return Rules.fail("联姻需引用明确双方及独立记录")
	if kind == "inquire_marriage":
		if not Rules.amount(params.get("offered_gift"), true): return Rules.fail("探询须提出实际礼金额度")
		return {"ok": true, "account_id": "", "amount": 0}
	var row: Dictionary = state.economic_contracts.get(params.proposal_id, {})
	if row.get("contract_kind") != "marriage" or row.get("match_id") != match_row.match_id: return {"ok": false, "code": "asset_not_ready", "error": "尚无对应真实探询"}
	if kind == "deliver_marriage_gift":
		if not row.has("terms"): return Rules.fail("尚未收到实际婚配条件")
		return {"ok": true, "account_id": match_row.sponsor_account, "amount": int(row.terms.gift)}
	if kind == "pay_marriage_dowry": return {"ok": true, "account_id": match_row.counter_account, "amount": int(row.get("terms", {}).get("dowry", 0))}
	return {"ok": true, "account_id": "", "amount": 0}

static func apply(state, kind: String, params: Dictionary, principal: String, execution: String, reservation: String) -> Dictionary:
	var cost := cost_for(state, kind, params)
	if not cost.ok: return cost
	var match_row := match_for(state, params.match_id)
	var account: String = match_row.counter_account if kind == "pay_marriage_dowry" else match_row.sponsor_account
	if not Accounts.new().can_operate(state, account, principal): return Rules.fail("本人无权代表该家庭承担联姻财产安排")
	if kind == "inquire_marriage":
		if state.economic_contracts.has(params.proposal_id) or state.economic_contracts.values().any(func(old): return old.get("contract_kind") == "marriage" and old.match_id == params.match_id and old.status != "declined"): return Rules.fail("已有该双方的探询、婚约或婚配")
		state.economic_contracts[params.proposal_id] = {"contract_id": params.proposal_id, "contract_kind": "marriage", "source_id": SOURCE, "match_id": params.match_id, "party_a": match_row.party_a, "party_b": match_row.party_b, "principal_id": principal, "location_id": match_row.location_id, "created_day": int(state.current_day), "offered_gift": int(params.offered_gift), "status": "inquiring", "inquiry_receipt": execution, "history": [], "blocked_reason": "等待本人及对方家庭实际答复。"}
		return result(state.economic_contracts[params.proposal_id], kind, execution, int(state.current_day), "已探询；没有签订婚约、支付礼金或婚配。")
	var row: Dictionary = state.economic_contracts[params.proposal_id]
	if kind == "receive_marriage_terms":
		if row.status == "inquiring": return {"ok": false, "code": "awaiting_delivery", "error": "尚未收到实际答复"}
		return result(row, kind, execution, int(state.current_day), row.blocked_reason if row.status == "declined" else "已收到双方表达及家庭条件；完整安排须另行授权。")
	var consent := ready(state, match_row, row.contract_id)
	if not consent.ok: return consent
	if kind == "accept_marriage_terms":
		if row.status != "offered": return Rules.fail("只有实际收到的条件可以另行接受")
		if Accounts.new().available(state, match_row.counter_account) < int(row.terms.dowry): return Rules.fail("对方家产不足兑现其实际承诺")
		row.status = "committed"
		row["commit_day"] = int(state.current_day)
		row["accepted_terms"] = row.terms.duplicate(true)
		row["signatures"] = {"sponsor_id": principal, "counter_id": consent.counter_id, "party_a": row.party_a, "party_b": row.party_b, "day": int(state.current_day)}
		return result(row, kind, execution, int(state.current_day), "已接受共同条件；礼金、对方承诺及双方意愿仍须实际落实。")
	if row.status != "committed": return Rules.fail("尚无已授权接受的共同婚约")
	if kind in ["deliver_marriage_gift", "pay_marriage_dowry"]:
		var gift: bool = kind == "deliver_marriage_gift"
		var field: String = "gift_ref" if gift else "dowry_ref"
		if row.has(field) or (not gift and not row.has("gift_ref")): return Rules.fail("款项已经交付或前序礼金尚未落实")
		var target: String = match_row.counter_account if gift else str(row.party_b) + "_cash"
		var payment := Accounts.new().apply(state, "transfer", {"execution_id": execution, "source_account_id": account, "destination_account_id": target, "amount": int(cost.amount), "actor_id": principal, "reason_ref": row.contract_id, "reservation_id": reservation})
		if not payment.get("ok", false): return payment
		row[field] = execution
		var response := result(row, kind, execution, int(state.current_day), "已完成实际礼金交割。" if gift else "对方已从自有家产履行随嫁财产承诺，财产仍归本人。")
		response["journal_refs"] = [execution]
		return response
	if kind == "complete_marriage":
		if not row.has("gift_ref") or not row.has("dowry_ref") or int(state.current_day) < int(row.commit_day) + int(match_row.arrangement_days): return {"ok": false, "code": "awaiting_delivery", "error": "婚配安排尚待实际交割或约定日期"}
		row.blocked_reason = "双方已确认成婚；礼金与随嫁财产均已实际交割。"
		row.status = "married"
		row["married_day"] = int(state.current_day)
		row["relationship_events"] = []
		for person in [row.party_a, row.party_b]:
			var other: String = row.party_b if person == row.party_a else row.party_a
			var relationships: Dictionary = state.character_states[person].relationships
			var before: int = int(relationships.get(other, 0))
			relationships[other] = clampi(before + 10, -100, 100)
			row.relationship_events.append({"person_id": person, "other_id": other, "before": before, "after": relationships[other]})
		return result(row, kind, execution, int(state.current_day), "双方当场确认婚配；个人财产、职务及已有义务继续分别保留。")
	return Rules.fail("未知联姻步骤")

static func result(row: Dictionary, kind: String, execution: String, day: int, text: String) -> Dictionary:
	var record := {"proposal_id": row.contract_id, "match_id": row.match_id, "party_a": row.party_a, "party_b": row.party_b, "kind": kind, "day": day}
	row.history.append({"kind": kind, "receipt": execution, "day": day})
	return {"ok": true, "result_ref": row.contract_id, "marriage_record": record, "visible_summary": text}

static func settle_daily(state, data: Dictionary) -> Dictionary:
	for row in state.economic_contracts.values():
		if row.get("contract_kind") != "marriage": continue
		var match_row := match_for(state, row.match_id)
		if row.status == "inquiring" and int(state.current_day) >= int(row.created_day) + int(match_row.reply_days):
			# Missing people cannot send an invented response. Refusal requires actual presence.
			var counter := representative(state, match_row.counter_account)
			if not Presence.present(state, row.party_a, row.location_id) or not Presence.present(state, row.party_b, row.location_id) or not Presence.present(state, counter, row.location_id): continue
			var consent := ready(state, match_row, row.contract_id)
			row["reply_day"] = int(state.current_day)
			row["reply"] = {"party_a": row.party_a, "party_b": row.party_b, "counter_id": counter, "accepted": consent.ok, "day": int(state.current_day)}
			row.status = "offered" if consent.ok else "declined"
			row.blocked_reason = "双方表达愿意继续商议；家庭要求礼金 %d、承诺随嫁财产 %d。接受前须另行确认。" % [maxi(int(row.offered_gift), int(match_row.minimum_gift)), int(match_row.dowry)] if consent.ok else consent.error
			if consent.ok: row["terms"] = {"gift": maxi(int(row.offered_gift), int(match_row.minimum_gift)), "dowry": int(match_row.dowry), "gift_account": match_row.counter_account, "dowry_account": str(row.party_b) + "_cash", "gift_refundable": false}
		elif row.status == "committed" and row.has("gift_ref") and not row.has("dowry_ref"):
			var counter := representative(state, match_row.counter_account)
			if counter == "": continue
			var execution := "marriage-dowry:" + str(row.contract_id)
			var paid: Dictionary = load("res://scripts/core/game_action_dispatcher.gd").apply(state, data, {"execution_id": execution, "request_id": execution, "actor_id": counter, "principal_id": counter, "executor_id": counter, "action_kind": "pay_marriage_dowry", "parameters": {"match_id": row.match_id, "proposal_id": row.contract_id}, "target_refs": [row.match_id], "expected_state_revision": state.state_revision})
			if not paid.get("ok", false): row.blocked_reason = str(paid.get("error", "对方承诺尚未交割"))
	return {"ok": true}

static func project(state, viewer: String) -> Array:
	var result_rows: Array = []
	for match_row in state.flags.get("marriage_rules", {}).get("matches", []):
		if not Accounts.new().can_operate(state, match_row.sponsor_account, viewer) or not Presence.present(state, viewer, match_row.location_id): continue
		var row := {"match_id": match_row.match_id, "name": match_row.name, "party_a": match_row.party_a, "party_b": match_row.party_b, "account_id": match_row.sponsor_account, "proposals": []}
		for proposal in state.economic_contracts.values():
			if proposal.get("contract_kind") != "marriage" or proposal.match_id != match_row.match_id: continue
			var visible := {"proposal_id": proposal.contract_id, "status": proposal.status, "text": proposal.blocked_reason, "created_day": proposal.created_day, "married_day": proposal.get("married_day", -1), "gift_paid": proposal.has("gift_ref"), "dowry_paid": proposal.has("dowry_ref")}
			if proposal.has("terms"): visible["terms"] = proposal.terms.duplicate(true)
			row.proposals.append(visible)
		result_rows.append(row)
	return result_rows

static func validate(raw: Dictionary) -> Dictionary:
	var rules: Variant = raw.get("flags", {}).get("marriage_rules", {})
	if not rules is Dictionary: return Rules.fail("联姻规则类型无效")
	var matches := {}
	if not rules.is_empty():
		if rules.get("source_id") != SOURCE or not rules.get("matches") is Array: return Rules.fail("联姻缺少来源")
		for row in rules.matches:
			if not row is Dictionary or not row.get("match_id") is String or matches.has(row.match_id) or not raw.character_states.has(row.get("party_a")) or not raw.character_states.has(row.get("party_b")) or row.party_a == row.party_b or not row.get("consent") is Dictionary or not row.get("counter_willing") is bool: return Rules.fail("联姻缺少不同的实际双方及意愿")
			for person in [row.party_a, row.party_b]:
				var consent: Variant = row.consent.get(person)
				if not consent is Dictionary or not Rules.amount(consent.get("age"), true) or not consent.get("willing") is bool or not (consent.get("minimum_relation") is int or consent.get("minimum_relation") is float): return Rules.fail("联姻成年与意愿定义无效")
			for key in ["minimum_gift", "dowry", "reply_days", "arrangement_days"]:
				if not Rules.amount(row.get(key), true): return Rules.fail("联姻额度或约定日期无效")
			if not raw.resource_accounts.has(row.get("sponsor_account")) or not raw.resource_accounts.has(row.get("counter_account")) or not raw.local_node_state.has(row.get("location_id")): return Rules.fail("联姻财产来源或实际地点缺失")
			matches[row.match_id] = row
	var committed := {}
	for row in raw.get("economic_contracts", {}).values():
		if row.get("contract_kind") != "marriage": continue
		if not matches.has(row.get("match_id")) or row.get("source_id") != SOURCE or not row.get("history") is Array or not raw.character_states.has(row.get("principal_id")): return Rules.fail("婚配记录缺少实际来源或履历")
		var model: Dictionary = matches[row.match_id]
		if row.get("party_a") != model.party_a or row.get("party_b") != model.party_b or row.get("location_id") != model.location_id or not Rules.amount(row.get("created_day")) or not Rules.amount(row.get("offered_gift"), true): return Rules.fail("婚配双方、地点或初次交涉无效")
		var kinds: Array = []
		var events := {}
		var last_day: int = int(row.created_day)
		for event in row.history:
			if not event is Dictionary or event.get("kind") not in KINDS or not Rules.amount(event.get("day")) or int(event.day) < int(row.created_day) or int(event.day) > int(raw.current_day): return Rules.fail("婚配履历日期或动作无效")
			if int(event.day) < last_day: return Rules.fail("婚配履历日期逆序")
			last_day = int(event.day)
			events[event.kind] = event
			var receipt: Dictionary = raw.action_receipts.get(event.get("receipt"), {})
			if receipt.get("marriage_record") != {"proposal_id": row.contract_id, "match_id": row.match_id, "party_a": row.party_a, "party_b": row.party_b, "kind": event.kind, "day": event.day} or not receipt.get("effect_refs", []).has(row.contract_id): return Rules.fail("婚配步骤缺少明确双方的共同回执")
			if event.kind != "receive_marriage_terms" and kinds.has(event.kind): return Rules.fail("婚配承诺或支付重复")
			kinds.append(event.kind)
		if kinds.is_empty() or kinds[0] != "inquire_marriage" or row.history[0].receipt != row.get("inquiry_receipt"): return Rules.fail("婚配缺少初次探询")
		if row.status not in ["committed", "married"]:
			for key in ["commit_day", "accepted_terms", "signatures", "gift_ref", "dowry_ref", "married_day", "relationship_events"]:
				if row.has(key): return Rules.fail("未承诺的探询夹带已签约或交割状态")
			for kind in kinds:
				if kind not in ["inquire_marriage", "receive_marriage_terms"]: return Rules.fail("探询阶段不能包含婚约执行履历")
		if row.status != "married" and (kinds.has("complete_marriage") or row.has("married_day") or row.has("relationship_events")): return Rules.fail("婚配完成履历与当前阶段不符")
		if row.status == "inquiring" and (row.has("reply") or row.has("terms") or row.has("reply_day")): return Rules.fail("未回复的探询不能包含答复")
		if row.status in ["offered", "declined", "committed", "married"]:
			if not row.get("reply") is Dictionary or not Rules.amount(row.get("reply_day")) or int(row.reply_day) < int(row.created_day) + int(model.reply_days) or int(row.reply_day) > int(raw.current_day) or row.reply.get("party_a") != row.party_a or row.reply.get("party_b") != row.party_b or not raw.character_states.has(row.reply.get("counter_id")): return Rules.fail("婚配没有实际双方与家庭的答复")
			if row.reply.get("day") != row.reply_day or not row.reply.get("accepted") is bool: return Rules.fail("婚配答复日期或意愿类型无效")
			if row.status == "declined" and (row.reply.accepted or row.has("terms")): return Rules.fail("拒绝不能夹带同意条件")
			if row.status != "declined":
				if not row.reply.get("accepted", false) or not row.get("terms") is Dictionary or row.terms.get("gift") != maxi(int(row.offered_gift), int(model.minimum_gift)) or row.terms.get("dowry") != model.dowry or row.terms.get("gift_account") != model.counter_account or row.terms.get("dowry_account") != str(row.party_b) + "_cash" or row.terms.get("gift_refundable") != false: return Rules.fail("婚配条件没有对应实际交涉")
		elif row.status != "inquiring": return Rules.fail("婚配状态无效")
		if row.status in ["committed", "married"]:
			if not kinds.has("accept_marriage_terms") or row.get("accepted_terms") != row.terms or not row.get("signatures") is Dictionary or not Rules.amount(row.get("commit_day")) or int(row.commit_day) < int(row.reply_day): return Rules.fail("婚约缺少另行接受与双方签署")
			if row.signatures.get("party_a") != row.party_a or row.signatures.get("party_b") != row.party_b or row.signatures.get("sponsor_id") != row.principal_id or not raw.character_states.has(row.signatures.get("counter_id")) or row.signatures.get("day") != row.commit_day or events.accept_marriage_terms.day != row.commit_day: return Rules.fail("婚约签署人物与实际双方或接受日期不符")
			for person in [row.party_a, row.party_b]:
				if committed.has(person): return Rules.fail("同一人物有重复婚约或婚配")
				committed[person] = true
		if row.has("dowry_ref") and not row.has("gift_ref"): return Rules.fail("对方交割缺少前序礼金")
		for pair in [["gift_ref", "deliver_marriage_gift"], ["dowry_ref", "pay_marriage_dowry"]]:
			if row.has(pair[0]) != kinds.has(pair[1]): return Rules.fail("交割履历与款项引用不一致")
			if row.has(pair[0]) and (events[pair[1]].receipt != row[pair[0]] or int(events[pair[1]].day) < int(row.get("commit_day", -1))): return Rules.fail("交割先于承诺或引用另一流水")
		if row.has("dowry_ref") and int(events.pay_marriage_dowry.day) < int(events.deliver_marriage_gift.day): return Rules.fail("交割顺序无效")
		for field in ["gift_ref", "dowry_ref"]:
			if not row.has(field): continue
			var gift: bool = field == "gift_ref"
			var payment: Dictionary = raw.resource_journal.get(row[field], {})
			if not kinds.has("deliver_marriage_gift" if gift else "pay_marriage_dowry") or payment.get("entry_kind") != "transfer" or payment.get("reason_ref") != row.contract_id or payment.get("source_account_id") != (model.sponsor_account if gift else model.counter_account) or payment.get("destination_account_id") != (model.counter_account if gift else str(row.party_b) + "_cash") or payment.get("amount") != row.terms.get("gift" if gift else "dowry"): return Rules.fail("婚约交割缺少实际款源、收款人和流水")
		if row.status == "married":
			if not kinds.has("complete_marriage") or not row.has("gift_ref") or not row.has("dowry_ref") or not Rules.amount(row.get("married_day")) or int(row.married_day) < int(row.commit_day) + int(model.arrangement_days) or not row.get("relationship_events") is Array or row.relationship_events.size() != 2: return Rules.fail("婚配完成缺少日期、真实交割或人物后果")
			if events.complete_marriage.day != row.married_day or int(row.married_day) < int(events.pay_marriage_dowry.day): return Rules.fail("成婚日期与交割或共同动作不符")
			var related: Array = []
			for event in row.relationship_events:
				if not event is Dictionary or related.has(event.get("person_id")): return Rules.fail("婚配关系后果重复")
				related.append(event.get("person_id"))
				if event.get("person_id") not in [row.party_a, row.party_b] or event.get("other_id") != (row.party_b if event.person_id == row.party_a else row.party_a) or event.get("after") != clampi(int(event.get("before", 0)) + 10, -100, 100): return Rules.fail("婚配关系后果无效")
	return {"ok": true}
