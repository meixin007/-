extends RefCounted

class_name PoliticalSeasonProgressionGuard

const CAMPAIGN_ID := "anshi_beta_1_10"
const ROUTE_REQUIRED_CODE := "beta110_route_required"
const REVIEW_REQUIRED_CODES := {
	"beta110_supply_review": "beta110_supply_review_required",
	"beta110_authority_review": "beta110_authority_review_required",
	"beta110_final_assessment": "beta110_final_assessment_required"
}

static func can_advance(state) -> Dictionary:
	if state == null or not (state is Object or state is Dictionary):
		return _fail("invalid_state", "political season progression requires a valid state")
	var flags: Variant = state.get("flags") if state is Object else state.get("flags", {})
	if flags == null:
		return {"ok": true, "code": "advance_allowed"}
	if not flags is Dictionary:
		return _fail("invalid_state", "political season progression requires state flags")
	var campaign_id := str((flags as Dictionary).get("campaign_id", ""))
	if campaign_id != CAMPAIGN_ID:
		return {"ok": true, "code": "advance_allowed"}
	var current_day := int(state.get("current_day") if state is Object else state.get("current_day", 0))
	var route_id := str((flags as Dictionary).get("beta110_route_id", "")).strip_edges()
	if route_id.is_empty():
		route_id = str((flags as Dictionary).get("beta110_public_route_id", "")).strip_edges()
	if current_day >= 31 and route_id.is_empty():
		return _progression_fail(
			ROUTE_REQUIRED_CODE,
			"confirm an aftershock route before advancing time",
			"",
			true,
			"select_and_confirm_beta110_route"
		)
	var workbench: Variant = state.get("court_workbench_state") if state is Object else state.get("court_workbench_state", {})
	var acknowledged: Dictionary = workbench.get("political_season_reviews_acknowledged", {}) if workbench is Dictionary and workbench.get("political_season_reviews_acknowledged", {}) is Dictionary else {}
	if current_day >= 45 and not bool(acknowledged.get("beta110_supply_review", false)):
		return _progression_fail(
			REVIEW_REQUIRED_CODES["beta110_supply_review"],
			"acknowledge the supply review before advancing time",
			"beta110_supply_review",
			false,
			"acknowledge_beta110_supply_review"
		)
	if current_day >= 65 and not bool(acknowledged.get("beta110_authority_review", false)):
		return _progression_fail(
			REVIEW_REQUIRED_CODES["beta110_authority_review"],
			"acknowledge the authority review before advancing time",
			"beta110_authority_review",
			false,
			"acknowledge_beta110_authority_review"
		)
	if current_day == 90 and not bool(acknowledged.get("beta110_final_assessment", false)):
		return _progression_fail(
			REVIEW_REQUIRED_CODES["beta110_final_assessment"],
			"acknowledge the final assessment before advancing time",
			"beta110_final_assessment",
			false,
			"acknowledge_beta110_final_assessment"
		)
	return {"ok": true, "code": "advance_allowed"}

static func _progression_fail(code: String, message: String, blocking_review_id: String, route_required: bool, next_step: String) -> Dictionary:
	var result := _fail(code, message)
	result["reason_code"] = code
	result["blocking_review_id"] = blocking_review_id
	result["route_required"] = route_required
	result["next_step"] = next_step
	return result

static func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "error": message, "message": message}
