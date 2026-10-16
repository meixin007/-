extends RefCounted

# Segments index the one authoritative step array; they carry no extra budget.
# This is an execution window, never a maximum plan length.
const WINDOW_SIZE := 16
const Canonical = preload("res://scripts/core/canonical_json.gd")

static func build(task: Dictionary) -> Dictionary:
	var ranges: Array = []
	var checkpoints: Array = []
	var cursor := 0
	for start in range(0, task.steps.size(), WINDOW_SIZE):
		var end := mini(start + WINDOW_SIZE, task.steps.size())
		var content: Array = []
		var receipts: Array = []
		var complete := true
		for index in range(start, end):
			var step: Dictionary = task.steps[index]
			var definition := {}
			for key in ["step_id", "action_kind", "target_refs", "parameters", "depends_on", "execution_id"]: definition[key] = step[key]
			content.append(definition)
			complete = complete and step.status == "completed"
			receipts.append(step.receipt_ref)
		ranges.append({"start": start, "end": end, "content_hash": Canonical.hash_value(content).get("hash", "")})
		if complete and cursor == ranges.size() - 1:
			checkpoints.append({"segment_index": cursor, "receipt_refs": receipts})
			cursor += 1
	return {"schema_version": 1, "plan_revision": task.plan_revision, "ranges": ranges, "cursor": cursor, "checkpoints": checkpoints}

static func refresh(task: Dictionary) -> void:
	task["execution_segments"] = build(task)

static func validate(task: Dictionary) -> Dictionary:
	for step in task.steps:
		for field in ["step_id", "action_kind", "target_refs", "parameters", "depends_on", "execution_id", "receipt_ref", "status"]:
			if not step.has(field): return {"ok": false, "error": "management segment lost step field: " + field}
	var saved: Variant = task.get("execution_segments")
	var actual := Canonical.hash_value(saved)
	var expected := Canonical.hash_value(build(task))
	if not saved is Dictionary or not actual.get("ok", false) or not expected.get("ok", false) or actual.hash != expected.hash:
		return {"ok": false, "error": "management plan lost or changed execution segments, revision or receipt checkpoints"}
	return {"ok": true}

static func start_index(task: Dictionary) -> int:
	var segments: Dictionary = task.execution_segments
	return task.steps.size() if int(segments.cursor) == segments.ranges.size() else int(segments.ranges[int(segments.cursor)].start)

static func progress(task: Dictionary) -> Dictionary:
	var segments: Dictionary = task.execution_segments
	return {"total": segments.ranges.size(), "completed": int(segments.cursor), "completed_steps": task.steps.filter(func(step): return step.status == "completed").size(), "total_steps": task.steps.size()}
