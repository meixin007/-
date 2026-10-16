extends RefCounted

class_name GovernanceReportService

const REPORT_KINDS := ["receipt", "progress", "anomaly", "closure"]
const ANOMALY_CONDITIONS := ["delayed", "blocked", "lost_contact"]
const OUTCOMES := ["", "completed", "partial", "failed"]
const INTERNAL_FIELDS := [
	"score", "hidden_score", "future_effects", "private_basis", "truth_payload",
	"resolver_trace", "rule_seed", "internal_notes"
]
const ACTION_LABELS := {
	"prioritize_grain_transport": "核验并转运粮道",
	"verify_rations": "核验军民配给与仓粮",
	"review_gate_records": "复核宫门与中书传令"
}
const CHARACTER_LABELS := {
	"guo_ziyi": "郭子仪",
	"li_bi": "李泌",
	"li_fuguo": "李辅国",
	"grain_official_lingwu": "灵武粮官",
	"chen_xuanli": "陈玄礼"
}
const LOCATION_LABELS := {
	"shuofang_front_node": "朔方前营",
	"lingwu_court_node": "灵武行在",
	"palace_inner_channel_node": "宫门内道"
}
const RESOURCE_LABELS := {
	"grain": "粮食",
	"treasury": "钱粮",
	"court_authority": "朝廷权威"
}

func create_from_plan(state, plan: Dictionary, governance_data: Dictionary = {}) -> Dictionary:
	if state == null or not (plan is Dictionary):
		return _fail("report plan is invalid", "invalid_report_plan")
	var source: Dictionary = plan.get("report", plan) if plan.get("report", plan) is Dictionary else {}
	var validation := _validate_plan(state, source, governance_data)
	if not bool(validation.get("ok", false)):
		return validation
	var governance: Dictionary = _governance(state)
	var report_id := str(source.get("report_id", "")).strip_edges()
	if report_id.is_empty():
		report_id = _next_report_id(governance)
	if (governance.get("reports", []) as Array).any(func(raw): return raw is Dictionary and str((raw as Dictionary).get("report_id", "")) == report_id):
		return _fail("report id already exists", "duplicate_report")
	var arrival_day := int(source.get("arrival_day", source.get("day", _current_day(state))))
	var created_day := int(source.get("created_day", _current_day(state)))
	var template: Dictionary = validation.get("template", {})
	var kind := str(source.get("kind", "progress"))
	var condition := str(source.get("condition", "normal"))
	var outcome := str(source.get("outcome", ""))
	var title := str(source.get("title", template.get("title", ""))).strip_edges()
	var summary := str(source.get("summary", "")).strip_edges()
	if summary.is_empty():
		summary = _first_non_empty([_execution_summary(source), template.get("summary", "")])
	var source_kind := str(source.get("source_kind", "")).strip_edges()
	var report := {
		"report_id": report_id,
		"order_id": str(source.get("order_id", "")),
		"case_chain_id": str(source.get("case_chain_id", "")),
		"kind": kind,
		"condition": condition,
		"outcome": outcome,
		"status": str(source.get("status", outcome if not outcome.is_empty() else condition)),
		"created_day": created_day,
		"arrival_day": arrival_day,
		"delivered_day": int(source.get("delivered_day", -1)),
		"day": arrival_day,
		"title": title,
		"summary": summary,
		"source_label": str(source.get("source_label", template.get("source_label", "行在传令"))),
		"confidence": clampf(float(source.get("confidence", 0.75)), 0.0, 1.0),
		"related_character_ids": _string_array(source.get("related_character_ids", [])),
		"related_location_ids": _string_array(source.get("related_location_ids", [])),
		"causes": _copy_array(source.get("causes", [])),
		"effects": _copy_array(source.get("effects", [])),
		"available_actions": _copy_array(source.get("available_actions", [])),
		"execution_details": (source.get("execution_details", {}) as Dictionary).duplicate(true) if source.get("execution_details", {}) is Dictionary else {},
		"template_family": str(source.get("template_family", "")),
		"template_id": str(source.get("template_id", "")),
		"public_text": str(source.get("public_text", "")),
		"wording_source": str(source.get("wording_source", "offline"))
	}
	if source_kind == "political_season_review":
		report["source_kind"] = source_kind
		report["review_id"] = str(source.get("review_id", "")).strip_edges()
		report["node_id"] = str(source.get("node_id", "")).strip_edges()
		report["source_ids"] = _string_array(source.get("source_ids", []))
	# A report plan may carry effects for later application, but the report itself is
	# immutable after creation except for delivered_day/public_text wording.
	var reports: Array = (governance.get("reports", []) as Array).duplicate(true)
	reports.append(report.duplicate(true))
	governance["reports"] = reports
	if not governance.has("next_sequence"):
		governance["next_sequence"] = 1
	return {"ok": true, "report_id": report_id, "report": report.duplicate(true)}

