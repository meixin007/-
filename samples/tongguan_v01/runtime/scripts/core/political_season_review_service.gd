extends RefCounted

class_name PoliticalSeasonReviewService

const GovernanceReportServiceScript = preload("res://scripts/core/governance_report_service.gd")
const GameStateTransactionScript = preload("res://scripts/core/game_state_transaction.gd")
const PhaseEndingEvaluatorScript = preload("res://scripts/core/phase_ending_evaluator.gd")

const CAMPAIGN_ID := "anshi_beta_1_10"
const COMMAND_KIND := "acknowledge_political_season_review"
const REVIEW_DAYS := {
	"beta110_supply_review": 45,
	"beta110_authority_review": 65,
	"beta110_final_assessment": 90
}
const REVIEW_PHASES := {
	"beta110_supply_review": "political_season_review",
	"beta110_authority_review": "authority_review",
	"beta110_final_assessment": "final_assessment"
}

var _transaction = GameStateTransactionScript.new()

func settle_daily(state, data: Dictionary, day: int) -> Dictionary:
	if state == null or str(data.get("campaign_id", "")) != CAMPAIGN_ID:
		return {"ok": true, "code": "no_op", "created_report_ids": []}
	var reviews := _reviews(data)
	var created: Array = []
	for raw_review in reviews:
		if not raw_review is Dictionary:
			return _fail("political season review must be a dictionary", "invalid_review")
		var review: Dictionary = raw_review as Dictionary
		if int(review.get("day", 0)) != day:
			continue
		var report_id := str(review.get("report_id", "")).strip_edges()
		var review_id := str(review.get("review_id", "")).strip_edges()
		if report_id.is_empty() or review_id.is_empty():
			return _fail("political season review requires stable ids", "invalid_review")
		if _has_report(state, report_id):
			continue
		var source_ids := _authoritative_source_ids(state, review)
		if source_ids.size() < 3:
			return _fail("political season review requires at least three authoritative sources", "insufficient_review_sources")
		var report_kind := "closure" if day == 90 else "progress"
		var outcome := "completed" if day == 90 else ""
		var plan := {
			"report_id": report_id,
			"source_kind": "political_season_review",
			"review_id": review_id,
			"node_id": str(review.get("node_id", "")),
			"source_ids": source_ids,
			"kind": report_kind,
			"condition": "normal",
			"outcome": outcome,
			"status": "queued",
			"created_day": day,
			"arrival_day": day,
			"title": str(review.get("title", review_id)),
			"summary": str(review.get("public_summary", review.get("summary", review_id))),
			"public_text": str(review.get("public_summary", review.get("summary", review_id))),
			"source_label": "政治季复盘",
			"confidence": 1.0,
			"related_location_ids": [str(review.get("node_id", ""))] if not str(review.get("node_id", "")).is_empty() else [],
			"causes": source_ids.duplicate(true),
			"effects": ["review:" + review_id]
		}
		var report_service := GovernanceReportServiceScript.new()
		var result: Dictionary = report_service.create_from_plan(state, plan, data.get("governance", {}) if data.get("governance", {}) is Dictionary else {})
		if not bool(result.get("ok", false)):
			return _fail(str(result.get("error", "review report creation failed")), str(result.get("code", "review_report_failed")))
		created.append(report_id)
	return {"ok": true, "code": "created" if not created.is_empty() else "no_op", "created_report_ids": created}

func preview_acknowledgement(context, review_id: String = "") -> Dictionary:
	if context == null or context.state == null or not context.scenario_data is Dictionary:
		return _fail("review acknowledgement requires a runtime context", "invalid_context")
	if str(context.scenario_data.get("campaign_id", "")) != CAMPAIGN_ID:
		return _fail("review acknowledgement requires BETA 1.10", "unsupported_campaign")
	var current := _current_review(context.state, context.scenario_data)
	if not bool(current.get("ok", false)):
		return current
	var requested_id := review_id.strip_edges()
	var candidate: Dictionary = current.get("review", {}) if current.get("review", {}) is Dictionary else {}
	var candidate_id := str(candidate.get("review_id", ""))
	if requested_id.is_empty():
		requested_id = candidate_id
	if requested_id != candidate_id:
		return _fail("only the current political season review can be acknowledged", "review_not_current")
	var input := {"review_id": requested_id}
	var preview: Dictionary = _transaction.preview_command(context.state, COMMAND_KIND, input)
	if not bool(preview.get("ok", false)):
		return preview
	var envelope: Dictionary = _transaction.build_command_envelope(COMMAND_KIND, input, preview.get("preview_token", {}))
	return {
		"ok": true,
		"code": "preview_ready",
		"review_id": requested_id,
		"review": candidate.duplicate(true),
		"input": input.duplicate(true),
		"input_hash": str(preview.get("input_hash", "")),
		"preview_token": envelope.get("preview_token", {}).duplicate(true),
		"envelope": envelope,
		"state_revision": int(context.state.state_revision)
	}

