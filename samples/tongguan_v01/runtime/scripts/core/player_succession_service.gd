extends RefCounted

const Rules = preload("res://scripts/core/management_state_contract.gd")
const Clan = preload("res://scripts/core/clan_succession_service.gd")
const Presence = preload("res://scripts/core/production_service.gd")
const Canonical = preload("res://scripts/core/canonical_json.gd")
const SOURCE := "scenario:qinghe_player_succession_756"
const KINDS := ["continue_as_successor"]
const PRIVATE_FIELDS := ["inventory", "player_assistant_assignment", "assistant_advice_state", "assistant_conversation_state", "active_conversation_target_id", "dialogue_history_summary", "pending_dialogue_intent", "pending_dialogue_response", "dialogue_action_records", "scene_stack", "active_dialogue_sessions", "dialogue_session_history", "court_workbench_state"]

static func initialize(state, data: Dictionary) -> Dictionary:
	var config: Dictionary = data.get("management", {}).get("player_succession_rules", {})
	if config.is_empty(): return {"ok": true}
	state.flags["player_succession"] = {"source_id": SOURCE, "rules": config.rules.duplicate(true), "initial_player_id": state.player_character_id, "history": [], "archives": {}}
	return {"ok": true}

static func rule_for(state, id: String) -> Dictionary:
	for rule in state.flags.get("player_succession", {}).get("rules", []):
		if rule.succession_id == id: return rule
	return {}

static func assess(state, rule: Dictionary) -> Dictionary:
	if rule.is_empty() or rule.from_id != state.player_character_id: return Rules.fail("没有当前人物的接续约定")
	if not rule.willing or int(state.character_states[rule.to_id].get("relationships", {}).get(rule.from_id, 0)) < int(rule.minimum_relation): return Rules.fail("接任者目前不愿接续")
	if rule.get("mode", "living") == "after_death":
		var estate: Dictionary = state.economic_contracts.get(rule.get("estate_id", ""), {})
		if state.character_states[rule.from_id].get("status") != "dead" or estate.get("contract_kind") != "personal_estate" or estate.get("owner_id") != rule.from_id or not state.action_receipts.has(estate.get("death_receipt", "")): return Rules.fail("须有原人物实际死亡及遗产登记")
	elif not Presence.present(state, rule.from_id, rule.location_id): return Rules.fail("交接双方须在场且能够办理")
	if not Presence.present(state, rule.to_id, rule.location_id): return Rules.fail("接任者尚未到场或无法办理")
	if Clan.head(state, rule.clan_id) != rule.to_id: return Rules.fail("须先完成实际家族经营权交接")
	var handovers: Array = state.flags.get("clan_succession", {}).get("history", []).filter(func(row): return row.clan_id == rule.clan_id and row.from_id == rule.from_id and row.to_id == rule.to_id)
	if handovers.is_empty(): return Rules.fail("没有双方的实际经营权交接记录")
	for suffix in ["_cash", "_rations"]:
		if state.resource_accounts.get(rule.to_id + suffix, {}).get("owner_ref") != {"entity_kind": "character", "entity_id": rule.to_id}: return Rules.fail("接任者缺少本人实际生活账户")
	return {"ok": true, "handover_ref": handovers.back().execution_id}

static func allows_successor_request(state, request: Dictionary) -> bool:
	if request.get("action_kind") not in KINDS or not request.get("parameters") is Dictionary: return false
	var rule := rule_for(state, str(request.parameters.get("succession_id", "")))
	if rule.get("mode") != "after_death" or rule.get("from_id") != state.player_character_id: return false
	return request.get("actor_id") == rule.to_id and request.get("principal_id") == rule.to_id and request.get("executor_id") == rule.to_id and str(request.get("authorization_id", "")).is_empty() and str(request.get("task_id", "")).is_empty() and assess(state, rule).get("ok", false)

static func cost_for(state, _kind: String, params: Dictionary) -> Dictionary:
	if not params.get("succession_id") is String or rule_for(state, params.succession_id).is_empty(): return Rules.fail("接续须明确本人同意的实际人物")
	return {"ok": true, "account_id": "", "amount": 0}

