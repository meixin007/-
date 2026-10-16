extends RefCounted

class_name GovernanceOrderResolver

const VISIBLE_RESULTS: Array[String] = ["completed", "partial", "delayed", "blocked", "lost_contact", "failed"]
const FACTORS: Array[String] = ["ability", "authority", "resources", "route", "deadline", "intel", "clauses", "prior_case"]
const STAGE_TRANSITIONS := {
	"issued": "delivered",
	"delivered": "acknowledged",
	"acknowledged": "gathering",
	"gathering": "executing"
}
const EFFECT_WHITELIST: Array[String] = [
	"resource_delta", "relationship_delta", "strategy_route_delta", "faction_delta",
	"resolution_path", "memory", "location_update"
]

## Builds a deterministic, side-effect-free daily plan. Every input is copied before use.
func plan_daily_transition(state_snapshot: Dictionary, governance_data: Dictionary, order: Dictionary) -> Dictionary:
	var snapshot: Dictionary = state_snapshot.duplicate(true)
	var source_order: Dictionary = order.duplicate(true)
	var data: Dictionary = governance_data.duplicate(true)
	var order_id := str(source_order.get("order_id", "")).strip_edges()
	if order_id.is_empty():
		return {"ok": false, "code": "invalid_order"}
	var action_id := str(source_order.get("action_id", "")).strip_edges()
	if action_id.is_empty():
		return {"ok": false, "code": "invalid_action"}
	var action: Dictionary = _action_config(data, action_id)
	var trace: Dictionary = _factor_trace(snapshot, data, source_order, action)
	var result := _resolve_result(data, source_order, action, trace)
	var stage := str(source_order.get("stage", "issued"))
	var resource_resolution := _resolve_resource_availability(snapshot, source_order, result, stage)
	if bool(resource_resolution.get("applied", false)):
		result = str(resource_resolution.get("result", result))
		trace["resource_availability"] = resource_resolution.get("details", {})
		trace["resource_status"] = str(resource_resolution.get("status", "available"))
	var next_stage := str(STAGE_TRANSITIONS.get(stage, stage))
	if stage == "executing":
		next_stage = "closed" if result in ["completed", "partial", "failed"] else "executing"
	var resolved: Dictionary = source_order.duplicate(true)
	resolved["stage"] = next_stage
	resolved["condition"] = result if result in ["delayed", "blocked", "lost_contact"] else "normal"
	resolved["outcome"] = result if next_stage == "closed" else ""
	resolved["rule_seed"] = int(source_order.get("rule_seed", snapshot.get("governance_state", {}).get("rule_seed", 107)))
	var effects := _allowed_effects(action.get("effects", data.get("effects", {})), data)
	var reports: Array = _report_descriptors(source_order, resolved, action, data, snapshot, trace)
	return {
		"ok": true,
		"order": resolved,
		"reports": reports,
		"effects": effects,
		"reservation_action": "release" if next_stage == "closed" else "keep",
		"visible_result": visible_result(resolved),
		"rule_trace": trace,
		"snapshot_day": int(snapshot.get("current_day", 0)),
		"action_id": action_id
	}

