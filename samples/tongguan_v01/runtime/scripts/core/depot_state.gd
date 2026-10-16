# scripts/core/depot_state.gd
extends RefCounted

var depot_id: String = ""
var location_node_id: String = ""
var owner_organization_id: String = ""
var owner_character_id: String = ""
var capacity: int = 100000

var stock: Dictionary = {
	"grain": 0,
	"silk_cash": 0,
	"warhorses": 0,
	"arms": 0,
	"labor": 0
}

func add_stock(commodity: String, amount: int) -> void:
	if not stock.has(commodity):
		stock[commodity] = 0
	stock[commodity] = maxi(0, int(stock[commodity]) + amount)

func consume_stock(commodity: String, amount: int) -> bool:
	if not stock.has(commodity) or int(stock[commodity]) < amount:
		return false
	stock[commodity] = int(stock[commodity]) - amount
	return true

func to_dict() -> Dictionary:
	return {
		"depot_id": depot_id,
		"location_node_id": location_node_id,
		"owner_organization_id": owner_organization_id,
		"owner_character_id": owner_character_id,
		"capacity": capacity,
		"stock": stock.duplicate(true)
	}

static func from_dict(data: Dictionary) -> Variant:
	var script: GDScript = load("res://scripts/core/depot_state.gd")
	var instance = script.new()
	instance.depot_id = str(data.get("depot_id", ""))
	instance.location_node_id = str(data.get("location_node_id", ""))
	instance.owner_organization_id = str(data.get("owner_organization_id", ""))
	instance.owner_character_id = str(data.get("owner_character_id", ""))
	instance.capacity = int(data.get("capacity", 100000))
	var raw_stock = data.get("stock", {})
	if raw_stock is Dictionary:
		for k in ["grain", "rations", "silk_cash", "warhorses", "arms", "labor"]:
			instance.stock[k] = int(raw_stock.get(k, 0))
	return instance