static func apply(state, data: Dictionary, params: Dictionary, principal: String, execution: String) -> Dictionary:
	var rule := rule_for(state, str(params.get("succession_id", "")))
	if rule.is_empty(): return Rules.fail("接续缺少实际人物约定")
	var deceased: bool = rule.get("mode", "living") == "after_death"
	if principal != (rule.to_id if deceased else state.player_character_id): return Rules.fail("接续须由实际当前人物或约定继任者确认")
	var checked := assess(state, rule)
	if not checked.ok: return checked
	var original: String = state.player_character_id
	var archive := {"principal_id": original}
	# Use the same canonical, credential-free representation as actual saves.
	var snapshot: Dictionary = state.to_dictionary()
	for field in PRIVATE_FIELDS:
		var value: Variant = snapshot[field]
		archive[field] = _archive_value(value)
	var digest := Canonical.hash_value(archive)
	if not digest.get("ok", false): return Rules.fail("原人物私人上下文无法完整封存：%s %s" % [str(digest.get("code", "")), str(digest.get("path", ""))])
	var record := {"execution_id": execution, "succession_id": rule.succession_id, "from_id": original, "to_id": rule.to_id, "organization_id": rule.clan_id, "location_id": rule.location_id, "day": int(state.current_day), "handover_ref": checked.handover_ref, "archive_hash": digest.hash}
	if deceased:
		record["estate_id"] = rule.estate_id
		record["confirming_actor_id"] = principal
	state.flags.player_succession.archives[execution] = archive
	state.flags.player_succession.history.append(record)
	# Knowledge belongs to the observer, even when the controlled identity changes.
	state.observer_character_knowledge[original] = snapshot.character_knowledge.duplicate(true)
	state.character_knowledge = state.observer_character_knowledge.get(rule.to_id, {}).duplicate(true)
	state.observer_character_knowledge.erase(rule.to_id)
	load("res://scripts/core/npc_ai_state_contract.gd").cancel_pending(state)
	state.npc_ai_runtime.policy_version += 1
	state.player_character_id = rule.to_id
	state.is_time_paused = true
	state.pause_reason = "player_succession"
	state.flags["player_organization_id"] = rule.clan_id
	state.flags["player_location_id"] = rule.location_id
	for field in PRIVATE_FIELDS:
		var value: Variant = state.get(field)
		state.set(field, [] if value is Array else ({} if value is Dictionary else ""))
	for asset in state.management_assets.values():
		if asset.get("asset_kind") == "movable" and asset.get("owner_ref") == {"entity_kind": "character", "entity_id": rule.to_id}:
			state.inventory.append({"id": asset.asset_id, "asset_ref": asset.asset_id})
	state.player_assistant_assignment = {"assistant_id": "", "principal_id": rule.to_id, "binding_revision": int(archive.player_assistant_assignment.get("binding_revision", 0)) + 1, "source_office_id": "", "status": "vacant", "reason": "新主体需重新选择助手"}
	var advice: Dictionary = load("res://scripts/core/assistant_advice_service.gd").initialize(state, data)
	if not advice.get("ok", false): return advice
	return {"ok": true, "result_ref": execution, "player_succession": record.duplicate(true), "visible_summary": "已继续扮演接任者；原人物私产、雇约及原始委托保留，私人会话已封存。"}