## Plans a child correction without mutating the parent order or input dictionaries.
func plan_correction(state_snapshot: Dictionary, governance_data: Dictionary, parent_order: Dictionary, correction: Dictionary) -> Dictionary:
	var parent: Dictionary = parent_order.duplicate(true)
	var condition := str(parent.get("condition", ""))
	if condition not in ["delayed", "blocked", "lost_contact"]:
		return {"ok": false, "code": "correction_unavailable"}
	var child: Dictionary = correction.duplicate(true)
	child["parent_order_id"] = str(parent.get("order_id", ""))
	child["correction_kind"] = str(correction.get("correction_kind", correction.get("kind", "wait")))
	if str(child.get("order_id", "")).is_empty():
		child["order_id"] = str(parent.get("order_id", "")) + "__correction__" + child["correction_kind"]
	if str(child.get("action_id", "")).is_empty():
		child["action_id"] = str(parent.get("action_id", ""))
	if str(child.get("stage", "")).is_empty():
		child["stage"] = "issued"
	var result := plan_daily_transition(state_snapshot.duplicate(true), governance_data.duplicate(true), child)
	if not bool(result.get("ok", false)):
		return result
	var child_order: Dictionary = (result.get("order", {}) as Dictionary).duplicate(true)
	child_order["parent_order_id"] = str(parent.get("order_id", ""))
	child_order["correction_kind"] = str(child.get("correction_kind", "wait"))
	result["order"] = child_order
	result["parent_order_id"] = str(parent.get("order_id", ""))
	return result

func _resolve_resource_availability(snapshot: Dictionary, order: Dictionary, result: String, stage: String) -> Dictionary:
	if stage != "executing":
		return {"applied": false, "result": result}
	var required_value: Variant = order.get("resources", {})
	if not required_value is Dictionary or (required_value as Dictionary).is_empty():
		return {"applied": false, "result": result}
	var available_value: Variant = snapshot.get("resources", {})
	var available_resources: Dictionary = available_value if available_value is Dictionary else {}
	var details: Dictionary = {}
	var total_required := 0
	var total_usable := 0
	for raw_key in (required_value as Dictionary).keys():
		var resource_name := str(raw_key).strip_edges()
		var required := maxi(int((required_value as Dictionary).get(raw_key, 0)), 0)
		if resource_name.is_empty() or required <= 0:
			continue
		var available := maxi(int(available_resources.get(resource_name, 0)), 0)
		if resource_name == "treasury" and snapshot.get("resource_accounts", {}).has("court_treasury"):
			var own_id := "governance:" + str(order.order_id) + ":treasury"
			var accounts: Dictionary = snapshot.resource_accounts
			for held in snapshot.get("resource_reservations", {}).values():
				if held.get("status") == "active" and held.get("reservation_id") != own_id and accounts.get(held.get("account_id"), {}).get("storage_ref") == accounts.court_treasury.storage_ref:
					available -= int(held.remaining_amount)
			var own: Dictionary = snapshot.get("resource_reservations", {}).get(own_id, {})
			available = maxi(0, mini(available, int(own.get("remaining_amount", 0))))
		var usable := mini(required, available)
		total_required += required
		total_usable += usable
		details[resource_name] = {"required": required, "available": available, "usable": usable}
	if total_required <= 0:
		return {"applied": false, "result": result}
	var resolved_result := result
	var status := "available"
	if total_usable < total_required:
		if result in ["failed", "delayed", "blocked", "lost_contact"]:
			status = "shortage_preserved"
		elif total_usable == 0:
			resolved_result = "blocked"
			status = "blocked"
		else:
			resolved_result = "partial"
			status = "partial"
	return {"applied": true, "result": resolved_result, "status": status, "details": details}

func visible_result(order: Dictionary) -> String:
	var outcome := str(order.get("outcome", ""))
	if outcome in ["completed", "partial", "failed"]:
		return outcome
	var condition := str(order.get("condition", "normal"))
	if condition in ["delayed", "blocked", "lost_contact"]:
		return condition
	return "completed" if str(order.get("stage", "")) == "closed" else "delayed"

func _action_config(data: Dictionary, action_id: String) -> Dictionary:
	for bucket_name in ["command_actions", "actions", "commands"]:
		var bucket: Variant = data.get(bucket_name, {})
		if bucket is Dictionary and (bucket as Dictionary).get(action_id) is Dictionary:
			return ((bucket as Dictionary).get(action_id) as Dictionary).duplicate(true)
	return {}