func deliver_due(state, governance_data: Dictionary = {}) -> Dictionary:
	if state == null:
		return _fail("missing state", "missing_state")
	var governance: Dictionary = _governance(state)
	var reports: Array = governance.get("reports", []) if governance.get("reports", []) is Array else []
	var delivered: Array = []
	var current_day := _current_day(state)
	var updated: Array = []
	for raw_report in reports:
		if not (raw_report is Dictionary):
			return _fail("invalid report record", "invalid_report")
		var report: Dictionary = (raw_report as Dictionary).duplicate(true)
		var arrival_day := int(report.get("arrival_day", report.get("day", report.get("created_day", 0))))
		var delivered_day := int(report.get("delivered_day", -1))
		var needs_delivery := delivered_day < 0 and arrival_day <= current_day
		var needs_visible_content := _visible_content_missing(report)
		if arrival_day <= current_day and (needs_delivery or needs_visible_content):
			var template := _template_for(report, governance_data)
			if not bool(template.get("ok", true)):
				return template
			if needs_delivery:
				report["delivered_day"] = current_day
				report["day"] = arrival_day
			_ensure_visible_content(report, template)
			if needs_delivery:
				delivered.append(report.duplicate(true))
		updated.append(report)
	governance["reports"] = updated
	return {"ok": true, "delivered": delivered}

func project_arrivals(state, current_day: int) -> Array:
	var arrived: Array = []
	if state == null:
		return arrived
	var reports: Variant = _governance(state).get("reports", [])
	if not (reports is Array):
		return arrived
	for raw_report in reports:
		if not (raw_report is Dictionary):
			continue
		var report: Dictionary = raw_report as Dictionary
		var arrival_day := int(report.get("arrival_day", report.get("day", report.get("created_day", 0))))
		var delivered_day := int(report.get("delivered_day", -1))
		if arrival_day > current_day or delivered_day < 0:
			continue
		arrived.append(_public_projection(report))
	arrived.sort_custom(func(left, right):
		var left_day := int((left as Dictionary).get("arrival_day", (left as Dictionary).get("day", 0)))
		var right_day := int((right as Dictionary).get("arrival_day", (right as Dictionary).get("day", 0)))
		if left_day != right_day:
			return left_day < right_day
		return str((left as Dictionary).get("report_id", "")) < str((right as Dictionary).get("report_id", "")))
	return arrived

func project_order_reports(state, order_id: String, current_day: int) -> Array:
	var result: Array = []
	for report in project_arrivals(state, current_day):
		if str((report as Dictionary).get("order_id", "")) == order_id:
			result.append(report)
	return result

func validate_report(state, report: Dictionary, governance_data: Dictionary = {}) -> Dictionary:
	return _validate_plan(state, report, governance_data)

func _validate_plan(state, source: Dictionary, governance_data: Dictionary) -> Dictionary:
	if source.is_empty():
		return _fail("report plan is empty", "invalid_report_plan")
	var report_id := str(source.get("report_id", ""))
	if not report_id.is_empty() and (report_id.length() > 128 or report_id.strip_edges().is_empty()):
		return _fail("report id is invalid", "invalid_report_id")
	var governance: Dictionary = _governance(state)
	var source_kind := str(source.get("source_kind", "")).strip_edges()
	if source_kind == "political_season_review":
		var review_validation := _validate_political_season_review_source(state, source)
		if not bool(review_validation.get("ok", false)):
			return review_validation
	else:
		var order_id := str(source.get("order_id", "")).strip_edges()
		if order_id.is_empty():
			return _fail("report order reference is required", "missing_order_reference")
		var orders: Variant = governance.get("orders", {})
		if orders is Dictionary and not (orders as Dictionary).is_empty() and not (orders as Dictionary).has(order_id):
			return _fail("report order reference is invalid", "invalid_order_reference")
	var chain_id := str(source.get("case_chain_id", "")).strip_edges()
	if not chain_id.is_empty():
		var chains: Variant = governance_data.get("case_chains", [])
		if chains is Array and not (chains as Array).is_empty() and not _contains_id(chains as Array, "case_chain_id", chain_id):
			return _fail("report case chain reference is invalid", "invalid_case_chain_reference")
		var memorials: Variant = governance.get("memorials", {})
		if memorials is Dictionary and not (memorials as Dictionary).is_empty() and not _has_chain(memorials as Dictionary, chain_id):
			return _fail("report case chain reference is invalid", "invalid_case_chain_reference")
	var kind := str(source.get("kind", "progress"))
	if not REPORT_KINDS.has(kind):
		return _fail("report kind is invalid", "invalid_report_kind")
	var condition := str(source.get("condition", "normal"))
	if kind == "anomaly":
		if not ANOMALY_CONDITIONS.has(condition):
			return _fail("anomaly condition is invalid", "invalid_report_condition")
	elif condition != "normal":
		return _fail("non-anomaly report condition is invalid", "invalid_report_condition")
	var outcome := str(source.get("outcome", ""))
	if not OUTCOMES.has(outcome):
		return _fail("report outcome is invalid", "invalid_report_outcome")
	if kind == "closure" and outcome.is_empty():
		return _fail("closure report outcome is required", "missing_report_outcome")
	var created_day := int(source.get("created_day", _current_day(state)))
	var arrival_day := int(source.get("arrival_day", source.get("day", created_day)))
	if created_day < 0 or arrival_day < created_day:
		return _fail("report arrival day is invalid", "invalid_report_day")
	var delivered_day := int(source.get("delivered_day", -1))
	if delivered_day < -1:
		return _fail("report delivered day is invalid", "invalid_report_day")
	if delivered_day >= 0 and delivered_day < arrival_day:
		return _fail("report delivered day precedes arrival", "invalid_report_day")
	var template := _template_for(source, governance_data)
	if not bool(template.get("ok", false)):
		return template
	return {"ok": true, "template": template.get("template", {})}

