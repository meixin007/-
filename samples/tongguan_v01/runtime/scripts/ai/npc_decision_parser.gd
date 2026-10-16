extends RefCounted
const Contract = preload("res://scripts/core/npc_ai_state_contract.gd")
const Catalog = preload("res://scripts/core/game_action_catalog.gd")
const Canonical = preload("res://scripts/core/canonical_json.gd")

func parse(value: Variant) -> Dictionary:
	var fields := ["schema_version", "kind", "reason_code", "action", "plan", "resource_limits"]
	if not Contract.exact(value, fields):
		var missing: Array = fields.filter(func(field): return not value is Dictionary or not value.has(field))
		var extras: int = value.keys().filter(func(field): return field not in fields).size() if value is Dictionary else 0
		return Contract.fail("NPC protocol fields mismatch; missing=" + str(missing) + "; unknown_field_count=" + str(extras))
	if value.schema_version != 1 or value.kind not in ["wait", "action", "plan"] or not value.reason_code is String or value.reason_code.is_empty() or value.reason_code.length() > 256: return Contract.fail("unknown NPC decision protocol or kind")
	if not value.action is Dictionary or not value.plan is Dictionary or not value.resource_limits is Array or not Canonical.hash_value(value).get("ok", false): return Contract.fail("noncanonical NPC selection")
	if value.kind == "wait":
		if not value.action.is_empty() or not value.plan.is_empty() or not value.resource_limits.is_empty(): return Contract.fail("waiting cannot carry effects")
	elif value.kind == "action":
		if not value.plan.is_empty() or not value.resource_limits.is_empty(): return Contract.fail("immediate action cannot carry a parallel plan")
		var valid := Catalog.validate_selection(value.action)
		if not valid.ok: return valid
	else:
		var plan_fields: Array = ["name", "steps"] + (["task_id"] if value.plan.has("task_id") else [])
		if not value.action.is_empty() or not Contract.exact(value.plan, plan_fields) or not value.plan.name is String or value.plan.name.is_empty() or value.plan.name.length() > 256 or not value.plan.steps is Array or value.plan.steps.is_empty() or value.plan.steps.size() > 8: return Contract.fail("invalid or oversized NPC plan")
		if value.plan.has("task_id") and not Contract.text_id(value.plan.task_id): return Contract.fail("NPC revision requires an existing task identity")
		var ids: Array = []
		for step in value.plan.steps:
			if not Contract.exact(step, ["step_id", "action_kind", "parameters", "target_refs", "depends_on"]) or not Contract.text_id(step.step_id) or ids.has(step.step_id) or not step.depends_on is Array: return Contract.fail("invalid NPC plan step")
			for dependency in step.depends_on:
				if not ids.has(dependency): return Contract.fail("NPC dependency must reference an earlier step")
			ids.append(step.step_id)
			var valid := Catalog.validate_selection({"action_kind": step.action_kind, "parameters": step.parameters, "target_refs": step.target_refs})
			if not valid.ok: return valid
		var accounts: Array = []
		for limit in value.resource_limits:
			if not Contract.exact(limit, ["account_id", "amount", "unit_id"]) or not Contract.text_id(limit.account_id) or accounts.has(limit.account_id) or not Contract.whole(limit.amount, 1) or limit.unit_id != "cash_unit": return Contract.fail("invalid NPC cumulative budget")
			accounts.append(limit.account_id)
	return {"ok": true, "selection": value.duplicate(true)}

func parse_transport(response: Dictionary) -> Dictionary:
	var choices: Variant = response.get("choices")
	if not choices is Array or choices.size() != 1 or not choices[0] is Dictionary: return Contract.fail("NPC response requires one choice")
	var message: Variant = choices[0].get("message")
	if not message is Dictionary or not message.get("content") is String or choices[0].get("finish_reason", "stop") not in ["stop", ""]: return Contract.fail("NPC response is missing or truncated")
	var json := JSON.new()
	if json.parse(message.content) != OK: return Contract.fail("NPC response must be one strict JSON object")
	if json.data is Dictionary and json.data.get("kind") == "context_request": return load("res://scripts/core/npc_context_pages.gd").parse_request(json.data)
	return parse(json.data)