func _topic_rule_for_action(data: Dictionary, action_id: String) -> Dictionary:
	var raw_rules: Variant = data.get("topic_rules", {})
	if not raw_rules is Dictionary:
		return {}
	for raw_rule in (raw_rules as Dictionary).values():
		if raw_rule is Dictionary and str((raw_rule as Dictionary).get("action_id", "")) == action_id:
			return (raw_rule as Dictionary).duplicate(true)
	return {}

func _factor_trace(snapshot: Dictionary, data: Dictionary, order: Dictionary, action: Dictionary) -> Dictionary:
	var trace: Dictionary = {}
	var values: Dictionary = {}
	var order_factors: Variant = order.get("factors", {})
	var data_factors: Variant = data.get("factor_scores", {})
	for factor in FACTORS:
		var value := 0
		if order_factors is Dictionary and (order_factors as Dictionary).has(factor):
			value = int((order_factors as Dictionary).get(factor, 0))
		elif data_factors is Dictionary and (data_factors as Dictionary).has(factor):
			value = int((data_factors as Dictionary).get(factor, 0))
		elif action.get("factors", {}) is Dictionary:
			value = int((action.get("factors", {}) as Dictionary).get(factor, 0))
		values[factor] = value
	var weights: Dictionary = action.get("factor_weights", data.get("factor_weights", {})) if action.get("factor_weights", data.get("factor_weights", {})) is Dictionary else {}
	var total := 0
	for factor in FACTORS:
		var weighted := int(values.get(factor, 0)) * int(weights.get(factor, 1))
		trace[factor] = weighted
		total += weighted
	trace["total"] = total
	trace["values"] = values.duplicate(true)
	return trace

func _resolve_result(data: Dictionary, order: Dictionary, action: Dictionary, trace: Dictionary) -> String:
	for source in [order, action]:
		var forced := str(source.get("forced_result", source.get("result", "")))
		if VISIBLE_RESULTS.has(forced):
			return forced
	var route_id := str(order.get("route_id", ""))
	var routes: Variant = action.get("routes", data.get("routes", {}))
	if routes is Dictionary and VISIBLE_RESULTS.has(str((routes as Dictionary).get(route_id, ""))):
		return str((routes as Dictionary).get(route_id))
	var thresholds: Dictionary = action.get("score_thresholds", data.get("score_thresholds", {})) if action.get("score_thresholds", data.get("score_thresholds", {})) is Dictionary else {}
	var total := int(trace.get("total", 0))
	if total >= int(thresholds.get("completed", 70)):
		return "completed"
	if total >= int(thresholds.get("partial", 40)):
		return "partial"
	if total <= int(thresholds.get("failed", 0)):
		return "failed"
	var profile := str(data.get("resolution_profile", "completed"))
	var profiles: Variant = data.get("resolution_profiles", {})
	if profiles is Dictionary:
		var action_profile := str((profiles as Dictionary).get(str(order.get("action_id", "")), ""))
		if VISIBLE_RESULTS.has(action_profile):
			profile = action_profile
		elif VISIBLE_RESULTS.has(str((profiles as Dictionary).get("default", ""))):
			profile = str((profiles as Dictionary).get("default"))
	return profile if VISIBLE_RESULTS.has(profile) else "completed"

func _allowed_effects(raw: Variant, data: Dictionary) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var whitelist: Array = EFFECT_WHITELIST.duplicate()
	if data.get("effect_whitelist", []) is Array and not (data.get("effect_whitelist", []) as Array).is_empty():
		whitelist = (data.get("effect_whitelist", []) as Array).duplicate(true)
	var effects: Dictionary = {}
	for key in (raw as Dictionary).keys():
		if whitelist.has(str(key)):
			effects[str(key)] = (raw as Dictionary).get(key).duplicate(true) if (raw as Dictionary).get(key) is Array or (raw as Dictionary).get(key) is Dictionary else (raw as Dictionary).get(key)
	return effects

