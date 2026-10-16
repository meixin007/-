# scripts/core/control_relation_state.gd
extends RefCounted

class_name ControlRelationState

var control_id: String = ""
# Target Type: "force" (军队), "depot" (仓廪府库), "node" (城池关隘), "office_seal" (官印文书)
var target_type: String = "force"
var target_id: String = ""
var controller_id: String = ""
var strength: int = 100 # 0-100 实控强度
# Control Type: "de_jure" (名实相符), "de_facto" (事实实控), "disputed" (争夺中), "usurped" (僭据占有)
var control_type: String = "de_jure"

func to_dict() -> Dictionary:
	return {
		"control_id": control_id,
		"target_type": target_type,
		"target_id": target_id,
		"controller_id": controller_id,
		"strength": strength,
		"control_type": control_type
	}

static func from_dict(data: Dictionary) -> Variant:
	var script: GDScript = load("res://scripts/core/control_relation_state.gd")
	var instance = script.new()
	instance.control_id = str(data.get("control_id", ""))
	instance.target_type = str(data.get("target_type", "force"))
	instance.target_id = str(data.get("target_id", ""))
	instance.controller_id = str(data.get("controller_id", ""))
	instance.strength = int(data.get("strength", 100))
	instance.control_type = str(data.get("control_type", "de_jure"))
	return instance
