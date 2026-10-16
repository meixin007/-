# scripts/core/transit_corridor_state.gd
extends RefCounted

var corridor_id: String = ""
var corridor_name: String = ""
var from_node_id: String = ""
var to_node_id: String = ""
var transit_type: String = "land" # land (官道) / river (漕运) / mountain_pass (险隘峡道) / desert (塞外瀚海)
var base_travel_days: int = 3
var loss_rate_per_day: float = 0.002
var is_blocked: bool = false
var blocking_reason: String = ""
var activation_status: String = ""
var pending_dependencies: Array = []
var required_crossings: Array = []
var threat_level: int = 0 # 0..100 敌军袭扰度
var urgency_level: float = 0.0 # 0.0..1.0 告急程度

func to_dict() -> Dictionary:
	var result := {
		"corridor_id": corridor_id,
		"corridor_name": corridor_name,
		"from_node_id": from_node_id,
		"to_node_id": to_node_id,
		"transit_type": transit_type,
		"base_travel_days": base_travel_days,
		"loss_rate_per_day": loss_rate_per_day,
		"is_blocked": is_blocked,
		"blocking_reason": blocking_reason,
		"threat_level": threat_level,
		"urgency_level": urgency_level
	}
	if not activation_status.is_empty():
		result["activation_status"] = activation_status
		result["pending_dependencies"] = pending_dependencies.duplicate(true)
	if not required_crossings.is_empty():
		result["required_crossings"] = required_crossings.duplicate(true)
	return result

static func from_dict(data: Dictionary) -> Variant:
	var script: GDScript = load("res://scripts/core/transit_corridor_state.gd")
	var instance = script.new()
	instance.corridor_id = str(data.get("corridor_id", data.get("id", "")))
	instance.corridor_name = str(data.get("corridor_name", data.get("name", "")))
	instance.from_node_id = str(data.get("from_node_id", ""))
	instance.to_node_id = str(data.get("to_node_id", ""))
	instance.transit_type = str(data.get("transit_type", "land"))
	instance.base_travel_days = int(data.get("base_travel_days", 3))
	instance.loss_rate_per_day = float(data.get("loss_rate_per_day", 0.002))
	instance.is_blocked = bool(data.get("is_blocked", false))
	instance.blocking_reason = str(data.get("blocking_reason", ""))
	instance.activation_status = str(data.get("activation_status", ""))
	var dependencies: Variant = data.get("pending_dependencies", [])
	instance.pending_dependencies = dependencies.duplicate(true) if dependencies is Array else []
	var crossings: Variant = data.get("required_crossings", [])
	instance.required_crossings = crossings.duplicate(true) if crossings is Array else []
	instance.threat_level = int(data.get("threat_level", 0))
	instance.urgency_level = float(data.get("urgency_level", 0.0))
	return instance
