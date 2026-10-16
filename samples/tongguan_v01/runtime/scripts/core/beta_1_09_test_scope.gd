extends RefCounted

class_name Beta109TestScope

const CAMPAIGN_ID := "anshi_beta_1_09"
const BETA110_CAMPAIGN_ID := "anshi_beta_1_10"
const SUPPORTED_CAMPAIGN_IDS := [CAMPAIGN_ID, BETA110_CAMPAIGN_ID, "anshi_beta_1_13"]
const MEMORIAL_IDS := [
	"memorial_shuofang_grain_001",
	"memorial_lingwu_ration_001",
	"memorial_gate_review_001"
]
const REQUEST_SCOPE_TAGS := ["beta109", "beta109_test"]
const BETA110_REQUEST_SCOPE_TAGS := ["beta110", "beta110_test"]
const ACTIVE_MEMORIAL_STATUSES := ["unread", "read", "consulting", "council"]

static func _is_multi_phase_campaign(campaign_id: String) -> bool:
	return campaign_id in [BETA110_CAMPAIGN_ID, "anshi_beta_1_13"] or campaign_id.begins_with("anshi_beta_1_1")

static func is_current(state = null, data: Dictionary = {}) -> bool:
	return SUPPORTED_CAMPAIGN_IDS.has(_campaign_id(state, data)) or _campaign_id(state, data).begins_with("anshi_beta_1_")

static func is_memorial_visible(memorial: Dictionary, state = null, data: Dictionary = {}) -> bool:
	if not _is_active_memorial(memorial):
		return false
	var campaign_id := _campaign_id(state, data)
	if not SUPPORTED_CAMPAIGN_IDS.has(campaign_id) and not campaign_id.begins_with("anshi_beta_1_"):
		return true
	var memorial_id := str(memorial.get("memorial_id", "")).strip_edges()
	if MEMORIAL_IDS.has(memorial_id):
		return true
	if _is_multi_phase_campaign(campaign_id):
		return _is_beta110_memorial(memorial, data)
	return false

static func is_request_visible(request: Dictionary, state = null, data: Dictionary = {}) -> bool:
	var campaign_id := _campaign_id(state, data)
	if not SUPPORTED_CAMPAIGN_IDS.has(campaign_id) and not campaign_id.begins_with("anshi_beta_1_"):
		return true
	var source_memorial_id := str(request.get("source_memorial_id", request.get("memorial_id", ""))).strip_edges()
	if MEMORIAL_IDS.has(source_memorial_id):
		return true
	if _is_multi_phase_campaign(campaign_id) and _contains_entry_id(data.get("beta110_followups", []), "memorial_id", source_memorial_id):
		return true
	var source_campaign_id := str(request.get("source_campaign_id", "")).strip_edges()
	if not source_campaign_id.is_empty():
		return source_campaign_id == campaign_id or (_is_multi_phase_campaign(campaign_id) and (source_campaign_id == CAMPAIGN_ID or source_campaign_id == BETA110_CAMPAIGN_ID or _is_multi_phase_campaign(source_campaign_id)))
	var allowed_scopes := REQUEST_SCOPE_TAGS.duplicate()
	if _is_multi_phase_campaign(campaign_id):
		allowed_scopes.append_array(BETA110_REQUEST_SCOPE_TAGS)
	var scope := str(request.get("test_scope", "")).strip_edges()
	if scope == campaign_id or allowed_scopes.has(scope):
		return true
	var raw_tags: Variant = request.get("request_tags", request.get("tags", []))
	if raw_tags is Array:
		for raw_tag in raw_tags:
			var tag := str(raw_tag).strip_edges()
			if REQUEST_SCOPE_TAGS.has(tag) or (_is_multi_phase_campaign(campaign_id) and BETA110_REQUEST_SCOPE_TAGS.has(tag)):
				return true
	var request_id := str(request.get("request_id", "")).strip_edges()
	if request_id.begins_with("routine__beta109") or request_id.begins_with("beta109__"):
		return true
	return _is_multi_phase_campaign(campaign_id) and (request_id.begins_with("routine__beta110") or request_id.begins_with("beta110__"))

static func memorial_label(memorial_id: String) -> String:
	match memorial_id:
		"memorial_shuofang_grain_001":
			return "测试节点 1｜粮道转运"
		"memorial_lingwu_ration_001":
			return "测试节点 2｜仓粮配给"
		"memorial_gate_review_001":
			return "测试节点 3｜宫门传令复核"
		_:
			return ""

static func _campaign_id(state = null, data: Dictionary = {}) -> String:
	var data_campaign_id := str(data.get("campaign_id", "")).strip_edges()
	if not data_campaign_id.is_empty():
		return data_campaign_id
	if state == null:
		return ""
	var flags: Variant = state.get("flags", {}) if state is Dictionary else state.get("flags")
	if flags is Dictionary:
		return str((flags as Dictionary).get("campaign_id", "")).strip_edges()
	return ""

static func _is_active_memorial(memorial: Dictionary) -> bool:
	return ACTIVE_MEMORIAL_STATUSES.has(str(memorial.get("status", "unread")).strip_edges())

static func _is_beta110_memorial(memorial: Dictionary, data: Dictionary) -> bool:
	var memorial_id := str(memorial.get("memorial_id", "")).strip_edges()
	if _contains_entry_id(data.get("beta110_followups", []), "memorial_id", memorial_id):
		return true
	var node_id := str(memorial.get("node_id", "")).strip_edges()
	if _contains_entry_id(data.get("beta110_nodes", []), "node_id", node_id):
		return true
	var case_id := str(memorial.get("linked_case_id", memorial.get("case_chain_id", ""))).strip_edges()
	return _contains_entry_id(data.get("beta110_nodes", []), "case_id", case_id)

static func _contains_entry_id(raw_entries: Variant, key: String, expected_id: String) -> bool:
	if expected_id.is_empty() or not raw_entries is Array:
		return false
	for raw_entry in raw_entries as Array:
		if raw_entry is Dictionary and str((raw_entry as Dictionary).get(key, "")).strip_edges() == expected_id:
			return true
	return false
