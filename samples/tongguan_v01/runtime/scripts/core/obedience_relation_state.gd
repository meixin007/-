# scripts/core/obedience_relation_state.gd
extends RefCounted

class_name ObedienceRelationState

var obedience_id: String = ""
var subordinate_id: String = ""
var superior_id: String = ""
# Scope: "military" (军令), "administrative" (政令), "personal_loyalty" (私人效忠), "all" (全面服从)
var scope: String = "all"
var strength: int = 80 # 0-100 服从度/服从倾向
# Basis: "formal_mandate" (朝廷名分), "personal_bond" (门生/故旧/恩情), "patronage" (幕府辟召), "fear" (威慑恐惧), "stipend" (军饷赏赐)
var basis: String = "formal_mandate"

func to_dict() -> Dictionary:
	return {
		"obedience_id": obedience_id,
		"subordinate_id": subordinate_id,
		"superior_id": superior_id,
		"scope": scope,
		"strength": strength,
		"basis": basis
	}

static func from_dict(data: Dictionary) -> Variant:
	var script: GDScript = load("res://scripts/core/obedience_relation_state.gd")
	var instance = script.new()
	instance.obedience_id = str(data.get("obedience_id", ""))
	instance.subordinate_id = str(data.get("subordinate_id", ""))
	instance.superior_id = str(data.get("superior_id", ""))
	instance.scope = str(data.get("scope", "all"))
	instance.strength = int(data.get("strength", 80))
	instance.basis = str(data.get("basis", "formal_mandate"))
	return instance
