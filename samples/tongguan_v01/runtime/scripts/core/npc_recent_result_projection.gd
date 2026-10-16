extends RefCounted
## Rebuild bounded feedback from original records. No second outcome ledger.
const LIMIT := 8
const RANKS := {"blocked": 0, "rejected": 1, "completed": 2, "progress": 3, "wait": 4}
const FAILURE_CATEGORIES := {"transport": "transport_failure", "protocol": "protocol_error", "stale": "stale_information", "domain": "conditions_not_met"}

static func failures(history: Array) -> Array:
	var result: Array = history.duplicate(true)
	for row in result: row["result_category"] = FAILURE_CATEGORIES[row.category]
	return result

static func build(state, actor: String, tasks: Array, contracts: Dictionary) -> Array:
	var result: Array = []
	for receipt in state.action_receipts.values():
		if receipt.get("executor_id") != actor: continue
		var outcome: String = receipt.get("social_record", {}).get("outcome", "")
		var category := "blocked" if receipt.get("reason_code") == "blocked" else "completed"
		if outcome in ["rejected", "withdrawn"]: category = "rejected"
		elif outcome in ["proposed", "countered", "accepted", "recorded"]: category = "progress"
		var row := _row(category, "action", receipt.execution_id, int(receipt.day))
		row.receipt_refs = [receipt.execution_id]
		row.journal_refs = receipt.journal_refs.duplicate()
		row["summary"] = str(receipt.get("visible_summary", "")).left(256)
		row["effect_refs"] = receipt.effect_refs.duplicate()
		_append(result, row)
	for task in tasks:
		# Remote principal progress requires a delivered report; the executor
		# knows their own actual work without consulting another actor's secrets.
		if task.get("executor_id") != actor: continue
		var status: String = task.get("status", "")
		var row := _row("completed" if status == "completed" else ("blocked" if status == "blocked" else "progress"), "task", task.task_id, int(task.get("completed_day", task.get("last_execution_day", task.get("created_day", 0)))))
		row["status"] = status
		row["completed_steps"] = 0
		row["total_steps"] = task.steps.size()
		for step in task.steps:
			if step.status != "completed": continue
			row.completed_steps += 1
			var receipt: Dictionary = state.action_receipts.get(step.get("receipt_ref", ""), {})
			if receipt.get("executor_id") != actor: continue
			row.receipt_refs.append(step.receipt_ref)
			for ref in receipt.journal_refs:
				if not row.journal_refs.has(ref): row.journal_refs.append(ref)
		_append(result, row)
	for id in contracts:
		# The caller supplies already-authorized, received contract projections.
		var visible: Dictionary = contracts[id]
		var status: String = visible.get("status", "")
		var category := "progress"
		if status in ["rejected", "withdrawn", "return_pending", "returned"]: category = "rejected"
		elif status in ["fulfilled", "received", "delivered"]: category = "completed"
		elif not str(visible.get("blocked_reason", "")).is_empty() or status == "blocked": category = "blocked"
		var row := _row(category, "contract", id, int(visible.get("known_day", visible.get("resolution_day", visible.get("day", visible.get("created_day", 0))))))
		row["status"] = status
		_append(result, row)
	for record in state.npc_decision_records.values():
		if record.get("actor_id") != actor or record.get("status") != "adopted" or record.get("selection", {}).get("kind") != "wait": continue
		_append(result, _row("wait", "decision", record.request_id, int(record.resolved_day)))
	return result

static func _row(category: String, kind: String, ref: String, day: int) -> Dictionary:
	return {"category": category, "source_kind": kind, "source_ref": ref, "day": maxi(0, day), "receipt_refs": [], "journal_refs": []}

static func _append(result: Array, row: Dictionary) -> void:
	if result.size() >= LIMIT and not _before(row, result.back()): return
	var index := 0
	while index < result.size() and not _before(row, result[index]): index += 1
	result.insert(index, row)
	if result.size() > LIMIT: result.pop_back()

static func _before(a: Dictionary, b: Dictionary) -> bool:
	if a.day != b.day: return a.day > b.day
	# Show interrupted/finished work before routine same-day activity.
	if RANKS[a.category] != RANKS[b.category]: return RANKS[a.category] < RANKS[b.category]
	return str(a.source_ref) < str(b.source_ref)