func confirm_acknowledgement(context, envelope: Dictionary) -> Dictionary:
	if context == null or context.state == null or not context.scenario_data is Dictionary:
		return _fail("review acknowledgement requires a runtime context", "invalid_context")
	if not envelope is Dictionary:
		return _fail("review acknowledgement requires an envelope", "invalid_envelope")
	if str(envelope.get("kind", "")) != COMMAND_KIND:
		return _fail("review acknowledgement command kind is invalid", "unknown_command_kind")
	var input: Variant = envelope.get("input", null)
	if not input is Dictionary:
		return _fail("review acknowledgement input is invalid", "invalid_command_payload")
	var review_id := str((input as Dictionary).get("review_id", "")).strip_edges()
	if review_id.is_empty():
		return _fail("review acknowledgement review_id is required", "invalid_review_id")
	return _transaction.execute_command(context, envelope, Callable(self, "_commit_acknowledgement").bind(review_id))

func _commit_acknowledgement(working_context, expected_review_id: String) -> Dictionary:
	var current := _current_review(working_context.state, working_context.scenario_data)
	if not bool(current.get("ok", false)):
		return current
	var review: Dictionary = current.get("review", {}) if current.get("review", {}) is Dictionary else {}
	var review_id := str(review.get("review_id", ""))
	if review_id != expected_review_id:
		return _fail("only the current political season review can be acknowledged", "review_not_current")
	var next_workbench: Dictionary = working_context.state.court_workbench_state.duplicate(true) if working_context.state.court_workbench_state is Dictionary else {}
	var acknowledged: Dictionary = next_workbench.get("political_season_reviews_acknowledged", {}) if next_workbench.get("political_season_reviews_acknowledged", {}) is Dictionary else {}
	acknowledged[review_id] = true
	next_workbench["political_season_reviews_acknowledged"] = acknowledged
	working_context.state.court_workbench_state = next_workbench
	var result := {
		"ok": true,
		"code": "acknowledged",
		"review_id": review_id,
		"acknowledged": true,
		"result_ref": "political_season_review|%s" % review_id
	}
	if review_id == "beta110_final_assessment":
		var ending_result: Dictionary = PhaseEndingEvaluatorScript.new().evaluate(working_context.state, working_context.scenario_data)
		if not bool(ending_result.get("ok", false)) or str(ending_result.get("kind", "")) != "ending":
			return _fail(str(ending_result.get("error", "final assessment could not close")), "final_assessment_not_ready")
		result["ending"] = ending_result.get("ending", {}).duplicate(true) if ending_result.get("ending", {}) is Dictionary else {}
	return result

func _reviews(data: Dictionary) -> Array:
	var raw_reviews: Variant = data.get("political_season_reviews", [])
	if raw_reviews is Array:
		return (raw_reviews as Array).duplicate(true)
	var review_data: Variant = data.get("political_season_review", {})
	if review_data is Dictionary and (review_data as Dictionary).get("reviews", []) is Array:
		return ((review_data as Dictionary).get("reviews", []) as Array).duplicate(true)
	return []

func _authoritative_source_ids(state, review: Dictionary) -> Array:
	var ids: Array = []
	var sources: Variant = review.get("sources", [])
	if sources is Array:
		for raw_source in sources as Array:
			if not raw_source is Dictionary:
				continue
			var source: Dictionary = raw_source as Dictionary
			for key in ["case_id", "report_id", "echo_id", "memorial_id", "order_id"]:
				var source_id := str(source.get(key, "")).strip_edges()
				if not source_id.is_empty() and _has_source(state, source_id) and not ids.has(source_id):
					ids.append(source_id)
	# Supplement authored sources only with records that really exist in the
	# authoritative state. Dormant case skeletons are intentionally excluded.
	var supplemental: Array = _authoritative_source_inventory(state)
	supplemental.sort()
	for source_id in supplemental:
		if ids.size() >= 4:
			break
		if not ids.has(source_id):
			ids.append(source_id)
	return ids

