extends RefCounted

class_name LocalNodeService

func get_node(state, node_id: String) -> Dictionary:
	if state == null:
		return {}
	return state.local_node_state.get(node_id, {}).duplicate(true)

func apply_order_effects(state, node_id: String, effects: Array, options: Dictionary = {}) -> Dictionary:
	if state == null:
		return _fail("missing state")
	if not state.local_node_state.has(node_id):
		return _fail("unknown node: " + node_id)
	var node: Dictionary = state.local_node_state[node_id].duplicate(true)
	for effect in effects:
		var field := str(effect.get("field", ""))
		if field == "":
			continue
		node[field] = clampi(int(node.get(field, 0)) + int(effect.get("value", 0)), 0, 100)
	var recent_orders: Array = node.get("recent_orders", []).duplicate(true)
	recent_orders.append({
		"reason": str(options.get("reason", "order effect")),
		"day": int(state.current_day),
		"effects": effects.duplicate(true)
	})
	node["recent_orders"] = recent_orders
	state.local_node_state[node_id] = node
	state.chronicle_causal_references.append({
		"kind": "local_node",
		"id": node_id,
		"reason": str(options.get("reason", "order effect")),
		"day": int(state.current_day)
	})
	return {"ok": true, "node": node.duplicate(true)}

func get_node_summary(state, node_id: String) -> String:
	var node := get_node(state, node_id)
	if node.is_empty():
		return ""
	return "%s supply=%d security=%d order=%d faction=%s" % [
		node_id,
		int(node.get("supply", 0)),
		int(node.get("security", 0)),
		int(node.get("public_order", 0)),
		str(node.get("dominant_faction", ""))
	]

func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
