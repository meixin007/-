extends RefCounted
const Rules = preload("res://scripts/core/management_state_contract.gd")
const Accounts = preload("res://scripts/core/resource_account_service.gd")
const Presence = preload("res://scripts/core/production_service.gd")
const SOURCE := "scenario:clan_handover_756"
const KINDS := ["handover_clan_head", "assume_clan_head"]

static func initialize(state, data: Dictionary) -> Dictionary:
	var config: Dictionary = data.get("management", {}).get("succession_rules", {})
	if config.is_empty(): return {"ok": true}
	var heads := {}
	for clan in config.clans: heads[clan.clan_id] = clan.initial_head_id
	state.flags["clan_succession"] = {"source_id": SOURCE, "rules": config.clans.duplicate(true), "heads": heads, "history": []}
	return {"ok": true}

static func definition(state, clan_id: String) -> Dictionary:
	for row in state.flags.get("clan_succession", {}).get("rules", []):
		if row.clan_id == clan_id: return row
	return {}

static func head(state, clan_id: String) -> String:
	return str(state.flags.get("clan_succession", {}).get("heads", {}).get(clan_id, ""))

static func assess(state, clan_id: String, candidate: String, deceased: bool = false) -> Dictionary:
	var model := definition(state, clan_id)
	if model.is_empty(): return Rules.fail("没有该家族的实际交接规则")
	var old := head(state, clan_id)
	var offers: Array = model.candidates.filter(func(row): return row.character_id == candidate)
	if offers.size() != 1 or candidate == old or not offers[0].willing or state.character_states.get(candidate, {}).get("clan_id") != clan_id: return Rules.fail("没有该家族成员本人愿意接任的依据")
	if int(state.character_states[candidate].get("relationships", {}).get(old, 0)) < int(offers[0].minimum_relation): return Rules.fail("候选当前不愿按原约接任")
	if (not deceased and not Presence.present(state, old, model.location_id)) or not Presence.present(state, candidate, model.location_id): return Rules.fail("原族长与接任者须实际到场办理交接")
	return {"ok": true}

static func cost_for(state, _kind: String, params: Dictionary) -> Dictionary:
	if not params.get("clan_id") is String or not params.get("successor_id") is String or definition(state, params.clan_id).is_empty(): return Rules.fail("移交须明确实际家族与接任者")
	return {"ok": true, "account_id": "", "amount": 0}

static func family_step(state, step: Dictionary, clan_id: String) -> bool:
	var params: Dictionary = step.parameters
	if step.action_kind in ["hire_family", "dismiss_family", "offer_family_wage", "pay_employment_debt"]:
		return state.office_state.get(params.get("office_id"), {}).get("organization_id") == clan_id
	if step.action_kind in ["rent_shop", "transfer_cash"]:
		return state.resource_accounts.get(params.get("funding_account_id", params.get("source_account_id", "")), {}).get("owner_ref") == {"entity_kind": "clan", "entity_id": clan_id}
	if step.action_kind in preload("res://scripts/core/pawnshop_service.gd").KINDS:
		return state.management_assets.get(params.get("shop_id"), {}).get("owner_ref") == {"entity_kind": "clan", "entity_id": clan_id} or str(params.get("shop_id", "")).begins_with("pawnshop:" + clan_id + ":")
	return false