func _has_source(state, source_id: String) -> bool:
	if source_id.is_empty():
		return false
	if state.accountability_cases is Dictionary and state.accountability_cases.has(source_id):
		var case_record: Variant = state.accountability_cases.get(source_id, {})
		if case_record is Dictionary and str((case_record as Dictionary).get("lifecycle", "dormant")) != "dormant":
			return _case_has_authoritative_facts(case_record as Dictionary)
	if state.governance_state is Dictionary:
		for bucket in ["memorials", "orders", "reports"]:
			var collection: Variant = state.governance_state.get(bucket, {}) if bucket != "reports" else state.governance_state.get(bucket, [])
			if collection is Dictionary and collection.has(source_id):
				return true
			if collection is Array:
				for raw_record in collection as Array:
					if raw_record is Dictionary and str((raw_record as Dictionary).get("report_id", "")) == source_id:
						return true
	for raw_ref in state.chronicle_causal_references if state.chronicle_causal_references is Array else []:
		if raw_ref is Dictionary and (str((raw_ref as Dictionary).get("id", "")) == source_id or str((raw_ref as Dictionary).get("echo_id", "")) == source_id):
			return true
	return false

func _authoritative_source_inventory(state) -> Array:
	var ids: Array = []
	if state.governance_state is Dictionary:
		for bucket in ["memorials", "orders"]:
			var collection: Variant = state.governance_state.get(bucket, {})
			if collection is Dictionary:
				for record_id in collection.keys():
					var record: Variant = collection.get(record_id, {})
					if record is Dictionary and not str(record_id).is_empty():
						ids.append(str(record_id))
		var reports: Variant = state.governance_state.get("reports", [])
		if reports is Array:
			for raw_report in reports as Array:
				if raw_report is Dictionary:
					var report_id := str((raw_report as Dictionary).get("report_id", "")).strip_edges()
					if not report_id.is_empty():
						ids.append(report_id)
	if state.chronicle_causal_references is Array:
		for raw_ref in state.chronicle_causal_references as Array:
			if raw_ref is Dictionary:
				var reference: Dictionary = raw_ref as Dictionary
				var reference_id := str(reference.get("echo_id", reference.get("id", ""))).strip_edges()
				if reference_id.begins_with("political_season_echo|"):
					reference_id = reference_id.trim_prefix("political_season_echo|")
				if not reference_id.is_empty():
					ids.append(reference_id)
	if state.accountability_cases is Dictionary:
		for case_id in state.accountability_cases.keys():
			var case_record: Variant = state.accountability_cases.get(case_id, {})
			if case_record is Dictionary and str((case_record as Dictionary).get("lifecycle", "dormant")) != "dormant" and _case_has_authoritative_facts(case_record as Dictionary):
				ids.append(str(case_id))
	var unique: Array = []
	for source_id in ids:
		if not str(source_id).is_empty() and not unique.has(str(source_id)):
			unique.append(str(source_id))
	return unique

func _case_has_authoritative_facts(case_record: Dictionary) -> bool:
	for key in ["facts", "claims", "evidence", "causal_refs"]:
		var value: Variant = case_record.get(key, [])
		if value is Array and not (value as Array).is_empty():
			return true
	return false

func _current_review(state, data: Dictionary) -> Dictionary:
	var day := int(state.current_day)
	var acknowledged: Dictionary = state.court_workbench_state.get("political_season_reviews_acknowledged", {}) if state.court_workbench_state is Dictionary and state.court_workbench_state.get("political_season_reviews_acknowledged", {}) is Dictionary else {}
	var due: Array = []
	for raw_review in _reviews(data):
		if not raw_review is Dictionary:
			continue
		var definition: Dictionary = raw_review as Dictionary
		var review_id := str(definition.get("review_id", "")).strip_edges()
		var review_day := int(definition.get("day", REVIEW_DAYS.get(review_id, 0)))
		if review_id.is_empty() or review_day <= 0 or day < review_day or bool(acknowledged.get(review_id, false)):
			continue
		if not _has_report(state, str(definition.get("report_id", review_id))):
			return _fail("%s report is not ready" % review_id, "review_report_not_ready")
		var review := definition.duplicate(true)
		review["review_id"] = review_id
		review["review_day"] = review_day
		review["acknowledged"] = false
		review["phase"] = str(REVIEW_PHASES.get(review_id, ""))
		due.append(review)
	due.sort_custom(func(left: Dictionary, right: Dictionary):
		var left_day := int(left.get("review_day", left.get("day", 0)))
		var right_day := int(right.get("review_day", right.get("day", 0)))
		return left_day < right_day if left_day != right_day else str(left.get("review_id", "")) < str(right.get("review_id", ""))
	)
	if due.is_empty():
		return _fail("no pending political season review is available", "review_not_ready")
	return {"ok": true, "review": (due[0] as Dictionary).duplicate(true)}

func _has_report(state, report_id: String) -> bool:
	if not state.governance_state is Dictionary:
		return false
	var reports: Variant = state.governance_state.get("reports", [])
	if not reports is Array:
		return false
	for raw_report in reports as Array:
		if raw_report is Dictionary and str((raw_report as Dictionary).get("report_id", "")) == report_id:
			return true
	return false

func _fail(message: String, code: String) -> Dictionary:
	return {"ok": false, "code": code, "error": message, "message": message}
