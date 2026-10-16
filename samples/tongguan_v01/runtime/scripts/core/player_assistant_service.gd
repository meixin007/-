extends RefCounted

const Transaction = preload("res://scripts/core/game_state_transaction.gd")
const Contract = preload("res://scripts/core/management_state_contract.gd")

static func eligible(state, data: Dictionary, character_id: String) -> Dictionary:
	if not _principal_available(state): return Contract.fail("委托人已无法确认助手绑定，须先处理人物接续")
	if not state.character_states.has(character_id) or character_id == state.player_character_id:
		return Contract.fail("助手须是本局另一名实际人物")
	var character: Dictionary = state.character_states[character_id]
	if character.get("status") in ["dead", "deceased", "executed", "missing", "imprisoned", "departed", "exiled", "unreachable"]:
		return Contract.fail("人物已无法担任助手")
	var player: Dictionary = state.character_states[state.player_character_id]
	if str(character.get("location_id", "")).trim_suffix("_node") != str(player.get("location_id", "")).trim_suffix("_node"):
		return Contract.fail("人物尚未到身边，需先安排会面或通信")
	var profile: Dictionary = data.get("start_profiles", {}).get(state.flags.get("start_profile_id", ""), {})
	var default_office_id := str(profile.get("assistant_source_office_id", ""))
	var holds_default: bool = not default_office_id.is_empty() and state.office_state.get(default_office_id, {}).get("holder_id") == character_id
	for office in state.office_state.values():
		if office.get("office_kind") == "regional" and office.get("holder_id") == character_id and office.get("organization_id") != state.flags.get("player_organization_id"):
			return Contract.fail("人物在另一州府履职，需先办理差遣或交接")
		if office.get("office_kind") == "regional" and office.get("holder_id") == character_id:
			var authority: Dictionary = preload("res://scripts/core/office_appointment_authority.gd").resolve(state.office_state, state.character_states, str(office.office_id))
			if not authority.get("ok", false) or authority.get("authority_holder_id") != state.player_character_id: return Contract.fail("人物的任命与差遣权源已变化，需先办理助手交接")
		if office.get("office_kind") == "family" and office.get("holder_id") == character_id and office.get("organization_id") != state.flags.get("player_organization_id") and not preload("res://scripts/core/resource_account_service.gd").new().can_operate(state,str(office.get("remuneration_terms",{}).get("account_id","")),state.player_character_id):
			return Contract.fail("人物已受雇于别家，需先协商交接")
	var definition: Dictionary = {}
	for entry in data.get("characters", []):
		if entry.get("id") == character_id:
			definition = entry
	var arranged := false
	for offer in data.get("management", {}).get("assistant_service_offers", []):
		if offer.get("character_id") != character_id or offer.get("principal_id") != state.player_character_id: continue
		if not offer.get("willing", false) or int(character.get("relationships", {}).get(state.player_character_id, 0)) < int(offer.minimum_relation): return Contract.fail("本人目前不愿继续协助，需先重新协商")
		if not state.resource_accounts.has(character_id + "_cash") or not state.resource_accounts.has(character_id + "_rations"): return Contract.fail("人物的实际生活来源尚未落实")
		arranged = true
	if not holds_default and not arranged and not definition.get("employment_preferences", {}).get("assistant_willing", false):
		return Contract.fail("本人尚未同意担任助手")
	return {"ok": true, "source_office_id": default_office_id if holds_default else ""}

static func initialize(state, data: Dictionary) -> Dictionary:
	var seen := {}
	for offer in data.get("management", {}).get("assistant_service_offers", []):
		if not offer is Dictionary or not state.character_states.has(offer.get("character_id")) or not state.character_states.has(offer.get("principal_id")) or not offer.get("willing") is bool or not str(offer.get("source_id", "")).begins_with("scenario:") or typeof(offer.get("minimum_relation")) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(offer.minimum_relation)) or float(offer.minimum_relation) != floor(float(offer.minimum_relation)) or int(offer.minimum_relation) < -100 or int(offer.minimum_relation) > 100: return Contract.fail("助手协助约定缺少有效人物、意愿或场景来源")
		var key: String = offer.character_id + ":" + offer.principal_id
		if seen.has(key): return Contract.fail("助手协助约定重复")
		seen[key] = true
	var profile: Dictionary = data.get("selected_start_profile", {})
	if profile.is_empty():
		return {"ok": true}
	var source := str(profile.get("assistant_source_office_id", ""))
	var candidate := str(state.office_state.get(source, {}).get("holder_id", ""))
	var result := eligible(state, data, candidate)
	state.player_assistant_assignment = {"assistant_id": candidate if result.get("ok", false) else "", "principal_id": state.player_character_id, "binding_revision": 1, "source_office_id": source if result.get("ok", false) else "", "status": "active" if result.get("ok", false) else "vacant", "reason": "" if result.get("ok", false) else str(result.get("error", "当前没有合适的在任人选"))}
	return {"ok": true}