static func _archive_value(value: Variant) -> Variant:
	# Dialogue terms can contain engine StringName keys. Normalize only that
	# string representation; unsupported objects still fail canonical hashing.
	if value is Dictionary:
		var result := {}
		for key in value:
			result[str(key) if key is StringName else key] = _archive_value(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(_archive_value(item))
		return result
	return str(value) if value is StringName else value

static func validate(raw: Dictionary) -> Dictionary:
	var model: Variant = raw.get("flags", {}).get("player_succession", {})
	if not model is Dictionary: return Rules.fail("玩家接续状态无效")
	if model.is_empty(): return Rules.fail("当前存档缺少玩家接续来源") if raw.get("campaign_id") == "anshi_beta_1_14" else {"ok": true}
	if model.get("source_id") != SOURCE or not model.get("rules") is Array or not model.get("history") is Array or not model.get("archives") is Dictionary or not raw.character_states.has(model.get("initial_player_id")): return Rules.fail("玩家接续来源或履历无效")
	var rules := {}
	for rule in model.rules:
		if not rule is Dictionary or not rule.get("succession_id") is String or rules.has(rule.succession_id) or not raw.character_states.has(rule.get("from_id")) or not raw.character_states.has(rule.get("to_id")) or rule.from_id == rule.to_id or not raw.local_node_state.has(rule.get("location_id")) or not rule.get("willing") is bool or typeof(rule.get("minimum_relation")) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(rule.minimum_relation)) or float(rule.minimum_relation) != floor(float(rule.minimum_relation)) or absf(float(rule.minimum_relation)) > 100: return Rules.fail("玩家接续定义缺少实际双方、地点或意愿")
		if raw.character_states[rule.from_id].get("clan_id") != rule.get("clan_id") or raw.character_states[rule.to_id].get("clan_id") != rule.get("clan_id"): return Rules.fail("玩家接续双方实际族属不一致")
		if rule.get("mode", "living") not in ["living", "after_death"]: return Rules.fail("玩家接续方式无效")
		if rule.get("mode") == "after_death":
			var estates: Array = raw.flags.get("estate_rules", {}).get("rules", []).filter(func(estate): return estate.get("estate_id") == rule.get("estate_id") and estate.get("owner_id") == rule.from_id and estate.get("successor_id") == rule.to_id and estate.get("clan_id") == rule.clan_id)
			if estates.size() != 1 or rule.get("source_id") != raw.flags.get("estate_rules", {}).get("source_id"): return Rules.fail("死亡接续缺少同源实际遗产与继任安排")
		rules[rule.succession_id] = rule
	var current: String = model.initial_player_id
	var seen := {}
	var previous_day := -1
	for row in model.history:
		if not row is Dictionary or not row.get("execution_id") is String or seen.has(row.execution_id) or not rules.has(row.get("succession_id")) or row.get("from_id") != current or not Rules.amount(row.get("day")) or int(row.day) < previous_day or int(row.day) > int(raw.current_day): return Rules.fail("玩家身份与接续履历不一致")
		var rule: Dictionary = rules[row.succession_id]
		if row.get("to_id") != rule.to_id or row.from_id != rule.from_id or row.get("organization_id") != rule.clan_id or row.get("location_id") != rule.location_id: return Rules.fail("玩家接续改写原定人物或经营范围")
		var handover: Dictionary = raw.action_receipts.get(row.get("handover_ref"), {}).get("clan_handover", {})
		if handover.get("from_id") != row.from_id or handover.get("to_id") != row.to_id or handover.get("clan_id") != rule.clan_id or int(handover.get("day", -1)) > int(row.day): return Rules.fail("玩家接续丢失实际经营权交接")
		var receipt: Dictionary = raw.action_receipts.get(row.execution_id, {})
		var confirming: String = row.from_id
		if rule.get("mode") == "after_death":
			var estate: Dictionary = raw.economic_contracts.get(rule.estate_id, {})
			if row.get("estate_id") != rule.estate_id or row.get("confirming_actor_id") != row.to_id or estate.get("owner_id") != row.from_id or int(estate.get("created_day", -1)) > int(row.day) or raw.character_states[row.from_id].get("status") != "dead" or handover.get("estate_id") != rule.estate_id: return Rules.fail("死亡接续丢失真实死亡、遗产或继任人确认")
			confirming = row.to_id
		elif row.has("estate_id") or row.has("confirming_actor_id"): return Rules.fail("生前接续不能伪装死亡确认")
		if receipt.get("player_succession") != row or receipt.get("executor_id") != confirming or not receipt.get("effect_refs", []).has(row.execution_id): return Rules.fail("玩家接续缺少实际确认者回执")
		var archive: Variant = model.archives.get(row.execution_id)
		if not archive is Dictionary or archive.get("principal_id") != row.from_id or Canonical.hash_value(archive).get("hash") != row.get("archive_hash"): return Rules.fail("原人物私人上下文丢失或已改写")
		var historical := raw.duplicate(false)
		historical["player_character_id"] = row.from_id
		for field in PRIVATE_FIELDS:
			if not archive.has(field) or typeof(archive[field]) != typeof(raw.get(field)): return Rules.fail("原人物私人上下文字段不完整")
			historical[field] = archive[field]
		if archive.player_assistant_assignment.get("principal_id") != row.from_id: return Rules.fail("封存助手绑定主体不一致")
		for checked in [Rules._validate_assistant_conversation(historical), Rules._validate_assistant_advice(historical), Rules._validate_pending_production(historical)]:
			if not checked.get("ok", false): return checked
		seen[row.execution_id] = true
		current = row.to_id
		previous_day = int(row.day)
	if current != raw.player_character_id or seen.size() != model.archives.size(): return Rules.fail("当前人物或私人存档与接续履历不一致")
	for receipt in raw.action_receipts.values():
		if receipt.has("player_succession") and not seen.has(receipt.execution_id): return Rules.fail("玩家接续履历遗漏共同动作")
	return {"ok": true}
