extends RefCounted

# Draft transport parts carry no authority and never create world actions.
const Canonical = preload("res://scripts/core/canonical_json.gd")
const FIELDS := ["schema_version", "kind", "plan_id", "part_index", "final", "remaining_goal", "dto"]

static func parse_part(value: Variant) -> Dictionary:
	if not value is Dictionary or value.size() != FIELDS.size(): return _fail("分批方案字段不完整")
	for field in FIELDS:
		if not value.has(field): return _fail("分批方案缺少 " + field)
	if value.schema_version != 2 or value.kind != "plan_part" or not value.plan_id is String or value.plan_id.is_empty() or value.plan_id.length() > 128 or not value.final is bool or not value.remaining_goal is String or value.remaining_goal.length() > 2048: return _fail("分批方案标识或剩余目标无效")
	if not preload("res://scripts/core/management_state_contract.gd").amount(value.part_index) or (value.final and value.remaining_goal != "") or (not value.final and value.remaining_goal.strip_edges().is_empty()): return _fail("分批方案序号或结束标记无效")
	if JSON.stringify(value).length() > 65536: return _fail("本批回复超过传输容量，未截断")
	var parsed: Dictionary = load("res://scripts/ai/assistant_plan_parser.gd").new().parse(value.dto)
	if not parsed.get("ok", false) or parsed.dto.kind not in ["proposal", "revise"]: return _fail("分批回复必须包含实际方案步骤")
	var part: Dictionary = value.duplicate(true)
	part.part_index = int(part.part_index)
	part.dto = parsed.dto
	return {"ok": true, "part": part}

static func append(parts: Array, value: Variant) -> Dictionary:
	var parsed := parse_part(value)
	if not parsed.ok: return parsed
	var part: Dictionary = parsed.part
	if part.part_index != parts.size(): return _fail("分批方案序号重复或跳号")
	if not parts.is_empty():
		if parts.back().final: return _fail("完整方案不能继续添加尾段")
		var first: Dictionary = parts[0]
		if part.plan_id != first.plan_id or part.dto.kind != first.dto.kind or part.dto.task_id != first.dto.task_id or part.dto.plan.name != first.dto.plan.name or Canonical.hash_value(part.dto.resource_limits) != Canonical.hash_value(first.dto.resource_limits): return _fail("续批改变了原方案、任务或累计预算")
	var ids: Dictionary = {}
	for prior in parts:
		for step in prior.dto.plan.steps: ids[step.step_id] = true
	for step in part.dto.plan.steps:
		if ids.has(step.step_id): return _fail("续批重复了已有步骤")
		for dependency in step.depends_on:
			if not ids.has(dependency): return _fail("续批依赖未来或不存在的步骤")
		ids[step.step_id] = true
	var next := parts.duplicate(true)
	next.append(part)
	return {"ok": true, "parts": next, "complete": part.final}

static func validate(parts: Variant) -> Dictionary:
	if not parts is Array: return _fail("保存的分批方案类型无效")
	var accepted: Array = []
	for part in parts:
		var result := append(accepted, part)
		if not result.ok: return result
		accepted = result.parts
	return {"ok": true}

static func assemble(parts: Array) -> Dictionary:
	var valid := validate(parts)
	if not valid.ok: return valid
	if parts.is_empty() or not parts.back().final: return _fail("完整方案尚未收到，不得采用前半段")
	var dto: Dictionary = parts[0].dto.duplicate(true)
	dto.plan.steps = []
	dto.basis = []; dto.risks = []
	for part in parts:
		dto.plan.steps.append_array(part.dto.plan.steps.duplicate(true))
		for field in ["basis", "risks"]:
			for item in part.dto[field]:
				if not dto[field].has(item): dto[field].append(item)
	dto.message = parts.back().dto.message
	return {"ok": true, "dto": dto}

static func continuation(parts: Array) -> Dictionary:
	if parts.is_empty(): return {}
	var last: Dictionary = parts.back()
	var count := 0
	for part in parts: count += part.dto.plan.steps.size()
	return {"plan_id": last.plan_id, "next_part_index": parts.size(), "received_steps": count, "last_step_id": last.dto.plan.steps.back().step_id, "last_steps": last.dto.plan.steps.slice(maxi(0, last.dto.plan.steps.size() - 4)), "remaining_goal": last.remaining_goal, "kind": last.dto.kind, "task_id": last.dto.task_id, "plan_name": last.dto.plan.name, "resource_limits": last.dto.resource_limits.duplicate(true)}

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message, "failure_kind": "invalid_result"}