func _template_for(report: Dictionary, governance_data: Dictionary) -> Dictionary:
	var family_id := str(report.get("template_family", "")).strip_edges()
	var template_id := str(report.get("template_id", "")).strip_edges()
	if family_id.is_empty() or template_id.is_empty():
		return {"ok": true, "template": {}}
	var families: Variant = governance_data.get("report_templates", {})
	if not (families is Dictionary) or not (families as Dictionary).has(family_id):
		return _fail("report template family is invalid", "invalid_report_template_family")
	var family: Variant = (families as Dictionary).get(family_id, {})
	if not (family is Dictionary) or not (family as Dictionary).has(template_id):
		return _fail("report template id is invalid", "invalid_report_template_id")
	var template: Variant = (family as Dictionary).get(template_id, {})
	if not (template is Dictionary):
		return _fail("report template is invalid", "invalid_report_template")
	return {"ok": true, "template": (template as Dictionary).duplicate(true)}

func _render_public_text(report: Dictionary, template: Dictionary) -> String:
	var execution_text := _execution_summary(report)
	var template_text := str(template.get("public_text", "")).strip_edges()
	var text := _first_non_empty([
		template_text,
		report.get("public_text", ""),
		execution_text,
		template.get("summary", ""),
		report.get("summary", ""),
		report.get("title", ""),
		"行在回报"
	])
	var slots := {
		"causes": _join_strings(report.get("causes", [])),
		"effects": _join_strings(report.get("effects", [])),
		"actions": _join_strings(report.get("available_actions", [])),
		"condition": str(report.get("condition", "normal")),
		"outcome": str(report.get("outcome", "")),
		"execution": execution_text
	}
	for key in slots.keys():
		text = text.replace("{{%s}}" % key, str(slots[key]))
		text = text.replace("{%s}" % key, str(slots[key]))
	return text.strip_edges()

func _execution_summary(report: Dictionary) -> String:
	var details_value: Variant = report.get("execution_details", {})
	if not details_value is Dictionary or (details_value as Dictionary).is_empty():
		return ""
	var details: Dictionary = details_value
	var action_id := str(details.get("action_id", "")).strip_edges()
	var recipient_id := str(details.get("recipient_id", "")).strip_edges()
	var location_id := str(details.get("location_id", "")).strip_edges()
	var action_label := str(ACTION_LABELS.get(action_id, action_id if not action_id.is_empty() else "政令事项"))
	var recipient_label := str(CHARACTER_LABELS.get(recipient_id, recipient_id if not recipient_id.is_empty() else "受命官员"))
	var location_label := str(LOCATION_LABELS.get(location_id, location_id if not location_id.is_empty() else "指定地点"))
	var day := int(report.get("day", report.get("created_day", 0)))
	var lines: Array[String] = []
	lines.append("第%d日，%s在%s执行“%s”。" % [day, recipient_label, location_label, action_label])
	var requested := _format_resources(details.get("requested_resources", {}))
	if not requested.is_empty():
		lines.append("资源要求：%s。" % requested)
	var stage := str(details.get("stage", ""))
	if stage == "closed":
		lines.append("结果：%s。" % _result_label(str(details.get("result", report.get("outcome", "")))))
		var usable := _format_resources(details.get("usable_resources", {}))
		if not usable.is_empty():
			lines.append("实际可用并计入执行的资源：%s。" % usable)
		var impact := _format_applied_effects(details.get("applied_effects", {}))
		if not impact.is_empty():
			lines.append("实际影响：%s。" % impact)
	else:
		lines.append("当前阶段：%s。" % _stage_label(stage))
		var condition := str(details.get("condition", "normal"))
		if condition != "normal":
			lines.append("当前状况：%s。" % _condition_label(condition))
	lines.append("下一步：%s。" % str(details.get("next_step", "等待下一阶段回报")))
	return "".join(lines)