func bind(context, character_id: String, execution_id: String) -> Dictionary:
	if context == null or context.state == null or execution_id.is_empty():
		return Contract.fail("更换助手需要有效上下文与执行标识")
	var input := {"principal_id": context.state.player_character_id, "assistant_id": character_id, "execution_id": execution_id}
	var transaction = Transaction.new()
	var preview := transaction.preview_command(context.state, "assistant_binding", input)
	if not preview.get("ok", false):
		return preview
	return transaction.execute_command(context, transaction.build_command_envelope("assistant_binding", input, preview.preview_token), func(working): return _bind(working, input))

static func _bind(context, input: Dictionary) -> Dictionary:
	var state = context.state
	if state.player_character_id != input.principal_id:
		return Contract.fail("助手绑定主体已变化")
	var chosen := str(input.assistant_id)
	var eligibility := {"ok": true, "source_office_id": ""} if chosen.is_empty() else eligible(state, context.scenario_data, chosen)
	if not eligibility.get("ok", false):
		return eligibility
	if state.player_assistant_assignment.get("assistant_id") == chosen and state.player_assistant_assignment.get("status") == ("vacant" if chosen.is_empty() else "active"):
		return {"ok": true, "code": "no_op"}
	state.player_assistant_assignment = {"assistant_id": chosen, "principal_id": state.player_character_id, "binding_revision": int(state.player_assistant_assignment.get("binding_revision", 0)) + 1, "source_office_id": eligibility.source_office_id, "status": "vacant" if chosen.is_empty() else "active", "reason": "玩家暂未选择助手" if chosen.is_empty() else ""}
	var advice: Dictionary = load("res://scripts/core/assistant_advice_service.gd").update(state, context.scenario_data, true)
	if not advice.get("ok", false): return advice
	return {"ok": true, "result_ref": "assistant:%d" % int(state.player_assistant_assignment.binding_revision)}

static func accepts_reply(state, stamp: Dictionary) -> bool:
	if not _principal_available(state): return false
	var binding: Dictionary = state.player_assistant_assignment
	var character: Dictionary = state.character_states.get(binding.get("assistant_id", ""), {})
	if character.is_empty() or character.get("status") in ["dead", "deceased", "executed", "missing", "imprisoned", "departed", "exiled", "unreachable"]:
		return false
	var source := str(binding.get("source_office_id", ""))
	if not source.is_empty() and state.office_state.get(source, {}).get("holder_id") != binding.get("assistant_id"):
		return false
	for office in state.office_state.values():
		if office.get("office_kind") == "regional" and office.get("holder_id") == binding.get("assistant_id"):
			var authority: Dictionary = preload("res://scripts/core/office_appointment_authority.gd").resolve(state.office_state, state.character_states, str(office.office_id))
			if not authority.get("ok", false) or authority.get("authority_holder_id") != state.player_character_id: return false
	return binding.get("status") == "active" and stamp.get("principal_id") == state.player_character_id and stamp.get("assistant_id") == binding.get("assistant_id") and stamp.get("binding_revision") == binding.get("binding_revision")

static func reconcile(state, data: Dictionary) -> Dictionary:
	var binding: Dictionary = state.player_assistant_assignment
	if binding.get("status") != "active":
		return {"ok": true}
	var validity := eligible(state, data, str(binding.get("assistant_id", "")))
	var source := str(binding.get("source_office_id", ""))
	if not source.is_empty() and state.office_state.get(source, {}).get("holder_id") != binding.get("assistant_id"):
		validity = Contract.fail("原任职已结束，待办理助手交接")
	if not validity.get("ok", false):
		binding.status = "unavailable"
		binding.reason = validity.get("error", "人物不可用")
		binding.binding_revision += 1
	return {"ok": true}

static func project(state, data: Dictionary) -> Dictionary:
	var binding: Dictionary = state.player_assistant_assignment.duplicate(true)
	if binding.get("status") == "active":
		var validity := eligible(state, data, str(binding.get("assistant_id", "")))
		var source := str(binding.get("source_office_id", ""))
		if not source.is_empty() and state.office_state.get(source, {}).get("holder_id") != binding.get("assistant_id"):
			validity = Contract.fail("原任职已结束，待办理助手交接")
		if not validity.get("ok", false):
			binding.status = "unavailable"
			binding.reason = validity.get("error", "人物不可用")
	var candidates: Array = []
	for id in state.character_states:
		if eligible(state, data, id).get("ok", false):
			candidates.append({"character_id": id, "name": str(state.character_states[id].get("name", id))})
	binding["candidates"] = candidates
	binding["name"] = str(state.character_states.get(binding.get("assistant_id", ""), {}).get("name", "空缺"))
	binding["source_office_name"] = str(state.office_state.get(binding.get("source_office_id", ""), {}).get("name", ""))
	return binding

static func _principal_available(state) -> bool:
	var principal: Dictionary = state.character_states.get(state.player_character_id, {})
	return not principal.is_empty() and principal.get("status") not in ["dead", "deceased", "executed", "missing", "imprisoned", "departed", "exiled", "unreachable"]
