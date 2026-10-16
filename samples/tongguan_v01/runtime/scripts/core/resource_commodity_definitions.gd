extends RefCounted

# Definitions only. Quantities remain in the existing depot/account/journal chain.
# tea_unit is an abstract game inventory unit, not a claim about historical weight.
const DEPOT_UNITS := {"silk_cash":"cash_unit", "rations":"ration_unit", "tea":"tea_unit"}
const AGRICULTURAL_PRODUCTS := {"grain":{"resource_key":"rations", "name":"粮食"}, "tea":{"resource_key":"tea", "name":"茶叶"}}

static func agricultural_resource(good_id: String) -> String:
	return str(AGRICULTURAL_PRODUCTS.get(good_id, {}).get("resource_key", ""))

static func agricultural_unit(good_id: String) -> String:
	return depot_unit(agricultural_resource(good_id))

static func depot_unit(resource_key: String) -> String:
	return str(DEPOT_UNITS.get(resource_key, ""))

static func initial_trade_commodity(resource_key: String) -> bool:
	# Money and household food retain their established scenario initializers.
	return resource_key == "tea"