func _format_resources(value: Variant) -> String:
	if not value is Dictionary or (value as Dictionary).is_empty():
		return ""
	var parts: Array[String] = []
	for raw_key in (value as Dictionary).keys():
		var key := str(raw_key)
		var label := str(RESOURCE_LABELS.get(key, key))
		parts.append("%s×%d" % [label, int((value as Dictionary).get(raw_key, 0))])
	return "、".join(parts)

func _format_applied_effects(value: Variant) -> String:
	if not value is Dictionary or (value as Dictionary).is_empty():
		return ""
	var effects: Dictionary = value
	var parts: Array[String] = []
	var consumed := _format_resources(effects.get("resource_consumed", {}))
	if not consumed.is_empty():
		parts.append("消耗" + consumed)
	if effects.has("relationship_delta"):
		parts.append("受命人与朝廷关系 %+d" % int(effects.get("relationship_delta", 0)))
	if bool(effects.get("memory_recorded", false)):
		parts.append("已留存结果记忆")
	if bool(effects.get("location_updated", false)):
		parts.append("地点已留下执行记录")
	return "、".join(parts)

func _stage_label(stage: String) -> String:
	return {
		"issued": "政令已发出",
		"delivered": "已抵达执行渠道",
		"acknowledged": "受命方已回执",
		"gathering": "正在收集执行材料",
		"executing": "正在执行",
		"closed": "已结案"
	}.get(stage, "待执行")

func _condition_label(condition: String) -> String:
	return {
		"delayed": "迟延",
		"blocked": "受阻",
		"lost_contact": "暂失联"
	}.get(condition, condition)

func _result_label(result: String) -> String:
	return {
		"completed": "执行完成",
		"partial": "部分完成",
		"failed": "执行失败"
	}.get(result, result if not result.is_empty() else "尚无结论")

func _visible_content_missing(report: Dictionary) -> bool:
	return str(report.get("public_text", "")).strip_edges().is_empty() \
		or str(report.get("title", "")).strip_edges().is_empty() \
		or str(report.get("summary", "")).strip_edges().is_empty()

func _ensure_visible_content(report: Dictionary, template: Dictionary) -> void:
	var template_data: Dictionary = template.get("template", {}) if template.get("template", {}) is Dictionary else {}
	if str(report.get("public_text", "")).strip_edges().is_empty():
		report["public_text"] = _render_public_text(report, template_data)
	if str(report.get("title", "")).strip_edges().is_empty():
		report["title"] = _first_non_empty([template_data.get("title", ""), report.get("public_text", ""), "行在回报"])
	if str(report.get("summary", "")).strip_edges().is_empty():
		report["summary"] = _first_non_empty([template_data.get("summary", ""), report.get("public_text", ""), report.get("title", ""), "行在回报"])

func _first_non_empty(values: Array) -> String:
	for value in values:
		var candidate := str(value).strip_edges()
		if not candidate.is_empty():
			return candidate
	return ""

func _public_projection(report: Dictionary) -> Dictionary:
	var projected: Dictionary = report.duplicate(true)
	for key in INTERNAL_FIELDS:
		projected.erase(key)
	return projected

func _governance(state) -> Dictionary:
	if state is Dictionary:
		var value: Variant = (state as Dictionary).get("governance_state", {})
		return value if value is Dictionary else {}
	if state != null:
		var value: Variant = state.get("governance_state")
		return value if value is Dictionary else {}
	return {}

func _current_day(state) -> int:
	if state is Dictionary:
		return int((state as Dictionary).get("current_day", 0))
	if state != null:
		return int(state.get("current_day"))
	return 0

