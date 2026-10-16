# scripts/core/character_scheme_state.gd
extends RefCounted

var scheme_id: String = ""
var actor_id: String = ""
var target_id: String = ""
var target_type: String = "office" # office / character / force / depot / policy
var scheme_kind: String = "usurp_office" # usurp_office / hoard_grain / impeach_rival / petition_autonomy / secure_border / advance_patronage / secretly_collaborate
var scheme_name: String = ""
var progress: int = 0 # 0 - 100
var progress_speed: int = 5
var is_revealed: bool = false
var evidence_level: int = 0 # 0 - 100
var secret_notes: String = ""
var trigger_conditions: Dictionary = {}
var outcome_effects: Dictionary = {}
var status: String = "active" # active / executing / completed / foiled / abandoned
var start_day: int = 1

func to_dict() -> Dictionary:
	return {
		"scheme_id": scheme_id,
		"actor_id": actor_id,
		"target_id": target_id,
		"target_type": target_type,
		"scheme_kind": scheme_kind,
		"scheme_name": scheme_name,
		"progress": progress,
		"progress_speed": progress_speed,
		"is_revealed": is_revealed,
		"evidence_level": evidence_level,
		"secret_notes": secret_notes,
		"trigger_conditions": trigger_conditions.duplicate(true),
		"outcome_effects": outcome_effects.duplicate(true),
		"status": status,
		"start_day": start_day
	}

static func from_dict(data: Dictionary) -> Variant:
	var script: GDScript = load("res://scripts/core/character_scheme_state.gd")
	var instance = script.new()
	instance.scheme_id = str(data.get("scheme_id", ""))
	instance.actor_id = str(data.get("actor_id", ""))
	instance.target_id = str(data.get("target_id", ""))
	instance.target_type = str(data.get("target_type", "office"))
	instance.scheme_kind = str(data.get("scheme_kind", "usurp_office"))
	instance.scheme_name = str(data.get("scheme_name", ""))
	instance.progress = int(data.get("progress", 0))
	instance.progress_speed = int(data.get("progress_speed", 5))
	instance.is_revealed = bool(data.get("is_revealed", false))
	instance.evidence_level = int(data.get("evidence_level", 0))
	instance.secret_notes = str(data.get("secret_notes", ""))
	var tc = data.get("trigger_conditions", {})
	if tc is Dictionary:
		instance.trigger_conditions = tc.duplicate(true)
	var oe = data.get("outcome_effects", {})
	if oe is Dictionary:
		instance.outcome_effects = oe.duplicate(true)
	instance.status = str(data.get("status", "active"))
	instance.start_day = int(data.get("start_day", 1))
	return instance
