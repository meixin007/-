extends RefCounted
const Contract = preload("res://scripts/core/management_state_contract.gd")
const KINDS := ["equip_item", "give_item"]
const UNAVAILABLE_STATUSES := ["dead", "deceased", "executed", "missing", "imprisoned", "departed", "exiled", "unreachable"]

static func initialize(state) -> Dictionary:
	if state.flags.get("managed_inventory_initialized", false): return Contract.fail("物品权利已经初始化")
	var references: Array = []
	for original in state.inventory:
		if not original is Dictionary or str(original.get("id", "")).is_empty() or state.management_assets.has(original.id): return Contract.fail("初始实物标识缺失或重复")
		if original.get("owner_id") != state.player_character_id or state.flags.get("starter_inventory_source_id") != "scenario:lingwu_imperial_regalia": return Contract.fail("初始实物没有登记来源")
		var definition: Dictionary = original.duplicate(true)
		for key in ["id", "owner_id", "holder_name", "equipped"]: definition.erase(key)
		var owner := {"entity_kind": "character", "entity_id": state.player_character_id}
		state.management_assets[original.id] = {"asset_id": original.id, "asset_kind": "movable", "name": original.name, "owner_ref": owner, "custodian_ref": owner.duplicate(true), "location_id": state.flags.player_location_id, "source_ref": {"entity_kind": "rule", "entity_id": original.id, "rule_id": "scenario:lingwu_imperial_regalia"}, "status": "available", "rights": [], "contract_refs": [], "condition": 100, "lien_contract_id": "", "equipped_by": state.player_character_id if original.get("equipped", false) else "", "item_definition": definition}
		references.append({"id": original.id, "asset_ref": original.id})
	for asset in state.management_assets.values():
		if asset.get("asset_kind") == "movable" and asset.get("owner_ref") == {"entity_kind": "character", "entity_id": state.player_character_id} and not references.any(func(ref): return ref.asset_ref == asset.asset_id):
			references.append({"id": asset.asset_id, "asset_ref": asset.asset_id})
	state.inventory = references
	state.flags["managed_inventory_initialized"] = true
	return {"ok": true}

static func project(state, id: String, viewer: String) -> Dictionary:
	var asset: Dictionary = state.management_assets.get(id, {})
	if asset.get("asset_kind") != "movable" or asset.get("owner_ref") != {"entity_kind": "character", "entity_id": viewer}: return {}
	var item: Dictionary = asset.get("item_definition", {}).duplicate(true)
	item["id"] = id
	item["name"] = str(asset.get("name", id))
	item["owner_id"] = viewer
	item["holder_name"] = str(state.character_states.get(viewer, {}).get("name", viewer))
	item["equipped"] = asset.get("equipped_by", "") == viewer
	item["status"] = str(asset.status)
	item["condition"] = int(asset.condition)
	item["location_id"] = str(asset.location_id)
	item["source_ref"] = asset.source_ref.duplicate(true)
	if not item.has("actions"): item["actions"] = ["inspect", "bestow"]
	item["custodian_ref"] = asset.custodian_ref.duplicate(true)
	var usable := disposition(state, id, viewer)
	item["can_dispose"] = usable.get("ok", false)
	item["restriction"] = str(usable.get("error", ""))
	return item

static func local_people(state, location: String) -> Array:
	var result: Array = []
	if location.is_empty(): return result
	for id in state.character_states:
		var person: Dictionary = state.character_states[id]
		if id == state.player_character_id or person.get("status") in UNAVAILABLE_STATUSES: continue
		if str(person.get("location_id", "")).trim_suffix("_node") == location.trim_suffix("_node"):
			result.append({"character_id": id, "name": str(person.get("name", id))})
	return result

static func disposition(state, id: String, principal: String) -> Dictionary:
	var asset: Dictionary = state.management_assets.get(id, {})
	var owner := {"entity_kind": "character", "entity_id": principal}
	if asset.get("asset_kind") != "movable" or asset.get("owner_ref") != owner: return Contract.fail("并非本人有权处分的实物")
	if asset.get("status") != "available" or asset.get("lien_contract_id", "") != "": return Contract.fail("物品已有抵押或其他权利限制，须先按合同解除")
	if asset.get("custodian_ref") != owner: return Contract.fail("物品由他人保管，尚未交回本人")
	if int(asset.get("condition", 0)) <= 0: return Contract.fail("物品已损毁，不能使用或赠予")
	return {"ok": true}

static func cost_for(state, kind: String, params: Dictionary) -> Dictionary:
	if kind not in KINDS or not state.management_assets.has(params.get("item_id")): return Contract.fail("实物或操作不存在")
	if kind == "equip_item" and not params.get("equipped") is bool: return Contract.fail("装备操作须指定佩带或卸下")
	if kind == "give_item" and not state.character_states.has(params.get("recipient_id")): return Contract.fail("赠予对象不存在")
	return {"ok": true, "account_id": "", "amount": 0}

static func apply(state, kind: String, params: Dictionary, principal: String, execution: String) -> Dictionary:
	var id: String = params.item_id
	var allowed := disposition(state, id, principal)
	if not allowed.get("ok", false): return allowed
	var asset: Dictionary = state.management_assets[id]
	var actions: Array = asset.get("item_definition", {}).get("actions", ["inspect", "bestow"])
	if kind == "equip_item":
		if not actions.has("equip"): return Contract.fail("此物没有随身佩带用途")
		asset["equipped_by"] = principal if params.equipped else ""
	else:
		if not actions.has("bestow"): return Contract.fail("此物的现有权利不允许赠予")
		var recipient: String = params.recipient_id
		var person: Dictionary = state.character_states[recipient]
		if recipient == principal or person.get("status") in UNAVAILABLE_STATUSES: return Contract.fail("受赠对象当前不能办理交割")
		if str(person.get("location_id", "")).trim_suffix("_node") != str(asset.location_id).trim_suffix("_node"): return Contract.fail("受赠人尚未到实物交割地点")
		if int(person.get("relationships", {}).get(principal, 0)) < -15: return Contract.fail("对方因关系不睦婉拒了这份礼物")
		var former: Dictionary = asset.owner_ref.duplicate(true)
		asset.owner_ref = {"entity_kind": "character", "entity_id": recipient}
		asset.custodian_ref = asset.owner_ref.duplicate(true)
		asset["equipped_by"] = ""
		asset.erase("pledge_offer")
		asset.erase("purchase_offer")
		var history: Array = asset.get("transfer_history", []).duplicate(true)
		history.append({"execution_id": execution, "from_ref": former, "to_ref": asset.owner_ref.duplicate(true), "day": int(state.current_day), "consent_rule": "unconditional_gift_relationship"})
		asset["transfer_history"] = history
		if principal == state.player_character_id:
			state.inventory = state.inventory.filter(func(ref): return ref.get("id") != id)
		if recipient == state.player_character_id:
			state.inventory.append({"id": id, "asset_ref": id})
	return {"ok": true, "result_ref": id}

static func equip_direct(state, id: String, equipped: bool) -> Dictionary:
	var context = load("res://scripts/core/game_runtime_context.gd").new()
	context.state = state
	context.scenario_data = {}
	var execution := "equip:%s:%d:%s" % [id, int(state.state_revision), str(equipped)]
	var player: String = state.player_character_id
	return load("res://scripts/core/game_action_dispatcher.gd").new().execute(context, {"execution_id": execution, "request_id": execution, "actor_id": player, "principal_id": player, "executor_id": player, "action_kind": "equip_item", "parameters": {"item_id": id, "equipped": equipped}, "target_refs": [id], "expected_state_revision": int(state.state_revision)})
