extends RefCounted

class_name CourtWorkbenchRouter

const CAMPAIGN_INTRO_ACKNOWLEDGED_KEY := "campaign_intro_acknowledged"
const POLITICAL_SEASON_REVIEW_ACKNOWLEDGED_KEY := "beta109_season_review_acknowledged"
const BETA110_POLITICAL_SEASON_REVIEW_ACKNOWLEDGED_KEY := "beta110_season_review_acknowledged"
const BETA110_REVIEW_DAYS := {
	"beta110_supply_review": 45,
	"beta110_authority_review": 65,
	"beta110_final_assessment": 90
}
const VALID_MODES := ["Court", "Characters", "Offices", "Management", "Assistant", "Factions", "Clans", "Memorials", "Council", "Nodes", "Tasks", "War", "Chronicle", "Items"]
const MODE_SELECTION_KEYS := {
	"Characters": "selected_character_id",
	"Offices": "selected_office_id",
	"Management": "selected_asset_id",
	"Factions": "selected_faction_id",
	"Clans": "selected_clan_id",
	"Council": "selected_governance_council_id",
	"Nodes": "selected_node_id",
	"War": "selected_route_id",
	"Tasks": "selected_task_id",
	"Chronicle": "selected_report_id",
	"Memorials": "selected_memorial_id",
	"Items": "selected_item_id"
}

func select_mode(state, mode: String) -> Dictionary:
	if state == null:
		return _fail("missing state")
	if not VALID_MODES.has(mode):
		return _fail("invalid workbench mode: " + mode)
	state.court_workbench_state["mode"] = mode
	return {"ok": true, "mode": mode}

func normalize_mode(mode: String) -> String:
	return mode if VALID_MODES.has(mode) else "Court"

func selection_key_for(kind: String) -> String:
	if MODE_SELECTION_KEYS.has(kind):
		return str(MODE_SELECTION_KEYS[kind])
	var normalized := kind.to_lower()
	return "selected_" + normalized + "_id"

func normalized_selection(state, mode: String) -> Dictionary:
	var normalized_mode := normalize_mode(mode)
	if state == null:
		return {"mode": normalized_mode, "selection": {}}
	var key := selection_key_for(normalized_mode)
	var workbench: Dictionary = state.court_workbench_state if state.get("court_workbench_state") is Dictionary else {}
	return {"mode": normalized_mode, "selection": {key: str(workbench.get(key, ""))}}

func open_settings(state) -> Dictionary:
	if state == null:
		return _fail("missing state")
	state.court_workbench_state["settings_open"] = true
	return {"ok": true}

func close_settings(state) -> Dictionary:
	if state == null:
		return _fail("missing state")
	state.court_workbench_state["settings_open"] = false
	return {"ok": true}

func is_campaign_intro_acknowledged(state) -> bool:
	return state != null and state.get("court_workbench_state") is Dictionary and bool(state.court_workbench_state.get(CAMPAIGN_INTRO_ACKNOWLEDGED_KEY, false))

func acknowledge_campaign_intro(state) -> Dictionary:
	if state == null or not (state.get("court_workbench_state") is Dictionary):
		return _fail("missing state")
	var next: Dictionary = state.court_workbench_state.duplicate(true)
	next[CAMPAIGN_INTRO_ACKNOWLEDGED_KEY] = true
	state.court_workbench_state = next
	return {"ok": true, "acknowledged": true}

func is_political_season_review_acknowledged(state) -> bool:
	if state == null or not (state.get("court_workbench_state") is Dictionary):
		return false
	var flags: Variant = state.get("flags")
	if flags is Dictionary and str((flags as Dictionary).get("campaign_id", "")) == "anshi_beta_1_10":
		var acknowledged: Variant = state.court_workbench_state.get("political_season_reviews_acknowledged", {})
		if not acknowledged is Dictionary:
			return false
		var current_day := int(state.get("current_day"))
		var selected_review_id := ""
		for review_id in BETA110_REVIEW_DAYS.keys():
			if current_day >= int(BETA110_REVIEW_DAYS[review_id]) and (selected_review_id.is_empty() or int(BETA110_REVIEW_DAYS[review_id]) > int(BETA110_REVIEW_DAYS[selected_review_id])):
				selected_review_id = str(review_id)
		return not selected_review_id.is_empty() and bool((acknowledged as Dictionary).get(selected_review_id, false))
	return bool(state.court_workbench_state.get(_political_season_review_acknowledged_key(state), false))

func acknowledge_political_season_review(state) -> Dictionary:
	if state == null or not (state.get("court_workbench_state") is Dictionary):
		return _fail("missing state")
	var flags: Variant = state.get("flags")
	var campaign_id := str((flags as Dictionary).get("campaign_id", "")) if flags is Dictionary else ""
	if campaign_id not in ["anshi_beta_1_09", "anshi_beta_1_10", "anshi_beta_1_13"] and not campaign_id.begins_with("anshi_beta_1_"):
		return {"ok": false, "code": "unsupported_campaign", "error": "political season review requires BETA 1.09, BETA 1.10, or BETA 1.13"}
	if campaign_id in ["anshi_beta_1_10", "anshi_beta_1_13"] or campaign_id.begins_with("anshi_beta_1_1"):
		return {"ok": false, "code": "review_service_required", "error": "Multi-phase review acknowledgement must use PoliticalSeasonReviewService"}
	var review_day := 30 if campaign_id == "anshi_beta_1_09" else 45
	if int(state.get("current_day")) < review_day:
		return {"ok": false, "code": "review_not_ready", "error": "political season review requires day %d" % review_day}
	if is_political_season_review_acknowledged(state):
		return {"ok": true, "code": "no_op", "acknowledged": true}
	var next: Dictionary = state.court_workbench_state.duplicate(true)
	next[_political_season_review_acknowledged_key(state)] = true
	state.court_workbench_state = next
	return {"ok": true, "code": "acknowledged", "acknowledged": true}

func select_report(state, report_id: String) -> Dictionary:
	if state == null or not (state.get("court_workbench_state") is Dictionary):
		return _fail("missing state")
	var clean_id := report_id.strip_edges()
	if clean_id.is_empty():
		return _fail("report id is required")
	var next: Dictionary = state.court_workbench_state.duplicate(true)
	next["selected_report_id"] = clean_id
	state.court_workbench_state = next
	return {"ok": true, "selected_report_id": clean_id}

func set_right_context(state, kind: String, payload: Dictionary = {}) -> Dictionary:
	if state == null:
		return _fail("missing state")
	state.court_workbench_state["right_context_kind"] = kind
	state.court_workbench_state["right_context_payload"] = payload.duplicate(true)
	return {"ok": true}

func _political_season_review_acknowledged_key(state) -> String:
	var flags: Variant = state.get("flags") if state != null else {}
	var campaign_id := str((flags as Dictionary).get("campaign_id", "")) if flags is Dictionary else ""
	return BETA110_POLITICAL_SEASON_REVIEW_ACKNOWLEDGED_KEY if (campaign_id in ["anshi_beta_1_10", "anshi_beta_1_13"] or campaign_id.begins_with("anshi_beta_1_1")) else POLITICAL_SEASON_REVIEW_ACKNOWLEDGED_KEY

func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
