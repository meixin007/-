extends RefCounted

# Account references resolve one existing balance; the adapter stores no money.
static func balance(state, storage: Dictionary) -> int:
	return int(raw_balance(state, storage))

static func raw_balance(state, storage: Dictionary) -> Variant:
	if storage.get("storage_kind") == "depot":
		return state.depot_states.get(storage.get("storage_id"), {}).get("stock", {}).get(storage.get("resource_key"), -1)
	if storage.get("storage_kind") == "resource_pool" and storage.get("storage_id") == "resources":
		return state.resources.get(storage.get("resource_key"), -1)
	return -1

static func write_balance(state, storage: Dictionary, value: int) -> void:
	if storage.storage_kind == "depot":
		state.depot_states[storage.storage_id].stock[storage.resource_key] = value
	else:
		state.resources[storage.resource_key] = value

static func key(storage: Dictionary) -> String:
	return "%s:%s:%s" % [storage.get("storage_kind", ""), storage.get("storage_id", ""), storage.get("resource_key", "")]

static func location(state, account: Dictionary) -> String:
	var storage: Dictionary = account.storage_ref
	if storage.storage_kind == "depot":
		return str(state.depot_states.get(storage.storage_id, {}).get("location_node_id", ""))
	return str(account.get("location_id", ""))

static func personal_account(state, character_id: String) -> String:
	var expected := character_id + "_cash"
	var account: Dictionary = state.resource_accounts.get(expected, {})
	if account.get("owner_ref", {}) == {"entity_kind": "character", "entity_id": character_id}:
		return expected
	return ""