func _validate_political_season_review_source(state, source: Dictionary) -> Dictionary:
	var review_id := str(source.get("review_id", "")).strip_edges()
	if review_id.is_empty():
		return _fail("political season review reference is required", "missing_review_reference")
	var node_id := str(source.get("node_id", "")).strip_edges()
	if node_id.is_empty():
		return _fail("political season review node reference is required", "missing_review_node_reference")
	var raw_source_ids: Variant = source.get("source_ids", null)
	if not raw_source_ids is Array:
		return _fail("political season review source_ids must be an array", "invalid_report_sources")
	var source_ids: Array = []
	var seen: Dictionary = {}
	for raw_source_id in (raw_source_ids as Array):
		if not raw_source_id is String:
			return _fail("political season review source_id is invalid", "invalid_report_source")
		var source_id := str(raw_source_id).strip_edges()
		if source_id.is_empty():
			return _fail("political season review source_id is invalid", "invalid_report_source")
		if seen.has(source_id):
			return _fail("political season review source_ids must be distinct", "duplicate_report_source")
		if not _has_authoritative_source(state, source_id):
			return _fail("political season review source is unknown: %s" % source_id, "unknown_report_source")
		seen[source_id] = true
		source_ids.append(source_id)
	if source_ids.size() < 3:
		return _fail("political season review requires at least three source_ids", "insufficient_report_sources")
	return {"ok": true, "source_ids": source_ids}

func _has_authoritative_source(state, source_id: String) -> bool:
	if source_id.is_empty():
		return false
	for key in [
		"chronicle_causal_references", "event_history", "active_events", "resolved_events",
		"battlefront_reports", "structured_memories", "active_npc_actions", "npc_action_feed",
		"intelligence_report_history"
	]:
		if _collection_contains_source(_state_value(state, key, []), source_id):
			return true
	for key in [
		"accountability_cases", "office_terms", "political_debts", "processed_transactions",
		"active_intelligence_reports"
	]:
		if _collection_contains_source(_state_value(state, key, {}), source_id):
			return true
	var governance: Dictionary = _governance(state)
	for key in ["memorials", "orders", "reports", "councils", "consultations"]:
		if _collection_contains_source(governance.get(key, {}), source_id):
			return true
	return false

func _state_value(state, key: String, fallback: Variant) -> Variant:
	if state is Dictionary:
		return (state as Dictionary).get(key, fallback)
	if state != null:
		var value: Variant = state.get(key)
		return fallback if value == null else value
	return fallback

func _collection_contains_source(collection: Variant, source_id: String) -> bool:
	if collection is Array:
		for raw_record in (collection as Array):
			if raw_record is Dictionary and _record_contains_source(raw_record as Dictionary, source_id):
				return true
		return false
	if not collection is Dictionary:
		return false
	var records: Dictionary = collection
	if _record_contains_source(records, source_id) or records.has(source_id):
		return true
	for raw_record in records.values():
		if raw_record is Dictionary and _record_contains_source(raw_record as Dictionary, source_id):
			return true
	return false

func _record_contains_source(record: Dictionary, source_id: String) -> bool:
	for key in [
		"id", "source_id", "reference_id", "ref_id", "case_id", "verdict_id", "transaction_id",
		"order_id", "memorial_id", "followup_id", "echo_id", "report_id", "event_id",
		"memory_id", "debt_id", "office_id", "chronicle_id"
	]:
		if str(record.get(key, "")) == source_id:
			return true
	for key in ["source_ids", "source_refs", "source_references"]:
		var raw_ids: Variant = record.get(key, [])
		if raw_ids is Array and (raw_ids as Array).has(source_id):
			return true
	return false

func _next_report_id(governance: Dictionary) -> String:
	var sequence := maxi(int(governance.get("next_sequence", 1)), 1)
	governance["next_sequence"] = sequence + 1
	return "report_%06d" % sequence

func _contains_id(records: Array, key: String, expected: String) -> bool:
	for raw in records:
		if raw is Dictionary and str((raw as Dictionary).get(key, "")) == expected:
			return true
	return false

func _has_chain(memorials: Dictionary, chain_id: String) -> bool:
	for value in memorials.values():
		if value is Dictionary and str((value as Dictionary).get("case_chain_id", "")) == chain_id:
			return true
	return false

func _string_array(value: Variant) -> Array:
	var result: Array = []
	if value is Array:
		for item in value:
			var text := str(item).strip_edges()
			if not text.is_empty():
				result.append(text)
	return result

func _join_strings(value: Variant) -> String:
	var values: Array = []
	if value is Array:
		for item in value:
			values.append(JSON.stringify(item) if item is Dictionary or item is Array else str(item))
	return "、".join(values)

func _copy_array(value: Variant) -> Array:
	return (value as Array).duplicate(true) if value is Array else []

func _fail(message: String, code: String) -> Dictionary:
	return {"ok": false, "code": code, "error": message, "message": message}