static func apply(state, params: Dictionary, principal: String, execution: String, kind: String = "handover_clan_head") -> Dictionary:
	var checked := cost_for(state, "handover_clan_head", params)
	if not checked.ok: return checked
	var clan_id: String = params.clan_id
	var old := head(state, clan_id)
	var deceased := kind == "assume_clan_head"
	if deceased:
		var estate: Dictionary = state.economic_contracts.get(params.get("estate_id", ""), {})
		var rule: Dictionary = load("res://scripts/core/personal_estate_service.gd").rule_for(state, str(params.get("estate_id", "")))
		if estate.get("contract_kind") != "personal_estate" or estate.get("owner_id") != old or state.character_states[old].get("status") != "dead" or rule.get("successor_id") != principal or params.successor_id != principal or rule.get("clan_id") != clan_id: return Rules.fail("死亡继任缺少实际死者、已登记遗产或约定继任人")
	elif old != principal: return Rules.fail("只有实际现任族长可移交家族经营权")
	checked = assess(state, clan_id, params.successor_id, deceased)
	if not checked.ok: return checked
	var accounts: Array = []
	for account in state.resource_accounts.values():
		if account.owner_ref == {"entity_kind": "clan", "entity_id": clan_id}:
			if not account.operator_refs.has({"entity_kind": "character", "entity_id": old}) or (not deceased and not Accounts.new().can_operate(state, account.account_id, old)): return Rules.fail("家族账户经营权与现任族长不一致")
			accounts.append(account.account_id)
	if accounts.is_empty(): return Rules.fail("家族没有实际经营账户")
	var mandates := {}
	for auth in state.action_authorizations.values():
		if auth.principal_id != old or auth.status != "active": continue
		if not auth.resource_limits.all(func(limit): return accounts.has(limit.account_id)): continue
		var tasks: Array = state.active_tasks.filter(func(task): return task.get("authorization_id") == auth.authorization_id)
		if tasks.is_empty() or not tasks.all(func(task): return task.steps.all(func(step): return family_step(state, step, clan_id))): continue
		mandates[auth.authorization_id] = {"scope": auth.scope.duplicate(true), "resource_limits": auth.resource_limits.duplicate(true), "version": auth.version, "principal_id": auth.principal_id}
		if auth.has("clan_mandate"): return Rules.fail("该任务已有未收口的经营权承继")
	var record := {"execution_id": execution, "clan_id": clan_id, "from_id": old, "to_id": params.successor_id, "day": int(state.current_day), "accounts": accounts, "mandates": mandates}
	if deceased: record["estate_id"] = params.estate_id
	for id in accounts: state.resource_accounts[id]["operator_refs"] = [{"entity_kind": "character", "entity_id": params.successor_id}]
	for id in mandates: state.action_authorizations[id]["clan_mandate"] = {"clan_id": clan_id, "handover_ref": execution}
	state.flags.clan_succession.heads[clan_id] = params.successor_id
	state.flags.clan_succession.history.append(record)
	return {"ok": true, "result_ref": execution, "clan_handover": record.duplicate(true), "visible_summary": "已移交家族经营权；账户、产权、雇约及债权保留，承继 %d 项原家族账户、任用或当铺授权；其他任务保留并继续核验现有权限。" % mandates.size()}

static func effective_principal(state, auth: Dictionary) -> String:
	var mandate: Dictionary = auth.get("clan_mandate", {})
	return str(auth.get("principal_id", "")) if mandate.is_empty() else head(state, str(mandate.get("clan_id", "")))

static func controls_task(state, task: Dictionary, viewer: String) -> bool:
	if task.get("principal_id") == viewer: return true
	var auth: Dictionary = state.action_authorizations.get(task.get("authorization_id", ""), {})
	var mandate: Dictionary = auth.get("clan_mandate", {})
	if mandate.is_empty() or effective_principal(state, auth) != viewer: return false
	return held_task_control(state, task, viewer, int(state.current_day))

static func held_task_control(state, task: Dictionary, viewer: String, day: int) -> bool:
	if task.get("principal_id") == viewer: return true
	var auth: Dictionary = state.action_authorizations.get(task.get("authorization_id", ""), {})
	var mandate: Dictionary = auth.get("clan_mandate", {})
	var record: Dictionary = state.action_receipts.get(mandate.get("handover_ref", ""), {}).get("clan_handover", {})
	return record.get("to_id") == viewer and int(record.get("day", -1)) <= day and record.get("clan_id") == mandate.get("clan_id") and record.get("mandates", {}).has(auth.get("authorization_id")) and task.get("principal_id") == auth.get("principal_id")

static func had_authority(raw: Dictionary, clan_id: String, person: String) -> bool:
	return raw.get("flags", {}).get("clan_succession", {}).get("history", []).any(func(row): return row.get("clan_id") == clan_id and row.get("from_id") == person)

static func project(state, viewer: String) -> Array:
	var result: Array = []
	for rule in state.flags.get("clan_succession", {}).get("rules", []):
		if state.character_states.get(viewer, {}).get("clan_id") != rule.clan_id: continue
		var row := {"clan_id": rule.clan_id, "head_id": head(state, rule.clan_id), "head_name": state.character_states[head(state, rule.clan_id)].name, "candidates": [], "history": []}
		if head(state, rule.clan_id) == viewer:
			for candidate in rule.candidates:
				if candidate.character_id == row.head_id: continue
				var eligibility := assess(state, rule.clan_id, candidate.character_id)
				row.candidates.append({"character_id": candidate.character_id, "name": state.character_states[candidate.character_id].name, "available": eligibility.ok, "reason": eligibility.get("error", "本人愿意接任")})
		for item in state.flags.clan_succession.history:
			if item.clan_id == rule.clan_id: row.history.append({"day": item.day, "from_id": item.from_id, "to_id": item.to_id})
		result.append(row)
	return result

