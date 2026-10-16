extends RefCounted

const Definitions = preload("res://scripts/core/resource_commodity_definitions.gd")
const Contract = preload("res://scripts/core/management_state_contract.gd")

# Startup-only scenario provisioning. Runtime production must use its own actual
# contract/receipt and the shared transaction, never call this as a resource grant.
static func initialize(state, data: Dictionary) -> Dictionary:
	var grants: Variant = data.get("management", {}).get("commodity_grants", [])
	if not grants is Array: return Contract.fail("商品初始库存须为数组")
	if not grants.is_empty() and int(state.current_day) != 0: return Contract.fail("商品初始来源只可在新开局登记")
	var prepared: Array[Dictionary] = []
	var seen := {}
	# Validate the complete batch before touching any warehouse.
	for grant in grants:
		if not grant is Dictionary or not grant.get("character_id") is String or not grant.get("resource_key") is String or not Contract.amount(grant.get("amount")) or not grant.get("source_id") is String or not str(grant.source_id).begins_with("scenario:") or str(grant.source_id).length() <= 9:
			return Contract.fail("商品初始库存缺少人物、数量、品类或明确场景来源")
		var person: String = grant.character_id
		var commodity: String = grant.resource_key
		var depot_id := "personal_" + person
		var id := person + "_" + commodity
		var depot: Dictionary = state.depot_states.get(depot_id, {})
		if not Definitions.initial_trade_commodity(commodity) or not state.character_states.has(person): return Contract.fail("商品或初始持有人未登记")
		if depot.is_empty() or depot.get("owner_character_id") != person or not depot.get("stock") is Dictionary or not state.local_node_state.has(depot.get("location_node_id")):
			return Contract.fail("商品必须进入持有人既有的实际仓库")
		if seen.has(id) or state.resource_accounts.has(id) or depot.stock.has(commodity) or state.resource_journal.has("initial:" + id): return Contract.fail("商品初始库存不能重复登记或覆盖既有库存")
		seen[id] = true
		prepared.append({"account_id":id, "depot_id":depot_id, "character_id":person, "resource_key":commodity, "amount":int(grant.amount), "source_id":grant.source_id})
	for grant in prepared:
		var id: String = grant.account_id
		var owner := {"entity_kind":"character", "entity_id":grant.character_id}
		var unit := Definitions.depot_unit(grant.resource_key)
		state.depot_states[grant.depot_id].stock[grant.resource_key] = grant.amount
		state.resource_accounts[id] = {"account_id":id, "owner_ref":owner, "resource_key":grant.resource_key, "unit_id":unit, "storage_ref":{"storage_kind":"depot", "storage_id":grant.depot_id, "resource_key":grant.resource_key}, "operator_refs":[owner.duplicate(true)]}
		if int(grant.amount) > 0:
			var entry := "initial:" + id
			state.resource_journal[entry] = {"entry_id":entry, "execution_id":entry, "entry_kind":"initial_grant", "source_ref":{"entity_kind":"rule", "entity_id":grant.character_id, "rule_id":grant.source_id}, "destination_ref":owner.duplicate(true), "destination_account_id":id, "amount":grant.amount, "unit_id":unit, "reason_ref":grant.source_id, "day":0}
	return {"ok":true}
