# scripts/core/position_claim_state.gd
extends RefCounted

class_name PositionClaimState

var claim_id: String = ""
var office_id: String = ""
var character_id: String = ""
var issuer_id: String = ""
# Status: "issued" (已签发), "in_transit" (赴任中), "active" (有效履职), "disputed" (争议中), "revoked" (已撤销), "pending_confirmation" (待追认)
var claim_status: String = "active"
var issued_day: int = 1
var effective_day: int = 1
var basis_text: String = "诏敕特授"
var predecessor_claim_id: String = ""

func to_dict() -> Dictionary:
	return {
		"claim_id": claim_id,
		"office_id": office_id,
		"character_id": character_id,
		"issuer_id": issuer_id,
		"claim_status": claim_status,
		"issued_day": issued_day,
		"effective_day": effective_day,
		"basis_text": basis_text,
		"predecessor_claim_id": predecessor_claim_id
	}

static func from_dict(data: Dictionary) -> Variant:
	var script: GDScript = load("res://scripts/core/position_claim_state.gd")
	var instance = script.new()
	instance.claim_id = str(data.get("claim_id", ""))
	instance.office_id = str(data.get("office_id", ""))
	instance.character_id = str(data.get("character_id", ""))
	instance.issuer_id = str(data.get("issuer_id", ""))
	instance.claim_status = str(data.get("claim_status", "active"))
	instance.issued_day = int(data.get("issued_day", 1))
	instance.effective_day = int(data.get("effective_day", 1))
	instance.basis_text = str(data.get("basis_text", "诏敕特授"))
	instance.predecessor_claim_id = str(data.get("predecessor_claim_id", ""))
	return instance