func _report_descriptors(source: Dictionary, resolved: Dictionary, action: Dictionary, data: Dictionary, snapshot: Dictionary, trace: Dictionary = {}) -> Array:
	var result: Array = []
	var stage := str(resolved.get("stage", ""))
	var kind := "progress"
	if stage == "delivered": kind = "progress"
	if stage == "closed": kind = "closure"
	if str(resolved.get("condition", "normal")) in ["delayed", "blocked", "lost_contact"]: kind = "anomaly"
	var day := int(snapshot.get("current_day", 0))
	var topic_rule := _topic_rule_for_action(data, str(source.get("action_id", "")))
	var template_family := str(action.get("report_template_family", "")).strip_edges()
	if template_family.is_empty():
		template_family = str(topic_rule.get("report_template_family", data.get("report_template_family", "governance"))).strip_edges()
	var template_id := str(action.get("report_template_id", kind))
	var report_templates: Variant = data.get("report_templates", {})
	if not report_templates is Dictionary or not (report_templates as Dictionary).has(template_family) or not ((report_templates as Dictionary).get(template_family, {}) is Dictionary) or not ((report_templates as Dictionary).get(template_family, {}) as Dictionary).has(template_id):
		template_family = ""
		template_id = ""
	result.append({
		"report_id": str(source.get("order_id", "")) + "__" + kind + "__" + str(day),
		"order_id": str(source.get("order_id", "")),
		"kind": kind,
		"condition": str(resolved.get("condition", "normal")),
		"outcome": str(resolved.get("outcome", "")),
		"status": stage,
		"created_day": day,
		"arrival_day": int(source.get("report_due_day", day)),
		"delivered_day": -1,
		"causes": [],
		"effects": [],
		"available_actions": action.get("recovery_actions", []),
		"execution_details": _execution_details(source, resolved, action, trace),
		"template_family": template_family,
		"template_id": template_id,
		"public_text": "",
		"wording_source": "offline"
	})
	return result

func _execution_details(source: Dictionary, resolved: Dictionary, action: Dictionary, trace: Dictionary) -> Dictionary:
	var requested_value: Variant = source.get("resources", {})
	var requested_resources: Dictionary = requested_value.duplicate(true) if requested_value is Dictionary else {}
	var availability_value: Variant = trace.get("resource_availability", {})
	var availability: Dictionary = availability_value if availability_value is Dictionary else {}
	var available_resources: Dictionary = {}
	var usable_resources: Dictionary = {}
	for raw_key in availability.keys():
		var detail: Variant = availability.get(raw_key, {})
		if not detail is Dictionary:
			continue
		available_resources[str(raw_key)] = int((detail as Dictionary).get("available", 0))
		usable_resources[str(raw_key)] = int((detail as Dictionary).get("usable", 0))
	var stage := str(resolved.get("stage", ""))
	var condition := str(resolved.get("condition", "normal"))
	var result := str(resolved.get("outcome", ""))
	var applied_effects: Dictionary = {}
	if stage == "closed":
		applied_effects = {
			"resource_consumed": usable_resources.duplicate(true),
			"relationship_delta": 3,
			"memory_recorded": true,
			"location_updated": not str(source.get("location_id", "")).strip_edges().is_empty()
		}
	var recovery_value: Variant = action.get("recovery_actions", [])
	var next_action_ids: Array = recovery_value.duplicate(true) if recovery_value is Array else []
	return {
		"stage": stage,
		"condition": condition,
		"action_id": str(source.get("action_id", "")),
		"recipient_id": str(source.get("recipient_id", "")),
		"location_id": str(source.get("location_id", "")),
		"requested_resources": requested_resources,
		"available_resources": available_resources,
		"usable_resources": usable_resources,
		"resource_status": str(trace.get("resource_status", "")),
		"result": result,
		"next_action_ids": next_action_ids,
		"next_step": "进入后续复盘" if stage == "closed" else "等待下一阶段回报",
		"applied_effects": applied_effects
	}