static func validate(raw: Dictionary) -> Dictionary:
	var system: Variant = raw.get("flags", {}).get("clan_succession", {})
	if not system is Dictionary: return Rules.fail("家族交接状态类型无效")
	if system.is_empty(): return {"ok": true}
	if system.get("source_id") != SOURCE or not system.get("rules") is Array or not system.get("heads") is Dictionary or not system.get("history") is Array: return Rules.fail("家族交接缺少来源及履历")
	var heads := {}
	for rule in system.rules:
		if not rule is Dictionary or not rule.get("clan_id") is String or heads.has(rule.clan_id) or not raw.character_states.has(rule.get("initial_head_id")) or not raw.local_node_state.has(rule.get("location_id")) or not rule.get("candidates") is Array: return Rules.fail("家族交接定义缺少实际人地")
		heads[rule.clan_id] = rule.initial_head_id
		for candidate in rule.candidates:
			if not candidate is Dictionary or not raw.character_states.has(candidate.get("character_id")) or raw.character_states[candidate.character_id].get("clan_id") != rule.clan_id or not candidate.get("willing") is bool or not (candidate.get("minimum_relation") is int or candidate.get("minimum_relation") is float): return Rules.fail("接任候选缺少实际族属或意愿定义")
	var seen := {}
	for row in system.history:
		if not row is Dictionary or not row.get("execution_id") is String or seen.has(row.execution_id) or not heads.has(row.get("clan_id")) or row.get("from_id") != heads[row.clan_id] or not raw.character_states.has(row.get("to_id")) or raw.character_states[row.to_id].get("clan_id") != row.clan_id or not Rules.amount(row.get("day")) or int(row.day) > int(raw.current_day) or not row.get("accounts") is Array or not row.get("mandates") is Dictionary: return Rules.fail("家族交接履历断裂或人地日期无效")
		if row.has("estate_id"):
			var estate: Dictionary = raw.economic_contracts.get(row.estate_id, {})
			if estate.get("contract_kind") != "personal_estate" or estate.get("owner_id") != row.from_id or raw.character_states[row.from_id].get("status") != "dead": return Rules.fail("死亡继任丢失实际遗产及死者")
		var receipt: Dictionary = raw.action_receipts.get(row.execution_id, {})
		if receipt.get("clan_handover") != row or not receipt.get("effect_refs", []).has(row.execution_id): return Rules.fail("家族交接缺少共同动作回执")
		seen[row.execution_id] = row
		heads[row.clan_id] = row.to_id
		for id in row.mandates:
			if raw.action_authorizations.get(id, {}).get("clan_mandate") != {"clan_id": row.clan_id, "handover_ref": row.execution_id}: return Rules.fail("交接丢失已承继的原任务授权")
		for account in row.accounts:
			if raw.resource_accounts.get(account, {}).get("owner_ref") != {"entity_kind": "clan", "entity_id": row.clan_id}: return Rules.fail("交接改写家族产权或丢失账户")
	if heads != system.heads: return Rules.fail("现任族长与真实交接履历不符")
	for account in raw.resource_accounts.values():
		var owner: Dictionary = account.owner_ref
		if owner.get("entity_kind") == "clan" and heads.has(owner.entity_id) and account.operator_refs != [{"entity_kind": "character", "entity_id": heads[owner.entity_id]}]: return Rules.fail("家族现任经营权与账户不一致")
	for auth in raw.action_authorizations.values():
		if not auth.has("clan_mandate"): continue
		var mandate: Variant = auth.clan_mandate
		if not mandate is Dictionary or not seen.has(mandate.get("handover_ref")): return Rules.fail("家族任务承继没有实际交接")
		var record: Dictionary = seen[mandate.handover_ref]
		var original: Dictionary = record.mandates.get(auth.authorization_id, {})
		if mandate.get("clan_id") != record.clan_id or auth.principal_id != original.get("principal_id") or auth.scope != original.get("scope") or auth.resource_limits != original.get("resource_limits") or int(auth.version) != int(original.get("version", -1)) + (1 if auth.status == "revoked" else 0): return Rules.fail("承继任务改写原委托人、范围或累计预算")
	return {"ok": true}
